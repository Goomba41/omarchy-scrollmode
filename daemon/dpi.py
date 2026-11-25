"""DPI discovery for pointing devices.

There is no universal way to read DPI from a mouse: HID gives relative counts,
and the resolution is a vendor-specific setting. This module keeps a small
registry of providers, ordered by how much of the work they do for the user:

  ratbag  - libratbag/ratbagd over ratbagctl; broad vendor coverage
  vendor  - signature parsers for mice that report DPI over HID vendor reports
  manual  - a value stored in the config for devices nothing can read
  none    - the device genuinely does not expose its DPI

Only read paths live here for now. Writing a new DPI value is a later step.
"""

from __future__ import annotations

import glob
import json
import os
import re
import select
import shutil
import subprocess
import threading
import time
from datetime import datetime

# Wings Tech Gaming Mouse reports its current DPI stage as
#   04 a2 02 <stage> 00 <code> <code>
# when the DPI button is pressed. The table is code * 100 DPI.
WINGS_STAGES = (900, 1800, 2700, 5400, 7200, 14000, 21000)
WINGS_CODES = tuple(value // 100 for value in WINGS_STAGES)


class VendorTable:
    def __init__(self, name: str, stages: tuple[int, ...], codes: tuple[int, ...]) -> None:
        self.name = name
        self.stages = tuple(int(value) for value in stages)
        self.codes = tuple(int(value) for value in codes)

    @property
    def codes_by_stage(self) -> tuple[int, ...]:
        return self.codes


VENDOR_TABLES = {
    ("2ea8", "2203"): VendorTable("Wings Tech Gaming Mouse", WINGS_STAGES, WINGS_CODES),
}


def device_vid_pid(device_id: str) -> tuple[str, str] | None:
    match = re.match(r"^([0-9a-fA-F]{4}):([0-9a-fA-F]{4})", device_id or "")
    if not match:
        return None
    return match.group(1).lower(), match.group(2).lower()


def vendor_table_for(device_id: str, *names: str) -> VendorTable | None:
    pair = device_vid_pid(device_id)
    if pair and pair in VENDOR_TABLES:
        return VENDOR_TABLES[pair]
    text = " ".join(name or "" for name in names).lower()
    if "wings" in text:
        return VENDOR_TABLES[("2ea8", "2203")]
    return None


def parse_vendor_report(data: bytes, table: VendorTable) -> int | None:
    """Return the stage index from a vendor report, or None.

    hidraw includes the report id, but some capture tools strip it, so both a
    leading 04 and a bare a2 02 payload are accepted. The stage byte is
    authoritative; the code is used when it points at a different stage.
    """
    raw = bytes(data)
    for prefix in (0, 1):
        length = prefix + 6
        if len(raw) < length:
            continue
        if raw[prefix] != 0xA2 or raw[prefix + 1] != 0x02:
            continue
        stage = raw[prefix + 2]
        code = raw[prefix + 4]
        if code in table.codes:
            return table.codes.index(code)
        if 0 <= stage < len(table.stages):
            if code in (0, table.codes[stage]):
                return stage
    return None


def stage_range(values: list[int]) -> dict | None:
    clean = sorted({int(value) for value in values if int(value) > 0})
    if not clean:
        return None
    diffs = [b - a for a, b in zip(clean, clean[1:]) if b > a]
    return {
        "min": clean[0],
        "max": clean[-1],
        "step": min(diffs) if diffs else 0,
    }


def build_info(
    stages: list[int],
    active_index: int | None,
    source: str,
    writable: bool,
    tools: dict | None = None,
    device: str = "",
) -> dict:
    clean: list[int] = []
    for value in stages:
        number = int(value)
        if number > 0 and number not in clean:
            clean.append(number)
    active = active_index if active_index is not None else -1
    if not (0 <= active < len(clean)):
        active = -1
    current = clean[active] if active >= 0 else 0
    return {
        "dpi": current,
        "stages": [
            {"index": index, "dpi": value, "active": index == active}
            for index, value in enumerate(clean)
        ],
        "source": source if clean else "none",
        "writable": bool(writable and clean),
        "range": stage_range(clean),
        "device": device,
        "tools": dict(tools or {}),
    }


def none_info(tools: dict | None = None) -> dict:
    return build_info([], None, "none", False, tools)


def manual_dpi(config: dict, device_id: str) -> int:
    if not device_id:
        return 0
    section = (config or {}).get("dpi")
    if not isinstance(section, dict):
        return 0
    manual = section.get("manual")
    if not isinstance(manual, dict):
        return 0
    try:
        value = int(float(manual.get(device_id) or 0))
    except (TypeError, ValueError):
        return 0
    return value if value > 0 else 0


def manual_info(config: dict, device_id: str, tools: dict | None = None) -> dict | None:
    value = manual_dpi(config, device_id)
    if value <= 0:
        return None
    return build_info([value], 0, "manual", False, tools)


# -- ratbag ----------------------------------------------------------------


def _norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (text or "").lower())


