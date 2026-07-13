import SwiftUI
import StrandDesign
import StrandAnalytics

// RitmoView.swift — «Ritmo», the experimental, NON-CLINICAL rhythm read (FER-666 F2). Presented as a
// light «Instrumento» sheet from the Experimental section of Ajustes. It shows last night's
// beat-to-beat regularity: a Poincaré cloud (the datum — the only saturated color), a neutral label
// in verdict serif, the confidence, and a one-line night summary; tapping the cloud reveals the six
// descriptive statistics. A first-time consent explainer gates the screen once; a disclaimer is
// pinned under every reading. No condition is ever named, no risk scored, no doctor recommended —
// the copy frame lives entirely in `RhythmCopy`, the data in the merged `NightRhythmProvider`.

struct RitmoView: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository

    /// One-time consent flag; persists across launches (criterion 4).
    @AppStorage("noop.rhythmConsentAccepted") private var consented = false

    @State private var read: NightRhythmRead? = nil
    @State private var expanded = false

    var body: some View {
        Group {
            if consented {
                readingSheet
            } else {
                ConsentView { consented = true }
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .task { if read == nil { read = await NightRhythmProvider.load(from: repo) } }
    }

    /// Whether the persistent disclaimer shows — only when there IS a reading (any sub-state,
    /// including "couldn't read"). The "needs a band" / "no sleep" states carry no reading.
    private var showsDisclaimer: Bool {
        if case .reading = read { return true }
        return false
    }

    private var readingSheet: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                    Text(RhythmCopy.screenOverline)
                        .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .padding(.top, CenitMetrics.screenPadding)

                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.bottom, CenitMetrics.screenPadding)
            }
            if showsDisclaimer { disclaimerFooter }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch read {
        case .none:
            LoadingStateView().frame(maxWidth: .infinity).padding(.top, 80)
        case .needsBand:
            MessageState(title: RhythmCopy.needsBandTitle, message: RhythmCopy.needsBandBody,
                         glyph: "waveform.path.ecg", theme: theme)
        case .noSleepLastNight:
            MessageState(title: RhythmCopy.noDataTitle, message: RhythmCopy.noDataBody,
                         glyph: "moon.zzz", theme: theme)
        case .reading(let nr):
            reading(nr)
        }
    }

    @ViewBuilder
    private func reading(_ nr: NightRhythmAssembler.NightRhythm) -> some View {
        if nr.summary.readableWindows == 0 {
            // Every window failed a gate — honest, no alarm.
            MessageState(title: RhythmCopy.unreadableTitle, message: RhythmCopy.unreadableWhy,
                         glyph: "dot.scope", theme: theme)
        } else if nr.summary.readableWindows < NightRhythmAssembler.NightRhythm.minWindowsForConfidentRead {
            CalibratingView(nr: nr, theme: theme)
        } else {
            RhythmReadingView(nr: nr, expanded: $expanded, theme: theme)
        }
    }

    private var disclaimerFooter: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            Text(RhythmCopy.disclaimer)
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.vertical, 12)
        }
        .background(theme.paper)
    }
}

// MARK: - Consent explainer (first time only)

private struct ConsentView: View {
    @Environment(\.instrumentoTheme) private var theme
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(RhythmCopy.consentOverline)
                .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, 22)

            Text(RhythmCopy.consentTitle)
                .font(InstrumentoType.groteskHeadline(27))
                .foregroundStyle(theme.ink)
                .padding(.bottom, 14)

            Text(RhythmCopy.consentBody)
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 9) {
                bullet(RhythmCopy.consentNoEcg)
                bullet(RhythmCopy.consentNoDx)
                bullet(RhythmCopy.consentNoDisease)
            }

            Spacer(minLength: 24)

            Button(action: onAccept) {
                Text(RhythmCopy.consentButton)
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(theme.ink, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, CenitMetrics.screenPadding + 8)
        .padding(.bottom, CenitMetrics.screenPadding)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Circle().fill(theme.inkTertiary).frame(width: 5, height: 5)
                .offset(y: -2)
            Text(text).font(StrandFont.body).foregroundStyle(theme.inkSecondary)
        }
    }
}

// MARK: - Full reading (cloud + label + tap → 6 stats)

private struct RhythmReadingView: View {
    let nr: NightRhythmAssembler.NightRhythm
    @Binding var expanded: Bool
    let theme: InstrumentoTheme

    var body: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 12) {
                PoincareCloud(points: nr.cloudPoints,
                              summary: "\(RhythmCopy.label(nr.summary.overall)) · \(nr.readableBeats) latidos")
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() } }

                if !expanded {
                    HStack(spacing: 4) {
                        Text(RhythmCopy.tapHint).font(StrandFont.footnote)
                        Image(systemName: "chevron.right").font(StrandFont.glyph(.chevron, weight: .semibold))
                    }
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(RhythmCopy.label(nr.summary.overall))
                    .font(InstrumentoType.groteskVerdict).foregroundStyle(theme.ink)
                Text(RhythmCopy.confidence(beats: nr.readableBeats, tier: nr.bestConfidence))
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(RhythmCopy.stats(nr.representativeWindow ?? placeholder).enumerated()), id: \.offset) { idx, s in
                        if idx > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                        statRow(s)
                    }
                }
            } else {
                Text(RhythmCopy.nightLine(nr.summary))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statRow(_ s: RhythmCopy.Stat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.label).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Text(s.gloss).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 12)
            Text(s.value).font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
        }
        .padding(.vertical, 10)
    }

    /// Never rendered when there's no representative window (the caller only reaches here with
    /// readable windows), but the API is non-optional — a benign all-nil fallback.
    private var placeholder: RhythmScreener.WindowResult {
        .init(label: .steady, sd1: nil, sd2: nil, sd1sd2: nil, normRmssd: nil,
              turningPointRate: nil, ectopicFraction: nil, nBeats: 0,
              confidence: .calibrating, agreedAcrossSources: false, poincare: [])
    }
}

// MARK: - Calibrando (thin night)

private struct CalibratingView: View {
    let nr: NightRhythmAssembler.NightRhythm
    let theme: InstrumentoTheme

    var body: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            PoincareCloud(points: nr.cloudPoints, faded: true,
                          summary: RhythmCopy.calibratingLabel)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(RhythmCopy.calibratingLabel)
                    .font(InstrumentoType.groteskVerdict).foregroundStyle(theme.inkSecondary)
                Text(RhythmCopy.confidence(beats: nr.readableBeats, tier: .calibrating))
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }

            Text(RhythmCopy.calibratingHedge)
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Message states (no reading: needs band / no sleep / unreadable)

private struct MessageState: View {
    let title: String
    let message: String
    let glyph: String
    let theme: InstrumentoTheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: glyph)
                .font(StrandFont.glyph(.empty, weight: .light))
                .foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(InstrumentoType.groteskHeadline(22)).foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 8)
    }
}
