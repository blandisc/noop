#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Plate calculator + warm-up (FER-720 · 3a)
//
// Pushed from the session keypad's «⛓ discos» accessory for a work weight. Shows the bar loaded to
// scale (per side, heaviest first), the user's editable plate inventory, and a suggested warm-up ramp
// up to the target — «Insertar calentamiento» drops those sets at the front of the exercise (1j).
//
// Metric (kg): the plate denominations, bar, and the whole «Flujo Entrenar v3» mock are kilograms.
// Imperial lb-plate inventories are a separate concern (not in scope here).

struct PlatesScreen: View {
    let theme: InstrumentoTheme
    /// The work weight (kg) to load and warm up to — the value in the cell that opened this.
    let targetKg: Double
    let exerciseName: String
    @ObservedObject var store: PlatesStore
    /// Insert the warm-up ramp into the session; the sheet dismisses after.
    let onInsertWarmup: ([(weightKg: Double, reps: Int)]) -> Void
    let onClose: () -> Void
    /// r20 (auditoría UX #6c): «Añadir calentamiento» ancla la hoja directo en su sección — quien
    /// pidió calentar no debería aterrizar en el héroe de discos.
    var startAtWarmup = false

    @State private var editingInventory = false

    private var loading: PlateMath.Loading {
        PlateMath.perSide(targetKg: targetKg, barKg: store.barKg, inventory: store.inventory)
    }
    private var warmup: [PlateMath.WarmupSet] {
        PlateMath.warmup(workKg: targetKg, barKg: store.barKg, inventory: store.inventory)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    loadedTotal
                    barDiagram
                    inventorySection
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    warmupSection
                        .id("warmup")
                }
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.top, 18)
                .padding(.bottom, CenitMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { if startAtWarmup { proxy.scrollTo("warmup", anchor: .top) } }
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        .preferredColorScheme(.light)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(exerciseName.uppercased()).groteskOverline().foregroundStyle(theme.inkTertiary)
            Spacer()
            Button(action: onClose) {
                StrandIcon.close.image.font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary)
            }
            .accessibilityLabel(Text("Close"))
        }
    }

    // MARK: The dominant number — the loaded total

    private var loadedTotal: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Canvas pass 2026-07-15 (UI·armonía #1): one hero size across sibling sheets (64,
                // same as the RPE sheet).
                Text(kg(loading.achievedKg))
                    .font(InstrumentoType.groteskSheetHero).tracking(InstrumentoType.groteskSheetHeroTracking)
                    .foregroundStyle(theme.ink)
                Text("kg").font(InstrumentoType.grotesk(20, weight: .regular)).foregroundStyle(theme.inkTertiary)
            }
            Text(perSideCaption).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            // (shortfall notice moved next to the CTA that resolves it — handoff placement.)
        }
        .frame(maxWidth: .infinity)
    }

    /// Amber strip under the dominant number when the rack can't hit the target exactly.
    private var shortfallNotice: some View {
        NoteStrip(style: .warning, theme: theme) {
            Text("Your plates can't hit \(kg(targetKg)) kg exactly, closest is \(kg(loading.achievedKg)) kg")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    /// «por lado: 20 + 15 + 1,25 · barra 20 kg» — the per-side breakdown, heaviest first (handoff
    /// prefixes the scope so the number can't be misread as total plates).
    private var perSideCaption: String {
        let plates = loading.perSide.map { plate($0) }.joined(separator: " + ")
        let bar = "\(String(localized: "bar")) \(kg(store.barKg)) kg"
        return plates.isEmpty ? bar : "\(String(localized: "per side")): \(plates) · \(bar)"
    }

    // MARK: Bar diagram (to scale, per side)

    private var barDiagram: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(loading.perSide.reversed().enumerated()), id: \.offset) { _, kg in
                plateBar(kg)
            }
            RoundedRectangle(cornerRadius: 2).fill(theme.hairlineStrong) // token-exempt: geometría de dato
                .frame(width: 54, height: 6)
            ForEach(Array(loading.perSide.enumerated()), id: \.offset) { _, kg in
                plateBar(kg)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .accessibilityElement()
        .accessibilityLabel(Text(perSideCaption))
    }

    private func plateBar(_ kg: Double) -> some View {
        // Height scales with plate mass (25 kg → tall, 1.25 kg → short), clamped to a readable band.
        let h = 30 + min(46, kg * 1.7)
        return RoundedRectangle(cornerRadius: 3) // token-exempt: geometría de dato
            .fill(theme.dataStrain)   // los discos SON el dato (carga) — ember, no tinta (handoff)
            .frame(width: max(8, min(16, 6 + kg * 0.45)), height: h)
            .overlay(
                Text(plate(kg)).font(.system(size: 9, weight: .medium)).monospacedDigit() // token-exempt: microtexto <10pt
                    .foregroundStyle(theme.paper)
                    .rotationEffect(.degrees(-90)).fixedSize()
            )
    }

    // MARK: Inventory

    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR INVENTORY · PER SIDE").groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Button(action: { withAnimation(.snappy) { editingInventory.toggle() } }) {
                    // UI·armonía #2: acción de UI en tinta, no en hue de dato de salud.
                    Text(editingInventory ? "Done" : "Edit")
                        .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.ink)
                }
            }
            if editingInventory {
                inventoryEditor
            } else {
                PlateChips(items: chipItems)
            }
        }
    }

    /// Read-mode chips: owned denominations with their pair counts («20 ×1», «10 ×2»).
    private var chipItems: [PlateChips.Chip] {
        PlatesStore.selectableKg.compactMap { kg in
            let count = store.pairs(for: kg)
            guard count > 0 else { return nil }
            return PlateChips.Chip(
                id: kg,
                label: "\(plate(kg)) ×\(count)",
                owned: true
            )
        }
    }

    /// Edit mode: a stepper row per denomination, then the bar weight.
    private var inventoryEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PlatesStore.selectableKg, id: \.self) { kg in
                pairRow(kg)
                Rectangle().fill(theme.hairline).frame(height: 1)
            }
            barStepper
        }
    }

    private func pairRow(_ kg: Double) -> some View {
        let count = store.pairs(for: kg)
        return HStack(spacing: 12) {
            Text("\(plate(kg)) kg")
                .font(StrandFont.subhead)
                .foregroundStyle(count > 0 ? theme.ink : theme.inkTertiary)
            Spacer()
            pairStepper(system: "minus") {
                store.setPairs(count - 1, for: kg)
            }
            .disabled(count <= 0)
            .opacity(count <= 0 ? 0.4 : 1)
            Text("\(count)")
                .font(StrandFont.subhead).monospacedDigit()
                .foregroundStyle(theme.ink)
                .frame(minWidth: 24, alignment: .center)
            pairStepper(system: "plus") {
                store.setPairs(count + 1, for: kg)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(plate(kg)) kg, \(count) pairs"))
    }

    /// Circular − / + control (bordered circle, hairline stroke) — matches the session stepper vocabulary.
    private func pairStepper(system: String, _ action: @escaping () -> Void) -> some View {
        StepperButton(system: system, size: 34, shape: .circle,
                      glyph: StrandFont.glyph(.inline, weight: .semibold), theme: theme, action: action)
    }

    private var barStepper: some View {
        HStack(spacing: 12) {
            Text("Bar").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            Spacer()
            Text("\(kg(store.barKg)) kg").font(StrandFont.subhead).monospacedDigit().foregroundStyle(theme.ink)
            Stepper("", value: $store.barKg, in: 5...25, step: 5).labelsHidden()
        }
        .padding(.vertical, 10)
    }

    // MARK: Warm-up

    private var warmupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested warm-up up to \(kg(targetKg)) kg")
                .groteskOverline().foregroundStyle(theme.inkTertiary)

            if warmup.isEmpty {
                Text("The work weight is light. No warm-up needed.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(warmup.enumerated()), id: \.offset) { i, set in
                        if i > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                        HStack {
                            Text(warmupLabel(set)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            Spacer()
                            Text("\(kg(set.weightKg)) kg")
                                .font(InstrumentoType.groteskNumber(15)).monospacedDigit()
                                .foregroundStyle(theme.ink)
                        }
                        .padding(.vertical, 10)
                    }
                }
                // Handoff: la nota honesta del faltante vive pegada al CTA que la resuelve.
                if loading.shortfallKg > 0.01 {
                    shortfallNotice
                }
                insertButton
            }
        }
    }

    private func warmupLabel(_ set: PlateMath.WarmupSet) -> String {
        let scope = set.fractionOfWork <= 0
            ? String(localized: "Bar only")
            : "\(Int((set.fractionOfWork * 100).rounded()))%"
        return "\(scope) · \(set.reps) \(String(localized: "reps"))"
    }

    private var insertButton: some View {
        Button {
            onInsertWarmup(warmup.map { (weightKg: $0.weightKg, reps: $0.reps) })
        } label: {
            Text("Insert warm-up into the session")
                .font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
        }
        .buttonStyle(.plain).padding(.top, 6)
    }

    // MARK: Formatting

    private func kg(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }
    /// A plate weight without a trailing «,0» (60, not 60,0) but keeping a half decimal (2,5 / 1,25).
    private func plate(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v.rounded())) }
        let s = (v * 100).truncatingRemainder(dividingBy: 100) == 25 ? String(format: "%.2f", v) : String(format: "%.1f", v)
        return s.replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Inventory chips (a small wrapping row)

