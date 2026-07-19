#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining
import CenitStore
import Foundation
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - WorkoutDetailScreen — el detalle de UNA sesión, en «Instrumento» (FER-261)
//
// Hermana de `StrainDetailScreen`/`SleepDetailScreen`: REUSA su lenguaje (hero + bloques separados por
// hairline + `theme: InstrumentoTheme` explícito + papel cálido), con su propio contenido. Se PUSHEA
// dentro del único `NavigationStack` que vive en la sheet de Entrenamientos (`WorkoutsView`) — NO crea un
// `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI, FER-171); el
// back nativo vuelve a la lista.
//
// El héroe DEGRADA con honestidad: esfuerzo (strain, strap-only) → FC media → duración. Nunca pinta un 0
// ni un «—» como protagonista falso. Las zonas de FC solo aparecen si la sesión las trae (`zonesJSON`);
// distancia/energía solo si existen, con un disclaimer cuando la fuente no es WHOOP (son estimaciones).
// El CRUD (editar/re-etiquetar/descartar/borrar/duplicar) vive en el menú ••• de la barra, según la
// fuente, y reusa el `Repository` tal cual — no toca la lógica de merge/persistencia.

struct WorkoutDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets/pushes from a sheet don't reliably carry
    /// it; the sibling detail screens do the same). (FER-162)
    var theme: InstrumentoTheme = .base
    /// The session to show. A value type — after a mutation we reload the list and pop, rather than try
    /// to keep a stale copy live.
    let row: WorkoutRow
    /// Re-read the list after a CRUD mutation, injected by `WorkoutsView` so both stay in sync.
    var onChange: () async -> Void = {}

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    /// Imperial/Metric display preference (display-only; nothing on disk changes). Same toggle the list reads.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// The add/edit sheet target (edit this manual row, or a manual copy of an imported one). nil = closed.
    @State private var editTarget: EditTarget?
    @State private var showActionMenu = false
    private struct EditTarget: Identifiable { let row: WorkoutRow; let id = UUID() }

    /// HRR-60s opt-in (FER-848): the block only exists behind the experimental-metrics toggle.
    @AppStorage(WhitespaceMetricsExperiment.enabledKey) private var experimentalMetrics = false
    /// Post-session 60-second heart-rate recovery, computed on appear from the stored HR stream (FER-852).
    @State private var hrr: HRRState = .loading
    /// How many recent prior sessions back the personal HRR baseline — bounds the on-appear store reads.
    private let hrrMaxPriorSessions = 20
    /// Drives the HRR block's staggered entrance (overline static; number → verdict → baseline →
    /// disclaimer rise+fade, 70 ms apart, no bounce — handoff «HRR-60s»). Set true on the block's appear.
    @State private var hrrRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Strength-tracker volume (kg) for a session that time-overlaps this workout row, if any.
    /// 0 means no match / no volume — the tile is gated on `volumeKg > 0` so we never paint a false 0.
    @State private var volumeKg: Double = 0
    /// The matched strength session's routine name («Día A — Empuje»), resolved by the same time-overlap
    /// join as the volume tile. `nil` (ad-hoc session, deleted routine, non-strength) falls back to the sport.
    @State private var routineTitle: String? = nil

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                contextLine
                if let zones = WorkoutZones.percents(row.zonesJSON) {
                    blockDivider
                    zonesBlock(zones)
                }
                if row.avgHr != nil || row.maxHr != nil {
                    blockDivider
                    heartBlock
                }
                if showsHRRBlock {
                    blockDivider
                    hrrBlock
                }
                if row.distanceM != nil || row.energyKcal != nil || volumeKg > 0 {
                    blockDivider
                    supportsBlock
                }
                if let notes = row.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blockDivider
                    notesBlock(notes)
                }
                blockDivider
                originBlock
                methodNote
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: row.startTs) {
            if experimentalMetrics { await loadHRR() }
            await loadVolume()
        }
        .background(theme.paper.ignoresSafeArea())
        .navigationTitle(Text(routineTitle ?? WorkoutSource.displaySport(row.sport)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { actionMenu } }
        .toolbarBackground(theme.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $editTarget) { target in
            ManualWorkoutSheet(editing: target.row, theme: theme) { saved, replacing in
                Task {
                    await repo.saveManualWorkout(saved, replacing: replacing)
                    await onChange()
                    dismiss()
                }
            }
        }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    private var blockDivider: some View { Rectangle().fill(theme.hairline).frame(height: 1) }

    // MARK: - Hero (esfuerzo → FC media → duración, degradación honesta)

    private enum Hero { case strain(Double), heartRate(Int), duration(Double) }

    /// Session length from the stored duration, or the span when it's missing. Computed once; reused by the
    /// hero (when it degrades to duration) and the context line.
    private var sessionDuration: Double { row.durationS ?? Double(max(0, row.endTs - row.startTs)) }

    /// The protagonist datum, picked by what the session actually carries — never a fabricated 0/«—». A
    /// stored `strain` of 0 isn't a real effort reading (WHOOP strain is logarithmic and > 0; a manual row
    /// leaves it nil), so it degrades like a missing value rather than showing "0.0 / 21".
    private var heroKind: Hero {
        if let s = row.strain, s > 0 { return .strain(s) }
        if let hr = row.avgHr { return .heartRate(hr) }
        return .duration(sessionDuration)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heroOverline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(heroValue)
                    .instrumentoHero(46)
                    .foregroundStyle(heroColor)
                if let unit = heroUnit {
                    Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var heroOverline: LocalizedStringKey {
        switch heroKind {
        case .strain:    return "Effort"
        case .heartRate: return "Average heart rate"
        case .duration:  return "Duration"
        }
    }
    private var heroValue: String {
        switch heroKind {
        case .strain(let s):    return String(format: "%.1f", s)
        case .heartRate(let hr): return "\(hr)"
        case .duration(let s):  return WorkoutFormat.duration(s)
        }
    }
    private var heroUnit: String? {
        switch heroKind {
        case .strain:    return "/ 21"
        case .heartRate: return String(localized: "bpm")
        case .duration:  return nil
        }
    }
    /// Color only on the measured datum: strain ember, HR rose; duration stays ink (it's not a saturated
    /// physiological figure, so coloring it would overclaim).
    private var heroColor: Color {
        switch heroKind {
        case .strain:    return theme.dataStrain
        case .heartRate: return theme.dataHeart
        case .duration:  return theme.ink
        }
    }

    private var contextLine: some View {
        Text(contextText)
            .font(StrandFont.subhead)
            .foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var contextText: String {
        "\(routineTitle ?? WorkoutSource.displaySport(row.sport)) · \(WorkoutFormat.date(row.startTs)) · \(WorkoutFormat.time(row.startTs)) · \(WorkoutFormat.duration(sessionDuration))"
    }

    // MARK: - Zonas de FC (solo si la sesión las trae)

    /// Zonas HR vía la paleta compartida `theme.hrZoneRamp`. 1 de 3 superficies de zonas HR distintas (intensidad/%-tiempo/minutos) — NO se unifican, solo comparten la paleta (FER-908).
    private func zonesBlock(_ percents: [Double]) -> some View {
        // Normalize the bar to the recorded zone time so it fills the width (WHOOP omits sub-Z1 time, so
        // the raw percents can sum to < 100); the % labels below show the raw share. Same shape as the
        // sleep-stage bar / the old aggregate zones bar, but with the warm `hrZoneRamp`.
        let total = max(percents.reduce(0, +), 0.001)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Heart-rate zones").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle()
                            .fill(theme.hrZoneRamp[i])
                            .frame(width: max(0, CGFloat(percents[i] / total) * geo.size.width))
                    }
                }
            }
            .frame(height: 34)
            .clipShape(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(zonesA11y(percents))
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text("Z\(i + 1)" as String).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        Text("\(Int(percents[i].rounded()))%")
                            .font(StrandFont.captionNumber).foregroundStyle(theme.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func zonesA11y(_ p: [Double]) -> Text {
        let parts = (0..<5).map { String(localized: "zone \($0 + 1) \(Int(p[$0].rounded())) percent") }
        return Text("Heart-rate zone split: \(parts.joined(separator: ", "))")
    }

    // MARK: - FC media / máx

    private var heartBlock: some View {
        HStack(spacing: 48) {
            if let avg = row.avgHr { stat("Avg HR", "\(avg)", unit: String(localized: "bpm"), color: theme.dataHeart) }
            if let mx = row.maxHr { stat("Max HR", "\(mx)", unit: String(localized: "bpm"), color: theme.dataHeart) }
        }
    }

    // MARK: - Distancia / energía / volumen (apoyos en ink, con disclaimer si no es WHOOP)

    private var supportsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 48) {
                if let m = row.distanceM, m > 0 {
                    stat("Distance", UnitFormatter.distanceFromMeters(m, system: unitSystem), unit: nil, color: theme.ink)
                }
                if let k = row.energyKcal, k > 0 {
                    stat("Energy", grouped(k), unit: String(localized: "kcal"), color: theme.ink)
                }
                // Strength-tracker volume when a logged session overlaps this workout (time join only).
                if volumeKg > 0 {
                    stat("Volume", StrengthHistoryFormat.volume(volumeKg, system: unitSystem), unit: nil, color: theme.ink)
                }
            }
            if WorkoutSource.classify(row.source) != .whoop {
                Text("Estimated by the source.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// One label-over-value support (ink overline + value). Color only when the caller passes a data hue.
    private func stat(_ label: LocalizedStringKey, _ value: String, unit: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(StrandFont.number(17)).foregroundStyle(color)
                if let unit { Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary) }
            }
        }
    }

    // MARK: - Notas

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(notes).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Origen

    private var originBlock: some View {
        HStack(spacing: 8) {
            Text("Source").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            workoutSourceBadge(for: row.source, theme: theme)
        }
    }

    /// The method note depends on whether there's a strain hero: with strain, explain the 0–21 scale; when
    /// degraded, explain WHY there's no effort number (strap-only), so the honest degradation reads as a
    /// fact, not a gap.
    private var methodNote: some View {
        Text(strainMethodNote)
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var strainMethodNote: LocalizedStringKey {
        // Keyed off the hero so the note never disagrees with the degraded value (a 0/absent strain reads
        // as "no effort number", not as a 0–21 reading).
        if case .strain = heroKind {
            return "Scale 0–21: it grows logarithmically, not a physical unit."
        }
        return "Effort (0–21 scale) is computed only by your strap: this session doesn't carry it."
    }

    // MARK: - Acciones (menú ••• según fuente)

    @ViewBuilder private var actionMenu: some View {
        Button { showActionMenu = true } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Session actions")
        .paperMenu(isPresented: $showActionMenu, items: actionMenuItems)
    }

    /// The «···» actions as paper-menu rows, per source (FER-837).
    private var actionMenuItems: [PaperMenuItem] {
        switch WorkoutSource.classify(row.source) {
        case .detected:
            return [
                .init(String(localized: "Re-label as"), systemImage: "tag",
                      children: WorkoutSource.relabelSports.map { sport in
                          PaperMenuItem(sport) { mutate { await repo.relabelDetected(row, sport: sport) } }
                      }),
                .init(String(localized: "Edit details…"), systemImage: "pencil") { editTarget = EditTarget(row: row) },
                .init(String(localized: "Dismiss (not a workout)"), systemImage: "xmark.circle", isDestructive: true) {
                    mutate { await repo.dismissDetected(row) }
                }
            ]
        case .manual:
            return [
                .init(String(localized: "Edit…"), systemImage: "pencil") { editTarget = EditTarget(row: row) },
                .init(String(localized: "Delete"), systemImage: "trash", isDestructive: true) {
                    mutate { await repo.deleteWorkout(row) }
                }
            ]
        case .whoop, .apple:
            return [
                .init(String(localized: "Duplicate as manual…"), systemImage: "plus.square.on.square") {
                    editTarget = EditTarget(row: asManualCopy(row))
                }
            ]
        }
    }

    /// Run a mutation, reload the list, then pop back to it — the detail's `row` is a value copy, so the
    /// honest move after any change is to return to the freshly-loaded list.
    private func mutate(_ op: @escaping () async -> Void) {
        Task { await op(); await onChange(); dismiss() }
    }

    /// A manual-source copy of an imported row, so "Duplicate as manual" pre-fills the add sheet without
    /// ever mutating the imported original (mirrors the list's old `asManualCopy`).
    private func asManualCopy(_ row: WorkoutRow) -> WorkoutRow {
        WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: WorkoutSource.displaySport(row.sport),
                   source: "manual", durationS: row.durationS, energyKcal: row.energyKcal,
                   avgHr: row.avgHr, maxHr: row.maxHr, strain: row.strain, distanceM: row.distanceM,
                   zonesJSON: row.zonesJSON, notes: row.notes)
    }

    // MARK: - Formatting

    /// Thousands-grouped integer for the energy support (e.g. "1,240").
    private func grouped(_ v: Double) -> String { StrandFormat.groupedInt(v) }

    // MARK: - HRR-60s (recuperación cardiaca post-esfuerzo, experimental — FER-852)

    /// What the block shows, once the on-appear compute settles. `.loading` and `.noData` both draw
    /// nothing (the block is simply absent); the surface never fabricates a reading it doesn't have.
    private enum HRRState {
        case loading
        case noData                                   // no stored HR for this session (e.g. a manual/Apple row)
        case noCoverage                               // HR present but the ±60 s anchors weren't both covered
        case reading(bpm: Int, trend: HeartRateRecovery.Trend)
    }

    /// True only when there's an actual reading or an honest "no coverage" to show — so the loading and
    /// no-stored-HR states draw neither the block nor its leading hairline divider.
    private var showsHRRBlock: Bool {
        guard experimentalMetrics else { return false }
        switch hrr {
        case .loading, .noData: return false
        case .noCoverage, .reading: return true
        }
    }

    /// The HRR block, or nil when there's nothing to show (loading / no stored HR). Placed after the
    /// heart block because it's a post-effort cardiac read. Color lives only on the bpm datum
    /// (`dataHeart`), hierarchy by space — the «Instrumento» DNA.
    @ViewBuilder private var hrrBlock: some View {
        switch hrr {
        case .loading, .noData:
            EmptyView()
        case .noCoverage:
            VStack(alignment: .leading, spacing: 6) {
                Text("Cardiac recovery · 60 s").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("No clean recovery reading for this session.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .reading(bpm, trend):
            // Pink anchor bar (chrome, static) + a staggered column: the overline is fixed; the number,
            // verdict, baseline and disclaimer rise+fade 70 ms apart. Color lives only on the bpm datum.
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 2).fill(theme.dataHeart) // token-exempt: geometría de dato (barra ancla HRR)
                    .frame(width: 3).padding(.vertical, 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cardiac recovery · 60 s").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    hrrRise(0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(bpm)").instrumentoHero(40).foregroundStyle(theme.dataHeart)
                            Text("bpm in 60 s").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                        }
                    }
                    hrrRise(1) {
                        Text(hrrNote(trend))
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let base = trend.baselineBpm, trend.nPrior >= 2 {
                        hrrRise(2) {
                            Text("vs your normal · ~\(Int(base.rounded())) bpm · \(trend.nPrior) sessions")
                                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        }
                    }
                    hrrRise(3) {
                        Text("Personal trend, not a clinical threshold. Experimental reading.")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            // Each element's own `.animation(value: hrrRevealed)` drives the staggered rise; just flip
            // the flag on appear (once).
            .onAppear { hrrRevealed = true }
        }
    }

    /// One staggered element of the HRR reading: rises 9 pt + fades in, ease-out 0.46 s, delayed 70 ms ·
    /// `index`. No bounce; honors Reduce Motion (appears in place). The chrome/divider never animate.
    @ViewBuilder private func hrrRise<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(hrrRevealed ? 1 : 0)
            .offset(y: (hrrRevealed || reduceMotion) ? 0 : 9)
            .strandAnimation(.easeOut(duration: 0.46).delay(Double(index) * 0.07), value: hrrRevealed)
    }

    /// es-MX copy mapped from the engine's TREND STATE (not the engine's raw English `note`), so the
    /// message localizes with the app while staying the engine's intra-user story — never Cole's cutoff.
    private func hrrNote(_ trend: HeartRateRecovery.Trend) -> LocalizedStringKey {
        if trend.nPrior < 2 {
            return "Still learning your usual recovery: keep logging sessions."
        }
        if trend.bluntedVsNormal {
            return "Your heart came down slower than usual after this one: a sign to watch recovery."
        }
        if let z = trend.z, z >= HeartRateRecovery.bluntedZThreshold {
            return "Your heart came down faster than usual: strong recovery after this session."
        }
        return "Your recovery after this session looks like your normal."
    }

    /// Compute HRR-60s for this session from the stored HR stream, and place it against the user's own
    /// prior sessions. Bounded work: one HR fetch for this session, plus a fetch per recent prior session
    /// to build the personal baseline. All reads are on-device; failures degrade to `.noData`/`.noCoverage`.
    private func loadHRR() async {
        let pad = HeartRateRecovery.horizonS + 2 * HeartRateRecovery.anchorHalfWidthS
        let hr = await repo.hrSamples(from: row.endTs - 2 * HeartRateRecovery.anchorHalfWidthS,
                                      to: row.endTs + pad, limit: 4000)
        guard !hr.isEmpty else { hrr = .noData; return }

        let result = HeartRateRecovery.hrr60s(sessionEnd: row.endTs, hr: hr)
        guard result.covered, let drop = result.hrrBpm else { hrr = .noCoverage; return }

        // Personal baseline: HRR of the most recent prior sessions that carried a clean reading.
        let priors = await repo.workoutRows()
            .filter { $0.endTs < row.endTs && ($0.avgHr != nil) }
            .sorted { $0.endTs > $1.endTs }
            .prefix(hrrMaxPriorSessions)
        var priorHRR: [Double] = []
        for p in priors {
            let phr = await repo.hrSamples(from: p.endTs - 2 * HeartRateRecovery.anchorHalfWidthS,
                                           to: p.endTs + pad, limit: 4000)
            let pr = HeartRateRecovery.hrr60s(sessionEnd: p.endTs, hr: phr)
            if pr.covered, let v = pr.hrrBpm { priorHRR.append(v) }
        }
        hrr = .reading(bpm: Int(drop.rounded()),
                       trend: HeartRateRecovery.trend(latest: drop, priorHRR: priorHRR))
    }

    // MARK: - Strength volume (time-overlap join to StrengthSession — no FK)

    /// Match this journal `WorkoutRow` to an in-app strength session by interval overlap (same style as
    /// `IntelligenceEngine` real-workout skip: `a.start < b.end && b.start < a.end`). Closest `startTs`
    /// wins when several overlap. Volume comes from `sessionVolumes()`; leave 0 when nothing real.
    private func loadVolume() async {
        volumeKg = 0
        let sessions = await repo.recentSessions()
        let rowStart = row.startTs
        let rowEnd = row.endTs
        let matches = sessions.filter { s in
            let sEnd = s.endTs ?? s.startTs
            return s.startTs < rowEnd && rowStart < sEnd
        }
        guard let matched = matches.min(by: { abs($0.startTs - rowStart) < abs($1.startTs - rowStart) })
        else { return }
        if let rid = matched.routineId, let store = await repo.storeHandle() {
            routineTitle = ((try? await store.routines()) ?? []).first(where: { $0.id == rid })?.name
        }
        let volumes = await repo.sessionVolumes()
        if let vol = volumes[matched.id]?.volumeKg, vol > 0 {
            volumeKg = vol
        }
    }
}

// MARK: - Shared source badge (list + detail)

/// The origin badge, colored per source (the user's choice over an all-ink treatment): Whoop ember, Apple
/// blue, Detected neutral ink (it's an honest "we guessed"), Manual amber. Built from the locked
/// `SourceBadge`. A free function so the list's rows and the detail's "Source" line stay identical.
@ViewBuilder
func workoutSourceBadge(for source: String, theme: InstrumentoTheme) -> some View {
    let (label, tint, a11y): (LocalizedStringKey, Color, LocalizedStringKey) = {
        switch WorkoutSource.classify(source) {
        case .whoop:    return ("Measured with your band", theme.dataStrain, "Source: measured with your band")
        case .apple:    return ("Apple", theme.dataSpO2, "Source Apple Health")
        case .detected: return ("Detected", theme.inkSecondary, "Source on-device detected")
        case .manual:   return ("Manual", theme.warning, "Source manual entry")
        }
    }()
    SourceBadge(label, tint: tint).accessibilityLabel(Text(a11y))
}
#endif
