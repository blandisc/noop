import Foundation
import StrandAnalytics

#if canImport(FoundationModels)
import FoundationModels

// OnDeviceCoach.swift — Level 2 of "Pregúntale a tus datos" (FER-308/332): free-text questions
// answered by Apple's on-device model (`FoundationModels`).
//
// THE WHOLE FILE is gated behind `#if canImport(FoundationModels)` + `@available(iOS 26, *)`.
// `FoundationModels` is a platform framework and must never leak into `Packages/**`.
//
// Inverted hierarchy (FER-332): the ENGINE is the source of truth, the model is polish. For each
// question we (1) classify the topic, (2) build the deterministic, engine-only answer for that topic
// (`CoachGrounding`), and (3) ask the model to REWRITE it naturally — never to invent. If the model
// is empty, errors, or slips a fabricated user-metric past `validate`, we show the deterministic
// answer verbatim. So the worst case is still a correct, on-topic answer — never the nonsense the
// FER-308 spike produced. No network: the model runs locally; this file opens no `URLSession`.

/// Drives the on-device free-text coach. `@MainActor` so every `@Published` mutation is main-thread;
/// the model call hops off-main inside `respond` and results are applied back here.
@available(iOS 26, *)
@MainActor
final class OnDeviceCoachEngine: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var thinking = false
    @Published var errorText: String?
    /// Set when the last answer was a grounded what-if about a behavior — drives the "turn it into a
    /// 7-day experiment" handoff (FER-333). Cleared on any non-what-if answer.
    @Published var lastWhatIf: WhatIfResult?

    private let grounding: CoachGrounding
    private let session: LanguageModelSession

    init(grounding: CoachGrounding) {
        self.grounding = grounding
        self.session = LanguageModelSession(
            instructions: Instructions {
                """
                Eres un coach de recuperación y sueño que habla español de México, cálido y directo.
                Te voy a dar la PREGUNTA del usuario y una RESPUESTA BASE construida con sus datos reales.
                Tu trabajo es REESCRIBIR esa base para que suene natural y conteste directo la pregunta.
                Reglas:
                1) No cambies NINGUNA cifra de la base ni inventes métricas del usuario.
                2) Puedes añadir UN consejo general breve (p. ej. "duerme 7–9 horas", "zona 2") — eso es
                consejo normal, no una cifra del usuario.
                3) 2–3 frases, sin tecnicismos ni emojis. No eres médico: no diagnostiques.
                """
            }
        )
    }

    /// True while the model is generating — bind buttons to its inverse to prevent concurrent calls.
    var isResponding: Bool { session.isResponding }

    /// Ask a free-text question. Classifies the topic, builds the engine's deterministic answer for
    /// it, and asks the model to rewrite it. Falls back to the deterministic answer on any failure
    /// (empty, error, or a fabricated user-metric caught by `validate`). Never throws.
    func send(_ userText: String) async {
        let q = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !session.isResponding else { return }

        errorText = nil
        messages.append(ChatMessage(role: .user, text: q))
        thinking = true
        defer { thinking = false }

        // The engine owns the answer; the model only rewrites it. A what-if about a logged behavior
        // gets the grounded historical contrast (and unlocks the experiment handoff).
        let whatIf = grounding.whatIf(q)
        lastWhatIf = whatIf
        let base = whatIf?.statement ?? grounding.deterministicAnswer(forTopic: CoachTopic.classify(q))

        do {
            let rewritten = try await session.respond(to: """
                Pregunta del usuario: \(q)

                Respuesta base (no cambies las cifras): \(base)

                Reescríbela natural y directa.
                """).content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Show the rewrite only if it didn't slip in a fabricated user metric; else the base.
            let safe = (!rewritten.isEmpty && grounding.validate(answer: rewritten).isEmpty) ? rewritten : base
            messages.append(ChatMessage(role: .assistant, text: safe))
        } catch {
            errorText = "No pude redactar en tu iPhone ahora; te dejo la lectura del motor."
            messages.append(ChatMessage(role: .assistant, text: base))
        }
    }
}
#endif
