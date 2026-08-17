import XCTest
import StrandAnalytics
@testable import Cenit

// MARK: - MorningReadingSchedulerTests (FER-114)
//
// El aviso matutino se decide con funciones PURAS (`hayLectura`, `proximasOcurrencias`, `plan`,
// `contenido`), justo para poder fijarlo aquí sin `UNUserNotificationCenter`, sin permisos y sin
// simulador con reloj real: los efectos (pedir permiso, cancelar, agregar) son una capa delgada
// encima de estas cuatro.
//
// Lo que estas pruebas defienden, en orden de importancia:
//   1. Nunca se manda un aviso sin lectura que dar (calibrando, `lowSignal`, sin noche anclada,
//      switch apagado → plan VACÍO).
//   2. La palabra del aviso es LA MISMA del héroe, letra por letra, y solo viaja el día en que
//      todavía es verdad. Un aviso de mañana jamás lleva la palabra de hoy.
//   3. Cambiar la hora mueve todas las fechas; el horizonte no se salta días ni cuando el reloj
//      brinca por el horario de verano.

final class MorningReadingSchedulerTests: XCTestCase {

    private typealias Aviso = MorningReadingScheduler.Aviso

    // MARK: Fixtures

    /// Calendario fijo (Ciudad de México, sin horario de verano desde 2022) para que las fechas de
    /// las pruebas no dependan de la zona de la máquina que las corre.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    private func fecha(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int,
                       _ calendar: Calendar? = nil) -> Date {
        (calendar ?? cal).date(from: DateComponents(year: y, month: m, day: d,
                                                    hour: h, minute: min))!
    }

    /// Una lectura CON veredicto: noche grabada (el eje de sueño trae dato) + veredicto real.
    private func conVeredicto(_ verdict: Preparedness.Verdict) -> Preparedness.Read {
        Preparedness.Read(verdict: verdict,
                          drivers: [.init(axis: .sleep, state: .inRange, orientedZ: 0.3),
                                    .init(axis: .autonomic, state: .inRange, orientedZ: 0.1)],
                          signalsPresent: 2, signalsTotal: 3,
                          maturity: .trusted, autonomicNights: 30, trend: nil)
    }

    /// «Lectura de día» (FER-1033): hay señales, pero NINGUNA noche grabada. El héroe no da palabra
    /// aquí, así que el aviso tampoco puede.
    private func sinNocheAnclada() -> Preparedness.Read {
        Preparedness.Read(verdict: .full,
                          drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: 0.1)],
                          signalsPresent: 1, signalsTotal: 3,
                          maturity: .trusted, autonomicNights: 30, trend: nil)
    }

    /// La base todavía se está formando: el motor devuelve `lowSignal`.
    private func calibrando() -> Preparedness.Read {
        Preparedness.Read(verdict: .lowSignal,
                          drivers: [.init(axis: .sleep, state: .inRange, orientedZ: 0.2)],
                          signalsPresent: 1, signalsTotal: 3,
                          maturity: .calibrating, autonomicNights: 2, trend: nil)
    }

    private func plan(_ prep: Preparedness.Read?,
                      enabled: Bool = true, hour: Int = 7, minute: Int = 0,
                      now: Date, calendar: Calendar? = nil,
                      dias: Int = MorningReadingScheduler.horizonteDias)
        -> [MorningReadingScheduler.Slot] {
        MorningReadingScheduler.plan(prep: prep, enabled: enabled, hour: hour, minute: minute,
                                     now: now, calendar: calendar ?? cal, dias: dias)
    }

    // MARK: 1 · Callar es la opción por defecto

    func test_silencio_sinLecturaDelMotor() {
        XCTAssertTrue(plan(nil, now: fecha(2026, 8, 17, 6, 0)).isEmpty)
        XCTAssertFalse(MorningReadingScheduler.hayLectura(nil))
    }

    func test_silencio_conLowSignal() {
        let prep = Preparedness.Read(verdict: .lowSignal,
                                     drivers: [.init(axis: .sleep, state: .inRange, orientedZ: 0)],
                                     signalsPresent: 1, signalsTotal: 3,
                                     maturity: .trusted, autonomicNights: 30, trend: nil)
        XCTAssertFalse(MorningReadingScheduler.hayLectura(prep))
        XCTAssertTrue(plan(prep, now: fecha(2026, 8, 17, 6, 0)).isEmpty)
    }

    /// Calibrando NO se avisa: «Conociéndote» no es una lectura, es una promesa en curso.
    func test_silencio_mientrasCalibra() {
        XCTAssertFalse(MorningReadingScheduler.hayLectura(calibrando()))
        XCTAssertTrue(plan(calibrando(), now: fecha(2026, 8, 17, 6, 0)).isEmpty)
    }

    /// Sin noche grabada el héroe se degrada a «lectura de día» y no dice palabra: el aviso calla.
    func test_silencio_sinNocheAnclada() {
        XCTAssertFalse(MorningReadingScheduler.hayLectura(sinNocheAnclada()))
        XCTAssertTrue(plan(sinNocheAnclada(), now: fecha(2026, 8, 17, 6, 0)).isEmpty)
    }

    func test_silencio_conElSwitchApagado() {
        XCTAssertTrue(plan(conVeredicto(.full), enabled: false, now: fecha(2026, 8, 17, 6, 0)).isEmpty)
    }

    func test_silencio_conHoraImposible() {
        XCTAssertTrue(plan(conVeredicto(.full), hour: 24, now: fecha(2026, 8, 17, 6, 0)).isEmpty)
        XCTAssertTrue(plan(conVeredicto(.full), hour: 7, minute: 60,
                           now: fecha(2026, 8, 17, 6, 0)).isEmpty)
    }

    // MARK: 2 · La palabra es la del héroe, y solo el día en que sigue siendo verdad

    func test_elAvisoDeHoy_llevaLaPalabraDelHeroe() {
        let slots = plan(conVeredicto(.caution), hour: 7, now: fecha(2026, 8, 17, 6, 0))
        XCTAssertEqual(slots.first?.aviso,
                       Aviso.lectura(palabra: LiquidHoyBuilder.palabraVeredicto(.caution)))
        XCTAssertEqual(slots.first?.fecha, fecha(2026, 8, 17, 7, 0))
    }

    /// Los tres veredictos que sí tienen palabra: la del aviso y la del héroe salen de la MISMA
    /// clave del catálogo, así que cambiar `hero.title.*` cambia las dos a la vez.
    func test_lasTresPalabras_sonLasDelHeroe() {
        for v in [Preparedness.Verdict.full, .caution, .easy] {
            let slots = plan(conVeredicto(v), hour: 7, now: fecha(2026, 8, 17, 6, 0))
            XCTAssertEqual(slots.first?.aviso,
                           Aviso.lectura(palabra: LiquidHoyBuilder.palabraVeredicto(v)),
                           "el aviso de \(v) no dice la palabra del héroe")
        }
    }

    /// Con la hora ya pasada, el siguiente aviso es MAÑANA: y mañana la lectura de hoy ya no será
    /// verdad, así que va sin palabra. Este es el caso que evita que la app se contradiga.
    func test_siLaHoraYaPaso_elSiguienteAvisoEsManana_ySinPalabra() {
        let slots = plan(conVeredicto(.full), hour: 7, now: fecha(2026, 8, 17, 9, 30))
        XCTAssertEqual(slots.first?.fecha, fecha(2026, 8, 18, 7, 0))
        XCTAssertEqual(slots.first?.aviso, Aviso.cita)
    }

    func test_ningunAvisoDeUnDiaFuturo_llevaPalabra() {
        let slots = plan(conVeredicto(.easy), hour: 7, now: fecha(2026, 8, 17, 6, 0))
        XCTAssertEqual(slots.first?.aviso,
                       Aviso.lectura(palabra: LiquidHoyBuilder.palabraVeredicto(.easy)))
        let futuros: [Aviso] = Array(slots.dropFirst()).map(\.aviso)
        XCTAssertEqual(futuros, [Aviso](repeating: .cita, count: slots.count - 1))
    }

    /// El texto de la cita no puede nombrar un veredicto: a esa hora nadie sabe cuál será.
    func test_laCita_noNombraNingunVeredicto() {
        let texto = MorningReadingScheduler.contenido(.cita)
        let completo = texto.titulo + " " + texto.cuerpo
        for v in [Preparedness.Verdict.full, .caution, .easy] {
            XCTAssertFalse(completo.localizedCaseInsensitiveContains(LiquidHoyBuilder.palabraVeredicto(v)),
                           "la cita nombra «\(LiquidHoyBuilder.palabraVeredicto(v))» sin tener la lectura")
        }
        XCTAssertFalse(texto.titulo.isEmpty)
        XCTAssertFalse(texto.cuerpo.isEmpty)
    }

    func test_elAvisoConLectura_titulaConLaPalabra() {
        let texto = MorningReadingScheduler.contenido(.lectura(palabra: "En rango"))
        XCTAssertEqual(texto.titulo, "En rango")
        XCTAssertFalse(texto.cuerpo.isEmpty)
    }

    // MARK: 3 · El horizonte, y el reloj

    func test_horizonte_sieteDiasSeguidosALaHoraElegida() {
        let slots = plan(conVeredicto(.full), hour: 6, minute: 30, now: fecha(2026, 8, 17, 5, 0))
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(Set(slots.map(\.id)).count, 7, "los identificadores tienen que ser únicos")
        for (i, slot) in slots.enumerated() {
            let c = cal.dateComponents([.hour, .minute], from: slot.fecha)
            XCTAssertEqual(c.hour, 6)
            XCTAssertEqual(c.minute, 30)
            XCTAssertEqual(slot.fecha, fecha(2026, 8, 17 + i, 6, 30))
        }
    }

    func test_cambiarLaHora_mueveTodasLasFechas() {
        let ahora = fecha(2026, 8, 17, 5, 0)
        let temprano = plan(conVeredicto(.full), hour: 7, now: ahora).map(\.fecha)
        let tarde = plan(conVeredicto(.full), hour: 21, now: ahora).map(\.fecha)
        XCTAssertEqual(temprano.count, tarde.count)
        XCTAssertTrue(zip(temprano, tarde).allSatisfy { par in par.0 != par.1 })
        XCTAssertEqual(tarde.first, fecha(2026, 8, 17, 21, 0))
    }

    /// El día que el reloj brinca (horario de verano en EE. UU., 8 de marzo de 2026: las 2:30 no
    /// existen), el horizonte no puede perder ese día ni repetir una fecha.
    func test_saltoDeHorarioDeVerano_noPierdeNiRepiteDias() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let ahora = fecha(2026, 3, 6, 12, 0, ny)
        let slots = plan(conVeredicto(.full), hour: 2, minute: 30, now: ahora, calendar: ny)
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(Set(slots.map(\.fecha)).count, 7)
        XCTAssertEqual(slots.map(\.fecha), slots.map(\.fecha).sorted())
        // Ningún par de avisos cae el mismo día civil.
        let dias = slots.map { ny.startOfDay(for: $0.fecha) }
        XCTAssertEqual(Set(dias).count, 7)
    }

    func test_proximasOcurrencias_sonEstrictamentePosterioresAAhora() {
        let ahora = fecha(2026, 8, 17, 7, 0)
        let fechas = MorningReadingScheduler.proximasOcurrencias(hour: 7, minute: 0, desde: ahora,
                                                                calendar: cal, count: 3)
        XCTAssertEqual(fechas.first, fecha(2026, 8, 18, 7, 0), "las 7:00 en punto de hoy ya pasaron")
        XCTAssertTrue(fechas.allSatisfy { $0 > ahora })
    }
}
