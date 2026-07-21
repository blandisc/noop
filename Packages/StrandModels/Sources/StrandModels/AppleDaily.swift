import Foundation

/// One Apple-Health daily-aggregate row. Natural key (deviceId, day). All metric columns nullable.
public struct AppleDaily: Equatable, Codable, Sendable {
    public let day: String           // YYYY-MM-DD
    public let steps: Int?
    public let activeKcal: Double?
    public let basalKcal: Double?
    public let vo2max: Double?
    public let avgHr: Int?
    public let maxHr: Int?
    public let walkingHr: Int?
    public let weightKg: Double?
    public init(day: String, steps: Int?, activeKcal: Double?, basalKcal: Double?, vo2max: Double?,
                avgHr: Int?, maxHr: Int?, walkingHr: Int?, weightKg: Double?) {
        self.day = day; self.steps = steps; self.activeKcal = activeKcal; self.basalKcal = basalKcal
        self.vo2max = vo2max; self.avgHr = avgHr; self.maxHr = maxHr
        self.walkingHr = walkingHr; self.weightKg = weightKg
    }
}
