# SysVanguard

Suite modular de diagnóstico, benchmark y optimización técnica para PCs con Windows, pensada para soporte técnico profesional e independiente. Estrictamente Windows — nada de modding destructivo ni desbloqueo de equipos, y sin desarme físico.

## Filosofía del proyecto

SysVanguard está separado en fases que **nunca se ejecutan a ciegas juntas**:

1. **Sondeo (Auditoría / Diagnóstico)**: diagnóstico de solo lectura. La única acción que ejecuta es el punto de restauración previo. Su trabajo es auditar e indicar el estado real del equipo.
2. **Medición de Rendimiento (Benchmark)**: captura de métricas cuantitativas en reposo (baseline stand-by) y pruebas de estrés térmico para comparar antes y después de cualquier intervención.
3. **Acciones / Tweaks**: optimización y mitigación curada mediante catálogo declarativo (`config/essential.json`), siempre con respaldo y posibilidad de reversión.
4. **Instalador de Software (Próximamente)**: despliegue de herramientas esenciales de mantenimiento y software estándar mediante WinGet.

Si una herramienta de diagnóstico empieza a "arreglar cosas sola" sin consentimiento informado, dejó de cumplir su propósito.

---

## Estructura del Proyecto

```text
sysvanguard/
│
├── config/
│   ├── presets.psd1           # Presets del sondeo (Rapido, SoloLectura, Completo)
│   ├── essential.json         # Catálogo curado de tweaks (Seguros, RiesgoMedio, RiesgoCritico)
│   └── tweaks.json            # Catálogo completo de referencia (WinUtil)
│
├── modules/
│   ├── Audit/                 # Diagnóstico de solo lectura
│   │   ├── Hardware.psm1      # Salud de discos, batería, espacio y temperatura
│   │   ├── Persistence.psm1   # Claves Run, carpeta Inicio y tareas programadas
│   │   ├── SystemState.psm1   # Uptime, activación, eventos críticos e inventario
│   │   └── Defender.psm1      # Detección de AV y escaneo rápido no bloqueante
│   │
│   ├── Actions/               # Intervención y modificación controlada
│   │   ├── RestorePoint.psm1  # Puntos de restauración e idempotencia
│   │   └── Tweaks.psm1        # Motor de aplicación y reversión de optimizaciones
│   │
│   ├── Benchmark/             # Medición de rendimiento
│   │   └── Benchmark.psm1     # Muestreo de reposo y estrés térmico
│   │
│   └── Report/                # Documentación de resultados
│       └── Report.psm1        # Reporte HTML interactivo e historial JSON
│
├── sysvanguard.ps1            # LANZADOR PRINCIPAL (Menú unificado de la suite)
├── sondeo.ps1                 # Punto de entrada directo al sondeo diagnóstico
└── README.md
```

---

## Requisitos

- Windows 10 u 11 (64-bit).
- Windows PowerShell 5.1 (incluida en el sistema, no requiere instalar PowerShell 7).
- Permisos de administrador.

---

## Cómo ejecutarlo

### Lanzador Principal (Menú Completo)
```powershell
powershell -ExecutionPolicy Bypass -File .\sysvanguard.ps1
```

### Acceso Directo al Sondeo
```powershell
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1
```
También admite ejecución desatendida mediante el parámetro `-Preset`:
```powershell
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1 -Preset Rapido
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1 -Preset Completo
```

---

## Presets de Sondeo

| Preset | Qué audita | Cuándo usarlo |
|---|---|---|
| `Rapido` | Hardware + Persistencia de arranque | Chequeo veloz inicial |
| `SoloLectura` | Hardware + Persistencia + Antivirus + Estado del sistema | Diagnóstico completo sin escaneo largo |
| `Completo` | Todo lo anterior + Escaneo de Windows Defender | Auditoría integral profunda |

---

## Catálogo de Tweaks (`config/essential.json`)

Los ajustes de optimización se basan en la herramienta de código abierto **WinUtil** de **Chris Titus Tech** (Licencia MIT) y se encuentran estrictamente categorizados por nivel de impacto:

- **Seguros (12 ajustes)**: Cero impacto funcional negativo. Mejoras ergonómicas (finalizar tarea en barra, mostrar extensiones), privacidad básica y desactivación de descargas promocionales.
- **Riesgo Medio (3 ajustes)**: Telemetría DiagTrack, Widgets de barra de tareas y umbral de memoria SvcHost. Requieren informar al usuario sobre posibles avisos en Configuración o pérdida del panel del clima.
- **Riesgo Crítico (4 ajustes)**: Permisos ACL en tienda, `/ResetBase` en DISM, bloqueo total de apps en segundo plano y remoción de IA/OfficeHub. **Solo para técnicos en escenarios específicos**, ya que pueden afectar notificaciones de WhatsApp o la capacidad de desinstalar actualizaciones.

---

## Historial y Reportes

- **Reportes HTML:** Se generan automáticamente en el Escritorio del usuario (`sondeo-vX.X.X-AAAAMMDD-HHMMSS.html`).
- **Historial del equipo:** Se almacena en `%ProgramData%\SondeoPC\historial.json` para permitir comparaciones longitudinales en el mismo PC a lo largo del tiempo.

---

## Referencias y Agradecimientos

- [Chris Titus Tech (WinUtil)](https://github.com/ChrisTitusTech/winutil) — Catálogo de directivas y ajustes de optimización (MIT License).
- [Sysinternals Autoruns](https://learn.microsoft.com/sysinternals/downloads/autoruns) — Inspiración para la auditoría de persistencia de inicio.
- [Microsoft Defender PowerShell module](https://learn.microsoft.com/powershell/module/defender/) — Monitoreo de seguridad y escaneo.