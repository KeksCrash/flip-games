#requires -RunAsAdministrator

# ============================================================
# KURZE OPTIONALE VARIABLEN VOR IEX
#
# $s  = Dauer Maus/Tastatur in Sekunden
# $cs = Controller-Dauer; nicht gesetzt/null = Wert von $s
# $m  = Maus blockieren
# $k  = Tastatur blockieren
# $c  = Sony-Controller blockieren
#
# Beispiele:
# $s=36;irm 'URL'|iex
# $s=36;$cs=15;irm 'URL'|iex
# $s=20;$m=$false;$k=$false;$c=$true;irm 'URL'|iex
#
# Lange alte Variablennamen werden weiterhin übernommen.
# ============================================================

if (-not (Test-Path variable:s)) {
    if (Test-Path variable:seconds) { $s = $seconds } else { $s = 60 }
}
if (-not (Test-Path variable:cs)) {
    if (Test-Path variable:CSeconds) { $cs = $CSeconds }
    elseif (Test-Path variable:controllerSeconds) { $cs = $controllerSeconds }
    else { $cs = $null }
}
if (-not (Test-Path variable:m)) {
    if (Test-Path variable:blockMouse) { $m = $blockMouse } else { $m = $true }
}
if (-not (Test-Path variable:k)) {
    if (Test-Path variable:blockKeyboard) { $k = $blockKeyboard } else { $k = $true }
}
if (-not (Test-Path variable:c)) {
    if (Test-Path variable:blockController) { $c = $blockController } else { $c = $true }
}

$s = [Math]::Max(1, [int]$s)
if ($null -eq $cs -or [string]::IsNullOrWhiteSpace([string]$cs)) {
    $cs = $s
} else {
    $cs = [Math]::Max(1, [int]$cs)
}

$m = [bool]$m
$k = [bool]$k
$c = [bool]$c

$seconds = $s
$CSeconds = $cs
$blockMouse = $m
$blockKeyboard = $k
$blockController = $c

$timeFile = Join-Path $env:TEMP 'input-block-time.txt'
$s | Set-Content -LiteralPath $timeFile -Force

Write-Host "Maus/Tastatur: $s s | Controller: $cs s | M:$m K:$k C:$c"

# ============================================================
# SONY-DUALSHOCK-/DUALSENSE-EINGABEGERÄT SUCHEN
# Nur HID-Gamecontroller; Audio- und Bluetooth-Teilgeräte bleiben aktiv.
# ============================================================

$ps4Controllers = @()

if ($c) {
    $ps4Controllers = @(
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Class -eq 'HIDClass' -and
                $_.InstanceId -match 'VID_054C' -and
                $_.FriendlyName -match 'HID-compliant game controller|HID-konformer Gamecontroller'
            } |
            Sort-Object InstanceId -Unique
    )
}

# ============================================================
# MAUSPOSITION FESTHALTEN
# ============================================================

