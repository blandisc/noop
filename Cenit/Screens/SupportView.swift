#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - «Acerca de y soporte» — FER-67 · adelgazada en FER-381
//
// The About screen, in the light «Instrumento diurno» language (warm paper, color only on the datum,
// hierarchy by space — no card-in-card). FER-381 removed the check-for-updates flow, the crypto
// donation section and the contact section per the owner's call: what's left is identity + version +
// What's New (changelog) + mission + attributions + a single «not affiliated / not a medical device»
// disclaimer. Logic unchanged; presentation only.

/// Theme wrapper: drives `\.instrumentoTheme` by the hour, then hands to the content (which reads the
/// resolved theme from the environment). The theme is also injected explicitly by every sheet caller
/// (it doesn't cross the `.sheet` boundary — FER-162); the by-hour wrap keeps it correct elsewhere too.
struct SupportView: View {
    var body: some View {
        SupportContent().instrumentoThemeByHour(solar: Self.solarWindow())
    }
    private static func solarWindow() -> SolarWindow? {
        guard let w = SolarClock.sunWindow(on: Date(), in: .current) else { return nil }
        return SolarWindow(sunrise: w.sunrise, sunset: w.sunset)
    }
}

private struct SupportContent: View {
    @Environment(\.instrumentoTheme) private var theme
    @State private var showWhatsNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About & support").font(StrandFont.title1).foregroundStyle(theme.ink)
                    Text("\(ProjectInfo.appName) — all your data, none of the cloud.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, -8)

                aboutSection
                divider
                builtOnSection

                disclaimer
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
    }

    private var divider: some View { Divider().overlay(theme.hairline) }

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
                QuietButton("What's new") { showWhatsNew = true }
            }

            Text("A standalone companion for your WHOOP. Everything stays on this device — your history, your live stream, your numbers. Nothing is uploaded. \(ProjectInfo.appName) is an independent, experimental project, not the WHOOP app.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Built on (attributions)

    private var builtOnSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Built on").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("This stands on community reverse-engineering. Huge thanks:")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            ForEach(ProjectInfo.attributions, id: \.repo) { a in
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary).accessibilityHidden(true)
                    Text(a.repo).font(StrandFont.mono(12)).foregroundStyle(theme.ink)
                    Text("· \(a.note)").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }

    // MARK: - Disclaimer (single, quiet, at the foot)

    private var disclaimer: some View {
        Text("Not affiliated with, endorsed by, or connected to WHOOP. Interoperability software for hardware you own and your own data. Use it only with a device you own, and not in breach of any agreement that applies to you. Not a medical device.")
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
                .fill(Color.black.opacity(0.35))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            SupportView()
                .frame(width: 540, height: 520)
                .background(theme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.inkTertiary)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 14)
        }
        .transition(.opacity)
    }
}
#endif
