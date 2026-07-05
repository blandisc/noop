import XCTest
import StrandAnalytics
@testable import Cenit

/// The non-clinical copy guard for «Ritmo» (FER-666). It resolves every shipped phrase in BOTH
/// languages — English (the catalog key itself, since `sourceLanguage: en`) and the es-MX catalog
/// translation — and sweeps each for any word that would name a condition, imply a diagnosis, or
/// push a clinical call-to-action. It also asserts every key HAS an es translation, so the screen
/// never silently falls back to English.
///
/// The banned list is condition-names + CTA + alarm/probability wildcards, en and es, accent-folded.
/// It does NOT ban "ecg" / "diagnosis" / "disease" / "diagnóstico" / "enfermedad": those appear only
/// inside the honest disclaimer as negations — banning them would flag the disclaimer itself.
final class RhythmCopyGuardTests: XCTestCase {

    private let banned = [
        // condition names (en + es)
        "atrial", "auricular", "palpitation", "palpitacion", "palpitaciones",
        "fibrilacion", "fibrillation", "afib", "arritmia", "arrhythmia",
        "taquicardia", "tachycardia", "bradicardia", "bradycardia",
        "latido irregular", "ritmo irregular", "irregular heartbeat",
        // clinical CTA (en + es)
        "consulta", "consulte", "medico", "cardiologo", "clinico", "clinician", "doctor",
        // alarm / probability wildcards (en + es)
        "posible", "possible", "riesgo", " risk", "anormal", "abnormal", "irregular", "peligro", "danger",
    ]

    private func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX")).lowercased()
    }

    private var esBundle: Bundle? {
        Bundle.main.path(forResource: "es", ofType: "lproj").flatMap(Bundle.init(path:))
    }

    func testShippedCopyNamesNoConditionOrCTA_enAndEs() throws {
        let es = try XCTUnwrap(esBundle, "es.lproj must exist in the app bundle (bilingual app)")
        for key in RhythmCopy.allEnglishKeys {
            let english = key                                                   // key IS the en text
            let spanish = es.localizedString(forKey: key, value: key, table: nil)
            for term in banned {
                XCTAssertFalse(fold(english).contains(term),
                               "EN «\(english)» must not contain clinical term “\(term.trimmingCharacters(in: .whitespaces))”.")
                XCTAssertFalse(fold(spanish).contains(term),
                               "ES «\(spanish)» must not contain clinical term “\(term.trimmingCharacters(in: .whitespaces))”.")
            }
        }
    }

    /// Every key must actually be translated to es (no silent English fallback on a Spanish device).
    func testEveryKeyHasSpanishTranslation() throws {
        let es = try XCTUnwrap(esBundle)
        let sentinel = "\u{1}MISSING\u{1}"
        for key in RhythmCopy.allEnglishKeys {
            let value = es.localizedString(forKey: key, value: sentinel, table: nil)
            XCTAssertNotEqual(value, sentinel, "Missing es translation for «\(key)».")
        }
    }

    /// The disclaimer keeps its three honest negations in both languages.
    func testDisclaimerStatesTheThreeNots() throws {
        let es = try XCTUnwrap(esBundle)
        let d = fold(es.localizedString(forKey: RhythmCopy.disclaimerKey, value: "", table: nil))
        XCTAssertTrue(d.contains("experimental"))
        XCTAssertTrue(d.contains("no es un ecg"))
        XCTAssertTrue(d.contains("diagnostico"))
        XCTAssertTrue(d.contains("no detecta enfermedades"))
    }
}

private extension RhythmCopy {
    static let disclaimerKey = "Experimental · Not an ECG or a diagnosis · Doesn't detect disease."
}
