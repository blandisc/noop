import Foundation

/// Árbitro de colisiones (issue §d): DECIDE, no aplica. Compara los literales medidos por
/// dimensión contra `roles.yaml` (el mapa sitio→rol etiquetado a mano) para separar:
///   - «roles distintos» — el DNA ya tiene un rol para ese valor (LiquidRadius.tarjeta=18 vs
///     .modulo=20 NO es colisión, son roles separados).
///   - «colisión real» — dos o más VALORES DISTINTOS compiten por el mismo rol/contexto, o un
///     literal no mapeado a ningún rol conocido.
struct CollisionVerdict {
    let dimension: String
    let context: String       // mosaico | sobrio | watch_oled | global
    let role: String?         // rol en disputa, si roles.yaml ya lo nombra
    let values: [Double]
    let canonical: Double?
    let rationale: String
}

enum Arbiter {
    /// Agrupa los `Hit` de radio/espaciado por (dimensión, contexto-heurístico) y contrasta
    /// contra roles.yaml. El contexto se infiere del PATH del archivo (Watch/mosaico/sobrio) —
    /// es una heurística declarada, no una verdad medida; se documenta como tal en el reporte.
    static func verdicts(hits: [Hit], roles: [RoleEntry]) -> [CollisionVerdict] {
        var verdicts: [CollisionVerdict] = []
        let byDimension = Dictionary(grouping: hits.filter { $0.value != nil && ($0.dimension == .radiusElevation || $0.dimension == .spacing) }) { $0.dimension }

        for (dim, dimHits) in byDimension {
            let dimensionKey = dim == .radiusElevation ? "radius" : "spacing"
            let contexted = Dictionary(grouping: dimHits) { context(for: $0.file) }
            for (ctx, group) in contexted {
                let values = Set(group.compactMap { $0.value }).sorted()
                guard values.count > 1 else { continue } // un solo valor: nada que arbitrar
                // ¿Cada valor ya tiene rol propio en roles.yaml (roles distintos, no colisión)?
                let roleForValue: [Double: String] = Dictionary(uniqueKeysWithValues: roles
                    .filter { $0.dimension == dimensionKey && ($0.context == ctx || $0.context == "global") }
                    .map { ($0.value, $0.role) })
                let unmapped = values.filter { roleForValue[$0] == nil }
                if unmapped.isEmpty {
                    continue // todos los valores ya son roles distintos y nombrados — no colisiona
                }
                // Canónico: si Liquid (roles.yaml) ya define un rol para alguno de estos valores,
                // ese es el canónico; si no, el más frecuente entre archivos ya-Liquid.
                let canonical = roleForValue.keys.sorted().first ?? mostFrequentInLiquidFiles(group)
                let rationale = roleForValue.isEmpty
                    ? "Ningún valor de este grupo tiene rol en roles.yaml — candidato a `falta-pieza` o a colisión real; requiere veredicto del dueño."
                    : "roles.yaml ya nombra \(roleForValue.count) de \(values.count) valores; \(unmapped.count) sin rol compiten por el mismo sitio — candidatos a colisión."
                verdicts.append(CollisionVerdict(dimension: dimensionKey, context: ctx, role: roleForValue.values.first, values: values, canonical: canonical, rationale: rationale))
            }
        }
        return verdicts.sorted { ($0.dimension, $0.context) < ($1.dimension, $1.context) }
    }

    private static func context(for file: String) -> String {
        if file.contains("Watch") { return "watch_oled" }
        if file.contains("Liquid") { return "mosaico" } // aproximación: superficies Liquid ya migradas
        return "sobrio"
    }

    private static func mostFrequentInLiquidFiles(_ hits: [Hit]) -> Double? {
        let liquidHits = hits.filter { $0.file.contains("Liquid") }
        var counts: [Double: Int] = [:]
        for h in liquidHits { if let v = h.value { counts[v, default: 0] += 1 } }
        if counts.isEmpty {
            for h in hits { if let v = h.value { counts[v, default: 0] += 1 } }
        }
        // Empate de frecuencia → el valor MENOR (determinismo: `Dictionary.max` no es estable
        // entre corridas cuando dos valores empatan en conteo).
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
    }
}

/// Deuda por generación (issue §c): qué pantallas siguen en «papel cálido»/oscuro por target,
/// vía los símbolos que efectivamente importan (Liquid* vs Instrumento*) — no por fecha ni git-blame.
enum GenerationCensus {
    static func classify(file: String, symbolReferences: Set<String>) -> Generation {
        let liquid = symbolReferences.contains { $0.hasPrefix("Liquid") }
        let instrumento = symbolReferences.contains { $0.hasPrefix("Instrumento") }
        if liquid && !instrumento { return .liquid }
        if instrumento && !liquid { return .instrumento }
        if liquid && instrumento { return .liquid } // mixta: se cuenta ya-migrada, con nota aparte
        return .indeterminada
    }

    static func target(for path: String) -> String {
        for t in ["CenitWatch", "CenitWidgets", "CenitShared", "CenitApp", "Cenit"] {
            if path.contains("/\(t)/") { return t }
        }
        return "otro"
    }
}
