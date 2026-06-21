#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

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

    private enum Phase { case landing, capture, confirm }

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
    @State private var adherence7d: [Double] = []
    @State private var todayKey = ""
    @State private var selectedDay = ""

    private let importer = DietPlanImporter()

    var body: some View {
        Group {
            switch phase {
            case .landing:
                if let plan = activePlan { scrolled { tracker(plan) } }
                else { emptyState }
            case .capture:
                scrolled { captureFlow }
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
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            header("Capture plan", "Bring your nutritionist's plan")

            step(1, "Copy the prompt and paste it into your trusted AI, along with your plan (PDF or photo).") {
                QuietButton(copied ? "Copied" : "Copy prompt") { copyPrompt() }
            }

            step(2, "Bring back the file it gives you — paste it or upload it.") {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    pasteField
                    HStack(spacing: NoopMetrics.gap) {
                        QuietButton("Upload .json file") { showFileImporter = true }
                        QuietButton("Continue") { parse(text: pasteText) }
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let parseError { errorNote(parseError) }
                }
            }
        }
    }

    private var pasteField: some View {
        TextEditor(text: $pasteText)
            .font(StrandFont.mono)
            .foregroundStyle(theme.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 96)
            .padding(NoopMetrics.cardPadding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if pasteText.isEmpty {
                    Text("Paste the result here…")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkTertiary)
                        .padding(NoopMetrics.cardPadding)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Paste your plan")
    }

    private func errorNote(_ error: DietPlanParseError) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.gap) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .regular))
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
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            planHeader("Review your plan", name: plan.name)
            mealList(plan)
            QuietButton("Save plan") { save(plan) }
        }
    }

    // MARK: - Daily tracker (FER-372)

    private func tracker(_ row: DietPlanRow) -> some View {
        let planned = activeParsed?.meals.count ?? 0
        let marked = todayStatuses.count
        let pct = marked == 0 ? nil
            : DietAdherence.dayPercent(statuses: Array(todayStatuses.values), plannedMeals: planned)
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            dayNav
            adherenceHero(pct: pct, marked: marked, planned: planned)
            if let plan = activeParsed { mealTracker(plan) }
            QuietButton("Replace plan") { startCapture() }
        }
    }

    /// Day navigation (FER-402): ‹ date › steps one day at a time; the forward arrow is disabled on
    /// today (no future to mark). The date and arrows stay in ink — color lives only in the apego %.
    private var dayNav: some View {
        let atToday = selectedDay >= todayKey
        return HStack {
            Button { goToDay(Self.shiftDay(selectedDay, by: -1)) } label: {
                Image(systemName: "chevron.left").font(StrandFont.headline).foregroundStyle(theme.ink)
            }
            .accessibilityLabel("Previous day")
            Spacer()
            Text(dayLabel(selectedDay)).font(StrandFont.subhead).foregroundStyle(theme.ink)
            Spacer()
            Button { goToDay(Self.shiftDay(selectedDay, by: 1)) } label: {
                Image(systemName: "chevron.right").font(StrandFont.headline)
                    .foregroundStyle(atToday ? theme.hairlineStrong : theme.ink)
            }
            .disabled(atToday)
            .accessibilityLabel("Next day")
        }
    }

    /// The day's adherence % — the one dominant numeral and the lone datum, so it carries the only
    /// saturated color. Until a meal is marked it shows «—» in ink (pending isn't a punitive 0%).
    private func adherenceHero(pct: Int?, marked: Int, planned: Int) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(selectedDay == todayKey ? "Diet · today" : "Diet").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                    if let pct {
                        Text("\(pct)").instrumentoHero(62).foregroundStyle(theme.dataRecovery)
                        Text(verbatim: "%").font(StrandFont.title1).foregroundStyle(theme.dataRecovery)
                    } else {
                        Text(verbatim: "—").instrumentoHero(62).foregroundStyle(theme.ink)
                    }
                }
                Group {
                    if pct != nil {
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

    private func mealTracker(_ plan: DietPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today's meals").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, NoopMetrics.gap)
            ForEach(Array(plan.meals.enumerated()), id: \.offset) { index, meal in
                mealTrackRow(meal)
                if index < plan.meals.count - 1 {
                    Rectangle().fill(theme.hairline).frame(height: 0.5)
                }
            }
        }
    }

    private func mealTrackRow(_ meal: DietMeal) -> some View {
        let status = todayStatuses[meal.id]
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            nameText(meal.name, fallback: "Meal").font(StrandFont.body).foregroundStyle(theme.ink)
            if status == nil, let foods = meal.options.first?.foods, !foods.isEmpty {
                Text(foods.joined(separator: " · "))
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: NoopMetrics.space2) {
                statusChip("Followed", meal.id, .cumpli, status)
                statusChip("Swapped",  meal.id, .sustitui, status)
                statusChip("Skipped",  meal.id, .salte, status)
            }
        }
        .padding(.vertical, NoopMetrics.gap)
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
                .padding(.vertical, NoopMetrics.gap)
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
        HStack(alignment: .top, spacing: NoopMetrics.gap) {
            Text("\(n)")
                .font(StrandFont.headline).monospacedDigit()
                .foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
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
                .padding(NoopMetrics.screenPadding)
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
        loaded = true
    }

    /// Load the viewed day's per-meal marks + the 7-day adherence trend ending on that day.
    private func loadTrackerData() async {
        let marks = await repo.dietAdherence(day: selectedDay)
        todayStatuses = Dictionary(marks.map { ($0.mealId, $0.status) }, uniquingKeysWith: { first, _ in first })
        adherence7d = await repo.dietAdherenceSeries(from: Self.weekAgoKey(of: selectedDay), to: selectedDay)
    }

    /// Jump to a day (never past today) and reload its marks + trend.
    private func goToDay(_ key: String) {
        guard key <= todayKey else { return }
        selectedDay = key
        Task { await loadTrackerData() }
    }

    /// Mark one meal's status on the viewed day: optimistic local update (the hero % recomputes at
    /// once), then persist + refresh the trend off the render path.
    private func mark(_ mealId: String, _ status: DietMealStatus) {
        todayStatuses[mealId] = status
        let planned = activeParsed?.meals.count ?? 0
        let day = selectedDay
        Task {
            await repo.saveDietAdherence(day: day, mealId: mealId, status: status, plannedMeals: planned)
            adherence7d = await repo.dietAdherenceSeries(from: Self.weekAgoKey(of: day), to: day)
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
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
            return "The plan's language isn't supported — it must be Spanish or English."
        case .unsupportedCiclo:
            return "Only daily plans are supported for now."
        case .noMeals:
            return "That plan has no meals. Check the file and try again."
        case .mealWithoutOptions:
            return "One of the meals has no food options. Check the file and try again."
        case .emptyOption:
            return "One of the meals has an empty option. Check the file and try again."
        case .invalidDailyTargets:
            return "The daily targets must be numbers. Check the file and try again."
        }
    }
}
#endif
