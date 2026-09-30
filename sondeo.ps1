#Requires -RunAsAdministrator
<#
    sondeo.ps1 - Sondeo inicial de PC (diagnostico, no remediacion automatica)
    Compatible con Windows PowerShell 5.1 (viene instalada de fabrica en Win10/11).
    Corre como: powershell -ExecutionPolicy Bypass -File .\sondeo.ps1
#>

$ScriptVersion = "0.4.1"
$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host "`n=== $title ===" -ForegroundColor Cyan
}

# ---------- Punto de restauracion ----------
function Ensure-RestorePoint {
    Write-Section "Punto de restauracion"

    do {
        $resp = (Read-Host "Crear punto de restauracion? (y/n)").Trim().ToLowerInvariant()
    } while ($resp -notin @('y', 'n'))

    if ($resp -eq 'n') {
        Write-Host "Creacion del punto de restauracion omitida" -ForegroundColor Yellow
        return [ordered]@{ Status = "OMITIDO"; Timestamp = (Get-Date) }
    }

    try {
        # Windows limita restore points a 1 cada 24h por defecto - lo forzamos a 0.
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -ErrorAction SilentlyContinue

        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Pre-sondeo $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS

        Write-Host "Punto de restauracion creado OK" -ForegroundColor Green
        return [ordered]@{ Status = "OK"; Timestamp = (Get-Date) }
    }
    catch {
        Write-Host "FALLO crear el punto de restauracion: $_" -ForegroundColor Red
        $resp = Read-Host "Continuar sin restore point? (s/n)"
        if ($resp -ne 's') { exit 1 }
        return [ordered]@{ Status = "FALLO"; Error = $_.Exception.Message }
    }
}

# ---------- Hardware / bateria ----------
function Get-HardwareStatus {
    Write-Section "Estado de hardware"

    $disks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus
    $disks | Format-Table -AutoSize | Out-Host

    $batteryReportPath = $null
    $wearPct = $null
    $batteryStatus = "No aplica (sin bateria detectada, equipo de escritorio)"

    if (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue) {
        try {
            $designCap = (Get-CimInstance -Namespace ROOT\WMI -ClassName BatteryStaticData -ErrorAction Stop).DesignedCapacity
            $fullCap   = (Get-CimInstance -Namespace ROOT\WMI -ClassName BatteryFullChargedCapacity -ErrorAction Stop).FullChargedCapacity
            if ($designCap -gt 0 -and $fullCap -gt 0) {
                $wearPct = [math]::Round((1 - ($fullCap / $designCap)) * 100, 1)
                $batteryStatus = "Desgaste: $wearPct%"
                Write-Host "Desgaste de bateria: $wearPct%"
            } else {
                $batteryStatus = "Bateria detectada, pero el driver no expone datos de capacidad (limitacion de WMI del equipo, no del script)"
            }
        } catch {
            $batteryStatus = "Bateria detectada, pero el driver no expone datos de capacidad (limitacion de WMI del equipo, no del script)"
            Write-Host "No se pudo calcular el desgaste de bateria en este equipo."
        }

        $batteryReportPath = "$env:TEMP\batteryreport.html"
        powercfg /batteryreport /output $batteryReportPath | Out-Null
        Write-Host "Reporte de bateria: $batteryReportPath"
    }
    else {
        Write-Host "No se detecto bateria (equipo de escritorio)"
    }

    return [ordered]@{ Disks = $disks; BatteryReport = $batteryReportPath; WearPct = $wearPct; BatteryStatus = $batteryStatus }
}

