import SwiftUI

// MARK: - Liquid Glass · CargaEscala (PROPUESTA 3 · bullet-graph de carga · FER-1045)
//
// Bullet-graph, NO gauge. Contesta «¿entrenaste más o menos que de costumbre?».
// La barra crece desde 0 hasta la razón del usuario (ACWR) sobre una escala 0→`maximo`;
// una muesca de tinta en `referencia` (1.0) marca «tu costumbre»; el corredor `corredor`
// (0.8–1.3) va lavado de verde. La razón se imprime como dato menor teñido por estado.
//
// Reemplaza a `LiquidCargaBar` (perilla sobre 4 segmentos) sin tocarla: hereda su fila
// [rótulo · barra · estado + razón], su vidrio de pastilla y su contrato de VoiceOver.
//
// Dos densidades:
//  · `.fila`   — compacta para la fila de Carga en Hoy (incluye su propio vidrio pastilla).
//  · `.bloque` — anotada (muesca, corredor, ticks y frase de contexto) para la hoja; se
//                monta DESNUDA porque la hoja ya aporta su superficie.
//
// Acento (color solo en el dato):
//  · en corredor  → `estado.tone` (verde con .ok).
//  · arriba (>corredor) → `estado.tone` (ámbar/atención con .atencion).
//  · abajo (<corredor)  → `tinta/700` NEUTRO — entrenar menos que de costumbre no es alarma
//                         (Impellizzeri 2020: el ACWR no predice lesiones), honesto sin teñir.
//  · calibrando → apagado, sin barra.

public struct LiquidCargaEscala: View {

    /// Densidad de presentación: fila compacta de Hoy vs. bloque anotado de la hoja.
    public enum Densidad: Sendable, Equatable { case fila, bloque }

    /// Una marca de la escala: su valor de razón y la etiqueta ya lista para pintar.
    public struct Tick: Sendable, Equatable {
        public let valor: Double
        public let etiqueta: String
        public init(valor: Double, etiqueta: String) {
            self.valor = valor
            self.etiqueta = etiqueta
        }
    }

    /// Marcas por defecto: los umbrales del motor (piso del corredor, costumbre, techo,
    /// sobrecarga). El cableado real las pasa LEÍDAS del motor, nunca copiadas a mano.
    public static let ticksPorDefecto: [Tick] = [
        .init(valor: 0.8, etiqueta: "0.8"),
        .init(valor: 1.0, etiqueta: "1.0"),
        .init(valor: 1.3, etiqueta: "1.3"),
        .init(valor: 1.5, etiqueta: "1.5"),
    ]

    private let razon: Double?
    private let estado: LiquidSignalState
    private let rotulo: String
    private let densidad: Densidad
    private let frase: String
    private let calibrando: Bool
    private let eje: String
    private let corredor: ClosedRange<Double>
    private let referencia: Double
    private let maximo: Double
    private let ticks: [Tick]
    private let a11y: String?

    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// - Parameters:
    ///   - razon: la razón del usuario (ACWR, ej. `1.03`); `nil` = calibrando (sin barra).
    ///   - estado: `.ok` (verde) / `.atencion` (ámbar) — define el acento cuando la razón NO
    ///     está por debajo del corredor (abajo se pinta neutro sin importar el estado).
    ///   - rotulo: el rótulo de estado YA localizado, ej. «EN EQUILIBRIO».
    ///   - densidad: `.fila` (Hoy, con vidrio) o `.bloque` (hoja, desnudo + frase + ticks).
    ///   - frase: la frase de contexto YA localizada; solo se pinta en `.bloque`.
    ///   - calibrando: fuerza el estado apagado aunque llegue una razón.
    ///   - eje: el rótulo del eje YA localizado para la fila (ej. «CARGA»); ignorado en bloque.
    ///   - corredor: el corredor sano, LEÍDO del motor (`acwrSweetSpotLow…High`).
    ///   - referencia: dónde cae «tu costumbre» (la muesca), típicamente `1.0`.
    ///   - maximo: tope de la escala (típicamente `2.0`); mapea la fracción de la barra.
    ///   - ticks: las marcas anotadas del `.bloque`, LEÍDAS del motor.
    ///   - a11yLabel: etiqueta de VoiceOver ya compuesta; si es `nil` se deriva con
    ///     `a11yLabel(eje:rotulo:razon:)`.
    public init(
        razon: Double?,
        estado: LiquidSignalState = .ok,
        rotulo: String,
        densidad: Densidad,
        frase: String = "",
        calibrando: Bool = false,
        eje: String = "CARGA",
        corredor: ClosedRange<Double> = 0.8...1.3,
        referencia: Double = 1.0,
        maximo: Double = 2.0,
        ticks: [Tick] = LiquidCargaEscala.ticksPorDefecto,
        a11yLabel: String? = nil
    ) {
        self.razon = razon
        self.estado = estado
        self.rotulo = rotulo
        self.densidad = densidad
        self.frase = frase
        self.calibrando = calibrando
        self.eje = eje
        self.corredor = corredor
        self.referencia = referencia
        self.maximo = maximo
        self.ticks = ticks
        self.a11y = a11yLabel
    }

