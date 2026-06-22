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
}
