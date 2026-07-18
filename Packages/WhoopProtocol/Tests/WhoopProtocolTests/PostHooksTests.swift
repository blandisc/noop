import XCTest
@testable import WhoopProtocol
import BiometricStreams

final class PostHooksTests: XCTestCase {
    static func hex(_ s: String) -> [UInt8] { FramingTests.hex(s) }

    func testRealtimeDataRRIntervalsEmpty() {
        let frame = Self.hex("aa1800ff28020f3de10128663c0000000000000000000000da855212")
        let out = parseFrame(frame)
        XCTAssertEqual(out.parsed["rr_intervals"], .intArray([]))
    }

    func testEventDoesNotSetBatteryForNonBatteryEvent() {
        // EVENT(48) RAW_DATA_COLLECTION_ON(46): event hook is a no-op for battery.
        let frame = Self.hex("aa0c00fc30262e0019d67e67e0155bb7")
        let out = parseFrame(frame)
        XCTAssertEqual(out.parsed["event"], .string("RAW_DATA_COLLECTION_ON(46)"))
        XCTAssertEqual(out.parsed["event_timestamp"], .int(1736365593))
        XCTAssertNil(out.parsed["battery_mV?"])
    }

    func testCommandResponseBattery() {
        let frame = Self.hex("aa10005724241a0000ff000000000000ac811df4")
        let out = parseFrame(frame)
        XCTAssertEqual(out.parsed["battery_pct"], .double(25.5))
        XCTAssertEqual(out.parsed["response payload"], .string("[9 bytes]"))
    }

    func testMetadataHistoryStart() {
        let frame = Self.hex("aa150016312c01223de101c019060000000600000097ef649b")
        let out = parseFrame(frame)
        XCTAssertEqual(out.parsed["meta_type"], .string("HISTORY_START(1)"))
        XCTAssertEqual(out.parsed["unix"], .int(31538466))
        XCTAssertEqual(out.parsed["subsec"], .int(6592))
        XCTAssertEqual(out.parsed["unk0"], .int(6))
        XCTAssertEqual(out.parsed["trim_cursor"], .int(6))
    }

    func testConsoleLogs() {
        let frame = Self.hex("aa3700923202000000000053594e54483a20424c453a20486973746f727920627572737420737563636573732e205472696d3a206f6b009f454893")
        let out = parseFrame(frame)
        XCTAssertEqual(out.typeName, "CONSOLE_LOGS")
        // The full log text (UTF-8, invalid bytes replaced) ends with the trailer text.
        XCTAssertEqual(out.parsed["log"]?.stringValue?.contains("BLE: History burst success. Trim:"), true)
        // The region value (cat "text") also lands in parsed.
        XCTAssertEqual(out.parsed["console log text"], .string("[48 bytes]"))
    }

    func testCommandResponseReportVersionInfo() {
        // Synthetic REPORT_VERSION_INFO (cmd 7) with a 37-byte payload (>=35, unpacked whole).
        // pay = [B0, B1, B2, LE32(1), LE32(2), LE32(3), LE32(4), LE32(5), LE32(6), LE32(7), LE32(8)]
        // struct '<BBBLLLLLLLL' unpacks: u[3..6] = fw_harvard, u[7..10] = fw_boylston
        var pay: [UInt8] = [0x0a, 0x01]                 // 2-byte response header (B[0], B[1])
        pay += [0x00]                                    // B[2]
        // fw_harvard = 1.2.3.4 (u[3]=1, u[4]=2, u[5]=3, u[6]=4 via LE u32 at pay[3..18])
        for v in [UInt32(1), 2, 3, 4] {
            let le: [UInt8] = [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                               UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
            pay += le
        }
        // fw_boylston = 5.6.7.8 (u[7]=5, u[8]=6, u[9]=7, u[10]=8 via LE u32 at pay[19..34])
        for v in [UInt32(5), 6, 7, 8] {
            let le: [UInt8] = [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                               UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
            pay += le
        }
        // pay length now = 3 + 16 + 16 = 35 (>=35), struct unpacks correctly.
        let frame = frameFromPayload(pay, type: 36, seq: 1, cmd: 7)
        let out = parseFrame(frame)
        XCTAssertEqual(out.cmdName, "REPORT_VERSION_INFO(7)")
        XCTAssertEqual(out.parsed["fw_harvard"], .string("1.2.3.4"))
        XCTAssertEqual(out.parsed["fw_boylston"], .string("5.6.7.8"))
    }

    func testCommandResponseGetClock() {
        // GET_CLOCK (cmd 11): clock = pay[2:6] u32.
        var pay: [UInt8] = [0x0a, 0x01]
        let clock: UInt32 = 1_700_000_000
        pay += [UInt8(clock & 0xFF), UInt8((clock >> 8) & 0xFF),
                UInt8((clock >> 16) & 0xFF), UInt8((clock >> 24) & 0xFF)]
        let frame = frameFromPayload(pay, type: 36, seq: 1, cmd: 11)
        let out = parseFrame(frame)
        XCTAssertEqual(out.parsed["clock"], .int(1_700_000_000))
    }

    func testCommandResponseGetDataRange() {
        // GET_DATA_RANGE (cmd 34): two unix-range u32s embedded in the payload.
        var pay: [UInt8] = [0x0a, 0x01, 0x00]  // 3-byte prefix (scan starts at o=3)
        let oldest: UInt32 = 1_700_000_000
        let newest: UInt32 = 1_700_086_400
        for v in [oldest, newest] {
            pay += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        pay += [0x00, 0x00, 0x00] // trailing pad (scan stops 3 before end)
        let frame = frameFromPayload(pay, type: 36, seq: 1, cmd: 34)
        let out = parseFrame(frame)
        XCTAssertEqual(out.parsed["history_oldest"], .string("2023-11-14 22:13 UTC"))
        XCTAssertEqual(out.parsed["history_newest"], .string("2023-11-15 22:13 UTC"))
    }
}
