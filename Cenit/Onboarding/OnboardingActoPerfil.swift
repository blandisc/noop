import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Acto 5 · el perfil (FER-113)
//
// Cuatro datos que el motor necesita de ti y que Apple Salud casi siempre ya sabe: edad, sexo,
// peso y estatura. La EDAD, ella sola, manda tus zonas de frecuencia cardiaca (`Profile.hrMax` =
// 208 − 0.7·edad, Tanaka, la misma fórmula que Ajustes: el sexo NO entra), y sexo, peso y estatura
// afinan el gasto de cada entrenamiento.
//
// Lo que este acto NO alimenta: la base del veredicto. Ésa sale de tu historial de FC en reposo,
// y ninguno de estos cuatro datos la toca — por eso el overline dejó de decir «para tu base».
//
// **Por qué es un acto propio y no una línea dentro del reveal.** FER-109 lo había convertido en
// una línea confirmable (`OnbPerfilLinea`), y esa línea solo existía en TRES de las cinco ramas:
// faltaba justo en `.sinDatos` y en la salida de «Ahora no», que son las dos ramas donde no hay
// autollenado posible — o sea, las únicas donde los cuatro valores se quedaban en el default de
// fábrica sin que nadie se enterara. Como paso propio, el perfil es la ÚLTIMA parada común de
// todas las ramas: se pasa por aquí se llegue por donde se llegue. Por eso el acto sabe a dónde
// va después (`OnbPerfilLuego`) en vez de suponerlo, y su CTA es literalmente el botón que la
// persona apretó una pantalla antes.
//
// Tres reglas de este acto:
//
//   · **La procedencia se VE, campo por campo.** «Desde Apple Salud» / «Lo pusiste tú» / «Lo puse
//     yo». Sin ese sello, un dato real y un default de fábrica se ven idénticos, que es
//     exactamente el defecto que este issue arregla.
//
//   · **Lo que el usuario edita GANA.** El autollenado corre UNA vez por onboarding, y su sello
//     vive en el wizard (no aquí): volver desde el acta reconstruye este acto, y un segundo
//     autollenado pisaría lo que la persona acaba de corregir.
//
//   · **Fuera de rango se DESCARTA, no se recorta.** Un peso de 12 kg en Salud es un dato
//     equivocado, no un peso bajo: recortarlo a 30 kg inventaría una medición que nadie hizo.
//
// Tipografía: el titular (22) y la FC máxima derivada (22) son lo más grande de la pantalla. La
// única talla de 30 en todo el flujo sigue siendo la palabra del veredicto, en el acto 4.

// MARK: - A dónde va el perfil cuando termina

/// La salida del acto, fijada por el wizard al entrar (`irAPerfil`). Quien tocó «Ir a Entrenar»
/// vuelve a encontrar «Ir a Entrenar» al pie de este paso, no un «Continuar» que lo lleve a otro
/// lado: el perfil se mete en el camino, no lo cambia.
enum OnbPerfilLuego: Hashable {
    /// El camino con veredicto: todavía quedan el acta y el ciclo.
    case acta
    /// Ya no hay nada más que explicar: entrar a la app.
    case entrar
    /// Igual que `entrar`, aterrizando en Entrenar (la mitad que sí funciona sin reloj).
    case entrenar
}

// MARK: - Los cuatro campos, sus rangos y su procedencia

enum OnbCampoPerfil: Hashable { case edad, sexo, peso, estatura }

/// De dónde salió el valor que se está viendo.
enum OnbProcedencia { case salud, tuyo, arranque }

/// Los rangos que este formulario admite, en UN solo lugar: los mismos que topan cada `Stepper` y
/// los que validan el autollenado. Separados, uno podía aceptar lo que el otro rechaza.
enum OnbPerfilRango {
    static let edad = 13...100
    static let pesoKg: ClosedRange<Double> = 30...250
    static let estaturaCm: ClosedRange<Double> = 120...230
    /// Los tres valores que `ProfileStore.sex` entiende (y los únicos que Apple Salud entrega).
    static let sexos = ["male", "female", "nonbinary"]
}

/// Lo que Apple Salud propone, ya filtrado por los rangos del formulario. Puro (sin HealthKit ni
/// SwiftUI) para poder probarlo: ver `OnboardingPerfilTests`.
struct OnbPerfilDeSalud: Equatable {
    var edad: Int?
    var sexo: String?
    var pesoKg: Double?
    var estaturaCm: Double?

