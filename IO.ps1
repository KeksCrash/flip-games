```powershell
#requires -RunAsAdministrator

# ============================================================
# IO.ps1
#
# KURZE VARIABLEN:
#
# $s  = Dauer Maus/Tastatur
# $cs = Dauer Controller
# $m  = Maus blockieren
# $k  = Tastatur blockieren
# $c  = Controller blockieren
#
# SSH-Start:
#
# $disableIO=$true;$s=60;$cs=60;$m=$true;$k=$true;$c=$true;
# irm 'https://raw.githubusercontent.com/KeksCrash/flip-games/refs/heads/master/IO.ps1' | iex
#
# Sofortige Freigabe:
#
# $enableIO=$true;
# irm 'https://raw.githubusercontent.com/KeksCrash/flip-games/refs/heads/master/IO.ps1' | iex
#
# Direkter lokaler Start:
#
# $s=60;$cs=30;$m=$true;$k=$true;$c=$true;
# irm 'URL-ZUM-SKRIPT' | iex
# ============================================================

$ErrorActionPreference = 'Stop'

# ============================================================
# FESTE NAMEN UND DATEIEN
# ============================================================

$taskName       = 'DisableIO'
$pidFile        = Join-Path $env:TEMP 'disable-io.pid'
$controllerFile = Join-Path $env:TEMP 'disable-io-controllers.txt'

if (-not (Test-Path variable:ioUrl)) {
    $ioUrl = 'https://raw.githubusercontent.com/KeksCrash/flip-games/refs/heads/master/IO.ps1'
}

# ============================================================
# HILFSFUNKTION: PROZESSBAUM BEENDEN
# ============================================================

function Stop-IOProcessTree {
    param(
        [Parameter(Mandatory)]
        [int]$RootProcessId
    )

    $allProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    )

    function Stop-ChildProcesses {
        param([int]$ParentId)

        $children = @(
            $allProcesses |
                Where-Object {
                    [int]$_.ParentProcessId -eq $ParentId
                }
        )

        foreach ($child in $children) {
            Stop-ChildProcesses -ParentId ([int]$child.ProcessId)

            Invoke-CimMethod `
                -InputObject $child `
                -MethodName Terminate `
                -ErrorAction SilentlyContinue |
                Out-Null
        }
    }

    Stop-ChildProcesses -ParentId $RootProcessId

    $root = $allProcesses |
        Where-Object {
            [int]$_.ProcessId -eq $RootProcessId
        } |
        Select-Object -First 1

    if ($root) {
        Invoke-CimMethod `
            -InputObject $root `
            -MethodName Terminate `
            -ErrorAction SilentlyContinue |
            Out-Null
    }
}

# ============================================================
# HILFSFUNKTION: GERÄT AKTIVIEREN
# ============================================================

function Enable-IODevice {
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    try {
        Enable-PnpDevice `
            -InstanceId $InstanceId `
            -Confirm:$false `
            -ErrorAction Stop

        return $true
    }
    catch {
        & pnputil.exe /enable-device "$InstanceId" 2>$null |
            Out-Null

        return ($LASTEXITCODE -eq 0)
    }
}

# ============================================================
# SOFORTIGE FREIGABE
# ============================================================

