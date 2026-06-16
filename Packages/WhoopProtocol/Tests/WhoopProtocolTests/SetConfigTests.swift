import XCTest
@testable import WhoopProtocol

/// FER-156: prove NOOP builds `SET_CONFIG` (0x78) frames BYTE-FOR-BYTE identical to the official
/// WHOOP app, using the exact frames captured from the app's BLE handshake (HCI sysdiagnose,
/// 2026-06-16). If crc8/crc32/payload-layout match the wire, these pass.
final class SetConfigTests: XCTestCase {

    private func bytes(_ hex: String) -> [UInt8] {
        var out = [UInt8](); var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!); i = j
        }
        return out
    }

    /// Frame a COMMAND exactly as `WhoopCommand.frame` does (same envelope), so the test exercises the
    /// real crc8/crc32 path that the app uses: `[0xAA][len u16 LE][crc8(len)][type=35][seq][cmd][payload][crc32 LE]`.
    private func frame(seq: UInt8, cmd: UInt8, payload: [UInt8]) -> [UInt8] {
        let inner: [UInt8] = [35, seq, cmd] + payload
        let length = UInt16(inner.count + 4)
        let lenBytes: [UInt8] = [UInt8(length & 0xFF), UInt8(length >> 8)]
        let c = crc32(inner)
        let trailer: [UInt8] = [UInt8(c & 0xFF), UInt8((c >> 8) & 0xFF),
                                UInt8((c >> 16) & 0xFF), UInt8((c >> 24) & 0xFF)]
        return [0xAA] + lenBytes + [crc8(lenBytes)] + inner + trailer
    }

    // MARK: - Byte-for-byte parity vs the captured WHOOP frames

    func testParity_capsenseWearDetect() {
        let want = bytes("aa4800f323c77801656e61626c655f63617073656e73655f776561725f64657465637400000000003200000000000000000000000000000000000000000000000000000000000000924bc1e7")
        let got = frame(seq: 0xc7, cmd: 0x78, payload: SetConfig.payload(key: "enable_capsense_wear_detect", value: 0x32))
        XCTAssertEqual(got, want)
    }

    func testParity_writeR25Packets() {
        let want = bytes("aa4800f323c67801656e61626c655f77726974655f7232355f7061636b65747300000000000000003100000000000000000000000000000000000000000000000000000000000000bf5ae120")
        let got = frame(seq: 0xc6, cmd: 0x78, payload: SetConfig.payload(key: "enable_write_r25_packets", value: 0x31))
        XCTAssertEqual(got, want)
    }

    func testParity_r19Packets() {
        let want = bytes("aa4800f323bf7801656e61626c655f7231395f7061636b65747300000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000fe22011c")
        let got = frame(seq: 0xbf, cmd: 0x78, payload: SetConfig.payload(key: "enable_r19_packets", value: 0x32))
        XCTAssertEqual(got, want)
    }

    // MARK: - Payload shape

    func testPayloadLayout() {
        let p = SetConfig.payload(key: "enable_r19_packets", value: 0x32)
        XCTAssertEqual(p.count, SetConfig.payloadLength)       // 65
        XCTAssertEqual(p[0], 0x01)                             // sub-opcode
        XCTAssertEqual(Array(p[1..<19]), Array("enable_r19_packets".utf8))  // key at offset 1
        XCTAssertEqual(p[1 + SetConfig.keyFieldWidth], 0x32)   // value after 32-byte key field
        XCTAssertTrue(p[19..<(1 + SetConfig.keyFieldWidth)].allSatisfy { $0 == 0 })  // key null-pad
    }

    func testOfficialBurstIsTheElevenCapturedKeys() {
        XCTAssertEqual(SetConfig.officialBurst.count, 11)
        XCTAssertEqual(SetConfig.officialBurst.first?.key, "general_ab_test")
        XCTAssertEqual(SetConfig.officialBurst.last?.key, "enable_capsense_wear_detect")
        // every key fits the 32-byte field
        for c in SetConfig.officialBurst { XCTAssertLessThanOrEqual(c.key.utf8.count, SetConfig.keyFieldWidth) }
    }
}
