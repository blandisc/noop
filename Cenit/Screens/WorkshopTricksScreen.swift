#if os(iOS)
import SwiftUI
import CenitDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - «Lo que Cénit sabe hacer» (decisión Fer 2026-07-16)
//
// La página del taller: los trucos distintivos que viven medio escondidos en el flujo Entrenar —
// progresión, descanso por FC, importar el plan de una IA, calentamientos en rampa, calculadora de
// discos, tickets térmicos. NO es un tutorial: una fila por truco, dicho en una línea, con el color
// solo en el glifo (§8.4). Dos puertas: el chip «? Trucos» del hub (permanente) y una tarjeta de
// una-sola-vez en el hub (se descarta con ✕ y no vuelve — `hubTricksCardDismissed`).

struct WorkshopTricksScreen: View {
    @Environment(\.instrumentoTheme) private var theme
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    private struct Trick: Identifiable {
        let id: String
        let systemImage: String
        let tint: Color
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let tricks: [Trick] = [
        .init(id: "progression", systemImage: "arrow.up.right",
              tint: LiquidColor.verdePrimario,
              title: "Progression that earns itself",
              body: "Hit the target two sessions in a row and the routine raises the weight. Turn it on per exercise, from its card."),
        .init(id: "hr-rest", systemImage: "heart.fill",
              tint: LiquidColor.rosa,
              title: "Rest by heart, not by clock",
              body: "Rest by heart rate ends when your pulse has recovered enough to lift again. Fixed time is always there if you prefer it."),
        .init(id: "import", systemImage: "square.and.arrow.down",
              tint: LiquidColor.cian,
              title: "Import your AI's plan",
              body: "Ask ChatGPT or Claude for a routine and bring the file in. Cénit never connects; you run the AI yourself."),
        .init(id: "warmup", systemImage: "flame",
              tint: LiquidColor.ambar,
              title: "Warm-ups on a ramp",
              body: "One tap adds the 40/60/80% ladder before your first heavy set."),
        .init(id: "plates", systemImage: "scalemass",
              tint: LiquidColor.indigo,
              title: "Plate calculator",
              body: "Tap the weight during a session and it tells you which plates to load per side."),
        .init(id: "tickets", systemImage: "ticket",
              tint: LiquidColor.tinta900,
              title: "Thermal tickets",
              body: "Every session prints its receipt. Save them and compare them in History."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text("The workshop").liquidKicker().foregroundStyle(LiquidColor.tinta500)
                Text("What Cénit can do")
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                Text("Things you may not have found yet")
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                VStack(alignment: .leading, spacing: .zero) {
                    ForEach(tricks) { t in
                        trickRow(t)
                        if t.id != tricks.last?.id { Divider().overlay(LiquidColor.tinta10) }
                    }
                }
                .padding(.top, LiquidSpace.s300)
            }
            .padding(.top, LiquidSpace.handoff14)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-200 (Anillo 2, épico FER-195): fondo de vidrio El Eje en vez del papel plano — llega
        // empujada desde el hub (`navigationDestination`) y conserva la navegación del stack
        // ambiente; su héroe no trae botón de salida propio que sustituir.
        .entrenarHojaFondo(tono: .neutro)
        .enableInjection()
    }

    private func trickRow(_ t: Trick) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s300) {
            Image(systemName: t.systemImage)
                .font(LiquidType.iconSF(size: 15))
                .foregroundStyle(t.tint)
                .frame(width: 34, height: 34)
                .liquidGlass(.superficieSolida)
                .overlay(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous)
                    .strokeBorder(t.tint.opacity(CenitOpacity.strokeSoft), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(t.title).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                Text(t.body).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LiquidSpace.s300)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Trucos del taller") {
    NavigationStack { WorkshopTricksScreen() }
        .instrumentoTheme(.base)
        .preferredColorScheme(.light)
}

#Preview("Trucos del taller · xxxLarge (AX5)") {
    NavigationStack { WorkshopTricksScreen() }
        .instrumentoTheme(.base)
        .preferredColorScheme(.light)
        .dynamicTypeSize(.accessibility5)
}
#endif
#endif
