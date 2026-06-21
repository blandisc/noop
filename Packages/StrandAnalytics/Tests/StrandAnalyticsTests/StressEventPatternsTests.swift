import XCTest
import Foundation
@testable import StrandAnalytics

final class StressEventPatternsTests: XCTestCase {

    private func dayKey(_ i: Int) -> String { String(format: "2025-05-%02d", i + 1) }

    func testDetectsRecurringEventWithHigherStress() {
        // 30 days. "Junta Q" on 10 of them, all higher stress; the other 20 lower. Both groups ≥5.
        var dayMean: [String: Double] = [:]
        var eventDays: Set<String> = []
        for i in 0..<30 {
            let isEvent = i % 3 == 0                       // 10 of 30
            let j = Double(i)
            dayMean[dayKey(i)] = isEvent ? 2.4 + 0.1 * sin(j) : 0.9 + 0.1 * cos(j)
            if isEvent { eventDays.insert(dayKey(i)) }
        }
        let patterns = StressEventPatterns.detect(eventDaysByType: ["Junta Q": eventDays], dayMeanByDay: dayMean)
        XCTAssertEqual(patterns.first?.title, "Junta Q")
        XCTAssertEqual(patterns.first?.higher, true)
    }

    func testOneOffEventIsNotAPattern() {
        // Same stress field, but "Dentista" only on 3 days (< the ≥5-per-side floor) → never a pattern.
        var dayMean: [String: Double] = [:]
        for i in 0..<30 { dayMean[dayKey(i)] = 1.3 + 0.1 * sin(Double(i)) }
        let three: Set<String> = [dayKey(0), dayKey(1), dayKey(2)]
        XCTAssertTrue(StressEventPatterns.detect(eventDaysByType: ["Dentista": three], dayMeanByDay: dayMean).isEmpty)
    }

    func testNoEffectWhenStressIsFlat() {
        // "Standup" on 10 days, but stress is the same distribution on event and non-event days.
        var dayMean: [String: Double] = [:]
        var eventDays: Set<String> = []
        for i in 0..<30 {
            dayMean[dayKey(i)] = 1.3 + 0.1 * sin(Double(i))
            if i % 3 == 0 { eventDays.insert(dayKey(i)) }
        }
        XCTAssertTrue(StressEventPatterns.detect(eventDaysByType: ["Standup": eventDays], dayMeanByDay: dayMean).isEmpty)
    }

    func testEmptyInputs() {
        XCTAssertTrue(StressEventPatterns.detect(eventDaysByType: [:], dayMeanByDay: ["2025-05-01": 1.0]).isEmpty)
        XCTAssertTrue(StressEventPatterns.detect(eventDaysByType: ["X": ["2025-05-01"]], dayMeanByDay: [:]).isEmpty)
    }
}
