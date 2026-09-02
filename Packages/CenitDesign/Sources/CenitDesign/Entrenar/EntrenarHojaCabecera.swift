import SwiftUI

// MARK: - EntrenarHojaCabecera — cabecera teñida de una hoja-herramienta (FER-197 · Ola 1)
//
// La cabecera COMÚN que las hojas minúsculas de Entrenar (RPE, Nota, Descanso, Discos,
// Progresión, Crear ejercicio…) componen sobre `.entrenarHojaFondo(tono:)`: glifo opcional +
// título + subtítulo opcional + UNA acción de salida. La acción de salida es PARAMETRIZABLE
// (`Salida`) — `.guardar`/`.cancelar` son texto, para la hoja que tiene algo que confirmar o
// descartar; `.cerrar` es el disco con aspa de `BackButton`, para la hoja de solo lectura o
// cuyo guardado ya vive en otro control (el CTA grande de `CreateExerciseSheet`). NO es un
// único botón «cerrar» a fuerza para las tres familias — cada hoja de la Ola 2 dice cuál es la
// suya (ver la tabla de `EntrenarHojaFondo.swift`).

public struct EntrenarHojaCabecera: View {
    /// Cómo se sale de la hoja.
    public enum Salida {
        /// Texto ya localizado («Guardar»). Confirma y sale — voz `verdeProfundo`, peso bold.
        case guardar(String)
        /// Texto ya localizado («Cancelar»). Descarta y sale — voz `tinta700`.
        case cancelar(String)
        /// El disco con aspa de `BackButton(role: .close)`. Sin texto: su VoiceOver ya dice
        /// «Cerrar» — para la hoja que no tiene nada que confirmar/descartar aparte.
        case cerrar
    }

    private let glifo: LiquidIcon.Glyph?
    private let titulo: String
    private let subtitulo: String?
    private let tono: LiquidTono
    private let salida: Salida
    private let onSalir: () -> Void

    @Environment(\.instrumentoTheme) private var theme

    /// - Parameters:
    ///   - glifo: la gota de icono (34/16/12 %, misma receta que `LiquidSheetHeader`). `nil` =
    ///     hojas sin identidad de icono propia (Cambiar ejercicio, Crear ejercicio).
    ///   - titulo: ya localizado.
    ///   - subtitulo: ya localizado; `nil` = sin segunda línea (RPE/Discos no la necesitan, la
    ///     hoja lo dice todo en el héroe de abajo).
    ///   - tono: tiñe la gota del glifo (si hay) — el mismo `LiquidTono` del fondo de la hoja.
    ///   - salida: qué control de salida dibuja (ver `Salida`).
    ///   - onSalir: la acción — la hoja decide si eso guarda, descarta o solo cierra.
    public init(glifo: LiquidIcon.Glyph? = nil, titulo: String, subtitulo: String? = nil,
                tono: LiquidTono = .neutro, salida: Salida, onSalir: @escaping () -> Void) {
        self.glifo = glifo
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.tono = tono
        self.salida = salida
        self.onSalir = onSalir
    }

    public var body: some View {
        HStack(alignment: .top, spacing: LiquidSpace.s300) {
            if let glifo {
                LiquidIconDrop(glifo, tone: tono == .neutro ? LiquidColor.tinta500 : tono.base,
                               size: 34, iconSize: 16, fillAlpha: 0.12)
            }
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(titulo)
                    .font(LiquidType.tituloHoja)
                    .foregroundStyle(LiquidColor.tinta900)
                    .accessibilityAddTraits(.isHeader)
                if let subtitulo {
                    Text(subtitulo)
                        .font(LiquidType.cuerpo)
                        .foregroundStyle(LiquidColor.tinta700)
                }
            }
            Spacer(minLength: LiquidSpace.s200)
            salidaControl
        }
    }

    @ViewBuilder
    private var salidaControl: some View {
        switch salida {
        case .cerrar:
            BackButton(role: .close, theme: theme, action: onSalir)
        case .cancelar(let texto):
            textoSalida(texto, tinta: LiquidColor.tinta700, peso: .semibold)
        case .guardar(let texto):
            textoSalida(texto, tinta: LiquidColor.verdeProfundo, peso: .bold)
        }
    }

    /// El botón de texto de `.guardar`/`.cancelar`: mismo target táctil de 44 (`EntrenarMetrics.row`)
    /// que el resto de la sección, sin engordar el dibujo — el toque crece hacia la izquierda.
    private func textoSalida(_ texto: String, tinta: Color, peso: Font.Weight) -> some View {
        Button(action: onSalir) {
            Text(texto)
                .font(LiquidType.boton.weight(peso))
                .foregroundStyle(tinta)
                .frame(minWidth: EntrenarMetrics.row, minHeight: EntrenarMetrics.row, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
    }
}

#if DEBUG
#Preview("EntrenarHojaCabecera · con glifo, subtítulo y las 3 salidas") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        EntrenarHojaCabecera(glifo: .llama, titulo: "RPE", subtitulo: "Serie 2 · 82,5 kg × 8 reps",
                             tono: .ambar, salida: .cerrar) {}
        EntrenarHojaCabecera(titulo: "Nota · Sentadilla", subtitulo: "Se guarda en el historial",
                             tono: .ambar, salida: .guardar("Guardar")) {}
        EntrenarHojaCabecera(titulo: "Nuevo ejercicio",
                             tono: .neutro, salida: .cancelar("Cancelar")) {}
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.fondoGradient)
    .instrumentoTheme(.base)
}

/// Sin glifo ni subtítulo — el mínimo de la cabecera (Cambiar ejercicio / Biblioteca).
#Preview("EntrenarHojaCabecera · mínima") {
    EntrenarHojaCabecera(titulo: "Cambiar ejercicio", salida: .cerrar) {}
        .padding(LiquidSpace.s550)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}

/// Dynamic Type grande: el título no se corta, el botón de texto envuelve antes que truncar.
#Preview("EntrenarHojaCabecera · xxxLarge") {
    EntrenarHojaCabecera(glifo: .luna, titulo: "Descanso entre series",
                         subtitulo: "Se aplica a esta serie y a las que siguen",
                         tono: .indigo, salida: .guardar("Guardar cambios")) {}
        .padding(LiquidSpace.s550)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
