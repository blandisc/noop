import SwiftUI
import StrandDesign

// MARK: - FER-51 · Host de modos (Cosmos · Matriz)
//
// Conmutador + crossfade entre las dos caras + franja de estado T1–T5.
// Persistencia de modo en `@AppStorage("hoy.modo")`. F1: postura Cosmos fija abierta
// (no hay gesto); `lastActiveDay` solo se actualiza al volver a activo (groundwork F2).

struct HoyModosHost: View {
    @AppStorage("hoy.modo") private var modoRaw = HoyModo.cosmos.rawValue
    @AppStorage("hoy.lastActiveDay") private var lastActiveDay = ""
    @Environment(\.scenePhase) private var scenePhase

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
                    // Lienzo de referencia Cosmos 390×820 (§1 de la cara).
                    CosmosAbiertoFace(model: cosmos, onTapAncla: onTapAncla)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(390.0 / 820.0, contentMode: .fit)
                        .transition(.opacity)
                } else {
                    // Matriz: GeometryReader + bandas §7; mínimo generoso en el scroll padre.
                    MatrizHoyFace(model: matriz, onTapSeccion: onTapSeccion)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 720)
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let hoy = Self.dayKey(Date())
            // F1: la postura Cosmos es fija abierta; no se restaura ni se persiste
            // otra postura. Solo se actualiza el día activo (groundwork F2).
            if lastActiveDay != hoy {
                lastActiveDay = hoy
            }
        }
        .onAppear {
            let hoy = Self.dayKey(Date())
            if lastActiveDay != hoy {
                lastActiveDay = hoy
            }
        }
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

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
