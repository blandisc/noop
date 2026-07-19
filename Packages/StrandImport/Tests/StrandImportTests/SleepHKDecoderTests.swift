import XCTest
import CenitStore
@testable import StrandImport

// Pins FER-486 (F3 of FER-483): the pure HK→NOOP sleep decode that HealthKitBridge
// delegates to when ingesting Apple Health sleep STAGES into CachedSleepSession.
// Runs on macOS without HealthKit: `swift test --package-path Packages/StrandImport`.
final class SleepHKDecoderTests: XCTestCase {

    private func sample(_ hk: Int, _ start: Int, _ end: Int) -> SleepHKSample {
        SleepHKSample(hkValue: hk,
                      start: Date(timeIntervalSince1970: TimeInterval(start)),
                      end: Date(timeIntervalSince1970: TimeInterval(end)),
                      dedupeKey: "")
    }

    // Decode stagesJSON back to (start,end,stage) tuples — the same shape the screen reads.
    private struct Seg: Decodable { let start: Int; let end: Int; let stage: String }
    private func segs(_ json: String?) -> [Seg] {
        guard let json, let d = json.data(using: .utf8),
              let s = try? JSONDecoder().decode([Seg].self, from: d) else { return [] }
        return s
    }

    // MARK: - HK value → stage

    func testHKValueMapping() {
        XCTAssertEqual(SleepHKDecoder.stage(forHKValue: SleepHKEncoder.asleepDeepValue), "deep")
        XCTAssertEqual(SleepHKDecoder.stage(forHKValue: SleepHKEncoder.asleepREMValue), "rem")
        XCTAssertEqual(SleepHKDecoder.stage(forHKValue: SleepHKEncoder.asleepCoreValue), "light")
        XCTAssertEqual(SleepHKDecoder.stage(forHKValue: 1), "light")               // asleepUnspecified
        XCTAssertEqual(SleepHKDecoder.stage(forHKValue: SleepHKEncoder.awakeValue), "wake")
        XCTAssertNil(SleepHKDecoder.stage(forHKValue: SleepHKEncoder.inBedValue))  // inBed dropped
        XCTAssertNil(SleepHKDecoder.stage(forHKValue: 99))                         // unknown dropped
    }

    /// Encoder/decoder agree on every stage NOOP carries: decode∘encode == identity on the stage class.
    func testRoundTripsWithEncoder() {
        for stage in ["deep", "rem", "light", "wake"] {
            XCTAssertEqual(SleepHKDecoder.stage(forHKValue: SleepHKEncoder.hkValue(forStage: stage)), stage)
        }
    }

    // MARK: - Sessionization

    func testEmptyInputYieldsNoSessions() {
        XCTAssertTrue(SleepHKDecoder.sessions(from: []).isEmpty)
    }

