import XCTest
@testable import NOOP

/// Pins the strap-log PII redaction (FER-127): a publicly shared strap log must lose the owner's BLE
/// MAC, the WHOOP serial (carried in the device name, tied to the account), and the per-install
/// CoreBluetooth peripheral UUID — while KEEPING the public standard-BLE and WHOOP-vendor service
/// UUIDs that make a shared GATT log useful. The redaction lives at the single log sink
/// (`LiveState.append(log:)`), so this also pins that every line through the sink is scrubbed.
@MainActor
final class RedactPiiTests: XCTestCase {

    // MARK: - MAC addresses → first + last byte only

    func testMasksBleMacToFirstAndLastByte() {
        XCTAssertEqual(LiveState.redactPii("Connected to AB:CD:EF:12:34:56"),
                       "Connected to AB:••:••:••:••:56")
    }

    func testMaskingLeavesNonMacHexPayloadsUntouched() {
        // Command payloads are space/none-separated hex, not colon-separated → not MAC-shaped → kept.
        let s = "TX cmd 1a 2b 3c 4d 5e 6f"
        XCTAssertEqual(LiveState.redactPii(s), s)
    }

    // MARK: - WHOOP serial in the device name → removed; model names kept

    func testRemovesWhoopSerialFromDeviceName() {
        XCTAssertEqual(LiveState.redactPii("Discovered WHOOP 4C1594026"),
                       "Discovered WHOOP <serial>")
    }

    func testKeepsModelNames() {
        XCTAssertEqual(LiveState.redactPii("WHOOP 4.0"), "WHOOP 4.0")
        XCTAssertEqual(LiveState.redactPii("WHOOP 5.0"), "WHOOP 5.0")
    }

    // MARK: - Peripheral UUID masked; public service UUIDs preserved

    func testMasksPeripheralUuid() {
        XCTAssertEqual(LiveState.redactPii("Discovered peripheral (E621E1F8-C36C-495A-93FC-0C247A3E6E5F)"),
                       "Discovered peripheral (<device>)")
    }

    func testKeepsStandardBleServiceUuid() {
        // 0x2A37 Heart Rate Measurement on the standard-BLE base — public, must survive untouched.
        let s = "char 00002a37-0000-1000-8000-00805f9b34fb notify"
        XCTAssertEqual(LiveState.redactPii(s), s)
    }

    func testKeepsWhoopVendorServiceUuid() {
        let s = "service 61080001-8d6d-82b8-614a-1c8cb0f8dcc6 discovered"
        XCTAssertEqual(LiveState.redactPii(s), s)
    }

    // MARK: - The sink itself redacts (the actual privacy guarantee)

    func testAppendRedactsThroughTheSink() {
        let st = LiveState()
        st.append(log: "Discovered WHOOP 4C1594026 at AB:CD:EF:12:34:56")
        XCTAssertEqual(st.log.last, "Discovered WHOOP <serial> at AB:••:••:••:••:56")
    }
}
