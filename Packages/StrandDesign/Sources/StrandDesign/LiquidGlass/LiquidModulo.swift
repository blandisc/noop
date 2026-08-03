import SwiftUI

// MARK: - Liquid Glass · Módulo de «El Tablero» (FER-28)
//
// El contenedor de vidrio de un módulo de Hoy. Sobre el suelo casi blanco, un vidrio liso se
// «lava»; lo que lo devuelve a lo caro es el conjunto exacto de esta receta:
//   · relleno blanco con densidad PROGRESIVA hacia abajo (.42 → .54 por índice),
//   · borde blanco .72 + un CANTO exterior hairline de tinta al 6 % (lo que separa «caro» de
//     «lavado» — un filo de tinta bajo el borde blanco),
//   · sombra de dos capas (contacto corto + ambiente que se alarga al bajar en la pila),
//   · «refracción honesta»: el fondo se ve 1.28× más vivo a través del vidrio que fuera,
//   · y la aurora fina en el filo (los tonos de SUS datos girando + especular fijo arriba).
//
// Radio 20. En iOS 26 el vidrio NATIVO aporta refracción/lensing reales; en el fallback se
// aproxima con material + saturación del backdrop. Un componente, no un `.liquidGlass` suelto:
// la pantalla nunca compone este material a mano.

public struct LiquidModulo<Content: View>: View {
    private let index: Int
    private let auroraTones: [Color]
    private let auroraPeriod: Double
    private let auroraReverse: Bool
    private let content: Content

    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// - Parameters:
    ///   - index: profundidad en la pila (0…3) → densidad del relleno y largo de la sombra.
    ///   - auroraTones: los tonos 1:1 de los datos del módulo (el filo ES sus datos).
    ///   - auroraPeriod: segundos por vuelta de la aurora (44 / 52 / 38 / 58 en Hoy).
    ///   - auroraReverse: gira invertido (los módulos pares).
    public init(index: Int, auroraTones: [Color], auroraPeriod: Double,
                auroraReverse: Bool = false, @ViewBuilder content: () -> Content) {
        self.index = index
        self.auroraTones = auroraTones
        self.auroraPeriod = auroraPeriod
        self.auroraReverse = auroraReverse
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidRadius.modulo, style: .continuous)
    }

    public var body: some View {
        content
            .padding(.vertical, LiquidSpace.s200)
            .padding(.horizontal, LiquidSpace.s400)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { glass }
            // Borde blanco interior + canto exterior de tinta (dos hairlines concéntricos).
            .overlay { shape.strokeBorder(LiquidColor.vidrioBordeSuperficie, lineWidth: 1) }
            .overlay { shape.stroke(LiquidColor.vidrioCanto, lineWidth: 0.5) }
            // La aurora fina vive en el filo, encima del borde.
            .overlay {
                LiquidAuroraEdge(tones: auroraTones, period: auroraPeriod,
                                 reverse: auroraReverse, radius: LiquidRadius.modulo)
            }
            .liquidShadow(LiquidElevation.modulo(index: index), silhouette: shape)
    }

    /// El material del módulo: en iOS 26 vidrio nativo (refracción real); antes, material del
    /// sistema con el backdrop saturado (`vidrioRefraccion`) + relleno de densidad por índice.
    @ViewBuilder
    private var glass: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
            Color.clear
                .background { shape.fill(LiquidColor.vidrioSuperficieDensidad(index)) }
                .glassEffect(.regular, in: shape)
        } else {
            ZStack {
                // La «refracción honesta»: el material muestrea el fondo y lo saturamos 1.28×,
                // así la plasta se ve más viva a través del vidrio que fuera.
                shape.fill(.ultraThinMaterial)
                    .saturation(LiquidColor.vidrioRefraccion)
                shape.fill(LiquidColor.vidrioSuperficieDensidad(index))
            }
        }
    }
}

#if DEBUG
#Preview("Liquid · Módulo") {
    ZStack {
        LiquidPlasta(ambiente: .bien)
        VStack(spacing: LiquidSpace.s250) {
            ForEach(Array([
                ("LO QUE INFORMA TU VEREDICTO",
                 [LiquidColor.indigo, LiquidColor.rosa, LiquidColor.verdePrimario], 44.0, false),
                ("EL DÍA",
                 [LiquidColor.ambar, LiquidColor.teal, LiquidColor.verdePrimario], 38.0, false),
            ].enumerated()), id: \.offset) { i, cfg in
                LiquidModulo(index: i, auroraTones: cfg.1, auroraPeriod: cfg.2,
                             auroraReverse: cfg.3) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cfg.0).liquidRegla().foregroundStyle(LiquidColor.tinta500)
                        HStack(alignment: .top, spacing: 0) {
                            LiquidColumna(label: "SUEÑO", value: "7:20", unit: "h",
                                          detail: "20:00 → 4:00", tone: LiquidColor.indigo) {}
                            LiquidCapilar()
                            LiquidColumna(label: "FC REPOSO", value: "52", unit: "lpm",
                                          detail: "en tu rango", tone: LiquidColor.rosa,
                                          alignment: .trailing) {}
                        }
                    }
                }
            }
        }
        .padding(LiquidSpace.s600)
    }
}
#endif