    // MARK: Cuerpo

    public var body: some View {
        Group {
            switch densidad {
            case .fila:   fila
            case .bloque: bloque
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: resolvedA11y))
    }

    /// «{eje}: {rótulo}[, {razón}]» — contrato de VoiceOver testeable. El número es el dato
    /// protagonista y también se ESCUCHA. Formateo con punto decimal (locale-neutral: el DS
    /// no conoce locales; el número es dato, no copy).
    public static func a11yLabel(eje: String, rotulo: String, razon: Double?) -> String {
        if let razon {
            return "\(eje): \(rotulo), \(formato(razon))"
        }
        return "\(eje): \(rotulo)"
    }

    private var resolvedA11y: String {
        a11y ?? Self.a11yLabel(eje: eje, rotulo: rotulo, razon: esCalibrando ? nil : razon)
    }

    // MARK: Estado derivado

    private var esCalibrando: Bool { calibrando || razon == nil }

    /// El acento del dato: verde en corredor, tono del estado arriba, neutro abajo.
    private var acento: Color {
        guard !esCalibrando, let r = razon else { return LiquidColor.tinta500 }
        if r < corredor.lowerBound { return LiquidColor.tinta700 }
        return estado.tone
    }

    private static func formato(_ v: Double) -> String { String(format: "%.2f", v) }

    private func frac(_ v: Double) -> Double { min(1, max(0, v / maximo)) }

    // MARK: Densidad · fila

