import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - AutonomicTrendCard

/// La tarjeta «cómo vienes» del path Apple-only de Hoy. Estados por `read.confidence` + `read.direction`.
struct AutonomicTrendCard: View {
    let read: AutonomicTrend.Read
    let showLowSampleBanner: Bool
    var onTap: () -> Void

    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            switch read.confidence {
            case .calibrating:
                calibratingContent
            case .building:
                buildingContent
            case .solid:
                solidContent
            }
            if showLowSampleBanner {
                lowSampleBanner
            }
        }
        .padding(CenitMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)   // llenar el ancho en los 3 estados (building no lo forzaba)
        .background(
            RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .stroke(theme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }

    // MARK: - State 1 · calibrating

    private var calibratingContent: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text("CÓMO VIENES")
                .instrumentoOverline()
                .foregroundStyle(theme.inkTertiary)

            HStack {
                Spacer(minLength: 0)
                calibratingRing
                Spacer(minLength: 0)
            }

            Text("Conociéndote. Necesito unas semanas de noches para leer tu tendencia.")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var calibratingRing: some View {
        let diameter: CGFloat = 68
        let fraction = min(1, max(0, CGFloat(read.nightsUsable) / 21.0))
        return ZStack {
            Circle()
                .stroke(theme.hairline, lineWidth: 7)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    theme.dataHrv,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(read.nightsUsable)")
                    .font(StrandFont.number(30))
                    .foregroundStyle(theme.ink)
                Text("de 21 noches")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    // MARK: - State 2 · building

    private var buildingContent: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            HStack(alignment: .center, spacing: CenitMetrics.space2) {
                Text("CÓMO VIENES")
                    .instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary)
                Text("afinando")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.tint(theme.dataHrv), in: Capsule())
            }

            Text("Sigo aprendiendo tu rango normal.")
                .font(StrandFont.body)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - State 3 · solid

    private var solidContent: some View {
        let direction = read.direction ?? .inBase
        return VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            leadPhrase(direction)
            zBand(direction)
            Text("últimos 7 días · sobre tu propia base")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
        }
    }

    private func leadPhrase(_ direction: AutonomicTrend.Direction) -> some View {
        (
            Text("Tu HRV de sueño viene ").foregroundStyle(theme.ink)
            + Text(directionPhrase(direction)).foregroundStyle(directionColor(direction))
            + Text(" tu promedio.").foregroundStyle(theme.ink)
        )
        .font(StrandFont.title3)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func directionPhrase(_ direction: AutonomicTrend.Direction) -> String {
        switch direction {
        case .below: return "por debajo de"
        case .inBase: return "en"
        case .above: return "por encima de"
        }
    }

    /// Valencia: `.above` and `.below` share `theme.warning`. Never green / `verdict` for high HRV.
    private func directionColor(_ direction: AutonomicTrend.Direction) -> Color {
        switch direction {
        case .below, .above: return theme.warning
        case .inBase: return theme.ink
        }
    }

    private func markerFill(_ direction: AutonomicTrend.Direction) -> Color {
        switch direction {
        case .below, .above: return theme.warning
        case .inBase: return theme.inkSecondary
        }
    }

    private func zBand(_ direction: AutonomicTrend.Direction) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            GeometryReader { geo in
                let w = geo.size.width
                VStack(spacing: 2) {
                    if !read.spark.isEmpty {
                        sparkline(width: w, height: 14)
                            .frame(height: 14)
                            .accessibilityHidden(true)
                    }
                    zTrack(width: w, direction: direction)
                        .frame(height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: read.spark.isEmpty ? 10 : 32)

            HStack {
                Text("por debajo")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 0)
                Text("tu rango normal")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.dataHrv)
                Spacer(minLength: 0)
                Text("por encima")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
    }

    private func zTrack(width: CGFloat, direction: AutonomicTrend.Direction) -> some View {
        let trackHeight: CGFloat = 6
        let markerSize: CGFloat = 7.5
        let z = min(2, max(-2, read.z7d ?? 0))
        let markerX = mapZToX(z, trackWidth: width)
        // Dead-zone z ∈ [−0.5, +0.5] → 1/4 of the [−2, +2] track, centered.
        let deadWidth = width * (1.0 / 4.0)
        let deadX = width / 2

        return ZStack {
            RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                .fill(theme.hairline)
                .frame(width: width, height: trackHeight)

            RoundedRectangle(cornerRadius: 2, style: .continuous) // token-exempt: banda de zona muerta del track z (geometría de dato)
                .fill(theme.dataHrv.opacity(StrandOpacity.tintFillStrong))
                .frame(width: deadWidth, height: trackHeight)
                .position(x: deadX, y: markerSize / 2)

            Path { path in
                path.move(to: CGPoint(x: width / 2, y: 0))
                path.addLine(to: CGPoint(x: width / 2, y: trackHeight + 1))
            }
            .stroke(theme.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .frame(width: width, height: trackHeight + 1)

            Circle()
                .fill(markerFill(direction))
                .overlay(
                    Circle()
                        .stroke(theme.surface, lineWidth: 2.5)
                )
                .frame(width: markerSize, height: markerSize)
                .position(x: markerX, y: markerSize / 2)
        }
        .frame(width: width, height: markerSize)
    }

    @ViewBuilder
    private func sparkline(width: CGFloat, height: CGFloat) -> some View {
        let values = read.spark
        if values.isEmpty {
            EmptyView()
        } else if values.count == 1, let only = values.first {
            // Single point: end marker only, no polyline.
            let color: Color = abs(only) > AutonomicTrend.swcK
                ? theme.warning
                : theme.ink.opacity(StrandOpacity.muted)
            Circle()
                .fill(color)
                .frame(width: 3.5, height: 3.5)
                .position(x: width / 2, y: height / 2)
                .frame(width: width, height: height)
        } else {
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = maxV - minV
            let count = values.count
            let lastRaw = values.last ?? 0
            let lastColor: Color = abs(lastRaw) > AutonomicTrend.swcK
                ? theme.warning
                : theme.ink.opacity(StrandOpacity.muted)

            ZStack(alignment: .topLeading) {
                Path { path in
                    for (i, v) in values.enumerated() {
                        let t: CGFloat = range < 1e-9
                            ? 0.5
                            : CGFloat((v - minV) / range)
                        // Invert: higher value → higher on screen → smaller y.
                        let y = (1 - t) * height
                        let x = CGFloat(i) / CGFloat(count - 1) * width
                        let p = CGPoint(x: x, y: y)
                        if i == 0 {
                            path.move(to: p)
                        } else {
                            path.addLine(to: p)
                        }
                    }
                }
                .stroke(
                    theme.ink.opacity(StrandOpacity.muted),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                let lastT: CGFloat = range < 1e-9
                    ? 0.5
                    : CGFloat((lastRaw - minV) / range)
                Circle()
                    .fill(lastColor)
                    .frame(width: 3.5, height: 3.5)
                    .position(
                        x: CGFloat(count - 1) / CGFloat(count - 1) * width,
                        y: (1 - lastT) * height
                    )
            }
            .frame(width: width, height: height)
        }
    }

    /// Linear map of z ∈ [−2, +2] → x ∈ [0, trackWidth].
    private func mapZToX(_ z: Double, trackWidth: CGFloat) -> CGFloat {
        CGFloat((z + 2) / 4) * trackWidth
    }

    // MARK: - Low-sample banner (any state)

    private var lowSampleBanner: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
            Text("Anoche tu reloj tomó pocas muestras; hoy no muevo la tendencia.")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabelText: String {
        let suffix = " Toca para saber cómo se estima."
        switch read.confidence {
        case .calibrating:
            return "Conociéndote. Necesito unas semanas de noches para leer tu tendencia." + suffix
        case .building:
            return "Sigo aprendiendo tu rango normal." + suffix
        case .solid:
            let direction = read.direction ?? .inBase
            return "Tu HRV de sueño viene \(directionPhrase(direction)) tu promedio." + suffix
        }
    }
}

// MARK: - AutonomicTrendDetailSheet

/// Explainer presented by the caller via `.sheet`. Theme is an explicit parameter because
/// `.sheet` sits in a fresh environment that does not reliably inherit `.instrumentoTheme`.
struct AutonomicTrendDetailSheet: View {
    var theme: InstrumentoTheme = .base

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("Cómo estimo tu tendencia")
                    .font(StrandFont.title3)
                    .foregroundStyle(theme.ink)

                Text("Miro la variabilidad de los latidos que tu reloj registra mientras duermes y la comparo con tu propio promedio, no con el de otra persona ni con un número fijo de población.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Es una guía de dirección, no una medición médica ni una puntuación exacta.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Task Force 1996; Plews 2013")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CenitMetrics.cardPadding)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }
}

