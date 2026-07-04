import Foundation

// MARK: - Daily Brief — el veredicto del día en palabras (FER-470)
//
// El motor de contenido de la página 1 de «Hoy». Sintetiza el `ReadinessEngine.Readiness` del día —más
// recuperación/base y el sueño de anoche— en un titular en lenguaje llano, un «porqué» de una frase, y
// 2–3 viñetas priorizadas. NO es matemática fisiológica nueva: reusa los flags/σ que `ReadinessEngine`
// ya computó; aquí solo se PRIORIZA y se traduce a copy.
//
// La DECISIÓN (qué viñetas, en qué orden, qué nivel) vive en `level` + `Bullet.kind`/`flag` —enums
// testeables sin afirmar strings—; el COPY (titular/porqué/lead/sub) es es-MX (app es-only). El color y
// el glifo NO viven aquí: la UI mapea `flag → color` (la misma fuente que la palabra del veredicto) y
// `BulletKind → SF Symbol`, así el paquete queda puro (sin SwiftUI/UIKit).
//
// i18n: el copy va como literales es-MX (no pasa por el catálogo). Cuando el app sea bilingüe habrá que
// migrarlo igual que el resto de la UI vieja.

/// El contenido del Daily Brief para un día CON veredicto. `DailyBriefEngine.make` devuelve `nil` cuando
/// no hay veredicto (`level == .insufficient`): el motor nunca inventa un brief sin lectura.
public struct DailyBrief: Sendable, Equatable {
    /// El nivel del veredicto del que se derivó (decisión testeable; el titular se elige de aquí).
    public let level: ReadinessEngine.Level
    /// Titular-veredicto en palabras, imperativo es-MX (p. ej. «Dale con todo.»).
    public let titular: String
    /// El «porqué»: una frase cálida compuesta del nivel + el hecho dominante de hoy.
    public let why: String
    /// 2–3 viñetas priorizadas (sueño fija si hay, luego las más relevantes del pool dinámico).
    public let bullets: [Bullet]

    public init(level: ReadinessEngine.Level, titular: String, why: String, bullets: [Bullet]) {
        self.level = level; self.titular = titular; self.why = why; self.bullets = bullets
    }

    /// Una viñeta del brief. `kind`/`flag` son la decisión (testeable); `lead`/`sub` el copy es-MX.
    public struct Bullet: Sendable, Equatable {
        /// Qué señal/tema representa (decisión testeable; la UI mapea esto a un SF Symbol).
        public let kind: BulletKind
        /// La valencia, de `ReadinessEngine.Flag`; la UI la mapea a color con la MISMA fuente que la
        /// palabra del veredicto en la página 1 (`flagColor`).
        public let flag: ReadinessEngine.Flag
        /// Encabezado semibold en lenguaje llano (p. ej. «Dormiste bien»).
        public let lead: String
        /// Subtítulo: la interpretación en palabras (o la cifra legible — duración, °C, ratio).
        public let sub: String

        public init(kind: BulletKind, flag: ReadinessEngine.Flag, lead: String, sub: String) {
            self.kind = kind; self.flag = flag; self.lead = lead; self.sub = sub
        }
    }

    /// Los temas posibles de una viñeta. `String`-backed + `CaseIterable` para tests legibles.
    public enum BulletKind: String, Sendable, Equatable, CaseIterable {
        case sleep, recovery, hrv, rhr, respRate, skinTemp, acwr
    }

    /// La viñeta de HRV ESTIMADA para un día sin banda (FER-623): la HRV de hoy vino de Apple Salud (SDNN),
    /// así que el veredicto —que mide solo contra la base de banda (RMSSD)— no trae señal de HRV. En su lugar
    /// el día se clasifica contra su PROPIA base SDNN (el mismo patrón `AppleRecoveryEstimator`) y se inyecta
    /// aquí, marcada «estimado» por la UI. `nil` cuando hoy es de banda o la base SDNN aún no es usable
    /// (cold-start: no se inventa σ). El z (σ, crudo, sobre la base = `+`) y el flag los calcula la capa de
    /// app reusando `ReadinessEngine` sobre la historia enmascarada a Apple — cero matemática nueva.
    public struct HrvEstimatedBullet: Sendable, Equatable {
        /// La desviación de la SDNN de hoy contra la propia base SDNN, en σ (sobre la base = `+`).
        public let z: Double
        /// La valencia, de `ReadinessEngine.Flag` (la UI la mapea a color con la misma fuente que el veredicto).
        public let flag: ReadinessEngine.Flag
        public init(z: Double, flag: ReadinessEngine.Flag) { self.z = z; self.flag = flag }
    }
}

