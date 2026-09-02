import SwiftUI

// MARK: - Liquid Glass · ChecklistRow (de qué está hecho el número)
//
// La fila de un FACTOR de un desglose: «de qué está hecha» la edad corporal, «lo que usamos» /
// «lo que falta» de la edad física. Un check cuando el factor está PRESENTE, un círculo vacío ○
// cuando está AUSENTE — y, si falta, el MOTIVO en tinta secundaria (por qué no entró al cálculo).
//
// La fila ausente NUNCA se oculta: decir «esto falta, y por esto» es la lectura honesta del
// desglose; borrarla afirmaría una completitud que el dato no tiene (criterio de aceptación de
// edad corporal — «nunca ocultes los que faltan»). El caller decide presente/ausente y el motivo;
// la pieza solo los presenta con el lenguaje visual de la familia.

public struct LiquidChecklistRow: View {
    private let etiqueta: String
    private let presente: Bool
    private let motivo: String?
    private let tono: Color

    public init(etiqueta: String, presente: Bool, motivo: String? = nil,
                tono: Color = LiquidColor.verdePrimario) {
        self.etiqueta = etiqueta
        self.presente = presente
        self.motivo = motivo
        self.tono = tono
    }

    /// El motivo se pinta SOLO cuando el factor está ausente y el caller dio una razón: un factor
    /// presente no necesita excusa; uno ausente la lleva SIEMPRE que exista. Es el candado de
    /// «nunca ocultes lo que falta» — si esto devolviera `false` para un ausente con motivo, la
    /// fila estaría escondiendo justo su propia razón de faltar.
    static func muestraMotivo(presente: Bool, motivo: String?) -> Bool {
        !presente && !(motivo?.isEmpty ?? true)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
            marca
            VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                Text(verbatim: etiqueta)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(presente ? LiquidColor.tinta900 : LiquidColor.tinta700)
                if Self.muestraMotivo(presente: presente, motivo: motivo), let motivo {
                    Text(verbatim: motivo)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LiquidSpace.s150)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Check (presente, en el tono del dato) o círculo vacío (ausente, tinta quieta). SF Symbol
    /// dibujado como el resto del cromo de la familia (`info.circle`, `chevron.left`): fuente
    /// `iconSF`, color EXPLÍCITO en el trazo.
    private var marca: some View {
        Image(systemName: presente ? "checkmark" : "circle")
            .font(LiquidType.iconSF(size: 15))
            .foregroundStyle(presente ? tono : LiquidColor.tinta500)
            .frame(width: 16, height: 16)
    }
}

#if DEBUG
#Preview("Liquid · ChecklistRow") {
    VStack(alignment: .leading, spacing: 0) {
        LiquidChecklistRow(etiqueta: "Frecuencia cardiaca en reposo", presente: true)
        LiquidChecklistRow(etiqueta: "VO₂ máx estimado", presente: true)
        LiquidChecklistRow(etiqueta: "Sueño", presente: false,
                           motivo: "Sin noches suficientes para tu base todavía.")
        LiquidChecklistRow(etiqueta: "Pasos diarios", presente: false,
                           motivo: "Conecta Apple Salud para incluirlos.")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
