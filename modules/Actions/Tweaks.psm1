<#
    Tweaks.psm1
    Modulo de optimizaciones y ajustes tecnicos para Windows.
    
    [ESTADO: DESHABILITADO PREVENTIVAMENTE POR SEGURIDAD]
    Ningun ajuste o modificacion al registro/servicios se ejecutara en el sistema
    hasta que se completen las pruebas exhaustivas de laboratorio y reversibilidad.
#>

$global:SysVanguardTweaksLocked = $true

function Get-TweakCatalog {
    param(
        [string]$Path = ""
    )
    <#
        Permite inspeccionar de SOLO LECTURA el catalogo clasificado sin modificar el sistema.
    #>
    if ($Path -and (Test-Path $Path)) {
        return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }

    $candidatos = @(
        (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "config\essential.json"),
        (Join-Path (Get-Location) "config\essential.json"),
        (Join-Path $PSScriptRoot "..\..\config\essential.json")
    )

    foreach ($cand in $candidatos) {
        if ($cand -and (Test-Path $cand)) {
            return (Get-Content $cand -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
    }

    Write-Host "No se encontro el archivo de catalogo config\essential.json" -ForegroundColor Yellow
    return $null
}

function Invoke-Tweak {
    param([string]$TweakId)
    Write-Host "`n[SEGURIDAD SYSVANGUARD] ACCESO BLOQUEADO." -ForegroundColor Red
    Write-Host "El motor de ejecucion de tweaks esta deshabilitado preventivamente para proteger la integridad del sistema." -ForegroundColor Yellow
    Write-Host "Consulte 'config/essential.json' para revision tecnica previa." -ForegroundColor DarkGray
    return [ordered]@{ Status = "Bloqueado"; Motivo = "Motor de tweaks deshabilitado preventivamente" }
}

function Undo-Tweak {
    param([string]$TweakId)
    Write-Host "`n[SEGURIDAD SYSVANGUARD] ACCESO BLOQUEADO." -ForegroundColor Red
    Write-Host "El motor de ejecucion de tweaks esta deshabilitado preventivamente." -ForegroundColor Yellow
    return [ordered]@{ Status = "Bloqueado"; Motivo = "Motor de tweaks deshabilitado preventivamente" }
}

Export-ModuleMember -Function Get-TweakCatalog, Invoke-Tweak, Undo-Tweak
