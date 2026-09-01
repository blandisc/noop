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
    /// 180 ms — el spring del selector del dock persiguiendo la pestaña activa («más
    /// responsivo», pedido del dueño /inject). Nombrado (FER-31).
    public static let selectorDuration: Double = 0.18
    /// 200 ms — el crossfade simple de la entrada bajo Reduce Motion (sin viaje ni stagger).
    /// Nombrado (FER-31).
    public static let entradaReduce: Double = 0.2
    /// 150 ms — blips brevísimos de estado (Watch: check-toggle). Censo FER-269 (2 sitios).
    public static let brief: Double = 0.15
    /// 200 ms — toggle suave de estado que NO es la entrada (fase de respiración, reveal del
    /// héroe de arranque). Comparte cifra con `entradaReduce` por coincidencia real del censo —
    /// el rol es distinto (esto no es un fallback de Reduce Motion). Censo FER-269 (3 sitios).
    public static let soft: Double = 0.2
    /// 350 ms — crossfade de los gates de arranque (onboarding completado, términos aceptados).
    /// Censo FER-269 (2 sitios).
    public static let measured: Double = 0.35
    /// 9 s — pulsos por cables, dashes.
    public static let flowPeriod: Double = 6
    /// 16–26 s — orbes de fondo (16, 21, 24 y 26 s usados en los ensambles).
    public static let driftPeriods: ClosedRange<Double> = 16...26
    /// 9 s: latido de la plasta de la hoja (escala 1 → 1.1 → 1, ciclo completo).
    public static let plastaLatidoPeriod: Double = 9
    /// 26 s: deriva de la masa secundaria de la plasta de la hoja (ciclo completo 0 → offset → 0).
    public static let plastaDerivaPeriod: Double = 26

    // MARK: Intervalos de refresco (TimelineView)

    /// 20 fps — animaciones AMBIENTALES (plasta, capilares, aurora): el drift lento no necesita
    /// más y ahorra batería. Constante nombrada (FER-31), no `1.0/20.0` mágico en cada vista.
    public static let intervaloAmbiente: Double = 1.0 / 20.0
    /// 60 fps — simulaciones PLENAS (partículas del orbe, siembra de motas). (FER-31)
    public static let intervaloPleno: Double = 1.0 / 60.0
    /// 12 fps — los SELLOS chicos de la Matriz (OrbeVivo, SelloGuardianVivo): un cuerpo de
    /// pocos pt no delata más cuadros y son varios a la vez. Nombrado (FER-audit) en vez del
    /// `1.0/12` suelto que vivía fuera del contrato de movimiento.
    public static let intervaloSello: Double = 1.0 / 12.0

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

    /// `settle` — ease-out crudo para apariciones puntuales que no vienen de una lista con
    /// stagger (un blip, un toggle de estado). La contraparte de `ambient` (easeInOut) cuando el
    /// sitio real usa `.easeOut(duration:)`, no `.easeInOut`. Censo FER-269.
    public static func settle(_ duration: Double) -> Animation {
        .easeOut(duration: duration)
    }

    /// `dismiss` — ease-in crudo, SOLO para desvanecer algo que se retira (arranca lento, acelera
    /// al salir) — el opuesto de `settle`. Censo FER-269 (Watch: ocultar el check tras el delay).
    public static func dismiss(_ duration: Double) -> Animation {
        .easeIn(duration: duration)
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

    /// `onda` — el «amanecer de datos» de El Tablero (FER-28): cada columna se hunde
    /// `ondaSink` pt en cascada de `ondaStagger` s por columna (orden de lectura).
    public static let ondaStagger: Double = 0.07
    public static let ondaSink: CGFloat = 1.5

    /// `sheet` — translateY(100 %) → 0 · dur/sheet · glass-spring. (API lista; Hoy no la usa.)
    public static let sheet = glassSpring(sheetDuration)
    /// La transición hermana del sheet, para `.transition(_:)`.
    public static var sheetTransition: AnyTransition { .move(edge: .bottom) }

    /// `fade` — aparición simple sin desplazamiento (gates a pantalla completa, overlays).
    /// Censo FER-269: el patrón dominante de `.transition(_:)` en el árbol (10 sitios).
    public static var fadeTransition: AnyTransition { .opacity }

    /// `risingFade` — entra desde abajo con fundido (pills, toasts, banners de éxito/aviso).
    /// Censo FER-269 (9 sitios).
    public static var risingFadeTransition: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }

    /// `fallingFade` — entra desde arriba con fundido (banners de error, alertas de guardado).
    /// Censo FER-269 (8 sitios).
    public static var fallingFadeTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    /// `trailing` — entra/sale desde el borde derecho, sin fundido (paneles de detalle que
    /// deslizan como un push de navegación). Censo FER-269 (2 sitios, Cuerpo).
    public static var trailingTransition: AnyTransition { .move(edge: .trailing) }

    /// `fadeOrIdentity` — el fundido se apaga bajo Reduce Motion (queda colocado sin viaje).
    /// Centraliza el ternario `reduceMotion ? .identity : .opacity` que el censo encontró repetido
    /// 4 veces en un mismo archivo (FER-269) en vez de que cada sitio lo repita a mano.
    public static func fadeOrIdentity(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }

    /// `ring progress` — el anillo/knob anima a su valor al entrar (dur/gentle · glass-out).
    public static let ringProgress = glassOut(gentle)

    /// `selector` — el vidrio del dock persigue la pestaña activa: spring corto y vivo
    /// (0.18 s glass-spring; «más responsivo», pedido del dueño /inject).
    public static let selector = glassSpring(selectorDuration)

    // MARK: Puente valor-neutral desde StrandMotion (FER-280·2e)
    //
    // Alta mecánica: mismos valores exactos que los presets de `StrandMotion` aún calientes
    // en `Cenit/**`. Cero rediseño de tempo — solo un dialecto (`LiquidMotion`) y nombres
    // es-MX por rol. `gentle` (Strand) NO se llama `gentle` aquí: `LiquidMotion.gentle` ya
    // es la duración 420 ms; el spring de casa para cambios de valor/estado es `suave`.
    //
    // Mapa viejo → nuevo (valores congelados):
    //   StrandMotion.fade         easeInOut(0.30)                         → fundido
    //   StrandMotion.gentle       spring(response: 0.5, damping: 0.8)      → suave
    //   StrandMotion.interactive  interactiveSpring(0.28, 0.82, blend 0.1) → toque
    //   StrandMotion.hero         spring(response: 0.85, damping: 0.85)    → heroe
    //   StrandMotion.countUp      easeOut(0.75)                           → conteo
    //   StrandMotion.gated(_:_)   helper Reduce Motion                    → condicionado(_:_:)

    /// 300 ms — fundido estándar de tarjetas / filtros / overlays.
    /// Origen: `StrandMotion.durationStandard` / `StrandMotion.fade` (Motion.swift).
    public static let fundidoDuration: Double = 0.30

    /// 750 ms — conteo 0→valor del recibo (una sola vez al guardar).
    /// Origen: `StrandMotion.countUp` (Motion.swift).
    public static let conteoDuration: Double = 0.75

    /// `fundido` — ease-in-out 300 ms. Origen: `StrandMotion.fade`.
    public static let fundido = Animation.easeInOut(duration: fundidoDuration)

    /// `suave` — spring de casa para cambios de valor/estado (hojas, foco, barras).
    /// Origen: `StrandMotion.gentle` = spring(response: 0.5, dampingFraction: 0.8).
    /// No se llama `gentle`: ese nombre ya es la duración Liquid de 420 ms.
    public static let suave = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// `toque` — interactive spring para manipulación directa (press, selección, drag).
    /// Origen: `StrandMotion.interactive` =
    /// interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.1).
    public static let toque = Animation.interactiveSpring(
        response: 0.28, dampingFraction: 0.82, blendDuration: 0.1
    )

    /// `heroe` — spring deliberado para materializar un héroe (p. ej. celebración de import).
    /// Origen: `StrandMotion.hero` = spring(response: 0.85, dampingFraction: 0.85).
    public static let heroe = Animation.spring(response: 0.85, dampingFraction: 0.85)

    /// `conteo` — ease-out 750 ms del numeral 0→valor del recibo.
    /// Origen: `StrandMotion.countUp`.
    public static let conteo = Animation.easeOut(duration: conteoDuration)

    /// Devuelve `animation`, o `nil` cuando Reduce Motion está activo.
    /// Origen: `StrandMotion.gated(_:_)` (ReduceMotion.swift).
    public static func condicionado(_ animation: Animation?, _ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    // MARK: Springs nombrados (censo FER-278 — mismos response/damping que el literal crudo)

    /// Spring del swipe-to-reveal de una fila del plan semanal (abre/cierra el offset al soltar
    /// o al cerrar desde fuera). Censo FER-278 (2 sitios, WeeklyPlanEditor).
    public static let filaDesliza = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Spring del rasgado del ticket térmico + asiento del wobble de boca al cerrar.
    /// Censo FER-278 (3 sitios, ReceiptPrinter).
    public static let reciboRasga = Animation.spring(response: 0.15, dampingFraction: 0.35)

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
    /// Revelado del DATO al separar (FER-56, dueño: antes destapaba a media separación
    /// —0.85× del viaje, aún en vuelo— con un fade rápido: se sentía brusco). Aparece
    /// cuando el orbe está CASI aterrizado (~0.7× del viaje) y florece suave (ease-out
    /// 0.5) — antes esperaba el viaje COMPLETO + rebote (1.91 s), que se sentía tardío
    /// (revisión del dueño 2026-08). Al reunir, la salida es inmediata.
    public static let revelarDatoEspera: Double = anticipacion + fusionDur * 0.68
    public static let revelarDatoDur: Double = 0.50
    public static var revelarDatoAnim: Animation {
        .easeOut(duration: revelarDatoDur).delay(revelarDatoEspera)
    }
    /// Crossfade bajo Reduce Motion (sustituye viaje/asentamiento).
    public static let reduceMotionCrossfade: Double = 0.3
    /// Los crossfades ambiental / reduce-motion ya envueltos como `Animation` (FER-31): la curva
    /// ease-in-out del crossfade vive en el contrato, no cruda en cada call site de la superficie.
    public static var ambienteCrossfadeAnim: Animation { .easeInOut(duration: ambienteCrossfade) }
    public static var reduceCrossfadeAnim: Animation { .easeInOut(duration: reduceMotionCrossfade) }

    // órbita (velocidades angulares rad/s + fases iniciales)
    public static let orbitaLuna1: Double = 0.85
    public static let orbitaLuna2: Double = -0.6
    public static let orbitaGuardian: Double = 0.32
    public static let faseLuna2: Double = .pi   // t=0: la luna queda libre del orbe (composición canónica RM)
    public static let faseGuardian: Double = 2.4 // t=0: el guardián no pisa a las lunas
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
    /// C.3 (FER-20): fracción de la caída (`ph`) donde la espiral deja su ruta y FUNDE
    /// hacia su partícula destino del embrión — el aterrizaje.
    public static let acrecionAterrizaje: Double = 0.85
    /// Graduación en vivo (FER-20, decisión del dueño): duración del morfo
    /// embrión → orbe cuando la base se completa con la pantalla abierta.
    public static let graduacionDur: Double = 1.4
    /// C.4 (FER-21): duración del SOPLO del orbe al tocar «Cómo llegué a esto» — la
    /// mitad-héroe de la ilusión en dos mitades. No bloquea la presentación del sheet.

    // tributo (las lunas alimentan el orbe)
    /// Duración del viaje luna→orbe de cada mota del chorro (s).
    public static let tributoPeriodo: Double = 2.6
    /// Motas por luna decisora (el guardián no tributa).
    public static let tributoParticulas: Int = 5

    // eclipse (guardián en pareja)
    public static let eclipseDur: Double = 1.8

    // ambiente monocromo
    public static let ambienteCrossfade: Double = 1.6
}

