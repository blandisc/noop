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

/// Carries a sheet's measured natural content height up to size its `.presentationDetents` (FER-112).
/// `reduce` takes the max across all reporters in a frame — the canonical form used by every "size the
/// sheet to its content" caller. The one documented exception is `ReceiptPrinterScreen`'s reveal-mask
/// height, which needs the CURRENT value (not a running max) and keeps its own private key (FER-975).
/// Moved here from SheetPaper.swift (FER-286); LiquidMetricSheet is the sole consumer.
struct SheetContentHeightKey: PreferenceKey {
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

    /// El alto con el que la hoja ABRE, congelado con la primera medición utilizable.
    /// Es el detent SELECCIONADO, así que no puede seguir a `altoMedido`: si lo siguiera,
    /// abrir el ⓘ (que crece) subiría la hoja de golpe — justo lo que el dueño prohibió.
    @State private var altoApertura: CGFloat = 0

    /// Detent vigente. Sin selección explícita iOS conserva el que ya estaba —el `.large`
    /// con el que la hoja se presenta mientras mide— y las hojas con instrumento se
    /// quedaban clavadas en pantalla completa (la hoja vieja abría a la medida porque su
    /// conjunto tenía un solo detent, `MetricInfoSheet:277`).
    @State private var seleccion: PresentationDetent

    /// `cargando` evita fijar la altura con un frame que todavía no tiene el contenido
    /// (pasada UX H1): sin esto la hoja se congelaba a la medida del ESQUELETO y el
    /// contenido rico quedaba apretado en cuanto llegaba.
    public init(tono: Color, detent: LiquidSheetDetent = .medio, cargando: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.tono = tono
        self.detent = detent
        self.cargando = cargando
        self.content = content()
        let inicial: PresentationDetent = (detent == .medio) ? .medium : .large
        _seleccion = State(initialValue: inicial)
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Ritmo (pasada UI H4 → ajuste r3): los BLOQUES respiran más que lo de adentro
            // — s400 entre bloques contra los s150/s300 internos. El s550 original dejaba
            // a la frase-veredicto flotando con «mucho espacio arriba y abajo» (dueño);
            // el mock lleva 9/18px alrededor de la frase, más cerca de 16 que de 22.
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                content
            }
            .padding(LiquidSpace.s550)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { geo in
                Color.clear.preference(key: SheetContentHeightKey.self, value: geo.size.height)
            })
        }
        // El alto del contenido CRECE, nunca encoge (pedido del dueño /inject): con el
        // detent de apertura congelado, abrir el ⓘ empuja el contenido hacia abajo dentro
        // del scroll en vez de saltar hacia ARRIBA.
        // Re-medir hacia abajo con un umbral ciego (por el hueco al cambiar de rango) se
        // evaluó y se DESCARTÓ: cerrar el ⓘ también encoge, y encogerlo ahí es justo el
        // salto prohibido. Si el hueco llega a molestar, atarlo a la CAUSA (el rango
        // seleccionado), no a un delta.
        .onPreferenceChange(SheetContentHeightKey.self) { nuevo in
            // Nunca se fija con un frame de carga; y congelar `altoMedido` en la primera
            // medición (intento anterior) lo dejaba clavado con un layout a medio resolver
            // y la hoja abría corta — por eso el que se congela es el detent, no la medida.
            guard !cargando else { return }
            if nuevo > altoMedido { altoMedido = nuevo }
            // La hoja abre a la medida de su contenido. Bajo un mínimo razonable no vale
            // la pena la medida — mejor abrir en `.large` que en una rendija. El detent
            // de apertura se fija UNA vez: `altoMedido` sigue creciendo, pero sólo para
            // el conjunto.
            if detent == .porContenido, altoApertura == 0, altoMedido > 320 {
                altoApertura = altoMedido
                seleccion = .height(altoMedido)
            }
        }
        .presentationBackground { LiquidSheetFondo(tone: tono) }
        .presentationDragIndicator(.visible)
        .presentationDetents(detents, selection: $seleccion)
        .presentationCornerRadius(LiquidRadius.hoja)
    }

    private var detents: Set<PresentationDetent> {
        switch detent {
        case .medio:
            // `.large` también en las cortas (pasada UX H4): con el ⓘ abierto en Dynamic
            // Type grande, leer 15 líneas por media pantalla sin poder crecer es hostil.
            return [.medium, .large]
        case .porContenido:
            guard altoApertura > 0 else { return [.large] }
            // `.height(altoApertura)` es el detent seleccionado: nunca sale del conjunto,
            // o iOS reasignaría la selección y la hoja se re-dimensionaría sola.
            // `.height(altoMedido)` acompaña al contenido que ya creció (el ⓘ abierto) y
            // `.large` deja el tope siempre a mano: sin él la hoja se quedaba sin a dónde
            // crecer y el scroll moría.
            return [.height(altoApertura), .height(altoMedido), .large]
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
