import SwiftUI

// MARK: - FER-56 · El sello del guardián VIVO (Ola 3)
//
// El guardián cuida DOS señales (temperatura de piel + respiración) y su regla es una
// PAREJA: una sola fuera nunca empuja tu día; solo las dos, dos noches seguidas. El sello
// dice esa regla SIN TEXTO, con geometría y color:
//
//   • calma            → un orbe único bicolor (dorado+azul INTERCALADOS), respirando.
//   • vigila una       → esa mitad se DESPRENDE un poco, en su color de identidad (frío):
//                        «te noté una», pero el día no se mueve — sin cálidos (espeja el
//                        chip `.terciario`, que a propósito no alarma por una sola).
//   • ambas 1.ª noche  → las dos mitades se SEPARAN y viran a ÁMBAR (espeja `.atencion`).
//   • ambas · racha    → se separan más, ROJO + un latido (espeja `.alarma`).
//   • sin datos        → quieto, neutro (nunca un falso «en calma» verde).
//
// La materia es la MISMA del orbe del héroe (`EcosistemaSimulacion`: esfera de Fibonacci
// proyectada). El truco de la separación honesta: DOS capas Canvas sobre la MISMA esfera
// —una dibuja solo los índices pares (temp), otra los impares (resp)—; superpuestas a
// offset 0 recomponen EXACTO el orbe intercalado de hoy, y al deslizarse con `.offset` a
// nivel de vista la separación se ANIMA sola (interpolable) y respeta Reduce Motion.

public struct SelloGuardianVivo: View {
    /// El estado del sello, proyectado 1:1 del chip del guardián (nunca lo contradice).
    public enum Estado: Sendable, Equatable {
        case calma          // nada fuera — bicolor, junto
        case vigilaTemp     // solo temp fuera — la mitad dorada se desprende, fría
        case vigilaResp     // solo resp fuera — la mitad azul se desprende, fría
        case ambasAmbar     // par fuera, 1.ª noche — separadas, ámbar
        case ambasRoja      // par fuera, racha ≥ 2 — separadas más, rojo + latido
        case sinDatos       // sin lectura del par — quieto, neutro
    }

    private let radio: CGFloat
    private let hueTemp: Color
    private let hueResp: Color
    private let estado: Estado
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // FER-audit: misma disciplina de pausa del héroe (background + previews «sin motion»).
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    private var quieto: Bool {
        // FER-73 · M11: «sin datos → quieto» estaba documentado pero no implementado: el reloj,
        // el giro y la respiración seguían corriendo y solo cambiaba el color.
        reduceMotion || ambientPaused || motionDisabled || estado == .sinDatos
    }

    public init(radio: CGFloat, hueTemp: Color, hueResp: Color, estado: Estado) {
        self.radio = radio
        self.hueTemp = hueTemp
        self.hueResp = hueResp
        self.estado = estado
    }

    // Separación por mitad, en fracción del radio (0 = fundidas, ~1 = separadas del todo).
    private var sepTemp: CGFloat {
        switch estado {
        case .vigilaTemp: return 0.42
        case .ambasAmbar: return 0.58
        case .ambasRoja:  return 0.82
        case .calma, .vigilaResp, .sinDatos: return 0
        }
    }
    private var sepResp: CGFloat {
        switch estado {
        case .vigilaResp: return 0.42
        case .ambasAmbar: return 0.58
        case .ambasRoja:  return 0.82
        case .calma, .vigilaTemp, .sinDatos: return 0
        }
    }
    // Color por mitad: identidad en calma/vigila-una (frío, sin alarma), cálido solo cuando
    // el PAR se sale (ámbar 1.ª noche → rojo en racha). Sin datos: neutro.
    private var colorTemp: Color {
        switch estado {
        case .ambasAmbar: return LiquidColor.particulaAmbar
        case .ambasRoja:  return LiquidColor.particulaRoja
        case .sinDatos:   return LiquidColor.particulaNeutra
        case .calma, .vigilaTemp, .vigilaResp: return hueTemp
        }
    }
    private var colorResp: Color {
        switch estado {
        case .ambasAmbar: return LiquidColor.particulaAmbar
        case .ambasRoja:  return LiquidColor.particulaRoja
        case .sinDatos:   return LiquidColor.particulaNeutra
        case .calma, .vigilaTemp, .vigilaResp: return hueResp
        }
    }
    private var late: Bool { estado == .ambasRoja }