    func testSingleNightGroupsContiguousSamplesIntoOneSession() {
        // 23:00 core → 23:30 deep → 00:00 rem (contiguous), all one night.
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.asleepCoreValue, base, base + 1800),
            sample(SleepHKEncoder.asleepDeepValue, base + 1800, base + 3600),
            sample(SleepHKEncoder.asleepREMValue, base + 3600, base + 5400),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].startTs, base)
        XCTAssertEqual(out[0].endTs, base + 5400)
        let stages = segs(out[0].stagesJSON).map(\.stage)
        XCTAssertEqual(stages, ["light", "deep", "rem"])
    }

    func testBriefAwakeningKeepsOneNight() {
        // A 10-min 3 a.m. awakening (< 1 h gap) stays inside one session.
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.asleepCoreValue, base, base + 3600),
            sample(SleepHKEncoder.awakeValue, base + 3600, base + 4200),       // 10-min wake
            sample(SleepHKEncoder.asleepDeepValue, base + 4200, base + 7800),
        ]
        XCTAssertEqual(SleepHKDecoder.sessions(from: s).count, 1)
    }

    func testLongGapSplitsIntoTwoSessions() {
        // A nap 8 h after the night ends → distinct session (gap > 1 h).
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.asleepCoreValue, base, base + 3600),
            sample(SleepHKEncoder.asleepREMValue, base + 3600, base + 7200),
            sample(SleepHKEncoder.asleepCoreValue, base + 7200 + 8 * 3600, base + 7200 + 8 * 3600 + 1800),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(out.count, 2)
        XCTAssertLessThan(out[0].startTs, out[1].startTs)
    }

    func testInBedEnvelopeExtendsSpanButEmitsNoSegment() {
        // inBed wraps the whole night; one asleepCore block inside. Span = inBed; one segment.
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.inBedValue, base, base + 7200),
            sample(SleepHKEncoder.asleepCoreValue, base + 600, base + 6600),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].startTs, base)             // inBed sets the start
        XCTAssertEqual(out[0].endTs, base + 7200)        // inBed sets the end
        XCTAssertEqual(segs(out[0].stagesJSON).count, 1) // only the core segment, not inBed
        XCTAssertEqual(segs(out[0].stagesJSON)[0].stage, "light")
    }

    func testInBedOnlyNightIsDropped() {
        // Manual "in bed" with no stage data → no hypnogram possible → no session.
        let base = 1_700_000_000
        let s = [sample(SleepHKEncoder.inBedValue, base, base + 7200)]
        XCTAssertTrue(SleepHKDecoder.sessions(from: s).isEmpty)
    }

    func testUnsortedInputIsSortedBeforeGrouping() {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.asleepREMValue, base + 3600, base + 5400),
            sample(SleepHKEncoder.asleepCoreValue, base, base + 1800),
            sample(SleepHKEncoder.asleepDeepValue, base + 1800, base + 3600),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(segs(out[0].stagesJSON).map(\.stage), ["light", "deep", "rem"])
        // Segments are start-sorted regardless of input order.
        let starts = segs(out[0].stagesJSON).map(\.start)
        XCTAssertEqual(starts, starts.sorted())
    }

    func testZeroLengthSamplesAreSkipped() {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.asleepCoreValue, base, base),          // zero-length, skipped
            sample(SleepHKEncoder.asleepDeepValue, base, base + 1800),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(segs(out[0].stagesJSON).count, 1)
        XCTAssertEqual(segs(out[0].stagesJSON)[0].stage, "deep")
    }

    /// The emitted stagesJSON is exactly the [{start,end,stage}] shape the hypnogram decodes
    /// (SleepDetailScreen.decodeSegments / AnalyticsEngine.decodeStages).
    func testStagesJSONShapeIsSegmentArray() {
        let base = 1_700_000_000
        let s = [sample(SleepHKEncoder.asleepDeepValue, base, base + 1800)]
        let json = SleepHKDecoder.sessions(from: s)[0].stagesJSON
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("\"start\""))
        XCTAssertTrue(json!.contains("\"end\""))
        XCTAssertTrue(json!.contains("\"stage\":\"deep\""))
    }

    // MARK: - Sleep efficiency (FER-1006)

    /// 8 h in bed, 6 h asleep → 0.75. The `inBed` envelope is the denominator; the stage samples
    /// sitting inside it are the numerator.
    func testEfficiencyUsesTheInBedEnvelopeAsDenominator() {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.inBedValue, base, base + 8 * 3600),
            sample(SleepHKEncoder.asleepDeepValue, base + 1800, base + 1800 + 2 * 3600),
            sample(SleepHKEncoder.asleepCoreValue, base + 1800 + 2 * 3600, base + 1800 + 6 * 3600),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(try XCTUnwrap(out[0].efficiency), 0.75, accuracy: 0.001)
    }

    /// THE scale test. The scorer centres on `RecoveryScorer.sleepPerfCenter == 0.85` and
    /// `Baselines.metricCfg["efficiency"]` runs `0.2…1.0`. Emitting whole percent would be 100× off
    /// and would saturate the sleep term without ever looking wrong on screen — the detail view
    /// normalises defensively (`stored <= 1.0 ? stored * 100 : stored`), so the UI would hide it.
    func testEfficiencyIsAFractionNotWholePercent() throws {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.inBedValue, base, base + 8 * 3600),
            sample(SleepHKEncoder.asleepCoreValue, base, base + 7 * 3600),
        ]
        let eff = try XCTUnwrap(SleepHKDecoder.sessions(from: s)[0].efficiency)
        XCTAssertLessThanOrEqual(eff, 1.0, "Efficiency must be a 0…1 fraction, never whole percent.")
        XCTAssertEqual(eff, 0.875, accuracy: 0.001)
    }

    /// No `inBed` sample → nil, NOT a ratio over the stage span. Without the envelope the only
    /// denominator available excludes the awake time before sleep onset and after waking, so the
    /// number would be systematically inflated. Abstaining is the honest answer.
    func testEfficiencyIsNilWithoutAnInBedEnvelope() {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.asleepDeepValue, base, base + 2 * 3600),
            sample(SleepHKEncoder.asleepREMValue, base + 2 * 3600, base + 4 * 3600),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(out.count, 1)
        XCTAssertNil(out[0].efficiency, "No inBed envelope ⇒ no efficiency, rather than an inflated one.")
    }

    /// Awake spans inside the night are time in bed but NOT asleep — they must lower efficiency.
    func testAwakeSegmentsDoNotCountAsAsleep() throws {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.inBedValue, base, base + 4 * 3600),
            sample(SleepHKEncoder.asleepCoreValue, base, base + 2 * 3600),
            sample(SleepHKEncoder.awakeValue, base + 2 * 3600, base + 3 * 3600),
            sample(SleepHKEncoder.asleepCoreValue, base + 3 * 3600, base + 4 * 3600),
        ]
        let eff = try XCTUnwrap(SleepHKDecoder.sessions(from: s)[0].efficiency)
        XCTAssertEqual(eff, 0.75, accuracy: 0.001, "3 h asleep of 4 h in bed — the awake hour counts against.")
    }

    /// Stage samples that run past the reported `inBed` window (Apple's envelope is not always
    /// exact) must not produce efficiency above 1.
    func testEfficiencyIsClampedToOne() throws {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.inBedValue, base, base + 3600),
            sample(SleepHKEncoder.asleepCoreValue, base, base + 2 * 3600),
        ]
        let eff = try XCTUnwrap(SleepHKDecoder.sessions(from: s)[0].efficiency)
        XCTAssertEqual(eff, 1.0, accuracy: 0.001)
    }

    /// Regression: adding efficiency must not disturb the hypnogram. `inBed` still contributes no
    /// segment and still extends the session span.
    func testInBedStillProducesNoSegmentAndStillExtendsTheSpan() {
        let base = 1_700_000_000
        let s = [
            sample(SleepHKEncoder.inBedValue, base, base + 8 * 3600),
            sample(SleepHKEncoder.asleepDeepValue, base + 3600, base + 2 * 3600),
        ]
        let out = SleepHKDecoder.sessions(from: s)
        XCTAssertEqual(segs(out[0].stagesJSON).count, 1, "inBed is an envelope, not a stage.")
        XCTAssertEqual(segs(out[0].stagesJSON)[0].stage, "deep")
        XCTAssertEqual(out[0].startTs, base)
        XCTAssertEqual(out[0].endTs, base + 8 * 3600)
    }
}
