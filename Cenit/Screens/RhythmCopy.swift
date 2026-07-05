import Foundation
import CoreGraphics
import StrandAnalytics

// RhythmCopy.swift — the es-MX, NON-CLINICAL copy + presentation helpers for the «Ritmo» screen
// (FER-666 F2). Every user-facing phrase for the experimental rhythm read lives here, in one place,
// so the copy guard (`RhythmCopyGuardTests`) can sweep it for any word that would name a condition
// or imply a diagnosis. The claim frame is the heart of this feature: only the four neutral labels,
// a persistent "experimental · not an ECG · not a diagnosis" disclaimer, and calm state messages —
// never a condition name, a probability-of-condition, or a "see a doctor" call-to-action.
//
// Strings are es-MX literals (the app's language) rather than catalog lookups so the guard runs
// deterministically over the exact words shipped, independent of locale resolution.

enum RhythmCopy {

    // MARK: - The four neutral labels (the only verdict-shaped words that ever surface)

    /// The dominant neutral phrase for a night's read. Descriptive only — no condition, no alarm.
    static func label(_ r: RhythmRegularity) -> String {
        switch r {
        case .steady:           return "Se vio estable."
        case .occasionalEctopy: return "Se vieron algunos latidos extra o salteados."
        case .varied:           return "Varió más de lo usual."
        case .unreadable:       return "No se pudo leer con claridad."
        }
    }

    // MARK: - Persistent disclaimer (pinned, visible in every reading state)

    static let disclaimer = "Experimental · No es un ECG ni un diagnóstico · No detecta enfermedades."

    // MARK: - Consent explainer (first time only)

    static let consentOverline = "EXPERIMENTAL"
    static let consentTitle    = "Un vistazo a tu ritmo"
    static let consentBody     = "Mientras duermes, Cénit mira qué tan parejo late tu corazón, latido a latido, y te lo dibuja."
    static let consentNoEcg    = "No es un ECG."
    static let consentNoDx     = "No es un diagnóstico."
    static let consentNoDisease = "No detecta enfermedades."
    static let consentButton   = "Entendido"

    // MARK: - Screen chrome

    static let screenOverline = "RITMO · ANOCHE"
    static let tapHint        = "toca la nube para ver los detalles"

    // MARK: - Confidence line ("1,240 latidos · lectura sólida")

    static func confidence(beats: Int, tier: RhythmConfidence) -> String {
        let n = beats.formatted(.number.grouping(.automatic))
        switch tier {
        case .solid:       return "\(n) latidos · lectura sólida"
        case .building:    return "\(n) latidos · lectura en formación"
        case .calibrating: return "\(n) latidos · calibrando"
        }
    }

    // MARK: - Night line ("4 de 5 ventanas legibles se vieron estables")

    static func nightLine(_ s: RhythmScreener.NightRhythmSummary) -> String {
        let total = s.readableWindows
        switch s.overall {
        case .steady:
            return "\(s.steadyWindows) de \(total) ventanas legibles se vieron estables."
        case .occasionalEctopy:
            return "En \(s.occasionalWindows) de \(total) ventanas legibles se vieron latidos extra o salteados."
        case .varied:
            return "\(s.variedWindows) de \(total) ventanas legibles variaron más de lo usual."
        case .unreadable:
            return "Ninguna ventana de anoche se pudo leer con claridad."
        }
    }

    // MARK: - State messages (calm, no alarm)

    static let calibratingLabel = "Aún calibrando."
    static let calibratingHedge = "Aún estoy aprendiendo tu ritmo. Unas cuantas noches más y la lectura se afina."

    static let unreadableTitle  = "No se pudo leer con claridad anoche."
    static let unreadableWhy    = "Hubo mucho movimiento o poca señal en reposo. Es normal, vuelve a intentar mañana."

    static let noDataTitle      = "Sin lectura de anoche."
    static let noDataBody       = "Duerme con tu strap para ver tu ritmo aquí."

    static let needsBandTitle   = "Ritmo necesita una banda WHOOP."
    static let needsBandBody    = "El tacograma latido a latido solo viene de la banda; no está disponible con solo Apple Health."

    // MARK: - The six statistics (label + plain-language gloss)

    /// One detail row: a plain label, a one-line gloss "in cristiano", and the formatted value.
    struct Stat: Identifiable {
        let id = UUID()
        let label: String
        let gloss: String
        let value: String
    }

