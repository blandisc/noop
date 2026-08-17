import XCTest
import StrandAnalytics
@testable import Cenit

// MARK: - FER-74 · Un sync vacío no borra el veredicto que ya tenías
//
// El motor tiene una salida temprana: sin la fila de HOY devuelve `lowSignal` con `drivers`
// vacío — «no encontré tu día», no «tu día está mal». Publicar eso tal cual tiraba el héroe a
// «Conociéndote · Noche 0 de 4» con años de historia en la base. La regla vive en
// `Repository.conservaVeredictoPrevio`, pura y testeable sin store.

final class RepositoryVeredictoPrevioTests: XCTestCase {

    /// Veredicto real (el que ya tenías publicado).
    private func pleno() -> Preparedness.Read {
        Preparedness.Read(
            verdict: .full,
            drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: 0.2),
                      .init(axis: .sleep, state: .inRange, orientedZ: nil)],
            signalsPresent: 2, signalsTotal: 3, maturity: .trusted,
            autonomicNights: 40, trend: nil)
    }

    /// La salida temprana del motor: no encontró la fila de `asOf` (drivers VACÍO).
    private func sinFilaDeHoy() -> Preparedness.Read {
        Preparedness.Read(verdict: .lowSignal, drivers: [], signalsPresent: 0, signalsTotal: 3,
                          maturity: .calibrating, autonomicNights: 0, trend: nil)
    }

    /// Baja señal REAL: el motor sí evaluó (drivers presentes) y no alcanzó quórum.
    private func bajaSenalReal() -> Preparedness.Read {
        Preparedness.Read(
            verdict: .lowSignal,
            drivers: [.init(axis: .autonomic, state: .noData, orientedZ: nil),
                      .init(axis: .sleep, state: .inRange, orientedZ: nil)],
            signalsPresent: 1, signalsTotal: 3, maturity: .trusted,
            autonomicNights: 40, trend: nil)
    }

    func test_sinFilaDeHoy_mismoDia_conservaElPrevio() {
        XCTAssertTrue(Repository.conservaVeredictoPrevio(
            nuevo: sinFilaDeHoy(), previo: pleno(),
            diaPublicado: "2026-08-16", diaAhora: "2026-08-16"))
    }

    func test_nilTambienConserva() {
        XCTAssertTrue(Repository.conservaVeredictoPrevio(
            nuevo: nil, previo: pleno(),
            diaPublicado: "2026-08-16", diaAhora: "2026-08-16"))
    }

    /// Cruzó la medianoche: el veredicto de AYER no se cuela al día nuevo.
    func test_diaDistinto_noConserva() {
        XCTAssertFalse(Repository.conservaVeredictoPrevio(
            nuevo: sinFilaDeHoy(), previo: pleno(),
            diaPublicado: "2026-08-15", diaAhora: "2026-08-16"))
    }

    /// Un pase CON datos siempre gana, aunque su veredicto sea peor que el anterior.
    func test_baja_senal_real_siempre_publica() {
        XCTAssertFalse(Repository.conservaVeredictoPrevio(
            nuevo: bajaSenalReal(), previo: pleno(),
            diaPublicado: "2026-08-16", diaAhora: "2026-08-16"))
        XCTAssertFalse(Repository.conservaVeredictoPrevio(
            nuevo: pleno(), previo: pleno(),
            diaPublicado: "2026-08-16", diaAhora: "2026-08-16"))
    }

    /// Sin nada previo no hay nada que conservar (primer arranque).
    func test_sinPrevio_noConserva() {
        XCTAssertFalse(Repository.conservaVeredictoPrevio(
            nuevo: sinFilaDeHoy(), previo: nil,
            diaPublicado: "2026-08-16", diaAhora: "2026-08-16"))
        XCTAssertFalse(Repository.conservaVeredictoPrevio(
            nuevo: nil, previo: nil, diaPublicado: nil, diaAhora: "2026-08-16"))
    }
}
