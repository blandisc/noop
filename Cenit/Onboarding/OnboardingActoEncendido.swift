import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Actos 3 y 4  ·  el encendido (FER-109)
//
// **Una sola pantalla que se transforma.** No hay corte entre «te estoy leyendo» y «esto dice»:
// el campo converge, se densifica hasta la evidencia que de verdad hay, se tiñe con el veredicto,
// CALLA, y la palabra entra encima en fade puro. Si fueran dos pantallas, el usuario vería un
// cambio de contexto justo en el instante que el flujo entero existe para entregar.
//
// El guion, en orden (`OnbGuion`):
//   1. densificación final 1.2 s   ← el contenido del acto 3 se va en el mismo tramo
//   2. teñido 450 ms               ← el color llega como REVELACIÓN, nunca de entrada. SOLO donde
//                                     hay color (`landing.revelaColor`); en las otras tres ramas
//                                     el beat no existe en vez de esperar por nada
//   3. SILENCIO 300 ms             ← pantalla vacía, solo el orbe. Es lo que hace aterrizar la
//                                     palabra, y se queda en las CUATRO ramas
//   4. la palabra, fade puro 700 ms, CERO desplazamiento
//   5. la ⓘ, 400 ms después, SOLA
//   6. 350 ms más (`esperaResto`) y entra el resto, con el stagger de 60 ms del sistema. Sin esa
//      espera los beats 5 y 6 caían en el mismo cuadro y la ⓘ nunca estaba sola
//
// El reloj del acto 3 tiene **piso** (2.5 s: leer 180 días no puede parecer un parpadeo aunque
// HealthKit conteste en 400 ms) y **techo** (20 s: a partir de ahí la espera dejó de ser una
// coreografía, y aparece una salida real). Salir de la app a media lectura y volver NO reinicia
// el reloj: el arranque se fija una vez y se mide contra `Date()`.
//
// La palabra NO se escribe aquí: se la pide prestada a `LiquidHoyBuilder.veredicto`, la misma
// función que la dice en Hoy.

struct OnbActoEncendido: View {

    @Binding var densidad: Double
    @Binding var tenido: Double
    @Binding var landing: OnboardingLanding?
    @Binding var revelado: Bool

    let onContinuar: () -> Void
    let onEntrenar: () -> Void
    let onEntrar: () -> Void

    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var repo: Repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// Se salió a la app Salud desde una de las dos ramas que mandan allá. Al volver al primer
    /// plano se relee SOLO: antes había que salir, encender el permiso, volver… y además
    /// encontrar el botón de «Reintentar» para que la app se enterara.
    @State private var fueASalud = false

    // El reloj
    /// Cuándo empezó la lectura. Se fija UNA vez y sobrevive a irse al segundo plano.
    @State private var arranque: Date?
    @State private var techoAlcanzado = false
    @State private var corriendo = false
    @State private var syncListo = false
    @State private var falloLectura = false

    // El progreso
    @State private var avance: Double = 0
    @State private var etapaClave: String?
    @State private var etapaN = 1
    @State private var ultimaEtapa = false
    @State private var anunciados: Set<Int> = []

    // Los beats del reveal
    @State private var opacidadLectura: Double = 1
    @State private var mostrarPalabra = false
    @State private var mostrarInfo = false
    @State private var mostrarResto = false
    @State private var mostrarRotulo = false
    @AccessibilityFocusState private var focoRevelado: Bool

    var body: some View {
        OnbShell {
            if revelado {
                lectura
            } else {
                leyendo
            }
        }
        // El acto 3 se retira FUNDIÉNDOSE durante la densificación, no cortando: cuando el
        // silencio llega, la pantalla ya está vacía sobre el orbe. El fundido va aquí (y no
        // dentro del builder) porque los hijos del shell tienen que seguir siendo hermanos
        // directos de su `VStack` para que los `Spacer` empujen el CTA al pie.
        .opacity(revelado ? 1 : opacidadLectura)
        .task { await correr() }
        // Volver de la app Salud relee sola: encender el permiso allá y regresar es exactamente
        // el momento en que la lectura puede cambiar de desenlace. Solo aplica a quien SALIÓ por
        // el botón de Salud (`fueASalud`): irse a otra app y volver no reinicia el encendido.
        .onChange(of: scenePhase) { _, fase in
            guard fase == .active, fueASalud else { return }
            fueASalud = false
            Task { await reintentar() }
        }
    }

