import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - OnboardingWizard  ·  el onboarding en siete actos (FER-109 · FER-113)
//
// El primer arranque dejó de ser un wizard de formularios y pasó a ser una sola escena que se
// transforma siete veces sobre EL MISMO lienzo de partículas. Lo que hay que entender antes de
// tocar este archivo:
//
//   1. **Un solo suelo: `LiquidColor.fondoGradient`.** Es exactamente el papel de Hoy. El
//      onboarding termina descubriendo la app, y con el papel cálido de «Instrumento» el
//      aterrizaje saltaba de color en el último cuadro. Cero `InstrumentoTheme.base.paper` aquí.
//
//   2. **El orbe se llena con TU evidencia, no con el reloj.** La densidad del lienzo la manda
//      `OnboardingLanding.densidadHonesta`, nunca cuánto tiempo llevas mirando la pantalla (ver
//      la cabecera de `AcumulacionSimulacion`: en Hoy un orbe llenándose YA significa «todavía no
//      te conozco», así que usar el mismo dibujo para «estoy descargando» enseñaría a leer mal la
//      pantalla de todas las mañanas).
//
//   3. **El color llega como REVELACIÓN.** El lienzo va en tinta neutra durante los primeros tres
//      actos; el veredicto lo tiñe UNA vez, en el encendido del acto 3 → 4. Y la palabra que
//      aparece ahí no se escribe en este flujo: sale de `LiquidHoyBuilder.veredicto`, la MISMA
//      función que la dice en Hoy, para que las dos pantallas no puedan discrepar.
//
//   4. **Actos 3 y 4 son la misma pantalla.** No hay corte entre «conectando» y «tu lectura»: la
//      convergencia se densifica, se tiñe, calla, y la palabra entra en fade puro encima.
//
// Los actos viven en archivos hermanos (`OnboardingActoPromesa`, `OnboardingActoEncendido`,
// `OnboardingActoPerfil`, `OnboardingActoActa`, `OnboardingActoCiclo`); aquí está la escena, el
// lienzo y el cableado.

struct OnboardingWizard: View {

    /// Se llama cuando el usuario termina (o se salta al final de) el onboarding.
    var onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var tabRouter: TabRouter

    @State private var acto: OnbActo = .promesa
    /// 0…1 de cuánta materia hay en el lienzo. Ver la regla 2 de la cabecera.
    @State private var densidad: Double = 0
    /// 0 = tinta neutra · 1 = el color del veredicto. Ver la regla 3.
    @State private var tenido: Double = 0
    /// El desenlace, en cuanto se conoce. `nil` hasta que la sincronización termina.
    @State private var landing: OnboardingLanding?
    /// El acto 4 ya reveló: el lienzo pasa de `.convergencia` a `.dentro`.
    @State private var revelado = false

    // El acto 5 (el perfil) es la ÚLTIMA parada común de TODAS las ramas, así que de dónde vino y
    // a dónde va se fijan al entrar (`irAPerfil`) en vez de que el acto los adivine.
    @State private var perfilAtras: OnbActo = .encendido
    @State private var perfilLuego: OnbPerfilLuego = .acta
    /// Lo que dejó el autollenado del perfil. Vive aquí y no en el acto porque volver desde el
    /// acta lo reconstruye en blanco: sin este sello afuera, el autollenado correría una segunda
    /// vez y pisaría lo que la persona acaba de corregir.
    @State private var perfilSello: OnbPerfilSello?

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()

            OnbLienzo(densidad: densidad, tenido: tenido, modo: modo,
                      destino: destinoTinte, dosCentros: acto == .ciclo)
                .ignoresSafeArea()
                .zIndex(0)