_STOP_WORDS = {
    "mouse", "gaming", "usb", "receiver", "wired", "wireless", "optical",
    "trackball", "the", "tech", "device",
}


def _tokens(text: str) -> list[str]:
    return [
        token for token in re.split(r"[^a-z0-9]+", (text or "").lower())
        if token and token not in _STOP_WORDS
    ]


def match_ratbag_device(
    devices: list[dict], names: list[str], override: str = ""
) -> dict | None:
    if not devices:
        return None
    if override:
        wanted = override.strip().lower()
        for device in devices:
            if wanted == str(device.get("id", "")).lower():
                return device
        for device in devices:
            if str(device.get("id", "")).lower().startswith(wanted):
                return device
        matched = [device for device in devices if wanted in str(device.get("name", "")).lower()]
        return matched[0] if matched else None

    best = None
    best_score = 0
    for device in devices:
        device_name = str(device.get("name") or "")
        norm_device = _norm(device_name)
        score = 0
        for name in names:
            norm_name = _norm(name)
            if not norm_name or not norm_device:
                continue
            if norm_name == norm_device:
                score = max(score, 100)
            elif norm_name in norm_device or norm_device in norm_name:
                score = max(score, 60)
            else:
                left = set(_tokens(device_name))
                right = set(_tokens(name))
                shared = left & right
                if len(shared) >= 2:
                    score = max(score, 30 + len(shared))
        if score > best_score:
            best_score = score
            best = device
    return best if best_score >= 30 else None


def parse_ratbagctl_list(text: str) -> list[dict]:
    devices = []
    for line in (text or "").splitlines():
        match = re.match(r"^\s*(\S+):\s+(.+?)\s*$", line)
        if match:
            devices.append({"id": match.group(1), "name": match.group(2)})
    return devices


def parse_ratbagctl_info(text: str) -> dict | None:
    profiles = []
    current = None
    for line in (text or "").splitlines():
        profile = re.match(r"^\s*Profile (\d+):(.*)$", line)
        if profile:
            current = {
                "index": int(profile.group(1)),
                "active": "(active)" in profile.group(2),
                "resolutions": [],
            }
            profiles.append(current)
            continue
        if current is None:
            continue
        resolution = re.match(r"^\s*(\d+):\s*(\d+)(?:x(\d+))?dpi(.*)$", line)
        if resolution:
            current["resolutions"].append({
                "index": int(resolution.group(1)),
                "dpi": int(resolution.group(2)),
                "flags": resolution.group(4),
            })
    if not profiles:
        return None
    profile = next((item for item in profiles if item["active"]), profiles[0])
    stages = []
    active_index = -1
    active_dpi = 0
    for resolution in profile["resolutions"]:
        flags = resolution["flags"]
        dpi = resolution["dpi"]
        if dpi <= 0 or "(disabled)" in flags:
            continue
        if dpi not in stages:
            stages.append(dpi)
        if "(active)" in flags or (active_index < 0 and "(default)" in flags):
            active_dpi = dpi
    if not stages:
        return None
    if active_dpi:
        active_index = stages.index(active_dpi)
    elif profile["resolutions"]:
        active_index = 0
    return {
        "profile": profile["index"],
        "stages": stages,
        "active": active_index,
        "range": stage_range(stages),
    }