    public var body: some View {
        let lado = radio * 2.5
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloSello, paused: quieto)) { tl in
            let t = quieto ? 0 : tl.date.timeIntervalSinceReferenceDate
            // Respira SIEMPRE (vivo, no quieto): un latido muy sutil en calma, más hondo en
            // racha (el par lleva dos noches fuera). Reduce Motion lo apaga (t = 0 ⇒ escala 1).
            let escala = 1 + (late ? 0.05 : 0.022) * CGFloat(sin(t * (late ? 2.4 : 1.15)))
            ZStack {
                capa(paridad: 0, hue: colorTemp, t: t)
                    .offset(x: -sepTemp * radio)
                capa(paridad: 1, hue: colorResp, t: t)
                    .offset(x: sepResp * radio)
            }
            .frame(width: lado, height: lado)
            .scaleEffect(escala)
        }
        .frame(width: lado, height: lado)
        // La separación (offset a nivel de vista) se ANIMA sola al cambiar de estado; en
        // Reduce Motion salta asentada, sin viaje.
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: estado)
        .accessibilityHidden(true)
    }

    private func capa(paridad: Int, hue: Color, t: Double) -> some View {
        Canvas { ctx, size in
            Self.dibujarParidad(ctx, centro: CGPoint(x: size.width / 2, y: size.height / 2),
                                radio: radio, hue: hue, paridad: paridad, t: t)
        }
    }

    // MARK: Trazo — media esfera por paridad (mismos índices/rotación que la otra capa, para
    // que a offset 0 recompongan el orbe intercalado). Geometría cacheada (perf de N relojes).
    private static let cacheCandado = NSLock()
    nonisolated(unsafe) private static var dirsCache: [Int: [SIMD3<Double>]] = [:]
    private static func direcciones(_ n: Int) -> [SIMD3<Double>] {
        cacheCandado.lock(); defer { cacheCandado.unlock() }
        if let d = dirsCache[n] { return d }
        let d = EcosistemaSimulacion.fibonacci(n)
        dirsCache[n] = d
        return d
    }

    static func dibujarParidad(_ ctx: GraphicsContext, centro: CGPoint, radio: CGFloat,
                               hue: Color, paridad: Int, t: Double) {
        // MISMA densidad y rotación que `OrbeVivo` (esfera): a offset 0 las dos paridades
        // recomponen el mismo orbe bicolor de hoy, mota por mota.
        let cuenta = min(240, max(36, Int(0.4 * radio * radio)))
        let fase = Double(MatrizDither.semilla(chartID: "sello-guardian", index: 0) % 628) / 100.0
        let rot = fase + t * 0.32   // vivo: giro perceptible (antes 0.12 ≈ 1 vuelta/52 s)
        for (i, dir) in direcciones(cuenta).enumerated() where i % 2 == paridad {
            let p = EcosistemaSimulacion.particula(
                dir: dir, indice: i, centro: centro, radio: radio,
                rotacion: rot, jitterAmp: radio <= 10 ? 0 : 0.7, t: t, alfaK: 1.4)
            let pr = p.tamano * (0.55 + radio / 60)
            ctx.fill(Path(ellipseIn: CGRect(x: p.pos.x - pr, y: p.pos.y - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(hue.opacity(min(1, p.alfa))))
        }
    }
}

#Preview("Sello guardián · estados") {
    HStack(spacing: 20) {
        ForEach(["calma", "vigilaT", "vigilaR", "ambar", "rojo", "sin"], id: \.self) { k in
            VStack(spacing: 10) {
                SelloGuardianVivo(
                    radio: 16, hueTemp: LiquidColor.doradoTemp, hueResp: LiquidColor.azul,
                    estado: {
                        switch k {
                        case "calma": return .calma
                        case "vigilaT": return .vigilaTemp
                        case "vigilaR": return .vigilaResp
                        case "ambar": return .ambasAmbar
                        case "rojo": return .ambasRoja
                        default: return .sinDatos
                        }
                    }())
                Text(k).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    .padding(40)
    .background(LiquidColor.fondoGradient)
}
