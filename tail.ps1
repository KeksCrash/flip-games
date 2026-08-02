# Tailscale: stille/headless Windows-Installation
#
# Aufruf:
#   $k='tskey-auth-DEIN_KEY'; irm 'RAW-URL/tailscale-headless.ps1' | iex
#
# Alternativ:
#   $env:TS_AUTHKEY='tskey-auth-DEIN_KEY'; irm 'RAW-URL/tailscale-headless.ps1' | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BaseUrl            = 'https://pkgs.tailscale.com/stable/'
$MsiLog             = Join-Path $env:TEMP 'tailscale-headless-install.log'
$DesiredAdapterName = 'Ethernet'
$DesiredProfileName = 'Netzwerk'

$AuthKey = if ($k) {
    [string]$k
}
elseif ($env:TS_AUTHKEY) {
    [string]$env:TS_AUTHKEY
}
else {
    $null
}

# ============================================================
# TAILSCALE.EXE SUCHEN
# ============================================================

function Find-TailscaleExe {
    $PossiblePaths = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe"
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
        "$env:SystemRoot\System32\tailscale.exe"
    )

    $Found = $PossiblePaths |
        Where-Object {
            $_ -and (Test-Path -LiteralPath $_)
        } |
        Select-Object -First 1

    if (-not $Found) {
        $Command = Get-Command 'tailscale.exe' -ErrorAction SilentlyContinue

        if ($Command) {
            $Found = $Command.Source
        }
    }

    return $Found
}

# ============================================================
# TAILSCALE-ADAPTER UND NETZWERKPROFIL UMBENENNEN
# ============================================================

function Set-TailscaleNetworkNames {
    param(
        [string]$AdapterName = 'Ethernet',
        [string]$ProfileName = 'Netzwerk',
        [int]$TimeoutSeconds = 40
    )

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $TailscaleAdapter = $null

    # Auf den virtuellen Tailscale-Adapter warten.
    do {
        $TailscaleAdapter = Get-NetAdapter `
            -IncludeHidden `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InterfaceDescription -match '(?i)tailscale' -or
                $_.Name -match '(?i)tailscale'
            } |
            Select-Object -First 1

        if (-not $TailscaleAdapter) {
            Start-Sleep -Milliseconds 500
        }
    }
    while (
        -not $TailscaleAdapter -and
        (Get-Date) -lt $Deadline
    )

    if (-not $TailscaleAdapter) {
        throw 'Der Tailscale-Netzwerkadapter wurde nicht gefunden.'
    }

    $MovedAdapterName = $null

    # Ist "Ethernet" bereits vergeben, bestehenden Adapter verschieben.
    $ExistingEthernet = Get-NetAdapter `
        -IncludeHidden `
        -Name $AdapterName `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ifIndex -ne $TailscaleAdapter.ifIndex
        } |
        Select-Object -First 1

    if ($ExistingEthernet) {
        $Number = 2

        do {
            $MovedAdapterName = "$AdapterName $Number"
            $Number++

            $NameAlreadyUsed = Get-NetAdapter `
                -IncludeHidden `
                -Name $MovedAdapterName `
                -ErrorAction SilentlyContinue
        }
        while ($NameAlreadyUsed)

        Rename-NetAdapter `
            -Name $ExistingEthernet.Name `
            -NewName $MovedAdapterName `
            -Confirm:$false `
            -ErrorAction Stop

        Write-Host (
            "Vorhandener Adapter '{0}' wurde zu '{1}' umbenannt." -f
            $AdapterName,
            $MovedAdapterName
        )
    }

    # Tailscale-Adapter zu "Ethernet" umbenennen.
    if ($TailscaleAdapter.Name -ne $AdapterName) {
        Rename-NetAdapter `
            -Name $TailscaleAdapter.Name `
            -NewName $AdapterName `
            -Confirm:$false `
            -ErrorAction Stop
    }

    # Adapter nach der Umbenennung erneut abrufen.
    $TailscaleAdapter = Get-NetAdapter `
        -IncludeHidden `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ifIndex -eq $TailscaleAdapter.ifIndex
        } |
        Select-Object -First 1

    if (-not $TailscaleAdapter -or $TailscaleAdapter.Name -ne $AdapterName) {
        throw "Der Tailscale-Adapter konnte nicht zu '$AdapterName' umbenannt werden."
    }

    # Auf das Windows-Netzwerkprofil warten.
    $ProfileDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ConnectionProfile = $null

    do {
        $ConnectionProfile = Get-NetConnectionProfile `
            -InterfaceIndex $TailscaleAdapter.ifIndex `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $ConnectionProfile) {
            Start-Sleep -Milliseconds 500
        }
    }
    while (
        -not $ConnectionProfile -and
        (Get-Date) -lt $ProfileDeadline
    )

    $ProfilesPath =
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles'

    if (-not (Test-Path -LiteralPath $ProfilesPath)) {
        throw 'Die Windows-Netzwerkprofilliste wurde nicht gefunden.'
    }

    $ProfileEntries = @(
        foreach ($ProfileKey in Get-ChildItem -LiteralPath $ProfilesPath) {
            $Properties = Get-ItemProperty `
                -LiteralPath $ProfileKey.PSPath `
                -ErrorAction SilentlyContinue

            if ($Properties) {
                [pscustomobject]@{
                    Path        = $ProfileKey.PSPath
                    ProfileName = [string]$Properties.ProfileName
                    Description = [string]$Properties.Description
                }
            }
        }
    )

    # Zuerst das aktuell verwendete Profil suchen.
    $RelatedProfiles = @()

    if ($ConnectionProfile) {
        $RelatedProfiles = @(
            $ProfileEntries |
                Where-Object {
                    $_.ProfileName -eq $ConnectionProfile.Name -and
                    (
                        $_.ProfileName -match '(?i)tailscale' -or
                        $_.Description -match '(?i)tailscale'
                    )
                }
        )
    }

    # Fallback: alle eindeutig zu Tailscale gehörenden Profile.
    if ($RelatedProfiles.Count -eq 0) {
        $RelatedProfiles = @(
            $ProfileEntries |
                Where-Object {
                    $_.ProfileName -match '(?i)^tailscale$' -or
                    $_.Description -match '(?i)tailscale'
                }
        )
    }

    if ($RelatedProfiles.Count -eq 0) {
        throw 'Das Tailscale-Netzwerkprofil wurde nicht in der Registry gefunden.'
    }

    foreach ($ProfileEntry in $RelatedProfiles) {
        Set-ItemProperty `
            -LiteralPath $ProfileEntry.Path `
            -Name 'ProfileName' `
            -Value $ProfileName `
            -ErrorAction Stop
    }

    return [pscustomobject]@{
        AdapterName       = $AdapterName
        ProfileName       = $ProfileName
        PreviousEthernet  = $MovedAdapterName
        InterfaceIndex    = $TailscaleAdapter.ifIndex
    }
}

