#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// Async wrappers around `UIDocumentPickerViewController` for importing/exporting the database
/// backup on iOS. Each call presents the system picker from the active window and resumes a
/// continuation with the chosen URL (or `nil` if cancelled).
enum DocumentPicker {

    /// Present the picker to export `url` (saves a copy into Files / iCloud Drive). Returns the
    /// destination URL the user picked, or `nil` if cancelled.
    @MainActor
    static func export(_ url: URL) async -> URL? {
        await present { coordinator in
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            picker.delegate = coordinator
            return picker
        }
    }

    /// Present the picker to import a file of one of `types`. `asCopy` is used so we receive a
    /// readable local copy in our sandbox (no security-scoped bookkeeping needed).
    @MainActor
    static func importFile(_ types: [UTType]) async -> URL? {
        await present { coordinator in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.delegate = coordinator
            picker.allowsMultipleSelection = false
            return picker
        }
    }

    /// Present the picker to choose a *folder* — e.g. one inside iCloud Drive — as the destination for
    /// automatic backups. Unlike import/export this returns the real **security-scoped** folder URL
    /// (`asCopy: false`), so the caller can persist a bookmark and keep writing into it on later runs
    /// without re-prompting. This works on a free Apple ID: it touches the user's own iCloud Drive
    /// through the Files system, which needs no iCloud-container entitlement. Returns `nil` if cancelled.
    @MainActor
    static func pickFolder() async -> URL? {
        await present { coordinator in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.delegate = coordinator
            picker.allowsMultipleSelection = false
            return picker
        }
    }

    // MARK: - Presentation plumbing

    @MainActor
    private static func present(_ make: (Coordinator) -> UIDocumentPickerViewController) async -> URL? {
        guard let root = topViewController() else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let coordinator = Coordinator(continuation: continuation)
            let picker = make(coordinator)
            // Keep the coordinator alive for the lifetime of the picker.
            objc_setAssociatedObject(picker, &Coordinator.assocKey, coordinator, .OBJC_ASSOCIATION_RETAIN)
            root.present(picker, animated: true)
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class Coordinator: NSObject, UIDocumentPickerDelegate {
        static var assocKey = 0
        private let continuation: CheckedContinuation<URL?, Never>
        private var resumed = false

        init(continuation: CheckedContinuation<URL?, Never>) {
            self.continuation = continuation
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(nil)
        }

        private func finish(_ url: URL?) {
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: url)
        }
    }
}
#endif
