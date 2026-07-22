import SwiftUI

// MARK: - Liquid Glass · Color (handoff «Liquid Glass v1» §4.1)
//
// La paleta del sistema Liquid Glass: tinta (texto/trazos), papel (fondos), verde (única voz
// de marca), tonos de dato con asignación 1:1 por métrica, semánticos y los blancos de vidrio
// (alfas fijos de #FFFFFF que componen las recetas de LiquidGlassRecipe).
//
// Regla de tinte del dato: el tono tiñe SOLO la gota del icono (al 10–12 % de alfa, ver
// `LiquidIconDrop`) y el valor numérico. Nunca el fondo de la tarjeta.
//
// Hex exactos del handoff — no sustituir. Todo hex del sistema vive aquí; pantallas y
// componentes consumen estos tokens.

public enum LiquidColor {

    // MARK: Tinta (texto y trazos)

    /// Texto principal, iconos activos.
    public static let tinta900 = Color(hex: "#221D16")
    /// Texto secundario, kickers de fecha.
    public static let tinta700 = Color(hex: "#5C5648")
    /// Labels, captions neutros, iconos inactivos.
    public static let tinta500 = Color(hex: "#6F6857")
    /// Tracks de anillos, divisores de lista — tinta/900 al 10 %.
    public static let tinta10 = tinta900.opacity(0.10)
    /// Segmentos de barra inactivos, chips de día vacíos — tinta/900 al 7 %.
    public static let tinta7 = tinta900.opacity(0.07)

    // MARK: Papel (fondos)

    /// Inicio del degradado de pantalla.
    public static let papelAlto = Color(hex: "#F8F6EF")
    /// Fin del degradado de pantalla.
    public static let papelBajo = Color(hex: "#F0EDE4")
    /// Relleno del vidrio/lente (dock) — #FBF9F2 al 50 %.
    public static let papelDock = Color(hex: "#FBF9F2").opacity(0.5)

    /// El degradado de pantalla papel/alto → papel/bajo (fondo base de toda pantalla Liquid).
    public static let papelGradient = LinearGradient(
        colors: [papelAlto, papelBajo], startPoint: .top, endPoint: .bottom)

    // MARK: Verde (única voz de marca)

    /// CTA, énfasis, palabra destacada del hero, pulsos.
    public static let verdePrimario = Color(hex: "#0C8F62")
    /// Deltas positivos, texto quiet.
    public static let verdeProfundo = Color(hex: "#00774B")
    /// SOLO halos/auroras de fondo (nunca texto).
    public static let verdeAurora = Color(hex: "#2EB27D")
    /// El verde claro de los orbes drift del fondo de Hoy (rgba(80,175,115,…) en el ensamble).
    public static let verdeOrbe = Color(hex: "#50AF73")
    /// Tope del degradado del botón primary (#12A06E → verde/primario).
    public static let verdeBotonAlto = Color(hex: "#12A06E")
    /// Texto sobre el botón primary (papel cálido, no blanco puro).
    public static let tintaSobreVerde = Color(hex: "#F4F1E8")

    // MARK: Tonos de dato (asignación 1:1, no intercambiables)

    /// Sueño.
    public static let indigo = Color(hex: "#5D5A9E")
    /// HRV.
    public static let cian = Color(hex: "#147C8C")
    /// FC en reposo.
    public static let rosa = Color(hex: "#B85068")
    /// Esfuerzo, temperatura de piel.
    public static let ambar = Color(hex: "#C4631F")
    /// Pasos.
    public static let teal = Color(hex: "#4C8998")
    /// Respiración.
    public static let azul = Color(hex: "#3B6FA0")
    /// Amanecer / halos cálidos.
    public static let oro = Color(hex: "#E8C24B")

    // MARK: Semánticos

    /// Deltas a favor.
    public static let positivo = Color(hex: "#00774B")
    /// Fuera de rango.
    public static let atencion = Color(hex: "#C4631F")
    /// Deltas en contra.
    public static let negativo = Color(hex: "#B3402A")

    // MARK: Blancos de vidrio (alfas fijos de #FFFFFF — §4.1)

