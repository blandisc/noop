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
                Reglas:
                1) Responde DIRECTO la pregunta que te hacen. Si preguntan "cuánto debería dormir", \
                da un rango concreto; si preguntan "por qué amanecí cansado", explica la causa.
                2) Para las CIFRAS DEL USUARIO (su recuperación, HRV, pulso, sueño, etc.) usa SOLO la \
                herramienta obtenerHechosDelUsuario; nunca des un valor distinto al que devuelve, ni \
                inventes una métrica suya. Si no hay un dato, dilo.
                3) SÍ puedes dar recomendaciones generales con números (p. ej. "duerme 7–9 horas", \
                "zona 2", "80/20") — eso es consejo normal, no una cifra del usuario.
                4) Corto (2–4 frases), accionable, sin tecnicismos ni emojis. No eres médico: no diagnostiques.
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
            var reply = try await session.respond(to: q).content
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Golden-rule guard (FER-330): only fires if the model misquoted one of the USER's own
            // metrics (a number with a metric unit the engine never produced). If so, ask it once to
            // restate using only the tool's figures, keeping its answer to the same question.
            if !reply.isEmpty, !grounding.validate(answer: reply).isEmpty {
                let corrected = try await session.respond(to: """
                    En tu respuesta anterior citaste una cifra de mis métricas que no está en los hechos. \
                    Vuelve a responder LA MISMA pregunta usando solo las cifras de la herramienta para \
                    mis datos; los consejos generales con números están bien.
                    """).content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !corrected.isEmpty, grounding.validate(answer: corrected).isEmpty {
                    reply = corrected
                } else {
                    // Still misquoting → don't show a wrong figure, and don't dump an unrelated
                    // template. A short, honest line keeps the answer about the user's question.
                    reply = "Mejor no arriesgo una cifra que no tengo confirmada. Pregúntamelo de otra forma y te ayudo."
                }
            }

            if reply.isEmpty {
                reply = "No alcancé a redactar una respuesta. Intenta de nuevo."
            }
            messages.append(ChatMessage(role: .assistant, text: reply))
        } catch {
            errorText = "No pude responder en tu iPhone ahora. Intenta de nuevo."
            messages.append(ChatMessage(role: .assistant,
                                        text: "No pude responder en tu iPhone ahora. Intenta de nuevo en un momento."))
        }
    }
}
#endif
