import SwiftUI
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - FER-51 · Host de modos (Cosmos · Matriz)
//
// Conmutador ARRIBA + swipe horizontal entre las dos caras + franja de estado T1–T5.
// Persistencia de modo en `@AppStorage("hoy.modo")`. Revisión del dueño en vivo
// (2026-08-06): las caras no traen héroe propio (el héroe es el ecosistema de arriba);
// el Cosmos tiene dos posturas — tocar el CIELO reúne todo a orbitar como planetas
// (partículas reales), tocarlo de nuevo lo abre a sus puestos con números.

struct HoyModosHost: View {
    @AppStorage("hoy.modo") private var modoRaw = HoyModo.cosmos.rawValue
    @AppStorage("hoy.gestoUsos") private var gestoUsos = 0
    @ObserveInjection private var inject
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Postura del Cosmos: amanece ABIERTA; el gesto de tocar el cielo la reúne.
    @State private var reunido = false

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

            // El conmutador vive ARRIBA de la cara (descubribilidad) y el swipe
            // horizontal sobre la cara también cambia de modo.
            HoyModoConmutador(
                modo: modo,
                rotuloCosmos: String(localized: "hoy.modo.cosmos", defaultValue: "Cosmos"),
                rotuloMatriz: String(localized: "hoy.modo.matriz", defaultValue: "Matrix"))

            Group {
                if modo.wrappedValue == .cosmos {
                    cosmosCara
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { g in
                        // Swipe horizontal = cambiar de modo (vertical sigue siendo scroll).
                        guard abs(g.translation.width) > abs(g.translation.height) * 1.4,
                              abs(g.translation.width) > 48 else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            modo.wrappedValue = g.translation.width < 0 ? .matriz : .cosmos
                        }
                    }
            )

            // Pista del gesto del cielo (las primeras 3 veces que aún no lo usas).
            if modo.wrappedValue == .cosmos && gestoUsos < 3 {
                Text(reunido ? String(localized: "hoy.hint.abrir", defaultValue: "Tap the sky to open it")
                             : String(localized: "hoy.hint.reunir", defaultValue: "Tap the sky to gather it"))
                    .font(InstrumentoType.grotesk(12, weight: .regular))
                    .foregroundStyle(LiquidColor.tinta500)
                    .transition(.opacity)
                    .padding(.bottom, LiquidSpace.s200)
            }
        }
        .enableInjection()   // Inject: recarga en caliente de las caras (no-op en Release)
    }

    // MARK: - Postura del Cosmos y el gesto

    /// El Cosmos con su gesto: tocar el CIELO (vacío) alterna reunido⇄abierto; tocar
    /// una ANCLA abre su hoja (el tap del hijo gana, comportamiento estándar).
    private var cosmosCara: some View {
        Group {
            if reunido {
                CosmosReunidoFace(model: cosmos)
            } else {
                CosmosAbiertoFace(model: cosmos, onTapAncla: onTapAncla)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { alternarPostura() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: reunido)
        .accessibilityAction(named: Text(reunido
            ? String(localized: "hoy.hint.abrir", defaultValue: "Tap the sky to open it")
            : String(localized: "hoy.hint.reunir", defaultValue: "Tap the sky to gather it"))) {
            alternarPostura()
        }
    }

    private func alternarPostura() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            reunido.toggle()
        }
        if gestoUsos < 3 { gestoUsos += 1 }
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
