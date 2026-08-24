#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// StressDayMapView.swift — the «mapa del día» block for the Detalle de Estrés (FER-377 · FER-860 ·
// FER-101 · TND-11).
//
// CAPA VISUAL en vidrio Liquid: el contenido vive en la tarjeta de sección de la familia
// (`liquidTarjetaSeccion`) bajo la `LiquidFranjaSeccion` del padre. Titular respuesta-primero,
// barras por hora con `LiquidBarrasHora` (el port del sistema de la vieja `StressBarsStrip` —
// huecos = muñón corto, nunca interpolados), momentos rankeados con eventos del calendario, y una
// nota que explica los huecos. Driven by `CalendarDayMap` — logic and EventKit UNCHANGED.
//
// La palabra y el calor de cada banda salen de la escalera ÚNICA de la pantalla
// (`StressDetailScreen.palabraEstres` / `.tonoEstres`) — nunca una segunda copia de los cortes.

struct StressDayMapBlock: View {
    @ObservedObject var model: CalendarDayMap
    /// Retenido por compatibilidad de firma — la capa Liquid ya no lo referencia. (FER-162)
    var theme: InstrumentoTheme = .base
    /// El calor del nivel de hoy, pasado por la pantalla padre (la rampa de la escalera única).
    var tono: Color = LiquidColor.tinta500
    @State private var showPicker = false
    /// La hora bajo el dedo en la tira de barras (`LiquidBarrasHora` la escribe y la limpia).
    @State private var scrubHora: Int? = nil

