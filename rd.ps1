#requires -Version 5.1

# ==========================================================
# UltraVNC Portable – Reverse-Verbindung
#
# Voraussetzungen:
# - Nur auf eigenen oder ausdrücklich freigegebenen PCs nutzen
# - Auf dem Ziel-PC muss vncviewer.exe im Listen-Modus laufen:
#
#   vncviewer.exe -listen 8080
#
# Das Skript:
# - lädt das offizielle portable UltraVNC-ZIP herunter
# - überprüft den SHA-256-Hash
# - entpackt UltraVNC nach TEMP
# - aktiviert den portablen INI-Modus
# - setzt das VNC-Passwort
# - startet winvnc.exe ohne Dienstinstallation
# - baut eine ausgehende Verbindung zum Viewer auf
# ==========================================================


# ===================== HIER ANPASSEN =======================

$ViewerHost = "0.0.0.0"
$ViewerPort = 5900

# Klassisches VNC-Passwort: maximal 8 Zeichen
$VncPassword = "pass"

# ==========================================================


$Version = "1.8.2.4"

$UltraVncUrl = "https://uvnc.eu/download/1800/UltraVNC_1824.zip"

$PasswordToolUrl = "https://uvnc.eu/download/133/createpassword.zip"

$ExpectedUltraVncSha256 =
    "8AF948089626008F02EDD1254AFC15C814E454EC5FC9E3EAA860356F19D4F113"


# ----------------------------------------------------------
# Portable Ordnerstruktur
# ----------------------------------------------------------

$PortableRoot = Join-Path $env:TEMP "UltraVNC-Portable"

$WorkFolder = Join-Path $PortableRoot $Version

$UltraVncZip = Join-Path `
    $PortableRoot `
    "UltraVNC_1824.zip"

$PasswordToolZip = Join-Path `
    $PortableRoot `
    "createpassword.zip"

$PasswordToolFolder = Join-Path `
    $WorkFolder `
    "PasswordTool"

$TarExe = Join-Path `
    $env:SystemRoot `
    "System32\tar.exe"


$ErrorActionPreference = "Stop"


# ==========================================================
# Hilfsfunktionen
# ==========================================================

function Remove-PathSafely {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {

        Remove-Item `
            -LiteralPath $Path `
            -Recurse `
            -Force `
            -ErrorAction Stop
    }
}


function Download-File {

    param(
        [Parameter(Mandatory)]
        [uri]$Uri,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $DestinationFolder =
        Split-Path -Parent $Destination

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {

        New-Item `
            -ItemType Directory `
            -Path $DestinationFolder `
            -Force |
            Out-Null
    }

    Write-Host "Lade herunter:"
    Write-Host "  $Uri"

    Invoke-WebRequest `
        -Uri $Uri `
        -OutFile $Destination `
        -UseBasicParsing `
        -ErrorAction Stop

    if (-not (
        Test-Path `
            -LiteralPath $Destination `
            -PathType Leaf
    )) {

        throw "Download wurde nicht erstellt: $Destination"
    }

    $DownloadedFile =
        Get-Item -LiteralPath $Destination

    if ($DownloadedFile.Length -le 0) {

        throw "Die heruntergeladene Datei ist leer: $Destination"
    }
}


function Expand-ZipWithTar {

    param(
        [Parameter(Mandatory)]
        [string]$Archive,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {

        New-Item `
            -ItemType Directory `
            -Path $Destination `
            -Force |
            Out-Null
    }

    & $script:TarExe `
        -xf $Archive `
        -C $Destination

    if ($LASTEXITCODE -ne 0) {

        throw @"
Das Archiv konnte nicht entpackt werden.

Archiv:
$Archive

Ziel:
$Destination

tar.exe Exitcode:
$LASTEXITCODE
"@
    }
}


function Stop-UltraVncPortable {

    Get-Process `
        -Name "winvnc" `
        -ErrorAction SilentlyContinue |
        Stop-Process `
            -Force `
            -ErrorAction SilentlyContinue

    Start-Sleep -Milliseconds 700
}


function Get-ArchitectureCandidate {

    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Candidates,

        [Parameter(Mandatory)]
        [bool]$Prefer64Bit
    )

    if ($Prefer64Bit) {

        $Selected = $Candidates |
            Where-Object {
                $_.FullName -match
                '(?i)([\\/](x64|win64|64bit)[\\/])'
            } |
            Select-Object -First 1
    }
    else {

        $Selected = $Candidates |
            Where-Object {
                $_.FullName -match
                '(?i)([\\/](x86|win32|32bit)[\\/])'
            } |
            Select-Object -First 1
    }

    if (-not $Selected -and $Candidates.Count -eq 1) {

        $Selected = $Candidates[0]
    }

    return $Selected
}