/// El motor del Daily Brief. Puro y determinista: misma entrada → misma salida.
public enum DailyBriefEngine {

    /// Arma el brief del día, o `nil` si no hay veredicto (`level == .insufficient`).
    /// - Parameters:
    ///   - readiness: el veredicto del día (de `ReadinessEngine.evaluate`).
    ///   - recovery: la recuperación 0–100 de hoy (nil mientras calibra).
    ///   - recoveryBaseline: la media reciente de recuperación, para la viñeta «vs tu base».
    ///   - sleepMinutes: el sueño de anoche en minutos (nil si aún no hay lectura).
    ///   - hrvEstimated: la viñeta de HRV estimada vs base SDNN para un día sin banda (FER-623); `nil` si hoy
    ///     es de banda (el veredicto ya trae su señal de HRV) o si la base SDNN aún no es usable (cold-start).
    public static func make(readiness: ReadinessEngine.Readiness,
                            recovery: Double?,
                            recoveryBaseline: Double?,
                            sleepMinutes: Double?,
                            hrvEstimated: DailyBrief.HrvEstimatedBullet? = nil) -> DailyBrief? {
        guard readiness.level != .insufficient else { return nil }
        let bullets = selectBullets(readiness: readiness, recovery: recovery,
                                    recoveryBaseline: recoveryBaseline, sleepMinutes: sleepMinutes,
                                    hrvEstimated: hrvEstimated)
        // Piso de 2 (FER-470): si el día no da para ≥2 viñetas (sin sueño, sin señales del cuerpo, solo
        // la recuperación), NO mostramos un brief de una sola línea — devolvemos nil y la página 1 cae al
        // copy honesto del veredicto. Así el brief siempre trae 2–3 viñetas. Caso escaso (mañana temprano
        // con historial de recuperación aún ralo y veredicto ACWR-driven).
        guard bullets.count >= 2 else { return nil }
        return DailyBrief(level: readiness.level,
                          titular: titular(readiness.level),
                          why: why(level: readiness.level, recovery: recovery,
                                   recoveryBaseline: recoveryBaseline, sleepMinutes: sleepMinutes),
                          bullets: bullets)
    }

    // MARK: Selección de viñetas (la decisión — pura y testeable)

    /// Un candidato del pool dinámico, antes de cortar a las 2–3 que entran. `internal` (no `private`)
    /// para que los constructores testeables (`sleepBullet`/`recoveryCandidate`) puedan devolverlo.
    struct Candidate: Equatable {
        let kind: DailyBrief.BulletKind
        let flag: ReadinessEngine.Flag
        let lead: String
        let sub: String
    }

