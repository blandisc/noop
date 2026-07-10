import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// CyclePhaseView.swift — the opt-in «Fase del ciclo» experiment surface (FER-672). Lives in Ajustes →
// Experiments, OFF by default. A tap opens the consent screen (declares what it is and is NOT); only an
// explicit acknowledgement activates it. Once active, the same sheet shows the current-phase STATE card.
//
// All the math is in `CyclePhaseEngine` (pure, StrandAnalytics). This file only maps the daily metrics
// NOOP already stores into the engine's input and renders the localized, hedged copy — never a date,
// never fertility/ovulation/contraception/diagnosis (the hard claim frame lives in the copy below and
// is guarded by CyclePhaseCopyGuardTests).

/// Opt-in state + informed-consent record for the cycle-phase experiment. On-device only (UserDefaults),
/// the same pattern as `TermsGateView`'s consent record — no account, no network.
enum CyclePhaseExperiment {
    static let enabledKey = "fer672.cyclePhase.enabled"
    static let consentVersionKey = "fer672.cyclePhase.consentVersion"
    /// Bump if the consent copy materially changes, to re-ask (mirrors `Terms.currentVersion`).
    static let consentVersion = 1

    /// Map the stored daily metrics into the engine's per-night input and estimate the current phase.
    /// Pure passthrough — no arithmetic here; the index lives in the engine.
    static func state(from days: [DailyMetric]) -> CyclePhaseEngine.State? {
        guard let today = days.last?.day else { return nil }
        let nights = days.map {
            CyclePhaseEngine.NightSample(day: $0.day,
                                         skinTempDevC: $0.skinTempDevC,
                                         restingHr: $0.restingHr.map(Double.init),
                                         avgHrv: $0.avgHrv)
        }
        return CyclePhaseEngine.estimate(nights, asOf: today)
    }
}

/// The experiment's single sheet: consent when off, the state card when on.
struct CyclePhaseSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(CyclePhaseExperiment.enabledKey) private var enabled = false
    @AppStorage(CyclePhaseExperiment.consentVersionKey) private var consentVersion = 0

    var body: some View {
        ScrollView {
            if enabled {
                CyclePhaseStateBody(days: repo.days,
                                    onDeactivate: { enabled = false })
            } else {
                CyclePhaseConsentBody(onActivate: {
                    consentVersion = CyclePhaseExperiment.consentVersion
                    enabled = true
                }, onDecline: { dismiss() })
            }
        }
        .background(theme.paper.ignoresSafeArea())
    }
}

// MARK: - Consent

