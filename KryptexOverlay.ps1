# KryptexOverlay.ps1
# Bound Kryptex Screen Auto-Sleep Companion
# - Native 250 FPS C# window tracking thread (moves instantaneously as fast as Kryptex is dragged)
# - Positioned 235px left of right border so Minimize, Maximize, and Close buttons remain 100% visible
# - Automatically hides when a different window is on top, when Kryptex is minimized, or when Kryptex is closed
# - Auto-switches to interactive WinSta0\Default desktop if launched from an isolated session
# - DPMS Display standby (monitors sleep, GPUs continue mining at 100% capacity)
# - Real-idle detection: filtered mouse cursor displacement (> 8px) & physical keystrokes
# - Global hotkeys: [Win + Shift + L] and [Ctrl + Alt + L]
# - Windows Lock detection: automatically sleeps screens on Win+L (SessionSwitch)

$script:baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:baseDir) { $script:baseDir = "E:\AI\KryptexAutoSleep" }
$script:logPath = Join-Path $script:baseDir "activity.log"
$script:configPath = Join-Path $script:baseDir "config.json"

function Write-Log ($msg) {
    $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$time] $msg"
    Add-Content -Path $script:logPath -Value $entry -ErrorAction SilentlyContinue
    try {
        if ((Get-Item $script:logPath -ErrorAction SilentlyContinue).Length -gt 500KB) {
            $lines = Get-Content $script:logPath -Tail 500
            Set-Content -Path $script:logPath -Value $lines
        }
    } catch {}
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'Win32KryptexBoundV6').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class Win32KryptexBoundV6 {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessW(
        string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes,
        bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("user32.dll")] public static extern IntPtr GetThreadDesktop(int dwThreadId);
    [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool GetUserObjectInformation(IntPtr hObj, int nIndex, StringBuilder pvInfo, int nLength, out int lpnLengthNeeded);

    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    [DllImport("user32.dll")] public static extern IntPtr DefWindowProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool LockWorkStation();
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumDesktopWindows(IntPtr hDesktop, EnumWindowsProc enumProc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr hDesktop);

    public static string GetCurrentDesktopName() {
        IntPtr hdesk = GetThreadDesktop(GetCurrentThreadId());
        StringBuilder dname = new StringBuilder(256);
        int needed;
        GetUserObjectInformation(hdesk, 2, dname, 256, out needed);
        return dname.ToString();
    }

    public static int RelaunchOnDefaultDesktop(string scriptPath, string workDir) {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.lpDesktop = "Winsta0\\Default";
        si.dwFlags = 1;
        si.wShowWindow = 0;

        string cmdLine = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File \"" + scriptPath + "\"";
        PROCESS_INFORMATION pi;
        bool ok = CreateProcessW(null, cmdLine, IntPtr.Zero, IntPtr.Zero, false, 0x08000000, IntPtr.Zero, workDir, ref si, out pi);
        if (!ok) return -Marshal.GetLastWin32Error();
        return pi.dwProcessId;
    }

    private static int lastX = -1, lastY = -1;
    private static long lastActivityTick = 0;
    private static long ignoreInputUntilTick = 0;

    public static void ResetActivity() {
        lastActivityTick = Environment.TickCount;
        POINT pt;
        if (GetCursorPos(out pt)) {
            lastX = pt.x;
            lastY = pt.y;
        }
    }

    public static void SetInputIgnorePeriod(int milliseconds) {
        ignoreInputUntilTick = Environment.TickCount + milliseconds;
        POINT pt;
        if (GetCursorPos(out pt)) {
            lastX = pt.x;
            lastY = pt.y;
        }
    }

    public static bool CheckForUserInput() {
        long now = Environment.TickCount;
        if (lastActivityTick == 0) lastActivityTick = now;

        POINT pt;
        if (GetCursorPos(out pt)) {
            // If we are in the input ignore period, continuously update baseline cursor coords
            // so residual movement/releases after clicking Sleep Now are completely swallowed
            if (now < ignoreInputUntilTick) {
                lastX = pt.x;
                lastY = pt.y;
                return false;
            }

            if (lastX != -1) {
                int dx = Math.Abs(pt.x - lastX);
                int dy = Math.Abs(pt.y - lastY);
                // Require intentional physical mouse movement (> 8px) rather than 2px micro-jitters
                if (dx > 8 || dy > 8) {
                    lastActivityTick = now;
                    lastX = pt.x;
                    lastY = pt.y;
                    return true;
                }
            }
            lastX = pt.x;
            lastY = pt.y;
        } else if (now < ignoreInputUntilTick) {
            return false;
        }

        // Mouse buttons: left (1), right (2), middle (4)
        if ((GetAsyncKeyState(1) & 0x8000) != 0 || 
            (GetAsyncKeyState(2) & 0x8000) != 0 || 
            (GetAsyncKeyState(4) & 0x8000) != 0) {
            lastActivityTick = now;
            return true;
        }

        // Keyboard keys (VK 8 to 222) - skip modifier keys (Shift, Ctrl, Alt, Win)
        // so releasing hotkeys like Ctrl, Alt, Win, Shift does NOT trigger an immediate wake
        for (int k = 8; k <= 222; k++) {
            if (k == 16 || k == 17 || k == 18 || k == 91 || k == 92 || k == 160 || k == 161 || k == 162 || k == 163 || k == 164 || k == 165) {
                continue;
            }
            if ((GetAsyncKeyState(k) & 0x8000) != 0) {
                lastActivityTick = now;
                return true;
            }
        }

        return false;
    }

    public static int GetIdleSeconds() {
        CheckForUserInput();
        long now = Environment.TickCount;
        long diff = now - lastActivityTick;
        if (diff < 0) { lastActivityTick = now; return 0; }
        return (int)(diff / 1000);
    }

    public static volatile bool ScreenSleeping = false;

    public static void TurnScreenOff(IntPtr ourHwnd) {
        ScreenSleeping = true;
        SetInputIgnorePeriod(2500);

        // Turn screen off using HWND_BROADCAST (0xFFFF) via PostMessage.
        // PostMessage is asynchronous (does not block the thread) and powers down all connected displays cleanly.
        PostMessage((IntPtr)0xFFFF, 0x0112, (IntPtr)0xF170, (IntPtr)2);
    }

    private static readonly Guid CLSID_MMDeviceEnumerator = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
    private static readonly Guid IID_IAudioSessionManager2 = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IntPtr ppDevices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionManager2 {
        [PreserveSig] int NotImpl1();
        [PreserveSig] int NotImpl2();
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
    }

    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionEnumerator {
        [PreserveSig] int GetCount(out int sessionCount);
        [PreserveSig] int GetSession(int sessionIndex, out IAudioSessionControl session);
    }

    [Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionControl {
        [PreserveSig] int GetState(out int pRetVal);
    }

    [Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionControl2 {
        [PreserveSig] int GetState(out int pRetVal);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string value, [MarshalAs(UnmanagedType.LPStruct)] Guid eventContext);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string value, [MarshalAs(UnmanagedType.LPStruct)] Guid eventContext);
        [PreserveSig] int GetGroupingParam(out Guid pRetVal);
        [PreserveSig] int SetGroupingParam([MarshalAs(UnmanagedType.LPStruct)] Guid overrideVal, [MarshalAs(UnmanagedType.LPStruct)] Guid eventContext);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);

        [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
        [PreserveSig] int GetProcessId(out uint pRetVal);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference(bool optOut);
    }

    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioMeterInformation {
        [PreserveSig] int GetPeakValue(out float pfPeak);
    }

    public static bool IsBrowserAudioAudible(out string activeApp) {
        activeApp = "";
        try {
            Type t = Type.GetTypeFromCLSID(CLSID_MMDeviceEnumerator, true);
            var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(t);
            IMMDevice dev;
            if (enumerator.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null) return false;

            Guid iid = IID_IAudioSessionManager2;
            object o;
            if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0 || o == null) {
                Marshal.ReleaseComObject(dev);
                return false;
            }

            var mgr = (IAudioSessionManager2)o;
            IAudioSessionEnumerator se;
            if (mgr.GetSessionEnumerator(out se) != 0 || se == null) {
                Marshal.ReleaseComObject(mgr);
                Marshal.ReleaseComObject(dev);
                return false;
            }

            int count;
            se.GetCount(out count);
            bool isPlaying = false;

            for (int i = 0; i < count; i++) {
                IAudioSessionControl ctl;
                if (se.GetSession(i, out ctl) == 0 && ctl != null) {
                    int state = 0;
                    ctl.GetState(out state);
                    // 1 = AudioSessionStateActive
                    if (state == 1) {
                        uint pid = 0;
                        var ctl2 = ctl as IAudioSessionControl2;
                        if (ctl2 != null) ctl2.GetProcessId(out pid);

                        float peak = 0.0f;
                        var meter = ctl as IAudioMeterInformation;
                        if (meter != null) meter.GetPeakValue(out peak);

                        if (pid > 0) {
                            try {
                                var p = Process.GetProcessById((int)pid);
                                string pName = p.ProcessName.ToLower();
                                if (pName.Contains("chrome") || pName.Contains("vivaldi") || pName.Contains("msedge") || 
                                    pName.Contains("firefox") || pName.Contains("brave") || pName.Contains("opera") ||
                                    pName.Contains("spotify") || pName.Contains("vlc") || pName.Contains("mpc-hc") ||
                                    pName.Contains("wmplayer")) {
                                    if (peak > 0.0005f) {
                                        activeApp = string.Format("{0} (Peak: {1:P1})", p.ProcessName, peak);
                                        isPlaying = true;
                                    }
                                }
                            } catch {}
                        }
                    }
                    Marshal.ReleaseComObject(ctl);
                    if (isPlaying) break;
                }
            }

            Marshal.ReleaseComObject(se);
            Marshal.ReleaseComObject(mgr);
            Marshal.ReleaseComObject(dev);
            return isPlaying;
        } catch (Exception ex) {
            activeApp = "Error: " + ex.Message;
            return false;
        }
    }

    public static IntPtr FindKryptex() {
        IntPtr visibleMatch = IntPtr.Zero;
        IntPtr anyMatch = IntPtr.Zero;

        EnumWindowsProc proc = (hWnd, lParam) => {
            if (!IsWindow(hWnd)) return true;
            StringBuilder cls = new StringBuilder(64);
            GetClassName(hWnd, cls, 64);
            if (cls.ToString() == "Chrome_WidgetWin_1") {
                StringBuilder title = new StringBuilder(128);
                GetWindowText(hWnd, title, 128);
                string t = title.ToString();
                if (t == "Kryptex") {
                    if (IsWindowVisible(hWnd) && !IsIconic(hWnd)) {
                        visibleMatch = hWnd;
                        return false;
                    }
                    if (anyMatch == IntPtr.Zero) {
                        anyMatch = hWnd;
                    }
                }
            }
            return true;
        };

        EnumWindows(proc, IntPtr.Zero);
        if (visibleMatch != IntPtr.Zero) return visibleMatch;

        IntPtr hDesk = OpenDesktop("Default", 0, false, 0x01FF);
        if (hDesk != IntPtr.Zero) {
            EnumDesktopWindows(hDesk, proc, IntPtr.Zero);
            CloseDesktop(hDesk);
        }

        return (visibleMatch != IntPtr.Zero) ? visibleMatch : anyMatch;
    }

    private static Thread trackerThread;
    private static volatile bool trackerRunning = false;

    public static void StartNativeTracker(IntPtr ourHwnd) {
        if (trackerRunning) return;
        trackerRunning = true;
        trackerThread = new Thread(() => {
            IntPtr cachedKryp = IntPtr.Zero;
            int lastSearchTick = 0;
            int lastPosX = -99999, lastPosY = -99999;
            bool wasShown = false;

            while (trackerRunning) {
                try {
                    // Pause window tracking & DWM updates while monitors are sleeping so DWM doesn't wake/flash displays
                    if (ScreenSleeping) {
                        Thread.Sleep(250);
                        continue;
                    }

                    int now = Environment.TickCount;
                    if (cachedKryp == IntPtr.Zero || !IsWindow(cachedKryp) || (now - lastSearchTick) > 500) {
                        cachedKryp = FindKryptex();
                        lastSearchTick = now;
                    }

                    bool shouldShow = false;
                    int targetX = 0, targetY = 0;

                    if (cachedKryp != IntPtr.Zero && IsWindowVisible(cachedKryp) && !IsIconic(cachedKryp)) {
                        IntPtr fg = GetForegroundWindow();
                        // Only show when Kryptex or our companion bar is the active foreground window
                        if (fg == cachedKryp || fg == ourHwnd) {
                            RECT r;
                            if (GetWindowRect(cachedKryp, out r)) {
                                int kw = r.Right - r.Left;
                                int kh = r.Bottom - r.Top;
                                if (kw > 200 && kh > 100) {
                                    RECT ourR;
                                    GetWindowRect(ourHwnd, out ourR);
                                    int ourW = ourR.Right - ourR.Left;
                                    if (ourW <= 50) ourW = 425;

                                    int clearance = 235; // Default profile for 150% DPI (e.g. ANDREX workstation)
                                    string host = Environment.MachineName;
                                    if (!string.Equals(host, "ANDREX", StringComparison.OrdinalIgnoreCase)) {
                                        // Dynamic DPI adaptation for friends' PCs
                                        uint dpi = GetDpiForWindow(cachedKryp);
                                        if (dpi == 0) dpi = GetDpiForWindow(ourHwnd);
                                        if (dpi == 0) dpi = 96;
                                        double scale = dpi / 96.0;
                                        // Standard Windows caption buttons (Minimize, Maximize, Close) take ~140px at 100% DPI + margin
                                        clearance = (int)(155 * scale);
                                    }

                                    targetX = r.Right - ourW - clearance;
                                    targetY = (r.Top >= -2000) ? (r.Top + 6) : 6;
                                    shouldShow = true;
                                }
                            }
                        }
                    }

                    if (shouldShow) {
                        if (!wasShown || targetX != lastPosX || targetY != lastPosY) {
                            // HWND_TOPMOST = -1, SWP_NOSIZE (0x0001) | SWP_NOACTIVATE (0x0010) | SWP_SHOWWINDOW (0x0040) | SWP_ASYNCWINDOWPOS (0x4000) = 0x4051
                            SetWindowPos(ourHwnd, (IntPtr)(-1), targetX, targetY, 0, 0, 0x4051);
                            lastPosX = targetX;
                            lastPosY = targetY;
                            wasShown = true;
                        }
                    } else {
                        if (wasShown || IsWindowVisible(ourHwnd)) {
                            ShowWindow(ourHwnd, 0); // SW_HIDE
                            wasShown = false;
                        }
                    }
                } catch {}
                Thread.Sleep(4); // ~250 FPS native tracking
            }
        });
        trackerThread.IsBackground = true;
        trackerThread.Start();
    }

    public static void StopNativeTracker() {
        trackerRunning = false;
    }
}
'@
    }

    $curDesk = [Win32KryptexBoundV6]::GetCurrentDesktopName()
    if ($curDesk -and ($curDesk -ne "Default")) {
        $newPid = [Win32KryptexBoundV6]::RelaunchOnDefaultDesktop($MyInvocation.MyCommand.Path, $script:baseDir)
        Write-Log "Relaunched from isolated desktop '$curDesk' onto Winsta0\Default (PID: $newPid)."
        if ($newPid -gt 0) {
            try {
                $childProc = [System.Diagnostics.Process]::GetProcessById($newPid)
                $childProc.WaitForExit()
            } catch {}
        }
        exit 0
    }

    Write-Log "Kryptex Companion Option Service Starting on desktop '$curDesk'..."

    [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime] | Out-Null
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $script:asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' 
    })[0]

    function Invoke-WinRTAwait($WinRtTask, $ResultType) {
        if (-not $script:asTaskGeneric -or -not $WinRtTask) { return $null }
        $asTask = $script:asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(400) | Out-Null
        return $netTask.Result
    }

    function Test-IsVideoOrAudioPlaying {
        # 1. Check Windows System Media Transport Controls (YouTube / browser media sessions)
        try {
            $sessionManagerAsync = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
            $sessionManager = Invoke-WinRTAwait $sessionManagerAsync ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
            if ($sessionManager) {
                $sessions = $sessionManager.GetSessions()
                foreach ($s in $sessions) {
                    $pb = $s.GetPlaybackInfo()
                    # PlaybackStatus 4 = Playing
                    if ($pb -and $pb.PlaybackStatus -eq 4) {
                        return @{ IsPlaying = $true; Source = "Video/Media: $($s.SourceAppUserModelId)" }
                    }
                }
            }
        } catch {}

        # 2. Check Core Audio WASAPI Peak metering for browsers (Vivaldi, Chrome, Edge, Firefox, Brave, etc.)
        try {
            $activeApp = ""
            if ([Win32KryptexBoundV6]::IsBrowserAudioAudible([ref]$activeApp)) {
                return @{ IsPlaying = $true; Source = "Browser Audio: $activeApp" }
            }
        } catch {}

        return @{ IsPlaying = $false; Source = "" }
    }

    function Parse-TimeString ($text) {
        if (-not $text) { return $null }
        $clean = $text.Trim().ToLower()
        if ($clean -match '^(\d+)\s*(s|sec|secs|second|seconds)$') {
            $val = [int]$matches[1]
            if ($val -gt 0) { return @{ Seconds = $val; Formatted = "$val sec" } }
        }
        elseif ($clean -match '^(\d+)\s*(m|min|mins|minute|minutes)$') {
            $val = [int]$matches[1]
            if ($val -gt 0) { return @{ Seconds = ($val * 60); Formatted = "$val min" } }
        }
        elseif ($clean -match '^(\d+)$') {
            $val = [int]$matches[1]
            if ($val -gt 0) { return @{ Seconds = ($val * 60); Formatted = "$val min" } }
        }
        return $null
    }

    $script:autoSleepEnabled = $true
    $script:timeInputText = "20 min"
    $script:idleThresholdSeconds = 1200

    if (Test-Path $script:configPath) {
        try {
            $cfg = Get-Content $script:configPath -Raw | ConvertFrom-Json
            if ($cfg.timeText) { $script:timeInputText = $cfg.timeText }
            if ($cfg.seconds) { $script:idleThresholdSeconds = [int]$cfg.seconds }
            if ($cfg.PSObject.Properties['autoSleepEnabled']) { $script:autoSleepEnabled = [bool]$cfg.autoSleepEnabled }
        } catch {}
    }

    function Save-Config {
        try {
            @{
                timeText = $script:timeInputText
                seconds = $script:idleThresholdSeconds
                autoSleepEnabled = $script:autoSleepEnabled
            } | ConvertTo-Json | Set-Content -Path $script:configPath -Force
        } catch {}
    }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kryptex Screen Sleep Option"
        Height="26" Width="275"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" ResizeMode="NoResize" Topmost="True">
    <Border Background="#15171F" CornerRadius="4" BorderBrush="#00E676" BorderThickness="1.2" Margin="0">
        <Border.Effect>
            <DropShadowEffect BlurRadius="6" ShadowDepth="1" Opacity="0.45" Color="#000000"/>
        </Border.Effect>
        <Grid Margin="6,0" VerticalAlignment="Center">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/> <!-- Status Dot -->
                <ColumnDefinition Width="Auto"/> <!-- Label -->
                <ColumnDefinition Width="Auto"/> <!-- Timeout input -->
                <ColumnDefinition Width="*"/>    <!-- Spacer -->
                <ColumnDefinition Width="Auto"/> <!-- Toggle Button -->
                <ColumnDefinition Width="Auto"/> <!-- Sleep Now -->
            </Grid.ColumnDefinitions>

            <!-- Status Dot -->
            <Ellipse x:Name="StatusDot" Grid.Column="0" Width="7" Height="7" Fill="#00E676" Margin="0,0,5,0" VerticalAlignment="Center" ToolTip="Screen Auto-Sleep Status"/>

            <!-- Option Label -->
            <TextBlock Grid.Column="1" Text="Sleep:" Foreground="#A0A5B5" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,5,0"/>

            <!-- Timeout Input Box (Click to edit, Enter to save) -->
            <TextBox x:Name="TimeInput" Grid.Column="2" Text="20 min" Width="50" Height="18"
                     Background="#0D0F14" Foreground="#00E676" FontWeight="SemiBold" FontSize="10.5"
                     BorderBrush="#252936" BorderThickness="1" VerticalContentAlignment="Center"
                     HorizontalContentAlignment="Center" VerticalAlignment="Center"
                     ToolTip="Idle timeout (e.g. '20 min', '15m', '45 sec'). Click to edit, Enter to save.">
                <TextBox.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="3"/>
                    </Style>
                </TextBox.Resources>
            </TextBox>

            <!-- Auto Sleep Toggle Button -->
            <Button x:Name="ToggleBtn" Grid.Column="4" Content="Auto Sleep" Margin="5,0,3,0" Padding="7,1" Height="19"
                    Background="#00C853" Foreground="#FFFFFF" FontWeight="Bold" FontSize="10" BorderThickness="0" Cursor="Hand"
                    ToolTip="Toggle automatic monitor standby while mining ON or OFF">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="3"/>
                    </Style>
                </Button.Resources>
            </Button>

            <!-- Sleep Now Button -->
            <Button x:Name="SleepNowBtn" Grid.Column="5" Content="Sleep Now" Margin="2,0,0,0" Padding="7,1" Height="19"
                    Background="#242834" Foreground="#D0D4E0" FontSize="10" BorderThickness="0" Cursor="Hand"
                    ToolTip="Shut off monitors immediately (Win+Shift+L)">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="3"/>
                    </Style>
                </Button.Resources>
            </Button>
        </Grid>
    </Border>
