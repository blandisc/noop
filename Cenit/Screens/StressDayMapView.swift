#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// StressDayMapView.swift — the «mapa del día» block for the Detalle de Estrés (FER-377).
//
// Vertical carril (Apple-Calendar-day-view metaphor) in the «Instrumento» language: time runs top→down,
// a stress STRIP colored by band on the left is the ONLY saturated color (the datum), events are plain
// TEXT ROWS on the right (no cards — DNA: no card-in-card). The day's peak is tied to its event and the
// coincidence is stated as observation ("fell within"), never cause. Honest with gaps: noisy/active
// buckets and cold start read "no reading", never a fabricated value. Driven by `CalendarDayMap`.

struct StressDayMapBlock: View {
    @ObservedObject var model: CalendarDayMap
    var theme: InstrumentoTheme = .base
    @State private var showPicker = false

    var body: some View {
        InfoAccordion(
            title: "Stress through the day",
            explanation: "We put your day's stress curve next to your events so you can see what your most and least activated moments coincided with. Here each moment is measured against your recent calm — your waking readings over about the last 7 days — so this maps when you spiked today, a different lens from the day's number above (your whole day vs your 30-day baseline). You choose which calendars are included; all-day events aren't matched to a moment. It reads coincidence, not cause — seeing two things together doesn't mean one caused the other. Everything is computed on your iPhone; nothing is shared.",
            accessibilityLabel: "Information about stress through the day",
            theme: theme
        ) {
            content
        }
        .task { await model.refresh() }
        .sheet(isPresented: $showPicker) {
            CalendarPickerSheet(model: model, theme: theme, isPresented: $showPicker)
                .instrumentoTheme(theme)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .needsPermission: invitation
        case .denied:          deniedView
        case .restricted:      restrictedView
        case .chooseCalendars: chooseView
        case .loading:         loadingView
        case .ready(let map):  ready(map)
        }
    }

