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
// Esqueleto Final (misma forma que `MetricDetailScreen.narrativeBodyFinal` / `SkinTempDetailScreen`):
// HeroInvertido → SeccionBloque «Your sports» (TarjetaSesion B) → disclaimer → PieMetodo.
// Full-bleed. Theme is passed explicitly (it does NOT cross the `.sheet` boundary). Math and
// ranking are preserved; this is a reskin of the sport list only.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroFinal
                if costs.isEmpty {
                    emptyState
                        .padding(.horizontal, 20)
                } else {
                    SeccionBloque(String(localized: "Your sports"), theme: theme) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(costs.enumerated()), id: \.offset) { _, cost in
                                sportCard(cost)
                            }
                        }
                    }
                    Text("It's an estimate from your own history, not a diagnosis.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    pieMetodoFinal
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }

    // MARK: - Hero Final (HeroInvertido · dataStrain · top-sport delta)

    /// Inverted hero: the top-ranked sport's median delta as numeral (engine order is |delta| desc ·
    /// .solid · name asc, so `costs.first` is already the largest effect). Association reading as
    /// verdict. No new aggregate/median is invented here.
    private var heroFinal: some View {
        // FER: numeral = costs.first (tope del ranking del engine), no un promedio nuevo.
        let top = costs.first
        let showsNumeral = top.map { abs($0.delta) >= ActivityCostEngine.barelyMovesPoints } ?? false
        return HeroInvertido(
            glyph: .afterSport,
            title: "After each sport",
            hue: theme.dataStrain,
            theme: theme,
            numeral: {
                if let cost = top, showsNumeral {
                    let pts = Int(abs(cost.delta).rounded())
                    // Same sign convention as sportCard: delta ≥ 0 → lower next morning → "−N".
                    HeroNumeral("\(cost.delta >= 0 ? "−" : "+")\(pts)",
                                suffix: String(localized: "points"),
                                size: 60,
                                theme: theme)
                } else {
                    Text(verbatim: "—")
                        .font(InstrumentoType.groteskNumber(60, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                }
            },
            verdict: {
                Text(heroVerdict)
                    .font(InstrumentoType.grotesk(15, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

    /// Association framing (not cause). Reuses the body prose idea when there is data; neutral when empty.
    private var heroVerdict: LocalizedStringKey {
        if costs.isEmpty {
            return "Still gathering how you wake after each sport."
        }
        if let top = costs.first, abs(top.delta) < ActivityCostEngine.barelyMovesPoints {
            return "Your next-day Charge barely moves after the sports we can see so far."
        }
        // Same association idea as the former body lead-in (short form for the inverted field).
        return "How your Charge tends to look the morning after each sport, vs your rest days. Observed in your history, not a cause."
    }

    // MARK: - Sport card (TarjetaSesion variant B)

    /// One sport as TarjetaSesion B: big delta + recovery bar + session note. A `.building` result is
    /// shown slightly dimmed to read as provisional without hiding it.
    private func sportCard(_ cost: ActivityCost) -> some View {
        let dimmed = cost.confidence == .building
        let pts = Int(abs(cost.delta).rounded())
        let barValue = "\(cost.delta >= 0 ? "−" : "+")\(pts) pts"
        // FER: barPct is a UI approximation only (no engine formula for "return to base" progress).
        // 1.0 when daysToBaseline is known, 0.5 when still open / climbing back without a day count.
        let barPct: Double = cost.daysToBaseline != nil ? 1.0 : 0.5
        let barNota = barNote(for: cost)
        let chip: LocalizedStringKey = cost.confidence == .solid
            ? "solid"
            : "building"
        return TarjetaSesion(
            titulo: cost.sport,
            chip: chip,
            barValue: barValue,
            barColor: theme.dataStrain,
            barPct: barPct,
            barOpacity: dimmed ? 0.72 : 1,
            barNota: barNota,
            theme: theme
        )
        .opacity(dimmed ? 0.72 : 1)
        // Full association sentence (preserved verbatim) for VoiceOver; bar shows the short nota.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(sentence(for: cost)))
    }

    /// Session / climb-back note for the bar. Uses the same fields as `sentence(for:)` without changing
    /// that helper's math or catalog keys (kept for accessibility / future use).
    private func barNote(for cost: ActivityCost) -> String {
        let n = cost.n
        if abs(cost.delta) < ActivityCostEngine.barelyMovesPoints {
            return String(format: String(localized: "%d sessions"), n)
        }
        guard let days = cost.daysToBaseline else {
            // Climbing-back case without a day estimate: sessions only (sentence(for:) still owns the full line).
            return String(format: String(localized: "%d sessions"), n)
        }
        if days == 1 {
            return String(format: String(localized: "Back to your base in ~1 day · %d sessions"), n)
        }
        return String(format: String(localized: "Back to your base in ~%d days · %d sessions"), days, n)
    }

    // MARK: - Sentence (localized; association, never causal)
    // Preserved verbatim for any future call site / a11y; cards use barNote for the TarjetaSesion slot.

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

    // MARK: - PieMetodo (method + origin seal)

    /// Method prose moved from the old DisclosureGroup into Metodo (verbatim); origin seal in sello.
    @ViewBuilder private var pieMetodoFinal: some View {
        PieMetodo(theme: theme) {
            Metodo(title: String(localized: "How it's calculated"), theme: theme) {
                VStack(alignment: .leading, spacing: 10) {
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
            }
        } sello: {
            OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
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
#Preview("ActivityRecoverySheet: con datos") {
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

#Preview("ActivityRecoverySheet: juntando datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ActivityRecoverySheet(costs: [], appleConnectHint: true)
    }
}
#endif
