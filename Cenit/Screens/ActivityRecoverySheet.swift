import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - ActivityRecoverySheet — «Cómo amaneces tras cada deporte» (FER-139)
//
// The light «Instrumento diurno» detail for the ActivityCost engine: per sport, how far below your
// rest-day Charge you tend to wake the morning after a session, over YOUR history. A descriptive
// ASSOCIATION, not a causal cost — every string and the "See the method" disclosure frame it that way
// (regression to the mean, non-random rest days, day-of-week confounders are named).
//
// A sibling of `MetricInfoSheet` (same warm paper, header, `theme.surface` blocks, method disclosure,
// disclaimer) rather than a `MetricInfo` case: its body is a variable-length LIST of sports, not a
// band table, so it doesn't fit that model. The theme is passed explicitly — it does NOT propagate
// through `.sheet`'s fresh environment (same rule the rest of Cuerpo follows).
//
// Cards are read-only (they don't navigate); the sheet ranks them in the engine's exact order and
// never re-sorts or re-filters. Empty input (no sport with enough sessions, or no untouched rest day)
// shows the honest "gathering your sessions" state instead of a fabricated number.

struct ActivityRecoverySheet: View {
    /// One `ActivityCost` per sport, already ranked by the engine (|delta| desc · .solid · name asc).
    let costs: [ActivityCost]

    /// The active «Instrumento diurno» theme, passed explicitly (it does NOT cross the `.sheet`
    /// environment boundary), so the sheet renders on the same warm paper as Cuerpo.
    var theme: InstrumentoTheme = .base

    /// When there are no sessions yet AND Apple Health isn't connected, the empty state offers a quiet
    /// "your workouts can come from Apple Health" line — without a button (the connect action lives in
    /// Today). Never set when there's already data.
    var appleConnectHint: Bool = false

    /// "See the method" disclosure — collapsed each time the sheet opens.
    @State private var methodExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // §8.7 header (FER-805): metric icon + ALL-CAPS overline instead of serif.
                MetricOverline(.afterSport, "After each sport", theme: theme)

                Text("This is how your Charge tends to look the morning after each sport, compared with your rest days. It's what we observe in your history, not a cause-and-effect link.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if costs.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(costs.enumerated()), id: \.offset) { _, cost in
                        sportCard(cost)
                    }
                    methodDisclosure
                    Text("It's an estimate from your own history, not a diagnosis.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Standardized origin seal (FER-805): computed on-device from your history.
                    OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }

    // MARK: - Sport card

    /// One sport: name + confidence badge, the localized impact sentence, and the session count. A
    /// `.building` (thin) result is shown slightly dimmed to read as provisional without hiding it.
    private func sportCard(_ cost: ActivityCost) -> some View {
        let dimmed = cost.confidence == .building
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: cost.sport)               // a real sport name from the source — not a string key
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                cost.confidence.sello(theme: theme)   // shared stamp (ScoreConfidence+Sello); this sheet never shows .calibrating
            }
            // Handoff v2 (reconciliación): el dato numérico prominente en ámbar (una Charge más baja al
            // día siguiente se lee como «−N pts»). Sólo cuando el efecto supera el piso de ruido.
            if abs(cost.delta) >= ActivityCostEngine.barelyMovesPoints {
                let pts = Int(abs(cost.delta).rounded())
                Text(verbatim: "\(cost.delta >= 0 ? "−" : "+")\(pts) pts")
                    .font(InstrumentoType.groteskNumber(21))
                    .foregroundStyle(theme.dataStrain)
            }
            Text(sentence(for: cost))
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(cost.n) sessions")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.cta, theme: theme, lineWidth: 0.5)
        .opacity(dimmed ? 0.72 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sentence (localized; association, never causal)

    /// The plain-language impact line, built from the engine's fields. English source strings mirror
    /// `ActivityCost.sentence()` so the catalog (es-MX / de) translates a wording the engine already
    /// owns. `|delta|` is always ≥ 3 in the typical branch (the engine's `barelyMovesPoints` floor), so
    /// "points" is always plural; only "day/days" varies, handled with separate keys. Direction:
    /// delta ≥ 0 → "lower" (you wake below baseline), < 0 → "higher".
    private func sentence(for cost: ActivityCost) -> LocalizedStringKey {
        let n = cost.n
        if abs(cost.delta) < ActivityCostEngine.barelyMovesPoints {
            return "Sessions like this are barely linked to any change in your next-day Charge (n=\(n))."
        }
        let pts = Int(abs(cost.delta).rounded())
        let lower = cost.delta >= 0
        guard let days = cost.daysToBaseline else {
            return lower
                ? "Sessions like this are typically followed by a Charge about \(pts) points lower the next morning (n=\(n))."
                : "Sessions like this are typically followed by a Charge about \(pts) points higher the next morning (n=\(n))."
        }
        if days == 1 {
            return lower
                ? "Sessions like this are typically followed by a Charge about \(pts) points lower the next morning, climbing back in about 1 day (n=\(n))."
                : "Sessions like this are typically followed by a Charge about \(pts) points higher the next morning, climbing back in about 1 day (n=\(n))."
        }
        return lower
            ? "Sessions like this are typically followed by a Charge about \(pts) points lower the next morning, climbing back in about \(days) days (n=\(n))."
            : "Sessions like this are typically followed by a Charge about \(pts) points higher the next morning, climbing back in about \(days) days (n=\(n))."
    }

    // MARK: - Method disclosure (transparency + named confounders)

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("We compare the median of your Charge the morning after each sport against your “untouched” rest days (no workouts, and not the days right after a session). The difference is what you see here.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It's an association, not a cause. Things like training on the days you already wake up well (then drifting back down), resting when you're tired or sick, or which day of the week you train all play a part.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Medians over your own history (Plews et al., 2013; HRV via RMSSD, Task Force 1996).")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("How it's calculated")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
    }

    // MARK: - Empty state ("gathering your sessions")

    /// Shown when the engine returns nothing — most often because no sport has ~6 sessions yet. We
    /// don't try to split that from the rarer "no untouched rest day" cause (it's not cheaply knowable
    /// here), so we show the dominant, honest message and never fabricate a progress number.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(StrandFont.glyph(.empty))
                .foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("Gathering your sessions")
                .font(StrandFont.title2)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            Text("We need about 6 sessions of the same sport to start showing how you wake afterward. Keep logging your workouts and this fills in on its own.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if appleConnectHint {
                Text("Your workouts can come from Apple Health. Connect it from Today to add them here.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Helpers

// MARK: - Preview

#if DEBUG
#Preview("ActivityRecoverySheet — con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ActivityRecoverySheet(costs: [
            ActivityCost(sport: "Weight Training", delta: 8.2, nextMorningCenter: 54, baselineCenter: 62,
                         daysToBaseline: 2, n: 12, confidence: .solid),
            ActivityCost(sport: "Running", delta: 5.1, nextMorningCenter: 57, baselineCenter: 62,
                         daysToBaseline: nil, n: 7, confidence: .building),
            ActivityCost(sport: "Yoga", delta: 1.4, nextMorningCenter: 61, baselineCenter: 62,
                         daysToBaseline: nil, n: 9, confidence: .solid),
        ])
    }
}

#Preview("ActivityRecoverySheet — juntando datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ActivityRecoverySheet(costs: [], appleConnectHint: true)
    }
}
#endif
