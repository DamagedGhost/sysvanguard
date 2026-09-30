# SysVanguard

Herramienta de sondeo diagnóstico para PCs con Windows, pensada para soporte técnico informal. Estrictamente Windows — nada de modding ni desbloqueo de equipos, y sin desarme físico.

## Filosofía del proyecto

SysVanguard está separado en dos fases que **nunca se ejecutan juntas**:

- **Sondeo**: diagnóstico de solo lectura. La única acción automática que ejecuta es el punto de restauración — no limpia, no desinstala, no repara nada por sí solo. Su trabajo es decirte dónde meter mano, no meter mano por ti.
- **Acciones / Tweaks**: limpieza, remoción de bloatware, ajustes de arranque. Se ejecuta aparte, a mano, referenciando lo que el sondeo encontró — nunca a ciegas.

Si el sondeo alguna vez empieza a "arreglar cosas solo", dejó de cumplir su propósito.

## Requisitos

- Windows 10 u 11 (ver sección de compatibilidad).
- Windows PowerShell 5.1 — viene instalada de fábrica, no requiere PowerShell 7.
- Permisos de administrador.

## Cómo correrlo

```powershell
powershell -ExecutionPolicy Bypass -File .\sondeo.ps1
```

1. Elige un preset del menú numerado.
2. Si no existe un punto de restauración creado hoy, te pregunta si quieres uno antes de continuar.
3. Al terminar, se abre solo un reporte HTML en el escritorio (`sondeo-AAAAMMDD-HHMMSS.html`).

## Presets disponibles

| Preset        | Qué corre                                                    | Cuándo usarlo                                  |
|---------------|---------------------------------------------------------------|--------------------------------------------------|
| `Rapido`      | Hardware + Arranque                                           | Chequeo veloz, sin tocar registro extendido      |
| `SoloLectura` | Hardware + Arranque + Antivirus instalado + Estado del sistema | Diagnóstico completo, sin el escaneo lento        |
| `Completo`    | Todo lo anterior + escaneo de Windows Defender                 | Cuando sospechas de malware activo (el más lento)|

## Cómo leer el semáforo del reporte

| Categoría                        | Verde                     | Amarillo                        | Rojo                          |
|-----------------------------------|---------------------------|----------------------------------|--------------------------------|
| Amenazas (Defender)                | 0 detecciones             | —                                | 1+ detecciones                |
| Arranque / persistencia            | 0 ítems sin firma válida  | 1–3 ítems sin firma válida       | 4+ ítems sin firma válida      |
| Discos                             | Todos "Healthy"           | —                                | Cualquier disco no saludable   |
| Batería (si el equipo tiene)       | <20% de desgaste          | 20–39% de desgaste              | ≥40% de desgaste               |
| Errores críticos (agrupados)       | 0 causas distintas        | 1–5 causas distintas            | 6+ causas distintas            |
| Activación de Windows              | Activado                  | Desconocido (ej. KMS sin acceso)| No activado                    |

Los umbrales son un punto de partida definido a criterio propio, no un estándar de la industria. Un evento se cuenta por **causa distinta** (Proveedor+Id agrupado), no por fila cruda: una ráfaga de 100 errores idénticos cuenta como 1, no como 100.

## Seguridad — leer antes de ejecutar

- El script requiere admin y modifica el registro: fuerza `SystemRestorePointCreationFrequency` a 0 para garantizar que siempre pueda crear un punto de restauración, sin esperar el límite de 24h de Windows.
- El escaneo de Defender llama a `MpCmdRun.exe` directo (no `Start-MpScan`) con un timeout duro de 10 minutos — si se cuelga en la fase de reporte a la nube, el propio script lo mata y sigue, en vez de bloquear la sesión completa.
- Por ahora **no** se distribuye como one-liner remoto (`irm ... | iex`) — se corre localmente, archivo por archivo. Eso significa que cualquiera puede y debería leer cada `.psm1` antes de correrlo, en vez de confiar a ciegas.
- El único cambio real al sistema durante el sondeo es el punto de restauración. Todo lo demás (hardware, arranque, antivirus, programas, eventos, estado del sistema) es de solo lectura.

## Compatibilidad

- **Windows 10 / 11**: soportado, sin cambios necesarios.
- **Windows 7**: no soportado — fin de soporte extendido desde 2023, trae PowerShell 2.0 por defecto (sin `[ordered]@{}` ni varios cmdlets usados acá), y le faltan módulos clave como `Storage` (`Get-PhysicalDisk`).

## Historial

Cada corrida queda registrada en `%ProgramData%\SondeoPC\historial.json` — por equipo, no por usuario, para poder comparar en el mismo PC más adelante.

## Estado del proyecto

- Versión actual: `0.5.0`.
- Pendiente: módulo de Acciones/Tweaks con selección curada propia (no aplicación automática del catálogo completo de ningún tercero).

## Referencias

- [Sysinternals Autoruns](https://learn.microsoft.com/sysinternals/downloads/autoruns) — inspiración para la auditoría de persistencia.
- [Microsoft Defender PowerShell module](https://learn.microsoft.com/powershell/module/defender/) — `Get-MpThreatDetection`, `Get-MpThreat`, `Get-MpComputerStatus`.
- [WMI SecurityCenter2 (AntiVirusProduct)](https://learn.microsoft.com/windows/win32/api/) — detección de antivirus instalado.
- [ManagementDateTimeConverter Class](https://learn.microsoft.com/dotnet/api/system.management.managementdatetimeconverter) — conversión de fechas DMTF de WMI.

---

*Nota: parte de la documentación de este README fue redactada con asistencia de IA, usada única y exclusivamente para redacción técnica y comprensión de documentos.*