import XCTest
@testable import StrandAnalytics

/// FER-350 — per-muscle load / freshness crossed with systemic recovery. Covers the empty state,
/// the cited decay, the primary/secondary weighting, the window cutoff, relative normalization, the
/// Schoenfeld weekly band, the systemic-recovery cross, and days-since-last.
final class MuscleFatigueMapTests: XCTestCase {

    typealias Event = MuscleFatigueMap.MuscleSetEvent

    // 1 — no events → empty map (the honest empty state).
    func testNoEventsIsEmpty() {
        XCTAssertTrue(MuscleFatigueMap.loads(events: [], window: .d7).isEmpty)
    }

    // 2 — decay is monotonic: a set today loads more than the same set 2 then 4 days ago.
    func testDecayIsMonotonicByRecency() {
        XCTAssertGreaterThan(MuscleFatigueMap.decay(daysAgo: 0), MuscleFatigueMap.decay(daysAgo: 2))
        XCTAssertGreaterThan(MuscleFatigueMap.decay(daysAgo: 2), MuscleFatigueMap.decay(daysAgo: 4))
        // 2-day half-life: today = 1.0, 2d ago = 0.5, 4d ago = 0.25.
        XCTAssertEqual(MuscleFatigueMap.decay(daysAgo: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MuscleFatigueMap.decay(daysAgo: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MuscleFatigueMap.decay(daysAgo: 4), 0.25, accuracy: 1e-9)
    }

    // 3 — a primary muscle (1.0) loads exactly twice a secondary (0.5) at the same recency.
    func testPrimaryIsTwiceSecondary() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "chest", involvement: 1.0, daysAgo: 1),
            Event(muscle: "triceps", involvement: 0.5, daysAgo: 1),
        ], window: .d7)
        let chest = loads.first { $0.muscle == "chest" }!
        let triceps = loads.first { $0.muscle == "triceps" }!
        XCTAssertEqual(chest.load, triceps.load * 2, accuracy: 1e-9)
    }

    // 4 — the window filters: a set 10 days ago is out for d7, in for d14.
    func testWindowCutoff() {
        let events = [Event(muscle: "lats", involvement: 1.0, daysAgo: 10)]
        XCTAssertTrue(MuscleFatigueMap.loads(events: events, window: .d7).isEmpty)
        XCTAssertEqual(MuscleFatigueMap.loads(events: events, window: .d14).count, 1)
    }

    // 5 — relative load is normalized to the user's most-loaded muscle (= 1.0).
    func testRelativeNormalizationToMax() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "quadriceps", involvement: 1.0, daysAgo: 0),  // biggest
            Event(muscle: "calves", involvement: 0.5, daysAgo: 4),      // smaller
        ], window: .d7)
        let quads = loads.first { $0.muscle == "quadriceps" }!
        XCTAssertEqual(quads.relative, 1.0, accuracy: 1e-9)
        XCTAssertEqual(quads.state, .loaded)
        let calves = loads.first { $0.muscle == "calves" }!
        XCTAssertLessThan(calves.relative, 1.0)
    }

    // 6 — weekly volume vs the Schoenfeld 10–20 band: below / within / above.
    func testWeeklyBand() {
        XCTAssertEqual(MuscleFatigueMap.band(weeklySets: 5), .below)
        XCTAssertEqual(MuscleFatigueMap.band(weeklySets: 15), .within)
        XCTAssertEqual(MuscleFatigueMap.band(weeklySets: 25), .above)
    }

    // weeklySets only counts the last 7 days, never decayed; a set 10 days ago (d14 window) adds 0.
    func testWeeklySetsIgnoreBeyond7Days() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "lats", involvement: 1.0, daysAgo: 10),
            Event(muscle: "lats", involvement: 1.0, daysAgo: 1),
        ], window: .d14)
        XCTAssertEqual(loads.first { $0.muscle == "lats" }!.weeklySets, 1.0, accuracy: 1e-9)
    }

    // 7 — cross with systemic recovery: red recovery gates everything; high recovery clears fresh muscles.
    func testSystemicRecoveryGate() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "chest", involvement: 1.0, daysAgo: 0),   // loaded (the max)
            Event(muscle: "calves", involvement: 0.5, daysAgo: 6),  // fresh
        ], window: .d7)

        let gated = MuscleFatigueMap.recommendation(loads: loads, recovery: 20)
        XCTAssertTrue(gated.gatedBySystemic)
        XCTAssertTrue(gated.readyMuscles.isEmpty)

        let cleared = MuscleFatigueMap.recommendation(loads: loads, recovery: 80)
        XCTAssertFalse(cleared.gatedBySystemic)
        XCTAssertTrue(cleared.readyMuscles.contains("calves"))
        XCTAssertFalse(cleared.readyMuscles.contains("chest"))
    }

    // readiness: red recovery → rest even for a fresh muscle; otherwise fresh → ready, loaded → caution.
    func testReadinessMatrix() {
        XCTAssertEqual(MuscleFatigueMap.readiness(state: .fresh, recovery: 20), .rest)
        XCTAssertEqual(MuscleFatigueMap.readiness(state: .fresh, recovery: 80), .ready)
        XCTAssertEqual(MuscleFatigueMap.readiness(state: .loaded, recovery: 80), .caution)
        XCTAssertEqual(MuscleFatigueMap.readiness(state: .fresh, recovery: nil), .ready)
    }

    // 8 — daysSinceLast is the most recent set that hit the muscle.
    func testDaysSinceLast() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "biceps", involvement: 1.0, daysAgo: 5),
            Event(muscle: "biceps", involvement: 1.0, daysAgo: 2),
        ], window: .d7)
        XCTAssertEqual(loads.first { $0.muscle == "biceps" }!.daysSinceLast, 2)
    }
}
