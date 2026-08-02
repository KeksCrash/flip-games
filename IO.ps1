#requires -Version 5.1
#requires -RunAsAdministrator

# BUILD: IO-2026-08-02-2035-NOPARAM
# Kein globaler CmdletBinding-/param-Block.
# Empfohlener Start: zuerst nach %TEMP% laden, mit dem PowerShell-Parser
# pruefen und danach als Datei ausfuehren; nicht direkt per iex.
$DisableIOBuild = 'IO-2026-08-02-2035-NOPARAM'
# Kein param()-Block: Dadurch funktioniert die Datei sowohl mit
# "irm <URL> | iex" als auch mit "powershell.exe -File IO.ps1 ...".
# Bei einem direkten -File-Aufruf werden bekannte Argumente hier ausgewertet.

$parsedInternalWorker     = $null
$parsedRelease            = $null
$parsedDuration           = $null
$parsedControllerDuration = $null
$parsedNoMouse            = $null
$parsedNoKeyboard         = $null
$parsedNoController       = $null
$parsedSourceUrl          = $null

for ($argumentIndex = 0; $argumentIndex -lt $args.Count; $argumentIndex++) {
    $argument = [string]$args[$argumentIndex]

    switch -Regex ($argument) {
        '^(?i)-InternalWorker$' {
            $parsedInternalWorker = $true
            continue
        }

        '^(?i)-(Release|EnableIO)$' {
            $parsedRelease = $true
            continue
        }

        '^(?i)-NoMouse$' {
            $parsedNoMouse = $true
            continue
        }

        '^(?i)-NoKeyboard$' {
            $parsedNoKeyboard = $true
            continue
        }

        '^(?i)-NoController$' {
            $parsedNoController = $true
            continue
        }

        '^(?i)-Duration$' {
            if (($argumentIndex + 1) -ge $args.Count) {
                throw 'Nach -Duration fehlt die Sekundenangabe.'
            }

            $argumentIndex++
            $parsedDuration = [int]$args[$argumentIndex]
            continue
        }

        '^(?i)-ControllerDuration$' {
            if (($argumentIndex + 1) -ge $args.Count) {
                throw 'Nach -ControllerDuration fehlt die Sekundenangabe.'
            }

            $argumentIndex++
            $parsedControllerDuration = [int]$args[$argumentIndex]
            continue
        }

        '^(?i)-SourceUrl$' {
            if (($argumentIndex + 1) -ge $args.Count) {
                throw 'Nach -SourceUrl fehlt die URL.'
            }

            $argumentIndex++
            $parsedSourceUrl = [string]$args[$argumentIndex]
            continue
        }
    }
}

if ($null -ne $parsedInternalWorker) {
    $InternalWorker = [bool]$parsedInternalWorker
}
elseif (-not (Test-Path variable:InternalWorker)) {
    $InternalWorker = $false
}
else {
    $InternalWorker = [bool]$InternalWorker
}

if ($null -ne $parsedRelease) {
    $Release = [bool]$parsedRelease
}
elseif (-not (Test-Path variable:Release)) {
    $Release = $false
}
else {
    $Release = [bool]$Release
}

if ($null -ne $parsedDuration) {
    $Duration = [int]$parsedDuration
}
elseif (-not (Test-Path variable:Duration)) {
    $Duration = 60
}

if ($null -ne $parsedControllerDuration) {
    $ControllerDuration = [int]$parsedControllerDuration
}
elseif (-not (Test-Path variable:ControllerDuration)) {
    $ControllerDuration = 0
}

if ($null -ne $parsedNoMouse) {
    $NoMouse = [bool]$parsedNoMouse
}
elseif (-not (Test-Path variable:NoMouse)) {
    $NoMouse = $false
}
else {
    $NoMouse = [bool]$NoMouse
}

if ($null -ne $parsedNoKeyboard) {
    $NoKeyboard = [bool]$parsedNoKeyboard
}
elseif (-not (Test-Path variable:NoKeyboard)) {
    $NoKeyboard = $false
}
else {
    $NoKeyboard = [bool]$NoKeyboard
}

