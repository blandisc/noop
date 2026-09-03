import SwiftUI

// MARK: - Liquid Glass · Encabezado de sección (FER-273, CONTRATO.md — checklist Fase 1)
//
// Encabezado de sección Liquid Glass · El Eje: kicker en mayúsculas chicas + aire, SIN banda
// de fondo — las secciones se separan con aire y vidrio, no con franja de papel.
// Reusa `LiquidType.kicker` + `.liquidKicker()` (MAYÚSCULAS 11.5/600, tracking +1.5) para que
// «kicker de sección» y «kicker de pantalla» hablen el mismo tamaño.

/// El encabezado de sección Liquid: un kicker a la izquierda + un trailing opcional a la
/// derecha (una acción, un hint de lectura), sin fondo — el caller ya vive sobre el papel/
/// vidrio de su pantalla.
public struct LiquidSectionHeader<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
            Text(title).liquidKicker().foregroundStyle(LiquidColor.tinta700)
            Spacer(minLength: LiquidSpace.s200)
            trailing
        }
        .padding(.top, LiquidSpace.s400)
        .padding(.bottom, LiquidSpace.s200)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension LiquidSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

#if DEBUG
#Preview("Liquid · Encabezado de sección") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            LiquidSectionHeader("La sesión de hoy")
            Text("El contenido de la sección vive aquí, sin banda de papel.")
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta900)
            LiquidSectionHeader("Tu plan") {
                Text("Editar semana").font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta700)
            }
            Text("Otra sección, con acción a la derecha.")
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta900)
            LiquidSectionHeader("Mis rutinas") {
                Text(verbatim: "＋ Nueva").font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta700)
            }
        }
        .padding(.horizontal, LiquidSpace.s550)
    }
    .background(LiquidColor.fondoGradient)
}
#endif
