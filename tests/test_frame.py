#!/usr/bin/env python3
"""Offline checks for the frame -> uinput path. Run with:

    python3 tests/test_frame.py

Needs python-evdev but no root: the uinput device is faked.
"""

import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "daemon"))

import evdev  # noqa: E402
from evdev import ecodes  # noqa: E402

import scrollmoded  # noqa: E402

CONFIG = os.path.join(os.path.dirname(__file__), "..", "config.default.json")


class FakeUI:
    def __init__(self):
        self.events = []
        self.synced = 0
        self.closed = False

    def write(self, event_type, code, value):
        self.events.append((event_type, code, value))

    def syn(self):
        self.synced += 1

    def close(self):
        self.closed = True


def event(event_type, code, value):
    return evdev.InputEvent(0, 0, event_type, code, value)


class FakeDev:
    fd = 0

    def grab(self):
        pass

    def ungrab(self):
        pass

    def capabilities(self, absinfo=False):
        return {}

    def close(self):
        pass


class FakeSeatGuard:
    """Pretend the test uid owns the active seat; tests override when needed."""

    def __init__(self, value=("test", 1000)):
        self.value = value

    def active(self, seat):
        return self.value


def fresh(mode="scroll"):
    daemon = scrollmoded.Daemon(CONFIG, 1000, 1000)
    daemon.cfg["exit_on_click"] = False
    daemon.mode = mode
    daemon.converter.speed = 1.0
    daemon.dev = FakeDev()
    daemon.ui = FakeUI()
    daemon.grabbed = True  # so activate() only switches the mode
    daemon.write_state = lambda: None
    # CI runners are headless (no active seat); never let the real guard run.
    daemon.seat_guard = FakeSeatGuard()
    return daemon


