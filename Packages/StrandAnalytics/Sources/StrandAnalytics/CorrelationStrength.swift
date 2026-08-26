import Foundation

// CorrelationStrength.swift — the ONE ladder that names a Pearson |r| (FER-104 / TND-29).
//
// Before this type there were two rival "how strong is it?" scales living in the app:
//
//   • CompareView.strengthWord(_:)  — a Pearson |r| ladder:
//       |r| < 0.10 negligible · < 0.30 weak · < 0.50 moderate · < 0.70 strong · else very strong
//   • BucleFormat.magnitudeWord(_:) — a Cohen's d EFFECT-SIZE ladder (0.20/0.50/0.80).
//
// Those two are LEGITIMATELY DIFFERENT scales — one grades a correlation coefficient, the other
// grades a standardized mean difference — so they are NOT unified here (forcing Cohen's d onto the
// r cuts would be wrong). What WAS a latent duplication is the r ladder itself: it lived only inside
// a view, so any second reader of a correlation would have re-invented the cuts (the exact class that
// produced the twin-screen P1s). This promotes the r ladder to a single, pure, testable source next
// to `CorrelationEngine`, keyed by the coefficient, one band per range. The APP owns the localized
// WORD for each band (so the strings resolve against the app bundle, not this package's) — this type
// only owns the cuts and the canonical minimum sample size.

/// The strength band of a Pearson correlation coefficient `r`, by the conventional |r| cuts. One band
/// per range (half-open on the upper bound), so a coefficient maps to exactly one word. The localized
/// noun ("moderate", …) is applied at the call site — this stays string-free and reusable.
public enum CorrelationStrength: String, CaseIterable, Sendable {
    case negligible
    case weak
    case moderate
    case strong
    case veryStrong

    /// Classify a coefficient by its magnitude. Sign is irrelevant to strength (a −0.9 is as strong as
    /// a +0.9), so this reads |r|. Cuts (half-open): |r| < 0.10 negligible · < 0.30 weak · < 0.50
    /// moderate · < 0.70 strong · ≥ 0.70 very strong — the widely used descriptive banding for a
    /// product-moment correlation.
    public static func classify(r: Double) -> CorrelationStrength {
        switch abs(r) {
        case ..<0.10: return .negligible
        case ..<0.30: return .weak
        case ..<0.50: return .moderate
        case ..<0.70: return .strong
        default:      return .veryStrong
        }
    }

    /// The canonical minimum number of overlapping observations below which a Pearson r is not worth
    /// computing/trusting: with n = 2 the coefficient is trivially ±1, so 3 is the mathematical floor
    /// (it matches `CorrelationEngine.pearson`, which returns nil for n < 3). This is the COMPUTE
    /// floor. A screen may layer a STRICTER surfacing bar on top for a ranked discovery list (the
    /// Metric Explorer requires n ≥ 10 before it will recommend a correlate) — that is a display
    /// policy, not this floor.
    public static let minPairs = 3
}
