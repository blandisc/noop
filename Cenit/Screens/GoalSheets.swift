#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Goal sheets (FER-311)
//
// The two «Instrumento» surfaces the «Tu meta» anchor opens: the goal picker (pure selection — 3 focos,
// condición fans out to two signals by progressive disclosure, optional date) and the trajectory
// simulator (the projection's two paths + confidence band). The theme is passed explicitly — it doesn't
// cross a `.sheet` boundary (FER-162). Color lives ONLY on the lever path / its datum (DESIGN.md §8.4).

// MARK: Goal picker

struct GoalPickerSheet: View {
    let theme: InstrumentoTheme
    let onSave: (GoalMetric, Date?) -> Void
    var onClear: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var focus: GoalFocus?
    @State private var conditionMetric: GoalMetric?
    @State private var useDate: Bool
    @State private var date: Date

    init(theme: InstrumentoTheme, initialMetric: GoalMetric? = nil, initialDate: Date? = nil,
         onSave: @escaping (GoalMetric, Date?) -> Void, onClear: (() -> Void)? = nil) {
        self.theme = theme
        self.onSave = onSave
        self.onClear = onClear
        _focus = State(initialValue: initialMetric?.focus)
        _conditionMetric = State(initialValue: initialMetric?.focus == .condition ? initialMetric : nil)
        _useDate = State(initialValue: initialDate != nil)
        _date = State(initialValue: initialDate
                      ?? Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date())
    }

    /// The resolved metric: direct for recovery/sleep, the sub-choice for condición, nil until valid.
    private var resolved: GoalMetric? {
        guard let focus else { return nil }
        return focus.directMetric ?? conditionMetric
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TU META").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("¿Qué quieres mejorar?")
                        .font(StrandFont.title2).foregroundStyle(theme.ink)
                }

                VStack(spacing: 0) {
                    ForEach(GoalFocus.allCases, id: \.self) { focusRow($0) }
                }

                dateSection

