import SwiftUI

// MARK: - EntrenarFilaEjercicio — fila de la Biblioteca de ejercicios (FER-289)
//
// La fila rica del catálogo: miniatura 52 con aro de familia · nombre + meta (o aviso) ·
// dato opcional (récord) · afordance trailing (chevron / Agregar·✓ / ninguna). Props ya
// resueltas (sin repo); el caller cablea taps. La miniatura llega por `@ViewBuilder`
// porque `ExerciseThumbView` vive en la app (caché GIF), fuera de CenitDesign.
//
// Afordancia `.agregar`: dos botones HERMANOS (abrir detalle + toggle) — nunca un Button
// anidado — para preservar VoiceOver de FER-121. `onToggle` + `agregarLabel` /
// `a11yAgregar` / `a11yQuitar` llegan ya localizados; la pieza es tonta.

/// Afordancia trailing de la fila de ejercicio en la Biblioteca.
public enum Afordancia: Sendable, Equatable {
    case chevron
    /// Toggle de selección en modo ADD. `seleccionado` pinta ✓; si no, cápsula «Agregar».
    case agregar(seleccionado: Bool)
    case ninguna
}

public struct EntrenarFilaEjercicio<Miniatura: View>: View {
    private let family: EntrenarFamily?
    private let nombre: String
    private let meta: String
    private let dato: (valor: String, rotulo: String)?
    private let afordancia: Afordancia
    private let aviso: String?
    private let divider: Bool
    private let agregarLabel: String
    private let a11yAgregar: String
    private let a11yQuitar: String
    private let action: (() -> Void)?
    private let onToggle: (() -> Void)?
    private let miniatura: () -> Miniatura

    /// - Parameters:
    ///   - family: identidad de movimiento (tiñe el aro y el dato); `nil` → aro `tinta500`.
    ///   - nombre / meta: ya localizados.
    ///   - dato: valor + rótulo del récord (sección «Con historial tuyo»); `nil` = sin columna.
    ///   - afordancia: chevron (BROWSE) · agregar (ADD) · ninguna.
    ///   - aviso: si no-nil, sustituye la meta (p. ej. «Sin músculo · toca para completar»).
    ///   - divider: filete inferior 0.5 pt; `false` en la última fila del grupo.
    ///   - agregarLabel / a11yAgregar / a11yQuitar: copy ya resuelto (solo con `.agregar`).
    ///   - action: abrir detalle. `nil` → el HStack del cuerpo no es Button (el caller
    ///     puede poner `.onTapGesture`); con valor, el cuerpo es un Button real.
    ///   - onToggle: toggle de selección (requerido cuando `afordancia == .agregar`).
    ///   - miniatura: `@ViewBuilder` — el caller inyecta `ExerciseThumbView` (app).
    public init(family: EntrenarFamily?,
                nombre: String,
                meta: String,
                dato: (valor: String, rotulo: String)? = nil,
                afordancia: Afordancia = .chevron,
                aviso: String? = nil,
                divider: Bool = true,
                agregarLabel: String = "",
                a11yAgregar: String = "",
                a11yQuitar: String = "",
                action: (() -> Void)? = nil,
                onToggle: (() -> Void)? = nil,
                @ViewBuilder miniatura: @escaping () -> Miniatura) {
        self.family = family
        self.nombre = nombre
        self.meta = meta
        self.dato = dato
        self.afordancia = afordancia
        self.aviso = aviso
        self.divider = divider
        self.agregarLabel = agregarLabel
        self.a11yAgregar = a11yAgregar
        self.a11yQuitar = a11yQuitar
        self.action = action
        self.onToggle = onToggle
        self.miniatura = miniatura
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let action {
                    Button(action: action) {
                        cuerpo
                    }
                    .buttonStyle(.liquidPress)
                    .accessibilityElement(children: .combine)
                } else {
                    cuerpo
                        .accessibilityElement(children: .combine)
                }
                if case .agregar(let seleccionado) = afordancia {
                    toggleAgregar(seleccionado: seleccionado)
                }
            }
            if divider {
                Rectangle()
                    .fill(LiquidColor.tinta10)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - Cuerpo

    private var cuerpo: some View {
        HStack(spacing: LiquidSpace.s300) {
            miniatura()
                .frame(width: Metrics.thumb, height: Metrics.thumb)
                .overlay(
                    RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: Metrics.thumb),
                                     style: .continuous)
                        .strokeBorder(aroTint, lineWidth: 1.5)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: nombre)
                    .font(LiquidType.tituloGemela)
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let aviso {
                    Text(verbatim: aviso)
                        .font(LiquidType.filaConteo)
                        .foregroundStyle(LiquidColor.atencionTexto)
                        .lineLimit(1)
                } else {
                    Text(verbatim: meta)
                        .font(LiquidType.filaConteo)
                        .foregroundStyle(LiquidColor.tinta500)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: LiquidSpace.s200)

            if let dato {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: dato.valor)
                        .font(LiquidType.valorS)
                        .foregroundStyle(family?.tint() ?? LiquidColor.tinta900)
                    Text(verbatim: dato.rotulo)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                .accessibilityElement(children: .combine)
            }

