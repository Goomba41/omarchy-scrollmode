# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.10.11] — 2026-11-26

### Changed

- Shortened the cursor tail and enlarged the main pointer body. The notch is
  deeper now, so the tail reads as a distinct short leg instead of a long
  diagonal bar.
- The face colours, uniform bevel and mode-derived palette are unchanged.

## [1.10.10] — 2026-11-26

### Changed

- Rebuilt the cursor from the supplied reference image: the standard pointer
  silhouette with a vertical left edge, a narrow notch, a right wing and a long
  diagonal tail. Corners are rounded.
- The glyph is a front-facing beveled 3D slab: outer silhouette, inset front
  face, full rear face and a uniform clipped bevel. Side and rear walls stay
  opaque.
- Every face derives from the mode colour. The front is lightest, the bevel and
  sides are slightly lighter than the base, and the rear keeps the base colour.
  Pointer, scroll and sniper therefore tint the whole object.
- Removed the upright/symmetric experiments. The reference orientation is used
  directly, without an extra 45° rotation.

## [1.10.8] — 2026-11-26

### Changed

- Returned to the ordinary system-pointer silhouette with smoothed corners:
  tip, right wing, deep notch and offset tail. The forced symmetric pointer is
  gone.
- Faces now use slightly different, lighter flat fills: a lit front, a
  slightly lifted side wall and the base colour at the rear. No gradients.
- Increased the fixed viewing yaw and depth a little, so the volume reads at
  rest while the silhouette stays even.

### Notes

- The cursor is now checked with an offscreen Qt render at many angles and
  sizes before installing. The panel is not opened and the pointer is not
  moved for visual checks.

## [1.10.7] — 2026-11-26

### Changed

- The cursor is now a single flat colour on every face. Gradients, side
  shading and the bright rim are gone, so no plane can look pressed in and no
  edge changes colour while turning.
- The tail is centred under the top point and the vertical rotation axis runs
  through both. The silhouette is now symmetric and the extrusion stays even.
- Face seams are sealed with same-colour strokes over the depth-sorted faces.

## [1.10.6] — 2026-11-26

### Fixed

- Rebuilt the cursor as a true uniform extrusion: the same rounded outline at
  `+depth` and `-depth`, one perspective projection, and no per-face scaling
  or fake offsets. This removes the crooked perspective and uneven silhouette.
- Added an opaque underlay of every face and gradient-shaded side walls, so
  the ends and rear face can no longer read as transparent or show the panel
  through a seam.
- Reduced thickness and the fixed viewing yaw, and lightened the rear/side
  colours, so the body stays solid and even while it turns.

## [1.10.5] — 2026-11-26

### Changed

- Replaced the triangular cursor prism with a full mouse-pointer silhouette:
  tip, right wing, notch and chunky tail, all rounded. The outline is
  extruded into a solid 3D object with opaque side walls, a darker rear face
  and a light beveled rim.
- Kept the existing motion: a slow idle turn, the opening glide, and the fast
  kick with air streaks.

## [1.11.0] — 2026-11-26

### Added

- **DPI writing through libratbag.** When ratbag controls the mouse, the stage
  chips are interactive: `h`/`l` move a preview, `Enter` applies it, and a
  click applies the clicked stage. The daemon runs `ratbagctl ... dpi set`,
  reads the value back and updates the panel. `omarchy-scrollmode dpi apply
  <n>` exposes the same operation from the CLI.
- Transient “Applying…” and write-error messages in the DPI section. The
  active chip stays on the last confirmed DPI if a write fails.
- `dpi` output now reports whether the source is writable or read-only.

### Changed

- The DPI grid is a keyboard focus target only when the source can be written.
  Vendor and manual DPI stay read-only.
- The section no longer offers to install Piper for a working ratbag device;
  **Open Piper** appears only when Piper is already present.

## [1.10.4] — 2026-11-25

### Fixed

