import SwiftUI
import StrandDesign

/// The compact "Sources" summary card — one tinted row per data source (WHOOP / Apple Health) plus
/// the last-sync footnote. Extracted from `TodayView` so the same card can live both on the macOS
/// Today footer and at the bottom of the iOS Data Sources screen. (FER-137 moved it off the iPhone
/// Today, which now reads as verdict + Key Metrics only.)
///
/// Self-contained: reads `repo`/`live` from the environment and loads its own apple-health workout
/// count, so any host just drops it in with no data plumbing. Renders nothing until there's data or a
/// sync to report.
struct SourcesSummaryCard: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState

    @State private var appleWorkouts = 0

    var body: some View {
        let whoopDays = repo.days.count - repo.appleHealthDays.count
        let ahDays    = repo.appleHealthDays.count
        let hasData   = whoopDays > 0 || ahDays > 0
        let hasSync   = live.lastSyncError != nil || live.lastSyncedAt != nil
        let showsSync = !live.backfilling && hasSync

        Group {
            if hasData || showsSync {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                        Text("Sources").strandOverline()
                        if hasData {
                            if whoopDays > 0 {
                                sourceRow(symbol: "bolt.heart.fill", name: "WHOOP",
                                          count: String(localized: "\(whoopDays) days · \(repo.sleeps.count) sleeps"),
                                          tint: StrandPalette.accent)
                            }
                            if ahDays > 0 {
                                sourceRow(symbol: "heart.fill", name: "Apple Health",
                                          count: String(localized: "\(ahDays) days · \(appleWorkouts) workouts"),
                                          tint: StrandPalette.metricCyan)
                            }
                        }
                        if showsSync {
                            if hasData { Divider().overlay(StrandPalette.hairline) }
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                if let error = live.lastSyncError {
                                    syncLine(text: error, tone: .warning, color: StrandPalette.statusWarning)
                                } else if let at = live.lastSyncedAt {
                                    syncLine(text: String(localized: "History synced \(relativeAgo(at, now: context.date.timeIntervalSince1970))"),
                                             tone: .neutral, color: StrandPalette.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            appleWorkouts = (await repo.workoutRows()).filter { $0.source == "apple-health" }.count
        }
    }

    /// One data-source row: tinted glyph + brand name on the left, tabular count flush right.
    private func sourceRow(symbol: String, name: LocalizedStringKey, count: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: NoopMetrics.sourceGlyph, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 8)
            Text(count).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    /// The sync footer line: a small status dot + footnote text.
    private func syncLine(text: String, tone: StrandTone, color: Color) -> some View {
        HStack(spacing: 6) {
            ConnectionDot(tone: tone, size: 6)
            Text(text).font(StrandFont.footnote).foregroundStyle(color)
        }
    }
}
