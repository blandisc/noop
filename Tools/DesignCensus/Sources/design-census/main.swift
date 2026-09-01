import Foundation
import SwiftSyntax
import SwiftParser

// Censo de 8 dimensiones (FER-266). Ejecutable AISLADO — ver Package.swift para por qué.
//
// Uso:
//   swift run design-census --repo ../.. \
//     --roles roles.yaml --labels labels/composicion-etiquetado.json \
//     --out ../../docs/design-system/CENSO.md

struct Args {
    var repo = "../.."
    var rolesPath = "roles.yaml"
    var labelsPath = "labels/composicion-etiquetado.json"
    var out = "../../docs/design-system/CENSO.md"
    var roots = ["Cenit", "CenitApp", "CenitShared", "CenitWidgets", "CenitWatch"]
}

func parseArgs(_ argv: [String]) -> Args {
    var a = Args()
    var it = argv.makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--repo": a.repo = it.next() ?? a.repo
        case "--roles": a.rolesPath = it.next() ?? a.rolesPath
        case "--labels": a.labelsPath = it.next() ?? a.labelsPath
        case "--out": a.out = it.next() ?? a.out
        case "--roots": a.roots = (it.next() ?? "").split(separator: ",").map(String.init)
        default: break
        }
    }
    return a
}

let args = parseArgs(Array(CommandLine.arguments.dropFirst()))
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let repoRoot = URL(fileURLWithPath: args.repo, relativeToPath: cwd)
let rolesURL = URL(fileURLWithPath: args.rolesPath, relativeToPath: cwd)
let labelsURL = URL(fileURLWithPath: args.labelsPath, relativeToPath: cwd)
let outMdURL = URL(fileURLWithPath: args.out, relativeToPath: cwd)
let outJSONURL = outMdURL.deletingPathExtension().appendingPathExtension("json")

extension URL {
    init(fileURLWithPath path: String, relativeToPath base: URL) {
        if path.hasPrefix("/") {
            self = URL(fileURLWithPath: path)
        } else {
            self = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        }
    }
}

let files = FileWalker.swiftFiles(repoRoot: repoRoot, roots: args.roots)
FileHandle.standardError.write("design-census: escaneando \(files.count) archivos .swift bajo \(args.roots.joined(separator: ", "))\n".data(using: .utf8)!)

var allHits: [Hit] = []
var allExempts: [ExemptHit] = []
var allCompositionCandidates: [CompositionCandidate] = []
var allIconNames: [String] = []
var allGenerations: [FileGenerationCount] = []

for url in files {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
    let relPath = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
    let tree = Parser.parse(source: text)
    let converter = SourceLocationConverter(fileName: relPath, tree: tree)

    let visitor = CensusVisitor(file: relPath, tree: tree, converter: converter, sourceText: text)
    visitor.walk(tree)
    allHits.append(contentsOf: visitor.hits)
    allHits.append(contentsOf: CensusVisitor.scanForegroundStyleLiteral(file: relPath, tree: tree, converter: converter))
    allCompositionCandidates.append(contentsOf: visitor.compositionCandidates)
    allIconNames.append(contentsOf: visitor.iconNames)
    allExempts.append(contentsOf: ExemptScanner.scan(text: text, file: relPath))

    let generation = GenerationCensus.classify(file: relPath, symbolReferences: visitor.symbolReferences)
    allGenerations.append(FileGenerationCount(file: relPath, target: GenerationCensus.target(for: url.path), generation: generation))
}

let roles = RolesFile.parse(rolesURL)
let labels = LabelsFile.load(labelsURL)
let verdicts = Arbiter.verdicts(hits: allHits, roles: roles)

let invocation = "cd Tools/DesignCensus && swift run design-census --repo ../.. --roles roles.yaml --labels labels/composicion-etiquetado.json --out ../../docs/design-system/CENSO.md"

let labelerNote = labels.isEmpty
    ? "`labels/composicion-etiquetado.json` está vacío en esta corrida."
    : "Etiquetado por: \(Set(labels.map(\.labeler)).sorted().joined(separator: ", ")) — declarado distinto del autor del detector (swift-syntax visitor) en el propio archivo de labels."

let report = CensusReport(
    repoRoot: repoRoot.path,
    commitHash: GitInfo.headShortHash(repoRoot: repoRoot),
    commitDate: GitInfo.headCommitDateISO(repoRoot: repoRoot),
    invocation: invocation,
    scannedFiles: files.count,
    hits: allHits,
    exempts: allExempts,
    compositionCandidates: allCompositionCandidates,
    compositionLabels: labels,
    verdicts: verdicts,
    generations: allGenerations,
    iconNames: allIconNames,
    labelerNote: labelerNote
)

do {
    try report.markdown().write(to: outMdURL, atomically: true, encoding: .utf8)
    let jsonData = try report.json()
    try jsonData.write(to: outJSONURL)
    FileHandle.standardError.write("design-census: escrito \(outMdURL.path) y \(outJSONURL.path)\n".data(using: .utf8)!)
} catch {
    FileHandle.standardError.write("design-census: error escribiendo salida — \(error)\n".data(using: .utf8)!)
    exit(1)
}
