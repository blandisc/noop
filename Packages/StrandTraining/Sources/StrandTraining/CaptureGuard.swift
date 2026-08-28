import Foundation

// CaptureGuard.swift — the single rule for "does this weight look like a fat-finger typo?" (FER-169 · B10).
//
// A 825 kg capture meant as 82.5 kg is harmless as an acta entry (the session log doesn't lie about
// what was tapped) but poisonous everywhere the app LEARNS from history: it would mint an absurd
// personal record and reseed the next session's console at 825 kg. The guard fires once, at capture,
// with a reversible question — but the same "is this absurd" verdict has to be re-askable, independently,
// at the two places that later read history (`CenitStore.StrengthStore`'s PR close and its next-session
// seed) without a persisted flag anywhere (`SetEntry` gets no new column). This type is that one
// question, asked identically by all three call sites — the constant lives here (StrandTraining is the
// pure, zero-dependency root both `Cenit` and `CenitStore` build on) so there is exactly one multiplier
// to tune, never three that could drift.
public enum CaptureGuard {
    /// A capture is judged absurd at 8× the best weight already known for the exercise (an existing
    /// personal record, or — with none yet — the row's own seed/prescription). Chosen so a legitimate
    /// big jump (a fresh PR, taking a held raise, a warm-up-to-work ramp) never trips it, while the
    /// canonical typo this guards against — a dropped decimal point, 82.5 mistyped as 825, a ~10×
    /// error — always does.
    public static let absurdWeightMultiplier: Double = 8

    /// Whether `weightKg` looks like a fat-finger capture against `referenceKg`. `referenceKg <= 0`
    /// means there is nothing yet to compare against — the very first weighted set an exercise has
    /// ever seen, with no record and no seed — and the guard never guesses a reference that doesn't
    /// exist, so it stays silent rather than false-triggering on a legitimate first entry.
    public static func isAbsurd(weightKg: Double, referenceKg: Double) -> Bool {
        referenceKg > 0 && weightKg >= absurdWeightMultiplier * referenceKg
    }
}
