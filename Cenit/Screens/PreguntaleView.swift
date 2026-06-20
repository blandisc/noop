import SwiftUI
import StrandDesign
import StrandAnalytics

// PreguntaleView.swift — the unified "Pregúntale a tus datos" entry (FER-308).
//
// One door, three tiers (see CoachAvailability):
//   • on-device (Apple Intelligence) → free text, grounded, "pensando" state.
//   • templates-only ("Modo esencial") → why-it's-unavailable + chips + engine templates.
//   • external (Nivel 3) → the preserved BYO-key LLM chat (CoachView), reachable from either.
//
// «Instrumento diurno»: warm paper, color only on the datum (handled by the engine's own readings),
// hierarchy by space. Only StrandDesign tokens.

struct PreguntaleView: View {
    let grounding: CoachGrounding
    /// Behavior insights (with their breakdown) so a what-if can hand off to a 7-day experiment (FER-333).
    var behaviorInsights: [Insight] = []

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var coach: AICoachEngine
    @State private var showExternal = false

    private var availability: (tier: CoachTier, reason: CoachUnavailableReason?) {
        CoachAvailability.current()
    }

    var body: some View {
        Group {
            #if canImport(FoundationModels)
            if #available(iOS 26, *), availability.tier == .onDevice {
                OnDeviceChatScreen(grounding: grounding, behaviorInsights: behaviorInsights,
                                   openExternal: { showExternal = true })
            } else {
                EssentialModeScreen(grounding: grounding,
                                    reason: availability.reason ?? .osTooOld,
                                    openExternal: { showExternal = true })
            }
            #else
            EssentialModeScreen(grounding: grounding,
                                reason: availability.reason ?? .osTooOld,
                                openExternal: { showExternal = true })
            #endif
        }
        .background(theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showExternal) {
            CoachView()
                .instrumentoTheme(theme)
                .environmentObject(coach)
        }
    }
}

// MARK: - Shared pieces

/// The header: title + a tier badge ("On-device" / "Modo esencial").
private struct PreguntaleHeader: View {
    let onDevice: Bool
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        HStack {
            Text("Pregúntale a tus datos")
                .font(StrandFont.title2).foregroundStyle(theme.ink)
            Spacer()
            HStack(spacing: 5) {
                if onDevice { Image(systemName: "cpu").font(.system(size: 11)) }
                Text(onDevice ? "On-device" : "Modo esencial")
                    .font(StrandFont.footnote)
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(onDevice ? "Respuestas en tu iPhone" : "Modo esencial, sin Apple Intelligence")
        }
    }
}

/// The "respuestas más profundas con tu IA" upgrade row (Nivel 3 — external LLM, opt-in).
private struct ExternalUpgradeRow: View {
    let hasKey: Bool
    let action: () -> Void
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(theme.inkSecondary)
                Text(hasKey ? "Respuestas más profundas con tu IA" : "Conecta tu IA · opcional")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.inkTertiary)
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .stroke(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// One answer bubble built from the engine's words.
private struct AnswerBubble: View {
    let text: String
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(StrandFont.body).foregroundStyle(theme.ink)
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal").font(.system(size: 11))
                Text("Solo cifras del motor · sin red").font(StrandFont.footnote)
            }
            .foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .stroke(theme.hairline, lineWidth: 1))
    }
}

// MARK: - Modo esencial (Level 1)

/// "Modo esencial": shown when there's no Apple Intelligence. Explains WHY (and what the user needs),
/// then offers pre-armed chips answered with deterministic engine templates (no model, no network).
private struct EssentialModeScreen: View {
    let grounding: CoachGrounding
    let reason: CoachUnavailableReason
    let openExternal: () -> Void

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var coach: AICoachEngine
    @State private var answer: String?
    @State private var lastAsked: CoachChip?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PreguntaleHeader(onDevice: false)

                // The coach speaks first — seed with today's standout so the box is never blank.
                CoachOpenerBubble(text: grounding.opener())

                // Dynamic suggestions (ordered by what stands out today), or follow-ups after answering.
                let chips = answer == nil ? grounding.suggestedChips()
                                          : grounding.followUpChips(after: lastAsked ?? .today)
                FlowChips(chips: chips, theme: theme) { chip in
                    lastAsked = chip
                    answer = grounding.deterministicAnswer(forChip: chip)
                }

                if let answer { AnswerBubble(text: answer) }

                // Why it's only the essential mode + what's needed (quieter, below the value).
                VStack(alignment: .leading, spacing: 8) {
                    Label(reason.title, systemImage: "info.circle")
                        .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.inkSecondary)
                        .labelStyle(.titleAndIcon)
                    Text(reason.detail).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    Divider().overlay(theme.hairline)
                    Text("Qué necesitas").font(StrandFont.footnote.weight(.semibold)).foregroundStyle(theme.ink)
                    Text(CoachUnavailableReason.requirements)
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .stroke(theme.hairline, lineWidth: 1))

                ExternalUpgradeRow(hasKey: coach.hasKey, action: openExternal)
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The coach's opening line as a left bubble (no "engine figures" footer — it's an invitation, not a datum).
private struct CoachOpenerBubble: View {
    let text: String
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        Text(text)
            .font(StrandFont.body).foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .stroke(theme.hairline, lineWidth: 1))
    }
}

