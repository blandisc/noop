import SwiftUI

// MARK: - «Detalle de Tendencias Final» — componentes compartidos (FER-856/857)
//
// FER-164: el apagón del papel dejó aquí solo las piezas CON consumidor vivo verificado por
// símbolo (2026-08-30). Las demás (`SeccionFranja`, `SeccionBloque`, `TileSurface`, `PieMetodo`,
// `QueMedimosCard`, `ChipTendencia`, `QueLaMueveHeader`, `PaperSideBarBlock`) se borraron cuando
// su último consumidor migró a Liquid. FER-280·3c podó además `HeatLegend` — su único consumidor
// real era `HeatCalendarSection`, también podado (0 usos reales fuera de su propio preview).
// Sobreviven:
//
//   · `BarraAncla` — el ÚNICO formato legal de caption (rect 2×10 del color del dato + texto);
//                    vive en `WorkoutHistoryScreen` y dentro de `GraficaRangos`
//   · `Metodo`     — el DisclosureGroup «Cómo se calcula» sobre superficie (`RestEditorScreen`)
//   · `OnFieldOpacity` — opacidades sancionadas sobre campo invertido (`ConfidenceSello`)
//
// Los componentes son mudos en copy: reciben `String`/`LocalizedStringKey` ya localizados desde la
// capa de app (el paquete no carga catálogo propio).

// MARK: - Opacidades sobre campo invertido

/// Opacidades sancionadas para texto/chrome sobre un campo saturado (el texto es `theme.paper`
/// sobre el hue de la pantalla). Del handoff: secundarios 0.72–0.78, cápsula 0.16.
enum OnFieldOpacity {
    /// Texto secundario sobre el campo («/100», «vs tu base», el driver del veredicto).
    public static let secondary: Double = 0.75
    /// Fondo de la cápsula secundaria («+6 vs tu base», «en curso»).
    static let capsule: Double = 0.16
    /// Chrome atenuado (el trazo del ⓘ).
    static let dimChrome: Double = 0.8
    /// Regla/divisor vertical entre dos datos sobre el campo invertido.
    static let divider: Double = 0.28
}

// MARK: - BarraAncla

/// El único formato legal de caption bajo un instrumento: un rectángulo 2×10 del color del dato que
/// explica + texto 11pt en tinta terciaria. Ningún caption flota sin su ancla.
public struct BarraAncla: View {
    private let texto: String
    private let color: Color
    private let theme: InstrumentoTheme

    public init(_ texto: String, color: Color, theme: InstrumentoTheme) {
        self.texto = texto
        self.color = color
        self.theme = theme
    }

    public var body: some View {
        // La barra (rect 2pt) abarca TODA la altura del texto — no una raya de 10pt: en captions de dos
        // renglones cubría solo el primero. Overlay a la izquierda del texto: su alto lo fija el texto.
        Text(texto)
            .font(StrandFont.scaled(11))
            .lineSpacing(2.5)
            .foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 7)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 2)
            }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Metodo

#if !os(watchOS)
/// El DisclosureGroup «Cómo se calcula» estandarizado: superficie radio 12, padding 14, plegado por
/// defecto. El título llega localizado desde la app; el contenido es libre.
public struct Metodo<Content: View>: View {
    private let title: String
    private let theme: InstrumentoTheme
    private let content: Content
    @State private var expanded = false

    public init(title: String, theme: InstrumentoTheme, @ViewBuilder content: () -> Content) {
        self.title = title
        self.theme = theme
        self.content = content()
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                content
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(StrandFont.scaled(13))
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
#endif

// MARK: - Previews

#if DEBUG
#if !os(watchOS)
#Preview("BarraAncla + Metodo") {
    let t = InstrumentoTheme.base
    VStack(alignment: .leading, spacing: 18) {
        BarraAncla("El pronóstico es una proyección, no una garantía.", color: t.verdict, theme: t)
        Metodo(title: "Cómo se calcula", theme: t) {
            Text("Cada señal se compara con tu propia base de 30 días.")
                .font(StrandFont.scaled(13))
                .foregroundStyle(t.inkSecondary)
        }
    }
    .padding(20)
    .background(t.paper)
}
#endif
#endif
