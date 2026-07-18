#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandAnalytics
import StrandTraining
import WhoopProtocol

// ReceiptPrinterScreen.swift — full-screen thermal receipt printer for a finished strength session.
// Presents via `.fullScreenCover` so the printer mouth reaches the true top of the screen.
//
// FER-720 NOTE: The old share-receipt screen had privacy toggles (HR/kcal off by default, FER-720). This receipt
// intentionally shows everything (owner-approved) — no toggles here, by design.

struct ReceiptPrinterScreen: View {
    let theme: InstrumentoTheme
    let summary: StrengthSummary
    let sessionId: String
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Loaded receipt

    @State private var receipt: ThermalReceipt?
    @State private var loadFailed = false

    // MARK: - Print / ticket state machines

    private enum PrintPhase: Equatable { case warmingUp, printing, done }
    private enum TicketState: Equatable { case printed, torn, removed }

    @State private var printPhase: PrintPhase = .warmingUp
    @State private var ticketState: TicketState = .printed
    @State private var revealHeight: CGFloat = 0
    @State private var ticketHeight: CGFloat = 420
    @State private var mouthWidth: CGFloat = 120
    @State private var mouthPrinting = false
    @State private var tiltDegrees: Double = 5
    @State private var swayAngle: Double = 0
    @State private var mouthWobble: Double = 0

    // MARK: - Drag

    @State private var dragOffset: CGFloat = 0
    @State private var restOffset: CGFloat = 0
    @State private var isDragging = false

    // MARK: - Classic toggle

    @State private var showClassic = false

    // MARK: - Constants

    private let ticketWidth: CGFloat = 300
    private let restingMouth: CGFloat = 120
    private let warmUpMs: UInt64 = 650
    private let printDuration: Double = 6.2

    private var units: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var screenHeight: CGFloat { UIScreen.main.bounds.height }
    private var removeThreshold: CGFloat { -(screenHeight * 0.33) }

