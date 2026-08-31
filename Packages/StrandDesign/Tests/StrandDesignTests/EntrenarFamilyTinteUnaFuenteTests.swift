import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-88 — el tinte de familia estaba definido TRES veces y una de las tres se había ido por su
/// lado: `EntrenarFamily.tint` decía `dataSteps` (#4C8998) para tirón mientras `RoutineRegion.tint`
/// y `movementFamilyTint` decían `dataHrv` (#147C8C). El mismo tirón salía de dos colores según
/// quién lo dibujara — que es exactamente lo que la caja de piezas existía para impedir.
///
/// Estas pruebas no comprueban «que se vea bien»: comprueban que solo hay UNA tabla, y que la
/// clasificación por músculo sigue diciendo lo mismo que antes de separarla del color.
final class EntrenarFamilyTinteUnaFuenteTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// Igualdad de color por componentes, no por luminancia: dos colores distintos pueden compartir
    /// luminancia y colarse por una comparación floja.
    private func mismoColor(_ a: Color, _ b: Color) -> Bool {
        let x = a.rgbaComponents, y = b.rgbaComponents
        return abs(x.r - y.r) < 1e-6 && abs(x.g - y.g) < 1e-6 && abs(x.b - y.b) < 1e-6
    }

    /// LA TABLA, clavada por valor. Esta es la prueba que de verdad puede fallar: si alguien cambia
    /// el color de una familia, truena aquí y tiene que ser una decisión, no un descuido.
    ///
    /// Un intento anterior comparaba el puente contra la familia — y como el puente ya DELEGA en la
    /// familia, la igualdad se cumplía sola: la prueba no podía reprobar. El canario lo destapó.
    func testLaTablaDeTintesEsLaQueSeAcordo() {
        let esperado: [(EntrenarFamily, Color, String)] = [
            (.push,     theme.dataStrain, "ámbar"),
            (.pull,     theme.dataHrv,    "cian"),
            (.legs,     theme.dataSleep,  "índigo"),
            (.fullBody, theme.dataSleep,  "índigo"),
        ]
        for (familia, token, nombre) in esperado {
            XCTAssertTrue(mismoColor(familia.tint(theme), token),
                          "\(familia) dejó de ser \(nombre)")
        }
        // Y el que se había ido por su lado: tirón NO es `dataSteps` (#4C8998). Lo fue en el
        // paquete mientras la app pintaba `dataHrv`, y ese desacuerdo es el defecto que FER-88 cerró.
        XCTAssertFalse(mismoColor(EntrenarFamily.pull.tint(theme), theme.dataSteps),
                       "tirón volvió a dataSteps: la tabla se re-bifurcó")
    }

    /// El puente por músculos no tiene tabla propia: clasifica y delega. Lo que se comprueba aquí es
    /// la CLASIFICACIÓN, que sí es lógica suya y sí puede romperse.
    func testElPuenteClasificaCadaMusculoEnSuFamilia() {
        let casos: [(String, EntrenarFamily)] = [
            ("lats", .pull), ("back", .pull), ("biceps", .pull), ("traps", .pull), ("forearms", .pull),
            ("quadriceps", .legs), ("hamstrings", .legs), ("glutes", .legs), ("calves", .legs),
            ("abductors", .legs), ("adductors", .legs),
            ("chest", .push), ("shoulders", .push), ("triceps", .push),
        ]
        for (musculo, esperada) in casos {
            XCTAssertEqual(theme.movementFamily(primaryMuscles: [musculo]), esperada, musculo)
        }
    }

    /// Sin músculos clasificables cae a empuje, igual que antes de la unificación: es el
    /// comportamiento que ya estaba en pantalla y no se cambia de contrabando.
    func testSinMusculosClasificablesCaeAEmpuje() {
        XCTAssertEqual(theme.movementFamily(primaryMuscles: []), .push)
        XCTAssertEqual(theme.movementFamily(primaryMuscles: ["cardio", "unknown"]), .push)
    }

    /// Las cuatro familias son distinguibles entre sí, salvo el par que el diseño decidió compartir
    /// (pierna y cuerpo completo van en el mismo índigo). Sin esto, unificar la tabla podría
    /// aplanar dos identidades en una sin que nadie lo notara.
    func testLasFamiliasSonDistinguiblesSalvoElParQueComparteIndigo() {
        XCTAssertTrue(mismoColor(EntrenarFamily.legs.tint(theme), EntrenarFamily.fullBody.tint(theme)),
                      "pierna y completo comparten índigo por diseño")
        let pares: [(EntrenarFamily, EntrenarFamily)] = [(.push, .pull), (.push, .legs), (.pull, .legs)]
        for (a, b) in pares {
            XCTAssertFalse(mismoColor(a.tint(theme), b.tint(theme)), "\(a) y \(b) tienen que distinguirse")
        }
    }

    /// El par obligatorio: el hue es para bolitas y numerales grandes; el tono de LECTURA es el que
    /// puede tocar texto. Las cuatro familias tienen que cumplir AA en su tono de lectura.
    func testElTonoDeLecturaDeCadaFamiliaCumpleAA() {
        for f in EntrenarFamily.allCases {
            XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(f.reading(theme), theme.paper), 4.5, "\(f)")
        }
    }
}

