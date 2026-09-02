import Foundation

/// Arma CENSO.md + CENSO.json. Todo lo que entra aquí ya viene ordenado/determinista — el
/// único dato no derivado del árbol es la fecha, y esa sale de `git show HEAD` (Support.swift),
/// nunca del reloj, para que dos corridas del mismo commit produzcan el MISMO archivo (regla de
/// idempotencia del issue).
struct CensusReport {
    let repoRoot: String
    let commitHash: String
    let commitDate: String
    let invocation: String
    let scannedFiles: Int
    let hits: [Hit]
    let exempts: [ExemptHit]
    let compositionCandidates: [CompositionCandidate]
    let compositionLabels: [CompositionLabel]
    let verdicts: [CollisionVerdict]
    let generations: [FileGenerationCount]
    let iconNames: [String]
    let labelerNote: String

    // MARK: - Derivados

    var hitsByDimension: [Dimension: [Hit]] {
        Dictionary(grouping: hits, by: \.dimension)
    }

    var evasionHits: [Hit] {
        hits.filter { $0.rule.hasPrefix("evasion:") }
    }

    // NOTA de determinismo: `Dictionary` en Swift itera en orden dependiente del hash-seed del
    // proceso (aleatorio entre corridas) y `.sorted` no es estable — dos corridas del MISMO árbol
    // pueden ordenar distinto un empate de conteos si el comparador solo mira el conteo. Cada
    // `.sorted` de abajo rompe el empate por una clave secundaria (nombre/archivo) para que el
    // orden sea una función pura del contenido, no del proceso — la regla de idempotencia del
    // issue (dos corridas = cero diff) depende de esto.

    var evasionByAPI: [(api: String, count: Int, files: Set<String>)] {
        let byRule = Dictionary(grouping: evasionHits, by: \.rule)
        return byRule.map { (api: $0.key, count: $0.value.count, files: Set($0.value.map(\.file))) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.api < $1.api }
    }

