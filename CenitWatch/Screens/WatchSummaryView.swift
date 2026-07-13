import SwiftUI
import StrandDesign

/// State 6 — the minimal end-of-session summary. Duration is the hero (ember, as the session's output);
/// average heart rate and active energy are secondary; a line confirms it reached Health (or warns it
/// didn't). No series / volume / recovery — those live on the iPhone receipt. Dismissed with «Listo», or
/// on its own after ~30s when saved; a failed save waits for the tap. Scrollable by the crown for AX.
struct WatchSummaryView: View {
    let summary: WatchSessionSummary
    @EnvironmentObject var manager: WatchWorkoutManager
    private let t = InstrumentoTheme.base

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                Text("Session").instrumentoOverline().foregroundStyle(t.inkTertiary).accessibilityHidden(true)

                Text(verbatim: durationText)
                    .instrumentoHero(40)
                    .foregroundStyle(t.dataStrain)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityLabel(Text("Duration, \(summary.durationMinutes) minutes"))

                HStack(alignment: .top) {
                    stat("Avg HR", summary.averageHeartRate.map { Text(verbatim: "\($0)") })
                    Spacer()
                    stat("Active", summary.activeEnergyKcal.map { Text("\($0) kcal") })
                }

                saveLine

                // FER-810 — handoff to the rich receipt on the phone (volume, PRs, diet). The wrist summary
                // stays minimal; this opens the saved workout's history detail on the iPhone.
                Button { manager.openReceiptFromWrist() } label: {
                    HStack(spacing: CenitMetrics.space1) {
                        Text("See receipt on iPhone")
                        Image(systemName: "chevron.right").font(StrandFont.footnote).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .tint(t.inkSecondary)

                Button { manager.dismissSummary() } label: {
                    Text("Done").frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(t.ink)
            }
            .padding(.horizontal, CenitMetrics.gap)
            .padding(.vertical, CenitMetrics.space2)
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: Text?) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            Text(label).font(StrandFont.footnote).foregroundStyle(t.inkTertiary)
            (value ?? Text(verbatim: "--"))
                .font(StrandFont.bodyNumber)
                .foregroundStyle(value == nil ? t.inkDim : t.ink)
        }
    }

    @ViewBuilder private var saveLine: some View {
        switch summary.saveState {
        case .saved:
            HStack(spacing: CenitMetrics.space1) {
                Image(systemName: "checkmark")
                Text("Saved to Health")
            }
            .font(StrandFont.caption)
            .foregroundStyle(t.verdict)
        case .failed:
            HStack(spacing: CenitMetrics.space1) {
                Image(systemName: "exclamationmark.triangle")
                Text("Couldn't save to Health")
            }
            .font(StrandFont.caption)
            .foregroundStyle(t.critical)
            .lineLimit(nil)
        }
    }

    /// «MM:SS», tabular via the hero font. Minutes run past 60 for long sessions (no hour rollover
    /// needed on the wrist).
    private var durationText: String {
        let total = Int(summary.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
