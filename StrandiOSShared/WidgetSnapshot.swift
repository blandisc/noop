import Foundation
import os

/// Small, Codable glance snapshot shared between the iOS app and its widget/Live-Activity extension
/// via an App Group. The app writes it; the widget reads it. Keeping it tiny avoids any cross-process
/// database access — the widget never opens SQLite.
public struct WidgetSnapshot: Codable, Equatable {
    public var recovery: Int?
    public var bpm: Int?
    public var batteryPct: Int?
    public var bonded: Bool
    public var updated: Date

    public init(recovery: Int?, bpm: Int?, batteryPct: Int?, bonded: Bool, updated: Date) {
        self.recovery = recovery
        self.bpm = bpm
        self.batteryPct = batteryPct
        self.bonded = bonded
        self.updated = updated
    }

    /// App Group suite the app and widget both use. Must match the `com.apple.security.application-groups`
    /// entitlement on both targets. If the entitlement is missing on either side, `UserDefaults(suiteName:)`
    /// returns nil and every consumer (PendingIntents, WidgetSnapshot.publish, Live Activity) silently
    /// no-ops — see `assertGroupProvisioned` for the debug-time canary.
    public static let suiteName = "group.com.noopapp.noop"
    public static let storageKey = "noop.widget.snapshot"

    /// Debug-only canary: trips on the first run after a misprovisioning so the silent no-op gets
    /// caught immediately rather than masquerading as "widget shows nothing yet." Release builds do
    /// nothing — App Store apps can't crash on a missing entitlement.
    public static func assertGroupProvisioned() {
        assert(UserDefaults(suiteName: suiteName) != nil,
               "App Group '\(suiteName)' not provisioned on this target — check the entitlement.")
    }

    /// The shared store for every App-Group consumer (this snapshot + `PendingIntents`). Returns the
    /// App-Group suite normally; if the entitlement is missing it logs a fault ONCE and falls back to
    /// `UserDefaults.standard` instead of the old silent `guard … else { return }` no-op.
    ///
    /// A missing App Group can't be fully recovered — the widget/extension run in separate processes
    /// and only the real group container is shared — but the fallback keeps within-process reads and
    /// writes working, and (unlike the silent no-op) the misprovisioning is now visible in Release
    /// logs rather than masquerading as "the widget just shows nothing." `assertGroupProvisioned()`
    /// still hard-fails Debug builds so it's caught long before Release.
    public static func sharedDefaults() -> UserDefaults {
        if let group = UserDefaults(suiteName: suiteName) { return group }
        _ = warnMissingGroupOnce
        return .standard
    }

    /// One-time fault log on the first fallback (lazy `static let` runs at most once, thread-safe).
    private static let warnMissingGroupOnce: Void = {
        Logger(subsystem: "com.noopapp.noop", category: "AppGroup").fault(
            "App Group '\(suiteName, privacy: .public)' unavailable — entitlement missing on this target. Falling back to standard defaults; the widget and Live Activity will not see app updates until this is fixed.")
    }()

    public static var placeholder: WidgetSnapshot {
        WidgetSnapshot(recovery: 72, bpm: 58, batteryPct: 84, bonded: true, updated: Date())
    }

    /// Read the last-published snapshot from the shared suite, if any.
    public static func load() -> WidgetSnapshot? {
        guard let data = sharedDefaults().data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        return snap
    }

    /// Persist this snapshot into the shared suite.
    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        WidgetSnapshot.sharedDefaults().set(data, forKey: WidgetSnapshot.storageKey)
    }
}
