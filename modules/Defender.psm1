<#
    Defender.psm1
    Antivirus instalado (SecurityCenter2) + escaneo rapido con timeout duro
    (Start-MpScan no tiene timeout y se puede colgar en la fase de reporte
    a MAPS/nube, asi que llamamos MpCmdRun.exe directo para poder matarlo).
#>

function Get-InstalledAntivirus {
    Write-Host "`n=== Antivirus instalado ===" -ForegroundColor Cyan
    $avList = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
        Select-Object displayName, @{N = 'ProductStateHex'; E = { '0x{0:X6}' -f $_.productState } }

    if (-not $avList) {
        Write-Host "No se pudo leer root\SecurityCenter2 (normal en Windows Server, o revisa permisos)."
    } else {
        $avList | Format-Table -AutoSize | Out-Host
        Write-Host "ProductStateHex es un bitmask propio de Windows - para leer habilitado/actualizado con precision, cruza el hex con la referencia publica de SecurityCenter2 en vez de asumir el significado."
    }
    return $avList
}

function Invoke-DefenderScan {
    Write-Host "`n=== Escaneo con Windows Defender ===" -ForegroundColor Cyan
    $status = Get-MpComputerStatus
    Write-Host "Firmas actualizadas: $($status.AntivirusSignatureLastUpdated)"

    $mpCmdRun = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path $mpCmdRun)) {
        $mpCmdRun = Get-ChildItem "$env:ProgramData\Microsoft\Windows Defender\Platform" -Filter MpCmdRun.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }

    $timeoutSeconds = 300
    $threats = @()
    $resultado = "No ejecutado"

    if ($mpCmdRun -and (Test-Path $mpCmdRun)) {
        Write-Host "Iniciando quick scan via MpCmdRun.exe (timeout: $($timeoutSeconds/60) min)..."

        # Correr en un Job separado para que un eventual cuelgue de MpCmdRun
        # no congele el hilo principal de PowerShell.
        $scanJob = Start-Job -ScriptBlock {
            param($exe)
            $p = Start-Process -FilePath $exe -ArgumentList "-Scan -ScanType 1" `
                               -PassThru -NoNewWindow -Wait
            return $p.ExitCode
        } -ArgumentList $mpCmdRun

        $terminoATiempo = Wait-Job -Job $scanJob -Timeout $timeoutSeconds

        if ($terminoATiempo) {
            $exitCode = Receive-Job -Job $scanJob
            Remove-Job  -Job $scanJob -Force

            $resultado = "Completado (codigo $exitCode)"

            $detecciones = Get-MpThreatDetection
            $catalogo    = Get-MpThreat -ErrorAction SilentlyContinue

            $threats = foreach ($d in $detecciones) {
                $info = $catalogo | Where-Object { $_.ThreatID -eq $d.ThreatID } | Select-Object -First 1
                [PSCustomObject]@{
                    Proceso   = $d.ProcessName
                    Nombre    = if ($info) { $info.ThreatName } else { "Desconocido (ID $($d.ThreatID))" }
                    Severidad = if ($info) { $info.SeverityID } else { $null }
                    Detectado = $d.InitialDetectionTime
                    Usuario   = $d.DomainUser
                }
            }
        } else {
            Write-Host "El scan no termino en $($timeoutSeconds/60) min, se aborta para no bloquear el sondeo." -ForegroundColor Yellow
            # Matar el proceso MpCmdRun que vive dentro del job antes de eliminar el job
            try {
                $childPid = (Get-Job -Id $scanJob.Id).ChildJobs[0].JobStateInfo
                # Forzar cierre de cualquier MpCmdRun que siga en pie
                Get-Process -Name MpCmdRun -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            } catch {}
            Remove-Job -Job $scanJob -Force
            $resultado = "No completado (timeout $($timeoutSeconds/60) min)"
        }
    } else {
        Write-Host "No se encontro MpCmdRun.exe, se omite el scan activo." -ForegroundColor Yellow
        $resultado = "MpCmdRun.exe no encontrado"
    }

    Write-Host "Resultado del scan: $resultado"
    Write-Host "Amenazas detectadas: $($threats.Count)"
    return [ordered]@{ Status = $status; Threats = $threats; Resultado = $resultado }
}

Export-ModuleMember -Function Get-InstalledAntivirus, Invoke-DefenderScan
