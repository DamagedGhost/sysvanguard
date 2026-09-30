<#
    Persistence.psm1
    Items de arranque + verificacion de firma digital (Sospechoso = sin firma valida).
#>

function Get-StartupAudit {
    Write-Host "`n=== Auditoria de arranque / persistencia ===" -ForegroundColor Cyan
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

Export-ModuleMember -Function Get-StartupAudit
