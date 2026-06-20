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
            explanation: "We put your day's stress curve next to your events so you can see what your most and least activated moments coincided with. You choose which calendars are included; all-day events aren't matched to a moment. It reads coincidence, not cause — seeing two things together doesn't mean one caused the other. Everything is computed on your iPhone; nothing is shared.",
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

    // MARK: - Ready

    @ViewBuilder private func ready(_ map: CalendarDayMap.DayMap) -> some View {
        let hasReadings = map.curve.contains { $0.stress != nil }
        let hasEvents = !map.timed.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            if !map.allDay.isEmpty {
                allDayRow(map.allDay)
            }

            // Draw the carril whenever there's anything to plot — a curve, events, or both.
            if hasReadings || hasEvents {
                StressCarril(map: map, theme: theme)
            }

            if map.referenceMissing {
                // Cold start: the personal waking reference isn't ready, so there's no curve to read yet.
                Text("I'm still learning your rhythm — I need a few days of waking readings to mark your peaks. Your events are already here.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if hasReadings, let line = coincidenceLine(map.coincidence) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13)).foregroundStyle(theme.critical)
                    line.font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            } else if !hasReadings && !hasEvents {
                Text("No events today and no stress readings yet — your curve fills in as your strap syncs.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            calendarsFooter(map.selectedNames)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func allDayRow(_ events: [StressDayMap.DayEvent]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All day").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(verbatim: events.map(\.title).joined(separator: " · "))
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("All day: \(events.map(\.title).joined(separator: ", ")). Not matched to a moment."))
    }

    /// Build the day's coincidence sentence (observation, never cause). `nil` when there's no reading.
    private func coincidenceLine(_ c: StressDayMap.Coincidence?) -> Text? {
        guard let c else { return nil }
        let time = c.peakDate.formatted(.dateTime.hour().minute())
        if let ev = c.event {
            return Text("Your highest point today, \(time), fell within “\(ev.title)”.")
        }
        return Text("Your highest point today was at \(time). It didn't coincide with any of your events.")
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

// MARK: - The carril (time axis + stress strip + event rows)

private struct StressCarril: View {
    let map: CalendarDayMap.DayMap
    let theme: InstrumentoTheme

    private let stripX: CGFloat = 44
    private let stripW: CGFloat = 9
    private let eventX: CGFloat = 64
    private let rowH: CGFloat = 34
    private let bucketSeconds: Double = 180

    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        // At accessibility text sizes the positioned carril can't stay legible without horizontal
        // scroll → fall back to a plain time-ordered list ("time · event · band"). (FER-377 a11y)
        if dynamicType.isAccessibilitySize { accessibleList } else { carril }
    }

    private var carril: some View {
        let layout = Layout(map: map, bucketSeconds: bucketSeconds, rowH: rowH)
        return ZStack(alignment: .topLeading) {
            // time rule
            Rectangle().fill(theme.hairline)
                .frame(width: 1, height: layout.height)
                .offset(x: stripX - 2, y: 0)

            // stress strip — the only saturated color (the datum)
            RoundedRectangle(cornerRadius: stripW / 2, style: .continuous)
                .fill(theme.surface)
                .frame(width: stripW, height: layout.height)
                .offset(x: stripX, y: 0)
            ForEach(layout.segments) { seg in
                Rectangle().fill(color(for: seg.value))
                    .frame(width: stripW, height: max(1, seg.height))
                    .offset(x: stripX, y: seg.y)
            }

            // hour labels
            ForEach(layout.hours) { h in
                Text(h.label).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(width: 34, alignment: .trailing)
                    .offset(x: 0, y: h.y - 7)
                    .accessibilityHidden(true)
            }

            // "now" marker (partial day)
            if let nowY = layout.nowY {
                Rectangle().fill(theme.inkTertiary.opacity(0.5))
                    .frame(width: stripW + 8, height: 1)
                    .offset(x: stripX - 4, y: nowY)
            }

            // peak dot tied to the event
            if let peakY = layout.peakY {
                Circle().fill(theme.critical)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(theme.paper, lineWidth: 1.5))
                    .offset(x: stripX + stripW / 2 - 5, y: peakY - 5)
            }

            // event rows (text, no boxes)
            ForEach(layout.events) { row in
                eventRow(row).offset(x: eventX, y: row.y - rowH / 2)
            }
        }
        .frame(height: layout.height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func eventRow(_ row: Layout.EventRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: row.event.title)
                .font(row.isPeak ? StrandFont.subhead.weight(.medium) : StrandFont.subhead)
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            // The peak's red time + the coincidence line carry the peak; no extra "peak" word needed.
            Text(verbatim: row.timeLabel)
                .font(StrandFont.footnote)
                .foregroundStyle(row.isPeak ? theme.critical : theme.inkTertiary)
        }
        .frame(height: rowH, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowLabel(row))
    }

    /// Localized VoiceOver label: title, time, and (when known) the stress band during the event — so the
    /// band is never conveyed by color alone. Dynamic title + locale time, no English connectors. (FER-377)
    private func rowLabel(_ row: Layout.EventRow) -> Text {
        var label = Text(verbatim: "\(row.event.title), \(row.timeLabel)")
        if let bw = row.bandWord { label = label + Text(verbatim: ", ") + Text(verbatim: bw) }
        return label
    }

    private var accessibleList: some View {
        let layout = Layout(map: map, bucketSeconds: bucketSeconds, rowH: rowH)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(layout.events) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text(verbatim: row.timeLabel)
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: row.event.title)
                            .font(row.isPeak ? StrandFont.subhead.weight(.medium) : StrandFont.subhead)
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let bw = row.bandWord {
                            Text(verbatim: bw).font(StrandFont.footnote)
                                .foregroundStyle(row.isPeak ? theme.critical : theme.inkTertiary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowLabel(row))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for value: Double?) -> Color {
        guard let v = value else { return theme.hairlineStrong }   // "no reading" gray
        return v < 1 ? theme.verdict : (v < 2 ? theme.warning : theme.critical)
    }

    // MARK: Layout math (pure, computed once)

    struct Layout {
        struct Seg: Identifiable { let id = UUID(); let y: CGFloat; let height: CGFloat; let value: Double? }
        struct Hour: Identifiable { let id = UUID(); let y: CGFloat; let label: String }
        struct EventRow: Identifiable {
            let id = UUID(); let y: CGFloat; let event: StressDayMap.DayEvent
            let isPeak: Bool; let timeLabel: String; let bandWord: String?
        }

        let height: CGFloat
        let segments: [Seg]
        let hours: [Hour]
        let events: [EventRow]
        let peakY: CGFloat?
        let nowY: CGFloat?

        init(map: CalendarDayMap.DayMap, bucketSeconds: Double, rowH: CGFloat) {
            let cal = Calendar.current
            // Visible window: from the earliest of (first reading, first event, 6am) to the latest of
            // (last reading, last event end, now), floored/ceiled to the hour.
            var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
            for p in map.curve { lo = min(lo, p.date.timeIntervalSince1970 - bucketSeconds); hi = max(hi, p.date.timeIntervalSince1970) }
            for e in map.timed { lo = min(lo, e.start.timeIntervalSince1970); hi = max(hi, e.end.timeIntervalSince1970) }
            let startOfDay = cal.startOfDay(for: map.now).timeIntervalSince1970
            let sixAM = startOfDay + 6 * 3600
            if lo == Double.greatestFiniteMagnitude { lo = sixAM; hi = map.now.timeIntervalSince1970 }
            lo = min(lo, sixAM); hi = max(hi, map.now.timeIntervalSince1970)
            lo = (lo / 3600).rounded(.down) * 3600
            hi = (hi / 3600).rounded(.up) * 3600
            let span = max(3600, hi - lo)
            let pxPerHour: CGFloat = 26
            let baseHeight = CGFloat(span / 3600) * pxPerHour

            func y(_ ts: Double) -> CGFloat { CGFloat((ts - lo) / span) * baseHeight }

            // strip segments (each reading covers [date-bucket, date])
            segments = map.curve.map { p in
                let y0 = y(p.date.timeIntervalSince1970 - bucketSeconds)
                let y1 = y(p.date.timeIntervalSince1970)
                return Seg(y: y0, height: y1 - y0, value: p.stress)
            }

            // hour ticks every 2h
            var hrs: [Hour] = []
            var t = lo
            while t <= hi {
                let label = Date(timeIntervalSince1970: t).formatted(.dateTime.hour())
                hrs.append(Hour(y: y(t), label: label))
                t += 7200
            }
            hours = hrs

            // peak
            let peakDate = map.coincidence?.peakDate
            peakY = peakDate.map { y($0.timeIntervalSince1970) }

            // now (only if before the end of the window → partial day)
            let nowTs = map.now.timeIntervalSince1970
            nowY = nowTs < hi ? y(nowTs) : nil

            // events: place at start time, then push down to avoid overlap (keeps order + ~time)
            var rows: [EventRow] = []
            var prevY = -rowH
            for e in map.timed.sorted(by: { $0.start < $1.start }) {
                let natural = y(e.start.timeIntervalSince1970)
                let placed = max(natural, prevY + rowH)
                prevY = placed
                let isPeak = peakDate.map { $0 >= e.start && $0 <= e.end && !e.isAllDay } ?? false
                let timeLabel = e.start.formatted(.dateTime.hour().minute())
                let bandWord = StressDayMap.averageStress(during: e, in: map.curve).map { v -> String in
                    v < 1 ? String(localized: "Low") : (v < 2 ? String(localized: "Moderate") : String(localized: "High"))
                }
                rows.append(EventRow(y: placed, event: e, isPeak: isPeak, timeLabel: timeLabel, bandWord: bandWord))
            }
            events = rows

            height = max(baseHeight, (rows.last?.y ?? 0) + rowH)
        }
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
                                    Text(verbatim: cal.title).font(StrandFont.subhead).foregroundStyle(theme.ink)
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
#endif
