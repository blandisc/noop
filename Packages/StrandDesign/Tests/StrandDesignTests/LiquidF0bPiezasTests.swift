import XCTest
import SwiftUI
@testable import StrandDesign

/// Pruebas de las piezas de F0b que quedaron sin cubrir (FER-99): barras de contribución,
/// barras por hora, gráfica superpuesta y tooltip multi-serie.
///
/// Todas prueban COMPORTAMIENTO, no compilación: cada caso corresponde a una forma concreta
/// en que la pieza podría mentirle al usuario si alguien la «simplifica» después.
///
/// Run: swift test --filter LiquidF0bPiezasTests
final class LiquidF0bPiezasTests: XCTestCase {

    // MARK: - Barras de contribución · el signo es la información

    /// La convención es contraintuitiva a propósito y por eso necesita candado: en edad
    /// corporal, un efecto NEGATIVO (te quita años) es buena noticia y va en verde; uno
    /// POSITIVO (te suma años) va en ámbar. Invertirlo haría que la hoja felicitara al usuario
    /// por envejecer.
    func test_contribucion_elSignoEligeElColor() {
        XCTAssertEqual(LiquidBarrasContribucion.tono(para: -1.2), LiquidColor.positivo,
                       "restar edad es buena noticia")
        XCTAssertEqual(LiquidBarrasContribucion.tono(para: 0.8), LiquidColor.atencion,
                       "sumar edad pide atención")
    }

    /// Un factor en cero SE MUESTRA (es información: «esto no te está moviendo»), así que su
    /// fracción tiene que ser un número válido, no un nil ni un NaN que lo saque del render.
    func test_contribucion_factorEnCero_siguePresente() {
        let f = LiquidBarrasContribucion.fraccion(efecto: 0, maximo: 4)
        XCTAssertEqual(f, 0, accuracy: 0.0001)
        XCTAssertFalse(f.isNaN)
    }

    /// La escala la manda el caller para que dos sesiones sean comparables. Si el componente
    /// normalizara contra su propio máximo local, un factor de −0.2 en una semana tranquila se
    /// vería igual de grande que uno de −4 en una semana dura.
    func test_contribucion_escalaUsaElMaximoDelCaller() {
        let conMaximoGrande = LiquidBarrasContribucion.fraccion(efecto: -1, maximo: 4)
        let conMaximoChico  = LiquidBarrasContribucion.fraccion(efecto: -1, maximo: 2)
        XCTAssertLessThan(conMaximoGrande, conMaximoChico,
                          "el mismo efecto ocupa menos cuando la escala del caller es mayor")
        XCTAssertEqual(conMaximoChico, 0.5, accuracy: 0.0001)
    }

    func test_contribucion_maximoCero_noDivideEntreCero() {
        let f = LiquidBarrasContribucion.fraccion(efecto: -3, maximo: 0)
        XCTAssertTrue(f.isFinite, "un máximo en cero no puede producir infinito ni NaN")
    }

    func test_contribucion_efectoFueraDeEscala_seClampea() {
        XCTAssertLessThanOrEqual(LiquidBarrasContribucion.fraccion(efecto: -99, maximo: 4), 1)
        XCTAssertGreaterThanOrEqual(LiquidBarrasContribucion.fraccion(efecto: 99, maximo: 4), 0)
    }

    // MARK: - Barras por hora · sin lectura no es calma

    /// El invariante central de la pieza. Una hora sin medir NO puede producir una barra:
    /// si lo hiciera, un día con el reloj descargado se leería como un día en calma total.
    func test_horas_sinLectura_noDibujaBarra() {
        let dominio: ClosedRange<Double> = 0...3
        XCTAssertNil(LiquidBarrasHora.alto(valor: nil, dominio: dominio, altoTotal: 100),
                     "sin lectura no hay barra, hay hueco")
        XCTAssertNotNil(LiquidBarrasHora.alto(valor: 0, dominio: dominio, altoTotal: 100),
                        "medido en cero SÍ dibuja: es un dato, no un hueco")
    }

    func test_horas_valorFueraDeDominio_seClampea() {
        let dominio: ClosedRange<Double> = 0...3
        XCTAssertEqual(LiquidBarrasHora.fraccion(9, dominio: dominio), 1, accuracy: 0.0001)
        XCTAssertEqual(LiquidBarrasHora.fraccion(-4, dominio: dominio), 0, accuracy: 0.0001)
    }

    func test_horas_dominioDegenerado_noRevienta() {
        let f = LiquidBarrasHora.fraccion(2, dominio: 2...2)
        XCTAssertTrue(f.isFinite, "un dominio de ancho cero no puede producir NaN")
    }