$mousePositionJob = {
    param(
        [int]$Duration,
        [string]$TimeFile
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $position = [System.Windows.Forms.Cursor]::Position
    $x = $position.X
    $y = $position.Y
    $endTime = (Get-Date).AddSeconds($Duration)

    while ((Get-Date) -lt $endTime) {
        [System.Windows.Forms.Cursor]::Position =
            New-Object System.Drawing.Point($x, $y)

        Start-Sleep -Milliseconds 10
    }
}

# ============================================================
# MAUSEINGABEN BLOCKIEREN
# ============================================================

$mouseHookJob = {
    param([int]$DurationMilliseconds)

    Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class InterceptMouse
{
    private const int WH_MOUSE_LL   = 14;
    private const int WM_MOUSEMOVE  = 0x0200;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP   = 0x0202;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_RBUTTONUP   = 0x0205;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_MBUTTONUP   = 0x0208;
    private const int WM_MOUSEWHEEL  = 0x020A;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_XBUTTONUP   = 0x020C;
    private const int WM_MOUSEHWHEEL = 0x020E;

    private static IntPtr hookID = IntPtr.Zero;
    private static readonly LowLevelMouseProc hookCallback = HookCallback;

    public static void Run(int durationMilliseconds)
    {
        hookID = SetHook(hookCallback);

        if (hookID == IntPtr.Zero)
            throw new InvalidOperationException(
                "Der Maus-Hook konnte nicht installiert werden."
            );

        try
        {
            DateTime end = DateTime.UtcNow.AddMilliseconds(durationMilliseconds);

            while (DateTime.UtcNow < end)
            {
                MSG msg;

                while (PeekMessage(out msg, IntPtr.Zero, 0, 0, 1))
                {
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }

                Thread.Sleep(5);
            }
        }
        finally
        {
            UnhookWindowsHookEx(hookID);
            hookID = IntPtr.Zero;
        }
    }

    private static IntPtr SetHook(LowLevelMouseProc proc)
    {
        using (Process process = Process.GetCurrentProcess())
        using (ProcessModule module = process.MainModule)
        {
            return SetWindowsHookEx(
                WH_MOUSE_LL,
                proc,
                GetModuleHandle(module.ModuleName),
                0
            );
        }
    }

    private delegate IntPtr LowLevelMouseProc(
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    private static IntPtr HookCallback(
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    )
    {
        if (nCode >= 0)
        {
            int message = wParam.ToInt32();

            switch (message)
            {
                case WM_MOUSEMOVE:
                case WM_LBUTTONDOWN:
                case WM_LBUTTONUP:
                case WM_RBUTTONDOWN:
                case WM_RBUTTONUP:
                case WM_MBUTTONDOWN:
                case WM_MBUTTONUP:
                case WM_MOUSEWHEEL:
                case WM_XBUTTONDOWN:
                case WM_XBUTTONUP:
                case WM_MOUSEHWHEEL:
                    return (IntPtr)1;
            }
        }

        return CallNextHookEx(hookID, nCode, wParam, lParam);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int x;
        public int y;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int idHook,
        LowLevelMouseProc lpfn,
        IntPtr hMod,
        uint dwThreadId
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hhk,
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out MSG lpMsg,
        IntPtr hWnd,
        uint wMsgFilterMin,
        uint wMsgFilterMax,
        uint wRemoveMsg
    );

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);
}
"@

    [InterceptMouse]::Run($DurationMilliseconds)
}

# ============================================================
# TASTATUREINGABEN BLOCKIEREN
# ============================================================

$keyboardHookJob = {
    param([int]$DurationMilliseconds)

    Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class InterceptKeyboard
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN     = 0x0100;
    private const int WM_KEYUP       = 0x0101;
    private const int WM_SYSKEYDOWN  = 0x0104;
    private const int WM_SYSKEYUP    = 0x0105;

    private static IntPtr hookID = IntPtr.Zero;
    private static readonly LowLevelKeyboardProc hookCallback = HookCallback;

    public static void Run(int durationMilliseconds)
    {
        hookID = SetHook(hookCallback);

        if (hookID == IntPtr.Zero)
            throw new InvalidOperationException(
                "Der Tastatur-Hook konnte nicht installiert werden."
            );

        try
        {
            DateTime end = DateTime.UtcNow.AddMilliseconds(durationMilliseconds);

            while (DateTime.UtcNow < end)
            {
                MSG msg;

                while (PeekMessage(out msg, IntPtr.Zero, 0, 0, 1))
                {
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }

                Thread.Sleep(5);
            }
        }
        finally
        {
            UnhookWindowsHookEx(hookID);
            hookID = IntPtr.Zero;
        }
    }

    private static IntPtr SetHook(LowLevelKeyboardProc proc)
    {
        using (Process process = Process.GetCurrentProcess())
        using (ProcessModule module = process.MainModule)
        {
            return SetWindowsHookEx(
                WH_KEYBOARD_LL,
                proc,
                GetModuleHandle(module.ModuleName),
                0
            );
        }
    }

    private delegate IntPtr LowLevelKeyboardProc(
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    private static IntPtr HookCallback(
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    )
    {
        if (nCode >= 0)
        {
            int message = wParam.ToInt32();

            if (
                message == WM_KEYDOWN ||
                message == WM_KEYUP ||
                message == WM_SYSKEYDOWN ||
                message == WM_SYSKEYUP
            )
            {
                return (IntPtr)1;
            }
        }

        return CallNextHookEx(hookID, nCode, wParam, lParam);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int x;
        public int y;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int idHook,
        LowLevelKeyboardProc lpfn,
        IntPtr hMod,
        uint dwThreadId
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hhk,
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out MSG lpMsg,
        IntPtr hWnd,
        uint wMsgFilterMin,
        uint wMsgFilterMax,
        uint wRemoveMsg
    );

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);
}
"@

    [InterceptKeyboard]::Run($DurationMilliseconds)
}

# ============================================================
# CONTROLLER NACH ABLAUF WIEDER AKTIVIEREN
# ============================================================

$controllerRestoreJob = {
    param(
        [string[]]$InstanceIds,
        [int]$Duration
    )

    Start-Sleep -Seconds $Duration

    foreach ($instanceId in $InstanceIds) {
        try {
            Enable-PnpDevice -InstanceId $instanceId -Confirm:$false -ErrorAction Stop
        }
        catch {
            & "$env:SystemRoot\System32\pnputil.exe" /enable-device "$instanceId" | Out-Null
        }
    }
}

$createdJobs = [System.Collections.Generic.List[object]]::new()
$controllerDisabled = $false