    init(edad: Int?, sexo: String?, pesoKg: Double?, estaturaCm: Double?) {
        self.edad = Self.dentro(edad, OnbPerfilRango.edad)
        self.pesoKg = Self.dentro(pesoKg, OnbPerfilRango.pesoKg)
        self.estaturaCm = Self.dentro(estaturaCm, OnbPerfilRango.estaturaCm)
        // Un sexo que el selector no tiene lo dejaría sin ningún segmento marcado.
        if let sexo, OnbPerfilRango.sexos.contains(sexo) {
            self.sexo = sexo
        } else {
            self.sexo = nil
        }
    }

    private static func dentro<T: Comparable>(_ valor: T?, _ rango: ClosedRange<T>) -> T? {
        guard let valor, rango.contains(valor) else { return nil }
        return valor
    }
}

/// Lo que dejó el autollenado: qué campos llenó Apple Salud y con qué valores quedó el perfil.
/// Lo que hoy no coincida con este sello lo puso la persona, y por eso gana.
///
/// Vive en el WIZARD (llega como `@Binding`) y no en el acto: volver desde el acta reconstruye el
/// acto con su estado en blanco, y sin el sello afuera el autollenado correría una segunda vez y
/// pisaría la corrección que se acaba de hacer.
struct OnbPerfilSello: Equatable {
    var deSalud: Set<OnbCampoPerfil>
    var edad: Int
    var sexo: String
    var pesoKg: Double
    var estaturaCm: Double
}

// MARK: - El acto

struct OnbActoPerfil: View {

