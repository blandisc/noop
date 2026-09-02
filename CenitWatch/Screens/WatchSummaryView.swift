import SwiftUI
import CenitDesign

/// State 6 — the minimal end-of-session summary. Duration is the hero (ember, as the session's output);
/// average heart rate and active energy are secondary; a line confirms it reached Health (or warns it
/// didn't). No series / volume / recovery — those live on the iPhone receipt. Dismissed with «Listo», or
/// on its own after ~30s when saved; a failed save waits for the tap. Scrollable by the crown for AX.
///
/// Liquid sobre OLED (DECISIONS 2026-09-03, FER-309/312).
struct WatchSummaryView: View {
    let summary: WatchSessionSummary
    @EnvironmentObject var manager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                Text("Session").liquidKicker().foregroundStyle(LiquidOLED.tintaTerciaria).accessibilityHidden(true)

                // token-exempt(sistema): geometría watchOS — duración 40 tabular; displayM es 40 pero no tabular
                Text(verbatim: durationText)
                    .font(.system(size: WatchMetrics.heroSummaryDuration, weight: .bold).monospacedDigit())
                    .foregroundStyle(LiquidOLED.ambar)
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
                    HStack(spacing: LiquidSpace.s100) {
                        Text("See receipt on iPhone")
                        Image(systemName: "chevron.right").font(LiquidType.pie).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: WatchMetrics.summarySecondaryHeight)
                }
                // token-exempt(sistema): control nativo watchOS
                .buttonStyle(.bordered)
                .tint(LiquidOLED.tintaSecundaria)

                Button { manager.dismissSummary() } label: {
                    Text("Done").frame(maxWidth: .infinity, minHeight: WatchMetrics.summaryPrimaryHeight)
                }
                .tint(LiquidOLED.tinta)
            }
            .padding(.horizontal, LiquidSpace.s300)
            .padding(.vertical, LiquidSpace.s200)
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: Text?) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(label).font(LiquidType.pie).foregroundStyle(LiquidOLED.tintaTerciaria)
            (value ?? Text(verbatim: "--"))
                .font(Font.system(.subheadline).monospacedDigit()) // bodyNumber → cuerpoLista tabular
                .foregroundStyle(value == nil ? LiquidOLED.tintaTerciaria : LiquidOLED.tinta) // inkDim → tintaTerciaria
        }
    }

    @ViewBuilder private var saveLine: some View {
        switch summary.saveState {
        case .saved:
            HStack(spacing: LiquidSpace.s100) {
                Image(systemName: "checkmark")
                Text("Saved to Health")
            }
            .font(LiquidType.filaConteo)
            .foregroundStyle(LiquidOLED.verde)
        case .failed:
            HStack(spacing: LiquidSpace.s100) {
                Image(systemName: "exclamationmark.triangle")
                Text("Couldn't save to Health")
            }
            .font(LiquidType.filaConteo)
            .foregroundStyle(LiquidOLED.negativo)
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
