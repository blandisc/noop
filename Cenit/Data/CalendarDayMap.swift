import Foundation
import SwiftUI
import EventKit
import WhoopProtocol
import StrandAnalytics

// CalendarDayMap.swift — the app-layer orchestrator for the «mapa del día» (FER-377).
//
// Owns the EventKit permission flow + calendar selection, reads beat-to-beat RR from the store (per day,
// the IntelligenceEngine pattern — bounded reads), builds the personal waking reference + today's
// intraday stress curve (`StressEngine`), and crosses it with the day's events (`StressDayMap`). Pure
// math stays in StrandAnalytics; this only does I/O + state. EventKit lives in the app layer, never in a
// package. Everything is on-device — `EKEventStore` reads the phone's own calendars, nothing leaves.

@MainActor
final class CalendarDayMap: ObservableObject {

    /// What the block should render. Mirrors the UX state matrix.
    enum Phase: Equatable {
        case needsPermission     // not asked yet → invitation (no auto-prompt)
        case denied              // declined → Settings deep link
        case restricted          // MDM/parental → no recovery path
        case chooseCalendars     // authorized, none picked yet
        case loading
        case ready(DayMap)
    }

    /// Everything the «Momentos primero» block needs once built.
    struct DayMap: Equatable {
        var curve: [StressEngine.StressPoint]      // today's 0–3 readings (nil = no reading)
        var timed: [StressDayMap.DayEvent]         // today's timed events, time-ordered
        var allDay: [StressDayMap.DayEvent]        // today's all-day events (listed apart)
        var coincidence: StressDayMap.Coincidence? // peak ↔ event (the headline)
        var moments: StressMoments.DayMoments      // ranked activated moments + calmest (FER-433)
        var referenceMissing: Bool                 // cold start: no waking reference yet
        var selectedNames: [String]                // chosen calendar labels «title (account)» (footer)
        var now: Date
    }

    struct CalInfo: Identifiable, Equatable {
        let id: String
        let title: String
        /// The calendar's source/account («iCloud», «Gmail», …) — distinguishes same-named calendars.
        let account: String
        /// Display label: «title (account)» when the account is known, else just the title. (FER-433)
        var label: String { account.isEmpty ? title : "\(title) (\(account))" }
    }

    @Published private(set) var phase: Phase = .needsPermission
    @Published private(set) var calendars: [CalInfo] = []
    @Published private(set) var selectedIDs: Set<String>

    private let store = EKEventStore()
    private let restingHR: Double
    private let maxHR: Double
    /// Beat-to-beat RR for `[from, to]` (wall-clock seconds). Injected so the model stays store-free.
    private let rrLoader: (_ from: Int, _ to: Int) async -> [RRInterval]
    /// Sleep spans (wall-clock seconds) overlapping `[from, to]`, to exclude from the waking reference.
    private let sleepLoader: (_ from: Int, _ to: Int) async -> [ClosedRange<Int>]

    private static let selectionKey = "noop.stress.calendarIDs"
    /// How many trailing days of waking RR feed the personal reference.
    private static let referenceDays = 7

    init(restingHR: Double,
         maxHR: Double,
         rrLoader: @escaping (_ from: Int, _ to: Int) async -> [RRInterval],
         sleepLoader: @escaping (_ from: Int, _ to: Int) async -> [ClosedRange<Int>]) {
        self.restingHR = restingHR
        self.maxHR = maxHR
        self.rrLoader = rrLoader
        self.sleepLoader = sleepLoader
        let saved = UserDefaults.standard.stringArray(forKey: Self.selectionKey)
        self.selectedIDs = Set(saved ?? [])
    }

    // MARK: - Intent

    /// Resolve the current authorization status and, if cleared, build the map. Called on appear.
    func refresh() async {
        switch Self.readStatus() {
        case .needsPermission: phase = .needsPermission
        case .restricted:      phase = .restricted
        case .denied:          phase = .denied
        case .authorized:
            loadCalendars()
            if selectedIDs.isEmpty { phase = .chooseCalendars } else { await buildMap() }
        }
    }