    private var fila: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(eje)
                .font(LiquidType.cargaLabel).tracking(LiquidType.cargaLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            bulletTrack(trackH: 6)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(rotulo)
                    .font(LiquidType.cargaStatus).tracking(LiquidType.cargaStatusTracking)
                    .foregroundStyle(esCalibrando ? LiquidColor.tinta500 : LiquidColor.tinta700)
                    .minimumScaleFactor(0.8)
                if let razon, !esCalibrando {
                    Text(Self.formato(razon))
                        .font(LiquidType.cargaRatio)
                        .foregroundStyle(acento)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, LiquidSpace.s400)
        .liquidGlass(.pastilla)
        // Área tocable ≥ 44 pt sin engordar el vidrio (paridad con LiquidCargaBar).
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: Densidad · bloque

    private var bloque: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(rotulo)
                    .font(LiquidType.cargaStatus).tracking(LiquidType.cargaStatusTracking)
                    .foregroundStyle(esCalibrando ? LiquidColor.tinta500 : LiquidColor.tinta700)
                if let razon, !esCalibrando {
                    Text(Self.formato(razon))
                        .font(LiquidType.cargaRatio)
                        .foregroundStyle(acento)
                }
                Spacer(minLength: 0)
            }
            bulletTrack(trackH: 14)
            ticksRow
            if !frase.isEmpty {
                Text(frase)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, LiquidSpace.s100)
            }
        }
    }

    private var ticksRow: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ForEach(ticks.indices, id: \.self) { i in
                let t = ticks[i]
                Text(t.etiqueta)
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize()
                    .alignmentGuide(.leading) { d in d.width / 2 }
                    .position(x: w * frac(t.valor), y: 6)
            }
        }
        .frame(height: 12)
    }

    // MARK: Track del bullet

    private func bulletTrack(trackH: CGFloat) -> some View {
        let corridorAlfa = densidad == .fila
            ? LiquidChart.bandaActivaAlfa
            : LiquidChart.bandaReposoAlfa
        // Objetivo de la barra (fracción 0…1); con el motion congelado va directo.
        let target = razon.map { frac($0) } ?? 0
        return GeometryReader { geo in
            let w = geo.size.width
            let grown = (motionDisabled || reduceMotion || entered) ? target : 0
            ZStack(alignment: .leading) {
                Capsule().fill(LiquidColor.tinta7)
                    .frame(height: trackH)
                // Corredor sano.
                Capsule()
                    .fill(LiquidColor.verdePrimario.opacity(corridorAlfa))
                    .frame(width: max(0, w * (frac(corredor.upperBound) - frac(corredor.lowerBound))),
                           height: trackH)
                    .offset(x: w * frac(corredor.lowerBound))
                // Barra del dato — crece desde 0.
                if let _ = razon, !esCalibrando {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [acento.opacity(0.9), acento.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: w * grown, height: trackH)
                }
                // Muesca «tu costumbre».
                Rectangle()
                    .fill(LiquidColor.tinta900)
                    .frame(width: 1.5, height: trackH + 4)
                    .offset(x: w * frac(referencia) - 0.75)
            }
            .frame(height: trackH, alignment: .leading)
        }
        .frame(height: trackH)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !entered else { return }
            if motionDisabled || reduceMotion {
                entered = true
            } else {
                withAnimation(LiquidMotion.ringProgress) { entered = true }
            }
        }
    }
}

#if DEBUG
private struct LiquidCargaEscalaDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {

            grupo("FILA · Hoy") {
                LiquidCargaEscala(razon: 1.03, estado: .ok, rotulo: "EN EQUILIBRIO",
                                  densidad: .fila)
                LiquidCargaEscala(razon: 1.62, estado: .atencion, rotulo: "SOBRECARGA",
                                  densidad: .fila)
                LiquidCargaEscala(razon: 0.62, estado: .ok, rotulo: "A LA BAJA",
                                  densidad: .fila)
                LiquidCargaEscala(razon: nil, rotulo: "ARMANDO · 8/14",
                                  densidad: .fila, calibrando: true)
            }

            grupo("BLOQUE · hoja") {
                LiquidCargaEscala(razon: 1.03, estado: .ok, rotulo: "EN EQUILIBRIO",
                                  densidad: .bloque,
                                  frase: "Entrenaste como de costumbre esta semana.")
                LiquidCargaEscala(razon: 1.62, estado: .atencion, rotulo: "SOBRECARGA",
                                  densidad: .bloque,
                                  frase: "Bastante más que de costumbre — ojo con el descanso.")
                LiquidCargaEscala(razon: 0.62, estado: .ok, rotulo: "A LA BAJA",
                                  densidad: .bloque,
                                  frase: "Menos que de costumbre. Buen momento para sumar.")
                LiquidCargaEscala(razon: nil, rotulo: "Armando tu costumbre",
                                  densidad: .bloque,
                                  frase: "8 de 14 días con esfuerzo registrado.",
                                  calibrando: true)
            }
        }
        .padding(LiquidSpace.s550)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColor.papelGradient)
    }

    @ViewBuilder
    private func grupo<Content: View>(_ titulo: String,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s400) {
            Text(titulo)
                .font(LiquidType.cargaLabel).tracking(LiquidType.cargaLabelTracking)
                .foregroundStyle(LiquidColor.tinta500)
            content()
        }
    }
}

#Preview("Liquid · CargaEscala") {
    LiquidCargaEscalaDemo()
}
#endif
