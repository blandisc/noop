import SwiftUI
import CenitDesign
import CenitStore
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - Manual workout sheet — Liquid Glass · El Eje (FER-266 · FER-304)
//
// Add a workout you tracked elsewhere, or edit one you already logged. Five inputs — sport,
// start, duration, average HR, calories — validated by WorkoutSource.buildManualRow (the same
// honest-row rules the engine uses). On save the caller persists it under the strap source via
// Repository.saveManualWorkout. Captured-but-unexposed fields (maxHr / strain / zones) on an edited
// row are carried over by WorkoutSource.preservingCaptured so editing a live-tracked session's
// sport/duration never silently wipes its real strain.
//
// `editing` is non-nil when editing an existing row (its values pre-fill the form and it is passed
// as `replacing:` so a changed natural key deletes the old row). nil = a fresh add.
//
// Liquid Glass · El Eje tokens. The old fixed `frame(width: 420)` (a macOS-era width) is gone —
// the form fills the sheet's width on iPhone.
//
// FER-202 (anillo 3, épico FER-195): el papel plano cede al cristal El Eje
// (`.entrenarHojaFondo(tono: .neutro)` + `EntrenarHojaCabecera(.cancelar)`). Las DOS salidas se
// conservan — Cancelar sube a la cabecera, Guardar/Añadir sigue siendo el CTA del footer (mismo
// patrón que `RestEditorScreen` Ola 2). Cero cambio de comportamiento.

