import XCTest
import SwiftUI
@testable import StrandDesign

/// Arnés de renders de los 5 estados canónicos del héroe (FER-1045, sesión /inject):
/// escribe un PNG por estado a /tmp/noop-liquid/ para verificación visual del dueño.
/// Run: swift test --filter LiquidHoyEstadosRenderTests
final class LiquidHoyEstadosRenderTests: XCTestCase {

    #if os(macOS)
    @MainActor
    func test_renderCincoEstados() throws {
        for (nombre, model) in Self.estados {
            let view = LiquidHoyScreen(model: model, scrolls: false)
                .environment(\.liquidMotionDisabled, true)
                .frame(width: 402, height: 874)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("ImageRenderer no produjo imagen para \(nombre)")
                continue
            }
            XCTAssertGreaterThan(png.count, 50_000, "\(nombre): PNG sospechosamente vacío")
            let url = URL(fileURLWithPath: "/tmp/noop-liquid/estado_\(nombre).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? png.write(to: url)
            print("WROTE \(url.path)")
        }
    }
    #endif

    /// Los 5 estados con el copy es-MX REAL del builder (paridad de producto).
    static let estados: [(String, LiquidHoyModel)] = {
        let base = LiquidHoyModel.ejemplo

        // 2 · «Bien, con un detalle» (ámbar): sueño fuera de rango, confianza a medias.
        let ambar = LiquidHoyModel(
            kicker: base.kicker,
            dial: base.dial,
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "EN TU RANGO",
                      progress: 0.42, icon: .ondaSenal, state: .ok, valor: "54 lpm"),
                .init(id: "sueno", label: "SUEÑO", caption: "FUERA DE RANGO",
                      progress: 0.82, icon: .lunaSenal, state: .atencion, valor: "5:10"),
            ],
            hero: .veredicto(title: "Bien,\ncon un detalle", highlight: "un detalle",
                             highlightTone: LiquidColor.atencion,
                             subtitle: "Vas bien, con un detalle a vigilar.",
                             confianza: "Confianza: 8 de 14 noches"),
            carga: .medida(pos: 62, zone: 2, status: "ALTA", ratio: "1.32", razon: 1.32, state: .atencion),
            metricas: base.metricas,
            guardian: .init(label: "VIGILANDO", temp: "+0.1°", resp: "14 rpm", estado: .tranquilo),
            heroHint: base.heroHint,
            ambiente: .atencion,
            heroPuerta: "Cómo llegué a esto")

        // 3 · «Ándate leve» (rojo): dos ejes fuera.
        let rojo = LiquidHoyModel(
            kicker: base.kicker,
            dial: base.dial,
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "FUERA DE RANGO",
                      progress: 0.12, icon: .ondaSenal, state: .atencion, valor: "61 lpm"),
                .init(id: "sueno", label: "SUEÑO", caption: "FUERA DE RANGO",
                      progress: 0.15, icon: .lunaSenal, state: .atencion, valor: "4:20"),
            ],
            hero: .veredicto(title: "Ándate\nleve", highlight: "leve",
                             highlightTone: LiquidColor.negativo,
                             subtitle: "Tu cuerpo te pide bajarle hoy.",
                             confianza: nil),
            carga: .medida(pos: 78, zone: 3, status: "MUY ALTA", ratio: "1.61", razon: 1.61, state: .atencion),
            metricas: base.metricas,
            // Estado JUNTAS del guardián: temp y respiración se salieron juntas → la franja se tiñe.
            guardian: .init(label: "JUNTAS", temp: "+0.9°", resp: "20 rpm", estado: .juntas),
            heroHint: base.heroHint,
            ambiente: .alerta,
            heroPuerta: "Cómo llegué a esto")

        // 4 · «Lectura de día» (neutro): sin noche grabada.
        let lectura = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 13),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "EN TU RANGO",
                      progress: 0.45, icon: .ondaSenal, state: .ok, valor: "52 lpm"),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "LECTURA DE DÍA",
                            title: "Tus señales de día están en tu rango.",
                            subtitle: "Sin noche grabada: esta lectura es menos precisa."),
            carga: .medida(pos: 51.5, zone: 1, status: "EN EQUILIBRIO", ratio: "1.03", razon: 1.03, state: .ok),
            metricas: base.metricas,
            // Estado «una fuera»: solo la temperatura se tiñe; el veredicto NO cambia.
            guardian: .init(label: "VIGILANDO", temp: "+0.9°", resp: "14 rpm", estado: .tempFuera),
            heroHint: base.heroHint,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto")

        // 5 · «Aún sin datos suficientes» (neutro): nada vota.
        let sinDatos = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 10),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "SIN DATOS",
                      progress: nil, icon: .ondaSenal, state: .ok),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "PREPARACIÓN",
                            title: "Aún sin datos suficientes",
                            subtitle: "Duerme con tu Apple Watch unas noches y tu veredicto diario aparecerá aquí."),
            carga: .calibrando(status: "CALIBRANDO"),
            metricas: base.metricas,
            // Sin lecturas todavía: el guardián se muestra con «—» (siempre visible).
            guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .tranquilo),
            heroHint: nil,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto")

        return [("1_verde", base), ("2_ambar", ambar), ("3_rojo", rojo),
                ("4_lectura", lectura), ("5_sindatos", sinDatos)]
    }()
}
