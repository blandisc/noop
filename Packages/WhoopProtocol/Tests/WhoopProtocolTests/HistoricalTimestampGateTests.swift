import XCTest
@testable import WhoopProtocol

/// #547 — the type-47 ingest timestamp gate (FER-691). A bad-clock WHOOP 4.0 (repeated
/// trim=0xFFFFFFFF) emits records whose own unix decodes to scattered garbage: far-past (2024),
/// a bogus 2027=1827642881, and FUTURE dates. Cénit used to trust them verbatim, so one ~12h polluted
/// block was re-attributed to every day-window and a future row surfaced as the "last night"
/// carry-over. `extractHistoricalStreams` now drops any record whose resolved ts is implausible
/// (< MIN_PLAUSIBLE_UNIX or > now + FUTURE_MARGIN, or months outside the strap's own GET_DATA_RANGE
/// window) and tallies the drop in `Streams.droppedImplausible`.
final class HistoricalTimestampGateTests: XCTestCase {

    // A plausible recent capture instant used as both the strap ts and the wall ref. The gate anchors its
    // FUTURE bound on the LATER of this ref and the live clock, so "recent past" tests stay deterministic
    // (always < now) while "future" tests use a value clearly beyond the live clock + margin (FAR_FUTURE).
    private let wallNow = Int(Date().timeIntervalSince1970) - 7 * 86_400   // a week ago — unambiguously past
    // Year ~2096 — beyond any plausible live clock + FUTURE_MARGIN, the shape of the field's future garbage.
    private let FAR_FUTURE = 4_000_000_000

    /// Build a synthetic CRC-valid type-47 HISTORICAL_DATA ParsedFrame carrying `unix` + a fixed HR, so
    /// the gate (which keys off the parsed `unix`) can be exercised without hand-rolling record bytes.
    private func histFrame(unix: Int, bpm: Int = 60) -> ParsedFrame {
        ParsedFrame(
            ok: true, typeName: "HISTORICAL_DATA", seq: 24, cmdName: nil, crcOK: true,
            lenBytes: 0, rawHex: "", fields: [],
            parsed: ["hist_version": .int(24), "unix": .int(unix), "heart_rate": .int(bpm)]
        )
    }

    // MARK: - bounds

    func testBounds() {
        XCTAssertEqual(MIN_PLAUSIBLE_UNIX, 1_700_000_000)   // 2023-11 floor (== DataRange.earliestUnix)
        XCTAssertEqual(FUTURE_MARGIN, 86_400)               // 1 day
    }

    func testIsPlausiblePredicate() {
        XCTAssertTrue(isPlausibleHistoricalUnix(wallNow, wallNow: wallNow))
        XCTAssertTrue(isPlausibleHistoricalUnix(MIN_PLAUSIBLE_UNIX, wallNow: wallNow))           // exactly the floor
        XCTAssertTrue(isPlausibleHistoricalUnix(wallNow + FUTURE_MARGIN, wallNow: wallNow))      // exactly the ceiling
        XCTAssertFalse(isPlausibleHistoricalUnix(MIN_PLAUSIBLE_UNIX - 1, wallNow: wallNow))      // just below floor
        XCTAssertFalse(isPlausibleHistoricalUnix(wallNow + FUTURE_MARGIN + 1, wallNow: wallNow)) // just above ceiling
    }

    // MARK: - gate behavior

    func testKeepsNormalRecord() {
        let st = extractHistoricalStreams([histFrame(unix: wallNow, bpm: 61)],
                                          deviceClockRef: wallNow, wallClockRef: wallNow)
        XCTAssertEqual(st.hr.count, 1)
        XCTAssertEqual(st.hr.first?.ts, wallNow)
        XCTAssertEqual(st.hr.first?.bpm, 61)
        XCTAssertEqual(st.droppedImplausible, 0)
    }

    func testRejectsFutureDatedRecord() {
        // A record dated far beyond now (live clock + margin) — can't post-date its own capture; bad clock.
        let st = extractHistoricalStreams([histFrame(unix: FAR_FUTURE)],
                                          deviceClockRef: wallNow, wallClockRef: wallNow)
        XCTAssertEqual(st.hr.count, 0, "future-dated record must be dropped")
        XCTAssertEqual(st.droppedImplausible, 1)
    }

    func testRejectsFarPastRecord() {
        // The field's literal garbage values: a far-past 2009-ish second, and the bogus 2027=1827642881.
        let st = extractHistoricalStreams(
            [histFrame(unix: 1_250_000_000), histFrame(unix: 1_827_642_881)],
            deviceClockRef: wallNow, wallClockRef: wallNow)
        XCTAssertEqual(st.hr.count, 0, "far-past AND >ceiling garbage must both be dropped")
        XCTAssertEqual(st.droppedImplausible, 2)
    }

    func testMixedChunkKeepsOnlyPlausible() {
        let frames = [
            histFrame(unix: wallNow - 3600, bpm: 55),   // 1h before the ref — keep
            histFrame(unix: 1_250_000_000),             // far past — drop
            histFrame(unix: wallNow - 7200, bpm: 58),   // 2h before the ref — keep
            histFrame(unix: FAR_FUTURE),                // far future — drop
            histFrame(unix: 1_827_642_881),             // bogus 2027=1827642881 (> now+margin) — drop
        ]
        let st = extractHistoricalStreams(frames, deviceClockRef: wallNow, wallClockRef: wallNow)
        XCTAssertEqual(st.hr.count, 2)
        XCTAssertEqual(st.hr.map(\.bpm).sorted(), [55, 58])
        XCTAssertEqual(st.droppedImplausible, 3)
    }

