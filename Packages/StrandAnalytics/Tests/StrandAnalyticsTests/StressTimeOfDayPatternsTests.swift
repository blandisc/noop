import XCTest
import Foundation
@testable import StrandAnalytics

final class StressTimeOfDayPatternsTests: XCTestCase {

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    /// Day key for day `i` starting 2025-05-01 (UTC), contiguous.
    private func dayKey(_ i: Int) -> String {
        let d = StressTimeOfDayPatterns.utcCalendar.date(from: DateComponents(year: 2025, month: 5, day: 1 + i))!
        return Self.fmt.string(from: d)
    }

    func testDetectsMorningHigherAndPeakCluster() {
        var s: [String: StressDaySummary] = [:]
        for i in 0..<24 {
            let j = Double(i)
            let morning = 2.5 + 0.12 * sin(j)        // clearly higher, with variance
            let other = 0.8 + 0.12 * cos(j)          // clearly lower, with variance
            s[dayKey(i)] = StressDaySummary(
                partMeans: [.morning: morning, .afternoon: other, .evening: other],
                peakHour: 9, dayMean: (morning + 2 * other) / 3)
        }
        let patterns = StressTimeOfDayPatterns.detect(summariesByDay: s, maxPatterns: 10)
        XCTAssertTrue(patterns.contains { $0.family == .partOfDay(.morning) && $0.higher },
                      "a consistently more-activated morning should surface")
        XCTAssertTrue(patterns.contains { $0.family == .peakHour(9) },
                      "a daily peak clustered at 9 should surface")
    }

    func testPartOfDayUsesPerDayPairedContrast() {
        // The day's overall level wanders, but morning stays well above its OWN day's other parts. A
        // per-day paired contrast detects this steady within-day effect (each day = ONE observation);
        // the old pseudo-replicated pooling would have drowned it in the between-day level swings.
        var s: [String: StressDaySummary] = [:]
        for i in 0..<16 {
            let base = 1.0 + 0.3 * sin(Double(i))            // the day's level wanders
            let margin = 0.9 + 0.06 * sin(Double(i) * 2)     // morning steady above its own day
            s[dayKey(i)] = StressDaySummary(
                partMeans: [.morning: base + margin, .afternoon: base, .evening: base - 0.1],
                peakHour: nil, dayMean: base + margin / 3)
        }
        let patterns = StressTimeOfDayPatterns.detect(summariesByDay: s, maxPatterns: 10)
        XCTAssertTrue(patterns.contains { $0.family == .partOfDay(.morning) && $0.higher },
                      "a steady within-day morning elevation should surface via the paired contrast")
    }

    func testNoPatternsBelowMinDays() {
        var s: [String: StressDaySummary] = [:]
        for i in 0..<10 {     // < minDays
            s[dayKey(i)] = StressDaySummary(partMeans: [.morning: 2.5, .afternoon: 0.8], peakHour: 9, dayMean: 1.6)
        }
        XCTAssertTrue(StressTimeOfDayPatterns.detect(summariesByDay: s).isEmpty)
    }

    func testFlatDayYieldsNoPartOrPeakPattern() {
        var s: [String: StressDaySummary] = [:]
        for i in 0..<24 {
            let j = Double(i)
            s[dayKey(i)] = StressDaySummary(
                partMeans: [.morning: 1.4 + 0.1 * sin(j),
                            .afternoon: 1.4 + 0.1 * cos(j),
                            .evening: 1.4 + 0.1 * sin(j + 1)],   // all parts share the same level
                peakHour: 6 + (i % 12),                          // scattered peaks → no cluster
                dayMean: 1.4 + 0.05 * sin(j))
        }
        let patterns = StressTimeOfDayPatterns.detect(summariesByDay: s, maxPatterns: 10)
        XCTAssertFalse(patterns.contains { if case .partOfDay = $0.family { return true }; return false })
        XCTAssertFalse(patterns.contains { if case .peakHour = $0.family { return true }; return false })
    }

    func testDominantPeakHour() {
        XCTAssertEqual(StressTimeOfDayPatterns.dominantPeakHour([9, 9, 10, 8, 9, 15, 9, 10]), 9)  // clusters at 9
        XCTAssertNil(StressTimeOfDayPatterns.dominantPeakHour([1, 5, 9, 13, 17, 21, 3, 7]))       // scattered
    }
}
