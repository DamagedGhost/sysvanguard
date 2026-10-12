<#
    Tweaks.psm1
    Placeholder. Esto es para la fase de ACCIONES (limpieza/bloatware/
    deshabilitar startup sospechoso), que es una invocacion SEPARADA del
    sondeo, no algo que sondeo.ps1 llame en la misma corrida.

    Cuando se implemente, cada accion deberia:
      - Referenciar el hallazgo del sondeo que la origina (no re-escanear a ciegas).
      - Pedir su propio punto de restauracion via RestorePoint.psm1
        (Ensure-RestorePoint -Forzar), sin depender del que se haya
        creado (o no) durante el sondeo.
      - Ser reversible cuando sea posible: deshabilitar en vez de borrar.

    TODO: Limpieza-Nivel1 (temporales, DISM component cleanup)
    TODO: Bloatware-Nivel2 (AppX config-driven)
    TODO: Persistencia-Nivel3 (deshabilitar items marcados Sospechoso=True)
#>

Export-ModuleMember -Function *
