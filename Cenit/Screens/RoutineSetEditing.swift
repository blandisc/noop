#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// RoutineSetEditing.swift — the per-set rest logic + rest chip shared by the two inline set-table screens:
// the routine builder (1d, `RoutineBuilderScreen`) and the unified «Rutina» editor (`RoutineEditorScreen`, FER-839).
// Both edit the SAME model (`RoutineExercise` + its `RoutineSet`s) with the SAME F0 rest model, so the
// resolution/apply/label helpers live here once. The set TABLE itself (numeral ring vs plain label, thumb,
// column widths) stays per-screen because those renderings genuinely differ.

/// Identifies the set whose rest the 1e editor is editing (exercise index + set index).
struct RestEditTarget: Identifiable, Hashable { let ei: Int; let si: Int; var id: String { "\(ei)-\(si)" } }

/// Identifies the exercise whose progression plan the 2c editor is editing (FER-D).
struct ProgressionTarget: Identifiable, Hashable { let ei: Int; var id: Int { ei } }

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
            // FER-952 bug: `hrValue` is a FRACTION only for peakDrop/karvonen — formatting it as a
            // percent regardless turned a fixed 160 bpm into «1600%» and restingMargin into noise.
            let hr = String(localized: "HR", comment: "compact chip prefix for a heart-rate rest threshold")
            switch cfg.hrReference {
            case .peakDrop, .karvonenReserve:
                let pct = Int((cfg.hrValue * 100).rounded())
                guard pct > 0 else { return String(localized: "by HR") }
                return hr + " · \(pct)%"
            case .fixedBpm:
                let bpm = Int(cfg.hrValue.rounded())
                guard bpm > 0 else { return String(localized: "by HR") }
                return hr + " · \(bpm) bpm"
            case .restingMargin:
                return String(localized: "by HR")   // target = resting + margin; no number to promise
            }
        }
        let s = cfg.seconds
        return s % 60 == 0 ? String(localized: "\(s / 60) min") : String(localized: "\(s) s")
    }

    // MARK: - Superset grouping (a group = consecutive slots sharing supersetGroup)
    //
    // Pure functions over the slot array, shared by the builder and the «Rutina» editor (FER-838
    // /simplify — they were duplicated verbatim). Mutations return nothing; callers mark their own
    // dirty state.

    static func sameGroup(_ res: [RoutineExercise], _ a: Int, _ b: Int) -> Bool {
        guard res.indices.contains(a), res.indices.contains(b),
              let ga = res[a].supersetGroup, let gb = res[b].supersetGroup else { return false }
        return ga == gb
    }

    static func inSuperset(_ res: [RoutineExercise], _ i: Int) -> Bool {
        guard res.indices.contains(i), res[i].supersetGroup != nil else { return false }
        return sameGroup(res, i, i - 1) || sameGroup(res, i, i + 1)
    }

    /// First member of a superset group (shows the «Superset» overline above it).
    static func firstOfGroup(_ res: [RoutineExercise], _ i: Int) -> Bool {
        inSuperset(res, i) && !sameGroup(res, i, i - 1)
    }

    static func supersetWithNext(_ res: inout [RoutineExercise], _ i: Int) {
        guard i < res.count - 1 else { return }
        let group = res[i].supersetGroup ?? res[i + 1].supersetGroup
            ?? (res.compactMap(\.supersetGroup).max() ?? 0) + 1
        res[i].supersetGroup = group
        res[i + 1].supersetGroup = group
    }

    static func breakSuperset(_ res: inout [RoutineExercise], _ i: Int) {
        guard let g = res[i].supersetGroup else { return }
        res[i].supersetGroup = nil
        let remaining = res.indices.filter { res[$0].supersetGroup == g }
        if remaining.count == 1 { res[remaining[0]].supersetGroup = nil }
    }
}

// MARK: - Per-set rest chip (→ 1e push)
//
// Each set carries its own rest (choque 3): the chip shows this set's EFFECTIVE rest (its own override, or the
// exercise's rest as fallback). Troquel grammar (r15): the hue lives ONLY in the leading icon (♥ recovery
// for HR, clock ember for time); the value reads in ink. Tapping pushes the shared `RestEditorScreen` (1e).

struct RestChip: View {
    @Environment(\.instrumentoTheme) private var theme
    let cfg: RestConfig
    let action: () -> Void

    var body: some View {
        let isHR = cfg.mode == .heartRate
        // FER-952 (owner): SAME chip grammar as the live session's troquel rest chip (r15) — the hue
        // lives ONLY in the leading icon (♥ recovery for HR, clock ember for time), value in ink.
        return Button(action: action) {
            HStack(spacing: 6) {
                (isHR ? StrandIcon.heart.image : StrandIcon.clock.image)
                    .font(StrandFont.glyph(.chevron))
                    .foregroundStyle(isHR ? theme.dataRecovery : theme.dataStrain)
                Text(RoutineSetEditing.restChipLabel(cfg))
                    .font(InstrumentoType.groteskNumber(12, weight: .medium))
                    .foregroundStyle(theme.ink).lineLimit(1)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .troquelChip(theme)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit rest for this set"))
    }
}
#endif
