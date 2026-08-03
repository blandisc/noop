import XCTest
@testable import StrandAnalytics

/// Pins `MetricLevelPhrase` (FER-29 · contrato 4): one data-driven home for the level-reading key,
/// replacing the four scattered switches (~47 cases) with TOTAL coverage and no silent `default`.
final class MetricLevelPhraseTests: XCTestCase {

    // MARK: - Key derivation is pure and stable

    func testKeyShapeIsComposedFromInputs() {
        XCTAssertEqual(
            MetricLevelPhrase.key(metricID: "sleep", levelKey: "optimal", comparison: .vsTarget),
            "reading.vsTarget.sleep.optimal")
        XCTAssertEqual(
            MetricLevelPhrase.key(metricID: "hrv", levelKey: "below", comparison: .vsBase),
            "reading.vsBase.hrv.below")
    }

    func testConvenienceKeyUsesTheMetricsOwnComparison() {
        // sleep → vsTarget, spo2 → vsPopulation, resolved from the table, not passed in.
        XCTAssertEqual(MetricLevelPhrase.key(metricID: "sleep", levelKey: "short"),
                       "reading.vsTarget.sleep.short")
        XCTAssertEqual(MetricLevelPhrase.key(metricID: "spo2", levelKey: "low"),
                       "reading.vsPopulation.spo2.low")
    }

    // MARK: - No mute default: an unknown pair is nil ON PURPOSE

    func testUnknownPairReturnsNilNotAWrongKey() {
        XCTAssertNil(MetricLevelPhrase.key(metricID: "sleep", levelKey: "notALevel"))
        XCTAssertNil(MetricLevelPhrase.key(metricID: "nope", levelKey: "optimal"))
        XCTAssertNil(MetricLevelPhrase.entry(metricID: "nope", levelKey: "x"))
        XCTAssertNil(MetricLevelPhrase.comparison(forMetricID: "nope"))
    }

    // MARK: - Total coverage over every fixed metric's levels (+ HRV + Carga)

    func testEveryFixedMetricLevelHasAContractRow() {
        // The metrics that own a sheet. Recovery has NO sheet in FER-29 and is absent by design.
        let sheetFixed: [(String, MetricLevels.FixedMetric)] = [
            ("rhr", .restingHR), ("resp_rate", .respiration), ("skin_temp", .skinTemp),
            ("spo2", .bloodOxygen), ("steps", .steps), ("stress", .stress), ("strain", .strain),
            ("sleep", .sleep),
        ]
        for (id, metric) in sheetFixed {
            for level in MetricLevels.levels(for: metric) {
                XCTAssertNotNil(MetricLevelPhrase.entry(metricID: id, levelKey: level.key),
                                "\(id).\(level.key) must be in the contract")
            }
        }
    }

    func testHRVPersonalLevelsCovered() {
        for level in ["below", "inBase", "above"] {
            let e = MetricLevelPhrase.entry(metricID: "hrv", levelKey: level)
            XCTAssertEqual(e?.comparison, .vsBase, "hrv.\(level)")
        }
    }

    func testCargaLoadBandsCovered() {
        // Carga is not a FixedMetric; its levels are ReadinessEngine.LoadBand. Must be in the contract.
        for band in ["rampingDown", "sweetSpot", "buildingFast", "spiking"] {
            XCTAssertNotNil(MetricLevelPhrase.key(metricID: "load", levelKey: band),
                            "load.\(band) must be in the contract")
        }
    }

    // MARK: - Keys are unique (no two rows collide into one catalog entry)

    func testEveryTableKeyIsUnique() {
        let keys = MetricLevelPhrase.table.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate reading keys would merge two phrases")
        XCTAssertFalse(keys.isEmpty)
    }

    func testComparisonAssignments() {
        XCTAssertEqual(MetricLevelPhrase.comparison(forMetricID: "sleep"), .vsTarget)
        XCTAssertEqual(MetricLevelPhrase.comparison(forMetricID: "hrv"), .vsBase)
        XCTAssertEqual(MetricLevelPhrase.comparison(forMetricID: "skin_temp"), .vsBase)
        XCTAssertEqual(MetricLevelPhrase.comparison(forMetricID: "steps"), .vsPopulation)
        XCTAssertEqual(MetricLevelPhrase.comparison(forMetricID: "load"), .vsBase)
    }
}
