#!/bin/bash
# install.sh — Magic: The Gathering Online on Apple Silicon Macs, without Rosetta 2.
#
# Runtime: MetalSharp-Wine (Wine 11 built natively for arm64; FEX-Emu translates
# MTGO's x86 code inside Wine instead of Rosetta). Signed + notarized.
#
# Usage:   bash install.sh
# Re-run any time: finished steps are skipped, and missing pieces are repaired.
#
# Creates:
#   ~/Applications/MetalSharp-Wine.app   Wine runtime (arm64)
#   ~/.wine-mtgo-arm64/                   Windows environment ("prefix") for MTGO
#   ~/.mtgo-arm64/                        launcher, winetricks, logs
#   ~/Applications/MTGO.app               double-click launcher (also in Spotlight)

set -euo pipefail

PREFIX="${MTGO_PREFIX:-$HOME/.wine-mtgo-arm64}"
APPDIR="$HOME/Applications"
WORK="$HOME/.mtgo-arm64"
LOG="$WORK/install.log"
MTGO_URL="http://mtgo.patch.daybreakgames.com/patch/mtg/live/client/MTGO.application"
WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"
RELEASES_API="https://api.github.com/repos/metalsharp/MetalSharp-Wine/releases/latest"

NET40_NAME=dotNetFx40_Full_x86_x64.exe
NET40_URL=https://download.microsoft.com/download/9/5/A/95A9616B-7A37-4AF6-BC36-D6EA96C8DAAE/dotNetFx40_Full_x86_x64.exe
NET40_SHA=65e064258f2e418816b304f646ff9e87af101e4c9552ab064bb74d281c38659f
NET48_NAME=ndp48-x86-x64-allos-enu.exe
NET48_URL=https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe
NET48_SHA=95889d6de3f2070c07790ad6cf2000d33d9a1bdfc6a381725ab82ab1c314fd53

mkdir -p "$APPDIR" "$WORK"
exec > >(tee -a "$LOG") 2>&1

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\nFull log: %s\n' "$*" "$LOG" >&2; exit 1; }
trap 'die "failed at line $LINENO (exit $?)"' ERR

# ------------------------------------------------------------------ 1. System checks
step "Checking your Mac"
[[ "$(uname -s)" == "Darwin" ]] || die "This installer is for macOS."
[[ "$(uname -m)" == "arm64" ]]  || die "This installer is for Apple Silicon Macs."
ver="$(sw_vers -productVersion)"
maj="${ver%%.*}"; rest="${ver#*.}"; min="${rest%%.*}"; [[ "$rest" == "$ver" ]] && min=0
echo "macOS $ver"
if (( maj < 26 || (maj == 26 && min < 4) )); then
  die "macOS 26.4 or later is required (32-bit Windows code under FEX needs it)."
fi
if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "Rosetta 2 is installed, but nothing in this setup uses it."
else
  echo "Rosetta 2 is not installed. Good: nothing here needs it."
fi

export PATH="/opt/homebrew/bin:$PATH"
command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install it from https://brew.sh and re-run."

step "Installing helper tools (cabextract, 7-Zip) with Homebrew"
command -v cabextract >/dev/null 2>&1 || brew install cabextract
command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1 || brew install sevenzip
SZ="$(command -v 7zz || command -v 7z)"

# ------------------------------------------------------------------ 2. MetalSharp-Wine
step "Installing MetalSharp-Wine (native arm64 Wine + FEX)"
WINE_APP="$APPDIR/MetalSharp-Wine.app"
if [[ ! -d "$WINE_APP" ]]; then
  json="$(curl -fsSL "$RELEASES_API")" || die "Could not reach the GitHub releases API."
  urls="$(printf '%s' "$json" | grep -Eo '"browser_download_url": *"[^"]+"' | sed -E 's/.*"(https[^"]+)"$/\1/')"
  url="$(printf '%s\n' "$urls" | grep -E 'MetalSharp-Wine-[^/]*-arm64\.zip$' | head -n1 || true)"
  [[ -n "$url" ]] || { printf 'Assets found:\n%s\n' "$urls"; die "No signed MetalSharp-Wine .zip in the latest release."; }
  echo "Downloading $url"
  rm -rf "$WORK/wine-extract"; mkdir -p "$WORK/wine-extract"
  curl -fL --progress-bar -o "$WORK/metalsharp-wine.zip" "$url"
  ditto -x -k "$WORK/metalsharp-wine.zip" "$WORK/wine-extract"   # keeps signature + entitlements
  src="$(find "$WORK/wine-extract" -maxdepth 3 -name '*.app' -type d | head -n1)"
  [[ -n "$src" ]] || die "No .app found inside the MetalSharp-Wine zip."
  mv "$src" "$WINE_APP"
  rm -rf "$WORK/wine-extract" "$WORK/metalsharp-wine.zip"
