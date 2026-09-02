import SwiftUI
import CenitDesign
import StrandAnalytics

// MARK: - OnboardingWizard  ·  el onboarding en siete actos (FER-109 · FER-113)
//
// El primer arranque dejó de ser un wizard de formularios y pasó a ser una sola escena que se
// transforma siete veces sobre EL MISMO lienzo de partículas. Lo que hay que entender antes de
// tocar este archivo:
//
//   1. **Un solo suelo: `LiquidColor.fondoGradient`.** Es exactamente el papel de Hoy. El
//      onboarding termina descubriendo la app, y con el papel cálido de «Instrumento» el
//      aterrizaje saltaba de color en el último cuadro. El suelo es `LiquidColor.fondoGradient`.
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
//   5. **Después de la palabra viene el ACTA, nunca un formulario.** La ⓘ del reveal dice «está
//      aquí, siempre» señalando al acta, y es el único gesto de curiosidad del flujo: lo que sigue
//      a la palabra tiene que ser lo que la explica. El perfil (los cuatro datos que no salen de
//      tus señales) se cobra al SALIR del acta, rumbo al ciclo.
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
    /// Solo para saber si el perfil sigue INTACTO cuando Salud se conecta tarde (ver
    /// `replantearAutollenado`). El acto del perfil es quien lo edita.
    @EnvironmentObject private var profile: ProfileStore

    @State private var acto: OnbActo = .promesa
    /// 0…1 de cuánta materia hay en el lienzo. Ver la regla 2 de la cabecera.
    @State private var densidad: Double = 0
    /// 0 = tinta neutra · 1 = el color del veredicto. Ver la regla 3.
    @State private var tenido: Double = 0
    /// El desenlace, en cuanto se conoce. `nil` hasta que la sincronización termina.
    @State private var landing: OnboardingLanding?
    /// El acto 4 ya reveló: el lienzo pasa de `.convergencia` a `.dentro`.
    @State private var revelado = false

    // El perfil es la ÚLTIMA parada común de TODAS las ramas, así que de dónde vino y a dónde va
    // se fijan al entrar (`irAPerfil`) en vez de que el acto los adivine.
    @State private var perfilAtras: OnbActo = .encendido
    @State private var perfilLuego: OnbPerfilLuego = .ciclo
    /// Lo que dejó el autollenado del perfil. Vive aquí y no en el acto porque volver al perfil
    /// (desde el ciclo) lo reconstruye en blanco: sin este sello afuera, el autollenado correría
    /// una segunda vez y pisaría lo que la persona acaba de corregir.
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
                .transition(LiquidMotion.fadeTransition)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(LiquidMotion.glassOut(LiquidMotion.gentle), value: acto)
        // Conectar Salud DESPUÉS de haber pasado por el perfil (ruta real: «Ahora no» → perfil →
        // Atrás → reconsiderar → Conectar) dejaba el sello ya puesto, así que el autollenado no
        // volvía a correr: los cuatro campos seguían diciendo «Lo puse yo» y la nota le echaba a
        // Apple la culpa de no haber dado datos… con Salud ya conectada. El sello se invalida
        // aquí, en el wizard, porque el acto del perfil ni siquiera está en pantalla cuando el
        // permiso cambia. Vive aquí también la excepción que protege la doctrina del acto: si la
        // persona ya corrigió algo, su corrección GANA y el sello se queda.
        .onChange(of: health.auth) { _, nuevo in
            guard nuevo == .authorized else { return }
            replantearAutollenado()
        }
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
            // El reveal sale al ACTA, no al perfil. La ⓘ de la palabra promete «¿quieres ver cómo
            // llegué a esa palabra? está aquí, siempre» y es el único gesto de curiosidad del
            // flujo: aterrizarla en un formulario era contestar otra cosa. El perfil se cobra al
            // SALIR del acta, rumbo al ciclo, y sigue siendo la última parada común de todas las
            // ramas —incluidas las dos sin autollenado posible, que entran directo (FER-113).
            OnbActoEncendido(
                densidad: $densidad,
                tenido: $tenido,
                landing: $landing,
                revelado: $revelado,
                onContinuar: { ir(a: .acta) },
                onEntrenar: { irAPerfil(desde: .encendido, luego: .entrenar) },
                onEntrar: { irAPerfil(desde: .encendido, luego: .entrar) })
        case .perfil:
            OnbActoPerfil(
                sello: $perfilSello,
                luego: perfilLuego,
                landing: landing,
                // Quien llegó por «Ahora no» nunca vio el diálogo de Salud: su nota no puede
                // culpar a Apple de no haber dado datos que nadie le pidió.
                desdeSalida: perfilAtras == .salida,
                onAtras: { ir(a: perfilAtras) },
                onContinuar: { salirDelPerfil() })
        case .acta:
            OnbActoActa(
                landing: landing,
                onAtras: { ir(a: .encendido) },
                onContinuar: { irAPerfil(desde: .acta, luego: .ciclo) })
        case .ciclo:
            OnbActoCiclo(
                landing: landing,
                onAtras: { ir(a: .perfil) },
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
        // El perfil hereda el campo tal como lo dejó el acto anterior. Viniendo del ACTA ya está
        // descompuesto, y volver a juntarlo aquí para descomponerlo otra vez en el ciclo sería
        // deshacer delante del usuario el gesto que el acta acaba de hacer. Viniendo del reveal
        // (las ramas que salen directo a la app) hereda la esfera formada. Y llegando por «Ahora
        // no» nunca hubo encendido, así que el campo sigue CONGELADO: formar la esfera ahí
        // dibujaría un orbe que ninguna evidencia sostiene.
        case .perfil:
            if perfilAtras == .acta { return .descomposicion }
            return revelado ? .dentro : .quieto
        case .acta:               return .descomposicion
        case .ciclo:              return .circulacion
        }
    }

    /// El color al que el lienzo se tiñe cuando hay veredicto. La familia de PARTÍCULA (más
    /// profunda que los semánticos: un punto de 0.7–2.2 pt con alfa ≤ .65 lava cualquier tono
    /// medio), la misma que usa el héroe de Hoy. Sin palabra no hay tinte: el orbe se queda gris
    /// en vez de apostar un color.
    private var destinoTinte: (r: Double, g: Double, b: Double)? {
        // `revelaColor` es la MISMA puerta que el acto 4 consulta para saber si el beat del teñido
        // existe: si aquí hubiera color y allá no (o al revés), el guion se desincronizaría.
        guard let landing, landing.revelaColor else { return nil }
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
        case .ciclo:    ir(a: .ciclo)
        case .entrar:   terminar()
        case .entrenar: terminar(irAEntrenar: true)
        }
    }

    /// Salud se conectó DESPUÉS de que el perfil ya corrió su autollenado: el sello se tira para
    /// que vuelva a correr, ahora sí con la puerta abierta. La excepción es lo que sostiene la
    /// regla del acto —lo que la persona edita GANA—: si algún campo ya no coincide con el sello,
    /// hubo corrección a mano y el sello se queda como está (un segundo autollenado la borraría).
    private func replantearAutollenado() {
        guard let s = perfilSello else { return }
        let intacto = profile.age == s.edad && profile.sex == s.sexo
            && profile.weightKg == s.pesoKg && profile.heightCm == s.estaturaCm
        if intacto { perfilSello = nil }
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
    /// 5 · El acta: de qué está hecha la palabra. Es a DONDE APUNTA la ⓘ del reveal, así que va
    /// inmediatamente después de la palabra: entre las dos no puede meterse un formulario.
    case acta
    /// 6 · El perfil: los cuatro datos que el motor necesita de ti, precargados de Apple Salud.
    /// Se cobra al salir del acta, y aparece en TODAS las ramas —incluidas las que salen directo
    /// del reveal a la app y la salida de «Ahora no» (FER-113).
    /// (Sus claves de copy van sin número a propósito: `onb.perfil.*`.)
    case perfil
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