    // MARK: - Acto 3 · la lectura

    @ViewBuilder
    private var leyendo: some View {
        Spacer(minLength: LiquidSpace.s800)

        OnbOverline(OnbCopy.conexionOverline)
        OnbTitular(ultimaEtapa ? OnbCopy.conexionCalculando : OnbCopy.conexionTitular)
            .padding(.top, LiquidSpace.s250)

        // El contador RUEDA (los dígitos nunca parpadean, ley del canvas de la sesión de fuerza).
        // Cuenta la ventana que se está leyendo, no la historia que resultó: el número honesto de
        // días TUYOS llega en el reveal, cuando ya se contó.
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
            Text(diasLeidos, format: .number)
                .font(LiquidType.valorL)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(LiquidColor.tinta900)
            Text(OnbCopy.conexionDias)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .padding(.top, LiquidSpace.s600)
        .animation(animContador, value: diasLeidos)
        .accessibilityElement(children: .combine)

        Text(OnbCopy.conexionProgreso(nombreEtapa, etapaN).teñida(nombreEtapa, con: tonoEtapa))
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, LiquidSpace.s250)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Se puede LEER barriendo (esconderla le quitaría el progreso a quien usa VoiceOver),
            // pero no se ANUNCIA: los 15 pasos salen por hitos (≤3, ver `anunciarHitos`). Quince
            // anuncios seguidos convierten una espera tranquila en una metralleta.
            .accessibilityLabel(Text(String(OnbCopy.conexionProgreso(nombreEtapa, etapaN).characters)))

        Spacer(minLength: LiquidSpace.s600)

        // La regla del juicio, en la última etapa: el momento en que el motor está calculando la
        // base es exactamente cuando explicar CONTRA QUÉ compara tiene sentido.
        if ultimaEtapa && !falloLectura {
            OnbCuerpo(OnbCopy.conexionRegla, tono: LiquidColor.tinta700)
                .liquidEntrada()
        }

