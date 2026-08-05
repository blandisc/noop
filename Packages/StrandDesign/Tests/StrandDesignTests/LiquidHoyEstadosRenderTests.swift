import XCTest
import SwiftUI
@testable import StrandDesign

/// Arnés de renders de los estados de «Hoy»: escribe un PNG por estado a /tmp/noop-liquid/
/// para verificación visual del dueño. Con `liquidMotionDisabled` el Ecosistema dibuja su
/// cuadro canónico t = 0 (determinista para ImageRenderer, que no dispara onAppear).
/// Run: swift test --filter LiquidHoyEstadosRenderTests
///
/// ESTE ARCHIVO ES EL MAPA DE ESTADOS. Vive aquí, y no en un documento aparte, porque lo que
/// enumera es exactamente lo que renderiza: un mapa en markdown se desfasa en silencio, éste
/// no compila si un estado deja de existir. Cada uno con la condición EXACTA que lo dispara:
///
///   0 · orbe dormido      `noSources`: sin datos de Salud Y sin permiso. No pasa por el héroe.
///   12 · entrada          `LiquidOrbeEntrada`, el overlay de arranque. Tampoco pasa por el héroe.
///   8 · leyendo tu noche  `prep == nil && verdictPending` (primer pintado, aún cargando).
///   13 · recién conectado con permiso, `nights == 0` → «Noche 0 de 4».
///   5 · conociéndote      con permiso, `0 < nights < Baselines.minNightsSeed` (4).
///   11 · provisional      veredicto real con `nights < minNightsTrust` (14) → línea de confianza.
///   1 · en rango          `verdict == .full`, anclado a una noche.
///   2 · hoy ve leve       `verdict == .caution` (un eje fuera, o el par del guardián).
///   3 · recupera          `verdict == .easy` (≥ 2 ejes fuera, o ámbar + tendencia a la baja).
///   7 · eclipse           subcaso de 2/3: `sentinel == .corroborated` (temp Y resp juntas).
///   6 · separado          cualquiera de los anteriores con la fase del Ecosistema en `.separada`.
///   4 · lectura de día    veredicto SIN noche grabada (`isNightAnchored == false`).
///   10 · sin lectura hoy  sin veredicto, con permiso, `nights >= 4` (la base ya está sembrada).
///   9 · sin permiso       `healthConnected == false` Y `noSources == false` (datos sin la marca
///                         de conectado; p. ej. tras restaurar un respaldo).
///
/// FALTA UNO, a propósito, y está levantado como deuda en FER-47: «lectura de día CON el
/// guardián en pareja». El motor sí baja el veredicto, pero `lecturaDeDia()` ignora el
/// centinela y afirma «tus señales de día están en tu rango» mientras el guardián dice JUNTAS.
/// No se renderiza aquí porque renderizarlo sería bendecir una pantalla que se contradice.
final class LiquidHoyEstadosRenderTests: XCTestCase {

