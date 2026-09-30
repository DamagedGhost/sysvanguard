#Requires -RunAsAdministrator
<#
    sondeo.ps1 - Orquestador de SysVanguard
    Menu interactivo de presets (config/presets.psd1) + punto de
    restauracion como decision de sesion (no de preset, no de tweaks).
    Compatible con Windows PowerShell 5.1.
#>

$ScriptVersion = "0.5.0"
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Get-ChildItem "$root\modules\*.psm1" | ForEach-Object { Import-Module $_.FullName -Force }
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

$preset = Show-Menu
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
foreach ($pasoNombre in $preset.Pasos) {
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
New-HtmlReport $report $historyPath $ScriptVersion
