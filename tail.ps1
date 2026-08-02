# Tailscale: stille/headless Windows-Installation
# Aufruf:
#   $k='tskey-auth-DEIN_KEY'; irm 'RAW-URL/tailscale-headless.ps1' | iex
# Alternativ:
#   $env:TS_AUTHKEY='tskey-auth-DEIN_KEY'; irm 'RAW-URL/tailscale-headless.ps1' | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BaseUrl = 'https://pkgs.tailscale.com/stable/'
$MsiLog  = Join-Path $env:TEMP 'tailscale-headless-install.log'
$AuthKey = if ($k) { [string]$k } elseif ($env:TS_AUTHKEY) { [string]$env:TS_AUTHKEY } else { $null }

try {
    $Identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    $IsAdmin   = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $IsAdmin) {
        throw 'PowerShell muss als Administrator gestartet werden.'
    }

    if ([string]::IsNullOrWhiteSpace($AuthKey) -or $AuthKey -notlike 'tskey-*') {
        throw "Auth-Key fehlt. Aufruf: `$k='tskey-auth-...'; irm 'URL' | iex"
    }

    # Architektur bestimmen
    $Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }

    Write-Host '[1/6] Beende eventuell laufende Tailscale-GUI ...'
    Stop-Process -Name 'tailscale-ipn' -Force -ErrorAction SilentlyContinue

    Write-Host '[2/6] Ermittle aktuelles Tailscale-MSI ...'
    $Page = Invoke-WebRequest -UseBasicParsing -Uri $BaseUrl

    $Pattern = 'tailscale-setup-[0-9.]+-' + [regex]::Escape($Arch) + '\.msi'
    $MsiName = [regex]::Matches($Page.Content, $Pattern).Value |
        Sort-Object -Unique |
        Sort-Object {
            [version]($_ -replace '^tailscale-setup-', '' -replace ('-' + $Arch + '\.msi$'), '')
        } -Descending |
        Select-Object -First 1

    if (-not $MsiName) {
        throw "Kein aktuelles $Arch-MSI auf $BaseUrl gefunden."
    }

    $MsiPath = Join-Path $env:TEMP $MsiName
    $MsiUrl  = $BaseUrl + $MsiName

    Write-Host "[3/6] Lade $MsiName herunter ..."
    Invoke-WebRequest -UseBasicParsing -Uri $MsiUrl -OutFile $MsiPath

    if (-not (Test-Path -LiteralPath $MsiPath)) {
        throw 'MSI-Datei wurde nicht heruntergeladen.'
    }

    if ((Get-Item -LiteralPath $MsiPath).Length -lt 1MB) {
        throw 'Die heruntergeladene MSI-Datei ist ungewöhnlich klein.'
    }

    Write-Host '[4/6] Installiere Tailscale vollständig still ...'
    $MsiArgs = @(
        '/i'
        "`"$MsiPath`""
        '/qn'
        '/norestart'
        'TS_NOLAUNCH=1'
        "/L*v `"$MsiLog`""
    )

    $Installer = Start-Process -FilePath 'msiexec.exe' -ArgumentList $MsiArgs -Wait -PassThru

    if ($Installer.ExitCode -notin 0, 3010) {
        throw "MSI-Installation fehlgeschlagen: Exitcode $($Installer.ExitCode). Log: $MsiLog"
    }

    $TailscaleExe = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe"
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
        "$env:SystemRoot\System32\tailscale.exe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

    if (-not $TailscaleExe) {
        $Cmd = Get-Command 'tailscale.exe' -ErrorAction SilentlyContinue
        if ($Cmd) { $TailscaleExe = $Cmd.Source }
    }

    if (-not $TailscaleExe) {
        throw "tailscale.exe wurde nach der Installation nicht gefunden. Log: $MsiLog"
    }

    Set-Service -Name 'Tailscale' -StartupType Automatic
    Start-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if ((Get-Service -Name 'Tailscale').Status -ne 'Running') {
        throw 'Der Tailscale-Dienst konnte nicht gestartet werden.'
    }

    Write-Host '[5/6] Melde Gerät ohne Browser und GUI an ...'
    & $TailscaleExe up "--auth-key=$AuthKey" --unattended=true --accept-dns=false

    if ($LASTEXITCODE -ne 0) {
        throw "tailscale up ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
    }

    # GUI schließen und Benutzer-Autostart entfernen; Dienst bleibt aktiv.
    Stop-Process -Name 'tailscale-ipn' -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Tailscale' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Host '[6/6] Prüfe Headless-Status ...'
    $Service = Get-Service -Name 'Tailscale'
    $Gui     = Get-Process -Name 'tailscale-ipn' -ErrorAction SilentlyContinue
    $Ip      = (& $TailscaleExe ip -4 2>$null | Select-Object -First 1)

    Write-Host ''
    Write-Host '========== TAILSCALE HEADLESS =========='
    Write-Host "Dienst: $($Service.Status)"
    Write-Host "GUI:    $(if ($Gui) { 'LÄUFT NOCH' } else { 'Keine GUI' })"
    Write-Host "IPv4:   $Ip"
    Write-Host ''
    & $TailscaleExe status

    if ($Service.Status -ne 'Running' -or $Gui -or -not $Ip) {
        throw 'Der Headless-Test war nicht vollständig erfolgreich.'
    }

    Write-Host ''
    Write-Host 'ERFOLG: Tailscale ist still installiert, angemeldet und läuft headless.'
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
    Remove-Item Env:\TS_AUTHKEY -ErrorAction SilentlyContinue
}
