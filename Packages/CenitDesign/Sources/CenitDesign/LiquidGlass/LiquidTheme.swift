import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - LiquidTheme — resolución de color por modo (épico Modo oscuro · FER-343, cimiento A1/FER-345)
//
// El contrato de resolución de tema. Los tokens públicos de `LiquidColor` conservan su NOMBRE y su
// tipo `Color`, pero su valor-fuente pasa a un `Color` dinámico construido aquí con el provider de la
// plataforma (`UIColor/NSColor(dynamicProvider:)`, detrás de `#if canImport` — el paquete sigue sin
// `import UIKit/AppKit` desnudo). La fuente de verdad DETERMINISTA para tests y para el héroe Metal es
// `Color.resolved(at:)`, que fija `EnvironmentValues.colorScheme` de forma EXPLÍCITA antes de
// `resolve(in:)` — un color dinámico NO resuelve oscuro desde la apariencia ambiente en un host
// headless de macOS; solo desde un scheme explícito (probado en `LiquidThemeResolveTests`).
//
// Un solo interruptor global, `oscuroHabilitado` (default `false`, leído DENTRO de cada provider),
// mantiene TODO resolviendo claro — en todos los procesos, app y widgets — hasta que A3 lo voltea de
// forma atómica. Con el flag apagado, los valores claros son byte-idénticos a los hex estáticos
// anteriores (`LiquidThemeRegresionClaroTests`), así que A1 no cambia nada visible por sí solo.
//
// Watch: el `#else` deja watchOS sin rama dinámica a propósito — el reloj conserva su vocabulario
// `LiquidOLED` (decisión D1=a); sus `static let` NO se vuelven dinámicos.

public enum LiquidTheme {

    /// ¿Está viva la maquinaria de modo oscuro? Default `false` → TODO resuelve claro (A1/A2).
    /// A3 lo pone en `true` (cambio de default, MISMO PR) para todos los procesos con un solo
    /// interruptor de fuente. En producción no vuelve a cambiar en runtime (la elección
    /// Sistema/Claro/Oscuro es `preferredColorScheme`, no este flag); solo los tests lo alternan.
    nonisolated(unsafe) public static var oscuroHabilitado = false

    /// Un `Color` que sigue el modo de la vista. Colapsa a `light` mientras `oscuroHabilitado == false`.
    public static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(UIKit) && os(iOS)
        return Color(uiColor: UIColor { traits in
            guard oscuroHabilitado, traits.userInterfaceStyle == .dark
            else { return UIColor(light) }
            return UIColor(dark)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            guard oscuroHabilitado,
                  appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            else { return NSColor(light) }
            return NSColor(dark)
        })
        #else
        // watchOS (importa UIKit pero no queremos el modo dinámico del iPhone; D1=a) → siempre claro.
        return light
        #endif
    }
}

public extension Color {
    /// Fuente de verdad determinista para tests y Metal: resolución EXPLÍCITA por `scheme`.
    /// Fija `colorScheme` a mano y lee `resolve(in:)` — no depende de la apariencia del host.
    /// Honra `LiquidTheme.oscuroHabilitado` (claro en ambos schemes si está apagado).
    func resolved(at scheme: ColorScheme) -> Color {
        var env = EnvironmentValues()
        env.colorScheme = scheme
        return Color(resolve(in: env))
    }
}
