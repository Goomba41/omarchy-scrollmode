#!/usr/bin/env python3
"""scrollmoded - trackball scroll-mode daemon for Omarchy.

The daemon keeps a pointing device in its normal pointer mode and, on request,
grabs it exclusively (EVIOCGRAB) and replays its events through a uinput
device. While grabbed, ball movement is converted into high-resolution scroll
wheel events instead of pointer motion.

Only the grabbed interval is affected: in pointer mode the device is not
grabbed at all, so the compositor sees it exactly as before.

Control is a line based unix socket in the runtime directory; the current mode
is mirrored into a small file the bar widget watches.
"""

from __future__ import annotations

import argparse
import ctypes
from datetime import datetime
import errno
import fcntl
import glob
import json
import math
import os
import pwd
import re
import select
import selectors
import signal
import socket
import struct
import sys
import threading
import time
import traceback

try:
    import evdev
    from evdev import ecodes
except ImportError:  # pragma: no cover - reported before anything else runs
    sys.stderr.write(
        "scrollmoded: python-evdev is missing; install it first (see README: Requirements)\n"
    )
    raise SystemExit(1)

import dpi as dpi_providers

APP = "omarchy-scrollmode"
RUNTIME_DIR = os.environ.get("SCROLLMODE_RUNTIME_DIR", "/run/omarchy-scrollmode")
STATE_PATH = os.path.join(RUNTIME_DIR, "state")
DEVICE_PATH = os.path.join(RUNTIME_DIR, "device")
STATUS_PATH = os.path.join(RUNTIME_DIR, "status.json")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "control.sock")
STATE_DIR = os.environ.get("SCROLLMODE_STATE_DIR", "/var/lib/omarchy-scrollmode")
STATS_PATH = os.path.join(STATE_DIR, "stats.json")
IDENTITY_PATH = os.path.join(STATE_DIR, "identity.json")
LOCK_PATH = os.path.join(RUNTIME_DIR, "daemon.lock")

HIDPP_SW_ID = 0x0A
HIDPP_NAME_FEATURE = 0x0005
HIDPP_BATTERY_FEATURE = 0x1004
HIDPP_NAME_KEYS = ("m575", "ergo", "mx ", "trackball", "mouse")
HIDPP_LOCK = threading.Lock()

BATTERY_LEVELS = {1: "critical", 2: "low", 4: "good", 8: "full"}
BATTERY_STATES = {
    0: "discharging",
    1: "charging",
    2: "nearly-full",
    3: "full",
    4: "slow-charging",
    5: "invalid",
    6: "thermal-error",
    7: "charging-error",
}

# Inertia: a fast flick keeps scrolling after the ball stops, decaying.
INERTIA_TRIGGER_DEFAULT = 12.0  # notches/s at which a flick starts coasting
INERTIA_STRENGTH_DEFAULT = 100.0  # percent; higher = longer coast
INERTIA_DECAY_BASE = 4.0        # per second at 100 % strength
INERTIA_STOP_SPEED = 60.0      # counts/s at which coasting ends
INERTIA_MAX_SECONDS = 2.2
KEYBOARD_HINTS = ("keyboard", "keypad", "kbd")
# Buttons with a standard meaning that must not be repurposed as a sniper
# trigger: left/right/middle, Back/Forward (BTN_* and KEY_* variants).
RESERVED_BUTTONS = frozenset((158, 159, 272, 273, 274, 275, 276, 277, 278))
# Models that are trackballs even when the advertised name omits the word.
TRACKBALL_KEYS = (
    "trackball",
    "track ball",
    "m570",
    "m575",
    "mx ergo",
    "marble",
    "orbit",
    "slimblade",
    "expert mouse",
    "deft",
    "huge",
    "gameball",
    "ploopy",
    "trackman",
    "thumb ball",
    "kensington",
    "elecom",
)
TRACKPAD_KEYS = ("touchpad", "trackpad", "touch pad", "magic trackpad")
TABLET_KEYS = ("tablet", "wacom", "intuos", "bamboo", "huion", "xp-pen", "xppen")
MOUSE_KEYS = ("mouse", "mice")
DEVICE_CODES = {
    "trackball": "TB",
    "mouse": "MS",
    "trackpad": "TP",
    "tablet": "TA",
    "unknown": "UN",
}
HIDPP_TYPE_KINDS = {3: "mouse", 4: "trackpad", 5: "trackball"}

VIRTUAL_NAME = "omarchy-scrollmode virtual pointer"
VIRTUAL_PREFIX = "omarchy-scrollmode"

HI_RES_PER_NOTCH = 120

REL_WHEEL_HI_RES = getattr(ecodes, "REL_WHEEL_HI_RES", 0x0B)
REL_HWHEEL_HI_RES = getattr(ecodes, "REL_HWHEEL_HI_RES", 0x0C)

DEFAULTS = {
    "device": {
        "match": "logitech",
        "path": "",
        "selected": "",
        "exclude": ["omarchy-scrollmode"],
    },
    "hotkey": "ALT + Z",
    "sniper_hotkey": "ALT + S",
    "hold_threshold_ms": 300,
    "scroll": {
        "counts_per_notch": 85.0,
        "sensitivity": 1.0,
        "sniper_multiplier": 0.20,
        "invert_vertical": False,
        "invert_horizontal": False,
        "axis_lock": True,
        "axis_window_seconds": 0.25,
        "hi_res": True,
        "inertia": False,
        "inertia_trigger": 12.0,
        "inertia_strength": 100.0,
    },
    "sniper_button": 0,
    "exit_on_click": True,
    "auto_exit_seconds": 0,
    "hold_max_seconds": 60,
    "battery": {
        "show_bar": True,
        "low_percent": 20,
        "poll_seconds": 300,
    },
    "dpi": {
        "ratbag_device": "",
        "manual": {},
    },
}


def log(message: str) -> None:
    sys.stderr.write(f"{APP}: {message}\n")
    sys.stderr.flush()


def deep_merge(base: dict, override: dict) -> dict:
    merged = dict(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("top level must be a JSON object")
    return deep_merge(DEFAULTS, data)


def load_config_or_defaults(path: str) -> dict:
    """A missing config is not fatal: the daemon runs on the built-in defaults."""
    try:
        return load_config(path)
    except FileNotFoundError:
        log(f"config not found ({path}), using defaults")
        return deep_merge(DEFAULTS, {})


def event_paths() -> list[str]:
    def number(path: str) -> int:
        match = re.search(r"event(\d+)$", path)
        return int(match.group(1)) if match else 0

    return sorted(glob.glob("/dev/input/event*"), key=number)


def read_udev_props(path: str) -> dict:
    """Properties udev already worked out for this event node."""
    try:
        info = os.stat(path)
    except OSError:
        return {}
    database = f"/run/udev/data/c{os.major(info.st_rdev)}:{os.minor(info.st_rdev)}"
    props = {}
    try:
        with open(database, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("E:") and "=" in line:
                    key, _, value = line[2:].rstrip("\n").partition("=")
                    props[key] = value
    except OSError:
        pass
    return props


def clean_udev(value: str) -> str:
    return (value or "").replace("_", " ").strip()


def pretty_device_name(props: dict, fallback: str) -> str:
    vendor = props.get("ID_VENDOR_FROM_DATABASE") or clean_udev(props.get("ID_VENDOR", ""))
    model = props.get("ID_MODEL_FROM_DATABASE") or clean_udev(props.get("ID_MODEL", ""))
    if vendor and model:
        return model if vendor.lower() == model.lower() else f"{vendor} {model}"
    return model or vendor or fallback


def looks_like_keyboard(raw_name: str, props: dict) -> bool:
    haystack = " ".join(
        [
            raw_name,
            props.get("ID_VENDOR", ""),
            props.get("ID_MODEL", ""),
            props.get("ID_VENDOR_FROM_DATABASE", ""),
            props.get("ID_MODEL_FROM_DATABASE", ""),
        ]
    ).lower()
    return any(hint in haystack for hint in KEYBOARD_HINTS)


def device_identity(device: evdev.InputDevice) -> str:
    parts = [f"{device.info.vendor:04x}:{device.info.product:04x}", device.name or ""]
    uniq = (getattr(device, "uniq", "") or "").strip()
    if uniq:
        parts.append(uniq)
    return "|".join(parts)


def _hidpp_name_matches(hidpp_name: str, raw: str, display: str) -> bool:
    words = [
        word for word in re.findall(r"[a-z0-9]+", (hidpp_name or "").lower())
        if len(word) >= 3 and word not in ("logitech", "trackball", "mouse")
    ]
    haystack = f"{raw} {display}".lower()
    return bool(words) and any(word in haystack for word in words)


def _pointer_wireless(name: str, props: dict) -> bool:
    bus = str(props.get("ID_BUS") or "").lower()
    model = " ".join(
        str(props.get(key) or "") for key in ("ID_MODEL", "ID_MODEL_FROM_DATABASE", "ID_MODEL_ENC")
    ).lower()
    if bus == "bluetooth" or "bluetooth" in model:
        return True
    return "receiver" in model or "dongle" in model or "receiver" in name.lower()


def _pointer_connection(name: str, props: dict) -> str:
    """Best-effort transport label: usb, receiver, bluetooth or unknown."""
    bus = str(props.get("ID_BUS") or "").lower()
    haystack = " ".join(
        str(value or "")
        for value in (
            name,
            props.get("ID_MODEL"),
            props.get("ID_MODEL_FROM_DATABASE"),
            props.get("ID_MODEL_ENC"),
            props.get("ID_USB_MODEL"),
            props.get("ID_USB_MODEL_ENC"),
        )
    ).replace("_", " ").replace("-", " ").lower()
    if bus == "bluetooth" or "bluetooth" in haystack:
        return "bluetooth"
    if "receiver" in haystack or "dongle" in haystack:
        return "receiver"
    if bus == "usb":
        return "usb"
    return "unknown"


def _with_kind(kind: str, confidence: str, source: str) -> dict:
    return {
        "kind": kind,
        "code": DEVICE_CODES.get(kind, "UN"),
        "confidence": confidence,
        "sources": [source],
    }


def classify_pointer(name: str, raw_name: str, props: dict, caps: dict, hidpp_type: int | None = None) -> dict:
    """Classify a pointer from HID++, udev tags, names and evdev capabilities.

    HID++ is authoritative where the device speaks it (Logitech today); the
    other sources keep the classifier useful for every other vendor.
    """
    if hidpp_type in HIDPP_TYPE_KINDS:
        kind = HIDPP_TYPE_KINDS[hidpp_type]
        result = _with_kind(kind, "high", "hidpp:0x0005")
        result["wireless"] = _pointer_wireless(name, props)
        result["connection"] = _pointer_connection(f"{raw_name} {name}", props)
        return result

    if str(props.get("ID_INPUT_TRACKBALL") or "") == "1":
        result = _with_kind("trackball", "high", "udev:ID_INPUT_TRACKBALL")
    elif str(props.get("ID_INPUT_TOUCHPAD") or "") == "1":
        result = _with_kind("trackpad", "high", "udev:ID_INPUT_TOUCHPAD")
    elif str(props.get("ID_INPUT_TABLET") or "") == "1":
        result = _with_kind("tablet", "high", "udev:ID_INPUT_TABLET")
    else:
        haystack = " ".join(
            [
                raw_name,
                name,
                str(props.get("ID_MODEL") or ""),
                str(props.get("ID_MODEL_FROM_DATABASE") or ""),
                str(props.get("ID_MODEL_ENC") or ""),
                str(props.get("ID_VENDOR_FROM_DATABASE") or ""),
            ]
        ).lower()
        if any(key in haystack for key in TRACKBALL_KEYS):
            result = _with_kind("trackball", "medium", "name")
        elif any(key in haystack for key in TRACKPAD_KEYS):
            result = _with_kind("trackpad", "medium", "name")
        elif any(key in haystack for key in TABLET_KEYS):
            result = _with_kind("tablet", "medium", "name")
        elif "receiver" not in haystack and any(key in haystack for key in MOUSE_KEYS):
            result = _with_kind("mouse", "low", "name")
        elif ecodes.EV_ABS in caps and ecodes.ABS_X in caps.get(ecodes.EV_ABS, []) \
                and ecodes.ABS_Y in caps.get(ecodes.EV_ABS, []):
            result = _with_kind("trackpad", "low", "evdev:absolute")
        else:
            result = _with_kind("unknown", "low", "evdev:relative")
    result["wireless"] = _pointer_wireless(name, props)
    result["connection"] = _pointer_connection(f"{raw_name} {name}", props)
    return result


def scan_pointers(excluded: list[str]) -> tuple[list[dict], int]:
    """Every pointing device on the system, as stable ids + display names."""
    seen = set()
    found = []
    hidden = 0
    for path in event_paths():
        try:
            device = evdev.InputDevice(path)
        except OSError:
            continue
        try:
            name = device.name or ""
            lower = name.lower()
            if VIRTUAL_PREFIX in lower:
                continue
            if any(item and item in lower for item in excluded):
                continue
            caps = device.capabilities(absinfo=False)
            rel = set(caps.get(ecodes.EV_REL, []))
            keys = set(caps.get(ecodes.EV_KEY, []))
            if not (ecodes.REL_X in rel and ecodes.REL_Y in rel and ecodes.BTN_LEFT in keys):
                continue

            props = read_udev_props(path)
            if looks_like_keyboard(name, props):
                hidden += 1
                continue

            identity = device_identity(device)
            if identity in seen:
                continue
            seen.add(identity)
            display_name = pretty_device_name(props, name)
            classification = classify_pointer(display_name, name, props, caps)
            found.append(
                {
                    "id": identity,
                    "name": display_name,
                    "raw": name,
                    "path": path,
                    "seat": props.get("ID_SEAT") or "seat0",
                    **classification,
                }
            )
        finally:
            device.close()
    return found, hidden


def choose_device(cfg: dict, devices: list[dict]) -> dict | None:
    selected = str(cfg["device"].get("selected") or "")
    if selected:
        for device in devices:
            if device["id"] == selected:
                return device
        return None

    pinned = str(cfg["device"].get("path") or "")
    if pinned:
        for device in devices:
            if device["path"] == pinned:
                return device
        return None

    wanted = str(cfg["device"].get("match") or "").lower()
    if wanted:
        for device in devices:
            if wanted in device["name"].lower():
                return device
    for device in devices:
        if looks_like_trackball(device["name"]):
            return device
    return devices[0] if devices else None


def open_pointer(path: str) -> evdev.InputDevice | None:
    try:
        return evdev.InputDevice(path)
    except OSError as exc:
        log(f"cannot open {path}: {exc}")
        return None


def _hidpp_request(fd, index: int, feature: int, function: int, params: bytes = b"", timeout: float = 0.6):
    report = bytearray(20)
    report[0] = 0x11
    report[1] = index
    report[2] = feature
    report[3] = (function << 4) | HIDPP_SW_ID
    report[4:4 + len(params)] = params
    try:
        os.write(fd, bytes(report))
    except OSError:
        return None

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], max(0.02, deadline - time.monotonic()))
        if not readable:
            return None
        try:
            data = os.read(fd, 64)
        except OSError:
            return None
        if len(data) < 7 or data[0] not in (0x10, 0x11):
            continue
        if data[1] != index or data[2] != feature or (data[3] >> 4) != function:
            continue
        return data
    return None


