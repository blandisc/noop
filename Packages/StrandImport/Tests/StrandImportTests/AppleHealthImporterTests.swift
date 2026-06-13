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

    // MARK: - Tolerant parse / byte sanitizer (#100)

    /// A 0x00 NUL byte planted mid-file (XML-1.0-illegal control char) must be scrubbed by the
    /// streaming sanitizer so the parse runs to EOF — records BEFORE and AFTER the bad byte both
    /// survive, and the import reports the skipped span rather than aborting the whole file.
    func testIllegalByteMidFileIsSanitizedAndBothSidesSurvive() throws {
        var bytes = Data()
        bytes.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="61"/>

        """.utf8))
        // Illegal control bytes mid-file (NUL + a lone 0x1F), between two valid records.
        bytes.append(contentsOf: [0x00, 0x1F])
        bytes.append(Data("""

         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W" unit="count/min" startDate="2024-01-02 09:00:00 +0000" endDate="2024-01-02 09:00:00 +0000" value="72"/>
        </HealthData>
        """.utf8))

        let r = try AppleHealthImporter().importXML(data: bytes)
        XCTAssertEqual(r.summary.recordCount, 2, "both records around the illegal byte must survive")
        XCTAssertGreaterThanOrEqual(r.summary.skippedSpans, 1, "the scrubbed illegal-byte run must be surfaced")
    }

    /// Invalid UTF-8 (a lone 0xFF continuation byte that is not part of any valid sequence) inside a
    /// text node is repaired to U+FFFD and does not abort the import.
    func testInvalidUTF8IsRepairedNotFatal() throws {
        var bytes = Data()
        bytes.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="
        """.utf8))
        bytes.append(contentsOf: [0xFF, 0xFE]) // invalid UTF-8 in the sourceName attribute value
        bytes.append(Data("""
        W" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="61"/>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W2" unit="count/min" startDate="2024-01-02 09:00:00 +0000" endDate="2024-01-02 09:00:00 +0000" value="72"/>
        </HealthData>
        """.utf8))

        let r = try AppleHealthImporter().importXML(data: bytes)
        // Both HeartRate records survive the repaired byte; the per-day aggregator counts each one.
        XCTAssertEqual(r.summary.recordCount, 2)
        XCTAssertGreaterThanOrEqual(r.summary.skippedSpans, 1)
    }

    /// TOLERANT PARSE layer: a hard, structural XML error (not a bad byte — the sanitizer can't fix
    /// a broken tag) AFTER at least one record was parsed keeps the partial result instead of
    /// discarding everything, and reports the truncated tail as a skipped span.
    func testHardParseErrorAfterRecordsKeepsPartialResult() throws {
        // Two valid records, then a malformed (never-closed, garbage) tag that libxml2 rejects.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="61"/>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W2" unit="count/min" startDate="2024-01-02 09:00:00 +0000" endDate="2024-01-02 09:00:00 +0000" value="72"/>
         <Record type="HKQuantityTypeIdentifierHeartRate" startDate=<<<BROKEN
        """
        let r = try AppleHealthImporter().importXML(data: Data(xml.utf8))
        // The two well-formed records before the break must survive.
        XCTAssertEqual(r.summary.recordCount, 2)
        XCTAssertGreaterThanOrEqual(r.summary.skippedSpans, 1, "the truncated tail must be surfaced as a skipped span")
    }

    /// A hard parse error with NO records parsed yet still throws (we don't silently swallow a
    /// completely broken file).
    func testHardParseErrorWithNoRecordsStillThrows() {
        let xml = "<<<not xml at all"
        XCTAssertThrowsError(try AppleHealthImporter().importXML(data: Data(xml.utf8)))
    }

    /// A clean export reports zero skipped spans (no false positives from the sanitizer).
    func testCleanFileReportsNoSkippedSpans() throws {
        let r = try parsed()
        XCTAssertEqual(r.summary.skippedSpans, 0)
    }

    /// A multi-byte UTF-8 character split across the sanitizer's chunk boundary must NOT be
    /// misclassified as invalid. We force a tiny chunk so the 2-byte "é" straddles two reads.
    func testMultiByteUTF8AcrossChunkBoundaryIsPreserved() throws {
        // "é" is U+00E9 = 0xC3 0xA9. Pad the sourceName so the split lands between those two bytes.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData>
         <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="caf\u{00E9}meter" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="61"/>
        </HealthData>
        """
        let data = Data(xml.utf8)

        // Drive the sanitizer directly with an 8-byte chunk so the multi-byte char is guaranteed to
        // be cut across a refill; then parse the sanitized output and confirm the value survived
        // and nothing was scrubbed.
        let san = SanitizingInputStream(source: InputStream(data: data), chunkSize: 8)
        let parser = XMLParser(stream: san)
        let delegate = HealthXMLDelegate()
        parser.delegate = delegate
        XCTAssertTrue(parser.parse(), "well-formed UTF-8 split across chunks must parse cleanly")
        XCTAssertEqual(san.scrubbedRunCount, 0, "a valid multi-byte char must not be scrubbed")
        let result = delegate.makeResult()
        XCTAssertEqual(result.summary.recordCount, 1, "the single well-formed record must parse")
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
