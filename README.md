# SysVanguard (v0.7.0)

Suite modular de diagnóstico, medición de rendimiento pasivo y optimización técnica para PCs con Windows, diseñada para soporte técnico profesional e independiente. Estrictamente Windows — nada de modding destructivo ni desbloqueo de equipos, y sin desarme físico.

---

## Filosofía del proyecto: Seguridad Primero (Security First)

SysVanguard opera bajo un principio inquebrantable de separación de fases:

1. **Sondeo (Auditoría / Diagnóstico)**: Diagnóstico de solo lectura. La única acción que ejecuta es el punto de restauración previo. Su trabajo es auditar e indicar el estado real del equipo sin alterar configuraciones.
2. **Medición de Rendimiento Pasivo (Benchmark Stand-by)**: Muestreo estadístico en reposo (CPU, RAM, temperatura y procesos de fondo) sin aplicar estrés térmico destructivo, protegiendo hardware con refrigeración comprometida.
3. **Acciones / Tweaks (BLOQUEADOS PREVENTIVAMENTE)**: Catálogo curado de 19 directivas basadas en WinUtil clasificado por nivel de riesgo. **Permanece deshabilitado por política de seguridad en el código** hasta completar validaciones de reversibilidad en laboratorio.
4. **Instalador de Software (A futuro)**: Despliegue de herramientas esenciales de mantenimiento y software estándar mediante WinGet.

> [!IMPORTANT]
> **Regla de oro de SysVanguard:** Una herramienta técnica jamás debe "arreglar cosas sola" sin consentimiento informado ni aplicar ajustes que puedan comprometer la estabilidad del sistema del cliente.

---

## Estructura Modular del Proyecto

```text
sysvanguard/
│
├── config/                               # Catálogos y configuración declarativa
│   ├── presets.psd1                      # Presets del sondeo (Rapido, SoloLectura, Completo, ConBenchmark, BenchmarkSolo)
│   ├── essential.json                    # Catálogo curado de 19 tweaks (Seguros, RiesgoMedio, RiesgoCritico)
│   └── tweaks.json                       # Catálogo original de referencia (WinUtil)
│
├── modules/                              # Módulos organizados por dominio
│   ├── Audit/                            # Diagnóstico de solo lectura
│   │   ├── Hardware.psm1                 # Salud de discos, batería, espacio y temperatura WMI
│   │   ├── Persistence.psm1              # Claves Run, carpeta Inicio y tareas programadas
│   │   ├── SystemState.psm1              # Uptime, activación, eventos críticos e inventario
│   │   └── Defender.psm1                 # Detección de AV y escaneo rápido no bloqueante
│   │
│   ├── Actions/                          # Modificación controlada del sistema
│   │   ├── RestorePoint.psm1             # Puntos de restauración e idempotencia
│   │   └── Tweaks.psm1                   # Motor de optimizaciones (BLOQUEADO PREVENTIVAMENTE)
│   │
│   ├── Benchmark/                        # Medición de rendimiento cuantitativo
│   │   └── Benchmark.psm1                # Muestreo pasivo de reposo (Stand-by Baseline)
│   │
│   └── Report/                           # Documentación y seguimiento
│       └── Report.psm1                   # Reporte HTML interactivo e historial JSON
│
├── sysvanguard.ps1                       # LANZADOR PRINCIPAL (Menú unificado de la suite)
├── sondeo.ps1                            # Atajo directo al sondeo diagnóstico (compatible CLI y presets)
└── README.md
```

---

## Requisitos

- Windows 10 u 11 (64-bit).
- Windows PowerShell 5.1 (nativa del sistema, no requiere PowerShell 7).
- Permisos de Administrador.

---

## Cómo ejecutarlo

### 1. Menú Principal Unificado
```powershell
powershell -ExecutionPolicy Bypass -File .\sysvanguard.ps1
```
Presenta las opciones de la suite:
* `1) Sondeo Diagnóstico` (invoca el auditor con selector de presets).
* `2) Medición de Rendimiento Pasivo` (permite elegir duración: 60s, 120s o 180s en reposo).
* `3) [BLOQUEADO] Optimizaciones y Tweaks` (aviso de seguridad y visor de catálogo en solo lectura).
* `4) Salir`.

### 2. Acceso Directo al Sondeo
```powershell
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1
```
También admite ejecución desatendida mediante el parámetro `-Preset`:
```powershell
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1 -Preset ConBenchmark
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1 -Preset BenchmarkSolo
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1 -Preset Rapido
```

---

## Presets de Sondeo Disponibles

