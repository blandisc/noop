import StrandDesign

// MARK: - Los rótulos del dock, traducidos (FER-112)
//
// `StrandDesign` no tiene catálogo de cadenas, así que los títulos del dock vivían hardcodeados
// en español dentro del paquete: la barra que acompaña TODAS las pantallas se veía en español
// aunque el teléfono estuviera en inglés. Aquí es donde sí hay catálogo, y de aquí salen.
//
// Las cuatro claves ya existían y ya estaban traducidas — solo que nadie se las estaba pidiendo.
extension LiquidTabRotulos {
    static var cenit: LiquidTabRotulos {
        .init(hoy: String(localized: "Today"),
              tendencias: String(localized: "Trends"),
              entrenar: String(localized: "Train"),
              // Clave «Ajustes», no «Settings»: las dos dan "Settings" en inglés, pero en
              // español la primera dice «Ajustes» —lo que ya dice el encabezado de esa misma
              // pantalla— y la segunda diría «Configuración». El dock y su pantalla tienen que
              // llamarse igual.
              ajustes: String(localized: "Ajustes"))
    }
}