/// A simple wrapping chip row for the plate inventory — owned chips read in ink. Kept local to this
/// screen (single use); the edit mode uses per-denomination steppers instead.
struct PlateChips: View {
    struct Chip: Identifiable {
        let id: Double
        let label: String
        let owned: Bool
    }
    let items: [Chip]
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        // Canvas pass 2026-07-15 (owner): ONE row, never two — compact chips, Grotesk numerals
        // (handoff voice), sharing the width equally.
        HStack(spacing: 6) {
            ForEach(items) { chip in
                chipView(chip)
            }
        }
    }

    /// One inventory chip. Extracted + explicit types so `body` type-checks cheaply
    /// (ternaries Color/Color.clear and `[CGFloat]` dash arrays are the slow inference).
    private func chipView(_ chip: Chip) -> some View {
        let labelColor: Color = chip.owned ? theme.ink : theme.inkTertiary
        let fillColor: Color = chip.owned ? theme.surface : Color.clear
        let borderColor: Color = chip.owned ? theme.hairlineStrong : theme.hairline
        let dashPattern: [CGFloat] = chip.owned ? [] : [3, 3]
        let chipHeight: CGFloat = 30
        let lineWidth: CGFloat = 1

        return Text(chip.label)
            .font(InstrumentoType.groteskNumber(13)).monospacedDigit()
            .foregroundStyle(labelColor)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 8).frame(height: chipHeight).frame(maxWidth: .infinity)
            .background(Capsule().fill(fillColor))
            .overlay(Capsule().strokeBorder(borderColor,
                                            style: StrokeStyle(lineWidth: lineWidth, dash: dashPattern)))
    }
}
#endif