    var body: some View {
        ZStack {
            theme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                printerMouthRow
                    .padding(.top, 4)

                Spacer(minLength: 8)

                centerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                actionBar
                    .padding(.horizontal, CenitMetrics.screenPadding)
                    .padding(.bottom, CenitMetrics.screenPadding)
            }
        }
        .instrumentoTheme(theme)
        .preferredColorScheme(.light)
        .task(id: sessionId) { await loadAndPrint() }
    }

    // MARK: - Printer mouth

    private var printerMouthRow: some View {
        HStack {
            Spacer(minLength: 0)
            PrinterMouth(width: mouthWidth, printing: mouthPrinting)
                .rotationEffect(.degrees(mouthWobble))
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                StrandIcon.close.image
                    .font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary)
                    .padding(12)
            }
            .accessibilityLabel(Text("Close"))
            .padding(.trailing, 8)
        }
    }

    // MARK: - Center (ticket / seal / classic)

    @ViewBuilder
    private var centerContent: some View {
        if showClassic {
            ScrollView {
                ShareCardView(theme: theme, summary: summary,
                              includeHR: true, includeKcal: true, includeRecords: true)
                    .frame(width: ShareCardView.width)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        } else if ticketState == .removed {
            VStack(spacing: 20) {
                ReceiptSavedSeal()
                    .environment(\.instrumentoTheme, theme)
                StrandCTAButton("REIMPRIMIR", kind: .outline) { reprint() }
                    .frame(maxWidth: 220)
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
        } else if let receipt {
            ticketStage(receipt)
        } else if loadFailed {
            Text("No se pudo armar el recibo.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary)
        } else {
            ProgressView()
                .tint(theme.inkTertiary)
        }
    }

    private func ticketStage(_ receipt: ThermalReceipt) -> some View {
        let totalY = restOffset + dragOffset
        return ZStack(alignment: .top) {
            // Torn stub left under the mouth once the ticket is torn free.
            if ticketState == .torn {
                ThermalTicketShape(topRadius: 7, toothWidth: 11, toothHeight: 7)
                    .fill(ThermalPalette.paper)
                    .frame(width: ticketWidth, height: 18)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)   // token-exempt: recibo térmico, el único objeto no-Instrumento (sombra de la impresora)
                    .offset(y: 2)
            }

            ThermalTicketView(receipt: receipt, width: ticketWidth)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: TicketHeightKey.self, value: g.size.height)
                    }
                )
                .onPreferenceChange(TicketHeightKey.self) { ticketHeight = max($0, 1) }
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: printPhase == .warmingUp ? 0 : revealHeight)
                }
                .rotation3DEffect(
                    .degrees(printPhase == .printing ? tiltDegrees : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .top,
                    perspective: 0.3
                )
                .rotationEffect(.degrees(printPhase == .done && !isDragging ? swayAngle : 0))
                .offset(y: totalY)
                .gesture(printPhase == .done ? dragGesture : nil)
                .opacity(printPhase == .warmingUp ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isDragging = true
                let raw = value.translation.height
                // Elastic resistance when dragging up past -20 while still attached (printed).
                if ticketState == .printed, raw < -20 {
                    dragOffset = (raw + 20) * 0.3 - 20
                } else {
                    dragOffset = raw
                }
            }
            .onEnded { value in
                isDragging = false
                let translation = value.translation.height
                let projected = restOffset + translation
                handleDragEnd(translation: translation, projected: projected)
            }
    }

    private func handleDragEnd(translation: CGFloat, projected: CGFloat) {
        let crossedRemove = projected <= removeThreshold || translation <= removeThreshold

        switch ticketState {
        case .printed:
            if translation <= -30 {
                // Tear first; may also remove in the same gesture.
                withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) {
                    ticketState = .torn
                    closeMouthWithWobble()
                }
                if crossedRemove {
                    removeTicket()
                } else {
                    withAnimation(.spring()) {
                        restOffset = 0
                        dragOffset = 0
                    }
                }
            } else if crossedRemove {
                tearThenRemove()
            } else {
                withAnimation(.spring()) {
                    dragOffset = 0
                }
            }
        case .torn:
            if crossedRemove {
                removeTicket()
            } else {
                withAnimation(.spring()) {
                    restOffset = 0
                    dragOffset = 0
                }
            }
        case .removed:
            break
        }
    }

    private func tearThenRemove() {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) {
            ticketState = .torn
            closeMouthWithWobble()
        }
        removeTicket()
    }

    private func removeTicket() {
        let fly = screenHeight + 90
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
            dragOffset = fly
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            ticketState = .removed
            dragOffset = 0
            restOffset = 0
        }
    }

    private func closeMouthWithWobble() {
        mouthPrinting = false
        mouthWidth = restingMouth
        mouthWobble = 4
        withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) {
            mouthWobble = 0
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 10) {
            StrandCTAButton("Ver en Apple Health") {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                }
            }

            HStack(spacing: 10) {
                StrandCTAButton("Guardar", kind: .outline) {
                    if let img = renderTicket() { FileExport.saveImageToPhotos(img) }
                }
                StrandCTAButton("Compartir", kind: .outline) {
                    if let img = renderTicket() { FileExport.exportImage(img) }
                }
                StrandCTAButton(showClassic ? "Ver ticket" : "Vista clásica", kind: .outline) {
                    withAnimation(.easeInOut(duration: 0.25)) { showClassic.toggle() }
                }
            }
        }
    }

    // MARK: - Render / load / print sequence

    @MainActor
    private func renderTicket() -> UIImage? {
        guard let receipt else { return nil }
        let renderer = ImageRenderer(content:
            ThermalTicketView(receipt: receipt, width: ticketWidth)
        )
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    @MainActor
    private func loadAndPrint() async {
        resetVisualState(keepReceipt: false)

        let sets = await model.repo.sessionSets(sessionId: sessionId)

        let sessionStart = summary.endTs - summary.durationS
        let hr = await model.repo.hrSamples(
            from: sessionStart - 120,
            to: summary.endTs + 120,
            limit: 8000
        )

        let all = await model.repo.allExercises()
        let exerciseNames = Dictionary(uniqueKeysWithValues: all.map {
            ($0.id, StrengthDisplay.name($0))
        })

        // HRR window — same pattern as WorkoutDetailScreen.loadHRR (no personal baseline).
        let pad = HeartRateRecovery.horizonS + 2 * HeartRateRecovery.anchorHalfWidthS
        let hrWin = await model.repo.hrSamples(
            from: summary.endTs - 2 * HeartRateRecovery.anchorHalfWidthS,
            to: summary.endTs + pad,
            limit: 4000
        )
        let hrrResult = HeartRateRecovery.hrr60s(sessionEnd: summary.endTs, hr: hrWin)
        let hrr: (bpm: Int, risingIsGood: Bool)? = {
            guard hrrResult.covered, let drop = hrrResult.hrrBpm else { return nil }
            return (bpm: Int(drop.rounded()), risingIsGood: true)
        }()

        let mapped = ReceiptMapping.receipt(
            summary: summary,
            sessionId: sessionId,
            sets: sets,
            exerciseNames: exerciseNames,
            hr: hr,
            age: Double(model.profile.age),
            hrr: hrr,
            system: units
        )
        receipt = mapped
        loadFailed = false

        await runPrintSequence()
    }

    @MainActor
    private func runPrintSequence() async {
        // warmingUp — resting mouth only
        printPhase = .warmingUp
        mouthWidth = restingMouth
        mouthPrinting = false
        revealHeight = 0
        tiltDegrees = 5

        try? await Task.sleep(nanoseconds: warmUpMs * 1_000_000)
        guard !Task.isCancelled else { return }

        // printing — widen mouth + reveal ticket bottom-first
        printPhase = .printing
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4)) {
            mouthWidth = ticketWidth
            mouthPrinting = true
        }

        let duration = reduceMotion ? 0.35 : printDuration
        withAnimation(.easeInOut(duration: duration)) {
            revealHeight = ticketHeight
        }

        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) + 50_000_000)
        guard !Task.isCancelled else { return }

        // done — settle tilt, start sway
        printPhase = .done
        mouthPrinting = true
        withAnimation(.easeOut(duration: 0.6)) {
            tiltDegrees = 0
        }
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
                swayAngle = 0.3
            }
        }
    }

    private func reprint() {
        showClassic = false
        resetVisualState(keepReceipt: true)
        Task { await runPrintSequence() }
    }

    private func resetVisualState(keepReceipt: Bool) {
        printPhase = .warmingUp
        ticketState = .printed
        revealHeight = 0
        mouthWidth = restingMouth
        mouthPrinting = false
        tiltDegrees = 5
        swayAngle = 0
        mouthWobble = 0
        dragOffset = 0
        restOffset = 0
        isDragging = false
        if !keepReceipt {
            receipt = nil
            loadFailed = false
        }
    }
}

// MARK: - Preference key (ticket height for the reveal mask)

private struct TicketHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 420
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
