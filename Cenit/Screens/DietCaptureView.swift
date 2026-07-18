#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import StrandAnalytics
import CenitStore
import UIKit       // UIApplication.openSettingsURLString (open Settings when notifications are denied)

/// Diet capture + daily tracker — the plan your nutritionist gave you, and how you follow it (FER-371/372).
///
/// «Instrumento diurno»: the **capture** panel has no measured datum, so it stays all-ink on warm
/// paper — the only color is `critical` on a parse error. Once a plan is active, the screen becomes the
/// **daily tracker** (FER-372): the day's adherence **%** is the one dominant numeral (the lone datum,
/// in `dataRecovery` green), with a 7-day sparkline and a tri-state checklist (Followed / Swapped /
/// Skipped) per meal. The star capture path is **bring-your-own-LLM**: copy a prompt, paste it into
/// your own AI with your plan (PDF/photo), and bring the `noop.diet.v1` file back. NOOP never calls the
/// network — the user runs the LLM step (`DietPlanImporter` from FER-370 validates the result).
struct DietCaptureView: View {

    @EnvironmentObject private var repo: Repository
    @Environment(\.instrumentoTheme) private var theme

    private enum Phase { case landing, capture, manual, confirm }

    /// Manual-capture form model (FER-403): a plan typed by hand instead of via BYO-LLM. Mirrors
    /// `noop.diet.v1` — a meal has a short name and ≥1 option (equivalent), each a list of foods.
    private struct ManualFood: Identifiable { let id = UUID(); var text = "" }
    private struct ManualOption: Identifiable { let id = UUID(); var foods: [ManualFood] = [ManualFood()] }
    private struct ManualMeal: Identifiable {
        let id = UUID(); var name = ""; var options: [ManualOption] = [ManualOption()]
        var days: Set<Int> = [1, 2, 3, 4, 5, 6, 7]   // ISO weekdays; all 7 = every day → diario (FER-431)
    }

    @State private var phase: Phase = .landing
    @State private var loaded = false
    @State private var activePlan: DietPlanRow?
    @State private var activeParsed: DietPlan?      // cached decode of activePlan's payload (off body)
    @State private var pasteText = ""
    @State private var pendingPlan: DietPlan?
    @State private var parseError: DietPlanParseError?
    @State private var copied = false
    @State private var showFileImporter = false

    // Daily tracker (FER-372): per-meal marks for the viewed day + its 7-day adherence trend.
    // Day navigation (FER-402): `selectedDay` is the day shown; `todayKey` caps the forward arrow so
    // you can't mark the future.
    @State private var todayStatuses: [String: DietMealStatus] = [:]
    @State private var todayOptions: [String: Int] = [:]   // mealId → chosen equivalent option (FER-401)
    @State private var adherence7d: [Double] = []
    @State private var heatDays: [RecoveryDay] = []   // last 90 days for the adherence heatmap (FER-410)
    // Meal reminders (FER-412): opt-in local notifications at each meal's suggested time.
    @State private var remindersOn = false
    @State private var reminderAuthDenied = false
    @State private var todayKey = ""
    @State private var selectedDay = ""
    // Manual capture (FER-403): the form being typed.
    @State private var manualPlanName = ""
    @State private var manualMeals: [ManualMeal] = [ManualMeal()]

    private let importer = DietPlanImporter()

