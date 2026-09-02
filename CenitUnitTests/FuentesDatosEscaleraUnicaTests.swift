import XCTest
import SwiftUI
import CenitDesign
@testable import Cenit

/// Guarda de los cimientos de la migración de «Fuentes de datos» + «Apple Health» a Liquid Glass
/// (FER-108). La clase de defecto que mata es la misma de siempre: dos vocabularios para LA MISMA
/// cosa. Aquí el fork es la CLAVE de la métrica — la vía de ingesta HealthKit (y por tanto las dos
/// pantallas de Apple Health) habla `resting_hr` / `asleep_min`, mientras el catálogo, `MetricIdentity`
/// (hues Liquid) y `canonicalTitle` están keyed por `rhr` / `sleep_total_min`. Sin UN puente, el port
/// pintaría FC en reposo con el verde de veredicto (el fallback) en vez del rosa de corazón, y el
/// sueño sin su índigo. Estas guardas fijan que hay UNA sola traducción, antes de mover el vidrio.
final class FuentesDatosEscaleraUnicaTests: XCTestCase {

    /// Las claves que hablan las dos pantallas de Apple Health (unión de `AppleHealthView.seriesKeys`
    /// y `DataSourcesView.metricRows`). Fijadas aquí como contrato — si una pantalla suma una clave
    /// nueva, esta prueba obliga a que resuelva a una métrica real del catálogo.
    private let clavesDeIngesta = [
        "steps", "active_kcal", "vo2max", "resting_hr", "hrv", "spo2",
        "resp_rate", "asleep_min", "weight", "body_fat", "lean_mass", "bmi",
        // FER-192: skin_temp (checklist + visor + cobertura) y avg_hr (checklist) se sumaron a las dos
        // pantallas — el contrato exige que también resuelvan a una métrica real del catálogo.
        "skin_temp", "avg_hr",
    ]

    // MARK: - UN puente ingesta → catálogo

    /// Solo dos claves divergen; el resto pasa de largo. Es la traducción única.
    func testPuenteDeClaveNormalizaSoloLasDosQueDivergen() {
        XCTAssertEqual(MetricCatalog.catalogKey(forIngestKey: "resting_hr"), "rhr")
        XCTAssertEqual(MetricCatalog.catalogKey(forIngestKey: "asleep_min"), "sleep_total_min")
        // Cada otra clave de ingesta YA es clave de catálogo y pasa idéntica.
        for k in ["steps", "active_kcal", "vo2max", "hrv", "spo2", "resp_rate",
                  "weight", "body_fat", "lean_mass", "bmi"] {
            XCTAssertEqual(MetricCatalog.catalogKey(forIngestKey: k), k, "\(k) no debe traducirse")
        }
    }

    /// TODA clave que hablan las pantallas resuelve a una métrica real del catálogo — ninguna se
    /// pierde en silencio (el contrato de no-pérdida a nivel de identidad).
    func testTodaClaveDeIngestaResuelveAUnaMetricaReal() {
        for k in clavesDeIngesta {
            XCTAssertNotNil(MetricCatalog.descriptor(forIngestKey: k),
                            "la clave de ingesta «\(k)» no resuelve a ninguna métrica del catálogo")
        }
    }

    // MARK: - Identidad Liquid alcanzable desde la clave de ingesta (probado por mutación)

    /// Si el puente se rompe, `resting_hr` cae al fallback neutro (`tinta500`) en vez del rosa de
    /// corazón, y esto truena. Ese es el bug que la guarda existe para atrapar.
    func testIdentidadDesdeClaveDeIngesta() {
        let fc = MetricIdentity.identity(forIngestKey: "resting_hr")
        XCTAssertEqual(fc.hue, LiquidColor.rosa, "FC en reposo es rosa de corazón, no el verde de fallback")
        XCTAssertEqual(fc.glyph, .corazon)

        let sueno = MetricIdentity.identity(forIngestKey: "asleep_min")
        XCTAssertEqual(sueno.hue, LiquidColor.indigo, "el sueño es índigo, no el verde de fallback")
        XCTAssertEqual(sueno.glyph, .luna)

        // Una que NO diverge conserva su identidad por el mismo camino.
        XCTAssertEqual(MetricIdentity.identity(forIngestKey: "steps").hue, LiquidColor.teal)
        XCTAssertEqual(MetricIdentity.identity(forIngestKey: "hrv").hue, LiquidColor.cian)
    }

    // MARK: - El nombre canónico (corto) es alcanzable desde la clave de ingesta

    func testTituloCanonicoDesdeClaveDeIngesta() {
        XCTAssertEqual(MetricCatalog.descriptor(forIngestKey: "resting_hr")?.canonicalTitle, "Resting HR",
                       "el port titula «Resting HR», no «Resting Heart Rate»")
        XCTAssertEqual(MetricCatalog.descriptor(forIngestKey: "hrv")?.canonicalTitle, "HRV")
        // La normalización también da el título del sueño.
        XCTAssertEqual(MetricCatalog.descriptor(forIngestKey: "asleep_min")?.canonicalTitle, "Asleep Time")
    }
}
