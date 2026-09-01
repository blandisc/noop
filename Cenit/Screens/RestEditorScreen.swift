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

// MARK: - Pure mapping (FER-89) — extracted so it's testable without mounting the View
//
// Antes de FER-89 la hoja solo conocía 2 de las 5 formas reales (`RestMode.fixed` + 2 de los 4
// `HRRestReference`); `.peakDrop`/`.fixedBpm` no tenían UI y, peor, un `RestConfig` YA GUARDADO en
// esas dos formas se degradaba en silencio a `.restingMargin` al reabrir el editor (pérdida de
// contenido real, no solo de alcance de UI).

enum RestEditorMapping {
    /// El `hrRef` con el que abre la hoja: exactamente el persistido, las CUATRO formas. Código
    /// viejo (`current.hrReference == .karvonenReserve ? .karvonenReserve : .restingMargin`)
    /// tronaría aquí para `.peakDrop`/`.fixedBpm` — devolvía `.restingMargin` y el método guardado se
    /// perdía al reabrir el editor.
    static func seedHRRef(_ current: RestConfig) -> HRRestReference { current.hrReference }

    /// La `RestConfig` que arma el CTA «Aplicar» — una rama por cada una de las 5 formas reales.
    /// Código viejo (el switch de 2 ramas de antes de FER-89) no compilaría con las 4 del enum, o
    /// perdería `.peakDrop`/`.fixedBpm` si alguien lo redujera de vuelta a un ternario.
    static func buildConfig(mode: RestMode, hrRef: HRRestReference, seconds: Int,
                            margin: Int, reserve: Double, peakDropFraction: Double,
                            fixedTargetBpm: Int) -> RestConfig {
        guard mode == .heartRate else {
            return RestConfig(mode: .fixed, seconds: seconds, hrReference: .restingMargin, hrValue: 0)
        }
        switch hrRef {
        case .restingMargin:
            return RestConfig(mode: .heartRate, seconds: seconds, hrReference: .restingMargin, hrValue: Double(margin))
        case .karvonenReserve:
            return RestConfig(mode: .heartRate, seconds: seconds, hrReference: .karvonenReserve, hrValue: reserve)
        case .peakDrop:
            return RestConfig(mode: .heartRate, seconds: seconds, hrReference: .peakDrop, hrValue: peakDropFraction)
        case .fixedBpm:
            return RestConfig(mode: .heartRate, seconds: seconds, hrReference: .fixedBpm, hrValue: Double(fixedTargetBpm))
        }
    }
}

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
    /// EST-6 (FER-831): originally chose the header's icon by presentation (chevron pushed, ✕ sheeted).
    /// FER-198 (Ola 2) unified the exit into `EntrenarHojaCabecera(.cancelar("Cancel"))` — one text
    /// control, same in both contexts — so this flag no longer drives the icon; kept only because
    /// callers outside this screen still set it (out of this reskin's file scope to prune).
    var closeAsDismiss: Bool = false

    @State private var mode: RestMode
    @State private var seconds: Int
    /// Cuál de las 4 formas de `HRRestReference` maneja el target — las 5 formas reales del motor son
    /// `RestMode.fixed` + estas 4 (FER-89: `.restingMargin`/`.karvonenReserve` ya vivían aquí;
    /// `.peakDrop`/`.fixedBpm` no tenían UI hasta esta fase). Todas resuelven a un bpm por el mismo
    /// motor citado (`RestTarget.resolve`).
    @State private var hrRef: HRRestReference
    /// Margin in bpm over resting HR for the `.restingMargin` method (target = resting + margin, FER-759).
    @State private var margin: Int
    /// Fraction of HR reserve for the Karvonen threshold (0.35 exigente … 0.50 suave).
    @State private var reserve: Double
    /// Fracción de caída desde el pico de esta serie para `.peakDrop` (FER-89: el motor ya la calcula
    /// — `RestTarget.resolve(reference: .peakDrop, ...)` — pero nunca tuvo UI). Sin `peakHR` a la mano
    /// en este editor (se conoce EN VIVO, durante la serie, no al configurar el descanso), el preview
    /// siempre es solo-porcentaje — igual que `.karvonenReserve` sin perfil de FC.
    @State private var peakDropFraction: Double
    /// Objetivo fijo en lpm para `.fixedBpm` (FER-89): un número que el usuario pone directo, sin
    /// depender de su FC en reposo — ya persistido y formateado por `restChipLabel`, pero invisible en
    /// esta hoja hasta esta fase.
    @State private var fixedTargetBpm: Int
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
        // FER-89: honra el método persistido tal cual — las 4 formas, no solo Karvonen. Antes de esta
        // fase, un config .peakDrop/.fixedBpm se degradaba en silencio a .restingMargin al reabrir.
        _hrRef = State(initialValue: RestEditorMapping.seedHRRef(current))
        // Seed the margin from a restingMargin config, else the +20 default (parity with FER-348) so an
        // existing routine keeps its target until the user drags it down.
        _margin = State(initialValue: current.hrReference == .restingMargin && current.hrValue > 0
                        ? min(30, max(5, Int(current.hrValue))) : 20)
        // Seed the reserve from a karvonenReserve config, else the «Normal» 41 % anchor.
        _reserve = State(initialValue: current.hrReference == .karvonenReserve && current.hrValue > 0
                         ? min(0.6, max(0.3, current.hrValue)) : 0.41)
        _peakDropFraction = State(initialValue: current.hrReference == .peakDrop && current.hrValue > 0
                                  ? min(0.50, max(0.10, current.hrValue)) : 0.25)
        _fixedTargetBpm = State(initialValue: current.hrReference == .fixedBpm && current.hrValue > 0
                                ? min(170, max(80, Int(current.hrValue.rounded()))) : 120)
        _applyToAll = State(initialValue: defaultApplyToAll)
        _saveToRoutine = State(initialValue: persistsToRoutine)
    }

    /// The Karvonen-reserve threshold in bpm, from the SAME cited single source the rest engine uses at
    /// runtime (`RestTarget.resolve`, Karvonen 1957) — never a forked copy of the formula (FER-716).
    private var thresholdBpm: Int? {
        RestTarget.resolve(reference: .karvonenReserve, value: reserve,
                           peakHR: nil, restingHR: restingHR, maxHR: maxHR)
    }

    // MARK: Front control (2 of 5 forms) — FER-89

    /// Lo que el control de 2 opciones AL FRENTE puede representar. `.other` no es un item del
    /// control (no aparece en `items`) — existe solo para que `selection` pueda decir «ninguna de las
    /// 2 de aquí» cuando una de las 3 formas de «más opciones» está activa, sin inventar un tercer
    /// segmento visible.
    private enum FrontChoice: Hashable { case fixed, restingMargin, other }

    private var frontChoice: Binding<FrontChoice> {
        Binding(
            get: {
                if mode == .fixed { return .fixed }
                return hrRef == .restingMargin ? .restingMargin : .other
            },
            set: { choice in
                switch choice {
                case .fixed:         mode = .fixed
                case .restingMargin: mode = .heartRate; hrRef = .restingMargin
                case .other:         break   // no es un segmento tocable — nunca se asigna desde el control
                }
            }
        )
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.seccionAire) {
                // FER-198 (Ola 2): la cabecera de la familia El Eje absorbe el `header` a mano
                // (BackButton) Y el `InstrumentoFlowTitle` de abajo — mismas DOS cadenas ya
                // localizadas (título/overline), sin copy nueva. `Salida.cancelar` unifica el
                // cierre en un único control de texto (antes chevron/aspa según `closeAsDismiss`
                // — ese flag queda inerte en esta hoja, ver nota en `closeAsDismiss`).
                EntrenarHojaCabecera(
                    titulo: String(localized: "Rest when you finish"),
                    subtitulo: setNumber.map { String(localized: "\(exerciseName) · set \($0)") } ?? exerciseName,
                    tono: .verde, salida: .cancelar(String(localized: "Cancel")), onSalir: onCancel)
                // FER-89: las 2 formas AL FRENTE — por tiempo fijo y sobre tu reposo (el default de
                // FC). Las otras 3 (Karvonen, caída desde el pico, lpm fijo) viven en «más opciones»
                // dentro de `hrSection`; si una de ellas está activa, ningún segmento de este control
                // se resalta — es honesto: ninguna de las 2 de aquí es la que de verdad está activa.
                SegmentedPillControl([FrontChoice.fixed, .restingMargin], selection: frontChoice, theme: theme,
                                     inkThumb: true,
                                     icon: { $0 == .restingMargin ? "heart.fill" : nil }) {
                    $0 == .fixed ? String(localized: "By time") : String(localized: "Over your rest")
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
        .entrenarHojaFondo(tono: .verde)
        .instrumentoTheme(theme)
        // FER-988: el gesto de volver, vetado a favor de `onCancel` — la salida de esta pantalla
        // aplica/descarta según su modo, y un pop crudo se la saltaría. Inerte como hoja (`.close`).
        .keepsSwipeBack { onCancel(); return false }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    // MARK: HR mode

    /// The «margin over rest» target in bpm (target = round(restingHR) + margin), nil without a baseline.
    private var marginTargetBpm: Int? { restingHR.map { Int($0.rounded()) + margin } }

    private var hrSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
            Text("Rest ends when your pulse drops to the threshold. The phone buzzes when you're ready.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            // Owner call 2026-07-15: your OWN resting HR named up front — the anchor every margin
            // below is computed against.
            if let resting = restingHR {
                Text(String(localized: "your rest") + ": " + "\(Int(resting.rounded())) bpm")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            // FER-89: el cuerpo refleja SIEMPRE el `hrRef` activo — así un config ya guardado en una
            // de las 3 formas de «más opciones» se ve completo aunque el disclosure siga plegado.
            hrRefBody
            moreOptionsSection
        }
    }

    /// El cuerpo de la forma activa — una de las 4. Reemplaza el ternario de 2 ramas de antes de
    /// FER-89 (`hrRef == .restingMargin ? marginBody : reserveBody`), que no tenía dónde poner
    /// `.peakDrop`/`.fixedBpm`.
    @ViewBuilder private var hrRefBody: some View {
        switch hrRef {
        case .restingMargin:   marginBody
        case .karvonenReserve: reserveBody
        case .peakDrop:        peakDropBody
        case .fixedBpm:        fixedBpmBody
        }
    }

    /// «Más opciones» (FER-89, primera vez que esta hoja pliega algo): las 3 formas que no van al
    /// frente. Candidato de reuso evaluado — `Metodo<Content>` (`TendenciasDetalle.swift:322`), el
    /// `DisclosureGroup` ya estandarizado (radio 12, padding 14, plegado por defecto) — su label es un
    /// `Text` genérico, no prosa forzada, así que encaja sin fork: se reusa tal cual en vez de construir
    /// `EntrenarDisclosure` para lo mismo.
    private var moreOptionsSection: some View {
        Metodo(title: String(localized: "More options"), theme: theme) {
            SegmentedPillControl([HRRestReference.karvonenReserve, .peakDrop, .fixedBpm], selection: $hrRef,
                                 theme: theme, inkThumb: true, thumbTint: theme.dataHrv) {
                switch $0 {
                case .karvonenReserve: return String(localized: "Karvonen")
                case .peakDrop:        return String(localized: "Peak drop")
                case .fixedBpm:        return String(localized: "Fixed bpm")
                case .restingMargin:   return ""   // no es un item de este control
                }
            }
        }
    }

    /// «Over your rest» (FER-759): a bpm margin above the user's resting HR — the way to pull the target
    /// down toward rest. The bpm target is the dominant datum; the slider spans a practical +5…+30.
    private var marginBody: some View {
        // Handoff (verificado 2026-07-16): overline «DESCANSA HASTA», el bpm resultante como numeral
        // dominante, la ARITMÉTICA dicha completa («reposo 58 + margen 20 bpm») y el slider con sus
        // puntas «+5 exigente / +30 suave» — los presets salieron (el handoff no los trae).
        VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
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
        VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
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

    /// «Caída desde el pico» (FER-89, motor citado sin exponer hasta esta fase): un % de caída desde
    /// el pico de FC de esta serie. `RestTarget.resolve(reference: .peakDrop, ...)` necesita `peakHR`
    /// — el pico de la serie que se acaba de hacer — y este editor lo abre ANTES de la serie (config,
    /// no en vivo), así que `peakHR` siempre es `nil` aquí: el preview es siempre solo-porcentaje,
    /// igual que Karvonen sin perfil de FC.
    private var peakDropBody: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
            VStack(alignment: .center, spacing: 4) {
                Text("Rest down to").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(Int((peakDropFraction * 100).rounded()))")
                        .groteskSheetNumeral().monospacedDigit().foregroundStyle(theme.dataRecovery)
                    Text(verbatim: "%").font(InstrumentoType.grotesk(14, weight: .bold)).foregroundStyle(theme.inkSecondary)
                }
                (Text(verbatim: "\(Int((peakDropFraction * 100).rounded()))% ") + Text("below your peak heart rate"))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            Slider(value: $peakDropFraction, in: 0.10...0.50, step: 0.01).tint(theme.dataRecovery)
            HStack {
                Text("10% hard").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Text("50% easy").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    /// «Lpm fijo» (FER-89): un objetivo directo, sin arithmetic sobre tu FC en reposo — ya persistido
    /// y formateado por `RoutineSetEditing.restChipLabel` (`HR · N bpm`), pero invisible en esta hoja
    /// hasta esta fase.
    private var fixedBpmBody: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
            VStack(alignment: .center, spacing: 4) {
                Text("Rest down to").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(fixedTargetBpm)")
                        .groteskSheetNumeral().monospacedDigit().foregroundStyle(theme.dataRecovery)
                    Text(verbatim: "bpm").font(InstrumentoType.grotesk(14, weight: .bold)).foregroundStyle(theme.inkSecondary)
                }
                Text("the same bpm every session, not from your resting heart rate")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            Slider(value: Binding(get: { Double(fixedTargetBpm) }, set: { fixedTargetBpm = Int($0.rounded()) }),
                   in: 80...170, step: 1).tint(theme.dataRecovery)
            HStack {
                Text("80 bpm hard").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Text("170 bpm easy").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    // MARK: Time mode

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
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
            let config = RestEditorMapping.buildConfig(
                mode: mode, hrRef: hrRef, seconds: seconds, margin: margin, reserve: reserve,
                peakDropFraction: peakDropFraction, fixedTargetBpm: fixedTargetBpm)
            onApply(config, applyToAll, saveToRoutine && persistsToRoutine)
        }
        .padding(.top, 4)
    }

    static func clock(_ seconds: Int) -> String { SessionClock.format(seconds) }
}
