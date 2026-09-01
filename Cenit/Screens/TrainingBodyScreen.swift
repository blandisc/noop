#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - «Tu cuerpo» (Cuerpo) — FER-350 · rediseño «la respuesta lidera» · FER-91 · E10 fusión
//
// The jewel of the loop: front/back silhouettes tinted by each muscle's recent training load, CROSSED
// with the day's VERDICT (FER-82 — the same word Hoy shows, never a recovery score) — what to train
// today. A tracker without physiology (Fitbod) can't cross in a verdict; a physiology app without set
// logging (WHOOP) has no per-muscle load. Cénit has both.
//
// Light «Instrumento diurno» language (warm paper, color ONLY on the datum, hierarchy by space). The
// math is the pure, cited `MuscleFatigueMap` (StrandAnalytics): load = Σ involvement·decay(daysAgo) with
// a 2-day half-life (MPS time course), a 3/7/14-day window that filters which sets count, freshness
// relative to the user's own most-loaded muscle, weekly volume vs the Schoenfeld 10–20 band. The
// systemic gate is applied HERE, from the verdict (FER-82). THIS screen is the glue: it reads work sets from the store, expands each over its
// exercise's `muscleInvolvement`, computes whole-day ages in the local calendar, and draws the result.
//
// Entrenar v3 · 1n (FER-719) — the handoff skin («Rediseño Hoy» voice):
//   • A grotesk VERDICT headline leads (what's fresh, what still carries load), with the day's
//     verdict bullet right under it — the old hero card and gate bar collapse into these two lines.
//   • The 3/7/14-day lens is RETIRED: the decay itself carries time (see `MuscleFatigueMap`), so a
//     window filter double-encoded recency. The ranking is fixed to the last 7 days, showing each
//     muscle's weekly sets.
//   • The figures stay the detailed anatomical silhouettes tinted by the 5-stop fresh→loaded ramp,
//     with the continuous legend under them.
//   • The foot states the method in one line and expands into the cited paragraph («Ver el método»).
//   • The manual «mark all recovered» reset (FER-525) is PRESERVED: it filters which sets feed the
//     map (nothing deleted), which is orthogonal to the decay math.
//
// FER-91 · E10 — «mapa y dosis en una sola pantalla»: this file used to be `MuscleMapScreen.swift`
// (the atlas + the «most loaded» ranking); `MuscleVolumeScreen.swift` (the 30d/90d/6m/1y span picker
// vs the Schoenfeld band) folded in as `volumeSection` below, inline — no more push to a child screen.
// Three changes came with the fusion, each documented at its call site: (1) `ranking`/`peekCard`'s
// hand-rolled rows became `MuscleLoadRow` (StrandDesign · E2), which also DROPPED the 3-way
// fresh/moderate/loaded color word — that was a second, inconsistent color language for the same
// «recency» concept `theme.verdict` already owns for the day's bullet (see `loadRow` below); (2) the
// volume section's own «ⓘ How this is measured» sheet was NOT carried over — its citation (Schoenfeld
// 2017, the 10–20 band) is already inside this screen's ONE `method` foot, and the épico explicitly
// forbids a second note repeating the same cite; (3) the top-level empty-state gate now also waits on
// the volume fetch (`loadedVolume`) and checks `volumeEvents`, not just the map's own 84-day
// `hasHistory` — before the fusion, «Volumen por músculo» was reachable on its own and could show a
// wider window (up to a year) even on a stretch with nothing in the map's 84-day lookback; gating the
// WHOLE fused screen behind the map's narrower window alone would have hidden that data, which is
// exactly the loss this épico exists to catch.
//
// Presented as a light `.sheet` from Cuerpo (theme passed explicitly — it doesn't cross the `.sheet`
// boundary, FER-162); the per-muscle detail rides a nested `.sheet(item:)`, NO nested NavigationStack
// (FER-171).

/// Ruta de «Volumen por músculo», empujada desde el stack de Entrenar y desde «Mis entrenamientos»
/// (`WorkoutHistoryScreen.swift`). Antes de FER-91 llevaba solo al mapa (con su enlace propio a las
/// barras); ahora lleva a la pantalla fusionada `TrainingBodyScreen`, que YA incluye ambas lecturas —
/// el nombre del tipo no cambió a propósito, así que ningún call site externo necesitó tocarse.
struct MuscleVolumeRoute: Hashable {}

struct TrainingBodyScreen: View {
    let theme: InstrumentoTheme
    @EnvironmentObject var repo: Repository
    /// El MISMO puente de Salud que la landing (`EntrenarView.healthConnected`): sin él el hilo no
    /// puede distinguir «sin lectura» de «sin conectar Salud» (FER-136 · V7).
    @EnvironmentObject private var health: HealthKitBridge
    /// La boleta del veredicto, servida DENTRO de «Tu cuerpo» (FER-136 · V7): el MISMO
    /// `VeredictoActaSheet` que abre la landing y la sesión en vivo — un solo destino, nunca una
    /// segunda acta.
    @State private var showVeredictoActa = false

    /// All completed work sets in the trailing 84 days, expanded to per-muscle events (one fetch). The
    /// decay carries recency (no window, FER-719); the detail's weekly trend buckets the whole span.
    @State private var events: [MuscleFatigueMap.MuscleSetEvent] = []
    /// muscle → the exercises the user actually did that hit it (dedup, strongest involvement kept).
    @State private var hitsByMuscle: [String: [MuscleHit]] = [:]
    @State private var loaded = false
    @State private var selected: MuscleSelection? = nil
    @State private var showMethod = false
    /// The muscle the user tapped once — the «peek» (highlighted + a mini load indicator). A second tap
    /// on the same muscle (or on the peek card) opens the full detail. `nil` = no peek; the figure falls
    /// back to highlighting the most-loaded muscle.
    @State private var peeked: String? = nil
    /// Manual recovery reset (FER-525): epoch seconds. Work sets before this are ignored, so the map reads
    /// «all fresh» as if the user had rested — without deleting any history. 0 = never reset.
    @AppStorage("muscleRecoveryResetAt") private var recoveryResetAt: Double = 0
    /// Whether the user has ANY logged work set in the window — separates «no data yet» (onboarding empty
    /// state) from «all recovered» (the green map). (FER-525)
    @State private var hasHistory = false
    @State private var showResetConfirm = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    private static let trendDays = 84

