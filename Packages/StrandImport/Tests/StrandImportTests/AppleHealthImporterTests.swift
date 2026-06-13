import XCTest
@testable import StrandImport

final class AppleHealthImporterTests: XCTestCase {

    private let fixtureName = "sample_health_data.xml"

    private func parsed() throws -> AppleHealthImportResult {
        let data = Fixtures.data(fixtureName)
        XCTAssertFalse(data.isEmpty, "\(fixtureName) fixture missing")
        return try AppleHealthImporter().importXML(data: data)
    }

    /// The fixture's records all fall on the local civil day 2024-01-02 (+0100).
    private func fixtureDay() throws -> AppleDailyAggregate {
        let r = try parsed()
        return try XCTUnwrap(r.daily.first { $0.day == "2024-01-02" }, "expected a 2024-01-02 aggregate")
    }

    // MARK: - Type filtering / aggregation

    func testRelevantTypesAggregated() throws {
        let d = try fixtureDay()
        // BodyMass is a relevant (body-composition) type -> weight present.
        XCTAssertEqual(try XCTUnwrap(d.weightKg), 72.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.avgHr), 61, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.restingHr), 58, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.respRate), 15.8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.steps), 1200, accuracy: 1e-9)
    }

    func testIrrelevantTypeExcluded() throws {
        // DietaryWater (250 mL) is not a relevant type — it must not surface in any
        // metric point (it has no mapping and was never ingested).
        let points = AppleHealthAggregator.metricPoints(try parsed().daily)
        XCTAssertFalse(points.contains { $0.value == 250 })
    }

    // MARK: - OxygenSaturation ×100

    func testOxygenSaturationFractionScaledToPercent() throws {
        // Raw value 0.97 -> 97.0 as the day's mean SpO₂.
        XCTAssertEqual(try XCTUnwrap(fixtureDay().spo2Pct), 97.0, accuracy: 1e-9)
    }

    // MARK: - Dates -> local civil day

    func testRecordsBucketToLocalDay() throws {
        // Every +0100 record lands on 2024-01-02 (the wall-clock day), so the
        // export collapses to exactly one daily aggregate.
        let r = try parsed()
        XCTAssertEqual(r.daily.map { $0.day }, ["2024-01-02"])
    }

    func testNegativeOffsetDateParsing() {
        let p = HealthDateParser()
        let result = p.parse("2024-06-01 14:30:00 -0500")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, Fixtures.utc(2024, 6, 1, 19, 30, 0)) // +5h to UTC
        XCTAssertEqual(result?.1, -300)
    }

    // MARK: - Sleep

    func testSleepStagesAggregatedToNight() throws {
        // core 60m + deep 60m + awake 15m, all waking on 2024-01-02.
        let d = try fixtureDay()
        XCTAssertEqual(try XCTUnwrap(d.coreMin), 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.deepMin), 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.awakeMin), 15, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.asleepMin), 120, accuracy: 1e-9) // core+deep+rem+unspecified
    }

    func testSleepStageMappingTable() {
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisInBed"), .inBed)
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleep"), .asleepUnspecified)
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleepCore"), .asleepCore)
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleepDeep"), .asleepDeep)
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleepREM"), .asleepREM)
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAwake"), .awake)
        XCTAssertEqual(SleepStage.from(rawValue: "garbage"), .unknown)
    }

    // MARK: - Correlation dedupe

    func testCorrelationChildNotCounted() throws {
        // HeartRate 61 appears top-level AND nested in a Correlation; only the
        // top-level one is ingested (correlationDepth skip). Records = 6 quantity
        // + 3 sleep = 9, plus 1 workout = 10.
        let r = try parsed()
        XCTAssertEqual(r.summary.recordCount, 10)
        XCTAssertEqual(try XCTUnwrap(fixtureDay().maxHr), 61, accuracy: 1e-9)
    }

    func testIdenticalAveragedReadingsMeanIsStable() throws {
        // Two identical top-level readings: with the global dedupe set removed,
        // both now count — but for an averaged metric the mean is unchanged.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="70"/>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="70"/>
        </HealthData>
        """
        let r = try AppleHealthImporter().importXML(data: Data(xml.utf8))
        let d = try XCTUnwrap(r.daily.first)
        XCTAssertEqual(try XCTUnwrap(d.avgHr), 70, accuracy: 1e-9)
    }

    // MARK: - Workouts

    func testWorkoutParsed() throws {
        let r = try parsed()
        XCTAssertEqual(r.workouts.count, 1)
        let w = r.workouts[0]
        XCTAssertEqual(w.activityType, "Running")
        XCTAssertEqual(w.durationS, 45 * 60)              // 45 min -> seconds
        XCTAssertEqual(w.distanceM!, 8050, accuracy: 0.5) // 8.05 km -> ~8050 m
        XCTAssertEqual(w.energyKcal, 540)
        XCTAssertEqual(w.start, Fixtures.utc(2024, 1, 2, 16, 0, 0)) // 17:00 +0100
        XCTAssertEqual(w.tzOffsetMin, 60)
    }

    // MARK: - Prefix stripping

    func testStripPrefix() {
        XCTAssertEqual(HealthXMLDelegate.stripPrefix("HKQuantityTypeIdentifierHeartRate"), "HeartRate")
        XCTAssertEqual(HealthXMLDelegate.stripPrefix("HKCategoryTypeIdentifierSleepAnalysis"), "SleepAnalysis")
        XCTAssertEqual(HealthXMLDelegate.stripPrefix("HKWorkoutActivityTypeRunning"), "Running")
        XCTAssertEqual(HealthXMLDelegate.stripPrefix("AlreadyClean"), "AlreadyClean")
    }

    // MARK: - Summary

    func testSummary() throws {
        let r = try parsed()
        XCTAssertEqual(r.summary.sourceKind, .appleHealth)
        XCTAssertEqual(r.summary.recordCount, 10)         // 9 records + 1 workout
        XCTAssertNotNil(r.summary.earliest)
        XCTAssertNotNil(r.summary.latest)
        XCTAssertLessThanOrEqual(r.summary.earliest!, r.summary.latest!)
        XCTAssertEqual(r.summary.countsByCategory["Workout"], 1)
    }

    // MARK: - Unknown elements tolerated

    func testUnknownElementsTolerated() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
         <SomeFutureElement foo="bar"><Nested/></SomeFutureElement>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="80">
          <UnknownChild key="x" value="y"/>
         </Record>
        </HealthData>
        """
        let r = try AppleHealthImporter().importXML(data: Data(xml.utf8))
        let d = try XCTUnwrap(r.daily.first)
        XCTAssertEqual(try XCTUnwrap(d.avgHr), 80, accuracy: 1e-9)
    }
}