</Window>
"@

    [System.Xml.XmlReader]$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $script:window = [System.Windows.Markup.XamlReader]::Load($reader)

    $script:statusDot = $script:window.FindName("StatusDot")
    $script:timeInput = $script:window.FindName("TimeInput")
    $script:toggleBtn = $script:window.FindName("ToggleBtn")
    $script:sleepNowBtn = $script:window.FindName("SleepNowBtn")

    $script:timeInput.Text = $script:timeInputText

    function Update-UIState {
        if ($script:autoSleepEnabled) {
            $script:toggleBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00C853")
            $script:toggleBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
            $script:statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00E676")
        } else {
            $script:toggleBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#343744")
            $script:toggleBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#84899A")
            $script:statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5A5E70")
        }
    }
    Update-UIState

    $script:isScreenOff = $false
    $script:wakeGraceUntilTick = 0
    $script:lastIdleCheck = 0

    $script:minerProcesses = @(
        'kryptex_*',
        'Kryptex',
        'xmrig*',
        'nbminer*',
        'gminer*',
        'lolminer*',
        't-rex*',
        'rigel*',
        'srbminer*',
        'teamredminer*'
    )

    $script:applyTimeChange = {
        $parsed = Parse-TimeString $script:timeInput.Text
        if ($parsed) {
            $script:idleThresholdSeconds = $parsed.Seconds
            $script:timeInputText = $parsed.Formatted
            $script:timeInput.Text = $parsed.Formatted
            $script:timeInput.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00E676")
            Write-Log "Idle timeout updated to $($parsed.Formatted) ($($parsed.Seconds)s)."
            Save-Config
        } else {
            $script:timeInput.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF5252")
            $script:timeInput.Text = $script:timeInputText
        }
    }

    $script:timeInput.Add_GotFocus({
        $script:timeInput.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00E676")
        $script:timeInput.SelectAll()
    })

    $script:timeInput.Add_LostFocus({
        & $script:applyTimeChange
        $script:timeInput.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#252936")
    })

    $script:timeInput.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter -or $e.Key -eq [System.Windows.Input.Key]::Return) {
            & $script:applyTimeChange
            [System.Windows.Input.Keyboard]::ClearFocus()
            $e.Handled = $true
        }
    })

    $script:toggleBtn.Add_Click({
        $script:autoSleepEnabled = -not $script:autoSleepEnabled
        Update-UIState
        if ($script:autoSleepEnabled) {
            Write-Log "User enabled Auto Sleep."
        } else {
            Write-Log "User disabled Auto Sleep."
        }
        Save-Config
    })

    $script:executeScreenOff = {
        param([string]$reason, [bool]$lockWorkstation = $false)
        Write-Log "$reason. Turning screen off."
        $script:isScreenOff = $true
        [Win32KryptexBoundV6]::ScreenSleeping = $true
        [Win32KryptexBoundV6]::SetInputIgnorePeriod(2500)
        if ($lockWorkstation) {
            try { [Win32KryptexBoundV6]::LockWorkStation() | Out-Null } catch {}
        }
        [Win32KryptexBoundV6]::TurnScreenOff($script:ourHwnd)
    }

    $script:sleepNowBtn.Add_Click({
        & $script:executeScreenOff "User clicked [Sleep Now]" $false
    })

    $script:helper = New-Object System.Windows.Interop.WindowInteropHelper($script:window)
    $script:ourHwnd = $script:helper.EnsureHandle()
    $script:source = [System.Windows.Interop.HwndSource]::FromHwnd($script:ourHwnd)

    [Win32KryptexBoundV6]::RegisterHotKey($script:ourHwnd, 1, 0x000C, 0x4C) | Out-Null # Win+Shift+L
    [Win32KryptexBoundV6]::RegisterHotKey($script:ourHwnd, 2, 0x0003, 0x4C) | Out-Null # Ctrl+Alt+L
    Write-Log "Hotkeys registered successfully (Win+Shift+L, Ctrl+Alt+L)."

    # Listen for Windows Session Lock (e.g. Win+L, Start Menu Lock, LockWorkStation)
    $script:sessionSwitchHandler = [Microsoft.Win32.SessionSwitchEventHandler]{
        param($s, $e)
        if ($e.Reason -eq [Microsoft.Win32.SessionSwitchReason]::SessionLock) {
            Write-Log "Windows session locked (Win+L / SessionLock). Turning screen off."
            $script:isScreenOff = $true
            [Win32KryptexBoundV6]::ScreenSleeping = $true
            [Win32KryptexBoundV6]::SetInputIgnorePeriod(3000)
            [Win32KryptexBoundV6]::TurnScreenOff($script:ourHwnd)
        }
    }
    [Microsoft.Win32.SystemEvents]::add_SessionSwitch($script:sessionSwitchHandler)

    $script:source.AddHook({
        param($hwnd, $msg, $wParam, $lParam, [ref]$handled)
        if ($msg -eq 0x0312) { # WM_HOTKEY
            $hotkeyId = [int]$wParam
            if ($hotkeyId -eq 2) {
                # Ctrl+Alt+L pressed
                & $script:executeScreenOff "Hotkey pressed [Ctrl+Alt+L]" $false
            } else {
                # Win+Shift+L pressed
                & $script:executeScreenOff "Hotkey pressed [Win+Shift+L]" $false
            }
            $handled = $true
        }
    })

    $script:window.Add_Closed({
        try { [Microsoft.Win32.SystemEvents]::remove_SessionSwitch($script:sessionSwitchHandler) } catch {}
        [Win32KryptexBoundV6]::StopNativeTracker()
        [Win32KryptexBoundV6]::UnregisterHotKey($script:ourHwnd, 1) | Out-Null
        [Win32KryptexBoundV6]::UnregisterHotKey($script:ourHwnd, 2) | Out-Null
        Write-Log "Kryptex Companion Exited."
    })

    # Start dedicated 250 FPS C# window tracker thread
    [Win32KryptexBoundV6]::StartNativeTracker($script:ourHwnd)

    # Idle & DPMS timer (lightweight check every 250ms)
    $script:timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:timer.Interval = [TimeSpan]::FromMilliseconds(250)

    $script:lastVideoPlayingLog = 0

    $script:timer.Add_Tick({
        try {
            $now = [Environment]::TickCount
            $userInput = [Win32KryptexBoundV6]::CheckForUserInput()

            if ($userInput) {
                if ($script:isScreenOff) {
                    Write-Log "User input detected (mouse or key). Resuming display."
                    $script:isScreenOff = $false
                    [Win32KryptexBoundV6]::ScreenSleeping = $false
                    $script:wakeGraceUntilTick = $now + 15000
                }
            }

            if (-not $script:isScreenOff -and $script:autoSleepEnabled -and ($now -gt $script:wakeGraceUntilTick)) {
                if (($now - $script:lastIdleCheck) -ge 2000 -or ($now - $script:lastIdleCheck) -lt 0) {
                    $script:lastIdleCheck = $now

                    $miners = Get-Process -Name $script:minerProcesses -ErrorAction SilentlyContinue
                    if ($miners) {
                        $idleSec = [Win32KryptexBoundV6]::GetIdleSeconds()

                        if ($idleSec -ge $script:idleThresholdSeconds) {
                            # Verify whether a video (YouTube, browser video/audio) is currently playing
                            $videoStatus = Test-IsVideoOrAudioPlaying
                            if ($videoStatus.IsPlaying) {
                                # Prevent auto-sleep while YouTube/video is playing; reset activity tick so user is not interrupted
                                [Win32KryptexBoundV6]::ResetActivity()
                                if (($now - $script:lastVideoPlayingLog) -gt 60000 -or ($now - $script:lastVideoPlayingLog) -lt 0) {
                                    Write-Log "Idle threshold reached ($($script:idleThresholdSeconds)s), but sleep deferred because $($videoStatus.Source) is active."
                                    $script:lastVideoPlayingLog = $now
                                }
                            } else {
                                Write-Log "Idle threshold ($($script:idleThresholdSeconds)s) reached while mining. Turning screen off once."
                                $script:isScreenOff = $true
                                [Win32KryptexBoundV6]::ScreenSleeping = $true
                                [Win32KryptexBoundV6]::TurnScreenOff($script:ourHwnd)
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Log "IDLE TICK ERROR: $($_.Exception.Message)"
        }
    })

    $script:app = New-Object System.Windows.Application
    $script:app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

    $script:window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $script:window.Left = -32000
    $script:window.Top = -32000

    $script:timer.Start()

    $script:app.Run($script:window) | Out-Null
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
}
