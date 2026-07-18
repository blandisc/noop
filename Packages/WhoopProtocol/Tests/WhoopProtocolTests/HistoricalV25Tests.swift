import XCTest
@testable import WhoopProtocol
import BiometricStreams

/// type-47 HISTORICAL_DATA **v25** — the WHOOP 4.0 layout (issue #30 / FER-690) that is structurally
/// incompatible with the v24 fallback. These are REAL v25 records (84 B, 1 Hz) captured from v1.92+ full
/// dumps. Before the explicit layout, the decoder fell back to v24 (gravity as f32 at the v24 offsets),
/// whose |g| landed nowhere near 1 g → the gate rejected it and NO gravity was stored, so the sleep
/// stager (which gates on gravity) lost actigraphy across v25 stretches. The explicit layout reads the
/// DSP gravity vector at @73/75/77 (3×i16 LE / 16384) and recovers motion + timestamp.
final class HistoricalV25Tests: XCTestCase {
    // Real WHOOP 4.0 v25 records (frame[4]==0x2f type-47, frame[5]==0x19 version 25).
    private let v25Hex = [
        "aa50000c2f190013390000140d2b6a4075010068a2010032fdbcfd98fdd3fdccfd47ffb00366064f073e06c103d3016cffa2fc87fa2ffae5fdbe03140675060c0510012dff1bfec0018f3c500500010068dc8f44",
        "aa50000c2f190014390000150d2b6a487001003ab301008dfd6afdaffda9fdaffd68fddbfb0dfc09fd77fe89fe62febffec9fe91ff0bff81ff5fff3e00d600790078ff3dff4bff801d553c5005010000d7c016b3",
        "aa50000c2f190015390000160d2b6a586b01006d8f0100a3ff94ffc4ffbcffbeff22004a009400cb0048005d006b004400d700130115013301f20088001d0031ffd9fe5eff75ff0048933c50050001008bdf2c2c",
    ]

    private func bytes(_ s: String) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(s.count / 2); var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!); i = j }
        return out
    }

    func testV25IsRecognizedAsVersion25() {
        let out = parseFrame(bytes(v25Hex[0]))
        XCTAssertTrue(out.ok)
        XCTAssertEqual(out.typeName, "HISTORICAL_DATA")
        XCTAssertEqual(out.parsed["hist_version"]?.intValue, 25)
    }

    func testV25DecodesUnixAndGravity() {
        for hex in v25Hex {
            let p = parseFrame(bytes(hex)).parsed
            XCTAssertEqual(p["hist_version"]?.intValue, 25)
            // Timestamp present (real unix seconds @11).
            let unix = p["unix"]?.intValue
            XCTAssertNotNil(unix, "v25 must decode its own unix timestamp")
            XCTAssertGreaterThan(unix ?? 0, MIN_PLAUSIBLE_UNIX, "unix should be a plausible recent time")
            // Gravity present, and a real DSP orientation vector is ~1 g.
            guard let gx = p["gravity_x"]?.doubleValue,
                  let gy = p["gravity_y"]?.doubleValue,
                  let gz = p["gravity_z"]?.doubleValue else {
                return XCTFail("v25 must decode a gravity vector (motion for the sleep stager)")
            }
            let mag = (gx * gx + gy * gy + gz * gz).squareRoot()
            XCTAssertTrue((0.5...1.5).contains(mag), "|gravity| ≈ 1 g on a real record, got \(mag)")
        }
    }

    /// The whole point (FER-690): v25 records flow through extractHistoricalStreams into gravity rows the
    /// sleep stager can use — where the v24 fallback previously produced zero gravity.
    func testV25ExtractsGravityRows() {
        let parsed = v25Hex.map { parseFrame(bytes($0)) }
        let streams = extractHistoricalStreams(parsed, deviceClockRef: 0, wallClockRef: 0)
        XCTAssertEqual(streams.gravity.count, v25Hex.count,
                       "every v25 record should yield a gravity sample for actigraphy")
    }

    /// v25 stores no per-second HR (it's PPG-derived) — so the decode yields motion WITHOUT a bogus HR,
    /// rather than a garbage HR from misreading the v24 offsets.
    func testV25HasNoSpuriousHeartRate() {
        let p = parseFrame(bytes(v25Hex[0])).parsed
        XCTAssertNil(p["heart_rate"]?.intValue, "v25 carries no per-second HR; none should be invented")
    }
}
