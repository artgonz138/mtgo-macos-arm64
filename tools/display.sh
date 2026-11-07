#!/bin/bash
# tools/display.sh — switch MTGO's display mode. Quit MTGO first.
#   standard  Retina off, normal size. Slightly soft text; MTGO's window vanishes least often. (default)
#   sharp     Retina on, interface ~75% size. Crisp text; occasional vanishing.
#   large     Retina on, normal size. Crisp text; vanishes most often.
set -euo pipefail
export WINEPREFIX="${MTGO_PREFIX:-$HOME/.wine-mtgo-arm64}" WINEDEBUG=-all
W="$HOME/Applications/MetalSharp-Wine.app/Contents/MacOS/wine"
case "${1:-}" in
  standard) retina=n; dpi=96 ;;
  sharp)    retina=y; dpi=144 ;;
  large)    retina=y; dpi=192 ;;
  *) echo "usage: bash tools/display.sh standard|sharp|large"; exit 1 ;;
esac
"$(dirname "$W")/wineserver" -k 2>/dev/null || true
"$W" reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d "$retina" /f >/dev/null
"$W" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null
"$W" reg add 'HKLM\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts' /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null
echo "Display mode: $1 (RetinaMode=$retina, DPI=$dpi). Start MTGO again from ~/Applications/MTGO.app."
