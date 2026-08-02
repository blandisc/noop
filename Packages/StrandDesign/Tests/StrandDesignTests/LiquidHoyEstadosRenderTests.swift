import XCTest
import SwiftUI
@testable import StrandDesign

/// Arnés de renders de los estados canónicos del héroe (FER-1045 → FER-10 «El Ecosistema»):
/// escribe un PNG por estado a /tmp/noop-liquid/ para verificación visual del dueño.
/// Con `liquidMotionDisabled` el Ecosistema dibuja su cuadro canónico t = 0 (determinista
/// para ImageRenderer, que no dispara onAppear).
/// Run: swift test --filter LiquidHoyEstadosRenderTests
final class LiquidHoyEstadosRenderTests: XCTestCase {

    #if os(macOS)
    @MainActor
    func test_renderEstados() throws {
        for (nombre, model, fase) in Self.estados {
            let view = ZStack {
                LiquidAmbientBackground.hoy(model.ambiente)
                VStack(spacing: 0) {
                    LiquidHoyContent(model: model, ecosistemaFase: fase)
                        .padding(.top, LiquidSpace.s800)
                    Spacer(minLength: 0)
                }
            }
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

    /// Los 7 estados con el copy es-MX REAL del builder (paridad de producto): los 5
    /// canónicos + el estado SEPARADO (fase forzada) + el ECLIPSE del guardián.
    static let estados: [(String, LiquidHoyModel, EcosistemaSimulacion.Fase?)] = {
        let base = LiquidHoyModel.ejemplo

        // 2 · «Hoy ve leve» (ámbar): sueño fuera de rango; guardián tranquilo con la
        // temperatura apenas movida — «mostrar no es votar» dentro del día ámbar.
        let ambar = LiquidHoyModel(
            kicker: base.kicker,
            dial: base.dial,
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "EN TU RANGO",
                      progress: 0.42, icon: .ondaSenal, state: .ok, valor: "54 lpm",
                      badge: .init(valor: "54", contexto: "lpm · en tu rango")),
                .init(id: "sueno", label: "SUEÑO", caption: "FUERA DE RANGO",
                      progress: 0.82, icon: .lunaSenal, state: .atencion, valor: "5:10",
                      badge: .init(valor: "5:10", contexto: "h · fuera de tu rango")),
            ],
            hero: .veredicto(title: "Hoy ve leve", highlight: "leve",
                             highlightTone: LiquidColor.atencion,
                             subtitle: "Tu sueño amaneció por debajo de tu rango.",
                             confianza: "Confianza: 8 de 14 noches"),
            carga: .medida(pos: 62, zone: 2, status: "ALTA", ratio: "1.32", razon: 1.32, state: .atencion),
            metricas: base.metricas,
            guardian: .init(label: "VIGILANDO", temp: "+0.1°", resp: "14 rpm", estado: .tranquilo),
            heroHint: base.heroHint,
            ambiente: .atencion,
            heroPuerta: "Cómo llegué a esto")

        // 3 · «Recupera» (rojo): la decisora falló — desgaste SIN eclipse (guardián quieto).
        let rojo = LiquidHoyModel(
            kicker: base.kicker,
            dial: base.dial,
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "FUERA DE RANGO",
                      progress: 0.32, icon: .ondaSenal, state: .atencion, valor: "61 lpm",
                      badge: .init(valor: "61", contexto: "lpm · fuera de tu rango")),
                .init(id: "sueno", label: "SUEÑO", caption: "EN TU RANGO",
                      progress: 0.76, icon: .lunaSenal, state: .ok, valor: "7:05",
                      badge: .init(valor: "7:05", contexto: "h · en tu rango")),
            ],
            hero: .veredicto(title: "Recupera", highlight: "Recupera",
                             highlightTone: LiquidColor.negativo,
                             subtitle: "Tu pulso en reposo pasó la noche alto.",
                             confianza: nil),
            carga: .medida(pos: 78, zone: 3, status: "MUY ALTA", ratio: "1.61", razon: 1.61, state: .atencion),
            metricas: base.metricas,
            guardian: .init(label: "VIGILANDO", temp: "+0.1°", resp: "14 rpm", estado: .tranquilo),
            heroHint: base.heroHint,
            ambiente: .alerta,
            heroPuerta: "Cómo llegué a esto")

        // 4 · «Lectura de día» (neutro): sin noche grabada → la luna de sueño no se fabrica.
        let lectura = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 13),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "EN TU RANGO",
                      progress: 0.45, icon: .ondaSenal, state: .ok, valor: "52 lpm",
                      badge: .init(valor: "52", contexto: "lpm · en tu rango")),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "LECTURA DE DÍA",
                            title: "Tus señales de día están en tu rango.",
                            subtitle: "Sin noche grabada: esta lectura es menos precisa."),
            carga: .medida(pos: 51.5, zone: 1, status: "EN EQUILIBRIO", ratio: "1.03", razon: 1.03, state: .ok),
            metricas: base.metricas,
            // «Una fuera»: solo la temperatura se tiñe; el héroe NO cambia.
            guardian: .init(label: "VIGILANDO", temp: "+0.9°", resp: "14 rpm", estado: .tempFuera),
            heroHint: base.heroHint,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto")

        // 5 · «Conociéndote» (neutro): la acreción — sin base todavía.
        let calibrando = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 10),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "SIN DATOS",
                      progress: nil, icon: .ondaSenal, state: .ok),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "PREPARACIÓN",
                            title: "Conociéndote",
                            subtitle: "Noche 4 de 7 · tu rango se está formando"),
            carga: .calibrando(status: "CALIBRANDO"),
            metricas: base.metricas,
            guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .tranquilo),
            heroHint: nil,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto",
            calibracion: .init(noche: 4, total: 7))

        // 7 · El ECLIPSE: ámbar con el guardián en pareja — la única causa que lo saca de
        // su órbita.
        let eclipse = LiquidHoyModel(
            kicker: base.kicker,
            dial: base.dial,
            senales: base.senales,
            hero: .veredicto(title: "Hoy ve leve", highlight: "leve",
                             highlightTone: LiquidColor.atencion,
                             subtitle: "Algo se salió de tu patrón: temperatura y respiración se movieron juntas.",
                             confianza: nil),
            carga: .medida(pos: 51.5, zone: 1, status: "EN EQUILIBRIO", ratio: "1.03", razon: 1.03, state: .ok),
            metricas: base.metricas,
            guardian: .init(label: "JUNTAS", temp: "+0.6°", resp: "19 rpm", estado: .juntas),
            heroHint: base.heroHint,
            ambiente: .atencion,
            heroPuerta: "Cómo llegué a esto")

        return [("1_verde", base, nil),
                ("2_ambar", ambar, nil),
                ("3_rojo", rojo, nil),
                ("4_lectura", lectura, nil),
                ("5_calibrando", calibrando, nil),
                ("6_separado", base, .separada),
                ("7_eclipse", eclipse, nil)]
    }()
}