// MARK: - Previews

#if DEBUG
private enum AutonomicTrendCardPreviewData {
    static let calibrating = AutonomicTrend.Read(
        direction: nil,
        confidence: .calibrating,
        nightsUsable: 8,
        nightsToTrend: 6,
        recentDenseNights: 8,
        z7d: nil,
        spark: [],
        asOfWasDense: true
    )

    static let building = AutonomicTrend.Read(
        direction: .inBase,
        confidence: .building,
        nightsUsable: 16,
        nightsToTrend: 0,
        recentDenseNights: 7,
        z7d: nil,
        spark: [],
        asOfWasDense: true
    )

    static let solidAbove = AutonomicTrend.Read(
        direction: .above,
        confidence: .solid,
        nightsUsable: 25,
        nightsToTrend: 0,
        recentDenseNights: 7,
        z7d: 0.8,
        spark: [-0.2, 0.1, 0.3, 0.5, 0.6, 0.4, 0.7, 0.8, 0.6, 0.8],
        asOfWasDense: true
    )

    static let solidInBase = AutonomicTrend.Read(
        direction: .inBase,
        confidence: .solid,
        nightsUsable: 25,
        nightsToTrend: 0,
        recentDenseNights: 7,
        z7d: -0.1,
        spark: [-0.2, 0.05, -0.1, 0.15, 0.0, -0.05, 0.1, -0.15, 0.05, -0.1],
        asOfWasDense: true
    )
}

