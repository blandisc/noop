import SwiftUI

// MARK: - InstrumentoSectionBand — the handoff's sunken section header (FER-939/940)
//
// «Rediseño v4b» opens every section with a full-bleed sunken strip: an uppercase Grotesk overline
// on `patternBlock`, optionally with a trailing action («Editar semana», «＋ Nueva», a hint). First
// shipped privately in the Entrenar hub (FER-939); promoted here when «Tu Plan» adopted the same
// band (FER-940) — one component, one look.
//
// The band undoes the screen's horizontal inset with negative padding so the wash runs edge to
// edge, then restores the text to the margin — callers just drop it inside their padded VStack.

public struct InstrumentoSectionBand<Trailing: View>: View {
    @Environment(\.instrumentoTheme) private var theme
    private let title: LocalizedStringKey
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(InstrumentoType.grotesk(11, weight: .semibold)).tracking(1.4)
                .textCase(.uppercase).foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, LiquidSpace.s600)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.patternBlock)
        .padding(.horizontal, -LiquidSpace.s600)
    }
}

public extension InstrumentoSectionBand where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

#Preview("Section bands") {
    VStack(alignment: .leading, spacing: 24) {
        InstrumentoSectionBand("The session today")
        InstrumentoSectionBand("Your plan") {
            Text("Edit week").font(StrandFont.subhead)
        }
        InstrumentoSectionBand("My routines") {
            Text(verbatim: "＋ Nueva").font(StrandFont.subhead)
        }
    }
    .padding(.horizontal, LiquidSpace.s600)
    .padding(.vertical, 40)
    .background(InstrumentoTheme.base.paper)
}
