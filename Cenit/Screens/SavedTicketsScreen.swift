#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// SavedTicketsScreen.swift — «Tickets guardados»: grid of thermal mini-receipts for completed
// strength sessions. Read-only — never edits or deletes. Pushed from WorkoutHistoryScreen via
// `SavedTicketsRoute` on the Entrenar NavigationStack. Tap → existing `WorkoutSessionRoute` detail.
// FER-293: piel Liquid Glass · El Eje (cabecera de flujo, vacío alineado a la izquierda, LiquidAviso).

struct SavedTicketsScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// Filter chips. `StrengthSession` has no cardio/strength flag — every stored session is strength.
    /// `.cardio` always yields an empty list (honest degradation until a real classifier exists).
    private enum Segment: Hashable { case all, strength, cardio }

    @State private var segment: Segment = .all
    @State private var sessions: [StrengthSession] = []
    @State private var routineNames: [String: String] = [:]
    @State private var volumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    @State private var loaded = false
    /// `repo.storeHandle()` came back nil — a real read failure, distinct from «cero tickets»
    /// (Estados, decisión #16 del épico, FER-90).
    @State private var readError = false

    /// The receipt being reprinted (tap → reconstruct summary → present the printer). nil = closed.
    @State private var receiptTarget: ReceiptTarget?
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject
    private struct ReceiptTarget: Identifiable {
        let id = UUID()
        let summary: StrengthSummary
        let sessionId: String
    }

    private let columns = [
        GridItem(.flexible(), spacing: LiquidSpace.s300),
        GridItem(.flexible(), spacing: LiquidSpace.s300)
    ]

    /// Filtered list for the active segment. Newest-first order is preserved from `recentSessions`.
    private var filteredSessions: [StrengthSession] {
        switch segment {
        case .all, .strength:
            return sessions
        case .cardio:
            // Every StrengthSession is strength; no cardio classifier on this store path.
            return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                header
                segmentControl
                if loaded {
                    if readError {
                        readErrorBanner
                    } else if filteredSessions.isEmpty {
                        emptyState
                    } else {
                        ticketGrid
                    }
                }
            }
            .padding(.top, LiquidSpace.topeScroll)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-199 (Ola 3, épico FER-195): fondo de vidrio El Eje en vez del papel plano — la
        // pantalla llega empujada (SavedTicketsRoute) y conserva su navegación/toolbar del stack
        // ambiente tal cual, sin cabecera propia que sustituir.
        .entrenarHojaFondo(tono: .neutro)
        .task { await load() }
        .fullScreenCover(item: $receiptTarget) { target in
            ReceiptPrinterScreen(summary: target.summary,
                                 sessionId: target.sessionId, onClose: { receiptTarget = nil })
        }
        .enableInjection()
    }

    private var header: some View {
        // FER-293: la línea de conteo SUBE a kicker (mismo orden que Biblioteca / Detalle).
        LiquidFlowTitle(
            kicker: String(localized: "\(sessions.count) receipts · tap one to reprint"),
            titulo: String(localized: "Saved tickets"))
    }

    private var segmentControl: some View {
        SegmentedPillControl([Segment.all, .strength, .cardio], selection: $segment) { seg in
            switch seg {
            case .all: return String(localized: "All")
            case .strength: return String(localized: "Strength")
            case .cardio: return String(localized: "Cardio")
            }
        }
    }

    private var ticketGrid: some View {
        LazyVGrid(columns: columns, spacing: LiquidSpace.s300) {
            ForEach(Array(filteredSessions.enumerated()), id: \.element.id) { index, session in
                Button { openReceipt(session) } label: {
                    MiniTicketView(ticket: TicketMapping.miniTicket(
                        for: session,
                        index: index,
                        routineName: session.routineId.flatMap { routineNames[$0] },
                        volumeKg: volumes[session.id]?.volumeKg ?? 0,
                        system: system
                    ))
                }
                .buttonStyle(.liquidPress)
            }
        }
    }

    private var emptyState: some View {
        // FER-293: misma receta del Detalle — alineado a la IZQUIERDA (única desviación de «solo piel»).
        VStack(alignment: .leading, spacing: .zero) {
            Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                Image(systemName: "doc.plaintext")
                    .font(LiquidType.infoGlifoTitular)
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
                Text(emptyTitle)
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(emptyCaption)
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, LiquidSpace.s400)
        }
    }

    /// «Error de lectura» (Estados, decisión #16 del épico): LiquidAviso sustituye el
    /// `patternBlock` crítico (FER-293).
    private var readErrorBanner: some View {
        LiquidAviso(
            titulo: String(localized: "Couldn't read your saved tickets"),
            cuerpo: String(localized: "Try again."),
            tono: LiquidColor.negativo)
    }

    private var emptyTitle: LocalizedStringKey {
        switch segment {
        case .cardio: return "No cardio tickets yet"
        case .all, .strength: return "No tickets yet"
        }
    }

    private var emptyCaption: LocalizedStringKey {
        switch segment {
        case .cardio:
            return "Cardio sessions will show up here once they save a receipt."
        case .all, .strength:
            return "When you finish a strength session, its receipt lands here."
        }
    }

    // MARK: - Derived (mirrors WorkoutHistoryScreen)

    private func name(for session: StrengthSession) -> String {
        session.routineId.flatMap { routineNames[$0] } ?? String(localized: "Strength workout")
    }

    /// Tap → reconstruct the session's summary from stored data, then present the receipt printer as a
    /// full-screen cover (the reprint path, mirroring the end-of-session receipt).
    private func openReceipt(_ session: StrengthSession) {
        Task {
            let sets = await repo.sessionSets(sessionId: session.id)
            let all = await repo.allExercises()
            let names = Dictionary(all.map { ($0.id, StrengthDisplay.name($0)) },
                                   uniquingKeysWith: { a, _ in a })
            let summary = ReceiptMapping.summary(session: session, sets: sets,
                                                 exerciseNames: names, routineName: name(for: session))
            receiptTarget = ReceiptTarget(summary: summary, sessionId: session.id)
        }
    }

    private func load() async {
        // Estados → «Error de lectura»: igual que `WorkoutHistoryScreen.load()`, adelantada al frente.
        guard await repo.storeHandle() != nil else {
            readError = true
            loaded = true
            return
        }
        readError = false
        async let s = repo.recentSessions()
        async let r = repo.routines()
        async let v = repo.sessionVolumes()
        let (sessions, routines, volumes) = await (s, r, v)
        self.sessions = sessions
        self.routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        self.volumes = volumes
        self.loaded = true
    }
}
#endif
