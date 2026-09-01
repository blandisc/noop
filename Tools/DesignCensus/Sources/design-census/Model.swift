import Foundation

/// Las 8 dimensiones del censo (issue FER-266 §b).
enum Dimension: String, CaseIterable, Codable {
    case color
    case spacing
    case radiusElevation = "radio_elevacion"
    case typography = "tipografia_dynamictype"
    case movement = "movimiento"
    case interaction = "interaccion_haptica"
    case iconography = "iconografia"
    case composition = "composicion"
}

/// Un hallazgo [MEDIDO] por el AST: un literal o una API de evasión, con su ubicación.
struct Hit: Codable {
    let file: String
    let line: Int
    let dimension: Dimension
    let rule: String       // p.ej. "literal-radius", "evasion:Color.white"
    let snippet: String
    let value: Double?      // el número, si el hit es un literal numérico
}

/// Un `// token-exempt: <razón>` con su archivo/línea y la taxonomía asignada.
struct ExemptHit: Codable {
    let file: String
    let line: Int
    let reason: String
    let category: String   // dato | sistema | falta-pieza | optico | paridad | unico
}

/// Candidato del detector de composición (fondo+radio+sombra en cadena) — solo reporte.
struct CompositionCandidate: Codable {
    let file: String
    let line: Int
    let snippet: String
}

/// Deuda por generación visual, por archivo.
enum Generation: String, Codable {
    case liquid            // «Liquid Glass · El Eje» — vigente
    case instrumento       // «Instrumento diurno / papel cálido» — absorbida, en migración
    case indeterminada     // ni marcador Liquid* ni Instrumento* — no clasificable por símbolo
}

struct FileGenerationCount: Codable {
    let file: String
    let target: String
    let generation: Generation
}
