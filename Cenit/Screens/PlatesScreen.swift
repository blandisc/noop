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

    @State private var editingInventory = false

    private var loading: PlateMath.Loading {
        PlateMath.perSide(targetKg: targetKg, barKg: store.barKg, inventory: store.inventory)
    }
    private var warmup: [PlateMath.WarmupSet] {
        PlateMath.warmup(workKg: targetKg, barKg: store.barKg, inventory: store.inventory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                loadedTotal
                barDiagram
                inventorySection
                Rectangle().fill(theme.hairline).frame(height: 1)
                warmupSection
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Image(systemName: "xmark").font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary)
            }
            .accessibilityLabel(Text("Close"))
        }
    }

    // MARK: The dominant number — the loaded total

    private var loadedTotal: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kg(loading.achievedKg))
                    .font(InstrumentoType.grotesk(52, weight: .semibold)).monospacedDigit()
                    .tracking(-0.5).foregroundStyle(theme.ink)
                Text("kg").font(InstrumentoType.grotesk(20, weight: .regular)).foregroundStyle(theme.inkTertiary)
            }
            Text(perSideCaption).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            if loading.shortfallKg > 0.01 {
                Text("\(kg(loading.shortfallKg)) kg short of \(kg(targetKg)) with your plates")
                    .font(StrandFont.caption).foregroundStyle(theme.warning)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// «20 + 15 + 1,25 · barra 20 kg» — the per-side breakdown, heaviest first.
    private var perSideCaption: String {
        let plates = loading.perSide.map { plate($0) }.joined(separator: " + ")
        let bar = "\(String(localized: "bar")) \(kg(store.barKg)) kg"
        return plates.isEmpty ? bar : "\(plates) · \(bar)"
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
            .fill(theme.ink)
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
                Text("My plates").groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Button(action: { withAnimation(.snappy) { editingInventory.toggle() } }) {
                    Text(editingInventory ? "Done" : "Edit")
                        .font(StrandFont.caption).foregroundStyle(theme.dataStrain)
                }
            }
            barStepper
            PlateChips(items: chipItems)
        }
    }

    private var chipItems: [PlateChips.Chip] {
        PlatesStore.selectableKg.map { kg in
            let owned = store.owns(kg)
            let visible = editingInventory || owned
            return PlateChips.Chip(id: kg, label: plate(kg), owned: owned, visible: visible) {
                if editingInventory { store.toggle(kg) }
            }
        }
    }

    private var barStepper: some View {
        HStack(spacing: 12) {
            Text("Bar").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            Spacer()
            Text("\(kg(store.barKg)) kg").font(StrandFont.subhead).monospacedDigit().foregroundStyle(theme.ink)
            if editingInventory {
                Stepper("", value: $store.barKg, in: 5...25, step: 5).labelsHidden()
            }
        }
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
                                .font(StrandFont.subhead).fontWeight(.medium).monospacedDigit()
                                .foregroundStyle(theme.ink)
                        }
                        .padding(.vertical, 10)
                    }
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
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.ctaRadius, style: .continuous))
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

/// A simple wrapping chip row for the plate inventory — owned chips read in ink, un-owned (edit mode)
/// read as a muted outline. Kept local to this screen (single use).
struct PlateChips: View {
    struct Chip: Identifiable {
        let id: Double
        let label: String
        let owned: Bool
        let visible: Bool
        let tap: () -> Void
    }
    let items: [Chip]
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        // A lazy grid wraps naturally at this width without a custom layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items.filter(\.visible)) { chip in
                Button(action: chip.tap) {
                    Text(chip.label)
                        .font(StrandFont.subhead).monospacedDigit()
                        .foregroundStyle(chip.owned ? theme.ink : theme.inkTertiary)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Capsule().fill(chip.owned ? theme.surface : Color.clear))
                        .overlay(Capsule().strokeBorder(chip.owned ? theme.hairlineStrong : theme.hairline,
                                                        style: StrokeStyle(lineWidth: 1, dash: chip.owned ? [] : [3, 3])))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
#endif
