import XCTest
import SwiftUI
import StrandDesign
import StrandModels
@testable import Cenit

/// Guardas de los cimientos de la migración de Comparar + Explorador (FER-104 / TND-29). La clase de
/// defecto que matan es la misma que produjo P1 en gemelas y en el detalle de vital: dos escaleras /
/// dos vocabularios / dos mapas para LA MISMA cosa. Antes de mover el vidrio (TND-30/31) estos fijan
/// que hay UNA sola fuente por concepto:
///   • (2) el resolvedor «clave → serie diaria» da el MISMO número desde cualquier pantalla;
///   • (3) el puente de identidad métrica → (hue Liquid, glifo) es único, calcado de la hoja canónica;
///   • (4) el título canónico dice el nombre de Hoy («Effort»/«Stress»), no «Day Strain».
///   • foco 2: el rango es UNO solo (`ExploreRange`), con su frase heredada de `CompareRange`.
/// La suite corre en inglés: se afirma contra los defaultValue EN.
final class CompareExploreEscaleraUnicaTests: XCTestCase {

    // MARK: - (2) UN resolvedor de serie: el mismo número desde Comparar y Explorador
    //
    // Ambas pantallas llaman `MetricSeriesResolver.dashboardSeries` (CompareView.loadSelected y
    // MetricExplorerView), así que un mismo día resuelve al mismo número. Antes discrepaban en dos.

    /// Calorías (active_kcal / energy_kcal) NO se resuelven del dashboard: el picker es nil en ambas,
    /// así que las dos pantallas caen a `repo.series()` — el valor catalogado (Apple/importación), no
    /// el estimado HR-only `activeKcalEst` que las cambiaba de significado.
    func testCaloriasNoSeResuelvenDelDashboard() {
        XCTAssertNil(MetricSeriesResolver.dashboardPicker(for: "active_kcal"),
                     "active_kcal no puede resolver activeKcalEst: es OTRA cifra")
        XCTAssertNil(MetricSeriesResolver.dashboardPicker(for: "energy_kcal"),
                     "energy_kcal tampoco: cae a series()")
    }

    /// Eficiencia de sueño: se normaliza a PORCENTAJE (× 100 si viene como fracción 0–1), nunca cruda
    /// — antes el Explorador devolvía 0.92 y lo pintaba «1 %» contra la unidad «%» del catálogo.
    func testEficienciaDeSuenoEnPorcentaje() {
        let pick = MetricSeriesResolver.dashboardPicker(for: "sleep_efficiency")
        XCTAssertNotNil(pick)
        XCTAssertEqual(pick?(day(efficiency: 0.92)) ?? .nan, 92, accuracy: 0.0001,
                       "0.92 (fracción) debe leer 92, no 0.92")
        XCTAssertEqual(pick?(day(efficiency: 92)) ?? .nan, 92, accuracy: 0.0001,
                       "92 (ya en %) se conserva")
    }

    /// El resolvedor es UNO: `dashboardSeries` construye la serie con el mismo picker que consumen las
    /// dos pantallas, así que el número de un día es idéntico venga de donde venga.
    func testSerieResueltaEsUnicaYNormalizada() {
        let dias = [day(day: "2026-01-01", efficiency: 0.80),
                    day(day: "2026-01-02", efficiency: 0.91)]
        let serie = MetricSeriesResolver.dashboardSeries("sleep_efficiency", from: dias)
        XCTAssertEqual(serie?.map(\.value), [80, 91])
        // Calorías: nil (misma decisión para ambas pantallas).
        XCTAssertNil(MetricSeriesResolver.dashboardSeries("active_kcal", from: dias))
    }

    // MARK: - (3) UN puente de identidad métrica → (hue Liquid, glifo)

    /// El puente está calcado de `LiquidMetricSheetView.tono` / `.glifo` (la hoja canónica): esfuerzo →
    /// ámbar, VFC → cian, FC → rosa, temperatura → dorado propio, pasos → teal, SpO₂ → azul.
    func testPuenteDeIdentidadHue() {
        XCTAssertEqual(MetricIdentity.identity(forKey: "strain").hue, LiquidColor.ambar)
        XCTAssertEqual(MetricIdentity.identity(forKey: "hrv").hue, LiquidColor.cian)
        XCTAssertEqual(MetricIdentity.identity(forKey: "rhr").hue, LiquidColor.rosa)
        XCTAssertEqual(MetricIdentity.identity(forKey: "skin_temp").hue, LiquidColor.doradoTemp)
        XCTAssertEqual(MetricIdentity.identity(forKey: "steps").hue, LiquidColor.teal)
        XCTAssertEqual(MetricIdentity.identity(forKey: "spo2").hue, LiquidColor.azul)
    }

