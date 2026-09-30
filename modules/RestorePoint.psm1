<#
    RestorePoint.psm1
    Crea el punto de restauracion. La decision de SI preguntar o no vive
    en el orquestador (sondeo.ps1), no aqui: este modulo solo expone la
    accion y el chequeo de idempotencia, sin logica de UI/prompt.
#>

function Test-RestorePointToday {
    $hoy = (Get-Date).Date
    $puntos = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    foreach ($p in $puntos) {
        $fecha = $null
        try { $fecha = [System.Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime) }
        catch {
            try { $fecha = [datetime]$p.CreationTime } catch { continue }
        }
        if ($fecha -and $fecha.Date -eq $hoy) { return $true }
    }
    return $false
}

function Ensure-RestorePoint {
    param(
        [switch]$Forzar
    )

    if (-not $Forzar -and (Test-RestorePointToday)) {
        Write-Host "Ya existe un punto de restauracion de hoy, se omite." -ForegroundColor DarkGray
        return [ordered]@{ Status = "Omitido"; Motivo = "Ya existia uno de hoy" }
    }

    try {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -ErrorAction SilentlyContinue

        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Pre-sondeo $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS

        Write-Host "Punto de restauracion creado OK" -ForegroundColor Green
        return [ordered]@{ Status = "OK"; Timestamp = (Get-Date) }
    }
    catch {
        Write-Host "FALLO crear el punto de restauracion: $_" -ForegroundColor Red
        return [ordered]@{ Status = "FALLO"; Error = $_.Exception.Message }
    }
}

Export-ModuleMember -Function Ensure-RestorePoint, Test-RestorePointToday
