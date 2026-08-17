import Foundation
import StrandAnalytics

// MARK: - OnboardingLanding  ·  el desenlace del onboarding (FER-109)
//
// Al terminar de sincronizar Apple Salud el onboarding tiene que aterrizar en algún lado. La
// tentación es decidirlo por el PERMISO ("¿te dieron acceso?"), y ese camino no existe:
//
//   «HealthKit never reveals whether *read* was granted, so we treat a successful request as
//    `.authorized` and let queries return empty if the user declined.»
//                                          — `CenitApp/Health/HealthKitBridge.swift` (requestAuthorization)
//
// Es decir: `auth == .authorized` significa «el diálogo no tronó», NO «hay datos». Quien negó
// todo y quien concedió todo se ven IDÉNTICOS desde el permiso. Por eso el desenlace se decide
// CONTANDO lo que aterrizó en la base local (`AppleHealthCoverage`), que es la única evidencia
// que no miente: si hay filas, hubo lectura.
//
// El otro eje de la decisión es la FC en reposo. Es el tope real del veredicto — no la salud del
// usuario, no una arritmia, no el permiso: sin FC en reposo el eje autonómico de `Preparedness`
// sale `.noData`, el motor cae por la salida de baja señal y el veredicto es `lowSignal` PARA
// SIEMPRE (`Preparedness.evaluate`: `if autonomic.state == .noData { return Read(verdict:
// .lowSignal …) }`). Esperar más días no lo arregla, así que el onboarding tampoco debe prometerlo.
//
// Este archivo NO tiene copy: es la decisión desnuda. La palabra del veredicto vive en
// `LiquidHoyBuilder.veredicto(_:nights:prep:)` y es la ÚNICA que la dice, para que la pantalla de
// bienvenida y la de Hoy nunca puedan discrepar sobre lo mismo.

/// El desenlace del onboarding, decidido por lo que ATERRIZÓ, nunca por el permiso.
public enum OnboardingLanding: Equatable, Sendable {
    /// (a) Hay base suficiente: el onboarding muestra la palabra del veredicto (la que produce
    /// `LiquidHoyBuilder`, jamás una copia local).
    case lectura(verdict: Preparedness.Verdict, noches: Int, diasHistoria: Int)
    /// (b) Llegó FC en reposo pero la base es joven: NO hay palabra, hay conteo honesto
    /// («noche N de 4»), el mismo denominador del motor que ya usa Hoy.
    case calibrando(noches: Int, faltan: Int, diasHistoria: Int)
    /// (c) Llegaron señales pero CERO FC en reposo: el tope. Sin ella no hay veredicto, nunca —
    /// y el onboarding tiene que decir otra cosa que «tu base se está formando», porque esa
    /// promesa no se cumple ni esperando un año.
    case sinRitmoEnReposo(diasHistoria: Int)
    /// (d) No llegó ni una fila: o negaron la lectura, o Salud está vacío. Indistinguibles desde
    /// aquí (ver la nota de HealthKit arriba), y por suerte da igual: el desenlace es el mismo.
    case sinDatos
}

extension OnboardingLanding {

    /// Densidad 0…1 que la evidencia justifica. Es lo que impide que el orbe se llene solo por
    /// esperar: la simulación pide el número, no lo inventa.
    ///
    /// - `.lectura` / `.calibrando` → `noches / Baselines.minNightsTrust` (14), topado en 1. Son
    ///   las noches de la base autonómica que el veredicto de verdad carga (`autonomicNights`),
    ///   no los días de historia importada: 400 días de pasos no hacen firme a nadie.
    /// - `.sinRitmoEnReposo` → 0.34 como TECHO. Que se note que hay materia (llegaron señales),
    ///   pero que nunca cuaje, porque sin FC en reposo nunca va a cuajar.
    /// - `.sinDatos` → 0.
    public var densidadHonesta: Double {
        switch self {
        case .sinDatos:
            return 0
        case .sinRitmoEnReposo:
            return Self.techoSinRitmo
        case let .lectura(_, noches, _), let .calibrando(noches, _, _):
            let piso = max(0, noches)
            return min(1, Double(piso) / Double(Baselines.minNightsTrust))
        }
    }

