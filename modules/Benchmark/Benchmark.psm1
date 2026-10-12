<#
    Benchmark.psm1
    Modulo de medicion de rendimiento cuantitativo en reposo (stand-by / baseline).
    Mide el comportamiento real del sistema en vacio sin realizar modificaciones ni estres destructivo.
#>

function Measure-SystemBaseline {
    param(
        [int]$DurationSeconds = 60,
        [int]$IntervalSeconds = 3
    )

    Write-Host "`n=== Medicion de Rendimiento en Reposo (Stand-by Baseline) ===" -ForegroundColor Cyan
    Write-Host "Duracion del muestreo: $DurationSeconds segundos (intervalo cada $IntervalSeconds s)." -ForegroundColor DarkGray
    Write-Host "Recomendacion: Deje el equipo en reposo sin mover el mouse ni abrir aplicaciones para un resultado limpio.`n" -ForegroundColor DarkGray

    # Snapshot inicial de consumo de CPU por proceso para calcular el Delta exacto durante el reposo
    $startProcs = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        if ($null -ne $_.CPU) {
            $startProcs[$_.Id] = @{ Name = $_.ProcessName; Cpu = $_.CPU }
        }
    }

    $samples = [System.Collections.Generic.List[PSCustomObject]]::new()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $totalRamGB = 0

    while ($sw.Elapsed.TotalSeconds -lt $DurationSeconds) {
        # 1. Uso de CPU instantaneo via contador formateado (rapido y no bloqueante)
        $cpu = 0
        try {
            $cpuInst = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
            if ($cpuInst) { $cpu = [math]::Round($cpuInst.PercentProcessorTime, 0) }
        } catch { $cpu = 0 }

        # 2. Uso de Memoria RAM
        $usedRamGB = 0
        $freeRamGB = 0
        $pctRam = 0
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            if ($os) {
                $totalRamGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                $freeRamGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
                $usedRamGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
                if ($os.TotalVisibleMemorySize -gt 0) {
                    $pctRam = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
                }
            }
        } catch {}

        # 3. Temperatura de CPU (si el driver WMI la expone; silenciosa si no)
        $temp = $null
        try {
            $tz = Get-CimInstance -Namespace 'root\wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
            if ($tz) {
                $temps = @($tz | ForEach-Object { [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1) })
                $temp = ($temps | Measure-Object -Maximum).Maximum
            }
        } catch {}

        # 4. Total de procesos activos
        $procCount = 0
        try { $procCount = (Get-Process -ErrorAction SilentlyContinue).Count } catch {}

        # Guardar muestra
        $samples.Add([PSCustomObject]@{
            Cpu       = $cpu
            RamUsed   = $usedRamGB
            RamFree   = $freeRamGB
            RamPct    = $pctRam
            Temp      = $temp
            ProcCount = $procCount
        })

        $remaining = [math]::Max(0, [int]($DurationSeconds - $sw.Elapsed.TotalSeconds))
        $tempDisplay = if ($null -ne $temp) { " | Temp: $temp C" } else { "" }
        Write-Host ("`r[Muestreo Reposo] Restante: {0,3}s | CPU: {1,2}% | RAM: {2:N1} GB ({3:N0}%){4} | Procesos: {5}" -f $remaining, $cpu, $usedRamGB, $pctRam, $tempDisplay, $procCount) -NoNewline

        Start-Sleep -Seconds $IntervalSeconds
    }

    Write-Host "`n"

    if ($samples.Count -eq 0) {
        Write-Host "No se pudieron recolectar muestras de rendimiento." -ForegroundColor Red
        return $null
    }

    # Calculo estadistico
    $cpuPromedio = [math]::Round(($samples | Measure-Object -Property Cpu -Average).Average, 1)
    $cpuMaximo   = ($samples | Measure-Object -Property Cpu -Maximum).Maximum
    $ramUsoProm  = [math]::Round(($samples | Measure-Object -Property RamUsed -Average).Average, 2)
    $ramLibreProm= [math]::Round(($samples | Measure-Object -Property RamFree -Average).Average, 2)
    $ramPctProm  = [math]::Round(($samples | Measure-Object -Property RamPct -Average).Average, 1)
    $procProm    = [math]::Round(($samples | Measure-Object -Property ProcCount -Average).Average, 0)

    $validTemps = @($samples | Where-Object { $null -ne $_.Temp } | ForEach-Object { $_.Temp })
    $tempProm = if ($validTemps.Count -gt 0) { [math]::Round(($validTemps | Measure-Object -Average).Average, 1) } else { $null }
    $tempMax  = if ($validTemps.Count -gt 0) { ($validTemps | Measure-Object -Maximum).Maximum } else { $null }

    # Calculo de procesos que mas consumieron CPU durante la ventana de muestreo
    $topProcesos = @()
    $currentProcs = Get-Process -ErrorAction SilentlyContinue
    $deltas = foreach ($p in $currentProcs) {
        if ($null -ne $p.CPU -and $startProcs.ContainsKey($p.Id) -and ($null -ne $startProcs[$p.Id].Cpu)) {
            $delta = [math]::Round($p.CPU - $startProcs[$p.Id].Cpu, 2)
            if ($delta -gt 0) {
                [PSCustomObject]@{
                    Proceso        = $p.ProcessName
                    CpuSegundos    = $delta
                    Pid            = $p.Id
                    MemoriaMB      = [math]::Round($p.WorkingSet64 / 1MB, 1)
                }
            }
        }
    }
    if ($deltas) {
        $topProcesos = @($deltas | Sort-Object CpuSegundos -Descending | Select-Object -First 5)
    }

    # Visualizacion en consola
    Write-Host "--- Resumen de la Medicion en Reposo ---" -ForegroundColor Cyan
    Write-Host "  Muestras tomadas: $($samples.Count) ($DurationSeconds s totales)"
    Write-Host "  Uso de CPU en reposo: Promedio $cpuPromedio% (Pico maximo: $cpuMaximo%)"
    Write-Host "  Memoria RAM ocupada:  Promedio $ramUsoProm GB de $totalRamGB GB ($ramPctProm%)"
    if ($null -ne $tempProm) {
        Write-Host "  Temperatura de CPU:   Promedio $tempProm C (Maxima: $tempMax C)"
    } else {
        Write-Host "  Temperatura de CPU:   No disponible via WMI en este equipo." -ForegroundColor DarkGray
    }
    Write-Host "  Procesos activos prom: $procProm"

    if ($topProcesos.Count -gt 0) {
        Write-Host "`nTop procesos con mayor actividad de fondo durante el reposo:" -ForegroundColor Cyan
        $topProcesos | Format-Table -AutoSize | Out-Host
    }

    return [ordered]@{
        DuracionSegundos    = $DurationSeconds
        MuestrasTomadas     = $samples.Count
        CpuPromedio         = $cpuPromedio
        CpuMaximo           = $cpuMaximo
        RamTotalGB          = $totalRamGB
        RamUsoPromedioGB    = $ramUsoProm
        RamLibrePromedioGB  = $ramLibreProm
        RamPctUsoPromedio   = $ramPctProm
        TemperaturaPromedio = $tempProm
        TemperaturaMaxima   = $tempMax
        ProcesosPromedio    = $procProm
        TopProcesos         = $topProcesos
    }
}

Export-ModuleMember -Function Measure-SystemBaseline
