import SwiftUI
import CenitDesign

// MARK: - Piezas del onboarding en siete actos (FER-109 · FER-113)
//
// El vocabulario visual compartido por los siete actos + el copy es-MX en un solo lugar.
//
// Tres reglas del acto que viven aquí, y no en cada pantalla, para que no puedan divergir:
//
//   · **Un solo elemento a 30 pt en TODO el flujo: la palabra del veredicto** (acto 4). Todo lo
//     demás vive en `OnbTitular` (displayS, 22) hacia abajo. Por eso no existe aquí ningún
//     titular grande: si hiciera falta uno, sería el segundo, y el reveal dejaría de ser único.
//
//   · **El cuerpo de lectura ESCALA.** `LiquidType.cuerpo` es tamaño fijo (12.5) y este flujo es
//     el más denso en texto corrido de la app: a xxxLarge se quedaba clavado mientras el titular
//     crecía. Se usa la base publicada (`LiquidType.cuerpoLecturaBase`) escalada con
//     `@ScaledMetric`, que es justo el patrón que el token documenta.
//
//   · **Cero ámbar/rojo en cualquier indicador de confianza.** La confianza no es buena ni mala,
//     y el ámbar ya significa «una señal fuera de rango» en Hoy. Los conteos de noches y de días
//     hablan en tinta, siempre.
//
// El copy va con claves simbólicas (`onb.*`) + `defaultValue` en inglés, como `hero.title.*`:
// el catálogo es `sourceLanguage: en` y una literal en español se volvería una clave que nunca
// traduce de vuelta.

// MARK: - El guion (tiempos)

/// Los tiempos de la coreografía del onboarding, en un solo lugar — hermano de
/// `AcumulacionSimulacion.Guion` (que fija los de la FÍSICA) y de `LiquidEntradaMotion` (los de la
/// entrada de la app). Las curvas siguen siendo las del contrato (`LiquidMotion`); lo que vive
/// aquí es el compás de esta escena, que ninguna otra pantalla comparte.
enum OnbGuion {
    /// Acto 1: la materia se junta sola mientras lees la promesa, de 0 a `densidadPromesa`.
    /// No es evidencia (todavía no hay ninguna): es el campo presentándose.
    static let acumulacionPromesa: Double = 3.2
    static let densidadPromesa: Double = 0.5

    /// Acto 3 · el reloj. **Piso**: aunque la sincronización acabe en 400 ms, la lectura de 180
    /// días no puede parecer un parpadeo. **Techo**: pasados 20 s aparece la salida, porque a
    /// esa altura la espera dejó de ser una coreografía y pasó a ser un encierro.
    static let pisoLectura: Double = 2.5
    static let techoLectura: Double = 20

    /// El encendido (acto 3 → 4), en orden: densificación final, teñido, SILENCIO, la palabra en
    /// fade puro (cero desplazamiento), la ⓘ, y el resto con el stagger del sistema.
    static let densificacion: Double = 1.2
    static let tenido: Double = 0.45
    static let silencio: Double = 0.30
    static let palabra: Double = LiquidEcosistemaMotion.palabraDur
    static let esperaInfo: Double = 0.40
    /// El aire ENTRE la ⓘ y el resto del acto. Sin él los dos beats caían en el mismo cuadro:
    /// `mostrarInfo` y `mostrarResto` se fijaban en el mismo runloop, así que los 400 ms que
    /// `esperaInfo` compró para que la ⓘ llegara SOLA se gastaban en nada — entraba con el
    /// titular, el subtítulo y el rótulo que la señala, y el gesto se perdía en el montón.
    static let esperaResto: Double = 0.35

    /// El rótulo que enseña la ⓘ se va solo (o al primer toque).
    static let rotulo: Double = 4
}

// MARK: - Copy

/// El copy del onboarding. Un solo lugar: los actos solo lo consumen.
///
/// La palabra del veredicto NO está aquí a propósito — sale de `LiquidHoyBuilder.veredicto`,
/// que es la misma función que la usa en Hoy. Si viviera aquí, la pantalla de bienvenida y la
/// de la mañana podrían discrepar sobre lo mismo.
enum OnbCopy {

    // Acto 1 · Promesa
    static var promesaTitular: String {
        String(localized: "onb.1.titular",
               defaultValue: "Your body has been keeping the record. Nobody has read it.")
    }
    static var promesaCuerpo: String {
        String(localized: "onb.1.cuerpo",
               defaultValue: "I read it every morning and tell you, in one word, how you woke up. And when you train, I carry your routine and add weight the day it's due.")
    }
    static var promesaPrivacidad: String {
        String(localized: "onb.1.privacidad",
               defaultValue: "No account, no email, no cloud. Everything is computed on your iPhone. Put it in airplane mode and check right now.")
    }

