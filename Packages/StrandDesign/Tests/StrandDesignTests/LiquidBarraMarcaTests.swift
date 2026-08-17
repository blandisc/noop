import XCTest
import SwiftUI
@testable import StrandDesign

/// El contrato de `LiquidBarraMarca` en frío (sin render, sin simulador).
/// Run: swift test --filter LiquidBarraMarcaTests
///
/// Cubre las tres reglas de honestidad que el port hereda del papel
/// (`stageVsTypicalRow` del detalle de Sueño) y que son fáciles de romper sin notarlo:
/// sin base no se inventa marca, una fracción fuera de 0…1 no rompe el layout, y el
/// «más es mejor» tiñe el delta pero NO mueve el dibujo.
final class LiquidBarraMarcaTests: XCTestCase {

    /// El aire de la escala, replicado aquí a propósito: si alguien cambia el 1.18 del
    /// componente, estos números dejan de cuadrar y el test lo dice.
    private let aire = 1.18
    /// El tope al que llega SIEMPRE el elemento más grande de una fila: 1 / 1.18 ≈ 0.847.
    private var tope: Double { 1 / aire }

    // MARK: (a) Sin base todavía → no se dibuja marca

    /// Regla 2: `marca == nil` no pinta tick. Jamás una marca fantasma al 50 %.
    func test_sinBase_noHayMarca() {
        XCTAssertNil(LiquidBarraMarca.posicionMarca(fraccion: 0.22, marca: nil))
        XCTAssertNil(LiquidBarraMarca.posicionMarca(fraccion: 0, marca: nil))
        // Y tampoco hay delta: no hay contra qué comparar.
        XCTAssertNil(LiquidBarraMarca.deltaTexto(fraccion: 0.22, marca: nil))
    }