def main():
    # One notch of ball movement plus a left click in the same frame.
    daemon = fresh()
    daemon.handle_frame(
        [
            event(ecodes.EV_REL, ecodes.REL_Y, 85),
            event(ecodes.EV_KEY, ecodes.BTN_LEFT, 1),
        ]
    )
    ui = daemon.ui
    assert (ecodes.EV_KEY, ecodes.BTN_LEFT, 1) in ui.events, ui.events
    hi = [v for (t, c, v) in ui.events if c == scrollmoded.REL_WHEEL_HI_RES]
    clicks = [v for (t, c, v) in ui.events if c == ecodes.REL_WHEEL]
    print("emitted:", ui.events)
    assert hi == [-120], hi
    assert clicks == [-1], clicks
    assert ui.synced == 1, ui.synced
    assert not [1 for (t, c, _v) in ui.events if c in (ecodes.REL_X, ecodes.REL_Y)]

    # Sniper mode runs the same converter at the configured multiplier.
    daemon = fresh("sniper")
    daemon.cfg["scroll"]["sniper_multiplier"] = 0.5
    daemon.converter.speed = 0.5
    daemon.handle_frame([event(ecodes.EV_REL, ecodes.REL_Y, 85)])
    hi = [v for (t, c, v) in daemon.ui.events if c == scrollmoded.REL_WHEEL_HI_RES]
    print("sniper:", daemon.ui.events)
    assert hi == [-60], hi

    # Any mouse button leaves scroll mode when exit_on_click is on, and the
    # click is still forwarded before the grab is dropped. BTN_SIDE is a
    # momentary sniper trigger when enabled, so it is checked separately below.
    for code in (ecodes.BTN_LEFT, ecodes.BTN_RIGHT, ecodes.BTN_MIDDLE, ecodes.BTN_EXTRA):
        daemon = fresh()
        daemon.cfg["exit_on_click"] = True
        ui = daemon.ui
        daemon.handle_frame([event(ecodes.EV_KEY, code, 1)])
        assert daemon.mode == "pointer", (code, daemon.mode)
        assert (ecodes.EV_KEY, code, 1) in ui.events, ui.events
    print("exit on any button: ok")

    # The side button is a momentary sniper trigger: pressing slows the scroll
    # down, releasing restores scroll, and the button itself is swallowed.
    daemon = fresh("scroll")
    daemon.cfg["sniper_button"] = 279
    daemon.cfg["scroll"]["sniper_multiplier"] = 0.5
    ui = daemon.ui
    daemon.handle_frame([event(ecodes.EV_KEY, ecodes.BTN_TASK, 1)])
    assert daemon.mode == "sniper", daemon.mode
    assert not ui.events, ui.events
    daemon.handle_frame([event(ecodes.EV_REL, ecodes.REL_Y, 85)])
    hi = [v for (t, c, v) in ui.events if c == scrollmoded.REL_WHEEL_HI_RES]
    print("sniper button:", daemon.mode, hi)
    assert hi == [-60], hi
    daemon.handle_frame([event(ecodes.EV_KEY, ecodes.BTN_TASK, 0)])
    assert daemon.mode == "scroll", daemon.mode
    assert not [1 for (t, c, _v) in ui.events if t == ecodes.EV_KEY], ui.events
    print("sniper button: ok")

    # Back/Forward stay navigation buttons even if an old config names them.
    daemon = fresh("scroll")
    daemon.cfg["sniper_button"] = 275
    ui = daemon.ui
    daemon.handle_frame([event(ecodes.EV_KEY, ecodes.BTN_SIDE, 1)])
    assert daemon.mode == "scroll", daemon.mode
    assert (ecodes.EV_KEY, ecodes.BTN_SIDE, 1) in ui.events, ui.events
    print("reserved sniper button: ok")

    # Disabled trigger: the side button behaves like any other click.
    daemon = fresh("scroll")
    daemon.cfg["sniper_button"] = 0
    daemon.cfg["exit_on_click"] = True
    daemon.handle_frame([event(ecodes.EV_KEY, ecodes.BTN_SIDE, 1)])
    assert daemon.mode == "pointer", daemon.mode

    # Releasing a button does not exit.
    daemon = fresh()
    daemon.cfg["exit_on_click"] = True
    daemon.handle_frame([event(ecodes.EV_KEY, ecodes.BTN_LEFT, 0)])
    assert daemon.mode == "scroll", daemon.mode

    # Pointer mode forwards nothing and never writes to a missing uinput.
    daemon = fresh("pointer")
    daemon.ui = None
    daemon.handle_frame([event(ecodes.EV_REL, ecodes.REL_Y, 100)])

    # A quick tap toggles and keeps the mode.
    daemon = fresh("pointer")
    daemon.hold_press("toggle")
    assert daemon.mode == "pointer"
    daemon.hold_release("toggle")
    assert daemon.mode == "scroll", daemon.mode

    # Holding past the threshold engages the mode, release restores it.
    daemon = fresh("pointer")
    daemon.hold_press("toggle")
    daemon.press["at"] -= 1.0
    daemon.tick(time.monotonic())
    assert daemon.mode == "scroll", daemon.mode
    daemon.hold_release("toggle")
    assert daemon.mode == "pointer", daemon.mode

    # Sniper: tap toggles, hold is momentary, pointer is a no-op.
    daemon = fresh("scroll")
    daemon.hold_press("sniper")
    daemon.hold_release("sniper")
    assert daemon.mode == "sniper", daemon.mode

    daemon = fresh("scroll")
    daemon.hold_press("sniper")
    daemon.press["at"] -= 1.0
    daemon.tick(time.monotonic())
    assert daemon.mode == "sniper", daemon.mode
    daemon.hold_release("sniper")
    assert daemon.mode == "scroll", daemon.mode

    daemon = fresh("pointer")
    daemon.hold_press("sniper")
    daemon.hold_release("sniper")
    assert daemon.mode == "pointer", daemon.mode

    # A click that leaves scroll mode cancels a pending hold.
    daemon = fresh("scroll")
    daemon.cfg["exit_on_click"] = True
    daemon.hold_press("toggle")
    daemon.press["at"] -= 1.0
    daemon.tick(time.monotonic())
    assert daemon.mode == "scroll", daemon.mode
    daemon.handle_frame([event(ecodes.EV_KEY, ecodes.BTN_RIGHT, 1)])
    assert daemon.mode == "pointer", daemon.mode
    daemon.hold_release("toggle")
    assert daemon.mode == "pointer", daemon.mode

    print("tap/hold: ok")

    # -- shared computer: only the active owner may control -----------------
    daemon = fresh("scroll")
    daemon.seat_guard = FakeSeatGuard(("2", 2000))
    daemon.tick(time.monotonic())
    assert daemon.mode == "pointer", daemon.mode

    daemon = fresh("scroll")
    daemon.seat_guard = FakeSeatGuard(("1", 1000))
    daemon.last_seat_check = 0.0
    daemon.tick(time.monotonic())
    assert daemon.mode == "scroll", daemon.mode

    daemon = fresh("scroll")
    daemon.seat_guard = FakeSeatGuard(None)
    daemon.last_seat_check = 0.0
    daemon.tick(time.monotonic())
    assert daemon.mode == "pointer", daemon.mode
    print("seat switch releases the grab: ok")

    daemon = fresh("pointer")
    daemon.seat_guard = FakeSeatGuard(("1", 1000))
    assert daemon.command_allowed(1000) == (True, "")
    assert daemon.command_allowed(0) == (True, "")
    ok, reason = daemon.command_allowed(2000)
    assert not ok and "owning user" in reason, reason
    daemon.seat_guard = FakeSeatGuard(("2", 2000))
    ok, reason = daemon.command_allowed(1000)
    assert not ok and "active session" in reason, reason
    daemon.seat_guard = FakeSeatGuard(None)
    ok, reason = daemon.command_allowed(1000)
    assert not ok and "cannot verify" in reason, reason
    print("seat guard decisions: ok")

    # A tiny movement during a coast cancels it and must not start a second
    # coast from the same flick.
    converter = scrollmoded.ScrollConverter()
    converter.configure({"scroll": {
        "counts_per_notch": 100.0, "sensitivity": 1.0, "invert_vertical": False,
        "invert_horizontal": False, "axis_lock": True, "axis_window_seconds": 0.25,
        "hi_res": True, "inertia": True, "inertia_trigger": 12.0,
        "inertia_strength": 100.0}})
    now = 100.0
    for _ in range(6):
        converter.events(0, 60, now)
        now += 0.008
    for _ in range(4):
        now += 0.016
        converter.inertia_events(now)
    assert converter.inertia_active
    converter.events(0, 1, now)
    assert not converter.inertia_active
    restarted = 0
    for _ in range(100):
        now += 0.016
        restarted += len(converter.inertia_events(now))
    print("inertia restart after cancel:", restarted, "events (expect 0)")
    assert restarted == 0, restarted

    # Aggregate statistics written for the Stats tab.
    import json
    import tempfile
    directory = tempfile.mkdtemp(prefix="scrollmode-stats-")
    daemon = scrollmoded.Daemon(CONFIG, 1000, 1000)
    daemon.stats_path = os.path.join(directory, "stats.json")
    daemon.stats = daemon.load_stats()
    converter = daemon.converter
    converter.counts_per_notch = 85.0
    converter.inertia_decay = 5.0
    converter.gesture_raw_counts = 340.0
    converter.gesture_first = 100.0
    converter.last_motion = 100.1
    converter.gesture_down = 340.0
    converter.gesture_frames = 3
    converter.last_peak_notches = 20.0
    converter.peak_speed = 1700.0
    converter.peak_triggered = True
    converter.release_notches = 8.0
    daemon.update_stats()
    with open(daemon.stats_path) as handle:
        stats = json.load(handle)
    print("flick stats:", {k: stats[k] for k in ("counts", "notches", "flicks", "max_peak_notches")})
    assert stats["counts"] == 340.0, stats
    assert stats["notches"] == 4.0, stats
    assert stats["flicks"] == 1 and stats["coasted"] == 1, stats
    assert stats["max_peak_notches"] == 20.0, stats
    assert stats["max_coast_notches"] == 1.6, stats
    assert sum(day["flicks"] for day in stats["days"].values()) == 1, stats
    day = next(iter(stats["days"].values()))
    assert day["counts"] == 340.0 and day["notches"] == 4.0, day

    # Older statistics only stored notches per day; loading backfills counts.
    legacy_path = os.path.join(directory, "legacy.json")
    with open(legacy_path, "w") as handle:
        json.dump({
            "counts": 1700.0,
            "notches": 20.0,
            "days": {"2026-01-01": {"notches": 4.0, "flicks": 1, "ms": 10.0}},
        }, handle)
    daemon.stats_path = legacy_path
    legacy = daemon.load_stats()
    assert legacy["version"] == 2, legacy
    assert legacy["days"]["2026-01-01"]["counts"] == 340.0, legacy

    print("frame path: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
