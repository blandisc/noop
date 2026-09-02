import CenitDesign

// MARK: - Los rótulos del dock, traducidos (FER-112)
//
// `CenitDesign` no tiene catálogo de cadenas, así que los títulos del dock vivían hardcodeados
// en español dentro del paquete: la barra que acompaña TODAS las pantallas se veía en español
// aunque el teléfono estuviera en inglés. Aquí es donde sí hay catálogo, y de aquí salen.
//
// Las cuatro claves ya existían y ya estaban traducidas — solo que nadie se las estaba pidiendo.
extension LiquidTabRotulos {
    static var cenit: LiquidTabRotulos {
        .init(hoy: String(localized: "Today"),
              tendencias: String(localized: "Trends"),
              entrenar: String(localized: "Train"),
              // Ronda 2 #24: clave «Settings» (inglés), no el texto español «Ajustes» — esa era
              // una isla marcada `stale` en el catálogo, en riesgo de que un prune del catálogo se
              // la llevara y dejara el dock en español bajo UI inglesa. El encabezado de la propia
              // pantalla (`AjustesView.header`) usa la MISMA clave, así que dock y pantalla siguen
              // diciendo lo mismo («Ajustes» en es-MX) sin depender de un literal español.
              ajustes: String(localized: "Settings"))
    }
}
