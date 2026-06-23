import SwiftUI
import StrandDesign
import StrandTraining

/// The shared rest-between-sets editor: the mode toggle (by-HR / fixed) plus the duration stepper or
/// the HR-target reference + value. Extracted from `RoutineExerciseEditor` (FER-495) so the routine
/// builder and the in-session rest editor (FER-540) drive *identical* controls — one source of truth.
///
/// It binds the four rest fields of a `RoutineExercise`; the caller owns the container (a builder form
/// section, or a session sheet). The `restingMargin` / `0` defaults reproduce FER-348 exactly.
struct RestEditor: View {
    @Binding var restMode: RestMode
    @Binding var restSeconds: Int
    @Binding var hrRestReference: HRRestReference
    @Binding var hrRestValue: Double
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Rest between sets").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Picker("Rest mode", selection: $restMode) {
                Text("By HR").tag(RestMode.heartRate)
                Text("Fixed").tag(RestMode.fixed)
            }
            .pickerStyle(.segmented)
            if restMode == .fixed {
                valueRow("Seconds", display: "\(restSeconds) s") {
                    Stepper("Seconds", value: $restSeconds, in: 15...300, step: 15)
                        .labelsHidden().tint(theme.inkSecondary)
                }
            } else {
                // FER-495: how the HR rest target is computed. «Automatic» (restingMargin) = FER-348.
                HStack(spacing: 14) {
                    Text("Reference").font(StrandFont.body).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        ForEach([HRRestReference.restingMargin, .peakDrop, .karvonenReserve, .fixedBpm], id: \.self) { ref in
                            Button { selectHRReference(ref) } label: { Text(Self.hrRefLabel(ref)) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(Self.hrRefLabel(hrRestReference)).font(StrandFont.body).foregroundStyle(theme.ink)
                            Image(systemName: "chevron.down").font(.system(size: 13)).foregroundStyle(theme.inkTertiary)
                        }
                    }
                }
                .frame(minHeight: 40)
                hrValueRow
            }
            Text(restFootnote).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The value stepper for the chosen HR reference (hidden for «Automatic», which has no value).
    @ViewBuilder
    private var hrValueRow: some View {
        switch hrRestReference {
        case .restingMargin:
            EmptyView()
        case .peakDrop:
            valueRow("Target drop", display: "\(Int((hrRestValue * 100).rounded())) %") {
                Stepper("Target drop", value: $hrRestValue, in: 0.1...0.6, step: 0.05)
                    .labelsHidden().tint(theme.inkSecondary)
            }
        case .karvonenReserve:
            valueRow("Drop to", display: "\(Int((hrRestValue * 100).rounded())) %") {
                Stepper("Drop to", value: $hrRestValue, in: 0.4...0.8, step: 0.05)
                    .labelsHidden().tint(theme.inkSecondary)
            }
        case .fixedBpm:
            valueRow("Ready below", display: "\(Int(hrRestValue.rounded())) bpm") {
                Stepper("Ready below", value: $hrRestValue, in: 80...160, step: 5)
                    .labelsHidden().tint(theme.inkSecondary)
            }
        }
    }

    private func valueRow<Control: View>(_ label: LocalizedStringKey, display: String,
                                         @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 14) {
            Text(label).font(StrandFont.body).foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Text(display).font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                control()
            }
        }
        .frame(minHeight: 40)
    }

    /// Set the reference and seed a sensible default value for it (fractions vs bpm differ wildly).
    private func selectHRReference(_ ref: HRRestReference) {
        hrRestReference = ref
        switch ref {
        case .restingMargin:   hrRestValue = 0
        case .peakDrop:        hrRestValue = 0.30
        case .karvonenReserve: hrRestValue = 0.60
        case .fixedBpm:        hrRestValue = 110
        }
    }

    private static func hrRefLabel(_ ref: HRRestReference) -> LocalizedStringKey {
        switch ref {
        case .restingMargin:   return "Automatic"
        case .peakDrop:        return "% of peak"
        case .karvonenReserve: return "% of reserve"
        case .fixedBpm:        return "Threshold (bpm)"
        }
    }

    private var restFootnote: LocalizedStringKey {
        if restMode == .fixed { return "A fixed countdown between sets." }
        switch hrRestReference {
        case .restingMargin:
            return "Ready when your pulse returns near your resting rate — your strap reads it."
        case .peakDrop:
            return "Ready when your pulse drops the chosen % from the set's peak. No max or resting HR needed."
        case .karvonenReserve:
            return "Ready at the chosen % of your heart-rate reserve (Karvonen). Uses your max and resting HR; falls back to the timer if either is missing."
        case .fixedBpm:
            return "Ready when your pulse drops below the chosen rate."
        }
    }
}

/// The in-session rest editor as a sheet (FER-540): the shared `RestEditor` over a working copy, a note
/// about where the change lands, and a Save button. Used from the rest chip in `LiveStrengthSheet`.
struct RestEditorSheet: View {
    let persistsToRoutine: Bool
    let onSave: (RestMode, Int, HRRestReference, Double) -> Void
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var mode: RestMode
    @State private var seconds: Int
    @State private var reference: HRRestReference
    @State private var value: Double

    init(mode: RestMode, seconds: Int, reference: HRRestReference, value: Double,
         persistsToRoutine: Bool, onSave: @escaping (RestMode, Int, HRRestReference, Double) -> Void) {
        _mode = State(initialValue: mode)
        _seconds = State(initialValue: seconds)
        _reference = State(initialValue: reference)
        _value = State(initialValue: value)
        self.persistsToRoutine = persistsToRoutine
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            RestEditor(restMode: $mode, restSeconds: $seconds,
                       hrRestReference: $reference, hrRestValue: $value)
            Text(persistsToRoutine ? "Saved to your routine." : "This session only.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 0)
            Button {
                onSave(mode, seconds, reference, value)
                dismiss()
            } label: {
                Text("Save").font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.top, 18)
        .padding(.bottom, NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper)
    }
}