    /// Build the six descriptive stats from a readable window. Values only — no interpretation.
    static func stats(_ w: RhythmScreener.WindowResult) -> [Stat] {
        func ms(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) ms" } ?? "—" }
        func ratio(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "—" }
        func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0 * 100) } ?? "—" }
        return [
            Stat(label: "Forma de la nube (SD1:SD2)", gloss: "qué tan redonda vs. alargada", value: ratio(w.sd1sd2)),
            Stat(label: "Ancho corto (SD1)", gloss: "variación de un latido al siguiente", value: ms(w.sd1)),
            Stat(label: "Largo (SD2)", gloss: "variación a lo largo de la noche", value: ms(w.sd2)),
            Stat(label: "Variación relativa", gloss: "respecto a tu latido promedio", value: pct(w.normRmssd)),
            Stat(label: "Cambios de dirección", gloss: "qué tan «picudo» fue el ritmo", value: ratio(w.turningPointRate)),
            Stat(label: "Latidos extra o salteados", gloss: "fracción del total", value: pct(w.ectopicFraction)),
        ]
    }

    /// Every shipped string in one array, for the non-clinical copy guard to sweep. Includes the
    /// four labels, the disclaimer, consent, chrome, state messages and the six stat labels/glosses.
    static var allStrings: [String] {
        var out = [RhythmRegularity.steady, .occasionalEctopy, .varied, .unreadable].map(label)
        out += [disclaimer, consentOverline, consentTitle, consentBody, consentNoEcg, consentNoDx,
                consentNoDisease, consentButton, screenOverline, tapHint,
                calibratingLabel, calibratingHedge, unreadableTitle, unreadableWhy,
                noDataTitle, noDataBody, needsBandTitle, needsBandBody]
        // Interpolated lines: include a rendered sample of each branch so the guard sweeps their
        // fixed fragments too (the confidence tiers and every night-line variant), not just literals.
        out += [RhythmConfidence.solid, .building, .calibrating].map { confidence(beats: 1240, tier: $0) }
        out += [RhythmRegularity.steady, .occasionalEctopy, .varied, .unreadable].map {
            nightLine(RhythmScreener.NightRhythmSummary(readableWindows: 5, steadyWindows: 4,
                                                        occasionalWindows: 1, variedWindows: 3,
                                                        variationRecurred: true, overall: $0))
        }
        // Stat labels + glosses (values are numeric, not copy).
        let demo = RhythmScreener.WindowResult(label: .steady, sd1: 20, sd2: 55, sd1sd2: 0.36,
                                               normRmssd: 0.04, turningPointRate: 0.7, ectopicFraction: 0.01,
                                               nBeats: 300, confidence: .solid, agreedAcrossSources: false,
                                               poincare: [])
        out += stats(demo).flatMap { [$0.label, $0.gloss] }
        return out
    }
}

// MARK: - Presentation helpers over a night's read

extension NightRhythmAssembler.NightRhythm {

    /// Below this many readable windows, the night is shown as still "calibrando" — too thin to
    /// speak confidently, even if a window or two read cleanly. Presentation gate, not science.
    static let minWindowsForConfidentRead = 3

    /// The window that best represents the night for the plot: the readable window whose label
    /// matches the night's overall read, with the most beats (steadiest, densest evidence).
    var representativeWindow: RhythmScreener.WindowResult? {
        let readable = windows.filter { $0.label != .unreadable }
        return readable.filter { $0.label == summary.overall }.max { $0.nBeats < $1.nBeats }
            ?? readable.max { $0.nBeats < $1.nBeats }
    }

    /// Total clean beats across readable windows — the confidence count shown to the user.
    var readableBeats: Int {
        windows.filter { $0.label != .unreadable }.reduce(0) { $0 + $1.nBeats }
    }

    /// Best confidence tier among readable windows (solid > building > calibrating).
    var bestConfidence: RhythmConfidence {
        let tiers = windows.filter { $0.label != .unreadable }.map { $0.confidence }
        if tiers.contains(.solid) { return .solid }
        if tiers.contains(.building) { return .building }
        return .calibrating
    }

    /// The Poincaré cloud points (as CGPoints) from the representative window, for `PoincareCloud`.
    var cloudPoints: [CGPoint] {
        (representativeWindow?.poincare ?? []).map { CGPoint(x: $0.x, y: $0.y) }
    }
}
