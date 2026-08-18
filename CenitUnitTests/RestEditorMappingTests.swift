import XCTest
import StrandTraining
@testable import Cenit

/// FER-89 — `RestEditorScreen` pasó de conocer 2 de las 5 formas reales del motor
/// (`RestMode.fixed` + `HRRestReference.restingMargin`/`.karvonenReserve`) a las 5: `.fixed` +
/// las 4 `HRRestReference` (`.restingMargin`, `.karvonenReserve`, `.peakDrop`, `.fixedBpm`).
/// `RestEditorMapping` es la lógica pura que decide (a) con qué método abre la hoja un config ya
/// guardado y (b) qué `RestConfig` arma el CTA «Aplicar» — extraída para probarla sin montar la
/// vista.
final class RestEditorMappingTests: XCTestCase {

    // MARK: - seedHRRef

    /// El caso que ya funcionaba: Karvonen se conserva al reabrir.
    func testSeedHRRefPreservesKarvonenReserve() {
        let cfg = RestConfig(mode: .heartRate, seconds: 90, hrReference: .karvonenReserve, hrValue: 0.41)
        XCTAssertEqual(RestEditorMapping.seedHRRef(cfg), .karvonenReserve)
    }

    /// EL bug que esta fase corrige: antes de FER-89, `current.hrReference == .karvonenReserve ?
    /// .karvonenReserve : .restingMargin` degradaba CUALQUIER método que no fuera Karvonen a
    /// `.restingMargin` — incluido uno ya persistido en `.peakDrop`. Código viejo tronaría aquí:
    /// esperaría `.restingMargin` y recibiría `.peakDrop`.
    func testSeedHRRefPreservesPeakDropInsteadOfDowngrading() {
        let cfg = RestConfig(mode: .heartRate, seconds: 90, hrReference: .peakDrop, hrValue: 0.3)
        XCTAssertEqual(RestEditorMapping.seedHRRef(cfg), .peakDrop)
    }

    /// Mismo bug, mismo síntoma, para `.fixedBpm` — la otra forma que antes de FER-89 no tenía UI.
    func testSeedHRRefPreservesFixedBpmInsteadOfDowngrading() {
        let cfg = RestConfig(mode: .heartRate, seconds: 90, hrReference: .fixedBpm, hrValue: 130)
        XCTAssertEqual(RestEditorMapping.seedHRRef(cfg), .fixedBpm)
    }

    /// El default real (FER-348): `.restingMargin` con `hrValue == 0` sigue abriendo en
    /// `.restingMargin`, sin cambios de comportamiento para las rutinas ya existentes.
    func testSeedHRRefKeepsTheFER348Default() {
        let cfg = RestConfig(mode: .heartRate, seconds: 90, hrReference: .restingMargin, hrValue: 0)
        XCTAssertEqual(RestEditorMapping.seedHRRef(cfg), .restingMargin)
    }

    // MARK: - buildConfig — las 5 formas reales

    /// Tiempo fijo: la rama `mode == .fixed` ignora `hrRef` por completo, sea cual sea.
    func testBuildConfigFixedMode() {
        let cfg = RestEditorMapping.buildConfig(mode: .fixed, hrRef: .fixedBpm, seconds: 120,
                                                margin: 20, reserve: 0.41, peakDropFraction: 0.25,
                                                fixedTargetBpm: 130)
        XCTAssertEqual(cfg.mode, .fixed)
        XCTAssertEqual(cfg.seconds, 120)
        XCTAssertEqual(cfg.hrReference, .restingMargin)   // el campo va sin usar en modo fijo
        XCTAssertEqual(cfg.hrValue, 0)
    }

    /// «Sobre tu reposo»: `hrValue` es el margen en bpm, no una fracción.
    func testBuildConfigRestingMargin() {
        let cfg = RestEditorMapping.buildConfig(mode: .heartRate, hrRef: .restingMargin, seconds: 90,
                                                margin: 22, reserve: 0.41, peakDropFraction: 0.25,
                                                fixedTargetBpm: 130)
        XCTAssertEqual(cfg.hrReference, .restingMargin)
        XCTAssertEqual(cfg.hrValue, 22)
    }

    /// Karvonen: `hrValue` es la fracción de reserva (0…1), no el margen ni el bpm.
    func testBuildConfigKarvonenReserve() {
        let cfg = RestEditorMapping.buildConfig(mode: .heartRate, hrRef: .karvonenReserve, seconds: 90,
                                                margin: 22, reserve: 0.37, peakDropFraction: 0.25,
                                                fixedTargetBpm: 130)
        XCTAssertEqual(cfg.hrReference, .karvonenReserve)
        XCTAssertEqual(cfg.hrValue, 0.37)
    }

    /// Caída desde el pico — la forma que hasta FER-89 no tenía UI. Código viejo (el switch de 2
    /// ramas de antes) ni siquiera compilaría con este caso.
    func testBuildConfigPeakDrop() {
        let cfg = RestEditorMapping.buildConfig(mode: .heartRate, hrRef: .peakDrop, seconds: 90,
                                                margin: 22, reserve: 0.37, peakDropFraction: 0.32,
                                                fixedTargetBpm: 130)
        XCTAssertEqual(cfg.hrReference, .peakDrop)
        XCTAssertEqual(cfg.hrValue, 0.32)
    }

    /// Lpm fijo — la otra forma que hasta FER-89 no tenía UI. `hrValue` es el bpm directo.
    func testBuildConfigFixedBpm() {
        let cfg = RestEditorMapping.buildConfig(mode: .heartRate, hrRef: .fixedBpm, seconds: 90,
                                                margin: 22, reserve: 0.37, peakDropFraction: 0.32,
                                                fixedTargetBpm: 145)
        XCTAssertEqual(cfg.hrReference, .fixedBpm)
        XCTAssertEqual(cfg.hrValue, 145)
    }
}