    // MARK: - Volume per muscle (Entrenar v3 · 3d, FER-719 — folded in by FER-91 · E10)
    //
    // A DIFFERENT question from the list above: not «what's still loaded right now» but «did this
    // muscle get its weekly dose, averaged over a span you choose» — judged against the Schoenfeld
    // 10–20 band. It ignores the manual recovery reset on purpose (it reads history, not freshness)
    // and fetches its own trailing year independently of the map's 84-day window.

    /// The span the average runs over. Raw value = trailing days.
    private enum Span: Int, CaseIterable {
        case d30 = 30, d90 = 90, m6 = 182, y1 = 365
        var label: String {
            switch self {
            case .d30: return String(localized: "30 d")
            case .d90: return String(localized: "90 d")
            case .m6:  return String(localized: "6 m")
            case .y1:  return String(localized: "1 y")
            }
        }
    }

    @State private var span: Span = .d30
    /// Work sets over the trailing year, expanded to per-muscle events (one fetch; the span slices).
    /// Independent of `events` above: this one ignores the recovery reset and reaches back further.
    @State private var volumeEvents: [MuscleFatigueMap.MuscleSetEvent] = []
    @State private var loadedVolume = false

    private var volumes: [MuscleFatigueMap.MuscleWeeklyVolume] {
        MuscleFatigueMap.weeklyVolumes(events: volumeEvents, days: span.rawValue)
    }
    private var belowBand: [MuscleFatigueMap.MuscleWeeklyVolume] {
        volumes.filter { $0.band == .below }
    }
    /// The band rail draws 0…30 sets/week, like the muscle detail (band at 10–20 sits centered).
    private var railTop: Double { MuscleFatigueMap.weeklyVolumeRailTop }

    /// FER-82 «un solo oráculo»: the SYSTEMIC gate is the day's verdict (the same word Hoy shows),
    /// never the 0–100 score. This screen is reachable from Entrenar, and a score-gated headline
    /// could tell you to train on the morning the app is saying «Recupera». The per-muscle load and
    /// its tint keep coming from the log alone — that is what they measure.
    ///
    /// The pure engine keeps its `recovery` parameter (E11 owns that API); here it is always fed
    /// `nil` so no score gate applies, and the verdict gate is applied at the call site.
    /// Solo «Recupera» cierra la pantalla. «Hoy ve leve» retiene el PESO, no el entrenamiento, y un
    /// veredicto que solo va tarde (`pending`) no afirma nada: sería inventar un descanso que nadie
    /// ha dictaminado, y encima sin explicación porque la viñeta calla en ese estado. Regresión
    /// probada en `TrainingRegulationTests.testOnlyRecoverGatesTraining` (StrandAnalytics): SOLO
    /// `.recover` gatea, `.lighter` nunca.
    private var systemicGate: Bool { TrainingRegulation.gatesTraining(repo.trainingAdvice) }