if ($null -ne $parsedNoController) {
    $NoController = [bool]$parsedNoController
}
elseif (-not (Test-Path variable:NoController)) {
    $NoController = $false
}
else {
    $NoController = [bool]$NoController
}

if ($null -ne $parsedSourceUrl) {
    $SourceUrl = [string]$parsedSourceUrl
}
elseif (-not (Test-Path variable:SourceUrl)) {
    $SourceUrl = 'https://raw.githubusercontent.com/KeksCrash/flip-games/refs/heads/master/IO.ps1'
}

$ErrorActionPreference = 'Stop'

# ============================================================
# LEGACY-VARIABLEN AUS irm ... | iex UNTERSTÜTZEN
# ============================================================

if (Test-Path variable:s) {
    $Duration = [int]$s
}
elseif (Test-Path variable:seconds) {
    $Duration = [int]$seconds
}

if (Test-Path variable:cs) {
    $ControllerDuration = [int]$cs
}
elseif (Test-Path variable:CSeconds) {
    $ControllerDuration = [int]$CSeconds
}

$legacyBlockMouseSet = Test-Path variable:blockMouse
$legacyBlockMouse = if ($legacyBlockMouseSet) {
    [bool](Get-Variable blockMouse -ValueOnly)
}
else {
    $null
}

$legacyBlockKeyboardSet = Test-Path variable:blockKeyboard
$legacyBlockKeyboard = if ($legacyBlockKeyboardSet) {
    [bool](Get-Variable blockKeyboard -ValueOnly)
}
else {
    $null
}

$legacyBlockControllerSet = Test-Path variable:blockController
$legacyBlockController = if ($legacyBlockControllerSet) {
    [bool](Get-Variable blockController -ValueOnly)
}
else {
    $null
}

$blockMouse = -not $NoMouse
if (Test-Path variable:m) {
    $blockMouse = [bool]$m
}
elseif ($legacyBlockMouseSet) {
    $blockMouse = $legacyBlockMouse
}

$blockKeyboard = -not $NoKeyboard
if (Test-Path variable:k) {
    $blockKeyboard = [bool]$k
}
elseif ($legacyBlockKeyboardSet) {
    $blockKeyboard = $legacyBlockKeyboard
}

$blockController = -not $NoController
if (Test-Path variable:c) {
    $blockController = [bool]$c
}
elseif ($legacyBlockControllerSet) {
    $blockController = $legacyBlockController
}

if (Test-Path variable:ioUrl) {
    $SourceUrl = [string]$ioUrl
}

$releaseRequested = $Release
if ((Test-Path variable:enableIO) -and [bool]$enableIO) {
    $releaseRequested = $true
}

$Duration = [Math]::Max(1, [int]$Duration)
if ($ControllerDuration -le 0) {
    $ControllerDuration = $Duration
}
else {
    $ControllerDuration = [Math]::Max(1, [int]$ControllerDuration)
}

# ============================================================
# ALLE DATEIEN LIEGEN AUSSCHLIESSLICH IN %TEMP%\DisableIO
# ============================================================

$taskName       = 'DisableIO-Temp'
$workRoot       = Join-Path ([IO.Path]::GetTempPath()) 'DisableIO'
$tempScript     = Join-Path $workRoot 'IO.ps1'
$pidFile        = Join-Path $workRoot 'worker.pid'
$controllerFile = Join-Path $workRoot 'controllers.txt'
$logFile        = Join-Path $workRoot 'DisableIO.log'

# ============================================================
# ADMINISTRATORSTATUS
# ============================================================

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-IsAdministrator)) {
    throw 'DisableIO muss mit Administratorrechten ausgeführt werden.'
}

# ============================================================
# PROZESSBAUM BEENDEN
# ============================================================

