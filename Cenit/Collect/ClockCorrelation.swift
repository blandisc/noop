import Foundation
import WhoopProtocol
import WhoopStore

/// Pure helper: correlate the strap's monotonic device clock to wall time.
/// REALTIME_DATA timestamps are a device monotonic epoch; the server/app maps them to
/// unix time using the (device, wall) pair captured at connect via GET_CLOCK + now.
/// No CoreBluetooth, no I/O — fully unit-testable.
enum ClockCorrelation {
    /// Build a `ClockRef` from a decoded GET_CLOCK COMMAND_RESPONSE frame and the wall
    /// time observed when the response arrived. Returns nil unless the frame parsed OK,
    /// passed CRC, and carries a `clock` value.
    static func clockRef(from parsed: ParsedFrame, wall: Int) -> ClockRef? {
        guard parsed.ok, parsed.crcOK != false,
              let device = parsed.parsed["clock"]?.intValue else { return nil }
        return ClockRef(device: device, wall: wall)
    }
}
