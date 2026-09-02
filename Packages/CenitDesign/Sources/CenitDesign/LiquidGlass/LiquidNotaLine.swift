import SwiftUI

// MARK: - Liquid Glass · Nota de pie / fila de acuerdo (FER-254)
//
// Dos voces del mismo nombre (el DS no duplica tipos por régimen):
//   · Pie de hoja — una línea quieta (`LiquidNotaLine("…")`), método o aviso de ventana.
//   · Acuerdo de fusión — veredicto + valores de cada fuente, con regla lateral de 2 pt
//     (`LiquidNotaLine(verdict:values:tono:)`). Conflicto → `LiquidSignalState.atencion`;
//     coincidencia / delta menor → `.ok` (tinta quieta, no verde de señal).
//
// Strings YA localizados; el DS no conoce locales. Ambos valores se muestran — nunca se
// promedian aquí.

public struct LiquidNotaLine: View {
    private enum Kind {
        case pie(text: String, tono: Color)
        case acuerdo(verdict: String, values: String, tono: LiquidSignalState)
    }

    private let kind: Kind

    /// Ancho de la regla lateral del acuerdo — es trazo, no espaciado (paridad preview FER-254).
    private static let reglaAncho: CGFloat = 2

    /// Nota corta del pie (nota de método, o la línea de conectar Apple Salud).
    ///
    /// El `tono` es tinta quieta por defecto — la nota acompaña, no llama. El caller solo lo
    /// sube (a `LiquidColor.atencionTexto`) cuando la nota AVISA algo que cambia la lectura de
    /// lo que está viendo: p. ej. «se muestran los últimos N días» cuando la ventana se
    /// ensanchó sola.
    public init(_ text: String, tono: Color = LiquidColor.tinta500) {
        self.kind = .pie(text: text, tono: tono)
    }

    /// Fila de acuerdo entre fuentes (pasos / sueño total / kcal activas).
    ///
    /// `tono: .atencion` tiñe veredicto + regla; `.ok` deja veredicto en tinta700 y regla en
    /// tinta10 (sin tomar el verde de `LiquidSignalState.tone` — aquí «ok» es quietud, no
    /// celebración).
    public init(verdict: String, values: String, tono: LiquidSignalState) {
        self.kind = .acuerdo(verdict: verdict, values: values, tono: tono)
    }

    public var body: some View {
        switch kind {
        case let .pie(text, tono):
            Text(verbatim: text)
                .font(LiquidType.captionLectura)
                .foregroundStyle(tono)
                .fixedSize(horizontal: false, vertical: true)
        case let .acuerdo(verdict, values, tono):
            acuerdoBody(verdict: verdict, values: values, tono: tono)
        }
    }

    private func acuerdoBody(verdict: String, values: String,
                             tono: LiquidSignalState) -> some View {
        let conflicto = tono == .atencion
        let tintaVeredicto = conflicto ? LiquidColor.atencion : LiquidColor.tinta700
        let tintaRegla = conflicto ? LiquidColor.atencion : LiquidColor.tinta10
        return HStack(alignment: .top, spacing: LiquidSpace.s200) {
            Capsule()
                .fill(tintaRegla)
                .frame(width: Self.reglaAncho)
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: verdict)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(tintaVeredicto)
                Text(verbatim: values)
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Liquid · NotaLine (pie)") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        LiquidNotaLine("SDNN sobre los latidos nocturnos, comparado contra tu base de 21 noches (Task Force, 1996).")
        LiquidNotaLine("Conecta Apple Salud para ver tu VFC aquí.")
        LiquidNotaLine("Se muestran los últimos 47 días.", tono: LiquidColor.atencionTexto)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}

#Preview("Liquid · NotaLine (acuerdo)") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        LiquidNotaLine(verdict: "Las fuentes coinciden",
                       values: "Apple Salud 8,100 · Calculado 8,420",
                       tono: .ok)
        LiquidNotaLine(verdict: "Difieren ligeramente",
                       values: "Apple Salud 612 · Importado 588",
                       tono: .ok)
        LiquidNotaLine(verdict: "Fuentes en conflicto",
                       values: "Importado 7 h 12 m · Apple Salud 2 h 00 m",
                       tono: .atencion)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelAlto)
}
#endif