    /// Slot 1 = sueño (fijo, si hay sueño de anoche). Slots 2–3 = el pool dinámico ordenado por gravedad
    /// del flag y desempatado por prioridad fija de tipo (NO por |σ|: σ/°C/ratio no comparan entre sí).
    /// Con sueño se toman 2 del pool (total 3); sin sueño, 3.
    static func selectBullets(readiness: ReadinessEngine.Readiness,
                              recovery: Double?,
                              recoveryBaseline: Double?,
                              sleepMinutes: Double?,
                              hrvEstimated: DailyBrief.HrvEstimatedBullet? = nil) -> [DailyBrief.Bullet] {
        var bullets: [DailyBrief.Bullet] = []
        if let mins = sleepMinutes {
            let b = sleepBullet(mins)
            bullets.append(DailyBrief.Bullet(kind: b.kind, flag: b.flag, lead: b.lead, sub: b.sub))
        }

        var pool: [Candidate] = []
        // La recuperación es candidata SIEMPRE que haya recovery (en estado-veredicto siempre lo hay):
        // con base se compara «vs tu base»; sin base aún, se describe por zona del dial. Esto evita que
        // el brief degenere a 0 viñetas cuando no hay sueño ni señales del cuerpo.
        if let rec = recovery {
            pool.append(recoveryCandidate(recovery: rec, baseline: recoveryBaseline))
        }
        for s in readiness.signals {
            guard let kind = bulletKind(forSignalKey: s.key) else { continue }   // monotony, etc. fuera
            pool.append(Candidate(kind: kind, flag: s.flag,
                                  lead: signalLead(kind: kind, flag: s.flag),
                                  sub: signalSub(kind: kind, flag: s.flag) ?? s.value ?? s.detail))
        }
        // FER-623: un día sin banda no produce señal de HRV en el veredicto (su SDNN se enmascaró de la base
        // de banda). Si la capa de app calculó la HRV estimada contra la propia base SDNN, entra como viñeta
        // de HRV — pero solo si el veredicto no trajo ya una (nunca dos viñetas de HRV). La UI la marca
        // «estimado». Reusa el MISMO copy que una señal de banda; la fuente (SDNN) la señala el sello.
        if let est = hrvEstimated, !pool.contains(where: { $0.kind == .hrv }) {
            pool.append(Candidate(kind: .hrv, flag: est.flag,
                                  lead: signalLead(kind: .hrv, flag: est.flag),
                                  sub: signalSub(kind: .hrv, flag: est.flag) ?? ""))
        }
        // Orden estable: peor flag primero; a igual flag, prioridad fija de tipo.
        let ordered = pool.enumerated().sorted { a, b in
            let (ia, ca) = a; let (ib, cb) = b
            if flagRank(ca.flag) != flagRank(cb.flag) { return flagRank(ca.flag) > flagRank(cb.flag) }
            if typePriority(ca.kind) != typePriority(cb.kind) { return typePriority(ca.kind) < typePriority(cb.kind) }
            return ia < ib   // estabilidad
        }.map(\.element)

        let slots = sleepMinutes != nil ? 2 : 3
        for c in ordered.prefix(slots) {
            bullets.append(DailyBrief.Bullet(kind: c.kind, flag: c.flag, lead: c.lead, sub: c.sub))
        }
        return bullets
    }

    /// Gravedad del flag para ordenar: lo que pide atención primero, las buenas noticias después.
    static func flagRank(_ f: ReadinessEngine.Flag) -> Int {
        switch f { case .bad: return 3; case .watch: return 2; case .good: return 1; case .neutral: return 0 }
    }

    /// Prioridad fija de tipo (desempate a igual flag): lo más cercano al «hoy» fisiológico primero.
    static func typePriority(_ k: DailyBrief.BulletKind) -> Int {
        switch k {
        case .sleep:    return -1   // nunca cae aquí (es fijo), pero lo dejamos coherente
        case .recovery: return 0
        case .hrv:      return 1
        case .rhr:      return 2
        case .respRate: return 3
        case .skinTemp: return 4
        case .acwr:     return 5
        }
    }

    /// Mapea la `key` de una `ReadinessEngine.Signal` al tema de viñeta, o `nil` si no entra al brief
    /// (`monotony` se excluye: es matiz de variedad de entrenamiento, no una señal del día).
    static func bulletKind(forSignalKey key: String) -> DailyBrief.BulletKind? {
        switch key {
        case "hrv":      return .hrv
        case "rhr":      return .rhr
        case "respRate": return .respRate
        case "skinTemp": return .skinTemp
        case "acwr":     return .acwr
        default:         return nil
        }
    }

    // MARK: Viñetas concretas (copy es-MX)

