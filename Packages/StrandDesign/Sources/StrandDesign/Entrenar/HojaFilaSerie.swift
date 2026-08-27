import SwiftUI

// MARK: - HojaFilaSerie — átomo de serie de La Hoja (FER-166)
//
// Misma anatomía en edición y sesión (mock `hoja-pantallas.html` P1 / P3): número · peso · reps ·
// marca/agarre. La grilla cambia por contexto; la tríada (peso × reps × marca) va a tinta plena
// salvo fantasma. Distinto de `SetTable` / `EntrenarSetRow`: nombres y contrato nuevos para La Hoja.

/// Fila de una serie en «La Hoja de Rutina» — edición o sesión capturando.
public struct HojaFilaSerie: View {

    /// Dónde vive la fila: cambia la grilla y qué columnas aparecen.
    public enum Contexto {
        /// P1 — `[26 · 76 · 52 · flexible(ANTERIOR) · 22]` (`.trow.e`).
        case edicion
        /// P3 — `[26 · 86 · flexible · 24]` (`.trow`).
        case sesion
    }

    /// Estado visual de la marca (sesión) / atenuación (fantasma).
    public enum Marca {
        /// Círculo verde 22 con ✓ blanco (`.ok`).
        case hecha
        /// Círculo 22 borde punteado tinta 10 % (`.pend`).
        case pendiente
        /// Fondo blanco .45 radio 10 + playhead ANT debajo (`.activa`).
        case activa
        /// Toda la tríada en tinta500 weight 600 (`.ghost`).
        case fantasma
    }

    /// Datos ya formateados: la vista no formatea números.
    public struct Datos {
        /// `"1"`… o `"C"` (calentamiento).
        public let numero: String
        /// `"C"` se pinta ámbar (`.sn.c` → `LiquidColor.ambar`).
        public let esCalentamiento: Bool
        /// Ya formateado (`"82.5"`); la vista no formatea.
        public let peso: String
        /// `"kg"` — minúscula pegada, small 10, tinta500.
        public let unidad: String
        /// ▲ verdeProfundo 10 pt antes del peso.
        public let conSubida: Bool
        /// `"8"` o `"8-10"`.
        public let reps: String
        /// `"Q2"` → sufijo small `· Q2` en reps (solo hechas).
        public let q: String?
        /// Edición: columna ANTERIOR (`"80 × 8 · Q2"`, tinta500, derecha).
        public let anterior: String?
        /// Sesión, fila activa: playhead `"ANT 80 × 8 · Q1"` debajo.
        public let ant: String?
        /// Edición: glifo ≡ tinta500 en la última columna.
        public let arrastrable: Bool
        /// FER-166 (GAP cerrado): la primera fila de un stack no dibuja el hairline superior
        /// (`.trow:first-child{border-top:0}` del mock). El init sellado obligaba al caller a
        /// recortar con padding negativo; ahora el propio dato lo declara.
        public let esPrimera: Bool

        public init(
            numero: String,
            esCalentamiento: Bool,
            peso: String,
            unidad: String,
            conSubida: Bool,
            reps: String,
            q: String? = nil,
            anterior: String? = nil,
            ant: String? = nil,
            arrastrable: Bool = false,
            esPrimera: Bool = false
        ) {
            self.numero = numero
            self.esCalentamiento = esCalentamiento
            self.peso = peso
            self.unidad = unidad
            self.conSubida = conSubida
            self.reps = reps
            self.q = q
            self.anterior = anterior
            self.ant = ant
            self.arrastrable = arrastrable
            self.esPrimera = esPrimera
        }
    }

    private let datos: Datos
    private let contexto: Contexto
    private let marca: Marca
    private let onMarcar: (() -> Void)?

