<#
    SystemState.psm1
    Estado general (uptime/activacion), inventario de programas y
    errores criticos agrupados por causa (Proveedor+Id), no por fila cruda.
#>

function Get-SystemState {
    Write-Host "`n=== Estado general del sistema ===" -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    $lastUpdate = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1

    $activation = "Desconocido"
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND LicenseStatus=1" -ErrorAction Stop
        $activation = if ($lic) { "Activado" } else { "No activado" }
    } catch { }

    $state = [PSCustomObject]@{
        SO             = $os.Caption
        Build          = $os.Version
        UltimoArranque = $os.LastBootUpTime
        UptimeDias     = [math]::Round($uptime.TotalDays, 1)
        UltimoUpdate   = $lastUpdate.InstalledOn
        Activacion     = $activation
    }

    $state | Format-List | Out-Host
    return $state
}

function Get-ProgramInventory {
    Write-Host "`n=== Inventario de programas instalados ===" -ForegroundColor Cyan
    $basePaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $omitidas = 0
    $programs = foreach ($base in $basePaths) {
        $subkeys = Get-ChildItem -Path $base -ErrorAction SilentlyContinue
        foreach ($key in $subkeys) {
            try {
                $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                if ($props.DisplayName) {
                    [PSCustomObject]@{
                        DisplayName    = $props.DisplayName
                        DisplayVersion = $props.DisplayVersion
                        Publisher      = $props.Publisher
                        InstallDate    = $props.InstallDate
                    }
                }
            } catch {
                $omitidas++
            }
        }
    }

    $programs = @($programs | Sort-Object DisplayName -Unique)
    if ($omitidas -gt 0) {
        Write-Host "Se omitieron $omitidas claves de registro ilegibles (dato corrupto)." -ForegroundColor DarkGray
    }

    Write-Host "Programas encontrados: $($programs.Count)"
    return $programs
}

function Get-CriticalEvents {
    Write-Host "`n=== Errores criticos (ultimos 7 dias) ===" -ForegroundColor Cyan
    $raw = @()
    try {
        $raw = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop
    } catch {
        Write-Host "Sin eventos criticos en los ultimos 7 dias (o el log esta vacio)."
    }

    $grouped = @($raw | Group-Object ProviderName, Id | ForEach-Object {
        $primero = $_.Group | Sort-Object TimeCreated | Select-Object -First 1
        $ultimo  = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        [PSCustomObject]@{
            ProviderName = $primero.ProviderName
            Id           = $primero.Id
            Ocurrencias  = $_.Count
            PrimeraVez   = $primero.TimeCreated
            UltimaVez    = $ultimo.TimeCreated
            Mensaje      = $primero.Message.Substring(0, [Math]::Min(150, $primero.Message.Length))
        }
    } | Sort-Object Ocurrencias -Descending)

    Write-Host "Eventos criticos: $($raw.Count) entradas -> $($grouped.Count) causas distintas"
    return $grouped
}

Export-ModuleMember -Function Get-SystemState, Get-ProgramInventory, Get-CriticalEvents