- The device dropdown no longer rebuilds its open popup every time
  `status.json` is reloaded. The options list is now updated only when its
  contents change, and updates are deferred until the popup closes, so ghost
  rows no longer appear over the menu.
- Hint tooltips, DPI chip tooltips, the panel cursor frame and the bar tooltip
  are suppressed while the device popup is open, so they cannot paint above
  the menu.

## [1.10.3] — 2026-11-25

### Changed

- The Manual DPI slider now says that it only affects usage statistics and
  does not change the DPI stored on the mouse. The `?` hint repeats the same
  distinction.

## [1.10.2] — 2026-11-25

### Changed

- The DPI source now sits in the section heading as `DPI · vendor` before the
  rule. The separate source row is gone, leaving the stage grid and the
  manual fallback with more room.
- Block headings get a top gap only from the second visible block onward, so
  the first block after the tabs starts flush. Battery and Buttons & Hotkeys
  follow the same rule.

## [1.10.1] — 2026-11-25

### Added

- **Manual DPI** in the Device tab when a mouse does not expose its stages, or
  when a manual value is already set. The slider covers 50–64,000 DPI and has a
  matching **Clear manual DPI** button. Keyboard focus reaches both.
- Mouse statistics are now kept **per device**. Switching from a mouse with DPI
  to a simple one starts a fresh section instead of showing the previous
  mouse's distance or freezing it. The pre-v4 global mouse section is claimed
  once by the first mouse that becomes active after the upgrade.

### Changed

- DPI stages use an even grid of up to five columns, sized from the widest
  possible chip label. Rows grow as needed for mice with many stages.
- Removed the redundant current-DPI line, the stage/range line and the colour
  explanation. The highlighted chip and the source badge carry that
  information, and the section is shorter.

## [1.10.0] — 2026-11-25

### Added

- A **DPI** section in the Device tab for mice. It lists every exposed stage
  as a chip, highlights the current stage, names the provider and shows the
  range. Trackballs keep their ball-distance stats and never show the section.
- A DPI provider registry tried in order: **libratbag/ratbagd** through
  `ratbagctl`, a **vendor HID report** (Wings), a **manual** value, then
  **none**. libratbag and piper stay optional; the panel offers to install or
  open them when the mouse does not expose DPI on its own.
- Wings Tech Gaming Mouse support for the `04 a2 02 <stage> 00 <code> <code>`
  report, with the seven known stages (900–21,000 DPI) and the current stage
  cached in `dpi.json` after the first DPI-button press.
- Deterministic DPI colours from `DpiColor.js`: hue depends only on the DPI
  value (`800` is the same blue on every mouse), with slight lightness changes
  to separate nearby stages.
- `omarchy-scrollmode dpi`, `dpi set <value>` and `dpi clear` for the read view
  and the manual fallback.
- Mouse statistics now store `distance_m` at event time, so changing DPI later
  never rewrites earlier distance. Old counts are migrated once when the first
  DPI becomes known, and the Stats tab still falls back to counts.

### Changed

- Mouse Device tab no longer says that more mouse settings are coming; the DPI
  section occupies that space.
- `install.sh` installs `daemon/dpi.py` and `DpiColor.js`.

### Notes

- DPI is read-only in this release. Writing a stage from the panel is planned
  for 1.11.0.
- `ratbagd` is optional and not started automatically; when it is absent the
  vendor or manual path is used.

## [1.9.7] — 2026-11-25

### Changed

- Slider focus frames use a 2 px bottom pad and a 4 px top pad, balancing the
  visual weight of the label and the slider track.
- Auto exit and Check every use a 2 px top pad and a 4 px bottom pad, removing
  the extra air above them while keeping the chip row from touching the frame.
- The Buttons & Hotkeys heading gets a 16 px gap from the previous block.

## [1.9.6] — 2026-11-25

### Changed

- The Check every control now focuses as one block with its label and hint,
  matching Auto exit in Feel. Both groups use a smaller 4 px vertical inset
  inside the focus frame, and slider focus frames use the same tighter
  vertical padding.