    // MARK: - Permission / selection states

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28)).foregroundStyle(theme.inkTertiary)
            Text("Cross today's stress curve with your calendar to see what your most activated moments coincided with. Everything stays on your iPhone.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton("Connect my calendar") { Task { await model.requestAccess() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar access is off. Turn it on in Settings › Privacy & Security › Calendars › Cénit to see this cross-reference.")
                .font(StrandFont.footnote).foregroundStyle(theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.openSettings() } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var restrictedView: some View {
        Text("Your calendar isn't available on this device because of a system restriction.")
            .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chooseView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose which calendars to cross with your stress. You'll only see the ones you pick; nothing is shared.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton("Choose calendars") { showPicker = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingView: some View {
        Text("Crossing your day…")
            .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }

    // MARK: - Ready — «Momentos primero» (FER-433)
    //
    // Answer-first: the headline names the day's peak + the event it fell within; a small supporting bars
    // strip gives the shape of the day; then the ranked activated moments + the calmest one. The chart
    // never carries an event name (titles live in the rows + headline, cleaned + truncated); all-day
    // events stay context-only at the bottom.

    @ViewBuilder private func ready(_ map: CalendarDayMap.DayMap) -> some View {
        let hasReadings = map.curve.contains { $0.stress != nil }
        let hasEvents = !map.timed.isEmpty
        VStack(alignment: .leading, spacing: 16) {
            if map.referenceMissing {
                // Cold start: the personal waking reference isn't ready, so there's no curve to read yet.
                Text("I'm still learning your rhythm — I need a few days of waking readings to mark your peaks. Your events are already here.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasReadings && !hasEvents {
                Text("No events today and no stress readings yet — your curve fills in as your strap syncs.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                headline(map.coincidence)
                if hasReadings {
                    StressBarsStrip(curve: map.curve, events: map.timed, now: map.now, theme: theme)
                }
                momentsSections(map.moments)
            }
            if !map.allDay.isEmpty { allDayRow(map.allDay) }
            calendarsFooter(map.selectedNames)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Headline — the answer (peak + its event + level)

    @ViewBuilder private func headline(_ c: StressDayMap.Coincidence?) -> some View {
        if let c {
            let time = c.peakDate.formatted(.dateTime.hour().minute())
            // Give the peak a SIZE, not just an hour (Pase v2 #3): how far it rose above your usual calm
            // (the Low / activated boundary, `activatedFloor` = 1.0 — the same line drawn behind the bars).
            let overCalm = c.peakStress - StressMoments.activatedFloor
            let head = Text("Your highest point today was at \(time)").foregroundColor(theme.ink)
            let tail: Text = overCalm >= 0.1
                ? Text(verbatim: " — ").foregroundColor(theme.inkTertiary)
                    + Text("+\(magFmt(overCalm)) over your usual calm.").foregroundColor(bandColor(c.peakStress))
                : Text(verbatim: ".").foregroundColor(theme.ink)
            VStack(alignment: .leading, spacing: 4) {
                (head + tail)
                    .font(StrandFont.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let ev = c.event {
                    (Text("Coincided with “\(EventTitleCleaner.clean(ev.title))” · ")
                        .foregroundColor(theme.inkSecondary)
                     + Text(bandWord(c.peakStress)).foregroundColor(bandColor(c.peakStress)))
                        .font(StrandFont.subhead)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("It didn't coincide with any of your events.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("It's coincidence, not cause.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Moments — the ranked list (magnitude + time + clean event + band)

    @ViewBuilder private func momentsSections(_ m: StressMoments.DayMoments) -> some View {
        if !m.activated.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Your most activated moments")
                ForEach(Array(m.activated.enumerated()), id: \.offset) { _, mo in momentRow(mo) }
            }
        }
        if let calm = m.calmest {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Your calmest moment")
                momentRow(calm)
            }
        }
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key).instrumentoOverline().foregroundStyle(theme.inkTertiary)
    }

    private func momentRow(_ mo: StressMoments.Moment) -> some View {
        let time = mo.date.formatted(.dateTime.hour().minute())
        let cleanTitle = mo.event.map { EventTitleCleaner.clean($0.title) }
        return HStack(alignment: .center, spacing: 12) {
            magnitudeMeter(mo.stress)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: time).font(StrandFont.subhead).foregroundStyle(theme.ink)
                if let cleanTitle {
                    Text(verbatim: cleanTitle)
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                        .lineLimit(1).truncationMode(.tail)
                } else {
                    Text("no event on your calendar")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).italic()
                }
            }
            Spacer(minLength: 8)
            Text(bandWord(mo.stress)).font(StrandFont.footnote).foregroundStyle(bandColor(mo.stress))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(momentA11yLabel(mo, time: time))
    }

    /// VoiceOver reads time + the ORIGINAL (uncleaned) event title + the band word (band never by color
    /// alone). The display uses the cleaned title; accessibility keeps the user's full title.
    private func momentA11yLabel(_ mo: StressMoments.Moment, time: String) -> Text {
        var label = Text(verbatim: time)
        if let ev = mo.event { label = label + Text(verbatim: ", \(ev.title)") }
        return label + Text(verbatim: ", ") + Text(bandWord(mo.stress))
    }

    /// A small 0–3 magnitude bar in the moment's band color (how high that moment ran).
    private func magnitudeMeter(_ stress: Double) -> some View {
        let frac = max(0, min(1, stress / 3))
        return ZStack(alignment: .leading) {
            Capsule().fill(theme.hairline).frame(width: 40, height: 6)
            Capsule().fill(bandColor(stress)).frame(width: 40 * frac, height: 6)
        }
        .frame(width: 40)
    }

    // MARK: Band helpers (reuse StressBand — single source for the 0–3 → band mapping)

    private func bandColor(_ score: Double) -> Color { StressBand(score: score).dataColor(theme) }
    private func bandWord(_ score: Double) -> LocalizedStringKey { StressBand(score: score).displayWord }

    /// A 0–3 magnitude at one decimal, with no sign (the caller prepends «+»). e.g. 0.9.
    private func magFmt(_ v: Double) -> String { String(format: "%.1f", v) }

    private func allDayRow(_ events: [StressDayMap.DayEvent]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All day").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(verbatim: events.map { EventTitleCleaner.clean($0.title) }.joined(separator: " · "))
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1).offset(y: -8) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("All day: \(events.map(\.title).joined(separator: ", ")). Not matched to a moment."))
    }

    private func calendarsFooter(_ names: [String]) -> some View {
        Button { showPicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text("Calendars: \(names.isEmpty ? String(localized: "none") : names.joined(separator: ", "))")
                Text("· change").underline()
            }
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - Hourly bars strip (the day's shape, scrubbable) — FER-433 / 447

/// An hour-by-hour strip of the day's 0–3 stress — each bar is the MEAN of that civil hour's readings,
/// colored by band, from midnight to the current hour. Hold-and-drag to scrub: the touched hour highlights
/// and the readout names its level (band word in band colour) and the event that overlapped it. Taller than
/// the old per-bucket strip so the shape reads clearly. Hours with no waking reading (activity / sleep) draw
/// a faint stub, never a fabricated value. The precise peak + ranked moments still come from the fine 3-min
/// curve (headline + list), so this stays the day's *shape*; decorative for VoiceOver (the moments list and
/// headline carry the meaning).
private struct StressBarsStrip: View {
    let curve: [StressEngine.StressPoint]
    let events: [StressDayMap.DayEvent]
    let now: Date
    let theme: InstrumentoTheme

    /// The hour the user is reading; it persists after release so the value stays legible. nil before any touch.
    @State private var scrubHour: Int? = nil
    /// True only while the finger is down — dims the un-selected bars and shows the cursor line.
    @State private var isDragging = false

    private static let barsHeight: CGFloat = 150

    private var cal: Calendar { .current }
    private var startOfDay: Date { cal.startOfDay(for: now) }
    private var nowHour: Int { cal.component(.hour, from: now) }

    /// Mean 0–3 stress per civil hour, midnight → the current hour (nil = no waking reading that hour).
    private var hourly: [Double?] {
        var sums = [Double](repeating: 0, count: 24)
        var counts = [Int](repeating: 0, count: 24)
        for p in curve {
            guard let s = p.stress else { continue }
            let h = cal.component(.hour, from: p.date)
            guard (0..<24).contains(h) else { continue }
            sums[h] += s; counts[h] += 1
        }
        return (0...nowHour).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
    }

    var body: some View {
        let hours = hourly
        return VStack(alignment: .leading, spacing: 8) {
            readout(hours)
            chart(hours)
            axis
        }
        .sensoryFeedback(.selection, trigger: scrubHour)
        .accessibilityHidden(true)
    }

    // MARK: Readout — hora + nivel + evento (the hour under the finger)

    @ViewBuilder private func readout(_ hours: [Double?]) -> some View {
        Group {
            if let h = scrubHour, h < hours.count {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: hourLabel(h)).font(StrandFont.headline).foregroundStyle(theme.ink)
                        if let v = hours[h] {
                            Text(StressBand(score: v).displayWord)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StressBand(score: v).dataColor(theme))
                        } else {
                            Text("no reading").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        }
                    }
                    eventLine(atHour: h, hasReading: hours[h] != nil)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                    Text("Hold and slide to read each hour")
                }
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(height: 40, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func eventLine(atHour h: Int, hasReading: Bool) -> some View {
        if !hasReading {
            Text("during activity or sleep").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        } else if let title = eventTitle(atHour: h) {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 11))
                Text(verbatim: title).lineLimit(1).truncationMode(.tail)
            }
            .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        } else {
            Text("no event on your calendar")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).italic()
        }
    }

    // MARK: Bars + scrub

    private func chart(_ hours: [Double?]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let n = hours.count
            ZStack(alignment: .bottomLeading) {
                calmReferenceLine                     // «your usual calm» dashed line, behind the bars (#6)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(0..<n), id: \.self) { h in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(hours[h].map { StressBand(score: $0).dataColor(theme) } ?? theme.hairlineStrong)
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight(hours[h]), alignment: .bottom)
                            .opacity(isDragging && scrubHour != h ? 0.3 : 1)
                    }
                }
                .frame(width: w, height: Self.barsHeight, alignment: .bottom)
            }
            .frame(width: w, height: Self.barsHeight, alignment: .bottom)
            .overlay(alignment: .leading) { cursor(w: w, n: n) }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        isDragging = true
                        let idx = Int((val.location.x / w) * CGFloat(n))
                        scrubHour = Swift.min(n - 1, Swift.max(0, idx))
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: Self.barsHeight)
    }

    /// A dotted «your usual calm» reference (Pase v2 #6): a horizontal dashed line at the Low / activated
    /// boundary (stress 1.0, `activatedFloor`), so which hours rose into activated reads at a glance —
    /// exactly the bars that are NOT calm-colored. Drawn behind the bars, with a quiet right-aligned tag.
    private var calmReferenceLine: some View {
        let frac = CGFloat(StressMoments.activatedFloor / 3.0)   // 1.0 of 0–3
        return VStack(alignment: .trailing, spacing: 2) {
            Text("your usual calm")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.inkTertiary)
            DashedHLine()
                .stroke(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .offset(y: -frac * Self.barsHeight)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func cursor(w: CGFloat, n: Int) -> some View {
        if isDragging, let h = scrubHour, n > 0 {
            Rectangle().fill(theme.ink.opacity(0.55))
                .frame(width: 1.5, height: Self.barsHeight + 2)
                .offset(x: (CGFloat(h) + 0.5) / CGFloat(n) * w - 0.75, y: -1)
        }
    }

    private var axis: some View {
        HStack {
            Text(verbatim: startOfDay.formatted(.dateTime.hour()))
            Spacer()
            Text("now").foregroundStyle(theme.ink)
        }
        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
    }

    // MARK: Helpers

    private func barHeight(_ v: Double?) -> CGFloat {
        guard let v else { return 3 }
        return Swift.max(7, CGFloat(Swift.min(1, v / 3)) * Self.barsHeight)
    }

    private func hourLabel(_ h: Int) -> String {
        startOfDay.addingTimeInterval(TimeInterval(h * 3600)).formatted(.dateTime.hour())
    }

    /// The first timed event overlapping `[hourStart, hourStart+1h)`, cleaned for display. nil = none.
    private func eventTitle(atHour h: Int) -> String? {
        let s = startOfDay.addingTimeInterval(TimeInterval(h * 3600))
        let e = s.addingTimeInterval(3600)
        guard let ev = events.first(where: { $0.start < e && $0.end > s }) else { return nil }
        return EventTitleCleaner.clean(ev.title)
    }
}

// MARK: - Calendar picker

private struct CalendarPickerSheet: View {
    @ObservedObject var model: CalendarDayMap
    let theme: InstrumentoTheme
    @Binding var isPresented: Bool
    @State private var selected: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose calendars").font(StrandFont.title2).foregroundStyle(theme.ink)
                    Text("We'll only cross the ones you pick.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                if model.calendars.isEmpty {
                    Text("There are no calendars on this iPhone yet.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.calendars) { cal in
                            Button { toggle(cal.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selected.contains(cal.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(selected.contains(cal.id) ? theme.verdict : theme.inkTertiary)
                                    Text(verbatim: cal.label).font(StrandFont.subhead).foregroundStyle(theme.ink)
                                    Spacer(minLength: 8)
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                QuietButton("Done") {
                    Task { await model.updateSelection(selected); isPresented = false }
                }
                .disabled(selected.isEmpty)
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .onAppear { selected = model.selectedIDs }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

// MARK: - Dashed horizontal line (for the «your usual calm» reference)

/// A single horizontal line through the view's vertical center, for `.stroke(dash:)`. Token-free shape.
private struct DashedHLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
#endif
