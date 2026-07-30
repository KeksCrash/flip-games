[CmdletBinding()]
param(
    [ValidateSet("Run","PackageOnly","Remove")]
    [string]$Mode = "Run",

    [string]$Version = "1.8.2.4",

    [string]$ReverseHost = "192.168.196.30",

    [ValidateRange(1,65535)]
    [int]$ReversePort = 5500,

    [Security.SecureString]$Password,

    [string]$UploadTarget = "root@192.168.196.30:/sd/",

    [switch]$NoUpload
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$taskName = "UVNC-Run-Once"
$versionTag = $Version.Replace(".","")
$tempRoot = Join-Path $env:TEMP "UltraVNC-Portable"
$base = Join-Path $tempRoot $Version
$work = Join-Path $env:TEMP "UltraVNC-Setup-$Version"
$uvncExtract = Join-Path $work "UltraVNC"
$passwordExtract = Join-Path $work "PasswordTools"
$uvncArchive = Join-Path $work "UltraVNC_$versionTag.zip"
$passwordArchive = Join-Path $work "createpassword.zip"
$package = Join-Path $env:TEMP "UltraVNC-Portable-$Version-configured.zip"
$runtimeAppData = Join-Path $env:TEMP "UVNC-AppData-$Version"
$runtimeConfig = Join-Path $runtimeAppData "UltraVNC"
$runScript = Join-Path $base "Run-Interactive.ps1"
$uvncUrl = "https://uvnc.eu/download/1800/UltraVNC_$versionTag.zip"
$passwordUrl = "https://uvnc.eu/download/133/createpassword.zip"

$knownHashes = @{
    UltraVNC_1824 = "8AF948089626008F02EDD1254AFC15C814E454EC5FC9E3EAA860356F19D4F113"
    CreatePassword = "19CDE023E7B97171A9B30F7954DD3B1D9EDA07CB60D604526D6588ABBB7A8410"
    CreatePasswordX86 = "C3369FD7B1BE499A3E7B3A8A6922F745C6EF723ADD6CC67C751C57F8E17AE4BC"
    CreatePasswordX64 = "6FE619CF9C72FB052291D443CF087C97A782B1E123C4A3572543A8C31B6A5AD2"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PeArchitecture {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $reader = $null
    $stream = [IO.File]::Open(
        $LiteralPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        $reader = New-Object IO.BinaryReader($stream)
        if($reader.ReadUInt16() -ne 0x5A4D) {
            return "unknown"
        }

        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if($reader.ReadUInt32() -ne 0x00004550) {
            return "unknown"
        }

        switch($reader.ReadUInt16()) {
            0x014C { return "x86" }
            0x8664 { return "x64" }
            default { return "unknown" }
        }
    }
    finally {
        if($reader) {
            $reader.Dispose()
        }
        $stream.Dispose()
    }
}

function ConvertFrom-SecurePassword {
    param([Parameter(Mandatory)][Security.SecureString]$SecurePassword)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$ExpectedHash,
        [Parameter(Mandatory)][string]$Description
    )

    $actualHash = (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash
    if($actualHash -ne $ExpectedHash) {
        throw "$Description hat eine unerwartete SHA256-Prüfsumme. Erwartet: $ExpectedHash, erhalten: $actualHash"
    }
}

function Stop-TempWinVnc {
    $processes = @(
        Get-CimInstance Win32_Process -Filter "Name='winvnc.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -and
                $_.ExecutablePath.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)
            }
    )

    foreach($process in $processes) {
        Invoke-CimMethod -InputObject $process -MethodName Terminate | Out-Null
    }
}