- The gap below the Scroll/Feel/Device/Stats tab buttons is doubled to 8 px.

## [1.9.5] — 2026-11-25

### Changed

- Rebalanced the Buttons & Hotkeys section around its logical blocks: 8 px
  above and below its separator, 8 px between the heading and the button
  picker group, dense hotkey hint lines, 8 px between the hint paragraph and
  the button group, and only 2 px between Open config and Reset.

## [1.9.4] — 2026-11-25

### Changed

- Footer dots now sit in their own centred column between two equal hint
  halves, so they read as separators rather than prefixes.
- The settings content has an 8 px bottom pad matched to the 8 px gap above
  and below the footer separator.
- The Buttons & Hotkeys section has breathing room between its heading, hint
  lines, Open config button and Reset button.

### Fixed

- Removed the remaining translucent highlights from the cursor: the bevel and
  front edge are opaque colours and the soft specular overlay is gone. The
  silhouette fill underneath guarantees a solid prism at every angle.

## [1.9.3] — 2026-11-25

### Changed

- Footer hints now sit in a centred two-column grid with a dot between the
  hints on each row. The text is shorter and more direct (`j/k to move`,
  `Enter to select`, `r to rescan`, …), and no hint is elided or split.
- Focus frames sit on the element bounds with a consistent 6 px content inset.
  Grouped chip rows have padded wrappers, so the frame no longer cuts through
  the first or last chip. Question-mark hints keep a 22 px slot.
- Footer separator spacing is balanced at 8 px above and below, and the row
  spacing in Feel/Device is tighter so controls do not drift apart.
- The cursor silhouette is filled before its faces. Any hairline seam between
  the front, back and side quads now shows the side colour, never the panel.

### Fixed

- Removed the last phantom micro-scroll when the settings already fit above
  the footer.

## [1.9.2] — 2026-11-25

### Fixed

- Focus frames now stay inside each element's own bounds, 2 px in, with a
  consistent 6 px content inset. Adjacent buttons and rows no longer receive a
  frame that spills onto them, and full-width sliders keep all four borders.
- Help question marks reserve a 22 px focus slot, so their frame stays inside
  the label row while they remain part of the keyboard cursor cycle.
- Footer hints are now a centred three-column grid: each hint stays whole, no
  line ends with a dot, and there is a clear gap below the separator.
- Removed the phantom micro-scroll that appeared when the content already fit
  above the footer.

## [1.9.1] — 2026-11-25

### Fixed

- The connection type is now shown only in the device picker; the duplicate
  Device row and footer line were removed.
- The cursor arrow is now a fully opaque prism. The side faces no longer carry
  the back face's alpha, so the end cap reads as one solid 3D object.
- Slider labels keep the help icon next to the label and reserve room for the
  green Done mark, so it no longer collides with the value.
- The focus frame now has the same inset on every side and enough room inside
  the scroll viewport, so full-width sliders no longer lose their left and
  right borders. Content is inset consistently from the frame.
- The footer uses whole hint units: a hint wraps to the next line as a unit
  instead of splitting mid-phrase, and now includes `r rescan`.
- Help question marks are part of the keyboard cursor cycle; focusing one
  shows its tooltip.
- Added spacing between the footer separator and the scrollable content.
- Removed the buses and track-laps rows from the trackball statistics.

## [1.9.0] — 2026-11-25

### Added

- Keyboard-first panel navigation: `j`/`k` moves between controls, `h`/`l`
  adjusts the current control, `Enter` selects, `1`–`4` switches tabs, `r`
  rescans and `Esc` closes. Mouse hover feeds the same cursor, so there is only
  one highlight at a time.
- A fixed footer at the bottom of the panel: the active connection type on the
  first line and the keyboard hints on the second. It stays visible on every
  screen instead of scrolling with the settings.

### Changed

- Device picker labels now put the transport and device type at the end after
  dots, for example `Wings Tech Gaming Mouse · USB · MS`, instead of a
  bracketed code prefix.

