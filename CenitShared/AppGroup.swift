import Foundation
import os

/// Shared App-Group access for the iOS app and its extensions. The app and any extension that needs
/// cross-process storage (e.g. Shortcuts' `PendingIntents`) read/write the same suite.
///
/// FER-428 — extracted from the retired `WidgetSnapshot` when the Home/Lock-Screen widget was removed.
/// The snapshot itself is gone; the App-Group plumbing it hosted is still used by `PendingIntents`.
public enum AppGroup {
    /// App Group suite the app (and extensions) use. Must match the
    /// `com.apple.security.application-groups` entitlement on the target.
    public static let suiteName = "group.com.noopapp.noop"

    /// Debug-only canary: trips on the first run after a misprovisioning so a silent App-Group no-op
    /// gets caught immediately rather than masquerading as "nothing happened." Release builds do
    /// nothing — App Store apps can't crash on a missing entitlement.
    public static func assertGroupProvisioned() {
        assert(UserDefaults(suiteName: suiteName) != nil,
               "App Group '\(suiteName)' not provisioned on this target — check the entitlement.")
    }

    /// The shared store for every App-Group consumer (e.g. `PendingIntents`). Returns the App-Group
    /// suite normally; if the entitlement is missing it logs a fault ONCE and falls back to
    /// `UserDefaults.standard` instead of a silent no-op.
    public static func sharedDefaults() -> UserDefaults {
        if let group = UserDefaults(suiteName: suiteName) { return group }
        _ = warnMissingGroupOnce
        return .standard
    }

    /// One-time fault log on the first fallback (lazy `static let` runs at most once, thread-safe).
    private static let warnMissingGroupOnce: Void = {
        Logger(subsystem: "com.noopapp.noop", category: "AppGroup").fault(
            "App Group '\(suiteName, privacy: .public)' unavailable — entitlement missing on this target. Falling back to standard defaults.")
    }()
}
