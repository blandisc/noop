import SwiftUI

// MARK: - Liquid Glass · Motion (handoff §4.7)
//
// El contrato de movimiento del sistema: duraciones + easings + recetas nombradas. Las
// pantallas y componentes SOLO consumen este contrato — cero `0.3` / `.easeInOut` crudos
// en features, cero Core Animation, cero DispatchQueue.asyncAfter.
//
//   Duraciones   instant 120 ms · quick 240 ms · gentle 420 ms · sheet 560 ms ·
//                flow 9 s · drift 16–26 s
//   Easings      glass-out cubic-bezier(0.2, 0.6, 0.2, 1) — default de interacción
//                glass-spring cubic-bezier(0.34, 1.4, 0.4, 1) — sheets, apariciones
//                ambient ease-in-out — drift de orbes · flow linear — SOLO pulsos que viajan
//   Recetas      press · lift · entrada (stagger 60 ms) · sheet · ring progress
//
// Reduce Motion: toda animación continua (drift, flow) se congela; la entrada degrada a un
// crossfade simple. Los consumidores leen `accessibilityReduceMotion` + el override de
// entorno `liquidMotionDisabled` (para previews/tests, porque el flag de accesibilidad es
// de solo lectura).

public enum LiquidMotion {

    // MARK: Duraciones (segundos)

    /// 120 ms — press, toggles.
    public static let instant: Double = 0.12
    /// 240 ms — hover, cambios de estado.
    public static let quick: Double = 0.24
    /// 420 ms — entrada de contenido.
    public static let gentle: Double = 0.42
    /// 560 ms — hojas modales, navegación.
    public static let sheetDuration: Double = 0.56
    /// 9 s — pulsos por cables, dashes.
    public static let flowPeriod: Double = 6
    /// 16–26 s — orbes de fondo (16, 21, 24 y 26 s usados en los ensambles).
    public static let driftPeriods: ClosedRange<Double> = 16...26

    // MARK: Easings

    /// `glass-out` — el default de interacción.
    public static func glassOut(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.6, 0.2, 1, duration: duration)
    }

    /// `glass-spring` — sheets y apariciones con carácter (sobrepasa y asienta).
    public static func glassSpring(_ duration: Double) -> Animation {
        .timingCurve(0.34, 1.4, 0.4, 1, duration: duration)
    }

    /// `ambient` — drift de orbes de fondo.
    public static func ambient(_ duration: Double) -> Animation {
        .easeInOut(duration: duration)
    }

    /// `flow` — SOLO dashes/pulsos que viajan.
    public static func flowLinear(_ duration: Double) -> Animation {
        .linear(duration: duration)
    }

    // MARK: Recetas (transiciones compuestas)

    /// `press` — scale(0.97) · dur/instant · glass-out. Todo elemento tappable.
    public static let press = glassOut(instant)
    /// Escala del press.
    public static let pressScale: CGFloat = 0.97

    /// `lift` — translateY(−2) + sombra e/0 → e/2 · dur/quick · glass-out (hover/puntero).
    public static let lift = glassOut(quick)
    /// Desplazamiento vertical del lift.
    public static let liftOffset: CGFloat = -2

    /// `entrada` — fade + translateY(8 → 0) · dur/gentle · glass-out.
    public static let entrada = glassOut(gentle)
    /// Stagger entre hermanos de la entrada.
    public static let entradaStagger: Double = 0.06
    /// Desplazamiento inicial de la entrada.
    public static let entradaOffset: CGFloat = 8

    /// `sheet` — translateY(100 %) → 0 · dur/sheet · glass-spring. (API lista; Hoy no la usa.)
    public static let sheet = glassSpring(sheetDuration)
    /// La transición hermana del sheet, para `.transition(_:)`.
    public static var sheetTransition: AnyTransition { .move(edge: .bottom) }

    /// `ring progress` — el anillo/knob anima a su valor al entrar (dur/gentle · glass-out).
    public static let ringProgress = glassOut(gentle)

    /// `selector` — el vidrio del dock persigue la pestaña activa: spring corto y vivo
    /// (0.18 s glass-spring; «más responsivo», pedido del dueño /inject).
    public static let selector = glassSpring(0.18)

    // MARK: Ambientales (fase determinista para TimelineView — nunca por debajo de 9 s)

    /// Progreso 0→1→0 del `drift` (CSS `alternate` + ease-in-out ≈ coseno; ciclo completo
    /// = 2 × periodo). `reverse` arranca en el extremo opuesto (alternate-reverse).
    public static func driftProgress(time t: TimeInterval, period: Double, reverse: Bool = false) -> Double {
        let u = 0.5 - 0.5 * cos(.pi * t / period)
        return reverse ? 1 - u : u
    }

    /// Traslación máxima del drift (translate(28, 20) en la spec).
    public static let driftTranslation = CGSize(width: 28, height: 20)
    /// Escala máxima del drift (1 → 1.1).
    public static let driftScaleMax: CGFloat = 1.1

    /// Progreso 0–1 del pulso que viaja por un cable: un recorrido completo cada
    /// `flowPeriod` (9 s), lineal y continuo, con el delay de su cable (0 / 0.8 / 1.6).
    /// Es el equivalente en `trim` del `flowDash` de CSS (dash 2.5/93.5 → −96); en
    /// SwiftUI el pulso se dibuja con `Shape.trim`, no con stroke-dash.
    public static func flowPulseProgress(time t: TimeInterval, delay: Double = 0) -> Double {
        let raw = ((t - delay) / flowPeriod).truncatingRemainder(dividingBy: 1)
        return raw < 0 ? raw + 1 : raw
    }

    /// Largo del pulso como fracción del cable (los 2.5 pt del dash sobre un cable de
    /// ~130 pt del ensamble).
    public static let flowPulseLength: Double = 0.06
}

