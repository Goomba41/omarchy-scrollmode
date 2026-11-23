# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.3.0] — 2026-11-23

### Added

- Drawn trackball icon (`TrackballBall.qml`): a shaded sphere with a soft
  specular highlight (base glow, white core, small light spot) and a fine
  texture of scratches and dimples, instead of the three Nerd Font glyphs. Red
  for pointer, blue for scroll, amber for sniper. The sphere fills the bar icon
  slot, and its marks turn around the vertical axis, so they slide across the
  ball and disappear behind it instead of spinning in the picture plane.
- The settings header shows the same ball at 44 px next to the title and the
  device name in two lines. Opening the panel spins it fast for about a second,
  eases down and then keeps turning slowly (one turn per ten seconds) while the
  panel is open. A rounded mode badge sits next to the title: the mode icon and
  label in the mode color, over a dimmed mode-colored background with a
  matching border. `omarchy toggle animations` turns the spin off.
- The "Device" caption in the panel uses the same white body style as the other
  labels; the hidden-device note stays a quiet caption.
- `barWidget.defaultSection` is now `center`. The marketplace's Quattro contract
  only accepts `left`, `center` or `right`, and Omarchy maps `center` to the
  centerEnd slot, so the widget still lands where it did before.
- Sniper on the side mouse button: holding `BTN_SIDE` (configurable, default
  275) while scrolling switches to the sniper speed for as long as it is held;
  releasing restores scroll. The button is swallowed so apps do not see "back".
- Optional inertia: after a fast flick the scroll keeps going and decays to a
  stop. Off by default, and slow movement never triggers it.
- Panel toggles for inertia and for the sniper button.

### Fixed

- The daemon now forces a rescan when device enumeration unexpectedly comes back
  empty while a device is open, instead of leaving the widget on "no pointing
  device" until the service is restarted.

### Changed

- With no pointing device available, or with the service stopped, the ball and
  the header badge turn gray and the badge shows a broken-link icon and
  "No device" / "Нет устройства" instead of a mode.
- Left click on the bar widget opens (or closes) the settings panel; right click
  no longer does anything. The old single/double click mode switching and its
  230 ms delay are gone; modes are switched with `ALT + Z`, `ALT + S` or the
  sniper button.

### Tests

- `tests/test_frame.py` covers the sniper button (press, slower output,
  swallowed event, release).
- `scrollmoded.py --selftest` covers inertia: a fast flick coasts, slow motion
  does not.
- An end-to-end check with a fake uinput pointer verified plain scroll, the
  sniper button and inertia against the running daemon.

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
- One-click setup: when the daemon is missing, the panel offers **Install…** and
  opens a terminal running the bundled installer, so installing the plugin is
  enough and no commands have to be copied.
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

