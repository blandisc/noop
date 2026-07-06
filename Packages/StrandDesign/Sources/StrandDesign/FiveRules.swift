import SwiftUI

// MARK: - Las cinco reglas (handoff «Hoy» 2026-07 · FER-709)
//
// The «POR QUÉ 74» instrument: the recovery score as visible arithmetic. One row per driver;
// the row's LENGTH is the driver's real engine weight (one mark per point), its LIT marks are
// the driver's share of today's score, so the lit total across rows equals the numeral exactly.
// The app computes rows with `StrandAnalytics.RecoveryRules` and passes plain values in — this
// view owns only the drawing. A breathing dot marks where each partially-lit group switches
// off (the live edge of today's read).
//
// Marks share ONE pitch across rows (derived from the longest row), so length is weight —
// «el largo es el peso».

public struct FiveRulesView: View {

    public struct Row: Identifiable, Equatable {
        public let id: String
        /// Short group label, shown uppercased in the row's data color («SUEÑO»).
        public let label: String
        public let color: Color
        public let marks: Int
        public let lit: Int
        public init(id: String, label: String, color: Color, marks: Int, lit: Int) {
            self.id = id; self.label = label; self.color = color; self.marks = marks; self.lit = lit
        }
    }

    public var rows: [Row]
    /// 0…1 lights the lit marks in sequence across the instrument (the pull-to-refresh
    /// celebration). 1 = settled (default; opening the screen never animates).
    public var reveal: Double

    @Environment(\.instrumentoTheme) private var theme

    public init(rows: [Row], reveal: Double = 1) {
        self.rows = rows; self.reveal = reveal
    }

    // FER-743: 23 → 20 para compactar SEÑALES sin scroll (las marcas de 12/7 pt siguen cabiendo).
    private static let rowHeight: CGFloat = 20
    private static let labelWidth: CGFloat = 74
    private static let valueWidth: CGFloat = 40

    public var body: some View {
        let maxMarks = max(rows.map(\.marks).max() ?? 1, 1)
        let visible = visibleLitByRow()
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                ruleRow(row, visibleLit: visible[i], maxMarks: maxMarks)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Reveal sequencing: the lit marks light left→right, row by row, as `reveal` sweeps 0→1.
    private func visibleLitByRow() -> [Int] {
        let total = rows.reduce(0) { $0 + $1.lit }
        var budget = reveal >= 1 ? total : Int((reveal * Double(total)).rounded(.down))
        return rows.map { row in
            let v = min(row.lit, budget)
            budget -= v
            return v
        }
    }

    @ViewBuilder
    private func ruleRow(_ row: Row, visibleLit: Int, maxMarks: Int) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            Text(row.label)
                .font(InstrumentoType.grotesk(9, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(row.color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: Self.labelWidth, alignment: .leading)
            marksCanvas(row, visibleLit: visibleLit, maxMarks: maxMarks)
            Text(verbatim: "\(row.lit)/\(row.marks)")
                .font(InstrumentoType.grotesk(11, weight: .bold).monospacedDigit())
                .foregroundStyle(theme.inkSecondary)
                .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: String(localized: "%1$@: %2$lld of %3$lld points", bundle: .main), row.label, row.lit, row.marks)))
    }

    private func marksCanvas(_ row: Row, visibleLit: Int, maxMarks: Int) -> some View {
        GeometryReader { geo in
            let pitch = geo.size.width / CGFloat(maxMarks)
            let baseline = Self.rowHeight - 5
            Canvas { ctx, _ in
                for i in 0..<row.marks {
                    let x = CGFloat(i) * pitch + pitch / 2
                    let isLit = i < visibleLit
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: baseline))
                    path.addLine(to: CGPoint(x: x, y: baseline - (isLit ? 12 : 7)))
                    ctx.stroke(path,
                               with: .color(isLit ? row.color : row.color.opacity(0.24)),
                               style: StrokeStyle(lineWidth: isLit ? 2.6 : 1.3, lineCap: .round))
                }
            }
            // The live edge: a breathing dot where the group switches off (only when the row
            // is partially lit — a full or empty row has no edge to watch).
            if row.lit > 0, row.lit < row.marks, visibleLit == row.lit {
                BreathingDot(color: row.color, radius: 1.8)
                    .position(x: CGFloat(row.lit) * pitch - pitch / 2, y: baseline - 12 - 3)
            }
        }
        .frame(height: Self.rowHeight)
    }
}

#if DEBUG
#Preview("Cinco reglas") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Why 74").groteskOverline().foregroundStyle(t.inkTertiary)
            Spacer()
            Text("Length is weight").groteskOverline(small: true).foregroundStyle(t.inkMuted)
        }
        FiveRulesView(rows: [
            .init(id: "hrv", label: "HRV", color: t.dataHrv, marks: 54, lit: 43),
            .init(id: "rhr", label: "Resting HR", color: t.dataHeart, marks: 18, lit: 14),
            .init(id: "sleep", label: "Sleep", color: t.dataSleep, marks: 14, lit: 9),
            .init(id: "skinTemp", label: "Skin temp", color: t.dataStrain, marks: 9, lit: 6),
            .init(id: "respRate", label: "Respiration", color: t.dataSpO2, marks: 5, lit: 2),
        ])
    }
    .padding(24)
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
