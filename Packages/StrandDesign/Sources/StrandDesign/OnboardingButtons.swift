import SwiftUI

// MARK: - Onboarding / action buttons (Instrumento)
//
// FER-812: `InkButton` / `OutlineButton` are now thin aliases of the single canonical `StrandCTAButton`
// (solid / outline) so onboarding, Perfil, Import and «Listo» share the exact same CTA as the Entrenar
// flow — one radius, one padding, the grotesk voice. The names stay to keep every call site working.

/// CTA primario: relleno `ink`, label `paperHi`. El elemento de más peso de la pantalla **sin un solo
/// pixel de color**. Alias de `StrandCTAButton(.solid)`.
public struct InkButton: View {
    private let title: LocalizedStringKey
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }

    public var body: some View { StrandCTAButton(title, kind: .solid, action: action) }
}

/// Salida secundaria de PRIMERA CLASE: contorno legible, nunca un gris-fantasma. Alias de
/// `StrandCTAButton(.outline)`.
public struct OutlineButton: View {
    private let title: LocalizedStringKey
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }

    public var body: some View { StrandCTAButton(title, kind: .outline, action: action) }
}
