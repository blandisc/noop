import SwiftUI
import StrandDesign
import Combine
import Observation
import BiometricStreams
import CenitStore
import StrandImport
import StrandAnalytics
import StrandTraining

extension AppModel {

    /// Illness/strain early-warning (FER-667): compare the last ~2 days against a ~28-day baseline
    /// (ending 3 days ago) for resting HR, HRV, skin-temp deviation and respiration, then hand the
    /// per-signal z-scores to `IllnessSignalEngine` — a 0–100 composite behind a ≥2-signal
    /// corroboration gate with EXPLICIT confounder suppression. A hangover / sauna / hard-training
    /// night (read from the journal) damps the score ×0.45 and never fires the banner, so the classic
    /// early-illness signature (RHR↑ + HRV↓ + skin-temp↑) only raises when a plainer explanation was
    /// ruled out. On-device only; APPROXIMATE — a heads-up to rest, not a diagnosis.
    ///
    /// The journal read is async, so the recompute runs in a task; a newer dashboard emission cancels
    /// the in-flight one (`illnessTask`) so two runs never write `healthAlert` out of order.
    // AppModel-internal (split D1)
    func evaluateIllness(_ days: [DailyMetric]) {
        illnessTask?.cancel()
        guard behavior.illnessWatch, days.count >= 14 else { healthAlert = nil; return }
        illnessTask = Task { [weak self] in
            guard let self else { return }
            let context = await self.illnessContext(days)
            guard !Task.isCancelled else { return }
            self.applyIllnessEvaluation(days, context: context)
        }
    }

    /// Same-day behaviour context for the recent illness window, read from the journal (imported ∪
    /// native). A confounder answered "yes" on either of the last two nights suppresses the heads-up.
    /// `hardOrLateWorkout` is derived from a strain z-anomaly (a hard/late session elevates RHR and
    /// lowers HRV overnight just like early illness); `travelPhaseJump` stays false until the
    /// CircadianEngine (FER-671) can flag a body-clock jump.
    private func illnessContext(_ days: [DailyMetric]) async -> IllnessSignalEngine.Context {
        let recentKeys = Set(days.suffix(2).map(\.day))
        let yesQuestions = Set(
            await repo.journalEntries(days: 5)
                .filter { recentKeys.contains($0.day) && $0.answeredYes }
                .map(\.question))
        let recentStrain = days.suffix(2).compactMap(\.strain)
        let hardWorkout = !recentStrain.isEmpty && IllnessWatch.isAnomaly(
            recentMean: recentStrain.reduce(0, +) / Double(recentStrain.count),
            base: Array(days.suffix(31).dropLast(3)).compactMap(\.strain),
            higherIsWorse: true)
        return IllnessSignalEngine.Context(
            alcohol: yesQuestions.contains(IllnessJournal.alcohol),
            stress: yesQuestions.contains(IllnessJournal.stress),
            sauna: yesQuestions.contains(IllnessJournal.sauna),
            hardOrLateWorkout: hardWorkout,
            travelPhaseJump: false,
            alreadyUnwell: yesQuestions.contains(IllnessJournal.sick),
            baselineTrusted: true)   // gated to ≥14 nights at the call site
    }