fi
codesign --verify --deep --strict "$WINE_APP" || die "Code signature check failed. Delete $WINE_APP and re-run."
echo "Signature OK."

WINE="$WINE_APP/Contents/MacOS/wine"
[[ -x "$WINE" ]] || WINE="$(find "$WINE_APP" -type f -name wine -perm -u+x | head -n1)"
[[ -x "$WINE" ]] || die "Couldn't find the wine binary inside $WINE_APP"
WINESERVER="$(dirname "$WINE")/wineserver"
[[ -x "$WINESERVER" ]] || WINESERVER="$(find "$WINE_APP" -type f -name wineserver -perm -u+x | head -n1)"
[[ -x "$WINESERVER" ]] || die "Couldn't find wineserver inside $WINE_APP"
archs="$(lipo -archs "$WINE" 2>/dev/null || file -b "$WINE")"
[[ "$archs" == *x86_64* && "$archs" != *arm64* ]] && die "This wine binary is Intel-only (would need Rosetta)."

export WINE WINESERVER WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG=-all
WINEBIN="$(dirname "$WINE")"
export PATH="$WINEBIN:$PATH"
echo "Using $("$WINE" --version)"
reg() { "$WINE" reg add "$@" /f >/dev/null; }

# ------------------------------------------------------------------ 3. Prefix, fonts, .NET 4.8
step "Creating the Windows environment at $PREFIX"
if [[ ! -f "$PREFIX/system.reg" ]]; then
  "$WINE" wineboot -i
  "$WINESERVER" -w
else
  echo "Already exists."
fi

curl -fsSL -o "$WORK/winetricks" "$WINETRICKS_URL"
chmod +x "$WORK/winetricks"

step "Installing core fonts"
"$WORK/winetricks" -q corefonts || warn "corefonts failed; Wine's metric-compatible fonts will be used instead."
"$WINESERVER" -w

step "Installing .NET Framework 4.8 (slow under translation: 15-45 minutes)"
"$WORK/winetricks" -q dotnet48 || die ".NET Framework 4.8 failed to install."
"$WINESERVER" -w

# ------------------------------------------------------------------ 4. Repair .NET system DLLs
# Under ARM64 Wine the .NET installers skip everything destined for system32/syswow64:
# mscoree.dll (starts every .NET program), dfshim.dll (ClickOnce, used to install MTGO)
# and the CLR's private C runtimes. Unpack them from Microsoft's own installers.
step "Restoring .NET system files the installer skipped under ARM64 Wine"
get_installer() { # name url sha256 -> path
  local f
  f="$(find "$HOME/Library/Caches/winetricks" "$HOME/.cache/winetricks" -name "$1" 2>/dev/null | head -n1)"
  if [[ -z "$f" ]]; then
    f="$WORK/dotnet/$1"; mkdir -p "$WORK/dotnet"
    [[ -f "$f" ]] || curl -fL --progress-bar -o "$f" "$2" || die "download failed: $2"
  fi
  [[ "$(shasum -a 256 "$f" | cut -d' ' -f1)" == "$3" ]] || die "checksum mismatch: $f"
  echo "$f"
}
NET40="$(get_installer "$NET40_NAME" "$NET40_URL" "$NET40_SHA")"
NET48="$(get_installer "$NET48_NAME" "$NET48_URL" "$NET48_SHA")"
T="$WORK/dotnet-fix"; rm -rf "$T"; mkdir -p "$T"
"$SZ" e -y -o"$T/40" "$NET40" netfx_Core.mzz >/dev/null
"$SZ" e -y -o"$T/48" "$NET48" netfx_Full.mzz >/dev/null
cabextract -q -d "$T/40x" "$T/40/netfx_Core.mzz" 2>/dev/null || true
cabextract -q -d "$T/48x" "$T/48/netfx_Full.mzz" 2>/dev/null || true
C="$PREFIX/drive_c/windows"
while read -r src cab dir dll; do
  from="$T/$src/$cab"; to="$C/$dir/$dll"
  [[ -f "$from" ]] || die "missing from Microsoft's package: $cab"
  if [[ -f "$to" ]] && ! grep -q -a -E 'Wine (builtin|placeholder) DLL' "$to"; then
    echo "  ok     $dir/$dll"
  else
    cp -f "$from" "$to"; chmod u+w "$to"; echo "  added  $dir/$dll"
  fi
