import SwiftUI
import StrandDesign
import StrandAnalytics

// PlanViajeSheet.swift — «Planear un viaje» (FER-713 F2), the input + plan preview for the jet-lag /
// shift-work re-entrainment plan behind «Tu reloj corporal». The user picks a DIRECTION (east/west) and
// a MAGNITUDE (1–12 h); `CircadianEngine.planShift` builds the stepped light + sleep plan; the sheet
// shows it day-by-day and, on «Empezar el plan», persists the inputs via `JetLagPlanStore`. All
// user-facing copy is generated in es-MX from the DayPlan's NUMERIC fields — the engine's English
// `guidance`/`note` is never shown. Wellness framing only: «considera / apunta a», never medical, never
// drugs. Light theme «Instrumento», like F1.

struct PlanViajeSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(JetLagPlanStore.key) private var planJSON = ""

    /// When non-nil, the sheet opens directly on the plan of an ALREADY-active plan (read-only view +
    /// «Terminar plan»), instead of the input. nil = plan a fresh trip.
    let existing: ActiveJetLagPlan?
    init(existing: ActiveJetLagPlan? = nil) { self.existing = existing }

    /// East = advance the clock (earlier, `shiftHours > 0`); West = delay it (later, `shiftHours < 0`).
    private enum Direction: Hashable { case east, west }
    @State private var direction: Direction = .east
    @State private var magnitude = 3
    @State private var showingPlan = false
    @State private var currentSleep = 23.0
    @State private var currentWake = 7.0
    @State private var usedFallback = true
    @State private var loaded = false
    @State private var confirmTerminate = false

    private var shiftHours: Double { (direction == .east ? 1.0 : -1.0) * Double(magnitude) }
    private var plan: CircadianEngine.JetLagPlan {
        CircadianEngine.planShift(shiftHours: shiftHours,
                                  currentSleepHour: currentSleep, currentWakeHour: currentWake)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if showingPlan { planView } else { inputView }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .task {
            guard !loaded else { return }
            if let e = existing {
                // Open straight onto an active plan's timeline, reconstructed from its stored inputs.
                direction = e.shiftHours >= 0 ? .east : .west
                magnitude = max(1, Int(abs(e.shiftHours).rounded()))
                currentSleep = e.currentSleepHour; currentWake = e.currentWakeHour
                usedFallback = false
                showingPlan = true
            } else if let rec = await repo.latestCircadianPhase(),
                      let bed = rec.bedtimeHour, let wake = rec.wakeHour {
                currentSleep = bed; currentWake = wake; usedFallback = false
            }
            loaded = true
        }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            Text("PLANEAR UN VIAJE").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.top, NoopMetrics.screenPadding)
            Text(verbatim: "¿Cuánto se recorre tu horario? También aplica si cambias de turno.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $direction) {
                Text(verbatim: "Hacia el este (madrugas)").tag(Direction.east)
                Text(verbatim: "Hacia el oeste (trasnochas)").tag(Direction.west)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("HORAS DE DIFERENCIA").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Picker("", selection: $magnitude) {
                    ForEach(1...12, id: \.self) { Text(verbatim: "\($0) h").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }

            QuietButton("Ver mi plan") { showingPlan = true }
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Plan preview

    @ViewBuilder
    private var planView: some View {
        if plan.direction == .none {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text("TU PLAN").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.top, NoopMetrics.screenPadding)
                Text(verbatim: "Con un cambio tan chico tu reloj apenas se mueve — no necesitas un plan. Descansa como siempre.")
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                QuietButton("Entendido") { showingPlan = false }
            }
        } else {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text("TU PLAN").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.top, NoopMetrics.screenPadding)
                Text(verbatim: Self.summary(plan))
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if usedFallback {
                    Text(verbatim: "Aún no leemos tu reloj, así que este plan parte de un horario típico. Se afina cuando tengamos tu lectura.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(theme.hairline)
                Text("DÍA CON DÍA").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                VStack(spacing: 0) {
                    ForEach(plan.days, id: \.dayIndex) { day in
                        dayRow(day)
                        if day.dayIndex != plan.days.last?.dayIndex { Divider().overlay(theme.hairline) }
                    }
                }

                if existing == nil {
                    HStack(spacing: 12) {
                        QuietButton("Empezar el plan") { start() }
                        QuietButton("Ajustar") { showingPlan = false }
                    }
                } else {
                    QuietButton("Terminar plan") { confirmTerminate = true }
                        .confirmationDialog("¿Terminar tu plan de reajuste? Perderás el progreso.",
                                            isPresented: $confirmTerminate, titleVisibility: .visible) {
                            Button("Terminar", role: .destructive) { planJSON = ""; dismiss() }
                            Button("Cancelar", role: .cancel) {}
                        }
                }

                Text(verbatim: Self.methodLine)
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayRow(_ day: CircadianEngine.DayPlan) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "Día \(day.dayIndex)")
                .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                .frame(width: 52, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: "sun.max").font(.system(size: 14)).foregroundStyle(theme.dataStrain)
                    .accessibilityHidden(true)
                Text(verbatim: "luz \(JetLagPlanStore.clock(day.brightLightStartHour))–\(JetLagPlanStore.clock(day.brightLightEndHour))")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "Dormir ~\(JetLagPlanStore.clock(day.targetSleepHour))")
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Día \(day.dayIndex). Luz de las \(JetLagPlanStore.clock(day.brightLightStartHour)) a las \(JetLagPlanStore.clock(day.brightLightEndHour)). Dormir alrededor de las \(JetLagPlanStore.clock(day.targetSleepHour)).")
    }

    // MARK: - Actions

    private func start() {
        let startDay = Calendar.current.startOfDay(for: Date())
        let active = ActiveJetLagPlan(shiftHours: shiftHours,
                                      currentSleepHour: currentSleep, currentWakeHour: currentWake,
                                      startEpoch: Int(startDay.timeIntervalSince1970))
        planJSON = JetLagPlanStore.encode(active)
        dismiss()
    }

    // MARK: - Copy (es-MX; generated from the DayPlan numeric fields, never the engine's English string)

    static let methodLine =
        "Es una guía de bienestar basada en luz y horarios, no un tratamiento médico. No sustituye consejo profesional."

    static func summary(_ plan: CircadianEngine.JetLagPlan) -> String {
        let h = Int(plan.totalShiftHours.rounded())
        let verb = plan.direction == .advance ? "adelantar" : "atrasar"
        return "Vas a \(verb) tu reloj \(h) h. Con calma, alrededor de una hora al día, te toma unos \(plan.estimatedDays) días."
    }
}