    /// Fire the system prompt (only from a user tap), then resolve.
    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await store.requestAccess(to: .event)
            }
        } catch { /* treated as not-granted by the status re-read below */ }
        await refresh()
    }

    /// Persist a new calendar selection and rebuild.
    func updateSelection(_ ids: Set<String>) async {
        selectedIDs = ids
        UserDefaults.standard.set(Array(ids), forKey: Self.selectionKey)
        await refresh()
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: - Building

    private func loadCalendars() {
        calendars = store.calendars(for: .event)
            .map(Self.info)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// A `CalInfo` for a calendar — the single place that reads `title` + `source.title`. (FER-433)
    private static func info(_ cal: EKCalendar) -> CalInfo {
        CalInfo(id: cal.calendarIdentifier, title: cal.title, account: cal.source?.title ?? "")
    }

    private func buildMap() async {
        phase = .loading
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let now = Date()
        let startNext = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        // Events for the whole civil day (future ones included → "día parcial"), selected calendars only.
        let (timed, allDay, names) = fetchEvents(start: startOfToday, end: startNext)

        // Today's RR (start of day → now) and, per day, the trailing waking history for the reference.
        let todayRR = await rrLoader(Int(startOfToday.timeIntervalSince1970), Int(now.timeIntervalSince1970))
        let todaySleep = await sleepLoader(Int(startOfToday.timeIntervalSince1970), Int(now.timeIntervalSince1970))

        var daysRR: [[RRInterval]] = []
        var excludedPerDay: [[ClosedRange<Int>]] = []
        for back in 1...Self.referenceDays {
            let dayStart = cal.date(byAdding: .day, value: -back, to: startOfToday)!
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let from = Int(dayStart.timeIntervalSince1970), to = Int(dayEnd.timeIntervalSince1970)
            daysRR.append(await rrLoader(from, to))
            excludedPerDay.append(await sleepLoader(from, to))
        }

        let resting = restingHR, max = maxHR
        // Pure compute off the main actor (large RR arrays).
        let result = await Task.detached(priority: .userInitiated) { () -> (curve: [StressEngine.StressPoint], missing: Bool) in
            guard let reference = StressEngine.wakingReference(
                daysRR: daysRR, excludedPerDay: excludedPerDay, restingHR: resting, maxHR: max
            ) else {
                return ([], true)   // cold start — honest "still learning"
            }
            let curve = StressEngine.intradayStress(
                todayRR, reference: reference, excluded: todaySleep, restingHR: resting, maxHR: max)
            return (curve, false)
        }.value

        let coincidence = StressDayMap.peakCoincidence(result.curve, events: timed)
        // Ranked moments are a cheap O(n) pure reduction → fine on the main actor (no detached needed).
        let moments = StressMoments.detect(result.curve, events: timed)
        phase = .ready(DayMap(curve: result.curve, timed: timed, allDay: allDay,
                              coincidence: coincidence, moments: moments,
                              referenceMissing: result.missing, selectedNames: names, now: now))
    }

    /// Read the day's events from the selected calendars, split timed vs all-day (both time-ordered).
    private func fetchEvents(start: Date, end: Date) -> (timed: [StressDayMap.DayEvent],
                                                         allDay: [StressDayMap.DayEvent],
                                                         names: [String]) {
        let all = store.calendars(for: .event)
        let chosen = all.filter { selectedIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return ([], [], []) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        let untitled = String(localized: "(untitled)")
        var timed: [StressDayMap.DayEvent] = [], allDay: [StressDayMap.DayEvent] = []
        for e in store.events(matching: predicate) {
            let ev = StressDayMap.DayEvent(title: e.title?.isEmpty == false ? e.title : untitled,
                                           start: e.startDate, end: e.endDate, isAllDay: e.isAllDay)
            if ev.isAllDay { allDay.append(ev) } else { timed.append(ev) }
        }
        timed.sort { $0.start < $1.start }
        allDay.sort { $0.start < $1.start }
        return (timed, allDay, chosen.map { Self.info($0).label })
    }

    /// Historical event-type tags for the last `days` days (FER-388): `title → set of local day keys`
    /// it occurred on. ONE EventKit query over the whole window (not per day), timed events only, from
    /// the chosen calendars. On-device, NOT persisted — EventKit stays the source of truth. Empty unless
    /// authorized with ≥1 calendar chosen. The title is the cluster key; only titles that recur enough
    /// (≥ the stats floor) become a pattern downstream, so one-offs never do.
    func eventDaysByTitle(days: Int = 60) -> [String: Set<String>] {
        guard case .authorized = Self.readStatus(), !selectedIDs.isEmpty else { return [:] }
        let chosen = store.calendars(for: .event).filter { selectedIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [:] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) ?? end
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        var byTitle: [String: Set<String>] = [:]
        for e in store.events(matching: predicate) where !e.isAllDay {
            guard let title = e.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }
            byTitle[title, default: []].insert(Repository.localDayKey(e.startDate))
        }
        return byTitle
    }

    // MARK: - Authorization status (normalized across iOS 16/17)

    private enum Status { case needsPermission, denied, restricted, authorized }

    private static func readStatus() -> Status {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .needsPermission
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .fullAccess:    return .authorized
        case .authorized:    return .authorized          // iOS 16 full read/write
        case .writeOnly:     return .denied              // can't read events → treat as no access
        @unknown default:    return .needsPermission
        }
    }
}
