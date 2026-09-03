#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - «Acerca de y soporte» — Liquid Glass · El Eje (FER-180)
//
// Hoja Liquid Glass · El Eje (familia FER-108): header (overline + displayS + subtítulo),
// identidad/versión/misión en una `liquidTarjetaSeccion`, disclaimer quieto al pie, suelo
// `LiquidSheetFondo`. Solo piel — FER-381 ya dejó el contenido en identidad + versión + misión +
// el disclaimer «no afiliado / no dispositivo médico». Cada caller la monta en su propio

struct SupportView: View {
    /// Single source of truth for the version pill: the app bundle's marketing version, same value
    /// `AjustesView`'s footer shows.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s800) {
                header
                aboutCard
                disclaimer
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidOverline(String(localized: "About"))
            Text("About & support")
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text("\(ProjectInfo.appName): all your data, none uploaded.")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - About (identity + version pill + offline mission) — one Liquid card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(spacing: LiquidSpace.s200) {
                Text(ProjectInfo.appName).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                Text("v\(appVersion)")
                    .font(LiquidType.unidadCompacta)
                    .foregroundStyle(LiquidColor.tinta500)
                    .padding(.horizontal, LiquidSpace.s250)
                    .padding(.vertical, LiquidSpace.s075)
                    // Opaque pill: this screen rides a SHEET (paper), so no translucent glass inside
                    // it (design-lint `no-sheet-glass`) — `.pastillaSolida` is the solid paper variant
                    // (same recipe DataSourcesView uses for its coverage pill).
                    .liquidGlass(.pastillaSolida)
                Spacer(minLength: 0)
            }

            Text("A health app built on Apple Health. It all runs on this device: your history, your nights, your numbers. Cénit uploads nothing. \(ProjectInfo.appName) is an independent, experimental project.")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
    }

    // MARK: - Disclaimer (single, quiet, at the foot)

    private var disclaimer: some View {
        Text("Not a medical device.")
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    NavigationStack { SupportView() }
}
#endif
