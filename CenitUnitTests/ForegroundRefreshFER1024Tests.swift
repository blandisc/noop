import XCTest
@testable import Cenit

/// FER-1024: pins the pure day-rollover decision that governs whether a foreground return must force
/// a dashboard rebuild. This is the whole risk of the change — getting the midnight boundary wrong
/// reintroduces the FER-224/226/630 "«Hoy» shows yesterday after midnight" class, which cannot be
/// verified without a device crossing a real scene+midnight cycle. The pure function lets us pin it
/// on the fast loop instead.
final class ForegroundRefreshFER1024Tests: XCTestCase {

    // Nothing published yet → the launch sequence owns first paint; never force here.
    func testNilLastPublishedDayNeverForces() {
        XCTAssertFalse(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: nil,
                                                               currentDay: "2026-07-21"))
    }

    // Same local day → no forced rebuild; HealthKitBridge.sync's guarded refresh covers new data.
    func testSameDayDoesNotForce() {
        XCTAssertFalse(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: "2026-07-21",
                                                               currentDay: "2026-07-21"))
    }

    // Day rolled over (the midnight case) → force exactly one rebuild so «Hoy» re-buckets to today.
    func testDayRolloverForces() {
        XCTAssertTrue(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: "2026-07-20",
                                                              currentDay: "2026-07-21"))
    }

    // Month/year boundaries are just string inequality — no calendar math to get wrong.
    func testMonthAndYearBoundariesForce() {
        XCTAssertTrue(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: "2026-07-31",
                                                              currentDay: "2026-08-01"))
        XCTAssertTrue(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: "2025-12-31",
                                                              currentDay: "2026-01-01"))
    }

    /// An unfinished full pass forces a refresh even on the SAME day. First paint already stamps
    /// `lastRefreshDayKey = today`, so a user who backgrounds the app mid-load and returns the same
    /// day would otherwise never complete it — and with the «Preparación» verdict published only by
    /// the full pass, the hero would sit on «Leyendo tu noche…» all day.
    func testIncompleteFullPassForcesEvenSameDay() {
        XCTAssertTrue(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: "2026-07-21",
                                                              currentDay: "2026-07-21",
                                                              fullyLoaded: false),
                      "un pase completo a medias debe reintentarse aunque no haya cambiado el día")
        // Ya cargado y mismo día → sigue sin forzar (la conducta FER-1024 original, intacta).
        XCTAssertFalse(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: "2026-07-21",
                                                               currentDay: "2026-07-21",
                                                               fullyLoaded: true))
        // Nada publicado todavía → la secuencia de arranque manda, aunque no esté cargado.
        XCTAssertFalse(AppModel.shouldForceRefreshOnForeground(lastPublishedDay: nil,
                                                               currentDay: "2026-07-21",
                                                               fullyLoaded: false))
    }
}
