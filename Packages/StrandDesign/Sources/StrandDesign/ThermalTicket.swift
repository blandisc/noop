import SwiftUI

// MARK: - Thermal receipt system (handoff «Recibo de entrenamiento» · Entrenar, jul-2026)
//
// The workout receipt is a PHYSICAL object inside the screen: a thermal ticket — pure white,
// monospace, a dentated torn edge — deliberately apart from the app's warm «Instrumento diurno»
// paper. Everything here is the STATIC visual of that object; the printer physics (print / drag /
// tear / remove) lives in the app screen that presents it, not in the design system.
//
// The design package stays pure: these views take design-level value types (`ThermalReceipt`,
// `MiniTicket`) — the app maps its own `StrengthSummary` onto them. Fonts are SF Mono (via
// `StrandFont.mono`), the owner-approved stand-in for Space Mono (no bundled face).

// MARK: - Tokens

/// The thermal-ticket palette — a physical white object, so these are fixed (not theme-driven):
/// the app's paper never bleeds into the ticket. HR-zone colors carry Cénit meaning (olive → rose),
/// NOT the reference-video hues.
public enum ThermalPalette {
    /// Ticket stock — pure white (the ONLY pure white in the app).
    public static let paper       = Color(hex: "#FFFFFF")
    /// Thermal ink.
    public static let ink         = Color(hex: "#1B1B1B")
    /// Faint thermal ink — captions, order line, low-tint rows.
    public static let faint       = Color(hex: "#8A8A8A")
    /// The 1px dashed rule on the ticket.
    public static let rule        = Color(hex: "#CFCFCF")
    /// Record marker / HRR pink — the Cénit heart-recovery hue (`#A64A5E`).
    public static let recordPink  = Color(hex: "#A64A5E")

    // MARK: HR zones — Cénit meaning (Z2 olive · Z3 gold · Z4 ember · Z5 rose)
    public static let zone2 = Color(hex: "#9C8E68")
    public static let zone3 = Color(hex: "#C99A2E")
    public static let zone4 = Color(hex: "#C4631F")
    public static let zone5 = Color(hex: "#A64A5E")
    /// Z1 (rarely used on a strength ticket) — a calm neutral so a stray sample doesn't shout.
    public static let zone1 = Color(hex: "#B7AE97")

    public static let zoneRamp: [Color] = [zone1, zone1, zone2, zone3, zone4, zone5]

    /// HR-zone color for a 1…5 index (clamped). Index 0 mirrors Z1.
    public static func zoneColor(_ z: Int) -> Color { zoneRamp[max(0, min(5, z))] }
}

// MARK: - Models

/// One receipt = one strength (or cardio) session, itemized like a paper receipt.
public struct ThermalReceipt: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var zone: Int          // HR zone of the exercise (colors the leading dot)
        public var name: String
        public var isRecord: Bool
        public var detail: String     // «3×8 · 82,5 kg · 165 bpm»
        public var price: String      // volume as a "price" — «1.980»
        public init(zone: Int, name: String, isRecord: Bool = false, detail: String, price: String) {
            self.zone = zone; self.name = name; self.isRecord = isRecord
            self.detail = detail; self.price = price
        }
    }
    public struct ZoneSlice: Equatable, Sendable {
        public var zone: Int          // 2…5
        public var fraction: Double   // 0…1 of time-in-zone
        public var label: String      // «Z4 44%»
        public init(zone: Int, fraction: Double, label: String) {
            self.zone = zone; self.fraction = fraction; self.label = label
        }
    }
    public struct SummaryRow: Equatable, Sendable {
        public var key: String
        public var value: String
        public var pink: Bool         // only the HRR row wears color
        public init(key: String, value: String, pink: Bool = false) {
            self.key = key; self.value = value; self.pink = pink
        }
    }

    public var title: String          // «RECIBO DE ENTRENAMIENTO»
    public var kind: String           // «FUERZA — DÍA A · EMPUJE»
    public var orderLine: String      // «ORDEN:#0584 · 14 MAR 2025 · 07:12»
    public var items: [Item]
    public var totalCaption: String   // «6 ejercicios · 18 series»
    public var total: String          // «9.424 kg»
    public var zones: [ZoneSlice]
    public var summary: [SummaryRow]
    public var footerCode: String     // «CENIT · 0584 · 2025»
    public var footerTag: String      // tagline
    public var barcodeSeed: String

    public init(title: String = "RECIBO DE ENTRENAMIENTO", kind: String, orderLine: String,
                items: [Item], totalCaption: String, total: String, zones: [ZoneSlice],
                summary: [SummaryRow], footerCode: String, footerTag: String, barcodeSeed: String) {
        self.title = title; self.kind = kind; self.orderLine = orderLine; self.items = items
        self.totalCaption = totalCaption; self.total = total; self.zones = zones
        self.summary = summary; self.footerCode = footerCode; self.footerTag = footerTag
        self.barcodeSeed = barcodeSeed
    }
}

