import XCTest
import SwiftUI
import StrandAnalytics
import StrandDesign
@testable import Cenit

/// La guarda del contrato de TND-19 (FER-103): el catálogo tiene UNA sola escalera por métrica —
/// `MetricLevels.displayBands` — y el color de cada carril sale de la CLAVE de la banda, nunca de su
/// posición en el array. La clase de defecto que mata (la misma que produjo TND10-1/TND10-2 en las
/// gemelas): dos escaleras conviviendo para la misma métrica (steps: 4 bandas a mano vs 3 del motor,
/// 6,000 pasos leía «Light» aquí y «active» en Hoy) y rampas posicionales que no se enteran cuando la
/// escalera encoge (SpO₂ «low» pintado de verde veredicto; Respiración «elevated» en verde).
///
/// La suite corre en inglés: los textos se afirman contra el defaultValue EN del catálogo — la guarda
/// fija el MAPEO, no la traducción.
final class MetricInfoEscaleraUnicaTests: XCTestCase {

    // MARK: - (a) Steps: la tabla del catálogo ES la escalera del motor

    /// Los cortes, claves y textos de `MetricInfo.steps(...).bands` son EXACTAMENTE los de
    /// `MetricLevels.displayBands(for: .steps)` — tres bandas, no las cuatro a mano de antes.
    func testStepsBandsSonLasDelMotor() {
        let info = MetricInfo.steps(6_000)
        let motor = MetricLevels.displayBands(for: .steps)

        XCTAssertEqual(motor.count, 3, "el motor define 3 bandas de pasos")
        XCTAssertEqual(info.bands.count, motor.count,
                       "el catálogo debe tener LAS MISMAS bandas que el motor, no una segunda escalera")
        XCTAssertEqual(info.bands.map(\.key), motor.map(\.key))
        XCTAssertEqual(info.bands.map(\.key), ["sedentary", "active", "veryActive"])
        XCTAssertEqual(info.bands.map(\.lower), motor.map(\.lower))
        XCTAssertEqual(info.bands.map(\.upper), motor.map(\.upper))
        XCTAssertEqual(info.bands.map(\.range), motor.map(\.range))
    }

    /// El caso que mentía: 6,000 pasos era «Light» en el detalle y «active» en el motor/Hoy.
    /// Ahora la fila activa del catálogo es la del motor.
    func testSeisMilPasosCaenEnActive() {
        let info = MetricInfo.steps(6_000)
        let activa = info.bands.first(where: \.isActive)
        XCTAssertEqual(activa?.key, "active", "6,000 pasos deben leer «active», la banda del motor")

        let indiceMotor = MetricLevels.index(of: 6_000, for: .steps)
        XCTAssertEqual(info.bands.firstIndex(where: \.isActive), indiceMotor,
                       "la fila activa del catálogo debe ser el MISMO índice que resuelve el motor")
    }

    // MARK: - (b) Resting HR: ídem — misma escalera, cero duplicación latente

    func testRestingHRBandsSonLasDelMotor() {
        let info = MetricInfo.restingHR(52)
        // El factory localiza la unidad en el call site («bpm» → «lpm» en es); la suite corre en
        // inglés, así que el espejo exacto es el formato con la unidad resuelta aquí igual.
        let fmt = MetricFormat(valueStyle: .integer, boundaryStyle: .integer,
                               unit: String(localized: "bpm"))
        let motor = MetricLevels.displayBands(for: .restingHR, format: fmt)

        XCTAssertEqual(info.bands.count, motor.count)
        XCTAssertEqual(info.bands.map(\.key), motor.map(\.key))
        XCTAssertEqual(info.bands.map(\.key), ["rhrAthlete", "rhrLow", "rhrTypical", "rhrHigher"])
        XCTAssertEqual(info.bands.map(\.lower), motor.map(\.lower))
        XCTAssertEqual(info.bands.map(\.upper), motor.map(\.upper))
        XCTAssertEqual(info.bands.map(\.range), motor.map(\.range))
        XCTAssertEqual(info.bands.first(where: \.isActive)?.key, "rhrLow", "52 lpm cae en 50–60")
    }

    // MARK: - (c) Color de carril por CLAVE, nunca posicional

    /// SpO₂: «low (< 95)» JAMÁS recibe el color de veredicto/positivo, y «normal» jamás el de
    /// warning — la inversión exacta que producía la rampa posicional al encoger la escalera a 2.
    func testColorDeCarrilSpO2PorClave() {
        let theme = InstrumentoTheme.base
        let low = MetricDetailScreen.laneColor(metric: "spo2", bandKey: "low",
                                               theme: theme, fallback: .pink)
        let normal = MetricDetailScreen.laneColor(metric: "spo2", bandKey: "normal",
                                                  theme: theme, fallback: .pink)
        XCTAssertNotEqual(low, theme.verdict, "«low» no puede pintarse del verde de veredicto")
        XCTAssertNotEqual(low, theme.verdictDeep, "«low» no puede pintarse de ningún verde positivo")
        XCTAssertNotEqual(normal, theme.warning, "«normal» no puede pintarse de ámbar de warning")
        XCTAssertNotEqual(normal, theme.critical, "«normal» no puede pintarse de crítico")
        // El mapeo fijado: normal → veredicto; low → warning (absorbe el tramo «Borderline» retirado,
        // mismo criterio de suavizado que rhr FER-43 — ámbar honesto, no rojo de alarma).
        XCTAssertEqual(normal, theme.verdict)
        XCTAssertEqual(low, theme.warning)
    }

