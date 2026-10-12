@{
    Rapido = @{
        Descripcion = 'Chequeo rapido: hardware + arranque (sin AV, sin inventario, sin scan de Defender)'
        Pasos       = @('Hardware', 'Persistence')
    }
    SoloLectura = @{
        Descripcion = 'Diagnostico completo sin escaneo de Defender (mas rapido que Completo)'
        Pasos       = @('Hardware', 'Persistence', 'Antivirus', 'SystemState')
    }
    Completo = @{
        Descripcion = 'Sondeo exhaustivo: hardware, arranque, antivirus, inventario y scan de Defender'
        Pasos       = @('Hardware', 'Persistence', 'Antivirus', 'SystemState', 'Defender')
    }
    ConBenchmark = @{
        Descripcion = 'Sondeo completo + medicion en reposo (baseline de CPU, RAM y procesos activos de fondo)'
        Pasos       = @('Hardware', 'Persistence', 'Antivirus', 'SystemState', 'Benchmark')
    }
    BenchmarkSolo = @{
        Descripcion = 'Solo medicion de rendimiento pasivo en reposo (stand-by de 60 segundos)'
        Pasos       = @('Benchmark')
    }
}
