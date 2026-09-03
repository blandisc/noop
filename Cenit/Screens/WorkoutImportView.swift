#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import CenitDesign
import StrandImport
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// Import an LLM-generated workout program (FER-496) — the «trae-tu-propio-LLM» path, mirroring Diet
/// capture (FER-371). NOOP hands out a prompt, the user runs it in their own AI with their plan, and
/// brings back a `noop.workout.v1` file; importing it creates the real routines of the strength tracker.
/// NOOP never calls the network — the user runs the LLM step.
///
/// «Liquid Glass · El Eje»: there's no measured datum here, so the screen is all-ink on glass; the
/// Confirm step accents each routine with its type's hue (owner decision, Jul 2026), and the rest of
/// the screen remains all-ink — `critical` on a parse error and `verdict` (green) on a just-resolved
/// exercise. The one piece the format can't carry is the catalog identity of each exercise, so unmatched
/// names get a mapping step (map to an existing exercise or create it) before the routines are written.
struct WorkoutImportView: View {

    /// Called after routines are created, so the hub can reload «Mis rutinas».
    var onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var repo: Repository

    fileprivate enum Phase { case capture, mapping, confirm, done }

    /// The unmatched exercise name being mapped (wraps the name so `.sheet(item:)` has an `Identifiable`
    /// without a global `String` conformance). Names are deduped by normalization, so they're unique.
    private struct MappingName: Identifiable { let name: String; var id: String { name } }

    @State private var phase: Phase = .capture
    @State private var pasteText = ""
    @State private var program: WorkoutProgram?
    @State private var parseError: WorkoutProgramParseError?
    @State private var copied = false
    @State private var showFileImporter = false

    // Exercise reconciliation: the on-device catalog (seed + custom), the unmatched names that need a
    // decision, and the user's resolution per normalized name (an existing or just-created exercise).
    @State private var catalog: [Exercise] = []
    @State private var learnedAliases: [String: String] = [:]   // remembered mappings (FER-523)
    @State private var reconciler: WorkoutExerciseReconciler?   // built once at parse, reused at save
    @State private var unmatched: [String] = []
    @State private var resolution: [String: Exercise] = [:]
    @State private var autoMatched: Set<String> = []   // resolved by autoMatch (FER-794) — marked, reversible
    @State private var omitted: Set<String> = []   // normalized names the user chose not to import (FER-536)
    @State private var mappingTarget: MappingName?  // name being mapped → drives the library picker sheet
    @State private var creationTarget: MappingName? // name being created → drives the create-exercise sheet (FER-995)
    @State private var createdCount = 0
    @State private var celebrate = false   // done-screen pop-in (respects Reduce Motion)
    /// Ola 1 · E11: cuando el archivo trae `semanas`, el toggle de confirmación decide si además de
    /// las rutinas se instala el programa (calendario + fila `program`). Encendido por default — el
    /// archivo lo pidió; apagarlo importa SOLO las rutinas, como hacía la app antes de E11.
    @State private var installAsProgram = true
    /// M4 (decisión Fer): cerrar con el mapeo/confirmación a medias pide confirmación — antes el
    /// swipe-down tiraba todo el trabajo sin avisar.
    @State private var confirmDiscard = false
    /// FER-969: write failure after confirm — banner, stay on confirm (don't fake .done).
    @State private var saveError = false
    private var midWork: Bool { phase == .mapping || phase == .confirm }

    /// The user's weight unit (kg / lb), for the confirm-step preview only — stored weights are kg.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private let importer = WorkoutProgramImporter()

