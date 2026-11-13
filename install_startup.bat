@echo off
setlocal
echo Installing Kryptex Auto Sleep to Windows Startup...

set "TARGET_DIR=%~dp0"
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "SHORTCUT_PATH=%STARTUP_DIR%\Kryptex-AutoSleep.lnk"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut('%SHORTCUT_PATH%'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '\"%TARGET_DIR%run-overlay.vbs\"'; $sc.WorkingDirectory = '%TARGET_DIR:~0,-1%'; $sc.Description = 'Kryptex Companion Option & Auto Sleep'; $sc.Save()"

if exist "%SHORTCUT_PATH%" (
    echo [SUCCESS] Kryptex Auto Sleep added to Windows Startup!
) else (
    echo [ERROR] Failed to create startup shortcut.
)
timeout /t 3 >nul 2>&1
