import SwiftUI

// MARK: - Liquid Glass · SignalOrb (handoff §5.2)
//
// Orbe de señal (fila superior de Hoy): lente de vidrio PLANO 72 + medidor semicircular
// centrado + joya marcadora + micro-valor del eje adentro («56 ms»), con label rótulo y
// caption de estado debajo.
//
// Geometría del anillo: arranca a −245° (las 7:30 de un velocímetro) y barre
// `progress × 360°` en sentido horario; el punto marcador viaja EN el extremo del arco
// («en el extremo del progreso», §5.2). El prototipo HTML rotaba el arco a −155° pero
// calculaba el punto con −245° — seguimos la fórmula documentada y la prosa, de modo que
// arco y punto coinciden (desviación anotada en docs/design-system/LIQUID-GLASS.md).
//
// Motion: progreso y punto se animan a su valor al entrar (ring progress · dur/gentle ·
// glass-out); bajo Reduce Motion aparecen ya colocados.

public struct LiquidSignalOrb: View {
    private let label: String
    private let caption: String
    private let progress: Double?
    private let icon: LiquidIcon.Glyph
    private let state: LiquidSignalState
    private let valor: String?
    private let hint: String?
    private let action: (() -> Void)?

    @State private var shownProgress: Double = 0
    @State private var shownFill: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidDebugHide) private var debugHide

    /// `progress == nil` = SIN DATOS: solo el track, sin arco ni punto; el caption baja a
    /// tinta/500 (el eje no vota — FER-1045).
    public init(label: String, caption: String, progress: Double?,
                icon: LiquidIcon.Glyph, state: LiquidSignalState,
                valor: String? = nil, hint: String? = nil, action: (() -> Void)? = nil) {
        self.label = label
        self.caption = caption
        self.progress = progress
        self.icon = icon
        self.state = state
        // Revote /inject: sin lectura del eje (`progress == nil`) el valor se SUPRIME —
        // «Autonómico, 56 ms: sin datos» era contradictorio en pantalla y en VoiceOver.
        self.valor = progress == nil ? nil : valor
        self.hint = hint
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { column }
                .buttonStyle(.liquidPress)
                .accessibilityLabel(Self.a11yLabel(label: label, caption: caption, valor: valor))
                .accessibilityHint(Text(verbatim: hint ?? ""))
        } else {
            column
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.a11yLabel(label: label, caption: caption, valor: valor))
        }
    }

    /// «{label}, {valor}: {caption}» — el contrato de VoiceOver del orbe (testeable en frío).
    static func a11yLabel(label: String, caption: String, valor: String? = nil) -> String {
        valor.map { "\(label), \($0): \(caption)" } ?? "\(label): \(caption)"
    }

    private var column: some View {
        VStack(spacing: 5) {
            orb
            Text(label).liquidMicro().foregroundStyle(LiquidColor.tinta900)
                .multilineTextAlignment(.center)
            Text(caption).font(LiquidType.microEstado)
                .foregroundStyle(progress == nil ? LiquidColor.tinta500 : state.caption)
                .padding(.top, -3)
        }
        // Toda la columna es tocable (/inject 2026-07-23), no solo el trazo del glifo.
        .contentShape(Rectangle())
        .onAppear {
            guard shownProgress == 0, shownFill == 0, !motionDisabled else { return }
            if reduceMotion {
                if let clamped { shownProgress = clamped }
                shownFill = fillTarget
            } else {
                withAnimation(LiquidMotion.ringProgress) {
                    if let clamped { shownProgress = clamped }
                    shownFill = fillTarget
                }
            }
        }
    }

    private var clamped: Double? {
        progress.map { min(1, max(0.02, $0)) }
    }

    /// Nivel de luz DENTRO del lente — DISCRETO por el estado del eje, NO por el z crudo.
    /// Sigue la revisión adversarial (Grok): el motor descarta magnitud al votar, así que el
    /// llenado codifica el mismo bit que el veredicto (en rango / atención / sin datos), no un
    /// continuo que fingiría una resolución que la señal no tiene. Da la sensación de «lleno»
    /// sin ser un score de contrabando. En rango = luz alta; atención = media; sin datos = 0.
    private var fillTarget: Double {
        guard progress != nil else { return 0 }
        switch state {
        case .ok: return 0.9
        case .atencion: return 0.42
        }
    }

    private var orb: some View {
        // Con el motion congelado (previews/renders) el anillo se pinta ya en su valor.
        let displayed: Double? = motionDisabled ? clamped : (clamped == nil ? nil : shownProgress)
        let fill: Double = motionDisabled ? fillTarget : shownFill
        return ZStack {
            if !debugHide.contains("esferas") {
                LiquidSphere(tone: state.tone)
                    // El glow e/2 como geometría (círculo difuminado detrás): una sombra
                    // directa sobre material proyecta el RECTÁNGULO de su capa de fondo.
                    .liquidShadow(debugHide.contains("glow") ? []
                                  : LiquidElevation.e2(tone: state.tone),
                                  silhouette: Circle())
                    .padding(4)
            }
            // La LUZ del eje sube dentro del lente hasta su nivel discreto (en rango = alto,
            // atención = medio, sin datos = nada). Sensación de «lleno» honesta: el tono del
            // clima, suave, recortado al círculo; el anillo y el dato quedan encima.
            if fill > 0, !debugHide.contains("esferas") {
                OrbFill(level: fill, tone: state.tone)
                    .padding(4)
            }
            // Medidor CENTRADO (pedido del dueño, sesión /inject): el arco es el semicírculo
            // superior — nace en la mitad izquierda (9 en punto), corona arriba y muere en la
            // mitad derecha (3 en punto). 0.5 = arriba = «en tu rango»; izquierda = bajo,
            // derecha = alto — la misma semántica de las agujas.
            OrbRing()
                .trim(from: 0, to: 0.5)
                .stroke(LiquidColor.tinta10, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(orbStartAngle))
            if let displayed {
                OrbRing()
                    .trim(from: 0, to: displayed * 0.5)
                    .stroke(state.ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(orbStartAngle))
                // El marcador como JOYA del estado (pasada de elegancia /inject): el tono
                // del clima con anillo blanco — el punto negro peleaba con todo.
                OrbMarkerDot(progress: displayed)
                    .fill(state.tone)
                OrbMarkerDot(progress: displayed)
                    .stroke(Color.white, lineWidth: 1.6)
            }
            // Camino 1+3 (/inject): el DATO vive dentro del lente; el icono es la
            // identidad del eje cuando aún no hay lectura.
            if let valor {
                Text(valor)
                    .font(LiquidType.cargaRatio)
                    .foregroundStyle(LiquidColor.tinta900)
                    // El dato compuesto (autonómico) entra como PALABRA de dos líneas
                    // («EN TU / RANGO»); los numerales de eje («56 ms», «7:20») caben en una
                    // sin tocar el límite. Centrado para que la palabra respire en el lente.
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .offset(y: 1)
            } else {
                LiquidIcon(icon, size: 20, color: LiquidColor.tinta900.opacity(0.5))
                    .offset(y: 1)
            }
        }
        .frame(width: 72, height: 72)
    }
}