    var exemptsByCategory: [(category: String, count: Int)] {
        let counts = exempts.reduce(into: [String: Int]()) { $0[$1.category, default: 0] += 1 }
        return counts.map { (category: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.category < $1.category }
    }

    var exemptsByFile: [(file: String, count: Int)] {
        Dictionary(grouping: exempts, by: \.file).map { (file: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.file < $1.file }
    }

    var faltaPiezaClusters: [(signature: String, count: Int, examples: [ExemptHit], piezaPropuesta: String)] {
        ExemptScanner.faltaPiezaClusters(exempts)
    }

    /// Precision/recall del detector de composición contra `compositionLabels` (etiquetado a
    /// mano, ≥100). Empareja por (file, line) exacto — el detector y el etiquetador comparten
    /// esa clave porque el etiquetado se hizo SOBRE la lista que el detector produjo.
    var compositionPrecisionRecall: (precision: Double, recall: Double, tp: Int, fp: Int, fn: Int, n: Int, wilsonP: (Double, Double), wilsonR: (Double, Double))? {
        guard !compositionLabels.isEmpty else { return nil }
        let detected = Set(compositionCandidates.map { "\($0.file):\($0.line)" })
        let labeledPositive = Set(compositionLabels.filter(\.isComposition).map { "\($0.file):\($0.line)" })
        let labeledKeys = Set(compositionLabels.map { "\($0.file):\($0.line)" })
        let tp = detected.intersection(labeledPositive).count
        let fp = detected.subtracting(labeledPositive).intersection(labeledKeys).count
        let fn = labeledPositive.subtracting(detected).count
        let precisionDenom = tp + fp
        let recallDenom = tp + fn
        let precision = precisionDenom > 0 ? Double(tp) / Double(precisionDenom) : 0
        let recall = recallDenom > 0 ? Double(tp) / Double(recallDenom) : 0
        return (precision, recall, tp, fp, fn, compositionLabels.count,
                Wilson.interval(successes: tp, total: max(precisionDenom, 1)),
                Wilson.interval(successes: tp, total: max(recallDenom, 1)))
    }

    var generationByTarget: [(target: String, liquid: Int, instrumento: Int, indeterminada: Int)] {
        let byTarget = Dictionary(grouping: generations, by: \.target)
        return byTarget.map { target, items in
            (target: target,
             liquid: items.filter { $0.generation == .liquid }.count,
             instrumento: items.filter { $0.generation == .instrumento }.count,
             indeterminada: items.filter { $0.generation == .indeterminada }.count)
        }.sorted { $0.target < $1.target }
    }

    var iconVocabulary: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for n in iconNames { counts[n, default: 0] += 1 }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    // MARK: - Markdown

    func markdown() -> String {
        var md = ""
        md += "# CENSO.md — censo de 8 dimensiones\n\n"
        md += "> Regenerable: `\(invocation)`\n"
        md += ">\n"
        md += "> **Commit**: `\(commitHash)` · **fecha del commit**: \(commitDate) · **archivos .swift escaneados**: \(scannedFiles)\n"
        md += ">\n"
        md += "> Este archivo distingue **[MEDIDO]** (contado por el AST de swift-syntax, reproducible) de **[ETIQUETADO]** (`roles.yaml` y `labels/composicion-etiquetado.json`, mantenidos a mano por un agente — el AST no ve roles). \(labelerNote)\n"
        md += ">\n"
        md += "> **No gatea nada.** Es un reporte de solo lectura (FER-266); aplicar cualquier veredicto es trabajo de `/migracion`.\n\n"

        md += "## Resumen ejecutivo\n\n"
        md += "| Dimensión | Hits [MEDIDO] |\n|---|---|\n"
        for dim in Dimension.allCases {
            md += "| \(dim.rawValue) | \(hitsByDimension[dim]?.count ?? 0) |\n"
        }
        md += "\n"

        md += "## 1. Colador de evasiones [MEDIDO]\n\n"
        md += "APIs que evaden el regex de `Tools/check-design-drift.py` (multi-línea, nombre distinto, `token ± n`) pero que el AST sí ve:\n\n"
        md += "| API / patrón | conteo | archivos distintos |\n|---|---|---|\n"
        for e in evasionByAPI {
            md += "| `\(e.api)` | \(e.count) | \(e.files.count) |\n"
        }
        md += "\n"

        md += "## 2. Censo de `token-exempt` por taxonomía [ETIQUETADO por heurística sobre texto a mano]\n\n"
        md += "Taxonomía: `dato` · `sistema` · `falta-pieza` · `optico` · `paridad` · `unico`. Clasificación automática por palabras clave sobre la razón que el autor original ya escribió a mano — no reinterpreta intención, bucketiza.\n\n"
        md += "| Categoría | conteo |\n|---|---|\n"
        for (cat, count) in exemptsByCategory {
            md += "| \(cat) | \(count) |\n"
        }
        md += "\n**Total exempts vivos en el árbol**: \(exempts.count)\n\n"

        md += "### Top archivos por exempts\n\n"
        md += "| Archivo | exempts |\n|---|---|\n"
        for (file, count) in exemptsByFile.prefix(15) {
            md += "| `\(file)` | \(count) |\n"
        }
        md += "\n"

        md += "### Clusters ×3 de `falta-pieza` (regla anti-excepción del épico §5)\n\n"
        let clusters = faltaPiezaClusters
        if clusters.isEmpty {
            md += "Ninguno por ahora — todo `falta-pieza` está por debajo del umbral de 3.\n\n"
        } else {
            for c in clusters {
                md += "- **\(c.count)×** — pieza propuesta: _\(c.piezaPropuesta)_\n"
                for ex in c.examples {
                    md += "  - `\(ex.file):\(ex.line)` — \(ex.reason)\n"
                }
            }
            md += "\n"
        }

        md += "## 3. Colisiones de rol y veredicto del árbitro [ETIQUETADO + MEDIDO]\n\n"
        md += "Regla: canónico = Liquid Glass · El Eje en su contexto (`roles.yaml`); si Liquid no define el rol, el más frecuente entre pantallas ya migradas; empate → dueño con preview. **Estos veredictos viven aquí; aplicarlos es trabajo de `/migracion`.**\n\n"
        md += "Contexto asignado por heurística de ruta (`Watch` → watch_oled, `Liquid` en el path → mosaico, resto → sobrio) — es una aproximación declarada, no una verdad medida.\n\n"
        if verdicts.isEmpty {
            md += "Sin colisiones detectadas en esta corrida.\n\n"
        } else {
            md += "| Dimensión | Contexto | Valores en disputa | Canónico propuesto | Razonamiento |\n|---|---|---|---|---|\n"
            for v in verdicts {
                let valuesStr = v.values.map { String(format: "%g", $0) }.joined(separator: ", ")
                let canon = v.canonical.map { String(format: "%g", $0) } ?? "—"
                md += "| \(v.dimension) | \(v.context) | \(valuesStr) | \(canon) | \(v.rationale) |\n"
            }
            md += "\n"
        }

        md += "## 4. Detector de composición (fondo+radio+sombra) — solo reporte [MEDIDO + ETIQUETADO]\n\n"
        md += "**Nunca promovido a gate** (anti-alcance del épico). Candidatos detectados: \(compositionCandidates.count).\n\n"
        if let pr = compositionPrecisionRecall {
            md += "- n etiquetado = \(pr.n)\n"
            md += String(format: "- Precision = %.2f (Wilson 95%%: %.2f–%.2f), tp=%d fp=%d\n", pr.precision, pr.wilsonP.0, pr.wilsonP.1, pr.tp, pr.fp)
            md += String(format: "- Recall = %.2f (Wilson 95%%: %.2f–%.2f), fn=%d\n", pr.recall, pr.wilsonR.0, pr.wilsonR.1, pr.fn)
            md += "\n⚠️ **Sesgo de muestreo conocido**: el set etiquetado se tomó de los propios candidatos que el detector produjo (no de un barrido independiente del árbol), así que `fn` solo puede venir de un candidato detectado y luego descartado en el conteo — el recall de esta corrida NO mide qué fracción de composiciones REALES en todo el repo el detector se perdió, sólo qué tan bien re-encuentra su propia lista. Un recall verdadero necesitaría una muestra etiquetada por barrido ciego del árbol, independiente del detector — pendiente, fuera del alcance de esta primera corrida.\n\n"
            md += "\n\(labelerNote)\n\n"
        } else {
            md += "Sin `labels/composicion-etiquetado.json` (o vacío) — precision/recall pendiente. Ver `CONTRIBUTING`/header de invocación para regenerar el etiquetado.\n\n"
        }
        md += "<details><summary>Candidatos (primeros 30)</summary>\n\n"
        for c in compositionCandidates.prefix(30) {
            md += "- `\(c.file):\(c.line)` — `\(c.snippet)`\n"
        }
        md += "\n</details>\n\n"

        md += "## 5. Deuda por generación visual, por target [MEDIDO por símbolo]\n\n"
        md += "Clasificado por qué símbolos importa cada archivo (`Liquid*` vs `Instrumento*`) — no por fecha ni autor. Un archivo sin ninguno de los dos símbolos queda `indeterminada` (probable candidato: no usa CenitDesign en absoluto, o usa solo tipos neutros como `Color`/`Font` del sistema).\n\n"
        md += "| Target | Liquid (vigente) | Instrumento (absorbida, en migración) | Indeterminada |\n|---|---|---|---|\n"
        for g in generationByTarget {
            md += "| \(g.target) | \(g.liquid) | \(g.instrumento) | \(g.indeterminada) |\n"
        }
        md += "\n"

        md += "## 6. Iconografía — vocabulario de SF Symbols literales [MEDIDO]\n\n"
        md += "Usos de `Image(systemName: \"…\")` fuera de un token de icono — cada nombre distinto es un candidato a `CenitIcon` si se repite.\n\n"
        md += "| Símbolo | usos |\n|---|---|\n"
        for i in iconVocabulary.prefix(20) {
            md += "| `\(i.name)` | \(i.count) |\n"
        }
        md += "\n"

        md += "## Acta de la sesión de vocabulario del dueño\n\n"
        md += "_Pendiente — FER-268. Este espacio se llena a mano tras la revisión única del dueño (épico §5, principio 5); el censo no la sustituye._\n"

        return md
    }

    // MARK: - JSON

    struct JSONPayload: Codable {
        let commitHash: String
        let commitDate: String
        let invocation: String
        let scannedFiles: Int
        let hitsByDimension: [String: Int]
        let hits: [Hit]
        let exempts: [ExemptHit]
        let exemptsByCategory: [String: Int]
        let compositionCandidates: [CompositionCandidate]
        let generations: [FileGenerationCount]
        let iconVocabulary: [String: Int]
    }

    func jsonPayload() -> JSONPayload {
        JSONPayload(
            commitHash: commitHash,
            commitDate: commitDate,
            invocation: invocation,
            scannedFiles: scannedFiles,
            hitsByDimension: Dictionary(uniqueKeysWithValues: hitsByDimension.map { ($0.key.rawValue, $0.value.count) }),
            hits: hits.sorted { ($0.file, $0.line) < ($1.file, $1.line) },
            exempts: exempts.sorted { ($0.file, $0.line) < ($1.file, $1.line) },
            exemptsByCategory: Dictionary(uniqueKeysWithValues: exemptsByCategory.map { ($0.category, $0.count) }),
            compositionCandidates: compositionCandidates.sorted { ($0.file, $0.line) < ($1.file, $1.line) },
            generations: generations.sorted { $0.file < $1.file },
            iconVocabulary: Dictionary(uniqueKeysWithValues: iconVocabulary.map { ($0.name, $0.count) })
        )
    }

    func json() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(jsonPayload())
    }
}
