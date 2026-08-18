import SwiftUI
import Observation

// MARK: - «Hoy en atmósfera» (FER-118) · El fondo
//
// Blanco puro y, detrás de todo, el polvo: partículas de Metal fijas respecto al scroll (con
// un parallax del 22 %) que derivan hacia arriba, respiran y toman el color del veredicto. Va
// como `.background` del scroll de Hoy; el héroe (`LiquidEcosistema`) NO es parte del fondo:
// viaja con el contenido, y al bajar solo quedan las partículas atrás del vidrio.
//
// Un solo reloj (20 Hz, `LiquidMotion.intervaloAmbiente`: las derivas son ≤ 4 pt/s, o sea
// ≤ 0.2 pt por cuadro — invisible a más), pausable con hoja abierta / background / onboarding /
// pestaña oculta / Reduce Motion; y además el lienzo se redibuja bajo demanda cuando cambia el
// desplazamiento del scroll, para que el parallax siga al dedo aunque el reloj vaya lento.
//
// Backends, como el héroe (FER-13): en iOS con Metal, `AtmosferaMetalLienzo` (un draw
// instanciado); si no —macOS, watchOS, previews, renders, o el shader que no armó— un `Canvas`
// que recorre la MISMA `PolvoSimulacion` con la mitad de partículas a 12 Hz.

/// Lo que la pantalla le empuja al fondo SIN recomponerse entera por cada cuadro de scroll:
/// `TodayView` solo pasa el objeto; quien lee `desplazamiento` es `LiquidAtmosfera`, así el
/// scroll invalida el fondo y nada más.
@MainActor @Observable public final class AtmosferaEstado {
    /// `contentOffset.y` del scroll de Hoy, ≥ 0 (0 = tope; el overscroll del pull NO cuenta).
    public var desplazamiento: CGFloat = 0
    /// `false` cuando la pestaña Hoy no está en pantalla → el reloj se detiene.
    public var visible: Bool = true
    public init() {}
}

extension LiquidAmbiente {
    /// La tinta de partícula de este clima como `Color`: exactamente la que el héroe le pone a su
    /// orbe (`Coreografia.tintaClima`) — un solo diccionario para héroe y polvo.
    var particulaColor: Color {
        switch self {
        case .bien: return LiquidColor.particulaVerde
        case .atencion: return LiquidColor.particulaAmbar
        case .alerta: return LiquidColor.particulaRoja
        case .neutro: return LiquidColor.particulaNeutra
        }
    }
}

public struct LiquidAtmosfera: View {
    private let ambiente: LiquidAmbiente
    private let estado: AtmosferaEstado

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    /// El origen del tiempo del polvo: segundos de SESIÓN, no el reloj absoluto (un `Float` no
    /// resuelve `timeIntervalSinceReferenceDate`; con < 1 día de sesión resuelve 0.02 pt).
    @State private var inicio = Date()
    #if os(iOS) && canImport(MetalKit)
    @ObservedObject private var metal = EcosistemaMetal.compartido
    #endif

    public init(ambiente: LiquidAmbiente, estado: AtmosferaEstado) {
        self.ambiente = ambiente
        self.estado = estado
    }

    private var still: Bool { reduceMotion || motionDisabled }
    private var paused: Bool { still || ambientPaused || !estado.visible }
    private var neutra: Bool { ambiente == .neutro }
    private var paleta: EcosistemaPaleta { .desde(clima: ambiente.particulaColor) }
    /// El crossfade del clima: 1.6 s como el héroe; con Reduce Motion, el corte corto del héroe.
    private var crossfade: TimeInterval {
        reduceMotion ? LiquidEcosistemaMotion.reduceMotionCrossfade
                     : LiquidEcosistemaMotion.ambienteCrossfade
    }

