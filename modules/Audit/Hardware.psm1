<#
    Hardware.psm1
    Salud de disco, espacio libre, temperatura de CPU y bateria (si aplica).
    La temperatura via WMI (MSAcpi_ThermalZoneTemperature) no esta disponible
    en todos los fabricantes; si el driver no la expone, se omite silenciosamente.
#>

function Get-HardwareStatus {
    Write-Host "`n=== Estado de hardware ===" -ForegroundColor Cyan

    # ---------- Discos: salud + espacio libre ----------
    $physicalDisks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus

    $logicalDisks = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Used -ne $null -and $_.Free -ne $null) {
            $total = $_.Used + $_.Free
            $pctLibre = if ($total -gt 0) { [math]::Round(($_.Free / $total) * 100, 1) } else { $null }
            [PSCustomObject]@{
                Unidad   = $_.Name
                TotalGB  = [math]::Round($total / 1GB, 1)
                LibreGB  = [math]::Round($_.Free / 1GB, 1)
                PctLibre = $pctLibre
            }
        }
    }

    # Enriquecer physicalDisks con el PctLibre de la unidad correspondiente no es directo
    # (PhysicalDisk no mapea directamente a letra). Mostramos las dos tablas por separado.
    $disks = $physicalDisks
    $disks | Format-Table -AutoSize | Out-Host

    Write-Host "Espacio en unidades logicas:" -ForegroundColor Cyan
    $logicalDisks | Format-Table -AutoSize | Out-Host

    $discosLlenos = @($logicalDisks | Where-Object { $_.PctLibre -ne $null -and $_.PctLibre -lt 10 })
    if ($discosLlenos.Count -gt 0) {
        Write-Host "ATENCION: $($discosLlenos.Count) unidad(es) con menos del 10% de espacio libre." -ForegroundColor Yellow
    }

    # ---------- Temperatura de CPU ----------
    $tempCPU = $null
    try {
        $thermalZones = Get-CimInstance -Namespace 'root\wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        if ($thermalZones) {
            # Convertir de decimas de Kelvin a Celsius: (valor / 10) - 273.15
            $temps = @($thermalZones | ForEach-Object { [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1) })
            $tempCPU = ($temps | Measure-Object -Maximum).Maximum
            Write-Host "Temperatura CPU (zona termica max): $tempCPU C"
            if ($tempCPU -ge 90) { Write-Host "ATENCION: temperatura critica." -ForegroundColor Red }
            elseif ($tempCPU -ge 75) { Write-Host "Temperatura elevada, revisar refrigeracion." -ForegroundColor Yellow }
        }
    } catch {
        Write-Host "Temperatura CPU no disponible via WMI en este equipo (limitacion del driver/fabricante)." -ForegroundColor DarkGray
    }

    # ---------- Bateria ----------
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
    } else {
        Write-Host "No se detecto bateria (equipo de escritorio)"
    }

    return [ordered]@{
        Disks         = $disks
        LogicalDisks  = $logicalDisks
        TempCPU       = $tempCPU
        BatteryReport = $batteryReportPath
        WearPct       = $wearPct
        BatteryStatus = $batteryStatus
    }
}

Export-ModuleMember -Function Get-HardwareStatus