    // Acto 2 · Permiso
    static var permisoTitular: String {
        String(localized: "onb.2.titular", defaultValue: "To read it, I need you to open the door")
    }
    static var permisoCuerpo: String {
        String(localized: "onb.2.cuerpo",
               defaultValue: "I don't go out looking for anything. Apple has to hand me your signals, and only you can authorize that.")
    }
    static var permisoGrupoSostiene: String {
        String(localized: "onb.2.grupo.sostiene", defaultValue: "The one that holds it all up")
    }
    static var permisoGrupoVotan: String {
        String(localized: "onb.2.grupo.votan", defaultValue: "The other vote")
    }
    /// El centinela: temperatura y respiración cuentan UN voto, y solo el día que se salen juntas
    /// (`Preparedness`: `sentinelOut = tempHigh && respHigh`). Por eso son un grupo, no dos filas.
    static var permisoGrupoPar: String {
        String(localized: "onb.2.grupo.par", defaultValue: "The two that only count together")
    }
    static var permisoGrupoFuera: String {
        String(localized: "onb.2.grupo.fuera", defaultValue: "The one that no longer comes in")
    }
    static var permisoRhr: String {
        String(localized: "onb.2.rhr.nombre", defaultValue: "Resting heart rate")
    }
    static var permisoRhrGlosa: String {
        String(localized: "onb.2.rhr.glosa", defaultValue: "The backbone. Without it there is no reading.")
    }
    static var permisoSueno: String { String(localized: "onb.2.sueno.nombre", defaultValue: "Sleep") }
    static var permisoSuenoGlosa: String {
        String(localized: "onb.2.sueno.glosa",
               defaultValue: "How much you slept against the hours a body asks for, and how even it was.")
    }
    static var permisoTemp: String {
        String(localized: "onb.2.temp.nombre", defaultValue: "Skin temperature")
    }
    static var permisoTempGlosa: String {
        String(localized: "onb.2.temp.glosa",
               defaultValue: "It rises when something is brewing. On its own it doesn't count.")
    }
    static var permisoVfcNoche: String {
        String(localized: "onb.2.vfcnoche.nombre", defaultValue: "Night variability")
    }
    static var permisoVfcNocheGlosa: String {
        String(localized: "onb.2.vfcnoche.glosa",
               defaultValue: "It weighs half, and only when the night came with enough detail.")
    }
    static var permisoResp: String { String(localized: "onb.2.resp.nombre", defaultValue: "Breathing") }
    static var permisoRespGlosa: String {
        String(localized: "onb.2.resp.glosa",
               defaultValue: "It speeds up when something is coming on. On its own it doesn't count either.")
    }
    /// El pie del par: lo único que convierte dos filas en un voto.
    static var permisoParPie: String {
        String(localized: "onb.2.par.pie",
               defaultValue: "The day both step out together, they add one vote. Either one on its own stays a heads-up.")
    }
    static var permisoVfcDia: String {
        String(localized: "onb.2.vfcdia.nombre", defaultValue: "All-day variability")
    }
    static var permisoVfcDiaGlosa: String {
        String(localized: "onb.2.vfcdia.glosa",
               defaultValue: "It left the vote: it's a whole-day measure and it came out worse than your heart's.")
    }
    static var permisoNotaFuerte: String {
        String(localized: "onb.2.nota.fuerte", defaultValue: "Look for “Turn On All” and switch it on.")
    }
    static var permisoNotaCuerpo: String {
        String(localized: "onb.2.nota.cuerpo",
               defaultValue: "Apple opens this permission switched off. If you give me only part of it, I go mute and I can't tell you which piece is missing.")
    }

    // Acto 3 · Conexión
    static var conexionOverline: String { String(localized: "onb.3.overline", defaultValue: "Connecting") }
    static var conexionTitular: String {
        String(localized: "onb.3.titular", defaultValue: "I'm reading your last 180 days")
    }
    static var conexionDias: String { String(localized: "onb.3.dias", defaultValue: "days read") }
    /// El sueño NO se compara contra tu historia: su eje mide contra un PISO poblacional fijo
    /// (`Preparedness`: `sleepNeedFloorMin`, `orientedZ: nil`). Decir «tus señales contra tu propio
    /// rango» a secas era falso para la mitad del veredicto.
    static var conexionRegla: String {
        String(localized: "onb.3.regla",
               defaultValue: "Every morning I compare your heart against your own range, the one that comes out of your nights. Your sleep I measure differently: against the hours any body asks for.")
    }
    static var conexionCalculando: String {
        String(localized: "onb.3.calculando", defaultValue: "Computing your baseline")
    }
    static var conexionLargo: String {
        String(localized: "onb.3.largo",
               defaultValue: "This is going to take a while. I'll keep reading while you use the app.")
    }
    /// `%@` = la etapa · `%lld` = cuál de las 15.
    static func conexionProgreso(_ etapa: String, _ n: Int) -> AttributedString {
        let fmt = String(localized: "onb.3.progreso", defaultValue: "Reading: %@ · %lld of 15")
        return AttributedString(String(format: fmt, etapa, n))
    }

