import XCTest
@testable import WhoopProtocol

final class ReassemblerTests: XCTestCase {
    // Build a real ~1928-byte type-43 frame from a 1917-byte synthetic payload so the
    // test is self-contained (no capture dependency): inner = 1917+3, length = 1924,
    // total = 1928. Reassembly must reproduce it exactly from 244-byte fragments.
    private func bigFrame() -> [UInt8] {
        let payload = (0..<1917).map { UInt8($0 & 0xFF) }
        return frameFromPayload(payload, type: 43, seq: 7, cmd: 0)
    }

    func testReassembleFromFragments() {
        let frame = bigFrame()
        XCTAssertEqual(frame.count, 1928)
        var fragments: [[UInt8]] = []
        var i = 0
        while i < frame.count {
            fragments.append(Array(frame[i..<min(i + 244, frame.count)]))
            i += 244
        }
        XCTAssertEqual(fragments.count, 8)
        // Only the first fragment carries the 0xAA SOF.
        XCTAssertEqual(fragments[0].first, 0xAA)
        for f in fragments.dropFirst() {
            XCTAssertNotEqual(f.first, 0xAA)
        }
        let r = Reassembler()
        var assembled: [[UInt8]] = []
        for f in fragments {
            assembled.append(contentsOf: r.feed(f))
        }
        XCTAssertEqual(assembled.count, 1)
        XCTAssertEqual(assembled[0], frame)
    }

    func testTwoFramesInOneFeed() {
        let a = frameFromPayload([0x01, 0x02], type: 40)
        let b = frameFromPayload([0x03, 0x04], type: 48)
        let r = Reassembler()
        let out = r.feed(a + b)
        XCTAssertEqual(out, [a, b])
    }

    func testLeadingGarbageIsSkipped() {
        let a = frameFromPayload([0x09], type: 40)
        let r = Reassembler()
        let out = r.feed([0x11, 0x22, 0x33] + a)
        XCTAssertEqual(out, [a])
    }

    func testPartialFrameWaitsForRest() {
        let a = frameFromPayload([0x01, 0x02, 0x03, 0x04], type: 40)
        let r = Reassembler()
        XCTAssertTrue(r.feed(Array(a[0..<5])).isEmpty)        // header + part
        XCTAssertEqual(r.feed(Array(a[5..<a.count])), [a])    // remainder completes it
    }

    // MARK: - maxFrameBytes guard (FER-694, reimpl. of PR #374)

    func testImpossibleLengthResyncsToNextFrame() {
        // A garbage SOF declaring 0xFFFF bytes must be dropped, not waited on forever.
        let junk: [UInt8] = [0xAA, 0xFF, 0xFF, 0x00]
        let a = frameFromPayload([0x05, 0x06], type: 40)
        let r = Reassembler()
        XCTAssertEqual(r.feed(junk + a), [a])
    }

    func testImpossibleLengthWhoop5Resyncs() {
        let junk: [UInt8] = [0xAA, 0x01, 0xFF, 0xFF]
        let f = puffinCommandFrame(cmd: 0x10, seq: 1)
        let r = Reassembler(family: .whoop5)
        XCTAssertEqual(r.feed(junk + f), [f])
    }

    func testImpossibleLengthAloneLeavesStreamAlive() {
        let r = Reassembler()
        XCTAssertTrue(r.feed([0xAA, 0xFF, 0xFF, 0x00]).isEmpty)
        // Stream keeps working afterwards.
        let a = frameFromPayload([0x01], type: 40)
        XCTAssertEqual(r.feed(a), [a])
    }

    func testMaxSizedFrameStillPasses() {
        // A frame exactly at the cap must still assemble (guard is strictly greater-than).
        let payload = (0..<(Reassembler.maxFrameBytes - 11)).map { UInt8($0 & 0xFF) }
        let f = frameFromPayload(payload, type: 43)
        XCTAssertEqual(f.count, Reassembler.maxFrameBytes)
        let r = Reassembler()
        XCTAssertEqual(r.feed(f), [f])
    }

    func testValidFramesByteIdenticalWithGuardInPlace() {
        // Golden: same fragment-fed big frame as testReassembleFromFragments, unchanged.
        let frame = bigFrame()
        let r = Reassembler()
        var assembled: [[UInt8]] = []
        var i = 0
        while i < frame.count {
            assembled.append(contentsOf: r.feed(Array(frame[i..<min(i + 244, frame.count)])))
            i += 244
        }
        XCTAssertEqual(assembled, [frame])
    }
}
