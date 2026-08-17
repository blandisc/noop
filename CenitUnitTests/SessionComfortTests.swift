import XCTest
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

    override func tearDown() {
        UIApplication.shared.isIdleTimerDisabled = false
        defaults.removePersistentDomain(forName: "SessionComfortTests")
        super.tearDown()
    }
}