// MARK: - Recetas del Ecosistema (FER-10 — el héroe de esferas de partículas)
//
// Seis recetas nuevas al contrato, cada una con su comportamiento bajo Reduce Motion:
//   fusión      — viaje 1.55 s backOut(s=1.35) + stretch direccional 16 % + destello con
//                 chispas en el contacto + asentamiento amortiguado. RM: crossfade ≤0.3 s.
//   separación  — anticipación 0.22 s (squeeze 5 %) + apertura 1.55 s. RM: instantánea.
//   órbita      — lunas 0.85 / −0.6 rad/s, guardián 0.32 rad/s (dato coreografiado, NO
//                 ambiente: desviación sancionada al piso de 9 s, LIQUID-GLASS §8).
//                 RM: congelada en t = 0 (composición canónica determinista).
//   acreción    — 34 espirales cayendo ≈18 s al embrión. RM: constelación estática.
//   eclipse     — el guardián deja su órbita y asoma detrás (1.8 s smoothstep). RM: aparece
//                 colocado.
//   ambiente    — crossfade de color del clima 1.6 s. RM: el fade SÍ se conserva (un fade
//                 no es movimiento; lo que se congela es el drift).
public enum LiquidEcosistemaMotion {

    // fusión / separación
    public static let fusionDur: Double = 1.55
    /// Overshoot del back-out (s del cubic-back).
    public static let fusionOvershoot: Double = 1.35
    /// Estiramiento direccional máximo durante el viaje (squash & stretch).
    public static let fusionStretch: Double = 0.16
    /// Espera antes de la fusión de apertura (las esferas se presentan).
    public static let fusionIntroEspera: Double = 0.9
    /// Anticipación de la separación (el orbe toma aire).
    public static let anticipacion: Double = 0.22
    /// Squeeze de la anticipación (escala −5 %).
    public static let squeeze: Double = 0.05
    /// Asentamiento al quedar unido: `settleAmplitud·e^(−settleAmortiguacion·τ)·sin(settleFrecuencia·τ)`.
    public static let settleAmplitud: Double = 4
    public static let settleAmortiguacion: Double = 2.5
    public static let settleFrecuencia: Double = 11
    /// Fade de la palabra del veredicto al coronar.
    public static let palabraDur: Double = 0.70
    /// Crossfade bajo Reduce Motion (sustituye viaje/asentamiento).
    public static let reduceMotionCrossfade: Double = 0.3

    // órbita (velocidades angulares rad/s + fases iniciales)
    public static let orbitaLuna1: Double = 0.85
    public static let orbitaLuna2: Double = -0.6
    public static let orbitaGuardian: Double = 0.32
    public static let faseLuna2: Double = 2.2
    public static let faseGuardian: Double = 4.1
    /// Autorrotación de las nubes de partículas (esferas / lunas / guardián).
    public static let rotacionEsfera: Double = 0.6
    public static let rotacionLuna1: Double = 1.3
    public static let rotacionLuna2: Double = -1.1
    public static let rotacionGuardian: Double = 0.7
    /// Respiración del orbe fundido (±2 %).
    public static let respiracionEsfera: Double = 1.4
    /// Jitter de superficie (amplitud pt · velocidad rad/s); desgaste multiplica la amplitud.
    public static let jitterAmplitud: Double = 1.1
    public static let jitterDesgaste: Double = 2.6
    public static let jitterVelocidad: Double = 1.5
    /// Flicker de alfa en desgaste (rad/s; alfa 0.9–1.0).
    public static let flickerDesgaste: Double = 7.3
    /// Onda del menisco del nivel líquido (rad/s · amplitud pt).
    public static let nivelOndaVelocidad: Double = 2.0
    public static let nivelOndaAmplitud: Double = 2.2

    // acreción (calibrando)
    /// Ciclos de caída por segundo de cada espiral (caída completa ≈ 18.2 s).
    public static let acrecionCaida: Double = 0.055
    public static let acrecionGiro: Double = 0.45

    // eclipse (guardián en pareja)
    public static let eclipseDur: Double = 1.8

    // ambiente monocromo
    public static let ambienteCrossfade: Double = 1.6
}

// MARK: - Override de motion para previews/tests

private struct LiquidMotionDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

