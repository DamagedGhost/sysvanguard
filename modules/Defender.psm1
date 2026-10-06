<#
    Defender.psm1
    Antivirus instalado (SecurityCenter2) + escaneo rapido con timeout duro.
    Se utiliza MpCmdRun.exe en proceso independiente con monitoreo via Stopwatch
    y verificacion de .HasExited sin bloquear el hilo de PowerShell, evitando
    cuelgues por WinRM o pipes heredados.
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
    $status = Get-MpComputerStatus -ErrorAction SilentlyContinue

    if (-not $status) {
        Write-Host "No se pudo consultar el estado de Windows Defender." -ForegroundColor Yellow
        return [ordered]@{ Status = $null; Threats = @(); Resultado = "Estado de Defender no disponible" }
    }

    Write-Host "Firmas actualizadas: $($status.AntivirusSignatureLastUpdated)"

    # Si Defender esta apagado o en modo pasivo (p. ej. por AV de terceros), no ejecutar scan
    if ($status.AntivirusEnabled -eq $false -or $status.AMServiceEnabled -eq $false) {
        Write-Host "Windows Defender esta desactivado o en modo pasivo (antivirus de terceros o servicio inactivo)." -ForegroundColor Yellow
        return [ordered]@{ Status = $status; Threats = @(); Resultado = "Defender desactivado o en modo pasivo" }
    }

    $mpCmdRun = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path $mpCmdRun)) {
        $mpCmdRun = Get-ChildItem "$env:ProgramData\Microsoft\Windows Defender\Platform" -Filter MpCmdRun.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }

    $timeoutSeconds = 300
    $threats = @()
    $resultado = "No ejecutado"

    if ($mpCmdRun -and (Test-Path $mpCmdRun)) {
        Write-Host "Iniciando quick scan via MpCmdRun.exe (timeout: $($timeoutSeconds/60) min)..." -NoNewline

        # Proceso desacoplado sin Start-Job (evita fallos de WinRM / PSSessionStateBroken)
        # y sin WaitForExit bloqueante (evita deadlock de descriptores en .NET)
        $proc = Start-Process -FilePath $mpCmdRun -ArgumentList "-Scan -ScanType 1" -PassThru -WindowStyle Hidden

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited -and $sw.Elapsed.TotalSeconds -lt $timeoutSeconds) {
            Start-Sleep -Seconds 2
            Write-Host "." -NoNewline
        }
        Write-Host ""

        if ($proc.HasExited) {
            $resultado = "Completado (codigo $($proc.ExitCode))"

            $detecciones = Get-MpThreatDetection -ErrorAction SilentlyContinue
            $catalogo    = Get-MpThreat -ErrorAction SilentlyContinue

            if ($detecciones) {
                $threats = foreach ($d in $detecciones) {
                    $info = if ($catalogo) { $catalogo | Where-Object { $_.ThreatID -eq $d.ThreatID } | Select-Object -First 1 } else { $null }
                    [PSCustomObject]@{
                        Proceso   = $d.ProcessName
                        Nombre    = if ($info) { $info.ThreatName } else { "Desconocido (ID $($d.ThreatID))" }
                        Severidad = if ($info) { $info.SeverityID } else { $null }
                        Detectado = $d.InitialDetectionTime
                        Usuario   = $d.DomainUser
                    }
                }
            }
        } else {
            Write-Host "El scan no termino en $($timeoutSeconds/60) min, se aborta para no bloquear el sondeo." -ForegroundColor Yellow
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            try { Get-Process -Name MpCmdRun -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
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