/// A cell in the «Tickets guardados» grid — the compact face of a saved receipt.
public struct MiniTicket: Equatable, Identifiable, Sendable {
    public var id: String
    public var orderText: String      // «CÉNIT · #0584»
    public var dateText: String       // «9 JUL» (ignored when isToday)
    public var isToday: Bool
    public var type: String           // «EMPUJE»
    public var isRecord: Bool
    public var value: String          // «9.424»
    public var unit: String           // «kg» / «km»
    public var bars: [Double]         // 0…1 mini bars
    public init(id: String, orderText: String, dateText: String, isToday: Bool = false,
                type: String, isRecord: Bool = false, value: String, unit: String, bars: [Double]) {
        self.id = id; self.orderText = orderText; self.dateText = dateText; self.isToday = isToday
        self.type = type; self.isRecord = isRecord; self.value = value; self.unit = unit; self.bars = bars
    }
}

// MARK: - Torn edge

/// The ticket outline: rounded top corners + a straight body + a dentated («torn») bottom edge.
/// Clip a thermal surface with this so the perforated bottom reads as a real receipt.
public struct ThermalTicketShape: Shape {
    public var topRadius: CGFloat
    public var toothWidth: CGFloat
    public var toothHeight: CGFloat
    public init(topRadius: CGFloat = 7, toothWidth: CGFloat = 11, toothHeight: CGFloat = 7) {
        self.topRadius = topRadius; self.toothWidth = toothWidth; self.toothHeight = toothHeight
    }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(topRadius, min(rect.width, rect.height) / 2)
        let valleyY = rect.maxY - toothHeight
        p.move(to: CGPoint(x: rect.minX, y: valleyY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: valleyY))
        // Dentated bottom, right → left. Half-tooth steps: valley (up) → tip (down) alternating.
        let half = max(toothWidth / 2, 2)
        let steps = max(Int((rect.width / half).rounded(.up)), 2)
        for i in 1...steps {
            let x = max(rect.minX, rect.maxX - CGFloat(i) * half)
            let y = (i % 2 == 1) ? rect.maxY : valleyY   // odd = tip (down), even = valley (up)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.minX, y: valleyY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Barcode

/// A deterministic barcode drawn from a seed string — no randomness, so the same session always
/// prints the same bars (stable across redraws / snapshots).
public struct BarcodeGlyph: View {
    public var seed: String
    public var color: Color
    public init(seed: String, color: Color = ThermalPalette.ink) {
        self.seed = seed; self.color = color
    }
    public var body: some View {
        Canvas { ctx, size in
            var rng = seed.unicodeScalars.reduce(UInt64(1469598103934665603)) {
                ($0 ^ UInt64($1.value)) &* 1099511628211
            }
            var x: CGFloat = 0
            while x < size.width {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let barW = CGFloat((rng >> 33) % 3) + 1          // 1…3 pt
                if (rng >> 20) & 1 == 0 {                        // ~half inked
                    ctx.fill(Path(CGRect(x: x, y: 0, width: barW, height: size.height)),
                             with: .color(color))
                }
                x += barW + 1
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The Cénit dial glyph, in thermal ink

/// The Cénit dial reduced to ink on white for the receipt header: a ring, four cardinal marks, and
/// the «now» dot at the upper-right. Monochrome by design (a printed mark, not a themed datum).
public struct ThermalDialGlyph: View {
    public var diameter: CGFloat
    public init(diameter: CGFloat = 22) { self.diameter = diameter }
    public var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let c: CGPoint = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = min(size.width, size.height) / 2 - 2
            let ring: CGRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: ring),
                       with: .color(ThermalPalette.ink), lineWidth: 1.4)
            for a in stride(from: 0.0, to: 360.0, by: 90.0) {
                let rad: Double = a * .pi / 180.0
                let p1: CGPoint = CGPoint(x: c.x + cos(rad) * (r - 2.5), y: c.y + sin(rad) * (r - 2.5))
                let p2: CGPoint = CGPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r)
                var m: Path = Path(); m.move(to: p1); m.addLine(to: p2)
                ctx.stroke(m, with: .color(ThermalPalette.ink), lineWidth: 1)
            }
            let na: Double = -45.0 * .pi / 180.0                          // «now» at upper-right
            let np: CGPoint = CGPoint(x: c.x + cos(na) * r, y: c.y + sin(na) * r)
            let dot: CGRect = CGRect(x: np.x - 2, y: np.y - 2, width: 4, height: 4)
            ctx.fill(Path(ellipseIn: dot),
                     with: .color(ThermalPalette.ink))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Time-in-zone stacked bar

/// A single stacked bar of time-in-zone, colored by the Cénit zone ramp.
public struct ZoneStackBar: View {
    public var slices: [ThermalReceipt.ZoneSlice]
    public var height: CGFloat
    public init(slices: [ThermalReceipt.ZoneSlice], height: CGFloat = 9) {
        self.slices = slices; self.height = height
    }
    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, s in
                    Rectangle()
                        .fill(ThermalPalette.zoneColor(s.zone))
                        .frame(width: max(0, geo.size.width * s.fraction))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityHidden(true)
    }
}

// MARK: - The full receipt

/// The printed thermal ticket — the static object. The presenting screen animates its reveal and
/// gesture; this view only draws it. Fixed thermal colors; SF Mono throughout.
public struct ThermalTicketView: View {
    public var receipt: ThermalReceipt
    public var width: CGFloat

    public init(receipt: ThermalReceipt, width: CGFloat = 300) {
        self.receipt = receipt; self.width = width
    }

    private var shape: ThermalTicketShape { ThermalTicketShape(topRadius: 7) }

    private var ticketHeader: some View {
        VStack(spacing: 0) {
            ThermalDialGlyph(diameter: 22).padding(.bottom, 8)
            Text(receipt.title).font(StrandFont.mono(14, weight: .bold)).tracking(0.5)
            Text(receipt.kind).font(StrandFont.mono(9)).foregroundStyle(ThermalPalette.faint).padding(.top, 3)
            Text(receipt.orderLine).font(StrandFont.mono(9)).foregroundStyle(ThermalPalette.faint).padding(.top, 1)
        }
    }

    private var ticketItems: some View {
        VStack(spacing: 7) {
            ForEach(Array(receipt.items.enumerated()), id: \.offset) { (_: Int, item: ThermalReceipt.Item) in
                itemRow(item)
            }
        }
    }

    private var ticketTotal: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(receipt.totalCaption).font(StrandFont.mono(10))
            Spacer(minLength: 8)
            Text(receipt.total).font(StrandFont.mono(14, weight: .bold))
        }
    }

    @ViewBuilder private var ticketZones: some View {
        if !receipt.zones.isEmpty {
            sectionLabel("TIEMPO EN ZONA DE FC").padding(.top, 12)
            ZoneStackBar(slices: receipt.zones).padding(.top, 6)
            zoneLegend.padding(.top, 6)
        }
    }

    @ViewBuilder private var ticketSummary: some View {
        if !receipt.summary.isEmpty {
            sectionLabel("RESUMEN").padding(.top, 12)
            VStack(spacing: 4) {
                ForEach(Array(receipt.summary.enumerated()), id: \.offset) { (_: Int, row: ThermalReceipt.SummaryRow) in
                    HStack {
                        Text(row.key).font(StrandFont.mono(9)).foregroundStyle(ThermalPalette.faint)
                        Spacer(minLength: 8)
                        Text(row.value).font(StrandFont.mono(9, weight: .bold))
                            .foregroundStyle(row.pink ? ThermalPalette.recordPink : ThermalPalette.ink)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var ticketFooter: some View {
        VStack(spacing: 0) {
            Text("*** COPIA PARA TI ***").font(StrandFont.mono(9, weight: .bold)).tracking(1.5)
                .padding(.top, 12)
            BarcodeGlyph(seed: receipt.barcodeSeed).frame(height: 34).padding(.top, 8)
            Text(receipt.footerCode).font(StrandFont.mono(8)).foregroundStyle(ThermalPalette.faint).padding(.top, 4)
            Text(receipt.footerTag).font(StrandFont.mono(8)).foregroundStyle(ThermalPalette.faint).padding(.top, 2)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ticketHeader

            dashedRule.padding(.vertical, 11)

            // Itemized exercises
            ticketItems

            dashedRule.padding(.vertical, 11)

            ticketTotal

            ticketZones

            ticketSummary

            ticketFooter
        }
        .foregroundStyle(ThermalPalette.ink)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(width: width)
        .background(ThermalPalette.paper)
        .overlay(headBanding)                       // faint thermal texture, kept subtle
        .clipShape(shape)
        .shadow(color: .black.opacity(0.14), radius: 11, x: 0, y: 8)
    }

    @ViewBuilder private func itemRow(_ item: ThermalReceipt.Item) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(ThermalPalette.zoneColor(item.zone))
                .frame(width: 6, height: 6).padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.name).font(StrandFont.mono(10.5, weight: .bold))
                    if item.isRecord {
                        Text("RÉCORD").font(StrandFont.mono(7, weight: .bold)).tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(ThermalPalette.recordPink, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(item.detail).font(StrandFont.mono(8.5)).foregroundStyle(ThermalPalette.faint)
            }
            Spacer(minLength: 6)
            Text(item.price).font(StrandFont.mono(10, weight: .bold))
        }
        .multilineTextAlignment(.leading)
    }

    private var zoneLegend: some View {
        HStack(spacing: 9) {
            ForEach(Array(receipt.zones.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 3) {
                    Circle().fill(ThermalPalette.zoneColor(s.zone)).frame(width: 6, height: 6)
                    Text(s.label).font(StrandFont.mono(8)).foregroundStyle(ThermalPalette.faint)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        HStack {
            Text(t).font(StrandFont.mono(8, weight: .bold)).tracking(1).foregroundStyle(ThermalPalette.faint)
            Spacer(minLength: 0)
        }
    }

    private var dashedRule: some View {
        ThermalRuleLine().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(ThermalPalette.rule).frame(height: 1)
    }

    /// A whisper of thermal head-banding — horizontal lines at very low opacity. Keeps the ticket
    /// from reading as flat digital white without becoming noisy.
    private var headBanding: some View {
        LinearGradient(colors: [.black.opacity(0.018), .clear, .black.opacity(0.014)],
                       startPoint: .top, endPoint: .bottom)
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }
}

/// A 1px horizontal line usable as a Shape (for the ticket dashed rules).
struct ThermalRuleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Mini ticket (grid cell)

public struct MiniTicketView: View {
    public var ticket: MiniTicket
    public init(ticket: MiniTicket) { self.ticket = ticket }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(ticket.orderText).font(StrandFont.mono(7.5)).foregroundStyle(ThermalPalette.faint)
                Spacer(minLength: 4)
                if ticket.isToday {
                    Text("HOY").font(StrandFont.mono(7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ThermalPalette.zone4, in: RoundedRectangle(cornerRadius: 3))
                } else {
                    Text(ticket.dateText).font(StrandFont.mono(7.5)).foregroundStyle(ThermalPalette.faint)
                }
            }
            HStack(spacing: 4) {
                if ticket.isRecord { Circle().fill(ThermalPalette.recordPink).frame(width: 5, height: 5) }
                Text(ticket.type).font(StrandFont.mono(9, weight: .bold)).tracking(0.5)
            }
            .padding(.top, 8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(ticket.value).font(StrandFont.mono(20, weight: .bold))
                Text(ticket.unit).font(StrandFont.mono(9)).foregroundStyle(ThermalPalette.faint)
            }
            .padding(.top, 5)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(ticket.bars.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 1).fill(ThermalPalette.ink)
                        .frame(height: max(2, 16 * h))
                }
            }
            .frame(height: 16)
            .padding(.top, 8)
        }
        .foregroundStyle(ThermalPalette.ink)
        .padding(.horizontal, 11)
        .padding(.top, 11)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity)
        .background(ThermalPalette.paper)
        .clipShape(ThermalTicketShape(topRadius: 6, toothWidth: 10, toothHeight: 6))
        .shadow(color: Color(hex: "#221D16").opacity(0.14), radius: 7, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(ticket.type), \(ticket.value) \(ticket.unit)"))
    }
}

// MARK: - Printer mouth

/// The «printer mouth» drawn at the top of the receipt screen — a dark pill that stands in for the
/// Dynamic Island (the real system island can't emit in-app content). The presenting screen widens
/// it to the ticket width while printing; this view is just the resting pill.
public struct PrinterMouth: View {
    public var width: CGFloat
    public var printing: Bool
    public init(width: CGFloat = 120, printing: Bool = false) {
        self.width = width; self.printing = printing
    }
    public var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 16,
                               bottomTrailingRadius: 16, topTrailingRadius: 0, style: .continuous)
            .fill(Color.black)
            .frame(width: width, height: printing ? 34 : 30)
            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
            .overlay(
                printing
                ? Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1).blur(radius: 2)
                : nil
            )
            .accessibilityHidden(true)
    }
}

