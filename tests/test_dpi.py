#!/usr/bin/env python3
"""Offline checks for the DPI provider registry. Run with:

    python3 tests/test_dpi.py
"""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "daemon"))

import dpi  # noqa: E402

WINGS_ID = "2ea8:2203|Wings Tech Gaming Mouse"


def info_text(*resolutions):
    lines = [
        "0123456789abcdef - Wings Tech Gaming Mouse",
        "             Model: wings-gaming",
        "       Device Type: Mouse",
        "Number of Profiles: 1",
        "Profile 0: (active)",
        "  Resolutions:",
    ]
    lines.extend(resolutions)
    return "\n".join(lines) + "\n"


def main() -> int:
    # Vendor table and report parsing.
    table = dpi.vendor_table_for(WINGS_ID, "Wings Tech Gaming Mouse")
    assert table is not None
    assert table.stages == dpi.WINGS_STAGES, table.stages
    sample = bytes([0x04, 0xA2, 0x02, 3, 0x00, 54, 54, 0, 0])
    assert dpi.parse_vendor_report(sample, table) == 3
    assert dpi.parse_vendor_report(sample[1:], table) == 3
    assert dpi.parse_vendor_report(bytes([0x04, 0xA2, 0x02, 6, 0, 210, 210]), table) == 6
    assert dpi.parse_vendor_report(bytes([0x04, 0xA2, 0x02, 0, 0, 9, 9]), table) == 0
    assert dpi.parse_vendor_report(bytes([0x04, 0x00, 0x02, 3, 0, 54, 54]), table) is None
    print("vendor report: ok")

    # Stage ranges.
    assert dpi.stage_range([900, 1800, 2700]) == {"min": 900, "max": 2700, "step": 900}
    assert dpi.stage_range([]) is None
    assert dpi.stage_range([800, 800]) == {"min": 800, "max": 800, "step": 0}
    print("stage range: ok")

    # ratbagctl parsing and matching.
    listing = (
        "0123456789abcdef:    Logitech G502 HERO Gaming Mouse\n"
        "fedcba9876543210:    Wings Tech Gaming Mouse\n"
    )
    devices = dpi.parse_ratbagctl_list(listing)
    assert devices[0]["name"].startswith("Logitech G502"), devices
    assert dpi.match_ratbag_device(devices, ["Wings Tech Gaming Mouse"])["id"] == "fedcba9876543210"
    assert dpi.match_ratbag_device(devices, ["Logitech USB Receiver Mouse"],
                                   "fedcba")["name"].startswith("Wings")
    assert dpi.match_ratbag_device(devices, ["Something else"]) is None

    parsed = dpi.parse_ratbagctl_info(info_text(
        "    0: 800dpi (active) (default)",
        "    1: 1600dpi",
        "    2: 3200dpi (disabled)",
    ))
    assert parsed is not None
    assert parsed["stages"] == [800, 1600], parsed
    assert parsed["active"] == 0, parsed
    assert parsed["range"] == {"min": 800, "max": 1600, "step": 800}, parsed
    assert parsed["profile"] == 0

    parsed = dpi.parse_ratbagctl_info(info_text(
        "    0: 1200dpi",
        "    1: 2400dpi (active)",
    ))
    assert parsed["active"] == 1 and parsed["stages"] == [1200, 2400], parsed
    assert dpi.parse_ratbagctl_info("nothing here") is None
    assert dpi.parse_ratbagctl_dpi_output("1600dpi\n") == 1600
    assert dpi.parse_ratbagctl_dpi_output("1600x1600dpi") == 1600
    assert dpi.parse_ratbagctl_dpi_output("nonsense") == 0
    # A stopped ratbagd must not be woken through D-Bus just to read DPI.
    assert dpi.read_ratbag(["Wings Tech Gaming Mouse"], service_active=lambda: False) == (None, False)
    print("ratbag parsing: ok")

    # Provider priority: ratbag, then vendor, then manual, then none.
    directory = tempfile.mkdtemp(prefix="scrollmode-dpi-")

    def fake_reader(names, override=""):
        return {
            "id": "ratbag-device-1",
            "stages": [800, 1600],
            "active": 1,
            "range": {"min": 800, "max": 1600, "step": 800},
            "device": "Fake Mouse",
        }, True

    def fake_writer(info, value):
        return True, value

    manager = dpi.DpiManager(
        os.path.join(directory, "dpi.json"),
        {"dpi": {"manual": {WINGS_ID: 1200}}},
        ratbag_reader=fake_reader,
        ratbag_writer=fake_writer,
        which=lambda name: "/usr/bin/" + name,
    )
    info = manager.snapshot(WINGS_ID, "Wings Tech Gaming Mouse", "", "mouse", force=True)
    assert info["source"] == "ratbag" and info["dpi"] == 1600, info
    assert info["stages"][1]["active"] is True, info
    assert info["writable"] is True, info
    ok, actual, info = manager.apply_dpi(WINGS_ID, "Wings Tech Gaming Mouse", "", 800)
    assert ok and actual == "800", (ok, actual)
    assert info["dpi"] == 800 and info["stages"][0]["active"] is True, info

    def failing_writer(info, value):
        return False, "device is busy"

    manager = dpi.DpiManager(
        os.path.join(directory, "dpi.json"),
        {},
        ratbag_reader=fake_reader,
        ratbag_writer=failing_writer,
        which=lambda name: "/usr/bin/" + name,
    )
    manager.snapshot(WINGS_ID, "Wings Tech Gaming Mouse", "", "mouse", force=True)
    ok, message, info = manager.apply_dpi(WINGS_ID, "Wings Tech Gaming Mouse", "", 1600)
    assert not ok and message == "device is busy" and info is None, (ok, message, info)

    manager = dpi.DpiManager(
        os.path.join(directory, "dpi.json"),
        {"dpi": {"manual": {WINGS_ID: 1200}}},
        ratbag_reader=lambda names, override="": (None, False),
        which=lambda name: "",
    )
    info = manager.snapshot(WINGS_ID, "Wings Tech Gaming Mouse", "", "mouse", force=True)
    assert info["source"] == "vendor" and info["dpi"] == 0, info
    assert [stage["dpi"] for stage in info["stages"]] == list(dpi.WINGS_STAGES), info
    assert manager.note_vendor_stage(WINGS_ID, 3) == 5400
    info = manager.snapshot(WINGS_ID, "Wings Tech Gaming Mouse", "", "mouse", force=True)
    assert info["dpi"] == 5400 and info["stages"][3]["active"] is True, info
    with open(os.path.join(directory, "dpi.json"), "r", encoding="utf-8") as handle:
        saved = json.load(handle)
    assert saved["devices"][WINGS_ID]["stage"] == 3, saved

    unknown_id = "1234:5678|Mystery Mouse"
    manager = dpi.DpiManager(
        os.path.join(directory, "dpi.json"),
        {"dpi": {"manual": {unknown_id: 1200}}},
        ratbag_reader=lambda names, override="": (None, False),
        which=lambda name: "",
    )
    info = manager.snapshot(unknown_id, "Mystery Mouse", "", "mouse", force=True)
    assert info["source"] == "manual" and info["dpi"] == 1200, info
    assert info["stages"] == [{"index": 0, "dpi": 1200, "active": True}], info
    assert info["writable"] is False, info

    info = manager.snapshot("9999:0001|Plain Mouse", "Plain Mouse", "", "mouse", force=True)
    assert info["source"] == "none" and info["stages"] == [], info
    info = manager.snapshot("046d:c548|Trackball", "ERGO M575S", "", "trackball", force=True)
    assert info["source"] == "none" and info["stages"] == [], info
    print("provider priority: ok")

    print("dpi: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
