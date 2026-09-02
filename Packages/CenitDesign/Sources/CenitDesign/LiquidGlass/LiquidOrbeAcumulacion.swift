import SwiftUI

// MARK: - LiquidOrbeAcumulacion  ·  el lienzo del onboarding (FER-109)
//
// Dibuja `AcumulacionSimulacion`. La física vive allá (pura, testeable, sin SwiftUI); aquí solo
// se pinta, igual que `LiquidOrbeEntrada` respecto de `EntradaSimulacion`.
//
// Dos cosas que parecen detalle y no lo son:
//
//   · **≤ 18 `fill` por cuadro, nunca uno por partícula.** Son 390 motas; pintarlas de una en una
//     cuesta ~3× lo que cuesta agruparlas por alfa en 18 trazos. Y este lienzo corre en el minuto
//     MÁS caro de la vida de la app: primer arranque, HealthKit machacando SQLite, el árbol de la
//     app armándose. Si algo va a tironear, va a ser aquí.
//
//   · **Baja a 20 fps en cuanto no hay motas viajando.** Respirar y derivar no necesitan 60, y el
//     tramo largo (esperar a que termine una sincronización de 180 días) es justo el que más dura.
//
// El tinte llega como REVELACIÓN, nunca de entrada: `tinte == nil` pinta en tinta neutra. Es la
// misma ley que ya trae escrita `EntradaSimulacion` («el gris es lo único honesto a los 0 ms»), y
// aquí aplica igual porque durante casi todo el onboarding todavía no hay veredicto que colorear.

public struct LiquidOrbeAcumulacion: View {

    private let modo: AcumulacionSimulacion.Modo
    private let densidad: Double
    private let tinte: Color?
    private let centroRelativo: UnitPoint
    private let radio: CGFloat
    private let centroSecundario: UnitPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - modo: qué está haciendo el campo en este acto.
    ///   - densidad: 0…1. **La manda la evidencia, no el reloj** — quien llama pasa
    ///     `OnboardingLanding.densidadHonesta`. Ver la cabecera de `AcumulacionSimulacion`.
    ///   - tinte: `nil` mientras no haya veredicto. El color entra como revelación.
    ///   - centroRelativo: dónde vive el orbe dentro del lienzo, en unidades 0…1.
    ///   - radio: el radio del orbe en puntos.
    ///   - centroSecundario: el segundo orbe, solo para `.circulacion`.
    public init(modo: AcumulacionSimulacion.Modo,
                densidad: Double,
                tinte: Color? = nil,
                centroRelativo: UnitPoint = .init(x: 0.5, y: 0.36),
                radio: CGFloat = 74,
                centroSecundario: UnitPoint? = nil) {
        self.modo = modo
        self.densidad = densidad
        self.tinte = tinte
        self.centroRelativo = centroRelativo
        self.radio = radio
        self.centroSecundario = centroSecundario
    }

    public var body: some View {
        GeometryReader { geo in
            let lienzo = geo.size
            if reduceMotion {
                // Sin `TimelineView`: un cuadro fijo a la densidad actual. Lo que se congela es el
                // drift, no el significado — la densidad sigue diciendo cuánta evidencia hay, y los
                // cambios de densidad hacen crossfade porque un fundido no es movimiento.
                lienzoPintado(t: 0, lienzo: lienzo, still: true)
                    .animation(LiquidEcosistemaMotion.reduceCrossfadeAnim, value: densidad)
            } else {
                TimelineView(.animation(minimumInterval: intervalo, paused: pausado)) { ctx in
                    lienzoPintado(t: ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600),
                                  lienzo: lienzo, still: false)
                }
            }
        }
        // Decorado: el acto es el elemento accesible, no las motas. VoiceOver no debe esperar la
        // coreografía para poder leer la pantalla.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// 60 fps solo mientras hay motas viajando; 20 en cuanto el campo nada más respira. Lo decide el
    /// MODO, que es quien sabe si algo está en vuelo — no la densidad: durante el acto 3 la densidad
    /// se queda clavada en su promesa (0.5), así que preguntarle a ella dejaba a 60 fps el tramo MÁS
    /// LARGO del flujo (la espera de la sincronización), justo el que este archivo promete abaratar.
    private var intervalo: Double {
        switch modo {
        case .quieto, .dentro, .descomposicion: LiquidMotion.intervaloAmbiente    // 1/20
        case .disperso, .convergencia, .circulacion: LiquidMotion.intervaloPleno  // 1/60
        }
    }

