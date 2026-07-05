import Foundation
import Combine
import StrandAnalytics

/// InactivityPrefs — settings + persisted de-dup state for the inactivity reminder (FER-664).
///
/// The detection, gating and de-dup all live in the pure, unit-tested `SedentaryDetector` engine
/// (StrandAnalytics). This store owns the user knobs and the restart-safe LAST_* state; the BLE
/// offload hook (`BLEManager.maybeBuzzInactivity`) reads the engine seams (`loadConfig` / `loadState`
/// / `saveState`) straight from UserDefaults and feeds them to `SedentaryDetector.evaluate`.
///
/// Unlike the upstream — which reused a separate notification-master store — Cénit has no such master,
/// so the feature toggle IS the master (`notificationsMasterOn = enabled`) and the only-when-worn gate
/// is always on, mirroring the other haptic automations (zone coaching / stress nudge) that gate on
/// `live.worn`. The active-hours window is evaluated by the engine against the candidate bout's LOCAL
/// end time, not `now`: gravity only reaches the app on the strap's offload flush, so an overnight bout
/// is processed in the morning; keying off the bout's own end time is what makes "active hours excludes
/// nighttime sleep" actually hold. iOS-safe (UserDefaults only).
@MainActor
final class InactivityPrefs: ObservableObject {

    /// Feature toggle (opt-in, default OFF).
    @Published var enabled: Bool             { didSet { d.set(enabled, forKey: K.enabled) } }
    /// Minutes seated before the first nudge (UI 15–120, step 15).
    @Published var thresholdMinutes: Int     { didSet { d.set(thresholdMinutes, forKey: K.threshold) } }
    /// If still seated, re-buzz this often (UI 15–120, step 15).
    @Published var reNudgeMinutes: Int       { didSet { d.set(reNudgeMinutes, forKey: K.reNudge) } }
    /// Only nudge during the active-hours window (default ON).
    @Published var activeHoursEnabled: Bool  { didSet { d.set(activeHoursEnabled, forKey: K.activeOn) } }
    /// Active-hours start, minutes since local midnight (default 09:00).
    @Published var activeStartMinutes: Int   { didSet { d.set(activeStartMinutes, forKey: K.activeStart) } }
    /// Active-hours end, minutes since local midnight (default 17:00).
    @Published var activeEndMinutes: Int     { didSet { d.set(activeEndMinutes, forKey: K.activeEnd) } }
    /// Suppress during quiet hours (default OFF).
    @Published var quietHoursEnabled: Bool   { didSet { d.set(quietHoursEnabled, forKey: K.quietOn) } }
    /// Quiet-hours start, minutes since local midnight (default 22:00).
    @Published var quietStartMinutes: Int    { didSet { d.set(quietStartMinutes, forKey: K.quietStart) } }
    /// Quiet-hours end, minutes since local midnight (default 07:00).
    @Published var quietEndMinutes: Int      { didSet { d.set(quietEndMinutes, forKey: K.quietEnd) } }

    private let d = UserDefaults.standard
    private enum K {
        static let enabled     = "inactivity.enabled"
        static let threshold   = "inactivity.thresholdMinutes"
        static let reNudge     = "inactivity.reNudgeMinutes"
        static let activeOn    = "inactivity.activeHoursEnabled"
        static let activeStart = "inactivity.activeStartMinutes"
        static let activeEnd   = "inactivity.activeEndMinutes"
        static let quietOn     = "inactivity.quietHoursEnabled"
        static let quietStart  = "inactivity.quietStartMinutes"
        static let quietEnd    = "inactivity.quietEndMinutes"
        // De-dup / freshness state (persisted so a relaunch can't re-buzz a replayed window).
        static let lastProcessedTs = "inactivity.lastProcessedGravityTs"
        static let lastBuzzAt      = "inactivity.lastBuzzAt"
        static let lastBoutStart   = "inactivity.lastBuzzedBoutStart"
        static let lastBoutEnd     = "inactivity.lastBuzzedBoutEnd"
    }

