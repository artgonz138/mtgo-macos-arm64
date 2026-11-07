#!/bin/bash
# tools/debug-session.sh — record an MTGO session with full Mac-driver tracing and line up
# flicker/disappear moments with CPU load and what Wine did to MTGO's windows.
# Run with:  bash tools/debug-session.sh      (restarts MTGO with logging on)
set -uo pipefail
export WINEPREFIX="$HOME/.wine-mtgo-arm64"
W="${W:-$HOME/Applications/MetalSharp-Wine.app/Contents/MacOS/wine}"
WS="$(dirname "$W")/wineserver"
D="$HOME/.mtgo-arm64/debug/$(date +%Y%m%d-%H%M%S)"
URL=http://mtgo.patch.daybreakgames.com/patch/mtg/live/client/MTGO.application
mkdir -p "$D"

stamp() {  # prefix each line with epoch seconds
  if command -v perl >/dev/null 2>&1; then perl -ne 'BEGIN{$|=1} print time()," ",$_'
  else while IFS= read -r l; do echo "$(date +%s) $l"; done; fi
}
when() { date -r "$1" +%T 2>/dev/null || echo "$1"; }

echo "Collecting current settings..."
{
  for k in 'HKCU\Software\Wine\Mac Driver' 'HKCU\Control Panel\Desktop' 'HKCU\Software\Wine\Explorer' \
           'HKCU\Software\Wine\Explorer\Desktops' 'HKCU\Software\Microsoft\Avalon.Graphics' 'HKCU\Software\Wine\Direct3D'; do
    echo "-- $k"
    WINEDEBUG=-all "$W" reg query "$k" 2>&1 | grep -i -E 'RetinaMode|LogPixels|  Desktop|Default|DisableHW|renderer|unable'
  done
  echo "-- MTGO.exe.config WPF flags"
  find "$WINEPREFIX/drive_c/users" -path '*Apps/2.0*' -name 'MTGO.exe.config' 2>/dev/null | while read -r c; do
    grep -E 'DisableAutomationPeer|PurgeAutomationEvents|DisableStylusInput|DisableTabletDevices' "$c" \
      || echo "   (none of the four WPF flags present in $(basename "$(dirname "$c")"))"
  done
  echo "-- Mac: macOS $(sw_vers -productVersion 2>/dev/null), $(sysctl -n hw.ncpu 2>/dev/null) cores"
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset|Resolution|UI Looks like'
} > "$D/settings.txt" 2>&1

echo "Restarting MTGO with Mac-driver tracing on (logs can reach a few hundred MB; play 5-10 minutes)..."
"$WS" -k 2>/dev/null; sleep 2
find "$WINEPREFIX/drive_c/users" -path '*Apps/2.0*' -name 'MTGO.exe.config' 2>/dev/null | while read -r c; do
  sed -i '' -E 's/(key="(DisableAutomationPeer|PurgeAutomationEvents|DisableStylusInput|DisableTabletDevices)"[[:space:]]+value=)"false"/\1"true"/' "$c" 2>/dev/null || true
done
( WINEMSYNC=1 WINEDEBUG='err+all,+macdrv,fixme-all' "$W" rundll32.exe dfshim.dll,ShOpenVerbApplication "$URL" 2>&1 | stamp > "$D/wine.log" ) &

( while :; do
    now=$(date +%s)
    ps -axo pid=,pcpu=,rss=,command= | grep -i -E 'wine|\.exe' | grep -v -E 'grep|perl -ne' | sed "s/^/$now /"
    sleep 1
  done ) > "$D/cpu.log" 2>/dev/null &
SAMPLER=$!

echo
echo "Play normally. Each time MTGO flickers or vanishes, click this Terminal window and press Return"
echo "(a few seconds late is fine). When you're done, type q and press Return."
n=0
while IFS= read -r line; do
  [[ "$line" == q* ]] && break
  date +%s >> "$D/marks.log"; n=$((n+1)); echo "  event #$n marked at $(date +%T)"
done
kill "$SAMPLER" 2>/dev/null

top_procs() {  # $1=from $2=to : busiest Wine processes in that window (peak % of one core)
  awk -v a="$1" -v b="$2" '$1>=a && $1<=b {c=$0; sub(/^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +/,"",c)
    if($3>=mx[$2]){mx[$2]=$3; cmd[$2]=substr(c,1,90)}} END{for(p in mx) printf "  %5.0f%%  %s\n", mx[p], cmd[p]}' "$D/cpu.log" | sort -rn | head -4
}
{
  echo "== settings"; cat "$D/settings.txt"
  first=$(head -n1 "$D/cpu.log" | cut -d' ' -f1); last=$(tail -n1 "$D/cpu.log" | cut -d' ' -f1)
  echo "== whole session: busiest Wine processes (peak CPU)"; top_procs "${first:-0}" "${last:-0}"
  echo "== wine log: $(wc -l < "$D/wine.log" | tr -d ' ') lines; most frequent messages"
  cut -d' ' -f2- "$D/wine.log" | sed -E 's/^[0-9a-f]{4}://; s/0x[0-9a-f]+/0x_/g; s/-?[0-9]+,-?[0-9]+/N,N/g' | sort | uniq -c | sort -rn | head -15
  echo "== $n flicker marks"
  if [[ -f "$D/marks.log" ]]; then
    while read -r m; do
      echo "-- flicker at $(when "$m")  busiest processes in the 10 s before:"
      top_procs $((m-10)) "$m"
      echo "   Wine/Mac-driver events in the 8 s before (count there vs. typical 8 s), most unusual first:"
      awk -v m="$m" -v t0="${first:-0}" -v t1="${last:-1}" '
        { split($2,a,":"); k=a[2]":"a[3]":"a[4]; tot[k]++; if($1>=m-8 && $1<=m) win[k]++ }
        END{ T=t1-t0; if(T<8)T=8; for(k in win){e=tot[k]*8/T; printf "   %6d  vs %8.1f  %s\n", win[k], e, k} }' "$D/wine.log" \
        | awk '{r=$1/($3+0.5); printf "%10.2f %s\n", r, $0}' | sort -rn | head -n 12 | cut -c12-
      echo "   Window show/hide/order/alpha lines in the 8 s before:"
      awk -v m="$m" '$1>=m-8 && $1<=m' "$D/wine.log" | cut -d' ' -f2- \
        | grep -i -E 'show|hide|order|opaque|alpha|layer|minimi|visible|shape|color_key|set_cocoa_window' | grep -v -i flush \
        | sed -E 's/0x[0-9a-f]+/0x_/g; s/-?[0-9]+,-?[0-9]+/N,N/g' | sort | uniq -c | sort -rn | head -n 15 | sed 's/^/   /'
    done < "$D/marks.log"
  fi
} > "$D/summary.txt" 2>&1
cat "$D/summary.txt"
pbcopy < "$D/summary.txt" 2>/dev/null && echo "(summary copied to clipboard — paste it to Claude)"
echo "Full logs: $D"