    // Acto 4 · Lectura
    static var lecturaOverline: String {
        String(localized: "onb.4.overline.lectura", defaultValue: "Your first reading")
    }
    static var lecturaTitular: String {
        String(localized: "onb.4.titular.lectura", defaultValue: "I've read it. This is what it says today.")
    }
    static func lecturaHistoria(dias: Int, noches: Int) -> String {
        String(format: String(localized: "onb.4.historia",
                              defaultValue: "I already have your %lld days of history, and %lld nights with the watch on."),
               dias, noches)
    }
    static var lecturaRotuloInfo: String {
        String(localized: "onb.4.rotulo.info",
               defaultValue: "Want to see how I got to that word? It lives right here, always.")
    }
    static var calibrandoTitular: String {
        String(localized: "onb.4.titular.calibrando", defaultValue: "I can't read you yet")
    }
    static func calibrandoCuerpo(dias: Int, noches: Int, meta: Int) -> String {
        String(format: String(localized: "onb.4.calibrando.cuerpo",
                              defaultValue: "I already have your %lld days of history, but I've got %lld nights with the watch on. Your word arrives as soon as I gather %lld."),
               dias, noches, meta)
    }
    /// El otro `.calibrando`: la base YA está (`faltan == 0`) y aun así el motor no se atreve —
    /// típicamente porque todavía no existe la fila de HOY. Decirle «tu palabra llega en cuanto
    /// junte 60 noches» a quien ya tiene 60 es prometerle algo que ya ocurrió, y es el estado
    /// normal de quien abre la app en la mañana antes de que Apple publique su FC en reposo.
    static func calibrandoCuerpoSinHoy(dias: Int, noches: Int) -> String {
        String(format: String(localized: "onb.4.calibrando.cuerpo.sinhoy",
                              defaultValue: "I already have your %lld days of history and your %lld nights. What I still don't have is today: your watch hasn't published this morning's resting heart rate yet."),
               dias, noches)
    }
    static var calibrandoPie: String {
        String(localized: "onb.4.calibrando.pie", defaultValue: "I'm not going to make up a verdict in the meantime.")
    }
    static var encontreOverline: String {
        String(localized: "onb.4.overline.encontre", defaultValue: "What I found")
    }
    static var sinFcTitular: String {
        String(localized: "onb.4.titular.sinfc", defaultValue: "I can't read you")
    }
    static var sinFcCuerpo1: String {
        String(localized: "onb.4.sinfc.1",
               defaultValue: "I can't find your resting heart rate. Without it I can't give you the morning reading: it's the signal the whole judgement stands on.")
    }
    /// La causa POSIBLE, nombrada. La rama más probable de `.sinRitmoEnReposo` es el permiso
    /// parcial —lo que el acto 2 advirtió: «si me das solo una parte, me quedo mudo»—, y el acto
    /// solo ofrecía Entrenar: mandaba a la mitad de la app que no vino a buscar a alguien a quien
    /// un toque en Salud le arreglaría todo. HealthKit no revela el permiso de lectura, así que
    /// esto se dice como sospecha («casi siempre»), nunca como diagnóstico.
    static var sinFcCausa: String {
        String(localized: "onb.4.sinfc.causa",
               defaultValue: "Almost always it's one of two things: the heart permission stayed off in Health, or you don't sleep with a watch on yet.")
    }
    /// El «in 4 nights» era una promesa incondicional, y la subcausa MÁS probable de esta rama es el
    /// permiso apagado (lo dice `sinFcCausa`): ahí no hay noche que valga hasta encender Salud. Se
    /// separan las dos causas —reloj sin usar de noche vs permiso apagado— para no prometer que
    /// esperar arregla lo que solo arregla el botón de abajo.
    static var sinFcCuerpo2: String {
        String(localized: "onb.4.sinfc.2",
               defaultValue: "If you have a watch, wear it to sleep and your first reading comes within a few nights, as long as the heart permission is on. If it's off, waiting won't help: that's what the Health button below is for. If you have no watch, I'd rather tell you today than leave you waiting.")
    }
    static var sinFcCuerpo3: String {
        String(localized: "onb.4.sinfc.3",
               defaultValue: "What does work without a watch is Train: your week's plan, your routines and the progression that climbs on its own.")
    }
    static var sinFcCta: String { String(localized: "onb.4.sinfc.cta", defaultValue: "Go to Train") }
    static var sinFcCtaSecundaria: String {
        String(localized: "onb.4.sinfc.cta2", defaultValue: "Enter Cénit anyway")
    }
    static var sinDatosTitular: String {
        String(localized: "onb.4.titular.sindatos", defaultValue: "Nothing reached me")
    }
    static var sinDatosCuerpo1: String {
        String(localized: "onb.4.sindatos.1",
               defaultValue: "Nothing reached me from Apple Health. Almost always that means the permission stayed off.")
    }
    static var sinDatosCuerpo2: String {
        String(localized: "onb.4.sindatos.2",
               defaultValue: "Open the Health app, find Cénit in your list of apps and turn the signals on.")
    }
    static var errorSync: String {
        String(localized: "onb.4.error", defaultValue: "Couldn't read Apple Health. Try again.")
    }

