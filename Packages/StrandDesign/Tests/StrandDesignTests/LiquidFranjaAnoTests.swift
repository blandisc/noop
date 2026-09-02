import XCTest
import SwiftUI
@testable import StrandDesign

/// Las dos promesas caras de `LiquidFranjaAno`, en frío (sin simulador):
///
///  a) **El año entra completo.** A los anchos reales del teléfono (320 / 390 / 430 pt) las 53
///     columnas caben dentro del ancho disponible, sin recortar un solo mes. Un año recortado es
///     un año que miente, así que la franja comprime la celda antes que cortar.
///  b) **Sin dato no se pinta el tono.** `intensidad: nil` no produce alfa: esa celda va en track
///     neutro. Y un día MEDIDO en el mínimo sigue pintando (alfa piso 0.20), para que el hueco y
///     el mínimo nunca se confundan.
///
/// Run: `swift test --filter LiquidFranjaAnoTests`
final class LiquidFranjaAnoTests: XCTestCase {

    /// Anchos de pantalla reales del iPhone (mini / estándar / Max), sin descontar márgenes —
    /// el caso más apretado que la franja puede recibir.
    private let anchosTelefono: [CGFloat] = [320, 390, 430]

    /// Un año contiguo de 365 días que arranca `offsetDias` después del 1 de enero, en el MISMO
    /// calendario que usa el componente — así la fila de la primera celda es la de verdad,
    /// corra la prueba en la zona horaria que corra.
    private func anioDeMuestra(offsetDias: Int, conDato: Bool = true) -> [LiquidFranjaAno.Dia] {
        let cal = LiquidFranjaAno.calendarioSemanal()
        let base = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let inicio = cal.date(byAdding: .day, value: offsetDias, to: base)!
        return (0..<365).map { i in
            let fecha = cal.date(byAdding: .day, value: i, to: inicio)!
            return .init(fecha: fecha, intensidad: conDato ? Double(i % 101) / 100.0 : nil)
        }
    }

    // MARK: (a) El año entra sin recorte

    /// El caso que importa: 365 días a 320 / 390 / 430 pt, arrancando en CUALQUIER día de la
    /// semana. La franja dibujada nunca es más ancha que el espacio que le dieron, siempre
    /// dibuja sus 53 columnas, y la celda nunca cae por debajo del piso.
    func test_elAnioEntraSinRecorteALosAnchosDelTelefono() {
        for offset in 0..<7 {
            let dias = anioDeMuestra(offsetDias: offset)
            let columnas = LiquidFranjaAno.columnas(para: dias)
            XCTAssertEqual(columnas, 53, "un año siempre ocupa 53 columnas (offset \(offset))")

            for ancho in anchosTelefono {
                let m = LiquidFranjaAno.medidas(columnas: columnas, ancho: ancho,
                                                gutterPermitido: true, conMeses: true)
                XCTAssertLessThanOrEqual(
                    m.ancho, ancho + 0.5,
                    "la franja se sale del ancho \(ancho) (offset \(offset)): \(m.ancho)")
                XCTAssertEqual(m.columnas, 53,
                               "no se puede recortar una columna para que quepa (\(ancho))")
                XCTAssertGreaterThanOrEqual(
                    m.celda, LiquidFranjaAno.celdaMinima,
                    "la celda cayó bajo el piso a \(ancho) pt (offset \(offset))")
            }
        }
    }

    /// El mismo contrato, barrido fino: de 300 a 440 pt no hay un solo ancho donde la franja
    /// se derrame (los anchos de pantalla no son los únicos: dentro de una tarjeta con márgenes
    /// llega cualquier número).
    func test_ningunAnchoIntermedioDerramaLaFranja() {
        let dias = anioDeMuestra(offsetDias: 0)
        let columnas = LiquidFranjaAno.columnas(para: dias)
        for ancho in stride(from: CGFloat(300), through: 440, by: 5) {
            let m = LiquidFranjaAno.medidas(columnas: columnas, ancho: ancho,
                                            gutterPermitido: true, conMeses: true)
            XCTAssertLessThanOrEqual(m.ancho, ancho + 0.5, "derrame a \(ancho) pt: \(m.ancho)")
        }
    }

    /// Sin medir todavía (`ancho == 0`) la franja se dibuja al tamaño natural del papel —
    /// celda 12, separación 3 — y se re-acomoda cuando llega la medida.
    func test_sinMedirDibujaAlTamanioDelPapel() {
        let m = LiquidFranjaAno.medidas(columnas: 53, ancho: 0,
                                        gutterPermitido: true, conMeses: true)
        XCTAssertEqual(m.celda, LiquidFranjaAno.celdaBase, accuracy: 0.0001)
        XCTAssertEqual(m.separacion, 3, accuracy: 0.0001, "la separación del papel es 3")
        XCTAssertTrue(m.conGutter, "a tamaño natural el gutter de días sí cabe")
    }

