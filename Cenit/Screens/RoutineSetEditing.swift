#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// RoutineSetEditing.swift — la lógica de descanso por serie + los componentes que comparten las
// pantallas de entrenamiento: el editor «Rutina» (`RoutineEditorScreen`, FER-839) y la sesión activa
// (`LiveStrengthSheet`). Ambas trabajan sobre el MISMO modelo de descanso (F0), así que los helpers de
// resolución/aplicación/etiqueta viven aquí una sola vez.
//
// Aquí viven también `RestChip`, `SupersetTag` y `DeleteSetPill` — las tres estaban duplicadas entre
// esas dos pantallas y varias ya habían divergido (2026-07-19).
//
// El `RoutineBuilderScreen` que también compartía este archivo se retiró ese mismo día: era una SEGUNDA
// pantalla de prescripción, su único flujo vivo («Duplicar como rutina») ya terminaba en el editor, y
// mantenerla obligaba a curar cada componente dos veces.
//
// La TABLA de series sigue siendo de cada pantalla, y eso es a propósito: una prescribe y la otra
// captura, así que difieren de verdad (ver la nota gemela sobre el numeral en ambas).

/// Identifies the set whose rest the 1e editor is editing (exercise index + set index).
struct RestEditTarget: Identifiable, Hashable { let ei: Int; let si: Int; var id: String { "\(ei)-\(si)" } }

/// Identifies the exercise whose progression plan the 2c editor is editing (FER-D).
struct ProgressionTarget: Identifiable, Hashable { let ei: Int; var id: Int { ei } }

// MARK: - Per-set rest resolution (F0 model)

enum RoutineSetEditing {
    /// La forma de la rampa de calentamiento: tres series al 40 / 60 / 80 % del peso de trabajo, a 10
    /// repeticiones. Es una regla del DOMINIO, no de una pantalla, y estaba escrita a mano en tres
    /// lugares (editar rutina, sesión activa y el builder). Si algún día la rampa cambia —cuatro pasos,
    /// otros porcentajes— debe cambiar UNA vez. (2026-07-19)
    static let warmupFactors: [Double] = [0.4, 0.6, 0.8]
    static let warmupReps = 10

    /// This set's effective rest: its own override if set, else the exercise's rest fields (the F0 fallback).
    static func effectiveRest(_ re: RoutineExercise, _ si: Int) -> RestConfig {
        if let r = re.sets[si].rest { return r }
        return RestConfig(mode: re.restMode, seconds: re.restSeconds,
                          hrReference: re.hrRestReference, hrValue: re.hrRestValue)
    }

    /// 1-based work-set number for the 1e overline (nil for a warm-up «C» set).
    static func workSetNumber(_ re: RoutineExercise, _ si: Int) -> Int? {
        guard re.sets[si].kind == .work else { return nil }
        return re.sets[0...si].filter { $0.kind == .work }.count
    }

    /// «C» for a warm-up set; otherwise its position among the work sets (1-based, warm-ups don't count).
    static func setLabel(_ re: RoutineExercise, _ si: Int) -> String {
        if re.sets[si].kind == .warmup { return String(localized: "C") }
        return "\(re.sets[0...si].filter { $0.kind == .work }.count)"
    }

    /// Apply an edited rest from 1e. «This set» writes that set's override; «All sets» writes the
    /// exercise-level rest fields and clears every per-set override so the whole exercise inherits it.
    static func applyRest(to re: inout RoutineExercise, si: Int, config: RestConfig, applyToAll: Bool) {
        guard re.sets.indices.contains(si) else { return }
        if applyToAll {
            re.restMode = config.mode
            re.restSeconds = config.seconds
            re.hrRestReference = config.hrReference
            re.hrRestValue = config.hrValue
            for i in re.sets.indices { re.sets[i].rest = nil }
        } else {
            re.sets[si].rest = config
        }
    }

    /// The chip's compact label: «1 min» / «90 s» for time, «FC · N%» for the HR threshold. The HR prefix is
    /// localized on its own so the literal «%» never lands in a format-string key.
    static func restChipLabel(_ cfg: RestConfig) -> String {
        if cfg.mode == .heartRate {
            // FER-952 bug: `hrValue` is a FRACTION only for peakDrop/karvonen — formatting it as a
            // percent regardless turned a fixed 160 bpm into «1600%» and restingMargin into noise.
            let hr = String(localized: "HR", comment: "compact chip prefix for a heart-rate rest threshold")
            switch cfg.hrReference {
            case .peakDrop, .karvonenReserve:
                let pct = Int((cfg.hrValue * 100).rounded())
                guard pct > 0 else { return String(localized: "by HR") }
                return hr + " · \(pct)%"
            case .fixedBpm:
                let bpm = Int(cfg.hrValue.rounded())
                guard bpm > 0 else { return String(localized: "by HR") }
                return hr + " · \(bpm) bpm"
            case .restingMargin:
                return String(localized: "by HR")   // target = resting + margin; no number to promise
            }
        }
        let s = cfg.seconds
        return s % 60 == 0 ? String(localized: "\(s / 60) min") : String(localized: "\(s) s")
    }

