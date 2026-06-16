import XCTest
@testable import StrandAnalytics

final class SolarClockTests: XCTestCase {

    // Day-of-year anchors (non-leap year).
    private let equinoxMarch = 80   // ~Mar 21
    private let solsticeJune = 172  // ~Jun 21
    private let solsticeDec = 355   // ~Dec 21

    // MARK: - Physics-based checks (almanac-independent)

    /// On an equinox the day is ~12 h everywhere (slightly over 12 h because the
    /// −0.833° refraction altitude widens the window). Independent of longitude/zone.
    func testEquinoxDayLengthNear12hAtAllLatitudes() {
        for lat in [0.0, 19.43, 45.0, -33.9, 60.0] {
            let w = SolarClock.sunWindow(lat: lat, lon: 0, dayOfYear: equinoxMarch, gmtOffset: 0)
            let win = try! XCTUnwrap(w, "equinox window should exist at lat \(lat)")
            let dayLength = win.sunset - win.sunrise
            XCTAssertEqual(dayLength, 12.1, accuracy: 0.25,
                           "equinox day length should be ~12.1 h at lat \(lat), got \(dayLength)")
        }
    }

    /// Sunrise and sunset are symmetric about solar noon = 12 − λ/15 + gmtOffset.
    func testSymmetryAboutSolarNoon() {
        let lat = 19.43, lon = -99.13, gmt = -6.0
        let w = try! XCTUnwrap(SolarClock.sunWindow(lat: lat, lon: lon,
                                                    dayOfYear: solsticeJune, gmtOffset: gmt))
        let noon = 12.0 - lon / 15.0 + gmt
        XCTAssertEqual((w.sunrise + w.sunset) / 2.0, noon, accuracy: 1e-9)
    }

    /// At 45°N the day is long in June (~15.6 h) and short in December (~8.8 h);
    /// at 45°S the seasons flip. Magnitudes match standard solstice day lengths.
    func testSolsticeDayLengthAndSeasonalFlip() {
        let north = 45.0, south = -45.0
        let nJune = try! XCTUnwrap(SolarClock.sunWindow(lat: north, lon: 0, dayOfYear: solsticeJune, gmtOffset: 0))
        let nDec = try! XCTUnwrap(SolarClock.sunWindow(lat: north, lon: 0, dayOfYear: solsticeDec, gmtOffset: 0))
        XCTAssertEqual(nJune.sunset - nJune.sunrise, 15.6, accuracy: 0.4)
        XCTAssertEqual(nDec.sunset - nDec.sunrise, 8.8, accuracy: 0.4)

        let sJune = try! XCTUnwrap(SolarClock.sunWindow(lat: south, lon: 0, dayOfYear: solsticeJune, gmtOffset: 0))
        let sDec = try! XCTUnwrap(SolarClock.sunWindow(lat: south, lon: 0, dayOfYear: solsticeDec, gmtOffset: 0))
        // Southern hemisphere: short in June, long in December.
        XCTAssertEqual(sJune.sunset - sJune.sunrise, 8.8, accuracy: 0.4)
        XCTAssertEqual(sDec.sunset - sDec.sunrise, 15.6, accuracy: 0.4)
    }

    // MARK: - Real cities, within ±30 min of almanac values

    private func assertClose(_ actual: Double, _ expected: Double, _ label: String,
                             toleranceHours: Double = 0.5) {
        XCTAssertEqual(actual, expected, accuracy: toleranceHours,
                       "\(label): expected ~\(expected) h, got \(actual) h")
    }

    /// CDMX (19.43, −99.13, UTC−6, no DST). Real NOAA almanac: June solstice
    /// ≈ 05:59 / 19:18; March equinox ≈ 06:39 / 18:48. Approximation within ±30 min.
    func testMexicoCity() {
        let summer = try! XCTUnwrap(SolarClock.sunWindow(lat: 19.43, lon: -99.13,
                                                        dayOfYear: solsticeJune, gmtOffset: -6))
        assertClose(summer.sunrise, 5.98, "CDMX Jun sunrise")   // 05:59
        assertClose(summer.sunset, 19.30, "CDMX Jun sunset")    // 19:18

        let equinox = try! XCTUnwrap(SolarClock.sunWindow(lat: 19.43, lon: -99.13,
                                                         dayOfYear: equinoxMarch, gmtOffset: -6))
        assertClose(equinox.sunrise, 6.65, "CDMX Mar sunrise")  // 06:39
        assertClose(equinox.sunset, 18.80, "CDMX Mar sunset")   // 18:48
    }

    /// Tokyo (35.65, 139.74, UTC+9, no DST). Real NOAA almanac: June solstice
    /// ≈ 04:26 / 19:00.
    func testTokyo() {
        let w = try! XCTUnwrap(SolarClock.sunWindow(lat: 35.65, lon: 139.74,
                                                   dayOfYear: solsticeJune, gmtOffset: 9))
        assertClose(w.sunrise, 4.43, "Tokyo Jun sunrise")   // 04:26
        assertClose(w.sunset, 19.00, "Tokyo Jun sunset")    // 19:00
    }

