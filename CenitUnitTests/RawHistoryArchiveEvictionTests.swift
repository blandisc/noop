import XCTest
@testable import Cenit
import WhoopProtocol

/// FER-693 (#344): the reject archive has a byte cap. A full archive must not drop a rare never-seen
/// layout version (WHOOP 4 v19, WHOOP 5 v20/v21) — the exact frames we keep the archive to study. Each
/// distinct hist_version gets a retention FLOOR: over cap we evict oldest surplus from the most-populous
/// versions first, never below `perVersionFloor` newest lines of any version. These tests prove survival.
final class RawHistoryArchiveEvictionTests: XCTestCase {

    private func tmpDir(_ tag: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("noop-evict-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A minimal synthetic WHOOP 4 type-47 record whose hist_version byte (frame[5]) is `version`.
    private func whoop4Frame(version: UInt8, filler: UInt8) -> [UInt8] {
        var f: [UInt8] = [0xAA, 0x01, 0x00, 0x00, 47, version]
        f.append(contentsOf: [UInt8](repeating: filler, count: 24))   // 30 B → ~96 B JSONL line
        return f
    }

    func testRareVersionSurvivesAFloodOfCommonFrames() {
        let dir = tmpDir("flood"); defer { try? FileManager.default.removeItem(at: dir) }
        let archive = RawHistoryArchive(directory: dir, maxBytes: 4_096, perVersionFloor: 2)

        let rareA = whoop4Frame(version: 19, filler: 0xA1)
        let rareB = whoop4Frame(version: 19, filler: 0xB2)
        _ = archive.archive([rareA, rareB], trim: 1, family: .whoop4)

        for i in 0..<400 {
            _ = archive.archive([whoop4Frame(version: 18, filler: UInt8(i & 0xFF))], trim: 2, family: .whoop4)
        }

        let back = archive.readAll()
        let attrs = try? FileManager.default.attributesOfItem(atPath: archive.fileURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        XCTAssertLessThanOrEqual(size, 4_096 + 200, "archive should stay near its cap, not grow unbounded")
        let survivedRare = back.filter { RawHistoryArchive.versionByte($0.frame, family: .whoop4) == 19 }
        XCTAssertEqual(survivedRare.count, 2, "the floor must keep both rare v19 samples through the flood")
        XCTAssertTrue(back.contains { $0.frame == rareA })
        XCTAssertTrue(back.contains { $0.frame == rareB })
        XCTAssertTrue(back.contains { RawHistoryArchive.versionByte($0.frame, family: .whoop4) == 18 })
    }

    func testRareVersionWrittenWhenArchiveAlreadyFull() {
        let dir = tmpDir("interleaved"); defer { try? FileManager.default.removeItem(at: dir) }
        let archive = RawHistoryArchive(directory: dir, maxBytes: 4_096, perVersionFloor: 2)

        for i in 0..<400 {
            _ = archive.archive([whoop4Frame(version: 18, filler: UInt8(i & 0xFF))], trim: 1, family: .whoop4)
        }
        let rare = whoop4Frame(version: 20, filler: 0xCC)
        let result = archive.archive([rare], trim: 2, family: .whoop4)
        if case .capReached = result {
            XCTFail("a single small rare frame must be accepted by evicting common surplus, not skipped")
        }
        XCTAssertTrue(archive.readAll().contains { $0.frame == rare },
                      "the rare v20 frame must survive into a full archive")
    }

    func testEachDistinctVersionGetsItsOwnFloor() {
        let dir = tmpDir("multi"); defer { try? FileManager.default.removeItem(at: dir) }
        let archive = RawHistoryArchive(directory: dir, maxBytes: 6_144, perVersionFloor: 2)

        _ = archive.archive([whoop4Frame(version: 19, filler: 0x11)], trim: 1, family: .whoop4)
        _ = archive.archive([whoop4Frame(version: 21, filler: 0x22)], trim: 1, family: .whoop4)
        for i in 0..<400 {
            _ = archive.archive([whoop4Frame(version: 18, filler: UInt8(i & 0xFF))], trim: 2, family: .whoop4)
        }

        let back = archive.readAll()
        XCTAssertTrue(back.contains { RawHistoryArchive.versionByte($0.frame, family: .whoop4) == 19 },
                      "v19 must keep its floor")
        XCTAssertTrue(back.contains { RawHistoryArchive.versionByte($0.frame, family: .whoop4) == 21 },
                      "v21 must keep its floor")
    }

    func testUnderCapPlainAppendKeepsEverything() {
        let dir = tmpDir("under"); defer { try? FileManager.default.removeItem(at: dir) }
        let archive = RawHistoryArchive(directory: dir, maxBytes: 1_000_000, perVersionFloor: 2)
        for i in 0..<10 {
            _ = archive.archive([whoop4Frame(version: 18, filler: UInt8(i))], trim: 1, family: .whoop4)
        }
        XCTAssertEqual(archive.readAll().count, 10, "nothing should be evicted while under the cap")
    }

    // MARK: - pure eviction core

    private func jsonl(_ version: Int, _ family: String = "whoop4", filler: String = "00") -> String {
        // frame: AA 01 00 00 2F <version> <filler>  → type@4 = 0x2F (47), hist_version@5 = version.
        let hex = "aa0100002f" + String(format: "%02x", version) + filler
        return "{\"capturedAtMs\":1,\"trim\":1,\"family\":\"\(family)\",\"frameHex\":\"\(hex)\"}\n"
    }

    func testEvictLinesKeepsRareVersionUnderCap() {
        var lines = [jsonl(19, filler: "a1"), jsonl(19, filler: "b2")]   // rare, oldest
        for i in 0..<400 { lines.append(jsonl(18, filler: String(format: "%02x", i & 0xFF))) }
        let kept = RawHistoryArchive.evictLines(lines, maxBytes: 4_096, floor: 2)
        let bytes = kept.reduce(0) { $0 + $1.utf8.count }
        XCTAssertLessThanOrEqual(bytes, 4_096, "eviction must bring the archive within the cap")
        XCTAssertTrue(kept.contains { $0.contains("2f13a1") }, "rare v19 #1 must survive")  // 0x13 = 19
        XCTAssertTrue(kept.contains { $0.contains("2f13b2") }, "rare v19 #2 must survive")
        XCTAssertTrue(kept.contains { $0.contains("2f12") }, "common v18 still represented")  // 0x12 = 18
    }

    func testEvictLinesNoOpUnderCap() {
        let lines = (0..<10).map { jsonl(18, filler: String(format: "%02x", $0)) }
        XCTAssertEqual(RawHistoryArchive.evictLines(lines, maxBytes: 1_000_000, floor: 2), lines)
    }
}
