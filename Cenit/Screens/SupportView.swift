#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Acerca de y soporte» — Liquid Glass (FER-180)
//
// Migration of the light «Instrumento diurno» About/Support screen to the Liquid Glass language
// (same skin pass as Data Sources, FER-108 family): a hoja header (overline + displayS title +
// subtitle), the identity + version + mission block on a single `liquidTarjetaSeccion` card, and a
// quiet disclaimer footnote. This is a SKIN pass, not a content change — FER-381 already trimmed
// this screen down to identity + version + mission + the single «not affiliated / not a medical
// device» disclaimer; that content and its behavior (none — the screen is static) are conserved
// verbatim.
//
// The screen is presented inside its own NavigationStack by every caller (Ajustes forces the light
// paper theme on the sheet, `.preferredColorScheme(.light)`), so no navigation chrome lives here.

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
            Text("\(ProjectInfo.appName): all your data, none of the cloud.")
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

            Text("A health app built on Apple Health. Everything stays on this device: your history, your nights, your numbers. Nothing is uploaded. \(ProjectInfo.appName) is an independent, experimental project.")
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
