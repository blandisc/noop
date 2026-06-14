#if os(iOS) && DEBUG
import Foundation
import SwiftUI

/// Debug-only navigation for screenshot automation.
///
/// Two transport layers — both post to `.noopDebugNav` which RootTabView observes:
///   1. Darwin notifications (no dialog): notifyutil -p noop.nav.<screen>
///   2. URL scheme (backup):              xcrun simctl openurl booted "noopdev://<screen>"
///
/// Supported screen keys: today · trends · live · sleep · more ·
///   intelligence · coach · insights · explore · compare ·
///   workouts · health · stress · breathe · intervals ·
///   applehealth · datasources · automations · settings · support
extension Notification.Name {
    static let noopDebugNav = Notification.Name("noop.debugNav")
}

/// Handles noopdev:// URLs and broadcasts the target screen via NotificationCenter.
struct DebugURLHandler: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.scheme == "noopdev", let screen = url.host else { return }
            NotificationCenter.default.post(name: .noopDebugNav, object: screen)
        }
    }
}

/// Watches Darwin notifications posted by `notifyutil -p noop.nav.<screen>` and
/// bridges them to NSNotificationCenter so RootTabView can react without any iOS
/// permission dialogs or URL-scheme intercept flows.
final class DebugNavWatcher {
    static let shared = DebugNavWatcher()
    private init() {}

    private static let prefix = "noop.nav."
    private static let screens = [
        "today", "trends", "live", "sleep", "more",
        "intelligence", "coach", "insights", "explore", "compare",
        "workouts", "health", "stress", "breathe", "intervals",
        "applehealth", "datasources", "automations", "settings", "support",
    ]

    func start() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for screen in Self.screens {
            let name = "\(Self.prefix)\(screen)" as CFString
            CFNotificationCenterAddObserver(center, nil, darwinCallback, name, nil, .deliverImmediately)
        }
    }
}

private let darwinCallback: CFNotificationCallback = { _, _, rawName, _, _ in
    guard let rawName else { return }
    let full = rawName.rawValue as String
    let prefix = "noop.nav."
    guard full.hasPrefix(prefix) else { return }
    let screen = String(full.dropFirst(prefix.count))
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .noopDebugNav, object: screen)
    }
}
#endif
