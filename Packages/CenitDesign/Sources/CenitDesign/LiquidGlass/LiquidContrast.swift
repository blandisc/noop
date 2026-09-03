import SwiftUI

// MARK: - LiquidContrast — contraste de dato consciente del modo (A1/FER-345)
//
// `OKLab.darkened` es un algoritmo SOLO-para-claro: baja la luminosidad L para ganar contraste, lo
// que es monótono ÚNICAMENTE sobre papel claro. Sobre negro, oscurecer un tono DESTRUYE el contraste
// (p.ej. el rosa de FC cae de ~4.4 a ~1.8). El único camino sancionado para «tono de dato → tono de
// lectura AA» es `LiquidColor.contrastTuned`, que ramifica por modo y DEVUELVE un `Color` dinámico
// (así los call-sites, funciones puras que devuelven `Color` sin `@Environment`, migran 1:1 sin pasar
// el scheme). En `.dark` deja el tono si ya pasa AA o lo ACLARA — espejo de `EntrenarHilo.word(sobreOLED:)`.
//
// Este archivo y `LiquidColor.swift` (que define `tonoCampo`) son los ÚNICOS lugares sancionados para
// llamar `OKLab.darkened`/`OKLab.lightened` — el gate `no-raw-contrast` rebota cualquier uso crudo fuera.

public extension OKLab {
    /// Espejo exacto de `darkened`: SUBE la luminosidad `L` (conservando hue/chroma `a`,`b`) solo hasta
    /// alcanzar `ratio` contra un fondo OSCURO — el contraste es monótono creciente en `L` sobre negro.
    /// Devuelve `color` sin cambio si ya pasa. Bisecta en `L ∈ [origL, 1]` buscando el `L` MÁS OSCURO
    /// que aún pasa, para conservar el tono tanto como AA lo permita. Cita WCAG 2.x, igual que `darkened`.
    static func lightened(_ color: Color, toContrast ratio: Double, against bg: Color) -> Color {
        if contrastRatio(color, bg) >= ratio { return color }
        let c = color.rgbaComponents
        var lab = toLab((c.r, c.g, c.b))
        var lo = lab.L, hi = 1.0   // L más alto = más claro = más contraste sobre fondo oscuro
        for _ in 0..<16 {
            let mid = (lo + hi) / 2
            lab.L = mid
            let rgb = toRGB(lab)
            if contrastRatio(Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b), bg) >= ratio {
                hi = mid          // pasa — el umbral está en o por debajo; prueba más oscuro
            } else {
                lo = mid          // falla — aclara más
            }
        }
        lab.L = hi
        let rgb = toRGB(lab)
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

public extension LiquidColor {
    /// El par «hue de dato → tono de lectura AA», resuelto por modo. En `.light` oscurece contra el
    /// papel claro (el comportamiento de hoy). En `.dark` deja el gemelo oscuro del hue si ya pasa AA
    /// sobre el suelo oscuro (lo que A2 garantiza), o lo aclara (espejo de `EntrenarHilo.word(sobreOLED:)`).
    /// Devuelve un `Color` dinámico → los call-sites migran 1:1 desde `OKLab.darkened(…, against:)` sin
    /// pasar `scheme`. `floor` debe ser un token dinámico (el ancla se resuelve por modo dentro).
    static func contrastTuned(_ hue: Color, against floor: Color, toContrast ratio: Double = 4.5) -> Color {
        LiquidTheme.dynamic(
            light: OKLab.darkened(hue.resolved(at: .light), toContrast: ratio,
                                  against: floor.resolved(at: .light)),
            dark: tunedDark(hue.resolved(at: .dark), floor: floor.resolved(at: .dark), ratio: ratio)
        )
    }

    private static func tunedDark(_ h: Color, floor: Color, ratio: Double) -> Color {
        OKLab.contrastRatio(h, floor) >= ratio
            ? h
            : OKLab.lightened(h, toContrast: ratio, against: floor)
    }
}
