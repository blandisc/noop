import XCTest
import ZIPFoundation
@testable import StrandImport

final class ImportCoordinatorTests: XCTestCase {

    private let appleHealthFixture = "sample_health_data.xml"
    private var tempDirs: [URL] = []

    override func tearDownWithError() throws {
        for d in tempDirs { try? FileManager.default.removeItem(at: d) }
        tempDirs.removeAll()
    }

    private func makeTempDir() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("strandimport-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        tempDirs.append(d)
        return d
    }

    /// Build a zip from a set of (entryPath, fixtureName) pairs.
    private func makeZip(named: String, entries: [(String, String)]) throws -> URL {
        let dir = makeTempDir()
        let zipURL = dir.appendingPathComponent(named)
        let archive = try Archive(url: zipURL, accessMode: .create)
        for (entryPath, fixture) in entries {
            let data = Fixtures.data(fixture)
            try archive.addEntry(with: entryPath, type: .file,
                                 uncompressedSize: Int64(data.count)) { position, size in
                let start = data.startIndex + Int(position)
                let end = start + size
                return data.subdata(in: start..<end)
            }
        }
        return zipURL
    }

    // MARK: - Apple Health zip

    func testAppleHealthFromZipNested() throws {
        let zip = try makeZip(named: "export.zip", entries: [
            ("apple_health_export/export.xml", appleHealthFixture),
        ])
        let result = try ImportCoordinator().importAppleHealth(from: zip)
        XCTAssertGreaterThan(result.daily.count, 0)
        XCTAssertEqual(result.workouts.count, 1)
        let d = try XCTUnwrap(result.daily.first { $0.day == "2024-01-02" })
        XCTAssertEqual(try XCTUnwrap(d.deepMin), 60, accuracy: 1e-9)   // sleep aggregated to the night
        // OxygenSaturation still scaled when coming via the zip stream.
        XCTAssertEqual(try XCTUnwrap(d.spo2Pct), 97.0, accuracy: 1e-9)
    }

    // MARK: - Apple Health zip, localized filename (Spanish device)

    /// Apple names the export file by device language — a Spanish iPhone
    /// produces `exportación.xml`, not `export.xml`.
    func testAppleHealthFromZipSpanishLocalizedName() throws {
        let zip = try makeZip(named: "exportación.zip", entries: [
            ("apple_health_export/exportación.xml", appleHealthFixture),
        ])
        let result = try ImportCoordinator().importAppleHealth(from: zip)
        XCTAssertGreaterThan(result.daily.count, 0)
        XCTAssertEqual(result.workouts.count, 1)
    }

    /// The clinical-records twin (`exportación_cda.xml`) must be skipped even
    /// when it is the larger entry — only the main export is HealthData XML.
    func testAppleHealthFromZipSkipsLocalizedCDATwin() throws {
        let zip = try makeZip(named: "exportación.zip", entries: [
            // Bogus non-HealthData content standing in for the CDA document.
            ("apple_health_export/exportación_cda.xml", "physiological_cycles.csv"),
            ("apple_health_export/exportación.xml", appleHealthFixture),
        ])
        let result = try ImportCoordinator().importAppleHealth(from: zip)
        XCTAssertGreaterThan(result.daily.count, 0)
    }

    func testAppleHealthFromFolderSpanishLocalizedName() throws {
        let folder = makeTempDir()
        let nested = folder.appendingPathComponent("apple_health_export")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Fixtures.url(appleHealthFixture),
            to: nested.appendingPathComponent("exportación.xml"))
        let result = try ImportCoordinator().importAppleHealth(from: folder)
        XCTAssertGreaterThan(result.daily.count, 0)
    }

    // MARK: - Auto detection

    func testDetectKindAppleHealthByXMLExtension() throws {
        let result = try ImportCoordinator().detectAndImport(from: Fixtures.url(appleHealthFixture))
        XCTAssertEqual(result.kind, .appleHealth)
        if case .appleHealth(let r) = result {
            XCTAssertGreaterThan(r.daily.count, 0)
        } else {
            XCTFail("expected appleHealth")
        }
    }

    func testDetectKindAppleHealthByZipEntry() throws {
        let zip = try makeZip(named: "export.zip", entries: [
            ("apple_health_export/export.xml", appleHealthFixture),
        ])
        let result = try ImportCoordinator().detectAndImport(from: zip)
        XCTAssertEqual(result.kind, .appleHealth)
    }

    func testDetectKindAppleHealthBySpanishZipEntry() throws {
        let zip = try makeZip(named: "exportación.zip", entries: [
            ("apple_health_export/exportación.xml", appleHealthFixture),
        ])
        let result = try ImportCoordinator().detectAndImport(from: zip)
        XCTAssertEqual(result.kind, .appleHealth)
    }

    // MARK: - Error handling

    func testMissingFileThrows() {
        let bogus = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).zip")
        XCTAssertThrowsError(try ImportCoordinator().detectKind(of: bogus)) { err in
            XCTAssertTrue(err is ImportError)
        }
    }

    func testUndetectableInputThrows() throws {
        // A folder with no recognised files.
        let empty = makeTempDir()
        XCTAssertThrowsError(try ImportCoordinator().detectKind(of: empty))
    }
}
