@echo off
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "SHORTCUT_PATH=%STARTUP_DIR%\Kryptex-AutoSleep.lnk"

if exist "%SHORTCUT_PATH%" (
    del "%SHORTCUT_PATH%"
    echo [SUCCESS] Kryptex Auto Sleep shortcut removed from Windows Startup.
) else (
    echo [INFO] Shortcut was not found in Startup folder.
)
pause
