import SwiftUI
import StrandDesign

/// First-run acknowledgment gate (clickwrap). Shown over EVERYTHING — before onboarding, pairing, or
/// any Bluetooth access — until the current `Terms.currentVersion` is accepted, and again if the
/// terms materially change. The user must tick the (un-pre-checked) box and tap Accept; the accepted
/// version is then stored locally, the on-device equivalent of a consent record. See `Terms` / `TERMS.md`.
///
/// FER-416 — migrated to the light «Instrumento diurno» language (warm paper, ink, color only on the
/// affirmative control). Logic unchanged: the consent toggle still gates Accept, and `onAccept` still
/// records the accepted version. The theme defaults to `.base` (the app's day paper since FER-398).
struct TermsGateView: View {
    let onAccept: () -> Void
    var theme: InstrumentoTheme = .base
    @State private var checked = false

    var body: some View {
        ZStack {
            theme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Before you use Cénit")
                        .font(StrandFont.title1)
                        .foregroundStyle(theme.ink)
                    Text("Please read and accept the points below.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                }
                .padding(.top, 36)
                .padding(.bottom, 22)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Terms.points, id: \.0) { point in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.0)
                                    .font(StrandFont.headline)
                                    .foregroundStyle(theme.ink)
                                Text(point.1)
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("The full terms are in TERMS.md, shipped with Cénit. This is not legal advice.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 18)
                }

                Rectangle()
                    .fill(theme.hairline)
                    .frame(height: 1)

                VStack(spacing: 16) {
                    Toggle(isOn: $checked) {
                        Text("I have read and accept these terms, and I'm using Cénit with my own device and my own data, at my own risk.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.switch)
                    .tint(theme.verdict)

                    Button(action: onAccept) {
                        Text("Accept & Continue")
                            .font(StrandFont.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.ink)
                    .disabled(!checked)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(26)
            }
            .frame(maxWidth: 560, maxHeight: 640)
        }
    }
}
