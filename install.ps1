# install.ps1 - Kryptex Screen Auto-Sleep Companion Installer & Updater
# Target Directory: %LOCALAPPDATA%\KryptexAutoSleep
param(
    [string]$SourceUrl = "https://raw.githubusercontent.com/IAndrexI/kryptexsleep/main/KryptexOverlay.ps1"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     Kryptex Screen Auto-Sleep Companion Setup & Update   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$targetDir = "$env:LOCALAPPDATA\KryptexAutoSleep"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# 1. Stop any running instances first
Write-Host "[1/5] Stopping any existing instances..." -ForegroundColor Yellow
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | 
        Where-Object { $_.CommandLine -like '*KryptexOverlay.ps1*' -or $_.CommandLine -like '*KryptexAutoSleep.ps1*' } | 
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 600
} catch {}

# 2. Download / Update KryptexOverlay.ps1
$overlayPath = Join-Path $targetDir "KryptexOverlay.ps1"
Write-Host "[2/5] Fetching latest Kryptex Companion from GitHub..." -ForegroundColor Yellow

$downloadOk = $false
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    Invoke-WebRequest -Uri $SourceUrl -OutFile $overlayPath -UseBasicParsing
    if ((Get-Item $overlayPath).Length -gt 1000) {
        $downloadOk = $true
        Write-Host "      Successfully updated KryptexOverlay.ps1." -ForegroundColor Green
    }
} catch {
    Write-Host "      Could not download from online URL ($($_.Exception.Message))." -ForegroundColor DarkYellow
}

# Fallback: if running from a local folder that already has KryptexOverlay.ps1
if (-not $downloadOk) {
    $localOverlay = Join-Path $PSScriptRoot "KryptexOverlay.ps1"
    if (Test-Path $localOverlay) {
        Copy-Item -Path $localOverlay -Destination $overlayPath -Force
        Write-Host "      Copied KryptexOverlay.ps1 from local source." -ForegroundColor Green
    } elseif (-not (Test-Path $overlayPath)) {
        Write-Error "Failed to install: could not download or find KryptexOverlay.ps1."
        return
    }
}

# 3. Create run-overlay.vbs (for silent windowless background launch)
Write-Host "[3/5] Setting up silent background launcher..." -ForegroundColor Yellow
$vbsContent = @"
Set FSO = CreateObject("Scripting.FileSystemObject")
ScriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = ScriptDir
psPath = WshShell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
cmd = """" & psPath & """ -NoProfile -ExecutionPolicy Bypass -STA -File """ & ScriptDir & "\KryptexOverlay.ps1"""
WshShell.Run cmd, 0, False
"@
Set-Content -Path (Join-Path $targetDir "run-overlay.vbs") -Value $vbsContent -Encoding ASCII

# 4. Create start.bat and stop.bat in target folder
$startBat = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { `$_.CommandLine -like '*KryptexOverlay.ps1*' } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force }"
timeout /t 1 >nul 2>&1
start "" "%SystemRoot%\System32\wscript.exe" "%~dp0run-overlay.vbs"
"@
Set-Content -Path (Join-Path $targetDir "start.bat") -Value $startBat -Encoding ASCII

$stopBat = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { `$_.CommandLine -like '*KryptexOverlay.ps1*' } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force }"
echo [SUCCESS] Kryptex Companion stopped.
"@
Set-Content -Path (Join-Path $targetDir "stop.bat") -Value $stopBat -Encoding ASCII

# 5. Add to Windows Startup folder
Write-Host "[4/5] Registering Windows Startup shortcut..." -ForegroundColor Yellow
$startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$shortcutPath = Join-Path $startupFolder "Kryptex-AutoSleep.lnk"
try {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($shortcutPath)
    $sc.TargetPath = "wscript.exe"
    $sc.Arguments = "`"$targetDir\run-overlay.vbs`""
    $sc.WorkingDirectory = $targetDir
    $sc.Description = "Kryptex Screen Auto-Sleep Companion"
    $sc.Save()
    Write-Host "      Startup shortcut created." -ForegroundColor Green
} catch {
    Write-Warning "Could not register startup shortcut: $($_.Exception.Message)"
}

# 6. Launch the companion right now
Write-Host "[5/5] Starting Kryptex Companion now..." -ForegroundColor Yellow
Start-Process -FilePath "wscript.exe" -ArgumentList "`"$targetDir\run-overlay.vbs`"" -WorkingDirectory $targetDir

Write-Host "`n[SUCCESS] Kryptex Companion is installed & active!" -ForegroundColor Green
Write-Host "Installation path: $targetDir" -ForegroundColor Cyan
Write-Host "To update anytime in the future, just re-run this exact same command!`n" -ForegroundColor Green