    // Acto 6 · El perfil (FER-113)
    //
    // Sus claves van SIN número (`onb.perfil.*`): este acto se cobra al SALIR del acta (rumbo al
    // ciclo), y un prefijo numérico obligaría a renumerar 60 claves ya traducidas cada vez que el
    // guion cambie. Orden real del flujo: … reveal (4) → acta (5) → perfil (6) → ciclo (7).
    /// El overline NO dice «para tu base»: la base del veredicto es tu historial de FC en reposo, y
    /// estos cuatro datos no la alimentan (`Profile.hrMax = 208 − 0.7·edad`, sin sexo). Lo único
    /// cierto de los cuatro es que NO salen de tus señales.
    static var perfilOverline: String {
        String(localized: "onb.perfil.overline", defaultValue: "What isn't in your signals")
    }
    static var perfilTitular: String {
        String(localized: "onb.perfil.titular", defaultValue: "Now you're what's missing")
    }
    /// La rama con veredicto ya dado: el cuerpo puede apoyarse en lo que la persona acaba de leer.
    /// Nombra los CUATRO campos (el viejo prometía cuatro datos y justificaba tres: la estatura
    /// nunca se explicaba) y no le atribuye al sexo las zonas, porque la fórmula no lo usa.
    static var perfilCuerpo: String {
        String(localized: "onb.perfil.cuerpo",
               defaultValue: "Your morning word already came out of your heart and your sleep. This is for the other half: your age gives me your heart rate zones, and your sex, your weight and your height fine-tune what you burn when you train.")
    }
    /// Y la rama sin palabra (calibrando, sin FC en reposo, sin datos, «Ahora no»): ahí no hay
    /// lectura a la cual referirse, así que el cuerpo arranca de cero.
    static var perfilCuerpoSinLectura: String {
        String(localized: "onb.perfil.cuerpo.sinlectura",
               defaultValue: "This doesn't come out of your signals, you have to tell me: your age gives me your heart rate zones, and your sex, your weight and your height fine-tune what you burn when you train.")
    }
    /// La nota cuando Apple Salud SÍ llenó algo: recupera el «Desde Apple Salud · editable» del
    /// wizard viejo, que es lo que hace que el prellenado no se sienta impuesto.
    static var perfilNotaSalud: String {
        String(localized: "onb.perfil.nota.salud",
               defaultValue: "What Apple Health already knew is filled in, and it stays editable. Fix anything that looks off: what you set wins.")
    }
    /// Y cuando no llenó nada, que es la rama entera por la que este acto existe.
    static var perfilNotaSinSalud: String {
        String(localized: "onb.perfil.nota.sinsalud",
               defaultValue: "Apple Health gave me none of these, so I filled them in myself to get started. Adjust them, or your zones will be an average person's instead of yours.")
    }
    /// La tercera nota: quien llegó por «Ahora no» nunca conectó Salud, así que echarle la culpa a
    /// Apple («no me dio ninguno de estos datos») es cargarle a otro una decisión que fue suya.
    static var perfilNotaSinPermiso: String {
        String(localized: "onb.perfil.nota.sinpermiso",
               defaultValue: "You didn't connect Apple Health, so I set these four myself to get started. Adjust them, or your zones will be an average person's instead of yours.")
    }
    /// Mientras el autollenado corre. Los cuatro campos están INERTES hasta que hay sello: el
    /// `.task` corre después del primer cuadro, así que sin esta puerta un stepper tocado en ese
    /// instante se lo llevaba el prellenado — y encima el campo quedaba sellado «Desde Apple
    /// Salud», justo al revés de la doctrina del acto («lo que tú pongas manda»).
    static var perfilBuscando: String {
        String(localized: "onb.perfil.buscando",
               defaultValue: "Looking for what Apple Health already knows about you.")
    }
    static var perfilMarcaSalud: String {
        String(localized: "onb.perfil.marca.salud", defaultValue: "From Apple Health")
    }
    static var perfilMarcaTuyo: String {
        String(localized: "onb.perfil.marca.tuyo", defaultValue: "You set this one")
    }
    static var perfilMarcaMio: String {
        String(localized: "onb.perfil.marca.mio", defaultValue: "I filled this one in")
    }
    static var perfilFcMax: String {
        String(localized: "onb.perfil.fcmax", defaultValue: "Your estimated max heart rate")
    }
    static var perfilFcMaxNota: String {
        String(localized: "onb.perfil.fcmax.nota",
               defaultValue: "It comes out of your age. If you know your real one from a test, you can set it by hand in Settings.")
    }