    /// Un ancho enorme (iPad, macOS) NO infla los cuadros: la celda tiene techo en la del papel.
    func test_unAnchoEnormeNoInflaLaCelda() {
        let m = LiquidFranjaAno.medidas(columnas: 53, ancho: 2000,
                                        gutterPermitido: true, conMeses: true)
        XCTAssertEqual(m.celda, LiquidFranjaAno.celdaBase, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(m.ancho, 2000)
    }

    /// La separación baja CON la celda (razón del papel 12:3 = 4:1). Si se quedara en 3 pt, a
    /// anchos de teléfono el gap sería más ancho que el cuadro y la franja leería como matriz
    /// de puntos, no como calor.
    func test_laSeparacionMantieneLaRazonDelPapel() {
        for ancho in anchosTelefono {
            let m = LiquidFranjaAno.medidas(columnas: 53, ancho: ancho,
                                            gutterPermitido: true, conMeses: true)
            XCTAssertEqual(m.separacion, m.celda / LiquidFranjaAno.razonSeparacion, accuracy: 0.0001)
            XCTAssertLessThan(m.separacion, m.celda, "el gap nunca puede ganarle al cuadro")
        }
    }

    /// El gutter cede antes que el año: a anchos de teléfono se suelta (su renglón sería
    /// ilegible) y el año se queda con esos puntos, así que la celda CRECE al soltarlo.
    func test_aAnchoDeTelefonoElGutterCedeYLaCeldaCrece() {
        let conGutter = LiquidFranjaAno.celda(paraAncho: 390, columnas: 53, conGutter: true)
        let m = LiquidFranjaAno.medidas(columnas: 53, ancho: 390,
                                        gutterPermitido: true, conMeses: true)
        XCTAssertLessThan(conGutter, LiquidFranjaAno.celdaMinimaGutter,
                          "premisa: a 390 pt el gutter ya no es legible")
        XCTAssertFalse(m.conGutter, "debió soltarse el gutter")
        XCTAssertGreaterThan(m.celda, conGutter, "al soltar el gutter la celda tiene que crecer")
    }

    /// En tallas de accesibilidad el gutter se suelta AUNQUE quepa: su caja de 24 pt no sostiene
    /// texto AX. La franja sigue diciendo el año completo por `accessibilityValue`.
    func test_tallaAccesibleSueltaElGutterAunqueQuepa() {
        let normal = LiquidFranjaAno.medidas(columnas: 53, ancho: 900,
                                             gutterPermitido: true, conMeses: true)
        let ax = LiquidFranjaAno.medidas(columnas: 53, ancho: 900,
                                         gutterPermitido: false, conMeses: true)
        XCTAssertTrue(normal.conGutter, "premisa: a 900 pt el gutter sí cabe")
        XCTAssertFalse(ax.conGutter)
        XCTAssertEqual(ax.columnas, 53, "soltar chrome nunca cuesta columnas")
    }

    // MARK: (b) Sin dato no se pinta el tono

    /// `intensidad: nil` no produce alfa — no hay tono que pintar, la celda va en track neutro.
    func test_sinDatoNoPintaTono() {
        XCTAssertNil(LiquidFranjaAno.alfa(nil))
        XCTAssertNil(LiquidFranjaAno.alfa(Double.nan), "un NaN es ausencia de dato, no un 0")
    }

    /// La otra mitad de la regla: un día MEDIDO en el mínimo sí pinta (alfa piso 0.20). Sin ese
    /// piso, «medí y salió mínimo» y «no medí» se verían igual.
    func test_elMinimoMedidoSiSePinta() {
        let piso = LiquidFranjaAno.alfa(0)
        XCTAssertEqual(piso, LiquidFranjaAno.alfaPiso)
        XCTAssertGreaterThan(piso ?? 0, 0, "sin dato ≠ tono al 0 %")
    }

    /// La rampa completa: 0.26 … 1.00, lineal, clampeada fuera de 0…1.
    func test_laRampaDeAlfaVaDe026A100() {
        XCTAssertEqual(LiquidFranjaAno.alfa(0) ?? 0, 0.26, accuracy: 0.0001)
        XCTAssertEqual(LiquidFranjaAno.alfa(1) ?? 0, 1.00, accuracy: 0.0001)
        XCTAssertEqual(LiquidFranjaAno.alfa(-5) ?? 0, 0.26, accuracy: 0.0001, "clampea por abajo")
        XCTAssertEqual(LiquidFranjaAno.alfa(9) ?? 0, 1.00, accuracy: 0.0001, "clampea por arriba")
        XCTAssertGreaterThan(LiquidFranjaAno.alfa(0.5) ?? 0, LiquidFranjaAno.alfa(0) ?? 0)
        XCTAssertLessThan(LiquidFranjaAno.alfa(0.5) ?? 0, LiquidFranjaAno.alfa(1) ?? 0)
    }

    /// **El candado que faltaba.** Las dos rejillas de calor se apilan en la MISMA pantalla:
    /// Recuperación y Esfuerzo montan el calendario de 90 días y, debajo, esta franja. Si sus
    /// rampas divergen, el mismo día se pinta de dos tonos distintos según quién lo dibuje, y
    /// el usuario lee una diferencia de intensidad que no existe. La revisión adversarial de
    /// F0a encontró exactamente esa divergencia (0.20 aquí contra 0.26 arriba).
    func test_laRampaCoincideConLaDelCalendarioDe90Dias() {
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(LiquidFranjaAno.alfa(t) ?? -1,
                           LiquidCalendario90.alfa(intensidad: t),
                           accuracy: 0.0001,
                           "las dos rejillas tiñen el mismo día con el mismo alfa (t = \(t))")
        }
    }

