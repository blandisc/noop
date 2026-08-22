import XCTest
import StrandAnalytics
@testable import Cenit

// MARK: - El acta y el voto del par (FER-81 · adversarial H3)
//
// El motor cuenta TRES votantes (FC en reposo, sueño y el par temperatura+respiración) pero la
// boleta solo DIBUJA dos filas. Sumar el voto del par al conteo sin decírselo a la prosa hacía
// que el acta nombrara una señal que estaba dentro. Cada test es una de esas frases falsas.

@MainActor
final class ActaVotoDelParTests: XCTestCase {

    private func read(verdict: Preparedness.Verdict,
                      autonomicOut: Bool, sleepOut: Bool,
                      par: Bool,
                      trend: AutonomicTrend.Direction? = nil,
                      maturity: BaselineStatus = .trusted,
                      autonomicPossible: Bool = true,
                      autonomicNights: Int = 30) -> Preparedness.Read {
        Preparedness.Read(
            verdict: verdict,
            // Sin FC nocturna posible el eje autonómico es `.noData` — con `.inRange` el
            // fixture firmaba un estado que el motor NO puede producir, y por eso el test
            // pasaba por encima del riel de la fila sin verlo (cuarta vuelta adversarial).
            drivers: [.init(axis: .autonomic,
                            state: !autonomicPossible ? .noData : (autonomicOut ? .low : .inRange),
                            orientedZ: nil),
                      .init(axis: .sleep, state: sleepOut ? .low : .inRange, orientedZ: nil)],
            signalsPresent: 3, signalsTotal: 3, maturity: maturity, autonomicNights: autonomicNights,
            trend: trend,
            sentinel: par ? .init(state: .corroborated, streakNights: 2, watchingSignal: nil,
                                  tempOut: true, respOut: true)
                          : .init(state: .quiet, streakNights: 0, watchingSignal: nil,
                                  tempOut: false, respOut: false),
            sentinelHistory: [.init(day: Repository.localDayKey(Date()), tempOut: par, respOut: par,
                                    tempMissing: false, respMissing: false, respJudged: true,
                                    gapBefore: false)],
            bodyHistory: [.init(day: Repository.localDayKey(Date()), rhrResolved: 55,
                                autonomicOrientedZ: 0.1, autonomicOut: autonomicOut,
                                sleepOut: sleepOut, rhrBaseCenter: 55, hrvBaseCenter: 45,
                                rhrBand: 53...57)],
            autonomicPossible: autonomicPossible)
    }