# ---------- Arranque / persistencia + firmas ----------
function Get-StartupAudit {
    Write-Section "Auditoria de arranque / persistencia"
    $items = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User

    $results = foreach ($item in $items) {
        $exePath = $null
        $expanded = [Environment]::ExpandEnvironmentVariables($item.Command)
        if ($expanded -match '^"([^"]+\.exe)"') { $exePath = $matches[1] }
        elseif ($expanded -match '^(.*?\.exe)\b') { $exePath = $matches[1] }

        $sigStatus = "No resoluble"
        if ($exePath -and (Test-Path -LiteralPath $exePath -ErrorAction SilentlyContinue)) {
            try { $sigStatus = (Get-AuthenticodeSignature -FilePath $exePath).Status }
            catch { $sigStatus = "Error" }
        }

        [PSCustomObject]@{
            Name       = $item.Name
            Location   = $item.Location
            Ruta       = $exePath
            Firma      = $sigStatus
            Sospechoso = ($sigStatus -ne 'Valid')
        }
    }

    $results | Format-Table -AutoSize | Out-Host
    $sospechosos = @($results | Where-Object Sospechoso)
    $color = if ($sospechosos.Count -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host "Items de arranque sin firma valida: $($sospechosos.Count) de $($results.Count)" -ForegroundColor $color

    return $results
}

# ---------- Antivirus instalado ----------
function Get-InstalledAntivirus {
    Write-Section "Antivirus instalado"
    $avList = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
        Select-Object displayName, @{N = 'ProductStateHex'; E = { '0x{0:X6}' -f $_.productState } }

    if (-not $avList) {
        Write-Host "No se pudo leer root\SecurityCenter2 (normal en Windows Server, o revisa permisos)."
    } else {
        $avList | Format-Table -AutoSize | Out-Host
        Write-Host "ProductStateHex es un bitmask propio de Windows - para leer habilitado/actualizado con precision, cruza el hex con la referencia publica de SecurityCenter2 en vez de asumir el significado."
    }
    return $avList
}

# ---------- Inventario de programas ----------
function Get-ProgramInventory {
    Write-Section "Inventario de programas instalados"
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
                # Leemos cada clave por separado: si una tiene un valor con tipo de
                # dato corrupto (comun en equipos con mucho historial de instalaciones/GPO),
                # solo se salta esa, no tumba el inventario completo.
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

# ---------- Eventos criticos ----------
function Get-CriticalEvents {
    Write-Section "Errores criticos (ultimos 7 dias)"
    $raw = @()
    try {
        $raw = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop
    } catch {
        Write-Host "Sin eventos criticos en los ultimos 7 dias (o el log esta vacio)."
    }

    # Agrupamos por Proveedor+Id: una rafaga de 100 filas del mismo error
    # es UNA causa recurrente, no 100 problemas distintos.
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


# ---------- Estado general / activacion ----------
function Get-SystemState {
    Write-Section "Estado general del sistema"
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

# ---------- Escaneo Windows Defender ----------
function Invoke-DefenderScan {
    Write-Section "Escaneo con Windows Defender"
    $status = Get-MpComputerStatus
    Write-Host "Firmas actualizadas: $($status.AntivirusSignatureLastUpdated)"

    # Start-MpScan no tiene timeout y se puede colgar en la fase de reporte a MAPS/nube.
    # Llamamos MpCmdRun.exe directo para poder matarlo si se pasa de tiempo.
    $mpCmdRun = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path $mpCmdRun)) {
        $mpCmdRun = Get-ChildItem "$env:ProgramData\Microsoft\Windows Defender\Platform" -Filter MpCmdRun.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }

    $timeoutSeconds = 600
    $threats = @()
    $resultado = "No ejecutado"

    if ($mpCmdRun -and (Test-Path $mpCmdRun)) {
        Write-Host "Iniciando quick scan via MpCmdRun.exe (timeout: $($timeoutSeconds/60) min)..."
        $proc = Start-Process -FilePath $mpCmdRun -ArgumentList "-Scan -ScanType 1" -PassThru -WindowStyle Hidden
        $terminoATiempo = $proc.WaitForExit($timeoutSeconds * 1000)

        if ($terminoATiempo) {
            $resultado = "Completado (codigo $($proc.ExitCode))"
            $threats = Get-MpThreatDetection
        } else {
            Write-Host "El scan no termino en $($timeoutSeconds/60) min, se aborta para no bloquear el sondeo." -ForegroundColor Yellow
            try { $proc.Kill() } catch {}
            $resultado = "No completado (timeout $($timeoutSeconds/60) min)"
        }
    } else {
        Write-Host "No se encontro MpCmdRun.exe, se omite el scan activo." -ForegroundColor Yellow
        $resultado = "MpCmdRun.exe no encontrado"
    }

    Write-Host "Resultado del scan: $resultado"
    Write-Host "Amenazas detectadas: $($threats.Count)"
    return [ordered]@{ Status = $status; Threats = $threats; Resultado = $resultado }
}

# ---------- Historial local por equipo ----------
function Save-History($data) {
    $dir = "$env:ProgramData\SondeoPC"
    New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $historyPath = "$dir\historial.json"

    $entry = [ordered]@{
        Fecha            = (Get-Date).ToString('s')
        Equipo           = $env:COMPUTERNAME
        VersionScript    = $ScriptVersion
        AmenazasDefender = $data.Defender.Threats.Count
        UptimeDias       = $data.SystemState.UptimeDias
        DesgasteBateria  = $data.Hardware.WearPct
        ItemsSospechosos = @($data.Startup | Where-Object Sospechoso).Count
    }

    $history = @()
    if (Test-Path $historyPath) {
        try { $history = @(Get-Content $historyPath -Raw | ConvertFrom-Json) } catch { $history = @() }
    }
    $history += $entry
    ($history | ConvertTo-Json -Depth 4) | Out-File -FilePath $historyPath -Encoding UTF8

    Write-Host "Historial actualizado: $historyPath ($($history.Count) corridas registradas)"
    return $historyPath
}

# ---------- Semaforo para el resumen ejecutivo ----------
function Get-Semaforo($ok, $textoOk, $textoWarn, $textoFail, $isWarn) {
    if ($ok) { return @{ Clase = 'ok'; Texto = $textoOk } }
    elseif ($isWarn) { return @{ Clase = 'warn'; Texto = $textoWarn } }
    else { return @{ Clase = 'fail'; Texto = $textoFail } }
}

# ---------- Reporte HTML ----------
function New-HtmlReport($data, $historyPath) {
    Write-Section "Generando reporte"
    $outPath = "$env:USERPROFILE\Desktop\sondeo-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    $sospechosos  = @($data.Startup | Where-Object Sospechoso)
    $discosMalos  = @($data.Hardware.Disks | Where-Object { $_.HealthStatus -ne 'Healthy' })
    $eventosCount = @($data.CriticalEvents).Count

    $resumen = @()
    $resumen += Get-Semaforo ($data.Defender.Threats.Count -eq 0) "Sin amenazas" "" "Amenazas detectadas: $($data.Defender.Threats.Count)" $false
    $resumen += Get-Semaforo ($sospechosos.Count -eq 0) "Arranque limpio" "$($sospechosos.Count) items sin firma valida" "$($sospechosos.Count) items sin firma valida" ($sospechosos.Count -gt 0 -and $sospechosos.Count -le 3)
    $resumen += Get-Semaforo ($discosMalos.Count -eq 0) "Discos saludables" "" "Disco(s) con problemas de salud" $false
    if ($null -ne $data.Hardware.WearPct) {
        $resumen += Get-Semaforo ($data.Hardware.WearPct -lt 20) "Bateria OK ($($data.Hardware.WearPct)%)" "Bateria con desgaste ($($data.Hardware.WearPct)%)" "Bateria muy desgastada ($($data.Hardware.WearPct)%)" ($data.Hardware.WearPct -lt 40)
    }
    $resumen += Get-Semaforo ($eventosCount -eq 0) "Sin errores criticos recientes" "$eventosCount causas distintas de error" "$eventosCount causas distintas de error" ($eventosCount -le 5)
    $resumen += Get-Semaforo ($data.SystemState.Activacion -eq 'Activado') "Windows activado" "Activacion desconocida" "Windows no activado" ($data.SystemState.Activacion -eq 'Desconocido')

    $resumenHtml = ($resumen | ForEach-Object { "<li class='$($_.Clase)'>$($_.Texto)</li>" }) -join "`n"

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Reporte de sondeo - $(Get-Date -Format 'dd/MM/yyyy HH:mm')</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; background:#1e1e1e; color:#e0e0e0; padding:2rem; }
  h1 { color:#4fc3f7; }
  h2 { color:#81c784; border-bottom:1px solid #444; padding-bottom:4px; margin-top:2rem; }
  table { border-collapse: collapse; width:100%; margin-top:0.5rem; }
  th, td { border:1px solid #444; padding:6px 10px; text-align:left; font-size:0.9rem; }
  th { background:#2d2d2d; }
  ul.resumen { list-style:none; padding:0; }
  ul.resumen li { padding:6px 10px; margin:4px 0; border-radius:4px; }
  .ok { background:#1b3a1f; color:#81c784; }
  .warn { background:#3a331b; color:#ffb74d; }
  .fail { background:#3a1b1b; color:#e57373; }
  footer { margin-top:2rem; padding-top:1rem; border-top:1px solid #444; font-size:0.8rem; color:#888; }
  input.filtro { width:100%; padding:6px 10px; margin-top:0.5rem; background:#2d2d2d; color:#e0e0e0; border:1px solid #444; border-radius:4px; box-sizing:border-box; }
</style>
</head>
<body>
<h1>Reporte de sondeo inicial</h1>
<p>Generado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') - Equipo: $env:COMPUTERNAME</p>

<h2>Resumen ejecutivo</h2>
<ul class="resumen">
$resumenHtml
</ul>

<h2>Punto de restauracion</h2>
<p>Estado: $($data.RestorePoint.Status)</p>

<h2>Hardware</h2>
$($data.Hardware.Disks | ConvertTo-Html -Fragment)
<p>Estado de bateria: $($data.Hardware.BatteryStatus)</p>

<h2>Arranque / persistencia</h2>
<input type="text" class="filtro" placeholder="Filtrar arranque..." onkeyup="filtrarTabla(this,'tabla-startup')">
<div id="tabla-startup">
$($data.Startup | ConvertTo-Html -Fragment)
</div>

<h2>Antivirus instalado</h2>
$($data.Antivirus | ConvertTo-Html -Fragment)

<h2>Programas instalados</h2>
<input type="text" class="filtro" placeholder="Filtrar programas..." onkeyup="filtrarTabla(this,'tabla-programas')">
<div id="tabla-programas">
$($data.Programs | ConvertTo-Html -Fragment)
</div>

<h2>Errores criticos (7 dias, agrupados por causa)</h2>
<input type="text" class="filtro" placeholder="Filtrar errores..." onkeyup="filtrarTabla(this,'tabla-eventos')">
<div id="tabla-eventos">
$($data.CriticalEvents | ConvertTo-Html -Fragment)
</div>

<h2>Estado general / activacion</h2>
$($data.SystemState | ConvertTo-Html -Fragment)

<h2>Windows Defender</h2>
<p>Firmas actualizadas: $($data.Defender.Status.AntivirusSignatureLastUpdated)</p>
<p>Resultado del scan: $($data.Defender.Resultado)</p>
<p>Amenazas detectadas: $($data.Defender.Threats.Count)</p>
$($data.Defender.Threats | ConvertTo-Html -Fragment)

<footer>Sondeo PC v$ScriptVersion - Historial: $historyPath</footer>

<script>
function filtrarTabla(input, containerId) {
    var filtro = input.value.toLowerCase();
    var filas = document.getElementById(containerId).getElementsByTagName('tr');
    for (var i = 1; i < filas.length; i++) {
        var texto = filas[i].innerText.toLowerCase();
        filas[i].style.display = texto.indexOf(filtro) > -1 ? '' : 'none';
    }
}
</script>
</body>
</html>
"@

    $html | Out-File -FilePath $outPath -Encoding UTF8
    Write-Host "Reporte guardado en: $outPath" -ForegroundColor Green
    Start-Process $outPath
    return $outPath
}

# ==================== MAIN ====================
Write-Host "=== SONDEO INICIAL DE PC (v$ScriptVersion) ===" -ForegroundColor Yellow

$report = [ordered]@{}
$report.RestorePoint   = Ensure-RestorePoint
$report.Hardware       = Get-HardwareStatus
$report.Startup        = Get-StartupAudit
$report.Antivirus      = Get-InstalledAntivirus
$report.Programs       = Get-ProgramInventory
$report.CriticalEvents = Get-CriticalEvents
$report.SystemState    = Get-SystemState
$report.Defender       = Invoke-DefenderScan

$historyPath = Save-History $report
New-HtmlReport $report $historyPath