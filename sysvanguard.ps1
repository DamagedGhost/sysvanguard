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
        Write-Host "  1) Sondeo Diagnostico (Hardware, Persistencia, Seguridad, Rendimiento)" -ForegroundColor White
        Write-Host "  2) Medicion de Rendimiento Pasivo (Benchmark Stand-by / Reposo)" -ForegroundColor White
        Write-Host "  3) [BLOQUEADO] Optimizaciones y Tweaks (Deshabilitado preventivamente)" -ForegroundColor DarkGray
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
                Write-Host "`n=== Medicion de Rendimiento Pasivo (Stand-by) ===" -ForegroundColor Cyan
                Write-Host "Mide el uso de CPU, consumo de RAM, temperatura y procesos de fondo sin estres destructivo." -ForegroundColor DarkGray
                Write-Host "Elige duracion del muestreo:"
                Write-Host "  1) 60 segundos (Rapido)"
                Write-Host "  2) 120 segundos (Estandar)"
                Write-Host "  3) 180 segundos (Exhaustivo)"
                $selDur = Read-Host "Opcion (1-3, por defecto 1)"
                $segundos = 60
                if ($selDur -eq '2') { $segundos = 120 }
                elseif ($selDur -eq '3') { $segundos = 180 }

                Measure-SystemBaseline -DurationSeconds $segundos -IntervalSeconds 3
                Write-Host "`nPresione Enter para regresar al menu principal..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            "3" {
                Clear-Host
                Write-Host "=================================================================" -ForegroundColor Red
                Write-Host "       AVISO DE SEGURIDAD: MOTOR DE TWEAKS DESHABILITADO         " -ForegroundColor Yellow
                Write-Host "=================================================================" -ForegroundColor Red
                Write-Host "`nPor que esta deshabilitado:" -ForegroundColor Cyan
                Write-Host "  Para proteger los equipos de clientes y usuarios finales, NINGUNA modificacion"
                Write-Host "  al registro ni a los servicios de Windows se ejecutara hasta completar la fase"
                Write-Host "  de pruebas de compatibilidad y verificacion de reversibilidad (Undo)."
                Write-Host "`nEstado actual del catalogo:" -ForegroundColor Cyan
                Write-Host "  - Archivo de configuracion: 'config/essential.json'"
                Write-Host "  - Categorias definidas: Seguros (12), Riesgo Medio (3), Riesgo Critico (4)"
                Write-Host "  - Estado de ejecucion: 100% BLOQUEADO. Cero modificaciones al sistema."
                
                Write-Host ""
                $verCat = Read-Host "Desea consultar el catalogo en modo SOLO LECTURA? (s/n)"
                if ($verCat -eq 's') {
                    $cat = Get-TweakCatalog
                    if ($cat) {
                        Write-Host "`n--- SEGUROS (Riesgo Bajo / Cero impacto funcional negativo) ---" -ForegroundColor Green
                        $cat.Seguros.psobject.properties | ForEach-Object {
                            Write-Host "  - $($_.Value.nombre)" -ForegroundColor Green
                            Write-Host "    $($_.Value.descripcion)" -ForegroundColor DarkGray
                        }
                        Write-Host "`n--- RIESGO MEDIO (Efectos secundarios moderados) ---" -ForegroundColor Yellow
                        $cat.RiesgoMedio.psobject.properties | ForEach-Object {
                            Write-Host "  - $($_.Value.nombre)" -ForegroundColor Yellow
                            Write-Host "    $($_.Value.descripcion)" -ForegroundColor DarkGray
                        }
                        Write-Host "`n--- RIESGO CRITICO (Puede romper funciones en usuarios comunes) ---" -ForegroundColor Red
                        $cat.RiesgoCritico.psobject.properties | ForEach-Object {
                            Write-Host "  - $($_.Value.nombre)" -ForegroundColor Red
                            Write-Host "    PELIGRO: $($_.Value.advertencia_riesgo)" -ForegroundColor DarkRed
                        }
                    }
                }
                Write-Host "`nPresione Enter para regresar al menu principal..." -ForegroundColor DarkGray
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
