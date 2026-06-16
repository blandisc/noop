import Foundation

/// Pure decision: from one historical offload's signals (frame-type tallies + a couple of BLE-event
/// hints), assess whether the WHOOP 4.0's RTC is likely lost — i.e. the strap is NOT persisting
/// biometry to flash because its clock is invalid — WITHOUT relying on `GET_CLOCK` (this firmware
/// never answers it) and WITHOUT trusting `GET_DATA_RANGE` alone (its plausible-unix scan is noisy;
/// see FER-150). No CoreBluetooth, no I/O — fully unit-testable.
///
/// Background (FER-93): an un-clocked 4.0 logs "RTC timestamp … is invalid; not saving data to
/// flash" and its offload returns CONSOLE_LOGS (type 50) with ZERO biometric records (type 47). The
/// volatile RTC resets on power loss (battery-pack removal). The reliable *success* signal is
/// "biometric (type-47) frames > 0"; the reliable *loss* signals are the firmware's own log text, the
/// narrating-not-saving offload shape, an implausible retained-range, or a recent power loss with no
/// biometry since. This policy turns those into a verdict the BLE layer can act on (re-assert
/// SET_CLOCK) and the sync diagnostic can phrase honestly (FER-152) — none of which need GET_CLOCK.
///
/// Plain-typed on purpose (no protocol/CoreBluetooth types in its surface) so it stays trivially
/// testable here and relocatable to the planned orchestration package (FER-101) without churn.
public enum RtcHealthPolicy {

    /// What one offload + recent link history told us.
    public struct Signals: Equatable, Sendable {
        /// type-47 HISTORICAL_DATA frames decoded in the latest offload — the band IS saving.
        public var biometricFrames: Int
        /// type-50 CONSOLE_LOGS frames in the latest offload — the band narrating, not serving history.
        public var consoleLogFrames: Int
        /// A CONSOLE_LOGS / ERROR line reported the RTC invalid / "not saving data to flash".
        public var consoleLogReportsRtcInvalid: Bool
        /// `GET_DATA_RANGE` returned a plausible, recent, non-collapsed window (validated by the
        /// caller — see FER-150). False when it's empty, in the future, or a single-point garbage read.
        public var dataRangeWindowPlausible: Bool
        /// A recent power-loss hint (BATTERY_PACK_REMOVED / CHARGING_OFF) — the volatile RTC may have
        /// reset since, so the clock should be re-asserted even before the next offload proves it.
        public var recentPowerLoss: Bool

        public init(biometricFrames: Int = 0,
                    consoleLogFrames: Int = 0,
                    consoleLogReportsRtcInvalid: Bool = false,
                    dataRangeWindowPlausible: Bool = true,
                    recentPowerLoss: Bool = false) {
            self.biometricFrames = biometricFrames
            self.consoleLogFrames = consoleLogFrames
            self.consoleLogReportsRtcInvalid = consoleLogReportsRtcInvalid
            self.dataRangeWindowPlausible = dataRangeWindowPlausible
            self.recentPowerLoss = recentPowerLoss
        }
    }

    public struct Verdict: Equatable, Sendable {
        /// The strap is persisting biometry (type-47 flowing) — its clock is fine.
        public var savingHealthy: Bool
        /// The strap's RTC is probably invalid and it isn't saving to flash.
        public var rtcLikelyLost: Bool
        /// NOOP should (re-)send SET_CLOCK now. The caller throttles re-sends.
        public var shouldReassertClock: Bool
    }

    /// Assess one offload. `savingHealthy` wins: any real biometry means the clock is fine *now*, so
    /// we never flag "lost" while type-47 is flowing (a stale RTC-invalid log replayed in the same
    /// offload must not override live evidence of saving). "Lost" requires a POSITIVE signal — the
    /// firmware's own RTC-invalid log, a narrating-not-saving offload (logs but zero biometry), an
    /// implausible retained-range, or a recent power loss with nothing saved since — NOT merely
    /// "0 biometric frames", which also means "nothing new / caught up".
    public static func assess(_ s: Signals) -> Verdict {
        let saving = s.biometricFrames > 0
        let narratingNotSaving = !saving && s.consoleLogFrames > 0
        let lost = !saving && (
            s.consoleLogReportsRtcInvalid
            || narratingNotSaving
            || !s.dataRangeWindowPlausible
            || s.recentPowerLoss
        )
        return Verdict(savingHealthy: saving,
                       rtcLikelyLost: lost,
                       shouldReassertClock: lost)
    }
}