/// Pausa SOLO las animaciones ambientales continuas (drift de orbes, pulsos de cables) sin
/// tocar las recetas de interacción. El app la setea desde `scenePhase` para que un Hoy en
/// background no mantenga TimelineViews vivos (FER-1045).
private struct LiquidAmbientPausedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var liquidAmbientPaused: Bool {
        get { self[LiquidAmbientPausedKey.self] }
        set { self[LiquidAmbientPausedKey.self] = newValue }
    }
}

/// SOLO DEV (sesiones /inject): apaga capas Liquid por nombre para bisecar artefactos
/// visuales en vivo — «aurora», «orbes», «cables», «esferas», «glow». Vacío en producción;
/// ninguna pantalla la setea fuera de una sesión de depuración.
private struct LiquidDebugHideKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

public extension EnvironmentValues {
    var liquidDebugHide: Set<String> {
        get { self[LiquidDebugHideKey.self] }
        set { self[LiquidDebugHideKey.self] = newValue }
    }
}

public extension EnvironmentValues {
    /// Congela TODO el motion del sistema Liquid y presenta la UI ya asentada (progresos
    /// en su valor, entradas visibles). Para previews «sin motion», tests y renders — el
    /// flag real de accesibilidad es de solo lectura y ahí la entrada degrada a crossfade.
    var liquidMotionDisabled: Bool {
        get { self[LiquidMotionDisabledKey.self] }
        set { self[LiquidMotionDisabledKey.self] = newValue }
    }
}

// MARK: - Receta `press` (ButtonStyle)

/// El press del sistema: scale 0.97 · dur/instant · glass-out. Todo elemento clickeable
/// pasa por aquí — ningún componente re-escribe su propio press.
public struct LiquidPressButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? LiquidMotion.pressScale : 1)
            .animation(LiquidMotion.press, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == LiquidPressButtonStyle {
    /// `Button { … } label: { … }.buttonStyle(.liquidPress)`
    static var liquidPress: LiquidPressButtonStyle { LiquidPressButtonStyle() }
}

// MARK: - Receta `entrada` (modificador)

private struct LiquidEntrada: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    func body(content: Content) -> some View {
        content
            .opacity(shown || motionDisabled ? 1 : 0)
            .offset(y: shown || motionDisabled || reduceMotion ? 0 : LiquidMotion.entradaOffset)
            .onAppear {
                guard !shown, !motionDisabled else { return }
                if reduceMotion {
                    // Reduce Motion: crossfade simple, sin desplazamiento ni stagger.
                    withAnimation(.easeInOut(duration: 0.2)) { shown = true }
                } else {
                    let delay = baseDelay + Double(index) * LiquidMotion.entradaStagger
                    withAnimation(LiquidMotion.entrada.delay(delay)) { shown = true }
                }
            }
    }
}

public extension View {
    /// La entrada del sistema: fade + rise 8 pt · dur/gentle · glass-out, con stagger de
    /// 60 ms por `index` entre hermanos. Bajo Reduce Motion degrada a crossfade simple.
    func liquidEntrada(index: Int = 0, delay: Double = 0) -> some View {
        modifier(LiquidEntrada(index: index, baseDelay: delay))
    }
}

// MARK: - Receta `lift` (hover, plataformas con puntero)

private struct LiquidLift: ViewModifier {
    let tone: Color
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    func body(content: Content) -> some View {
        #if os(iOS) || os(macOS)
        let still = reduceMotion || motionDisabled
        // En reposo, las capas e/2 van transparentes (la receta de vidrio ya trae su e/0);
        // así el hover interpola e/0 → e/2 sin duplicar la sombra de reposo.
        let e2 = LiquidElevation.e2(tone: tone)
        let restLayers = e2.map { LiquidShadowLayer(color: $0.color.opacity(0), radius: $0.radius, y: $0.y) }
        return content
            .offset(y: hovered ? LiquidMotion.liftOffset : 0)
            .liquidShadow(hovered ? e2 : restLayers)
            .onHover { over in
                if still {
                    hovered = over
                } else {
                    withAnimation(LiquidMotion.lift) { hovered = over }
                }
            }
        #else
        return content
        #endif
    }
}

public extension View {
    /// La receta `lift`: −2 pt + sombra e/0 → e/2 con el tono del dato, en plataformas con
    /// puntero (iPad/Mac). En touch puro es inerte.
    func liquidLift(tone: Color) -> some View {
        modifier(LiquidLift(tone: tone))
    }
}

#if DEBUG
#Preview("Liquid · Motion (press + entrada)") {
    struct Demo: View {
        @State private var round = 0
        var body: some View {
            VStack(spacing: LiquidSpace.s400) {
                ForEach(0..<3, id: \.self) { i in
                    Button {} label: {
                        Text("Bloque \(i + 1) · entrada +\(i * 60) ms")
                            .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                            .foregroundStyle(LiquidColor.tinta900)
                            .padding(.vertical, 14).frame(maxWidth: .infinity)
                            .liquidGlass(.superficie)
                    }
                    .buttonStyle(.liquidPress)
                    .liquidEntrada(index: i)
                    .id("\(round)-\(i)")
                }
                Button("Repetir entrada") { round += 1 }
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.verdeProfundo)
            }
            .padding(LiquidSpace.s550)
            .background(LiquidColor.papelGradient)
        }
    }
    return Demo()
}
#endif