function Remove-TransientTask {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Remove-GeneratedFiles {
    Stop-TempWinVnc
    Remove-TransientTask
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $runtimeAppData -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $package -Force -ErrorAction SilentlyContinue

    if(Test-Path -LiteralPath $tempRoot) {
        $remaining = @(Get-ChildItem -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue)
        if($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-UltraVncIni {
    param([Parameter(Mandatory)][string]$Directory)

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $Directory "ultravnc.portable") -Force | Out-Null

    $ini = @"
[ultravnc]
passwd=
passwd2=

[admin]
UseRegistry=0
MSLogonRequired=0
NewMSLogon=0
AuthRequired=1
UseDSMPlugin=0
DSMPlugin=
DSMPluginConfig=
SocketConnect=1
HTTPConnect=0
AutoPortSelect=0
PortNumber=5900
HTTPPortNumber=8080
LoopbackOnly=0
AllowLoopback=1
InputsEnabled=1
LocalInputsDisabled=0
FileTransferEnabled=1
FTUserImpersonation=1
QuerySetting=2
QueryTimeout=10
QueryAccept=0
QueryIfNoLogon=0
ConnectPriority=0
IdleTimeout=0
IdleInputTimeout=0
KeepAliveInterval=5
SocketKeepAliveTimeout=10000
DisableTrayIcon=1
DebugMode=2
DebugLevel=10
Avilog=0
Secure=0
RemoveWallpaper=0
RemoveAero=0
RemoveEffects=0
RemoveFontSmoothing=0
BlankMonitorEnabled=0
BlackAlphaBlending=0
primary=1
secondary=0
rdpmode=0

[poll]
TurboMode=1
PollUnderCursor=0
PollForeground=0
PollFullScreen=1
OnlyPollConsole=0
OnlyPollOnEvent=0
MaxCpu=40
EnableDriver=1
EnableHook=1
EnableVirtual=1
autocapt=2
SingleWindow=0
SingleWindowName=
"@

    Set-Content -LiteralPath (Join-Path $Directory "ultravnc.ini") -Value $ini -Encoding ASCII
}

function Get-OfficialPasswordTools {
    $tools = @(
        Get-ChildItem -LiteralPath $passwordExtract -Filter "*.exe" -File -Recurse |
            ForEach-Object {
                [pscustomobject]@{
                    File = $_
                    Architecture = Get-PeArchitecture -LiteralPath $_.FullName
                    Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
            }
    )

    $x86 = $tools | Where-Object {
        $_.File.Name -eq "createpassword.exe" -and
        $_.Architecture -eq "x86" -and
        $_.Hash -eq $knownHashes.CreatePasswordX86
    } | Select-Object -First 1

    $x64 = $tools | Where-Object {
        $_.File.Name -eq "createpassword64.exe" -and
        $_.Architecture -eq "x64" -and
        $_.Hash -eq $knownHashes.CreatePasswordX64
    } | Select-Object -First 1

    if(!$x86 -or !$x64) {
        throw "Das offizielle Archiv enthält nicht die erwarteten, unveränderten x86/x64-Passwortwerkzeuge."
    }

    return @{
        x86 = $x86.File.FullName
        x64 = $x64.File.FullName
    }
}

function Set-PasswordWithOfficialTool {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][string]$PlainPassword,
        [Parameter(Mandatory)][hashtable]$Tools
    )

    $sourceTool = $Tools[$Architecture]
    $toolName = Split-Path $sourceTool -Leaf
    $localTool = Join-Path $Directory $toolName
    Copy-Item -LiteralPath $sourceTool -Destination $localTool -Force

    if((Get-PeArchitecture -LiteralPath $localTool) -ne $Architecture) {
        throw "$toolName passt nicht zur Serverarchitektur $Architecture."
    }

    Push-Location $Directory
    try {
        & $localTool $PlainPassword
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if($null -ne $exitCode -and $exitCode -ne 0) {
        throw "$toolName ist mit Exitcode $exitCode fehlgeschlagen."
    }

    $iniPath = Join-Path $Directory "ultravnc.ini"
    $passwordLine = Get-Content -LiteralPath $iniPath |
        Where-Object { $_ -match '^passwd=[0-9A-Fa-f]{18}$' } |
        Select-Object -First 1

    if(!$passwordLine) {
        throw "$toolName hat keinen gültigen 18-stelligen passwd-Wert in $iniPath erzeugt."
    }

    return $passwordLine.Substring(7).ToUpperInvariant()
}

function Expand-AndConfigureUltraVnc {
    param(
        [Parameter(Mandatory)][string]$PlainPassword,
        [Parameter(Mandatory)][hashtable]$Tools
    )

    New-Item -ItemType Directory -Path $uvncExtract -Force | Out-Null
    Expand-Archive -LiteralPath $uvncArchive -DestinationPath $uvncExtract -Force

    $servers = @(Get-ChildItem -LiteralPath $uvncExtract -Filter "winvnc.exe" -File -Recurse)
    if($servers.Count -eq 0) {
        throw "Das UltraVNC-Archiv enthält keine winvnc.exe."
    }

    $prepared = New-Object Collections.Generic.List[string]
    $generatedHashes = @{}

    foreach($server in $servers) {
        $architecture = Get-PeArchitecture -LiteralPath $server.FullName
        if($architecture -notin @("x86","x64") -or $prepared.Contains($architecture)) {
            continue
        }

        $destination = Join-Path $base $architecture
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path (Join-Path $server.Directory.FullName "*") -Destination $destination -Recurse -Force

        $copiedServer = Join-Path $destination "winvnc.exe"
        if((Get-PeArchitecture -LiteralPath $copiedServer) -ne $architecture) {
            throw "Die kopierte winvnc.exe passt nicht zu $architecture."
        }

        New-UltraVncIni -Directory $destination
        $generatedHashes[$architecture] = Set-PasswordWithOfficialTool `
            -Directory $destination `
            -Architecture $architecture `
            -PlainPassword $PlainPassword `
            -Tools $Tools

        $prepared.Add($architecture)
        Write-Host "${architecture}: offizielles Passwortwerkzeug erfolgreich ausgeführt." -ForegroundColor Green
    }

    if($prepared.Count -eq 0) {
        throw "Keine verwendbare x86- oder x64-Version wurde gefunden."
    }

    if($generatedHashes.Count -gt 1) {
        $uniqueHashes = @($generatedHashes.Values | Select-Object -Unique)
        if($uniqueHashes.Count -ne 1) {
            throw "x86- und x64-Passwortwerkzeug haben unterschiedliche passwd-Werte erzeugt."
        }
    }

    return $prepared
}

function Get-InteractiveUser {
    $userName = (Get-CimInstance Win32_ComputerSystem).UserName
    if(!$userName) {
        $userName = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty UserName
    }
    if(!$userName) {
        throw "Kein interaktiv angemeldeter Windows-Benutzer wurde gefunden."
    }
    return $userName
}

function Start-InteractiveReverseConnection {
    param([Parameter(Mandatory)][string]$Architecture)

    if(!(Test-IsAdministrator)) {
        throw "Der interaktive Start aus einer SSH-Sitzung benötigt Administratorrechte."
    }

    $directory = Join-Path $base $Architecture
    $server = Join-Path $directory "winvnc.exe"
    $ini = Join-Path $directory "ultravnc.ini"
    if(!(Test-Path -LiteralPath $server) -or !(Test-Path -LiteralPath $ini)) {
        throw "Die vorbereitete $Architecture-Version ist unvollständig."
    }

    Stop-TempWinVnc
    Remove-TransientTask
    Remove-Item -LiteralPath $runtimeAppData -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $runtimeConfig -Force | Out-Null
    Copy-Item -LiteralPath $ini -Destination (Join-Path $runtimeConfig "ultravnc.ini") -Force

    $launcher = @"
`$ErrorActionPreference = "Stop"
`$env:APPDATA = "$runtimeAppData"
`$env:LOCALAPPDATA = "$runtimeAppData"
Start-Process -FilePath "$server" -ArgumentList "-autoreconnect","-connect","${ReverseHost}::${ReversePort}","-run" -WorkingDirectory "$directory"
"@
    Set-Content -LiteralPath $runScript -Value $launcher -Encoding UTF8

    $powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $action = New-ScheduledTaskAction `
        -Execute $powerShellExe `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runScript`""

    $principal = New-ScheduledTaskPrincipal `
        -UserId (Get-InteractiveUser) `
        -LogonType Interactive `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Principal $principal `
        -Force | Out-Null

    Start-ScheduledTask -TaskName $taskName

    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 500
        $process = Get-CimInstance Win32_Process -Filter "Name='winvnc.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ExecutablePath -and
                $_.ExecutablePath.Equals($server,[StringComparison]::OrdinalIgnoreCase) -and
                $_.SessionId -ne 0
            } |
            Select-Object -First 1
    } until($process -or (Get-Date) -ge $deadline)

    Remove-TransientTask

    if(!$process) {
        throw "WinVNC wurde nicht im interaktiven Desktop gestartet."
    }

    Write-Host "WinVNC läuft interaktiv in Sitzung $($process.SessionId)." -ForegroundColor Green
    Write-Host "Reverse-Ziel: ${ReverseHost}::$ReversePort" -ForegroundColor Green
    $process | Select-Object ProcessId,SessionId,ExecutablePath,CommandLine
}

if($Mode -eq "Remove") {
    Remove-GeneratedFiles
    Write-Host "Temporäre UltraVNC-Prozesse, Aufgabe und Dateien wurden entfernt." -ForegroundColor Green
    return
}

if($Mode -eq "Run" -and !(Test-IsAdministrator)) {
    throw "Für -Mode Run über SSH sind Administratorrechte erforderlich."
}

if(!$Password) {
    $Password = Read-Host "VNC-Passwort (1 bis 8 druckbare ASCII-Zeichen)" -AsSecureString
}

$plainPassword = ConvertFrom-SecurePassword -SecurePassword $Password
try {
    if([string]::IsNullOrWhiteSpace($plainPassword) -or
       $plainPassword.Length -gt 8 -or
       $plainPassword -notmatch '^[\x21-\x7E]{1,8}$') {
        throw "Das Passwort muss 1 bis 8 druckbare ASCII-Zeichen enthalten."
    }

    Stop-TempWinVnc
    Remove-TransientTask
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $runtimeAppData -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $package -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    Write-Host "Lade UltraVNC $Version und die offiziellen Passwortwerkzeuge ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $uvncUrl -OutFile $uvncArchive -UseBasicParsing
    Invoke-WebRequest -Uri $passwordUrl -OutFile $passwordArchive -UseBasicParsing

    if($Version -eq "1.8.2.4") {
        Assert-FileHash `
            -LiteralPath $uvncArchive `
            -ExpectedHash $knownHashes.UltraVNC_1824 `
            -Description "UltraVNC-Archiv"
    }
    else {
        Write-Warning "Für UltraVNC $Version ist keine feste Archivprüfsumme hinterlegt."
    }

    Assert-FileHash `
        -LiteralPath $passwordArchive `
        -ExpectedHash $knownHashes.CreatePassword `
        -Description "Offizielles createpassword-Archiv"

    New-Item -ItemType Directory -Path $passwordExtract -Force | Out-Null
    Expand-Archive -LiteralPath $passwordArchive -DestinationPath $passwordExtract -Force
    $tools = Get-OfficialPasswordTools
    $prepared = @(Expand-AndConfigureUltraVnc -PlainPassword $plainPassword -Tools $tools)
}
finally {
    $plainPassword = $null
    if($Password) {
        $Password.Dispose()
    }
}

Compress-Archive -Path (Join-Path $base "*") -DestinationPath $package -CompressionLevel Optimal
Write-Host "Installation: $base" -ForegroundColor Green
Write-Host "Archiv:       $package" -ForegroundColor Green
Write-Warning "Das Archiv enthält einen verschleierten VNC-Passwortwert und muss vertraulich behandelt werden."

if(!$NoUpload) {
    $scp = Get-Command scp.exe -ErrorAction SilentlyContinue
    if(!$scp) {
        Write-Warning "scp.exe fehlt; der Upload wurde übersprungen."
    }
    else {
        Write-Host "Übertrage das Archiv nach $UploadTarget ..." -ForegroundColor Cyan
        & $scp.Source $package $UploadTarget
        if($LASTEXITCODE -ne 0) {
            Write-Warning "SCP-Upload fehlgeschlagen (Exitcode $LASTEXITCODE). Der lokale Ablauf wird fortgesetzt."
        }
        else {
            Write-Host "SCP-Upload abgeschlossen." -ForegroundColor Green
        }
    }
}

if($Mode -eq "Run") {
    $selectedArchitecture = if(
        [Environment]::Is64BitOperatingSystem -and
        $prepared -contains "x64"
    ) {
        "x64"
    }
    elseif($prepared -contains "x86") {
        "x86"
    }
    else {
        throw "Keine passende Serverarchitektur wurde vorbereitet."
    }

    Start-InteractiveReverseConnection -Architecture $selectedArchitecture
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Fertig. UltraVNC und seine Laufzeitkonfiguration liegen ausschließlich unter TEMP." -ForegroundColor Green