def _hidpp_name(fd, index: int) -> str | None:
    found = None
    for _attempt in range(2):
        found = _hidpp_request(fd, index, 0x00, 0, struct.pack(">H", HIDPP_NAME_FEATURE))
        if found and found[2] == 0x00:
            break
        time.sleep(0.05)
    if not found or found[2] != 0x00:
        return None

    feature = found[4]
    if feature in (0x00, 0xFF) or feature >= 0x20:
        return None

    count = _hidpp_request(fd, index, feature, 0)
    if not count:
        return None
    length = count[4]
    if not 0 < length <= 128:
        return None

    raw = b""
    offset = 0
    while offset < length:
        part = _hidpp_request(fd, index, feature, 1, bytes([offset]))
        if not part:
            break
        chunk = bytes(part[4:])
        if not chunk:
            break
        raw += chunk[: length - offset]
        offset += len(chunk)

    if len(raw) < length:
        return None
    return raw[:length].decode("utf-8", "replace").strip("\x00 ")


def _hidpp_device_type(fd, index: int):
    feature = _hidpp_feature_index(fd, index, HIDPP_NAME_FEATURE)
    if feature is None:
        return None
    response = _hidpp_request(fd, index, feature, 2)
    if not response or len(response) < 5:
        return None
    return response[4]


def _hidpp_probe_once_unlocked() -> tuple[str, int | None]:
    for link in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(os.path.join(link, "device", "uevent"), "r", encoding="utf-8") as handle:
                uevent = handle.read()
            with open(os.path.join(link, "device", "report_descriptor"), "rb") as handle:
                descriptor = handle.read()
        except OSError:
            continue
        if "046D" not in uevent.upper() or b"\x06\x00\xff" not in descriptor:
            continue

        node = "/dev/" + os.path.basename(link)
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            while select.select([fd], [], [], 0)[0]:
                os.read(fd, 64)
            time.sleep(0.1)
            best = None
            for index in range(1, 7):
                name = _hidpp_name(fd, index)
                if not name:
                    continue
                type_code = _hidpp_device_type(fd, index)
                if type_code in HIDPP_TYPE_KINDS:
                    score = 3
                elif any(key in name.lower() for key in HIDPP_NAME_KEYS):
                    score = 1
                else:
                    score = 0
                if best is None or score > best[0]:
                    best = (score, name, type_code)
                    if score == 3:
                        break
            if best:
                return best[1], best[2]
        finally:
            os.close(fd)
    return "", None


def _hidpp_probe_once() -> tuple[str, int | None]:
    with HIDPP_LOCK:
        return _hidpp_probe_once_unlocked()


def _hidpp_feature_index(fd, index: int, feature_id: int, timeout: float = 0.3):
    response = _hidpp_request(fd, index, 0x00, 0, struct.pack(">H", feature_id), timeout)
    if not response or response[2] != 0x00 or len(response) < 5:
        return None
    feature = response[4]
    return feature if feature not in (0x00, 0xFF) else None


def parse_battery(caps: bytes, info: bytes, wireless: bool = False) -> dict:
    """Decode the HID++ 0x1004 unified battery reads."""
    if not caps or not info or len(caps) < 2 or len(info) < 3:
        return unavailable_battery()
    has_percentage = bool(caps[1] & 0x02)
    percent = int(info[0]) if has_percentage else None
    level = BATTERY_LEVELS.get(int(info[1]), "")
    state = BATTERY_STATES.get(int(info[2]), "")
    return {
        "available": True,
        "percent": max(0, min(100, percent)) if percent is not None else None,
        "level": level,
        "state": state,
        "charging": state in ("charging", "nearly-full", "slow-charging"),
        "wireless": bool(wireless),
        "source": "hidpp",
        "updated": datetime.now().astimezone().isoformat(timespec="seconds"),
    }


def unavailable_battery() -> dict:
    return {
        "available": False,
        "percent": None,
        "level": "",
        "state": "",
        "charging": False,
        "wireless": False,
        "source": "",
        "updated": "",
    }


def _read_battery_at(node: str, index: int, feature: int, wireless: bool = False):
    try:
        fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        time.sleep(0.15)
        while select.select([fd], [], [], 0)[0]:
            os.read(fd, 64)
        caps = _hidpp_request(fd, index, feature, 0)
        info = _hidpp_request(fd, index, feature, 1)
    finally:
        os.close(fd)
    if not caps or not info:
        return None
    return parse_battery(bytes(caps[4:]), bytes(info[4:]), wireless)


_BATTERY_HINT = None


def _find_battery() -> tuple[str, int, int, bool] | None:
    best = None
    for link in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(os.path.join(link, "device", "uevent"), "r", encoding="utf-8") as handle:
                uevent = handle.read()
            with open(os.path.join(link, "device", "report_descriptor"), "rb") as handle:
                descriptor = handle.read()
        except OSError:
            continue
        if "046D" not in uevent.upper() or b"\x06\x00\xff" not in descriptor:
            continue
        hid_name = ""
        hid_id = ""
        for line in uevent.splitlines():
            if line.startswith("HID_NAME="):
                hid_name = line.partition("=")[2]
            elif line.startswith("HID_ID="):
                hid_id = line.partition("=")[2]
        wireless = "receiver" in hid_name.lower() or hid_id.upper().startswith("0005:")
        node = "/dev/" + os.path.basename(link)
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            while select.select([fd], [], [], 0)[0]:
                os.read(fd, 64)
            time.sleep(0.1)
            for index in range(1, 7):
                # Ask for the feature first: absent devices answer the root
                # request immediately, while the name lookup can wait for a
                # sleep timeout on every empty pairing slot.
                feature = _hidpp_feature_index(fd, index, HIDPP_BATTERY_FEATURE, 0.3)
                if feature is None:
                    continue
                name = _hidpp_name(fd, index) or ""
                lower = name.lower()
                if any(key in lower for key in ("m575", "ergo", "trackball", "mouse")):
                    score = 3
                elif "mx " in lower:
                    score = 1
                else:
                    score = 0
                if best is None or score > best[0]:
                    best = (score, node, index, feature, wireless)
        except OSError:
            continue
        finally:
            os.close(fd)
    return (best[1], best[2], best[3], best[4]) if best else None


def hidpp_battery_state() -> dict:
    """Read the paired mouse battery over HID++, keeping the last good value."""
    global _BATTERY_HINT
    with HIDPP_LOCK:
        if _BATTERY_HINT:
            for attempt in range(2):
                state = _read_battery_at(*_BATTERY_HINT)
                if state and state["available"]:
                    return state
                if attempt == 0:
                    time.sleep(0.1)
            _BATTERY_HINT = None
        hint = _find_battery()
        if hint:
            for attempt in range(2):
                state = _read_battery_at(*hint)
                if state and state["available"]:
                    _BATTERY_HINT = hint
                    return state
                if attempt == 0:
                    time.sleep(0.1)
    return unavailable_battery()


def hidpp_device_identity() -> tuple[str, int | None]:
    """Ask the Logitech receiver for the paired name and device type."""
    for attempt in range(3):
        name, type_code = _hidpp_probe_once()
        if name:
            return name, type_code
        time.sleep(0.15)
    return "", None


def hidpp_device_name() -> str:
    return hidpp_device_identity()[0]


def looks_like_trackball(name: str) -> bool:
    lower = (name or "").lower()
    return any(key in lower for key in TRACKBALL_KEYS)


def friendly_device_name(raw: str) -> str:
    name = (raw or "").strip()
    if not name:
        return ""
    if not name.lower().startswith("logitech"):
        name = "Logitech " + name
    if name.lower().endswith(" trackball"):
        name = name[: -len(" trackball")].strip()
    return name


