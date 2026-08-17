import XCTest
import SwiftUI
@testable import StrandDesign

/// `LiquidHipnograma` — la gramática de la noche, verificada EN FRÍO (sin montar la vista):
/// qué tramos existen, dónde caen, qué ancho miden y qué pasa cuando no hubo noche.
/// Run: swift test --filter LiquidHipnogramaTests
final class LiquidHipnogramaTests: XCTestCase {

    // MARK: Utilería

    /// Ancho útil de la hoja en un iPhone (≈402 pt menos el margen s550 y el eje de etapas)
    /// y el alto que monta el detalle de Sueño.
    private let lienzo = CGSize(width: 300, height: 176)
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Un tramo por minutos desde el arranque de la noche.
    private func tramo(_ etapa: LiquidHipnograma.Etapa,
                       _ desde: Double, _ hasta: Double) -> LiquidHipnograma.Intervalo {
        .init(inicio: base.addingTimeInterval(desde * 60),
              fin: base.addingTimeInterval(hasta * 60),
              etapa: etapa)
    }

    /// Noche contigua de 8 h con tramos holgados (el más corto, 20 min, mide 12.5 pt en el
    /// lienzo: muy por encima del piso de 2 pt, así que la proporción se lee limpia).
    private func nocheHolgada() -> [LiquidHipnograma.Intervalo] {
        [tramo(.despierto, 0, 20), tramo(.ligero, 20, 120), tramo(.profundo, 120, 240),
         tramo(.rem, 240, 330), tramo(.ligero, 330, 450), tramo(.despierto, 450, 480)]
    }

    // MARK: - (a) Un tramo de 0 minutos no existe

    /// El fallback diario de Apple fabrica etapas en 0 (`startTs == endTs`). Dibujarlas
    /// insinuaría una medición que nunca ocurrió — y en el hipnograma además dejaría una
    /// pastilla flotando en un carril donde no pasó nada.
    func test_tramoEnCero_noProduceBanda() {
        let conCeros = [tramo(.ligero, 0, 60),
                        tramo(.despierto, 60, 60),   // 0 minutos: no existe
                        tramo(.profundo, 60, 150),
                        tramo(.rem, 150, 150)]       // 0 minutos: no existe

        XCTAssertEqual(LiquidHipnograma.visibles(conCeros).count, 2)
        let bandas = LiquidHipnograma.bandas(conCeros, en: lienzo)
        XCTAssertEqual(bandas.count, 2, "solo los tramos MEDIDOS se dibujan")
        XCTAssertFalse(bandas.contains { $0.etapa == .despierto },
                       "«despierto 0 min» no puede aparecer en el carril de arriba")
        XCTAssertFalse(bandas.contains { $0.etapa == .rem })
    }

    /// Un tramo invertido (`fin < inicio`) es un dato roto, no un tramo negativo: se filtra
    /// igual que el de 0, en vez de dibujar una banda de ancho negativo.
    func test_tramoInvertido_noProduceBanda() {
        let roto = [tramo(.ligero, 0, 60), tramo(.profundo, 120, 90)]
        XCTAssertEqual(LiquidHipnograma.bandas(roto, en: lienzo).count, 1)
    }

    /// Los tramos llegan en cualquier orden y el componente los ordena: el span se toma del
    /// PRIMERO en tiempo, así que una lista revuelta desplazaría toda la noche.
    func test_visibles_ordenaPorInicio() {
        let revuelta = [tramo(.rem, 240, 330), tramo(.ligero, 20, 120), tramo(.despierto, 0, 20)]
        let orden = LiquidHipnograma.visibles(revuelta).map(\.etapa)
        XCTAssertEqual(orden, [.despierto, .ligero, .rem])
    }

    // MARK: - (b) El ancho ES la duración