// MARK: - Entrada de la app (FER-41 · «El orbe en tres actos», acto I)

/// Las perillas de la animación de arranque. `duracionTotal` es la PERILLA MAESTRA: cada
/// hito de la coreografía (`EntradaSimulacion.Guion`) es una fracción de ella, así que
/// acelerar o alargar toda la entrada es cambiar este número — nunca reescalar seis tiempos
/// a mano y que se desfasen entre sí.
public enum LiquidEntradaMotion {
    /// Cuánto dura la coreografía completa: llegada → respiro → ascenso → teñido.
    public static let duracionTotal: Double = 2.8
    /// El fundido con el que la entrada se retira y descubre la app ya construida.
    /// FER-73 (dueño): 0.35 → 0.5. El relevo pasa con el orbe YA parado en su destino, y medio
    /// segundo de cruce hace que los dos dibujos (el de la entrada y el del héroe) se lean como
    /// el mismo objeto en vez de un corte.
    public static let salida: Double = 0.5
    /// Con «Reducir movimiento» no hay viaje: el orbe aparece asentado y teñido y solo se
    /// sostiene lo justo para que el relevo no lea como un parpadeo.
    public static let duracionReduce: Double = 0.45
    /// El fundido de salida, ya envuelto (la curva vive en el contrato, no en el call site).
    public static var salidaAnim: Animation { .easeOut(duration: salida) }
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
                    withAnimation(.easeInOut(duration: LiquidMotion.entradaReduce)) { shown = true }
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

// MARK: - Receta `onda` (apertura de «El Tablero», FER-28)

private struct LiquidOnda: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    func body(content: Content) -> some View {
        let still = reduceMotion || motionDisabled
        if #available(iOS 17.0, macOS 14.0, *), !still {
            content
                .keyframeAnimator(initialValue: CGFloat(0), trigger: appeared) { view, y in
                    view.offset(y: y)
                } keyframes: { _ in
                    KeyframeTrack {
                        // El retardo en cascada por columna (orden de lectura) va como un
                        // tramo plano antes del hundimiento.
                        LinearKeyframe(0, duration: Double(index) * LiquidMotion.ondaStagger)
                        CubicKeyframe(LiquidMotion.ondaSink, duration: 0.14)
                        CubicKeyframe(0, duration: 0.16)
                    }
                }
                .onAppear { appeared = true }
        } else {
            // Reduce Motion / OS previo: colocada directo (sin onda), como el resto del sistema.
            content
        }
    }
}

public extension View {
    /// La «onda de apertura» de El Tablero: la columna se hunde 1.5 pt UNA vez al entrar, en
    /// cascada por `index` (orden de lectura, 70 ms entre columnas). Es un «amanecer de datos»:
    /// no se repite en cada visita al tab (corre en `onAppear`). Reduce Motion la omite.
    func liquidOnda(index: Int = 0) -> some View {
        modifier(LiquidOnda(index: index))
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
                            .liquidGlass(.superficie) // token-exempt: preview, fuera de una hoja
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
