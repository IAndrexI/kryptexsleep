# Kryptex Screen Auto-Sleep Companion

A lightweight companion bar natively docked to the Kryptex Miner application header.

## 1-Step Command (Install and Update)

To install or update the application, open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/IAndrexI/kryptexsleep/main/install.ps1 | iex
```

Running this exact same command at any time in the future will automatically stop the running instance, pull the newest files, and restart the companion with your saved settings preserved.

---

## Detailed Step-by-Step Installation

If you prefer to perform each step manually:

1. Open PowerShell on your computer.
2. Execute the install script using:
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/IAndrexI/kryptexsleep/main/install.ps1 | Invoke-Expression
   ```
3. The script will automatically:
   - Terminate any older background instances.
   - Create the target folder at `%LOCALAPPDATA%\KryptexAutoSleep`.
   - Download the latest `KryptexOverlay.ps1` script.
   - Configure a silent background launcher (`run-overlay.vbs`).
   - Create a shortcut in your Windows Startup directory (`shell:startup`) so it launches automatically on boot.
   - Start the companion immediately in the background.

---

## Features

- Window Integration:
  - Docks directly into the title bar of the Kryptex Miner window.
  - Automatically minimizes when Kryptex is minimized, restores when restored, and closes when Kryptex is closed.
  - Hides automatically when another application window is focused on top.
  - Positioned with clearance so the Minimize, Maximize, and Close buttons remain completely unobstructed.
  - Smooth 250 FPS native window tracking when dragging Kryptex across monitors.
- Smart Idle and Media Detection:
  - Detects real mouse cursor displacement and physical keyboard activity.
  - Video Playback Guard: Detects active YouTube, browser video, and media player playback via Windows System Media Transport Controls (SMTC) and Core Audio session peak metering to prevent the screen from sleeping while watching videos.
- Monitor Sleep:
  - Uses DPMS power management to put monitors into low-power standby while GPUs continue mining at 100% capacity.
  - Eliminates multi-monitor display flashing via a single directed window procedure call.
- Hotkeys:
  - Press `Win + Shift + L` or `Ctrl + Alt + L` to immediately turn off screens.
