import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - Rest editor (1e, FER-716)
//
// The full-screen rest editor pushed from the session (the rest card's «Change rest» / an exercise's rest
// chip). Handoff «Flujo Entrenar v3 · 1e»: the threshold is the one dominant datum (color only on it); a
// bold ink-thumb segmented picks time vs HR; the scope (this set / all sets, FER-715) and a
// «save to routine» toggle decide where it lands. On apply it hands back a `RestConfig` + the scope +
// whether to persist to the backing routine.

struct RestEditorScreen: View {
    let theme: InstrumentoTheme
    let exerciseName: String
    /// 1-based set number for the overline (nil = editing at the exercise level, no specific set).
    let setNumber: Int?
    /// Whether this session is backed by a saved routine (enables the «save to routine» toggle).
    let persistsToRoutine: Bool
    /// The user's resting HR + HR-max, to render the Karvonen threshold in bpm (nil → % only).
    let restingHR: Double?
    let maxHR: Double?
    let onCancel: () -> Void
    /// (config, applyToAllSets, saveToRoutine).
    let onApply: (RestConfig, Bool, Bool) -> Void

    @State private var mode: RestMode
    @State private var seconds: Int
    /// Fraction of HR reserve for the Karvonen threshold (0.35 exigente … 0.50 suave).
    @State private var reserve: Double
    @State private var applyToAll: Bool
    @State private var saveToRoutine: Bool

    init(theme: InstrumentoTheme, exerciseName: String, setNumber: Int?, current: RestConfig,
         persistsToRoutine: Bool, restingHR: Double?, maxHR: Double?, defaultApplyToAll: Bool,
         onCancel: @escaping () -> Void, onApply: @escaping (RestConfig, Bool, Bool) -> Void) {
        self.theme = theme; self.exerciseName = exerciseName; self.setNumber = setNumber
        self.persistsToRoutine = persistsToRoutine; self.restingHR = restingHR; self.maxHR = maxHR
        self.onCancel = onCancel; self.onApply = onApply
        _mode = State(initialValue: current.mode)
        _seconds = State(initialValue: max(15, current.seconds))
        // Seed the reserve from a karvonenReserve config, else the «Normal» 41 % anchor.
        _reserve = State(initialValue: current.hrReference == .karvonenReserve && current.hrValue > 0
                         ? min(0.6, max(0.3, current.hrValue)) : 0.41)
        _applyToAll = State(initialValue: defaultApplyToAll)
        _saveToRoutine = State(initialValue: persistsToRoutine)
    }

    private var thresholdBpm: Int? {
        guard let r = restingHR, let m = maxHR, m > r else { return nil }
        return Int((r + reserve * (m - r)).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                VStack(alignment: .leading, spacing: 6) {
                    Text(setNumber.map { "\(exerciseName) · set \($0)" } ?? exerciseName)
                        .groteskOverline().foregroundStyle(theme.inkTertiary)
                    Text("Rest when you finish")
                        .font(InstrumentoType.groteskScreenTitle)
                        .tracking(InstrumentoType.groteskScreenTitleTracking).foregroundStyle(theme.ink)
                }
                SegmentedPillControl([RestMode.fixed, .heartRate], selection: $mode, theme: theme, inkThumb: true) {
                    $0 == .fixed ? String(localized: "By time") : String(localized: "By heart rate")
                }
                if mode == .heartRate { hrSection } else { timeSection }
                capNote
                scopeSection
                if persistsToRoutine {
                    Toggle(isOn: $saveToRoutine) {
                        Text("Save to the routine (next sessions)").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                    .toggleStyle(.instrumento)
                }
                cta
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 12).padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.ink)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Back"))
            .padding(.leading, -12)
            Spacer()
            Button(action: onCancel) { Text("Cancel").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary) }
                .buttonStyle(.plain)
        }
    }

    // MARK: HR mode

    private var hrSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rest ends when your pulse drops to the threshold. The strap buzzes when you're ready.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thresholdBpm.map { "\($0)" } ?? "\(Int(reserve * 100))")
                    .groteskSheetNumeral().monospacedDigit().foregroundStyle(theme.dataRecovery)
                Text(thresholdBpm != nil ? "lpm · \(Int(reserve * 100))% of your reserve" : "% of your reserve")
                    .font(StrandFont.headline).foregroundStyle(theme.inkSecondary)
            }
            Slider(value: $reserve, in: 0.30...0.55, step: 0.01).tint(theme.dataRecovery)
            HStack(spacing: 8) {
                reservePreset("Easy · 50%", 0.50)
                reservePreset("Normal · 41%", 0.41)
                reservePreset("Hard · 35%", 0.35)
            }
        }
    }

    private func reservePreset(_ label: String, _ frac: Double) -> some View {
        let sel = abs(reserve - frac) < 0.005
        return Button { reserve = frac } label: {
            Text(label).font(StrandFont.caption).foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Capsule().fill(sel ? theme.ink : Color.clear))
                .overlay(Capsule().strokeBorder(sel ? Color.clear : theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Time mode

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                stepper("minus") { seconds = max(15, seconds - 15) }
                Text(Self.clock(seconds)).groteskSheetNumeral().monospacedDigit().foregroundStyle(theme.ink)
                stepper("plus") { seconds = min(600, seconds + 15) }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 8) {
                secondsPreset("1:00", 60); secondsPreset("2:00", 120); secondsPreset("3:00", 180)
            }
        }
    }

    private func stepper(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    private func secondsPreset(_ label: String, _ s: Int) -> some View {
        let sel = seconds == s
        return Button { seconds = s } label: {
            Text(label).font(StrandFont.caption).monospacedDigit().foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Capsule().fill(sel ? theme.ink : Color.clear))
                .overlay(Capsule().strokeBorder(sel ? Color.clear : theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Scope + note + CTA

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apply to").groteskOverline().foregroundStyle(theme.inkTertiary)
            SegmentedPillControl([false, true], selection: $applyToAll, theme: theme, inkThumb: true) {
                $0 ? String(localized: "All sets") : String(localized: "This set only")
            }
        }
    }

    private var capNote: some View {
        HStack(spacing: 8) {
            Circle().fill(theme.dataRecovery).frame(width: 7, height: 7)
            Text("Safety cap: if you don't drop within 5 min, the session continues anyway.")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private var cta: some View {
        Button {
            let config = mode == .heartRate
                ? RestConfig(mode: .heartRate, seconds: seconds, hrReference: .karvonenReserve, hrValue: reserve)
                : RestConfig(mode: .fixed, seconds: seconds, hrReference: .restingMargin, hrValue: 0)
            onApply(config, applyToAll, saveToRoutine && persistsToRoutine)
        } label: {
            Text("Apply").font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                .foregroundStyle(theme.paper).frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.ctaRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
