import SwiftUI
import Foundation
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - FER-51 · Host de la Matriz
//
// Decisión del dueño (2026-08-06, revisión en vivo): el modo Cosmos se APAGÓ — era mucha
// complejidad; la Matriz es la apuesta y se pule a fondo. (El código muerto de Cosmos se
// podó después, FER-audit.) Este host monta la franja de estado T1–T5 + la cara Matriz.

struct HoyMatrizHost: View {
    @ObserveInjection private var inject

    let matriz: MatrizHoyModel
    let plantilla: LiquidHoyBuilder.Plantilla
    /// Apple Salud desconectada (permiso revocado). Con veredicto en caché (t1/t2) pinta un
    /// aviso discreto: el dato es honesto pero es de anoche (FER-audit).
    var saludDesconectada: Bool = false
    var onTapSeccion: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: esAvisoDesconexion ? LiquidSpace.s150 : LiquidSpace.s300) {
            if let copy = estadoCopy {
                if esAvisoDesconexion {
                    AvisoDesconexion(texto: copy)
                        .accessibilityIdentifier("hoy-estado-copy")
                } else {
                    estadoGrupo(copy)
                }
            }
            MatrizHoyFace(model: matriz, onTapSeccion: onTapSeccion)
                .frame(maxWidth: .infinity)
        }
        // UN solo dueño del margen horizontal (hallazgo DeepSeek #14: antes 24 del
        // TodayView + 16 de la cara = 40 desalineados del copy de estado).
        .padding(.horizontal, MatrizTokens.margenH)
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    /// El aviso de Salud desconectada (con veredicto en caché) es el ÚNICO estado que resalta:
    /// un glow rojo cálido que respira para llevar la vista, sin alarmar. Los demás copys de
    /// estado (leyendo, sin sync) son notas neutras.
    private var esAvisoDesconexion: Bool {
        saludDesconectada && (plantilla == .t1Pleno || plantilla == .t2Provisional)
    }

    // MARK: - Estado (copy §11)

    private var estadoCopy: String? {
        switch plantilla {
        case .t1Pleno, .t2Provisional:
            // Con veredicto en caché pero Salud desconectada, avisamos honesto que el dato
            // es de anoche (FER-audit: antes callaba y el usuario no sabía que se desconectó).
            return saludDesconectada
                ? String(localized: "hoy.desconectado.cache",
                         defaultValue: "Apple Health disconnected · showing your last reading")
                : nil
        case .t3SinVeredicto(let causa):
            switch causa {
            case .leyendo:
                return String(localized: "hoy.leyendo", defaultValue: "Reading your night…")
            case .sinSync:
                return String(localized: "hoy.sinlectura.sync",
                              defaultValue: "No reading today · pending sync")
            case .nocheNoRegistrada:
                return String(localized: "hoy.sinlectura.noche",
                              defaultValue: "No reading today · the night wasn't recorded")
            }
        case .t4SinPermiso:
            return String(localized: "hoy.sinlectura.sync",
                          defaultValue: "No reading today · pending sync")
        case .t5Dormido:
            return nil
        }
    }

    private func estadoGrupo(_ texto: String) -> some View {
        Text(texto)
            .font(InstrumentoType.grotesk(13, weight: .medium))
            .foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("hoy-estado-copy")
    }
}

// MARK: - Aviso de Apple Salud desconectada (FER-64/65 · pulido en vivo)
//
// Compacto: una pastilla que HUGa el texto (no una franja de ancho completo), con un punto
// latiente y un glow rojo CÁLIDO (rojoClaro, no el neón del sistema oscuro) muy sutil que respira
// para llevar la vista sin alarmar. Respeta Reduce Motion y la pausa ambiental de la Matriz
// (reloj compartido: `liquidAmbientPaused`).
private struct AvisoDesconexion: View {
    let texto: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    private var quieto: Bool { reduceMotion || ambientPaused }

    var body: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloSello, paused: quieto)) { tl in
            let fase = quieto ? 0.5 : (sin(tl.date.timeIntervalSinceReferenceDate * 1.5) * 0.5 + 0.5)
            HStack(spacing: LiquidSpace.s150) {
                Circle()
                    .fill(LiquidColor.rojoClaro)
                    .frame(width: 5, height: 5)
                    .opacity(0.5 + 0.5 * fase)   // token-exempt: latido del punto de aviso
                Text(texto)
                    .font(InstrumentoType.grotesk(13, weight: .medium))
                    .foregroundStyle(LiquidColor.rojoClaro)
            }
            .padding(.vertical, LiquidSpace.s100)
            .padding(.horizontal, LiquidSpace.s200)
            .background(
                Capsule(style: .continuous)
                    .fill(LiquidColor.rojoClaro.opacity(0.05 + 0.04 * fase))   // token-exempt: fondo del aviso
            )
            .shadow(color: LiquidColor.rojoClaro.opacity(0.12 + 0.10 * fase),   // token-exempt: glow que respira
                    radius: 8 + 5 * fase)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