function Stop-IOProcessTree {
    param(
        [Parameter(Mandatory)]
        [int]$RootProcessId
    )

    $allProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    )

    function Stop-Children {
        param([int]$ParentId)

        $children = @(
            $allProcesses |
                Where-Object {
                    [int]$_.ParentProcessId -eq $ParentId
                }
        )

        foreach ($child in $children) {
            Stop-Children -ParentId ([int]$child.ProcessId)

            Invoke-CimMethod `
                -InputObject $child `
                -MethodName Terminate `
                -ErrorAction SilentlyContinue |
                Out-Null
        }
    }

    Stop-Children -ParentId $RootProcessId

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
# PNP-GERÄTE AKTIVIEREN / DEAKTIVIEREN
# ============================================================

function Disable-IODevice {
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    $powerShellError = $null

    try {
        Disable-PnpDevice `
            -InstanceId $InstanceId `
            -Confirm:$false `
            -ErrorAction Stop

        return [pscustomobject]@{
            Success = $true
            Detail  = 'Disable-PnpDevice'
        }
    }
    catch {
        $powerShellError = $_.Exception.Message
    }

    $pnpOutput = @(
        & "$env:windir\System32\pnputil.exe" `
            /disable-device "$InstanceId" /force 2>&1
    )
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        return [pscustomobject]@{
            Success = $true
            Detail  = 'PnPUtil'
        }
    }

    return [pscustomobject]@{
        Success = $false
        Detail  = @(
            "Disable-PnpDevice: $powerShellError"
            "PnPUtil ExitCode: $exitCode"
            ($pnpOutput -join "`n")
        ) -join "`n"
    }
}

function Enable-IODevice {
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    $powerShellError = $null

    try {
        Enable-PnpDevice `
            -InstanceId $InstanceId `
            -Confirm:$false `
            -ErrorAction Stop

        return [pscustomobject]@{
            Success = $true
            Detail  = 'Enable-PnpDevice'
        }
    }
    catch {
        $powerShellError = $_.Exception.Message
    }

    $pnpOutput = @(
        & "$env:windir\System32\pnputil.exe" `
            /enable-device "$InstanceId" 2>&1
    )
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        return [pscustomobject]@{
            Success = $true
            Detail  = 'PnPUtil'
        }
    }

    return [pscustomobject]@{
        Success = $false
        Detail  = @(
            "Enable-PnpDevice: $powerShellError"
            "PnPUtil ExitCode: $exitCode"
            ($pnpOutput -join "`n")
        ) -join "`n"
    }
}

# ============================================================
# CONTROLLER-GERÄTEBAUM
# ============================================================

