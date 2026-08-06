import SwiftUI
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - FER-51 · Host de la Matriz
//
// Decisión del dueño (2026-08-06, revisión en vivo): el modo Cosmos se APAGA — era
// mucha complejidad; la Matriz es la apuesta y se pule a fondo. Este host monta la
// franja de estado T1–T5 + la cara Matriz, y nada más. (Las caras Cosmos siguen en
// StrandDesign con sus tests por si la decisión se revierte; aquí ya no se montan.)

struct HoyMatrizHost: View {
    @ObserveInjection private var inject

    let matriz: MatrizHoyModel
    let plantilla: LiquidHoyBuilder.Plantilla
    var onTapSeccion: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: LiquidSpace.s300) {
            if let copy = estadoCopy {
                estadoGrupo(copy)
            }
            MatrizHoyFace(model: matriz, onTapSeccion: onTapSeccion)
                .frame(maxWidth: .infinity)
        }
        // UN solo dueño del margen horizontal (hallazgo DeepSeek #14: antes 24 del
        // TodayView + 16 de la cara = 40 desalineados del copy de estado).
        .padding(.horizontal, MatrizTokens.margenH)
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    // MARK: - Estado (copy §11)

    private var estadoCopy: String? {
        switch plantilla {
        case .t1Pleno, .t2Provisional:
            return nil
        case .t3SinVeredicto(let causa):
            switch causa {
            case .leyendo:
                return String(localized: "hoy.leyendo", defaultValue: "Reading your night…")
            case .sinSync:
                return String(localized: "hoy.sinlectura.sync",
                              defaultValue: "No reading today · pending sync")
            case .nocheNoRegistrada:
                return String(localized: "hoy.sinlectura.noche",
                              defaultValue: "No reading today · the night wasn't recorded")
            }
        case .t4SinPermiso:
            return String(localized: "hoy.sinlectura.sync",
                          defaultValue: "No reading today · pending sync")
        case .t5Dormido:
            return nil
        }
    }

    private func estadoGrupo(_ texto: String) -> some View {
        Text(texto)
            .font(InstrumentoType.grotesk(13, weight: .medium))
            .foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("hoy-estado-copy")
    }
}