    /// Cada banda mide su fracción de la noche, y las bandas de una noche contigua llenan el
    /// lienzo completo. Es el contrato del hipnograma: el ojo compara LARGOS.
    func test_anchos_proporcionalesALaDuracion() {
        let noche = nocheHolgada()
        let bandas = LiquidHipnograma.bandas(noche, en: lienzo)
        let total: TimeInterval = 480 * 60

        XCTAssertEqual(bandas.count, noche.count)
        for (banda, tramo) in zip(bandas, LiquidHipnograma.visibles(noche)) {
            let esperado = CGFloat(tramo.duracion / total) * lienzo.width
            XCTAssertEqual(banda.rect.width, esperado, accuracy: 0.01,
                           "el ancho de \(tramo.etapa) debe ser su fracción de la noche")
        }
        let suma = bandas.reduce(0) { $0 + $1.rect.width }
        XCTAssertEqual(suma, lienzo.width, accuracy: 0.01,
                       "una noche contigua llena el lienzo: ni hueco ni desborde")
        // Y se encadenan sin traslapes: el fin de una banda es el arranque de la siguiente.
        for (i, banda) in bandas.enumerated().dropFirst() {
            XCTAssertEqual(banda.rect.minX, bandas[i - 1].rect.maxX, accuracy: 0.01)
        }
    }

    /// El ÚNICO punto donde el ancho deja de ser proporcional, y siempre a favor de que la
    /// medición se vea: un despertar de 1 min en una noche de 8 h mediría 0.6 pt (invisible)
    /// y se pisa a 2. Por eso la prueba de proporcionalidad usa tramos holgados.
    func test_tramoDiminuto_seSostieneEnElPiso() throws {
        let noche = [tramo(.ligero, 0, 239), tramo(.despierto, 239, 240), tramo(.profundo, 240, 480)]
        let bandas = LiquidHipnograma.bandas(noche, en: lienzo)
        let despertar = try XCTUnwrap(bandas.first { $0.etapa == .despierto })
        XCTAssertEqual(despertar.rect.width, 2, accuracy: 0.01,
                       "el piso de 2 pt mantiene visible un tramo real diminuto")
    }

    // MARK: - (c) Sin noche no se inventa nada

    func test_listaVacia_noDibujaNadaNiRevienta() {
        XCTAssertTrue(LiquidHipnograma.visibles([]).isEmpty)
        XCTAssertTrue(LiquidHipnograma.bandas([], en: lienzo).isEmpty)
        XCTAssertNil(LiquidHipnograma.ventana([]))
        XCTAssertNil(LiquidHipnograma.indice(atX: 150, en: lienzo, intervalos: []))
    }

    /// Una lista que SOLO trae tramos en 0 es igual de vacía: es el fallback diario de Apple
    /// disfrazado de noche.
    func test_todoEnCero_esUnaNocheVacia() {
        let ceros = [tramo(.ligero, 0, 0), tramo(.profundo, 0, 0), tramo(.rem, 30, 30)]
        XCTAssertTrue(LiquidHipnograma.bandas(ceros, en: lienzo).isEmpty)
        XCTAssertNil(LiquidHipnograma.indice(atX: 10, en: lienzo, intervalos: ceros))
    }

    /// Un lienzo degenerado (ancho 0 durante el primer layout) no debe reventar ni fabricar
    /// un índice.
    func test_lienzoSinAncho_noProduceIndice() {
        XCTAssertNil(LiquidHipnograma.indice(atX: 0, en: .zero, intervalos: nocheHolgada()))
    }

    // MARK: - Carriles: la gramática del hipnograma

    /// Despierto ARRIBA, profundo ABAJO. No es una decisión del caller: es cómo se lee una
    /// noche (paridad `SleepStage.bandRank`).
    func test_ordenDeCarriles_despiertoArribaProfundoAbajo() {
        XCTAssertEqual(LiquidHipnograma.Etapa.ordenVertical,
                       [.despierto, .rem, .ligero, .profundo])
        XCTAssertEqual(LiquidHipnograma.Etapa.despierto.carril, 0)
        XCTAssertEqual(LiquidHipnograma.Etapa.rem.carril, 1)
        XCTAssertEqual(LiquidHipnograma.Etapa.ligero.carril, 2)
        XCTAssertEqual(LiquidHipnograma.Etapa.profundo.carril, 3)

        let bandas = LiquidHipnograma.bandas(nocheHolgada(), en: lienzo)
        let yDespierto = bandas.first { $0.etapa == .despierto }?.rect.midY ?? 0
        let yProfundo = bandas.first { $0.etapa == .profundo }?.rect.midY ?? 0
        XCTAssertLessThan(yDespierto, yProfundo, "despierto vive arriba de profundo")
    }