    /// La línea punteada es «tu normal», no una meta: si el caller no tiene base todavía, no
    /// se dibuja NI se menciona. Inventar un promedio es la mentira más fácil de esta pieza.
    func test_horas_sinReferencia_noSeDibujaNiSeAnuncia() {
        XCTAssertNil(LiquidBarrasHora.fraccionReferencia(nil, dominio: 0...3))
        let voz = LiquidBarrasHora.a11yValue(base: "seis horas con lectura",
                                             referencia: nil,
                                             referenciaEtiqueta: "tu calma normal")
        XCTAssertFalse(voz.lowercased().contains("calma normal"),
                       "sin referencia, VoiceOver tampoco la nombra")
    }

    func test_horas_conReferencia_seAnuncia() {
        let voz = LiquidBarrasHora.a11yValue(base: "seis horas con lectura",
                                             referencia: 1.2,
                                             referenciaEtiqueta: "tu calma normal")
        XCTAssertTrue(voz.contains("tu calma normal"))
    }

    // MARK: - Tiempo en zonas · «no se midió» ≠ «cero minutos»

    private func zona(_ id: Int, _ minutos: Double?) -> LiquidTiempoZonas.Zona {
        LiquidTiempoZonas.Zona(id: id, etiqueta: "Z\(id)", minutos: minutos, color: LiquidColor.ambar)
    }

    /// El hallazgo de la revisión adversarial: la pieza no tenía forma de decir «el día no se
    /// midió», así que un día sin lecturas se narraba como seis ceros medidos — afirmando que
    /// sí se midió y que todo salió en reposo.
    func test_zonas_diaSinMedir_noSeNarraComoSeisCeros() {
        let sinMedir = (0..<6).map { zona($0, nil) }
        XCTAssertFalse(LiquidTiempoZonas.hayMedicion(sinMedir))
        XCTAssertEqual(LiquidTiempoZonas.a11yValue(zonas: sinMedir, explicito: "",
                                                   sinMedicion: "sin lecturas hoy"),
                       "sin lecturas hoy",
                       "sin una sola lectura, la voz no puede recitar porcentajes")

        let cerosMedidos = (0..<6).map { zona($0, 0) }
        XCTAssertTrue(LiquidTiempoZonas.hayMedicion(cerosMedidos),
                      "seis ceros MEDIDOS sí son una medición: el día se midió y fue tranquilo")
    }

    /// Sin medición no se dibuja relleno; con cero medido sí hay algo que ver.
    func test_zonas_elRielDistingueLosTresEstados() {
        let partes = LiquidTiempoZonas.partes([zona(0, nil), zona(1, 0), zona(2, 60)])
        XCTAssertNil(LiquidTiempoZonas.anchoRiel(partes[0], ancho: 144),
                     "sin medir no hay relleno")
        XCTAssertEqual(LiquidTiempoZonas.anchoRiel(partes[1], ancho: 144), 0,
                       "cero medido: ancho 0, pero presente — el render le pone su marca de base")
        XCTAssertGreaterThan(LiquidTiempoZonas.anchoRiel(partes[2], ancho: 144) ?? 0, 0)
    }

    /// Con los minutos reales de un día (742/260/180/96/34/8 sobre 1320), la zona 5 es el
    /// 0.6 % — 0.87 pt en un riel de 144. Sin piso, ocho minutos medidos se verían idénticos a
    /// cero minutos y la zona más dura del día desaparecería.
    func test_zonas_unaAstillaRealSigueSiendoVisible() {
        let dia = [742.0, 260, 180, 96, 34, 8].enumerated().map { zona($0.offset, $0.element) }
        let partes = LiquidTiempoZonas.partes(dia)
        let z5 = LiquidTiempoZonas.anchoRiel(partes[5], ancho: 144)
        XCTAssertGreaterThanOrEqual(z5 ?? 0, LiquidTiempoZonas.astillaMinima,
                                    "ocho minutos reales no pueden desaparecer contra el riel")
        XCTAssertLessThan(z5 ?? 999, LiquidTiempoZonas.anchoRiel(partes[0], ancho: 144) ?? 0,
                          "pero sigue siendo claramente la más chica: el piso no miente sobre el tamaño")
    }

    // MARK: - Banda de edad · la incertidumbre es la lectura honesta