    /// La viñeta de sueño: flag por suficiencia (corta < 6 h, completa ≥ 7 h, intermedia neutral).
    static func sleepBullet(_ minutes: Double) -> Candidate {
        // Redondea (no trunca) para que el h/min mostrado coincida con el Detalle
        // de Sueño (SleepDetailScreen.hoursOnly, que usa .rounded()). La
        // clasificación de abajo sigue con el valor crudo `minutes` (FER-626).
        let total = Swift.max(0, Int(minutes.rounded()))
        let h = total / 60, m = total % 60
        let dur = "\(h) h \(m) min"
        if minutes < 360 {
            return Candidate(kind: .sleep, flag: .watch, lead: "Dormiste poco", sub: "\(dur) · noche corta")
        } else if minutes >= 420 {
            return Candidate(kind: .sleep, flag: .good, lead: "Dormiste bien", sub: "\(dur) · sueño completo")
        } else {
            return Candidate(kind: .sleep, flag: .neutral, lead: "Dormiste", sub: dur)
        }
    }

    /// La viñeta de recuperación: flag por banda + comparación con la media reciente (si la hay). El sub
    /// habla el vocabulario del Detalle (FER-637): la zona con nombre de `MetricLevels.recovery` («en
    /// Moderado»), nunca «tu base» — ese concepto no existe en la pantalla de Recuperación. Con `baseline`
    /// se añade la comparación en llano («mejor que tus últimos días»); sin base aún, la zona sola.
    static func recoveryCandidate(recovery: Double, baseline: Double?) -> Candidate {
        let delta = baseline.map { recovery - $0 }
        let flag: ReadinessEngine.Flag
        if recovery >= RecoveryScorer.bandYellowMax || (delta ?? 0) >= 5 { flag = .good }
        else if recovery < RecoveryScorer.bandRedMax { flag = .bad }
        else if (delta ?? 0) <= -5 { flag = .watch }
        else { flag = .neutral }

        let lead: String
        switch flag {
        case .good:    lead = "Estás recuperado"
        case .bad:     lead = "Recuperación baja"
        case .watch:   lead = "Vienes por debajo"
        case .neutral: lead = "Recuperación estable"
        }
        let zone = recoveryZoneName(recovery)
        let sub: String
        if let d = delta {
            if d >= 5 { sub = "en \(zone), mejor que tus últimos días" }
            else if d <= -5 { sub = "en \(zone), por debajo de tus últimos días" }
            else { sub = "en \(zone), como tus últimos días" }
        } else {
            sub = "en \(zone)"
        }
        return Candidate(kind: .recovery, flag: flag, lead: lead, sub: sub)
    }

    /// El nombre es-MX de la zona de recuperación del Detalle para un score 0–100 (FER-637). Los RANGOS
    /// vienen de `MetricLevels.recovery` (una sola fuente con la pantalla); los nombres son el es-MX del
    /// String Catalog (este archivo es copy es-only, igual que leads/subs). Si FER-638 renombra una zona
    /// en el catálogo, se renombra también aquí.
    static func recoveryZoneName(_ score: Double) -> String {
        let key = MetricLevels.levels(for: .recovery).first { lvl in
            (lvl.lower.map { score >= $0 } ?? true) && (lvl.upper.map { score < $0 } ?? true)
        }?.key
        switch key {
        case "depleted": return "Agotado"
        case "low":      return "Bajo"
        case "moderate": return "Moderado"
        case "primed":   return "A punto"
        case "peak":     return "Pico"
        default:         return "Moderado"   // inalcanzable: la partición 0–100 es total
        }
    }

