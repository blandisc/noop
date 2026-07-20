import Foundation

/// Single source of truth for project identity and attribution — reused by the Support screen.
/// Deliberately contains no author/AI identifiers so the public repo can stay anonymous.
enum ProjectInfo {
    static let appName = "Cénit"
    static let tagline = "Your body. Your data. Your machine. Local-first, no cloud."
    static let version = "0.1.0"
    /// Public contact for questions, feedback, bug reports. Baked into every platform.
    static let contactEmail = "contacto@cenit.app" // TODO(owner): correo real antes de subir a tienda
}