    #if os(macOS)
    @MainActor
    func test_renderEstados() throws {
        for (nombre, model, fase) in Self.estados {
            let view = ZStack {
                LiquidAmbientBackground.tablero(model.ambiente)
                VStack(spacing: 0) {
                    LiquidHoyContent(model: model, ecosistemaFase: fase)
                        .padding(.top, LiquidSpace.s550)
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

    /// Los dos estados de Hoy que NO pasan por `LiquidHoyModel` porque no son el héroe con
    /// datos: el estado sin ni una fuente (el orbe DORMIDO) y el cuadro final de la entrada
    /// (FER-41).
    ///
    /// La entrada se renderiza con el movimiento desactivado, que es el camino de «Reducir
    /// movimiento»: ahí el clima se lee en vivo, así que el PNG SÍ sale teñido de su veredicto
    /// (antes salía gris porque `ImageRenderer` no ejecuta `.task`, donde el camino normal lo
    /// fija).
    #if os(macOS)
    @MainActor
    func test_renderEstadoVacioYEntrada() throws {
        let piezas: [(String, AnyView)] = [
            ("0_orbe_dormido", AnyView(
                ZStack {
                    LiquidColor.fondoGradient.ignoresSafeArea()
                    VStack(spacing: 0) {
                        LiquidOrbeDormidoEstado(
                            titulo: "El orbe aún duerme",
                            cuerpo: "Conecta Apple Salud y empezará a latir con tus noches.",
                            cta: "Conectar Apple Salud",
                            privacidad: "Todo se queda en tu iPhone. Sin cuenta, sin nube.",
                            onConectar: {})
                        .padding(.top, LiquidSpace.s1400)
                        .padding(.horizontal, LiquidSpace.s550)
                        Spacer(minLength: 0)
                    }
                })),
            ("12_entrada_asentada", AnyView(
                LiquidOrbeEntrada(clima: { .bien }, onFin: {}))),
        ]
        for (nombre, vista) in piezas {
            let view = vista
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
            let url = URL(fileURLWithPath: "/tmp/noop-liquid/estado_\(nombre).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? png.write(to: url)
            print("WROTE \(url.path)")
        }
    }
    #endif

    /// Los 11 estados del héroe con el copy es-MX REAL del builder (paridad de producto):
    /// los 3 veredictos, lectura de día, calibrando, separado, eclipse, leyendo, sin permiso,
    /// sin lectura de hoy y el veredicto provisional con su línea de confianza.
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
            modulos: LiquidHoyModel.atencionModulos,
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
                             // El eje autonómico es una z ORIENTADA: `autonomicAxis` solo produce `.low`,
                             // así que el builder jamás dice «alto» de esta señal.
                             subtitle: "Tu señal autonómica quedó abajo de tu rango.",
                             confianza: nil),
            carga: .medida(pos: 78, zone: 3, status: "MUY ALTA", ratio: "1.61", razon: 1.61, state: .atencion),
            metricas: base.metricas,
            modulos: LiquidHoyModel.ejemploModulos,
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
            metricas: metricasSinHoy(base.metricas),
            modulos: modulosSinHoy(LiquidHoyModel.ejemploModulos),
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
                            subtitle: "Noche 3 de 4 · tu rango se está formando"),
            carga: .calibrando(status: "CALIBRANDO"),
            metricas: metricasSinHoy(base.metricas),
            modulos: modulosSinHoy(LiquidHoyModel.calibrandoModulos),
            guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .sinLectura),
            heroHint: nil,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto",
            calibracion: .init(noche: 3, total: 4))

        // 7 · El ECLIPSE: ámbar con el guardián en pareja — la única causa que lo saca de
        // su órbita.
        let eclipse = LiquidHoyModel(
            kicker: base.kicker,
            dial: base.dial,
            senales: base.senales,
            hero: .veredicto(title: "Hoy ve leve", highlight: "leve",
                             highlightTone: LiquidColor.atencion,
                             subtitle: "Tu temperatura y tu respiración se salieron juntas de tu patrón.",
                             confianza: nil),
            carga: .medida(pos: 51.5, zone: 1, status: "EN EQUILIBRIO", ratio: "1.03", razon: 1.03, state: .ok),
            metricas: base.metricas,
            modulos: LiquidHoyModel.ejemploModulos,
            guardian: .init(label: "JUNTAS", temp: "+0.6°", resp: "19 rpm", estado: .juntas),
            heroHint: base.heroHint,
            ambiente: .atencion,
            heroPuerta: "Cómo llegué a esto")



        /// Las métricas tal como quedan cuando HOY no tiene fila. No es una licencia del
        /// arnés: `TodayView` resuelve el sueño con `todayOnly` —así que cae a «—»— y el
        /// ritmo en reposo, la temperatura y la respiración con `latestFromDisplay`, que
        /// acepta hasta 13 días atrás. La asimetría que se ve aquí es la de producción.
        func metricasSinHoy(_ base: [LiquidHoyModel.Metrica]) -> [LiquidHoyModel.Metrica] {
            base.map { m in
                guard m.id == "sleep" else { return m }
                return .init(id: m.id, label: m.label, value: "—", unit: "",
                             delta: "", tone: m.tone, icon: m.icon)
            }
        }

        /// El TABLERO cuando hoy no tiene fila. Va aparte de `metricasSinHoy` porque el arnés
        /// hardcodea el tablero en vez de derivarlo de las métricas como hace el builder —
        /// así que aquí hay que repetir a mano lo que allá es automático. (Ese desacople es,
        /// en sí, la razón por la que el arnés puede desfasarse de producción sin avisar.)
        func modulosSinHoy(_ base: [LiquidHoyModel.Modulo]) -> [LiquidHoyModel.Modulo] {
            base.map { mod in
                guard mod.id == "veredicto" else { return mod }
                return .init(id: mod.id, kicker: mod.kicker, auroraTones: mod.auroraTones,
                             auroraPeriod: mod.auroraPeriod, auroraReverse: mod.auroraReverse,
                             columnas: mod.columnas.map { col in
                    guard col.id == "sleep" else { return col }
                    return .init(id: col.id, label: col.label, tone: LiquidColor.tinta500,
                                 alineacion: col.alineacion,
                                 contenido: .simple(value: "—", unit: "", detail: "", mejora: false),
                                 destino: col.destino,
                                 a11yLabel: "Sueño, sin dato de hoy")
                })
            }
        }

        // 8 · «Leyendo tu noche…»: el primer pintado, antes de que el refresh complete el
        // veredicto. Decirle «no conozco tu base» a alguien con años de historia sería falso.
        let leyendo = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 8),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "SIN DATOS",
                      progress: nil, icon: .ondaSenal, state: .ok),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "PREPARACIÓN", title: "Leyendo tu noche…",
                            subtitle: "Un momento."),
            carga: .calibrando(status: "CALIBRANDO"),
            metricas: metricasSinHoy(base.metricas),
            modulos: modulosSinHoy(LiquidHoyModel.calibrandoModulos),
            guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .sinLectura),
            heroHint: nil,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto")

        // 9 · SIN PERMISO de Salud: la única puerta real es conceder el permiso, así que el
        // héroe cambia de promesa. No lleva contador: sin permiso no se sabe qué falta.
        let sinPermiso = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 11),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "SIN DATOS",
                      progress: nil, icon: .ondaSenal, state: .ok),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "PREPARACIÓN", title: "Aún no conozco tu base",
                            subtitle: "Conecta Apple Salud en Ajustes y tu veredicto diario aparecerá aquí."),
            carga: .calibrando(status: "CALIBRANDO"),
            metricas: metricasSinHoy(base.metricas),
            modulos: modulosSinHoy(LiquidHoyModel.calibrandoModulos),
            guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .sinLectura),
            heroHint: nil,
            ambiente: .neutro,
            // Sin permiso la ruta del héroe es `.salud`, y el builder le pone ESA puerta:
            // la única salida real es conceder el permiso, no explicar un veredicto que no hay.
            heroPuerta: "Conectar Salud")

        // 10 · «Sin lectura de hoy»: la base YA está formada; lo que falta es la lectura de
        // hoy. Sin contador a propósito — decir «se está formando» con los puntos llenos
        // sería falso (gate /cso B2).
        let sinLectura = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 9),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "SIN DATOS",
                      progress: nil, icon: .ondaSenal, state: .ok),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "PREPARACIÓN", title: "Sin lectura de hoy",
                            subtitle: "Tu rango ya está formado; la lectura de hoy aún no llega."),
            carga: base.carga,
            metricas: metricasSinHoy(base.metricas),
            modulos: modulosSinHoy(LiquidHoyModel.ejemploModulos),
            guardian: .init(label: "VIGILANDO", temp: "+0.1°", resp: "14 rpm", estado: .tranquilo),
            heroHint: nil,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto")

        // 11 · PROVISIONAL: veredicto de verdad, pero sobre una base todavía joven. La línea
        // de confianza es el tether honesto y solo existe mientras la base no está firme.
        let provisional = LiquidHoyModel(
            kicker: base.kicker,
            dial: base.dial,
            senales: base.senales,
            hero: .veredicto(title: "En rango", highlight: "rango",
                             highlightTone: LiquidColor.verdePrimario,
                             subtitle: "Tus dos señales amanecieron en tu rango.",
                             confianza: "Confianza: 6 de 14 noches"),
            carga: base.carga,
            metricas: base.metricas,
            modulos: LiquidHoyModel.ejemploModulos,
            guardian: base.guardian,
            heroHint: base.heroHint,
            ambiente: .bien,
            heroPuerta: "Cómo llegué a esto")


        // 13 · RECIÉN CONECTADO: hay permiso pero todavía cero noches en el banco. Es la
        // pantalla del instante siguiente a conceder Salud, y la única que enseña el contador
        // en cero. `calibracionConteo` lo clampa a (0, minNightsSeed), así que «Noche 0 de 4»
        // es literalmente lo que dice la app.
        let recienConectado = LiquidHoyModel(
            kicker: base.kicker,
            dial: .init(night: nil, sol: (start: 6.8, end: 20.3), marker: 10),
            senales: [
                .init(id: "autonomico", label: "EN REPOSO", caption: "SIN DATOS",
                      progress: nil, icon: .ondaSenal, state: .ok),
                .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                      progress: nil, icon: .lunaSenal, state: .ok),
            ],
            hero: .demotado(kicker: "PREPARACIÓN", title: "Conociéndote",
                            subtitle: "Noche 0 de 4 · tu rango se está formando"),
            carga: .calibrando(status: "CALIBRANDO"),
            metricas: metricasSinHoy(base.metricas),
            modulos: modulosSinHoy(LiquidHoyModel.calibrandoModulos),
            guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .sinLectura),
            heroHint: nil,
            ambiente: .neutro,
            heroPuerta: "Cómo llegué a esto",
            calibracion: .init(noche: 0, total: 4))

        return [("1_verde", base, nil),
                ("2_ambar", ambar, nil),
                ("3_rojo", rojo, nil),
                ("4_lectura", lectura, nil),
                ("5_calibrando", calibrando, nil),
                ("6_separado", base, .separada),
                ("7_eclipse", eclipse, nil),
                ("8_leyendo", leyendo, nil),
                ("9_sin_permiso", sinPermiso, nil),
                ("10_sin_lectura", sinLectura, nil),
                ("11_provisional", provisional, nil),
                ("13_recien_conectado", recienConectado, nil)]
    }()
}