    // MARK: - Superset grouping (a group = consecutive slots sharing supersetGroup)
    //
    // Pure functions over the slot array, shared by the builder and the «Rutina» editor (FER-838
    // /simplify — they were duplicated verbatim). Mutations return nothing; callers mark their own
    // dirty state.

    static func sameGroup(_ res: [RoutineExercise], _ a: Int, _ b: Int) -> Bool {
        guard res.indices.contains(a), res.indices.contains(b),
              let ga = res[a].supersetGroup, let gb = res[b].supersetGroup else { return false }
        return ga == gb
    }

    static func inSuperset(_ res: [RoutineExercise], _ i: Int) -> Bool {
        guard res.indices.contains(i), res[i].supersetGroup != nil else { return false }
        return sameGroup(res, i, i - 1) || sameGroup(res, i, i + 1)
    }

    /// First member of a superset group (shows the «Superset» overline above it).
    static func firstOfGroup(_ res: [RoutineExercise], _ i: Int) -> Bool {
        inSuperset(res, i) && !sameGroup(res, i, i - 1)
    }

    static func supersetWithNext(_ res: inout [RoutineExercise], _ i: Int) {
        guard i < res.count - 1 else { return }
        let group = res[i].supersetGroup ?? res[i + 1].supersetGroup
            ?? (res.compactMap(\.supersetGroup).max() ?? 0) + 1
        res[i].supersetGroup = group
        res[i + 1].supersetGroup = group
    }

    static func breakSuperset(_ res: inout [RoutineExercise], _ i: Int) {
        guard let g = res[i].supersetGroup else { return }
        res[i].supersetGroup = nil
        let remaining = res.indices.filter { res[$0].supersetGroup == g }
        if remaining.count == 1 { res[remaining[0]].supersetGroup = nil }
    }

    // MARK: - «Series iguales» (FER-88) — el detector que decide si la receta se pliega
    //
    // `RoutineEditorScreen` pliega la receta de un ejercicio en una sola `RecetaLine` («3 series ·
    // 80 kg × 8») cuando todas sus series de TRABAJO coinciden, y la abre en renglones automáticos
    // (con el aviso «series distintas» + «Igualar todas») en cuanto una difiere. Pura, sin `View` ni
    // `Repository`, para que el criterio de aceptación la pruebe sin montar una pantalla.

    /// El calentamiento NUNCA cuenta — ni para plegar ni para abrir. Sin series de trabajo (caso
    /// imposible en la práctica, pero no en el tipo) no hay nada que distinguir: colapsa.
    ///
    /// FER-88 (esta conformación): la comparación también debería cubrir `RoutineSet.repsRangeTop` —
    /// dos series con el mismo peso/reps pero distinto techo de rango cuentan como DISTINTAS. Ese
    /// campo todavía no existe en `Training.swift` (aterriza con E13/FER-94; `grep -rn repsRangeTop
    /// Cenit/ Packages/` → 0 resultados hoy) y ese archivo no es de esta fase, así que la extensión
    /// queda BLOQUEADA — no silenciada: en cuanto el campo aterrice, esta función gana una línea más
    /// (`$0.repsRangeTop == first.repsRangeTop`) y su prueba gemela dejará de estar comentada.
    static func workSetsAreEqual(_ sets: [RoutineSet]) -> Bool {
        let work = sets.filter { $0.kind == .work }
        guard let first = work.first else { return true }
        return work.allSatisfy { $0.weightKg == first.weightKg && $0.reps == first.reps }
    }
}

// MARK: - Per-set rest chip (→ 1e push)
//
// Each set carries its own rest (choque 3): the chip shows this set's EFFECTIVE rest (its own override, or the
// exercise's rest as fallback). Troquel grammar (r15): the hue lives ONLY in the leading icon (♥ recovery
// for HR, clock ember for time); the value reads in ink. Tapping pushes the shared `RestEditorScreen` (1e).

struct RestChip: View {
    @Environment(\.instrumentoTheme) private var theme
    let cfg: RestConfig
    let action: () -> Void

