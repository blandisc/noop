import SwiftUI
import StrandDesign

/// "What's New" — a proper in-app changelog, shown automatically after an update and reachable any
/// time from Settings. It also restates, up top, what NOOP is and what to expect, so people who never
/// open GitHub still understand the experimental footing and the WHOOP 5/MG status.
///
/// FER-415 — migrated to the light «Instrumento diurno» language (warm paper, ink, hierarchy by space —
/// no dark `NoopCard` boxes), matching the other sheets (FER-167 `WhyVerdictSheet`, FER-162). The theme
/// is passed in explicitly (it does NOT propagate through `.sheet`'s fresh environment, FER-162).
struct WhatsNewView: View {
    let onClose: () -> Void
    /// The active «Instrumento diurno» theme. Defaults to `.base` (the app is anchored to day paper
    /// since FER-398); callers may pass their own. Does not cross the `.sheet` boundary.
    var theme: InstrumentoTheme = .base

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    expectationsSection
                    ForEach(AppChangelog.releases) { release in
                        Divider().overlay(theme.hairline)
                            .padding(.vertical, 18)
                        releaseSection(release)
                    }
                }
                .padding(20)
            }
            Divider().overlay(theme.hairline)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paper)
        .sheetPaper(theme)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What's new").font(StrandFont.title2)
                    .foregroundStyle(theme.ink)
                Text("Cénit \(AppChangelog.currentVersion)").font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.inkTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    /// "What to expect" — overline + the experimental / offline / strap-support notes, laid out by
    /// space (no card box). Glyphs in ink, not an accent (color is reserved for data — none here).
    private var expectationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT TO EXPECT").font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.inkTertiary)
            ForEach(AppChangelog.expectations) { e in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: e.icon)
                        .foregroundStyle(theme.ink)
                        .frame(width: 22)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.title).font(StrandFont.headline)
                            .foregroundStyle(theme.ink)
                        Text(e.body).font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One release: a quiet outlined version chip (was the dark `SourceBadge`), title + date, and the
    /// bulleted items. Bullets are ink-tertiary dots, not an accent.
    private func releaseSection(_ release: AppChangelog.Release) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("v\(release.version)").font(StrandFont.caption)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.hairlineStrong, lineWidth: 0.5)
                    )
                Text(release.title).font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                Spacer()
                Text(release.date).font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
            }
            ForEach(Array(release.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(theme.inkTertiary).frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(item).font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Text("Got it").frame(minWidth: 120).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.ink)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
