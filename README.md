# MTGO on Apple Silicon Macs (no Rosetta)

Run **Magic: The Gathering Online** on an Apple Silicon Mac with one script. It doesn't need Rosetta 2, a virtual machine, or a Windows license.

MTGO is a Windows-only .NET/WPF app. This project runs it on [MetalSharp-Wine](https://github.com/metalsharp/MetalSharp-Wine), a build of Wine 11 compiled natively for arm64. Inside Wine, [FEX-Emu](https://github.com/FEX-Emu/FEX) translates MTGO's x86 code instead of Rosetta. That matters because Apple is phasing Rosetta out: macOS 27 is the last release with full Rosetta support.

> Unofficial community project, not affiliated with Wizards of the Coast or Daybreak Games. Magic: The Gathering Online is a trademark of Wizards of the Coast. This repo contains only scripts. Everything else is downloaded from its official source at install time.

## Requirements

- Apple Silicon Mac (M1 or later)
- **macOS 26.4 or later.** FEX needs it to run MTGO's 32-bit components.
- [Homebrew](https://brew.sh)
- Several GB of free disk space, and 30–60 minutes for the first install (.NET installs slowly under translation)

Tested on an M4 Max with macOS 27.0 and MetalSharp Wine 5.0 (wine-11.20).

## Install

In Terminal:

```bash
git clone https://github.com/artgonz138/mtgo-macos-arm64.git ~/mtgo-macos-arm64
cd ~/mtgo-macos-arm64
bash install.sh
```

(No git? Download the ZIP from the green **Code** button on GitHub, unzip it, and run `bash install.sh` inside the folder.)

When the "Magic The Gathering Online" install dialog appears, click **Install**. MTGO downloads (about 640 MB) and opens the login screen.

After that, start MTGO with **~/Applications/MTGO.app** (or Spotlight: "MTGO"). The launcher checks for MTGO updates every time it starts, like the Windows client.

The installer is safe to re-run. Finished steps are skipped, and anything missing is repaired.

### What the installer does

1. Checks for Apple Silicon and macOS 26.4+, then installs `cabextract` and `sevenzip` with Homebrew.
2. Downloads the latest signed and notarized MetalSharp-Wine release into `~/Applications` and verifies its signature.
3. Creates a dedicated Windows environment (a "prefix") at `~/.wine-mtgo-arm64`, then uses [winetricks](https://github.com/Winetricks/winetricks) to install the core fonts and **.NET Framework 4.8**.
4. **Restores the .NET system files the installer skips under ARM64 Wine** (see below). They're unpacked from Microsoft's own .NET 4.0 and 4.8 installers, which are checksum-verified.
5. Applies the MTGO settings: software rendering for WPF, Retina off, sound off, Windows 10 mode, and Microsoft's ClickOnce handler.
6. Precompiles the .NET libraries (`ngen`) to cut in-game stutter.
7. Creates the launcher and `MTGO.app`, then starts the MTGO installer.

## Display modes

Quit MTGO, then run:

```bash
bash tools/display.sh standard   # default: Retina off, normal size, slightly soft text
bash tools/display.sh sharp      # Retina on, interface ~75% size, crisp text
bash tools/display.sh large      # Retina on, normal size, crisp text
```

The Retina modes look much better, but they make the window vanishing described below happen more often.

## Known issues

### The MTGO window sometimes disappears for a moment

This is the main remaining issue. For a split second, MTGO's window shows whatever is behind it, and clicks during that moment go to the app underneath.

**Cause:** MTGO draws its main window as a WPF *layered* (per-pixel transparent) window and pushes a full frame about 34 times a second through `UpdateLayeredWindow`. Wine's Mac driver turns that into a non-opaque macOS window. macOS shows, and sends clicks through, any pixel whose opacity is 0. So when a frame arrives blank, or before its pixels are copied in, the whole window turns see-through for that moment. A Mac-driver trace shows no hide or order-out events and a constant window opacity of 1, only the steady layered-window updates.

**What helps:** keep Retina off (`display.sh standard`). Frames with four times the pixels take longer and get caught half-done more often.

**What doesn't:**

- **GPU rendering for WPF (DXVK):** much worse, because each frame then also has to be read back from the GPU.
- **Wine's "virtual desktop":** the Mac driver doesn't support it ([Wine bug 34374](https://bugs.winehq.org/show_bug.cgi?id=34374)).

The real fix belongs in the Mac driver. If you can reproduce it, `tools/debug-session.sh` collects the evidence, and reports to MetalSharp help.

### Performance

- MTGO redraws its whole window in software, through translation, so expect some lag in busy moments. Retina off is fastest.
- Always start MTGO from `MTGO.app`. `tools/debug-session.sh` turns on heavy logging that slows the game down.
- The launcher sets `WINEMSYNC=1` and re-applies four WPF settings (`DisableAutomationPeer`, `PurgeAutomationEvents`, `DisableStylusInput`, `DisableTabletDevices`) every time it starts, since MTGO updates reset them. These stop the collection view from pinning a CPU core.

### Sound is off

Sound is turned off by default, following the Lutris MTGO installer. Sound hasn't been tested with this setup. To turn it on: `WINEPREFIX=~/.wine-mtgo-arm64 ~/.mtgo-arm64/winetricks sound=coreaudio`

## Why the .NET repair step exists

Under ARM64 Wine, Microsoft's .NET installers report success but skip every file that belongs in `system32` and `syswow64`. Without those files:

- `mscoree.dll` is missing, so no .NET program can start.
- `dfshim.dll` is missing. That's the ClickOnce handler MTGO installs through, so `rundll32` falls back to Wine's stub, which has no install function and does nothing. Meanwhile MTGO's own `setup.exe` just opens the install manifest as XML in Wine's Internet Explorer.
- The CLR's private C runtimes (`*_clr0400.dll`) are missing.

The installer extracts all 20 files from `netfx_Core.mzz` (.NET 4.0) and `netfx_Full.mzz` (.NET 4.8), copies them in, sets `dfshim` to native, and launches MTGO with `rundll32 dfshim.dll,ShOpenVerbApplication <MTGO.application URL>`.

## Troubleshooting

- **Install log:** `~/.mtgo-arm64/install.log`. **Game log:** `~/.mtgo-arm64/mtgo.log`.
- **Recording a problem:** `bash tools/debug-session.sh` restarts MTGO with Wine error and Mac-driver tracing on. Press Return in Terminal each time the problem happens, then type `q` when you're done. It prints a summary of CPU load and window events around each mark, and copies it to the clipboard. Logs can reach a few hundred MB; delete them with `rm -rf ~/.mtgo-arm64/debug`.
- **"macOS cannot verify MetalSharp-Wine":** System Settings → Privacy & Security → Open Anyway.

## Uninstall

```bash
bash uninstall.sh
```

This removes `~/.wine-mtgo-arm64`, `~/.mtgo-arm64`, `~/Applications/MTGO.app` and `~/Applications/MetalSharp-Wine.app`.

## Credits

- [MetalSharp-Wine](https://github.com/metalsharp/MetalSharp-Wine): arm64 Wine with FEX-Emu
- [winetricks](https://github.com/Winetricks/winetricks)
- [pauleve/docker-mtgo](https://github.com/pauleve/docker-mtgo) and the [Lutris MTGO installer](https://lutris.net/games/install/39999/view), for MTGO-under-Wine groundwork and the WPF config settings

## License

MIT. See [LICENSE](LICENSE).
