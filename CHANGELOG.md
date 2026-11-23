# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.2.0] — 2026-11-23

### Added

- Device picker in the settings panel: every pointing device is listed with a
  stable id, and **Use this device** makes the daemon grab it. The selection is
  stored as `device.selected` and survives reboots.
- "Device not applied" state: settings stay hidden until the picked device is
  actually active, so nothing is configured for a device that was not grabbed.
- "No pointing device found" state with a Retry button; the bar icon is dimmed
  whenever nothing is grabbed.
- Pretty device names from udev (`ID_VENDOR` + `ID_MODEL`) and from HID++ 2.0
  for Logitech receivers.
- Keyboard filter: pointer nodes that are obviously keyboards (`keyboard`,
  `keypad`, `kbd`) are hidden, and the count is shown next to the **Device**
  label.
- Icon-only **Refresh** button next to the device selector, with a tooltip.
- Green **✓ Done** confirmation on every action: buttons flash it, sliders and
  toggles show `· ✓ Done` after their title, auto-exit chips replace their label
  with `✓ Done`, and "Reset to defaults" turns yellow while it waits for the
  second click.
- CLI: `devices`, `use <id>`, `rescan`.
- Runtime `status.json` with the device list, active id and hidden count.
- Russian localization.

### Fixed

- Bar icons stopped switching after a daemon restart: the unit now keeps the
  runtime directory (`RuntimeDirectoryPreserve=yes`) and the widget re-reads its
  files every 1.5 s in case an inode is replaced.
- The settings panel could open with zero height before its content was laid
  out; it now opens with a usable minimum and grows.
- Binding loops in the percentage sliders.
- Letter hotkeys were unreliable on remapped layouts (Workman); bindings now
  use physical keycodes.
- Holding a `Super`-based hotkey scrolled workspaces (Omarchy binds
  `SUPER + wheel`), so the hotkeys moved to `Alt`.
- The sniper key triggered Compose; sniper is now `Alt + S`, a plain chord.

### Changed

- Speed and sniper sliders are percentages where **higher means faster**
  (100 % = the calibrated speed), and they snap to real steps.
- The device name is shown inline after the panel title.
- The device dropdown is full width and the Refresh button sits beside "Use
  this device", so every control has the same height.
- The repository root is the plugin (`manifest.json` at the top) so
  `omarchy plugin add <git-url>` installs it; the daemon lives in `daemon/`.

## [1.1.0] — 2026-11-21

### Added

- Sniper mode: a slower scroll speed toggled without re-grabbing the device.
- Right-click settings panel with speed, sniper speed, invert, axis lock,
  hi-res, leave-on-click, hold threshold, auto-exit, rescan and reset.
- Tap/hold bindings: tap toggles, holding engages a momentary mode.
- Any mouse button leaves scroll mode on click (`exit_on_click`).
- `set` and `reset` CLI commands with validation and atomic writes.
- `en` and `ru` catalogs, following the Omarchy language.

## [1.0.0] — 2026-11-20

### Added

- `scrollmoded` daemon: grabs the pointing device only in scroll mode and
  replays it through uinput as high-resolution wheel events.
- `omarchy-scrollmode` CLI (toggle/on/off/status/reload/hotkey).
- Bar widget with pointer/scroll icons and click-to-toggle.
- Hyprland hotkey block generation (physical keycodes).
- systemd unit, installer, uninstaller and self-tests.