    // Acto 5 · El acta (sus claves conservan el prefijo `onb.5.*` de FER-109)
    static var actaOverline: String {
        String(localized: "onb.5.overline", defaultValue: "What it's made of")
    }
    /// TRES votos, no «ejes» a secas: el motor cuenta autonómico + sueño + centinela y la palabra
    /// sale de ese conteo (`Preparedness`: `out == 0 ? .full : (out == 1 ? .caution : .easy)`).
    static var actaIntro: String {
        String(localized: "onb.5.intro",
               defaultValue: "Your body votes three times every morning, and the word comes out of the count. There is no 0 to 100 score.")
    }
    static var actaOverlinePalabras: String {
        String(localized: "onb.5.overline.palabras", defaultValue: "The four words")
    }
    // Las glosas cuentan VOTOS, no señales: seis señales entran al acta y solo tres votan, así que
    // «una señal se salió» describía un conteo que el motor nunca hace.
    static var actaGlosaFull: String {
        String(localized: "onb.5.glosa.full",
               defaultValue: "None of the three votes stepped out. Today your body isn't asking you to ease off.")
    }
    static var actaGlosaCaution: String {
        String(localized: "onb.5.glosa.caution",
               defaultValue: "One vote stepped out. Train, but don't chase a record.")
    }
    static var actaGlosaEasy: String {
        String(localized: "onb.5.glosa.easy",
               defaultValue: "Two or all three stepped out. Your body is paying for something. Bring the load down.")
    }
    static var actaGlosaCalibrando: String {
        String(localized: "onb.5.glosa.calibrando",
               defaultValue: "I still have nothing to go on. I'd rather stay quiet than make up a word for you.")
    }
    static var actaOverlineEjes: String {
        String(localized: "onb.5.overline.ejes", defaultValue: "The three votes")
    }
    static var actaEjeAutonomico: String {
        String(localized: "onb.5.eje.autonomico", defaultValue: "Autonomic")
    }
    static var actaEjeAutonomicoGlosa: String {
        String(localized: "onb.5.eje.autonomico.glosa",
               defaultValue: "Your heart and your nervous system. If this one has no reading, there is no verdict.")
    }
    static var actaEjeSueno: String { String(localized: "onb.5.eje.sueno", defaultValue: "Sleep") }
    /// El único eje que NO se compara contra tu historia: piso poblacional fijo, `orientedZ: nil`.
    static var actaEjeSuenoGlosa: String {
        String(localized: "onb.5.eje.sueno.glosa",
               defaultValue: "How much you slept against the recommended hours. It's the only signal I don't compare against your history.")
    }
    static var actaEjeTemp: String { String(localized: "onb.5.eje.temp", defaultValue: "Temperature") }
    static var actaEjeTempGlosa: String {
        String(localized: "onb.5.eje.temp.glosa",
               defaultValue: "How far it drifted from your own baseline. On its own it doesn't count: it only adds up the day your breathing steps out with it.")
    }
    static var actaOverlineDentro: String {
        String(localized: "onb.5.overline.dentro", defaultValue: "Inside the axis that leads")
    }
    static var actaRhr: String { String(localized: "onb.5.rhr", defaultValue: "Resting heart") }
    static var actaRhrGlosa: String {
        String(localized: "onb.5.rhr.glosa",
               defaultValue: "The densest, best validated signal your watch gives.")
    }
    static var actaVfcNoche: String {
        String(localized: "onb.5.vfcnoche", defaultValue: "Night variability")
    }
    static var actaVfcNocheGlosa: String {
        String(localized: "onb.5.vfcnoche.glosa",
               defaultValue: "It only counts if the night came with enough detail. It never votes alone.")
    }
    static var actaOverlineNoPesa: String {
        String(localized: "onb.5.overline.nopesa", defaultValue: "What doesn't count, and why")
    }
    static var actaVfcDia: String {
        String(localized: "onb.5.vfcdia", defaultValue: "All-day variability")
    }
    static var actaVfcDiaGlosa: String {
        String(localized: "onb.5.vfcdia.glosa",
               defaultValue: "It left the vote: it's a whole-day measure and it came out worse than your heart's. I still show it, but it doesn't vote.")
    }
    static var actaResp: String { String(localized: "onb.5.resp", defaultValue: "Your breathing") }
    static var actaRespGlosa: String {
        String(localized: "onb.5.resp.glosa",
               defaultValue: "On its own it doesn't vote. Together with your temperature, it does.")
    }
    static var actaPasos: String {
        String(localized: "onb.5.pasos", defaultValue: "Your steps, your rings, your streaks")
    }
    static var actaPasosGlosa: String {
        String(localized: "onb.5.pasos.glosa",
               defaultValue: "They don't come in. What you did yesterday is context for understanding the number, not part of the number.")
    }
    static var actaOverlineContra: String {
        String(localized: "onb.5.overline.contra", defaultValue: "What I compare you against")
    }
    /// Dos respuestas, no una: el corazón se mide contra TU historia y el sueño contra un piso que
    /// es igual para todos. La versión anterior extendía la primera a todo el veredicto. Sin conteo
    /// a propósito: el acta explica el MÉTODO, no cuántas noches llevas hoy —y citar «tus propias 0
    /// noches» al llegar desde `.calibrando(0)` contradecía justo la tesis que la frase defiende.
    static var actaContra: String {
        String(localized: "onb.5.contra",
               defaultValue: "Your heart, against your own nights, never against anybody else's average. Your sleep, against the hours a body asks for, because what you got used to sleeping isn't what you need. That's why I need time before I say anything: by the fourth night I already give you a reading, by the fourteenth I know your normal.")
    }
    /// Sin «de tu veredicto»: al Acta se llega también desde `.calibrando`, que no mostró ⓘ ni
    /// veredicto. La ⓘ es donde vive esto pase lo que pase —haya palabra hoy o no—, así que el pie
    /// no la ata a un veredicto que esa rama todavía no tiene.
    static var actaPie: String {
        String(localized: "onb.5.pie",
               defaultValue: "All of this is always one tap away, in the ⓘ. You can come back whenever you want.")
    }
    static var actaCta: String { String(localized: "onb.5.cta", defaultValue: "Got it") }

