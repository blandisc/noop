import Foundation
import os

/// Shared App-Group access for the iOS app and its extensions. The app and any extension that needs
/// cross-process storage (e.g. Shortcuts' `PendingIntents`, the Live Activity's `RestActivityBridge`)
/// read/write the same suite.
///
/// FER-428 — extracted from the retired `WidgetSnapshot` when the Home/Lock-Screen widget was removed.
/// The snapshot itself is gone; the App-Group plumbing it hosted is still used by `PendingIntents`.
public enum AppGroup {
    /// App Group suite the app (and extensions) use. Must match the
    /// `com.apple.security.application-groups` entitlement on every target that shares it
    /// (`NOOP.entitlements`, `CenitWidgets.entitlements`, and the `project.yml` mirrors of both).
    ///
    /// This is the ONE declaration of the suite — `RestActivityBridge` reads it rather than repeating
    /// the literal. It used to say `group.com.noopapp.noop` (a leftover from the old bundle-id prefix)
    /// while every entitlement said `group.com.feriracheta.noop`; nothing caught the drift because an
    /// unentitled suite fails silently rather than loudly. See `warnIfGroupUnprovisioned` below.
    public static let suiteName = "group.com.feriracheta.noop"

    /// Startup canary: surfaces a misprovisioned App Group immediately instead of letting it
    /// masquerade as "nothing happened."
    ///
    /// This deliberately does NOT probe `UserDefaults`. For a suite the target isn't entitled to,
    /// `UserDefaults(suiteName:)` still returns a non-nil instance backed by a *private* plist in the
    /// app's own preferences, so even a write/read round-trip succeeds while nothing is actually
    /// shared — the failure mode is invisible to any `UserDefaults`-level check. The container URL is
    /// the real signal: "If you call the method with an invalid group identifier in iOS, the method
    /// returns a `nil` value." (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`).
    ///
    /// It **logs** rather than traps on device, on purpose: App Groups need a paid team to provision,
    /// and `docs/BUILD.md` documents installing with a *free* Apple ID, where a missing entitlement is
    /// an environment limitation rather than a bug — crashing there would break the documented install
    /// path. In the Simulator entitlements always apply, so a nil container there really is a config
    /// error and gets an `assert` (compiled out of Release anyway).
    public static func warnIfGroupUnprovisioned() {
        _ = warnUnsharedGroupOnce
        #if targetEnvironment(simulator)
        assert(isGroupShared,
               "App Group '\(suiteName)' not provisioned on this target — check com.apple.security.application-groups.")
        #endif
    }

    /// Whether the group container is actually reachable, i.e. the entitlement is really in place.
    /// Always `true` on macOS (see above), so callers must not treat it as a cross-platform guarantee.
    private static var isGroupShared: Bool {
        #if os(macOS)
        return true
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) != nil
        #endif
    }

    /// The shared store for every App-Group consumer (`PendingIntents`, `RestActivityBridge`). Returns
    /// the App-Group suite normally; if the suite can't be opened at all it logs a fault ONCE and falls
    /// back to `UserDefaults.standard` instead of a silent no-op.
    public static func sharedDefaults() -> UserDefaults {
        _ = warnUnsharedGroupOnce
        if let group = UserDefaults(suiteName: suiteName) { return group }
        return .standard
    }

    /// One-time fault log when the group isn't really shared (lazy `static let` runs at most once,
    /// thread-safe). Keyed off the container URL, not `UserDefaults(suiteName:)` — the latter is
    /// non-nil even when unentitled, which is exactly how the old suite-name drift went unnoticed.
    /// This fires in Release too, so a device build still reports the problem in Console.app.
    private static let warnUnsharedGroupOnce: Void = {
        guard !isGroupShared else { return }
        Logger(subsystem: "com.noopapp.noop", category: "AppGroup").fault(
            "App Group '\(suiteName, privacy: .public)' unavailable — entitlement missing on this target. Writes stay private to this process.")
    }()
}
