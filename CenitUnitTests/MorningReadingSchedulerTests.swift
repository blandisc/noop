import XCTest
import StrandAnalytics
@testable import Cenit

// MARK: - MorningReadingSchedulerTests (FER-114 · FER-111)
//
// El aviso matutino se decide con funciones PURAS (`hayLectura`, `proximasOcurrencias`, `plan`,
// `contenido`), justo para poder fijarlo aquí sin `UNUserNotificationCenter`, sin permisos y sin
// simulador con reloj real: los efectos (pedir permiso, cancelar, agregar) son una capa delgada
// encima de estas cuatro.
//
// Lo que estas pruebas defienden, en orden de importancia:
//   1. Nunca se programa un aviso sin lectura que dar (calibrando, `lowSignal`, sin noche anclada,
//      switch apagado → plan VACÍO). La puerta sigue siendo `hayLectura`, aunque el texto ya no
//      dependa de ella: a quien no tiene reloj no se le recuerda ir por una lectura que no existe.
//   2. NINGÚN aviso lleva jamás la palabra del veredicto (FER-111). El aviso es un RECORDATORIO,
//      no una entrega: Cénit no despierta sola, así que el texto se congela al programarse y sería
//      mentira si nombrara una lectura. El plan no puede variar con el veredicto ni tratar distinto
//      al aviso que cae hoy.
//   3. Cambiar la hora mueve todas las fechas; el horizonte no se salta días ni cuando el reloj
//      brinca por el horario de verano.
//   4. «Todavía no hay lectura» NO es «el dueño lo apagó»: lo primero deja lo pendiente en paz, lo
//      segundo lo cancela. Confundirlos dejaba al dueño sin su aviso cada mañana.

final class MorningReadingSchedulerTests: XCTestCase {

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
    /// aquí, así que tampoco hay lectura que ir a leer.
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
    //
    // El texto ya no depende del motor, pero PROGRAMAR sí: recordarle leerse a quien el motor no le
    // puede dar veredicto es citarlo a una puerta que va a encontrar cerrada.

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

    // MARK: 2 · Ningún aviso lleva palabra, nunca (FER-111)
    //
    // Cénit no despierta sola: cero `UIBackgroundModes`, cero `enableBackgroundDelivery`, cero
    // `BGTaskScheduler`. El texto de una notificación se congela al PROGRAMARSE, así que una palabra
    // dentro de él solo puede envejecer o inventarse. El aviso es un recordatorio: un solo texto,
    // igual todos los días.

    /// El texto no nombra ningún veredicto: a esa hora nadie sabe cuál será. Las palabras salen de
    /// `LiquidHoyBuilder`, o sea de la MISMA clave del catálogo que el héroe, así que la prueba
    /// sigue siendo verdad en cualquier idioma.
    func test_elTexto_noNombraNingunVeredicto() {
        let texto = MorningReadingScheduler.contenido
        let completo = texto.titulo + " " + texto.cuerpo
        for v in [Preparedness.Verdict.full, .caution, .easy] {
            XCTAssertFalse(completo.localizedCaseInsensitiveContains(LiquidHoyBuilder.palabraVeredicto(v)),
                           "el aviso nombra «\(LiquidHoyBuilder.palabraVeredicto(v))» sin tener la lectura")
        }
        XCTAssertFalse(texto.titulo.isEmpty)
        XCTAssertFalse(texto.cuerpo.isEmpty)
    }

    /// El veredicto NO se filtra al horario: con la misma hora y el mismo `now`, los tres veredictos
    /// producen exactamente el mismo plan. Si alguien reintrodujera una rama que cambia el aviso
    /// según la lectura, esta prueba lo caza.
    func test_elPlan_noDependeDelVeredicto() {
        let ahora = fecha(2026, 8, 17, 6, 0)
        let base = plan(conVeredicto(.full), now: ahora)
        XCTAssertFalse(base.isEmpty)
        for v in [Preparedness.Verdict.caution, .easy] {
            XCTAssertEqual(plan(conVeredicto(v), now: ahora), base,
                           "el plan de \(v) no es el mismo que el de .full")
        }
    }

