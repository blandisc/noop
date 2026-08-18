#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-51 — arnés PNG de la cara de Hoy (T1 bueno / T2 calibrando / T3 alerta), desde FER-118
/// en su envase de vidrio sobre la atmósfera. No es aserción de CI: escribe PNGs en /tmp/noop-fer51/.
/// Run: `swift test --filter MatrizHoyFaceSnapshotTests`
final class MatrizHoyFaceSnapshotTests: XCTestCase {

    @MainActor func test_t1_bueno() throws {
        try render(MatrizHoyFace(model: Self.t1Bueno, onTapSeccion: { _ in }),
                   to: "matriz_hoy_t1_bueno", size: CGSize(width: 390, height: 1040))
    }

    @MainActor func test_t2_calibrando() throws {
        try render(MatrizHoyFace(model: Self.t2Calibrando, onTapSeccion: { _ in }),
                   to: "matriz_hoy_t2_calibrando", size: CGSize(width: 390, height: 1040))
    }

    @MainActor func test_t3_alerta() throws {
        try render(MatrizHoyFace(model: Self.t3Alerta, onTapSeccion: { _ in }),
                   to: "matriz_hoy_t3_alerta", size: CGSize(width: 390, height: 1040))
    }

    @MainActor func test_orden_a11y_visual_bandas_divididas() {
        let ids = Self.t1Bueno.ordenA11y
        // sueño + FC + VFC + guardián + carga + esfuerzo + estrés + pasos — el héroe de
        // la pantalla es el ecosistema de arriba; la Matriz ya no lo repite (2026-08-06).
        XCTAssertEqual(ids, [
            "sleep", "rhr", "guardian", "carga", "strain", "hrv", "stress", "steps",
        ])
        // Bandas divididas aportan 2 elementos cada una (3 splits × 2 + 2 full = 8).
        XCTAssertEqual(ids.count, 8)
    }

    // MARK: - Fixtures (datasets tipados — evita el type-checker de CI)