/// A wrapping row of tappable question chips.
private struct FlowChips: View {
    let chips: [CoachChip]
    let theme: InstrumentoTheme
    let onTap: (CoachChip) -> Void

    var body: some View {
        // A simple two-column adaptive grid keeps it readable at any Dynamic Type size.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Button { onTap(chip) } label: {
                    Text(chip.question)
                        .font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .background(theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - On-device chat (Level 2)

/// Identifiable wrapper so a what-if's `Insight` can drive `.sheet(item:)` for the experiment handoff.
private struct StartExperimentItem: Identifiable {
    let id = UUID()
    let insight: Insight
}

#if canImport(FoundationModels)
@available(iOS 26, *)
private struct OnDeviceChatScreen: View {
    let grounding: CoachGrounding
    let openExternal: () -> Void

    let behaviorInsights: [Insight]

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @StateObject private var engine: OnDeviceCoachEngine
    @State private var draft = ""
    @State private var startItem: StartExperimentItem?

    init(grounding: CoachGrounding, behaviorInsights: [Insight], openExternal: @escaping () -> Void) {
        self.grounding = grounding
        self.behaviorInsights = behaviorInsights
        self.openExternal = openExternal
        _engine = StateObject(wrappedValue: OnDeviceCoachEngine(grounding: grounding))
    }

    /// The behavior insight matching the last what-if, so we can offer to test it as an experiment.
    private var whatIfInsight: Insight? {
        guard let wi = engine.lastWhatIf else { return nil }
        return behaviorInsights.first { $0.lever?.behavior == wi.behavior && $0.lever?.outcome == wi.outcome }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PreguntaleHeader(onDevice: true)

                    // "Cómo funciona" explainer.
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(theme.dataRecovery)
                        Text("Cómo funciona: el modelo de Apple Intelligence de tu iPhone redacta la respuesta apoyándose en tus cifras reales. Nunca inventa números y nada sale del teléfono.")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    }
                    .padding(12)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                        .stroke(theme.hairline, lineWidth: 1))

                    // The coach speaks first + dynamic suggestions, until the user starts.
                    if engine.messages.isEmpty {
                        CoachOpenerBubble(text: grounding.opener())
                        FlowChips(chips: grounding.suggestedChips(), theme: theme) { chip in
                            Task { await engine.send(chip.question) }
                        }
                    }

                    ForEach(engine.messages) { msg in
                        if msg.role == .user {
                            Text(msg.text)
                                .font(StrandFont.body).foregroundStyle(theme.paper)
                                .padding(.vertical, 10).padding(.horizontal, 13)
                                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            AnswerBubble(text: msg.text)
                        }
                    }

                    if engine.thinking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Pensando…").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Pensando")
                    }

                    // What-if → close the loop: offer to turn it into a 7-day experiment (FER-333).
                    if !engine.thinking, let insight = whatIfInsight {
                        Button { startItem = StartExperimentItem(insight: insight) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "flask").font(.system(size: 14))
                                Text("Convertirlo en experimento de 7 días").font(StrandFont.subhead)
                                Spacer()
                                Image(systemName: "arrow.right").font(.system(size: 13))
                            }
                            .foregroundStyle(theme.ink)
                            .padding(.vertical, 11).padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                                .strokeBorder(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .buttonStyle(.plain)
                    }

                    // Follow-up suggestions once there's an answer on screen.
                    if !engine.messages.isEmpty && !engine.thinking {
                        FlowChips(chips: grounding.followUpChips(after: .today), theme: theme) { chip in
                            Task { await engine.send(chip.question) }
                        }
                    }

                    ExternalUpgradeRow(hasKey: coach.hasKey, action: openExternal)
                }
                .padding(NoopMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            composer
        }
        .onChange(of: engine.thinking) { _, now in
            if now { AccessibilityNotification.Announcement("Pensando").post() }
        }
        .sheet(item: $startItem) { item in
            StartExperimentSheet(insight: item.insight, theme: theme) { behavior, outcome, sign in
                // `startExperiment` returns nil when one is already running (one-at-a-time) — don't
                // claim we started it then.
                let started = await repo.startExperiment(behavior: behavior, outcome: outcome, expectedSign: sign)
                startItem = nil
                engine.messages.append(ChatMessage(role: .assistant, text: started != nil
                    ? "Listo, empecé tu experimento de 7 días con \(behavior.lowercased()). Lo verás en el Bucle, en «Tu experimento»."
                    : "Ya tienes un experimento en curso. Cuando termine, podrás probar este — lo ves en el Bucle, en «Tu experimento»."))
                engine.lastWhatIf = nil
            }
            .instrumentoTheme(theme)
            .environmentObject(repo)
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Escribe tu pregunta…", text: $draft, axis: .vertical)
                .font(StrandFont.body).foregroundStyle(theme.ink)
                .lineLimit(1...4)
                .padding(.vertical, 9).padding(.leading, 14)
            Button {
                let q = draft
                draft = ""
                Task { await engine.send(q) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.paper)
                    .frame(width: 32, height: 32)
                    .background(theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.isResponding)
            .accessibilityLabel("Enviar pregunta")
        }
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().stroke(theme.hairline, lineWidth: 1))
        .padding(NoopMetrics.screenPadding)
    }
}
#endif
