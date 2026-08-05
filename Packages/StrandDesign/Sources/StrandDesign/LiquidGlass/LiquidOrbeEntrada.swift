import SwiftUI

// MARK: - «El orbe en tres actos» — el orbe FUERA del héroe (FER-41)
//
// Dos momentos en los que el orbe aparece solo, sin las lunas ni el guardián del Ecosistema:
// el ACTO I (la entrada de la app) y el ACTO II (la espera, cuando no hay ni una fuente).
// Viven juntos porque comparten una sola primitiva de dibujo (`nubeDeOrbe`) y porque son el
// MISMO objeto contando dos cosas distintas — separarlos invitaría a que uno derivara del
// otro con el tiempo.
//
// La coreografía del acto I no está aquí: vive en `EntradaSimulacion`, pura y unit-testeada.
// Este archivo solo la DIBUJA.

// MARK: Primitiva compartida

/// Un grupo de partículas del orbe: qué índices lleva, dónde está su centro y con cuánto alfa
/// entra. El acto I manda seis (una por corriente); el acto II, uno solo.
struct GrupoDeOrbe {
    var indices: [Int]
    var centro: CGPoint
    var alfaK: Double
}

/// Dibuja los grupos dados con el mismo bucketing que el héroe (`LiquidEcosistema.dibujarNube`):
/// un `Path` por nivel de alfa en vez de un fill por partícula. Sin ese agrupado, 300 fills por
/// frame no sostienen la tasa de refresco.
///
/// Los buckets son COMPARTIDOS entre grupos a propósito. Un diccionario por grupo dejaba el
/// pico de la entrada en ~40 fills por cuadro —el triple que el héroe para las mismas 300
/// partículas— porque cada corriente rehacía sus doce niveles por su cuenta. Como todas se
/// pintan del mismo color, dos partículas de corrientes distintas con el mismo alfa pueden
/// compartir trazo: 12 fills como techo, salgan de donde salgan.
@inline(__always)
private func nubeDeOrbe(_ ctx: inout GraphicsContext,
                        dirs: [SIMD3<Double>],
                        grupos: [GrupoDeOrbe],
                        radio: CGFloat,
                        rotacion: Double,
                        nivel: Double?,
                        jitter: Double,
                        t: TimeInterval,
                        color: Color) {
    var buckets: [Int: Path] = [:]
    for grupo in grupos where grupo.alfaK > 0.004 {
        for i in grupo.indices {
            let p = EcosistemaSimulacion.particula(
                dir: dirs[i], indice: i, centro: grupo.centro, radio: radio,
                rotacion: rotacion, jitterAmp: jitter, t: t, alfaK: grupo.alfaK, nivel: nivel)
            guard p.alfa > 0.004 else { continue }
            let idx = min(11, max(0, Int(p.alfa * 12)))
            buckets[idx, default: Path()].addEllipse(in: CGRect(
                x: p.pos.x - p.tamano, y: p.pos.y - p.tamano,
                width: p.tamano * 2, height: p.tamano * 2))
        }
    }
    for (idx, path) in buckets {
        ctx.fill(path, with: .color(color.opacity(min(1, (Double(idx) + 0.5) / 12))))
    }
}

/// El especular del orbe: el mismo reflejo arriba-a-la-izquierda que corona al orbe fundido
/// del héroe, para que el objeto se reconozca como el mismo bajo la misma luz.
@inline(__always)
private func especularDeOrbe(_ ctx: inout GraphicsContext, centro: CGPoint, radio: CGFloat, alfa: Double) {
    guard alfa > 0.004 else { return }
    let foco = CGPoint(x: centro.x - radio * 0.38, y: centro.y - radio * 0.42)
    let r = radio * 0.62
    ctx.fill(Path(ellipseIn: CGRect(x: foco.x - r, y: foco.y - r, width: r * 2, height: r * 2)),
             with: .radialGradient(
                Gradient(colors: [LiquidColor.particulaBlanca.opacity(0.55 * alfa),
                                  LiquidColor.particulaBlanca.opacity(0)]),
                center: foco, startRadius: 0, endRadius: r))
}

// MARK: - Acto I · la entrada

/// La animación de arranque: seis corrientes de partículas entran desde fuera de la pantalla,
/// se funden en el orbe, respiran, suben a su cénit y se tiñen del clima del día.
///
/// El host la monta ENCIMA de la app ya construida y la retira cuando `onFin` dispara: la
/// entrada nunca bloquea la carga, solo la tapa mientras dura.
///
/// `clima` es un CIERRE, no un valor, y eso es la mitad del diseño: al abrir la app el
/// veredicto casi nunca está calculado todavía, así que la entrada no lo lee al montarse — lo
/// lee UNA sola vez, en el instante en que el teñido arranca, que es cuando el color empieza a
/// importar. Antes de eso el orbe es gris y da igual; leerlo por frame en cambio dejaría que un
/// veredicto que aterriza a media revelación saltara de color a la vista del usuario.
public struct LiquidOrbeEntrada: View {
    private typealias G = EntradaSimulacion.Geometria