            if case .chevron = afordancia {
                LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, LiquidSpace.filaRespiro)
        .padding(.horizontal, LiquidSpace.s100)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Toggle ADD (hermano del cuerpo — FER-121)
    //
    // `OutlineCapsule` es un Button; no puede anidarse aquí. El chrome outline se dibuja
    // estático dentro del label (mismos pads sm que OutlineCapsule) para un solo Button real.

    private func toggleAgregar(seleccionado: Bool) -> some View {
        Button {
            onToggle?()
        } label: {
            Group {
                if seleccionado {
                    Image(systemName: "checkmark.circle.fill")
                        .font(LiquidType.iconSF(size: 21))
                        .foregroundStyle(LiquidColor.tinta900)
                } else {
                    // Chrome outline pixel-fiel a OutlineCapsule.sm (pads s250/s150), sin
                    // anidar su Button — el toque lo lleva este Button hermano (FER-121).
                    Text(verbatim: agregarLabel)
                        .font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta900)
                        .padding(.horizontal, LiquidSpace.s250)
                        .padding(.vertical, LiquidSpace.s150)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(LiquidColor.vidrioBordeFuerte, lineWidth: 1)
                        )
                }
            }
            .frame(width: Metrics.toggleWidth, height: LiquidControl.hitTarget)
        }
        .buttonStyle(.liquidPress)
        .contentShape(Rectangle())
        .animation(nil, value: seleccionado)
        .accessibilityLabel(Text(seleccionado ? a11yQuitar : a11yAgregar))
    }

    private var aroTint: Color {
        family?.tint() ?? LiquidColor.tinta500
    }
}

private enum Metrics {
    static let thumb: CGFloat = 52
    static let toggleWidth: CGFloat = 78
}

#if DEBUG
#Preview("EntrenarFilaEjercicio · chevron + dato") {
    EntrenarFilaEjercicio(
        family: .push,
        nombre: "Press banca",
        meta: "Pecho · Barra",
        dato: (valor: "82,5 kg", rotulo: "tu récord"),
        afordancia: .chevron,
        action: {}
    ) {
        RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 52), style: .continuous)
            .fill(LiquidColor.tinta10)
            .frame(width: 52, height: 52)
    }
    .padding(.horizontal, LiquidSpace.s400)
    .background(LiquidColor.fondoGradient)
}

#Preview("EntrenarFilaEjercicio · agregar") {
    EntrenarFilaEjercicio(
        family: .pull,
        nombre: "Jalón al pecho",
        meta: "Dorsales · Polea",
        afordancia: .agregar(seleccionado: false),
        agregarLabel: "Agregar",
        a11yAgregar: "Agregar a la selección",
        a11yQuitar: "Quitar de la selección",
        action: {},
        onToggle: {}
    ) {
        RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 52), style: .continuous)
            .fill(LiquidColor.tinta10)
            .frame(width: 52, height: 52)
    }
    .padding(.horizontal, LiquidSpace.s400)
    .background(LiquidColor.fondoGradient)
}

#Preview("EntrenarFilaEjercicio · agregar seleccionado") {
    EntrenarFilaEjercicio(
        family: .legs,
        nombre: "Sentadilla",
        meta: "Cuádriceps · Barra",
        afordancia: .agregar(seleccionado: true),
        agregarLabel: "Agregar",
        a11yAgregar: "Agregar a la selección",
        a11yQuitar: "Quitar de la selección",
        action: {},
        onToggle: {}
    ) {
        RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 52), style: .continuous)
            .fill(LiquidColor.tinta10)
            .frame(width: 52, height: 52)
    }
    .padding(.horizontal, LiquidSpace.s400)
    .background(LiquidColor.fondoGradient)
}

#Preview("EntrenarFilaEjercicio · aviso") {
    EntrenarFilaEjercicio(
        family: nil,
        nombre: "Svend press",
        meta: "",
        afordancia: .chevron,
        aviso: "Sin músculo · toca para completar",
        action: {}
    ) {
        RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 52), style: .continuous)
            .fill(LiquidColor.tinta10)
            .frame(width: 52, height: 52)
    }
    .padding(.horizontal, LiquidSpace.s400)
    .background(LiquidColor.fondoGradient)
}

#Preview("EntrenarFilaEjercicio · sin family") {
    EntrenarFilaEjercicio(
        family: nil,
        nombre: "Ejercicio propio",
        meta: "Sin equipo",
        afordancia: .ninguna,
        action: nil
    ) {
        RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 52), style: .continuous)
            .fill(LiquidColor.tinta10)
            .frame(width: 52, height: 52)
    }
    .padding(.horizontal, LiquidSpace.s400)
    .background(LiquidColor.fondoGradient)
}
#endif
