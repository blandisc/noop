import Foundation

// SetCapture.swift — the single rule for which measure a logged set stores, by exercise type (FER-351).
//
// The guided session (`StrengthSessionModel`, in the app) captures weight, reps, time and distance on
// every working set, but only some of them mean anything for a given `ExerciseType`. This pure helper
// is that mapping in one place — so a time/distance set never persists the model's placeholder reps and
// the weight×reps path is untouched — and it's testable with `swift test` (the app's session model is
// SwiftUI-coupled and can only be exercised in a simulator).

public enum SetCapture {

    /// The persisted measures for one logged set, given its exercise type and the raw captured values.
    /// Returns nil for any field the type doesn't measure (and for zero weight/reps, which mean "unset").
    ///
    /// - `weightReps`: weight + reps.
    /// - `bodyweight`: reps, plus the optional added load («lastre») when > 0.
    /// - `time`: elapsed seconds only.
    /// - `distance`: meters + elapsed seconds.
    ///
    /// Ola 1 (FER-327): `reps` es OPCIONAL — `nil` = un AMRAP todavía pendiente. Se persiste igual que un
    /// 0: como `nil` («sin capturar»), nunca como un cero que fingiría una serie de volumen cero.
    public static func fields(type: ExerciseType, weightKg: Double, reps: Int?,
                              timeS: Int?, distanceM: Double?)
        -> (weightKg: Double?, reps: Int?, timeS: Double?, distanceM: Double?) {
        switch type {
        case .weightReps, .bodyweight:
            // Both store reps + weight; for bodyweight the weight is the optional lastre (nil when 0).
            return (weightKg > 0 ? weightKg : nil, (reps ?? 0) > 0 ? reps : nil, nil, nil)
        case .time:
            return (nil, nil, timeS.map(Double.init), nil)
        case .distance:
            return (nil, nil, timeS.map(Double.init), (distanceM ?? 0) > 0 ? distanceM : nil)
        }
    }
}
