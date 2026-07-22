import SwiftUI
import StrandDesign
import Combine
import Observation
import BiometricStreams
import CenitStore
import StrandImport
import StrandAnalytics
import StrandTraining

/// Data source currently running an import from the Data Sources screen.
enum DataSourceImportKind {
    case appleHealth
}

extension AppModel {

    /// Cancel the in-flight import, if any. The importer stops at its next cooperative check and the
    /// matching card returns to its idle state.
    func cancelImport() { importTask?.cancel() }

    /// Returns true only for the source currently importing.
    func isImporting(_ source: DataSourceImportKind) -> Bool {
        activeImportSource == source
    }

    /// Whether the last import for a source ended in failure (for warning styling).
    func importFailed(_ source: DataSourceImportKind) -> Bool {
        switch source {
        case .appleHealth: return appleHealthImportFailed
        }
    }

    /// Import an Apple Health export (export.zip) — streams + aggregates per-day into the store
    /// under the `apple-health` source, then refreshes. Large exports take ~1–2 minutes.
    func importAppleHealth(url: URL) {
        beginImport(.appleHealth)
        importTask?.cancel()
        importTask = Task { [weak self] in
            guard let self else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let store = await repo.storeHandle() else {
                    finishImport(.appleHealth, summary: "Couldn't open the local store.", failed: true)
                    return
                }
                // The parser fires `progress` off the main thread; hop back to
                // update the @Published count the card observes.
                let progress: AppleHealthImporter.ProgressHandler = { count in
                    Task { @MainActor [weak self] in self?.appleHealthImportProgress = count }
                }
                let summary = try await AppleHealthImport.importExport(
                    url: url, into: store, deviceId: appleDeviceId,
                    maxHR: repo.strainHRmax, sex: repo.strainSex,
                    progress: progress, isCancelled: { Task.isCancelled })
                await repo.refresh()
                finishImport(.appleHealth, summary: "Imported \(summary.recordCount) records")
            } catch is CancellationError {
                finishImport(.appleHealth, summary: "Import cancelled.")
            } catch {
                finishImport(.appleHealth, summary: "Import failed: \(error)", failed: true)
            }
        }
    }

    /// Marks a source as importing and clears only that source's old status text + failure flag.
    private func beginImport(_ source: DataSourceImportKind) {
        activeImportSource = source
        switch source {
        case .appleHealth:
            appleHealthImportSummary = nil
            appleHealthImportFailed = false
            appleHealthImportProgress = nil
        }
    }

    /// Stores the completed import summary (and typed failure flag) on the matching source card.
    private func finishImport(_ source: DataSourceImportKind, summary: String, failed: Bool = false) {
        switch source {
        case .appleHealth:
            appleHealthImportSummary = summary
            appleHealthImportFailed = failed
            appleHealthImportProgress = nil
        }
        activeImportSource = nil
    }
}
