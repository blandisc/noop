import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics
import Inject   // recarga en caliente (dev-only, inerte en Release)

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
    /// EST-6 (FER-831): the close affordance follows the presentation. The Builder PUSHES this (chevron
    /// back, default); the live session presents it as a `.sheet`, so it closes with ✕. One correct
    /// affordance per context — and NO `NavigationStack` inside the session (FER-171 forbids nesting one).
    var closeAsDismiss: Bool = false

    @State private var mode: RestMode
    @State private var seconds: Int
    /// Which HR method drives the target: a margin over the user's resting HR (FER-759) or the
    /// Karvonen reserve. Both resolve to a bpm target through the same cited engine.
    @State private var hrRef: HRRestReference
    /// Margin in bpm over resting HR for the `.restingMargin` method (target = resting + margin, FER-759).
    @State private var margin: Int
    /// Fraction of HR reserve for the Karvonen threshold (0.35 exigente … 0.50 suave).
    @State private var reserve: Double
    @State private var applyToAll: Bool
    @State private var saveToRoutine: Bool

    init(theme: InstrumentoTheme, exerciseName: String, setNumber: Int?, current: RestConfig,
         persistsToRoutine: Bool, restingHR: Double?, maxHR: Double?, defaultApplyToAll: Bool,
         closeAsDismiss: Bool = false,
         onCancel: @escaping () -> Void, onApply: @escaping (RestConfig, Bool, Bool) -> Void) {
        self.theme = theme; self.exerciseName = exerciseName; self.setNumber = setNumber
        self.persistsToRoutine = persistsToRoutine; self.restingHR = restingHR; self.maxHR = maxHR
        self.closeAsDismiss = closeAsDismiss
        self.onCancel = onCancel; self.onApply = onApply
        _mode = State(initialValue: current.mode)
        _seconds = State(initialValue: max(15, current.seconds))
        // Method: honor a saved Karvonen config; everything else (incl. the FER-348 default) starts on the
        // simpler «margin over rest» method.
        _hrRef = State(initialValue: current.hrReference == .karvonenReserve ? .karvonenReserve : .restingMargin)
        // Seed the margin from a restingMargin config, else the +20 default (parity with FER-348) so an
        // existing routine keeps its target until the user drags it down.
        _margin = State(initialValue: current.hrReference == .restingMargin && current.hrValue > 0
                        ? min(30, max(5, Int(current.hrValue))) : 20)
        // Seed the reserve from a karvonenReserve config, else the «Normal» 41 % anchor.
        _reserve = State(initialValue: current.hrReference == .karvonenReserve && current.hrValue > 0
                         ? min(0.6, max(0.3, current.hrValue)) : 0.41)
        _applyToAll = State(initialValue: defaultApplyToAll)
        _saveToRoutine = State(initialValue: persistsToRoutine)
    }

    /// The Karvonen-reserve threshold in bpm, from the SAME cited single source the rest engine uses at
    /// runtime (`RestTarget.resolve`, Karvonen 1957) — never a forked copy of the formula (FER-716).
    private var thresholdBpm: Int? {
        RestTarget.resolve(reference: .karvonenReserve, value: reserve,
                           peakHR: nil, restingHR: restingHR, maxHR: maxHR)
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                InstrumentoFlowTitle(
                    overline: Text(setNumber.map { String(localized: "\(exerciseName) · set \($0)") } ?? exerciseName),
                    Text("Rest when you finish"))
                // Canvas pass 2026-07-15: FC carries its heart glyph (handoff «♥ FC»).
                SegmentedPillControl([RestMode.fixed, .heartRate], selection: $mode, theme: theme,
                                     inkThumb: true,
                                     icon: { $0 == .heartRate ? "heart.fill" : nil }) {
                    $0 == .fixed ? String(localized: "By time") : String(localized: "By heart rate")
                }
                if mode == .heartRate {
                    hrSection
                    capNote   // the 5-min cap only exists on an HR rest — by time there's nothing to cap
                }
                else { timeSection }
                // Scope only makes sense when the editor was opened FOR a set (the rest card). From the
                // exercise chip there's no «this set» to point at — the edit is exercise-wide by definition.
                if setNumber != nil { scopeSection }
                if persistsToRoutine {
                    Toggle(isOn: $saveToRoutine) {
                        Text("Save to the routine (next sessions)").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                    .toggleStyle(.instrumento)
                }
                cta
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 12).padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        // FER-988: el gesto de volver, vetado a favor de `onCancel` — la salida de esta pantalla
        // aplica/descarta según su modo, y un pop crudo se la saltaría. Inerte como hoja (`.close`).
        .keepsSwipeBack { onCancel(); return false }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    private var header: some View {
        HStack {
            // EST-6 (FER-814/831): a single close affordance that matches the presentation — the back
            // chevron when pushed (Builder), the ✕ when presented as a sheet (the live session). Never two.
            BackButton(role: closeAsDismiss ? .close : .back, theme: theme, action: onCancel)
                .padding(.leading, -2)
            Spacer()
        }
    }

    // MARK: HR mode

    /// The «margin over rest» target in bpm (target = round(restingHR) + margin), nil without a baseline.
    private var marginTargetBpm: Int? { restingHR.map { Int($0.rounded()) + margin } }

    private var hrSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rest ends when your pulse drops to the threshold. The phone buzzes when you're ready.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            // Owner call 2026-07-15: your OWN resting HR named up front — the anchor every margin
            // below is computed against.
            if let resting = restingHR {
                Text(String(localized: "your rest") + ": " + "\(Int(resting.rounded())) bpm")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            // The method selector rides the data hue (handoff: HR selector in the HRV blue-teal).
            SegmentedPillControl([HRRestReference.restingMargin, .karvonenReserve], selection: $hrRef,
                                 theme: theme, inkThumb: true, thumbTint: theme.dataHrv) {
                $0 == .restingMargin ? String(localized: "Over your rest") : String(localized: "Karvonen")
            }
            if hrRef == .restingMargin { marginBody } else { reserveBody }
        }
    }

    /// «Over your rest» (FER-759): a bpm margin above the user's resting HR — the way to pull the target
    /// down toward rest. The bpm target is the dominant datum; the slider spans a practical +5…+30.
    private var marginBody: some View {
        // Handoff (verificado 2026-07-16): overline «DESCANSA HASTA», el bpm resultante como numeral
        // dominante, la ARITMÉTICA dicha completa («reposo 58 + margen 20 bpm») y el slider con sus
        // puntas «+5 exigente / +30 suave» — los presets salieron (el handoff no los trae).
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .center, spacing: 4) {
                Text("Rest down to").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marginTargetBpm.map { "\($0)" } ?? "+\(margin)")
                        .groteskSheetNumeral().monospacedDigit().foregroundStyle(theme.dataRecovery)
                    Text(verbatim: "bpm").font(InstrumentoType.grotesk(14, weight: .bold)).foregroundStyle(theme.inkSecondary)
                }
                if let resting = restingHR {
                    Text("rest \(Int(resting.rounded())) + margin \(margin) bpm")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                } else {
                    Text("your rest + \(margin) bpm margin")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            Slider(value: Binding(get: { Double(margin) }, set: { margin = Int($0.rounded()) }),
                   in: 5...30, step: 1).tint(theme.dataRecovery)
            HStack {
                Text("+5 hard").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Text("+30 easy").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    /// «Reserve» (Karvonen 1957): a % of heart-rate reserve. Needs the HR-max profile to show bpm.
    private var reserveBody: some View {
        // Misma anatomía del handoff que el margen: el bpm en el que ACABAS como numeral, la
        // aritmética dicha, y las puntas del slider con su valencia.
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .center, spacing: 4) {
                Text("Rest down to").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(thresholdBpm.map { "\($0)" } ?? "\(Int(reserve * 100))")
                        .groteskSheetNumeral().monospacedDigit().foregroundStyle(theme.dataRecovery)
                    Text(verbatim: thresholdBpm != nil ? "bpm" : "%").font(InstrumentoType.grotesk(14, weight: .bold)).foregroundStyle(theme.inkSecondary)
                }
                (Text(verbatim: "\(Int((reserve * 100).rounded()))% ") + Text("of your heart-rate reserve"))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            Slider(value: $reserve, in: 0.30...0.55, step: 0.01).tint(theme.dataRecovery)
            HStack {
                Text("30% hard").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Text("55% easy").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    // MARK: Time mode

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                stepper("minus") { seconds = max(0, seconds - 15) }
                Text(Self.clock(seconds)).groteskSheetNumeral().monospacedDigit().foregroundStyle(theme.ink)
                stepper("plus") { seconds = min(600, seconds + 15) }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 8) {
                // r9 (owner): «Sin descanso» — 0 s registra y sigue de largo, sin fase de descanso.
                secondsPreset(String(localized: "No rest"), 0)
                secondsPreset("1:00", 60); secondsPreset("2:00", 120); secondsPreset("3:00", 180)
            }
            .frame(maxWidth: .infinity, alignment: .center)   // presets share the stepper's axis
        }
    }

    private func stepper(_ system: String, _ action: @escaping () -> Void) -> some View {
        StepperButton(system: system, size: 44, shape: .roundedControl,
                      glyph: StrandFont.glyph(.lead), theme: theme, action: action)
    }
    private func secondsPreset(_ label: String, _ s: Int) -> some View {
        PresetPill(label, selected: seconds == s, theme: theme) { seconds = s }
    }

    // MARK: Scope + note + CTA

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scope").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            SegmentedPillControl([false, true], selection: $applyToAll, theme: theme, inkThumb: true) {
                $0 ? String(localized: "All sets") : String(localized: "This set")
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private var cta: some View {
        StrandCTAButton("Apply") {
            let config: RestConfig
            if mode == .heartRate {
                config = hrRef == .karvonenReserve
                    ? RestConfig(mode: .heartRate, seconds: seconds, hrReference: .karvonenReserve, hrValue: reserve)
                    : RestConfig(mode: .heartRate, seconds: seconds, hrReference: .restingMargin, hrValue: Double(margin))
            } else {
                config = RestConfig(mode: .fixed, seconds: seconds, hrReference: .restingMargin, hrValue: 0)
            }
            onApply(config, applyToAll, saveToRoutine && persistsToRoutine)
        }
        .padding(.top, 4)
    }

    static func clock(_ seconds: Int) -> String { SessionClock.format(seconds) }
}
