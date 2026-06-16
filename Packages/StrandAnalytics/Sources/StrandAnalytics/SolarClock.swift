import Foundation

// SolarClock.swift — approximate local sunrise / sunset WITHOUT GPS, network, or
// any location permission. Pure and database-free (the StrandAnalytics rule); the
// only platform dependency is Foundation's `TimeZone` / `Calendar`.
//
// Method — the NOAA sunrise/sunset solar-geometry approximation (NOAA Global
// Monitoring Laboratory, Solar Calculator: https://gml.noaa.gov/grad/solcalc/).
// We use the low-precision form that models Earth's orbit as circular and ignores
// the equation of time, which is accurate to roughly ±15 min at low and mid
// latitudes — plenty for a 24-hour dial face. The steps (all angles in degrees):
//
//   declination   δ    = −23.44° · cos( 360/365 · (N + 10) )      (N = day-of-year)
//   hour angle    cosH = ( sin(−0.833°) − sinφ·sinδ ) / (cosφ·cosδ)
//   solar noon    noon = 12 − λ/15 + gmtOffset            (local clock hours)
//   sunrise = noon − H/15        sunset = noon + H/15      (H = acos(cosH), degrees)
//
// −0.833° is the official NOAA sunrise/sunset solar altitude (−50′: 34′ of mean
// atmospheric refraction + 16′ solar semi-diameter). When |cosH| > 1 the sun never
// reaches that altitude on the given day — polar night or midnight sun — and we
// return nil.

public enum SolarClock {

    // MARK: - Core (pure NOAA approximation)

    /// Local sunrise and sunset, as clock hours (e.g. 6.5 == 06:30), for a location
    /// and day. Returns nil for the polar edge cases — midnight sun or polar night —
    /// where the sun does not cross the horizon that day (|cosH| > 1).
    ///
    /// Hours are in the zone's local clock and may fall fractionally outside
    /// [0, 24) at extreme in-zone longitudes; callers placing them on a 24-hour
    /// face can wrap with `truncatingRemainder(dividingBy: 24)`.
    ///
    /// - Parameters:
    ///   - lat: latitude φ in degrees, north positive.
    ///   - lon: longitude λ in degrees, east positive.
    ///   - dayOfYear: N, day-of-year 1...366.
    ///   - gmtOffset: the zone's offset from UTC in hours (e.g. −6 for CST).
    public static func sunWindow(lat: Double, lon: Double, dayOfYear: Int, gmtOffset: Double)
        -> (sunrise: Double, sunset: Double)? {
        let deg = Double.pi / 180.0

        // Solar declination — Cooper's approximation, as used by the NOAA calculator.
        let declination = -23.44 * cos((360.0 / 365.0) * Double(dayOfYear + 10) * deg)

        let phi = lat * deg
        let delta = declination * deg

        // Hour angle at the −0.833° sunrise/sunset altitude.
        let cosH = (sin(-0.833 * deg) - sin(phi) * sin(delta)) / (cos(phi) * cos(delta))

        // |cosH| > 1 → the sun stays fully above (midnight sun) or below (polar
        // night) the horizon all day: no sunrise/sunset exists.
        guard cosH >= -1.0, cosH <= 1.0 else { return nil }

        let hourAngle = acos(cosH) / deg        // degrees
        let noon = 12.0 - lon / 15.0 + gmtOffset // local clock hours
        let halfDay = hourAngle / 15.0           // degrees → hours
        return (sunrise: noon - halfDay, sunset: noon + halfDay)
    }

    // MARK: - Location without permission

    /// Latitude assumed when only a UTC offset is known (the zone isn't in the
    /// table): a temperate mid-northern latitude, so the dial still shows a
    /// plausible day arc rather than an equatorial or polar extreme.
    static let fallbackLatitude = 40.0

    /// A representative coordinate for a time zone, WITHOUT any location permission.
    /// Looks `timeZone.identifier` up in the bundled IANA table
    /// ([[TimeZoneCoordinates]]); for an unknown zone it falls back to longitude
    /// derived from the UTC offset (15° per hour) at a default mid-latitude. Never
    /// touches CoreLocation or the network.
    public static func representativeCoordinate(for timeZone: TimeZone, on date: Date = Date())
        -> (lat: Double, lon: Double) {
        if let coordinate = TimeZoneCoordinates.coordinate(forZone: timeZone.identifier) {
            return coordinate
        }
        let offsetHours = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        return (lat: fallbackLatitude, lon: offsetHours * 15.0)
    }

    // MARK: - Convenience

    /// Sunrise/sunset for a calendar date in a time zone, resolving the approximate
    /// location from the zone itself (no permission needed). Returns nil in the
    /// polar edge cases. Ties together day-of-year, UTC offset, and the per-zone
    /// coordinate so callers only need a `Date` and a `TimeZone`.
    public static func sunWindow(on date: Date, in timeZone: TimeZone)
        -> (sunrise: Double, sunset: Double)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let coordinate = representativeCoordinate(for: timeZone, on: date)
        let gmtOffset = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        return sunWindow(lat: coordinate.lat, lon: coordinate.lon,
                         dayOfYear: dayOfYear, gmtOffset: gmtOffset)
    }
}