    /// El hallazgo más grave de la revisión: el port había borrado la banda de ±N años. El
    /// original dice de sí mismo «the band, not the point, is the honest read» — un punto sin
    /// su intervalo afirma más precisión de la que el motor tiene.
    func test_bandaEdad_laBandaSeDibujaYSeMueveConElDato() {
        let dominio: ClosedRange<Double> = 20...60
        let baja = LiquidBandaEdad.posicion(31 - 5, en: dominio)
        let alta = LiquidBandaEdad.posicion(31 + 5, en: dominio)
        XCTAssertLessThan(baja, alta, "la banda tiene ancho: no es un punto disfrazado")
        XCTAssertEqual((baja + alta) / 2, LiquidBandaEdad.posicion(31, en: dominio), accuracy: 1e-9,
                       "la banda está centrada en la edad corporal")
    }

    func test_bandaEdad_seClampeaSinRomperElLayout() {
        let dominio: ClosedRange<Double> = 20...60
        XCTAssertEqual(LiquidBandaEdad.posicion(5, en: dominio), 0, accuracy: 1e-9)
        XCTAssertEqual(LiquidBandaEdad.posicion(99, en: dominio), 1, accuracy: 1e-9)
        XCTAssertEqual(LiquidBandaEdad.posicion(30, en: 30...30), 0.5, accuracy: 1e-9,
                       "dominio degenerado cae al centro, no a NaN")
    }

    // MARK: - Gráfica superpuesta · cada serie con SU escala

    /// Comparar VFC en milisegundos con pasos en miles sobre un eje común es mentir sobre la
    /// relación entre las dos. Cada serie se normaliza contra su propio dominio.
    func test_superpuesta_cadaSerieNormalizaContraSuDominio() {
        let vfc = LiquidGraficaSuperpuesta.normalizado(60, en: 40...80)
        let pasos = LiquidGraficaSuperpuesta.normalizado(6_000, en: 2_000...10_000)
        XCTAssertEqual(vfc, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pasos, 0.5, accuracy: 0.0001,
                       "el punto medio de cada escala cae a la misma altura, que es el punto")
    }

    func test_superpuesta_normalizadoSeClampeaYNoRevienta() {
        XCTAssertEqual(LiquidGraficaSuperpuesta.normalizado(999, en: 0...10), 1, accuracy: 0.0001)
        XCTAssertEqual(LiquidGraficaSuperpuesta.normalizado(-5, en: 0...10), 0, accuracy: 0.0001)
        XCTAssertTrue(LiquidGraficaSuperpuesta.normalizado(5, en: 5...5).isFinite,
                      "dominio de ancho cero no produce NaN")
    }

    /// Menos de dos series no es una comparación: la pieza debe caer a un estado honesto en vez
    /// de dibujar una gráfica de una sola línea que finge ser un comparador.
    func test_superpuesta_menosDeDosSeries_daEstadoHonesto() {
        let ancla = Date(timeIntervalSince1970: 1_700_000_000)
        let rango = ancla...(ancla.addingTimeInterval(7 * 86_400))
        let una = [serie("a", ancla, LiquidColor.cian)]
        XCTAssertNotEqual(LiquidGraficaSuperpuesta.resolverEstado(una, rango), .datos,
                          "una sola serie no puede rendir como comparación")
        let dos = [serie("a", ancla, LiquidColor.cian), serie("b", ancla, LiquidColor.rosa)]
        XCTAssertEqual(LiquidGraficaSuperpuesta.resolverEstado(dos, rango), .datos)
    }

    /// Dos métricas ELEGIDAS, pero la ventana solo deja UNA con lecturas: la causa es «sin
    /// lecturas en el rango», no «faltan métricas». La pieza debe caer a `.sinLecturas` (su copy
    /// «no hay datos en <rango>»), nunca a `.minimo` (el copy de «conecta Apple Health»). Si el
    /// caller filtrara las series vacías ANTES de preguntar el estado —el defecto TND30-1— la
    /// pieza vería una sola serie y elegiría el mensaje equivocado.
    func test_superpuesta_dosElegidas_soloUnaConLecturasEnVentana_daSinLecturas() {
        let ancla = Date(timeIntervalSince1970: 1_700_000_000)
        let rango = ancla...(ancla.addingTimeInterval(7 * 86_400))
        let conLecturas = serie("a", ancla, LiquidColor.cian)           // 5 puntos dentro
        let fueraDeVentana = LiquidGraficaSuperpuesta.Serie(
            id: "b", nombre: "B", color: LiquidColor.rosa,
            puntos: [(fecha: ancla.addingTimeInterval(40 * 86_400), valor: 1)],  // fuera del rango
            dominio: 0...1)
        let estado = LiquidGraficaSuperpuesta.resolverEstado([conLecturas, fueraDeVentana], rango)
        XCTAssertEqual(estado, .sinLecturas,
                       "dos elegidas, una sin lecturas en la ventana: la causa es el rango, no el conteo")
        XCTAssertNotEqual(estado, .minimo,
                          "nunca .minimo con dos series elegidas: mostraría el copy de HealthKit")
    }