private struct CyclePhaseConsentBody: View {
    @Environment(\.instrumentoTheme) private var theme
    let onActivate: () -> Void
    let onDecline: () -> Void
    @State private var acked = false

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EXPERIMENT").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Cycle phase").font(StrandFont.serif(28)).foregroundStyle(theme.ink)
            }
            Text("This is a self-knowledge tool: it looks for a pattern in your own body's temperature while you sleep. Before turning it on, read calmly what it does and what it doesn't.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            CyclePhaseWhatItIs(theme: theme)

            Text("Everything is computed on your iPhone and stays here. You can turn this experiment off whenever you like; nothing is lost. This is not medical advice.")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(theme.hairline)

            Toggle(isOn: $acked) {
                Text("I understand this is a rough estimate to know myself better, not a contraceptive method or a medical tool.")
                    .font(StrandFont.footnote).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.instrumento)

            Button(action: onActivate) {
                Text("Turn on experiment")
                    .font(StrandFont.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent).tint(theme.ink)
            .disabled(!acked)

            Button(action: onDecline) {
                Text("Not now").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The «what it does / what it doesn't» block — the single source of truth for the limits, reused by the
/// consent screen and the ⓘ explainer.
private struct CyclePhaseWhatItIs: View {
    let theme: InstrumentoTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What it does").font(StrandFont.headline).foregroundStyle(theme.ink)
                Text("With several weeks of nights, it learns the rhythm of your temperature and estimates which phase of your cycle you're probably in: follicular or luteal.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The reading is approximate and always comes with a «probably». Temperature confirms the phase one to three days after it changes, so this looks backward, not at this moment.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("What it doesn't do").font(StrandFont.headline).foregroundStyle(theme.ink)
                ForEach([
                    "It is not a contraceptive method.",
                    "It doesn't predict your fertile days or your ovulation.",
                    "It doesn't diagnose pregnancy or any health condition.",
                    "It doesn't tell you which day your next period starts.",
                ], id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark").font(StrandFont.glyph(.chevron, weight: .semibold))
                            .foregroundStyle(theme.inkTertiary).padding(.top, 3)
                        Text(LocalizedStringKey(line)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - State card

private struct CyclePhaseStateBody: View {
    @Environment(\.instrumentoTheme) private var theme
    let days: [DailyMetric]
    let onDeactivate: () -> Void
    @State private var showInfo = false
    @State private var confirmOff = false

    /// Distinct usable nights (a skin-temp reading present) — the band signal the engine needs.
    private var usableCount: Int { days.compactMap(\.skinTempDevC).count }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            content
            Divider().overlay(theme.hairline)
            HStack(spacing: 16) {
                Button { showInfo = true } label: {
                    Label("What is this?", systemImage: "info.circle")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: 0)
                Button { confirmOff = true } label: {
                    Text("Turn off experiment").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showInfo) {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    Text("Cycle phase").font(StrandFont.serif(28)).foregroundStyle(theme.ink)
                    CyclePhaseWhatItIs(theme: theme)
                }
                .padding(NoopMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.paper.ignoresSafeArea())
            .instrumentoTheme(theme)
        }
        .instrumentoConfirm(
            isPresented: $confirmOff,
            title: String(localized: "Turn off experiment"),
            context: String(localized: "CYCLE PHASE · EXPERIMENT"),
            message: String(localized: "I'll stop estimating your phase. Your temperature data and everything else stay the same."),
            actions: [
                .init(String(localized: "Keep estimating"), role: .primary),
                .init(String(localized: "Turn off"), role: .destructive, handler: onDeactivate)
            ]
        )
    }

    @ViewBuilder private var content: some View {
        // No band signal at all → the reading needs the band (Apple-Health-only / never paired).
        if usableCount == 0 {
            card(overline: "NO BAND SIGNAL", title: "This reading needs your band.",
                 body: "The phase is estimated from the temperature your band measures while you sleep. When you sync nights with the band again, I'll pick the reading back up.")
        } else if let state = CyclePhaseExperiment.state(from: days) {
            switch state {
            case let .learning(soFar, needed):
                learning(soFar: soFar, needed: needed)
            case .noClearPattern:
                card(overline: "NO CLEAR PATTERN", title: "I don't see a clear pattern in your data.",
                     body: "Your night-time temperature doesn't show a rhythm I can read with confidence. This is common and doesn't mean anything is wrong with you or your band. I'll keep watching in case it appears.")
            case let .estimated(phase, confidence, _):
                estimated(phase: phase, confidence: confidence)
            }
        } else {
            // Defensive: no days at all behaves like the learning entry point.
            learning(soFar: 0, needed: CyclePhaseEngine.minUsableNights)
        }
    }

    private func learning(soFar: Int, needed: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LEARNING").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("I'm learning your pattern.").font(StrandFont.serif(24)).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("I need several weeks of nights with your band on to read the rhythm of your temperature. Still watching.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CyclePhaseProgressBar(fraction: needed > 0 ? min(1, Double(soFar) / Double(needed)) : 0, theme: theme)
                .padding(.top, 4)
            Text("\(soFar) of ~\(needed) nights").font(StrandFont.subhead).foregroundStyle(theme.ink)
            Text("The more nights you sleep with the band, the sooner I see it.")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
    }

    private func estimated(phase: CyclePhaseEngine.Phase, confidence: CyclePhaseEngine.PhaseConfidence) -> some View {
        let phaseText: LocalizedStringKey = phase == .lutealLean
            ? "You're probably in the luteal phase."
            : "You're probably in the follicular phase."
        let confText: LocalizedStringKey = {
            switch confidence {
            case .low: return "Low confidence · it's a faint signal."
            case .moderate: return "Moderate confidence."
            case .solid: return "Solid confidence for an estimate."
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text("APPROXIMATE READING").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(phaseText).font(StrandFont.serif(24)).foregroundStyle(theme.verdict)   // color only in the datum
                .fixedSize(horizontal: false, vertical: true)
            Text(confText).font(StrandFont.subhead).foregroundStyle(theme.ink)
            Text("Temperature confirms the phase one to three days after the change, so this reflects your recent nights, not this instant.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Text("Based on your band's night-time temperature.")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
    }

    private func card(overline: LocalizedStringKey, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(title).font(StrandFont.serif(24)).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(body).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A calm, dateless progress bar for the learning state — a fill fraction, no percentage read-out.
private struct CyclePhaseProgressBar: View {
    let fraction: Double
    let theme: InstrumentoTheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                Capsule().fill(theme.inkSecondary)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(Text("\(Int((fraction * Double(CyclePhaseEngine.minUsableNights)).rounded())) of ~\(CyclePhaseEngine.minUsableNights) nights learned"))
    }
}
