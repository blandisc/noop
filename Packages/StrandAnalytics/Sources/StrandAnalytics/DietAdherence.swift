import Foundation
import WhoopStore

/// Diet-plan adherence (FER-372).
///
/// A **plain, transparent proportion** — not a clinical, predictive, or weighted score: the share of
/// a day's prescribed meals you actually followed. The rule, stated explicitly so there's no black box:
///
/// > `apego_día = (#cumplí + #sustituí) / #comidas_planeadas × 100`, rounded.
///
/// `cumpli` (ate it as planned) and `sustitui` (an equivalent swap — the nutritionist's «equivalentes»)
/// both count as adherent; `salte` (skipped) and unmarked meals do not. The denominator is the plan's
/// **full** meal count, so the day's figure climbs as more meals are marked and reads its true value
/// once the day is logged. No clinical claim — it's a self-report ratio.
public enum DietAdherence {

    /// Meals that count toward adherence: `cumpli` or `sustitui`.
    public static func adherentCount(_ statuses: [DietMealStatus]) -> Int {
        statuses.filter { $0 == .cumpli || $0 == .sustitui }.count
    }

    /// The day's adherence percentage (0–100, rounded), or `nil` when the plan has no meals.
    /// `statuses` holds only the meals that have been marked; unmarked meals are simply absent and
    /// lower the result through the fixed `plannedMeals` denominator, never the numerator.
    public static func dayPercent(statuses: [DietMealStatus], plannedMeals: Int) -> Int? {
        guard plannedMeals > 0 else { return nil }
        let adherent = adherentCount(statuses)
        return Int((Double(adherent) / Double(plannedMeals) * 100).rounded())
    }
}
