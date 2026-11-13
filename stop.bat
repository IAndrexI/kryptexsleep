@echo off
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*KryptexOverlay.ps1*' -or $_.CommandLine -like '*KryptexAutoSleep.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo [SUCCESS] Kryptex Companion stopped.
powershell -NoProfile -Command "Start-Sleep -Seconds 1"