// MARK: - «GUARDADO» embossed state

/// The debossed seal revealed behind the ticket once it's torn off and pulled out — engraved into
/// the app's warm paper (not the thermal white). Theme-driven, unlike the ticket itself.
public struct ReceiptSavedSeal: View {
    public var title: LocalizedStringKey
    public var subtitle: LocalizedStringKey
    public var chip: LocalizedStringKey
    @Environment(\.instrumentoTheme) private var theme

    public init(title: LocalizedStringKey = "GUARDADO",
                subtitle: LocalizedStringKey = "Tu recibo se guardó en tus tickets.",
                chip: LocalizedStringKey = "HISTORIAL › MIS TICKETS") {
        self.title = title; self.subtitle = subtitle; self.chip = chip
    }

    public var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(theme.paper)
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(Color(hex: "#DAD3C2"), lineWidth: 1))
                .overlay(ThermalDialEmboss().padding(12))
                .shadow(color: .black.opacity(0.14), radius: 2, x: 0, y: 2)
                .padding(.bottom, 14)
            Text(title)
                .font(InstrumentoType.grotesk(17, weight: .bold)).tracking(3)
                .foregroundStyle(Color(hex: "#E4DECF"))
                .shadow(color: .white.opacity(0.9), radius: 0, x: 0, y: 1)
                .shadow(color: .black.opacity(0.14), radius: 1, x: 0, y: -1)
            Text(subtitle)
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary).padding(.top, 6)
            Text(chip)
                .font(StrandFont.mono(8, weight: .bold)).tracking(0.8)
                .foregroundStyle(theme.inkTertiary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(theme.paper, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.hairline, lineWidth: 1))
                .padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
    }

    /// The dial glyph, engraved (deboss) into the paper — faint stroke, no fill.
    private struct ThermalDialEmboss: View {
        @Environment(\.instrumentoTheme) private var theme
        var body: some View {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(Color(hex: "#DAD3C2")), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Sample data

public extension ThermalReceipt {
    static let sample = ThermalReceipt(
        kind: "FUERZA — DÍA A · EMPUJE",
        orderLine: "ORDEN:#0584 · 14 MAR 2025 · 07:12",
        items: [
            .init(zone: 4, name: "Press banca", isRecord: true, detail: "3×8 · 82,5 kg · 165 bpm", price: "1.980"),
            .init(zone: 3, name: "Press militar", detail: "3×10 · 24 kg · 148 bpm", price: "720"),
            .init(zone: 4, name: "Fondos", detail: "3×12 · lastre 10 kg", price: "1.224"),
            .init(zone: 5, name: "Aperturas", detail: "3×15 · 14 kg · 158 bpm", price: "630"),
        ],
        totalCaption: "6 ejercicios · 18 series",
        total: "9.424 kg",
        zones: [
            .init(zone: 2, fraction: 0.10, label: "Z2 10%"),
            .init(zone: 3, fraction: 0.26, label: "Z3 26%"),
            .init(zone: 4, fraction: 0.44, label: "Z4 44%"),
            .init(zone: 5, fraction: 0.20, label: "Z5 20%"),
        ],
        summary: [
            .init(key: "DURACIÓN", value: "00:48:12"),
            .init(key: "ESFUERZO", value: "11.2 / 21"),
            .init(key: "FC MEDIA", value: "144 bpm"),
            .init(key: "CALORÍAS", value: "316 kcal"),
            .init(key: "RECUPERACIÓN 60s", value: "38 bpm ↑", pink: true),
        ],
        footerCode: "CENIT · 0584 · 2025",
        footerTag: "tu esfuerzo, en tinta.",
        barcodeSeed: "0584-2025-DIA-A"
    )
}

public extension MiniTicket {
    static let sampleGrid: [MiniTicket] = [
        .init(id: "0584", orderText: "CÉNIT · #0584", dateText: "HOY", isToday: true, type: "EMPUJE",
              isRecord: true, value: "9.424", unit: "kg", bars: [0.6, 0.9, 0.4, 0.75, 0.55]),
        .init(id: "0583", orderText: "CÉNIT · #0583", dateText: "9 JUL", type: "TIRÓN",
              value: "7.980", unit: "kg", bars: [0.5, 0.7, 0.85, 0.45, 0.6]),
        .init(id: "0582", orderText: "CÉNIT · #0582", dateText: "7 JUL", type: "PIERNA",
              isRecord: true, value: "12.150", unit: "kg", bars: [0.8, 0.55, 0.95, 0.65, 0.5]),
        .init(id: "0581", orderText: "CÉNIT · #0581", dateText: "5 JUL", type: "CARDIO",
              value: "6.4", unit: "km", bars: [0.45, 0.6, 0.5, 0.7, 0.4]),
    ]
}

// MARK: - Previews

#if DEBUG
#Preview("Ticket completo") {
    ScrollView {
        ThermalTicketView(receipt: .sample).padding(40)
    }
    .background(Color(hex: "#F4F1E8"))
    .preferredColorScheme(.light)
}

#Preview("Mini tickets · grid") {
    let cols = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]
    return ScrollView {
        LazyVGrid(columns: cols, spacing: 11) {
            ForEach(MiniTicket.sampleGrid) { MiniTicketView(ticket: $0) }
        }
        .padding(20)
    }
    .background(Color(hex: "#F4F1E8"))
    .preferredColorScheme(.light)
}

#Preview("Boca + GUARDADO") {
    VStack(spacing: 0) {
        PrinterMouth(width: 200)
        Spacer().frame(height: 40)
        ReceiptSavedSeal()
        Spacer()
    }
    .padding(.top, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(InstrumentoTheme.base.paper)
    .environment(\.instrumentoTheme, .base)
    .preferredColorScheme(.light)
}

#Preview("Torn edge · barcode") {
    VStack(spacing: 24) {
        ThermalTicketShape(topRadius: 7).fill(ThermalPalette.paper)
            .frame(width: 200, height: 120)
            .shadow(radius: 6)
        BarcodeGlyph(seed: "demo-42").frame(width: 200, height: 40)
    }
    .padding(40)
    .background(Color(hex: "#F4F1E8"))
    .preferredColorScheme(.light)
}
#endif