function Get-PnpParentId {
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    try {
        $value = (
            Get-PnpDeviceProperty `
                -InstanceId $InstanceId `
                -KeyName 'DEVPKEY_Device_Parent' `
                -ErrorAction Stop
        ).Data

        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            return $null
        }

        return [string]$value
    }
    catch {
        return $null
    }
}

function Get-PnpDeviceChain {
    param(
        [Parameter(Mandatory)]
        $Device
    )

    $chain = [System.Collections.Generic.List[object]]::new()
    $current = $Device
    $seen = @{}

    for ($level = 0; $level -lt 12; $level++) {
        if ($null -eq $current) {
            break
        }

        $currentId = [string]$current.InstanceId
        if ([string]::IsNullOrWhiteSpace($currentId)) {
            break
        }

        if ($seen.ContainsKey($currentId)) {
            break
        }

        $seen[$currentId] = $true
        $chain.Add($current)

        $parentId = Get-PnpParentId -InstanceId $currentId
        if ([string]::IsNullOrWhiteSpace($parentId)) {
            break
        }

        $current = Get-PnpDevice `
            -InstanceId $parentId `
            -ErrorAction SilentlyContinue
    }

    return @($chain)
}

function Resolve-ControllerTarget {
    param(
        [Parameter(Mandatory)]
        $Device
    )

    $chain = @(Get-PnpDeviceChain -Device $Device)

    # Bei USB den höchsten gerätespezifischen VID/PID-Knoten nehmen,
    # nicht nur das untergeordnete "HID-compliant game controller".
    $usbTargets = @(
        $chain |
            Where-Object {
                $id   = [string]$_.InstanceId
                $name = [string]$_.FriendlyName

                $id -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}' -and
                $name -notmatch '(?i)Root Hub|Host Controller'
            }
    )

    if ($usbTargets.Count -gt 0) {
        return $usbTargets[-1]
    }

    # Bei Bluetooth nur den Controller-Zweig wählen, niemals den Adapter.
    $bluetoothTargets = @(
        $chain |
            Where-Object {
                $id   = [string]$_.InstanceId
                $name = [string]$_.FriendlyName

                $id -match '(?i)^(BTHENUM|BTHLEDEVICE)\\' -and
                $name -notmatch '(?i)Bluetooth.*Adapter|Radio|Enumerator'
            }
    )

    if ($bluetoothTargets.Count -gt 0) {
        # Den obersten gerätespezifischen Bluetooth-Knoten wählen,
        # damit der komplette Controller und nicht nur eine HID-Funktion
        # deaktiviert wird.
        return $bluetoothTargets[-1]
    }

    # Virtuelle oder nicht auflösbare Controller: den erkannten
    # Gamecontroller-Knoten selbst verwenden.
    return $Device
}

function Get-ControllerTargets {
    $leaves = @(
        Get-PnpDevice `
            -PresentOnly `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $name = [string]$_.FriendlyName
                $cls  = [string]$_.Class

                $allowedClass =
                    $cls -in @(
                        'HIDClass',
                        'GameController',
                        'XnaComposite',
                        'XboxComposite'
                    )

                $controllerName =
                    $name -match '(?i)' +
                    '^HID-compliant game controller$|' +
                    '^HID-konformer Gamecontroller$|' +
                    'game\s*controller|' +
                    'gamepad|' +
                    'joystick|' +
                    'wireless\s*controller|' +
                    'DualShock|' +
                    'DualSense|' +
                    'Xbox.*controller|' +
                    'Xbox.*gamepad|' +
                    'controller\s*for\s*windows|' +
                    'Switch.*controller|' +
                    'Pro\s*Controller|' +
                    'Joy-?Con|' +
                    'Logitech.*(controller|gamepad)|' +
                    'Thrustmaster.*(controller|gamepad)|' +
                    'virtual.*(controller|gamepad)|' +
                    'ViGEm.*controller'

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

                $allowedClass -and
                $controllerName -and
                -not $excludedName
            }
    )

    $targets = foreach ($leaf in $leaves) {
        Resolve-ControllerTarget -Device $leaf
    }

    return @(
        $targets |
            Where-Object { $null -ne $_ } |
            Sort-Object InstanceId -Unique
    )
}

# ============================================================
# DEAKTIVIERTE CONTROLLER SOFORT IN TEMP SICHERN
# ============================================================

function Save-DisabledControllerId {
    param(
        [Parameter(Mandatory)]
        [string]$InstanceId
    )

    New-Item `
        -Path $workRoot `
        -ItemType Directory `
        -Force |
        Out-Null

    $savedIds = @()

    if (Test-Path -LiteralPath $controllerFile) {
        $savedIds = @(
            Get-Content `
                -LiteralPath $controllerFile `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
        )
    }

    $savedIds = @(
        $savedIds
        $InstanceId
    ) |
        Sort-Object -Unique

    $savedIds |
        Set-Content `
            -LiteralPath $controllerFile `
            -Encoding Unicode `
            -Force
}

# ============================================================
# TEMP-ZUSTAND FREIGEBEN UND BEREINIGEN
# ============================================================

function Remove-DisableIOTask {
    param([switch]$DoNotStopRunningTask)

    if (-not $DoNotStopRunningTask) {
        Stop-ScheduledTask `
            -TaskName $taskName `
            -ErrorAction SilentlyContinue
    }

    Unregister-ScheduledTask `
        -TaskName $taskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        & "$env:windir\System32\schtasks.exe" `
            /Delete /TN $taskName /F 2>$null |
            Out-Null
    }
}

function Restore-SavedControllers {
    if (-not (Test-Path -LiteralPath $controllerFile)) {
        return $true
    }

    $ids = @(
        Get-Content `
            -LiteralPath $controllerFile `
            -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } |
            Sort-Object -Unique
    )

    $failedIds = [System.Collections.Generic.List[string]]::new()

    foreach ($instanceId in $ids) {
        $result = Enable-IODevice -InstanceId $instanceId

        if (-not $result.Success) {
            $failedIds.Add($instanceId)

            Write-Warning @"
Controller konnte nicht aktiviert werden.
InstanceId: $instanceId
$($result.Detail)
"@
        }
    }

    if ($failedIds.Count -gt 0) {
        $failedIds |
            Set-Content `
                -LiteralPath $controllerFile `
                -Force

        return $false
    }

    Remove-Item `
        -LiteralPath $controllerFile `
        -Force `
        -ErrorAction SilentlyContinue

    return $true
}

function Stop-ExistingDisableIO {
    param([switch]$KeepTempScript)

    Remove-DisableIOTask

    if (Test-Path -LiteralPath $pidFile) {
        $savedPid = Get-Content `
            -LiteralPath $pidFile `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($savedPid -match '^\d+$') {
            Stop-IOProcessTree -RootProcessId ([int]$savedPid)
        }
    }

    $controllersRestoredSuccessfully = Restore-SavedControllers

    Remove-Item `
        -LiteralPath $pidFile, $logFile `
        -Force `
        -ErrorAction SilentlyContinue

    if (-not $controllersRestoredSuccessfully) {
        Write-Warning (
            'Mindestens ein Controller blieb deaktiviert. ' +
            "Die Wiederherstellungsdaten bleiben unter $workRoot erhalten."
        )

        return $false
    }

    if ($KeepTempScript) {
        Get-ChildItem `
            -LiteralPath $workRoot `
            -Force `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -ne $tempScript
            } |
            Remove-Item `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
    }
    else {
        Remove-Item `
            -LiteralPath $workRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    return $true
}

# ============================================================
# SOFORTIGE FREIGABE
# ============================================================

if ($releaseRequested) {
    Write-Host 'Beende DisableIO und stelle Controller wieder her ...'
    $released = Stop-ExistingDisableIO

    if ($released) {
        Write-Host 'Maus, Tastatur und Controller wurden freigegeben.'
    }
    else {
        Write-Warning (
            'Die Hooks wurden beendet, aber mindestens ein Controller ' +
            'konnte nicht automatisch aktiviert werden.'
        )
    }

    return
}

# ============================================================
# BOOTSTRAP: TEMP-KOPIE + TEMPORÄRE AUFGABE
# ============================================================

if (-not $InternalWorker) {
    New-Item `
        -Path $workRoot `
        -ItemType Directory `
        -Force |
        Out-Null

    $currentScriptPath = $null
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        try {
            $currentScriptPath = [IO.Path]::GetFullPath($PSCommandPath)
        }
        catch {
            $currentScriptPath = $null
        }
    }

    $runningFromTemp =
        -not [string]::IsNullOrWhiteSpace($currentScriptPath) -and
        [string]::Equals(
            $currentScriptPath,
            [IO.Path]::GetFullPath($tempScript),
            [StringComparison]::OrdinalIgnoreCase
        )

    $oldRunCleared = Stop-ExistingDisableIO `
        -KeepTempScript:$runningFromTemp

    if (-not $oldRunCleared) {
        throw (
            'Ein zuvor deaktivierter Controller konnte nicht wieder ' +
            'aktiviert werden. Neuer Lauf wurde abgebrochen.'
        )
    }

    New-Item `
        -Path $workRoot `
        -ItemType Directory `
        -Force |
        Out-Null

    if (-not $runningFromTemp) {
        if (
            -not [string]::IsNullOrWhiteSpace($currentScriptPath) -and
            (Test-Path -LiteralPath $currentScriptPath)
        ) {
            Copy-Item `
                -LiteralPath $currentScriptPath `
                -Destination $tempScript `
                -Force
        }
        else {
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri $SourceUrl `
                -OutFile $tempScript
        }
    }

    if (-not (Test-Path -LiteralPath $tempScript)) {
        throw "Temporäre Skriptdatei wurde nicht erstellt: $tempScript"
    }

    $interactiveUser = (
        Get-CimInstance Win32_ComputerSystem
    ).UserName

    if ([string]::IsNullOrWhiteSpace($interactiveUser)) {
        throw 'Kein interaktiv angemeldeter Windows-Benutzer gefunden.'
    }

    $workerArguments = [System.Collections.Generic.List[string]]::new()
    $workerArguments.Add('-NoProfile')
    $workerArguments.Add('-NonInteractive')
    $workerArguments.Add('-ExecutionPolicy Bypass')
    $workerArguments.Add('-WindowStyle Hidden')
    $workerArguments.Add("-File `"$tempScript`"")
    $workerArguments.Add('-InternalWorker')
    $workerArguments.Add("-Duration $Duration")
    $workerArguments.Add("-ControllerDuration $ControllerDuration")

    if (-not $blockMouse) {
        $workerArguments.Add('-NoMouse')
    }

    if (-not $blockKeyboard) {
        $workerArguments.Add('-NoKeyboard')
    }

    if (-not $blockController) {
        $workerArguments.Add('-NoController')
    }

    $action = New-ScheduledTaskAction `
        -Execute "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument ($workerArguments -join ' ') `
        -WorkingDirectory ([IO.Path]::GetTempPath())

    $principal = New-ScheduledTaskPrincipal `
        -UserId $interactiveUser `
        -LogonType Interactive `
        -RunLevel Highest

    $maximumDuration = [Math]::Max(
        $Duration,
        $ControllerDuration
    )

    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (
            New-TimeSpan -Seconds ($maximumDuration + 180)
        ) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -Hidden

    try {
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Principal $principal `
            -Settings $settings `
            -Force |
            Out-Null

        Start-ScheduledTask -TaskName $taskName
    }
    catch {
        Stop-ExistingDisableIO
        throw
    }

    Write-Host "DisableIO wurde für $interactiveUser gestartet."
    Write-Host "Maus/Tastatur: $Duration Sekunden"
    Write-Host "Controller:    $ControllerDuration Sekunden"
    Write-Host "Temp-Ordner:   $workRoot"
    Write-Host ''
    Write-Host 'Notfallfreigabe:'
    Write-Host "`$enableIO=`$true;irm '$SourceUrl'|iex"
    return
}

# ============================================================
# INTERAKTIVER WORKER
# ============================================================

New-Item `
    -Path $workRoot `
    -ItemType Directory `
    -Force |
    Out-Null

$PID |
    Set-Content `
        -LiteralPath $pidFile `
        -Force

Write-Host ''
Write-Host '================ DisableIO ================'
Write-Host "Maus/Tastatur: $Duration Sekunden"
Write-Host "Controller:    $ControllerDuration Sekunden"
Write-Host "Maus:          $blockMouse"
Write-Host "Tastatur:      $blockKeyboard"
Write-Host "Controller:    $blockController"
Write-Host '==========================================='
Write-Host ''

# ============================================================
# MAUSPOSITION FESTHALTEN
# ============================================================

$mousePositionJob = {
    param([int]$Seconds)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $position = [System.Windows.Forms.Cursor]::Position
    $x = $position.X
    $y = $position.Y
    $endTime = [DateTime]::UtcNow.AddSeconds($Seconds)

    while ([DateTime]::UtcNow -lt $endTime) {
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

    private const int WM_MOUSEMOVE   = 0x0200;
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

    private static IntPtr hookId = IntPtr.Zero;
    private static readonly LowLevelMouseProc callback = HookCallback;

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
            DateTime end = DateTime.UtcNow.AddMilliseconds(durationMilliseconds);

            while (DateTime.UtcNow < end)
            {
                MSG message;

                while (PeekMessage(out message, IntPtr.Zero, 0, 0, 1))
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

        return CallNextHookEx(hookId, nCode, wParam, lParam);
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
        uint threadId
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string moduleName);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out MSG message,
        IntPtr window,
        uint minimum,
        uint maximum,
        uint removeMessage
    );

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG message);
}
"@

    [DisableIOMouseHook]::Run($DurationMilliseconds)
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
    private static readonly LowLevelKeyboardProc callback = HookCallback;

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
            DateTime end = DateTime.UtcNow.AddMilliseconds(durationMilliseconds);

            while (DateTime.UtcNow < end)
            {
                MSG message;

                while (PeekMessage(out message, IntPtr.Zero, 0, 0, 1))
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

        return CallNextHookEx(hookId, nCode, wParam, lParam);
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
        uint threadId
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int nCode,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string moduleName);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out MSG message,
        IntPtr window,
        uint minimum,
        uint maximum,
        uint removeMessage
    );

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG message);
}
"@

    [DisableIOKeyboardHook]::Run($DurationMilliseconds)
}