    /// Score the recent window with `IllnessSignalEngine` and set the banner. Only a `.raised` level
    /// (clear multi-signal anomaly, no confounder) surfaces the alarming banner + notification; mild /
    /// suppressed / already-unwell / quiet stay silent — that suppression is the false-positive win.
    private func applyIllnessEvaluation(_ days: [DailyMetric], context: IllnessSignalEngine.Context) {
        let previous: String? = healthAlert
        func mean(_ vals: [Double]) -> Double? {
            if vals.isEmpty { return nil }
            let sum: Double = vals.reduce(0.0) { (acc: Double, v: Double) in acc + v }
            return sum / Double(vals.count)
        }
        // FER-543 / FER-641 / FER-882 / FER-884: the HRV and resting-HR terms score against a
        // SINGLE-SOURCE history, chosen by the data-source mode. In Combined / strap-only they use the
        // STRAP-ONLY history exactly as before (regression zero): Apple-only nights carry SDNN, not the
        // band's RMSSD (not interchangeable, no published conversion; Shaffer & Ginsberg 2017), AND their
        // resting HR is read from awake sedentary samples excluding sleep — ~10–13 bpm above the band's
        // sleep-nadir RHR (Fenland Study; Gonzales et al. 2023, PLoS One 18(5):e0285272) — so mixing either
        // into the band baseline contaminates it (FER-519). In Apple-only mode `strapDays` is EMPTY, which
        // would collapse illness to <2 signals and never fire; instead we score Apple's OWN RHR/SDNN against
        // an APPLE-ISOLATED baseline (`SourceLens.maskForBaseline(keep:.apple)`). A within-source z-score is
        // valid regardless of Apple's absolute RHR offset or SDNN≠RMSSD — it measures the deviation from the
        // user's own Apple norm (within-source SDNN z-score; same frame as retired FER-153 estimates).
        // Skin temp is likewise source-routed (FER-882: each instrument has its own absolute-°C baseline).
        // Respiration IS the same physical metric across sources (both measured during sleep, breaths/min)
        // and keeps the full merged history. `appleHealthDays == []` ⇒ identity (a strap-only user → no change).
        let strapDays: [DailyMetric] = SourceLens.strapOnlyHistory(days, appleHealthDays: repo.appleHealthDays)
        // FER-884: the source that feeds RHR/HRV/skin-temp — Apple only when the mode excludes the band.
        let signalSource: SourceLens.Source = (repo.dataSourceMode == .appleHealthOnly) ? .apple : .band
        // RHR/HRV history: strapDays byte-for-byte in Combined/strap-only; Apple-isolated in Apple-only.
        let vitalsDays: [DailyMetric] = signalSource == .apple
            ? SourceLens.maskForBaseline(days, keep: .apple, appleDays: repo.appleHealthDays)
            : strapDays

        // Each signal's illness-ward z-score is computed exactly as before (robust σ via IllnessWatch,
        // recent = last ~2 nights, base = the ~28 nights ending 3 days ago), then handed to the engine
        // which owns the corroboration + confounder logic. The es-MX phrase is rendered here, in the app
        // layer, so the copy stays localised; the engine only decides which phrases to surface.
        var inputs: IllnessSignalEngine.Inputs = IllnessSignalEngine.Inputs()
        var labels: [String: String] = [:]
        func read(_ key: String, _ kp: (DailyMetric) -> Double?, higherIsWorse: Bool,
                  from src: [DailyMetric], label: (_ recent: Double, _ base: Double) -> String)
        -> IllnessSignalEngine.SignalReading? {
            let recent: [DailyMetric] = Array(src.suffix(2))
            let base: [DailyMetric] = Array(src.suffix(31).dropLast(3))
            let recentVals: [Double] = recent.compactMap(kp)
            let baseVals: [Double] = base.compactMap(kp)
            guard let r: Double = mean(recentVals),
                  let dev = IllnessWatch.deviation(recentMean: r, base: baseVals, higherIsWorse: higherIsWorse)
            else { return nil }
            labels[key] = label(r, dev.baseMean)
            let z: Double = dev.z
            return IllnessSignalEngine.SignalReading(zIllnessward: z)
        }
        inputs.restingHR = read("restingHR", { (d: DailyMetric) -> Double? in d.restingHr.map(Double.init) },
                                higherIsWorse: true, from: vitalsDays) { (recent: Double, base: Double) -> String in
            let delta: Int = Int((recent - base).rounded())
            return String(localized: "resting HR +\(delta) bpm")
        }
        // HRV's percentage phrase needs a positive baseline; skip the whole term if the base mean is 0.
        let hrvBaseWindow: [Double] = Array(vitalsDays.suffix(31).dropLast(3)).compactMap { (d: DailyMetric) -> Double? in d.avgHrv }
        if let hrvBase: Double = mean(hrvBaseWindow), hrvBase > 0 {
            inputs.hrv = read("hrv", { (d: DailyMetric) -> Double? in d.avgHrv }, higherIsWorse: false, from: vitalsDays) {
                (recent: Double, base: Double) -> String in
                let pct: Int = Int(((1.0 - recent / base) * 100.0).rounded())
                return String(localized: "HRV −\(pct)%")
            }
        }
        // FER-882: skin temp Δ is source-specific — route through the same baseline lens.
        let skinTempDays: [DailyMetric] = SourceLens.maskForBaseline(days, keep: signalSource, appleDays: repo.appleHealthDays)
        inputs.skinTemp = read("skinTemp", { (d: DailyMetric) -> Double? in d.skinTempDevC }, higherIsWorse: true, from: skinTempDays) {
            (r: Double, _: Double) -> String in
            String(localized: "skin temp +\(String(format: "%.1f", r))°C")
        }
        inputs.respiration = read("respiration", { (d: DailyMetric) -> Double? in d.respRateBpm }, higherIsWorse: true, from: days) {
            (_: Double, _: Double) -> String in
            String(localized: "respiration up")
        }

        let result = IllnessSignalEngine.evaluate(inputs, context: context, firedLabels: labels)
        healthAlert = result.level == .raised
            ? String(localized: "Your body looks strained: \(result.firedSignals.joined(separator: ", ")). Consider taking it easy.")
            : nil
        // Banner transition (clear → raised): surface it as a system notification so the
        // early-warning reaches the user when the window is closed. IllnessNotifier rate-limits to
        // once per local day; the not-a-diagnosis hedge lives in its subtitle.
        if let alert = healthAlert, previous == nil {
            IllnessNotifier.post(alert)
        }
    }

    /// Re-run the illness watch over the cached history. Called when the Automations toggle
    /// flips — the repo.$days sink only fires on data changes, so a flip would otherwise wait
    /// for the next refresh.
    func reevaluateIllness() {
        evaluateIllness(repo.days)
    }
}
