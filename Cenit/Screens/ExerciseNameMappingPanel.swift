#if os(iOS)
import SwiftUI
import CenitDesign
import StrandImport
import StrandTraining

/// One free-text exercise name that still needs a catalog decision (FER-333 · E9).
/// `sessionCount` / `setCount` come from CSV history import; plan import leaves them at 0.
struct UnresolvedName: Identifiable, Hashable {
    let name: String
    var sessionCount: Int = 0
    var setCount: Int = 0
    var id: String { name }
}

/// Shared mapping UI for plan import (`WorkoutImportView`) and CSV history import
/// (`StrengthHistoryImportSheet`). Caller owns catalog/create sheets and persists
/// learned aliases on save via `repo.saveLearnedExerciseAlias`.
struct ExerciseNameMappingPanel: View {
    let names: [UnresolvedName]
    let reconciler: WorkoutExerciseReconciler
    @Binding var resolution: [String: Exercise]
    @Binding var omitted: Set<String>
    @Binding var autoMatched: Set<String>
    var onPickCatalog: (String) -> Void
    var onCreateOwn: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            ForEach(Array(names.enumerated()), id: \.element.id) { index, item in
                mappingRow(item)
                if index < names.count - 1 {
                    Rectangle().fill(LiquidColor.vidrioBorde).frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func mappingRow(_ item: UnresolvedName) -> some View {
        let key = WorkoutExerciseReconciler.normalize(item.name)
        let resolved = resolution[key]
        let isOmitted = omitted.contains(key)
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(verbatim: item.name)
                .font(LiquidType.cuerpo)
                .foregroundStyle(isOmitted ? LiquidColor.tinta500 : LiquidColor.tinta900)
            if item.sessionCount > 0 {
                Text("in \(item.sessionCount) sessions")
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
            }

            if isOmitted {
                omittedBlock(item: item, key: key)
            } else if let resolved {
                resolvedBlock(name: item.name, key: key, resolved: resolved)
            } else {
                unresolvedBlock(item: item, key: key)
            }
        }
        .padding(.vertical, LiquidSpace.s300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(for: item, key: key, resolved: resolved, isOmitted: isOmitted))
    }

    private func omittedBlock(item: UnresolvedName, key: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(spacing: LiquidSpace.s200) {
                Text("Ignored").font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    .accessibilityElement(children: .combine)
                Spacer(minLength: LiquidSpace.s200)
                undoLink {
                    omitted.remove(key)
                }
            }
            if item.setCount > 0 {
                Text("Ignoring leaves \(item.setCount) sets out; the session still imports.")
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resolvedBlock(name: String, key: String, resolved: Exercise) -> some View {
        let isAuto = autoMatched.contains(key)
        return VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(spacing: LiquidSpace.s200) {
                HStack(spacing: LiquidSpace.s125) {
                    Image(systemName: isAuto ? "sparkles" : "checkmark.circle.fill")
                        .font(LiquidType.caption)
                        .accessibilityHidden(true)
                    Group {
                        if isAuto {
                            Text("Matched automatically · \(StrengthDisplay.name(resolved))")
                        } else {
                            Text("Matched · \(StrengthDisplay.name(resolved))")
                        }
                    }
                    .font(LiquidType.captionFuerte)
                    .lineLimit(1).minimumScaleFactor(0.85)
                }
                .foregroundStyle(LiquidColor.verdePrimario)
                .padding(.horizontal, LiquidSpace.s225).padding(.vertical, LiquidSpace.s075)
                .background(LiquidColor.verdePrimario.opacity(CenitOpacity.tintFill),
                            in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
                .accessibilityElement(children: .combine)
                Spacer(minLength: LiquidSpace.s200)
                undoLink {
                    resolution[key] = nil
                    autoMatched.remove(key)
                }
            }
            Button { onPickCatalog(name) } label: {
                Text("Change mapping")
                    .font(LiquidType.tituloFilaMedia)
                    .foregroundStyle(LiquidColor.tinta500)
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    private func unresolvedBlock(item: UnresolvedName, key: String) -> some View {
        let suggestions = reconciler.suggestions(for: item.name)
        return VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            if !suggestions.isEmpty {
                Text("Did you mean…")
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                ForEach(suggestions, id: \.id) { s in
                    Button { resolve(item.name, with: s) } label: {
                        HStack(spacing: LiquidSpace.s200) {
                            Image(systemName: "sparkles")
                                .font(LiquidType.caption)
                                .foregroundStyle(LiquidColor.ambar)
                            Text(StrengthDisplay.name(s))
                                .font(LiquidType.cuerpo.weight(.medium))
                                .foregroundStyle(LiquidColor.tinta900)
                            Spacer(minLength: LiquidSpace.s200)
                            Text("Use")
                                .font(LiquidType.tituloFilaNegrita)
                                .foregroundStyle(LiquidColor.papelTarjeta)
                                .padding(.horizontal, LiquidSpace.s250).padding(.vertical, LiquidSpace.s100)
                                .background(LiquidColor.tinta900,
                                            in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
                        }
                        .padding(.horizontal, LiquidSpace.s250).padding(.vertical, LiquidSpace.s200)
                        .liquidGlass(.superficieSolida)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Use \(StrengthDisplay.name(s)) for \(item.name)"))
                }
            }
            HStack(spacing: LiquidSpace.s200) {
                chip("Catalog") { onPickCatalog(item.name) }
                chip("Create own") { onCreateOwn(item.name) }
                chip("Ignore") { omitted.insert(key) }
            }
            if item.setCount > 0 {
                Text("Ignoring leaves \(item.setCount) sets out; the session still imports.")
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func resolve(_ name: String, with exercise: Exercise) {
        let key = WorkoutExerciseReconciler.normalize(name)
        resolution[key] = exercise
        autoMatched.remove(key)
        omitted.remove(key)
    }

    private func undoLink(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Undo")
                .font(LiquidType.tituloFilaMedia)
                .foregroundStyle(LiquidColor.tinta500)
                .underline()
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta700)
                .padding(.horizontal, LiquidSpace.s300).padding(.vertical, LiquidSpace.s150)
                .outlineCapsule(
                    .outline,
                    size: .aMedida(
                        insets: EdgeInsets(top: .zero, leading: .zero,
                                           bottom: .zero, trailing: .zero),
                        minHeight: nil,
                        touchInset: .zero))
        }
        .buttonStyle(.plain)
    }

    private func accessibilityLabel(for item: UnresolvedName, key: String,
                                    resolved: Exercise?, isOmitted: Bool) -> Text {
        if isOmitted {
            return Text("\(item.name), ignored")
        }
        if let resolved {
            return Text("\(item.name), matched to \(StrengthDisplay.name(resolved))")
        }
        let suggestion = reconciler.suggestions(for: item.name).first.map(StrengthDisplay.name)
        if item.sessionCount > 0, let suggestion {
            return Text("\(item.name), in \(item.sessionCount) sessions, unresolved. Suggestion: \(suggestion)")
        }
        if item.sessionCount > 0 {
            return Text("\(item.name), in \(item.sessionCount) sessions, unresolved")
        }
        if let suggestion {
            return Text("\(item.name), unresolved. Suggestion: \(suggestion)")
        }
        return Text("\(item.name), unresolved")
    }
}
#endif
