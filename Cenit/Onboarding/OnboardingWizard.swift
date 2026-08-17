import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - OnboardingWizard  ·  el onboarding en seis actos (FER-109)
//
// El primer arranque dejó de ser un wizard de formularios y pasó a ser una sola escena que se
// transforma seis veces sobre EL MISMO lienzo de partículas. Lo que hay que entender antes de
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
//   3. **El color llega como REVELACIÓN.** El lienzo va en tinta neutra durante cinco de los seis
//      actos; el veredicto lo tiñe UNA vez, en el encendido del acto 3 → 4. Y la palabra que
//      aparece ahí no se escribe en este flujo: sale de `LiquidHoyBuilder.veredicto`, la MISMA
//      función que la dice en Hoy, para que las dos pantallas no puedan discrepar.
//
//   4. **Actos 3 y 4 son la misma pantalla.** No hay corte entre «conectando» y «tu lectura»: la
//      convergencia se densifica, se tiñe, calla, y la palabra entra en fade puro encima.
//
// Los actos viven en archivos hermanos (`OnboardingActoPromesa`, `OnboardingActoEncendido`,
// `OnboardingActoActa`, `OnboardingActoCiclo`); aquí está la escena, el lienzo y el cableado.

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
            OnbActoEncendido(
                densidad: $densidad,
                tenido: $tenido,
                landing: $landing,
                revelado: $revelado,
                onContinuar: { ir(a: .acta) },
                onEntrenar: { terminar(irAEntrenar: true) },
                onEntrar: { terminar() })
        case .acta:
            OnbActoActa(
                landing: landing,
                onAtras: { ir(a: .encendido) },
                onContinuar: { ir(a: .ciclo) })
        case .ciclo:
            OnbActoCiclo(
                landing: landing,
                onAtras: { ir(a: .acta) },
                onEntrar: { terminar() })
        case .salida:
            OnbActoSalida(
                onReconsiderar: { ir(a: .permiso) },
                onEntrar: { terminar() })
        }
    }

    // MARK: El lienzo, acto por acto

    private var modo: AcumulacionSimulacion.Modo {
        switch acto {
        case .promesa:            return .disperso
        case .permiso, .salida:   return .quieto
        case .encendido:          return revelado ? .dentro : .convergencia
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

    /// El final del flujo. «Ir a Entrenar» aterriza en la pestaña que sí funciona sin reloj,
    /// vía el mismo `TabRouter` que usan las demás pantallas.
    private func terminar(irAEntrenar: Bool = false) {
        if irAEntrenar { tabRouter.requested = .train }
        onFinished()
    }
}

// MARK: - Los seis actos (+ la salida)

enum OnbActo: Hashable {
    /// 1 · La promesa.
    case promesa
    /// 2 · El permiso, que es también el diagrama de pesos.
    case permiso
    /// 3 y 4 · La conexión y la lectura: LA MISMA pantalla, que se transforma sin corte.
    case encendido
    /// 5 · El acta: de qué está hecha la palabra.
    case acta
    /// 6 · El ciclo y la mañana.
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

#Preview("Onboarding · seis actos") { OnboardingPreview() }
#endif
