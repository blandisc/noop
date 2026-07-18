import XCTest
import CenitStore
@testable import StrandImport

// Pins FER-103: the pure stage-mapping and key-generation logic that HealthKitBridge
// delegates to when writing WHOOP sleep stages into Apple Health. Tests run on macOS
// without HealthKit via `swift test --package-path Packages/StrandImport`.
final class SleepHKEncoderTests: XCTestCase {

    // MARK: - Stage → HK value

    func testDeepMapsToAsleepDeep() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "deep"), SleepHKEncoder.asleepDeepValue)
    }
    func testRemMapsToAsleepREM() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "rem"), SleepHKEncoder.asleepREMValue)
    }
    func testWakeMapsToAwake() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "wake"), SleepHKEncoder.awakeValue)
    }
    func testLightMapsToAsleepCore() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "light"), SleepHKEncoder.asleepCoreValue)
    }
    func testUnknownStageFallsToAsleepCore() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "unknown"), SleepHKEncoder.asleepCoreValue)
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: ""), SleepHKEncoder.asleepCoreValue)
    }

    // MARK: - Sample construction

    private func makeSession(startTs: Int = 1_700_000_000, endTs: Int = 1_700_028_800,
                             stagesJSON: String? = nil) -> CachedSleepSession {
        CachedSleepSession(startTs: startTs, endTs: endTs,
                           efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: stagesJSON)
    }

    func testEmptySessionsReturnsEmpty() {
        XCTAssertTrue(SleepHKEncoder.samples(from: [], deviceId: "dev").isEmpty)
    }

    func testInvalidSessionEndEqualToStartIsSkipped() {
        let s = makeSession(startTs: 1_700_000_000, endTs: 1_700_000_000)
        XCTAssertTrue(SleepHKEncoder.samples(from: [s], deviceId: "dev").isEmpty)
    }

    func testNoStagesJsonEmitsOnlyInBed() {
        let s = makeSession()
        let result = SleepHKEncoder.samples(from: [s], deviceId: "test-device")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].hkValue, SleepHKEncoder.inBedValue)
    }

    func testInBedSpansFullSession() {
        let s = makeSession(startTs: 1_700_000_000, endTs: 1_700_028_800)
        let result = SleepHKEncoder.samples(from: [s], deviceId: "dev")
        let inBed = result[0]
        XCTAssertEqual(inBed.start, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(inBed.end,   Date(timeIntervalSince1970: 1_700_028_800))
    }

    func testWithStagesEmitsInBedPlusSegments() {
        let json = #"[{"start":1700000000,"end":1700003600,"stage":"light"},{"start":1700003600,"end":1700007200,"stage":"deep"},{"start":1700007200,"end":1700010800,"stage":"rem"}]"#
        let s = makeSession(startTs: 1_700_000_000, endTs: 1_700_010_800, stagesJSON: json)
        let result = SleepHKEncoder.samples(from: [s], deviceId: "dev")
        XCTAssertEqual(result.count, 4)         // inBed + 3 segments
        XCTAssertEqual(result[0].hkValue, SleepHKEncoder.inBedValue)
        XCTAssertEqual(result[1].hkValue, SleepHKEncoder.asleepCoreValue) // light
        XCTAssertEqual(result[2].hkValue, SleepHKEncoder.asleepDeepValue) // deep
        XCTAssertEqual(result[3].hkValue, SleepHKEncoder.asleepREMValue)  // rem
    }

    func testSegmentWithEndEqualToStartIsSkipped() {
        let json = #"[{"start":1700000000,"end":1700000000,"stage":"deep"}]"#
        let s = makeSession(stagesJSON: json)
        let result = SleepHKEncoder.samples(from: [s], deviceId: "dev")
        XCTAssertEqual(result.count, 1) // only inBed; bad segment skipped
    }

    // MARK: - Dedup keys

    func testInBedDedupeKey() {
        let s = makeSession(startTs: 1_700_000_000)
        let key = SleepHKEncoder.samples(from: [s], deviceId: "my-whoop-noop")[0].dedupeKey
        XCTAssertEqual(key, "noop:my-whoop-noop:sleep:inBed:1700000000")
    }

    func testSegmentDedupeKey() {
        let json = #"[{"start":1700003600,"end":1700007200,"stage":"deep"}]"#
        let s = makeSession(startTs: 1_700_000_000, endTs: 1_700_007_200, stagesJSON: json)
        let result = SleepHKEncoder.samples(from: [s], deviceId: "dev")
        XCTAssertEqual(result[1].dedupeKey, "noop:dev:sleep:1700000000:1700003600")
    }

    func testDedupeKeysAreUniqueAcrossTwoSessions() {
        let s1 = makeSession(startTs: 1_700_000_000, endTs: 1_700_028_800)
        let s2 = makeSession(startTs: 1_700_100_000, endTs: 1_700_128_800)
        let result = SleepHKEncoder.samples(from: [s1, s2], deviceId: "dev")
        let keys = result.map(\.dedupeKey)
        XCTAssertEqual(Set(keys).count, keys.count, "all keys must be unique")
    }
}
