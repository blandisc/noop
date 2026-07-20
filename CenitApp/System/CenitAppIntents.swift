#if os(iOS)
import Foundation
import AppIntents

/// Queue of actions requested by an App Intent while the app may be suspended. Intents can't reach
/// into the running `AppModel` directly (BLE only lives in the foreground app), so they enqueue here
/// and the app drains the queue when it next becomes active.
enum PendingIntents {
    enum Action: String { case markMoment }

    /// A queued action plus the instant it was requested. The queue can sit for hours — an intent
    /// run from the lock screen only drains when the app next becomes active — so the request time
    /// has to travel with the action: a `markMoment` stamped at drain time is a marker for the wrong
    /// moment, which defeats the point of the intent.
    struct Entry {
        let action: Action
        let date: Date
    }

    private static let key = "noop.pendingIntents"
    /// Shared App-Group store, with the same logged `.standard` fallback as `AppGroup.sharedDefaults`
    /// (FER-32) instead of a silent no-op when the entitlement is missing.
    private static var defaults: UserDefaults { AppGroup.sharedDefaults() }

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func append(_ action: Action, at date: Date = Date()) {
        let d = defaults
        var list = d.stringArray(forKey: key) ?? []
        list.append("\(action.rawValue)|\(stamp.string(from: date))")
        d.set(list, forKey: key)
    }

    static func drain() -> [Entry] {
        let d = defaults
        let raw = d.stringArray(forKey: key) ?? []
        d.removeObject(forKey: key)
        let now = Date()
        return raw.compactMap { decode($0, fallback: now) }
    }

    /// Parses an `action|ISO8601` pair. Entries written by a build that predates the timestamp are
    /// bare action names: they keep working across the update by falling back to the drain time (the
    /// old behaviour) instead of being dropped on the floor.
    private static func decode(_ raw: String, fallback: Date) -> Entry? {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let name = parts.first, let action = Action(rawValue: String(name)) else { return nil }
        let date = parts.count == 2 ? stamp.date(from: String(parts[1])) : nil
        return Entry(action: action, date: date ?? fallback)
    }
}

/// Record a timestamped "moment" — the iOS analogue of the strap double-tap "mark a moment" action.
struct MarkMomentIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a Moment"
    static var description = IntentDescription("Record a timestamped moment in Cénit.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingIntents.append(.markMoment)
        return .result(dialog: "Moment marked.")
    }
}


/// Surfaces NOOP's intents to Siri, Spotlight, and the Shortcuts gallery without any user setup.
struct CenitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MarkMomentIntent(),
                    phrases: ["Mark a moment in \(.applicationName)"],
                    shortTitle: "Mark a Moment",
                    systemImageName: "mappin.and.ellipse")
    }
}
#endif