    var body: some View {
        content
            .task { await model.refresh() }
            .sheet(isPresented: $showPicker) {
                CalendarPickerSheet(model: model, isPresented: $showPicker)
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
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Image(systemName: "calendar.badge.clock")
                .font(LiquidType.infoGlifoTitular)
                .foregroundStyle(LiquidColor.tinta500)
            Text("Cross today's stress curve with your calendar to see what your most activated moments coincided with. Everything stays on your iPhone.")
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
            LiquidGlassButton(String(localized: "Connect my calendar"), variant: .glass) {
                Task { await model.requestAccess() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            Text("Calendar access is off. Turn it on in Settings › Privacy & Security › Calendars › Cénit to see this cross-reference.")
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.atencionTexto)
                .fixedSize(horizontal: false, vertical: true)
            LiquidVerMas(title: String(localized: "Open Settings"),
                         tone: LiquidColor.tinta700) { model.openSettings() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var restrictedView: some View {
        Text("Your calendar isn't available on this device because of a system restriction.")
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta700)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chooseView: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text("Choose which calendars to cross with your stress. You'll only see the ones you pick; nothing is shared.")
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
            LiquidGlassButton(String(localized: "Choose calendars"), variant: .glass) {
                showPicker = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingView: some View {
        Text("Crossing your day…")
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, LiquidSpace.s600)
    }

    // MARK: - Ready — «Momentos primero» en la tarjeta de la familia (FER-433 · FER-101)

    @ViewBuilder private func ready(_ map: CalendarDayMap.DayMap) -> some View {
        let hasReadings = map.curve.contains { $0.stress != nil }
        let hasEvents = !map.timed.isEmpty
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            if map.referenceMissing {
                Text("I'm still learning your rhythm: I need a few days of waking readings to mark your peaks. Your events are already here.")
                    .font(LiquidType.cuerpo)
                    .lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasReadings && !hasEvents {
                Text("No events today and no stress readings yet: your curve fills in as more readings sync.")
                    .font(LiquidType.cuerpo)
                    .lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                headline(map.coincidence)
                if hasReadings {
                    barrasHora(map)
                }
                momentsList(map.moments)
                if hasReadings {
                    LiquidNotaLine(String(localized: "The grey gaps are hours with no waking reading, never a made-up value."))
                }
            }
            if !map.allDay.isEmpty { allDayRow(map.allDay) }
            calendarsFooter(map.selectedNames)
        }
        .liquidTarjetaSeccion()
    }

    // MARK: Headline — the answer (peak + its event + over-calm)

    @ViewBuilder private func headline(_ c: StressDayMap.Coincidence?) -> some View {
        if let c {
            let time = c.peakDate.formatted(.dateTime.hour().minute())
            let overCalm = c.peakStress - StressMoments.activatedFloor
            VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                if let ev = c.event {
                    let clean = EventTitleCleaner.clean(ev.title)
                    // Reuses the existing coincidence copy keys (FER-433); clean title for display.
                    Text("Your highest point today, \(time), fell within “\(clean)”.")
                        .font(LiquidType.tituloGemela)
                        .foregroundStyle(LiquidColor.tinta900)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your highest point today was at \(time)")
                        .font(LiquidType.tituloGemela)
                        .foregroundStyle(LiquidColor.tinta900)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("no event on your calendar")
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if overCalm >= 0.1 {
                    Text("+\(magFmt(overCalm)) over your usual calm.")
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(StressDetailScreen.tonoEstres(c.peakStress))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Barras por hora — `LiquidBarrasHora` (la pieza del sistema, port de la vieja tira)

    /// Mean 0–3 stress per civil hour, midnight → the current hour (`nil` = no waking reading
    /// that hour). La agregación es la MISMA de la vieja `StressBarsStrip` — solo cambió la piel.
    private func barrasHora(_ map: CalendarDayMap.DayMap) -> some View {
        let cal = Calendar.current
        let nowHour = cal.component(.hour, from: map.now)
        let startOfDay = cal.startOfDay(for: map.now)
        var sums = [Double](repeating: 0, count: 24)
        var counts = [Int](repeating: 0, count: 24)
        for p in map.curve {
            guard let s = p.stress else { continue }
            let h = cal.component(.hour, from: p.date)
            guard (0..<24).contains(h) else { continue }
            sums[h] += s; counts[h] += 1
        }
        let horas: [LiquidBarrasHora.Hora] = (0...max(0, nowHour)).map { h in
            .init(id: h,
                  valor: counts[h] > 0 ? sums[h] / Double(counts[h]) : nil,
                  etiqueta: Self.horaEtiqueta(h, startOfDay: startOfDay))
        }
        return LiquidBarrasHora(
            horas: horas,
            tono: tono,
            referencia: StressMoments.activatedFloor,
            referenciaEtiqueta: String(localized: "your usual calm"),
            dominio: 0...3,
            seleccion: $scrubHora,
            formatoChip: { hora in
                guard let v = hora.valor else { return String(localized: "no reading") }
                return "\(String(format: "%.1f", v)) · \(StressDetailScreen.palabraEstres(v))"
            },
            a11yLabel: String(localized: "Stress through the day"),
            a11yValue: "")
    }

    /// «14:00» — la etiqueta de una hora civil, con el reloj del sistema.
    private static func horaEtiqueta(_ h: Int, startOfDay: Date) -> String {
        startOfDay.addingTimeInterval(TimeInterval(h * 3600)).formatted(.dateTime.hour())
    }

    // MARK: Moments — ranked list (time + event + band word), capilares between rows

    @ViewBuilder private func momentsList(_ m: StressMoments.DayMoments) -> some View {
        let rows: [StressMoments.Moment] = m.activated + (m.calmest.map { [$0] } ?? [])
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.date) { i, mo in
                    if i > 0 {
                        LiquidCapilar(eje: .horizontal)
                    }
                    momentRow(mo)
                }
            }
        }
    }

    private func momentRow(_ mo: StressMoments.Moment) -> some View {
        let time = mo.date.formatted(.dateTime.hour().minute())
        let cleanTitle = mo.event.map { EventTitleCleaner.clean($0.title) }
        return HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
            Text(verbatim: time)
                .font(LiquidType.valorS)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(width: 38, alignment: .leading)
                .monospacedDigit()
            if let cleanTitle {
                Text(verbatim: cleanTitle)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("no event on your calendar")
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
                    .lineLimit(1)
            }
            Spacer(minLength: LiquidSpace.s200)
            Text(verbatim: StressDetailScreen.palabraEstres(mo.stress))
                .font(LiquidType.tituloFila)
                .foregroundStyle(StressDetailScreen.tonoEstres(mo.stress))
        }
        .padding(.vertical, LiquidSpace.s200)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(momentA11yLabel(mo, time: time))
    }

    private func momentA11yLabel(_ mo: StressMoments.Moment, time: String) -> Text {
        var label = Text(verbatim: time)
        if let ev = mo.event { label = label + Text(verbatim: ", \(ev.title)") }
        return label + Text(verbatim: ", ") + Text(verbatim: StressDetailScreen.palabraEstres(mo.stress))
    }

    private func magFmt(_ v: Double) -> String { String(format: "%.1f", v) }

    private func allDayRow(_ events: [StressDayMap.DayEvent]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text("All day").liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: events.map { EventTitleCleaner.clean($0.title) }.joined(separator: " · "))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, LiquidSpace.s050)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("All day: \(events.map(\.title).joined(separator: ", ")). Not matched to a moment."))
    }

    private func calendarsFooter(_ names: [String]) -> some View {
        Button { showPicker = true } label: {
            HStack(spacing: LiquidSpace.s150) {
                StrandIcon.calendar.image
                Text("Calendars: \(names.isEmpty ? String(localized: "none") : names.joined(separator: ", "))")
                Text("· change").underline()
            }
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500)
        }
        .buttonStyle(.plain)
        .padding(.top, LiquidSpace.s050)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Calendar picker (en vidrio)

private struct CalendarPickerSheet: View {
    @ObservedObject var model: CalendarDayMap
    @Binding var isPresented: Bool
    @State private var selected: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    Text("Choose calendars")
                        .font(LiquidType.displayS)
                        .tracking(LiquidType.displaySTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                    Text("We'll only cross the ones you pick.")
                        .font(LiquidType.cuerpo)
                        .foregroundStyle(LiquidColor.tinta700)
                }
                if model.calendars.isEmpty {
                    Text("There are no calendars on this iPhone yet.")
                        .font(LiquidType.cuerpo)
                        .foregroundStyle(LiquidColor.tinta500)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.calendars) { cal in
                            Button { toggle(cal.id) } label: {
                                HStack(spacing: LiquidSpace.s250) {
                                    Image(systemName: selected.contains(cal.id) ? "checkmark.circle.fill" : "circle")
                                        .font(LiquidType.infoGlifo)
                                        .foregroundStyle(selected.contains(cal.id)
                                                         ? LiquidColor.verdePrimario
                                                         : LiquidColor.tinta500)
                                    Text(verbatim: cal.label)
                                        .font(LiquidType.cuerpo)
                                        .foregroundStyle(LiquidColor.tinta900)
                                    Spacer(minLength: LiquidSpace.s200)
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                LiquidGlassButton(String(localized: "Done"), variant: .primary, expands: true) {
                    Task { await model.updateSelection(selected); isPresented = false }
                }
                .disabled(selected.isEmpty)
            }
            .padding(LiquidSpace.s550)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { LiquidSheetFondo(tone: LiquidColor.tinta500).ignoresSafeArea() }
        .presentationBackground { LiquidSheetFondo(tone: LiquidColor.tinta500) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        .onAppear { selected = model.selectedIDs }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
#endif
