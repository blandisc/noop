import SwiftUI

// MARK: - LiquidStatePill (FER-280 · clase 4)
//
// Pastilla de estado El Eje — `StatePill` (era Instrumento) no habla Liquid.
// Dos variantes, cada una pixel-fiel a su sitio real:
//
//   · `.estado` — `BreathingView.swift:182-196` / `IntervalTimerView.swift:199-211`:
//     HStack (punto opcional + caption) · pad H s300 · V s150 · `.liquidGlass(.pastillaSolida)`.
//     Dot verde opaco (`LiquidColor.verdePrimario`) cuando el caller no pasa otro tono.
//
//   · `.valencia` — `WorkoutHistoryScreen.swift:645`: chip Δ% con tintFill + chipRadius,
//     tipografía grotesk 11 bold, pad H `chipHorizontal` · V `s075`. El tono lo trae el
//     caller (`theme.positiveText` / `theme.warning`) — la pieza no inventa valencia.
//
// Cuándo SÍ: anunciar estado vivo/listo/pausado sobre cristal de hoja; chip de Δ% con
// color de valencia. Cuándo NO: pastilla Instrumento de chrome (`StatePill`); chip de
// procedencia (`LiquidOrigenChip`/`LiquidOrigenBadge`); filtro removible (`LiquidChipSeleccion`).

/// Constantes de la receta — fuera de la View para que los tests no toquen MainActor.
public enum LiquidStatePillMetrics {
    /// `LiquidSpace.s150` — diámetro del punto (BreathingView / IntervalTimerView).
    public static let dotSize: CGFloat = LiquidSpace.s150
    /// Pad H estado — `LiquidSpace.s300`.
    public static let estadoPadH: CGFloat = LiquidSpace.s300
    /// Pad V estado — `LiquidSpace.s150`.
    public static let estadoPadV: CGFloat = LiquidSpace.s150
    /// Pad H valencia — `LiquidSpace.chipHorizontal` (WorkoutHistoryScreen:645).
    public static let valenciaPadH: CGFloat = LiquidSpace.chipHorizontal
    /// Pad V valencia — `LiquidSpace.s075`.
    public static let valenciaPadV: CGFloat = LiquidSpace.s075
    /// Tipografía valencia — grotesk 11 bold.
    public static let valenciaFontSize: CGFloat = 11
    /// Default del punto «vivo» (BreathingView).
    public static let dotVivoDefault: Color = LiquidColor.verdePrimario
}

public struct LiquidStatePill: View {
    public enum Kind: Sendable {
        /// Pastilla opaca El Eje (`.pastillaSolida`). `dot == nil` → sin punto.
        case estado(dot: Color?)
        /// Chip de valencia Δ%. `tono` ya resuelto por el caller.
        case valencia(tono: Color)
    }

    private let text: String
    private let kind: Kind

    /// Pastilla de estado (BreathingView / IntervalTimerView).
    public init(_ text: String, dot: Color? = nil) {
        self.text = text
        self.kind = .estado(dot: dot)
    }

    /// Chip de valencia (WorkoutHistoryScreen Δ%).
    public init(valencia text: String, tono: Color) {
        self.text = text
        self.kind = .valencia(tono: tono)
    }

    public var body: some View {
        switch kind {
        case .estado(let dot):
            estadoBody(dot: dot)
        case .valencia(let tono):
            valenciaBody(tono: tono)
        }
    }

    // MARK: - Estado (BreathingView:182-196)

    private func estadoBody(dot: Color?) -> some View {
        HStack(spacing: LiquidSpace.s150) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: LiquidStatePillMetrics.dotSize,
                           height: LiquidStatePillMetrics.dotSize)
            }
            Text(verbatim: text)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta900)
        }
        .padding(.horizontal, LiquidStatePillMetrics.estadoPadH)
        .padding(.vertical, LiquidStatePillMetrics.estadoPadV)
        .liquidGlass(.pastillaSolida)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Valencia (WorkoutHistoryScreen:645)

    private func valenciaBody(tono: Color) -> some View {
        Text(verbatim: text)
            .font(InstrumentoType.grotesk(LiquidStatePillMetrics.valenciaFontSize, weight: .bold))
            .foregroundStyle(tono)
            .padding(.horizontal, LiquidStatePillMetrics.valenciaPadH)
            .padding(.vertical, LiquidStatePillMetrics.valenciaPadV)
            .background(tono.opacity(CenitOpacity.tintFill),
                        in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Liquid · StatePill") {
    let t = InstrumentoTheme.base
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        Text("estado · pastillaSolida").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
        HStack(spacing: LiquidSpace.s200) {
            LiquidStatePill("Session live", dot: LiquidStatePillMetrics.dotVivoDefault)
            LiquidStatePill("Ready")
            LiquidStatePill("Running", dot: t.dataStrain)
            LiquidStatePill("Complete", dot: t.dataRecovery)
        }
        Text("valencia · Δ%").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
        HStack(spacing: LiquidSpace.s200) {
            LiquidStatePill(valencia: "↗ +12% vs. last month", tono: t.positiveText)
            LiquidStatePill(valencia: "↘ −8% vs. last month", tono: t.warning)
        }
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