    /// ¿Hay color que revelar? Solo el desenlace CON palabra tiñe el lienzo: sin veredicto el orbe
    /// se queda gris en vez de apostar un tono (y `lowSignal` no tiene tono propio). El wizard lo
    /// usa para elegir el destino del tinte, y el acto 4 para saltarse el beat del teñido cuando
    /// no hay nada que teñir — 450 ms de espera muertos en tres de las cuatro ramas.
    public var revelaColor: Bool {
        guard case let .lectura(verdict, _, _) = self else { return false }
        return verdict != .lowSignal
    }

    /// Cuántos días de historia leyó, para el contador que rueda. Son días CON alguna fila de
    /// Apple (`AppleHealthCoverage.totalDays`), no el span del calendario: un hueco de tres meses
    /// no cuenta como historia.
    public var diasHistoria: Int {
        switch self {
        case .sinDatos:                              return 0
        case let .lectura(_, _, dias):               return dias
        case let .calibrando(_, _, dias):            return dias
        case let .sinRitmoEnReposo(dias):            return dias
        }
    }

    /// El techo de densidad de `.sinRitmoEnReposo`: hay materia, nunca cuaja.
    static let techoSinRitmo: Double = 0.34
}

/// Decide el desenlace. Función pura: mismos números, mismo resultado, sin tocar HealthKit ni la
/// base — para poder probarla sin simulador y sin reloj.
public enum OnboardingLandingDecider {

    /// La clave con la que `CenitStore.appleHealthCoverage` cuenta los días de FC en reposo
    /// (`COUNT(restingHr) AS resting_hr` sobre `dailyMetric`). Constante y no literal suelto: si
    /// la clave del store cambia, este archivo tiene un solo lugar que corregir.
    public static let claveFCReposo = "resting_hr"

    /// - Parameters:
    ///   - totalDays: días distintos con alguna fila de Apple (`AppleHealthCoverage.totalDays`).
    ///   - diasPorMetrica: `AppleHealthCoverage.daysByMetric`. Una métrica AUSENTE es una llave
    ///     ausente, no un cero — por eso se lee con `?? 0`.
    ///   - preparedness: la lectura del motor para hoy, si ya se pudo evaluar.
    ///   - seed: noches que el motor necesita para sembrar la base (`Baselines.minNightsSeed`).
    ///     Parámetro para poder probarlo, nunca para inventar un umbral propio.
    public static func decidir(totalDays: Int,
                               diasPorMetrica: [String: Int],
                               preparedness: Preparedness.Read?,
                               seed: Int = Baselines.minNightsSeed) -> OnboardingLanding {

        // 1. Ni una fila. El caso de quien negó la lectura y el de quien tiene Salud vacío caen
        //    aquí juntos, y está bien: no hay forma de distinguirlos y no cambia qué mostrar.
        guard totalDays > 0 else { return .sinDatos }

        // 2. El tope. Llegaron señales (sueño, pasos, lo que sea) pero cero FC en reposo: el eje
        //    autonómico sale `.noData` y `Preparedness` se queda en `lowSignal` para siempre.
        //    Va ANTES del conteo de noches a propósito: «te faltan 2 noches» sería mentira aquí.
        guard (diasPorMetrica[claveFCReposo] ?? 0) > 0 else {
            return .sinRitmoEnReposo(diasHistoria: totalDays)
        }

        // 3. Hay FC en reposo, pero el motor todavía no puede opinar. Tres formas de lo mismo:
        //    no hubo lectura, la lectura salió `lowSignal`, o la base no llegó al seed. Si el
        //    motor no se atreve a la palabra, el onboarding tampoco: cuenta noches y ya.
        //
        //    OJO con el caso que SÍ pasa: quien trae el reloj de día y no duerme con él. Ese
        //    usuario tiene `resting_hr` (el agregado despierto de Apple) y ninguna noche
        //    nocturna — y `Preparedness` lo resuelve solo: si la serie nocturna no cubre
        //    `minNightsSeed`, usa la serie DESPIERTA entera («One construct, always»), así que
        //    llega aquí con noches y veredicto reales. No hay nada que bloquearle: cae en
        //    `.lectura` por el paso 4, que es lo correcto.
        let noches = preparedness?.autonomicNights ?? 0
        guard let prep = preparedness, prep.verdict != .lowSignal, noches >= seed else {
            return .calibrando(noches: noches,
                               faltan: max(0, seed - noches),
                               diasHistoria: totalDays)
        }

        // 4. Hay palabra. El onboarding la pide prestada a Hoy; aquí solo viaja el enum.
        return .lectura(verdict: prep.verdict, noches: noches, diasHistoria: totalDays)
    }
}