    /// Respiración: «elevated (≥ 20)» jamás en verde; «normal» en veredicto.
    func testColorDeCarrilRespiracionPorClave() {
        let theme = InstrumentoTheme.base
        let normal = MetricDetailScreen.laneColor(metric: "resp_rate", bandKey: "normal",
                                                  theme: theme, fallback: .pink)
        let elevated = MetricDetailScreen.laneColor(metric: "resp_rate", bandKey: "elevated",
                                                    theme: theme, fallback: .pink)
        XCTAssertEqual(normal, theme.verdict)
        XCTAssertNotEqual(elevated, theme.verdict, "«elevated» no puede pintarse de verde")
        XCTAssertNotEqual(elevated, theme.verdictDeep)
        XCTAssertEqual(elevated, theme.warning)
    }

    /// Resting HR conserva el mapeo FER-43 (athlete verde profundo · low verde · typical tinta ·
    /// higher ámbar, nunca crítico) — ahora anclado a la clave, no al índice.
    func testColorDeCarrilRestingHRPorClave() {
        let theme = InstrumentoTheme.base
        func c(_ key: String) -> Color {
            MetricDetailScreen.laneColor(metric: "rhr", bandKey: key, theme: theme, fallback: .pink)
        }
        XCTAssertEqual(c("rhrAthlete"), theme.verdictDeep)
        XCTAssertEqual(c("rhrLow"), theme.verdict)
        XCTAssertEqual(c("rhrTypical"), theme.inkSecondary)
        XCTAssertEqual(c("rhrHigher"), theme.warning)
        XCTAssertNotEqual(c("rhrHigher"), theme.critical, "FER-43: la banda alta es ámbar, no rojo")
    }

    /// Una clave desconocida (o nil, la escalera a mano sin claves de motor) cae al hue de la métrica
    /// — el fallback inyectado — sin heredar el color de ninguna posición.
    func testClaveDesconocidaCaeAlFallback() {
        let theme = InstrumentoTheme.base
        XCTAssertEqual(MetricDetailScreen.laneColor(metric: "spo2", bandKey: "banana",
                                                    theme: theme, fallback: .pink), .pink)
        XCTAssertEqual(MetricDetailScreen.laneColor(metric: "steps", bandKey: "sedentary",
                                                    theme: theme, fallback: .pink), .pink)
        XCTAssertEqual(MetricDetailScreen.laneColor(metric: "spo2", bandKey: nil,
                                                    theme: theme, fallback: .pink), .pink)
    }

    // MARK: - (d) El héroe de SpO₂ solo tiene 2 lecturas — el «Borderline fantasma» está muerto

    /// Barrido 85…100: el héroe solo produce DOS palabras («Low» / «Healthy»), cortadas en el 95 del
    /// motor. El switch viejo tenía TRES tramos (≥ 95 / ≥ 90 / < 90) contra los DOS de la escalera:
    /// un 94% leía «Borderline» en el héroe y «low» en la tabla de la misma pantalla.
    func testHeroeSpO2SoloDosLecturas() {
        var palabras = Set<String>()
        for decimo in stride(from: 850, through: 1000, by: 1) {
            let v = Double(decimo) / 10
            let lectura = MetricDetailScreen.spo2HeroVerdict(v)
            palabras.insert(lectura.word)
            XCTAssertNotEqual(lectura.word, "Borderline", "el tramo fantasma no puede volver (\(v)%)")
            // La costura: la palabra del héroe nombra el MISMO nivel que resuelve el motor.
            let key = MetricLevels.levels(for: .bloodOxygen)[MetricLevels.index(of: v, for: .bloodOxygen)].key
            XCTAssertEqual(lectura.healthy, key == "normal",
                           "el héroe de \(v)% debe leer el nivel del motor (\(key))")
        }
        XCTAssertEqual(palabras, ["Low", "Healthy"], "exactamente dos lecturas posibles")
    }

    /// Los cortes exactos: 95 es «Healthy» (half-open [95, ∞)); 94.9 es «Low» — y 94, el viejo
    /// «Borderline», ahora lee «Bajo» («Low»).
    func testCorteDelHeroeEnNoventaYCinco() {
        XCTAssertEqual(MetricDetailScreen.spo2HeroVerdict(95).word, "Healthy")
        XCTAssertTrue(MetricDetailScreen.spo2HeroVerdict(95).healthy)
        XCTAssertEqual(MetricDetailScreen.spo2HeroVerdict(94.9).word, "Low")
        XCTAssertEqual(MetricDetailScreen.spo2HeroVerdict(94).word, "Low")
        XCTAssertEqual(MetricDetailScreen.spo2HeroVerdict(88).word, "Low")
        XCTAssertFalse(MetricDetailScreen.spo2HeroVerdict(88).healthy)
    }
}
