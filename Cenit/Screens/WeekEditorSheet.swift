#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - «Tu semana · editor» (FER-138)
//
// The fast, in-place way to rotate a day's routine without leaving the landing for the full «Tu Plan»
// editor (`WeeklyPlanEditorView`, still reachable from «Editar rutinas y semana ›»). Tapping a future/
// today row cycles Descanso → routine 1 → routine 2 → … → Descanso through the routines CURRENTLY in
// the split — «las rutinas del split» (spec), not the whole library, same scope as the week strip
// itself — and writes it to `WeeklySplit` the instant you tap, via the caller's binding, so the landing
// behind the sheet is never stale even if it's dismissed by a swipe instead of «Listo». Past days don't
// rotate — a toast says so instead of a silent no-op.
//
// «Instrumento diurno»: an editor has no measured datum, so it's ink on paper — the only color is the
// green «Listo» that closes it, the same closing CTA every other sheet in this section uses.
struct WeekEditorSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    /// El tema vivo, pasado explícito: no cruza el límite de `.sheet` (FER-162).
    let theme: InstrumentoTheme

    /// weekday → routineId (Calendar convention, 1 = Sun … 7 = Sat). Mutado EN VIVO al rotar un día, así
    /// que la landing detrás de la hoja nunca queda desfasada.
    @Binding var split: [Int: String]
    let routines: [Routine]
    let orderedWeekdays: [Int]
    let todayWeekday: Int
    /// Días (de esta semana) que ya tienen una sesión completada — la MISMA fuente que la tira de la
    /// landing (`trainedThisWeek`), para que «hecha» nunca contradiga el punto de arriba.
    let doneWeekdays: Set<Int>
    /// La letra de cada día, inyectada por la landing (`EntrenarView.weekdayLetter`) — una sola
    /// definición para la tira `WeekTokens` y esta hoja, así no derivan por separado.
    let dayLetter: (Int) -> String

    @State private var saveError = false
    @State private var lockedToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your week · editor").entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(orderedWeekdays, id: \.self) { wd in
                    dayRow(wd)
                    if wd != orderedWeekdays.last {
                        Rectangle().fill(theme.hairline).frame(height: 0.5)
                    }
                }
            }
            .padding(.top, LiquidSpace.s200)
            Text("Tap a day to rotate its routine. The routines are the ones you already have; days you've already trained don't change.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, LiquidSpace.s300)
            HStack {
                Spacer(minLength: 0)
                StrandCTAButton("Ready", tint: theme.positiveText, fillsWidth: false) { dismiss() }
            }
            .padding(.top, LiquidSpace.s300)
        }
        .padding(LiquidSpace.s600)
        // FER-200 (Anillo 2, épico FER-195): fondo de vidrio El Eje — se CONSERVA el chrome actual
        // (kicker + filas + CTA «Listo» abajo). Esta hoja no tiene botón de salida en cabecera
        // (cierra con «Ready» / swipe); meter `EntrenarHojaCabecera` AÑADIRÍA un control (REGLA
        // SUPREMA) — se flagea y solo se tiñe el fondo.
        .entrenarHojaFondo(tono: .neutro)
        .saveErrorToast(isPresented: $saveError)
        .overlay(alignment: .bottom) {
            if lockedToast {
                Text("Days already trained can't be edited")
                    .font(StrandFont.caption).fontWeight(.medium)
                    .foregroundStyle(theme.paper)
                    .padding(.horizontal, LiquidSpace.s300).padding(.vertical, LiquidSpace.s200)
                    .background(theme.ink, in: Capsule())
                    .padding(.bottom, CenitMetrics.sectionGap)
                    .transition(LiquidMotion.risingFadeTransition)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        lockedToast = false
                    }
            }
        }
        .animation(LiquidMotion.fundido, value: lockedToast)
        .instrumentoTheme(theme)
        .preferredColorScheme(.light)
    }

    // MARK: - Rows

    private var routinesById: [String: Routine] {
        Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func isPast(_ wd: Int) -> Bool {
        guard let idx = orderedWeekdays.firstIndex(of: wd),
              let todayIdx = orderedWeekdays.firstIndex(of: todayWeekday) else { return false }
        return idx < todayIdx
    }

    @ViewBuilder
    private func dayRow(_ wd: Int) -> some View {
        let past = isPast(wd)
        let isToday = wd == todayWeekday
        let name = split[wd].flatMap { routinesById[$0]?.name }
        let done = doneWeekdays.contains(wd)
        Button {
            if past { showLockedToast() } else { rotate(wd) }
        } label: {
            HStack(spacing: LiquidSpace.s300) {
                Text(verbatim: dayLetter(wd))
                    .font(StrandFont.scaled(11, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(theme.inkTertiary)
                    .frame(width: 26, alignment: .leading)
                routineLabel(name: name, isToday: isToday)
                Spacer(minLength: LiquidSpace.s200)
                if past {
                    if done { Text("Already done").font(StrandFont.caption).foregroundStyle(theme.inkDim) }
                } else {
                    Text("Tap to rotate").font(StrandFont.caption).foregroundStyle(theme.inkDim)
                }
            }
            .frame(minHeight: EntrenarMetrics.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(wd: wd, name: name, isToday: isToday, past: past, done: done))
        // Ronda 2 (menor): un día pasado sin sesión no rota, y sin hint VoiceOver solo se entera al
        // tocar y ver el toast (que no se anuncia solo) — el hint lo dice de antemano.
        .accessibilityHint(past ? Text("Not editable") : Text(""))
    }

    private func routineLabel(name: String?, isToday: Bool) -> Text {
        let base = nameText(name)
            .font(StrandFont.scaled(13.5, weight: name != nil ? .semibold : .regular, relativeTo: .subheadline))
            .foregroundStyle(name != nil ? theme.ink : theme.inkTertiary)
        guard isToday else { return base }
        let todaySuffix = (Text(verbatim: " · ") + Text("today"))
            .font(StrandFont.scaled(13.5, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(theme.inkTertiary)
        return base + todaySuffix
    }

    /// User-authored routine name (verbatim) or the localized «Rest» fallback.
    private func nameText(_ name: String?) -> Text {
        name.map { Text(verbatim: $0) } ?? Text("Rest")
    }

    private func accessibilityLabel(wd: Int, name: String?, isToday: Bool, past: Bool, done: Bool) -> Text {
        var t = Text(verbatim: weekdayFullName(wd) + ", ") + nameText(name)
        if isToday { t = t + Text(verbatim: ", ") + Text("today") }
        if past {
            if done { t = t + Text(verbatim: ", ") + Text("Already done") }
        } else {
            t = t + Text(verbatim: ", ") + Text("Tap to rotate")
        }
        return t
    }

    // MARK: - Actions

    /// The rotation set: every routine CURRENTLY assigned somewhere in the split, weekday-ordered — the
    /// spec's «las rutinas del split», not the whole library.
    private var rotationOptions: [String] {
        var seen = Set<String>(); var order: [String] = []
        for wd in orderedWeekdays {
            guard let id = split[wd], seen.insert(id).inserted else { continue }
            order.append(id)
        }
        return order
    }

    private func rotate(_ wd: Int) {
        let options = rotationOptions
        guard !options.isEmpty else { return }   // no routines anywhere in the split yet — nothing to cycle to
        let cycle: [String?] = [nil] + options
        let currentIndex = cycle.firstIndex(of: split[wd]) ?? -1
        let next = cycle[(currentIndex + 1) % cycle.count]
        let previous = split[wd]
        split[wd] = next   // optimistic — the landing behind the sheet updates immediately
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; split[wd] = previous; return }
            do {
                if let next {
                    try await store.setRoutineSchedule(weekday: wd, routineId: next)
                } else {
                    try await store.clearRoutineSchedule(weekday: wd)
                }
            } catch {
                saveError = true
                split[wd] = previous
            }
        }
    }

    private func showLockedToast() {
        withAnimation(LiquidMotion.fundido) { lockedToast = true }
    }

    // MARK: - Weekday labels


    /// The full localized weekday name, for VoiceOver's composite label («martes, Pierna A, …»).
    private func weekdayFullName(_ wd: Int) -> String {
        Calendar.current.weekdaySymbols[(wd - 1) % 7]
    }
}
#endif
