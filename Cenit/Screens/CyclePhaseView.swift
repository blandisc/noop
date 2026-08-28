import SwiftUI
import StrandDesign
import StrandAnalytics
import CenitStore

// CyclePhaseView.swift — the opt-in «Fase del ciclo» experiment surface (FER-672). Lives in Ajustes →
// Experiments, OFF by default. A tap opens the consent screen (declares what it is and is NOT); only an
// explicit acknowledgement activates it. Once active, the same sheet shows the current-phase STATE card.
//
// All the math is in `CyclePhaseEngine` (pure, StrandAnalytics). This file only maps the daily metrics
// NOOP already stores into the engine's input and renders the localized, hedged copy — never a date,
// never fertility/ovulation/contraception/diagnosis (the hard claim frame lives in the copy below and
// is guarded by CyclePhaseCopyGuardTests).
//
// FER-184: two changes on top of FER-672's math (untouched — the index stays a user-relative z-score).
// (1) Input: the sheet used to read through `SourceLens.clearBandColumns`, which nils `skinTempDevC` —
// a leftover from when this screen needed a strap that Cénit never ships with anymore. It now reads the
// real Apple Watch wrist-temperature deviation straight off `repo.days`. (2) Skin: re-themed from the
// light «Instrumento diurno» to Liquid Glass, matching the FER-174 family (Data Sources, Support,
// AFib History) — a skin pass, the consent gate and the honest hedges below are unchanged in substance,
// only reworded off a strap that never existed for any Cénit user onto the Apple Watch that does.

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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(CyclePhaseExperiment.enabledKey) private var enabled = false
    @AppStorage(CyclePhaseExperiment.consentVersionKey) private var consentVersion = 0

    var body: some View {
        ScrollView {
            Group {
                if enabled {
                    // FER-184: real Apple wrist temperature, straight off repo.days — no strap-domain
                    // clearing to undo (Cénit is Apple-only; there's no cross-source mix left to guard).
                    CyclePhaseStateBody(days: repo.days, onDeactivate: {
                        enabled = false
                        // Apagar debe surtir efecto YA: el veredicto en memoria aún lleva el margen lútea
                        // hasta el próximo sync. Recalcula para retirarlo en el acto (Grok, FER-181-B).
                        Task { await repo.refresh() }
                    })
                } else {
                    CyclePhaseConsentBody(onActivate: {
                        consentVersion = CyclePhaseExperiment.consentVersion
                        enabled = true
                        // Encender aplica el margen lútea al número: recalcula ya, no en el próximo sync.
                        Task { await repo.refresh() }
                    }, onDecline: { dismiss() })
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
    }
}

// MARK: - Consent

private struct CyclePhaseConsentBody: View {
    let onActivate: () -> Void
    let onDecline: () -> Void
    @State private var acked = false

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s800) {
            header
            CyclePhaseWhatItIs()
            Text(String(localized: "Everything is computed on your iPhone and stays here. You can turn this experiment off whenever you like; nothing is lost. This is not medical advice."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)

            acknowledgment

            VStack(spacing: LiquidSpace.s300) {
                LiquidGlassButton(String(localized: "Turn on experiment"), variant: .primary, expands: true) {
                    onActivate()
                }
                .disabled(!acked)
                .opacity(acked ? 1 : 0.6)

                Button(action: onDecline) {
                    Text(String(localized: "Not now"))
                        .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta500)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidOverline(String(localized: "Experiment"))
            Text(String(localized: "Cycle phase"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "This is a self-knowledge tool: it looks for a pattern in your own body's temperature while you sleep. Before turning it on, read calmly what it does and what it doesn't."))
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var acknowledgment: some View {
        Toggle(isOn: $acked) {
            Text(String(localized: "I understand this is a rough estimate to know myself better, not a contraceptive method or a medical tool."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(LiquidColor.verdePrimario)
        .liquidTarjetaSeccion()
    }
}

/// The «what it does / what it doesn't» block — the single source of truth for the limits, reused by the
/// consent screen and the ⓘ explainer.
private struct CyclePhaseWhatItIs: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Text(String(localized: "What it does")).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                Text(String(localized: "With several weeks of nights, it learns the rhythm of your temperature and estimates which phase of your cycle you're probably in: follicular or luteal."))
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "The reading is approximate and always comes with a «probably». Temperature confirms the phase one to three days after it changes, so this looks backward, not at this moment."))
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "While it's on, it also gives your recovery number a small allowance on likely-luteal days, so the normal luteal rise in your pulse and temperature isn't read as «less recovered». With it off, your recovery ignores your cycle entirely."))
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Text(String(localized: "What it doesn't do")).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                ForEach([
                    String(localized: "It is not a contraceptive method."),
                    String(localized: "It doesn't predict your fertile days or your ovulation."),
                    String(localized: "It doesn't diagnose pregnancy or any health condition."),
                    String(localized: "It doesn't tell you which day your next period starts."),
                ], id: \.self) { line in
                    HStack(alignment: .top, spacing: LiquidSpace.s200) {
                        Image(systemName: "xmark")
                            .font(LiquidType.iconSF(size: 12))
                            .foregroundStyle(LiquidColor.tinta500).padding(.top, 3)
                        Text(line).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
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
    let days: [DailyMetric]
    let onDeactivate: () -> Void
    @State private var showInfo = false
    @State private var confirmOff = false

    /// Distinct usable nights (a skin-temp reading present) — the Apple Watch wrist-temperature signal
    /// the engine needs.
    private var usableCount: Int { days.compactMap(\.skinTempDevC).count }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s800) {
            content
            LiquidCapilar(eje: .horizontal)
            HStack(spacing: LiquidSpace.s400) {
                Button { showInfo = true } label: {
                    Label(String(localized: "What is this?"), systemImage: "info.circle")
                        .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta500)
                }
                Spacer(minLength: 0)
                Button { confirmOff = true } label: {
                    Text(String(localized: "Turn off experiment")).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta500)
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showInfo) {
            ScrollView {
                VStack(alignment: .leading, spacing: LiquidSpace.s800) {
                    VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                        LiquidOverline(String(localized: "Experiment"))
                        Text(String(localized: "Cycle phase"))
                            .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                            .foregroundStyle(LiquidColor.tinta900)
                    }
                    CyclePhaseWhatItIs()
                }
                .padding(.horizontal, LiquidSpace.s550)
                .padding(.top, LiquidSpace.s550)
                .padding(.bottom, LiquidSpace.s800)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background { LiquidSheetFondo().ignoresSafeArea() }
        }
        .confirmationDialog(
            String(localized: "Turn off experiment"),
            isPresented: $confirmOff,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Turn off"), role: .destructive) { onDeactivate() }
            Button(String(localized: "Keep estimating"), role: .cancel) { }
        } message: {
            Text(String(localized: "I'll stop estimating your phase. Your temperature data and everything else stay the same."))
        }
    }

    @ViewBuilder private var content: some View {
        // No wrist-temperature signal at all → the reading needs the Apple Watch (Apple-Health-only,
        // an older Watch, or one that isn't worn to bed).
        if usableCount == 0 {
            card(overline: String(localized: "NO SIGNAL YET"),
                 title: String(localized: "This reading needs your Apple Watch."),
                 body: String(localized: "The phase is estimated from the wrist temperature your Apple Watch measures while you sleep. It takes a Series 8, Ultra or newer, worn to bed every night, and about 5 nights before Apple starts giving me that temperature at all. From there it's still several weeks of nights before I can read your phase."))
        } else if let state = CyclePhaseExperiment.state(from: days) {
            switch state {
            case let .learning(soFar, needed):
                learning(soFar: soFar, needed: needed)
            case .noClearPattern:
                card(overline: String(localized: "NO CLEAR PATTERN"),
                     title: String(localized: "I don't see a clear pattern in your data."),
                     body: String(localized: "Your night-time temperature doesn't show a rhythm I can read with confidence. This is common and doesn't mean anything is wrong with you or your Apple Watch. I'll keep watching in case it appears."))
            case let .estimated(phase, confidence, _):
                estimated(phase: phase, confidence: confidence)
            }
        } else {
            // Defensive: no days at all behaves like the learning entry point.
            learning(soFar: 0, needed: CyclePhaseEngine.minUsableNights)
        }
    }

    private func learning(soFar: Int, needed: Int) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            Text(String(localized: "Learning")).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text(String(localized: "I'm learning your pattern."))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "I need several weeks of nights with your Apple Watch worn to bed to read the rhythm of your temperature. Still watching."))
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
            CyclePhaseProgressBar(soFar: soFar, needed: needed)
                .padding(.top, LiquidSpace.s100)
            Text(String(localized: "\(soFar) of ~\(needed) nights"))
                .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Apple needs a Series 8, Ultra or newer, worn to bed, and about 5 nights before it starts giving me a reading; from there, the more nights you sleep with it on, the sooner I see your rhythm."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func estimated(phase: CyclePhaseEngine.Phase, confidence: CyclePhaseEngine.PhaseConfidence) -> some View {
        let phaseText = phase == .lutealLean
            ? String(localized: "You're probably in the luteal phase.")
            : String(localized: "You're probably in the follicular phase.")
        let confText: String = {
            switch confidence {
            case .low: return String(localized: "Low confidence · it's a faint signal.")
            case .moderate: return String(localized: "Moderate confidence.")
            case .solid: return String(localized: "Solid confidence for an estimate.")
            }
        }()
        return VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(String(localized: "Approximate reading")).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text(phaseText)
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
            Text(confText).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Temperature confirms the phase one to three days after the change, so this reflects your recent nights, not this instant."))
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, LiquidSpace.s100)
            Text(String(localized: "Based on your Apple Watch's night-time temperature."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
        }
    }

    private func card(overline: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            Text(overline).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text(title)
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
            Text(body).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A calm, dateless progress bar for the learning state — a fill fraction, no percentage read-out.
private struct CyclePhaseProgressBar: View {
    let soFar: Int
    let needed: Int

    private var fraction: Double { needed > 0 ? Double(soFar) / Double(needed) : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LiquidColor.tinta10)
                Capsule().fill(LiquidColor.verdePrimario)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        // `soFar`/`needed` directly, not re-derived from `fraction` — the day `needed` changes from
        // `minUsableNights`, a re-derived label would silently disagree with what the caller passed.
        .accessibilityLabel(Text("\(soFar) of ~\(needed) nights learned"))
    }
}