#Preview("Calibrating") {
    let t = InstrumentoTheme.base
    AutonomicTrendCard(
        read: AutonomicTrendCardPreviewData.calibrating,
        showLowSampleBanner: false,
        onTap: {}
    )
    .padding()
    .background(t.paper)
    .environment(\.instrumentoTheme, t)
}

#Preview("Building") {
    let t = InstrumentoTheme.base
    AutonomicTrendCard(
        read: AutonomicTrendCardPreviewData.building,
        showLowSampleBanner: false,
        onTap: {}
    )
    .padding()
    .background(t.paper)
    .environment(\.instrumentoTheme, t)
}

#Preview("Solid · above") {
    let t = InstrumentoTheme.base
    AutonomicTrendCard(
        read: AutonomicTrendCardPreviewData.solidAbove,
        showLowSampleBanner: false,
        onTap: {}
    )
    .padding()
    .background(t.paper)
    .environment(\.instrumentoTheme, t)
}

#Preview("Solid · inBase") {
    let t = InstrumentoTheme.base
    AutonomicTrendCard(
        read: AutonomicTrendCardPreviewData.solidInBase,
        showLowSampleBanner: false,
        onTap: {}
    )
    .padding()
    .background(t.paper)
    .environment(\.instrumentoTheme, t)
}

#Preview("Solid · low-sample banner") {
    let t = InstrumentoTheme.base
    AutonomicTrendCard(
        read: AutonomicTrendCardPreviewData.solidAbove,
        showLowSampleBanner: true,
        onTap: {}
    )
    .padding()
    .background(t.paper)
    .environment(\.instrumentoTheme, t)
}

#Preview("Detail sheet") {
    AutonomicTrendDetailSheet(theme: .base)
}
#endif