    private var loads: [MuscleFatigueMap.MuscleLoad] {
        MuscleFatigueMap.loads(events: events)
    }
    /// The «Más cargados» ranking is fixed to the last 7 days (the mock), independent of how far back
    /// the decayed tint reaches. `weeklySets` is the engine's 7-day count — the same window the row
    /// displays — so membership and the shown number are single-sourced.
    private var rankingLoads: [MuscleFatigueMap.MuscleLoad] {
        loads.filter { $0.weeklySets > 0 }
    }
    private var loadByMuscle: [String: MuscleFatigueMap.MuscleLoad] {
        Dictionary(loads.map { ($0.muscle, $0) }, uniquingKeysWith: { a, _ in a })
    }
    /// The most-loaded muscle (loads come back sorted by load, desc) — labels & outlines the figure.
    private var topMuscle: MuscleFatigueMap.MuscleLoad? { loads.first }
    /// The muscle the floating label & figure outline point at: the active peek, else the most-loaded.
    private var focused: MuscleFatigueMap.MuscleLoad? {
        if let p = peeked { return loadByMuscle[p] ?? MuscleFatigueMap.MuscleLoad(muscle: p, load: 0, relative: 0, daysSinceLast: 0, state: .fresh, weeklySets: 0, band: .below) }
        return topMuscle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                header
                if loaded && loadedVolume {
                    if loads.isEmpty && !hasHistory && volumeEvents.isEmpty {
                        emptyState
                    } else {
                        figures
                        if !rankingLoads.isEmpty {
                            ranking
                            grossReading
                        }
                        volumeSection
                        method
                    }
                }
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, LiquidSpace.topeScroll)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-202 (Ola · anillo 3, épico FER-195): fondo de vidrio El Eje — reemplaza el papel
        // plano. Conserva el hilo Liquid (`EntrenarHilo`), siluetas, `MuscleLoadRow` y la navegación
        // ambiente del stack; no se duplica el hilo ni se toca la apertura de `VeredictoActaSheet`.
        .entrenarHojaFondo(tono: .neutro)
        .pantallaFondo()
        .task {
            async let mapLoad: () = load()
            async let volumeLoad: () = loadVolume()
            _ = await (mapLoad, volumeLoad)
        }
        .sheet(item: $selected) { sel in
            MuscleDetailView(
                theme: theme,
                muscle: sel.muscle,
                load: loadByMuscle[sel.muscle],
                weeklyTrend: weeklyTrend(for: sel.muscle),
                hits: hitsByMuscle[sel.muscle] ?? [],
                systemicGate: systemicGate
            )
            .preferredColorScheme(.light)
        }
        // El hilo del veredicto abre la MISMA boleta que Entrenar (`EntrenarView.showVeredictoActa`)
        // y la sesión en vivo (`LiveStrengthSheet.bodyVeredictoActaSheet`) — el mismo contenido, para
        // que Tu cuerpo no pueda contar el día distinto (FER-136 · V7).
        .sheet(isPresented: $showVeredictoActa) {
            VeredictoActaSheet(prep: repo.todayPreparedness, healthConnected: healthConnected,
                               fullyLoaded: repo.fullyLoaded)
        }
        .enableInjection()
    }

    // MARK: - Header — kicker + el hilo del veredicto (FER-136 · V7)
    //
    // El MISMO hilo que la landing y la sesión en vivo: mismo constructor
    // (`LiquidHoyBuilder.hiloEntrenar`), mismo componente (`EntrenarHilo`, orbe 44) y la MISMA hoja
    // del veredicto al toque (`VeredictoActaSheet`) — Tu cuerpo no puede contar el día distinto. La
    // frase que completa la palabra sale del MISMO `loads` que ya ordena la ficha y el pie
    // (`muscleReading`), nunca una segunda derivación del mapa.

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your body · \(cabeceraFecha)").entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
            if loaded {
                hiloDelVeredicto.padding(.top, CenitMetrics.space2)
            }
        }
    }

    /// «Sáb 15 ago» — el mismo helper compartido que usa la cabecera de la landing
    /// (`StrandFormat.weekdayHeading`, quisquilloso ronda 4: antes dos copias a mano).
    private var cabeceraFecha: String { StrandFormat.weekdayHeading(Date()) }

    @ViewBuilder private var hiloDelVeredicto: some View {
        if let hilo = LiquidHoyBuilder.hiloEntrenar(
            prep: repo.todayPreparedness,
            nights: repo.todayPreparedness?.autonomicNights ?? 0,
            healthConnected: healthConnected,
            verdictPending: repo.todayPreparedness == nil && !repo.fullyLoaded,
            // `repo` no expone la rutina de hoy en esta pantalla (a diferencia de
            // `EntrenarView.todayRoutine`), pero es inofensivo: `hasPlan` solo mueve el `consejo` del
            // tono `.claro` (`LiquidHoyBuilder.swift:618`), y aquí ese consejo SIEMPRE se reemplaza por
            // `muscleReading` salvo en `.hueco`, donde `hasPlan` nunca se lee.
            hasPlan: true) {
            EntrenarHilo(tone: hilo.tono.entrenarTone,
                         word: LocalizedStringKey(hilo.palabra),
                         // Hueco (sin lectura / sin conectar Salud / conociéndote): el consejo de
                         // copy.md, tal cual. Con veredicto: la palabra se completa con el mapa; si el
                         // mapa no tiene nada que decir (todo fresco), cae al consejo genérico del
                         // constructor en vez de quedarse mudo (quisquilloso ronda 4: la landing SIEMPRE
                         // trae `hilo.consejo` para ese mismo tono con `hasPlan: true`).
                         advice: hilo.tono == .hueco
                            ? hilo.consejo.map { LocalizedStringKey($0) }
                            : (muscleReading.map { LocalizedStringKey($0.thread) }
                               ?? hilo.consejo.map { LocalizedStringKey($0) }),
                         radio: EntrenarMetrics.orbeCuerpo,
                         hint: "Opens today's ballot") {
                showVeredictoActa = true
            }
        }
    }

    private var healthConnected: Bool {
        #if DEBUG
        if ScreenshotFixtures.activeState() != nil { return true }
        #endif
        return health.auth == .authorized
    }

    // MARK: - Figures (detailed anatomical silhouettes)

    private var figures: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                BodyFiguresView(theme: theme, loadByMuscle: loadByMuscle,
                                maxLoad: loads.first?.load ?? 0,
                                highlight: focused?.muscle) { tapMuscle($0) }
                    .padding(.top, LiquidSpace.seccionCanto)
                if let f = focused { floatingLabel(f) }
            }
            if let p = peeked {
                peekCard(p).padding(.top, CenitMetrics.space1)
                resetRow.padding(.top, 7)  // token-exempt(optico): aire entre peekCard y resetRow, entre space1 (4) y space2 (8) — afinado a ojo, sin paso exacto
            } else {
                legend.padding(.top, LiquidSpace.s150)
                Text("Tap a muscle to see its load")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .padding(.top, 10)  // token-exempt: sin token exacto (edge ≠ rowVPad)
                if !loads.isEmpty {
                    markRecoveredButton.padding(.top, CenitMetrics.gap)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 10, bottom: 12, trailing: 10))  // token-exempt: EdgeInsets mixto sin token compuesto
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .instrumentoConfirm(
            isPresented: $showResetConfirm,
            title: String(localized: "Mark all muscles as recovered?"),
            context: String(localized: "MUSCLE MAP"),
            message: String(localized: "The map resets to fresh. Your workout history isn't deleted: logging a new workout loads that muscle again."),
            actions: [
                .init(String(localized: "Mark recovered"), role: .primary) { markAllRecovered() },
                .init(String(localized: "Leave the map as is"), role: .secondary)
            ]
        )
    }

    /// First tap on a muscle peeks it (highlight + mini indicator); a second tap on the same muscle
    /// opens the full detail.
    private func tapMuscle(_ muscle: String) {
        if peeked == muscle {
            selected = MuscleSelection(muscle: muscle)
        } else {
            withAnimation(StrandMotion.interactive) { peeked = muscle }
        }
    }

    private func floatingLabel(_ m: MuscleFatigueMap.MuscleLoad) -> some View {
        HStack(spacing: 7) {
            Circle().fill(theme.muscleStateColor(m.relative))
                .frame(width: 7, height: 7)
            Text(MuscleAtlas.name(m.muscle)).font(StrandFont.caption).fontWeight(.semibold).foregroundStyle(theme.paper)
            Text(stateSuffix(m.state)).font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
        }
        .padding(.horizontal, LiquidChip.compactoHorizontal).padding(.vertical, LiquidChip.compactoVertical)
        .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One muscle's row, fed straight from the engine's two readings (recency load + 7-day sets) —
    /// `MuscleLoadRow` (StrandDesign · E2), never a hand-rolled row. Shared by `ranking` and
    /// `peekCard` (FER-91 · E10): before the fusion each had its own bespoke HStack, and `peekCard`
    /// additionally painted a 3-way fresh/moderate/loaded color word (`stateWord`/`stateColor`,
    /// retired with it) — a second color language for the same «how loaded is it» question the
    /// ranking already answered with ink + the ámbar rail alone. `theme.verdict` (green) now appears
    /// ONLY on the day's verdict bullet above, never on a muscle row (the inconsistency this fusion
    /// closes).
    private func loadRow(_ muscle: String) -> MuscleLoadRow {
        let load = loadByMuscle[muscle]
        let state = load?.state ?? .fresh
        let daysSinceLast = load?.daysSinceLast ?? 0
        return MuscleLoadRow(
            name: MuscleAtlas.name(muscle),
            load: load?.relative ?? 0,
            recency: state == .fresh ? "fresh"
                : daysSinceLast == 0 ? "today" : daysSinceLast == 1 ? "yesterday" : "\(daysSinceLast) d ago",
            sets: load?.weeklySets ?? 0,
            isFresh: state == .fresh,
            action: { selected = MuscleSelection(muscle: muscle) }
        )
    }

    /// The mini load indicator for the peeked muscle — a tap target into the full detail. Kept in its
    /// own `EntrenarModulo` (unlike the plain `ranking` rows) so the atlas's active selection still
    /// reads as a callout, not just another list row.
    private func peekCard(_ muscle: String) -> some View {
        EntrenarModulo(tono: .neutro) {
            loadRow(muscle)
        }
        .padding(.horizontal, CenitMetrics.space1)
    }

    private var resetRow: some View {
        HStack {
            Text("Tap again to see everything").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Spacer()
            Button { withAnimation(StrandMotion.interactive) { peeked = nil } } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.uturn.backward").font(StrandFont.glyph(.chevron, weight: .semibold))
                    Text("Deselect").font(StrandFont.caption)
                }
                .foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CenitMetrics.space1)
    }

    /// «Mark all recovered» — sets the recovery-reset point so the map reads all-fresh, without deleting
    /// any workout history. (FER-525)
    private var markRecoveredButton: some View {
        Button { showResetConfirm = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(StrandFont.glyph(.chevron, weight: .semibold))
                Text("Mark all recovered").font(StrandFont.caption)
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, LiquidSpace.handoff14).padding(.vertical, CenitMetrics.space2)
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Marks every muscle as recovered"))
    }

    private func markAllRecovered() {
        recoveryResetAt = Date().timeIntervalSince1970
        withAnimation(StrandMotion.interactive) { peeked = nil }
        Task { await load() }
    }

    private func stateSuffix(_ s: MuscleFatigueMap.LoadState) -> LocalizedStringKey {
        switch s {
        case .fresh: return "· fresh"
        case .moderate: return "· moderate"
        case .loaded: return "· loaded"
        }
    }

    private var legend: some View {
        VStack(spacing: 6) {
            LinearGradient(colors: theme.muscleLoadRamp, startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))  // token-exempt: geometría de dato
            HStack {
                Text("Fresh").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Text("relative to your load").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("Loaded").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
        .padding(.horizontal, LiquidSpace.s150)
    }

    // MARK: - Ranking

    /// «Músculos cargados · últimos 7 días» — fixed to the last 7 days (the handoff); each row
    /// carries its weekly sets, the raw number the Schoenfeld band judges.
    private var ranking: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Loaded muscles · last 7 days").entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, CenitMetrics.space2)
            muscleColumnHeader.padding(.bottom, 2)  // token-exempt: ajuste óptico
            ForEach(Array(rankingLoads.enumerated()), id: \.element.muscle) { i, m in
                if i > 0 { Divider().overlay(theme.hairline) }
                loadRow(m.muscle)
            }
        }
    }

    /// «CARGA · SERIES · 7 D» — el par de columnas que `MuscleLoadRow` dibuja (nombre / riel /
    /// recencia / series / chevron), rotulado una sola vez arriba de la lista (FER-136 · V7). Oculto de
    /// VoiceOver: cada fila ya anuncia su propia carga y series en `MuscleLoadRow.accessibilityLabel`.
    /// Reserva el mismo número de columnas que `MuscleLoadRow.rowContent` (nombre / riel 120 / recencia
    /// / series / chevron), con placeholders invisibles para la recencia y el chevron — sin ellos
    /// «Sets · 7 d» caía sobre la columna de recencia de cada fila, no sobre la de series.
    private var muscleColumnHeader: some View {
        HStack(spacing: CenitMetrics.gap) {
            Color.clear.frame(maxWidth: .infinity)
            Text("Load").instrumentoOverline().frame(maxWidth: 120, alignment: .leading)
            Text(verbatim: "yesterday").font(StrandFont.caption).fixedSize(horizontal: true, vertical: false).hidden()
            Text("Sets · 7 d").instrumentoOverline()
            StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).hidden()
        }
        .foregroundStyle(theme.inkTertiary)
        .accessibilityHidden(true)
    }

    // MARK: - Lectura gruesa + nota de honestidad (FER-136 · V7)
    //
    // La misma prosa en dos anchos: `thread` (el hilo del veredicto, corto) y `gross` (el pie de
    // «Músculos cargados», completo) — ambas leen el MISMO `loads` que ya ordena `ranking`, nunca
    // una segunda derivación del mapa.

    private struct MuscleReading { let thread: String; let gross: String }

    private var muscleReading: MuscleReading? {
        let notFresh = loads.filter { $0.state != .fresh }   // `loads` ya viene ordenado por carga desc
        guard let first = notFresh.first else { return nil }
        let second = notFresh.dropFirst().first
        // El hilo (corto) NUNCA lleva la recencia entre paréntesis de un músculo «a medias» — copy.md
        // línea 16: «piernas cargadas de hoy, espalda a medias». La lectura gruesa (larga) SÍ la lleva
        // — línea 60: «espalda a medias (hace 3 días)» — así que cada ancho pide su propia cláusula
        // (`includeRecency`), NUNCA una segunda derivación del mapa.
        let threadClauses = [loadClause(first), second.map { loadClause($0) }].compactMap { $0 }
        let thread = threadClauses.joined(separator: ", ")
        let grossClauses = [loadClause(first, includeRecency: true), second.map { loadClause($0, includeRecency: true) }].compactMap { $0 }
        var gross = grossClauses.count == 2 ? String(localized: "\(grossClauses[0]) and \(grossClauses[1])") : grossClauses[0]
        gross += "."
        let freshRoom = loads.filter { $0.state == .fresh && $0.weeklySets < MuscleFatigueMap.weeklyBandLow }
            .sorted { $0.weeklySets < $1.weeklySets }
            .prefix(2)
        if !freshRoom.isEmpty {
            let names = freshRoom.map { muscleNameText($0.muscle) }
            let sets = freshRoom.map { setsText($0.weeklySets) }
            let nameText = names.count == 2 ? String(localized: "\(names[0]) and \(names[1])") : names[0]
            let setsCombined = sets.count == 2 ? String(localized: "\(sets[0]) and \(sets[1])") : sets[0]
            // quisquilloso ronda 4: SIN adjetivo pegado al nombre («listos») — "Pantorrillas"/"Espalda
            // baja" son femeninos y "listos" no concuerda; misma disciplina invariante que `loadClause`.
            gross += " " + String(localized: "Room for more sets in \(nameText) (\(setsCombined) of the 10–20 guide).")
        }
        return MuscleReading(thread: thread, gross: gross)
    }

    /// «Cuádriceps con carga de hoy» / «Espalda a medias» — sin concordancia de género (evita una
    /// tabla de género por músculo): un fraseo invariante, correcto en español para cualquier músculo.
    /// SIN coma propia (el join de `muscleReading` pone la única coma, entre cláusulas) — copy.md:
    /// «piernas cargadas de hoy, espalda a medias», nunca una coma dentro de cada cláusula.
    /// `includeRecency` añade «(hace N d)» a un músculo «a medias» SOLO para la lectura gruesa (larga);
    /// el hilo (corto) se queda en «a medias» a secas.
    private func loadClause(_ m: MuscleFatigueMap.MuscleLoad, includeRecency: Bool = false) -> String {
        let name = muscleNameText(m.muscle)
        if m.state == .moderate {
            guard includeRecency else { return name + String(localized: " halfway") }
            return name + String(localized: " halfway (\(recencyText(m.daysSinceLast)))")
        }
        switch m.daysSinceLast {
        case 0: return name + String(localized: " loaded today")
        case 1: return name + String(localized: " loaded yesterday")
        default: return name + String(localized: " loaded \(m.daysSinceLast) d ago")
        }
    }

    /// «hoy» / «ayer» / «hace N d» — las mismas tres llaves que `MuscleDetailView.lastText` ya usa,
    /// en `String` (no `LocalizedStringKey`) para poder interpolarlas dentro de la cláusula generada.
    private func recencyText(_ days: Int) -> String {
        switch days {
        case 0: return String(localized: "today")
        case 1: return String(localized: "yesterday")
        default: return String(localized: "\(days) d ago")
        }
    }

    /// El nombre del músculo en `String` (no `LocalizedStringKey`): el hilo (`EntrenarHilo.advice`) y
    /// la «Lectura gruesa» solo aceptan texto ya resuelto para poder interpolarlo en la oración
    /// generada. Mismo mapeo de 17 llaves que `MuscleAtlas.name`, vía `MuscleAtlas.nameKey` (la única
    /// fuente) — antes un segundo switch de 17 casos, duplicado a mano.
    private func muscleNameText(_ muscle: String) -> String {
        String(localized: String.LocalizationValue(MuscleAtlas.nameKey(muscle)))
    }

    /// «Lectura gruesa: …» + la nota de honestidad literal (copy.md), bajo el ranking — silencio
    /// cuando el mapa no tiene nada cargado ni a medias que contar todavía.
    @ViewBuilder private var grossReading: some View {
        if let reading = muscleReading {
            (Text("Rough read: ").font(StrandFont.caption).fontWeight(.semibold).foregroundColor(theme.ink)
             + Text(verbatim: reading.gross).font(StrandFont.caption).foregroundColor(theme.inkSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, CenitMetrics.gap)
        }
        Text("Load = sets that touch the muscle × how much it weighs in each exercise (primary 1, secondary ½) × time: every 2 days it's worth half. Fresh and loaded are compared against your most-loaded muscle, not a table. Sets = work sets from the last 7 days; 10–20 is a guide, not a target. You decide.")
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, CenitMetrics.space2)
    }

    // MARK: - Method foot — the cite, behind one disclosure
    //
    // FER-136 · V7 added the literal honesty note (`grossReading`, copy.md line 61) above, which
    // already states the mechanic in plain words — repeating it here as the button's visible teaser
    // would say the same thing twice on the same screen. The teaser now only names the citation this
    // foot exists for; the full paragraph (still with its academic cite) stays behind the tap.

    private var method: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(StrandMotion.interactive) { showMethod.toggle() } } label: {
                Text("See the method ›")
                    .font(StrandFont.caption).fontWeight(.semibold).foregroundColor(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, CenitMetrics.gap)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("See the method"))
            .accessibilityAddTraits(showMethod ? [.isSelected] : [])
            if showMethod {
                Text("Each set adds load to the muscles it works, decaying by half every two days: the time course of muscle protein synthesis (MacDougall 1995; Damas 2015). Color is relative to your most-loaded muscle, so it reads which of your muscles are hot right now. Weekly volume is judged against the 10–20 sets-per-week band (Schoenfeld 2017), a hypertrophy guide per muscle group; the volume shown is weighted by involvement, so secondary muscles count less. The recommendation crosses this with today's verdict, the same one Hoy shows: a day that asks you to ease off gates everything to rest.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)  // token-exempt: sin token exacto (edge ≠ rowVPad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: LiquidSpace.estadoVacioAire) {
            AnatomyBaseShape()
                .stroke(theme.hairline, lineWidth: 1.2)
                .aspectRatio(200.0 / 430.0, contentMode: .fit)
                .frame(maxHeight: 220)
                .padding(.top, CenitMetrics.space2)
            Text("Train to fill your map")
                .font(InstrumentoType.groteskHeadline(20)).foregroundStyle(theme.ink)
            Text("Log your sets and you'll see which muscles are loaded and which are fresh to train today.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, CenitMetrics.space2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CenitMetrics.screenPadding)
    }

    // MARK: - Data

    /// Weekly involvement-weighted volume for one muscle, oldest→newest, over the trailing 12 weeks —
    /// the detail's trend. Bucketed straight from the events (week = daysAgo / 7).
    private func weeklyTrend(for muscle: String) -> [Double] {
        let weeks = Self.trendDays / 7
        var buckets = [Double](repeating: 0, count: weeks)
        for e in events where e.muscle == muscle {
            let w = min(e.daysAgo / 7, weeks - 1)
            buckets[weeks - 1 - w] += e.involvement
        }
        return buckets
    }

    private func setsText(_ v: Double) -> String { MuscleFatigueMap.formattedSets(v) }

    private func load() async {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        guard let since = cal.date(byAdding: .day, value: -Self.trendDays, to: startToday) else {
            loaded = true; return
        }
        let rawSets = await repo.recentWorkSets(sinceTs: Int(since.timeIntervalSince1970))
        hasHistory = !rawSets.isEmpty
        let resetTs = Int(recoveryResetAt)
        let exercises = await repo.allExercises()
        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var ev: [MuscleFatigueMap.MuscleSetEvent] = []
        var hits: [String: [String: MuscleHit]] = [:]
        for set in rawSets where set.startTs >= resetTs {
            guard let ex = byId[set.exerciseId] else { continue }
            let setDay = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(set.startTs)))
            let daysAgo = cal.dateComponents([.day], from: setDay, to: startToday).day ?? 0
            for inv in ex.muscleInvolvement {
                ev.append(.init(muscle: inv.muscle, involvement: inv.weight, daysAgo: daysAgo))
                let primary = inv.weight >= Exercise.primaryWeight
                let existing = hits[inv.muscle]?[ex.id]
                if existing == nil || (primary && existing?.primary == false) {
                    hits[inv.muscle, default: [:]][ex.id] = MuscleHit(exerciseId: ex.id, name: StrengthDisplay.name(ex), primary: primary)
                }
            }
        }
        events = ev
        hitsByMuscle = hits.mapValues { dict in
            dict.values.sorted { ($0.primary ? 0 : 1, $0.name) < ($1.primary ? 0 : 1, $1.name) }
        }
        loaded = true
    }

    // MARK: - Volume section — «Volumen por músculo» (FER-719), folded in inline by FER-91 · E10
    //
    // A DIFFERENT reading from `ranking` above: not this week's recency, but the average weekly dose
    // over a span you pick, judged against the Schoenfeld 10–20 band. It keeps its own rows (bar vs
    // band + `movementFamilyTint`, not `MuscleLoadRow`'s ámbar recency rail) — the two rails answer
    // different questions and the épico's own spec preserves this section's rows as-is.

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Volume per muscle").groteskOverline().foregroundStyle(theme.inkTertiary)
            volumeSpanPicker
                .padding(.top, CenitMetrics.gap)
            if volumes.isEmpty {
                volumeEmptyState.padding(.top, LiquidSpace.topeScroll)
            } else {
                volumeRows.padding(.top, LiquidSpace.s150)
                volumeRailAxisMarks.padding(.top, CenitMetrics.space1)
                volumeInsightLine.padding(.top, CenitMetrics.gap)
            }
        }
        .padding(.top, LiquidSpace.topeScroll)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private var volumeSpanPicker: some View {
        SegmentedPillControl(Span.allCases, selection: $span, theme: theme) { $0.label }
    }

    private var volumeRows: some View {
        VStack(spacing: 0) {
            ForEach(volumes, id: \.muscle) { v in
                volumeRow(v)
            }
        }
    }

    private func volumeRow(_ v: MuscleFatigueMap.MuscleWeeklyVolume) -> some View {
        let below = v.band == .below
        return HStack(spacing: CenitMetrics.gap) {
            Text(MuscleAtlas.name(v.muscle))
                .font(StrandFont.body).foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let lo = MuscleFatigueMap.weeklyBandLow / railTop
                let hi = MuscleFatigueMap.weeklyBandHigh / railTop
                ZStack(alignment: .leading) {
                    // the 10–20 band, the fixed reference
                    RoundedRectangle(cornerRadius: 3).fill(theme.hairline)  // token-exempt: geometría de dato
                        .frame(width: w * (hi - lo), height: 14)
                        .offset(x: w * lo)
                    // the datum — each muscle wears its movement-family hue (handoff «Mis
                    // entrenamientos»: bars tell apart at a glance); below-band keeps the warning.
                    RoundedRectangle(cornerRadius: 3)  // token-exempt: geometría de dato
                        .fill(below ? theme.warning : theme.movementFamilyTint(primaryMuscles: [v.muscle]))
                        .frame(width: max(4, w * min(v.setsPerWeek, railTop) / railTop), height: 6)
                }
                .frame(height: 14, alignment: .leading)
            }
            .frame(height: 14)
            Text(setsText(v.setsPerWeek))
                .font(StrandFont.captionNumber)
                .fontWeight(below ? .semibold : .regular)
                .foregroundStyle(below ? theme.warning : theme.ink)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MuscleAtlas.name(v.muscle)))
        .accessibilityValue(Text("\(setsText(v.setsPerWeek)) sets per week") + Text(verbatim: ", ") + Text(volumeBandWord(v.band)))
    }

    private func volumeBandWord(_ b: MuscleFatigueMap.VolumeBand) -> LocalizedStringKey {
        switch b {
        case .below:  return "below the band"
        case .within: return "within the band"
        case .above:  return "above the band"
        }
    }

    // Rail axis marks — 0 / railTop/3 / 2·railTop/3 / railTop, under the bars only. Tick labels
    // aligned to the flexible rail column (same 96 + 12 + rail + 12 + 34 layout as `volumeRow`).
    private var volumeRailAxisMarks: some View {
        // Derived from `railTop` so a future band-rail change keeps the ticks honest (today 0 / 10 / 20 / 30).
        let marks: [Double] = [0, railTop / 3, 2 * railTop / 3, railTop]
        return HStack(spacing: CenitMetrics.gap) {
            Color.clear.frame(width: 96)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    // Edge ticks: "0" flush leading, top mark flush trailing (inside the rail width).
                    HStack {
                        Text("\(Int(marks[0].rounded()))")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: 0)
                        Text("\(Int(marks[marks.count - 1].rounded()))")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    // Mid ticks centered on their proportional positions along the rail.
                    ForEach(Array(marks.dropFirst().dropLast().enumerated()), id: \.offset) { _, mark in
                        Text("\(Int(mark.rounded()))")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                            .position(x: w * CGFloat(mark / railTop), y: h / 2)
                    }
                }
            }
            .frame(height: 14)
            Color.clear.frame(width: 34)
        }
        .accessibilityHidden(true)
    }

    // Insight foot — names the below-band muscles, actionably. The verdict-like line stays ON the
    // screen (FER-952 v2): which muscles sit below the band today.

    @ViewBuilder private var volumeInsightText: some View {
        if belowBand.isEmpty {
            Text("Every muscle you train is inside or above the band.")
        } else {
            let names = belowBand.prefix(2).map { MuscleAtlas.name($0.muscle) }
            let lead: Text = names.count >= 2
                ? Text(names[0]) + Text(" and ") + Text(names[1])
                : Text(names[0])
            lead + Text(" below the band · they could take 2–3 more sets a week.")
        }
    }

    private var volumeInsightLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(belowBand.isEmpty ? theme.verdict : theme.warning)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            volumeInsightText
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var volumeEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No sets in this range")
                .font(InstrumentoType.groteskHeadline(20)).foregroundStyle(theme.ink)
            Text("Log your workouts and you'll see each muscle's weekly volume against the band.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Fetch the max span (a year) once; the span picker re-slices in memory (`volumes`) with no more I/O.
    /// Unlike `load()` above, this ignores the manual recovery reset (FER-525): it reads history, not
    /// freshness — MuscleVolumeScreen's original contract, unchanged by the fusion.
    private func loadVolume() async {
        let cal = Calendar.current
        guard let since = cal.date(byAdding: .day, value: -Span.y1.rawValue, to: cal.startOfDay(for: Date())) else {
            loadedVolume = true; return
        }
        volumeEvents = await repo.muscleSetEvents(sinceTs: Int(since.timeIntervalSince1970))
        loadedVolume = true
    }
}

