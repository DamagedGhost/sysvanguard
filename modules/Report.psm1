<#
    Report.psm1
    Historial local por equipo + reporte HTML.
    Las secciones se generan dinamicamente segun que llaves existan en
    $data: si un preset no corrio Defender, no aparece un header vacio.
#>

function Get-Semaforo($ok, $textoOk, $textoWarn, $textoFail, $isWarn) {
    if ($ok) { return @{ Clase = 'ok'; Texto = $textoOk } }
    elseif ($isWarn) { return @{ Clase = 'warn'; Texto = $textoWarn } }
    else { return @{ Clase = 'fail'; Texto = $textoFail } }
}

function Save-History($data, $scriptVersion) {
    $dir = "$env:ProgramData\SondeoPC"
    New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $historyPath = "$dir\historial.json"

    $entry = [ordered]@{
        Fecha            = (Get-Date).ToString('s')
        Equipo           = $env:COMPUTERNAME
        VersionScript    = $scriptVersion
        AmenazasDefender = if ($data.Contains('Defender')) { $data.Defender.Threats.Count } else { $null }
        UptimeDias       = if ($data.Contains('SystemState')) { $data.SystemState.UptimeDias } else { $null }
        DesgasteBateria  = if ($data.Contains('Hardware')) { $data.Hardware.WearPct } else { $null }
        ItemsSospechosos = if ($data.Contains('Persistence')) { @($data.Persistence | Where-Object Sospechoso).Count } else { $null }
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

function New-HtmlReport($data, $historyPath, $scriptVersion) {
    Write-Host "`n=== Generando reporte ===" -ForegroundColor Cyan
    $outPath = "$env:USERPROFILE\Desktop\sondeo-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

    # ---------- Resumen ejecutivo: solo evalua lo que efectivamente corrio ----------
    $resumen = @()

    if ($data.Contains('Defender')) {
        $resumen += Get-Semaforo ($data.Defender.Threats.Count -eq 0) "Sin amenazas" "" "Amenazas detectadas: $($data.Defender.Threats.Count)" $false
    }
    if ($data.Contains('Persistence')) {
        $sospechosos = @($data.Persistence | Where-Object Sospechoso)
        $resumen += Get-Semaforo ($sospechosos.Count -eq 0) "Arranque limpio" "$($sospechosos.Count) items sin firma valida" "$($sospechosos.Count) items sin firma valida" ($sospechosos.Count -gt 0 -and $sospechosos.Count -le 3)
    }
    if ($data.Contains('Hardware')) {
        $discosMalos = @($data.Hardware.Disks | Where-Object { $_.HealthStatus -ne 'Healthy' })
        $resumen += Get-Semaforo ($discosMalos.Count -eq 0) "Discos saludables" "" "Disco(s) con problemas de salud" $false
        if ($null -ne $data.Hardware.WearPct) {
            $resumen += Get-Semaforo ($data.Hardware.WearPct -lt 20) "Bateria OK ($($data.Hardware.WearPct)%)" "Bateria con desgaste ($($data.Hardware.WearPct)%)" "Bateria muy desgastada ($($data.Hardware.WearPct)%)" ($data.Hardware.WearPct -lt 40)
        }
    }
    if ($data.Contains('CriticalEvents')) {
        $eventosCount = @($data.CriticalEvents).Count
        $resumen += Get-Semaforo ($eventosCount -eq 0) "Sin errores criticos recientes" "$eventosCount causas distintas de error" "$eventosCount causas distintas de error" ($eventosCount -le 5)
    }
    if ($data.Contains('SystemState')) {
        $resumen += Get-Semaforo ($data.SystemState.Activacion -eq 'Activado') "Windows activado" "Activacion desconocida" "Windows no activado" ($data.SystemState.Activacion -eq 'Desconocido')
    }

    $resumenHtml = ($resumen | ForEach-Object { "<li class='$($_.Clase)'>$($_.Texto)</li>" }) -join "`n"

    # ---------- Secciones dinamicas ----------
    $secciones = "<h2>Punto de restauracion</h2>`n<p>Estado: $($data.RestorePoint.Status)</p>`n"

    if ($data.Contains('Hardware')) {
        $secciones += "<h2>Hardware</h2>`n$($data.Hardware.Disks | ConvertTo-Html -Fragment)`n<p>Estado de bateria: $($data.Hardware.BatteryStatus)</p>`n"
    }
    if ($data.Contains('Persistence')) {
        $secciones += "<h2>Arranque / persistencia</h2>`n<input type='text' class='filtro' placeholder='Filtrar arranque...' onkeyup=`"filtrarTabla(this,'tabla-startup')`">`n<div id='tabla-startup'>`n$($data.Persistence | ConvertTo-Html -Fragment)`n</div>`n"
    }
    if ($data.Contains('Antivirus')) {
        $secciones += "<h2>Antivirus instalado</h2>`n$($data.Antivirus | ConvertTo-Html -Fragment)`n"
    }
    if ($data.Contains('Programs')) {
        $secciones += "<h2>Programas instalados</h2>`n<input type='text' class='filtro' placeholder='Filtrar programas...' onkeyup=`"filtrarTabla(this,'tabla-programas')`">`n<div id='tabla-programas'>`n$($data.Programs | ConvertTo-Html -Fragment)`n</div>`n"
    }
    if ($data.Contains('CriticalEvents')) {
        $secciones += "<h2>Errores criticos (agrupados por causa)</h2>`n<input type='text' class='filtro' placeholder='Filtrar errores...' onkeyup=`"filtrarTabla(this,'tabla-eventos')`">`n<div id='tabla-eventos'>`n$($data.CriticalEvents | ConvertTo-Html -Fragment)`n</div>`n"
    }
    if ($data.Contains('SystemState')) {
        $secciones += "<h2>Estado general / activacion</h2>`n$($data.SystemState | ConvertTo-Html -Fragment)`n"
    }
    if ($data.Contains('Defender')) {
        $secciones += "<h2>Windows Defender</h2>`n<p>Firmas actualizadas: $($data.Defender.Status.AntivirusSignatureLastUpdated)</p>`n<p>Resultado del scan: $($data.Defender.Resultado)</p>`n<p>Amenazas detectadas: $($data.Defender.Threats.Count)</p>`n$($data.Defender.Threats | ConvertTo-Html -Fragment)`n"
    }

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

$secciones

<footer>SysVanguard v$scriptVersion - Historial: $historyPath</footer>

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

Export-ModuleMember -Function Get-Semaforo, Save-History, New-HtmlReport
