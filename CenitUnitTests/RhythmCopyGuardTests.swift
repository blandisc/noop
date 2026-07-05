import XCTest
import StrandAnalytics
@testable import Cenit

/// The non-clinical copy guard for «Ritmo» (FER-666, criterion 8). It sweeps the ACTUAL es-MX
/// strings the screen ships (`RhythmCopy.allStrings`) — not just the engine's rawValues — for any
/// word that would name a condition, imply a diagnosis, or push a clinical call-to-action.
///
/// The banned list is deliberately condition-names + CTA terms (es + en), accent-folded. It does
/// NOT ban "ecg" / "diagnóstico" / "enfermedad": those appear ONLY inside the honest disclaimer
/// ("No es un ECG ni un diagnóstico · No detecta enfermedades") as negations, which is exactly the
/// claim frame we want — banning them would flag the disclaimer itself.
final class RhythmCopyGuardTests: XCTestCase {

    /// Condition names, diagnostic verbs, and clinical CTAs — es and en. Stored accent-folded and
    /// lowercased; the sweep folds the candidate the same way so "fibrilación" matches "fibrilacion".
    private let banned = [
        "atrial", "auricular", "palpitation", "palpitacion", "palpitaciones",
        "fibrilacion", "fibrillation", "afib", "arritmia", "arrhythmia",
        "taquicardia", "bradicardia", "latido irregular", "ritmo irregular",
        "consulta", "consulte", "medico", "cardiologo", "clinico", "clinician",
        // Alarm / probability wildcards — defense-in-depth against a future copy edit that would
        // reintroduce hedged-diagnosis language without tripping a condition-name match.
        "posible", "riesgo", "anormal", "irregular", "peligro",
    ]

    private func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX")).lowercased()
    }

    func testShippedEsCopyNamesNoConditionOrCTA() {
        for phrase in RhythmCopy.allStrings {
            let folded = fold(phrase)
            for term in banned {
                XCTAssertFalse(folded.contains(term),
                               "Ritmo copy «\(phrase)» must not contain clinical term “\(term)”.")
            }
        }
    }

    /// The four neutral labels specifically — the only verdict-shaped words that ever surface —
    /// must each be free of condition/diagnosis language.
    func testEveryNeutralLabelIsBenign() {
        for r in [RhythmRegularity.steady, .occasionalEctopy, .varied, .unreadable] {
            let folded = fold(RhythmCopy.label(r))
            for term in banned {
                XCTAssertFalse(folded.contains(term),
                               "Label for \(r) («\(RhythmCopy.label(r))») names a condition/CTA: “\(term)”.")
            }
        }
    }

    /// The disclaimer must stay present and intact (the persistent claim frame).
    func testDisclaimerStatesTheThreeNots() {
        let d = fold(RhythmCopy.disclaimer)
        XCTAssertTrue(d.contains("experimental"))
        XCTAssertTrue(d.contains("no es un ecg"))
        XCTAssertTrue(d.contains("diagnostico"))
        XCTAssertTrue(d.contains("no detecta enfermedades"))
    }
}
