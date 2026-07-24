import Foundation
import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - MetricLevelsHostModel (épico hoja Liquid, F3a)
//
// El WIRING del instrumento de niveles, extraído de `MetricInfoSheet` SIN cambiar un bit
// de comportamiento: serie completa parseada UNA vez, niveles resueltos con caché (incl.
// el fold personal de HRV sobre `Baselines.normalRange`, FER-619/571), y la ventana por
// rango vía `MetricWindowMath.make`. La hoja Instrumento sigue usando su propio código;
// este host lo consumirá la hoja Liquid (F3b/F6) — y los tests de paridad garantizan que
// ambos caminos producen los MISMOS números (LIQUID-SHEET-CONTRACT §6 F3a).

@Observable
final class MetricLevelsHostModel {
    /// El rango activo del explorador (semana por defecto, paridad con la hoja).
    var range: ExploreRange = .week

    private(set) var parsed: MetricWindowMath.Parsed = []

    /// D7 · ¿Ya llegó la serie? El host no exponía estado de carga, así que la hoja no podía
    /// distinguir «todavía no sé» de «no hay nada» e imprimía «0 de tus últimas 0 noches»
    /// (y «0 noches» en cada fila) desde el primer frame. Se enciende cuando `load(rows:)`
    /// corre — también con `rows` vacío: eso ya es una respuesta, no una espera.
    private(set) var cargado = false
    private var cache: [MetricLevels.Level]? = nil
    private var cacheKey: String = ""

    private let metricID: String
    private let levelsMetric: MetricLevels.FixedMetric?
    private let levelsRelative: Bool

    /// Misma parametrización que `MetricInfo`: `levelsMetric` = umbrales fijos (FER-570);
    /// `levelsRelative` = banda personal de HRV desde la base propia (FER-619).
    init(metricID: String, levelsMetric: MetricLevels.FixedMetric?, levelsRelative: Bool) {
        self.metricID = metricID
        self.levelsMetric = levelsMetric
        self.levelsRelative = levelsRelative
    }

    /// Carga la serie completa (el `levelsSeriesLoader` de siempre) parseando cada día a
    /// `Date` UNA vez — la misma memoización de la hoja (FER-607/976).
    func load(rows: [(day: String, value: Double)]) {
        parsed = rows.map { (day: $0.day, date: Repository.parseDayKey($0.day), value: $0.value) }
        refreshCache()
        cargado = true
    }

    /// La ventana del rango activo — lo que la gráfica dibuja.
    var window: MetricWindow {
        MetricWindowMath.make(parsed, selected: range)
    }

    /// Huella de los insumos de `levels` (id + historia completa) — el fold de HRV solo
    /// se re-corre cuando cambian, no por render (paridad `resolvedLevelsKey`, FER-976).
    var levelsKey: String {
        "\(metricID)|\(parsed.count)|\(parsed.first?.day ?? "")|\(parsed.last?.day ?? "")"
    }

    /// Los niveles del explorador (umbral fijo o banda personal HRV). nil = HRV sin base.
    var levels: [MetricLevels.Level]? {
        levelsKey == cacheKey ? cache : compute()
    }

    private func compute() -> [MetricLevels.Level]? {
        if let metric = levelsMetric { return MetricLevels.levels(for: metric) }
        guard levelsRelative else { return nil }
        // HRV: banda multiplicativa desde la base log-normal propia (exp(lnBase ± σ) → ms),
        // el MISMO motor de base que usa el score (foldHistory + hrvCfg). Guard nValid >= 1
        // — paridad FER-571/619 (Plews 2013).
        let state = Baselines.foldHistory(parsed.map { Optional($0.value) }, cfg: Baselines.hrvCfg)
        guard state.nValid >= 1 else { return nil }
        let band = Baselines.normalRange(state)
        return [
            MetricLevels.Level(key: "below",  lower: nil,             upper: band.lowerBound),
            MetricLevels.Level(key: "inBase", lower: band.lowerBound, upper: band.upperBound),
            MetricLevels.Level(key: "above",  lower: band.upperBound, upper: nil),
        ]
    }

    /// La clasificación de la ventana activa (conteos por nivel, total, nivel de hoy) —
    /// EXACTAMENTE la misma llamada que hace el explorador (MetricLevelsExplorer:67):
    /// `MetricLevels.classification(values:today:levels:)` sobre la ventana y los niveles
    /// resueltos. nil si no hay niveles (HRV sin base).
    func clasificacion(today: Double?) -> MetricLevels.Classification? {
        guard let levels else { return nil }
        return MetricLevels.classification(values: window.values, today: today, levels: levels)
    }

    private func refreshCache() {
        let key = levelsKey
        guard key != cacheKey else { return }
        cacheKey = key
        cache = compute()
    }
}
