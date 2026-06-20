import Foundation

// StressDayMap.swift — the pure "what coincided with what" logic for the day map (FER-377).
//
// The intraday stress curve (`StressEngine`) and the calendar events are crossed here, purely, so the
// matching is testable without EventKit or any UI. The app layer (Cenit) fetches events from EventKit
// and the RR curve from the store, then asks this for the day's headline coincidence.
//
// Honesty: this only reports TEMPORAL coincidence ("the peak fell inside this event"), never causation.
// All-day events have no instant to cross, so they never match the peak.

public enum StressDayMap {

    /// A calendar event reduced to what the cross needs: a title and a wall-clock window. `isAllDay`
    /// events are listed separately by the UI and never enter the peak match.
    public struct DayEvent: Equatable, Sendable {
        public let title: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool

        public init(title: String, start: Date, end: Date, isAllDay: Bool) {
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
        }

        /// True when `date` falls within a TIMED event's window (all-day events never contain an instant).
        public func contains(_ date: Date) -> Bool {
            !isAllDay && date >= start && date <= end
        }
    }

    /// The day's highest stress reading and the timed event (if any) it fell within.
    public struct Coincidence: Equatable, Sendable {
        /// When the day's highest reading occurred.
        public let peakDate: Date
        /// The 0–3 value at the peak.
        public let peakStress: Double
        /// The timed event whose window contains the peak, or `nil` if the peak fell in open time.
        public let event: DayEvent?

        public init(peakDate: Date, peakStress: Double, event: DayEvent?) {
            self.peakDate = peakDate
            self.peakStress = peakStress
            self.event = event
        }
    }

    /// The day's peak reading and the timed event it coincided with (if any). Returns `nil` when the
    /// curve has no reading at all (every bucket was no-reading). All-day events are excluded from the
    /// match — the UI lists them apart. On ties the earliest peak wins (stable, time-ordered curve).
    public static func peakCoincidence(_ curve: [StressEngine.StressPoint],
                                       events: [DayEvent]) -> Coincidence? {
        var best: (date: Date, stress: Double)? = nil
        for p in curve {
            guard let s = p.stress else { continue }
            if best == nil || s > best!.stress { best = (p.date, s) }
        }
        guard let peak = best else { return nil }
        let event = events.first { $0.contains(peak.date) }
        return Coincidence(peakDate: peak.date, peakStress: peak.stress, event: event)
    }

    /// Mean stress over a TIMED event's window, or `nil` when no readings land in it (all no-reading, or
    /// an all-day event). For the optional per-event line ("X coincided with N above your base").
    public static func averageStress(during event: DayEvent,
                                     in curve: [StressEngine.StressPoint]) -> Double? {
        guard !event.isAllDay else { return nil }
        var sum = 0.0, n = 0
        for p in curve {
            guard let s = p.stress, p.date >= event.start, p.date <= event.end else { continue }
            sum += s; n += 1
        }
        return n > 0 ? sum / Double(n) : nil
    }
}
