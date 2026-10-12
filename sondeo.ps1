#Requires -RunAsAdministrator
<#
    sondeo.ps1 - Orquestador de SysVanguard
    Menu interactivo de presets (config/presets.psd1) + punto de
    restauracion como decision de sesion (no de preset, no de tweaks).
    Compatible con Windows PowerShell 5.1.

    Parametros:
        -Preset <nombre>   Salta el menu interactivo y ejecuta el preset indicado.
                           Nombres disponibles en config/presets.psd1 (ej: Rapido, Completo).
#>
param(
    [Alias("Preset")]
    [string]$PresetName = ""
)

$ScriptVersion = "0.6.0"
# Continue: errores no fatales no matan el script; cada modulo maneja sus propios try/catch.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Get-ChildItem "$root\modules\*.psm1" -Recurse | ForEach-Object { Import-Module $_.FullName -Force }
$presets = Import-PowerShellDataFile "$root\config\presets.psd1"

# Mapa paso->funcion. SystemState se maneja aparte porque en realidad
# dispara tres funciones (SystemState, CriticalEvents, Programs) para
# no perder granularidad en el reporte.
$stepMap = [ordered]@{
    Hardware    = { Get-HardwareStatus }
    Persistence = { Get-StartupAudit }
    Antivirus   = { Get-InstalledAntivirus }
    Defender    = { Invoke-DefenderScan }
}

function Show-Menu {
    param([string]$NombrePreset = "")

    # Si se paso preset por CLI, usarlo directamente sin interaccion
    if ($NombrePreset -and $presets.Contains($NombrePreset)) {
        Write-Host "`n=== SONDEO SYSVANGUARD (v$ScriptVersion) ===" -ForegroundColor Yellow
        Write-Host "Preset seleccionado via parametro: $NombrePreset" -ForegroundColor DarkGray
        return $presets[$NombrePreset]
    }
    if ($NombrePreset -and -not $presets.Contains($NombrePreset)) {
        Write-Host "Preset '$NombrePreset' no encontrado. Presets disponibles: $($presets.Keys -join ', ')" -ForegroundColor Red
    }

    Write-Host "`n=== SONDEO SYSVANGUARD (v$ScriptVersion) ===" -ForegroundColor Yellow
    $keys = @($presets.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        Write-Host "$($i + 1)) $($keys[$i]) - $($presets[$keys[$i]].Descripcion)"
    }
    $sel = Read-Host "Elige un preset (numero)"
    $idx = 0
    [void][int]::TryParse($sel, [ref]$idx)
    $idx = $idx - 1
    if ($idx -lt 0 -or $idx -ge $keys.Count) {
        Write-Host "Opcion invalida, usando 'Completo' por defecto." -ForegroundColor Yellow
        return $presets['Completo']
    }
    return $presets[$keys[$idx]]
}

$presetActivo = Show-Menu -NombrePreset $PresetName
$report = [ordered]@{}

# ---------- Punto de restauracion: decision de sesion, no de preset ----------
if (Test-RestorePointToday) {
    Write-Host "Ya existe un punto de restauracion de hoy, se omite la pregunta." -ForegroundColor DarkGray
    $report.RestorePoint = [ordered]@{ Status = "Omitido"; Motivo = "Ya existia uno de hoy" }
} else {
    $resp = Read-Host "Crear punto de restauracion antes de continuar? (s/n)"
    if ($resp -eq 's') {
        $report.RestorePoint = Ensure-RestorePoint -Forzar
    } else {
        $report.RestorePoint = [ordered]@{ Status = "Omitido por el usuario" }
    }
}

# ---------- Pasos del preset elegido ----------
foreach ($pasoNombre in $presetActivo.Pasos) {
    if ($pasoNombre -eq 'SystemState') {
        $report.SystemState    = Get-SystemState
        $report.CriticalEvents = Get-CriticalEvents
        $report.Programs       = Get-ProgramInventory
    }
    elseif ($stepMap.Contains($pasoNombre)) {
        $report[$pasoNombre] = & $stepMap[$pasoNombre]
    }
    else {
        Write-Host "Paso desconocido en el preset: $pasoNombre" -ForegroundColor Red
    }
}