    /// El aviso que cae HOY no se trata distinto del que cae mañana: era la única rama que podía
    /// llevar palabra, y en la práctica solo le tocaba a quien ya había abierto la app. Los dos
    /// planes traen los mismos identificadores y las fechas corridas exactamente un día.
    func test_elAvisoDeHoy_noSeDistingueDelDeManana() {
        let antes = plan(conVeredicto(.full), hour: 7, now: fecha(2026, 8, 17, 6, 0))
        let despues = plan(conVeredicto(.full), hour: 7, now: fecha(2026, 8, 17, 9, 30))
        XCTAssertEqual(antes.first?.fecha, fecha(2026, 8, 17, 7, 0), "antes de las 7:00 el primero es hoy")
        XCTAssertEqual(despues.first?.fecha, fecha(2026, 8, 18, 7, 0), "pasadas las 7:00 el primero es mañana")
        XCTAssertEqual(antes.map(\.id), despues.map(\.id))
        for (uno, otro) in zip(antes, despues) {
            XCTAssertEqual(cal.date(byAdding: .day, value: 1, to: uno.fecha), otro.fecha)
        }
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

    // MARK: 4 · «Sin plan» no es «apagado»
    //
    // El defecto que estas pruebas cierran tenía consecuencia DIARIA: `repo.$dashboard` es
    // `@Published`, así que el `.sink` de `AppModel` dispara de inmediato con el valor de `init`
    // (`preparedness == nil`). Con el `cancelAll()` incondicional de antes, abrir la app a las
    // 06:00 —antes de que el reloj publicara la noche— borraba los 7 pendientes y nada los reponía:
    // el aviso de las 07:00 nunca sonaba.

    private func decision(_ prep: Preparedness.Read?, enabled: Bool = true,
                          hour: Int = 7, minute: Int = 0, now: Date,
                          cancelaSinPlan: Bool = false)
        -> MorningReadingScheduler.Reprogramacion {
        MorningReadingScheduler.reprogramacion(prep: prep, enabled: enabled, hour: hour,
                                               minute: minute, now: now, calendar: cal,
                                               cancelaSinPlan: cancelaSinPlan)
    }

    /// EL caso: sin lectura todavía, lo pendiente se queda donde está.
    func test_sinLecturaTodavia_noSeTocaLoPendiente() {
        XCTAssertEqual(decision(nil, now: fecha(2026, 8, 17, 6, 0)), .dejarComoEsta)
        XCTAssertEqual(decision(calibrando(), now: fecha(2026, 8, 17, 6, 0)), .dejarComoEsta)
        XCTAssertEqual(decision(sinNocheAnclada(), now: fecha(2026, 8, 17, 6, 0)), .dejarComoEsta)
    }

    /// Apagar el switch SÍ cancela: es la única forma de que el dueño calle el aviso.
    func test_elDuenoLoApaga_cancela() {
        XCTAssertEqual(decision(conVeredicto(.full), enabled: false, now: fecha(2026, 8, 17, 6, 0)),
                       .cancelar)
        // Y apagado manda incluso sin lectura: no hay nada que preservar.
        XCTAssertEqual(decision(nil, enabled: false, now: fecha(2026, 8, 17, 6, 0)), .cancelar)
    }

    /// Cambiar la hora es la excepción: sin plan nuevo, lo viejo se cancela igual (si no, sonaría a
    /// la hora anterior).
    func test_cambioDeHoraSinLectura_cancela() {
        XCTAssertEqual(decision(nil, now: fecha(2026, 8, 17, 6, 0), cancelaSinPlan: true), .cancelar)
    }

    func test_conLectura_reemplazaElHorarioEntero() {
        let ahora = fecha(2026, 8, 17, 6, 0)
        guard case let .reemplazar(slots) = decision(conVeredicto(.full), now: ahora) else {
            return XCTFail("con lectura el horario se reemplaza")
        }
        XCTAssertEqual(slots, plan(conVeredicto(.full), now: ahora))
        XCTAssertEqual(slots.count, MorningReadingScheduler.horizonteDias)
    }

    func test_proximasOcurrencias_sonEstrictamentePosterioresAAhora() {
        let ahora = fecha(2026, 8, 17, 7, 0)
        let fechas = MorningReadingScheduler.proximasOcurrencias(hour: 7, minute: 0, desde: ahora,
                                                                calendar: cal, count: 3)
        XCTAssertEqual(fechas.first, fecha(2026, 8, 18, 7, 0), "las 7:00 en punto de hoy ya pasaron")
        XCTAssertTrue(fechas.allSatisfy { $0 > ahora })
    }
}