// MARK: - Selection wrapper (sheet item)

private struct MuscleSelection: Identifiable {
    let muscle: String
    var id: String { muscle }
}

/// One exercise the user did that works a muscle.
struct MuscleHit: Hashable {
    let exerciseId: String
    let name: String
    let primary: Bool
}

// MARK: - Body figures (anatomical)

private struct BodyFiguresView: View {
    let theme: InstrumentoTheme
    let loadByMuscle: [String: MuscleFatigueMap.MuscleLoad]
    let maxLoad: Double
    /// The most-loaded muscle — outlined to tie the figure to the floating label.
    let highlight: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: CenitMetrics.space2) {
            figure(.front)
            figure(.back)
        }
    }

    private func figure(_ side: MuscleAtlas.Side) -> some View {
        VStack(spacing: 5) {
            ZStack {
                // The silhouette is stroke-only (fill:none) so the body reads as paper and color
                // lives only in the tinted muscles — the «Instrumento» rule (owner-approved, FER-781).
                AnatomyBaseShape()
                    .stroke(theme.hairline, lineWidth: 1.2)
                ForEach(MuscleAnatomy.paths(for: side)) { item in
                    let shape = SVGPath(segs: item.segs)
                    let isTop = highlight == item.muscle
                    shape
                        .fill(color(for: item.muscle))
                        .overlay(shape.stroke(isTop ? theme.ink : theme.hairlineStrong.opacity(StrandOpacity.dim),
                                              lineWidth: isTop ? 2 : 0.6))
                        .contentShape(shape)
                        .onTapGesture { onSelect(item.muscle) }
                        .accessibilityLabel(Text(MuscleAtlas.name(item.muscle)))
                        .accessibilityValue(Text(stateText(item.muscle)))
                }
            }
            .aspectRatio(200.0 / 430.0, contentMode: .fit)
            Text(side == .front ? "Front" : "Back")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for muscle: String) -> Color {
        guard let m = loadByMuscle[muscle], maxLoad > 0 else { return theme.muscleStateColor(0) }
        return theme.muscleStateColor(m.relative)
    }

    private func stateText(_ muscle: String) -> LocalizedStringKey {
        guard let m = loadByMuscle[muscle] else { return "fresh" }
        switch m.state {
        case .fresh: return "fresh"
        case .moderate: return "moderate"
        case .loaded: return "loaded"
        }
    }
}

