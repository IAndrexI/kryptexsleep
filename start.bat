@echo off
setlocal
cd /d "%~dp0"
echo Stopping any running Kryptex Companion instances...
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*KryptexOverlay.ps1*' -or $_.CommandLine -like '*KryptexAutoSleep.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
powershell -NoProfile -Command "Start-Sleep -Milliseconds 600"
start "" "%SystemRoot%\System32\wscript.exe" "%~dp0run-overlay.vbs"
echo [SUCCESS] Kryptex Companion Option started in background.
timeout /t 2 >nul 2>&1