## [1.8.4] — 2026-11-25

### Fixed

- The Scroll and Feel tabs no longer leak onto mouse devices. Their content
  is gated by the active device's scroll capability, and the panel falls back
  to the Device tab as soon as a mouse becomes active.
- The cursor arrow now has a proper prism end face: a smaller back face,
  connecting side faces and a bright beveled rim. It reads as a solid 3D
  pointer at every angle instead of a flat ribbon.

### Added

- Connection type in the device picker and the Device tab: USB cable, 2.4 GHz
  receiver, Bluetooth or unknown.

## [1.8.3] — 2026-11-24

### Fixed

- The device picker no longer copies the active mouse's name and type onto the
  Logitech receiver. Each listed device is named and classified from its own
  cached HID++ identity, so the trackball stays `[TB] Logitech ERGO M575S`
  while a different mouse is active.

## [1.8.2] — 2026-11-24

### Fixed

- Removed the horizontal-scale sign clamp that made the slow cursor turn jump
  when it crossed the edge-on angle. The perspective scale now passes smoothly
  through zero, with a slightly thicker extrusion so the pointer still reads in
  profile.
- Brightened the extruded edge and added a faint bevel on its far side, and the
  specular spot now fades out as the face turns away. The pointer no longer
  flashes dark when it passes edge-on.
- HID++ identity is cached per device and refreshed on input, so waking from
  sleep no longer leaves a stale name or type on the receiver. The cache is only
  read and written for Logitech receivers, and late probe results from a
  previous device are discarded, so a non-Logitech mouse cannot pick up the
  trackball's identity.

## [1.8.1] — 2026-11-24

### Changed

- The cursor arrow is now a massive rounded triangle with no thin stem. Its
  corners are softened and the extrusion is thicker, so it reads as a solid
  pointer instead of a sharp shard.
- The front-face highlight is projected with the arrow and clipped to its
  face, so it turns with the cursor instead of staying in screen space.
- The horizontal scale never collapses below a small minimum and the light
  edge is always drawn, removing the blink at the edge-on angle.

## [1.8.0] — 2026-11-24

### Changed

- Replaced the literal mouse glyph with a cursor-arrow badge for mouse
  devices. The arrow is extruded so it stays readable while turning around its
  vertical axis.
- Opening glides the arrow in and starts the idle turn; idle keeps a calm
  rotation; clicking spins it up, brakes back to idle and draws horizontal
  white air streams while fast.
- The old mouse body, wheel spin, side buttons and click sound waves were
  removed.

## [1.7.1] — 2026-11-24

### Changed

- Redrew the mouse glyph around the Logitech Signature M650 proportions: a
  tapered shell, split click panels, a dark rubber wheel with a metal rim and
  moving ridges, and two side buttons.
- Air streaks now run horizontally across the front of the trackball, with
  short side wisps, instead of tracing the outer rim.
- Made the mouse opening, idle and click animations more visible: a larger
  settle, a slow gentle drift while idle, a stronger press, a longer wheel
  spin and larger sound-wave arcs from the left button.

## [1.7.0] — 2026-11-24

### Added

- A top-down mouse glyph for mouse devices, inspired by the Logitech Signature
  M650, with split buttons, a dark rubber wheel with a metal rim, and side
  buttons. It has an opening glide/settle, a slow idle drift, and a click
  animation that presses the body, spins the wheel and sends small sound-wave
  arcs from the left button.
- A `DeviceIcon` selector used by both the bar and the panel header; future
  trackpad and unknown glyphs can plug in here.
- Clicking the trackball in the panel header kicks it into a deliberate
  spin-up and braking animation.
- White air streaks around the trackball while it moves faster than a
  threshold, fading in with speed and disappearing at idle.
- Both animations respect `Style.reduceMotion`.

## [1.6.0] — 2026-11-24

### Added