# ============================================================
# AUSFÜHRUNG
#
# Während der gesamten Controller-Zeit wird alle 250 ms erneut
# nach Gamecontrollern gesucht. Dadurch werden auch Controller
# deaktiviert, die erst nach dem Start per USB oder Bluetooth
# verbunden werden.
# ============================================================

$controllerRestoreAttempted = $false
$controllerRestoreSucceeded = $true
$controllerPollMilliseconds = 250

# Verhindert Befehlsfluten, solange Windows einen neu erkannten
# Geräteknoten noch vollständig einrichtet.
$controllerLastAttempt = @{}
$controllerLastWarning = @{}
$controllerSeenAtLeastOnce = $false
$controllerEmptyMessageShown = $false

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

    $startTime = [DateTime]::UtcNow
    $inputEnd = $startTime.AddSeconds($Duration)
    $controllerEnd = $startTime.AddSeconds($ControllerDuration)

    $totalEnd = if ($inputEnd -gt $controllerEnd) {
        $inputEnd
    }
    else {
        $controllerEnd
    }

    if ($blockMouse) {
        Start-Job `
            -Name 'DisableIO-MousePosition' `
            -ScriptBlock $mousePositionJob `
            -ArgumentList $Duration |
            Out-Null

        Start-Job `
            -Name 'DisableIO-MouseHook' `
            -ScriptBlock $mouseHookJob `
            -ArgumentList ($Duration * 1000) |
            Out-Null
    }

    if ($blockKeyboard) {
        Start-Job `
            -Name 'DisableIO-KeyboardHook' `
            -ScriptBlock $keyboardHookJob `
            -ArgumentList ($Duration * 1000) |
            Out-Null
    }

    if ($blockController) {
        Write-Host (
            'Controller-Überwachung aktiv: vorhandene und neu ' +
            'verbundene Controller werden gesperrt.'
        )
    }

    $nextControllerScan = $startTime

    while ([DateTime]::UtcNow -lt $totalEnd) {
        $now = [DateTime]::UtcNow

        # ----------------------------------------------------
        # Vorhandene und neu angeschlossene Controller sperren
        # ----------------------------------------------------

        if (
            $blockController -and
            -not $controllerRestoreAttempted -and
            $now -lt $controllerEnd -and
            $now -ge $nextControllerScan
        ) {
            $targets = @(Get-ControllerTargets)

            if ($targets.Count -eq 0) {
                if (-not $controllerEmptyMessageShown) {
                    Write-Host (
                        'Aktuell kein Gamecontroller erkannt; ' +
                        'Neuanschlüsse werden weiter überwacht.'
                    )
                    $controllerEmptyMessageShown = $true
                }
            }
            else {
                $controllerSeenAtLeastOnce = $true
                $controllerEmptyMessageShown = $false

                foreach ($controller in $targets) {
                    # Die Zeit nach jedem PnP-Aufruf erneut prüfen.
                    $now = [DateTime]::UtcNow
                    if ($now -ge $controllerEnd) {
                        break
                    }

                    $instanceId = [string]$controller.InstanceId
                    if ([string]::IsNullOrWhiteSpace($instanceId)) {
                        continue
                    }

                    # Ein erfolgreicher Disable-Aufruf entfernt das Gerät
                    # normalerweise aus PresentOnly. Solange Windows dies
                    # noch nicht umgesetzt hat, maximal einmal pro Sekunde
                    # erneut versuchen.
                    if ($controllerLastAttempt.ContainsKey($instanceId)) {
                        $elapsed = (
                            $now -
                            [DateTime]$controllerLastAttempt[$instanceId]
                        ).TotalMilliseconds

                        if ($elapsed -lt 1000) {
                            continue
                        }
                    }

                    $controllerLastAttempt[$instanceId] = $now

                    Write-Host (
                        'Deaktiviere Controller: {0}' -f
                        $controller.FriendlyName
                    )
                    Write-Host "InstanceId: $instanceId"

                    $result = Disable-IODevice `
                        -InstanceId $instanceId

                    if ($result.Success) {
                        # Sofort speichern, damit Notfallfreigabe und
                        # Prozessabbruch das Gerät wieder aktivieren können.
                        Save-DisabledControllerId `
                            -InstanceId $instanceId

                        Write-Host (
                            'Controller gesperrt über {0}.' -f
                            $result.Detail
                        )

                        [void]$controllerLastWarning.Remove($instanceId)
                    }
                    else {
                        # Bei noch nicht fertig enumerierten USB-/Bluetooth-
                        # Geräten erneut versuchen, Warnungen aber höchstens
                        # alle fünf Sekunden ausgeben.
                        $showWarning = $true

                        if ($controllerLastWarning.ContainsKey($instanceId)) {
                            $warningElapsed = (
                                $now -
                                [DateTime]$controllerLastWarning[$instanceId]
                            ).TotalSeconds

                            $showWarning = $warningElapsed -ge 5
                        }

                        if ($showWarning) {
                            $controllerLastWarning[$instanceId] = $now

                            Write-Warning @"
Controller konnte noch nicht deaktiviert werden: $($controller.FriendlyName)
InstanceId: $instanceId
$($result.Detail)
Die Überwachung versucht es bis zum Ablauf erneut.
"@
                        }
                    }
                }
            }

            $nextControllerScan = [DateTime]::UtcNow.AddMilliseconds(
                $controllerPollMilliseconds
            )
        }

        # ----------------------------------------------------
        # Controller exakt nach ihrer eigenen Dauer freigeben
        # ----------------------------------------------------

        if (
            -not $controllerRestoreAttempted -and
            $now -ge $controllerEnd
        ) {
            $controllerRestoreSucceeded = Restore-SavedControllers
            $controllerRestoreAttempted = $true

            if ($controllerRestoreSucceeded) {
                if ($controllerSeenAtLeastOnce) {
                    Write-Host (
                        'Controller-Sperre beendet; alle gespeicherten ' +
                        'Controller wurden wieder aktiviert.'
                    )
                }
                else {
                    Write-Host (
                        'Controller-Sperre beendet; während der Laufzeit ' +
                        'wurde kein Controller erkannt.'
                    )
                }
            }
        }

        Start-Sleep -Milliseconds 50
    }
}
finally {
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

    if (-not $controllerRestoreAttempted) {
        $controllerRestoreSucceeded = Restore-SavedControllers
        $controllerRestoreAttempted = $true
    }

    Remove-Item `
        -LiteralPath $pidFile, $logFile `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-DisableIOTask -DoNotStopRunningTask

    if ($controllerRestoreSucceeded) {
        Write-Host 'Alle ausgewählten Eingaben wurden wieder freigegeben.'

        Remove-Item `
            -LiteralPath $workRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
    else {
        Write-Warning (
            'Maus und Tastatur wurden freigegeben, aber mindestens ein ' +
            "Controller blieb deaktiviert. Status: $controllerFile"
        )
    }
}
