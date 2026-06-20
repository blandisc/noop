#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import WhoopStore

/// Diet capture — bring in the plan your nutritionist gave you (FER-371).
///
/// «Instrumento diurno»: a capture panel has **no measured datum**, so it stays all-ink on warm
/// paper (DESIGN.md §8.4) — the only color is `critical` on a parse error. Hierarchy is by space, not
/// boxes. The star path is **bring-your-own-LLM**: copy a prompt, paste it into your own AI with your
/// plan (PDF/photo), and bring the `noop.diet.v1` file back to paste or upload. NOOP never calls the
/// network — the user runs the LLM step (`DietPlanImporter` from FER-370 validates the result).
///
/// This screen is capture + confirm + saved summary only; the daily checklist and apego % are FER-372.
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

    private let importer = DietPlanImporter()

    var body: some View {
        Group {
            switch phase {
            case .landing:
                if let plan = activePlan { scrolled { savedSummary(plan) } }
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
            mealList(plan, showTimes: false)
            QuietButton("Save plan") { save(plan) }
        }
    }

    // MARK: - Saved summary

    private func savedSummary(_ row: DietPlanRow) -> some View {
        let plan = activeParsed
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                nameText(row.name, fallback: "Your plan")
                    .font(StrandFont.title1).foregroundStyle(theme.ink)
                if let plan {
                    Text("\(plan.meals.count) meals · active")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
            }
            if let plan { mealList(plan, showTimes: true) }
            QuietButton("Replace plan") { startCapture() }
        }
    }

    // MARK: - Shared pieces

    private func mealList(_ plan: DietPlan, showTimes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.meals.enumerated()), id: \.offset) { index, meal in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        nameText(meal.name, fallback: "Meal")
                            .font(StrandFont.body).foregroundStyle(theme.ink)
                        if showTimes, let t = meal.suggestedTime, !t.isEmpty {
                            Spacer()
                            Text(t).font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                        }
                    }
                    if !showTimes {
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
        activePlan = await repo.activeDietPlan()
        activeParsed = activePlan.flatMap { try? importer.parse(text: $0.payloadJSON) }
        loaded = true
    }

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
