import Foundation

/// Utilidades compartidas del censo. Nada de esto conoce SwiftSyntax — vive aparte para que
/// `Visitor.swift` (el único archivo que toca el AST) se lea de corrido.

// MARK: - Enumeración de archivos

enum FileWalker {
    /// Recorre las raíces dadas y regresa cada `.swift` bajo ellas, excluyendo `Packages/**`
    /// (la fuente de verdad, no el sospechoso) y el propio `Tools/DesignCensus` (por si algún
    /// día alguien apunta `--repo` a sí mismo).
    static func swiftFiles(repoRoot: URL, roots: [String]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for root in roots {
            let base = repoRoot.appendingPathComponent(root)
            guard let en = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in en {
                guard url.pathExtension == "swift" else { continue }
                let path = url.path
                if path.contains("/Packages/") { continue }
                if path.contains("/Tools/DesignCensus/") { continue }
                if path.contains("/.build/") || path.contains("/DerivedData/") { continue }
                out.append(url)
            }
        }
        return out.sorted { $0.path < $1.path }
    }
}

// MARK: - Wilson score interval (95%)

enum Wilson {
    /// Intervalo de Wilson para una proporción — el que no colapsa a [0,1] con n chico
    /// como sí le pasa al normal approximation. z = 1.96 (95%).
    static func interval(successes: Int, total: Int, z: Double = 1.96) -> (lower: Double, upper: Double) {
        guard total > 0 else { return (0, 0) }
        let n = Double(total)
        let p = Double(successes) / n
        let z2 = z * z
        let denom = 1 + z2 / n
        let center = p + z2 / (2 * n)
        let margin = z * (( p * (1 - p) / n + z2 / (4 * n * n) ).squareRoot())
        let lower = max(0, (center - margin) / denom)
        let upper = min(1, (center + margin) / denom)
        return (lower, upper)
    }
}

// MARK: - Git metadata (para el header del reporte — nunca el reloj)

enum GitInfo {
    static func headShortHash(repoRoot: URL) -> String {
        run(["git", "-C", repoRoot.path, "rev-parse", "--short=12", "HEAD"]) ?? "sin-commit"
    }

    /// Fecha del commit HEAD (autor), no `Date()` — así dos corridas del mismo árbol
    /// producen el MISMO header y el diff es cero (regla de idempotencia del issue).
    static func headCommitDateISO(repoRoot: URL) -> String {
        run(["git", "-C", repoRoot.path, "show", "-s", "--format=%cI", "HEAD"]) ?? "sin-fecha"
    }

    private static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty ?? true) ? nil : s
        } catch {
            return nil
        }
    }
}

// MARK: - roles.yaml (formato propio, deliberadamente simple)
//
// No traemos Yams: el paquete ya tiene UNA dependencia de red (swift-syntax) y el formato que
// necesitamos es plano. `roles.yaml` es una lista de líneas `dimension.rol: valor  # contexto`;
// líneas en blanco y las que empiezan con `#` se ignoran. Ver Tools/DesignCensus/roles.yaml para
// el archivo real — es el insumo [ETIQUETADO] que el agente mantiene a mano.

struct RoleEntry {
    let dimension: String   // "radius" | "spacing"
    let role: String        // "control", "tarjeta", "s400", …
    let value: Double
    let context: String     // "mosaico" | "sobrio" | "watch_oled" | "global"
}

enum RolesFile {
    static func parse(_ url: URL) -> [RoleEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [RoleEntry] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // "radius.control: 12  # mosaico"
            let parts = line.split(separator: "#", maxSplits: 1)
            let body = parts[0].trimmingCharacters(in: .whitespaces)
            let context = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "global"
            guard let colon = body.firstIndex(of: ":") else { continue }
            let key = body[body.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let valueStr = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let value = Double(valueStr) else { continue }
            let keyParts = key.split(separator: ".", maxSplits: 1)
            guard keyParts.count == 2 else { continue }
            out.append(RoleEntry(dimension: String(keyParts[0]), role: String(keyParts[1]), value: value, context: context.isEmpty ? "global" : context))
        }
        return out
    }
}

// MARK: - Etiquetado de composición (labels/composicion-etiquetado.json)

struct CompositionLabel: Codable {
    let file: String
    let line: Int
    let snippet: String
    /// true = un agente humano/otro-agente lo confirmó como candidato real de composición
    /// (fondo+radio+sombra repetido que debería ser un componente).
    let isComposition: Bool
    let labeler: String
}

enum LabelsFile {
    static func load(_ url: URL) -> [CompositionLabel] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CompositionLabel].self, from: data)) ?? []
    }
}
