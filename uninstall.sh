#!/bin/bash
# uninstall.sh — remove everything install.sh created.
set -u
PREFIX="${MTGO_PREFIX:-$HOME/.wine-mtgo-arm64}"
WS="$HOME/Applications/MetalSharp-Wine.app/Contents/MacOS/wineserver"
echo "This deletes MTGO, its Windows environment and MetalSharp-Wine:"
printf '  %s\n' "$PREFIX" "$HOME/.mtgo-arm64" "$HOME/Applications/MTGO.app" "$HOME/Applications/MetalSharp-Wine.app"
read -r -p "Continue? [y/N] " ans
[[ "$ans" =~ ^[Yy] ]] || { echo "Cancelled."; exit 0; }
[[ -x "$WS" ]] && WINEPREFIX="$PREFIX" "$WS" -k 2>/dev/null
rm -rf "$PREFIX" "$HOME/.mtgo-arm64" "$HOME/Applications/MTGO.app" "$HOME/Applications/MetalSharp-Wine.app"
echo "Removed. (Homebrew's cabextract and sevenzip were left installed.)"
