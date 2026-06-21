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
                    StressBarsStrip(curve: map.curve, now: map.now, theme: theme)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Your highest point today was at \(time).")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
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

// MARK: - Supporting bars strip (the day's shape, not the protagonist) — FER-433

/// A small bar-per-reading strip of the day's 0–3 stress over the waking window, colored by band. It's
/// supporting context only — no peak dot, no event names; decorative for VoiceOver (the moments list and
/// headline carry the meaning).
private struct StressBarsStrip: View {
    let curve: [StressEngine.StressPoint]
    let now: Date
    let theme: InstrumentoTheme

    var body: some View {
        let dates = curve.map(\.date)
        let lo = dates.first ?? now
        let hiRaw = Swift.max(dates.last ?? now, now)
        let hi = hiRaw > lo ? hiRaw : lo.addingTimeInterval(3600)
        let span = hi.timeIntervalSince1970 - lo.timeIntervalSince1970
        return VStack(alignment: .leading, spacing: 4) {
            Canvas { ctx, size in
                let barW: CGFloat = 3
                let usableW = Swift.max(1, size.width - barW)
                for p in curve {
                    guard let s = p.stress else { continue }
                    let fx = (p.date.timeIntervalSince1970 - lo.timeIntervalSince1970) / span
                    let x = CGFloat(Swift.min(1, Swift.max(0, fx))) * usableW
                    let h = CGFloat(Swift.min(1, Swift.max(0, s / 3))) * (size.height - 1)
                    let rect = CGRect(x: x, y: size.height - h, width: barW, height: Swift.max(1, h))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(StressBand(score: s).dataColor(theme)))
                }
            }
            .frame(height: 44)
            HStack {
                Text(verbatim: lo.formatted(.dateTime.hour()))
                Spacer()
                Text("now")
            }
            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .accessibilityHidden(true)
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
#endif