try {
    # ========================================================
    # ADMINISTRATOR PRUEFEN
    # ========================================================

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = New-Object `
        Security.Principal.WindowsPrincipal($Identity)

    $IsAdmin = $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $IsAdmin) {
        throw 'PowerShell muss als Administrator gestartet werden.'
    }

    if (
        [string]::IsNullOrWhiteSpace($AuthKey) -or
        $AuthKey -notlike 'tskey-*'
    ) {
        throw "Auth-Key fehlt. Aufruf: `$k='tskey-auth-...'; irm 'URL' | iex"
    }

    # Architektur bestimmen.
    $Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        'arm64'
    }
    else {
        'amd64'
    }

    # ========================================================
    # INSTALLATION
    # ========================================================

    Write-Host '[1/7] Beende eventuell laufende Tailscale-GUI ...'

    Stop-Process `
        -Name 'tailscale-ipn' `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Host '[2/7] Ermittle aktuelles Tailscale-MSI ...'

    $Page = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri $BaseUrl

    $Pattern =
        'tailscale-setup-[0-9.]+-' +
        [regex]::Escape($Arch) +
        '\.msi'

    $MsiName = [regex]::Matches(
        $Page.Content,
        $Pattern
    ).Value |
        Sort-Object -Unique |
        Sort-Object {
            [version](
                $_ `
                    -replace '^tailscale-setup-', '' `
                    -replace ('-' + $Arch + '\.msi$'), ''
            )
        } -Descending |
        Select-Object -First 1

    if (-not $MsiName) {
        throw "Kein aktuelles $Arch-MSI auf $BaseUrl gefunden."
    }

    $MsiPath = Join-Path $env:TEMP $MsiName
    $MsiUrl  = $BaseUrl + $MsiName

    Write-Host "[3/7] Lade $MsiName herunter ..."

    Invoke-WebRequest `
        -UseBasicParsing `
        -Uri $MsiUrl `
        -OutFile $MsiPath

    if (-not (Test-Path -LiteralPath $MsiPath)) {
        throw 'MSI-Datei wurde nicht heruntergeladen.'
    }

    if ((Get-Item -LiteralPath $MsiPath).Length -lt 1MB) {
        throw 'Die heruntergeladene MSI-Datei ist ungewoehnlich klein.'
    }

    Write-Host '[4/7] Installiere Tailscale vollstaendig still ...'

    $MsiArgs = @(
        '/i'
        "`"$MsiPath`""
        '/qn'
        '/norestart'
        'TS_NOLAUNCH=1'
        "/L*v `"$MsiLog`""
    )

    $Installer = Start-Process `
        -FilePath 'msiexec.exe' `
        -ArgumentList $MsiArgs `
        -Wait `
        -PassThru

    if ($Installer.ExitCode -notin 0, 3010) {
        throw (
            'MSI-Installation fehlgeschlagen: Exitcode {0}. Log: {1}' -f
            $Installer.ExitCode,
            $MsiLog
        )
    }

    $TailscaleExe = Find-TailscaleExe

    if (-not $TailscaleExe) {
        throw "tailscale.exe wurde nicht gefunden. Log: $MsiLog"
    }

    Set-Service `
        -Name 'Tailscale' `
        -StartupType Automatic

    Start-Service `
        -Name 'Tailscale' `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    if ((Get-Service -Name 'Tailscale').Status -ne 'Running') {
        throw 'Der Tailscale-Dienst konnte nicht gestartet werden.'
    }

    # ========================================================
    # ANMELDUNG
    # ========================================================

    Write-Host '[5/7] Melde Geraet ohne Browser und GUI an ...'

    & $TailscaleExe up `
        "--auth-key=$AuthKey" `
        --unattended=true `
        --accept-dns=false

    if ($LASTEXITCODE -ne 0) {
        throw "tailscale up ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
    }

    Stop-Process `
        -Name 'tailscale-ipn' `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-ItemProperty `
        -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'Tailscale' `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    # ========================================================
    # ADAPTER UND PROFIL UMBENENNEN
    # ========================================================

    Write-Host '[6/7] Benenne Netzwerkprofil und Adapter um ...'

    $NetworkNames = Set-TailscaleNetworkNames `
        -AdapterName $DesiredAdapterName `
        -ProfileName $DesiredProfileName `
        -TimeoutSeconds 40

    # ========================================================
    # STATUS PRUEFEN
    # ========================================================

    Write-Host '[7/7] Pruefe Headless-Status ...'

    $Service = Get-Service -Name 'Tailscale'

    $Gui = Get-Process `
        -Name 'tailscale-ipn' `
        -ErrorAction SilentlyContinue

    $Ip = (
        & $TailscaleExe ip -4 2>$null |
            Select-Object -First 1
    )

    $RenamedAdapter = Get-NetAdapter `
        -IncludeHidden `
        -Name $DesiredAdapterName `
        -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host '========== TAILSCALE HEADLESS =========='
    Write-Host "Dienst:            $($Service.Status)"
    Write-Host "GUI:               $(if ($Gui) { 'LAEUFT NOCH' } else { 'Keine GUI' })"
    Write-Host "IPv4:              $Ip"
    Write-Host "Netzwerkprofil:    $($NetworkNames.ProfileName)"
    Write-Host "Adaptername:       $($RenamedAdapter.Name)"

    if ($NetworkNames.PreviousEthernet) {
        Write-Host "Alter Ethernet:    $($NetworkNames.PreviousEthernet)"
    }

    Write-Host ''
    & $TailscaleExe status

    if (
        $Service.Status -ne 'Running' -or
        $Gui -or
        -not $Ip -or
        -not $RenamedAdapter
    ) {
        throw 'Der Headless-Test war nicht vollstaendig erfolgreich.'
    }

    Write-Host ''
    Write-Host 'ERFOLG: Tailscale laeuft headless.'
    Write-Host "Links im Freigabecenter:  $DesiredProfileName"
    Write-Host "Adapter rechts:           $DesiredAdapterName"
}
catch {
    Write-Error $_.Exception.Message

    if (Test-Path -LiteralPath $MsiLog) {
        Write-Host "MSI-Log: $MsiLog"
    }

    throw
}
finally {
    $AuthKey = $null
    $k = $null

    Remove-Item `
        Env:\TS_AUTHKEY `
        -ErrorAction SilentlyContinue
}
