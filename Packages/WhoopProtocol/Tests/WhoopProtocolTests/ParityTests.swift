import XCTest
@testable import WhoopProtocol
import BiometricStreams

/// Decodes only the subset of the golden parse_frame dict that the parity guard checks.
private struct GoldenEntry: Decodable {
    let type_name: String
    let seq: Int?
    let crc_ok: Bool?
    let cmd_name: String?
    let parsed: [String: ParsedValue]
}

private struct FrameEntry: Decodable {
    let hex: String
}

final class ParityTests: XCTestCase {
    private func resourceURL(_ name: String, _ ext: String) throws -> URL {
        let url = Bundle.module.url(forResource: name, withExtension: ext)
        return try XCTUnwrap(url, "missing test resource \(name).\(ext) — run scripts/gen_golden.py")
    }

    private func hexToBytes(_ s: String) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            out.append(UInt8(s[idx..<next], radix: 16)!)
            idx = next
        }
        return out
    }

    func testSwiftMatchesPythonGolden() throws {
        let framesData = try Data(contentsOf: resourceURL("frames", "json"))
        let goldenData = try Data(contentsOf: resourceURL("golden", "json"))
        let frames = try JSONDecoder().decode([FrameEntry].self, from: framesData)
        let golden = try JSONDecoder().decode([GoldenEntry].self, from: goldenData)

        XCTAssertEqual(frames.count, golden.count, "frames.json and golden.json length mismatch")
        XCTAssertGreaterThan(frames.count, 0, "no parity frames loaded")

        for (i, frameEntry) in frames.enumerated() {
            let g = golden[i]
            let out = parseFrame(hexToBytes(frameEntry.hex))
            XCTAssertEqual(out.typeName, g.type_name, "type_name mismatch at #\(i)")
            XCTAssertEqual(out.seq, g.seq, "seq mismatch at #\(i) (\(g.type_name))")
            XCTAssertEqual(out.crcOK, g.crc_ok, "crc_ok mismatch at #\(i) (\(g.type_name))")
            XCTAssertEqual(out.cmdName, g.cmd_name, "cmd_name mismatch at #\(i) (\(g.type_name))")
            // The core no-drift contract: the parsed dict must match exactly.
            XCTAssertEqual(out.parsed, g.parsed,
                           "parsed mismatch at #\(i) (\(g.type_name))\n  swift: \(out.parsed)\n  python: \(g.parsed)")
        }
    }

    func testEveryCorePacketTypeCovered() throws {
        let goldenData = try Data(contentsOf: resourceURL("golden", "json"))
        let golden = try JSONDecoder().decode([GoldenEntry].self, from: goldenData)
        let types = Set(golden.map { $0.type_name })
        for expected in ["REALTIME_DATA", "COMMAND_RESPONSE", "EVENT", "METADATA",
                         "CONSOLE_LOGS", "REALTIME_RAW_DATA"] {
            XCTAssertTrue(types.contains(expected), "parity fixture missing \(expected)")
        }
    }
}