    // Etiquetas del acta (el rol de cada renglón)
    static var etiquetaManda: String { String(localized: "onb.5.tag.manda", defaultValue: "leads") }
    static var etiquetaVota: String { String(localized: "onb.5.tag.vota", defaultValue: "votes") }
    static var etiquetaEspina: String { String(localized: "onb.5.tag.espina", defaultValue: "backbone") }
    static var etiquetaAcompana: String {
        String(localized: "onb.5.tag.acompana", defaultValue: "accompanies")
    }
    static var etiquetaFuera: String { String(localized: "onb.5.tag.fuera", defaultValue: "out") }
    /// La etiqueta del centinela: temperatura y respiración cargan UN voto entre las dos.
    static var etiquetaEnPar: String { String(localized: "onb.5.tag.enpar", defaultValue: "paired") }
    static var etiquetaNunca: String { String(localized: "onb.5.tag.nunca", defaultValue: "never") }

    // Acto 7 · Ciclo y mañana (claves `onb.6.*`, mismo motivo)
    static var cicloOverline: String {
        String(localized: "onb.6.overline", defaultValue: "And with that, what")
    }
    static var cicloTitular: String {
        String(localized: "onb.6.titular", defaultValue: "Today says. Train does.")
    }
    static var cicloCuerpo: String {
        String(localized: "onb.6.cuerpo",
               defaultValue: "The reading isn't a datum to file away. It's there to decide your day.")
    }
    static var cicloOverlineTraduce: String {
        String(localized: "onb.6.overline.traduce", defaultValue: "How it translates")
    }
    static var cicloFull: String {
        String(localized: "onb.6.full",
               defaultValue: "Your routine adds weight. Cénit keeps track of which exercise is due.")
    }
    static var cicloCaution: String {
        String(localized: "onb.6.caution", defaultValue: "Same load as last time. Today is not for chasing a record.")
    }
    static var cicloEasy: String {
        String(localized: "onb.6.easy", defaultValue: "I suggest rest, or something gentle that won't send a bill.")
    }
    static var cicloTarjetaFuerte: String {
        String(localized: "onb.6.tarjeta.fuerte", defaultValue: "Your routines add weight on their own.")
    }
    static var cicloTarjetaCuerpo: String {
        String(localized: "onb.6.tarjeta.cuerpo",
               defaultValue: "You don't have to remember when to go heavier: Cénit keeps the count per exercise and tells you the day it's due.")
    }
    static var cicloPie: String {
        String(localized: "onb.6.pie",
               defaultValue: "There's also a plan for the week, a live session and real rest days.")
    }
    static var cierreTitular: String {
        String(localized: "onb.6.cierre.titular", defaultValue: "Sleep. I'll do the rest.")
    }
    /// Cénit calcula SOLO con la app abierta: no hay `UIBackgroundModes`, ni
    /// `enableBackgroundDelivery`, ni `BGTaskScheduler` en todo el proyecto. «Sin que abras nada»
    /// prometía justo lo único que la app no puede hacer.
    static var cierreCuerpo: String {
        String(localized: "onb.6.cierre.cuerpo",
               defaultValue: "With the watch on. In the morning you open me and your word is already there: you don't have to log anything or ask me for anything.")
    }
    /// Lo único que sí ocurre sin abrir la app: el aviso local de `MorningReadingScheduler`
    /// (FER-114), que hasta hoy era invisible porque el flujo no lo nombraba en ningún lado.
    static var cierreAviso: String {
        String(localized: "onb.6.cierre.aviso",
               defaultValue: "If you want, I'll set you a reminder at whatever time you pick. It lives in Settings.")
    }
    /// El cierre «sin reloj» solo lo ve UN tipo de usuario: `.calibrando(0)` —con FC en reposo (o
    /// sea, CON reloj) pero sin noches nocturnas—, porque el Ciclo únicamente se alcanza desde
    /// lectura/calibrando (las ramas sin reloj de verdad salen antes). Así que «si algún día usas un
    /// reloj» era falso para su única audiencia: sí tiene reloj, no ha dormido con él. Y «sin que
    /// hagas nada» reintroducía la lectura pasiva que el cierre CON reloj ya había quitado.
    static var cierreTitularSinReloj: String {
        String(localized: "onb.6.cierre.titular.sinreloj", defaultValue: "Wear it to sleep, too")
    }
    static var cierreCuerpoSinReloj: String {
        String(localized: "onb.6.cierre.cuerpo.sinreloj",
               defaultValue: "Your watch is already giving me your days. Sleep with it on and I start reading your nights. That's where your morning word comes from.")
    }
    static var cicloDock: String {
        String(localized: "onb.6.dock", defaultValue: "Today says · Train does")
    }
    static var cicloDockPie: String {
        String(localized: "onb.6.dock.pie",
               defaultValue: "Resting counts too. There is no streak to lose here.")
    }