                VStack(spacing: 12) {
                    Button {
                        if let m = resolved { onSave(m, useDate ? date : nil); dismiss() }
                    } label: {
                        Text("Poner meta")
                            .font(StrandFont.headline)
                            .foregroundStyle(resolved != nil ? theme.paper : theme.inkTertiary)
                            .frame(maxWidth: .infinity).padding(15)
                            .background(resolved != nil ? theme.ink : theme.hairline,
                                        in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(resolved == nil)

                    if let onClear {
                        Button { onClear(); dismiss() } label: {
                            Text("Quitar meta").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    @ViewBuilder private func focusRow(_ f: GoalFocus) -> some View {
        let selected = focus == f
        VStack(alignment: .leading, spacing: 0) {
            Button {
                focus = f
                if f != .condition { conditionMetric = nil }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundStyle(selected ? theme.ink : theme.inkTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title).font(StrandFont.headline).foregroundStyle(theme.ink)
                        Text(f.subtitle).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }

            if selected && f == .condition {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(f.conditionMetrics, id: \.self) { m in
                        Button { conditionMetric = m } label: {
                            HStack(spacing: 9) {
                                Image(systemName: conditionMetric == m ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(conditionMetric == m ? theme.ink : theme.inkTertiary)
                                Text(m.signalLabel).font(StrandFont.subhead)
                                    .foregroundStyle(conditionMetric == m ? theme.ink : theme.inkSecondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 31)
                .padding(.bottom, 12)
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $useDate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Para una fecha?").font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text("Una carrera, un viaje… (opcional)")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
            .tint(theme.ink)

            if useDate {
                DatePicker("Fecha", selection: $date, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().tint(theme.ink)
            }
        }
    }
}

// MARK: Trajectory simulator

struct SimulatorScreen: View {
    let theme: InstrumentoTheme
    let metric: GoalMetric
    let targetDate: Date?
    var onEdit: (() -> Void)? = nil

    @EnvironmentObject private var repo: Repository
    @State private var sim: GoalSimulation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                if let sim {
                    if let proj = sim.projection {
                        chart(proj)
                        if proj.withLever != nil { completeReadout(proj, name: sim.leverName) }
                        else { bareReadout(proj) }
                        Text("Si tus patrones se mantienen.")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    } else {
                        gateState(sim.usableDays)
                    }
                } else {
                    LoadingStateView("Proyectando tu trayectoria").frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task { sim = await repo.goalSimulation(metric: metric, targetDate: targetDate) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TU META").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(metric.focus.title).font(StrandFont.title2).foregroundStyle(theme.ink)
                Text(subhead).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            if let onEdit {
                Button(action: onEdit) {
                    Text("Cambiar").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subhead: String {
        var parts: [String] = []
        if metric.focus == .condition { parts.append(metric == .hrv ? "por HRV" : "por FC en reposo") }
        if let targetDate { parts.append("para el \(Self.longDate.string(from: targetDate))") }
        parts.append("\(Repository.goalHorizon(targetDate: targetDate)) días")
        return parts.joined(separator: " · ")
    }

    // MARK: Chart

    private func chart(_ proj: TrajectorySimulator.Projection) -> some View {
        let base = proj.baseline.map {
            TrajectoryChart.Point(x: Double($0.dayOffset), estimate: $0.estimate, low: $0.low, high: $0.high)
        }
        let lever = proj.withLever?.map {
            TrajectoryChart.Point(x: Double($0.dayOffset), estimate: $0.estimate, low: $0.low, high: $0.high)
        }
        let xEnd = targetDate.map { Self.shortDate.string(from: $0) } ?? "+\(proj.horizonDays) d"
        return TrajectoryChart(
            baseline: base, withLever: lever, startValue: proj.level,
            goal: nil, goalLabel: nil, accent: accent, higherIsBetter: metric.higherIsBetter,
            xStartLabel: "hoy", xEndLabel: xEnd, accessibilityText: a11y(proj))
            .frame(height: 200)
    }

    // MARK: Readouts

    @ViewBuilder private func completeReadout(_ proj: TrajectorySimulator.Projection, name: String?) -> some View {
        let baseEnd = proj.baseline.last?.estimate ?? proj.level
        let leverEnd = proj.withLever?.last?.estimate ?? baseEnd
        let gap = abs(proj.gap ?? 0)
        let lever = name ?? "esta palanca"
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text("si cambias: \(lever)").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))

            (Text("Como vas llegas a ~\(metric.format(baseEnd)). ")
             + Text("Si cambias \(lever), ~\(metric.format(leverEnd))").foregroundColor(accent)
             + Text(" — \(metric.format(gap)) \(metric.higherIsBetter ? "más" : "menos")."))
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func bareReadout(_ proj: TrajectorySimulator.Projection) -> some View {
        let baseEnd = proj.baseline.last?.estimate ?? proj.level
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 12))
                Text("si cambias · aún aprendiendo qué te funciona").font(StrandFont.caption)
            }
            .foregroundStyle(theme.inkTertiary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))

            Text("Como vas llegas a ~\(metric.format(baseEnd)). Corre un experimento para ver el otro camino.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gateState(_ usable: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aún reuniendo señal")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.ink)
            Text("\(usable) de \(TrajectorySimulator.minDays) días")
                .font(StrandFont.subhead).monospacedDigit().foregroundStyle(theme.inkTertiary)
            Text("Con un par de semanas de base verás tu trayectoria y el costo de no cambiar.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    private var accent: Color {
        switch metric {
        case .recovery:  return theme.dataRecovery
        case .sleep:     return theme.dataSleep
        case .hrv:       return theme.dataHrv
        case .restingHr: return theme.dataHeart
        }
    }

    private func a11y(_ proj: TrajectorySimulator.Projection) -> String {
        let baseEnd = proj.baseline.last?.estimate ?? proj.level
        var s = "Como vas llegas a \(metric.format(baseEnd))."
        if let leverEnd = proj.withLever?.last?.estimate {
            s += " Si cambias una palanca, \(metric.format(leverEnd))."
        }
        return s
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "d MMM"; return f
    }()
    private static let longDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "d 'de' MMMM"; return f
    }()
}
#endif
