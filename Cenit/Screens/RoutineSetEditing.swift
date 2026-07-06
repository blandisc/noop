#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// RoutineSetEditing.swift — the per-set rest logic + rest chip shared by the two inline set-table screens:
// the routine builder (1d, `RoutineBuilderScreen`) and the plan-day editor (1o, `PlanDayEditorScreen`, FER-747).
// Both edit the SAME model (`RoutineExercise` + its `RoutineSet`s) with the SAME F0 rest model, so the
// resolution/apply/label helpers live here once. The set TABLE itself (numeral ring vs plain label, thumb,
// column widths) stays per-screen because those renderings genuinely differ.

/// Identifies the set whose rest the 1e editor is editing (exercise index + set index).
struct RestEditTarget: Identifiable, Hashable { let ei: Int; let si: Int; var id: String { "\(ei)-\(si)" } }

// MARK: - Per-set rest resolution (F0 model)

enum RoutineSetEditing {
    /// This set's effective rest: its own override if set, else the exercise's rest fields (the F0 fallback).
    static func effectiveRest(_ re: RoutineExercise, _ si: Int) -> RestConfig {
        if let r = re.sets[si].rest { return r }
        return RestConfig(mode: re.restMode, seconds: re.restSeconds,
                          hrReference: re.hrRestReference, hrValue: re.hrRestValue)
    }

    /// 1-based work-set number for the 1e overline (nil for a warm-up «C» set).
    static func workSetNumber(_ re: RoutineExercise, _ si: Int) -> Int? {
        guard re.sets[si].kind == .work else { return nil }
        return re.sets[0...si].filter { $0.kind == .work }.count
    }

    /// «C» for a warm-up set; otherwise its position among the work sets (1-based, warm-ups don't count).
    static func setLabel(_ re: RoutineExercise, _ si: Int) -> String {
        if re.sets[si].kind == .warmup { return String(localized: "C") }
        return "\(re.sets[0...si].filter { $0.kind == .work }.count)"
    }

    /// Apply an edited rest from 1e. «This set» writes that set's override; «All sets» writes the
    /// exercise-level rest fields and clears every per-set override so the whole exercise inherits it.
    static func applyRest(to re: inout RoutineExercise, si: Int, config: RestConfig, applyToAll: Bool) {
        guard re.sets.indices.contains(si) else { return }
        if applyToAll {
            re.restMode = config.mode
            re.restSeconds = config.seconds
            re.hrRestReference = config.hrReference
            re.hrRestValue = config.hrValue
            for i in re.sets.indices { re.sets[i].rest = nil }
        } else {
            re.sets[si].rest = config
        }
    }

    /// The chip's compact label: «1 min» / «90 s» for time, «FC · N%» for the HR threshold. The HR prefix is
    /// localized on its own so the literal «%» never lands in a format-string key.
    static func restChipLabel(_ cfg: RestConfig) -> String {
        if cfg.mode == .heartRate {
            let pct = Int((cfg.hrValue * 100).rounded())
            guard pct > 0 else { return String(localized: "by HR") }
            return String(localized: "HR", comment: "compact chip prefix for a heart-rate rest threshold") + " · \(pct)%"
        }
        let s = cfg.seconds
        return s % 60 == 0 ? String(localized: "\(s / 60) min") : String(localized: "\(s) s")
    }
}

// MARK: - Per-set rest chip (→ 1e push)
//
// Each set carries its own rest (choque 3): the chip shows this set's EFFECTIVE rest (its own override, or the
// exercise's rest as fallback). Time reads in ink; an HR threshold reads in the recovery green, because the
// threshold is a datum. Tapping pushes the shared `RestEditorScreen` (1e). `timeColor` is the only visual knob
// the two screens differ on (builder = ink, plan-day editor = inkSecondary).

struct RestChip: View {
    @Environment(\.instrumentoTheme) private var theme
    let cfg: RestConfig
    let timeColor: Color
    let action: () -> Void

    var body: some View {
        let isHR = cfg.mode == .heartRate
        return Button(action: action) {
            HStack(spacing: 5) {
                Text(RoutineSetEditing.restChipLabel(cfg)).font(StrandFont.caption).monospacedDigit()
                    .foregroundStyle(isHR ? theme.dataRecovery : timeColor).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isHR ? theme.dataRecovery : theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit rest for this set"))
    }
}
#endif
