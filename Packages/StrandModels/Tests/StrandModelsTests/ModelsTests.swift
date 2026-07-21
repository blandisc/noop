import XCTest
@testable import StrandModels

final class ModelsTests: XCTestCase {
    func testDailyMetricCodableRoundTrip() throws {
        let original = DailyMetric(
            day: "2026-07-20",
            totalSleepMin: 420,
            efficiency: 0.91,
            deepMin: 90,
            remMin: 100,
            lightMin: 230,
            disturbances: 2,
            restingHr: 52,
            avgHrv: 48.5,
            recovery: 72,
            strain: 11.2,
            exerciseCount: 1,
            spo2Pct: 96.5,
            skinTempDevC: -0.3,
            respRateBpm: 14.2,
            steps: 8_400,
            activeKcalEst: 520,
            effortConfidence: "solid",
            restConfidence: "building"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DailyMetric.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCachedSleepSessionCodableRoundTrip() throws {
        let original = CachedSleepSession(
            startTs: 1_721_404_800,
            endTs: 1_721_433_600,
            efficiency: 0.88,
            restingHr: 50,
            avgHrv: 55.0,
            stagesJSON: #"[{"start":0,"end":3600,"stage":"deep"}]"#
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CachedSleepSession.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