try {
    # Alte Jobs mit denselben Namen entfernen
    Get-Job -Name `
        InputBlockMousePosition,
        InputBlockMouseHook,
        InputBlockKeyboardHook,
        InputBlockControllerRestore `
        -ErrorAction SilentlyContinue |
        Stop-Job -ErrorAction SilentlyContinue

    Get-Job -Name `
        InputBlockMousePosition,
        InputBlockMouseHook,
        InputBlockKeyboardHook,
        InputBlockControllerRestore `
        -ErrorAction SilentlyContinue |
        Remove-Job -Force -ErrorAction SilentlyContinue

    # Sony-Controller-Eingabe deaktivieren
    if ($c) {
        if ($ps4Controllers.Count -gt 0) {
            $disabledControllers = @()

            foreach ($controller in $ps4Controllers) {
                try {
                    Write-Host "Controller aus: $($controller.FriendlyName)"
                    Disable-PnpDevice `
                        -InstanceId $controller.InstanceId `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $disabledControllers += $controller
                }
                catch {
                    try {
                        & "$env:SystemRoot\System32\pnputil.exe" `
                            /disable-device "$($controller.InstanceId)" | Out-Null

                        $state = Get-PnpDevice `
                            -InstanceId $controller.InstanceId `
                            -ErrorAction SilentlyContinue

                        if ($state.Status -ne 'OK') {
                            $disabledControllers += $controller
                        }
                        else {
                            Write-Warning "Controller konnte nicht deaktiviert werden."
                        }
                    }
                    catch {
                        Write-Warning "Controllerfehler: $($_.Exception.Message)"
                    }
                }
            }

            if ($disabledControllers.Count -gt 0) {
                $controllerDisabled = $true
                $ps4Controllers = @($disabledControllers)
                $controllerIds = [string[]]@($ps4Controllers.InstanceId)

                $controllerJob = Start-Job `
                    -Name InputBlockControllerRestore `
                    -ScriptBlock $controllerRestoreJob `
                    -ArgumentList (,$controllerIds), $cs

                $createdJobs.Add($controllerJob)
            }
        }
        else {
            Write-Warning 'Kein Sony-HID-Gamecontroller gefunden.'
        }
    }

    # Mausposition festhalten
    if ($m) {
        $positionJob = Start-Job `
            -Name InputBlockMousePosition `
            -ScriptBlock $mousePositionJob `
            -ArgumentList $s, $timeFile

        $createdJobs.Add($positionJob)

        $mouseJob = Start-Job `
            -Name InputBlockMouseHook `
            -ScriptBlock $mouseHookJob `
            -ArgumentList ($s * 1000)

        $createdJobs.Add($mouseJob)
    }

    # Tastatur blockieren
    if ($k) {
        $keyboardJob = Start-Job `
            -Name InputBlockKeyboardHook `
            -ScriptBlock $keyboardHookJob `
            -ArgumentList ($s * 1000)

        $createdJobs.Add($keyboardJob)
    }

    Start-Sleep -Seconds $s
}
finally {
    # Maus- und Tastaturjobs beenden
    Get-Job -Name `
        InputBlockMousePosition,
        InputBlockMouseHook,
        InputBlockKeyboardHook `
        -ErrorAction SilentlyContinue |
        Stop-Job -ErrorAction SilentlyContinue

    Get-Job -Name `
        InputBlockMousePosition,
        InputBlockMouseHook,
        InputBlockKeyboardHook `
        -ErrorAction SilentlyContinue |
        Remove-Job -Force -ErrorAction SilentlyContinue

    # Controller nur sofort aktivieren, wenn sein eigener Timer noch läuft
    $restoreJob = Get-Job `
        -Name InputBlockControllerRestore `
        -ErrorAction SilentlyContinue

    if ($restoreJob) {
        if ($restoreJob.State -eq 'Completed') {
            Receive-Job $restoreJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job $restoreJob -Force -ErrorAction SilentlyContinue
            $controllerDisabled = $false
        }
        elseif ($cs -le $s) {
            Stop-Job $restoreJob -ErrorAction SilentlyContinue
            Remove-Job $restoreJob -Force -ErrorAction SilentlyContinue

            foreach ($controller in $ps4Controllers) {
                try {
                    Enable-PnpDevice `
                        -InstanceId $controller.InstanceId `
                        -Confirm:$false `
                        -ErrorAction Stop
                }
                catch {
                    & "$env:SystemRoot\System32\pnputil.exe" `
                        /enable-device "$($controller.InstanceId)" | Out-Null
                }
            }

            $controllerDisabled = $false
        }
        else {
            Write-Host (
                "Der Controller bleibt noch {0} Sekunden deaktiviert." -f
                ($cs - $s)
            )
        }
    }
    elseif ($controllerDisabled) {
        foreach ($controller in $ps4Controllers) {
            try {
                Enable-PnpDevice `
                    -InstanceId $controller.InstanceId `
                    -Confirm:$false `
                    -ErrorAction Stop
            }
            catch {
                & "$env:SystemRoot\System32\pnputil.exe" `
                    /enable-device "$($controller.InstanceId)" | Out-Null
            }
        }
    }

    Remove-Item -LiteralPath $timeFile -Force -ErrorAction SilentlyContinue
}
