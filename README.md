# Omarchy Trackball Scroll

Turn any trackball (or mouse) into a scroll wheel, with a slower "sniper"
mode, for [Omarchy](https://omarchy.org/). Press a key and the ball scrolls
instead of moving the cursor; a bar widget shows the mode and opens the
settings on a left click.

<p align="center">
  <img src="preview.png" alt="Trackball Scroll Mode" width="800">
</p>

## Features

- **Pointer / scroll / sniper** modes, toggled from the keyboard or the bar.
- **Tap or hold**: tap a hotkey to toggle and keep the mode, hold it for a
  momentary mode that ends when you let go.
- **Real scroll wheel events**: high-resolution `REL_WHEEL_HI_RES` plus classic
  `REL_WHEEL` clicks, so smooth scrolling works in modern apps and discrete
  clicks still work everywhere else. Horizontal scrolling is emitted too.
- **No latency in pointer mode**: the device is not grabbed at all until scroll
  mode is on. If the daemon dies, the kernel drops the grab.
- **Any pointing device**: the panel lists every relative pointer it finds,
  labels it with a type code (`[TB]` trackball, `[MS]` mouse, `[TP]` trackpad,
  `[TA]` tablet, `[UN]` unknown) and you pick the one to grab. Selection
  survives reboots.
- **Pretty device names**: udev vendor/model names, HID++ names for Logitech
  receivers.
- **Drawn trackball**: a shaded sphere with a soft specular highlight and a
  fine texture of scratches and dimples, red for pointer, blue for scroll,
  amber for sniper. It fills the bar icon slot; the settings header shows the
  same ball at 44 px, turning around its vertical axis (fast for a second, then
  a slow idle turn) with a rounded mode badge next to the title.
- **Real settings UI**: speed, sniper speed, invert, axis lock, smooth
  scrolling, exit-on-click, inertia with trigger and coast controls, a learned
  sniper button, hold threshold, auto-exit, reset, open config.
- **Stats tab**: trackball stats are collected in pointer mode too: ball
  distance, turns, top speed, active time, days and the bus-to-Sun ladder.
  Flicks and coast remain scroll-only. A mouse gets its own stats: movement,
  wheel notches/pages, clicks, active time and days.
- **Battery**: for wireless mice that report a battery, a small charge ring on
  the bar ball, a battery badge in the panel header, and charge settings in the
  Device tab. Reads Logitech HID++ battery data, keeps the last known value
  while the mouse sleeps, and never writes to the device.
- **English and Russian**, following the Omarchy language setting.

## Requirements

- Omarchy (Hyprland + the Quickshell bar).
- Arch `python-evdev`: `sudo pacman -S --needed python-evdev`.
- Root once at install time: the daemon reads `/dev/input/event*` and creates a
  `uinput` device.

## Install

The only dependency beyond Omarchy is `python-evdev`. Install it once; the
installer checks for it and never installs packages itself:

```sh
sudo pacman -S --needed python-evdev
```

The repository **is** the plugin: `manifest.json` sits at the root, so Omarchy
can install and update it like any other plugin.

### As an Omarchy plugin (recommended)

```sh
omarchy plugin add https://github.com/Goomba41/omarchy-scrollmode.git --enable
```

The widget appears in the bar. Left-click it once: while the daemon is missing,
the panel shows a setup view with an **Install…** button.

<p align="center">
  <img src="docs/menu-setup.png" alt="Install background service" width="340">
</p>

**Install…** opens a terminal with the bundled installer and asks for your
password there. The daemon and its systemd unit are installed, the service
starts, and within a second the widget switches to the normal settings view.
No commands to copy.

Why a terminal? Reading `/dev/input` and creating a `uinput` device needs root,
and a shell plugin runs as your user. The installer is the only privileged
step; the terminal shows exactly what runs. (`pkexec` is deliberately not used:
it needs a running polkit agent, which is not guaranteed on every desktop.)

The service lives outside the plugin, so after `omarchy plugin update` re-run
the installer once (from the plugin directory) if the daemon changed:

```sh
~/.config/omarchy/plugins/anton.scrollmode/install.sh
```

The canonical repository is on GitHub; a read-only mirror lives at
[GitLab](https://gitlab.com/anton-borodavkin/omarchy-scrollmode).

### From a checkout

The installer is also the manual path, and it installs both halves at once.

```sh
git clone https://github.com/Goomba41/omarchy-scrollmode.git ~/Projects/omarchy-scrollmode
cd ~/Projects/omarchy-scrollmode
./install.sh
```

The script elevates once (via `sudo` by default, or `SCROLLMODE_ELEVATE=pkexec
./install.sh`) and installs:

| Path | What |
| --- | --- |
| `/usr/local/lib/omarchy-scrollmode/scrollmoded.py` | the daemon |
| `/usr/local/bin/omarchy-scrollmode` | the CLI |
| `/etc/systemd/system/omarchy-scrollmode.service` | systemd unit |
| `~/.config/omarchy/scrollmode.json` | config (created once, never overwritten) |
| `~/.config/omarchy/plugins/anton.scrollmode/` | the plugin (manifest, widget, i18n) |
| `~/.config/hypr/bindings.lua` | one managed hotkey block |

### What the installer changes

- Creates `~/.config/omarchy/scrollmode.json` **only when it does not exist**.
- Adds one delimited block to `~/.config/hypr/bindings.lua`; the rest of the
  file is left untouched, and the pre-install copy is kept as
  `bindings.lua.before-scrollmode`.
- Adds the widget to the bar with `omarchy bar put` — the same path any plugin
  uses; disabling or removing the plugin takes it out again.
- Installs the daemon, the CLI and a systemd unit under `/usr/local` and
  `/etc` (with sudo, from the visible installer).
- Does not install packages: if `python-evdev` is missing it stops and prints
  the pacman command above.

Nothing else is touched. Uninstall reverses all of it and keeps your settings
file.

## Usage

### Hotkeys

| Action | Keys |
| --- | --- |
| pointer ↔ scroll | `ALT + Z` |
| scroll ↔ sniper | `ALT + S` |

Both work two ways: a **tap** toggles the mode and keeps it, holding longer than
`hold_threshold_ms` (default 300 ms) engages the mode only while the keys are
held. Bindings use physical keycodes, so they work on remapped layouts
(Workman, Dvorak, …).

### Bar widget

| Action | Result |
| --- | --- |
| left click | open or close the settings panel |
| right click | nothing (kept free) |
| gray ball | no pointing device is grabbed, or the service is stopped |

The ball itself shows the mode: **red** pointer, **blue** scroll, **amber**
sniper. Pointer/scroll is toggled with `ALT + Z`, sniper with `ALT + S`; the
bar no longer changes the mode. The ball in the panel header turns around its
vertical axis, so its texture slides across the sphere and vanishes behind it.

<p align="center">
  <img src="docs/icons.png" alt="pointer, scroll and sniper balls" width="120">
</p>

### Settings panel

<p align="center">
  <img src="docs/menu.png" alt="Settings panel" width="340">
</p>

When no pointing device is available (or the service is stopped), the ball and
the header badge turn gray and the badge reads **No device** with a broken-link
icon.

The settings are grouped into **Scroll**, **Feel**, **Device** and **Stats**
tabs; the device picker stays above them. A circled question mark next to a setting opens
a short tooltip explaining what it changes. Every control writes
`~/.config/omarchy/scrollmode.json` through `omarchy-scrollmode set` and the
daemon reloads immediately. Sliders snap to
their step (5 % for speeds, 50 ms for the hold threshold).

Every action confirms itself: the button, slider title, toggle or auto-exit chip
flashes a green **✓ Done** for a moment, and "Reset to defaults" turns yellow
("Click again to reset") while it waits for the second click.

### Sniper on a mouse button

While scrolling, holding a spare mouse button slows the scroll down to the
sniper speed; releasing it returns to normal scrolling. It is off by default.
Press **Choose sniper button…** (or run `omarchy-scrollmode learn`) and then the
button you want; the CLI captures its code. Left, right, middle, Back and
Forward are reserved because they already have a standard meaning, so the
option is hidden for devices that only have those buttons. The button shows the
current choice and flashes **✓ Done** after a successful capture. The chosen
button is swallowed while scrolling, so it cannot trigger a navigation action.

### Inertia

With inertia on, a fast flick keeps scrolling for a moment and then decays to a
stop, instead of stopping the instant the ball does. It is off by default and
only starts on real flicks, so slow, precise movement is never affected.

The panel exposes two controls when it is on:

- **Trigger** — how fast the ball must move before a flick coasts, in notches
  per second (default 12). Lower is easier to trigger.
- **Coast** — how far it keeps going, in percent (default 100). Higher is
  longer.

**Trigger** gates on the fastest moment of the flick, but the coast starts from
the speed the ball had at release, so the hand-off does not jump back to the
peak after the app has already animated a slower tail.

### Battery

The bar ball carries a small charge ring in its bottom-right corner. The ring
is green while the charge is comfortable, amber near the warning threshold,
red at or below it, and blue while charging. The panel header shows the same
state as a battery badge next to the mode badge, with the percentage and a
battery or charging glyph.

The **Device** tab repeats the charge, its state and a thin gauge, then offers:

- **Show in bar** — draw the ring on the bar ball.
- **Low battery at** — the percentage at which the badge and ring turn urgent.
- **Check every** — how often the daemon asks the mouse for its battery
  (1, 5, 15 or 30 minutes). Plugging in updates it immediately.

Battery is read over Logitech HID++ `0x1004` (unified battery). The battery
badge, bar ring and Device section appear only when the active device is
wireless and reports a battery; wired mice and mice without a battery hide
them entirely. When the mouse is asleep or the receiver is busy the last known
value is kept and marked "last known" rather than disappearing. The daemon
never writes battery settings to the device.

### Stats

<p align="center">
  <img src="docs/stats.png" alt="Stats tab" width="340">
</p>

The **Stats** tab for a trackball opens with three headline numbers: record
speed, distance the ball rolled and ball turns. Ball movement is counted in
pointer mode as well as scroll/sniper, so the distance and turns grow whenever
the ball is used; flick and coast records stay scroll-only. Below them are
totals, flick records, days, and a distance ladder that climbs from bus lengths
and football fields through track laps and marathons to a lap around the Earth,
a trip to the Moon and an orbit around the Sun. Counts use enough decimal
places to move on a normal day of rolling. The big targets show progress toward
the current lap, trip or orbit, with the number already completed in brackets.

For a mouse the same tab shows **movement, wheel notches/pages, clicks, active
time and days**. Mouse movement is collected in pointer mode from the physical
device without grabbing it. The Earth/Moon/Sun ladder is shown when the mouse
reports a DPI; otherwise movement stays in raw counts and the tab says so.

It collects automatically and is stored in
`/var/lib/omarchy-scrollmode/stats.json` (plain readable JSON, no cursor
coordinates).

### Choosing the device

The **Device** dropdown lists every pointing device (a device with
`REL_X`/`REL_Y` and buttons). Pick one and press **Use this device**: the choice
is stored as `device.selected` and the daemon re-grabs it.

- Names come from udev (`ID_VENDOR` + `ID_MODEL`), from HID++ for a Logitech
  receiver, and fall back to the kernel name. Devices that are obviously
  keyboards (`keyboard`, `keypad`, `kbd` in the name/model) are skipped and
  counted in the "hidden" note next to the **Device** label.
- While `device.selected` is empty the daemon guesses: `device.match` (default
  `logitech`), then the first device that looks like a trackball, then the
  first pointer. This is only the initial guess.
- Moving the dropdown does **not** apply the device: settings stay hidden
  behind "Device not applied" until the daemon actually grabs it.
- If the chosen device disappears the panel says so and keeps the picker; it
  never silently switches to another mouse.

<p align="center">
  <img src="docs/menu-pending.png" alt="Device not applied" width="340">
</p>

### Device types and applicable settings

The daemon classifies every pointer when it connects and keeps the result in
`status.json` as `kind`, `code`, `confidence`, `sources`, `wireless` and the
`supportsScroll` / `supportsStats` / `supportsButtons` flags. The panel uses
those flags to show only the applicable parts:

- **Trackball** — Scroll, Feel, Device and Stats; battery when wireless.
- **Mouse** — Device and Stats only. The Device tab shows the picker, battery
  when wireless, and a note that more mouse settings are coming. Scroll/Feel,
  sniper and hotkeys are hidden.
- **Trackpad / tablet / unknown** — Device only for now; unknown pointers keep
  the scroll tabs so an unclassified trackball still works.

- **HID++ `0x0005` device type** is authoritative where the device speaks it:
  `3` mouse, `4` trackpad, `5` trackball. HID++ is Logitech's protocol, so this
  is the high-confidence path for Logitech receivers and Bluetooth mice.
- **udev/hwdb tags** such as `ID_INPUT_TRACKBALL`, `ID_INPUT_TOUCHPAD` and
  `ID_INPUT_TABLET` are the next high-confidence source. Coverage is not
  universal — the M575S, for example, is not tagged as a trackball here.
- **Name and model hints** (`trackball`, `M575`, `MX Ergo`, `Magic Trackpad`,
  `Wacom`, `mouse`, …) are used when no tag or HID++ type is available. These
  are marked medium or low confidence.
- A relative pointer with no usable signal is **unknown** (`UN`) rather than
  being guessed as a mouse.

HID++ type overrides the fallback only for the matching receiver or device
name, so a second mouse on the same machine cannot inherit the trackball type.
Trackpads and tablets are classified for the device list; grabbing them for
scroll mode needs absolute-axis handling later.

The daemon also refuses to enter scroll/sniper mode for a mouse, trackpad or
tablet. Mouse statistics are collected passively in pointer mode, without
grabbing the device.

With no pointing devices at all the panel only shows a notice and a Retry
button, and the bar icon is dimmed:

<p align="center">
  <img src="docs/menu-empty.png" alt="No pointing device found" width="340">
</p>

## Configuration

`~/.config/omarchy/scrollmode.json`

```jsonc
{
  "device": {
    "selected": "",             // device id picked in the panel (empty = auto)
    "match": "logitech",        // initial guess while selected is empty
    "path": "",                 // pin an exact node, e.g. "/dev/input/event4"
    "exclude": ["omarchy-scrollmode"]
  },
  "hotkey": "ALT + Z",          // pointer <-> scroll
  "sniper_hotkey": "ALT + S",   // scroll <-> sniper
  "hold_threshold_ms": 300,     // longer hold = momentary instead of toggle

  "scroll": {
    "counts_per_notch": 85,     // ball counts per wheel notch; bigger = slower
    "sensitivity": 1.0,         // multiplier on top of counts_per_notch
    "sniper_multiplier": 0.20,  // sniper speed as a share of normal (0.20 = 20 %)
    "invert_vertical": false,
    "invert_horizontal": false,
    "axis_lock": true,          // a gesture stays on its dominant axis
    "axis_window_seconds": 0.25,
    "hi_res": true,             // smooth scrolling; false = classic wheel clicks
    "inertia": false,           // coast after a fast flick
    "inertia_trigger": 12,      // notches/s needed to start coasting
    "inertia_strength": 100     // coast length, percent (100 = default)
  },

  "sniper_button": 0,           // spare mouse button code; learn it in the panel
  "exit_on_click": true,        // any mouse button leaves scroll mode
  "auto_exit_seconds": 0,       // 0 = stay until toggled, otherwise idle timeout
  "hold_max_seconds": 60,       // safety cap for a stuck momentary hold

  "battery": {
    "show_bar": true,           // draw the charge ring on the bar ball
    "low_percent": 20,          // badge/ring turn urgent at or below this
    "poll_seconds": 300         // seconds between battery reads (30-3600)
  }
}
```

`counts_per_notch` is the internal calibration. The panel shows it as a
percentage: `100 %` is the calibrated 85 counts/notch, `200 %` is twice as fast
(42–43 counts/notch). Sniping is shown as a percentage of the normal speed.

Apply changes without restarting anything:

```sh
omarchy-scrollmode reload   # re-read the config
omarchy-scrollmode hotkey   # rewrite the Hyprland bindings
```

## CLI

```sh
omarchy-scrollmode toggle        # pointer <-> scroll
omarchy-scrollmode battery       # print the mouse battery
omarchy-scrollmode sniper        # scroll <-> sniper (no-op in pointer)
omarchy-scrollmode on | off      # force scroll or pointer
omarchy-scrollmode status        # print the current mode
omarchy-scrollmode devices       # list pointing devices (active is marked *)
omarchy-scrollmode use <id>      # make a device the active one
omarchy-scrollmode rescan        # re-read the connected devices
omarchy-scrollmode set <path> <value>
omarchy-scrollmode learn         # capture a spare mouse button for sniper
omarchy-scrollmode reset         # restore the defaults
omarchy-scrollmode reload
omarchy-scrollmode hotkey [remove]
omarchy-scrollmode config        # print the config path
```

`set` validates keys and ranges, writes the JSON atomically and reloads the
daemon: `omarchy-scrollmode set scroll.counts_per_notch 60`. `learn` waits for a
spare mouse button, rejects left/right/middle and Back/Forward, and writes
`sniper_button` for you.

## How it works

```
hotkey / bar click
        │
        ▼
omarchy-scrollmode (CLI) ──unix socket──▶ scrollmoded
                                            │ EVIOCGRAB only in scroll mode
                                            │ uinput "virtual pointer"
                                            ▼
                                    Hyprland and apps
                                            │
                     /run/omarchy-scrollmode/{state,status.json}
                                            │
                                            ▼
                              anton.scrollmode bar widget
```

- In pointer mode the device is not grabbed; libinput sees it exactly as
  before.
- Entering scroll mode grabs the event node and creates a `uinput` device that
  replays buttons and turns ball motion into wheel events. The original device
  goes silent while grabbed; releasing the mode closes the virtual device.
- Ball counts are accumulated in high-resolution wheel units (120 per notch),
  so no precision is lost, and discrete clicks are derived from the same
  accumulator.
- The axis lock keeps a gesture on its dominant axis; a clean direction change
  switches immediately, so vertical-then-horizontal scrolling works.
- With inertia on, the daemon keeps the ball's velocity after the last frame and
  emits decaying wheel events until the speed falls below a threshold or a new
  movement arrives.
- The sniper button is handled inside the grabbed stream: it switches the
  converter to the sniper multiplier only while held and is not replayed.
- Device names and the device list come from `/run/udev/data` plus HID++ 2.0
  `DeviceName` (`0x0005`) over the receiver's hidraw interface.
- The panel title follows the active pointer type: **Trackball**, **Mouse**,
  **Trackpad**, **Tablet** or **Pointer** for an unknown device. The device
  picker prefixes each name with the matching two-letter code.

### Shared computers

The control socket belongs to the installing user, and the daemon accepts
commands only while that user owns the active session on the device's seat
(`seat0` on a normal desktop). When another user takes over the seat, a running
scroll mode is released within a second, so a lingering process of the previous
account cannot turn the new user's pointer movement into scrolling. `root` can
still control the daemon directly. This check is built into the daemon and
cannot be disabled from the user config.

## Troubleshooting

**The icon does not change / the panel is stale.** The daemon recreates
`/run/omarchy-scrollmode` on restart; the widget re-reads its files every 1.5 s
and the unit keeps the runtime directory (`RuntimeDirectoryPreserve=yes`). If
needed, restart the shell: `omarchy restart shell`.

**The device is not listed.** `omarchy-scrollmode devices` shows the daemon's
view; `journalctl -u omarchy-scrollmode -f` shows why a node was skipped.
Keyboards (`keyboard`/`keypad`/`kbd` in the name) are hidden on purpose.

**The hotkey does nothing.** Re-apply the bindings (`omarchy-scrollmode hotkey`)
and check `hyprctl configerrors`. Bindings are physical keycodes, so changing
the keyboard layout does not break them.

**Scrolling feels too fast/slow.** Change the speed in the panel or
`scroll.counts_per_notch` (higher = slower); for sniper, `sniper_multiplier`.

**Emergency stop.** `sudo systemctl stop omarchy-scrollmode` — the grab is
released when the process exits.

## Files at runtime

```
/run/omarchy-scrollmode/state        pointer | scroll | sniper
/run/omarchy-scrollmode/status.json  devices, kinds, active id, battery
/run/omarchy-scrollmode/device       display name of the active device
/run/omarchy-scrollmode/control.sock CLI control socket (0600, user-owned)

/var/lib/omarchy-scrollmode/stats.json  cumulative statistics for the Stats tab
```

## Development

```sh
python3 daemon/scrollmoded.py --selftest   # converter math
python3 tests/test_frame.py                # frame -> uinput path, tap/hold, clicks
omarchy plugin validate .                  # manifest + entry points
```

The repository layout:

| Path | What |
| --- | --- |
| `manifest.json`, `ScrollMode.qml`, `i18n/` | the Omarchy plugin, at the root so `omarchy plugin add` works |
| `TrackballBall.qml` | the drawn sphere used in the bar and in the panel header |
| `daemon/scrollmoded.py` | the daemon |
| `daemon/omarchy-scrollmode` | the CLI |
| `config.default.json` | first-run config |
| `install.sh`, `uninstall.sh` | installer/uninstaller |
| `tests/` | offline tests |
| `docs/` | screenshots used by this README |

The GitLab CI job in `.gitlab-ci.yml` runs the Python tests and a syntax check
on the shell scripts. `omarchy plugin validate` needs Omarchy itself, so it is
part of the local checks rather than CI.

## Uninstall

```sh
./uninstall.sh
```

Removes the service, binaries, widget and the managed hotkey block. The config
in `~/.config/omarchy/scrollmode.json` and the statistics in
`/var/lib/omarchy-scrollmode/stats.json` are kept; remove the statistics
directory with `sudo rm -rf /var/lib/omarchy-scrollmode` if you want a clean
slate.

## Limitations

- A Logitech receiver exposes **one** evdev node for all devices paired to it.
  Several Logitech mice on the same receiver therefore appear as a single
  entry, and the daemon grabs them together.
- The keyboard filter is name-based; a keyboard whose descriptor does not
  mention "keyboard" may still show its pointer interface.
- Trackballs have no standard HID flag, so device detection is identity-based
  (the device you picked), not classification.

## Roadmap

- Hotkey editor in the settings panel: capture a combination, validate it and
  write it to the config.
- More translations as the marketplace grows beyond English and Russian.

## License

MIT — see [LICENSE](LICENSE).
