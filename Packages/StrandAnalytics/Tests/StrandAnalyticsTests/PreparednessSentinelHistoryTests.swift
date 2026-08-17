import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-33 — `Read.sentinelHistory`: the sentinel's per-night signals for the whole window, so the
/// guardian sheet can DRAW the rule it explains instead of re-deriving the engine's cuts in the app
/// layer (where the picture and the vote would drift apart the day a threshold moves).
///
/// The contract these tests pin is PARITY, not new math: the history is a pure projection of the
/// same forward pass that already feeds `sentinel`, so its tail must agree with `sentinel` on every
/// fixture, and the vote must stay bit-identical (the frozen Preparedness suites cover that and are
/// untouched here).
final class PreparednessSentinelHistoryTests: XCTestCase {

    // MARK: Fixtures (same shape as PreparednessSentinelStreakTests, so the two read alike)

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, temp: Double? = 0.0) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp, respRateBpm: resp)
    }

    private func baseline() -> [DailyMetric] {
        (1...20).map { i in
            dm(String(format: "2026-06-%02d", i),
               hrv: 52 + Double(i % 5), rhr: 54 + i % 3, resp: 13 + Double(i % 3), temp: 0.0)
        }
    }

    private func corroborated(_ day: String) -> DailyMetric { dm(day, resp: 18, temp: 0.9) }
    private func watchingTemp(_ day: String)  -> DailyMetric { dm(day, resp: 14, temp: 0.9) }
    private func watchingResp(_ day: String)  -> DailyMetric { dm(day, resp: 18, temp: 0.0) }
    private func quiet(_ day: String)         -> DailyMetric { dm(day, resp: 14, temp: 0.0) }

    private func read(_ days: [DailyMetric], asOf: String) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: nil, asOf: asOf,
                                    nocturnalRestingHr: [:], cyclePhase: nil, nocturnalRmssd: nil))
    }

    // MARK: The tail agrees with `sentinel` on all four combinations

    func testTailMatchesSentinel_quiet() throws {
        let r = read(baseline() + [quiet("2026-06-21")], asOf: "2026-06-21")
        let s = try XCTUnwrap(r.sentinel)
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertEqual(last.day, "2026-06-21")
        XCTAssertEqual(last.tempOut, s.tempOut)
        XCTAssertEqual(last.respOut, s.respOut)
        XCTAssertFalse(last.tempOut || last.respOut)
    }

    func testTailMatchesSentinel_watchingTemp() throws {
        let r = read(baseline() + [watchingTemp("2026-06-21")], asOf: "2026-06-21")
        let s = try XCTUnwrap(r.sentinel)
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertEqual(last.tempOut, s.tempOut)
        XCTAssertEqual(last.respOut, s.respOut)
        XCTAssertTrue(last.tempOut)
        XCTAssertFalse(last.respOut)
    }

    func testTailMatchesSentinel_watchingResp() throws {
        let r = read(baseline() + [watchingResp("2026-06-21")], asOf: "2026-06-21")
        let s = try XCTUnwrap(r.sentinel)
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertEqual(last.tempOut, s.tempOut)
        XCTAssertEqual(last.respOut, s.respOut)
        XCTAssertFalse(last.tempOut)
        XCTAssertTrue(last.respOut)
    }

    func testTailMatchesSentinel_corroborated() throws {
        let r = read(baseline() + [corroborated("2026-06-21")], asOf: "2026-06-21")
        let s = try XCTUnwrap(r.sentinel)
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertEqual(last.tempOut, s.tempOut)
        XCTAssertEqual(last.respOut, s.respOut)
        XCTAssertTrue(last.tempOut && last.respOut)
    }

    // MARK: The history covers the window, in order

    func testHistoryCoversEveryNightInOrder() {
        let days = baseline() + [quiet("2026-06-21"), corroborated("2026-06-22")]
        let r = read(days, asOf: "2026-06-22")
        XCTAssertEqual(r.sentinelHistory.count, days.count)
        XCTAssertEqual(r.sentinelHistory.map(\.day), days.map(\.day),
                       "oldest → newest, one entry per input night")
    }

    // MARK: The streak the copy uses and the picture the sheet draws agree

    func testStreakAgreesWithHistoryTail() throws {
        let days = baseline() + [corroborated("2026-06-21"),
                                 corroborated("2026-06-22"),
                                 corroborated("2026-06-23")]
        let r = read(days, asOf: "2026-06-23")
        let s = try XCTUnwrap(r.sentinel)
        XCTAssertEqual(s.state, .corroborated)
        XCTAssertEqual(s.streakNights, 3)
        // The diagram must show exactly those three nights with BOTH signals out, and the night
        // before them quiet — otherwise the drawn rule contradicts the copy above it.
        let tail = r.sentinelHistory.suffix(3)
        XCTAssertTrue(tail.allSatisfy { $0.tempOut && $0.respOut })
        let beforeStreak = try XCTUnwrap(r.sentinelHistory.dropLast(3).last)
        XCTAssertFalse(beforeStreak.tempOut && beforeStreak.respOut)
    }

    func testLoneSignalNightIsDrawnAsLone() throws {
        // The rule the sheet draws: one signal out never pairs. The history has to show it that way.
        let r = read(baseline() + [watchingTemp("2026-06-21")], asOf: "2026-06-21")
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertTrue(last.tempOut)
        XCTAssertFalse(last.respOut, "a lone temp night must never render as a confirmed pair")
    }

    // MARK: Missing readings are distinguishable from "in range"

    func testMissingReadingsAreFlagged() throws {
        let days = baseline() + [dm("2026-06-21", resp: nil, temp: nil)]
        let r = read(days, asOf: "2026-06-21")
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertTrue(last.tempMissing)
        XCTAssertTrue(last.respMissing)
        XCTAssertFalse(last.tempOut)
        XCTAssertFalse(last.respOut)
    }

    func testPresentReadingsAreNotFlaggedMissing() throws {
        let r = read(baseline() + [quiet("2026-06-21")], asOf: "2026-06-21")
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertFalse(last.tempMissing)
        XCTAssertFalse(last.respMissing)
    }

    func testOneSignalMissingWhileTheOtherReads() throws {
        let days = baseline() + [dm("2026-06-21", resp: 18, temp: nil)]
        let r = read(days, asOf: "2026-06-21")
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertTrue(last.tempMissing)
        XCTAssertFalse(last.respMissing)
    }

    // MARK: The low-signal path reports nothing rather than something false

    /// FER-77 · CONTRATO NUEVO: sin señal autonómica no hay VEREDICTO, pero el centinela juzga
    /// otras dos señales (temperatura y respiración) y su juicio sigue siendo válido — son
    /// independientes del eje que faltó. Antes se devolvía todo vacío y el guardián perdía su
    /// historia entera cada día sin veredicto. Lo que NO cambia: el centinela nunca vota aquí, y
    /// la superficie sigue exigiendo por su lado el sello de noche y el par completo (FER-73).
    func testLowSignalPathConservaLaHistoriaDelCentinela() {
        let days = (1...20).map { i in
            dm(String(format: "2026-06-%02d", i), hrv: nil, rhr: nil, resp: nil, temp: 0.0)
        }
        let r = read(days, asOf: "2026-06-20")
        XCTAssertEqual(r.verdict, .lowSignal, "sin FC en reposo no hay veredicto")
        XCTAssertFalse(r.sentinelHistory.isEmpty, "la historia del par no se borra")
        XCTAssertEqual(r.sentinelHistory.last?.day, "2026-06-20")
        XCTAssertFalse(r.autonomicPossible, "nunca hubo FC en reposo en la ventana")
        // Y sin respiración, la noche queda marcada como NO juzgada: «no lo pude juzgar» jamás
        // puede leerse como «en rango».
        XCTAssertEqual(r.sentinelHistory.last?.respMissing, true)
        XCTAssertEqual(r.sentinelHistory.last?.respJudged, false)
    }

    // MARK: «No lo pude juzgar» no puede leerse como «en rango» (hallazgo del gate numérico)

    func testRespiracionSinBaseNoSeConfundeConEnRango() throws {
        // Una respiración absurda en la CABEZA de la ventana, donde la base todavía no es
        // usable: el motor no la marca, pero tampoco la aprueba. Sin `respJudged`, esta noche
        // se serializa idéntica a una tranquila y el diagrama del guardián dibujaría calma
        // donde el motor dijo «no sé».
        let days = [dm("2026-06-01", resp: 35, temp: 0.0)] + baseline().dropFirst()
        let r = read(days, asOf: "2026-06-20")
        let primera = try XCTUnwrap(r.sentinelHistory.first)
        XCTAssertEqual(primera.day, "2026-06-01")
        XCTAssertFalse(primera.respOut, "sin base usable el motor no marca")
        XCTAssertFalse(primera.respMissing, "sí hubo lectura")
        XCTAssertFalse(primera.respJudged, "pero NO fue juzgada: la UI no puede pintarla tranquila")
    }

    func testRespiracionConBaseMaduraSiEstaJuzgada() throws {
        let r = read(baseline() + [quiet("2026-06-21")], asOf: "2026-06-21")
        let last = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertTrue(last.respJudged)
        XCTAssertFalse(last.respOut)
    }

    func testTemperaturaNoNecesitaGemelo() throws {
        // El corte de temperatura es absoluto (°C de desviación), así que toda lectura es
        // juzgable: la asimetría de la API es deliberada, no un olvido.
        let days = [dm("2026-06-01", resp: nil, temp: 0.9)] + baseline().dropFirst()
        let r = read(days, asOf: "2026-06-20")
        let primera = try XCTUnwrap(r.sentinelHistory.first)
        XCTAssertTrue(primera.tempOut, "sin base y aun así marcada: el corte no depende de baseline")
    }

    // MARK: Un hueco de calendario no puede dibujarse como racha

    func testHuecoDeCalendarioSeMarca() throws {
        // El centinela rompe la racha cuando faltan noches; si el historial no lo dijera, un
        // diagrama equiespaciado mostraría como seguidas dos noches separadas por días.
        let days = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-25")]
        let r = read(days, asOf: "2026-06-25")
        let ultima = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertTrue(ultima.gapBefore, "del 21 al 25 hay hueco")
        let s = try XCTUnwrap(r.sentinel)
        XCTAssertEqual(s.streakNights, 1, "y la racha del motor tampoco lo cruza")
    }

    func testNochesContiguasNoMarcanHueco() throws {
        let days = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-22")]
        let r = read(days, asOf: "2026-06-22")
        let ultima = try XCTUnwrap(r.sentinelHistory.last)
        XCTAssertFalse(ultima.gapBefore)
        XCTAssertEqual(try XCTUnwrap(r.sentinel).streakNights, 2)
    }

    func testLaPrimeraNocheNoInventaHueco() throws {
        let r = read(baseline() + [quiet("2026-06-21")], asOf: "2026-06-21")
        let primera = try XCTUnwrap(r.sentinelHistory.first)
        XCTAssertFalse(primera.gapBefore, "sin predecesora no hay hueco que afirmar")
    }

    // MARK: The addition is inert for the vote

    func testHistoryDoesNotChangeTheVerdict() {
        // Same fixture as the streak suite's corroborated case: exposing the history must not move
        // the verdict by a hair (it is a projection, not a new term).
        let days = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-22")]
        let withHistory = read(days, asOf: "2026-06-22")
        XCTAssertEqual(withHistory.verdict, read(days, asOf: "2026-06-22").verdict)
        XCTAssertFalse(withHistory.sentinelHistory.isEmpty)
    }
}
