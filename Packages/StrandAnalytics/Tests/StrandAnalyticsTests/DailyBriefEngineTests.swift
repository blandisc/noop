import XCTest
@testable import StrandAnalytics

/// FER-470 — el motor del Daily Brief. Prueba la DECISIÓN (selección/orden de viñetas, niveles), no el
/// copy localizado: los tests construyen `Readiness` sintéticos con el `public init` y afirman `kind`/
/// `flag`/`level`, nunca las cadenas es-MX.
final class DailyBriefEngineTests: XCTestCase {

    private func readiness(_ level: ReadinessEngine.Level,
                           signals: [ReadinessEngine.Signal]) -> ReadinessEngine.Readiness {
        ReadinessEngine.Readiness(level: level, headline: "", summary: "", signals: signals,
                                  acwr: nil, monotony: nil)
    }

    private func sig(_ key: String, _ flag: ReadinessEngine.Flag,
                     value: String? = nil) -> ReadinessEngine.Signal {
        ReadinessEngine.Signal(key: key, label: key, detail: key, flag: flag, value: value)
    }

    // MARK: invariante — no inventa brief sin veredicto

    func testInsufficientReturnsNil() {
        XCTAssertNil(DailyBriefEngine.make(readiness: readiness(.insufficient, signals: []),
                                           recovery: 80, recoveryBaseline: 70, sleepMinutes: 460))
    }

    // MARK: slot de sueño fijo