/// Arranque del medidor centrado: 180° (las 9 en punto); barre 180° por arriba hasta las 3.
private let orbStartAngle: Double = 180

/// El círculo del anillo a r = 29/32 del radio del lienzo (64 → 29).
private struct OrbRing: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 * (29.0 / 32.0)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// La luz que llena el lente desde abajo hasta `level` (0…1) — recortada al círculo del
/// orbe para que se vea como líquido dentro del vidrio. Animable vía `level`.
private struct OrbFill: View {
    var level: Double
    var tone: Color

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let h = d * CGFloat(min(1, max(0, level)))
            tone.opacity(0.26)
                .frame(height: h)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

/// El punto marcador (r 3.4) viajando por el arco — Shape con `animatableData` para que
/// el punto recorra el anillo (no la cuerda) cuando el progreso anima.
private struct OrbMarkerDot: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 * (29.0 / 32.0)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Semicírculo superior: 180° + p·180°.
        let angle = (orbStartAngle + progress * 180) * .pi / 180
        let center = CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
        let dotR: CGFloat = 3.4
        return Path(ellipseIn: CGRect(x: center.x - dotR, y: center.y - dotR,
                                      width: dotR * 2, height: dotR * 2))
    }
}

#if DEBUG
#Preview("Liquid · SignalOrb") {
    HStack(spacing: 53) {
        LiquidSignalOrb(label: "AUTONÓMICO", caption: "EN TU RANGO", progress: 0.35,
                        icon: .ondaSenal, state: .ok)
        LiquidSignalOrb(label: "SUEÑO", caption: "EN TU RANGO", progress: 0.43,
                        icon: .lunaSenal, state: .ok)
        LiquidSignalOrb(label: "TÉRMICO", caption: "FUERA DE RANGO", progress: 0.72,
                        icon: .termoSenal, state: .atencion)
    }
    .padding(LiquidSpace.s800)
    .background(LiquidColor.papelGradient)
}
#endif