    /// El resfriado clásico: los dos ejes DENTRO y el par fuera. La prosa decía «la FC en reposo
    /// votó fuera» con las dos filas en «dentro».
    func test_parSolo_noNombraUnEjeQueEstaDentro() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .caution, autonomicOut: false,
                                                    sleepOut: false, par: true))
        XCTAssertFalse(acta.conteo.contains(String(localized: "acta.resumen.caution.auto",
                                                   defaultValue: "Resting HR voted outside; sleep, inside.")),
                       "ningún eje votó fuera: no se puede nombrar uno")
        XCTAssertTrue(acta.conteo.lowercased().contains("temperature")
                      || acta.conteo.lowercased().contains("temperatura"),
                      "la prosa nombra al par, que es quien votó: \\(acta.conteo)")
        // Y los vigilantes ya no dicen «no votan» el día que votaron.
        XCTAssertEqual(acta.vigilantesLabel,
                       String(localized: "acta.vigilantes.votaron", defaultValue: "Watching · they voted today"))
    }

    /// H3-b: un eje fuera + el par ⇒ el motor cuenta dos votos y da `.easy`, pero «los dos votos
    /// cayeron fuera» es falso: uno lo puso el par.
    func test_easyConParYUnEje_noDiceQueLosDosEjesVotaronFuera() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .easy, autonomicOut: false,
                                                    sleepOut: true, par: true))
        XCTAssertNotEqual(acta.conteo, String(localized: "Both of your votes fell outside."))
        XCTAssertTrue(acta.conteo.lowercased().contains("sleep")
                      || acta.conteo.lowercased().contains("sueño"))
        XCTAssertTrue(acta.conteo.lowercased().contains("together")
                      || acta.conteo.lowercased().contains("juntas"))
    }

    // MARK: Segunda vuelta adversarial — la rama del par contra la histéresis

    /// El DESFASE manda: con veredicto verde sostenido por la histéresis y el par corroborado
    /// hoy, la rama del par (que vivía ARRIBA del bloque de desfase) devolvía «se salieron
    /// juntas» y se comía la única explicación de por qué el veredicto NO se movió.
    func test_desfaseConPar_siempreExplicaLaHisteresis() {
        // .full con un voto fuera ⇒ el veredicto mostrado viene de ayer.
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .full, autonomicOut: false,
                                                    sleepOut: false, par: true))
        let t = acta.conteo.lowercased()
        XCTAssertTrue(t.contains("two days") || t.contains("dos días"),
                      "el desfase es lo que se está viendo: tiene que decirse: \(acta.conteo)")
        XCTAssertTrue(t.contains("together") || t.contains("juntas"),
                      "y sigue nombrando al par, que es quien votó: \(acta.conteo)")
    }

    /// Y cuando ADEMÁS un eje se salió, la frase corta lo escondía: era la única alcanzable.
    func test_desfaseConParYEjeFuera_nombraALosDos() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .full, autonomicOut: false,
                                                    sleepOut: true, par: true))
        let t = acta.conteo.lowercased()
        XCTAssertTrue(t.contains("together") || t.contains("juntas"))
        XCTAssertTrue(t.contains("one of your votes") || t.contains("uno de tus votos"),
                      "el voto que sí cayó fuera no puede desaparecer: \(acta.conteo)")
    }

    /// Sin FC nocturna posible, la tarjeta de calibración cuenta noches de reloj que jamás van a
    /// llegar — el héroe acaba de decir «todavía no puedo leer tus mañanas».
    func test_sinFCNocturnaPosible_elActaNoPrometeNochesDeReloj() {
        let base = read(verdict: .lowSignal, autonomicOut: false, sleepOut: false, par: false)
        let sinReloj = Preparedness.Read(
            verdict: .lowSignal, drivers: base.drivers, signalsPresent: 1, signalsTotal: 3,
            maturity: .calibrating, autonomicNights: 0, trend: nil,
            sentinel: base.sentinel, sentinelHistory: base.sentinelHistory,
            bodyHistory: base.bodyHistory, autonomicPossible: false)
        let acta = LiquidHoyBuilder.acta(prep: sinReloj)
        if case .calibrando = acta.confianza {
            XCTFail("prometer «0 de 4 noches» a quien no puede acumularlas es una promesa falsa")
        }
        XCTAssertFalse(acta.notas.contains { $0.id == "calibrando" },
                       "ni la nota de «N noches más con tu Apple Watch»")
    }

    // MARK: Tercera vuelta — lo que los arreglos de la segunda dejaron abierto

    /// El plural otra vez, en la rama nueva: con los DOS ejes fuera, «uno de tus votos» le baja
    /// la magnitud a lo que está pasando, justo el día más delicado.
    func test_desfaseConParYLosDosEjes_diceQueFueronLosDos() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .full, autonomicOut: true,
                                                    sleepOut: true, par: true))
        let t = acta.conteo.lowercased()
        XCTAssertFalse(t.contains("one of your votes") || t.contains("uno de tus votos"),
                       "cayeron los dos: \(acta.conteo)")
        XCTAssertTrue(t.contains("both of your votes") || t.contains("tus dos votos"),
                      "\(acta.conteo)")
    }

    /// El empujón de tendencia también puede venir del PAR: «un voto cayó fuera» salía con las
    /// dos filas de la boleta dibujadas DENTRO.
    func test_tendenciaConPar_noNombraUnVotoQueNoExiste() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .easy, autonomicOut: false,
                                                    sleepOut: false, par: true, trend: .below))
        let t = acta.conteo.lowercased()
        XCTAssertTrue(t.contains("trending down") || t.contains("bajando"),
                      "sigue contando el empujón de la tendencia: \(acta.conteo)")
        XCTAssertTrue(t.contains("together") || t.contains("juntas"),
                      "y dice quién votó de verdad: \(acta.conteo)")
    }

    /// Con lectura cruda en pantalla y sin base para juzgarla, la fila dice «sin comparar»
    /// (joya de calibrando), no «sin dato» — la gemela del `.sinJuicio` del dominó (FER-128 r11/r12).
    func test_acta_lecturaSinBase_diceSinComparar_noSinDato() {
        let prep = read(verdict: .lowSignal, autonomicOut: false, sleepOut: false, par: false,
                        maturity: .calibrating, autonomicPossible: false)
        // (El helper siempre da un driver de sueño; aquí solo el eje autonómico es `.noData`.)
        let con = LiquidHoyBuilder.acta(prep: prep, lecturasHoy: (rhr: true, sueno: true))
        XCTAssertEqual(con.filas[0].estado, .sinJuicio)
        XCTAssertEqual(con.filas[0].palabra, String(localized: "acta.voto.sinjuicio", defaultValue: "not compared"))
        XCTAssertEqual(con.filas[0].sub, String(localized: "acta.sub.fc.sinbase", defaultValue: "overnight · no base yet"),
                       "el sub no puede decir «contra tu base» bajo «sin comparar»")
        let sin = LiquidHoyBuilder.acta(prep: prep, lecturasHoy: (rhr: false, sueno: false))
        XCTAssertEqual(sin.filas[0].estado, .sinLectura, "sin lectura cruda sigue siendo «sin dato»")
        // Sin prep (nada llegó): con lectura cruda de sueño la fila de sueño también es «sin comparar».
        let sinPrep = LiquidHoyBuilder.acta(prep: nil, lecturasHoy: (rhr: false, sueno: true))
        XCTAssertEqual(sinPrep.filas[1].estado, .sinJuicio)
        XCTAssertEqual(sinPrep.filas[0].estado, .sinLectura)
    }

    /// Sin FC nocturna posible, la hoja entera tiene que contar la MISMA historia que el héroe:
    /// ni «Conociéndote», ni «tu base se está formando», ni «mañana la boleta se llena sola».
    func test_sinFCNocturnaPosible_todaLaHojaCuentaLaMismaHistoria() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .lowSignal, autonomicOut: false,
                                                    sleepOut: false, par: false,
                                                    maturity: .calibrating,
                                                    autonomicPossible: false))
        XCTAssertNotEqual(acta.nivel, String(localized: "hero.title.calibrando",
                                             defaultValue: "Getting to know you"),
                          "la palabra grande no puede prometer un proceso que no corre")
        XCTAssertNotEqual(acta.conteo,
                          String(localized: "The ballot is taking shape with your first nights."))
        XCTAssertFalse(acta.notas.contains { $0.id == "noche" },
                       "«duerme con tu Watch y MAÑANA se llena sola» es falso: faltan cuatro noches")
        // Una voz por hueco (FER-128 r11): lo que destraba lo dice el RESUMEN, y la nota calla.
        XCTAssertEqual(acta.conteo,
                       String(localized: "hero.sub.sinfc",
                              defaultValue: "Your verdict stands on your resting heart rate at night, and it hasn't arrived. Sleeping with your Apple Watch is what unlocks it."),
                       "y dice qué es lo que destraba")
        XCTAssertFalse(acta.notas.contains { $0.id == "sinfc" }, "sin repetirlo en una nota")
    }

    /// Mientras la pantalla promete que sigue leyendo —jalón manual, o noche corta con la
    /// ventana de la mañana todavía abierta— el acta no puede sentenciar que la señal no llegó.
    func test_mientrasLee_elActaNoSentenciaQueFaltaLaSenal() {
        let sinQuorum = read(verdict: .lowSignal, autonomicOut: false, sleepOut: false, par: false)
        let sentencia = String(localized: "acta.resumen.senal.insuficiente",
                               defaultValue: "Your sleep came in; your resting signal didn't, so there's no quorum.")
        XCTAssertNotEqual(LiquidHoyBuilder.acta(prep: sinQuorum, causaT3: .leyendo).conteo,
                          sentencia, "todavía está leyendo: no puede sentenciar")
        // Con la ventana ya cerrada, sí lo dice — y jamás «no llegó nada» con la noche llena.
        XCTAssertEqual(LiquidHoyBuilder.acta(prep: sinQuorum, causaT3: .senalInsuficiente).conteo,
                       sentencia)
    }

    // MARK: Cuarta vuelta — lo que quedaba prometiendo o contradiciendo

    /// El RIEL de la fila era el último rincón que seguía dibujando «aprendiendo tu base»:
    /// banda y joya centrada sobre cero mediciones, a quien no puede acumularlas.
    func test_sinFCNocturnaPosible_elRielNoDibujaUnaBaseQueNoExiste() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .lowSignal, autonomicOut: false,
                                                    sleepOut: false, par: false,
                                                    maturity: .calibrating,
                                                    autonomicPossible: false))
        let fc = acta.filas.first
        XCTAssertEqual(fc?.estado, .sinLectura,
                       "sin señal posible no hay base formándose: el riel no puede insinuarla")
    }

    /// Las NOTAS eran ciegas al voto del par: «los dos fuera a la vez» pegado bajo una boleta
    /// con una fila dibujada DENTRO, mientras el resumen dos renglones arriba lo decía bien.
    func test_notaDelParNoContradiceALaBoleta() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .easy, autonomicOut: false,
                                                    sleepOut: true, par: true))
        let aviso = acta.notas.first { $0.id == "aviso" }?.texto ?? ""
        XCTAssertNotEqual(aviso, String(localized: "Both out at once: today is for recovering, not pushing."),
                          "solo un eje está fuera: el otro voto lo puso el par")
        XCTAssertFalse(aviso.isEmpty, "pero el aviso sigue existiendo: el día pide recuperar")
    }

    /// La misma frase no puede imprimirse dos veces en la misma hoja.
    func test_sinFCNocturnaPosible_laHojaNoSeRepite() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .lowSignal, autonomicOut: false,
                                                    sleepOut: false, par: false,
                                                    maturity: .calibrating,
                                                    autonomicPossible: false))
        XCTAssertNil(acta.confianza,
                     "el resumen ya dice la causa y la nota ya dice la acción")
    }

    // MARK: Quinta vuelta — la magnitud y las promesas que quedaban

    /// La nota del par NO puede recetar el día rojo en un día ámbar. Con el par solo (los dos
    /// ejes dentro) el motor da «ve leve»; mi nota de la ronda 4 decía «hoy toca recuperar, no
    /// empujar» —el verbo del rojo— y encima repetía casi textual el resumen de arriba.
    func test_parSoloEnDiaAmbar_noRecetaElDiaRojo() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .caution, autonomicOut: false,
                                                    sleepOut: false, par: true))
        let aviso = acta.notas.first { $0.id == "aviso" }
        XCTAssertNil(aviso, "un solo voto no escala a día de recuperación")
        XCTAssertEqual(acta.notas.first { $0.id == "voto" }?.texto,
                       String(localized: "One vote out lightens the day; it doesn't sink it."),
                       "la magnitud la manda el veredicto, no el par")
    }

    /// Con Apple Salud desconectada, la barra «N de 4 noches» no puede avanzar: es la misma
    /// promesa rota que FER-76 apagó en el héroe, en gráfico.
    func test_saludDesconectada_elActaNoPintaLaBarraDeCalibracion() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .lowSignal, autonomicOut: false,
                                                    sleepOut: false, par: false,
                                                    maturity: .calibrating),
                                         healthConnected: false)
        XCTAssertNil(acta.confianza, "sin Salud conectada no entra ninguna noche")
    }

    /// SEXTA VUELTA · «Tu veredicto se apoya en N noches tuyas» hablaba en presente de un
    /// veredicto que hoy no existe: cerraba la hoja de quien acaba de leer «Sin lectura».
    func test_sinVeredicto_laConfianzaNoHablaDeTuVeredicto() {
        // 8 noches: POR DEBAJO de `minNightsTrust`, que es la única condición con la que el
        // código viejo emitía la nota. Con 30 la prueba pasaba igual sin el arreglo — o sea que
        // no fijaba nada (lo cazó la séptima vuelta revisando mis propias pruebas).
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .lowSignal, autonomicOut: false,
                                                    sleepOut: false, par: false,
                                                    maturity: .stale, autonomicNights: 8))
        XCTAssertNil(acta.confianza, "sin veredicto no hay veredicto que apoyar")
    }

    /// SÉPTIMA VUELTA · Con la base RANCIA lo que falta es la BASE, no el dato: el acta
    /// sentenciaba «tu señal en reposo no llegó» mientras el héroe y la Matriz enseñaban el
    /// número de hoy.
    func test_baseRancia_elActaHablaLaLenguaDelHeroe() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .lowSignal, autonomicOut: false,
                                                    sleepOut: false, par: false,
                                                    maturity: .stale, autonomicNights: 8))
        XCTAssertEqual(acta.nivel, String(localized: "hero.title.rancia",
                                          defaultValue: "Your range needs fresh nights"))
        XCTAssertNotEqual(acta.conteo,
                          String(localized: "Nothing came in last night: no sleep and no resting signals."))
    }

    /// SÉPTIMA VUELTA · El VERDE sostenido por la histéresis juraba que las dos señales
    /// amanecieron en rango mientras el acta decía «un voto cayó fuera hoy». El héroe era el
    /// único que mentía, y mentía sobre el cuerpo.
    func test_verdeConDesfase_elHeroeNoJuraQueTodoCayoDentro() {
        let prep = read(verdict: .full, autonomicOut: false, sleepOut: true, par: false)
        let (hero, _, _) = LiquidHoyBuilder.hero(prep: prep, nights: 30, healthConnected: true)
        guard case .veredicto(_, _, _, let sub, _) = hero else {
            return XCTFail("con veredicto el héroe es .veredicto")
        }
        XCTAssertNotEqual(sub, String(localized: "hero.sub.full.nombrado",
                                      defaultValue: "Your sleep and your resting heart rate woke up in your range."),
                          "hoy un eje se salió: no puede jurar que los dos cayeron dentro")
    }

    /// OCTAVA VUELTA · El héroe y el acta cuentan EL MISMO conteo. La frase fija en singular
    /// que metí en la séptima decía «una de tus señales» con dos fuera, y culpaba a un eje que
    /// estaba dentro cuando el único voto fuera era el del par.
    func test_verdeConDesfase_elHeroeCuentaLoMismoQueElActa() {
        // Dos ejes fuera bajo un titular verde: plural.
        let dos = read(verdict: .full, autonomicOut: true, sleepOut: true, par: false)
        let (heroDos, _, _) = LiquidHoyBuilder.hero(prep: dos, nights: 30, healthConnected: true)
        guard case .veredicto(_, _, _, let subDos, _) = heroDos else { return XCTFail("veredicto") }
        XCTAssertTrue(subDos.lowercased().contains("both of your votes")
                      || subDos.lowercased().contains("tus dos votos"),
                      "cayeron los dos: \(subDos)")
        // Y con el par como único voto fuera, nombra al PAR, no a un eje que está dentro.
        let par = read(verdict: .full, autonomicOut: false, sleepOut: false, par: true)
        let (heroPar, _, _) = LiquidHoyBuilder.hero(prep: par, nights: 30, healthConnected: true)
        guard case .veredicto(_, _, _, let subPar, _) = heroPar else { return XCTFail("veredicto") }
        XCTAssertTrue(subPar.lowercased().contains("temperature") || subPar.lowercased().contains("temperatura"),
                      "quien votó fue el par: \(subPar)")
    }

    /// Sin par, la prosa de siempre no cambia (no se rompió el camino normal).
    func test_sinPar_laProsaDeSiempre() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .easy, autonomicOut: true,
                                                    sleepOut: true, par: false))
        XCTAssertEqual(acta.conteo, String(localized: "Both of your votes fell outside."))
        XCTAssertEqual(acta.vigilantesLabel, String(localized: "Watching, not voting"))
    }
}
