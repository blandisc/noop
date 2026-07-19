import XCTest
@testable import Cenit
import StrandTraining

/// Fija la regla de formato de peso en UN solo lugar.
///
/// Contexto (2026-07-19): había TRES formateadores —`StrengthDisplay`, uno privado en
/// `LiveStrengthSheet` y otro en `ReceiptMapping`— y los tres se habían desfasado en imperial: dos
/// conservaban el decimal donde el primero redondea. La MISMA serie de 82.5 kg se leía «182 lb» al
/// editar la rutina y «181.9 lb» al entrenarla. No era estética: era el mismo número contradiciéndose.
/// Estos tests existen para que la próxima copia se caiga aquí y no en la pantalla del usuario.
final class StrengthDisplayWeightTests: XCTestCase {

    // MARK: - Imperial: entero, siempre

    func testImperialRoundsToWholePounds() {
        // 82.5 kg = 181.88 lb. El decimal es precisión falsa: ninguna barra se arma con 181.9 lb.
        XCTAssertEqual(StrengthDisplay.weightNumber(82.5, system: .imperial), "182")
    }

    func testImperialRoundsUpAndDownAtTheHalf() {
        // 100 kg = 220.46 lb → 220 ; 100.5 kg = 221.56 lb → 222
        XCTAssertEqual(StrengthDisplay.weightNumber(100, system: .imperial), "220")
        XCTAssertEqual(StrengthDisplay.weightNumber(100.5, system: .imperial), "222")
    }

    /// El viaje kg↔lb no es exacto: 5 lb guardadas como kg y convertidas de vuelta dan 4.999999…, que
    /// NO es igual a su propio `rounded()`. Sin normalizar, «±5» se imprimía «±5.0» y 2.5 lb caían a
    /// «2» en vez de «3». Estos tests cazaron ese bug; existen para que no regrese.
    func testRoundTripNoiseDoesNotLeakIntoTheOutput() {
        for pounds in [2.5, 5.0, 10.0, 45.0, 135.0] {
            let kg = pounds * 0.45359237
            let s = StrengthDisplay.incrementNumber(kg, system: .imperial)
            XCTAssertFalse(s.hasSuffix(".0"), "«\(s)» arrastra el ruido del round-trip para \(pounds) lb")
        }
    }

    func testImperialNeverEmitsADecimalPoint() {
        for kg in stride(from: 1.25, through: 200.0, by: 1.25) {
            let s = StrengthDisplay.weightNumber(kg, system: .imperial)
            XCTAssertFalse(s.contains("."), "«\(s)» trae decimal para \(kg) kg — en libras se cuenta entero")
        }
    }

    // MARK: - Métrico: un decimal solo si hace falta

    func testMetricKeepsTheHalfPlate() {
        XCTAssertEqual(StrengthDisplay.weightNumber(82.5, system: .metric), "82.5")
        XCTAssertEqual(StrengthDisplay.weightNumber(2.5, system: .metric), "2.5")
    }

    func testMetricDropsTheTrailingZero() {
        XCTAssertEqual(StrengthDisplay.weightNumber(80, system: .metric), "80")
        XCTAssertEqual(StrengthDisplay.weightNumber(0, system: .metric), "0")
    }

    // MARK: - `displayNumber` formatea valores YA convertidos con la MISMA regla

    func testDisplayNumberMatchesWeightNumberOnConvertedValues() {
        // Es el invariante que se rompió: las superficies que ya traen el valor convertido (celdas,
        // discos, ±paso) deben leer igual que las que parten de kg.
        for kg in [1.25, 2.5, 20.0, 60.0, 82.5, 100.0, 142.5] {
            let viaKg = StrengthDisplay.weightNumber(kg, system: .imperial)
            let viaConverted = StrengthDisplay.displayNumber(UnitFormatter.kgToPounds(kg), system: .imperial)
            XCTAssertEqual(viaKg, viaConverted, "desacuerdo en \(kg) kg: «\(viaKg)» contra «\(viaConverted)»")
        }
    }

    func testWeightAppendsTheUnit() {
        XCTAssertEqual(StrengthDisplay.weight(82.5, system: .metric), "82.5 kg")
        XCTAssertEqual(StrengthDisplay.weight(82.5, system: .imperial), "182 lb")
    }

    // MARK: - Un INCREMENTO no se redondea como un peso absoluto

    func testIncrementKeepsItsDecimalInPounds() {
        // El micro-disco más común de un gimnasio imperial es 2.5 lb. Con la regla de peso absoluto se
        // leería «+3 lb» — 20 % más de lo que la app va a subir de verdad. Ese es el bug que separa
        // `incrementNumber` de `weightNumber`.
        let twoAndHalfPoundsInKg = 2.5 * 0.45359237
        XCTAssertEqual(StrengthDisplay.incrementNumber(twoAndHalfPoundsInKg, system: .imperial), "2.5")
    }

    func testTheTwoRulesDisagreeOnPurpose() {
        // El contraste que justifica que existan dos reglas, en un valor lejos del filete .5 (donde el
        // ruido del round-trip decide el redondeo y el test no probaría nada estable).
        XCTAssertEqual(StrengthDisplay.weightNumber(1.25, system: .imperial), "3",   // 2.76 lb → entero
                       "el peso ABSOLUTO redondea")
        XCTAssertEqual(StrengthDisplay.incrementNumber(1.25, system: .imperial), "2.8",
                       "el INCREMENTO conserva el decimal — si esto cambia, las dos reglas se confundieron")
    }

    func testIncrementKeepsTheHalfPlateInKilos() {
        XCTAssertEqual(StrengthDisplay.incrementNumber(2.5, system: .metric), "2.5")
        XCTAssertEqual(StrengthDisplay.incrementNumber(5, system: .metric), "5")
    }

    func testTheFivePoundStepReadsCleanInBothUnits() {
        // El paso imperial son 5 lb exactas guardadas en kg: no debe aparecer «5.0» ni «6».
        XCTAssertEqual(StrengthDisplay.incrementNumber(5 * 0.45359237, system: .imperial), "5")
        XCTAssertEqual(StrengthDisplay.incrementNumber(2.5, system: .metric), "2.5")
    }

    // MARK: - La rampa de calentamiento es una sola regla

    func testWarmupRampIsOneRule() {
        // Estaba escrita a mano en tres pantallas. Si cambia, debe cambiar UNA vez.
        XCTAssertEqual(RoutineSetEditing.warmupFactors, [0.4, 0.6, 0.8])
        XCTAssertEqual(RoutineSetEditing.warmupReps, 10)
    }
}