    /// Sin marca, el relleno se escala contra sí mismo: llega al tope de la fila, no al 100 %.
    func test_sinBase_elRellenoSigueTopandoEnElAire() {
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: 0.22, marca: nil),
                       tope, accuracy: 1e-9)
    }

    /// Base MEDIDA en cero ≠ sin base: el tick no se pinta (caería sobre el borde izquierdo,
    /// igual que en el papel) pero el delta SÍ se dice, porque el cero es un dato real.
    func test_baseEnCero_sinTickPeroConDelta() {
        XCTAssertNil(LiquidBarraMarca.posicionMarca(fraccion: 0.22, marca: 0))
        XCTAssertEqual(LiquidBarraMarca.deltaTexto(fraccion: 0.22, marca: 0), "+22")
    }

    /// Fila entera en cero y sin base: nada que dibujar, y sin dividir entre cero.
    func test_todoEnCero_noExplota() {
        XCTAssertEqual(LiquidBarraMarca.denominador(fraccion: 0, marca: nil), 1)
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: 0, marca: nil), 0)
        XCTAssertNil(LiquidBarraMarca.posicionMarca(fraccion: 0, marca: nil))
    }

    // MARK: (b) Fracciones fuera de 0…1 se clampean sin romper el layout

    /// Un ancho negativo o mayor que el disponible rompe el layout de SwiftUI. Pase lo que
    /// pase, relleno y marca viven en 0…1.
    func test_fueraDeRango_seClampea() {
        for (f, m) in [(1.4, 0.5), (-0.3, 0.5), (2.0, 3.0), (0.4, -1.0), (-1.0, -1.0)] {
            let ancho = LiquidBarraMarca.anchoRelleno(fraccion: f, marca: m)
            XCTAssertTrue((0...1).contains(ancho), "ancho fuera de 0…1 con (\(f), \(m)): \(ancho)")
            if let pos = LiquidBarraMarca.posicionMarca(fraccion: f, marca: m) {
                XCTAssertTrue((0...1).contains(pos), "marca fuera de 0…1 con (\(f), \(m)): \(pos)")
            }
        }
        // Clampeado, 1.4 se comporta como 1.0: sigue siendo el máximo de su fila.
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: 1.4, marca: 0.5),
                       tope, accuracy: 1e-9)
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: -0.3, marca: 0.5), 0)
    }

    /// NaN / infinito (una división por cero río arriba en el caller) valen 0, no un
    /// `frame(width: nan)` que revienta el render.
    func test_noFinitos_valenCero() {
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: .nan, marca: 0.2), 0)
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: .infinity, marca: 0.2), 0)
        XCTAssertNil(LiquidBarraMarca.posicionMarca(fraccion: 0.2, marca: .nan))
        XCTAssertEqual(LiquidBarraMarca.denominador(fraccion: .nan, marca: nil), 1)
    }

    // MARK: (c) La voz menciona el promedio SOLO cuando existe

    func test_a11yValue_mencionaElPromedioSoloSiExiste() {
        XCTAssertEqual(
            LiquidBarraMarca.a11yValue(anoche: "22 % anoche", tipico: "típico 18 %"),
            "22 % anoche, típico 18 %")
        let sinBase = LiquidBarraMarca.a11yValue(anoche: "22 % anoche", tipico: nil)
        XCTAssertEqual(sinBase, "22 % anoche")
        XCTAssertFalse(sinBase.contains("típico"),
                       "sin base, VoiceOver no puede hablar de un promedio que no existe")
    }

    // MARK: La escala es POR FILA (18 % de aire sobre el máximo)

    /// El máximo de cada fila —sea el relleno o la marca— llega SIEMPRE a ~84.7 %: es la
    /// firma visible de que cada barra tiene su propio denominador.
    func test_escalaPorFila_elMaximoTopaEnElAire() {
        // Anoche por ENCIMA del típico: manda el relleno.
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: 0.22, marca: 0.18),
                       tope, accuracy: 1e-9)
        XCTAssertEqual(LiquidBarraMarca.posicionMarca(fraccion: 0.22, marca: 0.18) ?? -1,
                       0.18 / (0.22 * aire), accuracy: 1e-9)
        // Anoche por DEBAJO: manda la marca, y ahora es ella la que topa.
        XCTAssertEqual(LiquidBarraMarca.posicionMarca(fraccion: 0.46, marca: 0.52) ?? -1,
                       tope, accuracy: 1e-9)
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: 0.46, marca: 0.52),
                       0.46 / (0.52 * aire), accuracy: 1e-9)
    }

    /// Dos filas de tamaños muy distintos llenan lo mismo: NO hay escala compartida. Si
    /// alguien «arregla» esto normalizando entre filas, el test lo caza.
    func test_escalaPorFila_noEsCompartida() {
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: 0.46, marca: 0.40),
                       LiquidBarraMarca.anchoRelleno(fraccion: 0.06, marca: 0.05),
                       accuracy: 1e-9)
    }

    // MARK: El delta (en puntos porcentuales, con el signo del papel)

    func test_delta_signoYRedondeo() {
        XCTAssertEqual(LiquidBarraMarca.deltaTexto(fraccion: 0.22, marca: 0.18), "+4")
        XCTAssertEqual(LiquidBarraMarca.deltaTexto(fraccion: 0.46, marca: 0.52), "−6")
        XCTAssertEqual(LiquidBarraMarca.deltaTexto(fraccion: 0.22, marca: 0.22), "~0")
        // Diferencia real pero menor a medio punto: se dice «~0», nunca «+0» ni «−0».
        XCTAssertEqual(LiquidBarraMarca.deltaTexto(fraccion: 0.223, marca: 0.22), "~0")
        XCTAssertEqual(LiquidBarraMarca.deltaTexto(fraccion: 0.217, marca: 0.22), "~0")
    }

    /// El menos es U+2212 (signo menos), no el guion U+002D: con guion, la tipografía
    /// tabular lo dibuja más corto y más alto que el «+».
    func test_delta_usaSignoMenosTipografico() {
        let negativo = LiquidBarraMarca.deltaTexto(fraccion: 0.46, marca: 0.52)
        XCTAssertEqual(negativo?.hasPrefix("\u{2212}"), true)
        XCTAssertEqual(negativo?.contains("-"), false)
    }

    // MARK: Regla 3 · el componente NO juzga

    /// `masEsMejor` (el `higherIsBetter` del papel) SOLO cambia el color del delta: ni el
    /// ancho del relleno, ni la posición de la marca, ni el texto del delta lo miran.
    func test_masEsMejor_soloTiñeElDelta() {
        // Despierto: 13 % anoche contra 6 % típico. Más NO es mejor → atención.
        XCTAssertTrue(LiquidBarraMarca.mejora(fraccion: 0.13, marca: 0.06, masEsMejor: true))
        XCTAssertFalse(LiquidBarraMarca.mejora(fraccion: 0.13, marca: 0.06, masEsMejor: false))
        // Y el dibujo es idéntico en los dos sentidos (las funciones ni siquiera lo reciben).
        XCTAssertEqual(LiquidBarraMarca.anchoRelleno(fraccion: 0.13, marca: 0.06),
                       tope, accuracy: 1e-9)
        XCTAssertEqual(LiquidBarraMarca.deltaTexto(fraccion: 0.13, marca: 0.06), "+7")
    }

    /// Empate: `>= 0` / `<= 0` — un delta de cero nunca se pinta de atención.
    func test_empate_nuncaEsAtencion() {
        XCTAssertTrue(LiquidBarraMarca.mejora(fraccion: 0.2, marca: 0.2, masEsMejor: true))
        XCTAssertTrue(LiquidBarraMarca.mejora(fraccion: 0.2, marca: 0.2, masEsMejor: false))
    }

    /// Sin base no hay juicio: el delta no se pinta, y el color por omisión se calla en verde.
    func test_sinBase_noHayJuicio() {
        XCTAssertTrue(LiquidBarraMarca.mejora(fraccion: 0.9, marca: nil, masEsMejor: false))
    }

    // MARK: La firma del contrato

    /// Guardia de COMPILACIÓN: la llamada canónica del caller (con `masEsMejor`/`indice`
    /// omitidos) debe seguir siendo válida. Si alguien reordena o renombra el init, este
    /// archivo deja de compilar — que es justo el aviso que se busca.
    @MainActor
    func test_init_aceptaLaFirmaDelContrato() {
        let barra: LiquidBarraMarca? = LiquidBarraMarca(
            etiqueta: "Profundo", fraccion: 0.22, marca: 0.18,
            tono: LiquidColor.indigo, valorTexto: "1:31 · 22 %",
            a11yLabel: "Profundo",
            a11yValue: LiquidBarraMarca.a11yValue(anoche: "22 % anoche", tipico: "típico 18 %"))
        XCTAssertNotNil(barra)
    }
}
