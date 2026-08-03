import XCTest
import StrandAnalytics
@testable import Cenit

/// FER-29 · F3a-bis — el gate de cobertura del contrato 4. El compositor
/// (`LiquidMetricSheetView`, `TrainingLoadSheet`) ya no lleva el copy de las lecturas de
/// nivel: lo pide al catálogo con la clave que emite `MetricLevelPhrase`. Este test afirma
/// que CADA fila de `MetricLevelPhrase.table` (más las dos variantes `.lastNight` de sueño)
/// EXISTE en el String Catalog del bundle principal — si falta una, `String(localized:)`
/// devuelve la clave tal cual y el test truena, en vez de que el usuario vea «reading.…».
final class MetricReadingCoverageTests: XCTestCase {

    /// Una clave del catálogo RESUELVE cuando el string devuelto NO es la clave misma.
    private func assertResuelve(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        let resuelto = String(localized: String.LocalizationValue(key), bundle: .main)
        XCTAssertNotEqual(resuelto, key,
                          "Falta en el catálogo la clave de lectura «\(key)»",
                          file: file, line: line)
    }

    /// Cada `(metricID, levelKey)` del contrato tiene su frase en el catálogo.
    func test_todaLaTablaDeFrasesResuelve() {
        let filas = MetricLevelPhrase.table
        XCTAssertFalse(filas.isEmpty, "MetricLevelPhrase.table quedó vacía")
        for fila in filas {
            assertResuelve(fila.key)
        }
    }

    /// Las dos variantes «anoche» de sueño (contrato B6) también existen.
    func test_variantesLastNightDeSuenoResuelven() {
        for base in ["reading.vsTarget.sleep.short", "reading.vsTarget.sleep.extended"] {
            assertResuelve(base + ".lastNight")
        }
    }
}