    /// El lead interpretivo de una señal del cuerpo, por tipo y valencia. La dirección («subió/bajó») la
    /// decide el flag: para cada señal, `.good` es la dirección sana y `.watch`/`.bad` la que pide atención.
    /// La interpretación en palabras va en `signalSub` — el lead ya no empaca dos ideas con un guion (FER-637).
    ///
    /// FER-623: la HRV se ancla a «vs tu base» (sin verbo de cambio temporal). El σ siempre es relativo a la
    /// base personal, no a ayer; decir «bajó» sugería una comparación día-a-día que confundía («dice alta
    /// pero bajó vs ayer»). «sobre/bajo tu base» dice exactamente contra qué se mide.
    static func signalLead(kind: DailyBrief.BulletKind, flag: ReadinessEngine.Flag) -> String {
        let good = flag == .good
        switch kind {
        // FER-627: `.watch` (−1.0…−0.5σ) es el «cambio que vale la pena atender» (SWC), NO estar fuera de la
        // base — reservamos «bajo tu base» para `.bad` (<−1σ), que sí coincide con «Debajo de tu base» del
        // Detalle. Así el Brief deja de contradecir a la hoja de Detalle (que a −0.9σ dice «En tu base»).
        case .hrv:
            switch flag {
            case .good:    return "Tu HRV está sobre tu base"
            case .neutral: return "Tu HRV está en tu base"
            case .watch:   return "Tu HRV va a la baja"
            case .bad:     return "Tu HRV está bajo tu base"
            }
        case .rhr:
            switch flag {
            case .good:    return "Tu pulso en reposo está bajo tu base"
            case .neutral: return "Tu pulso en reposo está en tu base"
            case .watch, .bad: return "Tu pulso en reposo está sobre tu base"
            }
        case .respRate: return good ? "Tu respiración va estable" : "Tu respiración subió"
        case .skinTemp: return good ? "Tu temperatura va normal" : "Tu temperatura subió"
        case .acwr:     return good ? "Tu carga va en balance" : "Tu carga viene alta"
        case .recovery, .sleep: return ""   // estos tienen su propio constructor
        }
    }

    /// El sub interpretivo que acompaña al lead (FER-637): la lectura en palabras, donde antes iba la
    /// cifra σ que nadie entiende. `nil` para las señales cuya cifra sí es legible (temperatura en °C,
    /// carga como ratio) — esas conservan su `value`.
    static func signalSub(kind: DailyBrief.BulletKind, flag: ReadinessEngine.Flag) -> String? {
        switch kind {
        case .hrv:
            switch flag {
            case .good:    return "buena señal"
            case .neutral: return "todo en orden"
            case .watch:   return "cambio que vale la pena vigilar"
            case .bad:     return "tu cuerpo pide calma"
            }
        case .rhr:
            switch flag {
            case .good:    return "señal de recuperación"
            case .neutral: return "todo en orden"
            case .watch, .bad: return "tu cuerpo sigue activo"
            }
        case .respRate:
            return (flag == .good || flag == .neutral) ? "en su ritmo usual" : "por encima de lo usual"
        case .skinTemp, .acwr, .recovery, .sleep:
            return nil
        }
    }

    // MARK: Titular + porqué (copy es-MX)

    /// El titular-veredicto por nivel (D1 aprobada). `insufficient` no llega aquí (make devuelve nil antes).
    static func titular(_ level: ReadinessEngine.Level) -> String {
        switch level {
        case .primed:       return "Dale con todo."
        case .balanced:     return "Entrena a tu ritmo."
        case .strained:     return "Baja una marcha hoy."
        case .rundown:      return "Hoy toca recuperar."
        case .insufficient: return ""
        }
    }

    /// El «porqué» (D3 — Opción B): una frase cálida = cláusula del hecho dominante (sueño + recuperación)
    /// + el cierre por nivel. El hecho se rellena con los datos reales de hoy; el cierre es el consejo.
    static func why(level: ReadinessEngine.Level, recovery: Double?,
                    recoveryBaseline: Double?, sleepMinutes: Double?) -> String {
        let fact = factClause(recovery: recovery, recoveryBaseline: recoveryBaseline, sleepMinutes: sleepMinutes)
        let close: String
        switch level {
        case .primed:       close = "Buen día para empujar."
        case .balanced:     close = "Entrena a tu ritmo."
        case .strained:     close = "Hay algo que cuidar. Entrena con cabeza."
        case .rundown:      close = "Hoy tu cuerpo pide bajar el ritmo."
        case .insufficient: close = ""
        }
        return fact.isEmpty ? close : "\(fact). \(close)"
    }