class ScrollConverter:
    """Turns relative pointer counts into wheel events."""

    def __init__(self) -> None:
        self.counts_per_notch = 85.0
        self.sensitivity = 1.0
        self.speed = 1.0
        self.invert_v = False
        self.invert_h = False
        self.axis_lock = True
        self.axis_window = 0.25
        self.hi_res = True
        self.inertia = False
        self.inertia_trigger = INERTIA_TRIGGER_DEFAULT
        self.inertia_strength = INERTIA_STRENGTH_DEFAULT
        self.inertia_min_speed = 0.0
        self.inertia_decay = INERTIA_DECAY_BASE
        self.frame_interval = 0.008
        self.reset()

    def configure(self, cfg: dict) -> None:
        scroll = cfg["scroll"]
        self.counts_per_notch = max(1.0, float(scroll.get("counts_per_notch") or 85.0))
        self.sensitivity = max(0.0, float(scroll.get("sensitivity", 1.0)))
        self.invert_v = bool(scroll.get("invert_vertical"))
        self.invert_h = bool(scroll.get("invert_horizontal"))
        self.axis_lock = bool(scroll.get("axis_lock", True))
        self.axis_window = max(0.0, float(scroll.get("axis_window_seconds", 0.25)))
        self.hi_res = bool(scroll.get("hi_res", True))
        self.inertia = bool(scroll.get("inertia", False))
        self.inertia_trigger = max(
            1.0, float(scroll.get("inertia_trigger", INERTIA_TRIGGER_DEFAULT) or INERTIA_TRIGGER_DEFAULT)
        )
        self.inertia_strength = max(
            10.0,
            float(scroll.get("inertia_strength", INERTIA_STRENGTH_DEFAULT) or INERTIA_STRENGTH_DEFAULT),
        )
        self.inertia_min_speed = self.inertia_trigger * self.counts_per_notch
        self.inertia_decay = INERTIA_DECAY_BASE / (self.inertia_strength / 100.0)

    def reset(self) -> None:
        self.acc_v = 0.0
        self.acc_h = 0.0
        self.hr_v = 0
        self.hr_h = 0
        self.axis: str | None = None
        self.last_motion = 0.0
        self.vel_x = 0.0
        self.vel_y = 0.0
        self.peak_speed = 0.0
        self.peak_at = 0.0
        self.last_dx = 0
        self.last_dy = 0
        self.inertia_active = False
        self.inertia_axis: str | None = None
        self.inertia_started = 0.0
        self.last_tick = 0.0
        self.gesture_reported = True
        self.report_pending = False
        self.last_peak_notches = 0.0
        self.release_notches = 0.0
        self.peak_triggered = False
        self.gesture_active = False
        self.gesture_frames = 0
        self.gesture_first = 0.0
        self.gesture_total_x = 0
        self.gesture_total_y = 0
        self.gesture_raw_counts = 0.0
        self.gesture_up = 0.0
        self.gesture_down = 0.0
        self.gesture_left = 0.0
        self.gesture_right = 0.0
        self.gesture_peak_counts = 0.0
        self.gesture_peak_dt = 0.0
        self.gesture_tail_speed = 0.0

    def _pick_axis(self, dx: int, dy: int, now: float) -> str | None:
        if not self.axis_lock:
            return None
        if self.axis and now - self.last_motion > self.axis_window:
            self.axis = None

        # A clean change of direction switches the axis immediately, so a
        # vertical gesture followed by a horizontal one is not swallowed.
        if self.axis == "y" and dx and not dy:
            self.axis = "x"
        elif self.axis == "x" and dy and not dx:
            self.axis = "y"

        # Only lock an axis when it clearly dominates; a diagonal gesture keeps
        # both components and scrolls diagonally.
        if self.axis is None and abs(dx) + abs(dy) >= 3:
            if abs(dx) >= abs(dy) * 1.4:
                self.axis = "x"
            elif abs(dy) >= abs(dx) * 1.4:
                self.axis = "y"
        return self.axis

    def _axis_events(self, counts: float, vertical: bool) -> list[tuple[int, int, int]]:
        if counts == 0 or self.sensitivity == 0:
            return []

        # Work in high-resolution wheel units (120 per notch) so the discrete
        # wheel clicks stay exact integer arithmetic.
        units = (
            counts
            / self.counts_per_notch
            * self.sensitivity
            * self.speed
            * HI_RES_PER_NOTCH
        )
        out: list[tuple[int, int, int]] = []

        if vertical:
            self.acc_v += units
            whole = int(self.acc_v + math.copysign(1e-6, self.acc_v))
            self.acc_v -= whole
            if whole:
                if self.hi_res:
                    out.append((ecodes.EV_REL, REL_WHEEL_HI_RES, whole))
                self.hr_v += whole
            clicks = int(self.hr_v / HI_RES_PER_NOTCH)
            if clicks:
                out.append((ecodes.EV_REL, ecodes.REL_WHEEL, clicks))
                self.hr_v -= clicks * HI_RES_PER_NOTCH
        else:
            self.acc_h += units
            whole = int(self.acc_h + math.copysign(1e-6, self.acc_h))
            self.acc_h -= whole
            if whole:
                if self.hi_res:
                    out.append((ecodes.EV_REL, REL_HWHEEL_HI_RES, whole))
                self.hr_h += whole
            clicks = int(self.hr_h / HI_RES_PER_NOTCH)
            if clicks:
                out.append((ecodes.EV_REL, ecodes.REL_HWHEEL, clicks))
                self.hr_h -= clicks * HI_RES_PER_NOTCH
        return out

    def events(self, dx: int, dy: int, now: float) -> list[tuple[int, int, int]]:
        if dx == 0 and dy == 0:
            return []

        raw_dx, raw_dy = dx, dy
        previous = self.last_motion
        if previous:
            interval = now - previous
            if 0.002 <= interval <= 0.05:
                self.frame_interval = self.frame_interval * 0.8 + interval * 0.2
        axis = self._pick_axis(dx, dy, now)
        if axis == "x":
            dy = 0
            self.vel_y = 0.0
        elif axis == "y":
            dx = 0
            self.vel_x = 0.0
        if dx == 0 and dy == 0:
            return []

        # A new gesture must not inherit the speed of the previous one. Without
        # this, a slow vertical drag right after a fast horizontal one could
        # coast on the stale horizontal velocity.
        long_pause = bool(previous and now - previous > 0.15)
        if long_pause:
            self.vel_x = 0.0
            self.vel_y = 0.0
            previous = now - 0.016

        dt = max(0.001, now - previous) if previous else 0.016
        self.vel_x = self.vel_x * 0.65 + (dx / dt) * 0.35
        self.vel_y = self.vel_y * 0.65 + (dy / dt) * 0.35
        if self.inertia_active:
            # A new movement cancels the coast. Forget both the old peak and
            # the coast velocity, otherwise a tiny residual frame could start a
            # second coast from the same flick once this motion stops again.
            log(f"inertia cancelled after {(now - self.inertia_started) * 1000:.0f} ms")
            self.peak_speed = 0.0
            self.peak_at = 0.0
            self.vel_x = 0.0
            self.vel_y = 0.0
        self.inertia_active = False
        new_gesture = self.gesture_reported or not self.gesture_active or long_pause
        if new_gesture:
            # A previous gesture may have ended without a coast; never let its
            # peak trigger or colour the next one.
            self.peak_speed = 0.0
            self.peak_at = 0.0
            self.gesture_active = True
            self.gesture_frames = 0
            self.gesture_first = now
            self.gesture_total_x = 0
            self.gesture_total_y = 0
            self.gesture_raw_counts = 0.0
            self.gesture_up = 0.0
            self.gesture_down = 0.0
            self.gesture_left = 0.0
            self.gesture_right = 0.0
            self.gesture_peak_counts = 0.0
            self.gesture_peak_dt = 0.0
            self.gesture_tail_speed = 0.0
        self.gesture_reported = False
        self.last_motion = now
        self.last_dx = dx
        self.last_dy = dy

        # Use the raw frame speed for the peak, not the smoothed velocity.
        # A very short flick only gets 35 % of its real speed through the EMA,
        # so it could miss the trigger while a longer flick at the same speed
        # passed. Remember the fastest frame over 300 ms instead.
        frame_speed = math.hypot(dx / dt, dy / dt)
        if now - self.peak_at > 0.30 or frame_speed >= self.peak_speed:
            self.peak_speed = frame_speed
            self.peak_at = now

        self.gesture_frames += 1
        self.gesture_total_x += abs(dx)
        self.gesture_total_y += abs(dy)
        self.gesture_raw_counts += math.hypot(raw_dx, raw_dy)
        if raw_dy > 0:
            self.gesture_down += raw_dy
        elif raw_dy < 0:
            self.gesture_up -= raw_dy
        if raw_dx > 0:
            self.gesture_right += raw_dx
        elif raw_dx < 0:
            self.gesture_left -= raw_dx
        self.gesture_tail_speed = frame_speed
        if frame_speed >= self.gesture_peak_counts:
            self.gesture_peak_counts = frame_speed
            self.gesture_peak_dt = dt

        vertical = -dy if not self.invert_v else dy
        horizontal = dx if not self.invert_h else -dx
        return self._axis_events(vertical, True) + self._axis_events(horizontal, False)

    def guard_seconds(self) -> float:
        """How long to wait for another frame before starting the coast."""
        return min(0.04, max(0.010, self.frame_interval * 1.5))

    def _coast_at_release(self) -> None:
        """Continue at the speed the ball had at release, not at its peak.

        The trigger uses the peak, but jumping back to it makes the coast kick
        after the app has already animated the slower tail.
        """
        release = math.hypot(self.vel_x, self.vel_y)
        if release < 0.001:
            release = min(self.peak_speed, self.inertia_min_speed)
        if self.axis_lock:
            if self.inertia_axis == "x":
                sign = 1.0 if (self.vel_x > 0 or (self.vel_x == 0 and self.last_dx >= 0)) else -1.0
                self.vel_x = sign * release
                self.vel_y = 0.0
            else:
                sign = 1.0 if (self.vel_y > 0 or (self.vel_y == 0 and self.last_dy >= 0)) else -1.0
                self.vel_y = sign * release
                self.vel_x = 0.0
            return

        current = math.hypot(self.vel_x, self.vel_y)
        if current > 0.001:
            scale = release / current
            self.vel_x *= scale
            self.vel_y *= scale
        else:
            self.vel_x = math.copysign(release, self.last_dx or 1)
            self.vel_y = math.copysign(release, self.last_dy or 1)

    def inertia_events(self, now: float) -> list[tuple[int, int, int]]:
        """Coast after a flick, decaying to a stop."""
        if not self.inertia:
            return []

        if not self.inertia_active:
            # Wait for roughly one and a half frame intervals, so a 125 Hz
            # device starts its coast after ~12 ms instead of a fixed pause.
            if now - self.last_motion < self.guard_seconds():
                return []
            if not self.gesture_reported:
                self.gesture_reported = True
                self.gesture_active = False
                self.last_peak_notches = self.peak_speed / self.counts_per_notch
                self.release_notches = math.hypot(self.vel_x, self.vel_y) / self.counts_per_notch
                self.peak_triggered = self.peak_speed >= self.inertia_min_speed
                self.report_pending = True
            if now - self.peak_at > 0.30 or self.peak_speed < self.inertia_min_speed:
                return []
            self.inertia_active = True
            self.inertia_started = now
            # Do not turn the whole quiet gap into one large first frame: that
            # reads as a second kick after the app has already animated the
            # real scroll. One normal frame's worth is enough.
            self.last_tick = max(self.last_motion, now - 0.008)
            self.inertia_axis = self.axis if self.axis_lock else None
            self._coast_at_release()
            log(
                f"inertia peak {self.peak_speed:.0f} / release "
                f"{math.hypot(self.vel_x, self.vel_y):.0f} counts/s "
                f"after {(now - self.last_motion) * 1000:.0f} ms"
            )

        dt = min(0.05, max(0.001, now - self.last_tick))
        self.last_tick = now
        decay = math.exp(-self.inertia_decay * dt)
        self.vel_x *= decay
        self.vel_y *= decay

        vx, vy = self.vel_x, self.vel_y
        if self.inertia_axis == "x":
            vy = 0.0
        elif self.inertia_axis == "y":
            vx = 0.0

        if math.hypot(vx, vy) < INERTIA_STOP_SPEED or now - self.inertia_started > INERTIA_MAX_SECONDS:
            self.inertia_active = False
            self.peak_speed = 0.0
            self.peak_at = 0.0
            return []

        vertical = (-vy if not self.invert_v else vy) * dt
        horizontal = (vx if not self.invert_h else -vx) * dt
        return self._axis_events(vertical, True) + self._axis_events(horizontal, False)