    func testSleepIsFixedFirstSlot() {
        let r = readiness(.strained, signals: [sig("hrv", .bad), sig("rhr", .watch)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 50, recoveryBaseline: 55, sleepMinutes: 460)!
        XCTAssertEqual(b.bullets.count, 3)
        XCTAssertEqual(b.bullets.first?.kind, .sleep)
        // tras el sueño, la peor señal (hrv bad) va primero del pool dinámico
        XCTAssertEqual(b.bullets[1].kind, .hrv)
    }

    func testNoSleepFillsThreeFromPool() {
        let r = readiness(.strained, signals: [sig("hrv", .bad), sig("rhr", .watch), sig("acwr", .watch)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 50, recoveryBaseline: 55, sleepMinutes: nil)!
        XCTAssertEqual(b.bullets.count, 3)
        XCTAssertFalse(b.bullets.contains { $0.kind == .sleep })
    }

    // MARK: orden — peor flag primero

    func testWorseFlagRanksFirst() {
        // recovery 80 ≥ banda verde → good; rhr bad → rhr debe ir primero.
        let r = readiness(.strained, signals: [sig("rhr", .bad)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 80, recoveryBaseline: 60, sleepMinutes: nil)!
        XCTAssertEqual(b.bullets.first?.kind, .rhr)
        XCTAssertEqual(b.bullets.first?.flag, .bad)
    }

    // MARK: desempate por prioridad de tipo a igual flag

    func testTypePriorityTiebreak() {
        // recovery 55 vs base 55 → neutral; hrv y acwr watch → ambos van antes que recovery,
        // y entre ellos hrv (prioridad 1) antes que acwr (prioridad 5).
        let r = readiness(.strained, signals: [sig("acwr", .watch), sig("hrv", .watch)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 55, recoveryBaseline: 55, sleepMinutes: nil)!
        let kinds = b.bullets.map(\.kind)
        XCTAssertEqual(kinds.first, .hrv)
        XCTAssertLessThan(kinds.firstIndex(of: .hrv)!, kinds.firstIndex(of: .acwr)!)
    }

    // MARK: mínimo 2 = recuperación-vs-base + una señal (sin sueño)

    func testMinimumTwoFromRecoveryPlusOneSignal() {
        let r = readiness(.balanced, signals: [sig("hrv", .good)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 70, recoveryBaseline: 60, sleepMinutes: nil)!
        XCTAssertEqual(b.bullets.count, 2)
        XCTAssertEqual(Set(b.bullets.map(\.kind)), [.recovery, .hrv])
    }

    // MARK: rango de conteo + nivel propagado

    func testCountRangeAndLevelPropagated() {
        let r = readiness(.primed, signals: [sig("hrv", .good), sig("rhr", .good)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 82, recoveryBaseline: 70, sleepMinutes: 460)!
        XCTAssertEqual(b.level, .primed)
        XCTAssertTrue((2...3).contains(b.bullets.count))
        XCTAssertFalse(b.titular.isEmpty)   // hay titular y porqué para un veredicto
        XCTAssertFalse(b.why.isEmpty)
    }

    // MARK: monotony se excluye del pool

    func testMonotonyExcluded() {
        let r = readiness(.strained, signals: [sig("monotony", .watch), sig("hrv", .bad)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 60, recoveryBaseline: 60, sleepMinutes: nil)!
        XCTAssertFalse(b.bullets.contains { $0.kind == .sleep })
        XCTAssertTrue(b.bullets.contains { $0.kind == .hrv })
        // monotony no tiene BulletKind → nunca aparece
        XCTAssertEqual(b.bullets.count, 2)   // recovery(neutral) + hrv(bad), monotony fuera
    }

    // MARK: viñeta de sueño — flag por suficiencia

    func testSleepSufficiencyFlags() {
        XCTAssertEqual(DailyBriefEngine.sleepBullet(300).flag, .watch)  // 5 h → corta
        XCTAssertEqual(DailyBriefEngine.sleepBullet(390).flag, .neutral) // 6 h 30 → intermedia
        XCTAssertEqual(DailyBriefEngine.sleepBullet(460).flag, .good)   // 7 h 40 → completa
    }

    // MARK: piso de 2 — degenerado devuelve nil (FER-470 / QA D1)

    /// Con veredicto pero solo la recuperación (sin sueño, sin base, sin señales del cuerpo) el brief no
    /// da para ≥2 viñetas → `make` devuelve nil y la página 1 cae al copy honesto. No produce un brief
    /// de una sola línea. (monotony se excluye, así que aquí el pool queda en solo recovery.)
    func testDegenerateBelowTwoReturnsNil() {
        let r = readiness(.balanced, signals: [sig("monotony", .watch)])
        XCTAssertNil(DailyBriefEngine.make(readiness: r, recovery: 70,
                                           recoveryBaseline: nil, sleepMinutes: nil))
    }

    /// Sin base aún (historial ralo) la recuperación SÍ es candidata (descrita por zona del dial), así que
    /// recuperación + una señal del cuerpo da 2 viñetas — el brief se muestra.
    func testRecoveryWithoutBaselineStillCounts() {
        let r = readiness(.balanced, signals: [sig("hrv", .good)])
        let b = DailyBriefEngine.make(readiness: r, recovery: 72,
                                      recoveryBaseline: nil, sleepMinutes: nil)!
        XCTAssertEqual(b.bullets.count, 2)
        XCTAssertEqual(Set(b.bullets.map(\.kind)), [.recovery, .hrv])
    }

    // MARK: viñeta de HRV estimada vs base SDNN (FER-623)

    /// El parámetro `hrvEstimated` es aditivo: omitirlo produce el MISMO brief que antes (default nil).
    func testHrvEstimatedDefaultsToNilAndIsAdditive() {
        let r = readiness(.balanced, signals: [sig("rhr", .good)])
        let withDefault = DailyBriefEngine.make(readiness: r, recovery: 70, recoveryBaseline: 60, sleepMinutes: nil)
        let explicitNil = DailyBriefEngine.make(readiness: r, recovery: 70, recoveryBaseline: 60,
                                                sleepMinutes: nil, hrvEstimated: nil)
        XCTAssertEqual(withDefault, explicitNil)
    }

    /// Día sin banda: el veredicto no trae señal de HRV (su SDNN se enmascaró). La viñeta estimada se inyecta
    /// como viñeta de HRV con su σ y flag — así el día Apple-only SÍ muestra su HRV, clasificada vs base SDNN.
    func testHrvEstimatedInjectedWhenNoBandSignal() {
        let r = readiness(.balanced, signals: [sig("rhr", .good)])   // sin señal de hrv
        let est = DailyBrief.HrvEstimatedBullet(z: 0.9, flag: .good)
        let b = DailyBriefEngine.make(readiness: r, recovery: 70, recoveryBaseline: 60,
                                      sleepMinutes: nil, hrvEstimated: est)!
        let hrv = b.bullets.first { $0.kind == .hrv }
        XCTAssertNotNil(hrv, "el día sin banda debe mostrar su HRV estimada")
        XCTAssertEqual(hrv?.flag, .good)
        XCTAssertEqual(hrv?.sub, "+0.9σ")
    }

    /// Nunca dos viñetas de HRV: si el veredicto YA trae una señal de banda, la estimada se ignora (un día
    /// es de una sola fuente — banda o Apple, no ambas).
    func testHrvEstimatedIgnoredWhenBandSignalPresent() {
        let r = readiness(.strained, signals: [sig("hrv", .bad, value: "-1.2σ")])
        let est = DailyBrief.HrvEstimatedBullet(z: 0.9, flag: .good)
        let b = DailyBriefEngine.make(readiness: r, recovery: 60, recoveryBaseline: 60,
                                      sleepMinutes: nil, hrvEstimated: est)!
        let hrvBullets = b.bullets.filter { $0.kind == .hrv }
        XCTAssertEqual(hrvBullets.count, 1)
        XCTAssertEqual(hrvBullets.first?.flag, .bad)   // ganó la de banda, no la estimada
    }

    // MARK: - Bloque «Hoy en tu plan» (FER-613)

    /// Sin split configurado el bloque se omite por completo (la UI no deja hueco).
    func testTrainingBlockNoSplitReturnsNil() {
        XCTAssertNil(DailyBriefEngine.trainingBlock(hasSplit: false, todayRoutineName: nil,
                                                    streakDays: 0, recovery: 80))
    }

    /// Con split pero sin rutina hoy → estado de descanso, sin ritmo. La racha viaja para el copy «N días».
    func testTrainingBlockRestDay() {
        let tb = DailyBriefEngine.trainingBlock(hasSplit: true, todayRoutineName: nil,
                                                streakDays: 5, recovery: 80)!
        XCTAssertEqual(tb.state, .rest)
        XCTAssertNil(tb.routineName)
        XCTAssertNil(tb.pace)
        XCTAssertNil(tb.paceCopy)
        XCTAssertEqual(tb.streakDays, 5)
    }

    /// Día de entreno con recuperación alta (≥ greenCut) → ritmo «sube» + su línea.
    func testTrainingBlockTrainingDayDialUp() {
        let tb = DailyBriefEngine.trainingBlock(hasSplit: true, todayRoutineName: "Empuje",
                                                streakDays: 4, recovery: 80)!
        XCTAssertEqual(tb.state, .training)
        XCTAssertEqual(tb.routineName, "Empuje")
        XCTAssertEqual(tb.streakDays, 4)
        XCTAssertEqual(tb.pace, .up)
        XCTAssertNotNil(tb.paceCopy)
    }

    /// Recuperación en banda media (entre redCut y greenCut) → ritmo «mantén».
    func testTrainingBlockTrainingDayHold() {
        let tb = DailyBriefEngine.trainingBlock(hasSplit: true, todayRoutineName: "Pierna",
                                                streakDays: 1, recovery: 50)!
        XCTAssertEqual(tb.pace, .hold)
    }

    /// Recuperación baja (< redCut) → ritmo «baja».
    func testTrainingBlockTrainingDayDialBack() {
        let tb = DailyBriefEngine.trainingBlock(hasSplit: true, todayRoutineName: "Pierna",
                                                streakDays: 2, recovery: 20)!
        XCTAssertEqual(tb.pace, .down)
    }

    /// Día de entreno SIN recuperación aún → el bloque sale igual (rutina + racha) pero sin línea de ritmo.
    func testTrainingBlockTrainingDayNoRecoveryDegradesGracefully() {
        let tb = DailyBriefEngine.trainingBlock(hasSplit: true, todayRoutineName: "Empuje",
                                                streakDays: 4, recovery: nil)!
        XCTAssertEqual(tb.state, .training)
        XCTAssertEqual(tb.routineName, "Empuje")
        XCTAssertNil(tb.pace)
        XCTAssertNil(tb.paceCopy)
    }

    // MARK: - «La conexión de hoy» (FER-614)

    /// Construye un Insight de correlación sintético (como los que emite InsightEngine para el par A·B).
    private func corr(_ metric: String, r: Double, significant: Bool, relevance: Double = 1) -> Insight {
        Insight(kind: .correlation, title: "", reading: "",
                datum: InsightDatum(value: r, unit: "r", metric: metric),
                evidence: InsightEvidence(n: 28, pValue: 0.01, pAdjusted: 0.02, effectSize: r, significant: significant),
                confidence: significant ? .candidate : .medium, relevance: relevance)
    }

    /// Sin insights → no hay conexión.
    func testConnectionEmptyReturnsNil() {
        XCTAssertNil(DailyBriefEngine.connection(insights: []))
    }

    /// Una correlación NO significativa no sube al brief (hedge honesto).
    func testConnectionNonSignificantReturnsNil() {
        XCTAssertNil(DailyBriefEngine.connection(insights: [corr("HRV·Recuperación", r: 0.2, significant: false)]))
    }

    /// Correlación directa (r≥0): nombra las dos señales, dirección «van de la mano», sin jerga (sin r/n).
    func testConnectionDirectNamesBothSignals() {
        let c = DailyBriefEngine.connection(insights: [corr("Sueño·Recuperación", r: 0.45, significant: true)])!
        XCTAssertEqual(c.text, "Tu Sueño y tu Recuperación van de la mano")
        XCTAssertEqual(c.insight.datum.metric, "Sueño·Recuperación")
        XCTAssertFalse(c.text.contains("r="))
        XCTAssertFalse(c.text.contains("n="))
    }

    /// Correlación inversa (r<0): dirección «se mueven al revés».
    func testConnectionInversePhrasing() {
        let c = DailyBriefEngine.connection(insights: [corr("FC en reposo·Recuperación", r: -0.4, significant: true)])!
        XCTAssertEqual(c.text, "Tu FC en reposo y tu Recuperación se mueven al revés")
    }

    /// Elige la PRIMERA correlación significativa (la lista ya viene rankeada), saltando las no significativas
    /// y los insights que no son correlación.
    func testConnectionPicksFirstSignificantCorrelation() {
        let behavior = Insight(kind: .behavior, title: "", reading: "",
                               datum: InsightDatum(value: 8, unit: "pts", metric: "Recuperación"),
                               evidence: InsightEvidence(n: 20, pValue: 0.01, pAdjusted: 0.02, effectSize: 0.6, significant: true),
                               confidence: .candidate, relevance: 3)
        let insights = [behavior,
                        corr("HRV·Recuperación", r: 0.1, significant: false),
                        corr("Sueño·Recuperación", r: 0.5, significant: true)]
        let c = DailyBriefEngine.connection(insights: insights)!
        XCTAssertEqual(c.insight.datum.metric, "Sueño·Recuperación")
    }

    /// `connectionText` solo aplica a correlaciones.
    func testConnectionTextNonCorrelationReturnsNil() {
        let trend = Insight(kind: .trend, title: "", reading: "",
                            datum: InsightDatum(value: 5, unit: "pts", metric: "Recuperación"),
                            evidence: InsightEvidence(n: 14, pValue: nil, pAdjusted: nil, effectSize: nil, significant: false),
                            confidence: .medium, relevance: 1)
        XCTAssertNil(DailyBriefEngine.connectionText(for: trend))
    }

    // MARK: - «La conexión de hoy» con experimento (FER-615)

    private func exp(pending: Bool, day: Int = 3) -> DailyBriefEngine.ActiveExperiment {
        DailyBriefEngine.ActiveExperiment(behaviorLabel: "Meditación", outcomeLabel: "Recuperación",
                                          dayNumber: day, pendingCheckIn: pending)
    }

    /// El renglón del experimento: título cruzado + el día en curso, sin jerga.
    func testExperimentLineText() {
        let line = DailyBriefEngine.experimentLine(exp(pending: true))
        XCTAssertEqual(line.text, "Vas en el día 3 de “Meditación → Recuperación”")
        XCTAssertTrue(line.pendingCheckIn)
    }

    /// Sin experimento → cae a la correlación de F2 (mismo comportamiento).
    func testDayConnectionNoExperimentFallsToCorrelation() {
        let c = DailyBriefEngine.dayConnection(
            insights: [corr("Sueño·Recuperación", r: 0.45, significant: true)], experiment: nil)
        guard case .correlation(let conn)? = c else { return XCTFail("esperaba correlación") }
        XCTAssertEqual(conn.text, "Tu Sueño y tu Recuperación van de la mano")
    }

    /// Sin experimento ni correlación → nil (se omite el renglón).
    func testDayConnectionEmptyReturnsNil() {
        XCTAssertNil(DailyBriefEngine.dayConnection(insights: [], experiment: nil))
    }

    /// Prioridad 1: con check-in pendiente hoy, el experimento gana aunque haya correlación significativa.
    func testDayConnectionPendingCheckInWinsOverCorrelation() {
        let c = DailyBriefEngine.dayConnection(
            insights: [corr("Sueño·Recuperación", r: 0.5, significant: true)], experiment: exp(pending: true))
        guard case .experiment(let line)? = c else { return XCTFail("esperaba experimento") }
        XCTAssertTrue(line.pendingCheckIn)
    }

    /// Prioridad 2: sin check-in pendiente, gana la correlación significativa (mayor relevancia, F2).
    func testDayConnectionCorrelationWinsWhenNoPendingCheckIn() {
        let c = DailyBriefEngine.dayConnection(
            insights: [corr("Sueño·Recuperación", r: 0.5, significant: true)], experiment: exp(pending: false))
        guard case .correlation(let conn)? = c else { return XCTFail("esperaba correlación") }
        XCTAssertEqual(conn.insight.datum.metric, "Sueño·Recuperación")
    }

    /// Prioridad 3: sin check-in pendiente y sin correlación significativa, gana el estado del experimento.
    func testDayConnectionExperimentShownWhenNoCorrelation() {
        let c = DailyBriefEngine.dayConnection(
            insights: [corr("HRV·Recuperación", r: 0.1, significant: false)], experiment: exp(pending: false))
        guard case .experiment(let line)? = c else { return XCTFail("esperaba experimento") }
        XCTAssertFalse(line.pendingCheckIn)
        XCTAssertEqual(line.text, "Vas en el día 3 de “Meditación → Recuperación”")
    }
}