    /// Un año entero sin lecturas no pinta ni una celda de tono: la forma del año se conserva
    /// en track neutro (el estado vacío honesto).
    func test_unAnioVacioNoPintaNingunaCelda() {
        let dias = anioDeMuestra(offsetDias: 0, conDato: false)
        XCTAssertEqual(dias.count, 365)
        XCTAssertTrue(dias.allSatisfy { LiquidFranjaAno.alfa($0.intensidad) == nil })
        XCTAssertEqual(LiquidFranjaAno.columnas(para: dias), 53,
                       "sin datos el año conserva su forma")
    }

    // MARK: Paridad con la geometría del papel

    /// Coincide con la fórmula cerrada del papel, `ceil((primeraFila + total) / 7)`.
    func test_lasColumnasCoincidenConLaFormulaDelPapel() {
        let cal = LiquidFranjaAno.calendarioSemanal()
        for offset in 0..<7 {
            let dias = anioDeMuestra(offsetDias: offset)
            let primeraFila = LiquidFranjaAno.filaSemana(dias[0].fecha, cal)
            let formula = Int(ceil(Double(primeraFila + dias.count) / 7.0))
            XCTAssertEqual(LiquidFranjaAno.columnas(para: dias), formula, "offset \(offset)")
        }
    }

    /// Las filas son lunes-primero, como el papel: el lunes es la fila 0 y el domingo la 6.
    func test_lasFilasSonLunesPrimero() {
        let cal = LiquidFranjaAno.calendarioSemanal()
        // 2025-01-06 fue lunes.
        let lunes = cal.date(from: DateComponents(year: 2025, month: 1, day: 6))!
        for salto in 0..<7 {
            let d = cal.date(byAdding: .day, value: salto, to: lunes)!
            XCTAssertEqual(LiquidFranjaAno.filaSemana(d, cal), salto)
        }
    }

    // MARK: Marcas de mes

    /// Una marca se para sobre la columna donde cayó su día. Índices fuera de `dias` se ignoran
    /// (no revientan), y si dos meses caen en la misma columna gana el primero que se lee.
    func test_lasMarcasDeMesSeParanEnSuColumna() {
        let columnaPorIndice = [0, 0, 0, 1, 1, 2]
        let mapa = LiquidFranjaAno.etiquetasPorColumna(
            meses: [.init(indice: 0, etiqueta: "E"),
                    .init(indice: 4, etiqueta: "F"),
                    .init(indice: 5, etiqueta: "M"),
                    .init(indice: 3, etiqueta: "X"),      // misma columna que «F»: gana «F»
                    .init(indice: 99, etiqueta: "Z"),     // fuera de rango: se ignora
                    .init(indice: -1, etiqueta: "Y")],    // negativo: se ignora
            columnaPorIndice: columnaPorIndice,
            columnas: 3)
        XCTAssertEqual(mapa, [0: "E", 1: "F", 2: "M"])
    }

    /// Una marca que apunta a una columna que ya no existe (por un `columnas` recortado) no
    /// entra al mapa: nunca se dibuja una etiqueta huérfana.
    func test_unaMarcaFueraDeLasColumnasNoSeDibuja() {
        let mapa = LiquidFranjaAno.etiquetasPorColumna(
            meses: [.init(indice: 2, etiqueta: "D")],
            columnaPorIndice: [0, 1, 5],
            columnas: 3)
        XCTAssertTrue(mapa.isEmpty)
    }

    // MARK: Casos degenerados

    /// Sin días no hay franja: cero columnas, cero tamaño, sin división entre cero ni NaN.
    func test_sinDiasNoHayFranja() {
        XCTAssertEqual(LiquidFranjaAno.columnas(para: []), 0)
        let m = LiquidFranjaAno.medidas(columnas: 0, ancho: 390,
                                        gutterPermitido: true, conMeses: true)
        XCTAssertEqual(m.ancho, 0)
        XCTAssertEqual(m.alto, 0)
        XCTAssertTrue(m.celda.isFinite)
    }

    /// Un ancho absurdo (más chico que el piso de 53 celdas de 2 pt) toca el piso y se queda
    /// ahí — deja que el contenedor decida, pero no se inventa una celda invisible.
    func test_unAnchoAbsurdoSeQuedaEnElPiso() {
        let m = LiquidFranjaAno.medidas(columnas: 53, ancho: 40,
                                        gutterPermitido: true, conMeses: true)
        XCTAssertEqual(m.celda, LiquidFranjaAno.celdaMinima, accuracy: 0.0001)
        XCTAssertEqual(m.columnas, 53, "ni en el piso se recortan columnas")
    }
}