def ratbag_service_active(timeout: float = 0.6) -> bool:
    """Do not wake ratbagd through D-Bus: it can fight our HID++ reads."""
    try:
        result = subprocess.run(
            ["systemctl", "is-active", "--quiet", "ratbagd"],
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def read_ratbag(
    names: list[str],
    override: str = "",
    timeout: float = 2.0,
    service_active=None,
) -> tuple[dict | None, bool]:
    """Return (info, daemon_ok). info is None when no supported device matches."""
    tool = shutil.which("ratbagctl")
    if not tool:
        return None, False
    check = service_active or ratbag_service_active
    if not check():
        return None, False
    try:
        listing = subprocess.run(
            [tool, "list"],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None, False
    if listing.returncode != 0:
        return None, False
    devices = parse_ratbagctl_list(listing.stdout)
    device = match_ratbag_device(devices, names, override)
    if not device:
        return None, True
    try:
        info = subprocess.run(
            [tool, device["id"], "info"],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None, True
    if info.returncode != 0:
        return None, True
    parsed = parse_ratbagctl_info(info.stdout)
    if not parsed:
        return None, True
    parsed["device"] = device["name"]
    return parsed, True


class DpiManager:
    """Resolve the current DPI view for one device and cache provider results."""

    def __init__(
        self,
        state_path: str,
        config: dict,
        ratbag_reader=None,
        which=None,
        logger=None,
    ) -> None:
        self.state_path = state_path
        self.config = config or {}
        self._reader = ratbag_reader or read_ratbag
        self._which = which or shutil.which
        self._log = logger or (lambda _message: None)
        self._lock = threading.RLock()
        self._state = {"devices": {}}
        self._ratbag_cache: dict[str, dict] = {}
        self._tools = self._detect_tools()
        self._load_state()

    def _detect_tools(self) -> dict:
        return {
            "ratbag": bool(self._which("ratbagctl")),
            "piper": bool(self._which("piper")),
            "daemon": False,
        }

    def reload_config(self, config: dict) -> None:
        with self._lock:
            self.config = config or {}
            self._ratbag_cache.clear()

    def tools(self) -> dict:
        with self._lock:
            return dict(self._tools)

    def _load_state(self) -> None:
        try:
            with open(self.state_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return
        devices = data.get("devices") if isinstance(data, dict) else None
        if isinstance(devices, dict):
            self._state = {"devices": devices}

    def _save_state(self) -> None:
        try:
            os.makedirs(os.path.dirname(self.state_path), mode=0o755, exist_ok=True)
            tmp = self.state_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as handle:
                json.dump(self._state, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
            os.replace(tmp, self.state_path)
            os.chmod(self.state_path, 0o644)
        except OSError as exc:
            self._log(f"cannot write {self.state_path}: {exc}")

    def state_stage(self, device_id: str) -> int | None:
        with self._lock:
            entry = (self._state.get("devices") or {}).get(device_id)
        if not isinstance(entry, dict):
            return None
        try:
            stage = int(entry.get("stage"))
        except (TypeError, ValueError):
            return None
        return stage if stage >= 0 else None

    def note_vendor_stage(self, device_id: str, stage: int) -> int:
        """Record a stage reported by a vendor HID report; return its DPI."""
        table = vendor_table_for(device_id)
        if not table or not (0 <= stage < len(table.stages)):
            return 0
        dpi = table.stages[stage]
        with self._lock:
            entry = (self._state.get("devices") or {}).get(device_id)
            if isinstance(entry, dict) and entry.get("stage") == stage:
                return dpi
            devices = self._state.setdefault("devices", {})
            devices[device_id] = {
                "stage": stage,
                "dpi": dpi,
                "source": "vendor",
                "updated": datetime.now().astimezone().isoformat(timespec="seconds"),
            }
            self._save_state()
            self._ratbag_cache.pop(device_id, None)
        return dpi

    def snapshot(
        self,
        device_id: str,
        name: str = "",
        raw_name: str = "",
        kind: str = "unknown",
        force: bool = False,
        allow_ratbag: bool = True,
    ) -> dict:
        with self._lock:
            # Picking up a newly installed package should not need a restart.
            if force:
                self._tools.update(self._detect_tools())
            tools = dict(self._tools)
            if kind != "mouse" or not device_id:
                return none_info(tools)

            names = [name, raw_name]
            if allow_ratbag and tools["ratbag"]:
                cached = self._ratbag_cache.get(device_id)
                stale = cached is None or time.monotonic() - cached["at"] > 30.0
                if force or stale:
                    override = ""
                    section = self.config.get("dpi")
                    if isinstance(section, dict):
                        override = str(section.get("ratbag_device") or "")
                    try:
                        info, daemon_ok = self._reader(names, override)
                    except Exception as exc:  # a provider bug must not kill status
                        self._log(f"ratbag DPI read failed: {exc}")
                        info, daemon_ok = None, False
                    self._tools["daemon"] = bool(daemon_ok)
                    tools["daemon"] = bool(daemon_ok)
                    cached = {"at": time.monotonic(), "info": info}
                    self._ratbag_cache[device_id] = cached
                info = cached.get("info")
                if info and info.get("stages"):
                    return build_info(
                        info["stages"],
                        info.get("active"),
                        "ratbag",
                        False,
                        tools,
                        str(info.get("device") or ""),
                    )

            table = vendor_table_for(device_id, name, raw_name)
            if table:
                stage = self.state_stage(device_id)
                return build_info(
                    list(table.stages),
                    stage,
                    "vendor",
                    False,
                    tools,
                    table.name,
                )

            manual = manual_info(self.config, device_id, tools)
            if manual:
                return manual
            return none_info(tools)


# -- vendor HID monitor ----------------------------------------------------


def _hidraw_nodes(vid: str, pid: str, name: str = "") -> list[str]:
    wanted = (int(vid, 16), int(pid, 16))
    nodes = []
    for link in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(os.path.join(link, "device", "uevent"), "r", encoding="utf-8") as handle:
                uevent = handle.read()
        except OSError:
            continue
        ids = re.search(r"HID_ID=\w+:([0-9A-Fa-f]{8}):([0-9A-Fa-f]{8})", uevent)
        if ids:
            if (int(ids.group(1), 16), int(ids.group(2), 16)) == wanted:
                nodes.append("/dev/" + os.path.basename(link))
            continue
        if name and name.lower() in uevent.lower():
            nodes.append("/dev/" + os.path.basename(link))
    return nodes


class VendorMonitor(threading.Thread):
    """Listen for vendor DPI reports on the active device's hidraw nodes."""

    def __init__(self, on_stage, logger=None) -> None:
        super().__init__(name="dpi-vendor", daemon=True)
        self._on_stage = on_stage
        self._log = logger or (lambda _message: None)
        self._stop_event = threading.Event()
        self._wake = threading.Event()
        self._lock = threading.Lock()
        self._target: tuple[str, str, str] | None = None

    def set_target(self, device_id: str, name: str = "", raw_name: str = "") -> None:
        target = (device_id or "", name or "", raw_name or "")
        with self._lock:
            if target == self._target:
                return
            self._target = target if target[0] else None
        self._wake.set()

    def stop(self) -> None:
        self._stop_event.set()
        self._wake.set()

    def _current_target(self) -> tuple[str, str, str] | None:
        with self._lock:
            return self._target

    def run(self) -> None:
        fds: dict[int, str] = {}
        nodes: list[str] = []
        table = None
        device_id = ""
        last_scan = 0.0
        last_stage: int | None = None

        def close_all() -> None:
            for fd in list(fds):
                try:
                    os.close(fd)
                except OSError:
                    pass
            fds.clear()

        while not self._stop_event.is_set():
            target = self._current_target()
            if target is None:
                close_all()
                nodes = []
                table = None
                device_id = ""
                last_stage = None
                self._wake.wait(1.0)
                self._wake.clear()
                continue

            active_id, name, raw = target
            pair = device_vid_pid(active_id)
            table = vendor_table_for(active_id, name, raw)
            if not pair or table is None:
                close_all()
                nodes = []
                device_id = ""
                last_stage = None
                self._wake.wait(1.0)
                self._wake.clear()
                continue

            now = time.monotonic()
            if not fds or now - last_scan > 5.0:
                last_scan = now
                wanted_nodes = _hidraw_nodes(*pair, name if pair else "")
                if set(wanted_nodes) != set(nodes):
                    close_all()
                    nodes = wanted_nodes
                    device_id = active_id
                    last_stage = None
                for node in nodes:
                    if any(path == node for path in fds.values()):
                        continue
                    try:
                        fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
                    except OSError:
                        continue
                    fds[fd] = node
                # Drain reports that predate the monitor.
                for fd in list(fds):
                    try:
                        while select.select([fd], [], [], 0)[0]:
                            os.read(fd, 64)
                    except OSError:
                        try:
                            os.close(fd)
                        except OSError:
                            pass
                        fds.pop(fd, None)

            if not fds:
                self._wake.wait(1.0)
                self._wake.clear()
                continue

            try:
                ready, _, _ = select.select(list(fds), [], [], 1.0)
            except OSError:
                close_all()
                continue
            for fd in ready:
                try:
                    data = os.read(fd, 64)
                except OSError:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    fds.pop(fd, None)
                    continue
                if not data:
                    continue
                stage = parse_vendor_report(data, table)
                if stage is None:
                    continue
                if stage == last_stage:
                    continue
                last_stage = stage
                try:
                    self._on_stage(device_id, stage)
                except Exception as exc:  # never lose the monitor to a callback
                    self._log(f"vendor DPI callback failed: {exc}")
