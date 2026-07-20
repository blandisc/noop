import SwiftUI
import StrandDesign
import StrandAnalytics

// RelojCorporalSheet.swift — «Tu reloj corporal» (FER-712 F1 / FER-713 F2). The phase-reading block was
// retired; the sheet now opens to the jet-lag reajuste plan only (PlanViajeSheet), still presented as a
// light «Instrumento» sheet from the Experimental section of Ajustes.

struct RelojCorporalSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository

    /// The active jet-lag plan's inputs (FER-713 F2), shared with `PlanViajeSheet` via UserDefaults.
    @AppStorage(JetLagPlanStore.key) private var planJSON = ""
    @State private var showPlanViaje = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                Text("RELOJ CORPORAL")
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.top, CenitMetrics.screenPadding)
                reajusteSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
        }
        .background(theme.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showPlanViaje) {
            PlanViajeSheet(existing: JetLagPlanStore.decode(planJSON))
                .instrumentoTheme(theme).environmentObject(repo)
        }
    }

    // MARK: - Reajuste (FER-713 F2 — the jet-lag plan)

    @ViewBuilder
    private var reajusteSection: some View {
        Divider().overlay(theme.hairline)
        Text("REAJUSTE").instrumentoOverline().foregroundStyle(theme.inkTertiary)
        if let active = JetLagPlanStore.decode(planJSON) {
            let (jetLag, dayIndex) = JetLagPlanStore.progress(active)
            if jetLag.days.isEmpty || dayIndex > jetLag.estimatedDays {
                planFinished(total: jetLag.estimatedDays)
            } else {
                planActive(jetLag.days[dayIndex - 1], dayIndex: dayIndex, total: jetLag.estimatedDays)
            }
        } else {
            Text(verbatim: "¿Un viaje o cambio de turno a la vista? Arma un plan de luz y horarios para reajustar tu reloj a tu ritmo.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton("Planear un viaje") { showPlanViaje = true }
        }
    }

    private func planActive(_ day: CircadianEngine.DayPlan, dayIndex: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "Día \(dayIndex)")
                    .font(InstrumentoType.groteskHeadline(40)).foregroundStyle(theme.ink)
                Text(verbatim: "de \(total)")
                    .font(StrandFont.title2).foregroundStyle(theme.inkTertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: Self.todayGuidance(day))
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "Apunta a dormir alrededor de las ~\(JetLagPlanStore.clock(day.targetSleepHour)) y despertar ~\(JetLagPlanStore.clock(day.targetWakeHour)).")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton("Ver el plan completo") { showPlanViaje = true }
            // Anchor the wellness disclaimer with the actionable light/timing guidance, so it travels
            // with the claim even if the user never opens the full plan (/cso finding 3b).
            Text(verbatim: PlanViajeSheet.methodLine)
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan de reajuste, día \(dayIndex) de \(total). \(Self.todayGuidance(day)) Apunta a dormir alrededor de las \(JetLagPlanStore.clock(day.targetSleepHour)). Toca dos veces para ver el plan completo.")
    }

    private func planFinished(total: Int) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            Text(verbatim: "Listo: completaste tu reajuste de \(total) días. Ojalá tu reloj ya vaya a la par.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton("Cerrar") { planJSON = "" }
        }
    }

    private static func todayGuidance(_ day: CircadianEngine.DayPlan) -> String {
        "Hoy: busca luz brillante entre las ~\(JetLagPlanStore.clock(day.brightLightStartHour)) y las ~\(JetLagPlanStore.clock(day.brightLightEndHour)), y baja luces desde las ~\(JetLagPlanStore.clock(day.dimFromHour))."
    }
}