if ((Test-Path variable:enableIO) -and $enableIO) {
    Write-Host 'Beende DisableIO ...'

    Stop-ScheduledTask `
        -TaskName $taskName `
        -ErrorAction SilentlyContinue

    Unregister-ScheduledTask `
        -TaskName $taskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $pidFile) {
        $savedPid = Get-Content `
            -LiteralPath $pidFile `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($savedPid -match '^\d+$') {
            Stop-IOProcessTree -RootProcessId ([int]$savedPid)
        }
    }

    if (Test-Path -LiteralPath $controllerFile) {
        $controllerIds = @(
            Get-Content `
                -LiteralPath $controllerFile `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                } |
                Sort-Object -Unique
        )

        foreach ($id in $controllerIds) {
            Write-Host "Aktiviere Controller: $id"

            if (-not (Enable-IODevice -InstanceId $id)) {
                Write-Warning "Controller konnte nicht aktiviert werden: $id"
            }
        }
    }

    Remove-Item `
        -LiteralPath $pidFile, $controllerFile `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Host 'Maus, Tastatur und Controller wurden wieder freigegeben.'
    return
}

# ============================================================
# OPTIONALE VARIABLEN AUFLÖSEN
# ============================================================

if (Test-Path variable:s) {
    $seconds = $s
}
elseif (-not (Test-Path variable:seconds)) {
    $seconds = 60
}

if (Test-Path variable:cs) {
    $CSeconds = $cs
}
elseif (-not (Test-Path variable:CSeconds)) {
    $CSeconds = $null
}

if (Test-Path variable:m) {
    $blockMouse = [bool]$m
}
elseif (-not (Test-Path variable:blockMouse)) {
    $blockMouse = $true
}

if (Test-Path variable:k) {
    $blockKeyboard = [bool]$k
}
elseif (-not (Test-Path variable:blockKeyboard)) {
    $blockKeyboard = $true
}

if (Test-Path variable:c) {
    $blockController = [bool]$c
}
elseif (-not (Test-Path variable:blockController)) {
    $blockController = $true
}

$seconds = [Math]::Max(1, [int]$seconds)

if (
    $null -eq $CSeconds -or
    [string]::IsNullOrWhiteSpace([string]$CSeconds)
) {
    $CSeconds = $seconds
}
else {
    $CSeconds = [Math]::Max(1, [int]$CSeconds)
}

# ============================================================
# SSH-VARIANTE
#
# Das eigentliche Skript wird als geplante Aufgabe in der
# interaktiven Desktop-Sitzung gestartet.
# ============================================================

if (
    (Test-Path variable:disableIO) -and
    $disableIO -and
    -not (Test-Path variable:DisableIOProcess)
) {
    $interactiveUser = (
        Get-CimInstance Win32_ComputerSystem
    ).UserName

    if ([string]::IsNullOrWhiteSpace($interactiveUser)) {
        throw 'Kein interaktiv angemeldeter Windows-Benutzer gefunden.'
    }

    $mouseLiteral = if ($blockMouse) {
        '$true'
    }
    else {
        '$false'
    }

    $keyboardLiteral = if ($blockKeyboard) {
        '$true'
    }
    else {
        '$false'
    }

    $controllerLiteral = if ($blockController) {
        '$true'
    }
    else {
        '$false'
    }

    $payload = @"
`$DisableIOProcess = `$true
`$seconds = $seconds
`$CSeconds = $CSeconds
`$blockMouse = $mouseLiteral
`$blockKeyboard = $keyboardLiteral
`$blockController = $controllerLiteral
`$ioUrl = '$($ioUrl.Replace("'", "''"))'
irm `$ioUrl | iex
"@

    $encodedPayload = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($payload)
    )

    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument (
            '-NoProfile -ExecutionPolicy Bypass ' +
            '-WindowStyle Hidden ' +
            "-EncodedCommand $encodedPayload"
        )

    $principal = New-ScheduledTaskPrincipal `
        -UserId $interactiveUser `
        -LogonType Interactive `
        -RunLevel Highest

    $maximumDuration = [Math]::Max(
        $seconds,
        $CSeconds
    )

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (
            New-TimeSpan -Seconds ($maximumDuration + 180)
        ) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Stop-ScheduledTask `
        -TaskName $taskName `
        -ErrorAction SilentlyContinue

    Unregister-ScheduledTask `
        -TaskName $taskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Principal $principal `
        -Settings $settings `
        -Force |
        Out-Null

    Start-ScheduledTask -TaskName $taskName

    Write-Host "DisableIO wurde für $interactiveUser gestartet."
    Write-Host "Maus/Tastatur: $seconds Sekunden"
    Write-Host "Controller:    $CSeconds Sekunden"
    Write-Host ''
    Write-Host 'Notfallfreigabe:'
    Write-Host "`$enableIO=`$true;irm '$ioUrl'|iex"
    return
}