    // MARK: - #547 SESSION-RELATIVE gate (re-pollution by a wandering clock)

    func testSessionRelativeBounds() {
        XCTAssertEqual(SESSION_RANGE_MARGIN, 7 * 86_400)   // 7-day slack
    }

    func testSessionRelativeDropsInWindowFloorClearingGarbage() {
        // The #547 archetype: a 2024-12-25 record arrives in a sync whose strap GET_DATA_RANGE window is a
        // 2026 fortnight. The record CLEARS the absolute 2023-11 floor, but it's months before the strap's
        // OWN oldest banked marker → wandering-clock pollution. Session-relative gate must DROP it.
        let newest = Int(Date().timeIntervalSince1970) - 86_400          // strap's newest banked: ~yesterday
        let oldest = newest - 14 * 86_400                                // strap banked a 2-week window
        let badYule = 1_735_084_800                                      // 2024-12-25 00:00 UTC (clears floor)
        let st = extractHistoricalStreams(
            [histFrame(unix: badYule)],
            deviceClockRef: newest, wallClockRef: newest,
            sessionOldestUnix: oldest, sessionNewestUnix: newest)
        XCTAssertEqual(st.hr.count, 0, "a floor-clearing record months before the strap's own window is dropped")
        XCTAssertEqual(st.droppedImplausible, 1)
    }

    func testSessionRelativeKeepsLegitimatelyOldInWindowBackfill() {
        // A legitimately-OLD record that sits WITHIN the strap's banked [oldest, newest] window is real
        // history (a deep oldest-first backfill) and must be KEPT — session-relative, not absolute.
        let newest = Int(Date().timeIntervalSince1970) - 86_400
        let oldest = newest - 30 * 86_400                                // a month of banked backlog
        let realOld = oldest + 2 * 86_400                                // 2 days into the window — real history
        let st = extractHistoricalStreams(
            [histFrame(unix: realOld, bpm: 64)],
            deviceClockRef: newest, wallClockRef: newest,
            sessionOldestUnix: oldest, sessionNewestUnix: newest)
        XCTAssertEqual(st.hr.count, 1, "an in-window legitimately-old record is real backfill — keep it")
        XCTAssertEqual(st.hr.first?.bpm, 64)
        XCTAssertEqual(st.droppedImplausible, 0)
    }

    func testSessionRelativeFallsBackToAbsoluteWithoutMarkers() {
        // No range markers (replay / import / range-less) → absolute-only gate, unchanged. A 2024-12-25
        // record then SURVIVES (it clears the absolute floor) exactly as before this change.
        let badYule = 1_735_084_800
        let st = extractHistoricalStreams([histFrame(unix: badYule, bpm: 70)],
                                          deviceClockRef: badYule, wallClockRef: badYule)
        XCTAssertEqual(st.hr.count, 1, "with no session markers the absolute-only gate keeps a floor-clearing ts")
        XCTAssertEqual(st.droppedImplausible, 0)
    }

    func testSessionRelativeIgnoresMalformedMarkers() {
        // A wrong-epoch / below-floor oldest marker must NEVER reject real data — the gate falls back to
        // absolute-only when the markers aren't trustworthy (oldest below the floor here).
        let newest = Int(Date().timeIntervalSince1970) - 86_400
        let realRecent = newest - 3600
        let st = extractHistoricalStreams(
            [histFrame(unix: realRecent, bpm: 58)],
            deviceClockRef: newest, wallClockRef: newest,
            sessionOldestUnix: 12_345, sessionNewestUnix: newest)   // oldest < MIN_PLAUSIBLE_UNIX → malformed
        XCTAssertEqual(st.hr.count, 1, "a malformed (below-floor) oldest marker must not reject real data")
        XCTAssertEqual(st.droppedImplausible, 0)
    }

    func testIdentityRefTrustsRealRawTimestamp() {
        // The no-correlation path passes an identity ref: the future bound must fall back to the LIVE
        // wall clock, or every real record is rejected. A real recent ts must survive; only the floor
        // still applies.
        let realRecent = Int(Date().timeIntervalSince1970) - 3600
        let st = extractHistoricalStreams([histFrame(unix: realRecent, bpm: 72)],
                                          deviceClockRef: 0, wallClockRef: 0)
        XCTAssertEqual(st.hr.count, 1, "identity ref must still trust a genuinely recent raw ts")
        XCTAssertEqual(st.hr.first?.ts, realRecent)
        XCTAssertEqual(st.droppedImplausible, 0)
        // And far-past garbage is still dropped even under the identity ref.
        let st2 = extractHistoricalStreams([histFrame(unix: 1_250_000_000)],
                                           deviceClockRef: 0, wallClockRef: 0)
        XCTAssertEqual(st2.hr.count, 0)
        XCTAssertEqual(st2.droppedImplausible, 1)
    }
}
