import XCTest
import SwiftUI
import StrandDesign
@testable import Cenit

/// Guarda de los cimientos de la migración del aterrizaje de Tendencias (CuerpoView) a Liquid Glass
/// (FER-100). La clase de defecto que mata es la misma de siempre: dos vocabularios de color para el
/// MISMO dominio. Hoy el landing pinta cada dominio con `InstrumentoTheme.data*` inline (~14 lugares),
/// una escalera de color de PAPEL — con bugs latentes: temperatura de piel reusa el ámbar de esfuerzo,
/// VO₂max y respiración reusan un azul que significa otra cosa. La fuente única canónica ya existe:
/// `MetricIdentity.identity(forKey:)` (calcada de la hoja de Hoy, FER-104/TND-29). Estas guardas fijan
/// que el color de cada dominio del landing SALE de esa fuente, con los valores correctos, ANTES de
/// mover el vidrio — para que el port rute por ella y no reintroduzca `theme.data*`.
final class AterrizajeColorEscaleraUnicaTests: XCTestCase {

    /// Cada dominio que el landing pinta → su tono Liquid canónico. Si el port usa `theme.data*` en vez
    /// de `MetricIdentity`, estos valores no calzan (temperatura ámbar, vo2max azul, etc.).
    func testColorDeDominioSaleDeLaFuenteUnica() {
        func hue(_ key: String) -> Color { MetricIdentity.identity(forKey: key).hue }

        // Rest & load
        XCTAssertEqual(hue("sleep_total_min"), LiquidColor.indigo, "Sleep = índigo")
        XCTAssertEqual(hue("strain"), LiquidColor.ambar, "Day load = ámbar")
        XCTAssertEqual(hue("stress"), LiquidColor.estresMedio, "Stress = ocre medio, no verde")

        // Vitals
        XCTAssertEqual(hue("hrv"), LiquidColor.cian)
        XCTAssertEqual(hue("rhr"), LiquidColor.rosa, "Resting HR = rosa de corazón")
        XCTAssertEqual(hue("spo2"), LiquidColor.azul, "Blood Oxygen = azul (familia respiratoria)")
        XCTAssertEqual(hue("resp_rate"), LiquidColor.azul, "Respiratory = azul, NO el SpO₂-reuse de papel")
        XCTAssertEqual(hue("skin_temp"), LiquidColor.doradoTemp,
                       "Skin temp = su DORADO propio, NO el ámbar de esfuerzo que el papel le prestaba (FER-79)")

        // Activity + Longevity
        XCTAssertEqual(hue("steps"), LiquidColor.teal)
        XCTAssertEqual(hue("vo2max"), LiquidColor.tinta500,
                       "VO₂ Max = NEUTRO (sin familia aún, D1 de FER-108), NO el azul que el papel le prestaba")
    }

    /// La FC intradía del landing (columna «Heart Rate») es de la familia del corazón, no del neutro.
    /// Probado por mutación: sin la clave `heart_rate` en el caso rosa, cae al fallback tinta500.
    func testHeartRateIntradiaEsRosa() {
        XCTAssertEqual(MetricIdentity.identity(forKey: "heart_rate").hue, LiquidColor.rosa,
                       "la FC intradía comparte la familia rosa de corazón")
        XCTAssertEqual(MetricIdentity.identity(forKey: "heart_rate").glyph, .corazon)
    }
}
