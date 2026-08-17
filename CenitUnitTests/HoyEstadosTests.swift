import XCTest
import StrandAnalytics
import StrandModels
@testable import Cenit

// MARK: - HoyEstadosTests (FER-51 · Ola 4 · máquina T1–T5)
//
// Criterio 34 del REQ: fixtures de causaT3, SilencioSalud.disparaT4 y plantilla
// (precedencia T5 > T4 > T3 > T2 > T1). Puros; correctos por lectura (corren en
// CenitUnitTests con simulador).

final class HoyEstadosTests: XCTestCase {

    // MARK: Fixtures de calendario

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// Construye una fecha en UTC fija.
    private func date(y: Int, m: Int, d: Int, h: Int, min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = min
        return cal.date(from: comps)!
    }

    private func ventana(now: Date, sesionFinHoy: Date? = nil)
        -> LiquidHoyBuilder.VentanaNocturna {
        LiquidHoyBuilder.VentanaNocturna.evaluar(
            now: now, calendar: cal, sesionFinHoy: sesionFinHoy)
    }

    private func prep(_ verdict: Preparedness.Verdict) -> Preparedness.Read {
        Preparedness.Read(
            verdict: verdict, drivers: [],
            signalsPresent: 0, signalsTotal: 0,
            maturity: verdict == .lowSignal ? .calibrating : .trusted,
            autonomicNights: verdict == .lowSignal ? 2 : 21,
            trend: nil)
    }

    // MARK: causaT3 — 5 fixtures del criterio 34