        if falloLectura {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                OnbCuerpo(OnbCopy.errorSync, tono: LiquidColor.tinta900)
                LiquidGlassButton(OnbCopy.reintentar, variant: .primary, expands: true) {
                    Task { await reintentar() }
                }
                OnbSalidaTexto(titulo: OnbCopy.entrar, accion: onEntrar)
            }
            .padding(.top, LiquidSpace.s400)
        } else if techoAlcanzado {
            // El techo: la lectura sigue en el fondo, y la app deja de ser una sala de espera.
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                OnbCuerpo(OnbCopy.conexionLargo, tono: LiquidColor.tinta500)
                LiquidGlassButton(OnbCopy.entrar, variant: .glass, expands: true, action: onEntrar)
            }
            .padding(.top, LiquidSpace.s400)
        }
    }

    /// Sin movimiento, los dígitos no ruedan: aparecen puestos. El dato no se pierde.
    private var animContador: Animation? {
        reduceMotion ? nil : LiquidMotion.glassOut(LiquidMotion.quick)
    }

    /// Los días de la ventana ya recorridos. La ventana es 180 (lo que dice el titular).
    private var diasLeidos: Int { Int((avance * Double(Self.ventanaDias)).rounded()) }

    private var nombreEtapa: String { OnbEtapa.nombre(etapaClave) }
    private var tonoEtapa: Color { OnbEtapa.tono(etapaClave) }

    /// Los días que el titular promete leer. Es el mismo número que se le pasa a `sync(days:)`:
    /// si uno cambia, el otro miente.
    private static let ventanaDias = 180

    // MARK: - Acto 4 · la palabra

    @ViewBuilder
    private var lectura: some View {
        if let l = landing {
            switch l {
            case let .lectura(verdict, noches, dias):
                conVeredicto(verdict: verdict, noches: noches, dias: dias)
            case let .calibrando(noches, faltan, dias):
                calibrando(noches: noches, faltan: faltan, dias: dias)
            case .sinRitmoEnReposo:
                vistaSinRitmo
            case .sinDatos:
                vistaSinDatos
            }
        } else {
            vistaSinDatos
        }
    }

    // (a) Hay palabra.
    @ViewBuilder
    private func conVeredicto(verdict: Preparedness.Verdict, noches: Int, dias: Int) -> some View {
        let v = OnbVeredicto(verdict, noches: noches, prep: repo.todayPreparedness)

        Spacer(minLength: LiquidSpace.s800)

        if mostrarResto {
            OnbOverline(OnbCopy.lecturaOverline).liquidEntrada(index: 0)
            OnbTitular(OnbCopy.lecturaTitular)
                .padding(.top, LiquidSpace.s250)
                .liquidEntrada(index: 1)
        }

        // El bloque del reveal. La ⓘ es HERMANA del texto, nunca hija: dentro de un
        // `.accessibilityElement(children: .combine)` el botón deja de ser alcanzable (el
        // combinado se traga su acción), y es el ÚNICO gesto de curiosidad del acto. Así quedan
        // tres elementos para VoiceOver —la palabra (con el foco), la ⓘ, y el párrafo— en vez de
        // un bloque enorme con un botón muerto adentro.
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .lastTextBaseline, spacing: LiquidSpace.s200) {
                v.palabraText
                    .font(LiquidType.displayL)
                    .tracking(LiquidType.displayLTracking)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(mostrarPalabra ? 1 : 0)
                    // `opacity(0)` NO saca del árbol de accesibilidad: barriendo con VoiceOver, la
                    // palabra se podía leer antes de revelarse, que es justo lo que el silencio
                    // del guion compra.
                    .accessibilityHidden(!mostrarPalabra)
                    .accessibilityFocused($focoRevelado)
                if mostrarInfo {
                    Button(action: onContinuar) {
                        Image(systemName: "info.circle")
                            .font(LiquidType.infoGlifoTitular)
                            .foregroundStyle(v.tono)
                            .frame(minWidth: LiquidControl.hitTarget,
                                   minHeight: LiquidControl.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.liquidPress)
                    .transition(.opacity)
                    .accessibilityLabel(Text(OnbCopy.actaOverline))
                }
            }
            if mostrarResto {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    OnbCuerpo(v.subtitulo)
                    // La confianza («Confianza: 8 de 14 noches») es la MISMA línea que Hoy enseña
                    // al día siguiente, del mismo constructor. Sin ella, a quien lleva 8 noches se
                    // le presentaba la palabra con el mismo aplomo que a quien lleva 46.
                    if let confianza = v.confianza {
                        OnbCuerpo(confianza, tono: LiquidColor.tinta500)
                    }
                    OnbCuerpo(OnbCopy.lecturaHistoria(dias: dias, noches: noches),
                              tono: LiquidColor.tinta500)
                }
                .accessibilityElement(children: .combine)
                .liquidEntrada(index: 2)
            }
        }
        .padding(.top, LiquidSpace.s400)

        // El rótulo que enseña dónde vive el «por qué». Se va solo a los ~4 s o al primer toque:
        // es un puntero, no una tarjeta, y quedarse sería ruido en todas las visitas siguientes.
        if mostrarRotulo {
            OnbCuerpo(OnbCopy.lecturaRotuloInfo, tono: LiquidColor.tinta500)
                .padding(.top, LiquidSpace.s300)
                .transition(.opacity)
                .onTapGesture { esconderRotulo() }
        }

        Spacer(minLength: LiquidSpace.s600)

        // El perfil dejó de pedirse aquí: era una línea confirmable que solo existía en tres de
        // las cinco ramas, y faltaba justo donde no hay autollenado posible. Ahora se cobra al
        // salir del acta, igual para todas (FER-113).
        //
        // El CTA lleva al MISMO lugar que la ⓘ —el acta— y eso es correcto: lo que sigue a la
        // palabra es su explicación, se llegue por curiosidad o por seguir el flujo.
        if mostrarResto {
            LiquidGlassButton(OnbCopy.continuar, variant: .primary, expands: true,
                              action: onContinuar)
                .liquidEntrada(index: 3)
        }
    }

    // (b) Hay FC en reposo, pero la base es joven. Cero palabra, conteo honesto.
    @ViewBuilder
    private func calibrando(noches: Int, faltan: Int, dias: Int) -> some View {
        Spacer(minLength: LiquidSpace.s800)

        OnbOverline(OnbCopy.lecturaOverline).liquidEntrada(index: 0)
        OnbTitular(OnbCopy.calibrandoTitular)
            .padding(.top, LiquidSpace.s250)
            .liquidEntrada(index: 1)
            .accessibilityFocused($focoRevelado)
        OnbCuerpo(faltan > 0
                  ? OnbCopy.calibrandoCuerpo(dias: dias, noches: noches, meta: noches + faltan)
                  : OnbCopy.calibrandoCuerpoSinHoy(dias: dias, noches: noches))
            .padding(.top, LiquidSpace.s400)
            .liquidEntrada(index: 2)
        OnbCuerpo(OnbCopy.calibrandoPie, tono: LiquidColor.tinta500)
            .padding(.top, LiquidSpace.s300)
            .liquidEntrada(index: 3)

        Spacer(minLength: LiquidSpace.s600)

        LiquidGlassButton(OnbCopy.continuar, variant: .primary, expands: true, action: onContinuar)
            .liquidEntrada(index: 4)
    }

    // (c) El tope: llegaron señales, pero cero FC en reposo. Esperar no lo arregla, así que el
    // onboarding no lo promete — ofrece lo que SÍ funciona sin reloj.
    //
    // Pero la causa MÁS probable de esta rama es el permiso parcial (lo que el acto 2 advirtió:
    // «si me das solo una parte, me quedo mudo»), y con un solo CTA a Entrenar se mandaba a la
    // mitad de la app que no vino a buscar a alguien a quien un toque en Salud le arreglaría
    // todo. Por eso aquí hay puerta de vuelta: se nombra la sospecha y se ofrece Salud.
    @ViewBuilder
    private var vistaSinRitmo: some View {
        Group {
            Spacer(minLength: LiquidSpace.s800)

            OnbOverline(OnbCopy.encontreOverline).liquidEntrada(index: 0)
            OnbTitular(OnbCopy.sinFcTitular)
                .padding(.top, LiquidSpace.s250)
                .liquidEntrada(index: 1)
                .accessibilityFocused($focoRevelado)
            OnbCuerpo(OnbCopy.sinFcCuerpo1)
                .padding(.top, LiquidSpace.s400)
                .liquidEntrada(index: 2)
            OnbCuerpo(OnbCopy.sinFcCausa)
                .padding(.top, LiquidSpace.s300)
                .liquidEntrada(index: 3)
            OnbCuerpo(OnbCopy.sinFcCuerpo2)
                .padding(.top, LiquidSpace.s300)
                .liquidEntrada(index: 4)
            OnbCuerpo(OnbCopy.sinFcCuerpo3, tono: LiquidColor.tinta500)
                .padding(.top, LiquidSpace.s300)
                .liquidEntrada(index: 5)
        }

        Group {
            Spacer(minLength: LiquidSpace.s600)

            LiquidGlassButton(OnbCopy.sinFcCta, variant: .primary, expands: true, action: onEntrenar)
                .liquidEntrada(index: 6)
            // Segunda puerta, no segunda promesa: Entrenar sigue siendo lo que se ofrece de
            // primero, porque es lo único que funciona sin reloj pase lo que pase.
            LiquidGlassButton(OnbCopy.abrirSalud, variant: .glass, expands: true) { abrirSalud() }
                .padding(.top, LiquidSpace.s250)
                .liquidEntrada(index: 7)
            OnbSalidaTexto(titulo: OnbCopy.sinFcCtaSecundaria, accion: onEntrar)
                .liquidEntrada(index: 8)
        }
    }

    // (d) No llegó ni una fila. Negar la lectura y tener Salud vacío se ven idénticos desde aquí,
    // y da igual: el camino de salida es el mismo.
    @ViewBuilder
    private var vistaSinDatos: some View {
        Spacer(minLength: LiquidSpace.s800)

        OnbOverline(OnbCopy.encontreOverline).liquidEntrada(index: 0)
        OnbTitular(OnbCopy.sinDatosTitular)
            .padding(.top, LiquidSpace.s250)
            .liquidEntrada(index: 1)
            .accessibilityFocused($focoRevelado)
        OnbCuerpo(OnbCopy.sinDatosCuerpo1)
            .padding(.top, LiquidSpace.s400)
            .liquidEntrada(index: 2)
        OnbCuerpo(OnbCopy.sinDatosCuerpo2)
            .padding(.top, LiquidSpace.s300)
            .liquidEntrada(index: 3)

        Spacer(minLength: LiquidSpace.s600)

        LiquidGlassButton(OnbCopy.abrirSalud, variant: .primary, expands: true) { abrirSalud() }
            .liquidEntrada(index: 4)
        OnbSalidaTexto(titulo: OnbCopy.reintentar) { Task { await reintentar() } }
            .liquidEntrada(index: 5)
        // Sin esta salida el onboarding es un encierro: quien negó el permiso se quedaba con dos
        // botones que no llevan a la app. Ninguna rama del flujo puede ser un callejón, y menos
        // ésta, que es justo la de quien ya dijo que no.
        OnbSalidaTexto(titulo: OnbCopy.sinFcCtaSecundaria, accion: onEntrar)
            .liquidEntrada(index: 6)
    }

    // MARK: - La puerta a Salud

    /// Manda a la app Salud y deja anotado que hay que releer al volver (`fueASalud`). Es la
    /// mitad que faltaba del gesto: encender el permiso allá no sirve de nada si al regresar la
    /// app sigue enseñando el desenlace del intento anterior hasta que alguien toque un botón.
    @MainActor
    private func abrirSalud() {
        fueASalud = true
        if let url = URL(string: "x-apple-health://") { openURL(url) }
    }

    // MARK: - El reloj y el guion

    @MainActor
    private func correr() async {
        guard !corriendo else { return }
        corriendo = true

        // Volver del acta (que lleva «Atrás» a esta pantalla) reconstruye esta vista con su estado
        // en blanco, pero el desenlace ya se conoce: se restaura la escena revelada en vez de
        // volver a sincronizar y volver a encender. El encendido pasa UNA vez por instalación.
        if landing != nil {
            opacidadLectura = 0
            revelado = true
            mostrarPalabra = true
            mostrarInfo = true
            mostrarResto = true
            syncListo = true
            return
        }

        let inicio = arranque ?? Date()
        arranque = inicio

        // La sincronización arranca UNA vez y avisa cuando termina. Si el permiso quedó apagado,
        // `sync` regresa vacío de inmediato — y ese también es un desenlace legítimo (`.sinDatos`).
        if !syncListo {
            Task {
                _ = await health.sync(days: Self.ventanaDias)
                syncListo = true
            }
        }

        // El bucle del reloj: muestrea el progreso, respeta el piso, vigila el techo.
        while !Task.isCancelled {
            muestrear()
            let t = Date().timeIntervalSince(inicio)
            if t >= OnbGuion.techoLectura, !techoAlcanzado {
                withAnimation(LiquidMotion.glassOut(LiquidMotion.gentle)) { techoAlcanzado = true }
            }
            if syncListo && t >= OnbGuion.pisoLectura { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }

        if health.lastError != nil {
            withAnimation(LiquidMotion.glassOut(LiquidMotion.gentle)) { falloLectura = true }
            return
        }

        await encender(desenlace())
    }

    /// Vuelve a intentar la lectura **desde cero, con reloj nuevo**: un reintento explícito no es la
    /// continuación de la espera anterior, así que merece su propio piso y su propio techo. Quien
    /// fue a Salud, encendió los permisos y volvió no debe encontrarse «Esto va para largo» en el
    /// segundo cero por lo que tardó el intento pasado.
    @MainActor
    private func reintentar() async {
        // `landing` a nil es lo que hace que esto REINTENTE de verdad. Sin eso, `correr()` toma la
        // salida de «ya se conoce el desenlace» y sólo re-pinta la misma pantalla: el usuario iba a
        // Salud, encendía los permisos, volvía, tocaba «Reintentar» y no pasaba nada nunca.
        landing = nil
        revelado = false
        mostrarPalabra = false
        mostrarInfo = false
        mostrarResto = false
        opacidadLectura = 1
        falloLectura = false
        syncListo = false
        corriendo = false
        avance = 0
        // El reloj y el desfile arrancan limpios también: si no, el reintento hereda el techo
        // alcanzado, la última etapa del intento anterior y los hitos ya anunciados, y VoiceOver se
        // queda mudo durante toda la segunda lectura.
        techoAlcanzado = false
        ultimaEtapa = false
        etapaClave = nil
        etapaN = 1
        anunciados.removeAll()
        arranque = Date()
        await correr()
    }

    @MainActor
    private func muestrear() {
        guard let p = health.syncProgress else { return }
        let nuevo = Double(p.done) / Double(max(1, p.total))
        etapaClave = p.stageKey
        etapaN = min(p.total, p.done + 1)
        let esUltima = p.done >= p.total - 1
        if esUltima != ultimaEtapa {
            withAnimation(LiquidMotion.glassOut(LiquidMotion.gentle)) { ultimaEtapa = esUltima }
        }
        if nuevo != avance {
            avance = nuevo
            // La densidad NO la manda el avance de la descarga. Atarla a `done/total` haría que el
            // orbe se llenara por cuánto lleva bajando HealthKit, que es exactamente la mentira que
            // la cabecera de `AcumulacionSimulacion` prohíbe: la plenitud codificaría paciencia en
            // vez de evidencia. Y peor, se DESINFLABA delante del usuario al revelar, cuando la
            // evidencia real resultaba menor que la descarga.
            //
            // Durante la lectura la densidad se queda en lo que el acto 1 ya juntó (`densidadPromesa`)
            // y sube UNA sola vez, en el reveal, a `landing.densidadHonesta`. Lo que da la sensación
            // de convergencia en este acto es el MODO (`.convergencia` jala las motas al centro), no
            // el conteo: el movimiento cuenta el trabajo, el número cuenta los datos.
            if densidad < OnbGuion.densidadPromesa {
                let anim: Animation? = reduceMotion ? nil : LiquidMotion.ambient(LiquidMotion.gentle)
                withAnimation(anim) { densidad = OnbGuion.densidadPromesa }
            }
        }
        anunciarHitos(done: p.done, total: p.total)
    }

    /// ≤3 anuncios en todo el acto: arranque, mitad y última etapa. Ni uno por stage.
    @MainActor
    private func anunciarHitos(done: Int, total: Int) {
        func anunciar(_ hito: Int, _ texto: String) {
            guard !anunciados.contains(hito) else { return }
            anunciados.insert(hito)
            AccessibilityNotification.Announcement(texto).post()
        }
        if done == 0 { anunciar(0, OnbCopy.conexionTitular) }
        if done >= total / 2 { anunciar(1, String(OnbCopy.conexionProgreso(nombreEtapa, etapaN).characters)) }
        if done >= total - 1 { anunciar(2, OnbCopy.conexionCalculando) }
    }

    /// El desenlace, decidido por lo que ATERRIZÓ (nunca por el permiso: HealthKit no revela el
    /// de lectura, así que quien negó todo y quien concedió todo se ven idénticos desde ahí).
    @MainActor
    private func desenlace() -> OnboardingLanding {
        let cov = health.coverage
        return OnboardingLandingDecider.decidir(
            totalDays: cov?.totalDays ?? 0,
            diasPorMetrica: cov?.daysByMetric ?? [:],
            preparedness: repo.todayPreparedness)
    }

    /// El guion del encendido. Bajo Reduce Motion cada beat sobrevive, comprimido a un crossfade:
    /// lo que se congela es el movimiento, no el significado (y aquí no hay desplazamiento que
    /// congelar — la palabra siempre entra en fade puro).
    @MainActor
    private func encender(_ l: OnboardingLanding) async {
        let corto = reduceMotion
        func dur(_ d: Double) -> Double { corto ? LiquidEcosistemaMotion.reduceMotionCrossfade : d }
        func esperar(_ d: Double) async {
            guard d > 0 else { return }
            try? await Task.sleep(for: .seconds(d))
        }

        landing = l

        // 1 · Densificación final: el orbe se asienta en la densidad que la EVIDENCIA justifica,
        //     mientras el acto 3 se retira. Si la evidencia es poca, el orbe baja: es la corrección
        //     honesta, y es justo lo que impide que llenarse sea premio por esperar.
        withAnimation(.easeInOut(duration: dur(OnbGuion.densificacion))) {
            densidad = l.densidadHonesta
            opacidadLectura = 0
        }
        await esperar(dur(OnbGuion.densificacion))

        revelado = true   // el lienzo pasa a `.dentro`; la pantalla queda vacía sobre el orbe

        // 2 · Teñido. Solo existe donde hay color que revelar: en las otras tres ramas
        //     (`destinoTinte == nil`) eran 450 ms de espera con la pantalla vacía y nada
        //     cambiando. El SILENCIO de abajo, en cambio, se queda en las cuatro: sin palabra que
        //     revelar sigue siendo el aire correcto antes de una mala noticia.
        if l.revelaColor {
            withAnimation(.easeInOut(duration: dur(OnbGuion.tenido))) { tenido = 1 }
            await esperar(dur(OnbGuion.tenido))
        }

        // 3 · Silencio. Sin él la palabra llega pisando el color y no se lee como revelación.
        await esperar(corto ? 0 : OnbGuion.silencio)

        // 4 · La palabra, fade puro, cero desplazamiento.
        withAnimation(.easeIn(duration: dur(OnbGuion.palabra))) { mostrarPalabra = true }
        await esperar(dur(OnbGuion.palabra))
        await esperar(corto ? 0 : OnbGuion.esperaInfo)

        // 5 · La ⓘ, SOLA. Fijar el resto en este mismo runloop gastaba en nada los 400 ms de
        //     `esperaInfo`: la ⓘ nunca llegaba sola y el rótulo que la señala entraba con ella.
        withAnimation(LiquidMotion.glassOut(LiquidMotion.quick)) { mostrarInfo = true }
        await esperar(corto ? 0 : OnbGuion.esperaResto)

        // 6 · El resto, con el stagger de 60 ms del sistema (`liquidEntrada`). El foco de
        //     VoiceOver va DESPUÉS: moverlo antes de que el bloque exista lo deja sin destino.
        mostrarResto = true
        focoRevelado = true

        if case .lectura = l {
            withAnimation(LiquidMotion.glassOut(LiquidMotion.gentle)) { mostrarRotulo = true }
            await esperar(OnbGuion.rotulo)
            esconderRotulo()
        }
    }

    @MainActor
    private func esconderRotulo() {
        guard mostrarRotulo else { return }
        withAnimation(LiquidMotion.glassOut(LiquidMotion.quick)) { mostrarRotulo = false }
    }

}

