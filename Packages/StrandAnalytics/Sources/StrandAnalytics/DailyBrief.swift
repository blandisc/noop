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
        /// Subtítulo con la cifra (duración, σ, o la comparación con la base).
        public let sub: String

        public init(kind: BulletKind, flag: ReadinessEngine.Flag, lead: String, sub: String) {
            self.kind = kind; self.flag = flag; self.lead = lead; self.sub = sub
        }
    }

    /// Los temas posibles de una viñeta. `String`-backed + `CaseIterable` para tests legibles.
    public enum BulletKind: String, Sendable, Equatable, CaseIterable {
        case sleep, recovery, hrv, rhr, respRate, skinTemp, acwr
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
    public static func make(readiness: ReadinessEngine.Readiness,
                            recovery: Double?,
                            recoveryBaseline: Double?,
                            sleepMinutes: Double?) -> DailyBrief? {
        guard readiness.level != .insufficient else { return nil }
        let bullets = selectBullets(readiness: readiness, recovery: recovery,
                                    recoveryBaseline: recoveryBaseline, sleepMinutes: sleepMinutes)
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
                              sleepMinutes: Double?) -> [DailyBrief.Bullet] {
        var bullets: [DailyBrief.Bullet] = []
        if let mins = sleepMinutes {
            let b = sleepBullet(mins)
            bullets.append(DailyBrief.Bullet(kind: b.kind, flag: b.flag, lead: b.lead, sub: b.sub))
        }

        var pool: [Candidate] = []
        if let rec = recovery, let base = recoveryBaseline {
            pool.append(recoveryCandidate(recovery: rec, baseline: base))
        }
        for s in readiness.signals {
            guard let kind = bulletKind(forSignalKey: s.key) else { continue }   // monotony, etc. fuera
            pool.append(Candidate(kind: kind, flag: s.flag,
                                  lead: signalLead(kind: kind, flag: s.flag),
                                  sub: s.value ?? s.detail))
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
        let h = Int(minutes) / 60, m = Int(minutes) % 60
        let dur = "\(h) h \(m) min"
        if minutes < 360 {
            return Candidate(kind: .sleep, flag: .watch, lead: "Dormiste poco", sub: "\(dur) · noche corta")
        } else if minutes >= 420 {
            return Candidate(kind: .sleep, flag: .good, lead: "Dormiste bien", sub: "\(dur) · sueño completo")
        } else {
            return Candidate(kind: .sleep, flag: .neutral, lead: "Dormiste", sub: dur)
        }
    }

    /// La viñeta de recuperación vs tu base: flag por banda + comparación con la media reciente.
    static func recoveryCandidate(recovery: Double, baseline: Double) -> Candidate {
        let delta = recovery - baseline
        let flag: ReadinessEngine.Flag
        if recovery >= RecoveryScorer.bandYellowMax || delta >= 5 { flag = .good }
        else if recovery < RecoveryScorer.bandRedMax { flag = .bad }
        else if delta <= -5 { flag = .watch }
        else { flag = .neutral }

        let lead: String
        switch flag {
        case .good:    lead = "Estás recuperado"
        case .bad:     lead = "Recuperación baja"
        case .watch:   lead = "Vienes por debajo"
        case .neutral: lead = "Recuperación estable"
        }
        let sub: String
        if delta >= 5 { sub = "por encima de tu base" }
        else if delta <= -5 { sub = "por debajo de tu base" }
        else { sub = "en tu base" }
        return Candidate(kind: .recovery, flag: flag, lead: lead, sub: sub)
    }

    /// El lead interpretivo de una señal del cuerpo, por tipo y valencia. El `sub` lo lleva la cifra σ
    /// de la propia señal. La dirección («subió/bajó») la decide el flag: para cada señal, `.good` es la
    /// dirección sana y `.watch`/`.bad` la que pide atención.
    static func signalLead(kind: DailyBrief.BulletKind, flag: ReadinessEngine.Flag) -> String {
        let good = flag == .good
        switch kind {
        case .hrv:      return good ? "Tu HRV viene alta" : "Tu HRV bajó"
        case .rhr:      return good ? "Tu pulso en reposo bajó" : "Tu pulso en reposo subió"
        case .respRate: return good ? "Tu respiración va estable" : "Tu respiración subió"
        case .skinTemp: return good ? "Tu temperatura va normal" : "Tu temperatura subió"
        case .acwr:     return good ? "Tu carga va en balance" : "Tu carga viene alta"
        case .recovery, .sleep: return ""   // estos tienen su propio constructor
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
        case .strained:     close = "Hay algo que cuidar — entrena con cabeza."
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
