import SwiftUI
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - FER-51 · Host de modos (Cosmos · Matriz)
//
// Conmutador + crossfade entre las dos caras + franja de estado T1–T5.
// Persistencia de modo en `@AppStorage("hoy.modo")`. Revisión del dueño en vivo
// (2026-08-06): las caras ya NO traen héroe propio — el héroe de la pantalla es el
// ecosistema de partículas que vive arriba. La postura «reunida» de la F2 se retiró
// (era un doble del héroe); el gesto volverá como coreografía real del ecosistema
// en la Ola 2 (Metal).

struct HoyModosHost: View {
    @AppStorage("hoy.modo") private var modoRaw = HoyModo.cosmos.rawValue
    @ObserveInjection private var inject

    let matriz: MatrizHoyModel
    let cosmos: CosmosAbiertoModel
    let plantilla: LiquidHoyBuilder.Plantilla
    var onTapSeccion: (String) -> Void = { _ in }
    var onTapAncla: (String) -> Void = { _ in }

    private var modo: Binding<HoyModo> {
        Binding(
            get: { HoyModo(rawValue: modoRaw) ?? .cosmos },
            set: { modoRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: LiquidSpace.s300) {
            if let copy = estadoCopy {
                estadoGrupo(copy)
            }

            Group {
                if modo.wrappedValue == .cosmos {
                    CosmosAbiertoFace(model: cosmos, onTapAncla: onTapAncla)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(390.0 / 445.0, contentMode: .fit)
                        .transition(.opacity)
                } else {
                    // Matriz: bandas §7; la cara mide su contenido y scrollea la pantalla.
                    MatrizHoyFace(model: matriz, onTapSeccion: onTapSeccion)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: modo.wrappedValue)

            HoyModoConmutador(
                modo: modo,
                rotuloCosmos: String(localized: "hoy.modo.cosmos", defaultValue: "Cosmos"),
                rotuloMatriz: String(localized: "hoy.modo.matriz", defaultValue: "Matrix"))
            .padding(.top, LiquidSpace.s100)
            .padding(.bottom, LiquidSpace.s200)
        }
        .enableInjection()   // Inject: recarga en caliente de las caras (no-op en Release)
    }

    // MARK: - Estado (copy §11)

    private var estadoCopy: String? {
        switch plantilla {
        case .t1Pleno, .t2Provisional:
            return nil
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
            .padding(.horizontal, LiquidSpace.s100)
            .accessibilityIdentifier("hoy-estado-copy")
    }
}
