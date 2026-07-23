import SwiftUI

// MARK: - Liquid Glass · Cascarón de hoja de resumen (épico hoja Liquid, F1)
//
// El envoltorio ÚNICO de la hoja: fondo `LiquidSheetFondo` (degradado + suspiro del tono),
// grip del sistema, detents con paridad al comportamiento actual de MetricInfoSheet
// (`.medio` hojas cortas · `.porContenido` para las hojas con instrumento/curva), scroll
// y la columna de contenido con el gap de hoja. Las variantes componen adentro
// (header → cuerpo → pie); el cascarón no conoce métricas.

/// Paridad de detents con MetricInfoSheet:274-278.
public enum LiquidSheetDetent: Sendable, Equatable {
    /// Hojas cortas (la mayoría): detent medio del sistema.
    case medio
    /// Hojas con instrumento/curva (strain, heart_rate, niveles): alto por contenido.
    case porContenido(CGFloat)
}

public struct LiquidMetricSheet<Content: View>: View {
    private let tono: Color
    private let detent: LiquidSheetDetent
    private let content: Content

    public init(tono: Color, detent: LiquidSheetDetent = .medio,
                @ViewBuilder content: () -> Content) {
        self.tono = tono
        self.detent = detent
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                content
            }
            .padding(LiquidSpace.s550)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationBackground { LiquidSheetFondo(tone: tono) }
        .presentationDragIndicator(.visible)
        .presentationDetents(detents)
        .presentationCornerRadius(LiquidRadius.hoja)
    }

    private var detents: Set<PresentationDetent> {
        switch detent {
        case .medio:
            return [.medium, .large]
        case .porContenido(let alto):
            return [.height(alto), .large]
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
