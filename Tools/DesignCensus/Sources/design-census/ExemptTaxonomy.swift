import Foundation

/// Censo de `// token-exempt: <razón>` — texto crudo (no AST: es un comentario, el AST ya lo
/// descarta como trivia y reconstruirlo no aporta nada sobre leer la línea).
enum ExemptScanner {
    static let pattern = try! NSRegularExpression(pattern: #"//\s*token-exempt:?\s*(.*)$"#)

    static func scan(text: String, file: String) -> [ExemptHit] {
        var out: [ExemptHit] = []
        let lines = text.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            let ns = line as NSString
            guard let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let reason = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
            out.append(ExemptHit(file: file, line: idx + 1, reason: reason.trimmingCharacters(in: .whitespaces), category: classify(reason)))
        }
        return out
    }

    /// Taxonomía del issue (§c): dato / sistema / falta-pieza / optico / paridad / unico.
    /// Heurística por palabra clave sobre la razón anotada a mano — el humano que escribió el
    /// `token-exempt` ya explicó por qué; esto solo la bucketiza para el censo, no reinterpreta.
    static func classify(_ reasonRaw: String) -> String {
        let reason = reasonRaw.lowercased()
        if reason.isEmpty { return "unico" }
        func any(_ needles: [String]) -> Bool { needles.contains { reason.contains($0) } }

        if any(["dato", "barra", "leyenda", "swatch", "keypad", "gráfica", "grafica", "chart", "eje x", "eje y", "geometría de datos", "geometria de datos"]) {
            return "dato"
        }
        if any(["widget", "watch", "sistema operativo", "os ", "dynamic island", "isla dinámica", "isla dinamica", "geometría de sistema", "geometria de sistema", "hig", "safe area del sistema"]) {
            return "sistema"
        }
        if any(["sin token", "no hay token", "falta token", "falta pieza", "falta una pieza", "handoff", "banner", "no existe token", "todavía no", "todavia no"]) {
            return "falta-pieza"
        }
        if any(["óptico", "optico", "antialiasing", "ajuste visual", "hairline", "capilar", "pixel"]) {
            return "optico"
        }
        if any(["paridad", "legacy", "mismo valor que", "espeja", "iguala a", "compat"]) {
            return "paridad"
        }
        return "unico"
    }

    /// Regla ×3 (épico §5 principio 5): si el mismo patrón de exempt aparece 3+ veces bajo
    /// `falta-pieza`, es un componente que falta, no una excepción. Agrupa por una firma
    /// normalizada de la razón (palabras clave, sin ceremonia de NLP) y regresa clusters ≥3
    /// con una pieza propuesta (el texto más frecuente del cluster, a falta de mejor nombre).
    static func faltaPiezaClusters(_ hits: [ExemptHit]) -> [(signature: String, count: Int, examples: [ExemptHit], piezaPropuesta: String)] {
        let faltantes = hits.filter { $0.category == "falta-pieza" }
        var groups: [String: [ExemptHit]] = [:]
        for h in faltantes {
            groups[normalize(h.reason), default: []].append(h)
        }
        return groups
            .filter { $0.value.count >= 3 }
            .map { sig, hs in
                (signature: sig, count: hs.count, examples: Array(hs.prefix(5)),
                 piezaPropuesta: mostCommonReason(hs))
            }
            // Empate de conteo → orden alfabético de la firma (determinismo entre corridas:
            // `Dictionary` no garantiza orden de iteración estable entre procesos).
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.signature < $1.signature }
    }

    private static func normalize(_ reason: String) -> String {
        let stop: Set<String> = ["el", "la", "de", "del", "un", "una", "y", "que", "es", "en", "no", "para", "con", "a", "se"]
        let tokens = reason.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stop.contains($0) }
        return tokens.sorted().joined(separator: "-")
    }

    private static func mostCommonReason(_ hits: [ExemptHit]) -> String {
        var counts: [String: Int] = [:]
        for h in hits { counts[h.reason, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? hits.first?.reason ?? ""
    }
}
