import XCTest
@testable import Cenit

// MARK: - OnboardingPerfilTests (FER-113)
//
// El acto del perfil se precarga desde Apple Salud campo por campo, y aplica SOLO lo que cae en el
// rango que el formulario admite. Dos reglas que estos fixtures fijan:
//
//   · **Parcial es lo normal.** Salud casi siempre tiene sexo y fecha de nacimiento, y muy seguido
//     no tiene peso ni estatura. Que falte uno no puede tumbar a los otros tres.
//   · **Fuera de rango se DESCARTA, no se recorta.** Un peso de 12 kg es un dato equivocado, no un
//     peso bajo: recortarlo a 30 kg inventaría una medición que nadie hizo, y encima la pantalla
//     la sellaría como «Desde Apple Salud».

final class OnboardingPerfilTests: XCTestCase {

    private func deSalud(edad: Int? = nil, sexo: String? = nil,
                         peso: Double? = nil, estatura: Double? = nil) -> OnbPerfilDeSalud {
        OnbPerfilDeSalud(edad: edad, sexo: sexo, pesoKg: peso, estaturaCm: estatura)
    }

    // MARK: Lo que sí se aplica

    func testAplicaLosCuatroCamposEnRango() {
        let s = deSalud(edad: 34, sexo: "female", peso: 62.4, estatura: 165)
        XCTAssertEqual(s.edad, 34)
        XCTAssertEqual(s.sexo, "female")
        XCTAssertEqual(s.pesoKg, 62.4)
        XCTAssertEqual(s.estaturaCm, 165)
    }

    /// Los extremos ENTRAN: el rango del autollenado es exactamente el del `Stepper`, así que un
    /// valor que el formulario deja poner a mano no puede ser rechazado viniendo de Salud.
    func testLosLimitesSonInclusivos() {
        let bajo = deSalud(edad: 13, peso: 30, estatura: 120)
        XCTAssertEqual(bajo.edad, 13)
        XCTAssertEqual(bajo.pesoKg, 30)
        XCTAssertEqual(bajo.estaturaCm, 120)

        let alto = deSalud(edad: 100, peso: 250, estatura: 230)
        XCTAssertEqual(alto.edad, 100)
        XCTAssertEqual(alto.pesoKg, 250)
        XCTAssertEqual(alto.estaturaCm, 230)
    }

    // MARK: Lo que se descarta

    func testDescartaFueraDeRangoSinRecortar() {
        let s = deSalud(edad: 8, peso: 12, estatura: 40)
        XCTAssertNil(s.edad)
        XCTAssertNil(s.pesoKg)
        XCTAssertNil(s.estaturaCm)

        let arriba = deSalud(edad: 130, peso: 400, estatura: 260)
        XCTAssertNil(arriba.edad)
        XCTAssertNil(arriba.pesoKg)
        XCTAssertNil(arriba.estaturaCm)
    }

    /// Un sexo que `ProfileStore` no entiende dejaría el selector sin ningún segmento marcado.
    func testDescartaUnSexoQueElSelectorNoTiene() {
        XCTAssertNil(deSalud(sexo: "unknown").sexo)
        XCTAssertNil(deSalud(sexo: "").sexo)
        XCTAssertEqual(deSalud(sexo: "nonbinary").sexo, "nonbinary")
    }

    // MARK: Parcial

    func testUnCampoInvalidoNoTumbaALosOtros() {
        let s = deSalud(edad: 34, sexo: "male", peso: 9, estatura: 178)
        XCTAssertEqual(s.edad, 34)
        XCTAssertEqual(s.sexo, "male")
        XCTAssertNil(s.pesoKg, "el peso imposible se descarta")
        XCTAssertEqual(s.estaturaCm, 178, "y la estatura sigue llegando")
    }

    func testSaludVaciaNoProponeNada() {
        let s = deSalud()
        XCTAssertNil(s.edad)
        XCTAssertNil(s.sexo)
        XCTAssertNil(s.pesoKg)
        XCTAssertNil(s.estaturaCm)
    }
}