    var body: some View {
        ScrollView {
            Group {
                switch phase {
                case .capture: captureFlow
                case .mapping: mappingFlow
                case .confirm: if let p = program { confirmFlow(p) }
                case .done:    doneFlow
                }
            }
            .padding(LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-200 (Anillo 2, épico FER-195): fondo de vidrio El Eje — sin `NavigationStack` propio
        // en la raíz. Captura/confirmación visten `EntrenarHojaCabecera(.cerrar)`; mapeo/hecho
        // CONSERVAN el ✕ overlay (el stepper ya le cede el carril de 44 pt) — unificarlos en la
        // cabecera AÑADIRÍA título ahí o quitaría el carril del stepper (REGLA SUPREMA).
        .entrenarHojaFondo(tono: .neutro)
        // FER-969 / FER-280·2c: save failure → `.saveErrorToast`. Parse errors keep
        // their existing `errorNote` path in capture; this is only the final write.
        .saveErrorToast(isPresented: $saveError)
        // FER-138 / FER-200: captura y confirmación llevan `EntrenarHojaCabecera`; este ✕ se queda
        // solo para mapeo y hecho (el stepper le cede el carril de 44 pt).
        .overlay(alignment: .topTrailing) {
            // FER-200: mapeo/hecho conservan el ✕ flotante (mismo `BackButton(.close)` = salida
            // `.cerrar` de la familia) — no se unifica a `EntrenarHojaCabecera` aquí (ver nota
            // en `.entrenarHojaFondo` arriba).
            if phase == .mapping || phase == .done {
                BackButton(role: .close, action: dismissImport)
                    .padding(.trailing, LiquidSpace.s200).padding(.top, LiquidSpace.s200)
            }
        }
        .interactiveDismissDisabled(midWork)
        // El gesto repite el guard del botón: a medias pregunta, nunca descarta el mapeo en silencio.
        .edgeSwipeToExit(dismissImport)
        .liquidConfirm(
            isPresented: $confirmDiscard,
            title: String(localized: "Discard this import?"),
            context: String(localized: "IMPORT · IN PROGRESS"),
            message: String(localized: "The mapping you've done so far won't be saved."),
            actions: [
                .init(String(localized: "Keep importing"), role: .primary),
                .init(String(localized: "Discard import"), role: .destructive) { dismiss() }
            ]
        )
        .task {
            if catalog.isEmpty {
                catalog = await repo.allExercises()
                learnedAliases = await repo.learnedExerciseAliases()   // FER-523: remembered mappings
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { handleImport($0) }
        .sheet(item: $mappingTarget) { target in
            NavigationStack {
                ExerciseLibraryScreen { picks in
                    if let chosen = picks.first { resolve(target.name, with: chosen) }
                }
            }
        }
        // FER-995: «create new» opens the library's own create form, pre-filled with the plan's name,
        // the type it declared and a muscle proposed from the name — instead of silently saving an
        // exercise with no muscle, which is invisible to the muscle map, the volume and the classifier.
        .sheet(item: $creationTarget) { target in
            CreateExerciseSheet(catalog: catalog, initialName: target.name,
                                initialType: declaredType(target.name)) { exercise in
                createNew(target.name, as: exercise)
            }
        }
        .enableInjection()
    }

    // MARK: - Capture

    /// FER-138: la piel de dos fases del handoff — «‹» + kicker propio en vez del stepper de 4 pasos
    /// (ese sigue vivo en `mappingFlow`, sin tocar). PASO 1 muestra el prompt REAL que se copia (no un
    /// resumen inventado, truncado a 4 líneas); PASO 2 es la zona punteada de pegar + «Abrir archivo».
    /// La lógica sigue intacta: `parse`/`copyPrompt`/`handleImport` no cambian, solo quién los llama.
    private var captureFlow: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            // FER-200: `EntrenarHojaCabecera(.cerrar)` absorbe `importHeader` + el héroe — mismas
            // cadenas, misma salida (`dismiss` / `confirmDiscard` si hubiera trabajo a medias).
            EntrenarHojaCabecera(
                titulo: String(localized: "Your plan, from your AI"),
                subtitulo: String(localized: "Import plan · bring your own AI"),
                tono: .neutro, salida: .cerrar, onSalir: dismissImport)
            Text("Cénit never calls the network. Copy the prompt, run it in your AI with your plan, and paste the result here.")
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                HStack(alignment: .center, spacing: LiquidSpace.s200) {
                    Text("STEP 1 · THE PROMPT").entrenarCabeceraKicker().foregroundStyle(LiquidColor.tinta500)
                    Spacer(minLength: LiquidSpace.s200)
                    QuietButton(copied ? "✓ Copied" : "Copy") { copyPrompt() }
                }
                .frame(minHeight: EntrenarMetrics.row)
                // El prototipo dibuja la caja a 10.5; aquí va `Font.system(.footnote, design: .monospaced)` (footnote, ~13,
                // escalable): un bloque de texto que el usuario debe LEER y copiar no baja de la
                // talla mínima legible ni se clava fuera de Dynamic Type. Desviación consciente.
                Text(verbatim: WorkoutPrompt.forCurrentLocale())
                    .font(Font.system(.footnote, design: .monospaced)).foregroundStyle(LiquidColor.tinta700)
                    .lineLimit(4)
                    .padding(LiquidSpace.s400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(.superficieSolida)
            }

            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                Text("STEP 2 · BRING THE RESULT").entrenarCabeceraKicker().foregroundStyle(LiquidColor.tinta500)
                    .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
                dashedPasteField
                HStack(spacing: LiquidSpace.s300) {
                    openFileLink
                    Spacer(minLength: LiquidSpace.s200)
                    // Deviation from the prototype's tap-to-paste demo: parsing needs an explicit
                    // trigger (a real paste can be partial/edited before it's valid JSON), so a
                    // «Continue» stays, only once there's something to parse.
                    if !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        QuietButton("Continue") { parse(text: pasteText) }
                    }
                }
                if let parseError { errorNote(parseError) }
            }

            Text("Exercises that don't match the catalog go through a mapping step (pick an equivalent or create it) before anything is written.")
                .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Salida compartida de captura/confirmación (y del ✕ de mapeo/hecho): a medias pregunta,
    /// nunca tira el mapeo en silencio — misma lógica que el `importHeader` previo a FER-200.
    private func dismissImport() {
        if midWork { confirmDiscard = true } else { dismiss() }
    }

    /// Zona punteada de PASO 2: `LiquidCampoTexto` multilínea (FER-342) + marco a rayas del handoff.
    private var dashedPasteField: some View {
        LiquidCampoTexto(
            nil,
            texto: $pasteText,
            placeholder: String(localized: "Paste the JSON"),
            a11y: String(localized: "Paste your plan"),
            eje: .vertical,
            tipografia: Font.system(.footnote, design: .monospaced)
        )
        .frame(minHeight: 96)
        .overlay(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous)
            .strokeBorder(LiquidColor.vidrioBordeFuerte, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var openFileLink: some View {
        Button { showFileImporter = true } label: {
            HStack(spacing: LiquidSpace.s150) {
                Text("Open file").font(LiquidType.cuerpo.weight(.medium)).foregroundStyle(LiquidColor.tinta700)
                CenitIcon.disclosure.image
                    .font(LiquidType.iconSF(size: 12).weight(.semibold)).foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: LiquidControl.hitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func errorNote(_ error: WorkoutProgramParseError) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s300) {
            Image(systemName: "exclamationmark.triangle")
                .font(LiquidType.iconSF(size: 15)).foregroundStyle(LiquidColor.negativo)
                .accessibilityHidden(true)
            Text(message(for: error))
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mapping (the names that aren't in the catalog yet)

    private var mappingFlow: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            stepper(current: .mapping)
            header("Import plan", "\(unmatched.count) exercises to set up")
            Text("These aren't in your library. Match each one to an exercise you have, or create it.")
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)

            // FER-333 · E9: componente compartido con la importación de historial CSV — misma
            // interacción de mapeo, mismo copy («Ignore»/«Catalog»/«Create own»), un solo oráculo.
            if let reconciler {
                ExerciseNameMappingPanel(
                    names: unmatched.map { UnresolvedName(name: $0) },
                    reconciler: reconciler,
                    resolution: $resolution,
                    omitted: $omitted,
                    autoMatched: $autoMatched,
                    onPickCatalog: { mappingTarget = MappingName(name: $0) },
                    onCreateOwn: { creationTarget = MappingName(name: $0) })
            }

            // A name is "settled" once it's matched OR omitted — both let you continue.
            let remaining = unmatched.filter { resolution[norm($0)] == nil && !omitted.contains(norm($0)) }.count
            QuietButton(remaining == 0 ? "Continue" : "Resolve \(remaining) more to continue") {
                phase = .confirm
            }
            .disabled(remaining != 0)
        }
    }

    // MARK: - Confirm

    /// FER-138 / FER-200: misma cabecera de familia que `captureFlow` (`EntrenarHojaCabecera`),
    /// título fijo «Se leyó bien» (ya no repite el nombre del plan — vive en la fila de cada rutina)
    /// y el resumen con singular/plural correcto (`confirmSummary`). El chevron de «Corregir»
    /// vuelve a `.mapping`: es el paso donde SÍ se corrigen mapeos, aunque el prototipo lo dibuje
    /// volviendo a la captura.
    private func confirmFlow(_ program: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            // FER-200: misma cabecera de familia que captura — título/resumen ya localizados;
            // salida `.cerrar` con el guard de `confirmDiscard` (fase confirm = midWork).
            EntrenarHojaCabecera(
                titulo: String(localized: "It read well"),
                subtitulo: confirmSummary(program),
                tono: .neutro, salida: .cerrar, onSalir: dismissImport)

            VStack(alignment: .leading, spacing: .zero) {
                // Ronda 2 (menor): el kicker es UNA sola cadena con el separador «·», como pide el
                // spec — antes vivía partido en dos `Text` (nombre + metadato a la derecha).
                // `.textCase(.uppercase)` de `liquidKicker()` gritaría también el sufijo
                // (`NOOP.WORKOUT.V1`), así que solo «Rutinas leídas» se sube a mayúsculas a mano —
                // el identificador de formato se queda tal cual.
                Text(verbatim: String(localized: "Routines read").uppercased() + " · noop.workout.v1")
                    .font(LiquidType.kicker).tracking(LiquidType.kickerTracking)
                    .foregroundStyle(LiquidColor.tinta500)
                    .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
                ForEach(Array(program.routines.enumerated()), id: \.offset) { index, routine in
                    routinePreview(routine)
                    if index < program.routines.count - 1 {
                        Rectangle().fill(LiquidColor.vidrioBorde).frame(height: 0.5)
                    }
                }
            }

            if program.weeks != nil {
                programToggleSection(program)
            }

            HStack(spacing: LiquidSpace.s300) {
                Spacer(minLength: 0)
                fixLink
                CenitCTAButton(createRoutinesTitle(program.routines.count), tint: LiquidColor.verdeProfundo, fillsWidth: false) {
                    save(program)
                }
            }
        }
    }

    /// Ola 1 · E11: el archivo trajo `semanas` — el toggle decide si además de las rutinas se instala
    /// el programa (calendario + fila `program`); apagado, `save()` solo crea las rutinas, como hacía
    /// la app antes de esta ola. El aviso de `weeksDiffer` vive aquí, no en la lista de rutinas: es
    /// sobre el PLAN completo, no sobre una rutina en particular.
    private func programToggleSection(_ program: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Toggle(isOn: $installAsProgram) {
                VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                    Text(programToggleTitle(program))
                        .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    if let subtitle = programToggleSubtitle(program) {
                        Text(subtitle).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                    }
                }
            }
            .tint(LiquidColor.verdePrimario)
            .frame(minHeight: EntrenarMetrics.row)

            if program.warnings.contains(.weeksDiffer) {
                Text("This plan changes between weeks; Cénit will use week 1 for all of them and the last as the light week.")
                    .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func programToggleTitle(_ program: WorkoutProgram) -> String {
        String(localized: "Turn it into a \(program.weeks ?? Program.appWeeks.lowerBound)-week program")
    }

    private func programToggleSubtitle(_ program: WorkoutProgram) -> String? {
        guard program.deloadRule != .none, let weeks = program.weeks else { return nil }
        return String(localized: "light week in week \(weeks)")
    }

    private var fixLink: some View {
        Button { phase = .mapping } label: {
            HStack(spacing: LiquidSpace.s150) {
                Text("Fix").font(LiquidType.cuerpo.weight(.medium)).foregroundStyle(LiquidColor.tinta700)
                CenitIcon.disclosure.image
                    .font(LiquidType.iconSF(size: 12).weight(.semibold)).foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: LiquidControl.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// «N rutinas · M ejercicios · K por mapear (ya resuelto/s)» — cada tramo con su propio singular
    /// correcto (el catálogo NO pluraliza «rutinas»/«ejercicios» dentro de una cadena combinada, así
    /// que se arman por separado, igual que `CrearPlanScreen.routineCountText`).
    private func confirmSummary(_ p: WorkoutProgram) -> String {
        let exercises = p.routines.reduce(0) { $0 + $1.exercises.filter { !omitted.contains(norm($0.name)) }.count }
        let routineWord = p.routines.count == 1 ? String(localized: "1 routine") : String(localized: "\(p.routines.count) routines")
        let exerciseWord = exercises == 1 ? String(localized: "1 exercise") : String(localized: "\(exercises) exercises")
        var parts = [routineWord, exerciseWord]
        let mapped = unmatched.filter { !omitted.contains(norm($0)) }.count   // resolved AND kept (FER-536)
        if mapped > 0 {
            parts.append(mapped == 1 ? String(localized: "1 to map (already resolved)")
                                      : String(localized: "\(mapped) to map (already resolved)"))
        }
        return parts.joined(separator: " · ")
    }

    /// Row 52pt: nombre en el tinte de `RoutineClassifier` + el detalle por ejercicio de siempre
    /// (sets/reps/kg) como «desc» — más útil que el resumen terso del prototipo, y el mismo dato que
    /// `save()` va a escribir. El chip verde solo aparece si esta rutina trajo algún ejercicio que
    /// necesitó mapeo (FER-138).
    private func routinePreview(_ routine: WorkoutRoutine) -> some View {
        // Resolver con la misma precedencia que save(): reconciliador (matches directos/aliases) y
        // luego las decisiones manuales — si no, las rutinas con puros matches directos no clasifican.
        let muscles = routine.exercises.compactMap { ex in
            (reconciler?.resolve(ex) ?? resolution[norm(ex.name)])?.primaryMuscles
        }
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: muscles)
        let accent = region.tint()
        let mapped = mappedCount(routine)
        return HStack(alignment: .top, spacing: LiquidSpace.s300) {
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    nameText(routine.name, fallback: "Routine")
                        .font(LiquidType.cuerpo.weight(.semibold)).foregroundStyle(accent)
                    if let tag = routine.tag {
                        Text(verbatim: "· \(tag)").font(LiquidType.caption).foregroundStyle(accent)
                    }
                }
                ForEach(Array(routine.exercises.enumerated()), id: \.offset) { _, ex in
                    if !omitted.contains(norm(ex.name)) {   // omitted exercises aren't imported (FER-536)
                        Text(verbatim: exerciseLine(ex))
                            .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: LiquidSpace.s200)
            if mapped > 0 {
                Text(mapped == 1 ? "1 mapped" : "\(mapped) mapped")
                    .font(LiquidType.captionFuerte).foregroundStyle(LiquidColor.verdePrimario)
                    .padding(.horizontal, LiquidSpace.s225).padding(.vertical, LiquidSpace.s075)  // chip handoff 9/3 → s225/s075
                    .background(LiquidColor.verdePrimario.opacity(CenitOpacity.tintFill),
                                in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
            }
        }
        .frame(minHeight: 52, alignment: .top)
        .padding(.vertical, LiquidSpace.s300)
    }

    /// How many of this routine's exercises needed a mapping decision (were in `unmatched`) and are
    /// still in — omitted ones don't count as «mapeados» (FER-536: they aren't imported at all).
    private func mappedCount(_ routine: WorkoutRoutine) -> Int {
        let unmatchedKeys = Set(unmatched.map(norm))
        return routine.exercises.filter { ex in
            let key = norm(ex.name)
            return unmatchedKeys.contains(key) && !omitted.contains(key) && resolution[key] != nil
        }.count
    }

    // MARK: - Done

    /// Handoff: el cierre celebratorio — a diferencia de los pasos de trabajo, aquí el contenido se
    /// centra y respira. Un solo color (verdict verde), un solo gesto (el sello aparece con un pop
    /// suave). Sin confeti: la celebración a la «Liquid Glass» es espacio + un verde honesto.
    private var doneFlow: some View {
        VStack(spacing: .zero) {
            stepper(current: .done)
            Spacer(minLength: LiquidSpace.s700)

            VStack(spacing: LiquidSpace.s700) {
                ZStack {
                    Circle().fill(LiquidColor.verdePrimario.opacity(CenitOpacity.tintFill)).frame(width: 116, height: 116)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .semibold)).foregroundStyle(LiquidColor.verdePrimario)  // token-exempt(falta-pieza): glifo héroe del cierre (44pt, pareado al círculo de 116)
                }
                .scaleEffect(celebrate ? 1 : 0.72)
                .opacity(celebrate ? 1 : 0)
                .accessibilityHidden(true)

                VStack(spacing: LiquidSpace.s200) {
                    Text(createdRoutinesTitle(createdCount))
                        .font(LiquidType.displayS).tracking(LiquidType.displaySTracking).foregroundStyle(LiquidColor.tinta900)
                        .multilineTextAlignment(.center)
                    Text("They're in «My routines», ready to train.")
                        .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(celebrate ? 1 : 0)
            }

            Spacer(minLength: LiquidSpace.s700)
            CenitCTAButton("Done") { Task { await onComplete(); dismiss() } }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
        .onAppear {
            guard !celebrate else { return }
            if reduceMotion { celebrate = true }
            else { withAnimation(LiquidMotion.heroe.delay(0.05)) { celebrate = true } }
        }
    }

    // MARK: - Shared pieces

    /// 4-step progress strip: Capture → Map → Confirm → Done. Current + past steps use the strain/ember
    /// accent; future steps stay hairline. Labels dim except the active step.
    private func stepper(current: Phase) -> some View {
        let labels: [LocalizedStringKey] = ["Capture", "Map", "Confirm", "Done"]
        let currentIndex = phaseIndex(current)
        // El ✕ flota arriba-derecha (44pt): la tira le cede su carril para no chocar (bug Fer 2026-07-16).
        return VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(spacing: LiquidSpace.s200) {
                ForEach(0..<labels.count, id: \.self) { i in
                    let tono = i <= currentIndex ? LiquidColor.ambar : LiquidColor.vidrioBorde
                    LiquidBarraProgreso(fraccion: 1, tono: tono, pista: tono,
                                        altura: LiquidSpace.s075, animada: false)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, LiquidSpace.handoff44)
            HStack(spacing: LiquidSpace.s200) {
                ForEach(0..<labels.count, id: \.self) { i in
                    Text(labels[i])
                        .font(LiquidType.tituloFilaMedia)
                        .foregroundStyle(i == currentIndex ? LiquidColor.tinta900 : LiquidColor.tinta500)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            // El MISMO carril cedido que las barras: sin este padding las etiquetas se reparten el ancho
            // completo y las barras `ancho − 44`, así que cada etiqueta se centraba en una celda más ancha
            // que su barra y el desfase crecía hacia la derecha.
            .padding(.trailing, LiquidSpace.handoff44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(currentIndex + 1) of 4"))
    }

    private func phaseIndex(_ phase: Phase) -> Int {
        switch phase {
        case .capture: return 0
        case .mapping: return 1
        case .confirm: return 2
        case .done:    return 3
        }
    }

    private func header(_ overline: LocalizedStringKey, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(overline).liquidKicker().foregroundStyle(LiquidColor.tinta500)
            Text(title).font(LiquidType.displayS).tracking(LiquidType.displaySTracking).foregroundStyle(LiquidColor.tinta900)
        }
    }

    /// Verbatim user content (program/routine names are the plan's words) with a localized fallback.
    private func nameText(_ value: String, fallback: LocalizedStringKey) -> Text {
        value.isEmpty ? Text(fallback) : Text(verbatim: value)
    }

    // MARK: - Reconciliation helpers

    private func norm(_ name: String) -> String { WorkoutExerciseReconciler.normalize(name) }

    /// The program's declared type for a name (first occurrence) — so a created exercise keeps it.
    private func declaredType(_ name: String) -> ExerciseType {
        let key = norm(name)
        for routine in program?.routines ?? [] {
            for ex in routine.exercises where norm(ex.name) == key { return ex.type }
        }
        return .weightReps
    }

    private func resolve(_ name: String, with exercise: Exercise) {
        let key = norm(name)
        resolution[key] = exercise
        autoMatched.remove(key)    // a user pick is no longer "automatic" (FER-794)
        omitted.remove(key)        // resolving overrides a prior omit
        mappingTarget = nil
        // The learned alias is persisted at save() (FER-536), not here, so Undo can revert cleanly.
    }

    /// «Create new»: persist the exercise the user just completed in the create sheet and resolve the
    /// plan's name to it. The sheet requires a primary muscle, so this can no longer produce an exercise
    /// that's invisible to the muscle map, the weekly volume and `RoutineClassifier` (FER-995). The
    /// learned alias for the import name is persisted at save(), not here (FER-536).
    private func createNew(_ name: String, as exercise: Exercise) {
        Task {
            do {
                try await repo.saveCustomExercise(exercise)
                catalog.append(exercise)   // keep the local catalog current without a full re-fetch
                resolution[norm(name)] = exercise
            } catch {
                // FER-969 (QA D3): a failed save must not enter the local catalog/resolution — the
                // final routine write would reference an exercise that doesn't exist in the store.
                saveError = true
            }
        }
    }

    // MARK: - Actions

    private func copyPrompt() {
        PlatformPasteboard.copy(WorkoutPrompt.forCurrentLocale())
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { copied = false }
        }
    }

    private func parse(text: String) { parse(data: Data(text.utf8)) }

    private func parse(data: Data) {
        do {
            let p = try importer.parse(data)
            program = p
            parseError = nil
            installAsProgram = true
            let r = WorkoutExerciseReconciler(known: catalog, learned: learnedAliases,
                                              aliases: ExerciseAliasTable.bundled)
            reconciler = r
            unmatched = r.unmatchedNames(in: p)
            resolution = [:]
            autoMatched = []
            // FER-794: pre-resolve what autoMatch can (content-key / derived alias / confident fuzzy)
            // and MARK it — the mapping step still shows it, reversible, before anything is imported.
            for (name, hit) in r.autoMatches(in: p) {
                let key = norm(name)
                resolution[key] = hit
                autoMatched.insert(key)
            }
            phase = unmatched.isEmpty ? .confirm : .mapping
        } catch let error as WorkoutProgramParseError {
            parseError = error
        } catch {
            parseError = .notJSON
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { parseError = .notJSON; return }
        parse(data: data)
    }

    /// Resolve every exercise to a catalog id (matched or user-resolved) and write one `Routine` per
    /// program routine, in order. Idempotent ids are fresh UUIDs — re-importing makes new routines.
    private func save(_ program: WorkoutProgram) {
        let reconciler = self.reconciler
            ?? WorkoutExerciseReconciler(known: catalog, aliases: ExerciseAliasTable.bundled)
        let now = Int(Date().timeIntervalSince1970)
        let omittedSnapshot = omitted
        let resolutionSnapshot = resolution
        let installProgramSnapshot = installAsProgram
        Task {
            var created = 0
            // Ola 1 · E11: id de rutina creada por índice del plan — la entrada que
            // `assignedWeekdays()` necesita para agendar SOLO las rutinas que de verdad se escribieron
            // (una rutina sin ejercicios resueltos se salta arriba y no debe reclamar un día).
            var createdRoutineIds: [Int: String] = [:]
            for (rIndex, routine) in program.routines.enumerated() {
                let routineId = UUID().uuidString
                var slots: [RoutineExercise] = []
                for ex in routine.exercises {
                    let key = norm(ex.name)
                    if omittedSnapshot.contains(key) { continue }   // omitted → not imported (FER-536)
                    guard let exercise = reconciler.resolve(ex) ?? resolutionSnapshot[key] else { continue }
                    let hasRest = ex.restSeconds != nil
                    slots.append(RoutineExercise(
                        routineId: routineId, exerciseId: exercise.id, position: slots.count,
                        targetSets: ex.sets, targetReps: ex.reps, targetWeightKg: ex.weightKg,
                        warmupPercents: ex.warmupPercents,
                        restMode: hasRest ? .fixed : .heartRate, restSeconds: ex.restSeconds ?? 90,
                        supersetGroup: ex.supersetGroup))
                }
                guard !slots.isEmpty else { continue }
                let r = Routine(id: routineId,
                                name: routine.name.isEmpty ? String(localized: "Routine") : routine.name,
                                tag: routine.tag, createdTs: now, updatedTs: now, sortOrder: rIndex)
                do {
                    try await repo.saveRoutine(r, exercises: slots)
                    created += 1
                    createdRoutineIds[rIndex] = routineId
                } catch {
                    // Stay on confirm; don't advance to .done or learn aliases for a half-write.
                    saveError = true
                    return
                }
            }
            // Remember the confirmed mappings only now (FER-536) — so Undo before saving leaves no learned
            // alias behind. Omitted names are never remembered. Routines already landed; a failed alias
            // still advances to .done but surfaces the toast so the user knows the memory didn't stick.
            for (key, ex) in resolutionSnapshot where !omittedSnapshot.contains(key) {
                do {
                    try await repo.saveLearnedExerciseAlias(name: key, exerciseId: ex.id)
                } catch {
                    saveError = true
                }
            }
            // Ola 1 · E11 (FER-334, fix QA D1): agenda el calendario y arma el programa SOLO cuando
            // el usuario de verdad pidió instalar un programa — el mismo gate `installProgramSnapshot`
            // que ya protegía la fila `program`. Antes de este fix, `assignedWeekdays()` se llamaba
            // SIEMPRE que hubiera rutinas creadas: un archivo `noop.workout.v1` viejo (sin `semanas` ni
            // `dia`) o el toggle apagado auto-asignaban días LIBRES a rutinas sin `dia` y pisaban el
            // calendario semanal del usuario — un import nunca tocaba `routineSchedule` antes de esta
            // ola. Con el toggle apagado o un archivo sin `semanas`, `save()` solo crea las rutinas,
            // como siempre hizo. Best-effort (`try?`, como `applyTemplateGroup`): un día sin agendar o
            // un programa que no cuajó no deben tirar las rutinas que SÍ se guardaron.
            if !createdRoutineIds.isEmpty, let weeks = program.weeks, installProgramSnapshot,
               let store = await repo.storeHandle() {
                let weekdays = program.assignedWeekdays()
                for (rIndex, routineId) in createdRoutineIds {
                    guard rIndex < weekdays.count, let weekday = weekdays[rIndex] else { continue }
                    try? await store.setRoutineSchedule(weekday: weekday, routineId: routineId)
                }
                let p = Program(name: program.name.isEmpty ? String(localized: "Program") : program.name,
                                weeks: weeks, startTs: now, deloadRule: program.deloadRule,
                                endMode: program.endMode, createdTs: now)
                try? await store.setProgram(p)
            }
            createdCount = created
            phase = .done
        }
    }

    // MARK: - Display

    private func exerciseLine(_ ex: WorkoutExercise) -> String {
        var parts = [ex.name]
        switch ex.type {
        case .weightReps, .bodyweight:
            if let reps = ex.reps { parts.append("\(ex.sets)×\(reps)") } else { parts.append("\(ex.sets)×") }
            if let kg = ex.weightKg { parts.append(StrengthDisplay.weight(kg, system: unitSystem)) }
            else if ex.type == .bodyweight { parts.append(String(localized: "bodyweight")) }
        case .time:
            parts.append("\(ex.sets)×")
            if let reps = ex.reps { parts.append("\(reps) s") }
        case .distance:
            parts.append("\(ex.sets)×")
        }
        return parts.joined(separator: " · ")
    }

    private func createRoutinesTitle(_ n: Int) -> LocalizedStringKey { "Create \(n) routines" }
    private func createdRoutinesTitle(_ n: Int) -> LocalizedStringKey { "Created \(n) routines" }

    // MARK: - Error copy (es-MX via the String Catalog)

    private func message(for error: WorkoutProgramParseError) -> LocalizedStringKey {
        switch error {
        case .notJSON:
            return "We couldn't read that as a plan file. Paste the full result your AI gave you, or upload the .json."
        case .unsupportedSchema:
            return "That file isn't a Cénit workout plan. Make sure you used the prompt above."
        case .unsupportedIdioma:
            return "The plan's language isn't supported: it must be Spanish or English."
        case .unsupportedUnidad:
            return "The plan's unit isn't supported: it must be kg or lb."
        case .unsupportedTipo:
            return "One of the exercises has an unsupported type. Check the file and try again."
        case .noRoutines:
            return "That plan has no routines. Check the file and try again."
        case .routineWithoutExercises:
            return "One of the routines has no exercises. Check the file and try again."
        case .exerciseWithoutName:
            return "One of the exercises has no name. Check the file and try again."
        // Ola 1 · E10 (FER-329): programa de varias semanas. Copy mínimo para que el archivo se
        // rechace con razón; la pantalla del programa y el prompt actualizado llegan con E11.
        case .unsupportedSemanas:
            return "The plan's number of weeks isn't supported: it must be between 4 and 8."
        case .unsupportedSemanaLigera:
            return "The plan's light-week option isn't supported. Check the file and try again."
        case .unsupportedAlTerminar:
            return "The plan's end-of-cycle option isn't supported. Check the file and try again."
        }
    }
}

// MARK: - Previews (FER-946 — canvas del rediseño; datos espejo del handoff «Importar Plan»)

#if DEBUG
extension WorkoutImportView {

    /// Canvas-only: freeze the view at a phase with seeded state, so each step renders without
    /// driving the real flow. The live path (init(onComplete:)) is untouched.
    fileprivate init(previewPhase: Phase,
                     program: WorkoutProgram?,
                     pasteText: String = "",
                     unmatched: [String] = [],
                     resolution: [String: Exercise] = [:],
                     autoMatched: Set<String> = [],
                     omitted: Set<String> = [],
                     createdCount: Int = 0) {
        self.onComplete = {}
        _phase = State(initialValue: previewPhase)
        _program = State(initialValue: program)
        _pasteText = State(initialValue: pasteText)
        _catalog = State(initialValue: ExerciseCatalog.all)
        _reconciler = State(initialValue: WorkoutExerciseReconciler(
            known: ExerciseCatalog.all, aliases: ExerciseAliasTable.bundled))
        _unmatched = State(initialValue: unmatched)
        _resolution = State(initialValue: resolution)
        _autoMatched = State(initialValue: autoMatched)
        _omitted = State(initialValue: omitted)
        _createdCount = State(initialValue: createdCount)
    }

    /// El plan del handoff: «Bloque de fuerza 5×5» — Empuje A · Tirón A · Pierna.
    fileprivate static let previewProgram = WorkoutProgram(
        language: .es, name: "Bloque de fuerza 5×5", routines: [
            WorkoutRoutine(name: "Empuje A", tag: "Lun", exercises: [
                WorkoutExercise(name: "Press banca con barra", sets: 4, reps: 6, weightKg: 82.5),
                WorkoutExercise(name: "Press militar con barra", sets: 4, reps: 8, weightKg: 45),
                WorkoutExercise(name: "Contractor de pecho (máquina)", sets: 3, reps: 12),
                WorkoutExercise(name: "Elevaciones laterales", sets: 3, reps: 15, weightKg: 10),
            ]),
            WorkoutRoutine(name: "Tirón A", tag: "Mié", exercises: [
                WorkoutExercise(name: "Peso muerto", sets: 3, reps: 5, weightKg: 120),
                WorkoutExercise(name: "Remo con barra", sets: 4, reps: 8, weightKg: 70),
                WorkoutExercise(name: "Jalón al pecho", sets: 3, reps: 10, weightKg: 60),
                WorkoutExercise(name: "Curl con barra", sets: 3, reps: 12, weightKg: 30),
            ]),
            WorkoutRoutine(name: "Pierna", tag: "Vie", exercises: [
                WorkoutExercise(name: "Sentadilla con barra", sets: 4, reps: 6, weightKg: 100),
                WorkoutExercise(name: "Prensa", sets: 3, reps: 10, weightKg: 180),
                WorkoutExercise(name: "Curl femoral", sets: 3, reps: 12, weightKg: 40),
                WorkoutExercise(name: "Gemelos de pie", sets: 4, reps: 15, weightKg: 80),
            ]),
        ])

    fileprivate static func previewCapture() -> WorkoutImportView {
        WorkoutImportView(previewPhase: .capture, program: nil)
    }

    /// Mapping con los tres estados del handoff: auto-match ✦, sin match (sugerencia + chips), omitido.
    fileprivate static func previewMapping() -> WorkoutImportView {
        let r = WorkoutExerciseReconciler(known: ExerciseCatalog.all, aliases: ExerciseAliasTable.bundled)
        var resolution: [String: Exercise] = [:]
        var auto: Set<String> = []
        let autoName = "Press de banca plano"
        if let hit = r.suggestions(for: autoName).first {
            let key = WorkoutExerciseReconciler.normalize(autoName)
            resolution[key] = hit
            auto.insert(key)
        }
        return WorkoutImportView(
            previewPhase: .mapping, program: previewProgram,
            unmatched: [autoName, "Aperturas en pec-deck", "Cardio 20 min · caminadora"],
            resolution: resolution, autoMatched: auto,
            omitted: [WorkoutExerciseReconciler.normalize("Cardio 20 min · caminadora")])
    }

    fileprivate static func previewConfirm() -> WorkoutImportView {
        WorkoutImportView(previewPhase: .confirm, program: previewProgram)
    }

    fileprivate static func previewDone() -> WorkoutImportView {
        WorkoutImportView(previewPhase: .done, program: previewProgram, createdCount: 3)
    }
}

@MainActor
private func importPreview(_ view: WorkoutImportView) -> some View {
    view
        .environmentObject(Repository(deviceId: "preview"))
        .environment(\.locale, Locale(identifier: "es"))   // canvas en es-MX; quitar para ver el copy en inglés
}

#Preview("1 · Captura") { importPreview(.previewCapture()) }
#Preview("2 · Mapear") { importPreview(.previewMapping()) }
#Preview("3 · Confirmar") { importPreview(.previewConfirm()) }
#Preview("4 · Listo") { importPreview(.previewDone()) }
#endif
#endif
