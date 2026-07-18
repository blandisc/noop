import XCTest
import WhoopProtocol
import BiometricStreams

/// Pins the standard BLE Heart Rate Measurement (0x2A37) parser after its move into WhoopProtocol
/// (FER-756). Layout per the Bluetooth GATT spec: flags byte, then 8- or 16-bit HR (flag bit 0),
/// optional Energy Expended u16 (bit 3), optional R-R u16 words in 1/1024 s (bit 4).
final class StandardHeartRateTests: XCTestCase {

    func testEightBitHeartRate() {
        let m = StandardHeartRate.parse([0x00, 72])
        XCTAssertEqual(m?.hr, 72)
        XCTAssertEqual(m?.rr, [])
    }

    func testSixteenBitHeartRate() {
        // flags bit 0 set → HR is u16 LE: 0x0120 = 288.
        let m = StandardHeartRate.parse([0x01, 0x20, 0x01])
        XCTAssertEqual(m?.hr, 288)
    }

    func testRRIntervalsConvertFrom1024thsToMs() {
        // flags bit 4 set → two R-R words: 1024/1024 s = 1000 ms; 512/1024 s = 500 ms.
        let m = StandardHeartRate.parse([0x10, 60, 0x00, 0x04, 0x00, 0x02])
        XCTAssertEqual(m?.hr, 60)
        XCTAssertEqual(m?.rr, [1000, 500])
    }

    func testEnergyExpendedIsSkippedBeforeRR() {
        // flags bits 3+4 set → 2 EE bytes are skipped, then one R-R word (2048/1024 s = 2000 ms).
        let m = StandardHeartRate.parse([0x18, 55, 0xAA, 0xBB, 0x00, 0x08])
        XCTAssertEqual(m?.hr, 55)
        XCTAssertEqual(m?.rr, [2000])
    }

    func testTruncatedOrEmptyReturnsNil() {
        XCTAssertNil(StandardHeartRate.parse([]))
        XCTAssertNil(StandardHeartRate.parse([0x00]))          // flags only, no HR byte
        XCTAssertNil(StandardHeartRate.parse([0x01, 0x20]))    // 16-bit HR missing its high byte
    }
}