    public var body: some View {
        ZStack {
            LiquidColor.papelTarjeta
            TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente, paused: paused)) { ctx in
                let t = still ? 0 : ctx.date.timeIntervalSince(inicio)
                capa(t: t, desplazamiento: still ? 0 : estado.desplazamiento)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        #if os(iOS) && canImport(MetalKit)
        .onAppear { metal.preparar() }
        #endif
    }

    @ViewBuilder
    private func capa(t: TimeInterval, desplazamiento: CGFloat) -> some View {
        #if os(iOS) && canImport(MetalKit)
        if let recursos = metal.recursos, recursos.polvo != nil, !motionDisabled {
            AtmosferaMetalLienzo(recursos: recursos, paleta: paleta, t: t,
                                 desplazamiento: desplazamiento, neutra: neutra, still: still,
                                 crossfade: crossfade)
        } else {
            lienzoCanvas(t: t, desplazamiento: desplazamiento)
        }
        #else
        lienzoCanvas(t: t, desplazamiento: desplazamiento)
        #endif
    }

    /// El respaldo: la misma spec, la mitad de partículas (el `Canvas` rasteriza en CPU). El
    /// cambio de clima aquí es inmediato (el crossfade vive en el renderer de Metal).
    private func lienzoCanvas(t: TimeInterval, desplazamiento: CGFloat) -> some View {
        let paleta = self.paleta
        let neutra = self.neutra
        let still = self.still
        return Canvas(rendersAsynchronously: false) { ctx, size in
            let n = PolvoSimulacion.cuenta(lienzo: size) / 2
            for i in 0..<n {
                let p = PolvoSimulacion.particula(indice: i, t: t, lienzo: size,
                                                  desplazamiento: desplazamiento,
                                                  neutra: neutra, still: still)
                let c = Self.color(paleta, p.tono)
                let rect = CGRect(x: p.centro.x - p.radio, y: p.centro.y - p.radio,
                                  width: p.radio * 2, height: p.radio * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(c.opacity(p.alfa)))
            }
        }
    }

    /// El color de un tono de la paleta (SIMD4 sRGB → `Color`).
    static func color(_ paleta: EcosistemaPaleta, _ tono: PolvoSimulacion.Tono) -> Color {
        let c: SIMD4<Float>
        switch tono {
        case .clima: c = paleta.clima
        case .reposo: c = paleta.reposo
        case .sueno: c = paleta.sueno
        case .vigiaTemp: c = paleta.vigiaTemp
        case .vigiaResp: c = paleta.vigiaResp
        case .neutra: c = paleta.neutra
        }
        return Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: 1)
    }
}

// MARK: - Previews

#if DEBUG
private struct AtmosferaPreview: View {
    let ambiente: LiquidAmbiente
    let titulo: String
    @State private var estado = AtmosferaEstado()
    var body: some View {
        ZStack {
            LiquidAtmosfera(ambiente: ambiente, estado: estado)
            VStack {
                Text(titulo)
                    .font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta700)
                    .padding(LiquidSpace.s400).frame(maxWidth: .infinity, minHeight: 140,
                                                    alignment: .topLeading)
                    .liquidGlass(.superficieAtmosfera)
                Spacer()
            }
            .padding(LiquidSpace.s400)
        }
    }
}

#Preview("Atmósfera · verde") { AtmosferaPreview(ambiente: .bien, titulo: "En rango") }
#Preview("Atmósfera · ámbar") { AtmosferaPreview(ambiente: .atencion, titulo: "Ve leve") }
#Preview("Atmósfera · rojo") { AtmosferaPreview(ambiente: .alerta, titulo: "Recupera") }
#Preview("Atmósfera · neutro (calibrando)") { AtmosferaPreview(ambiente: .neutro, titulo: "Conociéndote") }
#Preview("Atmósfera · Reduce Motion (quieta)") {
    AtmosferaPreview(ambiente: .bien, titulo: "En rango · quieto")
        .environment(\.liquidMotionDisabled, true)
}
#endif