            contenido
                .id(acto)
                .transition(.opacity)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(LiquidMotion.glassOut(LiquidMotion.gentle), value: acto)
    }

    // MARK: El acto en turno

    @ViewBuilder
    private var contenido: some View {
        switch acto {
        case .promesa:
            OnbActoPromesa(densidad: $densidad, onEmpezar: { ir(a: .permiso) })
        case .permiso:
            OnbActoPermiso(
                onAtras: { ir(a: .promesa) },
                onConectar: {
                    await health.requestAuthorization()
                    ir(a: .encendido)
                },
                onAhoraNo: { ir(a: .salida) })
        case .encendido:
            // Las TRES salidas del reveal pasan por el perfil, no solo la del veredicto: quien no
            // trae reloj (o negó el permiso) es justo quien no tiene autollenado posible, y era el
            // único que se quedaba con los cuatro valores de fábrica sin enterarse (FER-113).
            OnbActoEncendido(
                densidad: $densidad,
                tenido: $tenido,
                landing: $landing,
                revelado: $revelado,
                onContinuar: { irAPerfil(desde: .encendido, luego: .acta) },
                onEntrenar: { irAPerfil(desde: .encendido, luego: .entrenar) },
                onEntrar: { irAPerfil(desde: .encendido, luego: .entrar) })
        case .perfil:
            OnbActoPerfil(
                sello: $perfilSello,
                luego: perfilLuego,
                onAtras: { ir(a: perfilAtras) },
                onContinuar: { salirDelPerfil() })
        case .acta:
            OnbActoActa(
                landing: landing,
                onAtras: { ir(a: .perfil) },
                onContinuar: { ir(a: .ciclo) })
        case .ciclo:
            OnbActoCiclo(
                landing: landing,
                onAtras: { ir(a: .acta) },
                onEntrar: { terminar() })
        case .salida:
            OnbActoSalida(
                onReconsiderar: { ir(a: .permiso) },
                onEntrar: { irAPerfil(desde: .salida, luego: .entrar) })
        }
    }

    // MARK: El lienzo, acto por acto

    private var modo: AcumulacionSimulacion.Modo {
        switch acto {
        case .promesa:            return .disperso
        case .permiso, .salida:   return .quieto
        case .encendido:          return revelado ? .dentro : .convergencia
        // El perfil hereda la esfera ya formada del reveal: el orbe sigue ahí, girando despacio,
        // mientras se corrigen cuatro datos. Descomponerlo aquí adelantaría el gesto del acta.
        // Llegando por «Ahora no» nunca hubo encendido, así que el campo sigue CONGELADO: formar
        // la esfera ahí dibujaría un orbe que ninguna evidencia sostiene.
        case .perfil:             return revelado ? .dentro : .quieto
        case .acta:               return .descomposicion
        case .ciclo:              return .circulacion
        }
    }

    /// El color al que el lienzo se tiñe cuando hay veredicto. La familia de PARTÍCULA (más
    /// profunda que los semánticos: un punto de 0.7–2.2 pt con alfa ≤ .65 lava cualquier tono
    /// medio), la misma que usa el héroe de Hoy. Sin palabra no hay tinte: el orbe se queda gris
    /// en vez de apostar un color.
    private var destinoTinte: (r: Double, g: Double, b: Double)? {
        guard case let .lectura(verdict, _, _) = landing else { return nil }
        switch verdict {
        case .full:      return LiquidColor.ParticulaRGB.verde
        case .caution:   return LiquidColor.ParticulaRGB.ambar
        case .easy:      return LiquidColor.ParticulaRGB.roja
        case .lowSignal: return nil
        }
    }

    // MARK: Navegación

    private func ir(a destino: OnbActo) {
        withAnimation(LiquidMotion.glassOut(LiquidMotion.gentle)) { acto = destino }
    }

    /// Entra al perfil dejando dicho de dónde vino (para «Atrás») y a dónde sale. Su CTA es el
    /// mismo botón que la persona acaba de tocar, así que el paso se mete en el camino sin
    /// cambiarle el destino.
    private func irAPerfil(desde: OnbActo, luego: OnbPerfilLuego) {
        perfilAtras = desde
        perfilLuego = luego
        ir(a: .perfil)
    }

    private func salirDelPerfil() {
        switch perfilLuego {
        case .acta:     ir(a: .acta)
        case .entrar:   terminar()
        case .entrenar: terminar(irAEntrenar: true)
        }
    }

    /// El final del flujo. «Ir a Entrenar» aterriza en la pestaña que sí funciona sin reloj,
    /// vía el mismo `TabRouter` que usan las demás pantallas.
    private func terminar(irAEntrenar: Bool = false) {
        if irAEntrenar { tabRouter.requested = .train }
        onFinished()
    }
}

// MARK: - Los siete actos (+ la salida)

enum OnbActo: Hashable {
    /// 1 · La promesa.
    case promesa
    /// 2 · El permiso, que es también el diagrama de pesos.
    case permiso
    /// 3 y 4 · La conexión y la lectura: LA MISMA pantalla, que se transforma sin corte.
    case encendido
    /// 5 · El perfil: los cuatro datos que el motor necesita de ti, precargados de Apple Salud.
    /// Aparece en TODAS las ramas, incluida la salida de «Ahora no» (FER-113).
    case perfil
    /// 6 · El acta: de qué está hecha la palabra.
    case acta
    /// 7 · El ciclo y la mañana.
    case ciclo
    /// La salida de «Ahora no».
    case salida
}

// MARK: - El lienzo

/// El campo de partículas de fondo, con `densidad` y `teñido` ANIMABLES.
///
/// `LiquidOrbeAcumulacion` recibe la densidad como un `Double` cualquiera, y SwiftUI no interpola
/// los parámetros de una vista que no declara `Animatable`: un `withAnimation` sobre la densidad
/// la hacía SALTAR al valor final en el siguiente cuadro. Con `animatableData` el sistema vuelve a
/// evaluar este `body` en cada cuadro del tramo, que es lo que convierte «se llenó» en «se está
/// llenando». El teñido viaja en el mismo par porque el guion del encendido los encadena.
private struct OnbLienzo: View, Animatable {
    var densidad: Double
    var tenido: Double
    let modo: AcumulacionSimulacion.Modo
    let destino: (r: Double, g: Double, b: Double)?
    let dosCentros: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(densidad, tenido) }
        set { densidad = newValue.first; tenido = newValue.second }
    }

    var body: some View {
        LiquidOrbeAcumulacion(
            modo: modo,
            densidad: densidad,
            tinte: destino.map { LiquidColor.particulaTeñida(hacia: $0, k: tenido) },
            centroRelativo: dosCentros ? UnitPoint(x: 0.28, y: 0.30) : UnitPoint(x: 0.5, y: 0.34),
            centroSecundario: dosCentros ? UnitPoint(x: 0.72, y: 0.30) : nil)
    }
}

// MARK: - Preview

#if DEBUG
private struct OnboardingPreview: View {
    @State private var model = AppModel.preview
    var body: some View {
        OnboardingWizard(onFinished: {})
            .environment(model)
            .environmentObject(model.repo)
            .environmentObject(model.profile)
            .environmentObject(TabRouter())
            .environmentObject(HealthKitBridge(repo: model.repo,
                                               appleDeviceId: "preview-apple",
                                               noopDeviceId: "preview"))
            .frame(width: 390, height: 800)
    }
}

#Preview("Onboarding · siete actos") { OnboardingPreview() }
#endif
