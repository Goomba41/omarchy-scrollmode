#!/usr/bin/env bash
# Remove the daemon, the systemd unit, the CLI, the bar widget and the managed
# hotkey block. The config in ~/.config/omarchy/scrollmode.json is kept, along
# with the bindings backup made at install time.
set -euo pipefail

PLUGIN_ID="anton.scrollmode"
PLUGIN_DST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
LIB_DIR="/usr/local/lib/omarchy-scrollmode"
BIN="/usr/local/bin/omarchy-scrollmode"
UNIT="/etc/systemd/system/omarchy-scrollmode.service"
BINDINGS="$HOME/.config/hypr/bindings.lua"
RUNTIME_DIR="/run/omarchy-scrollmode"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

say "stopping the service"
sudo systemctl disable --now omarchy-scrollmode.service 2>/dev/null || true
sudo rm -f "$UNIT"
sudo systemctl daemon-reload
sudo systemctl reset-failed omarchy-scrollmode.service 2>/dev/null || true

say "removing the managed hotkey"
if [[ -x $BIN ]]; then
  "$BIN" hotkey remove || true
elif [[ -f $BINDINGS ]]; then
  # The CLI is already gone (or half-removed): strip the block ourselves.
  sed -i '/^-- >>> omarchy-scrollmode >>>$/,/^-- <<< omarchy-scrollmode <<<$/d' "$BINDINGS"
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
fi

say "removing the bar widget"
omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
rm -rf "$PLUGIN_DST"
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

say "removing the daemon and the CLI"
sudo rm -rf "$LIB_DIR"
sudo rm -f "$BIN"

say "removing the runtime directory"
sudo rm -rf "$RUNTIME_DIR"

say "done"
echo "The config was kept at $HOME/.config/omarchy/scrollmode.json"
echo "The pre-install keybindings backup, if any, is $BINDINGS.before-scrollmode"