    private static var t1Bueno: MatrizHoyModel {
        let noches: [MatrizColumnas.Noche] = (0..<14).map { i in
            MatrizColumnas.Noche(valor: 6.5 + Double(i % 4) * 0.3, alerta: .ninguna)
        }
        let fc: [Double?] = (0..<20).map { i in 56 + Double(i % 5) }
        let vfc: [Double?] = (0..<20).map { i in 40 + Double(i % 7) }
        let estela: [Double] = [0.9, 1.0, 1.05, 0.95, 1.1]
        let strain: [Double?] = (0..<14).map { Double(10 + $0) }
        let steps: [Double?] = (0..<14).map { Double(6000 + $0 * 200) }
        let stress: [Int?] = [0, 1, 0, 1, 1, 0, 1]
        let temp: [Double?] = (0..<20).map { _ in 0.1 as Double? }
        let resp: [Double?] = (0..<20).map { _ in 14.0 as Double? }

        return MatrizHoyModel(
            bandas: [
                // Opción A (producción): niveles + gemelas Sueño|FC, luna en Sueño, sin «votes».
                .nivel("Decide your day", manualID: "manual.deciden"),
                .split(
                    izq: MatrizSeccion(
                        id: "sleep", hue: LiquidColor.indigo,
                        titulo: "Sleep", valor: "7:12", destacada: true,
                        sublabel: "last night · in your range",
                        chartID: "matriz-sleep",
                        chart: .columnas(noches: noches, referencia: 7, referenciaTag: "7 h",
                                         dominio: 4...10),
                        formaSello: .luna),
                    der: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "52",
                        unidad: "bpm", destacada: true,
                        sublabel: "last night · in your range",
                        chartID: "matriz-rhr",
                        chart: .regla(puntos: fc, banda: 53...59, dominio: 45...75,
                                         alertaHoy: .ninguna),
                        formaSello: .corazon)),
                .nivel("Watches over you", manualID: "guardian"),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                        dominio: -1...1, alertaHoy: .ninguna),
                    chip: .init(texto: "At ease", tono: .calma),
                    renglones: [
                        MatrizRenglon(id: "skintemp", titulo: "Skin temp",
                                      valor: "+0.1°", hue: LiquidColor.doradoTemp,
                                      chartID: "matriz-guardian-temp",
                                      chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                                          dominio: -1...1, alertaHoy: .ninguna)),
                        MatrizRenglon(id: "resp", titulo: "Breathing",
                                      valor: "14.0", hue: LiquidColor.azul,
                                      chartID: "matriz-guardian-resp",
                                      chart: .lineaSerena(puntos: resp, banda: 12...16,
                                                          dominio: 8...22, alertaHoy: .ninguna)),
                    ])),
                .nivel("Context", manualID: "manual.contexto"),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "1.12",
                        sublabel: "Steady",
                        chartID: "matriz-carga",
                        chart: .colina(p: 1.12, zona: 0.8...1.3, estela: estela)),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "12.4",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: strain))),
                .split(
                    izq: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "68",
                        unidad: "ms",
                        sublabel: "reference · does not vote · why?",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(puntos: vfc, base: 45, dominio: 20...80,
                                             alfa: 0.6, alertaHoy: .ninguna)),
                    der: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta900,
                        titulo: "Stress", valor: "Low",
                        sublabel: "vs your 7 days",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: stress))),
                // FER-118: Pasos cierra Contexto, ancho; el estante «Logbook» murió.
                .full(MatrizSeccion(
                    id: "steps", hue: LiquidColor.tinta700,
                    titulo: "Steps", valor: "8 432",
                    chartID: "matriz-steps",
                    chart: .barrasMini(valores: steps))),
            ])
    }

    private static var t2Calibrando: MatrizHoyModel {
        let vacioNoches = [MatrizColumnas.Noche](repeating: .init(valor: nil), count: 14)
        let vacio20 = [Double?](repeating: nil, count: 20)
        let vacio14 = [Double?](repeating: nil, count: 14)
        let vacio7 = [Int?](repeating: nil, count: 7)
        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "—",
                    sublabel: "Getting to know you",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: vacioNoches, referencia: 7, referenciaTag: "7 h",
                                     dominio: 4...10))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "—",
                        chartID: "matriz-rhr",
                        chart: .regla(puntos: vacio20, banda: nil, dominio: 45...75,
                                      alertaHoy: .ninguna)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "—",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(puntos: vacio20, base: nil, dominio: 20...80,
                                             alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "—",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: vacio20, banda: nil, dominio: -1...1,
                                        alertaHoy: .ninguna))),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "—",
                        sublabel: "Calibrating",
                        chartID: "matriz-carga",
                        chart: .colina(p: nil, zona: 0.8...1.3, estela: [])),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "—",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: vacio14))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta900,
                        titulo: "Stress", valor: "—",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: vacio7)),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "—",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: vacio14))),
            ])
    }

    private static var t3Alerta: MatrizHoyModel {
        let noches: [MatrizColumnas.Noche] = (0..<14).map { i in
            let alerta: MedidorLunar.Alerta = (i == 13 || i == 5) ? .atencion : .ninguna
            return MatrizColumnas.Noche(valor: i == 13 ? 5.0 : 7.0, alerta: alerta)
        }
        let fc: [Double?] = (0..<20).map { i in i == 19 ? 72.0 : 58.0 }
        let temp: [Double?] = (0..<20).map { i in i >= 17 ? 0.9 : 0.1 }
        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "5:00",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: noches, referencia: 7, referenciaTag: "7 h",
                                     dominio: 4...10))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "72",
                        chartID: "matriz-rhr",
                        chart: .regla(puntos: fc, banda: 53...59, dominio: 45...80,
                                      alertaHoy: .atencion)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "38 ms",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(puntos: (0..<20).map { _ in 38.0 as Double? },
                                             base: 45, dominio: 20...80,
                                             alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                        dominio: -1...1, alertaHoy: .alarma),
                    chip: .init(texto: "Temperature and breathing off · 3rd night",
                                tono: .alarma))),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "1.48",
                        sublabel: "Building",
                        chartID: "matriz-carga",
                        chart: .colina(p: 1.48, zona: 0.8...1.3,
                                         estela: [1.0, 1.1, 1.2, 1.3, 1.4])),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "14.0",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: (0..<14).map { Double(10 + $0) }))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta900,
                        titulo: "Stress", valor: "High",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: [0, 1, 1, 2, 2, 1, 2])),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "3 200",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: (0..<14).map { Double(3000 + $0 * 50) }))),
            ])
    }

    /// FER-118: la cara se rinde SOBRE la atmósfera real (blanco + polvo estático del Canvas) —
    /// el vidrio al 30 % tiene que dejar ver las motas y el canto de tinta tiene que recortar
    /// cada módulo. Motion apagado ⇒ vidrio de imitación (rasterizable) y polvo determinista.
    @MainActor private func render<V: View>(_ content: V, to name: String,
                                            size: CGSize) throws {
        let view = ZStack(alignment: .top) {
            LiquidAtmosfera(ambiente: .bien, estado: AtmosferaEstado())
            content
        }
            .frame(width: size.width, height: size.height)
            .environment(\.liquidMotionDisabled, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no se pudo renderizar \(name)")
        }
        let dir = URL(fileURLWithPath: "/tmp/noop-fer51", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
