import Foundation

/// The minimal end-of-session summary the watch shows (FER-741, state 6). `WatchWorkoutManager`
/// assembles it from the mirrored session when the iPhone (or the wrist) ends it. Deliberately small:
/// the duration is the hero; average heart rate and active energy are secondary; `saveState` decides
/// whether the card confirms it was saved to Health or warns that it could not. Series / volume /
/// recovery live on the iPhone receipt, never here.
struct WatchSessionSummary: Equatable {
    /// Total session length. The hero of the card.
    var duration: TimeInterval
    /// Average heart rate over the session, or `nil` if the sensor never read (no permission / no lock).
    var averageHeartRate: Int?
    /// Active energy in kilocalories, or `nil` when unavailable.
    var activeEnergyKcal: Int?
    /// Whether the watch's own `HKWorkout` reached Apple Health.
    var saveState: SaveState

    /// The save outcome drives the confirmation line and whether the card may auto-dismiss.
    enum SaveState: Equatable {
        /// The workout reached Apple Health → «Guardado en Salud»; the card may auto-dismiss after ~30s.
        case saved
        /// The save failed → «No se pudo guardar en Salud»; the card stays until «Listo» is tapped.
        case failed
    }

    /// Whole minutes, for the VoiceOver duration phrase («Duración, 48 minutos»).
    var durationMinutes: Int { Int((duration / 60).rounded()) }
}
