#Requires -RunAsAdministrator
<#
    sysvanguard.ps1 - Orquestador Principal de SysVanguard
    Suite modular de diagnostico, benchmark y optimizacion tecnica para Windows.
    Compatible con Windows PowerShell 5.1 y superior.
#>

$ScriptVersion = "0.7.0"
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Carga de todos los modulos recursivamente desde modules/
Get-ChildItem "$root\modules\*.psm1" -Recurse | ForEach-Object { 
    Import-Module $_.FullName -Force -WarningAction SilentlyContinue 
}

function Show-SysVanguardBanner {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "    SYSVANGUARD - Suite de Diagnostico y Mantenimiento v$ScriptVersion" -ForegroundColor Yellow
    Write-Host "    Equipo: $env:COMPUTERNAME | Usuario: $env:USERNAME" -ForegroundColor DarkGray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-MainMenu {
    do {
        Show-SysVanguardBanner
        Write-Host "  1) Sondeo Diagnostico (Auditoria Hardware, Persistencia, Seguridad)" -ForegroundColor White
        Write-Host "  2) Medicion de Rendimiento (Benchmark en Reposo / Estres Termico)" -ForegroundColor DarkGray
        Write-Host "  3) Optimizaciones y Tweaks (Catalogo Curado con Respaldo)" -ForegroundColor DarkGray
        Write-Host "  4) Salir" -ForegroundColor Red
        Write-Host ""

        $opcion = Read-Host "Selecciona una opcion (1-4)"

        switch ($opcion) {
            "1" {
                Write-Host "`nIniciando modulo de sondeo..." -ForegroundColor Cyan
                & "$root\sondeo.ps1"
                Write-Host "`nPresione Enter para regresar al menu principal..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            "2" {
                Write-Host "`n[En desarrollo] El modulo de Benchmark permitira medir baseline en reposo (5 min) y prueba de estres termico." -ForegroundColor Yellow
                Write-Host "Presione Enter para continuar..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            "3" {
                Write-Host "`n[En desarrollo] El motor de Tweaks aplicara ajustes desde 'config/essential.json' con punto de restauracion previo." -ForegroundColor Yellow
                Write-Host "Presione Enter para continuar..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            "4" {
                Write-Host "`nSaliendo de SysVanguard. Que tenga un buen dia." -ForegroundColor Green
                break
            }
            default {
                Write-Host "`nOpcion invalida. Intente de nuevo." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($opcion -ne "4")
}

Show-MainMenu
