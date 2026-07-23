import SwiftUI

// MARK: - Liquid Glass · Cascarón de hoja de resumen (épico hoja Liquid, F1)
//
// El envoltorio ÚNICO de la hoja: fondo `LiquidSheetFondo` (degradado + suspiro del tono),
// grip del sistema, detents con paridad al comportamiento actual de MetricInfoSheet
// (`.medio` hojas cortas · `.porContenido` para las hojas con instrumento/curva), scroll
// y la columna de contenido con el gap de hoja. Las variantes componen adentro
// (header → cuerpo → pie); el cascarón no conoce métricas.

/// Paridad de detents con MetricInfoSheet:274-278 (revote adversarial F1: la hoja corta
/// es SOLO .medium, y la de instrumento mide su contenido con fallback .large hasta el
/// primer layout — el mismo mecanismo de la hoja vieja).
public enum LiquidSheetDetent: Sendable, Equatable {
    /// Hojas cortas (la mayoría): detent medio del sistema, sin .large.
    case medio
    /// Hojas con instrumento/curva (strain, heart_rate, trend, niveles): alto medido del
    /// contenido; .large mientras la primera pasada de layout no ha medido.
    case porContenido
}

/// PreferenceKey del alto medido del contenido (paridad SheetContentHeightKey).
private struct LiquidSheetAltoKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct LiquidMetricSheet<Content: View>: View {
    private let tono: Color
    private let detent: LiquidSheetDetent
    private let cargando: Bool
    private let content: Content

    @State private var altoMedido: CGFloat = 0

    /// `cargando` evita fijar la altura con un frame que todavía no tiene el contenido
    /// (pasada UX H1): sin esto la hoja se congelaba a la medida del ESQUELETO y el
    /// contenido rico quedaba apretado en cuanto llegaba.
    public init(tono: Color, detent: LiquidSheetDetent = .medio, cargando: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.tono = tono
        self.detent = detent
        self.cargando = cargando
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Ritmo (pasada UI H4): los BLOQUES respiran más que lo de adentro — s550
            // entre bloques contra los s150/s300 internos. Un gap uniforme leía plano.
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                content
            }
            .padding(LiquidSpace.s550)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { geo in
                Color.clear.preference(key: LiquidSheetAltoKey.self, value: geo.size.height)
            })
        }
        // La altura se fija con la PRIMERA medición (pedido del dueño /inject): si se
        // re-midiera, abrir el ⓘ agrandaría la hoja y todo saltaría hacia ARRIBA; con la
        // altura fija, la explicación empuja el contenido hacia abajo dentro del scroll.
        .onPreferenceChange(LiquidSheetAltoKey.self) { nuevo in
            // La altura CRECE, nunca encoge, y nunca se fija con un frame de carga.
            // Congelarla en la PRIMERA medición (intento anterior) la dejaba clavada con
            // un layout a medio resolver y la hoja abría corta. Al toparse con el techo
            // de la pantalla deja de crecer, y ahí el ⓘ empuja el contenido hacia abajo
            // dentro del scroll — que es lo que el dueño pidió.
            guard !cargando else { return }
            if nuevo > altoMedido { altoMedido = nuevo }
        }
        .presentationBackground { LiquidSheetFondo(tone: tono) }
        .presentationDragIndicator(.visible)
        .presentationDetents(detents)
        .presentationCornerRadius(LiquidRadius.hoja)
    }

    private var detents: Set<PresentationDetent> {
        switch detent {
        case .medio:
            // `.large` también en las cortas (pasada UX H4): con el ⓘ abierto en Dynamic
            // Type grande, leer 15 líneas por media pantalla sin poder crecer es hostil.
            return [.medium, .large]
        case .porContenido:
            // `.large` acompaña a la altura medida: con contenido largo la hoja se
            // quedaba sin a dónde crecer y el scroll moría. Bajo un mínimo razonable no
            // vale la pena la medida — mejor abrir en `.large` que en una rendija.
            return altoMedido > 320 ? [.height(altoMedido), .large] : [.large]
        }
    }
}

#if DEBUG
#Preview("Liquid · MetricSheet (VFC)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        LiquidMetricSheet(tono: LiquidColor.cian) {
            LiquidSheetHeader(icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                              numeral: "56", unidad: "ms",
                              origenEtiqueta: "Apple Salud · anoche",
                              explicacion: "La variación entre latidos mientras duermes.")
            LiquidReadingLine("Tu VFC amaneció en tu rango.",
                              highlight: "en tu rango",
                              highlightTone: LiquidColor.verdeProfundo)
            LiquidMetodo(title: "Cómo se calcula") {
                LiquidNotaLine("SDNN sobre los latidos nocturnos (Task Force, 1996).")
            }
            LiquidVerMas(title: "Ver más en Tendencias", hint: "Abre el detalle completo",
                         tone: LiquidColor.cian, anchoCompleto: true, action: {})
        }
    }
}
#endif
