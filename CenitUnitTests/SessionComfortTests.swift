import XCTest
import StrandTraining
@testable import Cenit

/// FER-93 — las dos comodidades de la sesión, con la regla que las hace aceptables: apagadas por
/// defecto y sin efecto si el usuario no las pidió.
@MainActor
final class SessionComfortTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SessionComfortTests")!
        defaults.removePersistentDomain(forName: "SessionComfortTests")
    }

    /// Cambiar el comportamiento del iPhone de alguien sin avisarle es de mala educación: las dos
    /// nacen apagadas.
    func testAmbasNacenApagadas() {
        XCTAssertFalse(SessionComfort.isEnabled(SessionComfort.keepAwakeKey, defaults: defaults))
        XCTAssertFalse(SessionComfort.isEnabled(SessionComfort.restSoundKey, defaults: defaults))
    }

    func testElInterruptorMandaSobreLaBandera() {
        defaults.set(true, forKey: SessionComfort.keepAwakeKey)
        XCTAssertTrue(SessionComfort.isEnabled(SessionComfort.keepAwakeKey, defaults: defaults))
        defaults.set(false, forKey: SessionComfort.keepAwakeKey)
        XCTAssertFalse(SessionComfort.isEnabled(SessionComfort.keepAwakeKey, defaults: defaults))
    }

    /// La regla que protege la batería: con la sesión ABIERTA pero el interruptor apagado, el
    /// auto-bloqueo del sistema se queda como estaba.
    func testConElInterruptorApagadoLaSesionNoTocaElAutoBloqueo() {
        defaults.set(false, forKey: SessionComfort.keepAwakeKey)
        UIApplication.shared.isIdleTimerDisabled = false
        SessionComfort.applyKeepAwake(active: true, defaults: defaults)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    /// Y la que la protege de verdad: salir de la sesión SIEMPRE restaura, aunque el interruptor
    /// siga encendido. Una app que deja el auto-bloqueo apagado tras cerrarse quema batería a
    /// espaldas de su dueño.
    func testSalirDeLaSesionRestauraAunqueElInterruptorSigaEncendido() {
        defaults.set(true, forKey: SessionComfort.keepAwakeKey)
        SessionComfort.applyKeepAwake(active: true, defaults: defaults)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled, "con sesión y permiso, se suspende")
        SessionComfort.applyKeepAwake(active: false, defaults: defaults)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "al salir, siempre se restaura")
    }

    /// El aviso del fin de descanso ya no es solo el tono: la háptica es incondicional (el copy la
    /// prometía y no existía) y el tono depende del interruptor. Esta prueba fija la mitad que se
    /// puede afirmar sin UI: el tono NO suena si nadie lo pidió.
    func testElTonoNoSuenaSiNadieLoPidio() {
        defaults.set(false, forKey: SessionComfort.restSoundKey)
        XCTAssertFalse(SessionComfort.isEnabled(SessionComfort.restSoundKey, defaults: defaults))
        // `playRestChime` con el interruptor apagado es un no-op: no revienta ni suena.
        SessionComfort.playRestChime(defaults: defaults)
    }

    /// El aviso nace apagado, como los otros dos.
    func testLaNotificacionNaceApagada() {
        XCTAssertFalse(SessionComfort.isEnabled(SessionComfort.restNotifyKey, defaults: defaults))
    }

    /// Un descanso ya vencido no merece aviso: sin esta guarda, reabrir la app con un descanso
    /// viejo en el modelo dispararía una notificación de algo que terminó hace rato.
    func testUnDescansoVencidoNoMereceAviso() {
        let ahora = Date()
        XCTAssertFalse(RestEndNotifier.shouldSchedule(endsAt: ahora.addingTimeInterval(-30), now: ahora))
        XCTAssertFalse(RestEndNotifier.shouldSchedule(endsAt: ahora, now: ahora))
        XCTAssertTrue(RestEndNotifier.shouldSchedule(endsAt: ahora.addingTimeInterval(90), now: ahora))
    }

    /// La regla del aviso, afirmada sobre el predicado que la decide (falsear
    /// `UNUserNotificationCenter` no se puede, y una prueba que finge hacerlo no prueba nada):
    /// apagado no avisa, el descanso por PULSO no avisa (su fin lo decide tu pulso, no el reloj),
    /// y una sesión pausada tampoco.
    func testSoloElDescansoPorRelojYConElInterruptorEncendidoAvisa() {
        UserDefaults.standard.set(true, forKey: SessionComfort.restNotifyKey)
        defer { UserDefaults.standard.removeObject(forKey: SessionComfort.restNotifyKey) }

        let s = sesionDePrueba()
        XCTAssertFalse(s.debeAvisar, "sin descanso corriendo no hay nada que avisar")
        s.startRest(seconds: 90)
        XCTAssertTrue(s.debeAvisar, "descanso por reloj con el interruptor encendido")
        s.pause()
        XCTAssertFalse(s.debeAvisar, "pausado, el aviso sonaría en plena pausa")
        s.resume()
        XCTAssertTrue(s.debeAvisar)

        UserDefaults.standard.set(false, forKey: SessionComfort.restNotifyKey)
        XCTAssertFalse(s.debeAvisar, "con el interruptor apagado, nunca")
    }

    private func sesionDePrueba() -> StrengthSessionModel {
        let re = RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0,
                                 targetSets: 2, targetReps: 8, targetWeightKg: 80,
                                 restMode: .fixed, restSeconds: 90)
        let ex = Exercise(id: "bench", name: "Bench", type: .weightReps, equipment: nil,
                          primaryMuscles: [], secondaryMuscles: [], instructions: [])
        return StrengthSessionModel.make(routineId: "rt", routineName: "Push",
                                         slots: [.init(re: re, exercise: ex, lastSets: [])],
                                         startTs: 100)
    }

    func testTodaSalidaDelDescansoPasaPorElMismoEmbudo() {
        let re = RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0,
                                 targetSets: 2, targetReps: 8, targetWeightKg: 80,
                                 restMode: .fixed, restSeconds: 90)
        let ex = Exercise(id: "bench", name: "Bench", type: .weightReps, equipment: nil,
                          primaryMuscles: [], secondaryMuscles: [], instructions: [])
        let s = StrengthSessionModel.make(routineId: "rt", routineName: "Push",
                                          slots: [.init(re: re, exercise: ex, lastSets: [])],
                                          startTs: 100)
        s.startRest(seconds: 90)
        XCTAssertNotNil(s.restEndsAt, "el descanso arrancó")
        s.skipRest()
        XCTAssertNil(s.restEndsAt, "saltarlo limpia el descanso")

        s.startRest(seconds: 90)
        XCTAssertNotNil(s.restEndsAt)
        s.registerCurrentSet()   // palomear la siguiente serie
        s.skipRest()
        XCTAssertNil(s.restEndsAt, "y el otro camino también")
    }

    override func tearDown() {
        UIApplication.shared.isIdleTimerDisabled = false
        defaults.removePersistentDomain(forName: "SessionComfortTests")
        super.tearDown()
    }
}
