import XCTest
@testable import Cenit

// OnboardingPluralesTests — FER-142 (deuda ONB-01 declarada en FER-141).
//
// Las tres frases del acto 4 interpolaban varios números con «%lld» crudo y SIN variación de
// plural, así que en N=1 rompían la gramática en los dos idiomas: «1 nights», «1 noches»,
// «1 días». El arreglo las pasó al formato de diccionario de sustitución del catálogo (tokens
// %1$#@days@ + un bloque `substitutions` con one/other por token). `String(localized:)` devuelve
// la plantilla con esos tokens y `String(format:)` los expande contra los argumentos — que es
// justo lo que ya hacen los call sites de `OnbCopy`, sin tocar Swift.
//
// El español NO se puede leer con `String(localized:)`: la suite corre en inglés y resolvería el
// valor `en`, así que una aserción sobre frases en español pasaría en vacío (la lección de
// PreparacionDetalleModeloTests). Por eso el español se lee del bundle `es.lproj` a mano y se
// formatea igual que `OnbCopy`.
final class OnboardingPluralesTests: XCTestCase {

    /// La plantilla ESPAÑOL tal como la compiló el catálogo (con los tokens de sustitución),
    /// formateada igual que `OnbCopy`: `String(format:)` expande los `%#@…@` contra los args.
    private func es(_ clave: String, _ args: CVarArg...) throws -> String {
        let ruta = try XCTUnwrap(Bundle.main.path(forResource: "es", ofType: "lproj"),
                                 "el bundle no trae español")
        let bundleES = try XCTUnwrap(Bundle(path: ruta))
        let plantilla = bundleES.localizedString(forKey: clave, value: "‹AUSENTE›", table: nil)
        XCTAssertNotEqual(plantilla, "‹AUSENTE›", "la clave \(clave) no llegó al catálogo español")
        return String(format: plantilla, arguments: args)
    }

    // MARK: onb.4.historia (días, noches)

    func testHistoriaSingularNoche() throws {
        // El call site real, en el idioma de la suite: con 1 noche jamás el plural.
        let real = OnbCopy.lecturaHistoria(dias: 30, noches: 1)
        XCTAssertFalse(real.contains("1 noches") || real.contains("1 nights"),
                       "acto 4 · historia con 1 noche no puede decir el plural: «\(real)»")

        let uno = try es("onb.4.historia", 30, 1)
        XCTAssertTrue(uno.contains("1 noche con"), "es N=1 → «1 noche»: «\(uno)»")
        XCTAssertFalse(uno.contains("1 noches"))
    }

    func testHistoriaPluralNoches() throws {
        let tres = try es("onb.4.historia", 30, 3)
        XCTAssertTrue(tres.contains("3 noches con"), "es N=3 → «3 noches»: «\(tres)»")
        XCTAssertTrue(tres.contains("tus 30 días"), "días>1 usa el posesivo plural «tus»: «\(tres)»")
    }

    // MARK: onb.4.calibrando.cuerpo (días, noches, meta) — meta es un número pelón, nunca 1

    func testCalibrandoCuerpoSingularNocheMetaPelon() throws {
        let real = OnbCopy.calibrandoCuerpo(dias: 3, noches: 1, meta: 60)
        XCTAssertFalse(real.contains("1 noches") || real.contains("1 nights"),
                       "calibrando con 1 noche no puede pluralizar: «\(real)»")

        let uno = try es("onb.4.calibrando.cuerpo", 3, 1, 60)
        XCTAssertTrue(uno.contains("llevo 1 noche con"), "es N=1 → «1 noche»: «\(uno)»")
        XCTAssertFalse(uno.contains("1 noches"))
        // La meta (60) se interpola tal cual: token de sustitución mezclado con un %lld directo.
        XCTAssertTrue(uno.contains("junte 60"), "la meta se interpola sin plural: «\(uno)»")
    }

    // MARK: onb.4.calibrando.cuerpo.sinhoy (días, noches) — el posesivo español concuerda con N

    func testSinHoySingularConcuerdaPosesivo() throws {
        let real = OnbCopy.calibrandoCuerpoSinHoy(dias: 1, noches: 1)
        XCTAssertFalse(real.contains("1 nights") || real.contains("1 noches")
                       || real.contains("1 days") || real.contains("1 días"),
                       "sinhoy con 1 día / 1 noche no puede pluralizar nada: «\(real)»")

        let uno = try es("onb.4.calibrando.cuerpo.sinhoy", 1, 1)
        // «tus 1 noche» sería el defecto del posesivo; en singular es «tu 1 día … tu 1 noche».
        XCTAssertTrue(uno.contains("tu 1 día") && uno.contains("tu 1 noche"),
                      "es N=1 concuerda el posesivo singular: «\(uno)»")
        XCTAssertFalse(uno.contains("tus 1"), "«tus 1» es el defecto de concordancia: «\(uno)»")
    }

    func testSinHoyPluralUsaPosesivoPlural() throws {
        let varios = try es("onb.4.calibrando.cuerpo.sinhoy", 30, 5)
        XCTAssertTrue(varios.contains("tus 30 días") && varios.contains("tus 5 noches"),
                      "es N>1 usa «tus … días» y «tus … noches»: «\(varios)»")
    }
}