    /// El rango recorta: un punto fuera de la ventana elegida no puede seguir dibujándose.
    func test_superpuesta_elRangoRecortaLosPuntos() {
        let ancla = Date(timeIntervalSince1970: 1_700_000_000)
        let dentro = ancla.addingTimeInterval(86_400)
        let fuera  = ancla.addingTimeInterval(40 * 86_400)
        let puntos = [(fecha: dentro, valor: 1.0), (fecha: fuera, valor: 2.0)]
        let recorte = LiquidGraficaSuperpuesta.enRango(puntos, ancla...(ancla.addingTimeInterval(7 * 86_400)))
        XCTAssertEqual(recorte.count, 1)
        XCTAssertEqual(recorte.first?.fecha, dentro)
    }

    // MARK: - Tooltip multi-serie · ninguna serie desaparece

    /// Si el tooltip omitiera la serie sin lectura, el usuario que solo oye VoiceOver creería
    /// que esa métrica no está en la comparación — y la tarjeta cambiaría de alto al pasar por
    /// un hueco.
    func test_tooltip_laSerieSinLectura_sigueNombrada() {
        let filas: [LiquidTooltipMulti.Fila] = [
            .init(id: "hrv", color: LiquidColor.cian, nombre: "VFC", valor: "66 ms"),
            .init(id: "rhr", color: LiquidColor.rosa, nombre: "FC en reposo", valor: nil),
        ]
        let voz = LiquidTooltipMulti.a11yValor(filas: filas, sinLectura: "sin lectura")
        XCTAssertTrue(voz.contains("VFC 66 ms"))
        XCTAssertTrue(voz.contains("FC en reposo sin lectura"),
                      "la serie sin dato se nombra igual, con su hueco explícito")
    }

    func test_tooltip_conservaElOrdenDelCaller() {
        let filas: [LiquidTooltipMulti.Fila] = [
            .init(id: "c", color: LiquidColor.teal, nombre: "Pasos", valor: "8,412"),
            .init(id: "a", color: LiquidColor.cian, nombre: "VFC", valor: "66 ms"),
        ]
        let voz = LiquidTooltipMulti.a11yValor(filas: filas, sinLectura: "—")
        let iPasos = voz.range(of: "Pasos")!.lowerBound
        let iVFC = voz.range(of: "VFC")!.lowerBound
        XCTAssertLessThan(iPasos, iVFC,
                          "el orden es el de la leyenda del caller, no un orden alfabético propio")
    }

    func test_tooltip_sinFilas_noRevienta() {
        XCTAssertEqual(LiquidTooltipMulti.a11yValor(filas: [], sinLectura: "—"), "")
    }

    // MARK: - Checklist · un factor ausente NUNCA oculta su motivo

    /// El criterio de aceptación central de «de qué está hecha» (edad corporal) y «lo que falta»
    /// (edad física): un factor AUSENTE se muestra con su razón, no se borra. Si esta rama
    /// devolviera `false` para un ausente con motivo, la hoja escondería justo por qué le falta
    /// ese factor y afirmaría una completitud que el dato no tiene.
    func test_checklist_ausenteConMotivo_muestraElMotivo() {
        XCTAssertTrue(LiquidChecklistRow.muestraMotivo(presente: false,
                                                       motivo: "Sin noches suficientes todavía."),
                      "un factor ausente con motivo SIEMPRE lo enseña")
    }

    /// Un factor presente no necesita excusa, y un ausente sin razón no dibuja una línea vacía.
    func test_checklist_presenteYAusenteSinMotivo_noDibujanMotivo() {
        XCTAssertFalse(LiquidChecklistRow.muestraMotivo(presente: true,
                                                        motivo: "Frecuencia en reposo"),
                       "un factor presente no lleva motivo")
        XCTAssertFalse(LiquidChecklistRow.muestraMotivo(presente: false, motivo: nil))
        XCTAssertFalse(LiquidChecklistRow.muestraMotivo(presente: false, motivo: ""),
                       "un motivo vacío no cuenta como razón")
    }

    // MARK: - Helpers

    private func serie(_ id: String, _ ancla: Date, _ color: Color) -> LiquidGraficaSuperpuesta.Serie {
        LiquidGraficaSuperpuesta.Serie(
            id: id,
            nombre: id.uppercased(),
            color: color,
            puntos: (0..<5).map { (fecha: ancla.addingTimeInterval(TimeInterval($0) * 86_400),
                                   valor: Double($0)) },
            dominio: 0...4
        )
    }
}