    /// Quito (−0.18, −78.5, UTC−5). On the equator the window is ~12 h year-round;
    /// real NOAA almanac at the equinox ≈ 06:18 / 18:24.
    func testQuito() {
        let w = try! XCTUnwrap(SolarClock.sunWindow(lat: -0.18, lon: -78.5,
                                                   dayOfYear: equinoxMarch, gmtOffset: -5))
        assertClose(w.sunrise, 6.30, "Quito sunrise")   // 06:18
        assertClose(w.sunset, 18.40, "Quito sunset")    // 18:24
    }

    // MARK: - Polar edge cases → nil

    func testPolarNightAndMidnightSunReturnNil() {
        // High north: midnight sun in June, polar night in December.
        XCTAssertNil(SolarClock.sunWindow(lat: 80, lon: 0, dayOfYear: solsticeJune, gmtOffset: 0))
        XCTAssertNil(SolarClock.sunWindow(lat: 80, lon: 0, dayOfYear: solsticeDec, gmtOffset: 0))
        // High south: seasons flipped.
        XCTAssertNil(SolarClock.sunWindow(lat: -80, lon: 0, dayOfYear: solsticeJune, gmtOffset: 0))
        XCTAssertNil(SolarClock.sunWindow(lat: -80, lon: 0, dayOfYear: solsticeDec, gmtOffset: 0))
    }

    func testMidLatitudeNeverNil() {
        for day in stride(from: 1, through: 365, by: 30) {
            XCTAssertNotNil(SolarClock.sunWindow(lat: 45, lon: 0, dayOfYear: day, gmtOffset: 0),
                            "lat 45 should always have a sunrise/sunset (day \(day))")
        }
    }

    // MARK: - Coordinate resolution from TimeZone (no permission)

    func testRepresentativeCoordinateFromKnownZones() {
        let mx = SolarClock.representativeCoordinate(for: TimeZone(identifier: "America/Mexico_City")!)
        XCTAssertEqual(mx.lat, 19.4, accuracy: 0.1)
        XCTAssertEqual(mx.lon, -99.15, accuracy: 0.1)

        let london = SolarClock.representativeCoordinate(for: TimeZone(identifier: "Europe/London")!)
        XCTAssertEqual(london.lat, 51.51, accuracy: 0.1)
        XCTAssertEqual(london.lon, -0.13, accuracy: 0.1)

        let tokyo = SolarClock.representativeCoordinate(for: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(tokyo.lat, 35.65, accuracy: 0.1)
        XCTAssertEqual(tokyo.lon, 139.74, accuracy: 0.1)
    }

    /// An unknown (fixed-offset) zone falls back to longitude from the UTC offset
    /// (15°/h) at the default mid-latitude — no CoreLocation.
    func testFallbackByGMTOffsetForUnknownZone() {
        let west = SolarClock.representativeCoordinate(for: TimeZone(secondsFromGMT: -6 * 3600)!)
        XCTAssertEqual(west.lat, SolarClock.fallbackLatitude, accuracy: 1e-9)
        XCTAssertEqual(west.lon, -90.0, accuracy: 1e-9)   // −6 h × 15°/h

        let east = SolarClock.representativeCoordinate(for: TimeZone(secondsFromGMT: 5 * 3600)!)
        XCTAssertEqual(east.lat, SolarClock.fallbackLatitude, accuracy: 1e-9)
        XCTAssertEqual(east.lon, 75.0, accuracy: 1e-9)    // +5 h × 15°/h
    }

    // MARK: - Convenience: Date + TimeZone

    func testSunWindowOnDateResolvesZone() {
        var cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "America/Mexico_City")!
        cal.timeZone = tz
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 21))!

        let w = try! XCTUnwrap(SolarClock.sunWindow(on: date, in: tz))
        // Must match the core call with the table coordinate, day-of-year 80, UTC−6.
        let core = try! XCTUnwrap(SolarClock.sunWindow(lat: 19.4, lon: -99.15,
                                                      dayOfYear: 80, gmtOffset: -6))
        XCTAssertEqual(w.sunrise, core.sunrise, accuracy: 1e-6)
        XCTAssertEqual(w.sunset, core.sunset, accuracy: 1e-6)
        assertClose(w.sunrise, 6.65, "CDMX convenience sunrise")  // real ≈ 06:39
        assertClose(w.sunset, 18.80, "CDMX convenience sunset")   // real ≈ 18:48
    }

    /// A polar zone resolved from its identifier yields nil at both solstices.
    func testConveniencePolarZoneReturnsNil() {
        let tz = TimeZone(identifier: "Antarctica/Vostok")! // −78.4° latitude
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let june = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!
        let dec = cal.date(from: DateComponents(year: 2026, month: 12, day: 21))!
        XCTAssertNil(SolarClock.sunWindow(on: june, in: tz)) // polar night (S winter)
        XCTAssertNil(SolarClock.sunWindow(on: dec, in: tz))  // midnight sun (S summer)
    }
}
