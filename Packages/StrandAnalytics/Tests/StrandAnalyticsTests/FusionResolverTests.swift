import XCTest
@testable import StrandAnalytics

/// FER-670 — the single-construct fusion contract. Covers: trust ordering ("best signal wins"),
/// cross-validation boundaries, conflict-never-merges, single-source degradation, provenance
/// integrity, and — the critical condition — the EXCLUSION of every cross-source vital
/// (HRV/RHR/respiration/SpO₂/skin temp/sleep stages) from arbitration: those stay under `SourceLens`.
final class FusionResolverTests: XCTestCase {

    // MARK: - 1. Trust ordering ("best signal wins")

    func testStepsPhoneCountBeatsStrapFigure() {
        // The phone pedometer COUNTS steps (tier 0); the strap figure is motion-derived (tier 3).
        let point = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .noopComputed, value: 6000),   // strap motion figure
            FusionInput(source: .appleHealth, value: 8420),    // counts directly
        ])
        XCTAssertEqual(point?.winningSource, .appleHealth)
        XCTAssertEqual(point?.value, 8420)
        XCTAssertEqual(point?.contributors.first?.reason, "counts directly")
    }

    func testSleepWhoopBeatsPhoneBuckets() {
        // Imported WHOOP timeline (tier 0) beats phone sleep buckets (tier 2).
        let point = FusionResolver.resolve(metricKey: "sleep_total_min", inputs: [
            FusionInput(source: .appleHealth, value: 400),
            FusionInput(source: .whoopImport, value: 432),
        ])
        XCTAssertEqual(point?.winningSource, .whoopImport)
        XCTAssertEqual(point?.value, 432)
        XCTAssertEqual(point?.contributors.first?.reason, "band sleep timeline")
    }

    func testSleepTieOnSameTierBrokenStablyBySourcePriority() {
        // Imported (priority 0) and computed (priority 1) never share a tier for sleep, so exercise
        // the tiebreak with two same-tier strap sources on steps (both tier 3): whoopImport wins.
        let point = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .noopComputed, value: 6100),
            FusionInput(source: .whoopImport, value: 6000),
        ])
        XCTAssertEqual(point?.winningSource, .whoopImport)
        XCTAssertEqual(point?.value, 6000)
    }

    func testCaloriesPhoneAggregateBeatsHrEstimate() {
        let point = FusionResolver.resolve(metricKey: "active_kcal", inputs: [
            FusionInput(source: .noopComputed, value: 480),
            FusionInput(source: .appleHealth, value: 520),
        ])
        XCTAssertEqual(point?.winningSource, .appleHealth)
        XCTAssertEqual(point?.value, 520)
    }

    // MARK: - 2. Cross-validation classification at boundaries

    func testSleepAgreeWithinTolerance() {
        // Sleep tolerance: agree <= 20 min. Winner 432, other 445 → delta 13 → agree.
        let point = FusionResolver.resolve(metricKey: "sleep_total_min", inputs: [
            FusionInput(source: .whoopImport, value: 432),
            FusionInput(source: .appleHealth, value: 445),
        ])
        XCTAssertEqual(point?.agreement, .agree)
    }

    func testSleepMinorDeltaJustOverAgreeEdge() {
        // Delta 21 (> 20 agree edge, <= 60 minor edge) → minorDelta.
        let point = FusionResolver.resolve(metricKey: "sleep_total_min", inputs: [
            FusionInput(source: .whoopImport, value: 432),
            FusionInput(source: .appleHealth, value: 453),
        ])
        XCTAssertEqual(point?.agreement, .minorDelta)
    }

    func testSleepConflictTwoHoursVsSeven() {
        // 432 min vs 120 min — a gross divergence → conflict.
        let point = FusionResolver.resolve(metricKey: "sleep_total_min", inputs: [
            FusionInput(source: .whoopImport, value: 432),
            FusionInput(source: .appleHealth, value: 120),
        ])
        XCTAssertEqual(point?.agreement, .conflict)
    }

    func testStepsPercentBandAgree() {
        // Steps tolerance is ±10% agree / ±30% minor. Winner 8000, other 8500 → 6.25% → agree.
        let point = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .appleHealth, value: 8000),
            FusionInput(source: .noopComputed, value: 8500),
        ])
        XCTAssertEqual(point?.winningSource, .appleHealth)
        XCTAssertEqual(point?.agreement, .agree)
    }

    func testStepsPercentBandMinorDelta() {
        // Winner 8000, other 9700 → 21.25% (> 10%, <= 30%) → minorDelta.
        let point = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .appleHealth, value: 8000),
            FusionInput(source: .noopComputed, value: 9700),
        ])
        XCTAssertEqual(point?.agreement, .minorDelta)
    }

    func testStepsPercentBandConflict() {
        // Winner 8000, other 14000 → 75% over → conflict.
        let point = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .appleHealth, value: 8000),
            FusionInput(source: .noopComputed, value: 14000),
        ])
        XCTAssertEqual(point?.agreement, .conflict)
    }

    func testZeroWinnerPercentBandNonZeroOtherIsConflict() {
        // Percent edges collapse at a zero winner: 0 steps vs 500 → conflict ("one source says
        // nothing happened, the other says something did"). Pinned so the edge case stays deliberate.
        let point = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .appleHealth, value: 0),
            FusionInput(source: .noopComputed, value: 500),
        ])
        XCTAssertEqual(point?.agreement, .conflict)
        // And two zeros agree.
        let zeros = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .appleHealth, value: 0),
            FusionInput(source: .noopComputed, value: 0),
        ])
        XCTAssertEqual(zeros?.agreement, .agree)
    }

    func testWorstCaseAcrossContributorsWins() {
        // Three sources: one agrees, one conflicts → the point is a conflict.
        let point = FusionResolver.resolve(metricKey: "sleep_total_min", inputs: [
            FusionInput(source: .whoopImport, value: 430),
            FusionInput(source: .noopComputed, value: 440),  // delta 10 → agree
            FusionInput(source: .appleHealth, value: 300),   // delta 130 → conflict
        ])
        XCTAssertEqual(point?.agreement, .conflict)
    }

    // MARK: - 3. Conflict never silently merges

    func testConflictKeepsBothContributorsWinnerVerbatim() {
        let point = FusionResolver.resolve(metricKey: "sleep_total_min", inputs: [
            FusionInput(source: .appleHealth, value: 120),
            FusionInput(source: .whoopImport, value: 432),
        ])
        // Winner is the higher-trust source, value is verbatim (NOT an average of 120 & 432 = 276).
        XCTAssertEqual(point?.winningSource, .whoopImport)
        XCTAssertEqual(point?.value, 432)
        XCTAssertEqual(point?.agreement, .conflict)
        XCTAssertEqual(point?.contributors.count, 2)
        XCTAssertTrue(point?.contributors.contains { $0.source == .appleHealth } ?? false)
        XCTAssertTrue(point?.contributors.contains { $0.source == .whoopImport } ?? false)
    }

    // MARK: - 4. Single-source degradation

    func testSingleSourcePassesThroughNoAgreement() {
        let point = FusionResolver.resolve(metricKey: "steps", inputs: [
            FusionInput(source: .appleHealth, value: 9100),
        ])
        XCTAssertEqual(point?.value, 9100)
        XCTAssertEqual(point?.winningSource, .appleHealth)
        XCTAssertEqual(point?.agreement, .single)
        XCTAssertEqual(point?.contributors.count, 1)
    }

    func testEmptyInputsYieldNil() {
        XCTAssertNil(FusionResolver.resolve(metricKey: "steps", inputs: []))
    }

    // MARK: - 5. Provenance integrity

    func testWinningSourceMatchesSuppliedValue() {
        // Three sources; the winner's value must be exactly the value that source supplied.
        let inputs = [
            FusionInput(source: .appleHealth, value: 401),
            FusionInput(source: .noopComputed, value: 402),
            FusionInput(source: .whoopImport, value: 403),
        ]
        let point = FusionResolver.resolve(metricKey: "sleep_total_min", inputs: inputs)
        XCTAssertEqual(point?.winningSource, .whoopImport)
        XCTAssertEqual(point?.value, 403)
        // Contributors are winner-first and preserve every supplied value verbatim.
        XCTAssertEqual(point?.contributors.first?.source, .whoopImport)
        XCTAssertEqual(Set(point?.contributors.map(\.value) ?? []), Set([401, 402, 403]))
    }

    // MARK: - 6. FER-670 critical condition: cross-source vitals are NOT arbitrated here

    func testExcludedKeysAreRefusedEvenWithTwoSources() {
        // RMSSD vs SDNN, band-vs-Apple RHR/resp offsets, staging offsets: `SourceLens` territory.
        // The resolver must refuse (nil), never pick a winner or classify a tolerance.
        let excluded = ["hrv", "rhr", "resting_hr", "resp_rate", "spo2", "skin_temp",
                        "sleep_deep_min", "deep_min", "sleep_rem_min", "rem_min",
                        "sleep_light_min", "core_min", "in_bed_min", "avg_hr", "max_hr",
                        "recovery", "strain", "unknown_key"]
        for key in excluded {
            let point = FusionResolver.resolve(metricKey: key, inputs: [
                FusionInput(source: .whoopImport, value: 50),
                FusionInput(source: .appleHealth, value: 60),
            ])
            XCTAssertNil(point, "\(key) must NOT be arbitrated by FusionResolver")
            XCTAssertNil(MetricArbitrationPolicy.kind(forKey: key),
                         "\(key) must not map to a MetricKind")
        }
    }

    func testOnlySingleConstructKeysMap() {
        // The full allowlist — anything beyond these three constructs is a policy change, not a drift.
        XCTAssertEqual(MetricArbitrationPolicy.kind(forKey: "steps"), .steps)
        XCTAssertEqual(MetricArbitrationPolicy.kind(forKey: "sleep_total_min"), .sleep)
        XCTAssertEqual(MetricArbitrationPolicy.kind(forKey: "asleep_min"), .sleep)
        XCTAssertEqual(MetricArbitrationPolicy.kind(forKey: "active_kcal"), .calories)
        XCTAssertEqual(MetricArbitrationPolicy.kind(forKey: "energy_kcal"), .calories)
    }
}
