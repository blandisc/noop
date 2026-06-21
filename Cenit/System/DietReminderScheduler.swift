#if os(iOS)
import Foundation
import UserNotifications
import StrandImport

/// Local, on-device meal reminders for the active diet plan (FER-412). Opt-in: when enabled, one daily
/// repeating notification per meal that declares a `hora_sugerida`, at that time. Nothing leaves the
/// device — there's no push server; these are `UNCalendarNotificationTrigger`s. Mirrors the
/// `IllnessNotifier` pattern: authorization is requested once when the user flips the switch on, and the
/// schedule is rebuilt whenever the plan or the switch changes.
enum DietReminderScheduler {

    /// Identifier prefix for our requests, so we can cancel only ours.
    private static let prefix = "diet-reminder-"
    private static let enabledKey = "diet.remindersEnabled"

    /// The opt-in preference (single user, UserDefaults-backed).
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Ask for permission up front (called when the user enables the switch), so the system dialog
    /// appears at a predictable moment. Returns whether it was granted.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// One reminder slot per meal that declares a valid "HH:MM" `hora_sugerida`. The title is the meal's
    /// own name (verbatim); meals without a time produce no reminder.
    static func reminderSlots(_ meals: [DietMeal]) -> [(hour: Int, minute: Int, title: String)] {
        meals.compactMap { meal in
            guard let raw = meal.suggestedTime, let hm = parseHourMinute(raw) else { return nil }
            let name = meal.name.trimmingCharacters(in: .whitespaces)
            return (hm.hour, hm.minute, name.isEmpty ? String(localized: "Diet reminder") : name)
        }
    }

    /// Replace the scheduled diet reminders with the current plan's meal times — but only while the
    /// switch is on AND notifications are authorized. A no-op (after cancelling) otherwise. Awaits the
    /// cancel before adding so the fresh requests aren't swept by the cancel of the old ones.
    static func reschedule(_ meals: [DietMeal]) async {
        await cancelAll()
        guard isEnabled, await authorizationStatus() == .authorized else { return }
        let center = UNUserNotificationCenter.current()
        var index = 0
        for meal in meals {
            guard let raw = meal.suggestedTime, let hm = parseHourMinute(raw) else { continue }
            let name = meal.name.trimmingCharacters(in: .whitespaces)
            let title = name.isEmpty ? String(localized: "Diet reminder") : name
            // A semanal meal fires only on its weekdays; a diario meal (days == nil) fires every day. (FER-431)
            let calendarWeekdays: [Int?] = meal.days
                .map { $0.map { Optional(DietWeekday.calendarWeekday(forISOWeekday: $0)) } } ?? [nil]
            for weekday in calendarWeekdays {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = String(localized: "Did you mark this meal?")
                content.sound = .default
                var when = DateComponents()
                when.hour = hm.hour
                when.minute = hm.minute
                if let weekday { when.weekday = weekday }
                let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
                try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(index)", content: content, trigger: trigger))
                index += 1
            }
        }
    }

    /// Remove every pending diet reminder (ours only — matched by the identifier prefix). Snapshots the
    /// pending set first so it can only ever remove requests that existed before this call.
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    /// Parse a 24-hour "HH:MM" string; nil for anything malformed or out of range.
    private static func parseHourMinute(_ s: String) -> (hour: Int, minute: Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }
}
#endif