# ==========================================================
# Hauptprogramm
# ==========================================================

try {

    Write-Host ""
    Write-Host "UltraVNC Portable $Version"
    Write-Host "============================"
    Write-Host ""


    # ------------------------------------------------------
    # Eingaben prüfen
    # ------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($ViewerHost)) {

        throw "ViewerHost darf nicht leer sein."
    }


    if (
        $ViewerPort -lt 1 -or
        $ViewerPort -gt 65535
    ) {

        throw "Ungültiger Viewer-Port: $ViewerPort"
    }


    if ([string]::IsNullOrWhiteSpace($VncPassword)) {

        throw "Das VNC-Passwort darf nicht leer sein."
    }


    if ($VncPassword.Length -gt 8) {

        throw @"
Das klassische VNC-Passwort darf maximal 8 Zeichen enthalten.

Aktuelle Länge:
$($VncPassword.Length)
"@
    }


    if (-not (
        Test-Path `
            -LiteralPath $TarExe `
            -PathType Leaf
    )) {

        throw "Windows tar.exe wurde nicht gefunden: $TarExe"
    }


    if ($ViewerHost -eq "192.168.2.100") {

        Write-Warning `
            "Prüfe, ob 192.168.2.100 wirklich die IP des Viewer-PCs ist."
    }


    # ------------------------------------------------------
    # Alte portable Instanz beenden
    # ------------------------------------------------------

    Write-Host "Beende eventuell laufende UltraVNC-Instanzen ..."

    Stop-UltraVncPortable


    # ------------------------------------------------------
    # Alte temporäre Dateien löschen
    # ------------------------------------------------------

    Write-Host "Bereinige den alten portablen Ordner ..."

    Remove-PathSafely -Path $WorkFolder
    Remove-PathSafely -Path $UltraVncZip
    Remove-PathSafely -Path $PasswordToolZip


    New-Item `
        -ItemType Directory `
        -Path $PortableRoot `
        -Force |
        Out-Null


    New-Item `
        -ItemType Directory `
        -Path $WorkFolder `
        -Force |
        Out-Null


    # ------------------------------------------------------
    # UltraVNC herunterladen
    # ------------------------------------------------------

    Download-File `
        -Uri $UltraVncUrl `
        -Destination $UltraVncZip


    # ------------------------------------------------------
    # SHA-256 überprüfen
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Prüfe SHA-256 des UltraVNC-Archivs ..."


    $ActualUltraVncSha256 = (
        Get-FileHash `
            -LiteralPath $UltraVncZip `
            -Algorithm SHA256
    ).Hash.ToUpperInvariant()


    if (
        $ActualUltraVncSha256 -ne
        $ExpectedUltraVncSha256
    ) {

        throw @"
Die SHA-256-Prüfung ist fehlgeschlagen.

Erwartet:
$ExpectedUltraVncSha256

Gefunden:
$ActualUltraVncSha256

Die Datei wird nicht ausgeführt.
"@
    }


    Write-Host "SHA-256 korrekt."


    # ------------------------------------------------------
    # UltraVNC entpacken
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Entpacke UltraVNC ..."


    Expand-ZipWithTar `
        -Archive $UltraVncZip `
        -Destination $WorkFolder


    Remove-Item `
        -LiteralPath $UltraVncZip `
        -Force `
        -ErrorAction SilentlyContinue


    # ------------------------------------------------------
    # winvnc.exe suchen
    # ------------------------------------------------------

    $ServerCandidates = @(
        Get-ChildItem `
            -LiteralPath $WorkFolder `
            -Filter "winvnc.exe" `
            -File `
            -Recurse `
            -ErrorAction Stop
    )


    if ($ServerCandidates.Count -eq 0) {

        throw "winvnc.exe wurde im UltraVNC-Archiv nicht gefunden."
    }


    $Server = Get-ArchitectureCandidate `
        -Candidates $ServerCandidates `
        -Prefer64Bit ([Environment]::Is64BitOperatingSystem)


    if (-not $Server) {

        throw @"
Die passende winvnc.exe konnte nicht eindeutig ausgewählt werden.

Gefundene Dateien:
$(
    $ServerCandidates.FullName -join "`r`n"
)
"@
    }


    $ServerExe = $Server.FullName

    $ServerFolder = $Server.DirectoryName

    $IniPath = Join-Path `
        $ServerFolder `
        "ultravnc.ini"

    $PortableMarker = Join-Path `
        $ServerFolder `
        "ultravnc.portable"


    Write-Host ""
    Write-Host "Verwendete Serverdatei:"
    Write-Host "  $ServerExe"


    # ------------------------------------------------------
    # Portablen UltraVNC-Modus aktivieren
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Aktiviere den portablen UltraVNC-Modus ..."


    New-Item `
        -ItemType File `
        -Path $PortableMarker `
        -Force |
        Out-Null


    if (-not (
        Test-Path `
            -LiteralPath $PortableMarker `
            -PathType Leaf
    )) {

        throw "Die Datei ultravnc.portable konnte nicht erstellt werden."
    }


    # ------------------------------------------------------
    # Portable ultravnc.ini erstellen
    # ------------------------------------------------------

    $IniContent = @"
[admin]
UseRegistry=0
AuthRequired=1

AllowShutdown=1
AllowProperties=1
AllowEditClients=1

FileTransferEnabled=1
FTUserImpersonation=1

BlankMonitorEnabled=0
BlankInputsOnly=0

DisableTrayIcon=0

QuerySetting=2
QueryTimeout=10
QueryAccept=0

LoopbackOnly=0
AllowLoopback=1
"@


    Set-Content `
        -LiteralPath $IniPath `
        -Value $IniContent `
        -Encoding ASCII `
        -Force


    if (-not (
        Test-Path `
            -LiteralPath $IniPath `
            -PathType Leaf
    )) {

        throw "ultravnc.ini konnte nicht erstellt werden."
    }


    Write-Host "Portable Konfiguration erstellt:"
    Write-Host "  $IniPath"


    # ------------------------------------------------------
    # Passwortwerkzeug herunterladen
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Lade UltraVNC-Passwortwerkzeug herunter ..."


    New-Item `
        -ItemType Directory `
        -Path $PasswordToolFolder `
        -Force |
        Out-Null


    Download-File `
        -Uri $PasswordToolUrl `
        -Destination $PasswordToolZip


    # ------------------------------------------------------
    # Passwortwerkzeug entpacken
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Entpacke Passwortwerkzeug ..."


    Expand-ZipWithTar `
        -Archive $PasswordToolZip `
        -Destination $PasswordToolFolder


    Remove-Item `
        -LiteralPath $PasswordToolZip `
        -Force `
        -ErrorAction SilentlyContinue


    # ------------------------------------------------------
    # createpassword.exe auswählen
    # ------------------------------------------------------

    $PasswordCandidates = @(
        Get-ChildItem `
            -LiteralPath $PasswordToolFolder `
            -Filter "createpassword.exe" `
            -File `
            -Recurse `
            -ErrorAction Stop
    )


    if ($PasswordCandidates.Count -eq 0) {

        throw "createpassword.exe wurde nicht gefunden."
    }


    $ServerIs64Bit = (
        $ServerExe -match
        '(?i)([\\/](x64|win64|64bit)[\\/])'
    )


    $PasswordTool = Get-ArchitectureCandidate `
        -Candidates $PasswordCandidates `
        -Prefer64Bit $ServerIs64Bit


    if (-not $PasswordTool) {

        throw @"
Die passende createpassword.exe konnte nicht eindeutig ausgewählt werden.

Gefundene Dateien:
$(
    $PasswordCandidates.FullName -join "`r`n"
)
"@
    }


    # createpassword.exe muss im Verzeichnis der ultravnc.ini
    # ausgeführt werden.

    $LocalPasswordTool = Join-Path `
        $ServerFolder `
        "createpassword.exe"


    Copy-Item `
        -LiteralPath $PasswordTool.FullName `
        -Destination $LocalPasswordTool `
        -Force


    # ------------------------------------------------------
    # VNC-Passwort setzen
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Setze das VNC-Passwort ..."


$PasswordProcess = Start-Process `
    -FilePath $LocalPasswordTool `
    -ArgumentList @($VncPassword) `
    -WorkingDirectory $ServerFolder `
    -WindowStyle Hidden `
    -Wait `
    -PassThru


    if ($PasswordProcess.ExitCode -ne 0) {

        throw @"
Das VNC-Passwort konnte nicht gesetzt werden.

Exitcode:
$($PasswordProcess.ExitCode)
"@
    }


    if (-not (
        Test-Path `
            -LiteralPath $IniPath `
            -PathType Leaf
    )) {

        throw "ultravnc.ini wurde nach dem Passwortsetzen nicht gefunden."
    }


    $IniAfterPassword = Get-Content `
        -LiteralPath $IniPath `
        -Raw


    if (
        $IniAfterPassword -notmatch
        '(?im)^\s*passwd\s*=' -and

        $IniAfterPassword -notmatch
        '(?im)^\s*passwd2\s*=' -and

        $IniAfterPassword -notmatch
        '(?im)^\s*passwd3\s*='
    ) {

        Write-Warning `
            "In ultravnc.ini wurde kein Passwort-Eintrag erkannt."
    }
    else {

        Write-Host "VNC-Passwort wurde gesetzt."
    }


    # Passwortwerkzeug wird nach der Konfiguration nicht mehr benötigt.

    Remove-Item `
        -LiteralPath $LocalPasswordTool `
        -Force `
        -ErrorAction SilentlyContinue


    Remove-PathSafely -Path $PasswordToolFolder


    # ------------------------------------------------------
    # Verbindung zum Viewer testen
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Prüfe Viewer-Port:"
    Write-Host "  $ViewerHost`:$ViewerPort"


    $ViewerPortReachable = Test-NetConnection `
        -ComputerName $ViewerHost `
        -Port $ViewerPort `
        -InformationLevel Quiet `
        -WarningAction SilentlyContinue


    if ($ViewerPortReachable) {

        Write-Host "Viewer-Port ist erreichbar."
    }
    else {

        Write-Warning @"
Der Viewer-Port $ViewerHost`:$ViewerPort ist momentan nicht erreichbar.

Starte auf dem Viewer-PC zunächst:

vncviewer.exe -listen $ViewerPort

Prüfe außerdem die Windows-Firewall des Viewer-PCs.
Der UltraVNC-Server wird trotzdem gestartet.
"@
    }


    # ------------------------------------------------------
    # Portable UltraVNC-Instanz starten
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Starte portablen UltraVNC-Server ..."


    $ServerProcess = Start-Process `
        -FilePath $ServerExe `
        -ArgumentList "-run" `
        -WorkingDirectory $ServerFolder `
        -PassThru


    Start-Sleep -Seconds 3


    $ServerProcess.Refresh()


    if ($ServerProcess.HasExited) {

        throw @"
winvnc.exe wurde unerwartet beendet.

Exitcode:
$($ServerProcess.ExitCode)
"@
    }


    # ------------------------------------------------------
    # Reverse-Verbindung zum Viewer aufbauen
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Stelle Verbindung her:"
    Write-Host "  $ViewerHost`::$ViewerPort"


    Start-Process `
        -FilePath $ServerExe `
        -ArgumentList @(
            "-connect",
            "$ViewerHost`::$ViewerPort"
        ) `
        -WorkingDirectory $ServerFolder |
        Out-Null


    Start-Sleep -Seconds 3


    # ------------------------------------------------------
    # Laufenden Server prüfen
    # ------------------------------------------------------

    $RunningServerProcesses = @(
        Get-Process `
            -Name "winvnc" `
            -ErrorAction SilentlyContinue
    )


    if ($RunningServerProcesses.Count -eq 0) {

        throw "Nach dem Start wurde kein laufender winvnc-Prozess gefunden."
    }


    # ------------------------------------------------------
    # Abschluss
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "============================================"
    Write-Host "UltraVNC Portable läuft."
    Write-Host "============================================"
    Write-Host ""
    Write-Host "Version:        $Version"
    Write-Host "Viewer-Ziel:    $ViewerHost`::$ViewerPort"
    Write-Host "Passwort:       gesetzt"
    Write-Host "Portable Ordner:"
    Write-Host "  $ServerFolder"
    Write-Host ""
    Write-Host "PID:"
    Write-Host "  $($RunningServerProcesses.Id -join ', ')"
    Write-Host ""
    Write-Host "Es wurde kein UltraVNC-Dienst installiert."
    Write-Host "Es wurde kein Autostart-Eintrag erstellt."
    Write-Host "Die Konfiguration liegt neben winvnc.exe."
}
catch {

    Write-Host ""
    Write-Error $_.Exception.Message


    Remove-Item `
        -LiteralPath $UltraVncZip `
        -Force `
        -ErrorAction SilentlyContinue


    Remove-Item `
        -LiteralPath $PasswordToolZip `
        -Force `
        -ErrorAction SilentlyContinue


    exit 1
}