    private let clima: () -> LiquidAmbiente
    private let onFin: () -> Void

    /// Las direcciones de la esfera, una sola vez por proceso (300 `sin`/`cos` no se rehacen
    /// por frame).
    private static let dirs = EcosistemaSimulacion.fibonacci(EntradaSimulacion.Geometria.n)
    /// Qué partículas lleva cada corriente, precomputado: el reparto es fijo.
    private static let reparto: [[Int]] = {
        var r = [[Int]](repeating: [], count: EntradaSimulacion.Geometria.corrientes)
        for i in 0..<EntradaSimulacion.Geometria.n {
            r[EntradaSimulacion.corriente(i, de: EntradaSimulacion.Geometria.n)].append(i)
        }
        return r
    }()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    /// La app se puede ir al fondo a media coreografía (una llamada entrando, el Centro de
    /// Control). Sin esto el `TimelineView` sigue programando redibujos que nadie ve.
    @Environment(\.scenePhase) private var scenePhase
    @State private var inicio: Date?
    @State private var saltada = false
    /// La entrada avisa que terminó UNA sola vez. Hay dos caminos que llegan al final —la
    /// coreografía completa y el toque que la salta— y sin esta marca un toque justo al cierre
    /// dispararía los dos.
    @State private var aviso = false
    /// El clima FIJADO al arrancar el teñido. Neutro hasta entonces — que es exactamente lo
    /// que el orbe muestra mientras `tinte` vale 0.
    @State private var climaFijado: LiquidAmbiente = .neutro

    public init(clima: @escaping () -> LiquidAmbiente, onFin: @escaping () -> Void) {
        self.clima = clima
        self.onFin = onFin
    }

    private var sinViaje: Bool { reduceMotion || motionDisabled }

    public var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            // Con tope de 60 Hz explícito, como el resto del sistema: sin él, en ProMotion
            // esto pediría 120 cuadros por segundo justo durante el arranque en frío, cuando
            // HealthKit, SQLite y la construcción de la app ya se pelean por el CPU.
            TimelineView(.animation(minimumInterval: LiquidMotion.intervaloPleno,
                                    paused: scenePhase != .active)) { ctx in
                let t = tiempo(ctx.date)
                let cuadro = EntradaSimulacion.cuadro(t: t, reduce: sinViaje)
                Canvas(rendersAsynchronously: false) { g, size in
                    dibujar(&g, size: size, cuadro: cuadro, t: t)
                }
                // El fundido de salida se aplica AQUÍ y no dentro del Canvas: así atenúa la
                // composición ya resuelta en vez de cada relleno por separado (que dejaría
                // ver las partículas traslapándose entre sí mientras se apaga).
                .opacity(cuadro.alfa)
            }
        }
        // Decorativa de cabo a rabo: para VoiceOver esta pantalla no existe, así que el
        // lector de pantalla se va derecho a la app en vez de esperar la coreografía.
        .accessibilityHidden(true)
        // La forma es toda la pantalla: la entrada se come los toques en vez de dejarlos pasar
        // a una app que el usuario todavía no ve.
        .contentShape(Rectangle())
        // Un toque la salta: la entrada se disuelve donde vaya, sin brincar al final (un
        // salto desde media llegada se vería como un glitch, no como saltarse algo).
        .onTapGesture { saltar() }
        .opacity(saltada ? 0 : 1)
        .animation(.easeOut(duration: LiquidMotion.quick), value: saltada)
        .task {
            inicio = Date()
            // El veredicto se lee en el instante en que el color empieza a existir, no al
            // montarse: a los 0 ms casi nunca está calculado y el orbe acabaría siempre gris.
            try? await Task.sleep(for: .seconds(EntradaSimulacion.instanteDelTeñido(reduce: sinViaje)))
            guard !Task.isCancelled else { return }
            climaFijado = clima()
            try? await Task.sleep(for: .seconds(
                EntradaSimulacion.duracion(reduce: sinViaje)
                    - EntradaSimulacion.instanteDelTeñido(reduce: sinViaje)))
            guard !Task.isCancelled else { return }
            terminar()
        }
    }

    private func tiempo(_ ahora: Date) -> TimeInterval {
        guard let inicio else { return 0 }
        return max(0, ahora.timeIntervalSince(inicio))
    }

    private func terminar() {
        guard !aviso else { return }
        aviso = true
        onFin()
    }

    private func saltar() {
        guard !saltada, !aviso else { return }
        saltada = true
        Task {
            try? await Task.sleep(for: .seconds(LiquidMotion.quick))
            terminar()
        }
    }

    private func dibujar(_ g: inout GraphicsContext, size: CGSize,
                         cuadro c: EntradaSimulacion.Cuadro, t: TimeInterval) {
        // Escala uniforme por ancho + centrado vertical: los círculos siguen siendo círculos
        // y la composición conserva sus proporciones en cualquier alto de pantalla.
        let s = size.width / G.lienzo.width
        let dy = (size.height - G.lienzo.height * s) / 2
        let centro = CGPoint(x: c.centro.x * s, y: c.centro.y * s + dy)
        let radio = G.radio * s
        // El teñido es UN color por frame, interpolado en sRGB del gris neutro al clima. La
        // alternativa —dos nubes superpuestas cruzándose en opacidad— deja al orbe perdiendo
        // densidad justo a medio teñido, que es el instante que más se mira.
        let tinta = LiquidColor.particulaTeñida(hacia: climaFijado.particulaRGB, k: c.tinte)

        let grupos = (0..<G.corrientes).map { corriente -> GrupoDeOrbe in
            let d = c.desvios[corriente]
            return GrupoDeOrbe(indices: Self.reparto[corriente],
                               centro: CGPoint(x: centro.x + d.width * s,
                                               y: centro.y + d.height * s),
                               alfaK: c.alfas[corriente])
        }
        nubeDeOrbe(&g, dirs: Self.dirs, grupos: grupos, radio: radio, rotacion: c.rotacion,
                   nivel: nil,                        // esfera PLENA: objeto, no lectura
                   jitter: 0, t: t, color: tinta)
        especularDeOrbe(&g, centro: centro, radio: radio, alfa: c.especular)
    }
}

