import SwiftUI

// MARK: - Hoja · cápsula de acción compacta (FER-280 · 1c, clase 5)
//
// La receta de «＋ SET» de la Hoja viva (`HojaTarjetaEjercicio.swift:194-208`, constantes
// duplicadas en `HojaLiveMetrics`): mayúsculas grotesk + cápsula fondo/borde/canto sobre vidrio.
// `EntrenarCapsulaPuerta` cubre la misma familia visual pero SIEMPRE añade «›» (es una puerta a
// otra pantalla); esta pieza es para acciones DENTRO de la hoja (agregar serie, deshacer) que no
// navegan a ningún lado, así que la flecha es opcional y apagada por default.
//
// **Cuándo sí:** una acción compacta sobre vidrio dentro de una hoja de Entrenar (agregar serie,
// acción secundaria) que no debe prometer navegación. **Cuándo no:** una puerta a otra
// pantalla/hoja (usa `EntrenarCapsulaPuerta`, que sí trae «›»); un CTA de pantalla completa (usa
// `LiquidGlassButton`/`StrandCTAButton`).

/// Constantes con nombre de la receta — MISMOS alfas que `EntrenarCapsulaPuerta`
/// (fondo/highlight/canto son la misma familia visual, solo cambian tipografía/padding/hit-target).
private enum HojaCapsulaAccionMetrics {
    static let fondoAlfa: Double = 0.72
    static let bordeAlfa: Double = 0.90
    static let cantoAlfa: Double = 0.12
    static let chevron = "›"
}

/// La cápsula de acción de una hoja: texto corto en mayúsculas, con flecha opcional.
struct HojaCapsulaAccion: View {
    private let titulo: String
    private let mostrarFlecha: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - titulo: el texto YA localizado y en mayúsculas — el componente no aplica `.textCase`.
    ///   - mostrarFlecha: `false` (default) — la acción se queda en la misma hoja («＋ SET»,
    ///     ninguna navegación que anunciar). `true` agrega «›» para el caso raro en que la
    ///     cápsula SÍ empuje a otra hoja/pantalla desde dentro de una hoja.
    ///   - action: qué hace al tocarla.
    init(_ titulo: String, mostrarFlecha: Bool = false, action: @escaping () -> Void) {
        self.titulo = titulo
        self.mostrarFlecha = mostrarFlecha
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: mostrarFlecha ? "\(titulo) \(HojaCapsulaAccionMetrics.chevron)" : titulo)
                .font(InstrumentoType.grotesk(9.5, weight: .bold, relativeTo: .caption2))
                .tracking(1)
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.horizontal, CenitMetrics.gap)
                .padding(.vertical, LiquidSpace.s150)
                .frame(minHeight: HojaMetrics.hitMin)
                .background {
                    Capsule().fill(Color.white.opacity(HojaCapsulaAccionMetrics.fondoAlfa))
                }
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(HojaCapsulaAccionMetrics.bordeAlfa),
                                          lineWidth: 1)
                }
                .overlay {
                    Capsule().stroke(LiquidColor.tinta900.opacity(HojaCapsulaAccionMetrics.cantoAlfa),
                                     lineWidth: 0.5)
                }
        }
        .buttonStyle(.liquidPress)
    }
}

#if DEBUG
#Preview("HojaCapsulaAccion") {
    VStack(alignment: .leading, spacing: 20) {
        HojaCapsulaAccion(String(localized: "＋ SET")) {}
        HojaCapsulaAccion("VER DETALLE", mostrarFlecha: true) {}
    }
    .padding(24)
    .background(LiquidColor.fondoGradient)
}
#endif
