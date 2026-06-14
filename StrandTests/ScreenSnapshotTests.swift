/// Renders every main NOOP screen to PNG and saves to ~/Desktop/noop-screenshots/.
/// Run: xcodebuild test -scheme Strand -only-testing StrandTests/ScreenSnapshotTests
///
/// Uses NSHostingView + offscreen bitmap rendering — no external dependencies, no simulator.
/// Screens render in their empty/loading state (no real data needed).
/// iPhone-style proportions via a 390×844 frame (iPhone 16 logical size).

import XCTest
import SwiftUI
import AppKit
@testable import Strand

@MainActor
final class ScreenSnapshotTests: XCTestCase {

    // Output folder — created on first run
    static let outputDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Desktop/noop-screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // iPhone 16 Pro logical resolution (portrait)
    static let phoneSize = CGSize(width: 393, height: 852)

    // Shared model — one instance for all tests
    let model = AppModel()

    // MARK: - Tests

    func test_01_TodayView() {
        snap("01_Today", TodayView()
            .environmentObject(model)
            .environmentObject(model.live)
            .environmentObject(model.repo)
        )
    }

    func test_02_TrendsView() {
        snap("02_Trends", TrendsView()
            .environmentObject(model.repo)
        )
    }

    func test_03_LiveView() {
        snap("03_Live", LiveView()
            .environmentObject(model)
            .environmentObject(model.live)
            .environmentObject(model.repo)
        )
    }

    func test_04_SleepView() {
        snap("04_Sleep", SleepView()
            .environmentObject(model.repo)
            .environmentObject(model.live)
        )
    }

    func test_05_IntelligenceView() {
        snap("05_Intelligence", IntelligenceView()
            .environmentObject(model.repo)
        )
    }

    func test_06_CoachView() {
        snap("06_Coach", CoachView()
            .environmentObject(model.repo)
        )
    }

    func test_07_InsightsView() {
        snap("07_Insights", InsightsView()
            .environmentObject(model.repo)
        )
    }

    func test_08_MetricExplorerView() {
        snap("08_MetricExplorer", MetricExplorerView()
            .environmentObject(model.repo)
        )
    }

    func test_09_CompareView() {
        snap("09_Compare", CompareView()
            .environmentObject(model.repo)
        )
    }

    func test_10_WorkoutsView() {
        snap("10_Workouts", WorkoutsView()
            .environmentObject(model.repo)
        )
    }

    func test_11_HealthView() {
        snap("11_Health", HealthView()
            .environmentObject(model.repo)
        )
    }

    func test_12_StressView() {
        snap("12_Stress", StressView()
            .environmentObject(model.repo)
        )
    }

    func test_13_BreathingView() {
        snap("13_Breathe", BreathingView()
            .environmentObject(model.repo)
            .environmentObject(model.live)
        )
    }

    func test_14_IntervalTimerView() {
        snap("14_Intervals", IntervalTimerView()
            .environmentObject(model.repo)
            .environmentObject(model.live)
        )
    }

    func test_15_AppleHealthView() {
        snap("15_AppleHealth", AppleHealthView()
            .environmentObject(model.repo)
        )
    }

    func test_16_DataSourcesView() {
        snap("16_DataSources", DataSourcesView()
            .environmentObject(model)
            .environmentObject(model.repo)
        )
    }

    func test_17_AutomationsView() {
        snap("17_Automations", AutomationsView()
            .environmentObject(model.repo)
        )
    }

    func test_18_SettingsView() {
        snap("18_Settings", SettingsView()
            .environmentObject(model)
            .environmentObject(model.live)
            .environmentObject(model.profile)
            .environmentObject(AutoBackup())
        )
    }

    func test_19_SupportView() {
        snap("19_Support", SupportView()
            .environmentObject(model.repo)
        )
    }

    // MARK: - Render helper

    private func snap<V: View>(_ name: String, _ view: V) {
        let styled = view
            .preferredColorScheme(.dark)
            .frame(width: Self.phoneSize.width, height: Self.phoneSize.height)

        let host = NSHostingView(rootView: styled)
        host.frame = CGRect(origin: .zero, size: Self.phoneSize)

        // Force layout so the view tree is fully computed before drawing
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not create bitmap for \(name)"); return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)

        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)

        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            XCTFail("Could not encode PNG for \(name)"); return
        }

        let fileURL = Self.outputDir.appendingPathComponent("\(name).png")
        do {
            try png.write(to: fileURL)
            print("Saved: \(fileURL.path)")
        } catch {
            XCTFail("Write failed for \(name): \(error)")
        }
    }
}
