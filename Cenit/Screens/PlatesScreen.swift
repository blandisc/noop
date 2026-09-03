#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics

// MARK: - Plate calculator + warm-up (FER-720 · 3a · FER-302 Liquid Glass · El Eje)
//
// Pushed from the session keypad's «⛓ discos» accessory for a work weight. Shows the bar loaded to
// scale (per side, heaviest first), the user's editable plate inventory, and a suggested warm-up ramp
// up to the target — «Insertar calentamiento» drops those sets at the front of the exercise (1j).
//
// Metric (kg): the plate denominations, bar, and the whole «Flujo Entrenar v3» mock are kilograms.
// Imperial lb-plate inventories are a separate concern (not in scope here).

struct PlatesScreen: View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var loading: PlateMath.Loading {
        PlateMath.perSide(targetKg: targetKg, barKg: store.barKg, inventory: store.inventory)
    }
    private var warmup: [PlateMath.WarmupSet] {
        PlateMath.warmup(workKg: targetKg, barKg: store.barKg, inventory: store.inventory)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                    // FER-198 (Ola 2): la cabecera de la familia El Eje reemplaza el overline a
                    // mano + `BackButton` — mismo `exerciseName`, sin copy nueva.
                    EntrenarHojaCabecera(titulo: exerciseName, tono: .ambar, salida: .cerrar, onSalir: onClose)
                    loadedTotal
                    barDiagram
                    inventorySection
                    Rectangle().fill(LiquidColor.tinta10).frame(height: 1)
                    warmupSection
                        .id("warmup")
                }
                .padding(.horizontal, LiquidSpace.s600)
                .padding(.top, LiquidSpace.s450)
                .padding(.bottom, LiquidSpace.s600)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { if startAtWarmup { proxy.scrollTo("warmup", anchor: .top) } }
        }
        .entrenarHojaFondo(tono: .ambar)
        .edgeSwipeToExit(onClose)
    }

    // MARK: The dominant number — the loaded total

    private var loadedTotal: some View {
        VStack(alignment: .center, spacing: LiquidSpace.s150) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                // FER-302: numeral de hoja El Eje (hermanas RestEditor / RPE).
                Text(kg(loading.achievedKg))
                    .font(LiquidType.numeralHoja)
                    .foregroundStyle(LiquidColor.tinta900)
                    .accessibilityLabel(Text("Loaded total \(kg(loading.achievedKg)) kg"))
                Text("kg").font(LiquidType.numeralHojaUnidad).foregroundStyle(LiquidColor.tinta500)
            }
            Text(perSideCaption).font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta500)
            // (shortfall notice moved next to the CTA that resolves it — handoff placement.)
        }
        .frame(maxWidth: .infinity)
    }

    /// Amber strip under the dominant number when the rack can't hit the target exactly.
    private var shortfallNotice: some View {
        LiquidAviso(
            titulo: String(localized: "healthAlert.overline.atencion", defaultValue: "Heads up"),
            cuerpo: String(localized: "Your plates can't hit \(kg(targetKg)) kg exactly, closest is \(kg(loading.achievedKg)) kg"),
            tono: LiquidColor.atencion)
        .padding(.top, LiquidSpace.s100)
    }

    /// «por lado: 20 + 15 + 1,25 · barra 20 kg» — the per-side breakdown, heaviest first (handoff
    /// prefixes the scope so the number can't be misread as total plates).
    private var perSideCaption: String {
        let plates = loading.perSide.map { plate($0) }.joined(separator: " + ")
        let bar = "\(String(localized: "bar")) \(kg(store.barKg)) kg"
        return plates.isEmpty ? bar : "\(String(localized: "per side")): \(plates) · \(bar)"
    }

    // MARK: Bar diagram (to scale, per side)

    // FER-198 (Ola 2): `EntrenarFilaDiscos` es el mismo diagrama re-vestido — misma fórmula de
    // alto/ancho por kg, mismo orden invertido/directo por lado, mismo color del DATO
    // (`LiquidColor.ambar`); la barra central y el microtexto migran a tokens Liquid.
    private var barDiagram: some View {
        EntrenarFilaDiscos(
            discos: loading.perSide.map { EntrenarFilaDiscos.Disco(masaKg: $0, etiqueta: plate($0)) },
            tono: .ambar,
            a11yLabel: perSideCaption)
    }

    // MARK: Inventory

    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            HStack {
                Text("YOUR INVENTORY · PER SIDE").liquidKicker().foregroundStyle(LiquidColor.tinta500)
                Spacer()
                // FER-89 (auditoría Reduce Motion): sin esto el pliegue del editor de inventario
                // animaba siempre, sin alternativa quieta. `LiquidMotion.condicionado` apaga la animación
                // cuando el sistema pide Reducir movimiento — el mismo patrón que ya usa el paquete
                // (`ReduceMotion.swift`) en vez de un `reduceMotion ? nil : x` a mano.
                Button(action: { withAnimation(LiquidMotion.condicionado(.snappy, reduceMotion)) { editingInventory.toggle() } }) {
                    // UI·armonía #2: acción de UI en tinta, no en hue de dato de salud.
                    Text(editingInventory ? "Done" : "Edit")
                        .font(LiquidType.filaConteo.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
                        // FER-89: sin esto el toque real era del tamaño del texto (~20 pt) — bajo el
                        // piso de 44 pt (HIG). El dibujo no cambia (texto pegado al filo derecho);
                        // solo crece, hacia la izquierda, el área que responde.
                        .frame(minWidth: EntrenarMetrics.row, minHeight: EntrenarMetrics.row, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                // FER-89: adopta el press de la sección — antes no tenía NINGÚN buttonStyle explícito.
                .buttonStyle(EntrenarPressStyle())
                .accessibilityLabel(Text(editingInventory
                    ? String(localized: "plates.a11y.doneEditingInventory",
                             defaultValue: "Listo con el inventario")
                    : String(localized: "plates.a11y.editInventory",
                             defaultValue: "Editar inventario")))
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
        VStack(alignment: .leading, spacing: .zero) {
            ForEach(PlatesStore.selectableKg, id: \.self) { kg in
                pairRow(kg)
                Rectangle().fill(LiquidColor.tinta10).frame(height: 1)
            }
            barStepper
        }
    }

    private func pairRow(_ kg: Double) -> some View {
        let count = store.pairs(for: kg)
        return HStack(spacing: LiquidSpace.s300) {
            Text("\(plate(kg)) kg")
                .font(LiquidType.cuerpoBanner)
                .foregroundStyle(count > 0 ? LiquidColor.tinta900 : LiquidColor.tinta500)
            Spacer()
            EntrenarStepper(
                valor: "\(count)",
                tono: .ambar,
                talla: .fila,
                puedeBajar: count > 0,
                puedeSubir: true,
                onBajar: { store.setPairs(count - 1, for: kg) },
                onSubir: { store.setPairs(count + 1, for: kg) })
        }
        .padding(.vertical, LiquidSpace.s250)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(plate(kg)) kg, \(count) pairs"))
    }

    private var barStepper: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text("Bar").font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
            Spacer()
            EntrenarStepper(
                valor: "\(kg(store.barKg)) kg",
                tono: .ambar,
                talla: .fila,
                puedeBajar: store.barKg > 5,
                puedeSubir: store.barKg < 25,
                onBajar: { store.barKg = max(5, store.barKg - 5) },
                onSubir: { store.barKg = min(25, store.barKg + 5) })
        }
        .padding(.vertical, LiquidSpace.s250)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Bar \(kg(store.barKg)) kg"))
    }

    // MARK: Warm-up

    private var warmupSection: some View {
        VStack(alignment: .leading, spacing: EntrenarMetrics.bandGap) {
            Text("Suggested warm-up up to \(kg(targetKg)) kg")
                .liquidKicker().foregroundStyle(LiquidColor.tinta500)

            if warmup.isEmpty {
                Text("The work weight is light. No warm-up needed.")
                    .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
            } else {
                VStack(spacing: .zero) {
                    ForEach(Array(warmup.enumerated()), id: \.offset) { i, set in
                        if i > 0 { Rectangle().fill(LiquidColor.tinta10).frame(height: 1) }
                        HStack {
                            Text(warmupLabel(set)).font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                            Spacer()
                            Text("\(kg(set.weightKg)) kg")
                                .font(LiquidType.datoMenor).monospacedDigit()
                                .foregroundStyle(LiquidColor.tinta900)
                        }
                        .padding(.vertical, LiquidSpace.s250)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("\(warmupLabel(set)), \(kg(set.weightKg)) kg"))
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
        LiquidGlassButton("Insert warm-up into the session", variant: .primary, expands: true) {
            onInsertWarmup(warmup.map { (weightKg: $0.weightKg, reps: $0.reps) })
        }
        .padding(.top, LiquidSpace.s150)
        .accessibilityLabel(Text("Insert warm-up into the session"))
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

    var body: some View {
        // Canvas pass 2026-07-15 (owner): ONE row, never two — compact chips, Grotesk numerals
        // (handoff voice), sharing the width equally.
        HStack(spacing: LiquidSpace.s150) {
            ForEach(items) { chip in
                chipView(chip)
            }
        }
    }

    /// One inventory chip. Extracted + explicit types so `body` type-checks cheaply
    /// (ternaries Color/Color.clear and `[CGFloat]` dash arrays are the slow inference).
    private func chipView(_ chip: Chip) -> some View {
        let labelColor: Color = chip.owned ? LiquidColor.tinta900 : LiquidColor.tinta500
        let chipHeight: CGFloat = 30

        return Text(chip.label)
            .font(LiquidType.valorS).monospacedDigit()
            .foregroundStyle(labelColor)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .outlineCapsule(
                chip.owned ? .tenida(.ambar) : .outline,
                size: .aMedida(
                    insets: EdgeInsets(top: .zero, leading: LiquidSpace.s200,
                                       bottom: .zero, trailing: LiquidSpace.s200),
                    minHeight: chipHeight,
                    touchInset: .zero))
            .accessibilityLabel(Text(chip.label))
    }
}
#endif