    public init(
        datos: Datos,
        contexto: Contexto,
        marca: Marca,
        onMarcar: (() -> Void)? = nil
    ) {
        self.datos = datos
        self.contexto = contexto
        self.marca = marca
        self.onMarcar = onMarcar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filaPrincipal
            if contexto == .sesion, marca == .activa, let ant = datos.ant {
                playheadAnt(ant)
            }
        }
        .padding(.vertical, HojaMetrics.filaVPad)
        .padding(.horizontal, HojaMetrics.filaHPad)
        .frame(minHeight: HojaMetrics.hitMin)
        .background {
            if marca == .activa {
                RoundedRectangle(cornerRadius: HojaMetrics.activaRadius, style: .continuous)
                    .fill(Color.white.opacity(HojaMetrics.activaFondoAlfa))
            }
        }
        .overlay(alignment: .top) {
            // Hairline arriba salvo activa (mock `.activa{border-top-color:transparent}`) o
            // primera fila (`.trow:first-child{border-top:0}`).
            if marca != .activa, !datos.esPrimera {
                Rectangle()
                    .fill(LiquidColor.tinta7)
                    .frame(height: HojaMetrics.separadorGrosor)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .modifier(HojaFilaSerieA11y(onMarcar: contexto == .sesion ? onMarcar : nil))
    }

    // MARK: - Grilla

    @ViewBuilder private var filaPrincipal: some View {
        switch contexto {
        case .sesion:
            HStack(alignment: .firstTextBaseline, spacing: HojaMetrics.filaGap) {
                numeroCell
                    .frame(width: HojaMetrics.colNumero, alignment: .leading)
                pesoCell
                    .frame(width: HojaMetrics.colPesoSesion, alignment: .leading)
                repsCell
                    .frame(maxWidth: .infinity, alignment: .leading)
                marcaCell
                    .frame(width: HojaMetrics.colMarca, alignment: .trailing)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
            }
        case .edicion:
            HStack(alignment: .firstTextBaseline, spacing: HojaMetrics.filaGap) {
                numeroCell
                    .frame(width: HojaMetrics.colNumero, alignment: .leading)
                pesoCell
                    .frame(width: HojaMetrics.colPesoEdicion, alignment: .leading)
                repsCell
                    .frame(width: HojaMetrics.colRepsEdicion, alignment: .leading)
                anteriorCell
                    .frame(maxWidth: .infinity, alignment: .trailing)
                agarreCell
                    .frame(width: HojaMetrics.colMarcaEdicion, alignment: .trailing)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
            }
        }
    }

    // MARK: - Celdas

    private var numeroCell: some View {
        Text(verbatim: datos.numero)
            .font(InstrumentoType.grotesk(
                HojaMetrics.numeroSize, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(numeroColor)
    }

    private var pesoCell: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if datos.conSubida {
                Text(verbatim: "▲")
                    .font(InstrumentoType.grotesk(
                        HojaMetrics.subidaSize, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(LiquidColor.verdeProfundo)
                    .padding(.trailing, 2) // `.val .up` margin-right: 2px
            }
            Text(verbatim: datos.peso)
                .font(valFont)
                .foregroundStyle(triadaColor)
            Text(verbatim: datos.unidad)
                .font(InstrumentoType.grotesk(
                    HojaMetrics.unidadSize, weight: .semibold, relativeTo: .caption2))
                .foregroundStyle(LiquidColor.tinta500)
                .padding(.leading, 2) // `.val small` margin-left: 2px
        }
    }

    private var repsCell: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: datos.reps)
                .font(valFont)
                .foregroundStyle(triadaColor)
            if marca == .hecha, let q = datos.q {
                Text(verbatim: "· \(q)")
                    .font(InstrumentoType.grotesk(
                        HojaMetrics.unidadSize, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(LiquidColor.tinta500)
                    .padding(.leading, 4) // `.reps small` margin-left: 4px
            }
        }
    }

    @ViewBuilder private var anteriorCell: some View {
        if let anterior = datos.anterior {
            Text(verbatim: anterior)
                .font(InstrumentoType.grotesk(
                    HojaMetrics.antSize, weight: .regular, relativeTo: .caption2))
                .foregroundStyle(LiquidColor.tinta500)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var agarreCell: some View {
        if datos.arrastrable {
            Text(verbatim: "≡")
                .font(InstrumentoType.grotesk(
                    HojaMetrics.agarreSize, weight: .regular, relativeTo: .caption))
                .foregroundStyle(LiquidColor.tinta500)
        }
    }

    @ViewBuilder private var marcaCell: some View {
        let glifo = marcaGlifo
        if let onMarcar, contexto == .sesion {
            Button(action: onMarcar) { glifo }
                .buttonStyle(.plain)
        } else {
            glifo
        }
    }

    private var marcaGlifo: some View {
        Group {
            switch marca {
            case .hecha:
                ZStack {
                    Circle()
                        .fill(LiquidColor.verdePrimario)
                    Text(verbatim: "✓")
                        .font(InstrumentoType.grotesk(
                            HojaMetrics.marcaGlifoSize, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(Color.white)
                }
            case .pendiente, .activa, .fantasma:
                Circle()
                    .strokeBorder(
                        LiquidColor.tinta10,
                        style: StrokeStyle(
                            lineWidth: HojaMetrics.marcaBorde,
                            dash: HojaMetrics.marcaDash))
            }
        }
        .frame(width: HojaMetrics.marcaDiametro, height: HojaMetrics.marcaDiametro)
    }

    private func playheadAnt(_ ant: String) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: HojaMetrics.colNumero + HojaMetrics.filaGap)
            Text(verbatim: ant)
                .font(InstrumentoType.grotesk(
                    HojaMetrics.antSize, weight: .regular, relativeTo: .caption2))
                .foregroundStyle(LiquidColor.tinta500)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: HojaMetrics.colMarca)
        }
        .padding(.top, HojaMetrics.antOffsetY) // `.ant` margin-top: -3px
    }

    // MARK: - Color / tipografía

    private var valFont: Font {
        let size = contexto == .edicion ? HojaMetrics.valSizeEdicion : HojaMetrics.valSize
        let weight: GroteskWeight = marca == .fantasma ? .semibold : .bold
        return InstrumentoType.groteskNumber(size, weight: weight, relativeTo: .callout)
    }

    private var triadaColor: Color {
        marca == .fantasma ? LiquidColor.tinta500 : LiquidColor.tinta900
    }

    private var numeroColor: Color {
        if datos.esCalentamiento { return LiquidColor.ambar }
        return marca == .fantasma ? LiquidColor.tinta500 : LiquidColor.tinta700
    }

    /// Label compuesto para VoiceOver (mock AC: «Serie 2, 82.5 kilogramos, 8 repeticiones, pendiente»).
    private var accessibilityLabel: String {
        var parts: [String] = []
        if datos.esCalentamiento {
            parts.append("Calentamiento")
        } else {
            parts.append("Serie \(datos.numero)")
        }
        parts.append("\(datos.peso) kilogramos")
        parts.append("\(datos.reps) repeticiones")
        switch marca {
        case .hecha:
            parts.append("hecha")
            if let q = datos.q {
                let resto = q.hasPrefix("Q") ? String(q.dropFirst()) : q
                parts.append("quedaban \(resto)")
            }
        case .pendiente:
            parts.append("pendiente")
        case .activa:
            parts.append("activa")
            if let ant = datos.ant { parts.append(ant) }
        case .fantasma:
            parts.append("próxima")
        }
        return parts.joined(separator: ", ")
    }
}

/// Rasgo de botón + acción VoiceOver solo cuando hay `onMarcar` (sesión).
private struct HojaFilaSerieA11y: ViewModifier {
    let onMarcar: (() -> Void)?
    @ViewBuilder
    func body(content: Content) -> some View {
        if let onMarcar {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text(verbatim: "Marcar"), onMarcar)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("HojaFilaSerie · edición") {
    VStack(spacing: 0) {
        HojaFilaSerie(
            datos: .init(
                numero: "C", esCalentamiento: true,
                peso: "33", unidad: "kg", conSubida: false, reps: "10",
                anterior: "rampa 40·60·80 %", arrastrable: false),
            contexto: .edicion, marca: .pendiente)
        HojaFilaSerie(
            datos: .init(
                numero: "1", esCalentamiento: false,
                peso: "82.5", unidad: "kg", conSubida: false, reps: "8-10",
                anterior: "80 × 8 · Q2", arrastrable: true),
            contexto: .edicion, marca: .pendiente)
        HojaFilaSerie(
            datos: .init(
                numero: "2", esCalentamiento: false,
                peso: "82.5", unidad: "kg", conSubida: false, reps: "8-10",
                anterior: "80 × 8 · Q1", arrastrable: true),
            contexto: .edicion, marca: .pendiente)
        HojaFilaSerie(
            datos: .init(
                numero: "3", esCalentamiento: false,
                peso: "82.5", unidad: "kg", conSubida: false, reps: "8-10",
                anterior: "80 × 7 · Q0", arrastrable: true),
            contexto: .edicion, marca: .pendiente)
    }
    .padding(16)
    .background(LiquidColor.fondoGradient)
}

#Preview("HojaFilaSerie · sesión") {
    VStack(spacing: 0) {
        HojaFilaSerie(
            datos: .init(
                numero: "C", esCalentamiento: true,
                peso: "33", unidad: "kg", conSubida: false, reps: "10"),
            contexto: .sesion, marca: .hecha)
        HojaFilaSerie(
            datos: .init(
                numero: "1", esCalentamiento: false,
                peso: "82.5", unidad: "kg", conSubida: true, reps: "8", q: "Q2"),
            contexto: .sesion, marca: .hecha)
        HojaFilaSerie(
            datos: .init(
                numero: "2", esCalentamiento: false,
                peso: "82.5", unidad: "kg", conSubida: true, reps: "8",
                ant: "ANT 80 × 8 · Q1"),
            contexto: .sesion, marca: .activa)
        HojaFilaSerie(
            datos: .init(
                numero: "3", esCalentamiento: false,
                peso: "82.5", unidad: "kg", conSubida: true, reps: "8"),
            contexto: .sesion, marca: .fantasma)
    }
    .padding(16)
    .background(LiquidColor.fondoGradient)
}
#endif
