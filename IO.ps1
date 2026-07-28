#requires -RunAsAdministrator
# ============================================================
# SSH-/TASK-VARIANTE: disableIO / enableIO
# ============================================================

if (-not (Test-Path variable:ioUrl)) {
    $ioUrl = 'https://raw.githubusercontent.com/KeksCrash/flip-games/refs/heads/master/IO.ps1'
}

if (Test-Path variable:enableIO) {
    if ($enableIO) {
        Stop-ScheduledTask -TaskName 'DisableIO' -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName 'DisableIO' -Confirm:$false -ErrorAction SilentlyContinue

        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(powershell|pwsh)\.exe$' -and
                $_.CommandLine -match 'DisableIOProcess|InputBlockMouse|InputBlockKeyboard'
            } |
            ForEach-Object {
                Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue |
                    Out-Null
            }

        Get-PnpDevice -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -ne 'OK' -and
                (
                    $_.Class -in @('Mouse', 'Keyboard', 'HIDClass') -or
                    $_.InstanceId -match 'VID_054C'
                )
            } |
            Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue

        Write-Host 'Eingaben wurden wieder aktiviert.'
        return
    }
}

if (Test-Path variable:disableIO) {
    if ($disableIO -and -not (Test-Path variable:DisableIOProcess)) {
        $user = (Get-CimInstance Win32_ComputerSystem).UserName

        if (-not $user) {
            throw 'Kein interaktiv angemeldeter Windows-Benutzer gefunden.'
        }

        if (-not (Test-Path variable:seconds)) {
            $seconds = 60
        }

        if (-not (Test-Path variable:CSeconds)) {
            $CSeconds = $seconds
        }

        if (-not (Test-Path variable:blockMouse)) {
            $blockMouse = $true
        }

        if (-not (Test-Path variable:blockKeyboard)) {
            $blockKeyboard = $true
        }

        if (-not (Test-Path variable:blockController)) {
            $blockController = $true
        }

        $payload = @"
`$DisableIOProcess = `$true
`$seconds = $([int]$seconds)
`$CSeconds = $([int]$CSeconds)
`$blockMouse = `$$blockMouse
`$blockKeyboard = `$$blockKeyboard
`$blockController = `$$blockController
irm '$ioUrl' | iex
"@

        $encoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($payload)
        )

        $action = New-ScheduledTaskAction `
            -Execute 'powershell.exe' `
            -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encoded"

        $principal = New-ScheduledTaskPrincipal `
            -UserId $user `
            -LogonType Interactive `
            -RunLevel Highest

        $settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Seconds ([int]$seconds + 120)) `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries

        Register-ScheduledTask `
            -TaskName 'DisableIO' `
            -Action $action `
            -Principal $principal `
            -Settings $settings `
            -Force |
            Out-Null

        Start-ScheduledTask -TaskName 'DisableIO'

        Write-Host "DisableIO gestartet: $seconds Sekunden"
        Write-Host 'Notfall-Freigabe: $enableIO=$true; irm $ioUrl | iex'
        return
    }
}
# ============================================================
# OPTIONALE VARIABLEN
#
# Diese Variablen können VOR dem Aufruf per IEX gesetzt werden:
#
# $seconds = 60
# $CSeconds = 30
# $blockMouse = $true
# $blockKeyboard = $true
# $blockController = $true
#
# Beispiel:
#
# $seconds=60;$CSeconds=20;$blockController=$true;
# irm 'URL-ZUM-SKRIPT.ps1' | iex
#
# Nicht gesetzte Variablen erhalten die folgenden Standardwerte.
# ============================================================

if (-not (Test-Path variable:seconds)) {
    $seconds = 60
}

if (-not (Test-Path variable:CSeconds)) {
    $CSeconds = $null
}

if (-not (Test-Path variable:blockMouse)) {
    $blockMouse = $true
}

if (-not (Test-Path variable:blockKeyboard)) {
    $blockKeyboard = $true
}

if (-not (Test-Path variable:blockController)) {
    $blockController = $true
}

$seconds = [Math]::Max(1, [int]$seconds)

if ($null -eq $CSeconds -or "$CSeconds".Trim() -eq '') {
    $CSeconds = $seconds
}
else {
    $CSeconds = [Math]::Max(1, [int]$CSeconds)
}

$timeFile = Join-Path $env:TEMP 'input-block-time.txt'
$seconds | Set-Content -LiteralPath $timeFile -Force

Write-Host "Maus/Tastatur-Dauer: $seconds Sekunden"
Write-Host "Controller-Dauer:     $CSeconds Sekunden"
Write-Host "Maus blockieren:       $blockMouse"
Write-Host "Tastatur blockieren:   $blockKeyboard"
Write-Host "Controller blockieren: $blockController"

# ============================================================
# PS4-/DUALSHOCK-CONTROLLER SUCHEN
# Sony Vendor-ID: VID_054C
# ============================================================

$ps4Controllers = @()

if ($blockController) {
    $ps4Controllers = @(
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InstanceId -match 'VID_054C' -or
                $_.FriendlyName -match 'Wireless Controller|DualShock|DUALSHOCK|PS4 Controller'
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
        Enable-PnpDevice `
            -InstanceId $instanceId `
            -Confirm:$false `
            -ErrorAction SilentlyContinue
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

    # PS4-Controller deaktivieren
    if ($blockController) {
        if ($ps4Controllers.Count -gt 0) {
            foreach ($controller in $ps4Controllers) {
                Write-Host "Deaktiviere Controller: $($controller.FriendlyName)"

                Disable-PnpDevice `
                    -InstanceId $controller.InstanceId `
                    -Confirm:$false `
                    -ErrorAction Stop
            }

            $controllerDisabled = $true
            $controllerIds = @($ps4Controllers.InstanceId)

            $controllerJob = Start-Job `
                -Name InputBlockControllerRestore `
                -ScriptBlock $controllerRestoreJob `
                -ArgumentList $controllerIds, $CSeconds

            $createdJobs.Add($controllerJob)
        }
        else {
            Write-Warning 'Kein PS4-/DualShock-Controller gefunden.'
        }
    }

    # Mausposition festhalten
    if ($blockMouse) {
        $positionJob = Start-Job `
            -Name InputBlockMousePosition `
            -ScriptBlock $mousePositionJob `
            -ArgumentList $seconds, $timeFile

        $createdJobs.Add($positionJob)

        $mouseJob = Start-Job `
            -Name InputBlockMouseHook `
            -ScriptBlock $mouseHookJob `
            -ArgumentList ($seconds * 1000)

        $createdJobs.Add($mouseJob)
    }

    # Tastatur blockieren
    if ($blockKeyboard) {
        $keyboardJob = Start-Job `
            -Name InputBlockKeyboardHook `
            -ScriptBlock $keyboardHookJob `
            -ArgumentList ($seconds * 1000)

        $createdJobs.Add($keyboardJob)
    }

    Start-Sleep -Seconds $seconds
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
        elseif ($CSeconds -le $seconds) {
            Stop-Job $restoreJob -ErrorAction SilentlyContinue
            Remove-Job $restoreJob -Force -ErrorAction SilentlyContinue

            foreach ($controller in $ps4Controllers) {
                Enable-PnpDevice `
                    -InstanceId $controller.InstanceId `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue
            }

            $controllerDisabled = $false
        }
        else {
            Write-Host (
                "Der Controller bleibt noch {0} Sekunden deaktiviert." -f
                ($CSeconds - $seconds)
            )
        }
    }
    elseif ($controllerDisabled) {
        foreach ($controller in $ps4Controllers) {
            Enable-PnpDevice `
                -InstanceId $controller.InstanceId `
                -Confirm:$false `
                -ErrorAction SilentlyContinue
        }
    }

    Remove-Item -LiteralPath $timeFile -Force -ErrorAction SilentlyContinue
}