| Preset | Qué audita | Cuándo usarlo |
|---|---|---|
| `Rapido` | Hardware + Persistencia de arranque | Chequeo veloz inicial |
| `SoloLectura` | Hardware + Persistencia + Antivirus + Estado general | Diagnóstico completo sin escaneo largo |
| `Completo` | Todo lo anterior + Escaneo rápido de Windows Defender | Auditoría integral profunda con AV |
| `ConBenchmark` | Sondeo completo + Medición pasiva de reposo (60s) | Diagnóstico completo con métricas de CPU/RAM y procesos de fondo |
| `BenchmarkSolo` | Únicamente la medición en reposo (Stand-by) | Para medir rendimiento antes y después sin repetir el diagnóstico completo |

---

## Medición de Rendimiento Pasivo (Stand-by Baseline)

El módulo [Benchmark.psm1](file:///c:/Users/felip/Proyectos/00_PROYECTOS_CORE/sysvanguard/modules/Benchmark/Benchmark.psm1) realiza un muestreo de intervalo silencioso mientras el equipo reposa en vacío:

* **Métricas evaluadas:**
  * `% Uso de CPU` promedio y pico máximo.
  * `Memoria RAM` ocupada (GB y %) vs memoria disponible.
  * `Temperatura de CPU` (si es expuesta por el driver WMI del fabricante).
  * `Recuento de procesos y subprocesos activos`.
* **Identificación de Procesos en Segundo Plano (Delta de CPU):**  
  Calcula la diferencia exacta de tiempo de procesador entre el inicio y el fin del muestreo, identificando los **Top 5 procesos que más despiertan al equipo en segundo plano** (ej. navegadores, Discord, aplicaciones de bandeja o servicios residentes).
* **Seguridad de Hardware:** Se omitieron intencionalmente pruebas de estrés sintético para evitar provocar sobrecalentamiento, estrangulamiento térmico (*throttling*) o apagones en equipos de clientes con ventilación sucia o pastas térmicas degradadas.

---

## Catálogo de Tweaks y Bloqueo de Seguridad (`config/essential.json`)

El catálogo de optimizaciones toma como base las directivas de código abierto de **WinUtil** por **Chris Titus Tech** (Licencia MIT). Para evitar roturas en clientes comunes, los 19 ajustes están estrictamente categorizados:

- **Seguros (12 ajustes)**: Cero impacto funcional negativo. Finalizar tarea con clic derecho, mostrar extensiones de archivo, desactivar descargas promocionales de la tienda, habilitar rutas largas (>260 caracteres), desactivar Bing en el menú Inicio, pantalla azul detallada, limpieza de temporales, optimización de Edge y Brave.
- **Riesgo Medio (3 ajustes)**: Telemetría DiagTrack, remover panel de Widgets y optimización de memoria SvcHost. Requieren avisar al usuario de posibles carteles en Configuración o pérdida del panel del clima.
- **Riesgo Crítico (4 ajustes)**: Denegación ACL en base de datos de la tienda, `/ResetBase` en DISM (elimina la opción de desinstalar actualizaciones de Windows), bloqueo total de apps en segundo plano (rompe notificaciones de WhatsApp Desktop y alarmas) y remoción de IA/OfficeHub.

> [!CAUTION]
> **Estado de Ejecución:** El motor en [Tweaks.psm1](file:///c:/Users/felip/Proyectos/00_PROYECTOS_CORE/sysvanguard/modules/Actions/Tweaks.psm1) tiene la directiva `$global:SysVanguardTweaksLocked = $true`. Cualquier llamada a `Invoke-Tweak` o `Undo-Tweak` está **bloqueada en el código**. La opción del menú principal permite únicamente **inspección técnica en modo de solo lectura**.

---

## Reportes e Historial

- **Reporte HTML:** Se genera con semáforos ejecutivos y tablas detalladas directamente en el Escritorio del usuario (`sondeo-vX.X.X-AAAAMMDD-HHMMSS.html`).
- **Historial del equipo:** Se guarda automáticamente en `%ProgramData%\SondeoPC\historial.json` para permitir seguimiento comparativo a lo largo del tiempo.

---

## Referencias y Agradecimientos

- [Chris Titus Tech (WinUtil)](https://github.com/ChrisTitusTech/winutil) — Catálogo de directivas y ajustes de optimización para Windows (MIT License).
- [Sysinternals Autoruns](https://learn.microsoft.com/sysinternals/downloads/autoruns) — Inspiración para la auditoría de persistencia y arranque.
- [Microsoft Defender PowerShell module](https://learn.microsoft.com/powershell/module/defender/) — Consulta de estado y escaneo controlado.