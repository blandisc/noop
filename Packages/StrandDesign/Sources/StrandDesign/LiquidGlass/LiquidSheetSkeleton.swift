import SwiftUI

// MARK: - Liquid Glass · Skeleton de hoja (épico hoja Liquid, F5)
//
// El placeholder de la hoja de sueño mientras `buildDetached` entrega el modelo async —
// comportamiento NUEVO (§1.3 del contrato: hoy la hoja cae al layout clásico, sin
// skeleton). Cuatro bloques redacted en vidrio (`.superficie`) con las alturas
// aproximadas del contenido rico: doble dato, línea de lectura, barra de etapas y
// gráfica de niveles (144, el alto del explorador — contrato §5).
//
// Shimmer sobrio SOLO en movimiento permitido: un streak que viaja por los bloques con
// la cadencia `flow` del sistema (la gramática de «pulsos que viajan», `LiquidMotion`).
// Con Reduce Motion o `\.liquidMotionDisabled` activos, los bloques quedan ESTÁTICOS —
// el vidrio en reposo ya lee como «cargando» sin moverse.
//
// Accesible: el caller nombra el estado con `a11yCargando` (string YA localizado);
// los bloques son decorativos para VoiceOver.

public struct LiquidSheetSkeleton: View {
    private let a11yCargando: String

    @State private var fase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// Alturas aproximadas del contenido rico que el skeleton suplanta — geometría
    /// interna del componente (contrato §5: candidato menor, no token del sistema).
    private enum Alto {
        /// Doble dato: numeral 34 + etiqueta.
        static let dobleDato: CGFloat = 72
        /// Línea de lectura (una frase corta).
        static let lectura: CGFloat = 20
        /// Barra de etapas: overline + barra 12 + leyenda (barra 24→12, auditoría 2026-08-03).
        static let etapas: CGFloat = 52
        /// Gráfica de niveles (alto del explorador — debe igualar `LiquidChartAlto.explorador`).
        static let grafica: CGFloat = 144
    }

    public init(a11yCargando: String) {
        self.a11yCargando = a11yCargando
    }

    private var quieto: Bool { reduceMotion || motionDisabled }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s400) {
            bloque(alto: Alto.dobleDato)
            bloque(alto: Alto.lectura)
            bloque(alto: Alto.etapas)
            bloque(alto: Alto.grafica)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yCargando))
        .onAppear {
            guard !quieto, !fase else { return }
            withAnimation(LiquidMotion.flowLinear(LiquidMotion.flowPeriod)
                .repeatForever(autoreverses: false)) { fase = true }
        }
    }

    /// Un bloque redacted: vidrio/superficie vacío a la altura del contenido que espera,
    /// con el streak del shimmer recortado a su forma.
    private func bloque(alto: CGFloat) -> some View {
        Color.clear
            .frame(height: alto)
            .frame(maxWidth: .infinity)
            .overlay {
                if !quieto {
                    streak
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
            .liquidGlass(.superficieSolida)
    }

    /// El streak que viaja: banda especular (blanco de vidrio) que cruza el bloque una
    /// vez por periodo `flow`, lineal — nunca rebota.
    private var streak: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, LiquidColor.vidrioStreak, .clear],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.45)
                .offset(x: fase ? geo.size.width * 1.1 : -geo.size.width * 0.45)
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Liquid · SheetSkeleton (animado)") {
    LiquidSheetSkeleton(a11yCargando: "Cargando tu noche")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

#Preview("Liquid · SheetSkeleton (estático)") {
    // Reduce Motion / renders congelados: bloques en reposo, sin streak.
    LiquidSheetSkeleton(a11yCargando: "Cargando tu noche")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
        .environment(\.liquidMotionDisabled, true)
}
#endif
