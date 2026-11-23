#!/usr/bin/env bash
# Remove the daemon, the unit, the widget and the managed hotkey.
# The config in ~/.config/omarchy/scrollmode.json is kept.
set -euo pipefail

PLUGIN_ID="anton.scrollmode"
PLUGIN_DST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
LIB_DIR="/usr/local/lib/omarchy-scrollmode"
BIN="/usr/local/bin/omarchy-scrollmode"
UNIT="/etc/systemd/system/omarchy-scrollmode.service"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

say "stopping the service"
sudo systemctl disable --now omarchy-scrollmode.service 2>/dev/null || true
sudo rm -f "$UNIT"
sudo systemctl daemon-reload

say "removing the managed hotkey"
if [[ -x $BIN ]]; then
  "$BIN" hotkey remove || true
fi

say "removing the bar widget"
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
rm -rf "$PLUGIN_DST"

say "removing the daemon and the CLI"
sudo rm -rf "$LIB_DIR"
sudo rm -f "$BIN"

say "done. The config was kept at $HOME/.config/omarchy/scrollmode.json"