    // Defaults match SedentaryDetector.
    init() {
        enabled            = d.object(forKey: K.enabled) as? Bool ?? false
        thresholdMinutes   = d.object(forKey: K.threshold) as? Int ?? SedentaryDetector.defaultThresholdMinutes  // 45
        reNudgeMinutes     = d.object(forKey: K.reNudge) as? Int ?? SedentaryDetector.defaultReNudgeMinutes      // 30
        activeHoursEnabled = d.object(forKey: K.activeOn) as? Bool ?? true
        activeStartMinutes = d.object(forKey: K.activeStart) as? Int ?? SedentaryDetector.defaultActiveStartMin   // 09:00
        activeEndMinutes   = d.object(forKey: K.activeEnd) as? Int ?? SedentaryDetector.defaultActiveEndMin       // 17:00
        quietHoursEnabled  = d.object(forKey: K.quietOn) as? Bool ?? false
        quietStartMinutes  = d.object(forKey: K.quietStart) as? Int ?? SedentaryDetector.defaultQuietStartMin     // 22:00
        quietEndMinutes    = d.object(forKey: K.quietEnd) as? Int ?? SedentaryDetector.defaultQuietEndMin         // 07:00
    }

    // MARK: - Engine seams (UserDefaults-direct; safe to call off the BLE hook)
    //
    // These read/write the SAME keys as the @Published store above, so the BLE hook never has to reach
    // a @MainActor ObservableObject through the connection layer — it just reads defaults.

    /// Whether the feature toggle is on (cheap pre-check so the hook can bail before any DB read).
    static func isEnabled(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: K.enabled) as? Bool ?? false
    }

    /// Materialise the user knobs into the engine's `SedentaryConfig`. The feature toggle doubles as the
    /// notification master (Cénit has no separate one), and only-when-worn is always on (the caller
    /// passes the live `worn` flag). Detector tunables (move threshold / smoothing) keep the defaults.
    static func loadConfig(_ d: UserDefaults = .standard) -> SedentaryConfig {
        let on = d.object(forKey: K.enabled) as? Bool ?? false
        return SedentaryConfig(
            enabled: on,
            notificationsMasterOn: on,
            thresholdMinutes: d.object(forKey: K.threshold) as? Int ?? SedentaryDetector.defaultThresholdMinutes,
            reNudgeMinutes: d.object(forKey: K.reNudge) as? Int ?? SedentaryDetector.defaultReNudgeMinutes,
            activeHoursEnabled: d.object(forKey: K.activeOn) as? Bool ?? true,
            activeStartMinutes: d.object(forKey: K.activeStart) as? Int ?? SedentaryDetector.defaultActiveStartMin,
            activeEndMinutes: d.object(forKey: K.activeEnd) as? Int ?? SedentaryDetector.defaultActiveEndMin,
            quietHoursEnabled: d.object(forKey: K.quietOn) as? Bool ?? false,
            quietStartMinutes: d.object(forKey: K.quietStart) as? Int ?? SedentaryDetector.defaultQuietStartMin,
            quietEndMinutes: d.object(forKey: K.quietEnd) as? Int ?? SedentaryDetector.defaultQuietEndMin,
            onlyWhenWorn: true)
    }

    /// Rehydrate the persisted de-dup state (the LAST_* keys) the engine feeds back into `evaluate`.
    static func loadState(_ d: UserDefaults = .standard) -> SedentaryState {
        SedentaryState(
            lastProcessedGravityTs: d.object(forKey: K.lastProcessedTs) as? Int ?? 0,
            lastBuzzAt: d.object(forKey: K.lastBuzzAt) as? Int ?? 0,
            lastBuzzedBoutStart: d.object(forKey: K.lastBoutStart) as? Int ?? 0,
            lastBuzzedBoutEnd: d.object(forKey: K.lastBoutEnd) as? Int ?? 0)
    }

    /// Persist the engine's `nextState` so a relaunch can't re-buzz a replayed window.
    static func saveState(_ s: SedentaryState, to d: UserDefaults = .standard) {
        d.set(s.lastProcessedGravityTs, forKey: K.lastProcessedTs)
        d.set(s.lastBuzzAt, forKey: K.lastBuzzAt)
        d.set(s.lastBuzzedBoutStart, forKey: K.lastBoutStart)
        d.set(s.lastBuzzedBoutEnd, forKey: K.lastBoutEnd)
    }

    /// Local tz offset (seconds east of UTC) at `epochSec` — the engine evaluates active/quiet hours
    /// against the bout's local end time, so it needs the offset for that instant (DST-correct).
    static func tzOffsetSec(_ epochSec: Int) -> Int {
        TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }
}
