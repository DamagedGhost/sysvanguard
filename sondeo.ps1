#Requires -RunAsAdministrator
<#
    sondeo.ps1 — MVP de sondeo inicial de PC
    Compatible con Windows PowerShell 5.1 (viene instalada de fábrica en Win10/11).
    Corre como: powershell -ExecutionPolicy Bypass -File .\sondeo.ps1
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host "`n=== $title ===" -ForegroundColor Cyan
}

function Ensure-RestorePoint {
    Write-Section "Punto de restauración"
    try {
        # Windows limita restore points a 1 cada 24h por defecto — lo forzamos a 0
        # para garantizar que SIEMPRE se cree uno en cada corrida del sondeo.
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" `
            -Name "SystemRestorePointCreationFrequency" -Value 0 -ErrorAction SilentlyContinue

        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue

        Checkpoint-Computer -Description "Pre-sondeo $(Get-Date -Format 'yyyy-MM-dd HH:mm')" `
            -RestorePointType MODIFY_SETTINGS

        Write-Host "Punto de restauración creado OK" -ForegroundColor Green
        return [ordered]@{ Status = "OK"; Timestamp = (Get-Date) }
    }
    catch {
        Write-Host "FALLÓ crear el punto de restauración: $_" -ForegroundColor Red
        $resp = Read-Host "¿Continuar sin restore point? (s/n)"
        if ($resp -ne 's') { exit 1 }
        return [ordered]@{ Status = "FALLÓ"; Error = $_.Exception.Message }
    }
}

function Get-HardwareStatus {
    Write-Section "Estado de hardware"

    $disks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus
    $disks | Format-Table -AutoSize | Out-Host

    $batteryReportPath = $null
    if (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue) {
        $batteryReportPath = "$env:TEMP\batteryreport.html"
        powercfg /batteryreport /output $batteryReportPath | Out-Null
        Write-Host "Reporte de batería: $batteryReportPath"
    }
    else {
        Write-Host "No se detectó batería (¿es un equipo de escritorio?)"
    }

    return [ordered]@{ Disks = $disks; BatteryReport = $batteryReportPath }
}

function Get-StartupAudit {
    Write-Section "Auditoría de arranque / persistencia"
    # MVP: cmdlet nativo. Cuando integres autorunsc.exe (Sysinternals),
    # reemplaza esta función por el parseo de su salida CSV.
    $items = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
    $items | Format-Table -AutoSize | Out-Host
    return $items
}

function Invoke-DefenderScan {
    Write-Section "Escaneo con Windows Defender"
    $status = Get-MpComputerStatus
    Write-Host "Firmas actualizadas: $($status.AntivirusSignatureLastUpdated)"
    Write-Host "Iniciando quick scan (puede tardar unos minutos)..."
    Start-MpScan -ScanType QuickScan
    $threats = Get-MpThreatDetection
    Write-Host "Amenazas detectadas: $($threats.Count)"
    return [ordered]@{ Status = $status; Threats = $threats }
}

function New-HtmlReport($data) {
    Write-Section "Generando reporte"
    $outPath = "$env:USERPROFILE\Desktop\sondeo-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

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
  .ok { color:#81c784; } .warn { color:#ffb74d; } .fail { color:#e57373; }
</style>
</head>
<body>
<h1>Reporte de sondeo inicial</h1>
<p>Generado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') — Equipo: $env:COMPUTERNAME</p>

<h2>Punto de restauración</h2>
<p>Estado: $($data.RestorePoint.Status)</p>

<h2>Hardware</h2>
$($data.Hardware.Disks | ConvertTo-Html -Fragment)

<h2>Arranque / persistencia</h2>
$($data.Startup | ConvertTo-Html -Fragment)

<h2>Windows Defender</h2>
<p>Firmas actualizadas: $($data.Defender.Status.AntivirusSignatureLastUpdated)</p>
<p>Amenazas detectadas: $($data.Defender.Threats.Count)</p>
$($data.Defender.Threats | ConvertTo-Html -Fragment)

</body>
</html>
"@

    $html | Out-File -FilePath $outPath -Encoding UTF8
    Write-Host "Reporte guardado en: $outPath" -ForegroundColor Green
    Start-Process $outPath
}

# ==================== MAIN ====================
Write-Host "=== SONDEO INICIAL DE PC ===" -ForegroundColor Yellow

$report = [ordered]@{}
$report.RestorePoint = Ensure-RestorePoint
$report.Hardware     = Get-HardwareStatus
$report.Startup      = Get-StartupAudit
$report.Defender     = Invoke-DefenderScan

New-HtmlReport $report