// MARK: - La palabra, PRESTADA de Hoy

/// La palabra del veredicto tal cual la dice el héroe de Hoy. No hay copia local de ningún
/// `String(localized:)`: si `hero.title.*` cambia en el catálogo, cambia aquí en el mismo commit.
struct OnbVeredicto {
    let palabra: String
    let destacada: String
    let tono: Color
    let subtitulo: String
    /// «Confianza: 8 de 14 noches», mientras la base es joven; `nil` con la base firme. Se
    /// destructuraba y se TIRABA: al de 8 noches se le presentaba la palabra con el mismo aplomo
    /// que al de 46, y Hoy sí se la enseña al día siguiente. Cero copy nuevo — es la misma cadena.
    let confianza: String?

    init(_ verdict: Preparedness.Verdict, noches: Int, prep: Preparedness.Read?) {
        let hero = LiquidHoyBuilder.veredicto(verdict, nights: noches, prep: prep)
        switch hero {
        case let .veredicto(title, highlight, tone, subtitle, confidence):
            palabra = title
            destacada = highlight
            tono = tone
            subtitulo = subtitle
            confianza = confidence
        case let .demotado(_, title, subtitle):
            // Inalcanzable: `veredicto(_:)` siempre devuelve el caso con palabra. La rama existe
            // para no tener un `fatalError` en el camino que le muestra la app al usuario.
            palabra = title
            destacada = title
            tono = LiquidColor.tinta900
            subtitulo = subtitle
            confianza = nil
        }
    }

