import XCTest
import WhoopProtocol
import BiometricStreams
@testable import Cenit

/// Thread-safe parse counter. `ParseInstrumentation.onParse` is `@Sendable`, so it can't close over a
/// plain captured `var`; a small locked reference type satisfies the concurrency checker.
private final class ParseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// Pins **parse-once** on the BLE delegate hot path (FER-183): each complete frame must be parsed
/// EXACTLY ONCE and the resulting `ParsedFrame` reused by the live router, the GET_CLOCK read, the
/// clock-correlation and the live-gesture gate — previously the same bytes were parsed up to 3× per
/// frame on the main thread under the continuous ~2/s live flow. Verified through the
/// `ParseInstrumentation.onParse` seam (fires once per real `parseFrame`).
@MainActor
final class ParseOnceTests: XCTestCase {

    /// Arbitrary frames — only the parse COUNT matters here, so frame validity is irrelevant:
    /// `parseFrame` fires `onParse` before any content/CRC checks, so every byte array counts as
    /// exactly one parse.
    private let frames: [[UInt8]] = [
        [0xAA, 0x10, 0x00, 0x00, 0x28, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05],
        [0xAA, 0x0C, 0x00, 0x00, 0x30, 0x01, 0x06, 0x00, 0x11, 0x22, 0x33, 0x44],
        [0xAA, 0x08, 0x00, 0x00, 0x23, 0x02, 0x0E, 0x00, 0x55, 0x66, 0x77, 0x88],
    ]

    override func tearDown() {
        ParseInstrumentation.onParse = nil   // never leak the hook into another test
        super.tearDown()
    }

    /// The reuse overloads must NOT re-parse: handing them an already-parsed frame parses zero times.
    func testParsedOverloadsNeverReparse() {
        let router = FrameRouter(state: LiveState())
        let parsed = parseFrame(frames[0], family: .whoop4)   // the single, intentional parse

        let counter = ParseCounter()
        ParseInstrumentation.onParse = { counter.increment() }
        router.handle(parsed: parsed)
        router.dispatchLiveGestureIfFresh(parsed: parsed)
        XCTAssertEqual(counter.count, 0,
                       "handle(parsed:) / dispatchLiveGestureIfFresh(parsed:) must reuse the ParsedFrame, never re-parse")
    }

    /// Mirrors the delegate loop: parse ONCE per frame, then route + read the clock + correlate +
    /// gate the gesture, all reusing that one `ParsedFrame`. Total parses must equal the frame count,
    /// not 3× it (the regression this issue fixes).
    func testDelegateHotPathParsesEachFrameOnce() {
        let router = FrameRouter(state: LiveState())
        let counter = ParseCounter()
        ParseInstrumentation.onParse = { counter.increment() }

        for frame in frames {
            let parsed = parseFrame(frame, family: .whoop4)        // the loop's single parse
            router.handle(parsed: parsed)                          // was parseFrame #1 (inside handle)
            _ = parsed.parsed["clock"]?.intValue                   // was parseFrame #2 (GET_CLOCK read)
            _ = ClockCorrelation.clockRef(from: parsed, wall: 0)   // was parseFrame #3 (correlation)
            router.dispatchLiveGestureIfFresh(parsed: parsed)      // was a 4th parse during backfill
        }

        XCTAssertEqual(counter.count, frames.count,
                       "each frame must be parsed exactly once across router + clock + correlation + gesture")
    }
}