class SeatGuard:
    """Which user owns the active session on the seat we are about to grab.

    libsystemd is used directly: sd_pid_get_session() is not usable here because
    uwsm keeps the compositor outside the session-N.scope, but sd_seat_get_active()
    answers the only question that matters - is the installing user the one
    sitting at this seat right now.
    """

    def __init__(self) -> None:
        self._lib = None
        self._load_failed = False
        self._warned = False
        self._libc = None

    def _load(self):
        if self._lib is not None or self._load_failed:
            return self._lib
        try:
            lib = ctypes.CDLL("libsystemd.so.0", use_errno=True)
            lib.sd_seat_get_active.argtypes = [
                ctypes.c_char_p,
                ctypes.POINTER(ctypes.c_char_p),
                ctypes.POINTER(ctypes.c_uint),
            ]
            lib.sd_seat_get_active.restype = ctypes.c_int
            try:
                libc = ctypes.CDLL("libc.so.6", use_errno=True)
                libc.free.argtypes = [ctypes.c_void_p]
                libc.free.restype = None
                self._libc = libc
            except (OSError, AttributeError):
                self._libc = None
            self._lib = lib
        except (OSError, AttributeError):
            self._load_failed = True
        return self._lib

    def active(self, seat: str) -> tuple[str, int] | None:
        """The active (session, uid) on the seat, or None when unknown."""
        lib = self._load()
        if lib is None:
            if not self._warned:
                log("libsystemd is unavailable; the session guard cannot verify the seat")
                self._warned = True
            return None
        session = ctypes.c_char_p()
        uid = ctypes.c_uint()
        try:
            result = lib.sd_seat_get_active(
                seat.encode("utf-8"), ctypes.byref(session), ctypes.byref(uid)
            )
        except OSError:
            return None
        value = session.value.decode("utf-8", "replace") if session.value else ""
        if self._libc is not None:
            self._libc.free(ctypes.cast(session, ctypes.c_void_p))
        if result < 0:
            return None
        return value, int(uid.value)


class DeviceLost(Exception):
    pass


def default_trackball_stats() -> dict:
    return {
        "counts": 0.0,
        "notches": 0.0,
        "flicks": 0,
        "coasted": 0,
        "scroll_ms": 0.0,
        "up": 0.0,
        "down": 0.0,
        "left": 0.0,
        "right": 0.0,
        "max_peak_notches": 0.0,
        "max_peak_counts": 0.0,
        "max_flick_ms": 0.0,
        "max_coast_notches": 0.0,
        "days": {},
    }


def default_mouse_stats() -> dict:
    return {
        "counts": 0.0,
        "distance_m": 0.0,
        "distance_migrated": False,
        "wheel": 0.0,
        "clicks": 0,
        "active_ms": 0.0,
        "up": 0.0,
        "down": 0.0,
        "left": 0.0,
        "right": 0.0,
        "max_speed": 0.0,
        "dpi": 0.0,
        "days": {},
    }


class BatteryMonitor(threading.Thread):
    """Poll the paired mouse battery without blocking the scroll event loop."""

    def __init__(self, daemon: "Daemon") -> None:
        super().__init__(name="battery", daemon=True)
        self.owner = daemon
        self.stop_event = threading.Event()
        self.wake_event = threading.Event()
        self.attempts = 0

    def stop(self) -> None:
        self.stop_event.set()
        self.wake_event.set()

    def wake(self) -> None:
        self.wake_event.set()

    def run(self) -> None:
        while not self.stop_event.is_set():
            try:
                state = hidpp_battery_state()
            except Exception as exc:  # never lose the poller to a bad report
                log(f"battery read failed: {exc}")
                state = None
            self.owner.set_battery(state)
            battery_cfg = self.owner.cfg.get("battery") or {}
            try:
                poll = float(battery_cfg.get("poll_seconds") or 300)
            except (TypeError, ValueError):
                poll = 300.0
            # A missing battery is often just a sleeping mouse or a busy
            # receiver. Try a few quick reads at startup, then settle into the
            # configured interval.
            if state and state.get("available"):
                self.attempts = 0
                wait = max(30.0, min(3600.0, poll))
            else:
                self.attempts += 1
                wait = 3.0 if self.attempts <= 5 else 30.0
            self.wake_event.wait(wait)
            self.wake_event.clear()


