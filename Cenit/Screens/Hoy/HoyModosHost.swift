import SwiftUI
import Foundation
import CenitDesign
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
    /// Tap del aviso de desconexión → el MISMO flujo de conexión que la puerta «Connect
    /// Health» (C6 de la revisión conceptual: una sola causa, una sola ruta).
    var onTapAvisoSalud: () -> Void = {}
    /// FER-118 · El hint de barrido del guardián: se muestra hasta 3 veces o hasta el primer
    /// scrub (espejo de `maxSeparacionHints`); el contador vive aquí (la cara es del DS y no lee
    /// `AppStorage`).
    @AppStorage("today.scrubHints") private var scrubHints = 0
    private static let maxScrubHints = 3

    var body: some View {
        VStack(spacing: esAvisoDesconexion ? LiquidSpace.s150 : LiquidSpace.s300) {
            if let copy = estadoCopy {
                Group {
                    if esAvisoDesconexion {
                        Button(action: onTapAvisoSalud) {
                            AvisoDesconexion(texto: copy)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: copy))
                        .accessibilityHint(Text(String(localized: "hoy.desconectado.hint",
                                                       defaultValue: "Opens Data Sources to reconnect")))
                        .accessibilityIdentifier("hoy-estado-copy")
                    } else {
                        estadoGrupo(copy)
                    }
                }
                // El margen de la FRANJA (24, alineada con el héroe). Los módulos de vidrio llevan
                // el suyo (`margenModulos`), y lo aplica la cara: son dos dueños distintos a
                // propósito (FER-118) y NUNCA se suman. Desde FER-159 ambos valen 24 (el dueño los
                // alineó con el héroe; antes los módulos iban a 16 = dock).
                .padding(.horizontal, MatrizTokens.margenH)
            }
            MatrizHoyFace(model: matriz, onTapSeccion: onTapSeccion,
                          mostrarHintScrub: scrubHints < Self.maxScrubHints,
                          onHintMostrado: { scrubHints = min(Self.maxScrubHints, scrubHints + 1) },
                          onScrubCompletado: { scrubHints = Self.maxScrubHints })
                .frame(maxWidth: .infinity)
        }
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
            // Revisión conceptual (dueño 2026-08-15): la franja lleva SOLO la causa — el héroe
            // ya dice «No reading today»; repetirlo palabra por palabra en la misma columna era
            // eco, no información. De paso, sinSync ahora enseña el gesto que sí ayuda.
            switch causa {
            case .leyendo:
                return String(localized: "hoy.leyendo", defaultValue: "Reading your night…")
            case .sinSync:
                return String(localized: "hoy.sync.pendiente",
                              defaultValue: "Pending sync · pull down to sync")
            case .nocheNoRegistrada:
                return String(localized: "hoy.noche.noregistrada",
                              defaultValue: "The night wasn't recorded")
            case .senalInsuficiente:
                return String(localized: "hoy.senal.insuficiente",
                              defaultValue: "Night recorded · not enough signal for a verdict")
            case .calibrando:
                // FER-73 · H12: el héroe ya dice «Getting to know you · Night N of M»; una
                // franja que diga «not enough signal» debajo lo contradice. Calla.
                return nil
            }
        case .t4SinPermiso:
            // Revisión conceptual (dueño 2026-08-15): «pending sync» era MENTIRA aquí — sin
            // permiso no hay sync pendiente. El héroe ya es dueño del mensaje («Connect Apple
            // Health…» + CTA); una franja que dice otra cosa solo contradice. Calla.
            return nil
        case .t5Dormido:
            return nil
        }
    }

    private func estadoGrupo(_ texto: String) -> some View {
        Text(texto)
            .font(LiquidType.cuerpoBanner)
            .foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("hoy-estado-copy")
    }
}