- Applicability matrix: the panel builds its tabs from the active device's
  `supportsScroll`, `supportsStats` and `supportsButtons` flags. A mouse gets
  Device and Stats only; trackpad/tablet/unknown get Device only; trackball
  keeps the full panel. The daemon refuses scroll/sniper for non-trackball
  pointers.
- Mouse statistics: physical wheel notches, pages, clicks, movement, active
  time, top speed, direction and days. Movement is collected passively in
  pointer mode without grabbing the device. Distance comparisons appear when
  the mouse reports DPI; otherwise movement stays in raw counts with a note.
- Trackball statistics now count ball movement in pointer mode as well as
  scroll/sniper. Flicks and coast remain scroll-only.
- The stats file is now v3 with separate `trackball` and `mouse` sections;
  older flat stats migrate into the trackball section.
- Battery UI is gated by the active device being wireless, not just by the
  presence of a battery report somewhere in the daemon.

## [1.5.0] — 2026-11-24

### Added

- Pointer classification with `kind`, two-letter `code`, `confidence`,
  `sources` and `wireless` in `status.json`.
- HID++ `0x0005` device type for Logitech (`3` mouse, `4` trackpad,
  `5` trackball), plus udev `ID_INPUT_*` tags, name/model hints and an evdev
  fallback for every other vendor.
- The panel title follows the active device type; the device picker prefixes
  names with `[TB]`, `[MS]`, `[TP]`, `[TA]` or `[UN]`.
- The HID++ identity probe now prefers pointer types, so a paired keyboard
  cannot win over a trackball on a multi-device receiver.

## [1.4.2] — 2026-11-24

### Fixed

- Restored the Scroll-tab slider titles. Only the explanatory captions below
  the sliders are hidden; the titles, help icons and values remain.
- Slider titles now share the same body font size, width and elision behaviour
  as the toggle labels, so field labels line up consistently.

## [1.4.1] — 2026-11-24

### Changed

- The Scroll tab's two speed sliders no longer carry labels or hint lines,
  leaving a cleaner slider-and-value layout.
- The battery ring on the bar ball is larger and sits further into the
  bottom-right corner.
- The Device tab separates the sniper-button and hotkey controls under a
  **Buttons & hotkeys** band, like the battery block.
- Battery UI is shown only when the active device is wireless and reports a
  battery; wired devices and mice without a battery hide the bar ring, header
  badge and Device battery section.

## [1.4.0] — 2026-11-24

### Added

- Battery support for Logitech mice over HID++ `0x1004` (unified battery):
  percentage, coarse level, charging state and external power.
- A small charge ring in the bottom-right corner of the bar ball, colour-coded
  green, amber, red and blue while charging.
- A battery badge next to the mode badge in the panel header, with the
  percentage and a battery or charging glyph.
- A Battery section in the **Device** tab: charge/state readout, gauge,
  **Show in bar**, **Low battery at** and **Check every** settings.
- `omarchy-scrollmode battery` prints the current battery state.
- Battery data is included in `/run/omarchy-scrollmode/status.json`.

### Changed

- The daemon polls the battery in a background thread, so HID++ reads never
  block scrolling. The last known value is kept while the mouse sleeps and is
  marked stale instead of disappearing.

## [1.3.5] — 2026-11-24

### Changed

- Comparison percentages reset at 100 %, and the number of completed laps,
  trips or orbits is shown in brackets next to the progress.
- Replaced car lengths and 10K runs with bus lengths and running-track laps.
- Removed the extra divider between the headline numbers and the Totals
  section; the section heading already separates them.

### Fixed

- `status.json` is now compared with the file on disk instead of an in-memory
  cache. A service restart can no longer leave the panel showing "No pointing
  device" until another manual restart.

## [1.3.4] — 2026-11-24

### Changed

- Statistics sections now have bold uppercase headers with a divider line and
  more space between them, so each label stays attached to its number.
- The comparisons section is a distance ladder that grows from car lengths and
  football fields through 10K runs and marathons to the Earth, Moon and Sun.