    /// La cláusula del hecho dominante para el «porqué»: sueño + recuperación en lenguaje llano. Omite la
    /// parte que no tenga dato, así nunca afirma algo que no midió.
    static func factClause(recovery: Double?, recoveryBaseline: Double?, sleepMinutes: Double?) -> String {
        var parts: [String] = []
        if let mins = sleepMinutes {
            if mins < 360 { parts.append("dormiste poco") }
            else if mins >= 420 { parts.append("dormiste bien") }
            else { parts.append("descansaste") }
        }
        if let rec = recovery, let base = recoveryBaseline {
            let delta = rec - base
            if rec >= RecoveryScorer.bandYellowMax || delta >= 5 { parts.append("vienes recuperado") }
            else if rec < RecoveryScorer.bandRedMax || delta <= -5 { parts.append("tu recuperación viene baja") }
            else { parts.append("vienes estable") }
        }
        guard !parts.isEmpty else { return "" }
        let joined = parts.count == 2 ? "\(parts[0]) y \(parts[1])" : parts[0]
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}

// MARK: - Bloque «Hoy en tu plan» — el puente con Entrenar (FER-613)
//
// La fase 1 del «Daily Brief inteligente» (épico FER-612): al pie del brief, conecta cuerpo ↔ entrenamiento
// reusando motores ya probados (`WeeklySplit` para la rutina/racha, `TrainingRegulation` para el ajuste de
// ritmo). NO es matemática nueva. Igual que el resto del motor: la DECISIÓN (estado/ritmo) + el copy variable
// (la línea de ritmo, derivada de la banda de recuperación) viven aquí, puros y testeables; el copy estático
// (overline, «Empezar», «Hoy descansas», la pluralización «día/días») y el color/botón los pone la UI.

extension DailyBrief {
    /// El contenido del bloque «Hoy en tu plan». `DailyBriefEngine.trainingBlock` devuelve `nil` cuando no
    /// hay split configurado (el bloque se omite sin dejar hueco).
    public struct TrainingBlock: Sendable, Equatable {
        /// Hoy es día de entreno (con rutina asignada) o de descanso (el split no asigna rutina hoy).
        public enum State: Sendable, Equatable { case training, rest }
        /// El ajuste de ritmo del día — espejo de `TrainingRegulation.Adjustment`; la UI lo mapea a color.
        public enum Pace: Sendable, Equatable { case up, hold, down }

        public let state: State
        /// El nombre de la rutina de hoy (solo `.training`; `nil` en descanso).
        public let routineName: String?
        /// La racha de días cumpliendo el plan. Es el MISMO valor que muestra Entrenar (misma fuente,
        /// `WeeklySplit.adherenceStreak` vía el helper compartido `TrainingStreak`).
        public let streakDays: Int
        /// El ajuste de ritmo de hoy (solo `.training` y solo si hay recuperación). `nil` mientras no hay
        /// lectura — el bloque degrada con gracia y omite la línea de ritmo.
        public let pace: Pace?
        /// La línea es-MX del ajuste (derivada de la banda de recuperación). `nil` cuando no hay `pace`.
        public let paceCopy: String?

        public init(state: State, routineName: String?, streakDays: Int, pace: Pace?, paceCopy: String?) {
            self.state = state; self.routineName = routineName
            self.streakDays = streakDays; self.pace = pace; self.paceCopy = paceCopy
        }
    }
}

extension DailyBriefEngine {