    // Salida · «Ahora no»
    static var salidaOverline: String { String(localized: "onb.salida.overline", defaultValue: "That's okay") }
    static var salidaTitular: String {
        String(localized: "onb.salida.titular", defaultValue: "Without Apple Health I can do very little")
    }
    static var salidaCuerpo: String {
        String(localized: "onb.salida.cuerpo",
               defaultValue: "I won't push you. But so you know where you stand: without permission I can't see your heart or your sleep, and the morning verdict is exactly that.")
    }
    static var salidaSi: String {
        String(localized: "onb.salida.si",
               defaultValue: "The full Train tab: routines, the week's plan and the live session")
    }
    static var salidaNo: String {
        String(localized: "onb.salida.no", defaultValue: "The morning verdict, no")
    }
    static var salidaPie: String {
        String(localized: "onb.salida.pie",
               defaultValue: "Whenever you want, it connects in Settings in two taps.")
    }
    static var salidaCta: String {
        String(localized: "onb.salida.cta", defaultValue: "Connect it after all")
    }
    static var salidaCtaSecundaria: String {
        String(localized: "onb.salida.cta2", defaultValue: "Enter like this")
    }

    // Chrome reusado del catálogo (ya existente — no se acuñan claves nuevas para esto).
    static var empezar: String { String(localized: "Get started") }
    static var conectar: String { String(localized: "Connect Apple Health") }
    static var ahoraNo: String { String(localized: "Not now") }
    static var continuar: String { String(localized: "Continue") }
    static var reintentar: String { String(localized: "Retry") }
    static var abrirSalud: String { String(localized: "Open Health") }
    static var entrar: String { String(localized: "Enter Cénit") }
    static var atras: String { String(localized: "Back") }
    // Los cuatro campos del perfil y la unidad de la FC máxima: las mismas claves que ya usan
    // Ajustes y la hoja de «FC máxima», para que el onboarding no invente un vocabulario aparte.
    static var perfilEdad: String { String(localized: "Age") }
    static var perfilSexo: String { String(localized: "Sex") }
    static var perfilPeso: String { String(localized: "Weight") }
    static var perfilEstatura: String { String(localized: "Height") }
    static var fcMaxUnidad: String { String(localized: "bpm · Tanaka") }
}

// MARK: - El shell de un acto

/// Una página del onboarding: una columna que scrollea sobre el lienzo, con su CTA alcanzable.
///
/// `minHeight = viewport` para que los `Spacer` interiores empujen el CTA al pie mientras el
/// desbordamiento por Dynamic Type sigue scrolleando (el objetivo del flujo es **xxxLarge**, que
/// es donde la raíz de la app capa el tamaño). Es el mismo patrón del wizard anterior — lo único
/// que cambia es el suelo: papel de `LiquidColor.fondoGradient`, no `InstrumentoTheme.base.paper`.
///
/// Dos cosas que el shell resuelve para los actos LARGOS:
///
///   · **`indicadores`.** Esconder la barra de scroll es estética que cuesta conversión cuando el
///     contenido desborda: en un iPhone de 390×844 el acto del permiso apila ~900 pt en un
///     viewport útil de ~750 y NADA insinuaba que hubiera más abajo. Los actos que desbordan por
///     construcción (permiso, acta, ciclo) la enseñan.
///
///   · **`pie`.** Un CTA anclado al pie SOBRE el scroll, con el contenido pasando por debajo
///     (`safeAreaInset`, que además reserva su alto para que el final del contenido siga siendo
///     alcanzable). Es para el único gate del producto —el permiso—: sin ese toque no hay app, y
///     ese botón no puede depender de que alguien adivine que hay scroll.
struct OnbShell<Content: View, Pie: View>: View {
    private let indicadores: Bool
    private let content: () -> Content
    private let pie: (() -> Pie)?

    init(indicadores: Bool = false,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder pie: @escaping () -> Pie) {
        self.indicadores = indicadores
        self.content = content
        self.pie = pie
    }