    /// Cada carril se centra en su cuarto del alto (12.5 / 37.5 / 62.5 / 87.5 %), y la banda
    /// mide 22 pt centrados en esa guía.
    func test_carriles_centradosEnSuCuarto() {
        for (carril, fraccion) in [(0, 0.125), (1, 0.375), (2, 0.625), (3, 0.875)] {
            XCTAssertEqual(LiquidHipnograma.rowY(carril, alto: lienzo.height),
                           CGFloat(fraccion) * lienzo.height, accuracy: 0.01)
        }
        let banda = LiquidHipnograma.bandas([tramo(.rem, 0, 60)], en: lienzo)[0]
        XCTAssertEqual(banda.rect.height, 22, accuracy: 0.01)
        XCTAssertEqual(banda.rect.midY,
                       LiquidHipnograma.rowY(1, alto: lienzo.height), accuracy: 0.01)
    }

    // MARK: - Scrub: contención exacta, y si no, el vecino más cercano

    func test_scrub_contencionExacta() {
        let noche = nocheHolgada()   // 480 min → 300 pt: 1 min = 0.625 pt
        // 200 min de la noche = x 125: cae dentro de `profundo` (120→240), el tercer tramo.
        XCTAssertEqual(LiquidHipnograma.indice(atX: 125, en: lienzo, intervalos: noche), 2)
        // Los bordes del lienzo aterrizan en el primer y el último tramo.
        XCTAssertEqual(LiquidHipnograma.indice(atX: 0, en: lienzo, intervalos: noche), 0)
        XCTAssertEqual(LiquidHipnograma.indice(atX: lienzo.width, en: lienzo, intervalos: noche),
                       noche.count - 1)
    }

    /// El dedo en un HUECO de la noche (un tramo que el filtro se llevó, o una noche con
    /// registro interrumpido) no se queda sin respuesta: salta al tramo cuyo centro está más
    /// cerca en el tiempo.
    func test_scrub_enElHueco_saltaAlCentroMasCercano() {
        // 0–60 profundo · [hueco 60–90] · 90–120 rem. Span 120 min sobre 300 pt.
        let conHueco = [tramo(.profundo, 0, 60), tramo(.rem, 90, 120)]
        // t = 75 min (x 187.5): equidistante-ish, pero el centro de rem (105) queda a 30 min
        // y el de profundo (30) a 45 → gana rem.
        XCTAssertEqual(LiquidHipnograma.indice(atX: 187.5, en: lienzo, intervalos: conHueco), 1)
        // t = 65 min (x 162.5): centro de profundo a 35 min, el de rem a 40 → gana profundo.
        XCTAssertEqual(LiquidHipnograma.indice(atX: 162.5, en: lienzo, intervalos: conHueco), 0)
    }

    /// El índice que publica el scrub es sobre la lista YA filtrada y ordenada — si contara
    /// sobre la lista cruda, un tramo en 0 desfasaría el anillo a la banda vecina.
    func test_scrub_indexaLaListaVisible() {
        let conCero = [tramo(.despierto, 0, 0),      // se filtra
                       tramo(.profundo, 0, 60),      // visible 0
                       tramo(.rem, 60, 120)]         // visible 1
        let i = LiquidHipnograma.indice(atX: 250, en: lienzo, intervalos: conCero)
        XCTAssertEqual(i, 1)
        XCTAssertEqual(LiquidHipnograma.visibles(conCero)[i ?? 0].etapa, .rem)
    }
}
