#!/usr/bin/env bash
# Install the trackball scroll-mode daemon, its systemd unit and the bar widget.
# Run as your normal user: the script elevates once for the privileged part.
#
#   ./install.sh                            # uses sudo
#   SCROLLMODE_ELEVATE=pkexec ./install.sh  # uses pkexec
set -euo pipefail

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PLUGIN_ID="anton.scrollmode"
PLUGIN_SRC="$SRC_DIR"
PLUGIN_DST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CONFIG_FILE="$HOME/.config/omarchy/scrollmode.json"
LIB_DIR="/usr/local/lib/omarchy-scrollmode"
BIN="/usr/local/bin/omarchy-scrollmode"
UNIT="/etc/systemd/system/omarchy-scrollmode.service"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# Privileged stage: runs as root, started by the stage below with sudo/pkexec.
# --------------------------------------------------------------------------
root_stage() {
  local src="$1" user_uid="$2" user_gid="$3"

  /usr/bin/python3 -c 'import evdev' >/dev/null 2>&1 ||
    die "python-evdev is required. Install it first: sudo pacman -S --needed python-evdev"

  say "installing the daemon and the CLI"
  install -Dm755 "$src/daemon/scrollmoded.py" "$LIB_DIR/scrollmoded.py"
  install -Dm755 "$src/daemon/omarchy-scrollmode" "$BIN"

  say "installing the systemd unit"
  local unit_tmp
  unit_tmp="$(mktemp)"
  cat >"$unit_tmp" <<EOF
[Unit]
Description=Trackball scroll mode daemon
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/bin/python3 $LIB_DIR/scrollmoded.py --uid $user_uid --gid $user_gid
Restart=on-failure
RestartSec=2
RuntimeDirectory=omarchy-scrollmode
RuntimeDirectoryMode=0755
RuntimeDirectoryPreserve=yes
StateDirectory=omarchy-scrollmode
StateDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF
  install -Dm644 "$unit_tmp" "$UNIT"
  rm -f "$unit_tmp"

  systemctl daemon-reload
  systemctl enable omarchy-scrollmode.service
  systemctl reset-failed omarchy-scrollmode.service 2>/dev/null || true
  systemctl restart omarchy-scrollmode.service
  sleep 0.5
  systemctl is-active --quiet omarchy-scrollmode.service ||
    die "the daemon did not stay up, check: journalctl -u omarchy-scrollmode -n 40"
}

if [[ ${1:-} == --root-stage ]]; then
  shift
  [[ $# -eq 3 ]] || die "--root-stage needs <source-dir> <uid> <gid>"
  root_stage "$@"
  exit 0
fi

# --------------------------------------------------------------------------
# User stage
# --------------------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "run this as your user, not with sudo (it elevates itself)"
command -v python3 >/dev/null || die "python3 is required"
command -v omarchy >/dev/null || die "this installer is for Omarchy"
/usr/bin/python3 -c 'import evdev' >/dev/null 2>&1 ||
  die "python-evdev is required. Install it first: sudo pacman -S --needed python-evdev"

ELEVATE="${SCROLLMODE_ELEVATE:-sudo}"
command -v "$ELEVATE" >/dev/null || die "$ELEVATE is not available"

# The daemon reads this file at start, so it has to exist before the service.
if [[ ! -f $CONFIG_FILE ]]; then
  say "writing the default config"
  install -Dm644 "$SRC_DIR/config.default.json" "$CONFIG_FILE"
else
  say "keeping the existing config at $CONFIG_FILE"
fi

say "elevating for the daemon, the CLI and the systemd unit (via $ELEVATE)"
"$ELEVATE" bash "$SRC_DIR/install.sh" --root-stage "$SRC_DIR" "$(id -u)" "$(id -g)"

say "installing the bar widget"
if [[ "$PLUGIN_SRC" -ef "$PLUGIN_DST" ]]; then
  say "the plugin is already in place (installed from git)"
else
  # A full copy, not just the widget: the panel's "Install…" button runs
  # install.sh from the plugin directory, so it has to be there.
  mkdir -p "$PLUGIN_DST/i18n" "$PLUGIN_DST/daemon"
  install -m644 "$PLUGIN_SRC/manifest.json" "$PLUGIN_DST/manifest.json"
  install -m644 "$PLUGIN_SRC/ScrollMode.qml" "$PLUGIN_DST/ScrollMode.qml"
  install -m644 "$PLUGIN_SRC/TrackballBall.qml" "$PLUGIN_DST/TrackballBall.qml"
  install -m644 "$PLUGIN_SRC/CursorGlyph.qml" "$PLUGIN_DST/CursorGlyph.qml"
  install -m644 "$PLUGIN_SRC/DeviceIcon.qml" "$PLUGIN_DST/DeviceIcon.qml"
  install -m644 "$PLUGIN_SRC"/i18n/*.json "$PLUGIN_DST/i18n/"
  install -m755 "$PLUGIN_SRC/install.sh" "$PLUGIN_DST/install.sh"
  install -m755 "$PLUGIN_SRC/uninstall.sh" "$PLUGIN_DST/uninstall.sh"
  install -m755 "$PLUGIN_SRC/daemon/omarchy-scrollmode" "$PLUGIN_DST/daemon/omarchy-scrollmode"
  install -m644 "$PLUGIN_SRC/daemon/scrollmoded.py" "$PLUGIN_DST/daemon/scrollmoded.py"
  install -m644 "$PLUGIN_SRC/config.default.json" "$PLUGIN_DST/config.default.json"
fi

say "validating the plugin"
omarchy plugin validate "$PLUGIN_DST"

say "applying the hotkey"
"$BIN" hotkey || warn "Hyprland reported a problem with the binding; check ~/.config/hypr/bindings.lua"

if command -v omarchy-shell >/dev/null; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

say "placing the widget in centerEnd"
if omarchy bar put "$PLUGIN_ID" --section centerEnd --index 0; then
  omarchy bar move "$PLUGIN_ID" --section centerEnd --index 0 || true
else
  warn "could not place the widget automatically; run: omarchy bar put $PLUGIN_ID --section centerEnd"
fi

cat <<EOF

$(printf '\033[1;32mok\033[0m') installed.

  toggle now:        omarchy-scrollmode toggle
  or press:          $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("hotkey","SUPER + CAPS"))' "$CONFIG_FILE")
  config:            $CONFIG_FILE
  logs:              journalctl -u omarchy-scrollmode -f
  after edits:       omarchy-scrollmode reload && omarchy-scrollmode hotkey

Tune scroll feel with "scroll.counts_per_notch" (bigger = slower) and
"scroll.sensitivity" (multiplier).
EOF
