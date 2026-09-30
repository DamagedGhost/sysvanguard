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
        Descripcion = 'Sondeo completo: todo lo disponible, incluye scan de Defender (el mas lento)'
        Pasos       = @('Hardware', 'Persistence', 'Antivirus', 'SystemState', 'Defender')
    }
}