# ============================================================
# INTERAKTIVER HAUPTPROZESS
# ============================================================

$PID |
    Set-Content `
        -LiteralPath $pidFile `
        -Force

Write-Host ''
Write-Host '================ DisableIO ================'
Write-Host "Maus/Tastatur: $seconds Sekunden"
Write-Host "Controller:    $CSeconds Sekunden"
Write-Host "Maus:          $blockMouse"
Write-Host "Tastatur:      $blockKeyboard"
Write-Host "Controller:    $blockController"
Write-Host '==========================================='
Write-Host ''

# ============================================================
# GAMECONTROLLER SUCHEN
#
# Erkannt werden unter anderem:
#
# - DualShock 4
# - DualSense
# - Xbox 360 / One / Series
# - DS4Windows
# - ViGEm virtuelle Xbox-/DS4-Controller
# - Nintendo Switch Pro Controller
# - Joy-Con
# - Logitech
# - Thrustmaster
# - generische HID-Gamecontroller
#
# Audio, Maus, Tastatur, Touchpad und ViGEm-Bus selbst werden
# ausgeschlossen.
# ============================================================

$controllers = @()

if ($blockController) {
    $controllers = @(
        Get-PnpDevice `
            -PresentOnly `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $name = [string]$_.FriendlyName
                $id   = [string]$_.InstanceId
                $cls  = [string]$_.Class

                $controllerNameMatch =
                    $name -match '(?i)' +
                    'HID-compliant game controller|' +
                    'HID-konformer Gamecontroller|' +
                    'game\s*controller|' +
                    'gamepad|' +
                    'joystick|' +
                    'Xbox.*controller|' +
                    'Xbox.*gamepad|' +
                    'controller\s*for\s*windows|' +
                    'wireless\s*controller|' +
                    'DualShock|' +
                    'DualSense|' +
                    'PS[345].*controller|' +
                    'PlayStation.*controller|' +
                    'Switch.*controller|' +
                    'Pro\s*Controller|' +
                    'Joy-?Con|' +
                    'Logitech.*(controller|gamepad)|' +
                    'Thrustmaster.*(controller|gamepad)|' +
                    'virtual.*(controller|gamepad)|' +
                    'ViGEm.*controller'

                $controllerClassMatch =
                    $cls -match '(?i)' +
                    '^(GameController|' +
                    'XnaComposite|' +
                    'XboxComposite)$'

                $controllerIdMatch =
                    $cls -eq 'HIDClass' -and
                    $id -match '(?i)' +
                    'VID_054C|' +   # Sony
                    'VID_045E|' +   # Microsoft
                    'VID_057E|' +   # Nintendo
                    'VID_046D|' +   # Logitech
                    'VID_044F|' +   # Thrustmaster
                    'IG_0[0-9]|' +
                    'GAMEPAD|' +
                    'JOYSTICK'

                $excludedClass =
                    $cls -in @(
                        'Mouse',
                        'Keyboard',
                        'AudioEndpoint',
                        'MEDIA',
                        'Bluetooth',
                        'System',
                        'USB'
                    )

                $excludedName =
                    $name -match '(?i)' +
                    'mouse|' +
                    'maus|' +
                    'keyboard|' +
                    'tastatur|' +
                    'touchpad|' +
                    'headphone|' +
                    'headset|' +
                    'microphone|' +
                    'mikrofon|' +
                    'speaker|' +
                    'lautsprecher|' +
                    'audio|' +
                    'consumer\s*control|' +
                    'system\s*control|' +
                    'vendor-defined|' +
                    'ViGEm.*bus|' +
                    'emulation\s*bus|' +
                    'Bluetooth.*adapter|' +
                    'USB.*hub'

                (
                    $controllerNameMatch -or
                    $controllerClassMatch -or
                    $controllerIdMatch
                ) -and
                -not $excludedClass -and
                -not $excludedName
            } |
            Sort-Object InstanceId -Unique
    )
}