    var body: some View {
        let isHR = cfg.mode == .heartRate
        // FER-89: construido sobre `EntrenarChip` (E2) con sus overrides de icono/tono — la ÚNICA
        // forma de conservar la distinción reloj/pulso (r15: el hue vive SOLO en el icono, ♥
        // recovery para FC, reloj ember para tiempo fijo) que `EntrenarChip.Kind.rest` no admite por
        // sí solo (ver `EntrenarNivel.swift`). Mismo papel + borde `hairlineStrong` + chevron «›» de
        // antes, ahora desde la pieza compartida — el texto pasa de Grotesk tabular (12, medium) al
        // `StrandFont.caption` que `EntrenarChip` ya usa para descanso/progresión/calentamiento: es
        // el punto de la migración (converger en UN vocabulario), documentado, no un descuido.
        EntrenarChip(.rest, verbatim: RoutineSetEditing.restChipLabel(cfg),
                    icon: isHR ? "heart.fill" : "clock",
                    tone: isHR ? theme.dataRecovery : theme.dataStrain,
                    showsDisclosure: true, action: action)
            // 2026-07-19: la sesión activa reimplementaba este chip entero, con un comentario que ya
            // afirmaba «MISMO chip que el editor» mientras el código los tenía separados. Al
            // unificarlos se conservó la MEJOR accesibilidad de las dos —la de la sesión—: etiqueta y
            // valor separados, para que VoiceOver anuncie el descanso al cambiar sin releer la acción.
            // De paso se corrige el copy: FER-952 hizo el descanso por EJERCICIO, así que «de esta
            // serie» llevaba meses mintiendo. FER-89 conserva esto tal cual sobre la pieza nueva.
            .accessibilityLabel(Text("Edit rest"))
            .accessibilityValue(Text(RoutineSetEditing.restChipLabel(cfg)))
    }
}

// MARK: - El cromo de una celda de captura — papel pautado
//
// La celda donde se teclea peso y reps existía en tres variantes que sólo diferían por deriva: caja con
// relleno en el editor, regla en la sesión, y en `WorkoutEditSheet` una regla con **SF en vez de
// Grotesk** (DESIGN.md §8.7 le da los numerales a Grotesk) y el subrayado enfocado en **ember** donde
// las otras dos usan tinta. Ahora el cromo es uno.
//
// Es un modificador y no un componente porque el MECANISMO difiere de verdad y debe seguir difiriendo:
// el editor y la hoja de corrección usan `TextField` con teclado nativo; la sesión activa usa
// `SessionKeypad`, porque en pleno esfuerzo hacen falta ± por discos y no perder media pantalla bajo el
// teclado. Compartir el aspecto no obliga a compartir la entrada. (2026-07-19)
struct SetCellChrome: ViewModifier {
    @Environment(\.instrumentoTheme) private var theme
    let width: CGFloat
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.center)
            .font(InstrumentoType.groteskNumber(16, weight: .medium, relativeTo: .body)).monospacedDigit()
            .foregroundStyle(theme.ink)
            // El ancho se fija (las columnas se alinean con su encabezado); el alto es MÍNIMO, porque
            // la fuente escala con Dynamic Type y una caja fija recortaría el número.
            .frame(width: width)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? theme.ink : theme.hairlineStrong)
                    .frame(height: focused ? 2 : 1)
                    .padding(.bottom, 6)
            }
    }
}

extension View {
    /// El cromo de una celda de captura: papel pautado, 44 pt de piso táctil. Ver `SetCellChrome`.
    func setCellChrome(width: CGFloat, focused: Bool) -> some View {
        modifier(SetCellChrome(width: width, focused: focused))
    }
}

// MARK: - «SUPERSERIE» — el rótulo del par
//
// Cada pantalla tenía la mitad de la razón (2026-07-19). El editor usaba `groteskOverline` pero en
// `inkSecondary`; la sesión usaba `dataHrv` pero con `StrandFont.overline`, que DESIGN.md §8.7 marca
// como legacy («ninguna pantalla nueva lo usa»). La unión correcta es la voz del editor con el color
// de la sesión: **Grotesk en teal**. El teal no es decoración aquí — es la señal de superserie en todo
// el flujo (el badge A1/A2, el riel, las leyendas), así que el `inkSecondary` del editor rompía esa
// asociación justo donde más se necesita.
struct SupersetTag: View {
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        Text("Superset").groteskOverline().foregroundStyle(theme.dataHrv)
    }
}

// MARK: - «Quitar serie» — la pastilla que arma el long-press
//
// Vivía copiada en editar rutina y en la sesión activa con la MISMA anatomía (r21: glifo chico, caption
// plano, padding apretado, cápsula de contorno crítico). Solo difería el ACTO: el editor borra de la
// prescripción, la sesión borra de la captura y además apaga el calentamiento persistente si esa era la
// última «C». Se comparte la vista; el acto lo pone cada pantalla. (2026-07-19)
struct DeleteSetPill: View {
    @Environment(\.instrumentoTheme) private var theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "trash").font(StrandFont.glyph(.chevron))
                Text("Delete set").font(StrandFont.caption)
            }
            .foregroundStyle(theme.critical)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.critical.opacity(StrandOpacity.dim), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
#endif