/// FER-86 — el punto de identidad de familia dejó de estar copiado seis veces en crudo por la app.
/// Estas pruebas clavan lo único que un componente compartido puede prometer y que una copia no:
/// que hay UN tamaño, y que el aro que lo recorta es de verdad más grande que el punto.
final class EntrenarFamilyDotTests: XCTestCase {

    /// Antes de FER-86 el mismo punto se dibujaba a 8 pt en tres sitios y a 9 en otros tres. Si
    /// alguien vuelve a acuñar un segundo tamaño, que sea una decisión y no un descuido.
    func testHayUnSoloTamanoDePunto() {
        XCTAssertEqual(EntrenarMetrics.familyDot, 9)
    }

    /// El aro de papel existe para RECORTAR el punto sobre un fondo ocupado: si no fuera mayor, no
    /// recortaría nada y la variante «sobreFondo» sería decorativa.
    func testElAroRecortaDeVerdad() {
        XCTAssertGreaterThan(EntrenarMetrics.familyDotKnockout, EntrenarMetrics.familyDot)
    }

    /// El punto es una marca de identidad, no un blanco táctil: nunca debe crecer hasta parecer un
    /// control. Si algún día lo necesita, va envuelto en una fila de 44, no inflado.
    func testElPuntoNoPretendeSerUnControl() {
        XCTAssertLessThan(EntrenarMetrics.familyDotKnockout, EntrenarMetrics.row)
    }
}

/// FER-86 — la barra de la sesión pinta tres cifras a 17 pt, por debajo del piso de 24 en que el
/// ADN permite el hue saturado. El pulso venía en `dataHeart` crudo (4.24:1 sobre el papel) con un
/// comentario que se justificaba diciendo «el numeral es grande». No lo es.
final class SessionStatsBarContrasteTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// El hue crudo del pulso REPRUEBA. Si algún día pasara, esta prueba avisa que el ancla se
    /// movió y que el tono de lectura quizá ya no haga falta — no que se pueda usar el crudo.
    func testElHueCrudoDelPulsoNoAlcanzaElPisoDeTexto() {
        XCTAssertLessThan(OKLab.contrastRatio(theme.dataHeart, theme.paper), 4.5,
                          "dataHeart ya cumple AA: revisar si la barra todavía necesita oscurecerlo")
    }

    /// Y su tono de lectura sí, que es el que la barra usa.
    func testElTonoDeLecturaDelPulsoCumpleAA() {
        let lectura = theme.onPaper(theme.dataHeart)
        XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(lectura, theme.paper), 4.5)
        XCTAssertLessThan(OKLab.relativeLuminance(lectura), OKLab.relativeLuminance(theme.dataHeart),
                          "el tono de lectura tiene que ser más oscuro que su hue")
    }

    /// Las otras dos cifras de la barra son tinta, no hue: ahí no hay nada que oscurecer, pero sí
    /// que comprobar, porque son las que se leen a media serie.
    func testLasCifrasDeTintaDeLaBarraCumplenAA() {
        for (nombre, c) in [("ink", theme.ink), ("inkSecondary", theme.inkSecondary)] {
            XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(c, theme.paper), 4.5, nombre)
        }
    }
}

/// FER-86 — el botón «Empezar» del héroe se teñía con el hue de familia y pintaba su etiqueta en
/// papel encima. La etiqueta de `StrandCTAButton` se calibró contra el fondo de TINTA por omisión,
/// y nadie recalculó el par cuando un tinte lo sustituye. Decisión del dueño: como el handoff,
/// verde. Estas pruebas clavan por qué, con números y no con gusto.
final class BotonEmpezarContrasteTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// El defecto es REAL pero más angosto de lo que yo afirmé: de los tres tintes, solo el ÁMBAR
    /// de empuje reprueba como fondo de una etiqueta clara (3.87:1). El cian de tirón (4.61) y el
    /// índigo de pierna (5.78) sí pasan.
    ///
    /// O sea: el botón mentía su contraste SOLO en los días de empuje. Eso no lo salva —un día de
    /// cada tres con el texto por debajo del piso sigue siendo un defecto— pero decirlo como «los
    /// tres fallan» habría sido exagerar para justificar la decisión. La prueba clava el hecho
    /// exacto, y truena si algún día otro tinte cruza el piso en cualquier dirección.
    func testSoloElAmbarDeEmpujeReprobabaComoFondoDeTextoClaro() {
        let reprueban = EntrenarFamily.allCases.filter {
            OKLab.contrastRatio(theme.paperHi, $0.tint(theme)) < 4.5
        }
        XCTAssertEqual(reprueban, [.push],
                       "cambió qué familias reprueban como fondo: revisar la decisión del botón")
    }

    /// Y el verde del handoff sí: es el verde del veredicto ya oscurecido hasta cumplir contraste
    /// de texto, así que el mismo token sirve de fondo con etiqueta clara.
    func testElVerdeDelHandoffSiSirve() {
        XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(theme.paperHi, theme.positiveText), 4.5)
    }

    /// Es el MISMO verde de «avanza» de la app, no uno nuevo: `positiveText` deriva de `verdict`.
    /// Un verde inventado para este botón sería una cuarta voz de color en la sección.
    func testEsElVerdeDeLaAppYNoUnoNuevo() {
        XCTAssertLessThan(OKLab.relativeLuminance(theme.positiveText),
                          OKLab.relativeLuminance(theme.verdict),
                          "positiveText tiene que ser el verdict oscurecido, no un token suelto")
    }
}
