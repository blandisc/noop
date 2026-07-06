import XCTest
@testable import StrandAnalytics

/// FER-350 / FER-719 — per-muscle load / freshness crossed with systemic recovery. Covers the empty
/// state, the cited decay (2-day half-life, exact input→output cases), the primary/secondary
/// weighting, relative normalization, the Schoenfeld weekly band, the systemic-recovery cross,
/// days-since-last, and the weekly-volume-per-muscle API for the «Volumen por músculo» screen.
final class MuscleFatigueMapTests: XCTestCase {

    typealias Event = MuscleFatigueMap.MuscleSetEvent

    // 1 — no events → empty map (the honest empty state).
    func testNoEventsIsEmpty() {
        XCTAssertTrue(MuscleFatigueMap.loads(events: []).isEmpty)
    }

    // 2 — the cited decay, exact input→output (FER-719 acceptance criterion): a set 0/2/4/8 days
    // ago weighs 1.0 / 0.5 / 0.25 / 0.0625 (2-day half-life, MacDougall 1995; Damas 2015).
    func testDecayExactCases() {
        XCTAssertEqual(MuscleFatigueMap.decay(daysAgo: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MuscleFatigueMap.decay(daysAgo: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MuscleFatigueMap.decay(daysAgo: 4), 0.25, accuracy: 1e-9)
        XCTAssertEqual(MuscleFatigueMap.decay(daysAgo: 8), 0.0625, accuracy: 1e-9)
        // monotonic in recency
        XCTAssertGreaterThan(MuscleFatigueMap.decay(daysAgo: 0), MuscleFatigueMap.decay(daysAgo: 2))
        XCTAssertGreaterThan(MuscleFatigueMap.decay(daysAgo: 2), MuscleFatigueMap.decay(daysAgo: 4))
    }

    // 3 — a primary muscle (1.0) loads exactly twice a secondary (0.5) at the same recency.
    func testPrimaryIsTwiceSecondary() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "chest", involvement: 1.0, daysAgo: 1),
            Event(muscle: "triceps", involvement: 0.5, daysAgo: 1),
        ])
        let chest = loads.first { $0.muscle == "chest" }!
        let triceps = loads.first { $0.muscle == "triceps" }!
        XCTAssertEqual(chest.load, triceps.load * 2, accuracy: 1e-9)
    }

    // 4 — no recency window (FER-719): an old set still enters the map, but the decay alone has
    // already made it negligible — time lives in the math, not in a filter.
    func testNoWindowDecayCarriesTime() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "lats", involvement: 1.0, daysAgo: 10),
        ])
        XCTAssertEqual(loads.count, 1)
        XCTAssertEqual(loads[0].load, pow(2.0, -5), accuracy: 1e-9)   // ≈ 0.031
        // a negative daysAgo (future set) is invalid input and is dropped
        XCTAssertTrue(MuscleFatigueMap.loads(events: [Event(muscle: "x", involvement: 1, daysAgo: -1)]).isEmpty)
    }

    // 5 — relative load is normalized to the user's most-loaded muscle (= 1.0).
    func testRelativeNormalizationToMax() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "quadriceps", involvement: 1.0, daysAgo: 0),  // biggest
            Event(muscle: "calves", involvement: 0.5, daysAgo: 4),      // smaller
        ])
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

    // weeklySets only counts the last 7 days, never decayed; a set 10 days ago adds 0 to it even
    // though it still (negligibly) enters the load.
    func testWeeklySetsIgnoreBeyond7Days() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "lats", involvement: 1.0, daysAgo: 10),
            Event(muscle: "lats", involvement: 1.0, daysAgo: 1),
        ])
        XCTAssertEqual(loads.first { $0.muscle == "lats" }!.weeklySets, 1.0, accuracy: 1e-9)
    }

    // 7 — cross with systemic recovery: red recovery gates everything; high recovery clears fresh muscles.
    func testSystemicRecoveryGate() {
        let loads = MuscleFatigueMap.loads(events: [
            Event(muscle: "chest", involvement: 1.0, daysAgo: 0),   // loaded (the max)
            Event(muscle: "calves", involvement: 0.5, daysAgo: 6),  // fresh
        ])

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
        ])
        XCTAssertEqual(loads.first { $0.muscle == "biceps" }!.daysSinceLast, 2)
    }

    // MARK: - Weekly volume per muscle (FER-719, the «Volumen por músculo» screen)

    // 9 — exact input→output: 28 days with 48 involvement-weighted sets of chest → 12/week (within);
    // 8 sets of hamstrings over the same 4 weeks → 2/week (below → amber in the UI).
    func testWeeklyVolumesAveragesOverTheFullSpan() {
        // 48 chest sets and 16 half-involvement hamstring sets spread anywhere inside the 28-day
        // span — the average only depends on the totals.
        let events = (0..<48).map { Event(muscle: "chest", involvement: 1.0, daysAgo: $0 % 28) }
            + (0..<16).map { Event(muscle: "hamstrings", involvement: 0.5, daysAgo: $0 % 28) }

        let vols = MuscleFatigueMap.weeklyVolumes(events: events, days: 28)
        let chest = vols.first { $0.muscle == "chest" }!
        XCTAssertEqual(chest.setsPerWeek, 12.0, accuracy: 1e-9)     // 48 / 4 weeks
        XCTAssertEqual(chest.band, .within)
        let hams = vols.first { $0.muscle == "hamstrings" }!
        XCTAssertEqual(hams.setsPerWeek, 2.0, accuracy: 1e-9)       // 16·0.5 / 4 weeks
        XCTAssertEqual(hams.band, .below)
        // sorted by volume descending
        XCTAssertEqual(vols.map(\.muscle), ["chest", "hamstrings"])
    }

    // 10 — the span filters: a set outside the trailing `days` doesn't count; the divisor is the
    // full span even if the user only trained part of it (honest average, not best week).
    func testWeeklyVolumesSpanFilterAndDilution() {
        let events = [
            Event(muscle: "back", involvement: 1.0, daysAgo: 3),
            Event(muscle: "back", involvement: 1.0, daysAgo: 40),   // outside a 30-day span
        ]
        let vols = MuscleFatigueMap.weeklyVolumes(events: events, days: 30)
        XCTAssertEqual(vols.count, 1)
        XCTAssertEqual(vols[0].setsPerWeek, 1.0 / (30.0 / 7.0), accuracy: 1e-9)   // ≈ 0.23/wk
        XCTAssertEqual(vols[0].band, .below)
        // days is clamped to ≥ 7 (a week is the smallest unit)
        let clamped = MuscleFatigueMap.weeklyVolumes(events: [Event(muscle: "back", involvement: 1.0, daysAgo: 0)], days: 1)
        XCTAssertEqual(clamped[0].setsPerWeek, 1.0, accuracy: 1e-9)
    }
}
