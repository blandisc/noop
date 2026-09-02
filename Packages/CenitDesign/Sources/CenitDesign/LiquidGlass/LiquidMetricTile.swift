import SwiftUI

// MARK: - Liquid Glass · MetricTile (handoff §5.1)
//
// Tile de métrica del grid de Hoy. vidrio/superficie (r/tarjeta, e/0) → columna gap 3:
// [gota 22 + label] · [valor 20 SG700 en TONO + unidad 11 tinta/500] · [delta caption].
// El tono tiñe SOLO gota y valor — nunca el fondo.
//
// **Cuándo sí:** grid de métricas de un hub/tablero Liquid con un delta direccional real
// (vs. base, vs. periodo anterior). **Cuándo no:** una pantalla que solo tiene una serie sin
// signo (usa `delta: nil` + `caption`/`sparkline` — la variante quiet, FER-280 · 1c, H1.4) para
// no forkear la pieza; o una fila de lista (usa `LiquidListRow`).

public struct LiquidMetricTile: View {
    private let label: String
    private let value: String
    private let unit: String
    private let delta: String?
    private let deltaTone: LiquidDeltaTone
    private let tone: Color
    private let icon: LiquidIcon.Glyph
    private let origen: LiquidOrigen
    /// Pie plano sin tono — la variante «quiet» (FER-280 · 1c, H1.4): reemplaza la fila de
    /// delta cuando la pantalla no tiene un cambio direccional que anunciar (Apple Health:
    /// «as of 12 ago» / «avg · 7d»), no una advertencia ni un valor con valencia.
    private let caption: String?
    /// Traza diminuta opcional (quiet): mismo lugar donde iría el delta, para pantallas que
    /// solo tienen una serie, no un cambio con signo (Apple Health).
    private let sparkline: [Double]?
    private let a11yValencia: String?
    private let a11yOrigen: String?
    private let action: (() -> Void)?

    /// - Parameter delta: `nil` dibuja la variante «quiet» — sin fila de delta ni punto de
    ///   procedencia; usa `caption`/`sparkline` en su lugar (FER-280 · 1c: esto es lo que le
    ///   faltaba a `LiquidMetricTile` para que Apple Health lo usara sin fork — H1.4).
    /// - Parameter caption: pie plano sin tono, solo válido cuando `delta` es `nil`.
    /// - Parameter sparkline: traza diminuta opcional, solo válida cuando `delta` es `nil`.
    public init(label: String, value: String, unit: String = "", delta: String? = nil,
                deltaTone: LiquidDeltaTone = .neutral, tone: Color, icon: LiquidIcon.Glyph,
                origen: LiquidOrigen = .medido, caption: String? = nil, sparkline: [Double]? = nil,
                a11yValencia: String? = nil,
                a11yOrigen: String? = nil, action: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.delta = delta
        self.deltaTone = deltaTone
        self.tone = tone
        self.icon = icon
        self.origen = origen
        self.caption = caption
        self.sparkline = sparkline
        self.a11yValencia = a11yValencia
        self.a11yOrigen = a11yOrigen
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.liquidPress)
                .liquidLift(tone: tone)
                .accessibilityLabel(Self.a11yLabel(label: label, value: value,
                                                   unit: unit, delta: delta, caption: caption,
                                                   valencia: a11yValencia))
                .accessibilityValue(Text(verbatim: a11yOrigen ?? ""))
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.a11yLabel(label: label, value: value,
                                                   unit: unit, delta: delta, caption: caption,
                                                   valencia: a11yValencia))
                .accessibilityValue(Text(verbatim: a11yOrigen ?? ""))
        }
    }

    /// «{label}, {value} {unit}, {delta ?? caption}[, {valencia}]» — el contrato de VoiceOver
    /// del tile; la valencia hace audible lo que el color solo muestra (pasada UX). Sin `delta`
    /// ni `caption` (variante quiet mínima) el tercer segmento simplemente no aparece.
    static func a11yLabel(label: String, value: String, unit: String, delta: String? = nil,
                          caption: String? = nil, valencia: String? = nil) -> String {
        let valor = unit.isEmpty ? value : "\(value) \(unit)"
        var base = "\(label), \(valor)"
        if let tercero = delta ?? caption { base += ", \(tercero)" }
        return valencia.map { "\(base), \($0)" } ?? base
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: LiquidSpace.s150) {
                LiquidIconDrop(icon, tone: tone)
                Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(LiquidType.valorL).foregroundStyle(tone)
                if !unit.isEmpty {
                    Text(unit).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                }
            }
            .lineLimit(1)
            if let delta {
                HStack(spacing: LiquidSpace.s100) {
                    LiquidDeltaCaption(delta, tone: deltaTone)
                    if origen == .calculado {
                        LiquidOrigenDot()
                    }
                }
            } else {
                if let sparkline, sparkline.count > 1 {
                    Sparkline(values: sparkline, gradient: Gradient(colors: [tone]),
                              showsArea: false, showsHead: false, showsScrub: false)
                        .frame(height: 18)
                }
                if let caption {
                    Text(caption).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, LiquidSpace.s300)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .liquidGlass(.superficie) // token-exempt: tile de Hoy, no vive dentro de una hoja
        // TODO el tile es tocable, no solo donde hay pixel dibujado (/inject 2026-07-23):
        // sin `contentShape` el botón solo recibe toques sobre el texto/gota.
        .contentShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
    }
}

#if DEBUG
#Preview("Liquid · MetricTile") {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: LiquidSpace.s200), GridItem(.flexible())],
              spacing: LiquidSpace.s200) {
        LiquidMetricTile(label: "SUEÑO", value: "7:20", delta: "En tu base",
                         tone: LiquidColor.indigo, icon: .luna)
        LiquidMetricTile(label: "HRV", value: "56", unit: "ms", delta: "+2 ms vs tu base",
                         deltaTone: .up, tone: LiquidColor.cian, icon: .onda)
        LiquidMetricTile(label: "FC EN REPOSO", value: "52", unit: "lpm", delta: "En tu base",
                         tone: LiquidColor.rosa, icon: .corazon)
        LiquidMetricTile(label: "ESFUERZO", value: "10.0", delta: "−0.7 vs tu base",
                         deltaTone: .down, tone: LiquidColor.ambar, icon: .llama, action: {})
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}

/// Variante «quiet» (FER-280 · 1c): sin `delta`, con `caption`/`sparkline` en su lugar —
/// lo que Apple Health necesita (H1.4) sin forkear la pieza.
#Preview("Liquid · MetricTile quiet") {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: LiquidSpace.s200), GridItem(.flexible())],
              spacing: LiquidSpace.s200) {
        LiquidMetricTile(label: "PESO", value: "72.4", unit: "kg",
                         tone: LiquidColor.tinta700, icon: .carga,
                         caption: "as of 12 ago")
        LiquidMetricTile(label: "HRV", value: "56", unit: "ms",
                         tone: LiquidColor.cian, icon: .onda,
                         sparkline: [48, 52, 50, 55, 53, 56])
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
