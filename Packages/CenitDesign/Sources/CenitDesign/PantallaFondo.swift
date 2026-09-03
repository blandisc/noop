import SwiftUI

// MARK: - El lienzo de pantalla de la app (decisión del dueño 2026-08-29, sesión /inject)
//
// UN solo componente compartido para el fondo de TODAS las secciones (Entrenar, Tendencias, Ajustes…),
// para que ninguna divergiera en su lienzo. Reemplaza al papel cálido (`InstrumentoTheme.paper`) como
// GROUND de pantalla; `paper`/`surface` siguen vivos para toolbars, hojas y tarjetas.
//
// Hoy es la excepción declarada: su lienzo es `LiquidAtmosfera` (las partículas del orbe), que ya
// asienta sobre este mismo blanco — por eso no lleva `.pantallaFondo()` y sus partículas quedan intactas.

public enum CenitColor {
    /// El blanco del lienzo de pantalla — el token único. Cámbialo aquí y cambia en toda la app.
    public static let pantalla = LiquidTheme.dynamic(light: .white, dark: Color(hex: "#0C0B0A"))
}

public extension View {
    /// El fondo de pantalla compartido de la app. Aplícalo en el ground de cada sección (no en tarjetas
    /// ni paneles teñidos, que tienen su propio color).
    func pantallaFondo() -> some View {
        background(CenitColor.pantalla.ignoresSafeArea())
    }
}