    fileprivate init(indicadores: Bool, content: @escaping () -> Content, pie: (() -> Pie)?) {
        self.indicadores = indicadores
        self.content = content
        self.pie = pie
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: indicadores) {
                VStack(alignment: .leading, spacing: .zero) {
                    content()
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                .padding(.horizontal, LiquidSpace.s600)
                .padding(.vertical, LiquidSpace.s400)
            }
            .safeAreaInset(edge: .bottom, spacing: .zero) { pieAnclado }
        }
    }

    @ViewBuilder
    private var pieAnclado: some View {
        if let pie {
            VStack(alignment: .leading, spacing: .zero) {
                pie()
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s400)
            .padding(.bottom, LiquidSpace.s250)
            .background(velo)
        }
    }

    /// El velo bajo el pie anclado: el mismo papel del fondo, subiendo de transparente a opaco,
    /// para que el texto que sigue scrolleando por debajo no se le encime al botón. No es vidrio
    /// a propósito (el flujo vive sobre papel, y el vidrio-sobre-papel se lava).
    private var velo: some View {
        LinearGradient(colors: [LiquidColor.fondoBajo.opacity(0), LiquidColor.fondoBajo],  // token-exempt(falta-pieza): el velo tiene que arrancar EN CERO
                       startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}

extension OnbShell where Pie == EmptyView {
    /// El acto normal: sin pie anclado (su CTA viaja al final de la columna, empujado por los
    /// `Spacer`).
    init(indicadores: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(indicadores: indicadores, content: content, pie: nil)
    }
}

// MARK: - Tipografía del acto

/// El overline de sección: Grotesk 10/600 +2 MAYÚSCULAS, tinta/500.
struct OnbOverline: View {
    let texto: String
    var tono: Color = LiquidColor.tinta500
    init(_ texto: String, tono: Color = LiquidColor.tinta500) {
        self.texto = texto
        self.tono = tono
    }
    var body: some View {
        Text(texto).groteskOverline().foregroundStyle(tono)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// El titular de un acto: displayS (22), tinta/900. **Nunca 30** — esa talla es exclusiva de la
/// palabra del veredicto en el acto 4.
struct OnbTitular: View {
    let texto: String
    var tono: Color = LiquidColor.tinta900
    init(_ texto: String, tono: Color = LiquidColor.tinta900) {
        self.texto = texto
        self.tono = tono
    }
    var body: some View {
        Text(texto)
            .font(LiquidType.displayS)
            .tracking(LiquidType.displaySTracking)
            .foregroundStyle(tono)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Texto corrido. Escala con Dynamic Type desde la base publicada del token.
struct OnbCuerpo: View {
    let texto: String
    var tono: Color = LiquidColor.tinta700
    var fuerte: Bool = false
    @ScaledMetric(relativeTo: .footnote) private var size = LiquidType.cuerpoLecturaBase

    init(_ texto: String, tono: Color = LiquidColor.tinta700, fuerte: Bool = false) {
        self.texto = texto
        self.tono = tono
        self.fuerte = fuerte
    }

    var body: some View {
        Text(texto)
            .font(.system(size: size, weight: fuerte ? .semibold : .regular))
            .lineSpacing(LiquidType.cuerpoLineSpacing)
            .foregroundStyle(fuerte ? LiquidColor.tinta900 : tono)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// El capilar divisor entre grupos (tinta/900 al 10 %, 1 pt).
struct OnbHairline: View {
    var body: some View {
        Rectangle()
            .fill(LiquidColor.tinta10)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - El renglón del diagrama (actos 2 y 5)

/// Un renglón del diagrama de pesos: el NOMBRE en `groteskLane` MAYÚSCULAS (teñido con la
/// identidad de la señal, o en tinta cuando no vota), su glosa, y opcionalmente su peso y el
/// rol que juega.
///
/// El tono llega YA elegido para texto chico: el ámbar de dato (#C4631F) ronda 3.8:1 y no pasa
/// AA a este tamaño, así que quien tiña con esa familia pasa `LiquidColor.atencionTexto` (el
/// mismo criterio que `LiquidSheetHeader.tonoTexto` aplica dentro del paquete, que es interno).
///
/// El nombre va en `LiquidType.label` (rótulo 11.5/600 +1.5 que ESCALA, relativo a `.caption`) y
/// no en `InstrumentoType.groteskLane` (12 FIJO): con la fuente fija, la glosa —que sí escala—
/// crecía sola y a xxxLarge el título de la fila acababa ~30 % más chico que su descripción, en
/// las 21 filas del flujo. Es el mismo defecto que ya arreglaron `LiquidBandsTable` y
/// `LiquidBarrasContribucion` dentro del paquete; aquí se resuelve tomando el token de rótulo
/// publicado en vez de acuñar un tamaño suelto.
struct OnbFila: View {
    let nombre: String
    var tono: Color?
    let glosa: String
    var peso: String?
    var etiqueta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                Text(nombre)
                    .font(LiquidType.label)
                    .tracking(LiquidType.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(tono ?? LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let peso {
                    Text(peso)
                        .font(LiquidType.datoMenor)
                        .foregroundStyle(LiquidColor.tinta900)
                }
                if let etiqueta {
                    Text(etiqueta)
                        .groteskOverline(small: true)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            OnbCuerpo(glosa)
        }
        .padding(.vertical, LiquidSpace.s150)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chrome

/// La flecha de vuelta. Blanco táctil completo (44 pt), texto del catálogo.
struct OnbAtras: View {
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: LiquidSpace.s150) {
                Image(systemName: "chevron.left")
                    .font(LiquidType.captionLectura)
                Text(OnbCopy.atras)
                    .font(LiquidType.captionLectura)
            }
            .foregroundStyle(LiquidColor.tinta500)
            .frame(minWidth: LiquidControl.hitTarget, minHeight: LiquidControl.hitTarget,
                   alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityLabel(Text(OnbCopy.atras))
    }
}

/// Acción secundaria de texto (la salida de un acto). Voz quiet del sistema, blanco táctil 44.
struct OnbSalidaTexto: View {
    let titulo: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(titulo)
                .font(LiquidType.boton)
                .tracking(LiquidType.botonTracking)
                .foregroundStyle(LiquidColor.verdeProfundo)
                .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
    }
}

/// Una tarjeta de papel opaco (nunca vidrio: el flujo vive sobre el mismo suelo que Hoy y el
/// vidrio-sobre-papel se lava).
struct OnbTarjeta<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            content()
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficieSolida)
    }
}
