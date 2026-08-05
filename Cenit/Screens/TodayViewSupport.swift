import SwiftUI
import StrandAnalytics
import CenitStore
import Foundation

/// Publica el offset vertical del tope del contenido de Hoy para el pull-to-refresh propio (FER-222).
/// En el tope vale 0; al jalar hacia abajo (overscroll) crece > 0; con scroll normal es < 0. Solo se
/// conserva el último valor (un único productor), así que `reduce` toma el más reciente.
struct TodayScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension TodayView {

    /// Los ≤7 valores válidos más recientes de una métrica sobre los días de base: su ventana de media.
    func history(_ days: [DailyMetric], _ pick: (DailyMetric) -> Double?) -> [Double] {
        Array(days.compactMap(pick).suffix(7))
    }

}
