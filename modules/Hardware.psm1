<#
    Hardware.psm1
    Salud de disco y bateria (si aplica).
#>

function Get-HardwareStatus {
    Write-Host "`n=== Estado de hardware ===" -ForegroundColor Cyan

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

Export-ModuleMember -Function Get-HardwareStatus
