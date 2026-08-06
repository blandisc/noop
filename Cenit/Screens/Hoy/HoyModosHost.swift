import SwiftUI
import StrandDesign

// MARK: - FER-51 · Host de modos (Cosmos · Matriz)
//
// Conmutador + crossfade entre las dos caras + franja de estado T1–T5.
// Persistencia de modo en `@AppStorage("hoy.modo")`. F2: la postura del Cosmos (reunido⇄
// abierto) la alterna el gesto de tocar el cielo; amanece abierta con el cambio de día.

struct HoyModosHost: View {
    @AppStorage("hoy.modo") private var modoRaw = HoyModo.cosmos.rawValue
    @AppStorage("hoy.lastActiveDay") private var lastActiveDay = ""
    @AppStorage("hoy.gestoUsos") private var gestoUsos = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// F2 · postura del Cosmos: amanece ABIERTA; el gesto de tocar el cielo la reúne.
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

            Group {
                if modo.wrappedValue == .cosmos {
                    cosmosCara
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

            // F2 · pista del gesto (las primeras 3 veces que aún no lo usas).
            if modo.wrappedValue == .cosmos && gestoUsos < 3 {
                Text(reunido ? String(localized: "hoy.hint.abrir", defaultValue: "Tap the sky to open it")
                             : String(localized: "hoy.hint.reunir", defaultValue: "Tap the sky to gather it"))
                    .font(.footnote)
                    .foregroundStyle(LiquidColor.tinta500)
                    .transition(.opacity)
            }

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
            // F2: la postura amanece ABIERTA con el cambio de día calendario.
            if lastActiveDay != hoy {
                lastActiveDay = hoy
                reunido = false
            }
        }
        .onAppear {
            let hoy = Self.dayKey(Date())
            if lastActiveDay != hoy {
                lastActiveDay = hoy
                reunido = false
            }
        }
    }

    // MARK: - F2 · postura del Cosmos y el gesto

    /// El Cosmos con su gesto: tocar el CIELO (vacío) alterna reunido⇄abierto; tocar una
    /// ANCLA abre su hoja (el tap del hijo gana sobre el del padre, comportamiento estándar).
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
        reunido.toggle()
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

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
