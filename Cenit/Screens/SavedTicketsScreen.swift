#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// SavedTicketsScreen.swift — «Tickets guardados»: grid of thermal mini-receipts for completed
// strength sessions. Read-only — never edits or deletes. Pushed from WorkoutHistoryScreen via
// `SavedTicketsRoute` on the Entrenar NavigationStack. Tap → existing `WorkoutSessionRoute` detail.

struct SavedTicketsScreen: View {
    @Environment(\.instrumentoTheme) private var theme
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
        GridItem(.flexible(), spacing: CenitMetrics.gap),
        GridItem(.flexible(), spacing: CenitMetrics.gap)
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
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                segmentControl
                if loaded {
                    if filteredSessions.isEmpty {
                        emptyState
                    } else {
                        ticketGrid
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task { await load() }
        .fullScreenCover(item: $receiptTarget) { target in
            ReceiptPrinterScreen(theme: theme, summary: target.summary,
                                 sessionId: target.sessionId, onClose: { receiptTarget = nil })
        }
        .enableInjection()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            InstrumentoFlowTitle(Text("Saved tickets"))
            Text("\(sessions.count) receipts · tap one to reprint")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segmentControl: some View {
        SegmentedPillControl([Segment.all, .strength, .cardio], selection: $segment, theme: theme) { seg in
            switch seg {
            case .all: return String(localized: "All")
            case .strength: return String(localized: "Strength")
            case .cardio: return String(localized: "Cardio")
            }
        }
    }

    private var ticketGrid: some View {
        LazyVGrid(columns: columns, spacing: CenitMetrics.gap) {
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
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: CenitMetrics.gap) {
            Image(systemName: "doc.plaintext")
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text(emptyTitle).font(InstrumentoType.groteskHeadline(20)).foregroundStyle(theme.ink)
            Text(emptyCaption)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CenitMetrics.sectionGap)
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
