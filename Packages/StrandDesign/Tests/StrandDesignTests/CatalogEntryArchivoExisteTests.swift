import XCTest

// MARK: - FER-267 · el índice no puede apuntar a un archivo muerto
//
// La tabla curada `catalogEntries` vive en `StrandDesignTokens/main.swift` (el patrón
// `Role`/`roles` ya establecido ahí) — no se importa aquí: un ejecutable con top-level code
// en `main.swift` corre ese código al enlazarse con el binario de tests, así que este test
// lee en cambio el `docs/design-system/CATALOGO.md` YA GENERADO (`swift run
// StrandDesignTokens`, vigilado por `design-tokens.yml`) y verifica que cada `archivo` de su
// índice de componentes exista de verdad bajo `Sources/StrandDesign/` — justo lo que mata un
// índice que enseña muertos, la razón de ser de este issue. La honestidad de
// `rol`/`cuándo usarlo`/`cuándo no` la cuida el review humano; esto solo cierra el hueco barato.

final class CatalogEntryArchivoExisteTests: XCTestCase {
    /// `Tests/StrandDesignTests/<esteArchivo>.swift` → sube a la raíz del repo.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // .../Tests/StrandDesignTests
            .deletingLastPathComponent() // .../Tests
            .deletingLastPathComponent() // .../StrandDesign (raíz del paquete)
            .deletingLastPathComponent() // .../Packages
            .deletingLastPathComponent() // raíz del repo
    }

    /// Extrae la columna `archivo` de cada fila del índice de componentes: filas de la forma
    /// `| Rol | \`símbolo\` | \`archivo\` | cuándo usarlo | cuándo no |`.
    private func archivosDelIndice(_ catalogo: String) -> [String] {
        var archivos: [String] = []
        for line in catalogo.split(separator: "\n") {
            let cols = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            // Fila de datos del índice: 7 columnas ("" | Rol | símbolo | archivo | usarlo | no | "")
            // y la 3ª (símbolo) y 4ª (archivo) van entre backticks — el separador visual
            // "|---|---|" no las trae, así que no cuela como falso positivo.
            guard cols.count == 7, cols[2].hasPrefix("`"), cols[3].hasPrefix("`") else { continue }
            let archivo = cols[3].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            archivos.append(archivo)
        }
        return archivos
    }

    func test_cadaArchivoDelIndiceExiste() throws {
        let catalogoURL = repoRoot.appendingPathComponent("docs/design-system/CATALOGO.md")
        let catalogo = try String(contentsOf: catalogoURL, encoding: .utf8)
        let sourcesRoot = repoRoot.appendingPathComponent("Packages/StrandDesign/Sources/StrandDesign")

        let archivos = archivosDelIndice(catalogo)
        XCTAssertFalse(archivos.isEmpty, "no se encontraron filas de índice en \(catalogoURL.path) — ¿cambió el formato de la tabla?")

        let fm = FileManager.default
        for archivo in archivos {
            let path = sourcesRoot.appendingPathComponent(archivo).path
            XCTAssertTrue(fm.fileExists(atPath: path),
                          "el índice de CATALOGO.md apunta a `\(archivo)`, que no existe bajo Sources/StrandDesign/")
        }
    }
}
