import Foundation
import CenitStore
import WhoopProtocol
import BiometricStreams
import StrandAnalytics

// NightRhythmProvider.swift — the app-layer read for FER-666's «Ritmo» surface. It picks last
// night's main sleep, pulls the R-R + gravity streams over that window, and hands them to the
// pure `NightRhythmAssembler`. It also resolves the coarse UI state (no band / no sleep / a
// reading) so the screen (F2) binds to one value. No new science — the assembler and the
// `RhythmScreener` engine own all the math and every label. Nothing here names a condition.

/// The coarse state of last night's rhythm read, for the «Ritmo» screen to render.
enum NightRhythmRead: Equatable {
    /// Beat-to-beat timing only comes from a WHOOP band; not available on Apple-Health-only.
    case needsBand
    /// No main sleep last night (didn't sleep with the strap), so there is nothing to read.
    case noSleepLastNight
    /// A night was assembled. The reading may itself be all-unreadable (every window failed a
    /// gate) — the screen reads `summary.overall`/`readableWindows` to show "couldn't read".
    case reading(NightRhythmAssembler.NightRhythm)
}

enum NightRhythmProvider {

    /// The most recent MAIN night among `sessions` (a nap is excluded via the same duration
    /// floor the sleep engines use, `SleepMainNight.minDurationMinutes`). nil if none qualify.
    static func lastNight(_ sessions: [CachedSleepSession]) -> CachedSleepSession? {
        sessions
            .filter { SleepMainNight.qualifies(startTs: $0.startTs, endTs: $0.endTs) }
            .max { $0.startTs < $1.startTs }
    }

    /// Pure resolution of the read from already-fetched inputs. Testable without a store.
    static func read(usesWhoop: Bool, night: CachedSleepSession?,
                     rr: [RRInterval], gravity: [GravitySample]) -> NightRhythmRead {
        guard usesWhoop else { return .needsBand }
        guard let night else { return .noSleepLastNight }
        // A main night with no beats at all means the strap didn't log a tacogram — treat it as
        // "no reading to show" rather than an unreadable night full of empty gates.
        guard !rr.isEmpty else { return .noSleepLastNight }
        let assembled = NightRhythmAssembler.assemble(rr: rr, gravity: gravity,
                                                      from: night.startTs, to: night.endTs)
        return .reading(assembled)
    }

    /// Read last night's rhythm from the store: pick the night, pull its R-R + gravity, assemble.
    /// The screen (F2) calls this once on open. Looks back two days so an early-morning open
    /// still finds last night even if wake was just after midnight.
    @MainActor
    static func load(from repo: Repository) async -> NightRhythmRead {
        guard repo.dataSourceMode.usesWhoop else { return .needsBand }
        let now = Int(Date().timeIntervalSince1970)
        let sessions = await repo.sleepSessions(from: now - 2 * 86_400, to: now + 86_400, limit: 100)
        guard let night = lastNight(sessions) else { return .noSleepLastNight }
        let rr = await repo.rrIntervals(from: night.startTs, to: night.endTs)
        let gravity = await repo.gravitySamples(from: night.startTs, to: night.endTs)
        // FER-972 (P-02): the assemble walks the whole night's tacogram — pure CPU, so hop off the
        // main actor (CalendarDayMap's pattern) and hand back only the value.
        return await Task.detached(priority: .userInitiated) {
            read(usesWhoop: true, night: night, rr: rr, gravity: gravity)
        }.value
    }
}