    /// Arma el bloque «Hoy en tu plan», o `nil` si no hay split (el bloque se omite). Puro y determinista.
    /// - Parameters:
    ///   - hasSplit: el usuario tiene al menos un día asignado en su semana. Sin split → `nil`.
    ///   - todayRoutineName: la rutina de hoy (`WeeklySplit.todayRoutineId` resuelta a nombre), o `nil` si
    ///     hoy es descanso.
    ///   - streakDays: la racha de días cumpliendo el plan (`WeeklySplit.adherenceStreak`, calculada en la
    ///     capa de app porque depende del calendario local).
    ///   - recovery: la recuperación 0–100 de hoy (`nil` mientras no hay lectura → sin línea de ritmo).
    public static func trainingBlock(hasSplit: Bool,
                                     todayRoutineName: String?,
                                     streakDays: Int,
                                     recovery: Double?) -> DailyBrief.TrainingBlock? {
        guard hasSplit else { return nil }
        guard let name = todayRoutineName else {
            // Día de descanso: el split existe pero no asigna rutina hoy.
            return DailyBrief.TrainingBlock(state: .rest, routineName: nil, streakDays: streakDays,
                                            pace: nil, paceCopy: nil)
        }
        var pace: DailyBrief.TrainingBlock.Pace?
        var paceCopy: String?
        // El ajuste de ritmo es advisory (no instrucción clínica): solo cuando hay recuperación de hoy.
        if let rec = recovery, let s = TrainingRegulation.suggest(recovery: rec) {
            switch s.adjustment {
            case .dialUp:   pace = .up;   paceCopy = "Recuperación alta para ti · puedes con todo el plan"
            case .hold:     pace = .hold; paceCopy = "Recuperación en tu rango · entrena a tu carga de siempre"
            case .dialBack: pace = .down; paceCopy = "Recuperación baja para ti · quizá baja el volumen hoy"
            }
        }
        return DailyBrief.TrainingBlock(state: .training, routineName: name, streakDays: streakDays,
                                        pace: pace, paceCopy: paceCopy)
    }
}

// MARK: - «La conexión de hoy» — la correlación más relevante en una frase (FER-614)
//
// La fase 2 del «Daily Brief inteligente» (épico FER-612): un renglón que cruza dos señales. NO es
// matemática nueva — consume los `Insight` que `InsightEngine` ya rankeó (con FDR/efecto), elige a lo más UNA
// correlación significativa (la más relevante, que ya viene primero en la lista) y la traduce a una frase
// es-MX SIN jerga (sin r ni n). El detalle a fondo vive en Patrones: la UI lleva el `Insight` elegido para
// hacer deep-link. Hedge honesto: sin correlación significativa, no hay conexión (la UI omite el renglón).

extension DailyBrief {
    /// La «conexión de hoy»: una correlación significativa entre dos señales, lista para el renglón del brief.
    public struct Connection: Sendable, Equatable {
        /// La frase es-MX, sin jerga estadística (p. ej. «Tu Sueño y tu Recuperación van de la mano»).
        public let text: String
        /// La correlación elegida — la UI la usa para abrir su detalle/patrón en Patrones (deep-link).
        public let insight: Insight

        public init(text: String, insight: Insight) { self.text = text; self.insight = insight }
    }
}

extension DailyBriefEngine {

    /// Elige la «conexión de hoy» de la lista YA rankeada por `InsightEngine.generate` (significativas primero,
    /// luego por efecto): la primera correlación significativa. `nil` si no hay ninguna sólida — nunca inventa.
    public static func connection(insights: [Insight]) -> DailyBrief.Connection? {
        guard let top = insights.first(where: { $0.kind == .correlation && $0.evidence.significant }),
              let text = connectionText(for: top) else { return nil }
        return DailyBrief.Connection(text: text, insight: top)
    }

    /// Traduce una correlación a una frase es-MX que nombra las dos señales y la dirección, sin jerga. Devuelve
    /// `nil` si el insight no es una correlación o si su `metric` no trae las dos señales («A·B»). La dirección
    /// sale del signo de `effectSize` (r): r≥0 → «van de la mano»; r<0 → «se mueven al revés».
    static func connectionText(for insight: Insight) -> String? {
        guard insight.kind == .correlation else { return nil }
        let parts = insight.datum.metric.split(separator: "·").map(String.init)
        guard parts.count == 2 else { return nil }
        let direct = (insight.evidence.effectSize ?? 0) >= 0
        return "Tu \(parts[0]) y tu \(parts[1]) \(direct ? "van de la mano" : "se mueven al revés")"
    }
}

// MARK: - «La conexión de hoy» gana una 2ª fuente: el experimento N-of-1 (FER-615)
//
// La fase 3 del «Daily Brief inteligente» (épico FER-612): el MISMO renglón «La conexión de hoy» puede venir
// ahora de dos lados —la correlación detectada (F2) o el experimento N-of-1 en curso (FER-307/462)—. NO es
// matemática nueva: el experimento ya lo arma Patrones (estado/racha/check-in derivados del historial); aquí
// solo se DECIDE cuál de las dos fuentes muestra el renglón y se traduce el experimento a una frase es-MX. El
// motor queda puro: recibe el experimento como un input plano (etiquetas ya resueltas), nunca lee la DB.

extension DailyBrief {
    /// La fuente del renglón «La conexión de hoy»: la correlación detectada (F2) o el experimento en curso (F3).
    /// La UI las renderiza igual (acento + frase + CTA), pero el deep-link difiere: la correlación abre su patrón,
    /// el experimento abre el check-in/detalle del experimento en Patrones.
    public enum DayConnection: Sendable, Equatable {
        case correlation(Connection)
        case experiment(ExperimentLine)
    }