$historyPath = Save-History $report $ScriptVersion

# ---------- Resumen final en consola ----------
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  RESUMEN DEL SONDEO - $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

if ($report.Contains('Defender')) {
    $c = $report.Defender.Threats.Count
    if ($c -eq 0) { Write-Host "  [OK]   Defender: sin amenazas" -ForegroundColor Green }
    else           { Write-Host "  [ALERTA] Defender: $c amenaza(s) detectada(s)" -ForegroundColor Red }
}
if ($report.Contains('Persistence')) {
    $s = @($report.Persistence | Where-Object Sospechoso).Count
    if ($s -eq 0)       { Write-Host "  [OK]   Arranque: todos los items firmados" -ForegroundColor Green }
    elseif ($s -le 3)   { Write-Host "  [WARN] Arranque: $s item(s) sin firma valida" -ForegroundColor Yellow }
    else                { Write-Host "  [ALERTA] Arranque: $s items sin firma valida" -ForegroundColor Red }
}
if ($report.Contains('Hardware')) {
    $discosMalos = @($report.Hardware.Disks | Where-Object { $_.HealthStatus -ne 'Healthy' }).Count
    if ($discosMalos -eq 0) { Write-Host "  [OK]   Discos: saludables" -ForegroundColor Green }
    else                    { Write-Host "  [ALERTA] Discos: $discosMalos disco(s) con problemas" -ForegroundColor Red }

    if ($null -ne $report.Hardware.WearPct) {
        $w = $report.Hardware.WearPct
        if ($w -lt 20)    { Write-Host "  [OK]   Bateria: desgaste $w%" -ForegroundColor Green }
        elseif ($w -lt 40){ Write-Host "  [WARN] Bateria: desgaste $w%" -ForegroundColor Yellow }
        else               { Write-Host "  [ALERTA] Bateria: desgaste $w% (critico)" -ForegroundColor Red }
    }
    if ($null -ne $report.Hardware.TempCPU) {
        $t = $report.Hardware.TempCPU
        if ($t -lt 75)    { Write-Host "  [OK]   CPU: $t C" -ForegroundColor Green }
        elseif ($t -lt 90){ Write-Host "  [WARN] CPU: temperatura alta ($t C)" -ForegroundColor Yellow }
        else               { Write-Host "  [ALERTA] CPU: temperatura critica ($t C)" -ForegroundColor Red }
    }
    if ($report.Hardware.LogicalDisks) {
        $discosLlenos = @($report.Hardware.LogicalDisks | Where-Object { $_.PctLibre -ne $null -and $_.PctLibre -lt 10 }).Count
        if ($discosLlenos -gt 0) { Write-Host "  [WARN] Espacio: $discosLlenos unidad(es) con menos del 10% libre" -ForegroundColor Yellow }
    }
}
if ($report.Contains('CriticalEvents')) {
    $e = @($report.CriticalEvents).Count
    if ($e -eq 0)     { Write-Host "  [OK]   Eventos: sin errores criticos recientes" -ForegroundColor Green }
    elseif ($e -le 5) { Write-Host "  [WARN] Eventos: $e causa(s) de error en los ultimos 7 dias" -ForegroundColor Yellow }
    else              { Write-Host "  [ALERTA] Eventos: $e causas de error critico recientes" -ForegroundColor Red }
}
if ($report.Contains('SystemState')) {
    $act = $report.SystemState.Activacion
    if ($act -eq 'Activado')     { Write-Host "  [OK]   Windows: activado" -ForegroundColor Green }
    elseif ($act -eq 'Desconocido') { Write-Host "  [WARN] Windows: estado de activacion desconocido" -ForegroundColor Yellow }
    else                          { Write-Host "  [ALERTA] Windows: no activado" -ForegroundColor Red }
}
Write-Host "========================================`n" -ForegroundColor Yellow

$reportPath = New-HtmlReport $report $historyPath $ScriptVersion