    func testPuenteDeIdentidadGlifo() {
        XCTAssertEqual(MetricIdentity.identity(forKey: "strain").glyph, .llama)
        XCTAssertEqual(MetricIdentity.identity(forKey: "hrv").glyph, .onda)
        XCTAssertEqual(MetricIdentity.identity(forKey: "spo2").glyph, .resp)
    }

    /// Una métrica sin familia cae a tinta NEUTRA sin glifo — NO a verdePrimario (FER-108 · Grok D1):
    /// ese verde ya significa «veredicto/recuperación», prestárselo a una métrica sin identidad es
    /// pintar con un color que ya dice otra cosa (el mismo defecto del papel). Neutro = «sin identidad
    /// aún», honesto. Una clave inventada y una del catálogo sin familia (weight) lo hacen.
    func testPuenteFallbackNeutroSinGlifo() {
        let banana = MetricIdentity.identity(forKey: "banana")
        XCTAssertEqual(banana.hue, LiquidColor.tinta500, "sin identidad = tinta neutra, no el verde de veredicto")
        XCTAssertNil(banana.glyph)
        let weight = MetricIdentity.identity(forKey: "weight")
        XCTAssertEqual(weight.hue, LiquidColor.tinta500, "composición corporal aún sin familia: neutro, no verde")
        XCTAssertNil(weight.glyph)
        // recovery SÍ es verdePrimario legítimamente (verde de veredicto, su identidad real): está
        // mapeado EXPLÍCITO, no cae por el fallback — por eso NO cambió a neutro.
        XCTAssertEqual(MetricIdentity.identity(forKey: "recovery").hue, LiquidColor.verdePrimario)
        XCTAssertNil(MetricIdentity.identity(forKey: "recovery").glyph)
    }

    /// El puente cubre CADA métrica del catálogo (no truena por una clave nueva): siempre devuelve un
    /// hue, con o sin glifo.
    func testPuenteCubreTodoElCatalogo() {
        for m in MetricCatalog.all {
            _ = MetricIdentity.hue(for: m)   // no debe atorarse en ninguna clave
        }
    }

    // MARK: - (4) UN título canónico: «Effort», nunca «Day Strain»

    func testTituloCanonicoEsElDeHoy() {
        func title(_ key: String) -> String {
            MetricCatalog.all.first { $0.key == key }!.canonicalTitle
        }
        XCTAssertEqual(title("strain"), "Effort", "Hoy dice «Effort», no «Day Strain»")
        XCTAssertEqual(title("stress"), "Stress", "Hoy dice «Stress», no «Day Stress»")
        // D4/C-18: VFC y FC en reposo también toman el nombre CORTO de Hoy — «HRV»/«Resting HR» (es
        // «VFC»/«FC en reposo»), NUNCA el largo «Heart Rate Variability»/«Resting Heart Rate», que
        // HJ-12 rechazó como título (el largo solo vive en la expansión del ⓘ). La suite corre en
        // inglés, así que se afirma contra el defaultValue EN.
        XCTAssertEqual(title("hrv"), "HRV", "Hoy titula «HRV», no «Heart Rate Variability»")
        XCTAssertEqual(title("rhr"), "Resting HR", "Hoy titula «Resting HR», no «Resting Heart Rate»")
        // Una métrica sin override conserva su título de catálogo.
        XCTAssertEqual(title("recovery"), "Recovery")
        // El título CRUDO del catálogo sigue intacto (otros lo consumen como identidad): el largo se
        // conserva en `.title`, aunque `canonicalTitle` ya devuelva el corto.
        XCTAssertEqual(MetricCatalog.all.first { $0.key == "strain" }!.title, "Day Strain")
        XCTAssertEqual(MetricCatalog.all.first { $0.key == "hrv" }!.title, "Heart Rate Variability")
        XCTAssertEqual(MetricCatalog.all.first { $0.key == "rhr" }!.title, "Resting Heart Rate")
    }

    // MARK: - foco 2: UN solo rango (ExploreRange), con la frase heredada de CompareRange

    func testExploreRangePhraseHeredada() {
        XCTAssertEqual(ExploreRange.week.phrase, "the last 7 days")
        XCTAssertEqual(ExploreRange.month.phrase, "30 days")
        XCTAssertEqual(ExploreRange.quarter.phrase, "3 months")
        XCTAssertEqual(ExploreRange.half.phrase, "6 months")
        XCTAssertEqual(ExploreRange.year.phrase, "1 year")
        XCTAssertEqual(ExploreRange.all.phrase, "all history")
    }

    // MARK: - Fixture

    private func day(day: String = "2026-01-01", efficiency: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: efficiency, deepMin: nil,
                    remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                    avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)
    }
}
