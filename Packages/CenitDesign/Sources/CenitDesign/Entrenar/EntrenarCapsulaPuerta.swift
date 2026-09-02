import SwiftUI

// MARK: - Entrenar · cápsula-puerta del hub v18 (FER-171 · Parte A)
//
// La única pastilla de navegación secundaria del hub (mock `eje-hub-v18.html` `.editar`/`.mapa`:
// «EDITAR ›» sobre Tu semana, «MAPA ›» sobre Tu cuerpo) — mismo fondo/filos/sombra en los dos
// usos, así que es UN componente, no dos pastillas parecidas a mano.

/// Constantes con nombre de la receta (mock v18, clases `.editar`/`.mapa` — idénticas entre sí).
private enum EntrenarCapsulaPuertaMetrics {
    static let paddingH: CGFloat = 11
    static let paddingV: CGFloat = 6
    static let fondoAlfa: Double = 0.72
    /// Highlight superior — aproximación de `inset 0 1px 0 rgba(255,255,255,.9)` como
    /// `strokeBorder` completo (mismo patrón que el resto de la receta de vidrio del hub).
    static let highlightAlfa: Double = 0.90
    static let cantoAlfa: Double = 0.12
    /// Sombra `0 2px 6px rgba(34,29,22,.07)`: radius de SwiftUI = blur CSS ÷ 2 (misma convención
    /// que `LiquidElevation`).
    static let sombraY: CGFloat = 2
    static let sombraRadius: CGFloat = 3
    static let sombraAlfa: Double = 0.07
    /// El glifo de «lleva a otro lado» que hace de esta pastilla una PUERTA — el componente lo
    /// añade él mismo (las dos apariciones del mock lo traen) para que el caller no tenga que
    /// hardcodear un carácter decorativo en una cadena localizada.
    static let chevron = "›"
}

/// La cápsula-puerta: un texto corto en mayúsculas + «›», que navega a otra pantalla/hoja al
/// tocarla.
public struct EntrenarCapsulaPuerta: View {
    private let titulo: String
    private let mostrarFlecha: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - titulo: el texto YA localizado; las mayúsculas las decide el caller (el catálogo debe
    ///     traer la cadena ya en mayúsculas — el componente no aplica `.textCase`).
    ///   - mostrarFlecha: `true` (default) agrega «›» — la puerta EDITAR/MAPA del hub v18. `false`
    ///     (FER-170 · F5, épico FER-165): la cápsula RPE/✎ NOTA del enfoque (mock `hoja-pantallas.html`
    ///     `.capsula`) es la MISMA receta de vidrio, pero sin flecha — no navega a «otra pantalla»,
    ///     abre una hoja encima.
    ///   - action: qué hace al tocarla (navegar a la hoja/pantalla que anuncia).
    public init(_ titulo: String, mostrarFlecha: Bool = true, action: @escaping () -> Void) {
        self.titulo = titulo
        self.mostrarFlecha = mostrarFlecha
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(verbatim: mostrarFlecha ? "\(titulo) \(EntrenarCapsulaPuertaMetrics.chevron)" : titulo)
                .entrenarCapsulaPuertaLabel()
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.horizontal, EntrenarCapsulaPuertaMetrics.paddingH)
                .padding(.vertical, EntrenarCapsulaPuertaMetrics.paddingV)
                .background {
                    Capsule().fill(Color.white.opacity(EntrenarCapsulaPuertaMetrics.fondoAlfa))
                }
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(EntrenarCapsulaPuertaMetrics.highlightAlfa),
                                          lineWidth: 1)
                }
                .overlay {
                    Capsule().stroke(LiquidColor.tinta900.opacity(EntrenarCapsulaPuertaMetrics.cantoAlfa),
                                     lineWidth: 0.5)
                }
                .liquidShadow([.init(color: LiquidColor.tinta900.opacity(EntrenarCapsulaPuertaMetrics.sombraAlfa),
                                     radius: EntrenarCapsulaPuertaMetrics.sombraRadius,
                                     y: EntrenarCapsulaPuertaMetrics.sombraY)])
        }
        .buttonStyle(.liquidPress)
        // El dibujo se queda al tamaño chico del mock; lo que crece hasta 44 es el ÁREA DE
        // TOQUE — mismo criterio que `PaperStepper` (pad invisible, nunca infla la pastilla).
        .frame(minWidth: LiquidControl.hitTarget, minHeight: LiquidControl.hitTarget)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("EntrenarCapsulaPuerta") {
    VStack(alignment: .leading, spacing: 20) {
        EntrenarCapsulaPuerta("EDITAR") {}
        EntrenarCapsulaPuerta("MAPA") {}
    }
    .padding(24)
    .background(LiquidColor.fondoGradient)
}
#endif
