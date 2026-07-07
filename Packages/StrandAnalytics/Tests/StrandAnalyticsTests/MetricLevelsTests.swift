import XCTest
@testable import StrandAnalytics

/// Pins `MetricLevels` — the pure per-metric level engine behind the new metric detail (FER-570).
/// Covers: the EXACT README thresholds per fixed metric, the relative-to-baseline case
/// (HRV/Recovery), half-open boundary behaviour, the counts-sum invariant, and the empty window.
final class MetricLevelsTests: XCTestCase {

    // MARK: - Thresholds match the README exactly

    func testRecoveryLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .recovery)
        XCTAssertEqual(lv.map(\.key), ["depleted", "low", "moderate", "primed", "peak"])
        XCTAssertEqual(lv.map(\.lower), [nil, 25, 50, 70, 88])
        XCTAssertEqual(lv.map(\.upper), [25, 50, 70, 88, nil])
    }

    func testSleepLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .sleep)
        XCTAssertEqual(lv.map(\.key), ["short", "adequate", "optimal", "extended"])
        XCTAssertEqual(lv.map(\.lower), [nil, 360, 420, 510])
        XCTAssertEqual(lv.map(\.upper), [360, 420, 510, nil])
    }

    func testStrainLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .strain)
        XCTAssertEqual(lv.map(\.key), ["rest", "light", "moderate", "hard", "extreme"])
        XCTAssertEqual(lv.map(\.lower), [nil, 6, 10, 14, 18])
        XCTAssertEqual(lv.map(\.upper), [6, 10, 14, 18, nil])
    }

    func testRestingHRLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .restingHR)
        XCTAssertEqual(lv.map(\.key), ["athlete", "excellent", "normal", "elevated"])
        XCTAssertEqual(lv.map(\.lower), [nil, 50, 60, 80])
        XCTAssertEqual(lv.map(\.upper), [50, 60, 80, nil])
    }

    func testBloodOxygenLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .bloodOxygen)
        XCTAssertEqual(lv.map(\.key), ["low", "normal"])
        XCTAssertEqual(lv.map(\.lower), [nil, 95])
        XCTAssertEqual(lv.map(\.upper), [95, nil])
    }

    func testStepsLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .steps)
        XCTAssertEqual(lv.map(\.key), ["sedentary", "active", "veryActive"])
        XCTAssertEqual(lv.map(\.lower), [nil, 5000, 10000])
        XCTAssertEqual(lv.map(\.upper), [5000, 10000, nil])
    }

    func testStressLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .stress)
        XCTAssertEqual(lv.map(\.key), ["low", "medium", "high"])
        XCTAssertEqual(lv.map(\.lower), [nil, 1, 2])
        XCTAssertEqual(lv.map(\.upper), [1, 2, nil])
    }

    func testRespirationLevelsMatchReadme() {
        let lv = MetricLevels.levels(for: .respiration)
        XCTAssertEqual(lv.map(\.key), ["normal", "elevated"])
        XCTAssertEqual(lv.map(\.lower), [nil, 20])
        XCTAssertEqual(lv.map(\.upper), [20, nil])
    }

    func testSkinTempLevelsMatchEngineCuts() {
        // Deviation from the personal baseline (°C); the ReadinessEngine cut points (+0.4 watch, +0.8 bad),
        // symmetric −0.4 for "below your base".
        let lv = MetricLevels.levels(for: .skinTemp)
        XCTAssertEqual(lv.map(\.key), ["below", "inBase", "warm", "elevated"])
        XCTAssertEqual(lv.map(\.lower), [nil, -0.4, 0.4, 0.8])
        XCTAssertEqual(lv.map(\.upper), [-0.4, 0.4, 0.8, nil])
        // Boundaries are half-open [lower, upper): the edge falls into the UPPER level.
        XCTAssertEqual(MetricLevels.index(of: -0.4, for: .skinTemp), 1)   // exactly −0.4 → in your base
        XCTAssertEqual(MetricLevels.index(of: 0.4, for: .skinTemp), 2)    // exactly +0.4 → running warm
        XCTAssertEqual(MetricLevels.index(of: 0.8, for: .skinTemp), 3)    // exactly +0.8 → well above
        XCTAssertEqual(MetricLevels.index(of: 0.0, for: .skinTemp), 1)    // at baseline → in your base
        XCTAssertEqual(MetricLevels.index(of: -0.5, for: .skinTemp), 0)   // below your base
        // The names the app localises, including the new "warm" key.
        XCTAssertEqual(lv.map { MetricLevels.name(for: $0.key) },
                       ["Below your base", "In your base", "Running warm", "Elevated"])
    }

    // MARK: - Half-open boundaries: a value on the edge falls into the UPPER level

    func testBoundaryFallsToUpperLevel() {
        // Recovery: 25 → "low" (not "depleted"), 50 → "moderate", 70 → "primed", 88 → "peak".
        XCTAssertEqual(MetricLevels.index(of: 25, for: .recovery), 1)
        XCTAssertEqual(MetricLevels.index(of: 50, for: .recovery), 2)
        XCTAssertEqual(MetricLevels.index(of: 70, for: .recovery), 3)
        XCTAssertEqual(MetricLevels.index(of: 88, for: .recovery), 4)
        // Just below a boundary stays in the lower level.
        XCTAssertEqual(MetricLevels.index(of: 24.999, for: .recovery), 0)
        XCTAssertEqual(MetricLevels.index(of: 87.999, for: .recovery), 3)
    }

    func testStrainBoundaries() {
        XCTAssertEqual(MetricLevels.index(of: 0, for: .strain), 0)    // rest
        XCTAssertEqual(MetricLevels.index(of: 6, for: .strain), 1)    // light
        XCTAssertEqual(MetricLevels.index(of: 18, for: .strain), 4)   // extreme
        XCTAssertEqual(MetricLevels.index(of: 21, for: .strain), 4)   // extreme (top, open above)
    }

    func testSleepExtendedBoundary() {
        // 510 min sits exactly on the optimal→extended edge → extended (upper).
        XCTAssertEqual(MetricLevels.index(of: 510, for: .sleep), 3)
        XCTAssertEqual(MetricLevels.index(of: 509.99, for: .sleep), 2)
    }

    // MARK: - Counting a window: counts sum to the number of values, active = today's level

    func testRecoveryClassificationCountsAndActive() {
        // depleted, low, low, moderate, primed, peak  → [1,2,1,1,1]
        let values: [Double] = [10, 30, 49, 60, 80, 95]
        let c = MetricLevels.classification(for: .recovery, values: values, today: 95)
        XCTAssertEqual(c.counts, [1, 2, 1, 1, 1])
        XCTAssertEqual(c.counts.reduce(0, +), c.total)
        XCTAssertEqual(c.total, 6)
        XCTAssertEqual(c.activeIndex, 4)   // 95 → peak
    }

    func testCountsSumEqualsValidValuesForEveryFixedMetric() {
        // For each fixed metric, a spread of values must count without gaps or double-counting.
        let samples: [MetricLevels.FixedMetric: [Double]] = [
            .recovery: [0, 24, 25, 49, 50, 69, 70, 87, 88, 100],
            .sleep: [0, 359, 360, 419, 420, 509, 510, 700],
            .strain: [0, 5.9, 6, 9.9, 10, 13.9, 14, 17.9, 18, 21],
            .restingHR: [40, 49, 50, 59, 60, 79, 80, 100],
            .bloodOxygen: [88, 94.9, 95, 99, 100],
            .steps: [0, 4999, 5000, 9999, 10000, 30000],
            .stress: [0, 0.9, 1, 1.9, 2, 3],
            .respiration: [8, 12, 19.9, 20, 25],
            .skinTemp: [-1.0, -0.4, -0.39, 0, 0.39, 0.4, 0.79, 0.8, 1.2],
        ]
        for (metric, values) in samples {
            let c = MetricLevels.classification(for: metric, values: values, today: nil)
            XCTAssertEqual(c.counts.reduce(0, +), values.count, "\(metric) counts must sum to values")
            XCTAssertEqual(c.total, values.count, "\(metric) total")
            XCTAssertNil(c.activeIndex, "\(metric) no today → no active level")
            XCTAssertFalse(c.counts.contains(where: { $0 < 0 }))
        }
    }

    // MARK: - Empty window → no active level, zero counts, no crash

    func testEmptyWindow() {
        let c = MetricLevels.classification(for: .strain, values: [], today: nil)
        XCTAssertEqual(c.counts, [0, 0, 0, 0, 0])
        XCTAssertEqual(c.total, 0)
        XCTAssertNil(c.activeIndex)
    }

    func testEmptyWindowButTodayPresent() {
        // No history but a value today → counts all zero, but the active level is still known.
        let c = MetricLevels.classification(for: .recovery, values: [], today: 92)
        XCTAssertEqual(c.counts, [0, 0, 0, 0, 0])
        XCTAssertEqual(c.total, 0)
        XCTAssertEqual(c.activeIndex, 4)   // 92 → peak
    }

    // MARK: - Relative-to-baseline levels (HRV / Recovery)

    func testRelativeLevelsCutsAtPlusMinusOneSD() {
        let lv = MetricLevels.relativeLevels(baseline: 60, sd: 10)
        XCTAssertEqual(lv.map(\.key), ["below", "inBase", "above"])
        XCTAssertEqual(lv[0].upper, 50)   // baseline - 1·SD
        XCTAssertEqual(lv[1].lower, 50)
        XCTAssertEqual(lv[1].upper, 70)   // baseline + 1·SD
        XCTAssertEqual(lv[2].lower, 70)
        XCTAssertNil(lv[0].lower)
        XCTAssertNil(lv[2].upper)
    }

    func testRelativeClassificationHRV() {
        // baseline 50 ms, SD 8 → cuts at 42 / 58. Series straddles all three levels.
        // 40 below · 45 inBase · 50 inBase · 57 inBase · 60 above
        let c = MetricLevels.relativeClassification(
            values: [40, 45, 50, 57, 60], today: 60, baseline: 50, sd: 8)
        XCTAssertEqual(c.counts, [1, 3, 1])
        XCTAssertEqual(c.counts.reduce(0, +), 5)
        XCTAssertEqual(c.activeIndex, 2)   // 60 > 58 → above
    }

    func testRelativeBoundaryFallsToUpper() {
        // Exactly at baseline-SD (42) → inBase; exactly at baseline+SD (58) → above.
        let lv = MetricLevels.relativeLevels(baseline: 50, sd: 8)
        XCTAssertEqual(MetricLevels.index(of: 42, in: lv), 1)
        XCTAssertEqual(MetricLevels.index(of: 58, in: lv), 2)
        XCTAssertEqual(MetricLevels.index(of: 41.99, in: lv), 0)
    }

    func testRelativeCustomKWidensBase() {
        // k = 2 → cuts at baseline ± 2·SD (42→34, 58→66 for sd 8).
        let lv = MetricLevels.relativeLevels(baseline: 50, sd: 8, k: 2)
        XCTAssertEqual(lv[0].upper, 34)
        XCTAssertEqual(lv[1].upper, 66)
    }

    func testRelativeZeroSDStaysTotal() {
        // Degenerate spread: both cuts collapse to the baseline, so "inBase" = [50, 50) is empty.
        // The partition is still total — 49 → below, 50 and 51 → above (50 < 50 is false, so the
        // half-open inBase rejects it) — counts sum to the window, no crash.
        let c = MetricLevels.relativeClassification(
            values: [49, 50, 51], today: 50, baseline: 50, sd: 0)
        XCTAssertEqual(c.counts, [1, 0, 2])
        XCTAssertEqual(c.counts.reduce(0, +), 3)
        XCTAssertEqual(c.activeIndex, 2)             // 50 falls to the upper (above) level
    }

    func testRelativeEmptyWindow() {
        let c = MetricLevels.relativeClassification(
            values: [], today: nil, baseline: 50, sd: 8)
        XCTAssertEqual(c.counts, [0, 0, 0])
        XCTAssertEqual(c.total, 0)
        XCTAssertNil(c.activeIndex)
    }

    // MARK: - name(for:) — the single key→label home (FER-731)

    /// FER-638, pinned in ONE place: the 70–88 recovery zone (`primed`) reads "High", never "A punto".
    /// This is the rule the app's `MetricLevelsExplorer.label` / `MetricInfoSheet.recoveryLevelLabel`
    /// now read through, so it can't drift per screen again.
    func testPrimedNameIsHighNotAPunto() {
        XCTAssertEqual(MetricLevels.name(for: "primed"), "High")
    }

    /// Every recovery level key resolves to its finalized English label — the map the app localises.
    func testRecoveryLevelNames() {
        let names = MetricLevels.levels(for: .recovery).map { MetricLevels.name(for: $0.key) }
        XCTAssertEqual(names, ["Depleted", "Low", "Moderate", "High", "Peak"])
    }

    /// Unknown keys echo back verbatim (the old per-screen `default` behaviour), so a new level key
    /// degrades to its raw key instead of crashing or vanishing.
    func testUnknownKeyEchoesBack() {
        XCTAssertEqual(MetricLevels.name(for: "brandNewLevel"), "brandNewLevel")
    }

    // MARK: - activeIndex(for:in:) — the single public classifier (FER-731)

    func testActiveIndexMatchesInternalClassifier() {
        let lv = MetricLevels.levels(for: .recovery)
        // 75 sits in `primed` (70–88), index 3; boundary 88 falls to the upper `peak` (half-open).
        XCTAssertEqual(MetricLevels.activeIndex(for: 75, in: lv), 3)
        XCTAssertEqual(MetricLevels.activeIndex(for: 88, in: lv), 4)
        XCTAssertEqual(MetricLevels.activeIndex(for: 0, in: lv), 0)
    }

    func testActiveIndexEmptyLevelsIsNil() {
        XCTAssertNil(MetricLevels.activeIndex(for: 50, in: []))
    }
}