// MARK: - Aviso de Apple Salud desconectada (FER-64/65 · pulido en vivo)
//
// Dos líneas INTENCIONALES (no el wrap roto de una pastilla): la copia del catálogo se parte en
// el «·» → estado (semibold) + detalle (más tenue). Tarjeta rosa a susurro (radio de control),
// punto latiente y un glow rojo CÁLIDO (rojoClaro, no el neón del sistema oscuro) que respira
// para llevar la vista sin alarmar. Respeta Reduce Motion y la pausa ambiental (reloj compartido).
private struct AvisoDesconexion: View {
    let texto: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    // FER-73 · M14: faltaba `liquidMotionDisabled` — en capturas/fixtures «sin motion» el aviso
    // seguía respirando (y re-rasterizando su sombra) a 12 fps.
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    private var quieto: Bool { reduceMotion || ambientPaused || motionDisabled }

    /// «estado · detalle» partido en el «·» → dos renglones con jerarquía, no un corte a media frase.
    private var partes: (estado: String, detalle: String?) {
        let c = texto.components(separatedBy: " · ")
        guard c.count > 1 else { return (texto, nil) }
        return (c[0], c.dropFirst().joined(separator: " · "))
    }

    var body: some View {
        // FER-73 · M14: el TEXTO ya no vive dentro del TimelineView. Antes cada tick re-medía y
        // re-rasterizaba los dos `Text` + la sombra variable de toda la tarjeta a 12 fps; ahora
        // el reloj solo mueve una capa de respiro (punto + fondo + glow) detrás de un contenido
        // estático. Mismo dibujo, una fracción del trabajo por cuadro.
        HStack(alignment: .center, spacing: LiquidSpace.s200) {
            latido
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(partes.estado)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.rojoClaro)
                if let detalle = partes.detalle {
                    Text(detalle)
                        .font(LiquidType.cuerpo)
                        .foregroundStyle(LiquidColor.rojoClaro.opacity(0.72))   // token-exempt: detalle a susurro
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LiquidSpace.s200)
        .padding(.horizontal, LiquidSpace.s250)
        .background(respiro)
    }

    /// El punto que late (la única pieza de texto-adyacente que se anima).
    private var latido: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloSello, paused: quieto)) { tl in
            Circle()
                .fill(LiquidColor.rojoClaro)
                .frame(width: 6, height: 6)
                .opacity(0.55 + 0.45 * Self.fase(tl.date, quieto: quieto))   // token-exempt: latido del punto de aviso
        }
        .frame(width: 6, height: 6)
    }

    /// Fondo + glow: una capa aparte, sin texto que re-medir por cuadro.
    private var respiro: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloSello, paused: quieto)) { tl in
            let fase = Self.fase(tl.date, quieto: quieto)
            ZStack {
                // El halo se DIBUJA, no se deriva —colgado como `.shadow` del fondo del aviso,
                // el sistema lo proyectaba desde la alfa de ese fondo (6-10 %) y quedaba en ~1 %,
                // invisible— pero se dibuja como CONTORNO. Un relleno desenfocado del tamaño de
                // la tarjeta no es un halo: es un segundo fondo que le baja el contraste al
                // texto por dentro y se derrama sobre la Matriz por fuera, que solo tiene 6 pt
                // de despeje (tercera vuelta adversarial). El contorno concentra el brillo en el
                // filo, que es donde un halo vive.
                RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                    .strokeBorder(LiquidColor.rojoClaro.opacity(0.35 + 0.20 * fase),   // token-exempt: glow que respira
                                  lineWidth: 3)
                    .blur(radius: 6 + 3 * fase)
                RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                    .fill(LiquidColor.rojoClaro.opacity(0.06 + 0.04 * fase))   // token-exempt: fondo del aviso
            }
        }
    }

    private static func fase(_ date: Date, quieto: Bool) -> Double {
        quieto ? 0.5 : (sin(date.timeIntervalSinceReferenceDate * 1.5) * 0.5 + 0.5)
    }
}