    var body: some View {
        Group {
            switch phase {
            case .landing:
                if let plan = activePlan { scrolled { tracker(plan) } }
                else { emptyState }
            case .capture:
                scrolled { captureFlow }
            case .manual:
                scrolled { manualForm }
            case .confirm:
                if let plan = pendingPlan { scrolled { confirmStep(plan) } } else { emptyState }
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .navigationTitle("Diet")
        .task { await loadIfNeeded() }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "fork.knife",
            title: "You don't have a plan yet",
            message: "Capture the diet your nutritionist gave you and follow it day to day.",
            actionTitle: "Capture my plan",
            action: { startCapture() }
        )
    }

    // MARK: - Capture

    private var captureFlow: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            header("Capture plan", "Bring your nutritionist's plan")

            step(1, "Copy the prompt and paste it into your trusted AI, along with your plan (PDF or photo).") {
                QuietButton(copied ? "Copied" : "Copy prompt") { copyPrompt() }
            }

            step(2, "Bring back the file it gives you: paste it or upload it.") {
                VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                    pasteField
                    HStack(spacing: CenitMetrics.gap) {
                        QuietButton("Upload .json file") { showFileImporter = true }
                        QuietButton("Continue") { parse(text: pasteText) }
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let parseError { errorNote(parseError) }
                }
            }

            Button { startManual() } label: {
                Text("Capture by hand instead")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var pasteField: some View {
        TextEditor(text: $pasteText)
            .font(StrandFont.mono)
            .foregroundStyle(theme.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 96)
            .padding(CenitMetrics.cardPadding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if pasteText.isEmpty {
                    Text("Paste the result here…")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkTertiary)
                        .padding(CenitMetrics.cardPadding)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Paste your plan")
    }

    private func errorNote(_ error: DietPlanParseError) -> some View {
        HStack(alignment: .top, spacing: CenitMetrics.gap) {
            Image(systemName: "exclamationmark.triangle")
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(theme.critical)
                .accessibilityHidden(true)
            Text(message(for: error))
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Confirm

    private func confirmStep(_ plan: DietPlan) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            planHeader("Review your plan", name: plan.name)
            mealList(plan)
            QuietButton("Save plan") { save(plan) }
        }
    }

    // MARK: - Manual capture (FER-403)

    /// Type a plan by hand (no LLM): plan name + meals (short name + foods), with equivalent options.
    /// All-ink — there's no measured datum here, same as the BYO-LLM capture screen.
    private var manualForm: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            header("Diet · by hand", "Build your plan")

            VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                Text("Plan name").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                manualField($manualPlanName, "Plan name")
            }

            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("Meals").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ForEach($manualMeals) { meal in
                    manualMealCard(meal)
                }
                addRow("Add meal") { manualMeals.append(ManualMeal()) }
            }

            QuietButton("Save plan") { saveManual() }
                .disabled(!manualPlanIsValid)
        }
    }

    private func manualMealCard(_ meal: Binding<ManualMeal>) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            manualField(meal.name, "Short name")
            ForEach(meal.options) { option in
                manualOption(option, isEquivalent: option.wrappedValue.id != meal.wrappedValue.options.first?.id)
            }
            addRow("Equivalent option") { meal.wrappedValue.options.append(ManualOption()) }
            dayPicker(meal)
        }
        .padding(CenitMetrics.cardPadding)
        .overlay(
            RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 0.5)
        )
    }

    /// Weekday chips per meal (FER-431): all 7 selected = every day (diario); deselect any to make the
    /// plan weekly. ISO 1=Mon … 7=Sun. At least one day stays selected.
    private func dayPicker(_ meal: Binding<ManualMeal>) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text("Days").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            HStack(spacing: CenitMetrics.space1) {
                ForEach(1...7, id: \.self) { iso in
                    let on = meal.wrappedValue.days.contains(iso)
                    Button {
                        if on { if meal.wrappedValue.days.count > 1 { meal.wrappedValue.days.remove(iso) } }
                        else { meal.wrappedValue.days.insert(iso) }
                    } label: {
                        Text(verbatim: Self.weekdayInitial(iso))
                            .font(StrandFont.caption)
                            .foregroundStyle(on ? theme.paper : theme.inkSecondary)
                            .frame(width: 30, height: 30)
                            .background(on ? theme.ink : Color.clear, in: Circle())
                            .overlay(Circle().stroke(on ? theme.ink : theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: Self.weekdayName(iso)))
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
    }

    /// Locale-aware one-letter weekday for an ISO day (1=Mon…7=Sun). Uses the OS symbols (Sunday-indexed).
    private static func weekdayInitial(_ iso: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[(DietWeekday.calendarWeekday(forISOWeekday: iso) - 1) % symbols.count]
    }
    private static func weekdayName(_ iso: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(DietWeekday.calendarWeekday(forISOWeekday: iso) - 1) % symbols.count]
    }

    private func manualOption(_ option: Binding<ManualOption>, isEquivalent: Bool) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            if isEquivalent {
                Text("or equivalent").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            ForEach(option.foods) { food in
                HStack(spacing: CenitMetrics.space2) {
                    manualField(food.text, "Food")
                    Button {
                        option.wrappedValue.foods.removeAll { $0.id == food.wrappedValue.id }
                    } label: {
                        StrandIcon.close.image.font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove food")
                }
            }
            addRow("Add food") { option.wrappedValue.foods.append(ManualFood()) }
        }
    }

    private func manualField(_ text: Binding<String>, _ placeholder: LocalizedStringKey) -> some View {
        TextField(placeholder, text: text)
            .font(StrandFont.body)
            .foregroundStyle(theme.ink)
            .padding(.horizontal, CenitMetrics.gap)
            .padding(.vertical, CenitMetrics.space2)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1)
            )
    }

    private func addRow(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CenitMetrics.space2) {
                StrandIcon.add.image
                Text(title)
            }
            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
        }
        .buttonStyle(.plain)
    }

    /// Savable once at least one meal has at least one option with a non-empty food.
    private var manualPlanIsValid: Bool {
        manualMeals.contains { meal in
            meal.options.contains { option in
                option.foods.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        }
    }

    // MARK: - Daily tracker (FER-372)

    private func tracker(_ row: DietPlanRow) -> some View {
        // The meals planned for the VIEWED day (semanal filters by weekday; diario → all). The % counts
        // only those, so stray marks from a day a meal no longer applies can't skew it (FER-431).
        let dayMeals = mealsForDay(selectedDay)
        let planned = dayMeals.count
        let dayIds = Set(dayMeals.map(\.id))
        let dayStatuses = todayStatuses.filter { dayIds.contains($0.key) }
        let marked = dayStatuses.count
        let pct = (marked == 0 || planned == 0) ? nil
            : DietAdherence.dayPercent(statuses: Array(dayStatuses.values), plannedMeals: planned)
        return VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            dayNav
            adherenceHero(pct: pct, marked: marked, planned: planned, restDay: planned == 0)
            if planned > 0 { mealTracker(dayMeals) } else { restDayState }
            if let plan = activeParsed { indications(plan) }
            adherenceCalendar
            remindersRow
            QuietButton("Replace plan") { startCapture() }
        }
    }

    /// The meals planned for a day key — filtered by its weekday for `semanal` plans (FER-431); a `diario`
    /// plan returns all meals every day.
    private func mealsForDay(_ dayKey: String) -> [DietMeal] {
        guard let plan = activeParsed else { return [] }
        guard let date = Self.dayKeyParser.date(from: dayKey) else { return plan.meals }
        let iso = DietWeekday.isoWeekday(forCalendarWeekday: Calendar.current.component(.weekday, from: date))
        return plan.meals(forISOWeekday: iso)
    }

    /// Shown when a `semanal` plan has no meals for the viewed day — an honest rest day; the % stays «—».
    private var restDayState: some View {
        VStack(alignment: .center, spacing: CenitMetrics.space2) {
            StrandIcon.sleep.image.font(StrandFont.title1)
                .foregroundStyle(theme.hairlineStrong).accessibilityHidden(true)
            Text("Rest day: your plan has no meals today. Come back tomorrow or use ‹ ›.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CenitMetrics.gap)
    }

    /// The nutritionist's plan-level guidance, shown only when the plan actually carries it (FER-411):
    /// rules verbatim, plus any declared daily targets as a quiet reference — never invented, never counted.
    @ViewBuilder
    private func indications(_ plan: DietPlan) -> some View {
        let rules = (plan.rules ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let targets = plan.dailyTargets ?? [:]
        if !rules.isEmpty || !targets.isEmpty {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("Indications").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ForEach(rules, id: \.self) { rule in
                    HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                        Text(verbatim: "•").foregroundStyle(theme.inkTertiary)
                        Text(verbatim: rule).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(StrandFont.subhead)
                }
                if !targets.isEmpty { targetsReference(targets) }
            }
        }
    }

    /// Declared daily targets as reference chips — the keys are whatever the plan declared (the format
    /// doesn't fix them), so we show them verbatim and never map to units or count.
    private func targetsReference(_ targets: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text("Plan target · reference").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .padding(.top, CenitMetrics.space1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CenitMetrics.space2) {
                    ForEach(targets.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        Text(verbatim: "\(key.replacingOccurrences(of: "_", with: " ")) · \(value.formatted())")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                            .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.space1)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                    }
                }
            }
            Text("Only what your plan declared. NOOP doesn't count calories.")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
    }

    /// A 90-day adherence heatmap (FER-410): each cell a day, tinted green by its apego %, faint when
    /// untracked. Reuses `YearHeatStrip`; tapping a day jumps the tracker to it.
    private var adherenceCalendar: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text("Adherence · history").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if heatDays.contains(where: { $0.score != nil }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    YearHeatStrip(
                        days: heatDays,
                        cellSize: 13,
                        spacing: 3,
                        showsScrub: false,
                        tint: { theme.dataRecovery.opacity(0.20 + 0.80 * Swift.min(1, Swift.max(0, $0) / 100)) }, // token-exempt: rampa de intensidad del heatmap
                        emptyFill: theme.hairline,
                        emptyStroke: theme.hairlineStrong,
                        labelColor: theme.inkTertiary,
                        onSelect: { goToDay(Repository.localDayKey($0.date)) },
                        selectionColor: theme.ink,
                        valueFormat: { "\(Int($0.rounded()))%" },
                        valueWord: "adherence"
                    )
                }
                Text("Each cell is a day · greener = higher adherence. Tap a day to view it.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            } else {
                Text("Your daily adherence will appear here as you mark your meals.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    /// Build the trailing-90-day adherence heatmap (today-relative, contiguous so gaps show as faint
    /// untracked days). Score = the day's apego %, nil when there's no record.
    private static func buildHeatDays(_ byDay: [String: Double], todayKey: String) -> [RecoveryDay] {
        guard let today = dayKeyParser.date(from: todayKey) else { return [] }
        return (0..<90).reversed().compactMap { off -> RecoveryDay? in
            guard let date = Calendar.current.date(byAdding: .day, value: -off, to: today) else { return nil }
            let key = Repository.localDayKey(date)
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: byDay[key])
        }
    }

    /// Opt-in local meal reminders (FER-412). Off by default; on schedules one daily notification per
    /// meal that declares a time. The switch tints with the data hue (the app accent); everything else
    /// is ink. Disabled when the plan declares no times; shows an «Open Settings» path when denied.
    @ViewBuilder
    private var remindersRow: some View {
        let slots = activeParsed.map { DietReminderScheduler.reminderSlots($0.meals) } ?? []
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            HStack(alignment: .top, spacing: CenitMetrics.gap) {
                Image(systemName: "bell")
                    .font(StrandFont.body)
                    .foregroundStyle(theme.inkSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                    Text("Meal reminders").font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(reminderSubtitle(hasTimes: !slots.isEmpty, count: slots.count))
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CenitMetrics.gap)
                Toggle("", isOn: Binding(get: { remindersOn }, set: { setReminders($0) }))
                    .labelsHidden()
                    .tint(theme.dataRecovery)
                    .disabled(slots.isEmpty)
                    .accessibilityLabel("Meal reminders")
            }
            if remindersOn, !slots.isEmpty {
                VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        HStack {
                            Text(verbatim: slot.title).font(StrandFont.footnote).foregroundStyle(theme.ink)
                            Spacer()
                            Text(verbatim: String(format: "%02d:%02d", slot.hour, slot.minute))
                                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).monospacedDigit()
                        }
                    }
                }
            }
            if reminderAuthDenied {
                Button { openSystemSettings() } label: {
                    Text("Open Settings").font(StrandFont.subhead).foregroundStyle(theme.dataRecovery)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reminderSubtitle(hasTimes: Bool, count: Int) -> LocalizedStringKey {
        if !hasTimes { return "Your plan has no suggested times." }
        if reminderAuthDenied { return "Notifications are turned off." }
        if remindersOn { return "On · \(count) meals with a time." }
        return "We'll remind you at each one's suggested time."
    }

    /// Reflect the saved opt-in + current authorization, and rebuild the schedule from the active plan.
    private func syncReminderState() async {
        let enabled = DietReminderScheduler.isEnabled
        let status = await DietReminderScheduler.authorizationStatus()
        remindersOn = enabled && status == .authorized
        reminderAuthDenied = enabled && status == .denied
        if remindersOn, let meals = activeParsed?.meals { await DietReminderScheduler.reschedule(meals) }
    }

    private func setReminders(_ on: Bool) {
        if on {
            Task {
                let granted = await DietReminderScheduler.requestAuthorization()
                DietReminderScheduler.isEnabled = granted
                remindersOn = granted
                reminderAuthDenied = !granted
                if granted, let meals = activeParsed?.meals { await DietReminderScheduler.reschedule(meals) }
            }
        } else {
            DietReminderScheduler.isEnabled = false
            remindersOn = false
            reminderAuthDenied = false
            Task { await DietReminderScheduler.cancelAll() }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// Day navigation (FER-402): ‹ date › steps one day at a time; the forward arrow is disabled on
    /// today (no future to mark). The date and arrows stay in ink — color lives only in the apego %.
    private var dayNav: some View {
        let atToday = selectedDay >= todayKey
        return HStack {
            Button { goToDay(Self.shiftDay(selectedDay, by: -1)) } label: {
                StrandIcon.back.image.font(StrandFont.headline).foregroundStyle(theme.ink)
            }
            .accessibilityLabel("Previous day")
            Spacer()
            Text(dayLabel(selectedDay)).font(StrandFont.subhead).foregroundStyle(theme.ink)
            Spacer()
            Button { goToDay(Self.shiftDay(selectedDay, by: 1)) } label: {
                StrandIcon.disclosure.image.font(StrandFont.headline)
                    .foregroundStyle(atToday ? theme.hairlineStrong : theme.ink)
            }
            .disabled(atToday)
            .accessibilityLabel("Next day")
        }
    }

    /// The day's adherence % — the one dominant numeral and the lone datum, so it carries the only
    /// saturated color. Until a meal is marked it shows «—» in ink (pending isn't a punitive 0%).
    private func adherenceHero(pct: Int?, marked: Int, planned: Int, restDay: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                Text(selectedDay == todayKey ? "Diet · today" : "Diet").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space1) {
                    if let pct {
                        Text("\(pct)").instrumentoHero(62).foregroundStyle(theme.dataRecovery)
                        Text(verbatim: "%").font(StrandFont.title1).foregroundStyle(theme.dataRecovery)
                    } else {
                        Text(verbatim: "—").instrumentoHero(62).foregroundStyle(theme.ink)
                    }
                }
                Group {
                    if restDay {
                        Text("Rest day · no meals planned")
                    } else if pct != nil {
                        Text("adherence · \(marked) of \(planned) meals")
                    } else {
                        Text("Mark your meals · 0 of \(planned)")
                    }
                }
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            if adherence7d.count >= 2 {
                Sparkline(values: adherence7d,
                          gradient: Gradient(colors: [theme.dataRecovery]),
                          range: 0...100, showsArea: false, showsScrub: false)
                    .frame(height: 34)
                    .accessibilityLabel("7-day adherence trend")
                Text("Adherence · 7 days").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    private func mealTracker(_ meals: [DietMeal]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today's meals").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, CenitMetrics.gap)
            ForEach(Array(meals.enumerated()), id: \.offset) { index, meal in
                mealTrackRow(meal)
                if index < meals.count - 1 {
                    Rectangle().fill(theme.hairline).frame(height: 0.5)
                }
            }
        }
    }

    private func mealTrackRow(_ meal: DietMeal) -> some View {
        let status = todayStatuses[meal.id]
        return VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            nameText(meal.name, fallback: "Meal").font(StrandFont.body).foregroundStyle(theme.ink)
            if let note = meal.notes?.trimmingCharacters(in: .whitespaces), !note.isEmpty {
                (Text("Note: ") + Text(verbatim: note))
                    .font(StrandFont.footnote).italic().foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if meal.options.count > 1 {
                optionPicker(meal, status: status)
                if status == .sustitui {
                    swappedEquivalentsHint(meal)
                }
            } else {
                if let foods = meal.options.first?.foods, !foods.isEmpty {
                    Text(foods.joined(separator: " · "))
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: CenitMetrics.space2) {
                    statusChip("Followed", meal.id, .cumpli, status)
                    statusChip("Swapped",  meal.id, .sustitui, status)
                    statusChip("Skipped",  meal.id, .salte, status)
                }
            }
        }
        .padding(.vertical, CenitMetrics.gap)
    }

    /// Hint chip for multi-option meals marked Swapped — surfaces the second equivalent quietly.
    @ViewBuilder
    private func swappedEquivalentsHint(_ meal: DietMeal) -> some View {
        if meal.options.count > 1 {
            let foods = meal.options[1].foods.joined(separator: " + ")
            VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                Text(verbatim: "Option 2 · \(foods)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.dataHrv)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.tint(theme.dataHrv), in: Capsule())
                Text("or see equivalents")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// A meal with ≥2 equivalent options: pick which one you ate (= cumplí, recording which), or mark
    /// «Other» (an off-plan equivalent = sustituí) / «Skipped». All options stay visible, so the full
    /// plan is always consultable (FER-401). Color stays out — the apego % is the only datum.
    private func optionPicker(_ meal: DietMeal, status: DietMealStatus?) -> some View {
        let chosen = todayOptions[meal.id]
        return VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text("pick what you ate").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            ForEach(Array(meal.options.enumerated()), id: \.offset) { index, option in
                let sel = status == .cumpli && chosen == index
                Button { mark(meal.id, .cumpli, option: index) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.gap) {
                        Image(systemName: sel ? "largecircle.fill.circle" : "circle")
                            .font(StrandFont.subhead)
                            .foregroundStyle(sel ? theme.ink : theme.hairlineStrong)
                        Text(verbatim: option.foods.joined(separator: " · "))
                            .font(StrandFont.subhead).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? [.isSelected] : [])
            }
            HStack(spacing: CenitMetrics.space2) {
                statusChip("Other",   meal.id, .sustitui, status)
                statusChip("Skipped", meal.id, .salte, status)
            }
        }
    }

    /// One tri-state chip — ink stays the language; the selected one inverts to an ink fill. No color
    /// here: the apego % is the only datum. Mirrors the journal's `answerPill`.
    private func statusChip(_ title: LocalizedStringKey, _ mealId: String,
                            _ value: DietMealStatus, _ current: DietMealStatus?) -> some View {
        let sel = current == value
        return Button { mark(mealId, value) } label: {
            Text(title).font(StrandFont.caption)
                .foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(sel ? theme.ink : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(sel ? theme.ink : theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sel ? [.isSelected] : [])
    }

    // MARK: - Shared pieces

    private func mealList(_ plan: DietPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.meals.enumerated()), id: \.offset) { index, meal in
                VStack(alignment: .leading, spacing: 3) {
                    nameText(meal.name, fallback: "Meal")
                        .font(StrandFont.body).foregroundStyle(theme.ink)
                    ForEach(Array(meal.options.enumerated()), id: \.offset) { optIndex, option in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if optIndex > 0 {
                                Text("or").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                            }
                            Text(option.foods.joined(separator: " · "))
                                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, CenitMetrics.gap)
                if index < plan.meals.count - 1 {
                    Rectangle().fill(theme.hairline).frame(height: 1)
                }
            }
        }
    }

    private func header(_ overline: LocalizedStringKey, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(title).font(StrandFont.title1).foregroundStyle(theme.ink)
        }
    }

    /// Header whose title is **user data** (the plan's own name) — rendered verbatim, never localized.
    private func planHeader(_ overline: LocalizedStringKey, name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            nameText(name, fallback: "Your plan").font(StrandFont.title1).foregroundStyle(theme.ink)
        }
    }

    /// Verbatim user content, with a localized fallback when the field is empty. Plan/meal names are the
    /// nutritionist's words — never run them through the String Catalog.
    private func nameText(_ value: String, fallback: LocalizedStringKey) -> Text {
        value.isEmpty ? Text(fallback) : Text(verbatim: value)
    }

    private func step<Action: View>(_ n: Int, _ text: LocalizedStringKey,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: CenitMetrics.gap) {
            Text("\(n)")
                .font(StrandFont.headline).monospacedDigit()
                .foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text(text)
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }

    private func scrolled<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(CenitMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func loadIfNeeded() async {
        guard !loaded else { return }
        todayKey = Repository.localDayKey(Date())
        selectedDay = todayKey
        activePlan = await repo.activeDietPlan()
        activeParsed = activePlan.flatMap { try? importer.parse(text: $0.payloadJSON) }
        if activePlan != nil { await loadTrackerData() }
        await syncReminderState()
        loaded = true
    }

    /// Load the viewed day's per-meal marks + the 7-day adherence trend ending on that day.
    private func loadTrackerData() async {
        let marks = await repo.dietAdherence(day: selectedDay)
        todayStatuses = Dictionary(marks.map { ($0.mealId, $0.status) }, uniquingKeysWith: { first, _ in first })
        todayOptions = Dictionary(marks.compactMap { row in row.optionIndex.map { (row.mealId, $0) } },
                                  uniquingKeysWith: { first, _ in first })
        adherence7d = await repo.dietAdherenceSeries(from: Self.weekAgoKey(of: selectedDay), to: selectedDay)
        await loadHeat()
    }

    /// Load the trailing-90-day adherence heatmap (today-relative, independent of the viewed day).
    private func loadHeat() async {
        let byDay = await repo.dietAdherenceByDay(from: Self.shiftDay(todayKey, by: -89), to: todayKey)
        heatDays = Self.buildHeatDays(byDay, todayKey: todayKey)
    }

    /// Jump to a day (never past today) and reload its marks + trend.
    private func goToDay(_ key: String) {
        guard key <= todayKey else { return }
        selectedDay = key
        Task { await loadTrackerData() }
    }

    /// Mark one meal's status on the viewed day: optimistic local update (the hero % recomputes at
    /// once), then persist + refresh the trend off the render path.
    private func mark(_ mealId: String, _ status: DietMealStatus, option: Int? = nil) {
        todayStatuses[mealId] = status
        todayOptions[mealId] = option   // nil removes the key (sustitui/salte record no option)
        let day = selectedDay
        let planned = mealsForDay(day).count   // the day's planned meals (semanal varies by weekday, FER-431)
        Task {
            await repo.saveDietAdherence(day: day, mealId: mealId, status: status,
                                         plannedMeals: planned, optionIndex: option)
            adherence7d = await repo.dietAdherenceSeries(from: Self.weekAgoKey(of: day), to: day)
            await loadHeat()
        }
    }

    /// A readable label for a day key — «Today · <date>» on today, the date alone on past days.
    private func dayLabel(_ key: String) -> String {
        guard let d = Self.dayKeyParser.date(from: key) else { return key }
        let date = Self.dayLabelFormatter.string(from: d)
        return key == todayKey ? "\(String(localized: "Today")) · \(date)" : date
    }

    /// Six days before `key` — the start of the 7-day window ending on it.
    private static func weekAgoKey(of key: String) -> String {
        guard let d = dayKeyParser.date(from: key),
              let start = Calendar.current.date(byAdding: .day, value: -6, to: d) else { return key }
        return Repository.localDayKey(start)
    }

    /// Shift a "yyyy-MM-dd" key by whole days, re-keyed in the local calendar.
    private static func shiftDay(_ key: String, by days: Int) -> String {
        guard let d = dayKeyParser.date(from: key),
              let shifted = Calendar.current.date(byAdding: .day, value: days, to: d) else { return key }
        return Repository.localDayKey(shifted)
    }

    private static let dayKeyParser: DateFormatter = {
        DayKey.localFormatter
    }()

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    private func startCapture() {
        pasteText = ""
        pendingPlan = nil
        parseError = nil
        phase = .capture
    }

    private func startManual() {
        manualPlanName = ""
        manualMeals = [ManualMeal()]
        pendingPlan = nil
        parseError = nil
        phase = .manual
    }

    /// Build a `noop.diet.v1` plan from the form (dropping empty foods/options) and save it. Validation
    /// matches the importer: a meal needs ≥1 option with ≥1 food. No targets are invented; cycle = daily.
    private func saveManual() {
        let meals: [DietMeal] = manualMeals.compactMap { meal in
            let options: [DietOption] = meal.options.compactMap { option in
                let foods = option.foods.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                return foods.isEmpty ? nil : DietOption(foods: foods)
            }
            guard !options.isEmpty else { return nil }
            let days = meal.days.count == 7 ? nil : meal.days.sorted()   // all 7 → every day (FER-431)
            return DietMeal(id: UUID().uuidString, name: meal.name.trimmingCharacters(in: .whitespaces),
                            suggestedTime: nil, options: options, notes: nil, days: days)
        }
        guard !meals.isEmpty else { return }
        let cycle: DietPlanCycle = meals.contains { $0.days != nil } ? .semanal : .diario
        let language: DietPlanLanguage = (Locale.current.language.languageCode?.identifier == "es") ? .es : .en
        let plan = DietPlan(language: language, name: manualPlanName.trimmingCharacters(in: .whitespaces),
                            cycle: cycle, meals: meals)
        save(plan)
    }

    private func copyPrompt() {
        PlatformPasteboard.copy(DietPrompt.forCurrentLocale())
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { copied = false }
        }
    }

    private func parse(text: String) {
        parse(data: Data(text.utf8))
    }

    private func parse(data: Data) {
        do {
            pendingPlan = try importer.parse(data)
            parseError = nil
            phase = .confirm
        } catch let error as DietPlanParseError {
            parseError = error
        } catch {
            parseError = .notJSON
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { parseError = .notJSON; return }
        parse(data: data)
    }

    private func save(_ plan: DietPlan) {
        guard let row = try? importer.makeDietPlanRow(
            plan, id: UUID().uuidString, createdAt: Int(Date().timeIntervalSince1970)
        ) else { return }
        Task {
            await repo.saveDietPlan(row)
            activePlan = await repo.activeDietPlan()
            activeParsed = plan
            await loadTrackerData()
            await DietReminderScheduler.reschedule(plan.meals)   // new plan → re-aim reminders (FER-412)
            pasteText = ""
            pendingPlan = nil
            parseError = nil
            phase = .landing
        }
    }

    // MARK: - Error copy (es-MX via the String Catalog)

    private func message(for error: DietPlanParseError) -> LocalizedStringKey {
        switch error {
        case .notJSON:
            return "We couldn't read that as a plan file. Paste the full result your AI gave you, or upload the .json."
        case .unsupportedSchema:
            return "That file isn't a NOOP diet plan. Make sure you used the prompt above."
        case .unsupportedIdioma:
            return "The plan's language isn't supported: it must be Spanish or English."
        case .unsupportedCiclo:
            return "That plan's cycle isn't supported: it must be daily or weekly."
        case .noMeals:
            return "That plan has no meals. Check the file and try again."
        case .mealWithoutOptions:
            return "One of the meals has no food options. Check the file and try again."
        case .emptyOption:
            return "One of the meals has an empty option. Check the file and try again."
        case .invalidDailyTargets:
            return "The daily targets must be numbers. Check the file and try again."
        case .invalidDias:
            return "One of the meals has invalid days: use weekday numbers 1–7. Check the file and try again."
        case .semanalWithoutDias:
            return "A weekly plan needs each meal's days. Check the file and try again."
        }
    }
}
#endif