struct ManualWorkoutSheet: View {
    /// The row being edited, or nil for a new manual workout.
    let editing: WorkoutRow?
    /// Called with the validated row (and the original, when editing) once the user taps Save.
    let onSave: (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sport: String
    @State private var start: Date
    @State private var durationMin: Int
    @State private var avgHrText: String
    @State private var kcalText: String

    init(editing: WorkoutRow? = nil,
         onSave: @escaping (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void) {
        self.editing = editing
        self.onSave = onSave
        // Pre-fill from the edited row (display "detected" as "Activity" so a re-label starts clean).
        let e = editing
        _sport = State(initialValue: e.map { WorkoutSource.displaySport($0.sport) } ?? "")
        _start = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.startTs)) } ?? Date())
        _durationMin = State(initialValue: e.map { max(1, Int((($0.durationS ?? Double($0.endTs - $0.startTs)) / 60).rounded())) } ?? 45)
        _avgHrText = State(initialValue: e?.avgHr.map(String.init) ?? "")
        _kcalText = State(initialValue: e?.energyKcal.map { String(Int($0.rounded())) } ?? "")
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                header
                VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
                    LiquidCampoTexto(
                        String(localized: "Sport"),
                        texto: $sport,
                        placeholder: String(localized: "e.g. Running"),
                        a11y: String(localized: "Sport"),
                        tipografia: LiquidType.tituloGemela)
                    field("Start") {
                        DatePicker("", selection: $start, in: ...Date(),
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(LiquidColor.tinta900)
                            .accessibilityLabel("Start date and time")
                    }
                    field("Duration") {
                        EntrenarStepper(
                            valor: durationLabel,
                            tono: .neutro,
                            talla: .fila,
                            puedeBajar: durationMin > 1,
                            puedeSubir: durationMin < 24 * 60,
                            onBajar: { durationMin = max(1, durationMin - 5) },
                            onSubir: { durationMin = min(24 * 60, durationMin + 5) }
                        )
                        .accessibilityLabel("Duration in minutes")
                    }
                    HStack(alignment: .top, spacing: LiquidSpace.bloqueAjuste) {
                        field("Avg HR") {
                            numberInput(
                                String(localized: "optional"),
                                text: $avgHrText,
                                unit: String(localized: "bpm"),
                                a11y: String(localized: "Average heart rate in beats per minute, optional"))
                        }
                        field("Calories") {
                            numberInput(
                                String(localized: "optional"),
                                text: $kcalText,
                                unit: "kcal",
                                a11y: String(localized: "Calories in kilocalories, optional"))
                        }
                    }
                }
                if let validationNote { noteRow(validationNote) }
                footer
            }
            .padding(LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-202: cristal El Eje. Se retira `.sheetPaper` (papel opaco de presentación) — taparía
        // el vidrio; el fondo lo pinta `.entrenarHojaFondo`. ScrollView intacto (no-sheet-glass).
        .entrenarHojaFondo(tono: .neutro)
        .presentationDragIndicator(.visible)
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    // MARK: - Sections

    /// FER-202: `EntrenarHojaCabecera(.cancelar)` absorbe el título+subtítulo a mano Y el «Cancel»
    /// del footer — mismas cadenas ya localizadas, misma acción (`dismiss()`). El CTA de
    /// Guardar/Añadir sigue abajo (no cabe en la Salida única de la cabecera junto a Cancelar).
    private var header: some View {
        EntrenarHojaCabecera(
            titulo: editing == nil
                ? String(localized: "Add Workout")
                : String(localized: "Edit Workout"),
            subtitulo: editing == nil
                ? String(localized: "Log a session you tracked elsewhere.")
                : String(localized: "Adjust this session's details."),
            tono: .neutro,
            salida: .cancelar(String(localized: "Cancel")),
            onSalir: { dismiss() }
        )
    }

    private var footer: some View {
        HStack {
            Spacer()
            saveButton
        }
        .padding(.top, LiquidSpace.s100)
    }

    /// Prominent primary — verdict-green capsule when the inputs make an honest row, a quiet disabled
    /// surface otherwise (mirrors the disabled Save the form has always had, in the light language).
    private var saveButton: some View {
        let enabled = builtRow != nil
        let title: LocalizedStringKey = editing == nil ? "Add" : "Save"
        return Group {
            if enabled {
                OutlineCapsule(
                    size: .aMedida(
                        insets: EdgeInsets(top: LiquidSpace.s225, leading: LiquidSpace.pastillaHorizontal,
                                           bottom: LiquidSpace.s225, trailing: LiquidSpace.pastillaHorizontal),
                        minHeight: nil,
                        touchInset: .zero),
                    filled: true,
                    fill: LiquidColor.verdePrimario,
                    action: { save() }
                ) {
                    Text(title)
                        .font(LiquidType.boton)
                        .foregroundStyle(LiquidColor.papelTarjeta)
                }
            } else {
                // FER-220: la cápsula deshabilitada usa `.liquidGlass(.pastillaSolida)`
                // (recorte opaco compartido); el verde del CTA activo es color semántico.
                Button { save() } label: {
                    Text(title)
                        .font(LiquidType.boton)
                        .foregroundStyle(LiquidColor.tinta500)
                        .padding(.horizontal, LiquidSpace.pastillaHorizontal).padding(.vertical, LiquidSpace.s225)
                        .liquidGlass(.pastillaSolida)
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
        }
        .accessibilityLabel(editing == nil ? "Add workout" : "Save workout")
    }

    private func field<Content: View>(_ label: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(label).liquidKicker().foregroundStyle(LiquidColor.tinta500)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberInput(_ placeholder: String, text: Binding<String>,
                             unit: String, a11y: String) -> some View {
        LiquidCampoTexto(
            nil,
            texto: text,
            placeholder: placeholder,
            teclado: LiquidCampoTeclado.numberPad,
            a11y: a11y,
            sufijo: unit,
            tipografia: LiquidType.valorM)
    }

    private func noteRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LiquidType.unidad)
            .foregroundStyle(LiquidColor.atencionTexto)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Validation / build

    private var durationLabel: String {
        let h = durationMin / 60, m = durationMin % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Parsed avg-HR — nil for blank, an out-of-band sentinel handled by buildManualRow otherwise.
    private var avgHr: Int? { Int(avgHrText.trimmingCharacters(in: .whitespaces)) }
    private var kcal: Double? { Double(kcalText.trimmingCharacters(in: .whitespaces)) }

    /// The validated row, or nil when the inputs can't make an honest one (drives the disabled Save +
    /// the inline note). Built through the same WorkoutSource.buildManualRow the engine trusts.
    private var builtRow: WorkoutRow? {
        // A typed-but-unparseable number is invalid (e.g. "abc" in Avg HR) — guard before building.
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty && avgHr == nil { return nil }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty && kcal == nil { return nil }
        guard let base = WorkoutSource.buildManualRow(start: start, durationMin: durationMin,
                                                      sport: sport, avgHr: avgHr, energyKcal: kcal)
        else { return nil }
        // Carry over captured-but-unexposed fields when editing an existing strap session.
        return WorkoutSource.preservingCaptured(base, from: editing)
    }

    private var validationNote: LocalizedStringKey? {
        guard builtRow == nil else { return nil }
        if sport.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a sport." }
        if start > Date() { return "Start can't be in the future." }
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty, avgHr == nil || !(25...250).contains(avgHr ?? -1) {
            return "Average HR must be 25–250 bpm."
        }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty, kcal == nil || (kcal ?? -1) < 0 || (kcal ?? 0) > 20_000 {
            return "Calories must be 0–20,000."
        }
        return "Check the values and try again."
    }

    private func save() {
        guard let row = builtRow else { return }
        onSave(row, editing)
        dismiss()
    }
}

#if DEBUG
#Preview("Add") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ManualWorkoutSheet { _, _ in }
    }
}

#Preview("Edit") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ManualWorkoutSheet(editing: WorkoutRow(
            startTs: Int(Date().timeIntervalSince1970) - 3600, endTs: Int(Date().timeIntervalSince1970),
            sport: "Running", source: "manual", durationS: 3600, energyKcal: 540,
            avgHr: 148, maxHr: 172, strain: 12.4, distanceM: nil, zonesJSON: nil, notes: nil)) { _, _ in }
    }
}
#endif
