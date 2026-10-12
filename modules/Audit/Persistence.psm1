<#
    Persistence.psm1
    Items de arranque (Win32_StartupCommand) + tareas programadas de terceros,
    con verificacion de firma digital en ambos casos (Sospechoso = sin firma valida).
#>

function Get-StartupAudit {
    Write-Host "`n=== Auditoria de arranque / persistencia ===" -ForegroundColor Cyan

    # ---------- Run keys / carpeta Startup ----------
    $startupItems = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User

    $startupResults = foreach ($item in $startupItems) {
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
            Origen     = "Startup"
            Name       = $item.Name
            Location   = $item.Location
            Ruta       = $exePath
            Firma      = $sigStatus
            Sospechoso = ($sigStatus -ne 'Valid')
        }
    }

    # ---------- Tareas programadas de terceros ----------
    Write-Host "`n--- Tareas programadas de terceros ---" -ForegroundColor Cyan
    $tareasTerceros = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TaskPath -notlike '\Microsoft\*' -and
            $_.TaskPath -notlike '\MicrosoftEdgeUpdate*' -and
            $_.State -ne 'Disabled'
        }

    $taskResults = foreach ($tarea in $tareasTerceros) {
        $exePath = $null
        $accion = $tarea.Actions | Select-Object -First 1
        if ($accion -and $accion.Execute) {
            $expanded = [Environment]::ExpandEnvironmentVariables($accion.Execute)
            if ($expanded -match '^"?([^"]+\.exe)"?') { $exePath = $matches[1].Trim() }
        }

        $sigStatus = "No resoluble"
        if ($exePath -and (Test-Path -LiteralPath $exePath -ErrorAction SilentlyContinue)) {
            try { $sigStatus = (Get-AuthenticodeSignature -FilePath $exePath).Status }
            catch { $sigStatus = "Error" }
        }

        [PSCustomObject]@{
            Origen     = "ScheduledTask"
            Name       = $tarea.TaskName
            Location   = $tarea.TaskPath
            Ruta       = $exePath
            Firma      = $sigStatus
            Sospechoso = ($sigStatus -ne 'Valid')
        }
    }

    $results = @($startupResults) + @($taskResults)

    $results | Format-Table -AutoSize | Out-Host

    $sospechosos = @($results | Where-Object Sospechoso)
    $color = if ($sospechosos.Count -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host "Items sin firma valida: $($sospechosos.Count) de $($results.Count) (startup: $($startupResults.Count), tareas: $($taskResults.Count))" -ForegroundColor $color

    return $results
}

Export-ModuleMember -Function Get-StartupAudit