    private var pausado: Bool { scenePhase != .active }

    // MARK: El pintado

    private func lienzoPintado(t: TimeInterval, lienzo: CGSize, still: Bool) -> some View {
        let centro = CGPoint(x: lienzo.width * centroRelativo.x, y: lienzo.height * centroRelativo.y)
        let centroB = centroSecundario.map {
            CGPoint(x: lienzo.width * $0.x, y: lienzo.height * $0.y)
        }
        let motas = AcumulacionSimulacion.cuadro(t: t, densidad: densidad, modo: modo,
                                                 centro: centro, radio: radio, lienzo: lienzo,
                                                 centroB: centroB, reduce: still)
        return Canvas { ctx, _ in
            pintar(motas, en: &ctx)
        }
    }

    /// Agrupa por alfa cuantizada y pinta un trazo por cubeta: 12 cubetas para las motas del orbe
    /// (que tienen profundidad y por eso más rango de alfa) + 6 para el campo suelto = 18 `fill`.
    private func pintar(_ motas: [AcumulacionSimulacion.Mota], en ctx: inout GraphicsContext) {
        let cubetasOrbe = 12, cubetasCampo = 6
        var orbe = [Path](repeating: Path(), count: cubetasOrbe)
        var campo = [Path](repeating: Path(), count: cubetasCampo)

        for m in motas {
            let rect = CGRect(x: m.punto.x - m.radio, y: m.punto.y - m.radio,
                              width: m.radio * 2, height: m.radio * 2)
            if m.latcheada {
                let k = min(cubetasOrbe - 1, max(0, Int(m.alfa * Double(cubetasOrbe))))
                orbe[k].addEllipse(in: rect)
            } else {
                let k = min(cubetasCampo - 1, max(0, Int(m.alfa * Double(cubetasCampo))))
                campo[k].addEllipse(in: rect)
            }
        }

        let colorOrbe = tinte ?? LiquidColor.tinta500
        for (k, path) in orbe.enumerated() where !path.isEmpty {
            let alfa = (Double(k) + 0.5) / Double(cubetasOrbe)
            ctx.fill(path, with: .color(colorOrbe.opacity(alfa)))
        }
        for (k, path) in campo.enumerated() where !path.isEmpty {
            let alfa = (Double(k) + 0.5) / Double(cubetasCampo)
            ctx.fill(path, with: .color(LiquidColor.tinta500.opacity(alfa)))
        }
    }
}

// MARK: - Previews

#if DEBUG
private struct AcumulacionDemo: View {
    let modo: AcumulacionSimulacion.Modo
    let densidad: Double
    var tinte: Color? = nil
    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            LiquidOrbeAcumulacion(modo: modo, densidad: densidad, tinte: tinte)
        }
        .frame(width: 390, height: 500)
    }
}

#Preview("Acto 1 · formándose (0.35)") { AcumulacionDemo(modo: .disperso, densidad: 0.35) }
#Preview("Acto 2 · quieto (0.35)") { AcumulacionDemo(modo: .quieto, densidad: 0.35) }
#Preview("Acto 3 · convergencia (0.7)") { AcumulacionDemo(modo: .convergencia, densidad: 0.7) }
#Preview("Acto 4 · lleno, teñido") {
    AcumulacionDemo(modo: .dentro, densidad: 1, tinte: LiquidColor.verdePrimario)
}
#Preview("Acto 4 · poroso (8 noches)") { AcumulacionDemo(modo: .dentro, densidad: 8.0 / 14.0) }
#Preview("Acto 5 · descomposición") { AcumulacionDemo(modo: .descomposicion, densidad: 1) }
#Preview("Sin cuajar (sin reloj)") {
    AcumulacionDemo(modo: .dentro, densidad: AcumulacionSimulacion.Guion.techoSinCuajar)
}
#endif