// MARK: - Acto II · la espera

/// El orbe DORMIDO: el estado de Hoy cuando no hay ni una fuente conectada. El mismo objeto,
/// en tinta neutra y con su nivel en cero — un recipiente vacío, que es exactamente lo que se
/// sabe del usuario en ese momento. Respira lento y cada tanto una partícula chispea en verde:
/// la promesa de que va a despertar.
///
/// No lleva contador de noches a propósito: sin permiso no se sabe cuántas faltan, y el
/// historial del Apple Watch puede sembrar la base de golpe. Prometer «N noches» sería falso.
public struct LiquidOrbeDormido: View {
    private static let dirs = EcosistemaSimulacion.fibonacci(EcosistemaSimulacion.Geometria.nEsfera)
    private static let indices = Array(0..<EcosistemaSimulacion.Geometria.nEsfera)
    /// La partícula que chispea. Un índice fijo: la chispa siempre nace en el mismo punto de
    /// la esfera, así que gira con ella en vez de saltar por la superficie.
    private static let chispa = 137

    /// Periodo de la respiración y de la chispa (s) — el mismo, para que la chispa caiga
    /// siempre en la misma parte del ciclo y lea como un latido, no como ruido.
    private static let periodo: Double = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    /// Lo pone la pantalla cuando la app sale de `.active`. Sin esto el orbe seguiría
    /// respirando a 20 fps en segundo plano — el estado vacío es justo el que más tiempo
    /// pasa abierto sin que nadie lo mire.
    @Environment(\.liquidAmbientPaused) private var pausado

    public init() {}

    private var quieto: Bool { reduceMotion || motionDisabled || pausado }

    public var body: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente,
                                paused: quieto)) { ctx in
            Canvas(rendersAsynchronously: false) { g, size in
                dibujar(&g, size: size, t: quieto ? 0 : ctx.date.timeIntervalSinceReferenceDate)
            }
        }
        // El escenario del orbe: alto fijo a propósito. Es decorativo, así que NO crece con
        // Dynamic Type — si creciera, a tamaños AX empujaría el copy y el botón fuera de
        // pantalla justo para quien más necesita alcanzarlos.
        .frame(height: 168)
        .accessibilityHidden(true)
    }

    private func dibujar(_ g: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let centro = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height) * 0.38
        // Respiración: ±4.5 % con periodo `periodo`.
        let radio = base * (quieto ? 1 : 1 + 0.045 * sin(t * 2 * .pi / Self.periodo))
        nubeDeOrbe(&g, dirs: Self.dirs,
                   grupos: [GrupoDeOrbe(indices: Self.indices, centro: centro, alfaK: 0.9)],
                   radio: radio,
                   rotacion: quieto ? 0 : t * 0.14,
                   nivel: 0,                       // recipiente vacío: solo el piso y vapor
                   jitter: 0, t: t, color: LiquidColor.particulaNeutra)
        chispear(&g, centro: centro, radio: radio, t: t)
    }

    /// La chispa: un destello verde sobre UNA partícula, al final de cada ciclo de respiración.
    /// Con Reduce Motion no aparece — un parpadeo es movimiento aunque no se desplace.
    private func chispear(_ g: inout GraphicsContext, centro: CGPoint, radio: CGFloat, t: TimeInterval) {
        guard !quieto else { return }
        let fase = t.truncatingRemainder(dividingBy: Self.periodo) / Self.periodo
        guard fase > 0.58, fase < 0.74 else { return }
        let alfa = sin((fase - 0.58) / 0.16 * .pi)
        let p = EcosistemaSimulacion.particula(
            dir: Self.dirs[Self.chispa], indice: Self.chispa, centro: centro,
            radio: radio, rotacion: t * 0.14, jitterAmp: 0, t: t)
        let r = p.tamano * 1.9
        g.fill(Path(ellipseIn: CGRect(x: p.pos.x - r, y: p.pos.y - r, width: r * 2, height: r * 2)),
               with: .color(LiquidColor.verdeOrbe.opacity(0.9 * alfa)))
    }
}

