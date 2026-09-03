import Foundation

/// RIR (reps in reserve) ↔ RPE, in ONE pure place (ola 2 · C1, FER-361).
///
/// The engine stores perceived effort as RPE (`WorkingSet.rpe`, `SetEntry.rpe`); «QUEDABAN» / reps in
/// reserve is the SAME capture read the other way (FER-134). This lived on `LiveStrengthSheet`, but the
/// Apple Watch logger (C1) can't import the app layer (`CenitWatch` depends only on `CenitDesign`), so
/// the pure numeric conversion moves here and both the watch and the sheet call the one oracle.
///
/// The **label** is deliberately NOT built here: `qLabel` on the app side emits `String(localized:)` from
/// the app's string catalog, which a Foundation-only package doesn't have. So this returns a semantic
/// `Reserve` case and each layer localizes it in its own catalog (the owner's vocabulary forbids
/// «Q»/«Quedaban» in any visible string — 0 reads «al fallo», the rest «N en reserva» / «4+ en reserva»).
public enum RIRScale {
    /// RPE from reps-in-reserve: `RPE = 10 − RIR`, with RIR saturated to 0…4 so «4+» = RIR 4 (RPE 6).
    /// The engine doesn't distinguish «4» from «more than 4»; both read «with margin». (FER-134.)
    public static func rpe(fromRIR rir: Int) -> Double { Double(10 - min(4, max(0, rir))) }

    /// The reps-in-reserve reading of an RPE, saturated to 0…4 («4+» at the top). Inverse of `rpe(fromRIR:)`.
    public static func reserve(fromRPE rpe: Double) -> Int { min(max(10 - Int(rpe.rounded()), 0), 4) }

    /// The semantic reserve reading, localized by each layer (never a hard string here).
    public enum Reserve: Equatable, Sendable {
        case atFailure            // 0 in reserve
        case inReserve(Int)       // 1…3 in reserve
        case fourPlus             // 4+ in reserve
    }

    /// Map an RPE to its semantic reserve label case.
    public static func label(fromRPE rpe: Double) -> Reserve {
        let r = reserve(fromRPE: rpe)
        if r == 0 { return .atFailure }
        return r >= 4 ? .fourPlus : .inReserve(r)
    }
}
