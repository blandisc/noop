import Foundation
import StrandAnalytics

#if canImport(FoundationModels)
import FoundationModels

// OnDeviceCoach.swift — Level 2 of "Pregúntale a tus datos" (FER-308): free-text questions answered
// by Apple's on-device model (`FoundationModels`), grounded on the InsightEngine's real numbers.
//
// THE WHOLE FILE is gated behind `#if canImport(FoundationModels)` + `@available(iOS 26, *)`.
// `FoundationModels` is a platform framework and must never leak into `Packages/**` — the pure
// grounding it speaks lives in `StrandAnalytics` (`CoachGrounding`); this file only wires the model.
//
// Golden rule (the model never invents a figure): the model is told to source every number from the
// tool, AND every reply is run through `CoachGrounding.validate` — if it cites a figure the engine
// didn't produce, we discard it and fall back to the deterministic Level-1 answer. No network: the
// model runs locally; this file opens no `URLSession`.

/// The grounding tool the model calls to get the user's real numbers. It returns the engine's
/// compact fact summary verbatim — it computes nothing.
@available(iOS 26, *)
struct CoachFactsTool: Tool {
    let name = "obtenerHechosDelUsuario"
    let description = "Devuelve los hechos y cifras reales del usuario (recuperación, sueño, HRV, hallazgos) calculados por el motor on-device. Úsalo SIEMPRE antes de responder y cita solo estas cifras."

    let grounding: CoachGrounding

    @Generable
    struct Arguments {
        @Guide(description: "El tema de la pregunta del usuario, p. ej. sueño, recuperación, energía.")
        let tema: String
    }

    func call(arguments: Arguments) async throws -> String {
        grounding.toolContextString()
    }
}

/// Drives the on-device free-text coach. `@MainActor` so every `@Published` mutation is main-thread;
/// the model call hops off-main inside `respond` and results are applied back here.
@available(iOS 26, *)
@MainActor
final class OnDeviceCoachEngine: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var thinking = false
    @Published var errorText: String?

    private let grounding: CoachGrounding
    private let session: LanguageModelSession

    init(grounding: CoachGrounding) {
        self.grounding = grounding
        self.session = LanguageModelSession(
            tools: [CoachFactsTool(grounding: grounding)],
            instructions: Instructions {
                """
                Eres un coach de recuperación y sueño que habla español de México, cálido y directo.
                Reglas estrictas:
                1) NUNCA inventes cifras. Llama a la herramienta obtenerHechosDelUsuario y usa SOLO los \
                números que devuelve. Si no hay un dato, dilo; no lo estimes.
                2) Responde corto (2–4 frases), accionable, sin tecnicismos ni emojis.
                3) No eres médico: no diagnostiques.
                """
            }
        )
    }

    /// True while the model is generating — bind buttons to its inverse to prevent concurrent calls.
    var isResponding: Bool { session.isResponding }

    /// Ask a free-text question. Appends the turn, runs the on-device model, validates the reply
    /// against the engine's allowed figures, and falls back to the deterministic answer on any
    /// failure (empty reply, fabricated figure, or model error). Never throws.
    func send(_ userText: String) async {
        let q = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !session.isResponding else { return }

        errorText = nil
        messages.append(ChatMessage(role: .user, text: q))
        thinking = true
        defer { thinking = false }

        do {
            let reply = try await session.respond(to: q).content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fabricated = grounding.validate(answer: reply)
            if reply.isEmpty || !fabricated.isEmpty {
                // Golden-rule guard tripped (or empty) → use the engine's own words instead.
                messages.append(ChatMessage(role: .assistant, text: grounding.deterministicAnswer(forChip: .today)))
            } else {
                messages.append(ChatMessage(role: .assistant, text: reply))
            }
        } catch {
            errorText = "No pude responder en tu iPhone ahora. Te dejo la lectura del motor."
            messages.append(ChatMessage(role: .assistant, text: grounding.deterministicAnswer(forChip: .today)))
        }
    }
}
#endif
