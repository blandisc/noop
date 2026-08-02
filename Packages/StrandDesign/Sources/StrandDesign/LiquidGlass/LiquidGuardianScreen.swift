import SwiftUI

// MARK: - Liquid Glass · Hoja del guardián (FER-10)
//
// La hoja que contesta «¿qué es VIGILANDO?»: el centinela (temperatura + respiración)
// explicado con su regla — vigila, no vota; solo en pareja empuja. Nunca dice
// «enfermedad» ni diagnostica. Todos los strings llegan YA localizados.

/// El contenido de la hoja del guardián — strings del catálogo, armados por la app.
public struct LiquidGuardianHoja: Sendable {
    public let kicker: String        // «VIGILANDO»
    public let titulo: String        // «El guardián»
    public let intro: String
    public let filaTemp: (label: String, valor: String, fuera: Bool)
    public let filaResp: (label: String, valor: String, fuera: Bool)
    public let estadoAhora: String   // «Ahora: dentro de tu patrón.» / juntas / una
    public let reglaTitulo: String   // «Vigila; no vota.»
    public let reglaCuerpo: String

    public init(kicker: String, titulo: String, intro: String,
                filaTemp: (label: String, valor: String, fuera: Bool),
                filaResp: (label: String, valor: String, fuera: Bool),
                estadoAhora: String, reglaTitulo: String, reglaCuerpo: String) {
        self.kicker = kicker
        self.titulo = titulo
        self.intro = intro
        self.filaTemp = filaTemp
        self.filaResp = filaResp
        self.estadoAhora = estadoAhora
        self.reglaTitulo = reglaTitulo
        self.reglaCuerpo = reglaCuerpo
    }
}

public struct LiquidGuardianScreen: View {
    private let hoja: LiquidGuardianHoja

    public init(_ hoja: LiquidGuardianHoja) {
        self.hoja = hoja
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s400) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Text(hoja.kicker).liquidKicker().foregroundStyle(LiquidColor.tinta500)
                Text(hoja.titulo)
                    .font(LiquidType.tituloHoja)
                    .foregroundStyle(LiquidColor.tinta900)
            }
            Text(hoja.intro)
                .font(LiquidType.cuerpo).lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
            VStack(spacing: LiquidSpace.s200) {
                fila(hoja.filaTemp)
                fila(hoja.filaResp)
            }
            Text(hoja.estadoAhora)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Text(hoja.reglaTitulo)
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(hoja.reglaCuerpo)
                    .font(LiquidType.cuerpo).lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fila(_ f: (label: String, valor: String, fuera: Bool)) -> some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(f.label)
                .font(LiquidType.cargaLabel).tracking(LiquidType.cargaLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: 0)
            Text(f.valor)
                .font(LiquidType.datoMenor)
                .foregroundStyle(f.fuera ? LiquidColor.atencionTexto : LiquidColor.tinta700)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, LiquidSpace.s400)
        .liquidGlass(.pastilla)
    }
}

#if DEBUG
#Preview("Guardián · hoja") {
    ZStack {
        LiquidColor.fondoGradient.ignoresSafeArea()
        LiquidGuardianScreen(LiquidGuardianHoja(
            kicker: "VIGILANDO", titulo: "El guardián",
            intro: "Tu temperatura de piel y tu respiración de la noche, vigiladas contra tu propio patrón.",
            filaTemp: ("Temperatura", "+0.1°", false),
            filaResp: ("Respiración", "14 rpm", false),
            estadoAhora: "Ahora: dentro de tu patrón.",
            reglaTitulo: "Vigila; no vota.",
            reglaCuerpo: "Una sola señal fuera de tu patrón nunca cambia tu veredicto: un cuarto caliente o una cobija de más la mueven sola. Solo cuando las dos se salen juntas, el guardián empuja tu día a «Hoy ve leve». Nunca diagnostica nada."))
            .padding(LiquidSpace.s550)
    }
}
#endif