    /// El renglón del experimento N-of-1 en curso dentro del brief: su estado en una frase + si toca check-in hoy.
    public struct ExperimentLine: Sendable, Equatable {
        /// La frase es-MX del estado (p. ej. «Vas en el día 3 de “Meditación → Recuperación”»).
        public let text: String
        /// Hoy toca registrar el check-in (dentro de la ventana, sin marcar). La UI lo mapea al copy del CTA:
        /// `true` → «Registra check-in»; `false` → «Ver experimento».
        public let pendingCheckIn: Bool

        public init(text: String, pendingCheckIn: Bool) {
            self.text = text; self.pendingCheckIn = pendingCheckIn
        }
    }
}

extension DailyBriefEngine {

    /// El experimento N-of-1 en curso, como input plano para el renglón del brief (etiquetas ya resueltas en la
    /// capa de app — el motor no toca DB ni catálogo). Espejo de lo que muestra Patrones (FER-462).
    public struct ActiveExperiment: Sendable, Equatable {
        /// La etiqueta es-MX del comportamiento (p. ej. «Meditación»).
        public let behaviorLabel: String
        /// La etiqueta es-MX del resultado/outcome (p. ej. «Recuperación»).
        public let outcomeLabel: String
        /// El día en curso dentro de la ventana, 1-based (el `elapsedDay` de Patrones).
        public let dayNumber: Int
        /// Hoy toca check-in (dentro de ventana, sin marcar) — el `pendingCheckIn` de Patrones.
        public let pendingCheckIn: Bool

        public init(behaviorLabel: String, outcomeLabel: String, dayNumber: Int, pendingCheckIn: Bool) {
            self.behaviorLabel = behaviorLabel; self.outcomeLabel = outcomeLabel
            self.dayNumber = dayNumber; self.pendingCheckIn = pendingCheckIn
        }
    }

    /// Elige la fuente del renglón «La conexión de hoy» entre la correlación (F2) y el experimento en curso (F3),
    /// con una regla de prioridad **determinista y documentada**:
    ///
    /// 1. **Check-in pendiente hoy** → gana el experimento (la acción del día es lo que más puede pesar).
    /// 2. Si no, **gana la correlación significativa** (la conexión de mayor relevancia, ya rankeada — F2).
    /// 3. Si no hay correlación, **el experimento activo** (su estado día/título, sin check-in pendiente).
    /// 4. Sin nada → `nil` (la UI omite el renglón).
    ///
    /// `experiment` es `nil` cuando no hay experimento en curso → cae al comportamiento puro de F2.
    public static func dayConnection(insights: [Insight],
                                     experiment: ActiveExperiment?) -> DailyBrief.DayConnection? {
        let corr = connection(insights: insights)
        guard let exp = experiment else {
            return corr.map(DailyBrief.DayConnection.correlation)
        }
        let line = experimentLine(exp)
        if exp.pendingCheckIn { return .experiment(line) }   // 1
        if let corr { return .correlation(corr) }            // 2
        return .experiment(line)                             // 3
    }

    /// Traduce el experimento en curso a su renglón es-MX. El título cruza comportamiento → resultado, como en
    /// Patrones; la cifra es el día en curso (sin jerga estadística).
    static func experimentLine(_ exp: ActiveExperiment) -> DailyBrief.ExperimentLine {
        let title = "\(exp.behaviorLabel) → \(exp.outcomeLabel)"
        return DailyBrief.ExperimentLine(text: "Vas en el día \(exp.dayNumber) de “\(title)”",
                                         pendingCheckIn: exp.pendingCheckIn)
    }
}
