import XCTest
import WhoopProtocol

/// GOLDEN test for the SET_CLOCK(10) payload (FER-756). The expected bytes are computed BY HAND from
/// the old `BLEManager.setClockPayload` logic — 8 bytes: [seconds u32 LE][subseconds u32 LE = 0] —
/// so any drift in the outbound byte layout after the move to WhoopProtocol fails here. A wrong-length
/// or wrong-order SET_CLOCK is ack-received but NOT latched by the strap (RTC stays lost, no type-47).
final class SetClockTests: XCTestCase {

    /// 1_700_000_000 = 0x6553_F100. Little-endian: 00 F1 53 65, then 4 zero subsecond bytes.
    func testGoldenKnownTimestamp() {
        XCTAssertEqual(SetClock.payload(now: 1_700_000_000),
                       [0x00, 0xF1, 0x53, 0x65, 0x00, 0x00, 0x00, 0x00])
    }

    /// 1_750_123_456 = 0x6850_C3C0. Little-endian: C0 C3 50 68, then 4 zero subsecond bytes.
    func testGoldenSecondTimestamp() {
        XCTAssertEqual(SetClock.payload(now: 1_750_123_456),
                       [0xC0, 0xC3, 0x50, 0x68, 0x00, 0x00, 0x00, 0x00])
    }

    /// Edge values: all-zero and all-ones seconds still produce exactly 8 bytes with zero subseconds.
    func testGoldenEdges() {
        XCTAssertEqual(SetClock.payload(now: 0),
                       [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(SetClock.payload(now: 0xFFFF_FFFF),
                       [0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00])
    }
}