    /// Mañana, ventana cerrada, import fresco, noche vacía → nocheNoRegistrada.
    func test_causaT3_manana_importFresco_nocheVacia() {
        // 2026-08-05 12:00 UTC → hora local 12 ≥ 11 → ventana cerrada.
        let now = date(y: 2026, m: 8, d: 5, h: 12)
        let v = ventana(now: now)
        XCTAssertFalse(v.abierta, "a las 12 la ventana ya cerró")
        // Import DESPUÉS del inicio de ventana (21:00 de ayer).
        let lastSync = date(y: 2026, m: 8, d: 5, h: 8)
        XCTAssertGreaterThanOrEqual(lastSync, v.inicio)
        let causa = LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: lastSync, hayNocheRegistrada: false)
        XCTAssertEqual(causa, .nocheNoRegistrada)
    }

    /// Tarde, import viejo (anterior al inicio de ventana) → sinSync.
    func test_causaT3_tarde_importViejo() {
        let now = date(y: 2026, m: 8, d: 5, h: 16)
        let v = ventana(now: now)
        XCTAssertFalse(v.abierta)
        let lastSync = date(y: 2026, m: 8, d: 4, h: 10) // antes de 21:00 del 4
        XCTAssertLessThan(lastSync, v.inicio)
        let causa = LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: lastSync, hayNocheRegistrada: true)
        XCTAssertEqual(causa, .sinSync)
    }

    /// Precedencia: import viejo ∧ noche vacía → gana sinSync (no nocheNoRegistrada).
    func test_causaT3_precedencia_importViejo_sobre_nocheVacia() {
        let now = date(y: 2026, m: 8, d: 5, h: 14)
        let v = ventana(now: now)
        let lastSync = date(y: 2026, m: 8, d: 4, h: 12)
        XCTAssertLessThan(lastSync, v.inicio)
        let causa = LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: lastSync, hayNocheRegistrada: false)
        XCTAssertEqual(causa, .sinSync, "import viejo gana sobre noche vacía")
    }

    /// Noche completa registrada con import fresco → no es nocheNoRegistrada (leyendo).
    func test_causaT3_nocheCompleta_noAplicaNocheVacia() {
        let now = date(y: 2026, m: 8, d: 5, h: 13)
        let v = ventana(now: now)
        let lastSync = date(y: 2026, m: 8, d: 5, h: 7)
        XCTAssertGreaterThanOrEqual(lastSync, v.inicio)
        let causa = LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: lastSync, hayNocheRegistrada: true)
        // C2 (revisión conceptual 2026-08-15): con la ventana CERRADA y la noche registrada
        // pero sin veredicto, «Reading your night…» era una promesa eterna (iPhone sin
        // Watch). Ahora dice la verdad: noche registrada, falta señal.
        XCTAssertEqual(causa, .senalInsuficiente, "noche completa sin veredicto: señal insuficiente")
        XCTAssertNotEqual(causa, .nocheNoRegistrada)
    }

    /// FER-73 · H12: noche registrada + base FORMÁNDOSE ⇒ `.calibrando` (la franja calla; el
    /// héroe ya dice «Night N of M»). Sin calibrar, el mismo caso sigue siendo señal insuficiente.
    func test_causaT3_calibrando_gana_a_senalInsuficiente() {
        let now = date(y: 2026, m: 8, d: 5, h: 13)
        let v = ventana(now: now)
        let lastSync = date(y: 2026, m: 8, d: 5, h: 7)
        XCTAssertEqual(LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: lastSync, hayNocheRegistrada: true, calibrando: true), .calibrando)
        // Sin noche registrada, calibrar NO tapa la causa útil («la noche no se registró»).
        XCTAssertEqual(LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: lastSync, hayNocheRegistrada: false, calibrando: true), .nocheNoRegistrada)
        // Un import viejo sigue ganando: «pull down to sync» es accionable aun calibrando.
        XCTAssertEqual(LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: date(y: 2026, m: 8, d: 3, h: 12), hayNocheRegistrada: true,
            calibrando: true), .sinSync)
    }

    /// FER-73 · H20: sync EN CURSO ⇒ `.leyendo` aunque `lastSync` sea nil (arranque en frío):
    /// antes la franja pedía «pull down to sync» mientras el sync automático ya corría.
    func test_causaT3_syncing_gana_a_sinSync() {
        let now = date(y: 2026, m: 8, d: 5, h: 13)
        let v = ventana(now: now)
        XCTAssertEqual(LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: nil, hayNocheRegistrada: false, syncing: true), .leyendo)
        XCTAssertEqual(LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: nil, hayNocheRegistrada: false, syncing: false), .sinSync)
    }

    /// FER-73 · H13: solo una sesión ≥ 3 h que TERMINA HOY sella la noche; una siesta de ayer
    /// por la tarde (la sesión más tardía desde ayer al mediodía) ya no cierra la ventana.
    func test_hayNocheQueTerminaHoy_ignora_siesta_de_ayer() {
        let now = date(y: 2026, m: 8, d: 5, h: 8)
        func s(_ ini: Date, _ fin: Date) -> CachedSleepSession {
            CachedSleepSession(startTs: Int(ini.timeIntervalSince1970), endTs: Int(fin.timeIntervalSince1970),
                               efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
        }
        let siesta = s(date(y: 2026, m: 8, d: 4, h: 15), date(y: 2026, m: 8, d: 4, h: 16))
        let noche = s(date(y: 2026, m: 8, d: 4, h: 23), date(y: 2026, m: 8, d: 5, h: 6, min: 40))
        let siestaHoy = s(date(y: 2026, m: 8, d: 5, h: 6), date(y: 2026, m: 8, d: 5, h: 7))
        XCTAssertFalse(TodayView.hayNocheQueTerminaHoy(sessions: [siesta], calendar: cal, now: now))
        XCTAssertFalse(TodayView.hayNocheQueTerminaHoy(sessions: [siestaHoy], calendar: cal, now: now),
                       "una hora que termina hoy no es la noche")
        XCTAssertTrue(TodayView.hayNocheQueTerminaHoy(sessions: [siesta, noche], calendar: cal, now: now))
    }

    /// Ventana abierta ∧ import viejo → leyendo (SIEMPRE, sin importar el import).
    func test_causaT3_ventanaAbierta_importViejo_leyendo() {
        // 08:00 < 11 → ventana abierta (sin sesión que termine hoy).
        let now = date(y: 2026, m: 8, d: 5, h: 8)
        let v = ventana(now: now)
        XCTAssertTrue(v.abierta, "antes de las 11 sin sesión la ventana está abierta")
        let lastSync = date(y: 2026, m: 8, d: 3, h: 12) // muy viejo
        let causa = LiquidHoyBuilder.causaT3(
            ventana: v, lastSync: lastSync, hayNocheRegistrada: false)
        XCTAssertEqual(causa, .leyendo)
    }

    /// Sesión que termina hoy cierra la ventana aunque sea de madrugada.
    func test_ventanaNocturna_sesionFinHoy_cierra() {
        let now = date(y: 2026, m: 8, d: 5, h: 7)
        let sesionFin = date(y: 2026, m: 8, d: 5, h: 6, min: 30)
        let v = ventana(now: now, sesionFinHoy: sesionFin)
        XCTAssertFalse(v.abierta)
        // Inicio sigue siendo 21:00 de ayer.
        let expected = date(y: 2026, m: 8, d: 4, h: 21)
        XCTAssertEqual(v.inicio, expected)
    }

    // MARK: SilencioSalud.disparaT4

    func test_silencioT4_usuarioNuevo_noDispara() {
        let s = LiquidHoyBuilder.SilencioSalud(tipos: [
            (tuvo14d: false, vacio48h: true),
            (tuvo14d: false, vacio48h: true),
            (tuvo14d: false, vacio48h: true),
        ])
        XCTAssertFalse(s.disparaT4, "usuario nuevo (sin historia 14 d) no dispara T4")
    }

    func test_silencioT4_dosTipos_siDispara() {
        let s = LiquidHoyBuilder.SilencioSalud(tipos: [
            (tuvo14d: true, vacio48h: true),
            (tuvo14d: true, vacio48h: true),
            (tuvo14d: false, vacio48h: true),
        ])
        XCTAssertTrue(s.disparaT4, "2 tipos con tuvo14d ∧ vacio48h disparan T4")
    }

    func test_silencioT4_unSoloTipo_noDispara() {
        let s = LiquidHoyBuilder.SilencioSalud(tipos: [
            (tuvo14d: true, vacio48h: true),
            (tuvo14d: true, vacio48h: false),
            (tuvo14d: false, vacio48h: true),
        ])
        XCTAssertFalse(s.disparaT4)
    }

    // MARK: plantilla — T5 > T4 > T3 > T2 > T1

    func test_plantilla_T5_gana_sobre_todo() {
        let p = LiquidHoyBuilder.plantilla(
            prep: prep(.full), healthConnected: true, hasAnySource: false,
            silencioT4: nil, causaT3: nil)
        XCTAssertEqual(p, .t5Dormido)
    }

    func test_plantilla_T4_sinPermiso() {
        // T4 aplica SIN veredicto real (con veredicto, éste manda — ver test abajo).
        let p = LiquidHoyBuilder.plantilla(
            prep: nil, healthConnected: false, hasAnySource: true,
            silencioT4: nil, causaT3: nil)
        XCTAssertEqual(p, .t4SinPermiso)
    }

    func test_plantilla_veredicto_manda_sobre_T4() {
        // Estudio en frío R2: la franja «sin lectura» junto a un héroe que afirma
        // «En tu rango» confundía a todos los perfiles — el veredicto calla la franja
        // (Salud desconectada ya tiene su propio banner).
        let p = LiquidHoyBuilder.plantilla(
            prep: prep(.full), healthConnected: false, hasAnySource: true,
            silencioT4: nil, causaT3: nil)
        XCTAssertEqual(p, .t1Pleno)
    }

    func test_plantilla_T4_porSilencio() {
        let silencio = LiquidHoyBuilder.SilencioSalud(tipos: [
            (tuvo14d: true, vacio48h: true),
            (tuvo14d: true, vacio48h: true),
            (tuvo14d: false, vacio48h: false),
        ])
        let p = LiquidHoyBuilder.plantilla(
            prep: nil, healthConnected: true, hasAnySource: true,
            silencioT4: silencio, causaT3: nil)
        XCTAssertEqual(p, .t4SinPermiso)
    }

    func test_plantilla_T3_sinPrep() {
        let p = LiquidHoyBuilder.plantilla(
            prep: nil, healthConnected: true, hasAnySource: true,
            silencioT4: nil, causaT3: .sinSync)
        XCTAssertEqual(p, .t3SinVeredicto(.sinSync))
    }

    func test_plantilla_T3_lowSignal() {
        let p = LiquidHoyBuilder.plantilla(
            prep: prep(.lowSignal), healthConnected: true, hasAnySource: true,
            silencioT4: nil, causaT3: .leyendo)
        XCTAssertEqual(p, .t3SinVeredicto(.leyendo))
    }

    func test_plantilla_T2_caution() {
        let p = LiquidHoyBuilder.plantilla(
            prep: prep(.caution), healthConnected: true, hasAnySource: true,
            silencioT4: nil, causaT3: nil)
        XCTAssertEqual(p, .t2Provisional)
    }

    func test_plantilla_T2_easy() {
        let p = LiquidHoyBuilder.plantilla(
            prep: prep(.easy), healthConnected: true, hasAnySource: true,
            silencioT4: nil, causaT3: nil)
        XCTAssertEqual(p, .t2Provisional)
    }

    func test_plantilla_T1_full() {
        let p = LiquidHoyBuilder.plantilla(
            prep: prep(.full), healthConnected: true, hasAnySource: true,
            silencioT4: nil, causaT3: nil)
        XCTAssertEqual(p, .t1Pleno)
    }

    func test_plantilla_precedencia_T4_sobre_T3() {
        // Sin prep (sería T3) pero sin permiso → T4 gana.
        let p = LiquidHoyBuilder.plantilla(
            prep: nil, healthConnected: false, hasAnySource: true,
            silencioT4: nil, causaT3: .leyendo)
        XCTAssertEqual(p, .t4SinPermiso)
    }
}