// MARK: - Muscle detail

private struct MuscleDetailView: View {
    let theme: InstrumentoTheme
    let muscle: String
    let load: MuscleFatigueMap.MuscleLoad?
    let weeklyTrend: [Double]
    let hits: [MuscleHit]
    /// FER-82: the day's verdict already decided whether anything is cleared today; the sheet
    /// receives that answer, never a score to re-judge with.
    let systemicGate: Bool

    private var weeklySets: Double { load?.weeklySets ?? 0 }
    private var state: MuscleFatigueMap.LoadState { load?.state ?? .fresh }

    /// The measured content height — drives a fitted sheet detent so the sheet rises only as far as the
    /// content needs (with `.large` as a fallback when the content is taller than the fitted height, e.g.
    /// large Dynamic Type).
    @State private var contentHeight: CGFloat = 420

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text(MuscleAtlas.name(muscle)).instrumentoOverlineProminent().foregroundStyle(theme.inkSecondary)

                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                    Text(MuscleFatigueMap.formattedSets(weeklySets))
                        .font(InstrumentoType.groteskHeroNumeral(52)).foregroundStyle(stateColor)
                    Text("sets · 7 d").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }

                volumeBand
                statTiles
                if weeklyTrend.contains(where: { $0 > 0 }) { trend }
                if !hits.isEmpty { exercises }
                recommendation
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in contentHeight = h }
            })
        }
        // FER-202 (Ola · anillo 3): fondo de vidrio El Eje. Sin `EntrenarHojaCabecera`: hoy no hay
        // control de salida propio (solo swipe-dismiss + detents) — agregar `.cerrar` añadiría un
        // control (REGLA SUPREMA). Se conserva el overline del músculo y el sizing por contenido.
        .entrenarHojaFondo(tono: .neutro)
        .presentationDetents([.height(contentHeight), .large])
        .presentationDragIndicator(.visible)
    }

    /// The state hue. «Fresh» uses the map's sage (the head of `muscleLoadRamp`) so the fresh→loaded
    /// color chain is a SINGLE scale across the map and the detail (FER-350 redesign · #6).
    private var stateColor: Color {
        switch state {
        case .fresh: return theme.muscleLoadColor(0)
        case .moderate: return theme.warning
        case .loaded: return theme.muscleLoadColor(1)
        }
    }

    // Weekly volume vs the Schoenfeld 10–20 band, scaled to a 0–30 track.
    private var volumeBand: some View {
        let lo = MuscleFatigueMap.weeklyBandLow, hi = MuscleFatigueMap.weeklyBandHigh
        let top = MuscleFatigueMap.weeklyVolumeRailTop
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.hairline).frame(height: 8)  // token-exempt: geometría de dato
                    Rectangle().fill(theme.hairlineStrong)
                        .frame(width: w * (hi - lo) / top, height: 8)
                        .offset(x: w * lo / top)
                    RoundedRectangle(cornerRadius: 1).fill(stateColor)  // token-exempt: geometría de dato
                        .frame(width: 2, height: 16)
                        .offset(x: min(w - 2, w * min(weeklySets, top) / top))
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text("0").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("band 10–20").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("30+").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Text(bandText).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bandText: LocalizedStringKey {
        switch load?.band ?? .below {
        case .below: return "Below the recommended band: room for more volume this week."
        case .within: return "Within the recommended weekly band."
        case .above: return "Above the recommended band: a lot of volume this week."
        }
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            tile(title: "Last time", value: lastText)
            tile(title: "State", value: stateText, color: stateColor)
        }
    }

    private func tile(title: LocalizedStringKey, value: LocalizedStringKey, color: Color? = nil) -> some View {
        EntrenarTile(tono: .neutro) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Text(value).font(InstrumentoType.groteskTileValue).foregroundStyle(color ?? theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lastText: LocalizedStringKey {
        guard let d = load?.daysSinceLast else { return "—" }
        return d == 0 ? "today" : d == 1 ? "yesterday" : "\(d) d ago"
    }

    private var stateText: LocalizedStringKey {
        switch state {
        case .fresh: return "Fresh"
        case .moderate: return "Moderate"
        case .loaded: return "Loaded"
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trend · sets/week").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            TrendLine(values: weeklyTrend, color: stateColor)
                .frame(height: 48)
        }
    }

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Exercises that work it").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, CenitMetrics.space2)
            ForEach(Array(hits.prefix(6)), id: \.exerciseId) { hit in
                HStack {
                    Text(hit.name).font(StrandFont.body).foregroundStyle(theme.ink)
                    Spacer()
                    Text(hit.primary ? "primary" : "secondary")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                }
                .padding(.vertical, 7)  // token-exempt(optico): pad vertical de la fila ejercicio-etiqueta, entre space2 (8) y rowVPad (10) — sin paso exacto
                .overlay(alignment: .bottom) {
                    if hit.exerciseId != hits.prefix(6).last?.exerciseId {
                        Rectangle().fill(theme.hairline).frame(height: 0.5)
                    }
                }
            }
        }
    }

    private var recommendation: some View {
        let readiness = systemicGate ? MuscleFatigueMap.Readiness.rest
                                     : MuscleFatigueMap.readiness(state: state, recovery: nil)
        return Text(recommendationText(readiness))
            .font(InstrumentoType.groteskTileValue).foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(CenitMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func recommendationText(_ r: MuscleFatigueMap.Readiness) -> LocalizedStringKey {
        switch r {
        case .rest: return "Today's verdict asks you to ease off: rest or train light."
        case .caution: return "Still loaded: give it a day or two before training it again."
        case .ready: return "Fresh and ready: a good muscle to train today."
        }
    }
}

// MARK: - Tiny trend line (self-contained, no shared component coupling)

private struct TrendLine: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 1)
            let n = max(values.count - 1, 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(n)
                    let y = geo.size.height * (1 - CGFloat(v / maxV))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
    }
}

// MARK: - Fatigue-state colour

private extension InstrumentoTheme {
    /// Maps a muscle's relative load (0…1) onto `muscleLoadRamp` by fatigue STATE, so a fresh muscle reads
    /// green, a moderate one amber and a loaded one red. The raw ramp puts its green only near 0, so a muscle
    /// classified «fresh» (relative < `freshBelow`) painted at its raw fraction came out amber — contradicting
    /// the recommendation card. Each state band maps to its own slice of the ramp, keeping a gentle gradient
    /// within the band so the ranking still reads. (FER-516)
    func muscleStateColor(_ relative: Double) -> Color {
        let fresh = MuscleFatigueMap.freshBelow
        let loaded = MuscleFatigueMap.loadedAbove
        let position: Double
        if relative < fresh {
            position = relative / fresh * 0.06
        } else if relative < loaded {
            position = 0.45 + (relative - fresh) / (loaded - fresh) * 0.10
        } else {
            position = 0.80 + (relative - loaded) / (1 - loaded) * 0.20
        }
        return muscleLoadColor(position)
    }
}
#endif
