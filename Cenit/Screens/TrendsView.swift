import SwiftUI
import StrandDesign
import WhoopStore
import Foundation

// MARK: - Trends
//
// The longitudinal view, rebuilt on the locked Noop component system so every
// surface, height and gap is identical: one SegmentedPillControl for the range,
// a hero recovery ChartCard, a uniform grid of HRV / Resting HR / Day Strain
// ChartCards (all NoopMetrics.chartHeight tall), and the whole history as a
// recovery YearHeatStrip in a NoopCard. No hand-sized cards anywhere.

struct TrendsView: View {
    @EnvironmentObject var repo: Repository
    // NOTE: deliberately does NOT observe LiveState — Trends shows historical data only, and
    // observing it forced a full re-render of this subtree on every ~1 Hz live-HR tick.

    // The shared range control: W(7) / M(30) / 3M(90) / 6M(180) / 1Y(365) / ALL.
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week:    return String(localized: "W")
            case .month:   return String(localized: "M")
            case .quarter: return String(localized: "3M")
            case .half:    return String(localized: "6M")
            case .year:    return String(localized: "1Y")
            case .all:     return String(localized: "ALL")
            }
        }
        /// Trailing-day window, or nil for "all history".
        var days: Int? { self == .all ? nil : rawValue }

        /// This range plus every LARGER range, ascending — the auto-expand search
        /// order when the selected window holds zero points.
        var widening: [Range] {
            let order: [Range] = [.week, .month, .quarter, .half, .year, .all]
            guard let i = order.firstIndex(of: self) else { return [.all] }
            return Array(order[i...])
        }
    }

    @State private var range: Range = .quarter

    // Memoized snapshot of every expensive derivation (the four resolved series, the year strip,
    // the per-card Apple-source flags). Rebuilt only when the repo data or the selected range
    // actually changes — NOT on hover/animation re-renders. `nil` until first build / no history.
    @State private var model: TrendsModel?
    /// The input signature the cached `model` was built from; when it differs we rebuild.
    @State private var modelKey: TrendsInputKey?

    private struct ResolvedMetric {
        var points: [TrendPoint]
        var effective: Range
        var widened: Bool
        var caption: String
    }

    // MARK: Memoized build (FER-176)
    //
    // Everything expensive this screen draws — the four resolved metric series and the year
    // heat-strip — is derived ONCE per data/range change here, not per `body`. Each day-key is
    // parsed to a `Date` a single time and reused across every metric window + the strip, so a
    // multi-year import no longer re-filters `repo.days` and re-parses dates on the many body
    // re-evaluations from hover/animation. The result is cached in `model`, keyed by `dataKey`.

    /// Snapshot of every derivation the subviews read. Built once in `buildModel()`.
    private struct TrendsModel {
        var recovery: ResolvedMetric
        var hrv: ResolvedMetric
        var rhr: ResolvedMetric
        var strain: ResolvedMetric
        var hrvApple: Bool
        var rhrApple: Bool
        var stripDays: [RecoveryDay]
        var stripTitle: String
        var stripScored: Int
    }

    /// Cheap, Equatable fingerprint of the inputs the screen derives from (counts + newest-row
    /// identity + Apple-day count + the selected range). Recomputed every render but fast to
    /// compare; when it changes we rebuild `model`, otherwise re-renders pay nothing.
    private struct TrendsInputKey: Equatable {
        var loaded: Bool
        var daysCount: Int
        var firstDay: String?
        var lastDay: String?
        var lastDayRow: DailyMetric?
        var appleCount: Int
        var refreshSeq: Int
        var range: Int
    }

    private var dataKey: TrendsInputKey {
        TrendsInputKey(
            loaded: repo.loaded,
            daysCount: repo.days.count,
            firstDay: repo.days.first?.day,
            lastDay: repo.days.last?.day,
            lastDayRow: repo.days.last,
            appleCount: repo.appleHealthDays.count,
            refreshSeq: repo.refreshSeq,
            range: range.rawValue)
    }

    /// Build every derivation exactly once. Returns `nil` when there is no history.
    private func buildModel() -> TrendsModel? {
        let days = repo.days
        guard !days.isEmpty else { return nil }

        // Parse each distinct day-key to a Date a single time; reused by every window + the strip.
        var parsed: [String: Date] = [:]
        parsed.reserveCapacity(days.count)
        for d in days where parsed[d.day] == nil {
            parsed[d.day] = Repository.parseDayKey(d.day)
        }

        // Trailing-day window RELATIVE TO TODAY (the phone's local date) — not the latest recorded
        // day, which on a stale import anchored W/M/3M to months-old data so it looked current
        // (issue #23). Empty short windows auto-widen in `resolve`. `.all` returns everything.
        func window(_ r: Range) -> [DailyMetric] {
            guard let n = r.days else { return days }
            let cutoffKey = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date())
            return days.filter { $0.day >= cutoffKey }
        }
        func points(_ slice: [DailyMetric], _ value: (DailyMetric) -> Double?) -> [TrendPoint] {
            slice.compactMap { d in
                guard let v = value(d), let dt = parsed[d.day] else { return nil }
                return TrendPoint(date: dt, value: v)
            }
        }
        // Smallest range ≥ selected whose window holds ≥1 point (else ALL), keeping that window's
        // points so we don't re-filter to read them back.
        func resolve(_ value: (DailyMetric) -> Double?) -> ResolvedMetric {
            for r in range.widening {
                let pts = points(window(r), value)
                if !pts.isEmpty {
                    return ResolvedMetric(points: pts, effective: r,
                                          widened: r != range, caption: caption(count: pts.count, eff: r))
                }
            }
            let pts = points(days, value)
            return ResolvedMetric(points: pts, effective: .all,
                                  widened: .all != range, caption: caption(count: pts.count, eff: .all))
        }
        /// Whether the most recent day carrying this metric was surfaced from Apple Health (no
        /// strap coverage) — drives the per-card "Apple Health" source badge. (FER-62)
        func latestIsApple(_ value: (DailyMetric) -> Double?) -> Bool {
            guard let d = days.last(where: { value($0) != nil }) else { return false }
            return repo.appleHealthDays.contains(d.day)
        }

        // Year heat-strip: always at least a full year for context; all history on ALL.
        let stripCount = max(range.days ?? days.count, 365)
        let stripDays: [RecoveryDay] = days.suffix(stripCount).compactMap { d in
            guard let dt = parsed[d.day] else { return nil }
            return RecoveryDay(date: dt, score: d.recovery)
        }
        let stripTitle = (range == .all && days.count > 365) ? "Recovery — all history" : "Recovery — past year"

        return TrendsModel(
            recovery: resolve { $0.recovery },
            hrv: resolve { $0.avgHrv },
            rhr: resolve { $0.restingHr.map(Double.init) },
            strain: resolve { $0.strain },
            hrvApple: latestIsApple { $0.avgHrv },
            rhrApple: latestIsApple { $0.restingHr.map(Double.init) },
            stripDays: stripDays,
            stripTitle: stripTitle,
            stripScored: stripDays.filter { $0.score != nil }.count)
    }

    /// Caption text from an already-resolved count + effective range. Mirrors
    /// `caption(_:)` exactly but takes precomputed inputs to avoid re-filtering.
    private func caption(count n: Int, eff: Range) -> String {
        let unit = n == 1 ? String(localized: "reading") : String(localized: "readings")
        if eff != range {
            return String(localized: "\(n) \(unit) · sparse — widened to \(name(for: eff))")
        }
        return String(localized: "\(n) \(unit) · \(name(for: range))")
    }

    /// A padded value range for a series, snapped to "nice" bounds so the LOWEST gridline
    /// sits exactly at the plot floor. Without snapping, the 12% bottom pad pushes the floor
    /// below the lowest labelled gridline (e.g. strain floor ≈6.16 under a "8" gridline), so
    /// the area fill spills below the axis and reads as bleeding. Snapping to the same 1/2/5
    /// steps Swift Charts' `.automatic` axis uses makes the area sit on a labelled floor — the
    /// way the hero recovery chart sits cleanly on its "0" (#trends-bleed).
    private func valueRange(_ pts: [TrendPoint], fallback: ClosedRange<Double>, pad: Double = 0.12) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return fallback }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        let rawLo = lo - span * pad
        let rawHi = hi + span * pad
        let step = Self.niceStep((rawHi - rawLo) / 4)   // ~4 gridlines across the range
        let niceLo = (rawLo / step).rounded(.down) * step
        let niceHi = (rawHi / step).rounded(.up) * step
        return niceLo...niceHi
    }

    /// Round a rough axis step to the nearest "nice" 1/2/5 × 10ⁿ, matching the gridline
    /// steps `.automatic` axis marks pick — so our snapped bounds land on real gridlines.
    private static func niceStep(_ rough: Double) -> Double {
        guard rough > 0, rough.isFinite else { return 1 }
        let mag = pow(10, (log10(rough)).rounded(.down))
        let norm = rough / mag
        let nice: Double = norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10
        return nice * mag
    }

    private func mean(_ pts: [TrendPoint]) -> Double? {
        guard !pts.isEmpty else { return nil }
        return pts.map(\.value).reduce(0, +) / Double(pts.count)
    }

    /// "Trailing 90 days" / "All history" — used as a card subtitle.
    private var rangeSubtitle: String {
        guard let n = range.days else { return String(localized: "All history") }
        return String(localized: "Trailing \(n) days")
    }

    private func name(for r: Range) -> String {
        switch r {
        case .week:    return String(localized: "week")
        case .month:   return String(localized: "month")
        case .quarter: return String(localized: "3 months")
        case .half:    return String(localized: "6 months")
        case .year:    return String(localized: "year")
        case .all:     return String(localized: "all history")
        }
    }

    var body: some View {
        // Resolve the memoized model for THIS render. `dataKey` is O(1)-ish, so comparing it
        // every render is cheap; when it matches the cached key we reuse `model` untouched — the
        // many re-evaluations from hover/animation pay nothing. When it differs (or on first
        // render) we build once, here, so the very first frame already shows content. (FER-176)
        let key = dataKey
        let resolved: TrendsModel? = (key == modelKey) ? model : buildModel()
        return ScreenScaffold(title: "Trends", subtitle: "The thread of you over time.") {
            Group {
                if let m = resolved {
                    VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                        rangeBar(recovery: m.recovery)
                        heroRecovery(recovery: m.recovery)
                        smallMultiples(hrv: m.hrv, rhr: m.rhr, strain: m.strain,
                                       hrvApple: m.hrvApple, rhrApple: m.rhrApple)
                        yearStrip(m)
                    }
                } else {
                    ComingSoon(what: repo.loaded
                        ? "Trends need history to draw. Import your WHOOP export — or connect Apple Health — in Data Sources to see weeks, months and years."
                        : "Loading your history…")
                }
            }
            // Commit the freshly-built model after layout (writing @State during body is not
            // allowed); `resolved` already drives THIS frame, so there is no flash.
            .onChange(of: key) { _, newKey in
                modelKey = newKey
                model = buildModel()
            }
            .onAppear {
                if modelKey != key {
                    modelKey = key
                    model = resolved
                }
            }
        }
    }

    // MARK: Range control

    private func rangeBar(recovery: ResolvedMetric) -> some View {
        let cap = recovery.caption
        let isWide = recovery.widened
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SegmentedPillControl(Range.allCases, selection: $range) { $0.label }
                Spacer()
                Text(rangeSubtitle).strandOverline()
            }
            Text(cap)
                .font(StrandFont.footnote)
                .foregroundStyle(isWide ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                .accessibilityLabel(cap)
        }
    }

    // MARK: Hero — recovery over time

    private func heroRecovery(recovery: ResolvedMetric) -> some View {
        let pts = recovery.points
        let avg = mean(pts)
        return ChartCard(
            title: "Recovery",
            subtitle: recovery.caption,
            trailing: avg.map { "\(Int($0.rounded()))" },
            height: NoopMetrics.chartHeight,
            chart: {
                if pts.count >= 2 {
                    TrendChart(points: pts,
                               gradient: StrandPalette.recoveryGradient,
                               valueRange: 0...100,
                               showsArea: true,
                               height: NoopMetrics.chartHeight)
                } else {
                    sparsePlaceholder
                }
            },
            footer: {
                ChartFooter([
                    ("Avg", avg.map { "\(Int($0.rounded()))" } ?? "—"),
                    ("Peak", pts.map(\.value).max().map { "\(Int($0.rounded()))" } ?? "—"),
                    ("Low", pts.map(\.value).min().map { "\(Int($0.rounded()))" } ?? "—"),
                    ("Days", "\(pts.count)"),
                ])
            }
        )
    }

    // MARK: Small multiples — HRV / Resting HR / Day Strain

    private func smallMultiples(hrv: ResolvedMetric, rhr: ResolvedMetric, strain: ResolvedMetric,
                                hrvApple: Bool, rhrApple: Bool) -> some View {
        let cols = [GridItem(.adaptive(minimum: 320), spacing: NoopMetrics.gap)]
        let hrvPts = hrv.points
        let rhrPts = rhr.points
        let strainPts = strain.points

        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Daily signals", overline: "Trends", trailing: rangeSubtitle)
            LazyVGrid(columns: cols, alignment: .leading, spacing: NoopMetrics.gap) {
                metricChart(
                    title: "Heart rate variability", unit: String(localized: "ms"),
                    points: hrvPts,
                    subtitle: hrv.caption,
                    gradient: gradient(StrandPalette.metricPurple),
                    range: valueRange(hrvPts, fallback: 20...120),
                    appleSourced: hrvApple,
                    fmt: { "\(Int($0.rounded()))" }
                )
                metricChart(
                    title: "Resting heart rate", unit: String(localized: "bpm"),
                    points: rhrPts,
                    subtitle: rhr.caption,
                    gradient: gradient(StrandPalette.metricRose),
                    range: valueRange(rhrPts, fallback: 40...80),
                    appleSourced: rhrApple,
                    fmt: { "\(Int($0.rounded()))" }
                )
                metricChart(
                    title: "Day strain", unit: "/ 21",
                    points: strainPts,
                    subtitle: strain.caption,
                    gradient: StrandPalette.strainGradient,
                    range: valueRange(strainPts, fallback: 0...21),
                    fmt: { String(format: "%.1f", $0) }
                )
            }
        }
    }

    @ViewBuilder
    private func metricChart(
        title: LocalizedStringKey, unit: String,
        points pts: [TrendPoint],
        subtitle: String,
        gradient: Gradient,
        range: ClosedRange<Double>,
        appleSourced: Bool = false,
        fmt: @escaping (Double) -> String
    ) -> some View {
        let avg = mean(pts)
        ChartCard(
            title: title,
            subtitle: subtitle,
            trailing: avg.map(fmt),
            badge: appleSourced ? SourceBadge("Apple Health", tint: StrandPalette.metricCyan) : nil,
            height: NoopMetrics.chartHeight,
            chart: {
                if pts.count >= 2 {
                    TrendChart(points: pts,
                               gradient: gradient,
                               valueRange: range,
                               showsArea: true,
                               height: NoopMetrics.chartHeight,
                               valueFormat: { "\(fmt($0)) \(unit)" })
                } else {
                    sparsePlaceholder
                }
            },
            footer: {
                ChartFooter([
                    ("Mean \(unit)", avg.map(fmt) ?? "—"),
                    ("Min", pts.map(\.value).min().map(fmt) ?? "—"),
                    ("Max", pts.map(\.value).max().map(fmt) ?? "—"),
                ])
            }
        )
    }

    // MARK: Year heat-strip

    private func yearStrip(_ m: TrendsModel) -> some View {
        let recoveryDays = m.stripDays
        return NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("\(m.stripTitle)", overline: "Calendar", trailing: "\(m.stripScored) days")
                if recoveryDays.isEmpty {
                    sparsePlaceholder.frame(height: 120)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        YearHeatStrip(days: recoveryDays).padding(.vertical, 2)
                    }
                    Divider().overlay(StrandPalette.hairline)
                    legend
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Depleted").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            LinearGradient(gradient: StrandPalette.recoveryGradient, startPoint: .leading, endPoint: .trailing)
                .frame(width: 120, height: 8)
                .clipShape(Capsule())
            Text("Peaked").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer()
        }
    }

    // MARK: Shared bits

    /// Single-color gradient (for metric lines that aren't a value ramp).
    private func gradient(_ color: Color) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(0.55), location: 0.0),
            .init(color: color, location: 1.0),
        ])
    }

    private var sparsePlaceholder: some View {
        Text("Not enough data for this window.")
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#if DEBUG
@MainActor
private func previewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.dateFormat = "yyyy-MM-dd"
    let today = Date()
    var seeded: [DailyMetric] = []
    let span = 365 * 3
    for i in stride(from: span - 1, through: 0, by: -1) {
        guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
        let phase = Double(span - 1 - i)
        let rec = 55 + 28 * sin(phase / 11.0) + Double((Int(phase) * 31) % 17) - 8
        let hrv = 58 + 16 * sin(phase / 9.0) + Double((Int(phase) * 13) % 11) - 5
        let rhr = 52 + 4 * sin(phase / 7.0) + Double((Int(phase) * 7) % 5) - 2
        let strain = 9 + 6 * sin(phase / 5.0 + 1.2) + Double((Int(phase) * 5) % 4) - 2
        let gap = Int(phase) % 23 == 0
        seeded.append(DailyMetric(
            day: fmt.string(from: d),
            totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 110, lightMin: 200,
            disturbances: 6, restingHr: gap ? nil : Int(rhr.rounded()),
            avgHrv: gap ? nil : max(15, hrv), recovery: gap ? nil : max(2, min(99, rec)),
            strain: gap ? nil : max(0, min(21, strain)), exerciseCount: 1
        ))
    }
    repo.setDashboard(days: seeded)
    return repo
}

#Preview("Trends") {
    TrendsView()
        .environmentObject(previewRepo())
        .environmentObject(LiveState())
        .frame(width: 960, height: 960)
        .preferredColorScheme(.dark)
}
#endif