/// El estado completo de «sin ni una fuente»: el orbe dormido, lo que le falta para
/// despertar, y la única acción posible.
///
/// Los textos llegan de afuera: el catálogo de cadenas vive en la app, no en el sistema de
/// diseño. La jerarquía sí es del sistema — el título usa la voz de CALIBRANDO (`displayS`,
/// 22 pt) y no la de un veredicto (30 pt), porque esto todavía no afirma nada del cuerpo de
/// nadie: la humildad se ve en el tamaño.
public struct LiquidOrbeDormidoEstado: View {
    private let titulo: String
    private let cuerpo: String
    private let cta: String
    private let privacidad: String
    private let onConectar: () -> Void

    /// El cuerpo ESCALA con Dynamic Type. `LiquidType.cuerpo` es de tamaño fijo (SF no acepta
    /// `relativeTo:`), y aquí eso sería un defecto de accesibilidad y no un detalle: esta
    /// pantalla no tiene más trabajo que ser leída, y su lector podría no alcanzar nunca el
    /// botón porque el texto que se lo explica se quedó en 12.5 pt. Mismo patrón que
    /// `LiquidAutonomicoScreen` y `LiquidBandsTable`.
    @ScaledMetric(relativeTo: .footnote)
    private var cuerpoPt: CGFloat = LiquidType.cuerpoLecturaBase

    public init(titulo: String, cuerpo: String, cta: String, privacidad: String,
                onConectar: @escaping () -> Void) {
        self.titulo = titulo
        self.cuerpo = cuerpo
        self.cta = cta
        self.privacidad = privacidad
        self.onConectar = onConectar
    }

    public var body: some View {
        VStack(spacing: LiquidSpace.s400) {
            LiquidOrbeDormido()
            VStack(spacing: LiquidSpace.s250) {
                Text(titulo)
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(cuerpo)
                    .font(.system(size: cuerpoPt))
                    .lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            LiquidGlassButton(cta, variant: .primary, action: onConectar)
            Text(privacidad)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Sin margen horizontal propio: el margen de PANTALLA lo pone la pantalla. Cuando el
        // componente traía el suyo, Hoy le sumaba el de la suya y el título, el botón y el
        // aviso quedaban 16 pt más adentro que la fecha de la cabecera — un desalineo visible
        // en la primera pantalla que ve quien todavía no da permiso de Salud.
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Acto I · entrada") {
    LiquidOrbeEntrada(clima: { .bien }, onFin: {})
}

#Preview("Acto II · el orbe dormido") {
    ZStack {
        LiquidColor.fondoGradient.ignoresSafeArea()
        LiquidOrbeDormidoEstado(
            titulo: "El orbe aún duerme",
            cuerpo: "Conecta Apple Salud y empezará a latir con tus noches.",
            cta: "Conectar Apple Salud",
            privacidad: "Todo se queda en tu iPhone. Sin cuenta, sin nube.",
            onConectar: {})
        .padding(.horizontal, LiquidSpace.s550)
    }
}

#Preview("Acto II · AX5") {
    ZStack {
        LiquidColor.fondoGradient.ignoresSafeArea()
        ScrollView {
            LiquidOrbeDormidoEstado(
                titulo: "El orbe aún duerme",
                cuerpo: "Conecta Apple Salud y empezará a latir con tus noches.",
                cta: "Conectar Apple Salud",
                privacidad: "Todo se queda en tu iPhone. Sin cuenta, sin nube.",
                onConectar: {})
            .padding(.horizontal, LiquidSpace.s550)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