done <<'MAP'
40x _003_mscoree_dll_amd64 system32 mscoree.dll
40x _003_mscoree_dll_x86 syswow64 mscoree.dll
40x _001_dfshim_dll_amd64 system32 dfshim.dll
40x _001_dfshim_dll_x86 syswow64 dfshim.dll
48x msvcp_clr_dll_amd64 system32 msvcp110_clr0400.dll
48x msvcp_clr_dll_x86 syswow64 msvcp110_clr0400.dll
48x msvcr_clr_dll_amd64 system32 msvcr110_clr0400.dll
48x msvcr_clr_dll_x86 syswow64 msvcr110_clr0400.dll
48x msvcr100_clr0400_dll_amd64 system32 msvcr100_clr0400.dll
48x msvcr100_clr0400_dll_x86 syswow64 msvcr100_clr0400.dll
48x msvcp120_clr0400_dll_amd64 system32 msvcp120_clr0400.dll
48x msvcp120_clr0400_dll_x86 syswow64 msvcp120_clr0400.dll
48x msvcr120_clr0400_dll_amd64 system32 msvcr120_clr0400.dll
48x msvcr120_clr0400_dll_x86 syswow64 msvcr120_clr0400.dll
48x msvcp140_clr0400_dll_amd64 system32 msvcp140_clr0400.dll
48x msvcp140_clr0400_dll_x86 syswow64 msvcp140_clr0400.dll
48x ucrtbase_clr0400_dll_amd64 system32 ucrtbase_clr0400.dll
48x ucrtbase_clr0400_dll_x86 syswow64 ucrtbase_clr0400.dll
48x vcruntime140_clr0400_dll_amd64 system32 vcruntime140_clr0400.dll
48x vcruntime140_clr0400_dll_x86 syswow64 vcruntime140_clr0400.dll
MAP
rm -rf "$T"

# ------------------------------------------------------------------ 5. Settings
step "Applying MTGO settings"
reg 'HKCU\Software\Wine\DllOverrides' /v dfshim /t REG_SZ /d native             # Microsoft's ClickOnce, not Wine's stub
reg 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1   # WPF in software (GPU path is worse)
reg 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d n                # Retina makes the window vanish more often
reg 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 96
reg 'HKLM\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts' /v LogPixels /t REG_DWORD /d 96
"$WORK/winetricks" -q sound=disabled win10
"$WINESERVER" -w
echo "Done."

step "Precompiling .NET libraries (removes in-game stutter; 10-30 minutes)"
for fw in Framework64 Framework; do
  "$WINE" "C:\\windows\\Microsoft.NET\\$fw\\v4.0.30319\\ngen.exe" executeQueuedItems /nologo >/dev/null 2>&1 \
    && echo "  $fw: done" || warn "  $fw: ngen reported problems (MTGO still works, may stutter more)"
done
"$WINESERVER" -w

# ------------------------------------------------------------------ 6. Launchers
step "Writing launchers"
cat > "$WORK/launch.sh" <<EOF
#!/bin/bash
# MTGO launcher (generated by install.sh): MetalSharp-Wine, no Rosetta.
export WINEPREFIX=$(printf '%q' "$PREFIX") WINEARCH=win64 WINEDEBUG=-all WINEMSYNC=1
WINE=$(printf '%q' "$WINE")
# Re-apply WPF flags that stop MTGO's collection view from pinning a CPU core
# (MTGO updates overwrite this file). No-op if the keys aren't present.
find "\$WINEPREFIX/drive_c/users" -path '*Apps/2.0*' -name 'MTGO.exe.config' 2>/dev/null | while read -r cfg; do
  sed -i '' -E 's/(key="(DisableAutomationPeer|PurgeAutomationEvents|DisableStylusInput|DisableTabletDevices)"[[:space:]]+value=)"false"/\1"true"/' "\$cfg" || true
done
# Launch through .NET's ClickOnce handler: installs or updates MTGO, then starts it.
exec "\$WINE" rundll32.exe dfshim.dll,ShOpenVerbApplication $MTGO_URL
EOF
chmod +x "$WORK/launch.sh"

rm -rf "$APPDIR/MTGO.app"
osacompile -o "$APPDIR/MTGO.app" \
  -e "do shell script \"/bin/bash \" & quoted form of \"$WORK/launch.sh\" & \" >> \" & quoted form of \"$WORK/mtgo.log\" & \" 2>&1 &\""
echo "Created $APPDIR/MTGO.app"

trap - ERR
step "All set. Starting MTGO"
cat <<'MSG'
The first time, a dialog asks to install "Magic The Gathering Online": click Install.
MTGO downloads (~640 MB) and opens the login screen.

From now on, start MTGO with ~/Applications/MTGO.app (or Spotlight: "MTGO").
MSG
bash "$WORK/launch.sh" >> "$WORK/mtgo.log" 2>&1 &
