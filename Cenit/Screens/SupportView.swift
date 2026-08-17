#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Acerca de y soporte» — FER-67 · adelgazada en FER-381
//
// The About screen, in the light «Instrumento diurno» language (warm paper, color only on the datum,
// hierarchy by space — no card-in-card). FER-381 removed the check-for-updates flow, the crypto
// donation section and the contact section per the owner's call: what's left is identity + version +
// What's New (changelog) + mission + a single «not affiliated / not a medical device»
// disclaimer. Logic unchanged; presentation only.

/// Theme wrapper: anchors `\.instrumentoTheme` to the single warm day paper (`.base`), then hands to
/// the content (which reads the resolved theme from the environment). The theme is also injected
/// explicitly by every sheet caller (it doesn't cross the `.sheet` boundary — FER-162). (FER-398
/// retired the by-the-hour tint.)
struct SupportView: View {
    var body: some View {
        SupportContent().instrumentoTheme(.base)
    }
}

private struct SupportContent: View {
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About & support").font(StrandFont.title1).foregroundStyle(theme.ink)
                    Text("\(ProjectInfo.appName): all your data, none of the cloud.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, -8)

                aboutSection

                disclaimer
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    // MARK: - About (identity + version + what's new + mission)

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(ProjectInfo.appName).font(StrandFont.title2).foregroundStyle(theme.ink)
                Text("v\(AppChangelog.currentVersion)")
                    .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                Spacer()
            }

            Text("A health app built on Apple Health. Everything stays on this device: your history, your nights, your numbers. Nothing is uploaded. \(ProjectInfo.appName) is an independent, experimental project.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Disclaimer (single, quiet, at the foot)

    private var disclaimer: some View {
        Text("Not a medical device.")
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

/// Hosts ``SupportView`` as a centred panel over a dimmed backdrop (used by Today). Light «Instrumento»
/// paper panel; tap outside or the ✕ closes it. Taps on the panel are absorbed so its controls work.
struct SupportModalOverlay: View {
    @Binding var isPresented: Bool
    private let theme = InstrumentoTheme.base

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.35)) // token-exempt: scrim modal (negro, fuera de banda de tinte)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            SupportView()
                .frame(width: 540, height: 520)
                .background(theme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous)) // token-exempt: radio de panel modal 18pt (sin rol)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous) // token-exempt: radio de panel modal 18pt (sin rol)
                    .strokeBorder(theme.hairline, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(StrandFont.glyph(.lead))
                            .foregroundStyle(theme.inkTertiary)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 14) // token-exempt: sombra de panel modal (negro, fuera de banda)
        }
        .transition(.opacity)
    }
}
#endif