    /// La palabra con su sílaba destacada en el tono del veredicto, igual que en el héroe.
    var palabraText: Text {
        guard let range = palabra.range(of: destacada, options: .backwards) else {
            return Text(palabra).foregroundColor(LiquidColor.tinta900)
        }
        return Text(palabra[..<range.lowerBound]).foregroundColor(LiquidColor.tinta900)
            + Text(palabra[range]).foregroundColor(tono)
            + Text(palabra[range.upperBound...]).foregroundColor(LiquidColor.tinta900)
    }
}

// MARK: - Las 15 etapas de la sincronización

/// El nombre y el tono de cada etapa de `HealthKitBridge.sync`. Solo SIETE llevan hue: las que
/// tienen identidad de señal en el resto de la app. Las otras ocho van en tinta — teñirlas todas
/// convertiría el progreso en un arcoíris y le quitaría el significado al color.
enum OnbEtapa {

    static func nombre(_ clave: String?) -> String {
        switch clave {
        case "resting_hr":        return String(localized: "onb.etapa.rhr", defaultValue: "Your resting heart")
        case "avg_hr":            return String(localized: "onb.etapa.avghr", defaultValue: "Your daily rhythm")
        case "max_hr":            return String(localized: "onb.etapa.maxhr", defaultValue: "Your peak rhythm")
        case "hrv":               return String(localized: "onb.etapa.hrv", defaultValue: "Your variability")
        case "spo2":              return String(localized: "onb.etapa.spo2", defaultValue: "Your oxygen")
        case "resp_rate":         return String(localized: "onb.etapa.resp", defaultValue: "Your breathing")
        case "steps":             return String(localized: "onb.etapa.pasos", defaultValue: "Your steps")
        case "active_kcal":       return String(localized: "onb.etapa.gasto", defaultValue: "Your burn")
        case "basal_kcal":        return String(localized: "onb.etapa.basal", defaultValue: "Your resting burn")
        case "vo2max":            return String(localized: "onb.etapa.vo2", defaultValue: "Your VO₂ max")
        case "skin_temp":         return String(localized: "onb.etapa.temp", defaultValue: "Your temperature")
        case "sleep":             return String(localized: "onb.etapa.sueno", defaultValue: "Your sleep")
        case "workouts":          return String(localized: "onb.etapa.entrenos", defaultValue: "Your workouts")
        case "hr_apple_workouts": return String(localized: "onb.etapa.pulso", defaultValue: "Your training pulse")
        default:                  return String(localized: "onb.etapa.guardando", defaultValue: "Saving")
        }
    }

    static func tono(_ clave: String?) -> Color {
        switch clave {
        case "resting_hr": return LiquidColor.rosa
        case "hrv":        return LiquidColor.cian
        case "resp_rate":  return LiquidColor.azul
        case "steps":      return LiquidColor.teal
        case "skin_temp":  return LiquidColor.doradoTemp
        case "sleep":      return LiquidColor.indigo
        // El ámbar de dato no alcanza AA a este tamaño: su hermano de lectura sí (mismo criterio
        // que `LiquidSheetHeader.tonoTexto` aplica dentro del paquete).
        case "workouts":   return LiquidColor.atencionTexto
        default:           return LiquidColor.tinta500
        }
    }
}

extension AttributedString {
    /// Tiñe la primera aparición de `fragmento`. Es cómo el nombre de la etapa lleva su identidad
    /// dentro de una frase que sigue siendo UNA sola cadena localizable (partir el formato en
    /// trozos rompería cualquier traducción que reordene).
    func teñida(_ fragmento: String, con tono: Color) -> AttributedString {
        var copia = self
        if let r = copia.range(of: fragmento) { copia[r].foregroundColor = tono }
        return copia
    }
}
