import SwiftUI

// MARK: - Tope de Dynamic Type en las hojas (FER-394 · FER-128 r8/r9)

extension View {
    /// FER-394 capó Dynamic Type en xxxLarge para TODA la app («no prometemos los 5 tamaños
    /// gigantes de Accesibilidad»). Un `.sheet` abre una rama de entorno nueva y NO hereda ese
    /// tope: las hojas de Hoy salían a AX3 mientras Hoy se quedaba en xxxLarge —dos políticas
    /// en la misma pantalla, y leyendas/selectores/chips partiendo palabras (FER-128 r8,
    /// explorador XC8-02…06/10). Mismo tope, re-aplicado al contenido de cada hoja — también a
    /// las hojas HIJAS que una hoja de Hoy presenta (r9: `SleepDetailScreen`, `StressDayMapView`).
    func topeTextoHoja() -> some View { dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
}
