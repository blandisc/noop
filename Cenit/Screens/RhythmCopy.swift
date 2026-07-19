import Foundation
import CoreGraphics
import StrandAnalytics

// RhythmCopy.swift — the NON-CLINICAL copy + presentation helpers for the «Ritmo» screen (FER-666).
// Every user-facing phrase lives here as an ENGLISH key resolved via `String(localized:)`, so the
// app's String Catalog (`sourceLanguage: en`) carries the es-MX translation and the screen switches
// with the app language — bilingual like the rest of the app (the Spanish is authored in
// `Tools/translate-es.py`, the single source of truth for the `es` values).
//
// The claim frame is the heart of this feature: only the four neutral labels ever surface, a
// persistent "experimental · not an ECG · not a diagnosis" disclaimer stays pinned, and every state
// message is calm. No condition name, no probability-of-condition, no clinical call-to-action — in
// EITHER language. `RhythmCopyGuardTests` resolves each key in both en and es and sweeps for that.

enum RhythmCopy {

    // MARK: - The four neutral labels (the only verdict-shaped words that ever surface)

    static func label(_ r: RhythmRegularity) -> String {
        switch r {
        case .steady:           return String(localized: "Looked steady.")
        case .occasionalEctopy: return String(localized: "A few extra or skipped beats showed up.")
        case .varied:           return String(localized: "Varied more than usual.")
        case .unreadable:       return String(localized: "Couldn't read it clearly.")
        }
    }

    // MARK: - Persistent disclaimer (pinned in every reading state)

    static var disclaimer: String {
        String(localized: "Experimental · Not an ECG or a diagnosis · Doesn't detect disease.")
    }

    // MARK: - Consent explainer (first time only)

    static var consentOverline: String { String(localized: "EXPERIMENTAL") }
    static var consentTitle: String { String(localized: "A glimpse of your rhythm") }
    static var consentBody: String {
        String(localized: "While you sleep, Cénit looks at how evenly your heart beats, beat to beat, and draws it for you.")
    }
    static var consentNoEcg: String { String(localized: "It's not an ECG.") }
    static var consentNoDx: String { String(localized: "It's not a diagnosis.") }
    static var consentNoDisease: String { String(localized: "It doesn't detect disease.") }
    static var consentButton: String { String(localized: "Got it") }

    // MARK: - Screen chrome

    static var screenOverline: String { String(localized: "RHYTHM · LAST NIGHT") }
    static var tapHint: String { String(localized: "tap the cloud for the details") }

    // MARK: - Confidence line

    static func confidence(beats: Int, tier: RhythmConfidence) -> String {
        switch tier {
        case .solid:       return String(localized: "\(beats) beats · solid read")
        case .building:    return String(localized: "\(beats) beats · forming read")
        case .calibrating: return String(localized: "\(beats) beats · calibrating")
        }
    }

    // MARK: - Night line

    static func nightLine(_ s: RhythmScreener.NightRhythmSummary) -> String {
        let total = s.readableWindows
        switch s.overall {
        case .steady:
            return String(localized: "\(s.steadyWindows) of \(total) readable windows looked steady.")
        case .occasionalEctopy:
            return String(localized: "\(s.occasionalWindows) of \(total) readable windows showed extra or skipped beats.")
        case .varied:
            return String(localized: "\(s.variedWindows) of \(total) readable windows varied more than usual.")
        case .unreadable:
            return String(localized: "No window last night could be read clearly.")
        }
    }

    // MARK: - State messages (calm, no alarm)

    static var calibratingLabel: String { String(localized: "Still calibrating.") }
    static var calibratingHedge: String {
        String(localized: "I'm still learning your rhythm. A few more nights and the read sharpens.")
    }
    static var unreadableTitle: String { String(localized: "Couldn't read it clearly last night.") }
    static var unreadableWhy: String {
        String(localized: "There was too much movement or too little signal at rest. It's normal, try again tomorrow.")
    }
    static var noDataTitle: String { String(localized: "No reading from last night.") }
    static var noDataBody: String { String(localized: "Sleep with your strap to see your rhythm here.") }
    static var needsBandTitle: String { String(localized: "Ritmo needs a strap.") }
    static var needsBandBody: String {
        String(localized: "The beat-to-beat tacogram only comes from the band; it isn't available with Apple Health only.")
    }

    // MARK: - The six statistics (label + plain-language gloss)

    struct Stat: Identifiable {
        let id = UUID()
        let label: String
        let gloss: String
        let value: String
    }

    static func stats(_ w: RhythmScreener.WindowResult) -> [Stat] {
        func ms(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) ms" } ?? "—" }
        func ratio(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "—" }
        func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0 * 100) } ?? "—" }
        return [
            Stat(label: String(localized: "Cloud shape (SD1:SD2)"),
                 gloss: String(localized: "how round vs. elongated"), value: ratio(w.sd1sd2)),
            Stat(label: String(localized: "Short width (SD1)"),
                 gloss: String(localized: "variation from one beat to the next"), value: ms(w.sd1)),
            Stat(label: String(localized: "Length (SD2)"),
                 gloss: String(localized: "variation across the night"), value: ms(w.sd2)),
            Stat(label: String(localized: "Relative variation"),
                 gloss: String(localized: "against your average beat"), value: pct(w.normRmssd)),
            Stat(label: String(localized: "Direction changes"),
                 gloss: String(localized: "how jagged the rhythm was"), value: ratio(w.turningPointRate)),
            Stat(label: String(localized: "Extra or skipped beats"),
                 gloss: String(localized: "fraction of the total"), value: pct(w.ectopicFraction)),
        ]
    }

    /// English base keys of every shipped phrase, for the non-clinical guard to resolve in each
    /// language and sweep. Includes the format-string keys (with `%lld`) of the interpolated lines.
    /// Kept in lockstep with the `String(localized:)` literals above and seeded into the catalog.
    static let allEnglishKeys: [String] = [
        "Looked steady.", "A few extra or skipped beats showed up.",
        "Varied more than usual.", "Couldn't read it clearly.",
        "Experimental · Not an ECG or a diagnosis · Doesn't detect disease.",
        "EXPERIMENTAL", "A glimpse of your rhythm",
        "While you sleep, Cénit looks at how evenly your heart beats, beat to beat, and draws it for you.",
        "It's not an ECG.", "It's not a diagnosis.", "It doesn't detect disease.", "Got it",
        "RHYTHM · LAST NIGHT", "tap the cloud for the details",
        "%lld beats · solid read", "%lld beats · forming read", "%lld beats · calibrating",
        "%lld of %lld readable windows looked steady.",
        "%lld of %lld readable windows showed extra or skipped beats.",
        "%lld of %lld readable windows varied more than usual.",
        "No window last night could be read clearly.",
        "Still calibrating.",
        "I'm still learning your rhythm. A few more nights and the read sharpens.",
        "Couldn't read it clearly last night.",
        "There was too much movement or too little signal at rest. It's normal, try again tomorrow.",
        "No reading from last night.", "Sleep with your strap to see your rhythm here.",
        "Ritmo needs a strap.",
        "The beat-to-beat tacogram only comes from the band; it isn't available with Apple Health only.",
        "Cloud shape (SD1:SD2)", "how round vs. elongated",
        "Short width (SD1)", "variation from one beat to the next",
        "Length (SD2)", "variation across the night",
        "Relative variation", "against your average beat",
        "Direction changes", "how jagged the rhythm was",
        "Extra or skipped beats", "fraction of the total",
        "Your rhythm, beat to beat",   // the Ajustes → Experimental row subtitle
    ]
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
