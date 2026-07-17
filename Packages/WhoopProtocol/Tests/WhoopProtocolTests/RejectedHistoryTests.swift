import XCTest
@testable import WhoopProtocol

/// Tests for `rejectedHistoricalRecords` (FER-693, #77 / #91). It returns the HISTORICAL_DATA (type-47)
/// record frames that would otherwise be silently dropped (CRC failure or an unmapped layout), so the
/// Backfiller can archive them BEFORE acking the trim. Frames that decode cleanly, console (type-50)
/// frames, and 5/MG v26 PPG blocks must NOT be returned.
final class RejectedHistoryTests: XCTestCase {

    private func bytes(_ s: String) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(s.count / 2); var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!); i = j }
        return out
    }

    // A synthetic WHOOP 4.0 V24 type-47 record (HR=63) that decodes cleanly (from HistoricalV24Tests).
    private let v24Hex =
        "aa5a008e2f18000000000000f153650000000000003f0152030000000000000000dc053075" +
        "000000cdcc4c3dcdcccc3d5a657e3f00000040cdcc4c3dcdcccc3d5a657e3f504668428403" +
        "200364006400b80bb80b000000000000c25c1a88"

    // A real WHOOP 5/MG type-47 v18 record (HR present, decodes cleanly; from Whoop5HistoricalTests).
    private let whoop5V18Hex =
        "aa01740001003fb12f1280733d8401b69f266a66460066025a0265020000000000007b0a8d656463ff0012163cf6a439bf2924fd3ed763fe3e3200aa000000000000000000f7000901f10b0007010c020c00000000000000000000000000000000000000000000000100656f1e1e0000009d61a7c00000003e862817"

    // A real WHOOP 5/MG type-47 v26 record — the high-rate PPG waveform buffer stored by design.
    private let whoop5V26Hex =
        "aa015000010035412f1a80ad418401f0a3266aae470100c3c5050068faccfa8dfb46fc8bfd4cfebafedafe6dff56ffd5fffbff37ff6afce5f9d7f8dffa5efc98fddbfe5afe84fe15ff5cff405fb33c50080101006cb67c17"

    // MARK: - clean records are NOT rejected

    func testDecodableWhoop4RecordNotRejected() {
        XCTAssertTrue(rejectedHistoricalRecords([bytes(v24Hex)], family: .whoop4).isEmpty,
                      "a cleanly-decoding type-47 record must not be flagged as lost")
    }

    func testDecodableWhoop5RecordNotRejected() {
        XCTAssertTrue(rejectedHistoricalRecords([bytes(whoop5V18Hex)], family: .whoop5).isEmpty)
    }

    // MARK: - undecodable records ARE rejected

    func testCRCCorruptWhoop4RecordIsRejected() {
        // Flip a payload byte so the CRC32 trailer mismatches (crcOK == false) but the type byte is
        // still 47 — exactly the silent-loss case the guard exists to catch.
        var bad = bytes(v24Hex)
        bad[10] ^= 0xFF
        let f = parseFrame(bad)
        XCTAssertEqual(f.crcOK, false, "precondition: the corrupted frame must fail CRC")
        XCTAssertEqual(rejectedHistoricalRecords([bad], family: .whoop4), [bad])
    }

    func testCRCCorruptWhoop5RecordIsRejected() {
        var bad = bytes(whoop5V18Hex)
        bad[20] ^= 0xFF                    // corrupt a biometric payload byte (type byte @8 untouched)
        XCTAssertEqual(bad[8], 47)         // still a HISTORICAL_DATA record
        XCTAssertEqual(rejectedHistoricalRecords([bad], family: .whoop5), [bad])
    }

    // MARK: - by-design skips are NEVER rejected

    func testConsoleFrameExcluded() {
        // type-50 CONSOLE_LOGS is strap-side debug text — decodes to zero rows by design, never lost.
        let console = frameFromPayload([0x01, 0x02, 0x03, 0x04], type: 50, seq: 0, cmd: 0)
        XCTAssertEqual(console[4], 50)
        XCTAssertTrue(rejectedHistoricalRecords([console], family: .whoop4).isEmpty)
    }

    func testWhoop5V26PpgExcluded() {
        let v26 = bytes(whoop5V26Hex)
        XCTAssertEqual(v26[8], 47)         // it IS a type-47 record…
        XCTAssertEqual(v26[9], 26)         // …but version 26 (PPG), skipped by design — not lost data
        XCTAssertTrue(rejectedHistoricalRecords([v26], family: .whoop5).isEmpty)
    }

    func testNonHistoricalFrameExcluded() {
        // A REALTIME_DATA (type-40) frame is live, not offload — never a history-loss candidate.
        let realtime = frameFromPayload([0x01, 0x02, 0x03], type: 40, seq: 0, cmd: 0)
        XCTAssertTrue(rejectedHistoricalRecords([realtime], family: .whoop4).isEmpty)
    }

    func testTooShortFrameExcluded() {
        XCTAssertTrue(rejectedHistoricalRecords([[0xAA, 0x01]], family: .whoop4).isEmpty)
        XCTAssertTrue(rejectedHistoricalRecords([[]], family: .whoop5).isEmpty)
    }

    // MARK: - mixed batch returns only the genuine losses, in order

    func testMixedBatchReturnsOnlyRejects() {
        var bad = bytes(v24Hex); bad[10] ^= 0xFF   // undecodable
        let good = bytes(v24Hex)                   // clean
        let console = frameFromPayload([0x00], type: 50, seq: 0, cmd: 0)
        XCTAssertEqual(rejectedHistoricalRecords([good, bad, console], family: .whoop4), [bad])
    }

    // MARK: - FER-971 (C-01): the pair overload is decision-identical to the byte form

    /// The full corpus of this file, through BOTH families and BOTH parse modes: handing the
    /// function pre-parsed (raw, ParsedFrame) pairs must reject exactly the same frames as the
    /// bytes-only form — with pairs built `annotate: false` (the hot path's parse) AND
    /// `annotate: true` (proving the decision never depended on annotation fields).
    func testPairOverloadMatchesByteForm() {
        var corruptV24 = bytes(v24Hex); corruptV24[10] ^= 0xFF
        var corruptV18 = bytes(whoop5V18Hex); corruptV18[20] ^= 0xFF
        let corpus: [[UInt8]] = [
            bytes(v24Hex), corruptV24, bytes(whoop5V18Hex), corruptV18, bytes(whoop5V26Hex),
            frameFromPayload([0x01, 0x02], type: 50, seq: 0, cmd: 0),
            frameFromPayload([0x01, 0x02], type: 40, seq: 0, cmd: 0),
            [0xAA, 0x01], [],
        ]
        for family in [DeviceFamily.whoop4, .whoop5] {
            let byByte = rejectedHistoricalRecords(corpus, family: family)
            for annotate in [false, true] {
                let pairs = corpus.map { ($0, parseFrame($0, family: family, annotate: annotate)) }
                XCTAssertEqual(rejectedHistoricalRecords(pairs, family: family), byByte,
                               "family=\(family) annotate=\(annotate)")
            }
        }
    }

    /// The raw-byte gates stay load-bearing on the pair path: a pair whose parse LOOKS undecodable
    /// but whose bytes are not type-47 is never rejected, and a 5/MG v26 stays skipped even when
    /// its parse fails — the byte gates win over the parse.
    func testPairOverloadKeepsByteGates() {
        // A realtime (type-40) frame paired with a deliberately-broken parse: not type-47 → kept out.
        let realtime = frameFromPayload([0x01, 0x02, 0x03], type: 40, seq: 0, cmd: 0)
        var broken = realtime; broken[broken.count - 1] ^= 0xFF
        let mismatchedParse = parseFrame(broken, family: .whoop4, annotate: false)
        XCTAssertTrue(rejectedHistoricalRecords([(realtime, mismatchedParse)], family: .whoop4).isEmpty,
                      "a non-47 frame must never be rejected, whatever its parse says")
        // A v26 PPG block with a corrupted trailer (parse fails): still skipped by design.
        var v26bad = bytes(whoop5V26Hex); v26bad[v26bad.count - 1] ^= 0xFF
        let p = parseFrame(v26bad, family: .whoop5, annotate: false)
        XCTAssertTrue(rejectedHistoricalRecords([(v26bad, p)], family: .whoop5).isEmpty,
                      "the v26 byte-gate wins over a failed parse")
    }
}
