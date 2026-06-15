import SwiftUI
import StrandDesign
import StrandAnalytics

/// FER-113 — the "Why {verdict}?" sheet behind the verdict hero on iPhone. Explains *why* today reads
/// the way it does: the day's color, the reconciliation line, the full driver signals (brought to iOS
/// from the macOS-only readiness list), and a color legend that names the CONDITION behind each color
/// and marks where today lands. Mirrors `MetricInfoSheet`'s scaffold so the two explainers feel like one.
struct WhyVerdictSheet: View {
    let readiness: ReadinessEngine.Readiness

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Why \(readiness.headline.lowercased())?")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                colorChip
                if let bridge = readiness.bridge {
                    Text(bridge)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !readiness.signals.isEmpty { signalsSection }
                legendSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(StrandPalette.surfaceBase)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(WhySheetBackground())
    }

    /// "Today your day is amber — Strained" — makes the color the explicit subject (the user's
    /// original confusion was "why is it this color?").
    private var colorChip: some View {
        let c = levelColor(readiness.level)
        return HStack(spacing: 8) {
            Circle().fill(c).frame(width: 11, height: 11)
            Text("Today your day is \(colorName(readiness.level)) — \(readiness.headline)")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(c.opacity(0.30), lineWidth: 0.5))
    }

    /// The full driver list — this is what was macOS-only before; FER-113 brings it to the phone.
    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Your signals today")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textTertiary)
            ForEach(readiness.signals, id: \.key) { s in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(flagColor(s.flag)).frame(width: 7, height: 7).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(StrandFont.caption).foregroundStyle(StrandPalette.textPrimary)
                        Text(s.detail).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The legend explains the CONDITION behind each color (not just its name) and marks where today
    /// lands — answering "why is it amber / green / …?".
    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What each color means")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(.bottom, 6)
            legendRow(.primed, "Primed", "signals aligned, load supported")
            legendRow(.balanced, "Balanced", "nothing flagging")
            legendRow(.strained, "Strained", "one signal needs care")
            legendRow(.rundown, "Run down", "several signals down")
        }
    }

    private func legendRow(_ level: ReadinessEngine.Level, _ name: LocalizedStringKey,
                           _ condition: LocalizedStringKey) -> some View {
        let here = readiness.level == level
        let c = levelColor(level)
        return HStack(spacing: 9) {
            Circle().fill(c).frame(width: 9, height: 9)
            Text(name).font(StrandFont.caption).foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 96, alignment: .leading)
            Text(condition).font(StrandFont.footnote)
                .foregroundStyle(here ? c : StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if here {
                Text("TODAY").font(.system(size: 9, weight: .semibold)).foregroundStyle(c)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(c.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(here ? c.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: color maps (mirror TodayView so the hero and sheet never disagree)

    private func levelColor(_ l: ReadinessEngine.Level) -> Color {
        switch l {
        case .primed:       return StrandPalette.statusPrimed
        case .balanced:     return StrandPalette.statusPositive
        case .strained:     return StrandPalette.statusWarning
        case .rundown:      return StrandPalette.metricRose
        case .insufficient: return StrandPalette.textTertiary
        }
    }

    private func flagColor(_ f: ReadinessEngine.Flag) -> Color {
        switch f {
        case .good:    return StrandPalette.accent
        case .neutral: return StrandPalette.textTertiary
        case .watch:   return StrandPalette.statusWarning
        case .bad:     return StrandPalette.metricRose
        }
    }

    private func colorName(_ l: ReadinessEngine.Level) -> String {
        switch l {
        case .primed:       return String(localized: "mint")
        case .balanced:     return String(localized: "green")
        case .strained:     return String(localized: "amber")
        case .rundown:      return String(localized: "rose")
        case .insufficient: return String(localized: "gray")
        }
    }
}

private struct WhySheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.3, iOS 16.4, *) {
            content.presentationBackground(StrandPalette.surfaceBase)
        } else { content }
    }
}
