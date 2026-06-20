#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - «Acerca de y soporte» — FER-67
//
// The merged About + Support screen, in the light «Instrumento diurno» language (warm paper, color
// only on the datum, hierarchy by space — no card-in-card). FER-337 moved the old About card here;
// FER-67 reskins the whole thing and keeps a single «not affiliated / not a medical device» disclaimer
// and a single attributions block (no duplication). Identity → version → what's new → check-for-updates
// → mission → built-on → support the build (crypto donation) → contact → disclaimer. Logic is unchanged
// (UpdateChecker, donation/QR, contact); only presentation moved to Instrumento.

/// Theme wrapper: drives `\.instrumentoTheme` by the hour, then hands to the content (which reads the
/// resolved theme from the environment). The theme is also injected explicitly by every sheet caller
/// (it doesn't cross the `.sheet` boundary — FER-162); the by-hour wrap here keeps it correct when
/// presented inside an already-themed tree too.
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
    @Environment(\.openURL) private var openURL

    @State private var copied: String?
    @State private var selected = "BTC"
    @State private var showWhatsNew = false
    @StateObject private var updateChecker = UpdateChecker()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About & support").font(StrandFont.title1).foregroundStyle(theme.ink)
                    Text("\(ProjectInfo.appName) — all your data, none of the cloud. Free and always will be; chipping in is optional.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, -8)

                aboutSection
                divider
                builtOnSection
                divider
                donateSection
                divider
                contactSection

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

    // MARK: - About (identity + version + what's new + update check + mission)

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

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    QuietButton(updateChecker.state == .checking ? "Checking…" : "Check for updates") {
                        updateChecker.check(currentVersion: AppChangelog.currentVersion)
                    }
                    if case .upToDate(let v) = updateChecker.state {
                        Text("You're on the latest (\(v)).")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    } else if case .failed = updateChecker.state {
                        Text("Couldn't check. Try again.")
                            .font(StrandFont.footnote).foregroundStyle(theme.warning)
                    }
                    Spacer(minLength: 0)
                }

                if case .available(let v, let url, let notes) = updateChecker.state {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Version \(v) is available")
                                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                            Spacer()
                            QuietButton("Download") { openURL(url) }
                        }
                        if !notes.isEmpty {
                            ScrollView {
                                Text(notes).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
                }

                Text("Checks GitHub for the latest version when you tap — nothing else is sent.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
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

    // MARK: - Support the build (crypto donation)

    private var donateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Support the build").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Cénit is free and always will be, nothing is locked. It cost real money and a lot of unpaid hours to build, and there's a Windows app and an iOS app I want to ship next. If it's useful to you and you want to help with the development and testing costs, even a few quid in crypto genuinely keeps it moving, and honestly it keeps me motivated to keep building.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("I keep this project anonymous, so crypto is the only way to chip in — no Patreon, no PayPal, no name attached. Quick, global, and private for both of us.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Pick a coin → scan the QR or copy the address.
            HStack(spacing: 8) {
                ForEach(ProjectInfo.donations) { coin in
                    let on = selected == coin.symbol
                    Button { withAnimation(.easeOut(duration: 0.15)) { selected = coin.symbol } } label: {
                        Text(coin.symbol).font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(on ? theme.ink : Color.clear))
                            .foregroundStyle(on ? theme.paper : theme.inkSecondary)
                            .overlay(Capsule().strokeBorder(on ? Color.clear : theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(coin.name) donation address")
                }
                Spacer(minLength: 0)
            }

            if let coin = ProjectInfo.donations.first(where: { $0.symbol == selected }) {
                HStack(alignment: .top, spacing: 16) {
                    qrView(coin.address)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan with any \(coin.name) wallet")
                            .font(StrandFont.subhead).foregroundStyle(theme.ink)
                        Text(coin.address)
                            .font(StrandFont.mono(11)).foregroundStyle(theme.inkSecondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        QuietButton(copied == coin.symbol ? "Copied!" : "Copy address") {
                            PlatformPasteboard.copy(coin.address)
                            withAnimation { copied = coin.symbol }
                        }
                        .accessibilityLabel("Copy \(coin.name) address")
                    }
                    Spacer(minLength: 0)
                }
            }

            Text("Any amount helps. Thank you — genuinely.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
    }

    /// Black-on-white QR so wallet cameras read it cleanly regardless of the page color.
    private func qrView(_ address: String) -> some View {
        Group {
            if let img = QRCode.image(for: address) {
                Image(platformImage: img).resizable().interpolation(.none)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface)
            }
        }
        .frame(width: 150, height: 150)
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Donation QR code")
    }

    // MARK: - Contact

    private var contactSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Get in touch").font(StrandFont.headline).foregroundStyle(theme.ink)
                Text("Questions, feedback, bugs — \(ProjectInfo.contactEmail)")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            QuietButton("Email") {
                if let url = URL(string: "mailto:\(ProjectInfo.contactEmail)") { PlatformOpen.url(url) }
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
                .frame(width: 560, height: 680)
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
