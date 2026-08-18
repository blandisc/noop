import XCTest
@testable import Cenit
import StrandTraining
import StrandAnalytics

/// FER-87 · «El acta de la sesión»: the three pieces of pure logic the redesigned `summaryPhase`
/// leans on — which datum fills `receiptStats`' third slot, what «Guardado en Salud» says, and what
/// VoiceOver hears for the Effort hero. Each is exposed `static` (not `private`) on `LiveStrengthSheet`
/// specifically so it can be locked down here instead of only ever being eyeballed on a simulator.
final class LiveStrengthSheetSummaryFER87Tests: XCTestCase {

    // MARK: - receiptStatsThirdSlot: mutual exclusivity with the Effort hero

    /// With strain (→ the hero shows Effort), the old code before FER-87 would ALSO print the same
    /// 13.8 a second time as a "Strain" stat. This is the test that would have caught that: with
    /// strain present, the third slot must be `.sets`, never `.avgHr` (even if avgHr also happens to
    /// be present — the two are mutually exclusive by design, not just by today's data).
    func testThirdSlotIsSetsWhenStrainPresentEvenWithAvgHr() {
        XCTAssertEqual(LiveStrengthSheet.receiptStatsThirdSlot(strain: 13.8, setCount: 18, avgHr: 140),
                       .sets(18))
    }

    /// The plain happy path: strain present, no avg HR to conflict with — would fail against any
    /// version that swapped the branch order (checking `avgHr` before `strain`) and returned `.none`
    /// here instead of `.sets`.
    func testThirdSlotIsSetsWhenStrainPresentAndNoAvgHr() {
        XCTAssertEqual(LiveStrengthSheet.receiptStatsThirdSlot(strain: 13.8, setCount: 5, avgHr: nil),
                       .sets(5))
    }

    /// FER-498's original guarantee, preserved: no strain but a captured avg HR still proves the
    /// strap was read — would fail against a naive FER-87 port that made `receiptStats` only ever
    /// show `.sets` (dropping the avg-HR fallback the «sin dato cardiaco» state depends on).
    func testThirdSlotFallsBackToAvgHrWithoutStrain() {
        XCTAssertEqual(LiveStrengthSheet.receiptStatsThirdSlot(strain: nil, setCount: 4, avgHr: 132),
                       .avgHr(132))
    }

    /// Neither signal → nothing invented (no dash, no zero pretending to be a reading).
    func testThirdSlotIsNoneWithoutStrainOrAvgHr() {
        XCTAssertEqual(LiveStrengthSheet.receiptStatsThirdSlot(strain: nil, setCount: 4, avgHr: nil), .none)
    }

    // MARK: - healthSavedText: the kcal figure survives the retired Diet block

    /// Before FER-87 the kcal + "estimated" qualifier lived in `receiptStats`' "Calories · estimated"
    /// stat; this test would fail against code that dropped the qualifier when moving the figure into
    /// «Guardado en Salud» (the exact silent-content-loss this epic keeps re-committing).
    /// Compares against the SAME `String(localized:)` construction the production code uses (the
    /// `RelativeAgoTests` convention) — locale-agnostic, so this pins the interpolated VALUES chosen,
    /// not an English literal that would drift or fail under a non-English test locale.
    func testHealthSavedTextMarksEstimatedEnergy() {
        let s = summary(energyKcal: 412, energySource: .estimated)
        XCTAssertEqual(LiveStrengthSheet.healthSavedText(s),
                       String(localized: "Saved to Health · \(412) kcal estimated"))
    }

    /// Would fail against a version that always appended "estimated" regardless of source (or never
    /// appended it at all) — `.bandCalculated` (real strap HR via Keytel) must read plain.
    func testHealthSavedTextOmitsQualifierForBandCalculatedEnergy() {
        let s = summary(energyKcal: 412, energySource: .bandCalculated)
        XCTAssertEqual(LiveStrengthSheet.healthSavedText(s),
                       String(localized: "Saved to Health · \(412) kcal"))
    }

    /// A legacy session with no persisted energy (`energyKcal == nil`) still gets a confirmation row —
    /// just without a kcal figure it doesn't have.
    func testHealthSavedTextWithoutKcalOmitsTheFigure() {
        let s = summary(energyKcal: nil, energySource: nil)
        XCTAssertEqual(LiveStrengthSheet.healthSavedText(s), String(localized: "Saved to Health"))
    }

    /// kcal rounds the same way the retired stat did (`Int(kcal.rounded())`) — 411.6 reads as 412, not
    /// truncated to 411.
    func testHealthSavedTextRoundsKcal() {
        let s = summary(energyKcal: 411.6, energySource: .bandCalculated)
        XCTAssertEqual(LiveStrengthSheet.healthSavedText(s),
                       String(localized: "Saved to Health · \(412) kcal"))
    }

    // MARK: - strainAccessibilityValue: VoiceOver announces value + scale, not the bare numeral

    /// The acceptance criterion verbatim: «Esfuerzo, 13.8 de 21» — not «13.8» alone (what a naive
    /// `.accessibilityElement(children: .combine)` over the hero + its «/ 21» suffix Text would have
    /// produced, since VoiceOver tends to mangle a bare "/" glyph).
    func testStrainAccessibilityValueAppendsTheScale() {
        XCTAssertEqual(LiveStrengthSheet.strainAccessibilityValue("13.8", scaleSuffix: "/ 21"),
                       String(localized: "\("13.8") of \("21")"))
    }

    /// No suffix (a metric this helper was never meant for) → the bare value, never a dangling "of ".
    func testStrainAccessibilityValueWithoutSuffixReturnsBareValue() {
        XCTAssertEqual(LiveStrengthSheet.strainAccessibilityValue("13.8", scaleSuffix: nil), "13.8")
    }

    // MARK: - Helpers

    private func summary(energyKcal: Double?, energySource: EnergySource?) -> StrengthSummary {
        StrengthSummary(routineName: "Leg Day", endTs: 0, durationS: 3_120, volumeKg: 6_420, setCount: 18,
                        strain: 13.8, avgHr: nil, costBand: .moderate, costTomorrowPct: nil,
                        energyKcal: energyKcal, energySource: energySource,
                        prs: [], muscles: [], isFirstTime: false, comparison: nil, exercises: [])
    }
}
