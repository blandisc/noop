#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// StressDayMapView.swift — the «mapa del día» block for the Detalle de Estrés (FER-377 · FER-860).
//
// Presentation skin for the handoff «Detalle de Tendencias Final» / Estrés: content sits on a surface
// card under the parent's `SeccionFranja` (no nested InfoAccordion). Answer-first headline, hourly bars
// colored by band (gaps = short hairline, never interpolated), ranked moments with calendar events,
// and a `BarraAncla` explaining the gaps. Driven by `CalendarDayMap` — logic and EventKit unchanged.

struct StressDayMapBlock: View {
    @ObservedObject var model: CalendarDayMap
    var theme: InstrumentoTheme = .base
    @State private var showPicker = false

    var body: some View {
        content
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
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
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

    // MARK: - Ready — «Momentos primero» on a surface card (FER-433 · FER-860)

    @ViewBuilder private func ready(_ map: CalendarDayMap.DayMap) -> some View {
        let hasReadings = map.curve.contains { $0.stress != nil }
        let hasEvents = !map.timed.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            if map.referenceMissing {
                Text("I'm still learning your rhythm: I need a few days of waking readings to mark your peaks. Your events are already here.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasReadings && !hasEvents {
                Text("No events today and no stress readings yet: your curve fills in as your strap syncs.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                headline(map.coincidence)
                if hasReadings {
                    StressBarsStrip(curve: map.curve, events: map.timed, now: map.now, theme: theme)
                }
                momentsList(map.moments)
                if hasReadings {
                    BarraAncla(
                        String(localized: "The grey gaps are hours with no waking reading, never a made-up value."),
                        color: theme.hairline, theme: theme)
                }
            }
            if !map.allDay.isEmpty { allDayRow(map.allDay) }
            calendarsFooter(map.selectedNames)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.card, theme: theme)
    }

    // MARK: Headline — the answer (peak + its event + over-calm)

    @ViewBuilder private func headline(_ c: StressDayMap.Coincidence?) -> some View {
        if let c {
            let time = c.peakDate.formatted(.dateTime.hour().minute())
            let overCalm = c.peakStress - StressMoments.activatedFloor
            VStack(alignment: .leading, spacing: 3) {
                if let ev = c.event {
                    let clean = EventTitleCleaner.clean(ev.title)
                    // Reuses the existing coincidence copy keys (FER-433); clean title for display.
                    Text("Your highest point today, \(time), fell within “\(clean)”.")
                        .font(InstrumentoType.grotesk(16, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your highest point today was at \(time)")
                        .font(InstrumentoType.grotesk(16, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("no event on your calendar")
                        .font(InstrumentoType.grotesk(13))
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if overCalm >= 0.1 {
                    Text("+\(magFmt(overCalm)) over your usual calm.")
                        .font(InstrumentoType.grotesk(13))
                        .foregroundStyle(bandColor(c.peakStress))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Moments — ranked list (time + event + band word), hairlines between rows

    @ViewBuilder private func momentsList(_ m: StressMoments.DayMoments) -> some View {
        let rows: [StressMoments.Moment] = m.activated + (m.calmest.map { [$0] } ?? [])
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, mo in
                    if i > 0 {
                        Rectangle().fill(theme.hairline).frame(height: 1)
                    }
                    momentRow(mo)
                }
            }
        }
    }

    private func momentRow(_ mo: StressMoments.Moment) -> some View {
        let time = mo.date.formatted(.dateTime.hour().minute())
        let cleanTitle = mo.event.map { EventTitleCleaner.clean($0.title) }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: time)
                .font(InstrumentoType.groteskNumber(12))
                .foregroundStyle(theme.inkTertiary)
                .frame(width: 38, alignment: .leading)
                .monospacedDigit()
            if let cleanTitle {
                Text(verbatim: cleanTitle)
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("no event on your calendar")
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(bandWord(mo.stress))
                .font(InstrumentoType.grotesk(12, weight: .semibold))
                .foregroundStyle(bandColor(mo.stress))
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(momentA11yLabel(mo, time: time))
    }

    private func momentA11yLabel(_ mo: StressMoments.Moment, time: String) -> Text {
        var label = Text(verbatim: time)
        if let ev = mo.event { label = label + Text(verbatim: ", \(ev.title)") }
        return label + Text(verbatim: ", ") + Text(bandWord(mo.stress))
    }

    // MARK: Band helpers (reuse StressBand — single source for the 0–3 → band mapping)

    private func bandColor(_ score: Double) -> Color { StressBand(score: score).dataColor(theme) }
    private func bandWord(_ score: Double) -> LocalizedStringKey { StressBand(score: score).displayWord }
    private func magFmt(_ v: Double) -> String { String(format: "%.1f", v) }

    private func allDayRow(_ events: [StressDayMap.DayEvent]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All day").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(verbatim: events.map { EventTitleCleaner.clean($0.title) }.joined(separator: " · "))
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("All day: \(events.map(\.title).joined(separator: ", ")). Not matched to a moment."))
    }

    private func calendarsFooter(_ names: [String]) -> some View {
        Button { showPicker = true } label: {
            HStack(spacing: 6) {
                StrandIcon.calendar.image
                Text("Calendars: \(names.isEmpty ? String(localized: "none") : names.joined(separator: ", "))")
                Text("· change").underline()
            }
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - Hourly bars strip (the day's shape, scrubbable) — FER-433 / 447 / 860

/// Hour-by-hour 0–3 stress strip: each bar is the MEAN of that civil hour's readings, colored by band.
/// Gaps (no waking reading) draw a short hairline stub, never a fabricated value. Calm reference uses
/// `baseMark`. Axis ticks: 6 h / 14 h / 22 h. Logic unchanged from the previous map.
private struct StressBarsStrip: View {
    let curve: [StressEngine.StressPoint]
    let events: [StressDayMap.DayEvent]
    let now: Date
    let theme: InstrumentoTheme

    @State private var scrubHour: Int? = nil
    @State private var isDragging = false

    private static let barsHeight: CGFloat = 96
    private static let barWidth: CGFloat = 10

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
        return VStack(alignment: .leading, spacing: 6) {
            readout(hours)
            chart(hours)
            axis
        }
        .sensoryFeedback(.selection, trigger: scrubHour)
        .accessibilityHidden(true)
    }

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
                StrandIcon.calendar.image.font(StrandFont.glyph(.chevron))
                Text(verbatim: title).lineLimit(1).truncationMode(.tail)
            }
            .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        } else {
            Text("no event on your calendar")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
    }

    private func chart(_ hours: [Double?]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let n = max(hours.count, 1)
            let gap = max(2.0, (w - Self.barWidth * CGFloat(n)) / CGFloat(max(n - 1, 1)))
            ZStack(alignment: .bottomLeading) {
                // Floor line
                Rectangle()
                    .fill(theme.hairlineStrong)
                    .frame(height: 1.2)
                    .offset(y: 0)
                calmReferenceLine
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(0..<n), id: \.self) { h in
                        let v = h < hours.count ? hours[h] : nil
                        RoundedRectangle(cornerRadius: 2, style: .continuous) // token-exempt: geometría de dato
                            .fill(barFill(v))
                            .frame(width: Self.barWidth, height: barHeight(v), alignment: .bottom)
                            .opacity(barOpacity(v, h: h))
                            .recGrow(index: h)
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

    /// Low band at 0.55 opacity; gaps use hairline fill at full opacity; others full.
    private func barFill(_ v: Double?) -> Color {
        guard let v else { return theme.hairline }
        return StressBand(score: v).dataColor(theme)
    }

    private func barOpacity(_ v: Double?, h: Int) -> Double {
        let base: Double
        if let v {
            // Low band at 0.55 (mock); other bands full. Switch avoids needing Equatable.
            switch StressBand(score: v) {
            case .low: base = 0.55
            case .medium, .high: base = 1.0
            }
        } else {
            base = 1.0
        }
        if isDragging && scrubHour != h { return base * 0.3 }
        return base
    }

    /// Dotted «your usual calm» at activatedFloor (1.0 of 0–3), label on the right. Uses `baseMark`.
    private var calmReferenceLine: some View {
        let frac = CGFloat(StressMoments.activatedFloor / 3.0)
        return VStack(alignment: .trailing, spacing: 2) {
            Text("your usual calm")
                .font(InstrumentoType.grotesk(9, weight: .medium))
                .foregroundStyle(theme.inkTertiary)
            DashedHLine()
                .stroke(theme.baseMark, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .offset(y: -frac * Self.barsHeight)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func cursor(w: CGFloat, n: Int) -> some View {
        if isDragging, let h = scrubHour, n > 0 {
            Rectangle().fill(theme.ink.opacity(0.55)) // token-exempt: alfa exacto del cursor
                .frame(width: 1.5, height: Self.barsHeight + 2)
                .offset(x: (CGFloat(h) + 0.5) / CGFloat(n) * w - 0.75, y: -1)
        }
    }

    private var axis: some View {
        HStack {
            Text(verbatim: "6 h")
            Spacer()
            Text(verbatim: "14 h")
            Spacer()
            Text(verbatim: "22 h")
        }
        .font(InstrumentoType.grotesk(9))
        .foregroundStyle(theme.inkTertiary)
    }

    private func barHeight(_ v: Double?) -> CGFloat {
        guard let v else { return 8 } // short stub for gaps — never a made-up height
        return Swift.max(10, CGFloat(Swift.min(1, v / 3)) * Self.barsHeight)
    }

    private func hourLabel(_ h: Int) -> String {
        startOfDay.addingTimeInterval(TimeInterval(h * 3600)).formatted(.dateTime.hour())
    }

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
                                        .font(StrandFont.glyph(.lead))
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
            .padding(CenitMetrics.screenPadding)
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

private struct DashedHLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
#endif