    /// `.92` — highlight especular.
    public static let vidrioEspecular = Color.white.opacity(0.92)
    /// `.9` — borde de esfera / gota.
    public static let vidrioBordeFuerte = Color.white.opacity(0.9)
    /// `.85` — bordes de vidrio.
    public static let vidrioBorde = Color.white.opacity(0.85)
    /// `.8` — borde de pastilla + inner-highlights.
    public static let vidrioBordePastilla = Color.white.opacity(0.8)
    /// `.72` — borde de superficie (tiles).
    public static let vidrioBordeSuperficie = Color.white.opacity(0.72)
    /// `.55` — streak especular del dock.
    public static let vidrioStreak = Color.white.opacity(0.55)
    /// `.5` — relleno lente/dial.
    public static let vidrioLente = Color.white.opacity(0.5)
    /// `.45` — relleno pastilla.
    public static let vidrioPastilla = Color.white.opacity(0.45)
    /// `.30` — relleno superficie tile.
    public static let vidrioSuperficie = Color.white.opacity(0.30)
}

// MARK: - Estado de señal (§5.2 SignalOrb · §5.5 CargaBar)

/// El estado semántico compartido por las señales: `ok` habla en verde, `atencion` en ámbar.
/// Cada superficie toma de aquí su anillo, caption, tinte de esfera y status — nunca los
/// re-deriva.
public enum LiquidSignalState: Sendable {
    case ok, atencion

    /// El tono base del estado (tiñe esfera, glow e/2 y gradiente de segmento activo).
    public var tone: Color {
        switch self {
        case .ok: return LiquidColor.verdePrimario
        case .atencion: return LiquidColor.atencion
        }
    }

    /// El anillo de progreso del orbe (`rgba(tono, 0.45)` ok / `0.6` atención).
    public var ring: Color {
        switch self {
        case .ok: return LiquidColor.verdePrimario.opacity(0.45)
        case .atencion: return LiquidColor.atencion.opacity(0.6)
        }
    }

    /// El caption/status del estado («EN TU RANGO» / «EN EQUILIBRIO · 1.03»).
    public var caption: Color {
        switch self {
        case .ok: return LiquidColor.verdeProfundo
        case .atencion: return LiquidColor.atencion
        }
    }

    /// El color del texto de status de CargaBar (verde/primario, no profundo).
    public var status: Color {
        switch self {
        case .ok: return LiquidColor.verdePrimario
        case .atencion: return LiquidColor.atencion
        }
    }
}

// MARK: - Tono de delta (§5.1 MetricTile)

/// Dirección de un delta contra la base personal. `up` = a favor, `down` = en contra,
/// `neutral` = en tu base. El color sale de los semánticos — el caption jamás inventa color.
public enum LiquidDeltaTone: Sendable {
    case up, down, neutral

    public var color: Color {
        switch self {
        case .up: return LiquidColor.positivo
        case .down: return LiquidColor.negativo
        case .neutral: return LiquidColor.tinta500
        }
    }
}

#if DEBUG
#Preview("Liquid · Color") {
    let swatch: (String, Color) -> AnyView = { name, color in
        AnyView(HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 40, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(LiquidColor.tinta10))
            Text(name).font(.system(size: 11)).foregroundStyle(LiquidColor.tinta700)
        })
    }
    return ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            Text("TINTA · PAPEL · VERDE").font(LiquidType.kicker).tracking(LiquidType.kickerTracking)
                .foregroundStyle(LiquidColor.tinta500)
            swatch("tinta/900", LiquidColor.tinta900)
            swatch("tinta/700", LiquidColor.tinta700)
            swatch("tinta/500", LiquidColor.tinta500)
            swatch("verde/primario", LiquidColor.verdePrimario)
            swatch("verde/profundo", LiquidColor.verdeProfundo)
            swatch("verde/aurora", LiquidColor.verdeAurora)
            Text("TONOS DE DATO").font(LiquidType.kicker).tracking(LiquidType.kickerTracking)
                .foregroundStyle(LiquidColor.tinta500)
            swatch("índigo · sueño", LiquidColor.indigo)
            swatch("cian · hrv", LiquidColor.cian)
            swatch("rosa · fc reposo", LiquidColor.rosa)
            swatch("ámbar · esfuerzo/piel", LiquidColor.ambar)
            swatch("teal · pasos", LiquidColor.teal)
            swatch("azul · respiración", LiquidColor.azul)
            swatch("oro · amanecer", LiquidColor.oro)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(LiquidColor.papelGradient)
}
#endif
