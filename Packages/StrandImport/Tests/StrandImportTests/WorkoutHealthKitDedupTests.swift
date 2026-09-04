import XCTest
@testable import StrandImport

/// Ola 2 · C4 (FER-362): the pure de-dup of third-party strength workouts read from Apple Health.
/// The invariant the user feels: never the same workout twice. Rich sessions (Cénit or CSV) win over an
/// Apple echo; two apps that recorded the same session collapse to one; and the overlap rule is interval
/// overlap, not a start-time window.
final class WorkoutHealthKitDedupTests: XCTestCase {

    private typealias W = WorkoutHealthKitDedup.Workout
    private typealias R = WorkoutHealthKitDedup.RichInterval

    private func apple(_ start: Int, _ end: Int, _ sport: String = "TraditionalStrengthTraining",
                       name: String = "Strong") -> W {
        W(startTs: start, endTs: end, sport: sport, durationS: Double(end - start),
          source: "apple-health:\(name)")
    }

    // MARK: rich always wins (echo)

    func testAppleEchoOfCenitSessionIsDropped() {
        let rows = [apple(1000, 4000)]                       // Apple strength envelope
        let rich = [R(startTs: 1000, endTs: 4000)]           // the Cénit session it echoes
        XCTAssertTrue(WorkoutHealthKitDedup.survivingRows(rows, richSessions: rich).isEmpty)
    }

    func testAppleEchoOfCSVSessionIsDropped() {
        // A CSV-imported session is just another completed StrengthSession → the same RichInterval here.
        let rows = [apple(1000, 4000, name: "Strong")]
        let rich = [R(startTs: 1100, endTs: 3900)]           // overlapping CSV session
        XCTAssertTrue(WorkoutHealthKitDedup.survivingRows(rows, richSessions: rich).isEmpty)
    }

    func testEchoUsesIntervalOverlapNotStartWindow() {
        // Echo 40 min INTO a 90-min rich session: start times are 40 min apart (outside a ±30-min
        // start window) but the intervals DO overlap → it must still be dropped.
        let rich = [R(startTs: 0, endTs: 90 * 60)]
        let echo = apple(40 * 60, 80 * 60)                   // starts at min 40, well inside
        XCTAssertTrue(WorkoutHealthKitDedup.survivingRows([echo], richSessions: rich).isEmpty)
    }

    // MARK: third-vs-third collapse

    func testTwoAppsSameSessionCollapseToLongest() {
        let long = apple(1000, 4000, name: "Strong")         // 50 min
        let short = apple(1200, 3000, name: "AppleWatch")    // 30 min, overlaps `long`
        let survivors = WorkoutHealthKitDedup.survivingRows([long, short], richSessions: [])
        XCTAssertEqual(survivors, [long])                    // longest wins, the other collapses away
    }

    func testTwentyMinApartDoNotCollapse() {
        // Two 20-min workouts whose starts are 25 min apart do NOT overlap → both survive (this is
        // exactly what a ±30-min start-window would have wrongly collapsed).
        let a = apple(0, 20 * 60, name: "Strong")
        let b = apple(25 * 60, 45 * 60, name: "Hevy")
        let survivors = WorkoutHealthKitDedup.survivingRows([a, b], richSessions: [])
        XCTAssertEqual(survivors.count, 2)
    }

    func testNonOverlappingThirdPartySurvives() {
        let a = apple(0, 3000)
        let b = apple(100_000, 103_000)
        XCTAssertEqual(WorkoutHealthKitDedup.survivingRows([a, b], richSessions: []).count, 2)
    }

    // MARK: origin gate — only apple rows are ever hidden

    func testManualStrengthOverlappingRichIsNotDropped() {
        let manual = W(startTs: 1000, endTs: 4000, sport: "TraditionalStrengthTraining",
                       durationS: 3000, source: "manual")
        let rich = [R(startTs: 1000, endTs: 4000)]
        XCTAssertEqual(WorkoutHealthKitDedup.survivingRows([manual], richSessions: rich), [manual])
    }

    func testWhoopStrengthOverlappingRichIsNotDropped() {
        let whoop = W(startTs: 1000, endTs: 4000, sport: "TraditionalStrengthTraining",
                      durationS: 3000, source: "whoop")
        let rich = [R(startTs: 1000, endTs: 4000)]
        XCTAssertEqual(WorkoutHealthKitDedup.survivingRows([whoop], richSessions: rich), [whoop])
    }

    // MARK: cardio / non-strength pass through

    func testAppleRunningOverlappingRichSurvives() {
        // A run is not strength (loose heuristic doesn't match "Running"), so it's never an echo and
        // never collapses — even overlapping a strength session.
        let run = W(startTs: 1000, endTs: 4000, sport: "Running", durationS: 3000,
                    source: "apple-health:Strava")
        let rich = [R(startTs: 1000, endTs: 4000)]
        XCTAssertEqual(WorkoutHealthKitDedup.survivingRows([run], richSessions: rich), [run])
    }

    func testClosedStrengthSetIsClosed() {
        XCTAssertTrue(WorkoutHealthKitDedup.isClosedStrength("TraditionalStrengthTraining"))
        XCTAssertTrue(WorkoutHealthKitDedup.isClosedStrength("FunctionalStrengthTraining"))
        XCTAssertFalse(WorkoutHealthKitDedup.isClosedStrength("HighIntensityIntervalTraining"))
        XCTAssertFalse(WorkoutHealthKitDedup.isClosedStrength("CoreTraining"))
        XCTAssertFalse(WorkoutHealthKitDedup.isClosedStrength("Running"))
    }

    // MARK: order preserved

    func testSurvivorsKeepInputOrder() {
        let a = apple(100_000, 103_000, name: "Strong")      // newest
        let b = apple(1000, 4000, name: "Hevy")              // oldest
        let survivors = WorkoutHealthKitDedup.survivingRows([a, b], richSessions: [])
        XCTAssertEqual(survivors, [a, b])                    // input order, not re-sorted
    }
}