    @Binding var sello: OnbPerfilSello?
    let luego: OnbPerfilLuego
    /// El desenlace del reveal, para saber si el cuerpo puede apoyarse en una palabra ya dada.
    /// `nil` en la rama de «Ahora no», donde el encendido nunca corrió.
    let landing: OnboardingLanding?
    /// ¿Se llegó por «Ahora no»? Lo sabe el wizard (`perfilAtras == .salida`), no este acto: sin
    /// eso, la nota le echaría a Apple la culpa de una decisión que tomó la persona.
    let desdeSalida: Bool
    let onAtras: () -> Void
    let onContinuar: () -> Void

    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var health: HealthKitBridge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        // Los `Group` son puramente estructurales (SwiftUI tope los hijos de un builder en 10); son
        // transparentes para el layout, así que cada pieza sigue siendo hermana directa del `VStack`
        // del shell y el `Spacer` sigue empujando el CTA al pie.
        OnbShell {
            Group {
                OnbAtras(accion: onAtras)

                OnbOverline(OnbCopy.perfilOverline)
                    .padding(.top, LiquidSpace.s250)
                OnbTitular(OnbCopy.perfilTitular)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(cuerpo)
                    .padding(.top, LiquidSpace.s300)
            }

            Group {
                OnbTarjeta {
                    campoEdad
                    OnbHairline()
                    campoSexo
                    OnbHairline()
                    campoPeso
                    OnbHairline()
                    campoEstatura
                }
                .padding(.top, LiquidSpace.s600)

                OnbCuerpo(nota, tono: LiquidColor.tinta500)
                    .padding(.top, LiquidSpace.s400)

                fcMaxima
                    .padding(.top, LiquidSpace.s600)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(cta, variant: .primary, expands: true, action: onContinuar)
            }
        }
        .task { await autollenar() }
    }

    // MARK: - Los cuatro campos

    private var campoEdad: some View {
        Stepper(value: $profile.age, in: OnbPerfilRango.edad) {
            fila(OnbCopy.perfilEdad, valor: profile.age.formatted(), campo: .edad)
        }
        .tint(LiquidColor.tinta700)
        // El `Stepper` se queda como UN elemento ajustable (nada de `.combine` encima: eso le
        // quitaría el gesto de subir/bajar a VoiceOver). Etiqueta y valor van explícitos para que
        // se lea «Edad, 34, desde Apple Salud» en vez de un número suelto.
        .accessibilityLabel(Text(OnbCopy.perfilEdad))
        .accessibilityValue(Text(lectura(profile.age.formatted(), .edad)))
    }

    private var campoSexo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(OnbCopy.perfilSexo)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(OnbCopy.perfilSexo, selection: $profile.sex) {
                ForEach(OnbPerfilRango.sexos, id: \.self) { key in
                    Text(Self.etiquetaSexo(key)).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text(OnbCopy.perfilSexo))
            marca(.sexo)
        }
    }

    private var campoPeso: some View {
        Stepper(value: $profile.weightKg, in: OnbPerfilRango.pesoKg, step: 0.5) {
            fila(OnbCopy.perfilPeso, valor: pesoTexto, campo: .peso)
        }
        .tint(LiquidColor.tinta700)
        .accessibilityLabel(Text(OnbCopy.perfilPeso))
        .accessibilityValue(Text(lectura(pesoTexto, .peso)))
    }

    private var campoEstatura: some View {
        Stepper(value: $profile.heightCm, in: OnbPerfilRango.estaturaCm, step: 1) {
            fila(OnbCopy.perfilEstatura, valor: estaturaTexto, campo: .estatura)
        }
        .tint(LiquidColor.tinta700)
        .accessibilityLabel(Text(OnbCopy.perfilEstatura))
        .accessibilityValue(Text(lectura(estaturaTexto, .estatura)))
    }

    private var pesoTexto: String {
        UnitFormatter.massFromKilograms(profile.weightKg, system: unitSystem)
    }
    private var estaturaTexto: String {
        UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem)
    }

    /// La cara de un campo: etiqueta, valor y de dónde salió. El valor va en `valorM` (17) y no en
    /// `valorL` (22) a propósito: lo más grande de esta pantalla son el titular y la FC máxima que
    /// se deriva, y cuatro números de 22 competirían con los dos.
    private func fila(_ etiqueta: String, valor: String, campo: OnbCampoPerfil) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s300) {
                Text(etiqueta)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
                Spacer(minLength: 0)
                Text(valor)
                    .font(LiquidType.valorM)
                    .foregroundStyle(LiquidColor.tinta900)
            }
            marca(campo)
        }
    }

    /// El sello de procedencia del campo. Va en la voz de lectura (escala con Dynamic Type) y no
    /// en versalitas: son tres palabras que se leen, no una etiqueta de chrome.
    private func marca(_ campo: OnbCampoPerfil) -> some View {
        Text(textoMarca(campo))
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Lo que se deriva

    /// Para qué sirvieron los cuatro datos, en un número que se mueve con ellos: cambiar la edad
    /// mueve la FC máxima delante de los ojos. La cita («Tanaka») es la misma que muestra Ajustes.
    private var fcMaxima: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            OnbOverline(OnbCopy.perfilFcMax)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                Text(profile.hrMax, format: .number)
                    .font(LiquidType.valorL)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(LiquidColor.tinta900)
                Text(OnbCopy.fcMaxUnidad)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            .animation(reduceMotion ? nil : LiquidMotion.glassOut(LiquidMotion.quick),
                       value: profile.hrMax)
            OnbCuerpo(OnbCopy.perfilFcMaxNota, tono: LiquidColor.tinta500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy que depende de la rama

    /// El cuerpo se apoya en la palabra SOLO cuando la hay. En `.calibrando`, sin FC en reposo, sin
    /// datos y en «Ahora no» no hubo veredicto que leer, así que decir «tu palabra ya salió» sería
    /// hablarle de algo que la persona no vio.
    private var cuerpo: String {
        if case .lectura = landing { return OnbCopy.perfilCuerpo }
        return OnbCopy.perfilCuerpoSinLectura
    }

    /// La nota cambia con lo que DE VERDAD pasó, en tres ramas: decirle «lo que Apple Salud sabía
    /// ya está puesto» a quien nunca conectó Salud sería una mentira, y decirle «Apple Salud no me
    /// dio ninguno de estos datos» a quien contestó «Ahora no» le carga a Apple una decisión suya.
    /// El orden importa: lo que Salud SÍ llenó manda sobre de dónde se venía.
    private var nota: String {
        if !(sello?.deSalud.isEmpty ?? true) { return OnbCopy.perfilNotaSalud }
        return desdeSalida ? OnbCopy.perfilNotaSinPermiso : OnbCopy.perfilNotaSinSalud
    }

    private var cta: String {
        switch luego {
        case .acta:     return OnbCopy.continuar
        case .entrar:   return OnbCopy.entrar
        case .entrenar: return OnbCopy.sinFcCta
        }
    }

    /// Sexo con la etiqueta del catálogo (misma que usaba el editor de FER-109).
    static func etiquetaSexo(_ raw: String) -> String {
        switch raw {
        case "male":   return String(localized: "Male")
        case "female": return String(localized: "Female")
        default:       return String(localized: "Other")
        }
    }

    // MARK: - Procedencia

    private func textoMarca(_ campo: OnbCampoPerfil) -> String {
        switch procedencia(campo) {
        case .salud:    return OnbCopy.perfilMarcaSalud
        case .tuyo:     return OnbCopy.perfilMarcaTuyo
        case .arranque: return OnbCopy.perfilMarcaMio
        }
    }

    /// Lo que la persona editó GANA sobre lo que trajo Salud. Antes del autollenado (el primer
    /// cuadro) los cuatro valores son el default de fábrica, y eso es exactamente lo que dicen.
    private func procedencia(_ campo: OnbCampoPerfil) -> OnbProcedencia {
        guard let s = sello else { return .arranque }
        if editado(campo, contra: s) { return .tuyo }
        return s.deSalud.contains(campo) ? .salud : .arranque
    }

    private func editado(_ campo: OnbCampoPerfil, contra s: OnbPerfilSello) -> Bool {
        switch campo {
        case .edad:     return profile.age != s.edad
        case .sexo:     return profile.sex != s.sexo
        case .peso:     return profile.weightKg != s.pesoKg
        case .estatura: return profile.heightCm != s.estaturaCm
        }
    }

    /// Lo que VoiceOver lee como valor del campo: el número y de dónde salió.
    private func lectura(_ valor: String, _ campo: OnbCampoPerfil) -> String {
        "\(valor), \(textoMarca(campo))"
    }

    // MARK: - El autollenado

    /// Prellena el perfil desde Apple Salud campo por campo (parcial es lo normal: Salud suele
    /// tener sexo y fecha de nacimiento, y no siempre peso o estatura) y deja el sello con lo que
    /// vino de allá. Sin permiso concedido no hay nada que preguntar, y ésa es precisamente la
    /// rama en la que los cuatro valores son el default de fábrica.
    ///
    /// Corre UNA sola vez por onboarding, y el sello es lo que lo garantiza. El costo de esa
    /// decisión: quien encienda el permiso en Salud DESPUÉS de haber pasado por este acto ya no
    /// recibe el prellenado (sus cuatro campos siguen diciendo, con la verdad, «Lo puse yo»).
    /// Prefiero ese hueco a la alternativa, que es un segundo autollenado capaz de borrar lo que
    /// la persona acaba de escribir.
    @MainActor
    private func autollenar() async {
        guard sello == nil else { return }
        var deSalud: Set<OnbCampoPerfil> = []
        if health.auth == .authorized {
            let c = await health.readProfileCharacteristics()
            let s = OnbPerfilDeSalud(edad: c.age, sexo: c.sex,
                                     pesoKg: c.weightKg, estaturaCm: c.heightCm)
            if let v = s.edad { profile.age = v; deSalud.insert(.edad) }
            if let v = s.sexo { profile.sex = v; deSalud.insert(.sexo) }
            if let v = s.pesoKg { profile.weightKg = v; deSalud.insert(.peso) }
            if let v = s.estaturaCm { profile.heightCm = v; deSalud.insert(.estatura) }
        }
        sello = OnbPerfilSello(deSalud: deSalud, edad: profile.age, sexo: profile.sex,
                               pesoKg: profile.weightKg, estaturaCm: profile.heightCm)
    }
}

// MARK: - Preview

#if DEBUG
private struct OnbPerfilPreview: View {
    @State private var model = AppModel.preview
    /// Nil = el acto corre su autollenado. En preview no hay permiso de Salud, así que se ve la
    /// rama que este issue vino a arreglar: los cuatro campos en su valor de arranque.
    @State private var sello: OnbPerfilSello?

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            OnbActoPerfil(sello: $sello, luego: .acta,
                          landing: .lectura(verdict: .full, noches: 22, diasHistoria: 180),
                          desdeSalida: false, onAtras: {}, onContinuar: {})
        }
        .environmentObject(model.profile)
        .environmentObject(HealthKitBridge(repo: model.repo,
                                           appleDeviceId: "preview-apple",
                                           noopDeviceId: "preview"))
        .frame(width: 390, height: 800)
    }
}

#Preview("Onboarding · perfil") { OnbPerfilPreview() }
#endif