class Daemon:
    def __init__(self, config_path: str, uid: int, gid: int) -> None:
        self.config_path = config_path
        self.uid = uid
        self.gid = gid
        self.stats_path = STATS_PATH
        self.stats = {}
        self.cfg = load_config_or_defaults(config_path)
        self.converter = ScrollConverter()
        self.converter.configure(self.cfg)
        self.dpi_manager = dpi_providers.DpiManager(
            os.path.join(STATE_DIR, "dpi.json"), self.cfg, logger=log
        )
        self.dpi_monitor = dpi_providers.VendorMonitor(self.on_vendor_dpi, log)
        self.dpi_info = dpi_providers.none_info()
        self.dpi_dirty = False
        self.dpi_force = False
        self.last_dpi_at = 0.0
        self.last_dpi_id = ""

        self.mode = "pointer"
        self.dev: evdev.InputDevice | None = None
        self.ui: evdev.UInput | None = None
        self.grabbed = False
        self.frame: list = []
        self.running = True
        self.reload_pending = False
        self.toggle_pending = False
        self.last_activity = time.monotonic()
        self.activated_at = 0.0
        self.last_click_exit = 0.0
        self.press = None
        self.button_hold: str | None = None
        self.device_name = ""
        self.hidpp_type = None
        self.identity_ok = False
        self.identity_generation = 0
        self.last_identity_probe = 0.0
        self.active_id = ""
        self.last_scan = 0.0
        self.empty_scans = 0
        self.seat = "seat0"
        self.seat_guard = SeatGuard()
        self.last_seat_check = 0.0
        self.last_denied_log = 0.0
        self.learning_until = 0.0
        self.learn_error_until = 0.0
        self.learn_code = 0
        self.learn_error = ""
        self.rescan_requested = False
        self.battery = unavailable_battery()
        self.battery_dirty = False
        self.battery_thread = BatteryMonitor(self)
        self.device_kind = "unknown"
        self.supports_scroll = True
        self.supports_stats = False
        self.supports_buttons = False
        self.stats_dirty = False
        self.last_stats_save = 0.0
        self.last_stats_at = 0.0

        self.sel = selectors.DefaultSelector()
        self.server: socket.socket | None = None
        self.lock_handle = None

    # -- lifecycle ---------------------------------------------------------

    def logitech_receiver(self) -> bool:
        name = getattr(self.dev, "name", "") or ""
        return self.dev is not None and "logitech" in name.lower()

    def read_identity_cache(self) -> dict:
        try:
            with open(IDENTITY_PATH, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return {}
        if not isinstance(data, dict):
            return {}
        devices = data.get("devices")
        if isinstance(devices, dict):
            return {
                str(key): entry
                for key, entry in devices.items()
                if key and isinstance(entry, dict) and entry.get("name")
            }
        if data.get("id") and data.get("name"):
            return {str(data["id"]): data}  # migrate the single-device cache
        return {}

    def load_identity(self) -> dict | None:
        entry = self.read_identity_cache().get(self.active_id)
        if not isinstance(entry, dict) or not entry.get("name"):
            return None
        return entry

    def save_identity(self, device_id: str, raw: str, type_code) -> None:
        if not device_id:
            return
        try:
            os.makedirs(os.path.dirname(IDENTITY_PATH), mode=0o755, exist_ok=True)
            devices = self.read_identity_cache()
            devices[device_id] = {"name": raw, "type": type_code}
            tmp = IDENTITY_PATH + ".tmp"
            with open(tmp, "w", encoding="utf-8") as handle:
                json.dump({"devices": devices}, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
            os.replace(tmp, IDENTITY_PATH)
            os.chmod(IDENTITY_PATH, 0o644)
        except OSError as exc:
            log(f"cannot write {IDENTITY_PATH}: {exc}")

    def prepare_runtime(self) -> None:
        os.makedirs(RUNTIME_DIR, mode=0o755, exist_ok=True)
        try:
            os.makedirs(STATE_DIR, mode=0o755, exist_ok=True)
        except OSError as exc:
            log(f"cannot create {STATE_DIR}: {exc}")
        self.stats = self.load_stats()
        self.lock_handle = open(LOCK_PATH, "w", encoding="utf-8")
        try:
            fcntl.flock(self.lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise SystemExit(f"{APP}: another instance is already running")

        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o600)
        os.chown(SOCKET_PATH, self.uid, self.gid)
        server.listen(8)
        server.setblocking(False)
        self.server = server
        self.sel.register(server, selectors.EVENT_READ, "server")

        self.write_state()
        self.write_device("")
        self.refresh_status(force=True)

    def write_state(self) -> None:
        try:
            with open(STATE_PATH, "w", encoding="utf-8") as handle:
                handle.write(self.mode + "\n")
            os.chmod(STATE_PATH, 0o644)
            os.chown(STATE_PATH, self.uid, self.gid)
        except OSError as exc:
            log(f"cannot write {STATE_PATH}: {exc}")

    def probe_device_name(self, fallback: str) -> None:
        if not self.logitech_receiver():
            self.identity_ok = False
            self.hidpp_type = None
            self.device_name = fallback
            self.write_device(self.device_name)
            self.refresh_status(force=True)
            return

        device_id = self.active_id
        generation = self.identity_generation

        def work() -> None:
            previous_name = self.device_name
            try:
                raw, type_code = hidpp_device_identity()
            except Exception as exc:  # never let the probe hurt the daemon
                log(f"hidpp identity probe failed: {exc}")
                raw, type_code = "", None
            if generation != self.identity_generation or device_id != self.active_id:
                log("identity probe result discarded for a previous device")
                return
            if raw:
                self.hidpp_type = type_code
                self.identity_ok = True
                self.device_name = friendly_device_name(raw)
                self.save_identity(device_id, raw, type_code)
            else:
                self.identity_ok = False
                self.hidpp_type = self.hidpp_type if previous_name else None
                self.device_name = previous_name or fallback
            self.write_device(self.device_name)
            self.refresh_status(force=True)
            log(f"device name: {self.device_name} (type {self.hidpp_type})")

        self.last_identity_probe = time.monotonic()
        threading.Thread(target=work, name="hidpp-name", daemon=True).start()

    def write_device(self, name: str) -> None:
        try:
            with open(DEVICE_PATH, "w", encoding="utf-8") as handle:
                handle.write((name.strip() + "\n") if name else "")
            os.chmod(DEVICE_PATH, 0o644)
            os.chown(DEVICE_PATH, self.uid, self.gid)
        except OSError as exc:
            log(f"cannot write {DEVICE_PATH}: {exc}")

    def set_battery(self, state: dict | None) -> None:
        previous = (self.battery.get("percent"), self.battery.get("state"))
        if state and state.get("available"):
            state = dict(state)
            state["stale"] = False
            self.battery = state
            current = (state.get("percent"), state.get("state"))
            if current != previous:
                percent = f"{state['percent']}%" if state.get("percent") is not None else "level"
                log(f"battery {percent} {state.get('state') or 'unknown'}")
        elif self.battery.get("available"):
            last = dict(self.battery)
            last["stale"] = True
            self.battery = last
        else:
            self.battery = unavailable_battery()
        self.battery_dirty = True

    def current_dpi(self) -> int:
        try:
            return int(self.dpi_info.get("dpi") or 0)
        except (TypeError, ValueError):
            return 0

    def on_vendor_dpi(self, device_id: str, stage: int) -> None:
        """Called from the vendor monitor thread with a new DPI stage."""
        value = self.dpi_manager.note_vendor_stage(device_id, stage)
        if value > 0:
            log(f"vendor DPI stage {stage + 1} · {value} DPI")
        if device_id == self.active_id:
            self.dpi_dirty = True

    def update_dpi(self, name: str, raw_name: str, force: bool = False) -> None:
        now = time.monotonic()
        changed = self.active_id != self.last_dpi_id
        if changed:
            self.last_dpi_id = self.active_id
            self.last_dpi_at = 0.0
        if not (force or changed or now - self.last_dpi_at >= 15.0):
            return
        self.last_dpi_at = now
        self.dpi_info = self.dpi_manager.snapshot(
            self.active_id,
            name,
            raw_name,
            self.device_kind,
            force=force or changed,
            allow_ratbag=self.mode == "pointer",
        )
        self.dpi_monitor.set_target(self.active_id, name, raw_name)

    def refresh_status(self, force: bool = False) -> None:
        # Enumerating every /dev/input node costs a few hundred milliseconds on
        # a normal machine. That is invisible in pointer mode (the device is not
        # grabbed) but it stalls the grabbed event stream while scrolling and
        # makes the velocity estimate jump. The device list does not change
        # under an active grab, so keep the last snapshot until pointer mode.
        if not force and self.mode != "pointer":
            return
        now = time.monotonic()
        if not force and now - self.last_scan < 2.0:
            return
        self.last_scan = now

        excluded = [str(item).lower() for item in self.cfg["device"].get("exclude") or []]
        devices, hidden = scan_pointers(excluded)
        # An empty list while a device is open is inconsistent: the daemon holds
        # an event node, but the enumeration skipped everything. A rescan closes
        # and re-opens the device, which clears the state.
        if not devices and self.dev is not None:
            self.empty_scans += 1
            if self.empty_scans >= 2:
                self.empty_scans = 0
                self.rescan_requested = True
                log("device scan came back empty, rescanning")
        else:
            self.empty_scans = 0
        listed = []
        active_name = ""
        active_raw = ""
        active_kind = ""
        active_code = "UN"
        active_confidence = "low"
        active_wireless = False
        active_connection = "unknown"
        identities = self.read_identity_cache()
        for device in devices:
            name = device["name"]
            raw = device.get("raw", "").lower()
            receiver = "logitech usb receiver" in raw
            cached = identities.get(device["id"])
            if cached:
                name = friendly_device_name(cached["name"])
            if (
                receiver
                and device["id"] == self.active_id
                and self.device_name
                and (self.identity_ok or not cached)
            ):
                name = self.device_name
            kind = device.get("kind", "unknown")
            code = device.get("code", "UN")
            confidence = device.get("confidence", "low")
            sources = list(device.get("sources") or [])
            wireless = bool(device.get("wireless"))
            connection = str(device.get("connection") or "unknown")
            hidpp_type = cached.get("type") if cached else None
            if device["id"] == self.active_id and self.hidpp_type is not None:
                hidpp_type = self.hidpp_type
            if hidpp_type in HIDPP_TYPE_KINDS and (receiver or cached):
                kind = HIDPP_TYPE_KINDS[hidpp_type]
                code = DEVICE_CODES.get(kind, "UN")
                confidence = "high"
                sources = ["hidpp:0x0005"]
            elif self.hidpp_type in HIDPP_TYPE_KINDS and (
                _hidpp_name_matches(self.device_name, device.get("raw", ""), name)
            ):
                kind = HIDPP_TYPE_KINDS[self.hidpp_type]
                code = DEVICE_CODES.get(kind, "UN")
                confidence = "high"
                sources = ["hidpp:0x0005"]
            listed.append({
                "id": device["id"],
                "name": name,
                "kind": kind,
                "code": code,
                "confidence": confidence,
                "sources": sources,
                "wireless": wireless,
                "connection": connection,
            })
            if device["id"] == self.active_id:
                active_name = name
                active_raw = str(device.get("raw") or "")
                active_kind = kind
                active_code = code
                active_confidence = confidence
                active_wireless = wireless
                active_connection = connection

        self.device_kind = active_kind or "unknown"
        self.supports_scroll = self.device_kind in ("trackball", "unknown")
        self.supports_stats = self.device_kind in ("trackball", "mouse")
        self.supports_buttons = self.device_kind in ("trackball", "unknown")
        if self.ensure_mouse_device():
            self.save_stats()
        self.update_dpi(active_name, active_raw, force=self.dpi_force)
        self.dpi_force = False

        configured = self.sniper_button_code()
        buttons: set[int] = set()
        if self.dev is not None:
            try:
                buttons = set(self.dev.capabilities(absinfo=False).get(ecodes.EV_KEY, []))
            except OSError:
                buttons = set()
        if configured and configured not in buttons:
            configured = 0
        spare = any(
            code not in RESERVED_BUTTONS and 1 <= code <= 767 for code in buttons
        )
        sniper_available = bool(configured or spare)

        status = {
            "present": self.dev is not None,
            "activeId": self.active_id,
            "selectedId": str(self.cfg["device"].get("selected") or ""),
            "name": active_name,
            "kind": active_kind,
            "code": active_code,
            "confidence": active_confidence,
            "wireless": active_wireless,
            "connection": active_connection,
            "supportsScroll": self.supports_scroll,
            "supportsStats": self.supports_stats,
            "supportsButtons": self.supports_buttons,
            "hidden": hidden,
            "devices": listed,
            "sniperAvailable": sniper_available,
            "sniperCode": configured,
            "learning": self.learning_until > time.monotonic(),
            "learnCode": self.learn_code,
            "learnError": self.learn_error,
            "battery": self.battery,
            "dpi": self.dpi_info.get("dpi", 0),
            "dpiStages": self.dpi_info.get("stages", []),
            "dpiSource": self.dpi_info.get("source", "none"),
            "dpiWritable": bool(self.dpi_info.get("writable", False)),
            "dpiRange": self.dpi_info.get("range"),
            "dpiDevice": self.dpi_info.get("device", ""),
            "dpiTools": self.dpi_info.get("tools") or self.dpi_manager.tools(),
        }
        text = json.dumps(status, ensure_ascii=False)
        # Compare with the file instead of an in-memory cache: a restarting
        # daemon can overwrite status.json after the new one has written it,
        # and a cached "already written" flag would leave the panel showing
        # "no device" until the next manual restart.
        try:
            with open(STATUS_PATH, "r", encoding="utf-8") as handle:
                if handle.read() == text + "\n":
                    return
        except OSError:
            pass
        try:
            with open(STATUS_PATH, "w", encoding="utf-8") as handle:
                handle.write(text + "\n")
            os.chmod(STATUS_PATH, 0o644)
            os.chown(STATUS_PATH, self.uid, self.gid)
        except OSError as exc:
            log(f"cannot write {STATUS_PATH}: {exc}")

    # -- mode --------------------------------------------------------------

    def activate(self, target: str = "scroll") -> str:
        if target not in ("scroll", "sniper"):
            target = "scroll"
        if self.mode == target:
            return self.mode
        if self.dev is None:
            return self.mode
        if not self.supports_scroll:
            log(f"scroll mode is not supported for {self.device_kind}")
            return self.mode

        if self.grabbed and self.ui is not None:
            # Already scrolling: switching between scroll and sniper only
            # changes the speed multiplier, so the device is not re-grabbed.
            self.frame = []
            self.converter.reset()
            self._set_mode(target)
            log(f"scroll mode {target}")
            return self.mode

        caps = {
            event_type: codes
            for event_type, codes in self.dev.capabilities(absinfo=False).items()
            if codes and event_type != ecodes.EV_SYN
        }
        # libinput ignores the legacy wheel events while REL_WHEEL_HI_RES is
        # advertised, so the capability has to follow the hi_res setting.
        rel = set(caps.get(ecodes.EV_REL, []))
        rel.update({ecodes.REL_WHEEL, ecodes.REL_HWHEEL})
        if self.cfg["scroll"].get("hi_res", True):
            rel.update({REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES})
        else:
            rel.discard(REL_WHEEL_HI_RES)
            rel.discard(REL_HWHEEL_HI_RES)
        caps[ecodes.EV_REL] = sorted(rel)

        info = self.dev.info
        try:
            self.ui = evdev.UInput(
                caps,
                name=VIRTUAL_NAME,
                vendor=info.vendor,
                product=info.product,
                version=info.version,
                bustype=info.bustype,
                phys=f"{APP}/virtual",
            )
        except OSError as exc:
            log(f"cannot create the virtual pointer: {exc}")
            self.ui = None
            return self.mode

        try:
            self.dev.grab()
        except OSError as exc:
            log(f"cannot grab {self.dev.path}: {exc}")
            self.ui.close()
            self.ui = None
            return self.mode

        self.grabbed = True
        self.frame = []
        self.converter.reset()
        self.drain()
        self.last_activity = time.monotonic()
        self.activated_at = self.last_activity
        self._set_mode(target)
        log(f"scroll mode {target}")
        return self.mode

    def _set_mode(self, mode: str) -> None:
        self.mode = mode
        self.converter.speed = self._speed()
        self.write_state()

    def _speed(self) -> float:
        if self.mode != "sniper":
            return 1.0
        return max(0.0, float(self.cfg["scroll"].get("sniper_multiplier", 0.20) or 0.20))

    def _ungrab(self) -> None:
        if not self.grabbed or self.dev is None:
            self.grabbed = False
            return
        try:
            self.dev.ungrab()
        except OSError as exc:
            if exc.errno not in (errno.ENODEV, errno.EIO):
                log(f"ungrab failed: {exc}")
        self.grabbed = False

    def deactivate(self) -> str:
        self.press = None
        self.button_hold = None
        if self.mode == "pointer":
            return self.mode
        self.mode = "pointer"
        self.converter.speed = 1.0
        if self.ui is not None:
            try:
                self.ui.close()
            except OSError:
                pass
            self.ui = None
        self._ungrab()
        self.converter.reset()
        self.frame = []
        self.write_state()
        log("pointer mode")
        return self.mode

    def toggle(self) -> str:
        # A click that left scroll mode also lands on the bar widget; ignore the
        # widget's toggle right after it so the click cannot re-enter scroll.
        if time.monotonic() - self.last_click_exit < 0.35:
            return self.mode
        if self.mode == "pointer":
            return self.activate("scroll")
        return self.deactivate()

    def toggle_sniper(self) -> str:
        if self.mode == "sniper":
            return self.activate("scroll")
        if self.mode == "scroll":
            return self.activate("sniper")
        return self.mode

    # -- tap / hold bindings ------------------------------------------------
    #
    # A tap toggles the mode and keeps it. Holding the same keys past
    # hold_threshold_ms engages the mode only for as long as the key is held.

    def _apply_action(self, action: str) -> str:
        if action == "sniper":
            return self.toggle_sniper()
        return self.toggle()

    def _restore(self, mode: str) -> str:
        if mode == "pointer":
            return self.deactivate()
        if mode in ("scroll", "sniper"):
            return self.activate(mode)
        return self.mode

    def hold_press(self, action: str) -> str:
        self.press = {
            "action": action,
            "previous": self.mode,
            "at": time.monotonic(),
            "fired": False,
        }
        return self.mode

    def hold_release(self, action: str) -> str:
        press, self.press = self.press, None
        if not press or press["action"] != action:
            return self.mode
        if press["fired"]:
            return self._restore(press["previous"])
        return self._apply_action(action)

    def _fire_hold(self, now: float) -> None:
        if not self.press or self.press["fired"]:
            return
        threshold = float(self.cfg.get("hold_threshold_ms") or 300) / 1000.0
        if now - self.press["at"] < threshold:
            return

        self.press["fired"] = True
        action = self.press["action"]
        if action == "sniper":
            if self.press["previous"] in ("scroll", "sniper"):
                self.activate("sniper")
        else:
            self.activate("scroll")

    # -- config ------------------------------------------------------------

    def reload_config(self) -> None:
        try:
            self.cfg = load_config(self.config_path)
        except FileNotFoundError:
            log("config disappeared; keeping the previous one")
            return
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            log(f"config reload failed ({exc}); keeping the previous one")
            return
        self.converter.configure(self.cfg)
        self.converter.speed = self._speed()
        self.dpi_manager.reload_config(self.cfg)
        self.last_dpi_at = 0.0
        self.dpi_force = True
        self.battery_thread.wake()
        log("config reloaded")

    # -- device events -----------------------------------------------------

    def drain(self) -> None:
        """Discard events queued before the grab, without ever blocking."""
        if self.dev is None:
            return
        while select.select([self.dev.fd], [], [], 0)[0]:
            try:
                list(self.dev.read())
            except (BlockingIOError, OSError):
                return

    def read_device(self) -> None:
        if self.dev is None:
            return
        try:
            events = list(self.dev.read())
        except BlockingIOError:
            return
        except OSError as exc:
            if exc.errno in (errno.ENODEV, errno.EIO, errno.EBADF):
                raise DeviceLost() from exc
            if exc.errno == errno.EAGAIN:
                return
            raise

        for event in events:
            if event.type == ecodes.EV_SYN:
                if event.code == ecodes.SYN_REPORT:
                    frame, self.frame = self.frame, []
                    self.check_learn(frame)
                    self.handle_frame(frame)
                elif event.code == ecodes.SYN_DROPPED:
                    self.frame = []
                    self.converter.reset()
                continue
            self.frame.append(event)

    def handle_frame(self, frame: list) -> None:
        # HID++ often sleeps with the mouse. Retry when the device is clearly
        # awake, but only for a Logitech receiver, and never more than once
        # every few seconds.
        if (
            not self.identity_ok
            and self.dev is not None
            and self.logitech_receiver()
            and time.monotonic() - self.last_identity_probe > 4.0
        ):
            self.probe_device_name(self.dev.name)
        self.record_raw_stats(frame)
        if self.mode not in ("scroll", "sniper") or self.ui is None:
            return

        dx = 0
        dy = 0
        passthrough = []
        click = False
        sniper_button = self.sniper_button_code()

        for event in frame:
            # A mouse button held down acts as a temporary sniper trigger: press
            # slows the scroll down, release restores the previous mode. The
            # button is swallowed so it cannot trigger "back" in an app.
            if sniper_button and event.type == ecodes.EV_KEY and event.code == sniper_button:
                if event.value == 1 and self.button_hold is None:
                    self.button_hold = self.mode
                    if self.mode == "scroll":
                        self._set_mode("sniper")
                        log("sniper button held")
                elif event.value == 0 and self.button_hold is not None:
                    previous = self.button_hold
                    self.button_hold = None
                    if self.mode != "pointer":
                        self._set_mode(previous)
                        log(f"sniper button released, back to {previous}")
                continue
            if event.type == ecodes.EV_REL and event.code in (ecodes.REL_X, ecodes.REL_Y):
                if event.code == ecodes.REL_X:
                    dx += event.value
                else:
                    dy += event.value
                continue
            if (
                event.type == ecodes.EV_KEY
                and ecodes.BTN_MOUSE <= event.code <= ecodes.BTN_TASK
                and event.value == 1
            ):
                click = True
            passthrough.append(event)

        now = time.monotonic()
        try:
            for event in passthrough:
                self.ui.write(event.type, event.code, event.value)
            for event_type, code, value in self.converter.events(dx, dy, now):
                self.ui.write(event_type, code, value)
            self.ui.syn()
        except OSError as exc:
            raise DeviceLost() from exc

        if dx or dy:
            self.last_activity = now

        if click and self.cfg.get("exit_on_click"):
            self.last_click_exit = now
            self.deactivate()

    def load_stats(self) -> dict:
        try:
            with open(self.stats_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            data = {}
        if not isinstance(data, dict):
            data = {}

        # v4 keeps trackball stats global and mouse stats per device. Older
        # files had one global mouse section; it is kept as `mouse` and claimed
        # by the first mouse that becomes active after the upgrade.
        legacy = data if "counts" in data and "trackball" not in data else {}
        trackball = data.get("trackball") if isinstance(data.get("trackball"), dict) else legacy
        mouse = data.get("mouse") if isinstance(data.get("mouse"), dict) else {}
        mice = data.get("mice") if isinstance(data.get("mice"), dict) else {}
        stats = {
            "version": 4,
            "started": str(data.get("started") or ""),
            "updated": str(data.get("updated") or ""),
            "trackball": default_trackball_stats(),
            "mouse": default_mouse_stats(),
            "mice": {},
            "mouse_migrated": bool(data.get("mouse_migrated", False)),
            "mouse_device": str(data.get("mouse_device") or ""),
        }
        for key, value in stats["trackball"].items():
            if key in trackball:
                stats["trackball"][key] = trackball[key]
        for key, value in stats["mouse"].items():
            if key in mouse:
                stats["mouse"][key] = mouse[key]

        if not isinstance(stats["trackball"].get("days"), dict):
            stats["trackball"]["days"] = {}
        if not isinstance(stats["mouse"].get("days"), dict):
            stats["mouse"]["days"] = {}

        for device_id, entry in mice.items():
            if not isinstance(entry, dict) or not device_id:
                continue
            clean = default_mouse_stats()
            for key, value in clean.items():
                if key in entry:
                    clean[key] = entry[key]
            if not isinstance(clean.get("days"), dict):
                clean["days"] = {}
            stats["mice"][str(device_id)] = clean

        # Older statistics kept only notches per day. Rebuild counts from the
        # overall ratio so day distances stay correct after the upgrade.
        total_notches = float(stats["trackball"].get("notches") or 0.0)
        ratio = (float(stats["trackball"].get("counts") or 0.0) / total_notches
                 if total_notches > 0 else 85.0)
        for day in stats["trackball"]["days"].values():
            if isinstance(day, dict) and not day.get("counts"):
                day["counts"] = float(day.get("notches") or 0.0) * ratio
        return stats

    def save_stats(self) -> None:
        self.stats["updated"] = datetime.now().astimezone().isoformat(timespec="seconds")
        try:
            os.makedirs(os.path.dirname(self.stats_path), mode=0o755, exist_ok=True)
            tmp = self.stats_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as handle:
                json.dump(self.stats, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
            os.replace(tmp, self.stats_path)
            os.chmod(self.stats_path, 0o644)
            self.stats_dirty = False
            self.last_stats_save = time.monotonic()
        except OSError as exc:
            log(f"cannot write {self.stats_path}: {exc}")

    @staticmethod
    def mouse_stats_have_data(stats: dict) -> bool:
        if not isinstance(stats, dict):
            return False
        for key in ("counts", "distance_m", "wheel", "active_ms",
                    "up", "down", "left", "right", "max_speed", "dpi"):
            try:
                if float(stats.get(key) or 0.0) > 0:
                    return True
            except (TypeError, ValueError):
                continue
        try:
            if int(stats.get("clicks") or 0) > 0:
                return True
        except (TypeError, ValueError):
            pass
        return bool(stats.get("days"))

    def claim_legacy_mouse(self, device_id: str, entry: dict) -> bool:
        """Move the pre-v4 global mouse stats to the first active mouse once."""
        if self.stats.get("mouse_migrated"):
            return False
        owner = str(self.stats.get("mouse_device") or "")
        if owner and owner != device_id:
            return False
        legacy = self.stats.get("mouse")
        if not self.mouse_stats_have_data(legacy):
            self.stats["mouse_device"] = device_id
            return False
        for key, value in legacy.items():
            if key == "days":
                entry["days"] = json.loads(json.dumps(value))
            else:
                entry[key] = value
        self.stats["mouse_migrated"] = True
        self.stats["mouse_device"] = device_id
        log(f"legacy mouse stats moved to {device_id}")
        return True

    def mouse_stats(self) -> dict:
        if not self.active_id:
            return default_mouse_stats()
        mice = self.stats.setdefault("mice", {})
        entry = mice.get(self.active_id)
        if isinstance(entry, dict):
            return entry
        entry = default_mouse_stats()
        mice[self.active_id] = entry
        self.claim_legacy_mouse(self.active_id, entry)
        return entry

    def ensure_mouse_device(self) -> bool:
        """Create the per-device section as soon as a mouse becomes active."""
        if self.device_kind != "mouse" or not self.active_id:
            return False
        mice = self.stats.setdefault("mice", {})
        if isinstance(mice.get(self.active_id), dict):
            return False
        self.mouse_stats()
        return True

    @staticmethod
    def counts_to_meters(counts: float, dpi_value: int) -> float:
        if dpi_value <= 0:
            return 0.0
        return float(counts) / float(dpi_value) * 0.0254

    def migrate_mouse_distance(self, stats: dict, dpi_value: int) -> None:
        """Fill distance_m from raw counts once, when the DPI first becomes known."""
        stats["distance_m"] = self.counts_to_meters(
            float(stats.get("counts") or 0.0), dpi_value
        )
        for day in (stats.get("days") or {}).values():
            if isinstance(day, dict):
                day["distance_m"] = self.counts_to_meters(
                    float(day.get("counts") or 0.0), dpi_value
                )
        stats["distance_migrated"] = True
        stats["dpi"] = dpi_value
        log(f"mouse distance migrated at {dpi_value} DPI")

    def record_raw_stats(self, frame: list) -> None:
        """Count physical pointer movement in every mode, without grabbing."""
        if self.device_kind not in ("trackball", "mouse"):
            return
        dx = dy = 0.0
        wheel_lo = 0.0
        wheel_hi = 0.0
        clicks = 0
        for event in frame:
            if event.type == ecodes.EV_REL:
                if event.code == ecodes.REL_X:
                    dx += event.value
                elif event.code == ecodes.REL_Y:
                    dy += event.value
                elif event.code == ecodes.REL_WHEEL:
                    wheel_lo += abs(event.value)
                elif event.code == REL_WHEEL_HI_RES:
                    wheel_hi += abs(event.value) / 120.0
            elif (
                event.type == ecodes.EV_KEY
                and ecodes.BTN_MOUSE <= event.code <= ecodes.BTN_TASK
                and event.value == 1
            ):
                clicks += 1
        wheel = wheel_hi if wheel_hi else wheel_lo
        if not (dx or dy or wheel or clicks):
            return

        now = time.monotonic()
        dt = now - self.last_stats_at if self.last_stats_at else 0.01
        self.last_stats_at = now
        dt = max(0.001, min(1.0, dt))
        now_dt = datetime.now().astimezone()
        date = now_dt.date().isoformat()
        moved = bool(dx or dy)

        if self.device_kind == "mouse":
            stats = self.mouse_stats()
            self.stats["mouse_device"] = self.active_id
            dpi_value = self.current_dpi()
            if dpi_value > 0 and not stats.get("distance_migrated"):
                self.migrate_mouse_distance(stats, dpi_value)
            distance = math.hypot(dx, dy)
            meters = self.counts_to_meters(distance, dpi_value)
            stats["counts"] = float(stats.get("counts") or 0.0) + distance
            if dpi_value > 0:
                stats["dpi"] = dpi_value
                stats["distance_m"] = float(stats.get("distance_m") or 0.0) + meters
            stats["wheel"] = float(stats.get("wheel") or 0.0) + wheel
            stats["clicks"] = int(stats.get("clicks") or 0) + clicks
            stats["up"] = float(stats.get("up") or 0.0) + max(0.0, -dy)
            stats["down"] = float(stats.get("down") or 0.0) + max(0.0, dy)
            stats["left"] = float(stats.get("left") or 0.0) + max(0.0, -dx)
            stats["right"] = float(stats.get("right") or 0.0) + max(0.0, dx)
            if moved:
                stats["max_speed"] = max(
                    float(stats.get("max_speed") or 0.0), distance / dt
                )
            duration = min(dt, 0.5) if moved else 0.05
            stats["active_ms"] = float(stats.get("active_ms") or 0.0) + duration * 1000.0
            days = stats["days"]
            day = days.get(date)
            if not isinstance(day, dict):
                day = {"counts": 0.0, "distance_m": 0.0,
                       "wheel": 0.0, "clicks": 0, "ms": 0.0}
                days[date] = day
            day["counts"] = float(day.get("counts") or 0.0) + distance
            if dpi_value > 0:
                day["distance_m"] = float(day.get("distance_m") or 0.0) + meters
            day["wheel"] = float(day.get("wheel") or 0.0) + wheel
            day["clicks"] = int(day.get("clicks") or 0) + clicks
            day["ms"] = float(day.get("ms") or 0.0) + duration * 1000.0
        else:
            stats = self.stats["trackball"]
            raw = math.hypot(dx, dy)
            notches = raw / max(1.0, self.converter.counts_per_notch)
            stats["counts"] = float(stats.get("counts") or 0.0) + raw
            stats["notches"] = float(stats.get("notches") or 0.0) + notches
            stats["up"] = float(stats.get("up") or 0.0) + max(0.0, -dy)
            stats["down"] = float(stats.get("down") or 0.0) + max(0.0, dy)
            stats["left"] = float(stats.get("left") or 0.0) + max(0.0, -dx)
            stats["right"] = float(stats.get("right") or 0.0) + max(0.0, dx)
            if moved:
                stats["max_peak_counts"] = max(
                    float(stats.get("max_peak_counts") or 0.0), raw / dt
                )
                stats["max_peak_notches"] = max(
                    float(stats.get("max_peak_notches") or 0.0), notches / dt
                )
            duration = min(dt, 0.5) if moved else 0.05
            stats["scroll_ms"] = float(stats.get("scroll_ms") or 0.0) + duration * 1000.0
            days = stats["days"]
            day = days.get(date)
            if not isinstance(day, dict):
                day = {"counts": 0.0, "notches": 0.0, "flicks": 0, "ms": 0.0}
                days[date] = day
            day["counts"] = float(day.get("counts") or 0.0) + raw
            day["notches"] = float(day.get("notches") or 0.0) + notches
            day["ms"] = float(day.get("ms") or 0.0) + duration * 1000.0

        if not self.stats.get("started"):
            self.stats["started"] = now_dt.isoformat()
        self.stats_dirty = True

    def update_stats(self) -> None:
        """Record one completed scroll gesture (trackball only)."""
        if self.device_kind != "trackball":
            return
        conv = self.converter
        now = datetime.now().astimezone()
        date = now.date().isoformat()
        stats = self.stats["trackball"]
        duration = max(0.0, (conv.last_motion - conv.gesture_first) * 1000.0)
        stats["flicks"] = int(stats.get("flicks") or 0) + 1
        stats["max_flick_ms"] = max(
            float(stats.get("max_flick_ms") or 0.0), duration
        )
        if conv.peak_triggered:
            stats["coasted"] = int(stats.get("coasted") or 0) + 1
            coast = conv.release_notches / max(0.1, conv.inertia_decay)
            stats["max_coast_notches"] = max(
                float(stats.get("max_coast_notches") or 0.0), coast
            )
        days = stats["days"]
        day = days.get(date)
        if not isinstance(day, dict):
            day = {"counts": 0.0, "notches": 0.0, "flicks": 0, "ms": 0.0}
            days[date] = day
        day["flicks"] = int(day.get("flicks") or 0) + 1
        if not self.stats.get("started"):
            self.stats["started"] = now.isoformat()
        self.save_stats()

    def flush_inertia(self) -> None:
        """Emit the coasting events after a flick, on a timer of its own."""
        if self.ui is None or self.mode not in ("scroll", "sniper"):
            return
        events = self.converter.inertia_events(time.monotonic())
        if self.converter.report_pending:
            self.converter.report_pending = False
            self.update_stats()
        if not events:
            return
        try:
            for event_type, code, value in events:
                self.ui.write(event_type, code, value)
            self.ui.syn()
        except OSError as exc:
            raise DeviceLost() from exc

    # -- sniper button -----------------------------------------------------

    def sniper_button_code(self) -> int:
        """The configured trigger, ignoring reserved navigation buttons."""
        code = int(self.cfg.get("sniper_button") or 0)
        if not code or code in RESERVED_BUTTONS:
            return 0
        return code

    def start_learn(self) -> str:
        if self.dev is None:
            return "error: no pointing device"
        self.deactivate()
        self.learning_until = time.monotonic() + 10.0
        self.learn_code = 0
        self.learn_error = ""
        log("learn: press a spare mouse button")
        self.refresh_status(force=True)
        return "press a spare mouse button"

    def stop_learn(self, error: str = "") -> None:
        changed = self.learning_until > 0.0 or self.learn_error != error
        self.learning_until = 0.0
        self.learn_error = error
        self.learn_error_until = time.monotonic() + 8.0 if error else 0.0
        if changed:
            log(f"learn stopped ({error or 'ok'})")
            self.refresh_status(force=True)

    def check_learn(self, frame: list) -> None:
        if self.learning_until <= 0.0:
            return
        for event in frame:
            if event.type != ecodes.EV_KEY or event.value != 1:
                continue
            code = event.code
            if code in RESERVED_BUTTONS:
                self.stop_learn("reserved")
                return
            if 1 <= code <= 767:
                self.learn_code = code
                log(f"learned sniper button {code}")
                self.stop_learn("")
                return

    # -- control socket ----------------------------------------------------

    def command_allowed(self, peer_uid: int) -> tuple[bool, str]:
        """Only the owner may control the daemon while owning the active seat.

        The socket is already 0600 and owned by the installing user, so the UID
        check is belt and braces. The seat check is what closes the shared
        computer case: a lingering process of the previous account is still the
        same UID, but the seat now belongs to somebody else.
        """
        if peer_uid == 0:
            return True, ""
        if peer_uid != self.uid:
            return False, "denied: only the owning user may control the daemon"
        active = self.seat_guard.active(self.seat)
        if active is None:
            return False, f"denied: cannot verify the active session on {self.seat}"
        session, active_uid = active
        if active_uid != self.uid:
            return False, (
                f"denied: user {active_uid} owns the active session ({session}) "
                f"on {self.seat}, not {self.uid}"
            )
        return True, ""

    def handle_command(self, line: str) -> str:
        parts = line.strip().lower().split()
        verb = parts[0] if parts else ""
        arg = parts[1] if len(parts) > 1 else ""
        log(f"command {verb} {arg}".strip())

        if verb == "press":
            return self.hold_press(arg or "toggle")
        if verb == "release":
            return self.hold_release(arg or "toggle")
        if verb == "toggle":
            return self.toggle()
        if verb == "sniper":
            return self.toggle_sniper()
        if verb in ("on", "scroll"):
            return self.activate("scroll")
        if verb in ("off", "pointer"):
            return self.deactivate()
        if verb == "reload":
            self.reload_config()
            return self.mode
        if verb == "rescan":
            self.rescan_requested = True
            self.dpi_force = True
            return self.mode
        if verb == "learn":
            if arg == "cancel":
                self.stop_learn()
                return "cancelled"
            return self.start_learn()
        if verb in ("status", "ping") or not verb:
            return self.mode
        return f"error: unknown command {verb!r}"

    def accept(self) -> None:
        if self.server is None:
            return
        try:
            conn, _ = self.server.accept()
        except OSError:
            return
        with conn:
            conn.settimeout(0.2)
            try:
                creds = conn.getsockopt(
                    socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")
                )
                _pid, peer_uid, _gid = struct.unpack("3i", creds)
            except OSError:
                peer_uid = -1

            allowed, reason = self.command_allowed(peer_uid)
            if not allowed:
                now = time.monotonic()
                if now - self.last_denied_log >= 30.0:
                    self.last_denied_log = now
                    log(f"control denied for uid {peer_uid}: {reason}")
                try:
                    conn.sendall((reason + "\n").encode())
                except OSError:
                    pass
                return

            data = b""
            try:
                while b"\n" not in data and len(data) < 512:
                    chunk = conn.recv(512)
                    if not chunk:
                        break
                    data += chunk
            except (socket.timeout, OSError):
                pass
            command = data.decode("utf-8", "replace").strip()
            verb = command.split()[0] if command.split() else ""
            if verb in ("toggle", "sniper", "press", "release", "on", "off", "scroll", "pointer", "rescan", ""):
                self.reload_config()
            try:
                conn.sendall((self.handle_command(command) + "\n").encode())
            except OSError:
                pass

    # -- main loop ---------------------------------------------------------

    def tick(self, now: float) -> None:
        if self.stats_dirty and now - self.last_stats_save >= 30.0:
            self.save_stats()
        if self.battery_dirty:
            self.battery_dirty = False
            self.last_scan = 0.0
        if self.dpi_dirty:
            self.dpi_dirty = False
            self.last_scan = 0.0
            self.last_dpi_at = 0.0
        if self.learn_error and self.learn_error_until and now > self.learn_error_until:
            self.learn_error = ""
            self.learn_error_until = 0.0
            log("learn warning expired")
        self.refresh_status()
        if self.learning_until and now > self.learning_until:
            self.stop_learn("timeout")
        if self.mode != "pointer" and now - self.last_seat_check >= 1.0:
            self.last_seat_check = now
            active = self.seat_guard.active(self.seat)
            if active is None:
                log(f"cannot verify the active session on {self.seat}; releasing the grab")
                self.deactivate()
                return
            session, active_uid = active
            if active_uid != self.uid:
                log(
                    f"active session on {self.seat} is now uid {active_uid} "
                    f"(session {session}); releasing the grab"
                )
                self.deactivate()
                return

        if self.reload_pending:
            self.reload_pending = False
            self.reload_config()
        if self.toggle_pending:
            self.toggle_pending = False
            self.toggle()

        self._fire_hold(now)

        if self.press and self.press["fired"]:
            hold_max = float(self.cfg.get("hold_max_seconds") or 0)
            if hold_max > 0 and now - self.press["at"] >= hold_max:
                log("hold safety timeout")
                previous = self.press["previous"]
                self.press = None
                self._restore(previous)
                return

        if self.mode not in ("scroll", "sniper"):
            return

        auto_exit = float(self.cfg.get("auto_exit_seconds") or 0)
        if auto_exit > 0 and now - self.last_activity >= auto_exit:
            log("auto-exit after inactivity")
            self.deactivate()

    def run(self) -> None:
        self.prepare_runtime()
        self.battery_thread.start()
        self.dpi_monitor.start()
        signal.signal(signal.SIGTERM, self._stop)
        signal.signal(signal.SIGINT, self._stop)
        signal.signal(signal.SIGHUP, self._reload)
        signal.signal(signal.SIGUSR1, self._toggle_signal)

        announced_missing = False
        try:
            while self.running:
                if self.dev is None:
                    excluded = [str(item).lower() for item in self.cfg["device"].get("exclude") or []]
                    found, _hidden = scan_pointers(excluded)
                    target = choose_device(self.cfg, found)
                    if target is None:
                        if not announced_missing:
                            log("pointing device not found, waiting for it")
                            announced_missing = True
                        self.refresh_status(force=True)
                        self.wait_for_device(2.0)
                        continue
                    opened = open_pointer(target["path"])
                    if opened is None:
                        self.wait_for_device(1.0)
                        continue
                    self.dev = opened
                    announced_missing = False
                    self.active_id = target["id"]
                    self.identity_generation += 1
                    self.seat = target.get("seat") or "seat0"
                    self.refresh_status(force=True)
                    if self.logitech_receiver():
                        cached = self.load_identity()
                    else:
                        cached = None
                    if cached:
                        self.device_name = friendly_device_name(cached["name"])
                        self.hidpp_type = cached.get("type")
                        self.identity_ok = False
                        self.write_device(self.device_name)
                        self.probe_device_name(self.dev.name)
                    elif self.logitech_receiver():
                        if self.device_name:
                            self.write_device(self.device_name)
                        else:
                            self.write_device(self.dev.name)
                            self.probe_device_name(self.dev.name)
                    else:
                        self.device_name = getattr(self.dev, "name", "") or self.active_id
                        self.hidpp_type = None
                        self.identity_ok = False
                        self.write_device(self.device_name)
                    self.sel.register(self.dev.fd, selectors.EVENT_READ, "device")
                try:
                    self.serve()
                except DeviceLost:
                    log("device disconnected")
                    self.deactivate()
                finally:
                    self.close_device()
        finally:
            self.shutdown()

    def wait_for_device(self, timeout: float) -> None:
        """Keep answering the control socket while no device is present."""
        deadline = time.monotonic() + timeout
        self.refresh_status()
        while self.running:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return
            for key, _ in self.sel.select(timeout=remaining):
                if key.data == "server":
                    self.accept()
            self.refresh_status()

    def serve(self) -> None:
        while self.running:
            pending = self.press is not None and not self.press["fired"]
            now = time.monotonic()
            if self.converter.inertia_active:
                # 125 Hz output is visibly smoother than the old 60 Hz ticks.
                timeout = 0.008
            elif self.mode in ("scroll", "sniper"):
                gap = now - self.converter.last_motion
                guard = self.converter.guard_seconds()
                if gap < guard:
                    # Wake exactly when the guard expires, not a whole tick
                    # later; this is the difference between a visible pause and
                    # a continuous hand-off.
                    timeout = max(0.002, min(0.012, guard - gap))
                elif gap < 0.15:
                    timeout = 0.008
                else:
                    timeout = 0.05 if pending else 0.2
            else:
                timeout = 0.05 if pending else 0.2
            for key, _ in self.sel.select(timeout=timeout):
                if key.data == "device":
                    self.read_device()
                elif key.data == "server":
                    self.accept()
            if self.rescan_requested:
                self.rescan_requested = False
                return
            self.flush_inertia()
            self.tick(time.monotonic())

    def close_device(self) -> None:
        if self.dev is None:
            return
        try:
            self.sel.unregister(self.dev.fd)
        except (KeyError, ValueError, OSError):
            pass
        self.deactivate()
        try:
            self.dev.close()
        except OSError:
            pass
        self.dev = None
        self.active_id = ""
        self.device_name = ""
        self.hidpp_type = None
        self.identity_ok = False
        self.identity_generation += 1
        self.last_identity_probe = 0.0
        self.write_device("")
        self.refresh_status(force=True)

    def shutdown(self) -> None:
        self.running = False
        self.battery_thread.stop()
        self.dpi_monitor.stop()
        if self.stats_dirty:
            self.save_stats()
        self.deactivate()
        if self.server is not None:
            try:
                self.sel.unregister(self.server)
            except (KeyError, ValueError):
                pass
            self.server.close()
            self.server = None
        try:
            if os.path.exists(SOCKET_PATH):
                os.unlink(SOCKET_PATH)
        except OSError:
            pass

    # -- signals -----------------------------------------------------------

    def _stop(self, *_args) -> None:
        self.running = False

    def _reload(self, *_args) -> None:
        self.reload_pending = True

    def _toggle_signal(self, *_args) -> None:
        self.toggle_pending = True


# -- diagnostics -----------------------------------------------------------


def diagnose() -> int:
    print(f"{APP}: input devices")
    found = False
    for path in event_paths():
        try:
            device = evdev.InputDevice(path)
        except OSError as exc:
            print(f"  {path}: cannot open ({exc})")
            continue
        with device:
            caps = device.capabilities(absinfo=False)
            rel = caps.get(ecodes.EV_REL, [])
            keys = caps.get(ecodes.EV_KEY, [])
            mouse_buttons = [ecodes.KEY[code] for code in keys if 0x110 <= code <= 0x11F]
            mark = ""
            if ecodes.REL_X in rel and ecodes.REL_Y in rel and ecodes.BTN_LEFT in keys:
                mark = "  <= pointer candidate"
                found = True
            print(f"  {path}: {device.name!r}{mark}")
            print(f"      REL: {', '.join(ecodes.REL[c] for c in rel) or '-'}")
            print(f"      buttons: {', '.join(mouse_buttons) or '-'}")
    if not found:
        print("  no device with REL_X/REL_Y + BTN_LEFT found")
    return 0


def selftest() -> int:
    def make(overrides: dict | None = None) -> ScrollConverter:
        scroll = {
            "counts_per_notch": 100.0,
            "sensitivity": 1.0,
            "invert_vertical": False,
            "invert_horizontal": False,
            "axis_lock": True,
            "axis_window_seconds": 0.25,
            "hi_res": True,
        }
        scroll.update(overrides or {})
        converter = ScrollConverter()
        converter.configure({"scroll": scroll})
        return converter

    now = 1.0
    hi = 0
    clicks = 0
    converter = make()
    for _ in range(10):  # 10 frames x 10 counts = 100 counts = one notch
        for _event_type, code, value in converter.events(0, 10, now):
            if code == REL_WHEEL_HI_RES:
                hi += value
            elif code == ecodes.REL_WHEEL:
                clicks += value
        now += 0.01
    print(f"vertical: hi_res={hi} clicks={clicks}")
    assert (hi, clicks) == (-HI_RES_PER_NOTCH, -1), (hi, clicks)

    # Nothing is lost to rounding over many small frames.
    converter = make()
    total = 0
    now += 1.0
    for _ in range(1000):  # 1000 x 3 counts = 30 notches
        for _event_type, _code, value in converter.events(0, 3, now):
            if _code == REL_WHEEL_HI_RES:
                total += value
        now += 0.004
    print(f"many frames: {total} hi-res units (expect {-30 * HI_RES_PER_NOTCH})")
    assert total == -30 * HI_RES_PER_NOTCH, total

    # Inverted vertical direction.
    converter = make({"invert_vertical": True})
    now += 1.0
    inverted = sum(
        value
        for _event_type, _code, value in converter.events(0, 100, now)
        if _code == REL_WHEEL_HI_RES
    )
    print(f"inverted: {inverted} hi-res units")
    assert inverted == HI_RES_PER_NOTCH, inverted

    # High-resolution disabled still produces discrete wheel clicks.
    converter = make({"hi_res": False})
    now += 1.0
    clicks = sum(
        value
        for _event_type, code, value in converter.events(0, 250, now)
        if code == ecodes.REL_WHEEL
    )
    print(f"legacy wheel: {clicks} clicks")
    assert clicks == -2, clicks

    # Axis lock keeps a diagonal gesture on its dominant axis.
    converter = make()
    now += 1.0
    values = [
        value
        for _ in range(5)
        for _event_type, _code, value in converter.events(20, 2, now)
    ]
    print(f"axis lock: {values} (horizontal only)")
    assert values and all(value > 0 for value in values), values

    # Sniper mode is the same converter at a lower speed multiplier.
    converter = make()
    converter.speed = 0.5
    now += 1.0
    total = 0
    for _ in range(10):  # 10 x 10 counts = 100 counts, half speed = 0.5 notch
        for _event_type, _code, value in converter.events(0, 10, now):
            if _code == REL_WHEEL_HI_RES:
                total += value
        now += 0.01
    print(f"sniper: {total} hi-res units (expect {-HI_RES_PER_NOTCH // 2})")
    assert total == -HI_RES_PER_NOTCH // 2, total

    # Horizontal gestures produce horizontal wheel events.
    converter = make()
    now += 1.0
    horizontal = [
        (code, value)
        for _event_type, code, value in converter.events(100, 0, now)
    ]
    print(f"horizontal: {horizontal}")
    assert (REL_HWHEEL_HI_RES, 120) in horizontal, horizontal
    assert (ecodes.REL_HWHEEL, 1) in horizontal, horizontal
    assert not [1 for (code, _v) in horizontal if code == REL_WHEEL_HI_RES]

    # A vertical gesture followed by a clean horizontal one switches axis.
    converter = make()
    now += 1.0
    for _ in range(3):
        converter.events(0, 20, now)
        now += 0.01
    switched = [
        (code, value)
        for _event_type, code, value in converter.events(30, 0, now)
        if code in (REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES)
    ]
    print(f"axis switch: {switched}")
    assert switched and switched[-1][0] == REL_HWHEEL_HI_RES, switched

    # Inertia coasts only after a fast flick, and it decays to a stop.
    converter = make({"inertia": True})
    now += 1.0
    for _ in range(6):  # 6 x 60 counts in ~50 ms: a flick
        converter.events(0, 60, now)
        now += 0.008
    coast = 0
    ticks = 0
    for _ in range(300):
        now += 0.016
        events = converter.inertia_events(now)
        if events:
            ticks += 1
        for _event_type, code, value in events:
            if code == REL_WHEEL_HI_RES:
                coast += value
    print(f"inertia: {coast} hi-res units over {ticks} ticking frames")
    assert coast < 0, coast
    assert not converter.inertia_active, "inertia never stopped"
    assert ticks * 0.016 < 3.0, "inertia overstayed"

    # Slow, deliberate movement must not start coasting.
    converter = make({"inertia": True})
    now += 10.0
    for _ in range(5):
        converter.events(0, 4, now)
        now += 0.05
    coast = 0
    for _ in range(60):
        now += 0.016
        coast += len(converter.inertia_events(now))
    print(f"inertia from slow motion: {coast} events (expect 0)")
    assert coast == 0, coast

    # A moderate flick still coasts; a slower drag of the same shape does not.
    converter = make({"inertia": True})
    now += 10.0
    for _ in range(6):  # 12 counts / 8 ms = 1500 counts/s
        converter.events(0, 12, now)
        now += 0.008
    coast = 0
    for _ in range(100):
        now += 0.016
        for _event_type, code, value in converter.inertia_events(now):
            if code == REL_WHEEL_HI_RES:
                coast += value
    print(f"inertia moderate: {coast} hi-res units")
    assert coast < 0, coast

    converter = make({"inertia": True})
    now += 10.0
    for _ in range(6):  # 8 counts / 8 ms = 1000 counts/s
        converter.events(0, 8, now)
        now += 0.008
    coast = 0
    for _ in range(100):
        now += 0.016
        for _event_type, code, value in converter.inertia_events(now):
            if code == REL_WHEEL_HI_RES:
                coast += value
    print(f"inertia below threshold: {coast} events (expect 0)")
    assert coast == 0, coast

    # One very short fast frame still triggers: the raw peak is not attenuated
    # by the velocity smoothing.
    converter = make({"inertia": True})
    now += 10.0
    converter.events(0, 20, now)  # 20 counts / 16 ms = 1250 counts/s
    coast = 0
    for _ in range(100):
        now += 0.016
        for _event_type, code, value in converter.inertia_events(now):
            if code == REL_WHEEL_HI_RES:
                coast += value
    print(f"inertia short flick: {coast} hi-res units, peak {converter.last_peak_notches:.1f}/s")
    assert coast < 0, coast
    assert converter.last_peak_notches > 12, converter.last_peak_notches
    assert converter.gesture_frames == 1, converter.gesture_frames
    assert converter.gesture_peak_counts > 1200, converter.gesture_peak_counts
    assert converter.gesture_raw_counts == 20, converter.gesture_raw_counts

    print("selftest: ok")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog=APP, description=__doc__)
    parser.add_argument("--config", help="path to scrollmode.json")
    parser.add_argument("--uid", type=int, default=0, help="owner of the control socket")
    parser.add_argument("--gid", type=int, default=0, help="group of the control socket")
    parser.add_argument("--diagnose", action="store_true", help="list input devices and exit")
    parser.add_argument("--selftest", action="store_true", help="check the scroll math and exit")
    args = parser.parse_args(argv)

    if args.diagnose:
        return diagnose()
    if args.selftest:
        return selftest()

    uid = args.uid or int(os.environ.get("SUDO_UID") or 0)
    gid = args.gid or int(os.environ.get("SUDO_GID") or 0)
    if uid == 0:
        log("warning: running with uid 0, the control socket will be root-only")

    if args.config:
        config_path = args.config
    else:
        try:
            home = pwd.getpwuid(uid).pw_dir
        except KeyError:
            home = os.path.expanduser("~")
        config_path = os.path.join(home, ".config", "omarchy", "scrollmode.json")

    if not os.path.exists(config_path):
        log(f"config not found: {config_path} (using defaults)")

    log(f"starting (config {config_path})")
    daemon = Daemon(config_path, uid, gid)
    try:
        daemon.run()
    except Exception:  # keep the journal useful on unexpected failures
        traceback.print_exc()
        daemon.shutdown()
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