# ============================================================
# GERÄT DEAKTIVIEREN
# ============================================================

function Disable-IODevice {
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    try {
        Disable-PnpDevice `
            -InstanceId $InstanceId `
            -Confirm:$false `
            -ErrorAction Stop

        return $true
    }
    catch {
        & pnputil.exe `
            /disable-device "$InstanceId" `
            /force 2>$null |
            Out-Null

        return ($LASTEXITCODE -eq 0)
    }
}

# ============================================================
# MAUSPOSITION FESTHALTEN
# ============================================================

$mousePositionJob = {
    param([int]$Duration)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $position = [System.Windows.Forms.Cursor]::Position
    $x = $position.X
    $y = $position.Y

    $endTime = (Get-Date).AddSeconds($Duration)

    while ((Get-Date) -lt $endTime) {
        [System.Windows.Forms.Cursor]::Position =
            [System.Drawing.Point]::new($x, $y)

        Start-Sleep -Milliseconds 10
    }
}

# ============================================================
# MAUS-HOOK
# ============================================================

$mouseHookJob = {
    param([int]$DurationMilliseconds)

    Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class DisableIOMouseHook
{
    private const int WH_MOUSE_LL = 14;

    private const int WM_MOUSEMOVE    = 0x0200;
    private const int WM_LBUTTONDOWN  = 0x0201;
    private const int WM_LBUTTONUP    = 0x0202;
    private const int WM_RBUTTONDOWN  = 0x0204;
    private const int WM_RBUTTONUP    = 0x0205;
    private const int WM_MBUTTONDOWN  = 0x0207;
    private const int WM_MBUTTONUP    = 0x0208;
    private const int WM_MOUSEWHEEL   = 0x020A;
    private const int WM_XBUTTONDOWN  = 0x020B;
    private const int WM_XBUTTONUP    = 0x020C;
    private const int WM_MOUSEHWHEEL  = 0x020E;

    private static IntPtr hookId = IntPtr.Zero;

    private static readonly LowLevelMouseProc callback =
        HookCallback;

    public static void Run(int durationMilliseconds)
    {
        hookId = SetHook(callback);

        if (hookId == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "Der Maus-Hook konnte nicht installiert werden."
            );
        }

        try
        {
            DateTime end =
                DateTime.UtcNow.AddMilliseconds(
                    durationMilliseconds
                );

            while (DateTime.UtcNow < end)
            {
                MSG message;

                while (
                    PeekMessage(
                        out message,
                        IntPtr.Zero,
                        0,
                        0,
                        1
                    )
                )
                {
                    TranslateMessage(ref message);
                    DispatchMessage(ref message);
                }

                Thread.Sleep(5);
            }
        }
        finally
        {
            if (hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(hookId);
                hookId = IntPtr.Zero;
            }
        }
    }

    private static IntPtr SetHook(
        LowLevelMouseProc proc
    )
    {
        using (
            Process process =
                Process.GetCurrentProcess()
        )
        using (
            ProcessModule module =
                process.MainModule
        )
        {
            return SetWindowsHookEx(
                WH_MOUSE_LL,
                proc,
                GetModuleHandle(
                    module.ModuleName
                ),
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

        return CallNextHookEx(
            hookId,
            nCode,
            wParam,
            lParam
        );
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

    [DllImport(
        "user32.dll",
        SetLastError = true
    )]
    private static extern IntPtr SetWindowsHookEx(
        int idHook,
        LowLevelMouseProc lpfn,
        IntPtr hMod,
        uint threadId
    );

    [DllImport(
        "user32.dll",
        SetLastError = true
    )]
    private static extern bool UnhookWindowsHookEx(
        IntPtr hook
    );

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Auto
    )]
    private static extern IntPtr GetModuleHandle(
        string moduleName
    );

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out MSG message,
        IntPtr window,
        uint minimum,
        uint maximum,
        uint removeMessage
    );

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(
        ref MSG message
    );

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(
        ref MSG message
    );
}
"@

    [DisableIOMouseHook]::Run(
        $DurationMilliseconds
    )
}

# ============================================================
# TASTATUR-HOOK
# ============================================================

$keyboardHookJob = {
    param([int]$DurationMilliseconds)

    Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class DisableIOKeyboardHook
{
    private const int WH_KEYBOARD_LL = 13;

    private const int WM_KEYDOWN    = 0x0100;
    private const int WM_KEYUP      = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP   = 0x0105;

    private static IntPtr hookId = IntPtr.Zero;

    private static readonly LowLevelKeyboardProc callback =
        HookCallback;

    public static void Run(int durationMilliseconds)
    {
        hookId = SetHook(callback);

        if (hookId == IntPtr.Zero)
        {
            throw new InvalidOperationException(
                "Der Tastatur-Hook konnte nicht installiert werden."
            );
        }

        try
        {
            DateTime end =
                DateTime.UtcNow.AddMilliseconds(
                    durationMilliseconds
                );

            while (DateTime.UtcNow < end)
            {
                MSG message;

                while (
                    PeekMessage(
                        out message,
                        IntPtr.Zero,
                        0,
                        0,
                        1
                    )
                )
                {
                    TranslateMessage(ref message);
                    DispatchMessage(ref message);
                }

                Thread.Sleep(5);
            }
        }
        finally
        {
            if (hookId != IntPtr.Zero)
            {
                UnhookWindowsHookEx(hookId);
                hookId = IntPtr.Zero;
            }
        }
    }

    private static IntPtr SetHook(
        LowLevelKeyboardProc proc
    )
    {
        using (
            Process process =
                Process.GetCurrentProcess()
        )
        using (
            ProcessModule module =
                process.MainModule
        )
        {
            return SetWindowsHookEx(
                WH_KEYBOARD_LL,
                proc,
                GetModuleHandle(
                    module.ModuleName
                ),
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

        return CallNextHookEx(
            hookId,
            nCode,
            wParam,
            lParam
        );
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

    [DllImport(
        "user32.dll",
        SetLastError = true
    )]
    private static extern IntPtr SetWindowsHookEx(
        int idHook,
        LowLevelKeyboardProc lpfn,
        IntPtr hMod,
        uint threadId
    );

    [DllImport(
        "user32.dll",
        SetLastError = true
    )]
    private static extern bool UnhookWindowsHookEx(
        IntPtr hook
    );

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Auto
    )]
    private static extern IntPtr GetModuleHandle(
        string moduleName
    );

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out MSG message,
        IntPtr window,
        uint minimum,
        uint maximum,
        uint removeMessage
    );

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(
        ref MSG message
    );

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(
        ref MSG message
    );
}
"@

    [DisableIOKeyboardHook]::Run(
        $DurationMilliseconds
    )
}

# ============================================================
# CONTROLLER-WIEDERHERSTELLUNGSJOB
# ============================================================

$controllerRestoreJob = {
    param(
        [string[]]$InstanceIds,
        [int]$Duration
    )

    Start-Sleep -Seconds $Duration

    foreach ($instanceId in $InstanceIds) {
        try {
            Enable-PnpDevice `
                -InstanceId $instanceId `
                -Confirm:$false `
                -ErrorAction Stop
        }
        catch {
            & pnputil.exe `
                /enable-device "$instanceId" 2>$null |
                Out-Null
        }
    }
}

# ============================================================
# AUSFÜHRUNG
# ============================================================

$jobs = [System.Collections.Generic.List[object]]::new()
$disabledControllerIds = @()

try {
    Get-Job `
        -Name 'DisableIO-*' `
        -ErrorAction SilentlyContinue |
        Stop-Job `
            -ErrorAction SilentlyContinue

    Get-Job `
        -Name 'DisableIO-*' `
        -ErrorAction SilentlyContinue |
        Remove-Job `
            -Force `
            -ErrorAction SilentlyContinue

    # --------------------------------------------------------
    # Controller deaktivieren
    # --------------------------------------------------------

    if ($blockController) {
        if ($controllers.Count -eq 0) {
            Write-Warning 'Kein Gamecontroller gefunden.'
        }
        else {
            foreach ($controller in $controllers) {
                Write-Host (
                    'Deaktiviere Controller: {0}' -f
                    $controller.FriendlyName
                )

                if (
                    Disable-IODevice `
                        -InstanceId $controller.InstanceId
                ) {
                    $disabledControllerIds +=
                        $controller.InstanceId
                }
                else {
                    Write-Warning (
                        'Controller konnte nicht deaktiviert werden: {0}' -f
                        $controller.FriendlyName
                    )
                }
            }

            $disabledControllerIds =
                @(
                    $disabledControllerIds |
                        Sort-Object -Unique
                )

            if ($disabledControllerIds.Count -gt 0) {
                $disabledControllerIds |
                    Set-Content `
                        -LiteralPath $controllerFile `
                        -Force

                $controllerJob = Start-Job `
                    -Name 'DisableIO-ControllerRestore' `
                    -ScriptBlock $controllerRestoreJob `
                    -ArgumentList (
                        ,$disabledControllerIds
                    ), $CSeconds

                $jobs.Add($controllerJob)
            }
        }
    }

    # --------------------------------------------------------
    # Maus blockieren
    # --------------------------------------------------------

    if ($blockMouse) {
        $positionJob = Start-Job `
            -Name 'DisableIO-MousePosition' `
            -ScriptBlock $mousePositionJob `
            -ArgumentList $seconds

        $jobs.Add($positionJob)

        $mouseJob = Start-Job `
            -Name 'DisableIO-MouseHook' `
            -ScriptBlock $mouseHookJob `
            -ArgumentList ($seconds * 1000)

        $jobs.Add($mouseJob)
    }

    # --------------------------------------------------------
    # Tastatur blockieren
    # --------------------------------------------------------

    if ($blockKeyboard) {
        $keyboardJob = Start-Job `
            -Name 'DisableIO-KeyboardHook' `
            -ScriptBlock $keyboardHookJob `
            -ArgumentList ($seconds * 1000)

        $jobs.Add($keyboardJob)
    }

    # Prozess bleibt bis zum längsten Timer aktiv.
    $totalDuration = [Math]::Max(
        $seconds,
        $CSeconds
    )

    Start-Sleep -Seconds $totalDuration
}
finally {
    # --------------------------------------------------------
    # Alle Hooks und Jobs beenden
    # --------------------------------------------------------

    Get-Job `
        -Name 'DisableIO-*' `
        -ErrorAction SilentlyContinue |
        Stop-Job `
            -ErrorAction SilentlyContinue

    Get-Job `
        -Name 'DisableIO-*' `
        -ErrorAction SilentlyContinue |
        Receive-Job `
            -ErrorAction SilentlyContinue |
        Out-Null

    Get-Job `
        -Name 'DisableIO-*' `
        -ErrorAction SilentlyContinue |
        Remove-Job `
            -Force `
            -ErrorAction SilentlyContinue

    # --------------------------------------------------------
    # Tatsächlich deaktivierte Controller aktivieren
    # --------------------------------------------------------

    if (Test-Path -LiteralPath $controllerFile) {
        $idsToRestore = @(
            Get-Content `
                -LiteralPath $controllerFile `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                } |
                Sort-Object -Unique
        )

        foreach ($id in $idsToRestore) {
            Enable-IODevice -InstanceId $id |
                Out-Null
        }
    }

    Remove-Item `
        -LiteralPath $controllerFile, $pidFile `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Host 'Alle ausgewählten Eingaben wurden wieder freigegeben.'
}
```