- Counts use adaptive precision, so a normal day of rolling visibly changes
  them, including the very large targets.
- The note under the table explains that counts are multiples and `%` is
  progress to the target.

## [1.3.3] — 2026-11-24

### Changed

- The Stats tab opens with three side-by-side headline numbers: record speed,
  ball distance and ball turns. Totals, flick records and days use compact
  two-column cells, so the whole tab fits without hiding rows.
- The Earth, Moon and Sun comparisons now read as distance covered against the
  target plus a percentage precise enough that a normal day of rolling visibly
  moves it. The paper-stack and marathon rows were dropped.
- Days show the distance rolled rather than wheel notches.
- Existing statistics with per-day notches are migrated automatically; day
  distances are rebuilt from the stored notch counts.
- The Stats tab scrolls when the screen is too short for the full card.

## [1.3.2] — 2026-11-23

### Added

- Circled question-mark hints next to the non-obvious settings, with short
  tooltips explaining what each one changes.
- Sniper trigger learning: choose a spare mouse button in the panel (or run
  `omarchy-scrollmode learn`) and press it once. The button is stored as
  `sniper_button`; the option is hidden when the device reports no spare button.
- The settings panel is split into **Scroll**, **Feel**, **Device** and
  **Stats** tabs, so the full list fits without filling the screen. The device
  picker stays above the tabs.
- The sniper button control shows the current button and flashes a green
  **✓ Done** after a successful pick.
- The **Stats** tab: cumulative distance the ball rolled, ball turns, wheel
  notches, pages, flicks, top speed, longest coast, favourite direction and fun
  comparisons (around the Earth, to the Moon, around the Sun). The data lives in
  `/var/lib/omarchy-scrollmode/stats.json`; no home file and no cursor
  coordinates.

### Changed

- Inertia has **Trigger** and **Coast** controls (`inertia_trigger` in notches
  per second, `inertia_strength` in percent), so the balance is adjustable
  instead of hard-coded.
- The sniper button is off by default. Left, right, middle, Back and Forward are
  reserved and rejected during learning; an old `sniper_button: 275` config no
  longer steals the Back button.
- Setting titles are shorter now that the tooltips explain them.
- A rejected learn warning disappears after eight seconds instead of staying in
  the panel.
- The Trigger readout and the statistics toggle were removed; statistics are
  always collected into the system state directory instead of a JSONL file in
  the home directory.

### Fixed

- Inertia starts after about one and a half device frame intervals (roughly
  12 ms at 125 Hz, clamped to 10–40 ms) instead of a fixed 40 ms. The trigger
  uses the raw frame peak over 300 ms instead of the smoothed velocity: a short,
  sharp flick is no longer diluted to 35–58 % of its real speed. The coast
  starts from the release velocity, not the peak, so it no longer kicks back to
  a speed the ball already lost. The coast ticks at 125 Hz instead of 60 Hz,
  which keeps the smooth scrolling animation alive.
- A small movement during a coast clears the stale velocity and peak, so it
  cannot start a second coast from the same flick. This removes the occasional
  double kick. The first coast frame is capped to one normal 8 ms frame so the
  quiet gap does not read as another kick either.
- Device enumeration is paused while scrolling. Scanning every input node took
  roughly 250 ms on a normal desktop; during a grabbed flick that stalled the
  event stream, compressed many frames into one burst and made the velocity
  estimate (and therefore the coast) jump or disappear.

## [1.3.1] — 2026-11-23

### Security

- The daemon now refuses control commands from the installing user while
  another user owns the active session on the device's seat, and releases the
  grab within a second when the seat switches. This closes the shared-computer
  case where a lingering process of the previous account could convert the new
  user's pointer movement into scrolling. `root` can still control the daemon;
  the guard is built in and cannot be disabled from the user config.

### Changed

- `install.sh` no longer installs `python-evdev` with pacman. It checks for the
  module and stops with the exact command; the README lists it as a dependency.

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

