import XCTest
import CenitStore
import StrandTraining
@testable import Cenit

/// FER-202 (épico «Entrenar en vidrio») — la proyección `UnifiedWorkoutHistory` funde el historial de
/// fuerza de Cénit con la actividad de Apple Health en UNA línea de tiempo filtrable. Estas pruebas
/// candan los invariantes que la revisión adversarial marcó como delicados: el DEDUP del eco solo
/// aplica a origen Apple (nunca borra datos manuales/detectados/whoop), la sesión en curso se excluye,
/// y el orden/filtro son correctos. Llaman el MISMO código de producción, no una copia de la regla.
final class UnifiedWorkoutHistoryTests: XCTestCase {

    // MARK: helpers
    private func row(_ start: Int, _ end: Int, sport: String, source: String) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: end, sport: sport, source: source, durationS: nil,
                   energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                   zonesJSON: nil, notes: nil)
    }
    private func session(_ id: String, _ start: Int, _ end: Int?) -> StrengthSession {
        StrengthSession(id: id, startTs: start, endTs: end)
    }

    private let day = 86_400
    private let now = 1_700_000_000

    // MARK: orden + sesión en curso
    func testMergeOrdenaMasRecientePrimeroCruzandoFuentes() {
        let sessions = [session("A", now - 0*day, now - 0*day + 3000),
                        session("C", now - 5*day, now - 5*day + 3600)]
        let rows = [row(now - 2*day, now - 2*day + 1800, sport: "Running", source: "apple-health")]
        let out = UnifiedWorkoutHistory.merge(sessions: sessions, rows: rows)
        let starts = out.map(\.startTs)
        XCTAssertEqual(starts, starts.sorted(by: >), "la línea de tiempo va de más reciente a más antigua")
        XCTAssertEqual(out.count, 3)
    }

    func testSesionEnCursoSeExcluye() {
        let sessions = [session("A", now, now + 3000),         // completada
                        session("B", now - 3*day, nil)]         // en curso (endTs == nil)
        let out = UnifiedWorkoutHistory.merge(sessions: sessions, rows: [])
        XCTAssertEqual(out.count, 1, "una sesión en curso es estado vivo, no historial")
        XCTAssertTrue(out.first?.isStrength ?? false)
    }

    // MARK: dedup del eco — SOLO Apple
    func testEcoDeAppleSeDeDuplica() {
        let s = session("A", now, now + 3000)
        // el espejo del Apple Watch guarda la MISMA sesión como apple-health strength-like, solapada
        let echo = row(now + 100, now + 2900, sport: "TraditionalStrengthTraining", source: "apple-health")
        let out = UnifiedWorkoutHistory.merge(sessions: [s], rows: [echo])
        XCTAssertEqual(out.count, 1, "el eco de Apple de una sesión registrada se colapsa a UNA entrada")
        XCTAssertTrue(out.first?.isStrength ?? false, "gana la sesión rica de Cénit")
    }

    /// EL BLOQUEANTE de la revisión: sin gate de origen, un registro MANUAL de fuerza solapado se
    /// borraría en silencio. Debe SOBREVIVIR.
    func testFuerzaManualSolapadaSOBREVIVE() {
        let s = session("A", now, now + 3000)
        let manual = row(now + 100, now + 2900, sport: "Weight Training", source: "manual")
        let out = UnifiedWorkoutHistory.merge(sessions: [s], rows: [manual])
        XCTAssertEqual(out.count, 2, "un registro manual NUNCA se de-duplica, aunque solape una sesión")
        XCTAssertTrue(out.contains { if case .cardio(let r) = $0 { return r.source == "manual" }; return false })
    }

    func testDetectadoYWhoopSolapadosSOBREVIVEN() {
        let s = session("A", now, now + 3000)
        let detected = row(now + 100, now + 2900, sport: "Functional Strength Training", source: "apple-noop")
        let whoop    = row(now + 200, now + 2800, sport: "Strength", source: "whoop")
        let out = UnifiedWorkoutHistory.merge(sessions: [s], rows: [detected, whoop])
        XCTAssertEqual(out.filter { !$0.isStrength }.count, 2, "detected y whoop nunca son eco")
    }

    /// Una sesión de fuerza REAL de Apple/Watch en otro momento (sin solape) NO es eco → se ve.
    func testFuerzaDeAppleSinSolapeSOBREVIVE() {
        let s = session("A", now, now + 3000)
        let appleStrengthOtherDay = row(now - 4*day, now - 4*day + 3000,
                                        sport: "TraditionalStrengthTraining", source: "apple-health")
        let out = UnifiedWorkoutHistory.merge(sessions: [s], rows: [appleStrengthOtherDay])
        XCTAssertEqual(out.count, 2, "sin solape, la fuerza de Apple es actividad propia, no un eco")
    }

    // MARK: filtros
    func testFiltros() {
        let sessions = [session("A", now, now + 3000)]
        let rows = [row(now - 1*day, now - 1*day + 1800, sport: "Running", source: "apple-health"),
                    row(now - 2*day, now - 2*day + 2400, sport: "Walking", source: "apple-health")]
        let all = UnifiedWorkoutHistory.merge(sessions: sessions, rows: rows)
        XCTAssertEqual(UnifiedWorkoutHistory.filter(all, .all).count, 3)
        let strength = UnifiedWorkoutHistory.filter(all, .strength)
        XCTAssertEqual(strength.count, 1)
        XCTAssertTrue(strength.allSatisfy(\.isStrength), "«Fuerza» = solo sesiones ricas")
        let running = UnifiedWorkoutHistory.filter(all, .sport("Running"))
        XCTAssertEqual(running.count, 1)
        XCTAssertFalse(running.contains { $0.isStrength }, "un filtro de deporte nunca trae fuerza")
    }

    func testSportsListaPorFrecuencia() {
        let rows = [row(now, now + 1, sport: "Running", source: "apple-health"),
                    row(now - day, now - day + 1, sport: "Running", source: "apple-health"),
                    row(now - 2*day, now - 2*day + 1, sport: "Walking", source: "apple-health")]
        let all = UnifiedWorkoutHistory.merge(sessions: [], rows: rows)
        XCTAssertEqual(UnifiedWorkoutHistory.sports(all), ["Running", "Walking"], "más frecuente primero")
    }
}
