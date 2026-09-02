import Foundation
import SwiftUI
import CenitDesign
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Design-token generator (FER-131 handoff · 01)
//
// `Instrumento.swift` is the SINGLE SOURCE OF TRUTH for the «Instrumento diurno» tokens. This
// executable reads its public `InstrumentoTheme.base` roles (plus the computed text-tier tokens
// `positiveText` / `negativeText`) and rewrites the token blocks of the two doc artifacts:
//
//   • docs/design-system/tokens/design-tokens.json  → the `color.instrumento` object
//   • docs/design-system/DESIGN.md                  → the §8.2 color-roles table
//
// so neither can drift from code (the drift this fixes: `dataHrv` was `#2E7D6B` in the docs but
// `#147C8C` in code since FER-206). Run it with `swift run CenitDesignTokens` from this package
// dir after changing any token; CI re-runs it and fails if the committed files differ
// (see .github/workflows/design-tokens.yml). It is intentionally NOT shipped in the app — it only
// builds against `CenitDesign`'s PUBLIC API and does its own sRGB/WCAG math (macOS-only), so the
// package's own surface stays unchanged.

// MARK: sRGB hex + WCAG contrast (self-contained; no internal CenitDesign API)

func srgb(_ c: Color) -> (r: Double, g: Double, b: Double) {
    #if canImport(AppKit)
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
    return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    #else
    return (0, 0, 0)
    #endif
}
func hex(_ c: Color) -> String {
    let p = srgb(c)
    return String(format: "#%02X%02X%02X",
                  Int((p.r * 255).rounded()), Int((p.g * 255).rounded()), Int((p.b * 255).rounded()))
}
/// sRGB alpha component (0…1). NSColor keeps it even after `.usingColorSpace(.sRGB)`.
func alpha(_ c: Color) -> Double {
    #if canImport(AppKit)
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
    return Double(ns.alphaComponent)
    #else
    return 1
    #endif
}
/// Hex for an opaque color, `rgba(r,g,b,a)` for a translucent one (the Liquid vidrio/tinta
/// family is defined as fixed alphas of white/tinta — a bare hex would silently drop the alpha).
func value(_ c: Color) -> String {
    let a = alpha(c)
    if a >= 0.999 { return hex(c) }
    let p = srgb(c)
    return String(format: "rgba(%d,%d,%d,%.2f)",
                  Int((p.r * 255).rounded()), Int((p.g * 255).rounded()), Int((p.b * 255).rounded()), a)
}
func linearize(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func luminance(_ c: Color) -> Double {
    let p = srgb(c)
    return 0.2126 * linearize(p.r) + 0.7152 * linearize(p.g) + 0.0722 * linearize(p.b)
}
func ratio(_ a: Color, _ b: Color) -> Double {
    let la = luminance(a), lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// MARK: The canonical roles, in display order

struct Role { let key: String; let color: Color; let isSurface: Bool; let desc: String }

let t = InstrumentoTheme.base
let paper = t.paper
let roles: [Role] = [
    Role(key: "paper",          color: t.paper,          isSurface: true,  desc: "canvas — warm bone paper (never pure white)"),
    Role(key: "surface",        color: t.surface,        isSurface: true,  desc: "a sparingly-used raised surface; never nested"),
    Role(key: "hairline",       color: t.hairline,       isSurface: true,  desc: "faint warm 1px rule"),
    Role(key: "hairlineStrong", color: t.hairlineStrong, isSurface: true,  desc: "rule on emphasis"),
    Role(key: "paperHi",        color: t.paperHi,        isSurface: true,  desc: "paper-gradient highlight — lighter pool toward top-centre (derived from paper)"),
    Role(key: "paperLo",        color: t.paperLo,        isSurface: true,  desc: "paper-gradient rim — deeper warm edge (derived from paper)"),
    Role(key: "ink",            color: t.ink,            isSurface: false, desc: "primary text & the hero numeral"),
    Role(key: "inkSecondary",   color: t.inkSecondary,   isSurface: false, desc: "supporting copy & labels"),
    Role(key: "inkTertiary",    color: t.inkTertiary,    isSurface: false, desc: "overlines, captions, axis"),
    Role(key: "inkDim",         color: t.inkDim,         isSurface: true,  desc: "no-data cells — the «—» + its glyph; intentionally low-contrast, NOT AA text (derived from inkTertiary→paper)"),
    Role(key: "dataRecovery",   color: t.dataRecovery,   isSurface: false, desc: "recovery datum — color on the numeral (AA-large, ≥24pt)"),
    Role(key: "dataStrain",     color: t.dataStrain,     isSurface: false, desc: "strain datum — color on the numeral (AA-large, ≥24pt)"),
    Role(key: "dataSleep",      color: t.dataSleep,      isSurface: false, desc: "sleep trend hue (FER-147)"),
    Role(key: "dataHrv",        color: t.dataHrv,        isSurface: false, desc: "HRV trend hue — cyan, distinct from the verdict green (FER-206)"),
    Role(key: "dataHeart",      color: t.dataHeart,      isSurface: false, desc: "heart-rate trend hue, shared by HR & resting HR (FER-147)"),
    Role(key: "dataSpO2",       color: t.dataSpO2,       isSurface: false, desc: "blood-oxygen trend hue (FER-147)"),
    Role(key: "dataSteps",      color: t.dataSteps,      isSurface: false, desc: "steps trend hue (FER-147)"),
    Role(key: "verdict",        color: t.verdict,        isSurface: false, desc: "day verdict accent — positive green"),
    Role(key: "warning",        color: t.warning,        isSurface: false, desc: "caution / strained"),
    Role(key: "critical",       color: t.critical,       isSurface: false, desc: "depleted / error — contained brick red"),
    Role(key: "positiveText",   color: t.positiveText,   isSurface: false, desc: "positive delta on <24pt text — darkened verdict to clear text-AA (FER-131 · 02)"),
    Role(key: "negativeText",   color: t.negativeText,   isSurface: false, desc: "negative delta on <24pt text (= critical) (FER-131 · 02)"),
    Role(key: "inkMuted",         color: t.inkMuted,         isSurface: true,  desc: "quietest chrome — inactive tabs, unlit marks; intentionally NOT AA text (FER-708)"),
    Role(key: "patternBlock",     color: t.patternBlock,     isSurface: true,  desc: "«patrón/conexión» block background (FER-708)"),
    Role(key: "rangeBand",        color: t.rangeBand,        isSurface: true,  desc: "personal-range band behind a trend line (FER-708)"),
    Role(key: "rangeMidline",     color: t.rangeMidline,     isSurface: true,  desc: "dotted personal-median line inside the range band (FER-708)"),
    Role(key: "dataSun",          color: t.dataSun,          isSurface: true,  desc: "day/sun arc on the dial seal — context, not a datum (FER-708)"),
    Role(key: "ctaAccent",        color: t.ctaAccent,        isSurface: true,  desc: "accent on the ink CTA bar — only ever on ink, never on paper (FER-708)"),
    Role(key: "moderate",         color: t.moderate,         isSurface: true,  desc: "«moderado» lane fill (FER-708)"),
    Role(key: "dataSleepDeep",    color: t.dataSleepDeep,    isSurface: true,  desc: "deep-sleep stage fill (FER-708)"),
    Role(key: "dataSleepLight",   color: t.dataSleepLight,   isSurface: true,  desc: "light-sleep stage fill (FER-708)"),
    Role(key: "originBand",       color: t.originBand,       isSurface: true,  desc: "data-origin dot — strap/band (= dataRecovery) (FER-708)"),
    Role(key: "originApple",      color: t.originApple,      isSurface: true,  desc: "data-origin dot — Apple Salud (= dataSpO2) (FER-708)"),
    Role(key: "originComputed",   color: t.originComputed,   isSurface: true,  desc: "data-origin dot — computed on-device (= inkMuted) (FER-708)"),
]

func ratioSuffix(_ r: Role) -> String { r.isSurface ? "" : " — \(String(format: "%.1f", ratio(r.color, paper))):1" }
func onPaper(_ r: Role) -> String { r.isSurface ? "—" : "\(String(format: "%.1f", ratio(r.color, paper))):1" }

// MARK: JSON `color.instrumento` block

func jsonBlock() -> String {
    let pad = (roles.map { $0.key.count }.max() ?? 0) + 4   // align the opening brace
    var lines = [
        "\"instrumento\": {",
        "      \"$description\": \"«Instrumento diurno» (FER-131) — the light, warm-paper language; .base daytime anchor (the by-the-hour engine FER-132 varies these roles). GENERATED from Instrumento.swift by `swift run CenitDesignTokens` — do not edit by hand.\",",
    ]
    for (i, r) in roles.enumerated() {
        let keyField = "\"\(r.key)\":".padding(toLength: pad, withPad: " ", startingAt: 0)
        let comma = i == roles.count - 1 ? "" : ","
        lines.append("      \(keyField) { \"$value\": \"\(hex(r.color))\", \"$description\": \"\(r.desc)\(ratioSuffix(r))\" }\(comma)")
    }
    lines.append("    }")
    return lines.joined(separator: "\n")
}

// MARK: DESIGN.md §8.2 table

func designTable() -> String {
    var lines = ["| Role | Hex | On paper | Use |", "|---|---|---|---|"]
    for r in roles {
        lines.append("| `\(r.key)` | `\(hex(r.color))` | \(onPaper(r)) | \(r.desc) |")
    }
    return lines.joined(separator: "\n")
}

// MARK: Palette scale blocks (auditoría jul-2026, H6)
//
// Antes, el generador solo emitía `color.instrumento`; las escalas de `StrandPalette`
// (accent/status/metric/sleep/hrZone/recovery/strain) y `opacity` se mantenían A MANO, y una
// derivó: `sleep.rem` decía `#5BE0C7` en el JSON pero el código dice `#3E9E8C` desde FER-234. Ahora
// estas también salen del código (el código gana), con las descripciones curadas embebidas aquí para
// no perder información. Los arrays de `gradient.*` (que reflejan los mismos stops) siguen a mano —
// no hay deriva ahí y reflejan estas mismas constantes.

struct PEntry { let name: String; let color: Color; let desc: String? }

/// Un bloque de escala de color de Palette, en el formato de una-entrada-por-línea con clave alineada
/// (idéntico a los bloques hechos a mano), con un `$description` de bloque opcional al frente.
func paletteBlock(_ key: String, parentDesc: String?, _ entries: [PEntry]) -> String {
    let names = entries.map(\.name)
    let pad = (names.map { $0.count }.max() ?? 0) + 3   // «"name":» + espacios → alinea la llave
    var lines = ["\"\(key)\": {"]
    if let parentDesc { lines.append("      \"$description\": \"\(parentDesc)\",") }
    for (i, e) in entries.enumerated() {
        let keyField = "\"\(e.name)\":".padding(toLength: pad, withPad: " ", startingAt: 0)
        let comma = i == entries.count - 1 ? "" : ","
        let descPart = e.desc.map { ", \"$description\": \"\($0)\"" } ?? ""
        lines.append("      \(keyField) { \"$value\": \"\(hex(e.color))\"\(descPart) }\(comma)")
    }
    lines.append("    }")
    return lines.joined(separator: "\n")
}

/// The `opacity` object (numbers, not colors): the shared `disabled` value plus the `CenitOpacity`
/// scale added by the auditoría (H4).
func opacityBlock() -> String {
    let entries: [(String, Double, String)] = [
        ("disabled",       StrandPalette.disabledOpacity, "dimmed/disabled sections (= CenitOpacity.dim)"),
        ("tintFill",       CenitOpacity.tintFill,        "chip/badge tint fill (absorbs 0.10–0.12)"),
        ("tintFillStrong", CenitOpacity.tintFillStrong,  "emphasized tint (absorbs 0.14–0.18)"),
        ("strokeSoft",     CenitOpacity.strokeSoft,      "soft tinted stroke (absorbs 0.28–0.40)"),
        ("dim",            CenitOpacity.dim,             "dimmed value (absorbs 0.40–0.52)"),
        ("muted",          CenitOpacity.muted,           "secondary over color (absorbs 0.55–0.70)"),
    ]
    let pad = (entries.map { $0.0.count }.max() ?? 0) + 3
    var lines = ["\"opacity\": {", "    \"$type\": \"number\","]
    for (i, e) in entries.enumerated() {
        let keyField = "\"\(e.0)\":".padding(toLength: pad, withPad: " ", startingAt: 0)
        let comma = i == entries.count - 1 ? "" : ","
        let num = e.1 == e.1.rounded() ? String(format: "%.1f", e.1) : String(e.1)
        lines.append("    \(keyField) { \"$value\": \(num), \"$description\": \"\(e.2)\" }\(comma)")
    }
    lines.append("  }")
    return lines.joined(separator: "\n")
}

let sp = StrandPalette.self
let paletteScales: [(String, String?, [PEntry])] = [
    ("accent", nil, [
        PEntry(name: "default",   color: sp.accent, desc: "health green — chrome, not data"),
        PEntry(name: "focusRing", color: sp.accent, desc: nil),
    ]),
    ("status", nil, [
        PEntry(name: "positive", color: sp.statusPositive, desc: nil),
        PEntry(name: "warning",  color: sp.statusWarning,  desc: nil),
        PEntry(name: "critical", color: sp.statusCritical, desc: "never reused as a recovery color"),
    ]),
    ("metric", nil, [
        PEntry(name: "cyan",   color: sp.metricCyan,   desc: "Apple Health bars"),
        PEntry(name: "purple", color: sp.metricPurple, desc: "HRV / strain-style data"),
        PEntry(name: "amber",  color: sp.metricAmber,  desc: "calories / moderate"),
        PEntry(name: "rose",   color: sp.metricRose,   desc: "risk / high strain / low recovery"),
    ]),
    ("sleep", nil, [
        PEntry(name: "awake", color: sp.sleepAwake, desc: "rose"),
        PEntry(name: "light", color: sp.sleepLight, desc: "periwinkle"),
        PEntry(name: "deep",  color: sp.sleepDeep,  desc: "deep indigo"),
        PEntry(name: "rem",   color: sp.sleepREM,   desc: "muted teal (calmer than the old #5BE0C7 mint — FER-234)"),
    ]),
    ("hrZone", nil, [
        PEntry(name: "z1", color: sp.zone1, desc: nil),
        PEntry(name: "z2", color: sp.zone2, desc: nil),
        PEntry(name: "z3", color: sp.zone3, desc: nil),
        PEntry(name: "z4", color: sp.zone4, desc: nil),
        PEntry(name: "z5", color: sp.zone5, desc: nil),
    ]),
    ("recovery", "Traffic-light recovery scale, sampled by recoveryColor(score 0...100).", [
        PEntry(name: "s000", color: sp.recovery000, desc: "0.00 — depleted, pink-red"),
        PEntry(name: "s030", color: sp.recovery030, desc: "0.30 — low, amber"),
        PEntry(name: "s055", color: sp.recovery055, desc: "0.55 — moderate, gold"),
        PEntry(name: "s078", color: sp.recovery078, desc: "0.78 — primed, health green"),
        PEntry(name: "s100", color: sp.recovery100, desc: "1.00 — peak, bright green"),
    ]),
    ("strain", "Strain ramp (output / heat), sampled by strainColor(strain 0...21).", [
        PEntry(name: "s000", color: sp.strain000, desc: "0.00 — ember / warm gold"),
        PEntry(name: "s033", color: sp.strain033, desc: "0.33 — orange"),
        PEntry(name: "s066", color: sp.strain066, desc: "0.66 — rose-red"),
        PEntry(name: "s100", color: sp.strain100, desc: "1.00 — magenta"),
    ]),
]

// MARK: - Liquid Glass (FER-267 — «catálogo Liquid generado»)
//
// El tope de vocabulario del sistema Liquid: `LiquidColor` (color.liquid), `LiquidSpace` +
// los mixtos de `LiquidLayout` (space.liquid) y `LiquidRadius` (radius.liquid), leídos del
// API público — igual disciplina que `roles`/`paletteScales` arriba, el código gana. Los
// alfas fijos de `#FFFFFF`/tinta (la familia «vidrio») se emiten como `rgba(...)` (ver
// `value(_:)`) para no perder el dato que los define.

struct PEntry2 { let name: String; let color: Color; let desc: String? }

func liquidColorBlock(_ key: String, _ entries: [PEntry2]) -> String {
    let pad = (entries.map { $0.name.count }.max() ?? 0) + 3
    var lines = ["\"\(key)\": {"]
    for (i, e) in entries.enumerated() {
        let keyField = "\"\(e.name)\":".padding(toLength: pad, withPad: " ", startingAt: 0)
        let comma = i == entries.count - 1 ? "" : ","
        let descPart = e.desc.map { ", \"$description\": \"\($0)\"" } ?? ""
        lines.append("      \(keyField) { \"$value\": \"\(value(e.color))\"\(descPart) }\(comma)")
    }
    lines.append("    }")
    return lines.joined(separator: "\n")
}

let lc = LiquidColor.self
/// Los estáticos «hoja» de `LiquidColor` (no las escalas plasta*/ParticulaRGB, que son arrays/
/// tuplas, no un tono único — ver el comentario del propio archivo).
let liquidColorEntries: [PEntry2] = [
    PEntry2(name: "tinta900", color: lc.tinta900, desc: "texto principal, iconos activos"),
    PEntry2(name: "tinta700", color: lc.tinta700, desc: "texto secundario, kickers de fecha"),
    PEntry2(name: "tinta500", color: lc.tinta500, desc: "labels, captions neutros, iconos inactivos"),
    PEntry2(name: "tinta10", color: lc.tinta10, desc: "tracks de anillos, divisores de lista"),
    PEntry2(name: "tinta7", color: lc.tinta7, desc: "segmentos de barra inactivos, chips de día vacíos"),
    PEntry2(name: "papelAlto", color: lc.papelAlto, desc: "inicio del degradado de pantalla"),
    PEntry2(name: "papelBajo", color: lc.papelBajo, desc: "fin del degradado de pantalla"),
    PEntry2(name: "papelDock", color: lc.papelDock, desc: "relleno del vidrio/lente (dock)"),
    PEntry2(name: "papelTarjeta", color: lc.papelTarjeta, desc: "tarjeta de HOJA — blanco puro"),
    PEntry2(name: "fondoAlto", color: lc.fondoAlto, desc: "fondo neutro — «El Tablero»"),
    PEntry2(name: "fondoBajo", color: lc.fondoBajo, desc: "fondo neutro — «El Tablero»"),
    PEntry2(name: "papelMatriz", color: lc.papelMatriz, desc: "papel plano del modo Matriz"),
    PEntry2(name: "verdePrimario", color: lc.verdePrimario, desc: "CTA, énfasis, palabra destacada del hero, pulsos"),
    PEntry2(name: "verdeProfundo", color: lc.verdeProfundo, desc: "deltas positivos, texto quiet"),
    PEntry2(name: "verdeAurora", color: lc.verdeAurora, desc: "solo halos/auroras de fondo (nunca texto)"),
    PEntry2(name: "verdeOrbe", color: lc.verdeOrbe, desc: "orbes drift del fondo de Hoy"),
    PEntry2(name: "verdeBotonAlto", color: lc.verdeBotonAlto, desc: "tope del degradado del botón primary"),
    PEntry2(name: "tintaSobreVerde", color: lc.tintaSobreVerde, desc: "texto sobre el botón primary"),
    PEntry2(name: "indigo", color: lc.indigo, desc: "sueño"),
    PEntry2(name: "cian", color: lc.cian, desc: "HRV"),
    PEntry2(name: "rosa", color: lc.rosa, desc: "FC en reposo"),
    PEntry2(name: "ambar", color: lc.ambar, desc: "esfuerzo, temperatura de piel"),
    PEntry2(name: "teal", color: lc.teal, desc: "pasos"),
    PEntry2(name: "azul", color: lc.azul, desc: "respiración"),
    PEntry2(name: "oro", color: lc.oro, desc: "amanecer / halos cálidos"),
    PEntry2(name: "ambarClaro", color: lc.ambarClaro, desc: "clima de atención"),
    PEntry2(name: "doradoTemp", color: lc.doradoTemp, desc: "identidad de temperatura de piel en Cosmos/Matriz"),
    PEntry2(name: "verdeCarga", color: lc.verdeCarga, desc: "identidad de carga"),
    PEntry2(name: "estresMedio", color: lc.estresMedio, desc: "heatmap de estrés — nivel medio"),
    PEntry2(name: "estresAlto", color: lc.estresAlto, desc: "heatmap de estrés — nivel alto"),
    PEntry2(name: "celdaVacia", color: lc.celdaVacia, desc: "día sin lectura en un mosaico de calendario"),
    PEntry2(name: "celdaVaciaPip", color: lc.celdaVaciaPip, desc: "el mismo hueco a tamaño de pip en leyenda"),
    PEntry2(name: "particulaVerde", color: lc.particulaVerde, desc: "partícula en rango/atención"),
    PEntry2(name: "particulaRoja", color: lc.particulaRoja, desc: "partícula en desgaste"),
    PEntry2(name: "particulaAmbar", color: lc.particulaAmbar, desc: "partícula en atención"),
    PEntry2(name: "particulaNeutra", color: lc.particulaNeutra, desc: "partícula neutra — calibrando"),
    PEntry2(name: "rojoClaro", color: lc.rojoClaro, desc: "rojo claro del clima de alerta"),
    PEntry2(name: "positivo", color: lc.positivo, desc: "deltas a favor"),
    PEntry2(name: "atencion", color: lc.atencion, desc: "fuera de rango"),
    PEntry2(name: "negativo", color: lc.negativo, desc: "deltas en contra"),
    PEntry2(name: "atencionTexto", color: lc.atencionTexto, desc: "atención para texto chico (AA)"),
    PEntry2(name: "vidrioEspecular", color: lc.vidrioEspecular, desc: "highlight especular"),
    PEntry2(name: "vidrioBordeFuerte", color: lc.vidrioBordeFuerte, desc: "borde de esfera / gota"),
    PEntry2(name: "vidrioBorde", color: lc.vidrioBorde, desc: "bordes de vidrio"),
    PEntry2(name: "vidrioBordePastilla", color: lc.vidrioBordePastilla, desc: "borde de pastilla + inner-highlights"),
    PEntry2(name: "vidrioBordeSuperficie", color: lc.vidrioBordeSuperficie, desc: "borde de superficie (tiles)"),
    PEntry2(name: "vidrioStreak", color: lc.vidrioStreak, desc: "streak especular del dock"),
    PEntry2(name: "vidrioLente", color: lc.vidrioLente, desc: "relleno lente/dial"),
    PEntry2(name: "vidrioRealcePastilla", color: lc.vidrioRealcePastilla, desc: "realce especular de la pastilla del selector del dock"),
    PEntry2(name: "vidrioPastilla", color: lc.vidrioPastilla, desc: "relleno pastilla"),
    PEntry2(name: "vidrioSuperficie", color: lc.vidrioSuperficie, desc: "relleno superficie tile"),
    PEntry2(name: "vidrioStep", color: lc.vidrioStep, desc: "relleno de los steppers circulares del enfoque"),
    PEntry2(name: "vidrioCanto", color: lc.vidrioCanto, desc: "canto exterior hairline de un módulo"),
    PEntry2(name: "vidrioAtmosfera", color: lc.vidrioAtmosfera, desc: "relleno del módulo de vidrio sobre la atmósfera"),
    PEntry2(name: "vidrioAtmosferaSolida", color: lc.vidrioAtmosferaSolida, desc: "plan B opaco de la receta de atmósfera"),
]

let ls = LiquidSpace.self
let lr = LiquidRadius.self
/// A `CGFloat` pt value as compact JSON — `4` not `4.0`, `0.5` kept as-is.
func numberValue(_ v: CGFloat) -> String {
    let d = Double(v)
    return d == d.rounded() ? String(Int(d)) : String(d)
}

func numberBlock(_ key: String, _ entries: [(String, CGFloat, String?)]) -> String {
    let pad = (entries.map { $0.0.count }.max() ?? 0) + 3
    var lines = ["\"\(key)\": {"]
    for (i, e) in entries.enumerated() {
        let keyField = "\"\(e.0)\":".padding(toLength: pad, withPad: " ", startingAt: 0)
        let comma = i == entries.count - 1 ? "" : ","
        let descPart = e.2.map { ", \"$description\": \"\($0)\"" } ?? ""
        lines.append("      \(keyField) { \"$value\": \(numberValue(e.1))\(descPart) }\(comma)")
    }
    lines.append("    }")
    return lines.joined(separator: "\n")
}

/// `LiquidSpace.sXXX` (la escala cerrada) + los mixtos de `LiquidLayout` que el handoff pide
/// censar por nombre (`ecosistemaAlto`, `dockBottom`) para que el tope de vocabulario los vea.
let liquidSpaceEntries: [(String, CGFloat, String?)] = [
    ("s025", ls.s025, "micro-gap — rótulo ↔ dato dentro de una columna"),
    ("s050", ls.s050, "gaps de segmentos de barra"),
    ("s075", ls.s075, "respiro exterior de la pastilla táctil"),
    ("s100", ls.s100, nil),
    ("s125", ls.s125, "gap rótulo ↔ ratio / diámetro"),
    ("s150", ls.s150, "gota ↔ label"),
    ("s175", ls.s175, "paso fino entre s150 y s200 (FER-318)"),
    ("s200", ls.s200, "gap del grid de tiles"),
    ("s225", ls.s225, "padding vertical interior de la pastilla táctil"),
    ("s250", ls.s250, "gap entre módulos de «El Tablero»"),
    ("s300", ls.s300, "padding H de tile, separación entre bloques chicos"),
    ("s350", ls.s350, "padding del recibo térmico / screenTop (FER-309)"),
    ("s400", ls.s400, "padding H de pastilla / interior horizontal de módulo"),
    ("s450", ls.s450, "paso entre s400 y s550 (FER-318)"),
    ("s550", ls.s550, "margen horizontal de pantalla (legacy Liquid)"),
    ("s600", ls.s600, "margen horizontal de la pantalla «El Tablero»"),
    ("s700", ls.s700, "gap entre secciones de una hoja/lista"),
    ("s800", ls.s800, nil),
    ("s1400", ls.s1400, "safe-area top (velo de status)"),
    ("ecosistemaAlto", ls.ecosistemaAlto, "alto de la zona del héroe «El Ecosistema»"),
    ("dockBottom", ls.dockBottom, "margen inferior del dock flotante (negativo)"),
    ("chipHorizontal", ls.chipHorizontal, "respiro horizontal de chip/pastilla chica (FER-273)"),
    ("seccionCanto", ls.seccionCanto, "canto de sección — antes/después de un Divider (FER-273)"),
    ("filaRespiro", ls.filaRespiro, "respiro vertical de fila/chip compacto (FER-273)"),
    ("handoff14", ls.handoff14, "padding de tarjetas/controles chicos del handoff (FER-273)"),
    ("handoff44", ls.handoff44, "gap entre bloques de dato gemelos, == mínimo táctil HIG (FER-273)"),
    ("chipCompactoH", LiquidChip.compactoHorizontal, "chip compacto del handoff — horizontal (FER-273)"),
    ("chipCompactoV", LiquidChip.compactoVertical, "chip compacto del handoff — vertical (FER-273)"),
]

let liquidRadiusEntries: [(String, CGFloat, String?)] = [
    ("hairline", lr.hairline, "antialiasing del trazo de 1pt (capilar divisor)"),
    ("chip", lr.chip, "badge chico del handoff (FER-275)"),
    ("insetTarjeta", lr.insetTarjeta, "sub-tarjeta anidada dentro de otra tarjeta"),
    ("control", lr.control, "swatches, chips de día, inputs"),
    ("tile", lr.tile, "esquina del tile de métrica de Hoy (FER-309)"),
    ("tarjeta", lr.tarjeta, "tiles, tarjetas, contenedores de lista"),
    ("modulo", lr.modulo, "módulos de vidrio de «El Tablero»"),
    ("hoja", lr.hoja, "sheets y modales"),
    ("pastilla", lr.pastilla, "botones, dock, barras, badges (Capsule)"),
]

// MARK: - LiquidControl / LiquidOLED / LiquidType (FER-318 — catálogo al día)
//
// Misma disciplina que `liquidColorEntries` / `liquidSpaceEntries`: lista curada del API
// público. `Font` no expone tamaño/peso de forma fiable (SwiftUI), así que tipografía
// lista nombre + metadatos curados (tamaño, peso, ¿escala con Dynamic Type?).

let lctl = LiquidControl.self
let liquidControlEntries: [(String, CGFloat, String?)] = [
    ("hitTarget", lctl.hitTarget, "objetivo táctil mínimo HIG (44 pt)"),
    ("sm", lctl.sm, "chips, filas densas"),
    ("md", lctl.md, "control por defecto (== hitTarget)"),
    ("lg", lctl.lg, "CTAs, controles destacados"),
    ("tileAltura", lctl.tileAltura, "altura única del tile de métrica (FER-309)"),
]

let loled = LiquidOLED.self
let liquidOLEDEntries: [PEntry2] = [
    PEntry2(name: "fondo", color: loled.fondo, desc: "negro puro (OLED apaga el píxel)"),
    PEntry2(name: "superficie", color: loled.superficie, desc: "superficie elevada sobre negro"),
    PEntry2(name: "tinta", color: loled.tinta, desc: "tinta principal sobre negro"),
    PEntry2(name: "tintaSecundaria", color: loled.tintaSecundaria, desc: "tinta secundaria"),
    PEntry2(name: "tintaTerciaria", color: loled.tintaTerciaria, desc: "tinta terciaria / apagada"),
    PEntry2(name: "borde", color: loled.borde, desc: "canto fino sobre negro"),
    PEntry2(name: "bordeFuerte", color: loled.bordeFuerte, desc: "canto fuerte sobre negro"),
    PEntry2(name: "verde", color: loled.verde, desc: "verde de veredicto AA sobre negro"),
    PEntry2(name: "ambar", color: loled.ambar, desc: "ámbar de atención sobre negro"),
    PEntry2(name: "negativo", color: loled.negativo, desc: "rojo de error legible sobre negro"),
    PEntry2(name: "rosa", color: loled.rosa, desc: "rosa de FC sobre negro"),
]

/// Tipografía: `Font` no se introspecciona; metadatos curados del source de `LiquidType`.
struct TypeEntry { let name: String; let size: String; let weight: String; let dynamicType: String }
let liquidTypeEntries: [TypeEntry] = [
    TypeEntry(name: "captionRegular", size: "10.5", weight: "regular", dynamicType: "no"),
    TypeEntry(name: "captionFuerte", size: "10.5", weight: "semibold", dynamicType: "no"),
    TypeEntry(name: "captionNegrita", size: "10.5", weight: "bold", dynamicType: "no"),
    TypeEntry(name: "captionLecturaNegrita", size: "10.5", weight: "bold", dynamicType: "sí (.caption2)"),
    TypeEntry(name: "tituloFilaMedia", size: "13", weight: "medium", dynamicType: "no"),
    TypeEntry(name: "tituloFilaNegrita", size: "13", weight: "bold", dynamicType: "no"),
    TypeEntry(name: "tituloGemelaMedia", size: "15", weight: "medium", dynamicType: "no"),
    TypeEntry(name: "relojCompacto", size: "15 tabular", weight: "regular", dynamicType: "no"),
    TypeEntry(name: "pie", size: ".caption2", weight: "regular", dynamicType: "sí"),
    TypeEntry(name: "cuerpoLista", size: ".subheadline", weight: "regular", dynamicType: "sí"),
    TypeEntry(name: "subtituloFila", size: ".footnote", weight: "regular", dynamicType: "sí"),
    TypeEntry(name: "filaConteoNumero", size: ".caption tabular", weight: "medium", dynamicType: "sí"),
]

// MARK: - Catálogo de componentes (FER-267)
//
// La honestidad es asimétrica a propósito: `rol`/`simbolo` salen del código de arriba (Liquid);
// `archivo`/`cuandoUsarlo`/`cuandoNo` son una tabla CURADA — nadie deriva de un AST qué hace un
// componente o cuándo NO usarlo. `CatalogEntryArchivoExisteTests` cierra el hueco barato (el
// símbolo apunta a un archivo real); la veracidad del resto la cuida el review humano, igual
// que `Role.desc` arriba.

public struct CatalogEntry: Sendable {
    public let rol: String
    public let simbolo: String
    public let archivo: String
    public let cuandoUsarlo: String
    public let cuandoNo: String
}

public let catalogEntries: [CatalogEntry] = [
    // —— Superficie / vidrio ——
    CatalogEntry(rol: "Superficie de vidrio", simbolo: "liquidGlass(_:)",
                 archivo: "LiquidGlass/LiquidGlassRecipes.swift",
                 cuandoUsarlo: "Cualquier tile/tarjeta/pastilla/dock nuevo en pantallas Liquid — ÚNICA puerta al vidrio (blur + fondo + borde + highlight + sombra compuestos).",
                 cuandoNo: "No componer blur/material/sombra a mano; en hub Entrenar preferir `EntrenarModulo`/`EntrenarTile` (ya fijan régimen mosaico)."),
    CatalogEntry(rol: "Módulo mosaico (Entrenar)", simbolo: "EntrenarModulo",
                 archivo: "Entrenar/EntrenarVidrio.swift",
                 cuandoUsarlo: "Contenedor a lo ancho del hub/hojas Entrenar — fija `regimen: .mosaico` por construcción.",
                 cuandoNo: "No en pantallas sobrias (Hoy/detalle); ahí `liquidGlass(tono:regimen: .sobrio)` o receta de forma."),
    CatalogEntry(rol: "Tile mosaico (Entrenar)", simbolo: "EntrenarTile",
                 archivo: "Entrenar/EntrenarVidrio.swift",
                 cuandoUsarlo: "Tesela del grid 2-col del hub Entrenar (marcas, volumen, descanso…) — mosaico + minHeight fijo.",
                 cuandoNo: "No para sub-métricas de una hoja Liquid de detalle (usa `LiquidCajita`); no reinventar tile local."),
    // —— Lecturas / filas / secciones ——
    CatalogEntry(rol: "Cajita de sub-métrica", simbolo: "LiquidCajita",
                 archivo: "LiquidGlass/LiquidCajita.swift",
                 cuandoUsarlo: "Mosaico de lecturas en detalle Liquid (rótulo · valor · pie) vía `LiquidCajita`/`LiquidCajitaGrid`.",
                 cuandoNo: "No es el tile de hub con gota+delta (`LiquidMetricTile` está huérfano); no para filas de lista (`LiquidListRow`)."),
    CatalogEntry(rol: "Fila de lista", simbolo: "LiquidListRow",
                 archivo: "LiquidGlass/LiquidListRow.swift",
                 cuandoUsarlo: "Listas de hoja/detalle Liquid (historial, entradas) con la fila estándar.",
                 cuandoNo: "No para un grid de lecturas (usa `LiquidCajita`); no para check de factores (usa `LiquidChecklistRow`)."),
    CatalogEntry(rol: "Fila check de factores", simbolo: "LiquidChecklistRow",
                 archivo: "LiquidGlass/LiquidChecklistRow.swift",
                 cuandoUsarlo: "Fila presente/ausente de un factor (edad corporal, fitness, fuentes) con tono.",
                 cuandoNo: "No como fila genérica de navegación (usa `LiquidListRow`)."),
    CatalogEntry(rol: "Franja de sección (Liquid)", simbolo: "LiquidFranjaSeccion",
                 archivo: "LiquidGlass/LiquidFranjaSeccion.swift",
                 cuandoUsarlo: "Cabecera a sangre de sección en hojas Liquid de métrica (velo del tono al 4 %).",
                 cuandoNo: "No en pantallas Instrumento aún en papel (usa `InstrumentoSectionBand`); no inventar banda local."),
    // —— Selectores / chrome ——
    CatalogEntry(rol: "Selector de periodo (Liquid)", simbolo: "LiquidRangeSelector",
                 archivo: "LiquidGlass/LiquidRangeSelector.swift",
                 cuandoUsarlo: "Selector de periodo en Cuerpo / hojas Liquid (S·M·3M·…) con tick del tono.",
                 cuandoNo: "No en pantallas Instrumento/entrenamiento que aún usan `SegmentedPillControl`; no reinventar periodo."),
    CatalogEntry(rol: "Control segmentado (Instrumento)", simbolo: "SegmentedPillControl",
                 archivo: "Components.swift",
                 cuandoUsarlo: "Segmentado vivo en pantallas Instrumento/entrenamiento (historial, editors, no-periodo).",
                 cuandoNo: "No como selector de periodo en pantalla ya Liquid (usa `LiquidRangeSelector`)."),
    CatalogEntry(rol: "Chip de selección", simbolo: "LiquidChipSeleccion",
                 archivo: "LiquidGlass/LiquidChipSeleccion.swift",
                 cuandoUsarlo: "Chips de filtro/selección múltiple sobre vidrio.",
                 cuandoNo: "No para periodo Liquid (`LiquidRangeSelector`) ni segmentado Instrumento (`SegmentedPillControl`)."),
    CatalogEntry(rol: "Barra de tabs", simbolo: "LiquidTabBar",
                 archivo: "LiquidGlass/LiquidTabBar.swift",
                 cuandoUsarlo: "La barra de navegación inferior flotante («dock») de la app.",
                 cuandoNo: "No para un segmentado de contenido dentro de una pantalla."),
    CatalogEntry(rol: "Menú «···»", simbolo: "LiquidMenu",
                 archivo: "LiquidGlass/LiquidMenu.swift",
                 cuandoUsarlo: "El menú contextual de un «···» en pantalla Liquid: filas con icono, subtítulo de estado, destructiva al final y un nivel de submenú.",
                 cuandoNo: "No para una acción única (usa un botón); no reinventar el popover a mano."),
    CatalogEntry(rol: "Cabecera de hoja", simbolo: "LiquidSheetHeader",
                 archivo: "LiquidGlass/LiquidSheetHeader.swift",
                 cuandoUsarlo: "El encabezado estándar de cualquier hoja/sheet Liquid (título + cierre).",
                 cuandoNo: "No para el título en pantalla completa (header propio de la pantalla)."),
    CatalogEntry(rol: "Pie de hoja — método", simbolo: "LiquidMetodo",
                 archivo: "LiquidGlass/LiquidSheetFoot.swift",
                 cuandoUsarlo: "El bloque «cómo se calcula» al pie de una hoja de detalle.",
                 cuandoNo: "No para el badge de procedencia del dato (usa `LiquidOrigenChip`, mismo archivo)."),
    CatalogEntry(rol: "Chip de procedencia", simbolo: "LiquidOrigenChip",
                 archivo: "LiquidGlass/LiquidSheetFoot.swift",
                 cuandoUsarlo: "Marcar de dónde vino un dato (banda/Apple Salud/computado) al pie de una hoja Liquid.",
                 cuandoNo: "No como pastilla de estado genérica; en listas/detalle de entreno usa `LiquidOrigenBadge`."),
    CatalogEntry(rol: "Badge de procedencia (Liquid)", simbolo: "LiquidOrigenBadge",
                 archivo: "LiquidGlass/LiquidSheetFoot.swift",
                 cuandoUsarlo: "Pastilla caps de procedencia en historial/detalle de entrenamiento (Apple/Manual/Medido). `tono: nil` = neutro.",
                 cuandoNo: "No en pie de hoja con glifo (usa `LiquidOrigenChip`); no como pastilla de estado (`LiquidStatePill`)."),
    // SourceBadge (Instrumento) retirado en FER-294 B.2 — consumidores migrados a LiquidOrigenBadge.
    // —— Botones / confirmación / toast ——
    CatalogEntry(rol: "Botón pill Liquid", simbolo: "LiquidGlassButton",
                 archivo: "LiquidGlass/LiquidGlassButton.swift",
                 cuandoUsarlo: "Botones pill de pantalla Liquid (primary/glass/quiet/solida) con hit-target 44pt ya resuelto.",
                 cuandoNo: "No para CTA de tinta a lo ancho en flujo Instrumento/Entrenar (usa `CenitCTAButton`); no `.plain` sin press."),
    CatalogEntry(rol: "Botón pastilla sólida", simbolo: "LiquidGlassButton(.solida)",
                 archivo: "LiquidGlass/LiquidGlassButton.swift",
                 cuandoUsarlo: "Acción pill OPACA sobre hoja El Eje (p. ej. «Crear ejercicio» en Biblioteca) — papel sin vidrio-sobre-vidrio.",
                 cuandoNo: "No cuando quieras vidrio translúcido (usa `.glass`); no CTA a lo ancho (usa `CenitCTAButton`); no acción destructiva (`.destructive`)."),
    CatalogEntry(rol: "Campo de búsqueda Liquid", simbolo: "LiquidCampoBusqueda",
                 archivo: "LiquidGlass/LiquidCampoBusqueda.swift",
                 cuandoUsarlo: "Campo de búsqueda con lupa + limpiar sobre `.superficieSolida` (Biblioteca y listas Liquid).",
                 cuandoNo: "No reinventar HStack+TextField a mano; no para campos de métrica teñidos (usa `LiquidCampoMetrica`)."),
    CatalogEntry(rol: "Fila de ejercicio (Biblioteca)", simbolo: "EntrenarFilaEjercicio",
                 archivo: "Entrenar/EntrenarFilaEjercicio.swift",
                 cuandoUsarlo: "Fila del catálogo de ejercicios: miniatura + nombre/meta + récord + chevron/Agregar (FER-289).",
                 cuandoNo: "No para filas de historial de sesión (usa `EntrenarFilaFuerza`/`EntrenarFilaCardio`); no dibujar la fila a mano en la Biblioteca."),
    CatalogEntry(rol: "Chip de herramienta (Entrenar)", simbolo: "EntrenarChipHerramienta",
                 archivo: "Entrenar/EntrenarChipHerramienta.swift",
                 cuandoUsarlo: "Puerta de herramienta ancha (Crear plan / Nueva sección) sobre `.pastillaSolida` — mismo contrato que el viejo `InstrumentoToolChip` (FER-292).",
                 cuandoNo: "No para CTA pill de hoja (`LiquidGlassButton`); no para cápsula outline (`OutlineCapsule`); no reinventar HStack+SF a mano."),
    CatalogEntry(rol: "Fila de ajuste (hoja-herramienta)", simbolo: "EntrenarFilaHerramienta",
                 archivo: "Entrenar/EntrenarFilaHerramienta.swift",
                 cuandoUsarlo: "Fila rótulo + nota/valor + control en hojas Entrenar (Progresión, Descanso) — papel opaco, capilar tinta10.",
                 cuandoNo: "No para filas de navegación (usa `LiquidListRow`); no para filas de catálogo (`EntrenarFilaEjercicio`)."),
    CatalogEntry(rol: "Stepper de ajuste Entrenar", simbolo: "EntrenarStepper",
                 archivo: "Entrenar/EntrenarStepper.swift",
                 cuandoUsarlo: "Control − valor + de hoja-herramienta (incremento, reloj de descanso) — tallas `.fila`/`.hoja`.",
                 cuandoNo: "No para steppers Instrumento de papel (`PaperStepper`/`StepperButton`); el caller formatea el valor."),
    CatalogEntry(rol: "Toggle Liquid", simbolo: "LiquidToggleStyle / .liquid",
                 archivo: "LiquidGlass/LiquidToggleStyle.swift",
                 cuandoUsarlo: "Switch cromo El Eje (tinta900/tinta10/papelTarjeta) en hojas Liquid — `.toggleStyle(.liquid)`.",
                 cuandoNo: "No en pantallas aún Instrumento (usa `.instrumento`); no teñir el track con el color del dato."),
    CatalogEntry(rol: "Título de flujo Liquid", simbolo: "LiquidFlowTitle",
                 archivo: "LiquidGlass/LiquidFlowTitle.swift",
                 cuandoUsarlo: "Cabecera kicker + displayS de pantallas empujadas sin salida propia (Tickets).",
                 cuandoNo: "No cuando ya hay `EntrenarHojaCabecera`; no en pantallas Instrumento (usa `InstrumentoFlowTitle`)."),
    CatalogEntry(rol: "CTA de tinta (barra)", simbolo: "CenitCTAButton",
                 archivo: "CenitCTAButton.swift",
                 cuandoUsarlo: "CTA sólido/outline a lo ancho (o compacto) en flujos Entrenar/Instrumento — una sola barra canónica.",
                 cuandoNo: "No reinventar barra con radius/padding ad-hoc; en chrome Liquid de hoja preferir `LiquidGlassButton`."),
    CatalogEntry(rol: "Atrás / cerrar", simbolo: "BackButton",
                 archivo: "BackButton.swift",
                 cuandoUsarlo: "Disco de salir/atrás en hojas y pantallas Instrumento/Entrenar (`role: .back`/`.close`).",
                 cuandoNo: "No para una acción con nombre en el header (usa `HeaderActionButton`); no SF Symbol suelto."),
    CatalogEntry(rol: "Acción de header", simbolo: "HeaderActionButton",
                 archivo: "HeaderActionButton.swift",
                 cuandoUsarlo: "Cápsula con label (Guardar, Terminar) pareja de `BackButton` en la barra de encabezado.",
                 cuandoNo: "No para salir/cerrar (usa `BackButton`); no botón `.bordered` ad-hoc en ese slot."),
    CatalogEntry(rol: "Confirmación (tarjeta)", simbolo: "ConfirmCard / .instrumentoConfirm",
                 archivo: "ConfirmCard.swift",
                 cuandoUsarlo: "Reemplazo de `.confirmationDialog`: tarjeta de vidrio + scrim; API `.instrumentoConfirm`.",
                 cuandoNo: "No usar `.confirmationDialog`/alert genérico para decisiones con consecuencia; cada acción nombra lo que hace."),
    CatalogEntry(rol: "Diálogo de texto (Liquid)", simbolo: "LiquidInputCard / .liquidInput",
                 archivo: "LiquidGlass/LiquidInputCard.swift",
                 cuandoUsarlo: "Prompt de texto centrado (Nueva/Renombrar carpeta): cristal El Eje + scrim; misma firma que el viejo `.instrumentoInput` (FER-292).",
                 cuandoNo: "No usar `.alert`/`TextField` suelto para nombrar; no para confirmaciones sin campo (usa `.instrumentoConfirm`/`liquidConfirm`)."),
    CatalogEntry(rol: "Toast de error al guardar", simbolo: ".saveErrorToast",
                 archivo: "Cenit/Screens/SaveErrorToast.swift",
                 cuandoUsarlo: "Banner auto-descarte «No se pudo guardar» tras un write fallido (modifier de app).",
                 cuandoNo: "No reinventar banner rojo local; no para confirmaciones (usa `.instrumentoConfirm`)."),
    CatalogEntry(rol: "Bloque patrón (Instrumento)", simbolo: ".patternBlock(_:bar:)",
                 archivo: "SessionInstruments.swift",
                 cuandoUsarlo: "Fondo `patternBlock` + barra lateral de tono para avisos/errores en pantallas Instrumento.",
                 cuandoNo: "No en hojas ya Liquid (usa `LiquidPatternBlock`); no pintar `theme.patternBlock` a mano sin la barra."),
    CatalogEntry(rol: "Bloque patrón (Liquid)", simbolo: "LiquidPatternBlock",
                 archivo: "LiquidGlass/LiquidPatternBlock.swift",
                 cuandoUsarlo: "«Tu patrón» / lectura quieta en hojas Liquid — overline + líneas + barra del tono, sin vidrio.",
                 cuandoNo: "No en pantallas Instrumento (usa `.patternBlock`); no envolverlo en `liquidGlass`."),
    // —— Gráficas ——
    CatalogEntry(rol: "Gráfica de tendencia (Liquid)", simbolo: "LiquidTrendChart",
                 archivo: "LiquidGlass/LiquidTrendChart.swift",
                 cuandoUsarlo: "Series temporales dentro de una pantalla/hoja ya migrada a Liquid Glass.",
                 cuandoNo: "No en pantallas aún en Instrumento (usa `TrendChart`)."),
    CatalogEntry(rol: "Gráfica de tendencia (compartida)", simbolo: "TrendChart",
                 archivo: "TrendChart.swift",
                 cuandoUsarlo: "Serie temporal con hover/crosshair — inventario Instrumento y wrappers.",
                 cuandoNo: "No para una línea inline diminuta (usa `Sparkline`)."),
    CatalogEntry(rol: "Sparkline inline", simbolo: "Sparkline",
                 archivo: "Sparkline.swift",
                 cuandoUsarlo: "Tendencia diminuta dentro de un tile (Hoy / live-HR).",
                 cuandoNo: "No como gráfica principal de una pantalla de detalle (usa `TrendChart`/`LiquidTrendChart`)."),
    CatalogEntry(rol: "Hipnograma (Liquid)", simbolo: "LiquidHipnograma",
                 archivo: "LiquidGlass/LiquidHipnograma.swift",
                 cuandoUsarlo: "Bandas de etapa de sueño de una noche en hoja Liquid.",
                 cuandoNo: "No usar el `Hypnogram` legado (0 call-sites APP); no para otras series categóricas."),
    CatalogEntry(rol: "Calendario 90 días (Liquid)", simbolo: "LiquidCalendario90",
                 archivo: "LiquidGlass/LiquidCalendario90.swift",
                 cuandoUsarlo: "Mosaico de 90 días en hojas Liquid (Stress/Strain/Sleep).",
                 cuandoNo: "No usar `Calendario90`/`YearHeatStrip` del índice viejo (0 call-sites APP)."),
    CatalogEntry(rol: "Encabezado de sección (Liquid)", simbolo: "LiquidSectionHeader",
                 archivo: "LiquidGlass/LiquidSectionHeader.swift",
                 cuandoUsarlo: "Abrir una sección en una pantalla Liquid Glass — kicker + aire, sin banda de fondo (FER-273; adopción en Ola 3).",
                 cuandoNo: "No en pantallas «Instrumento diurno» aún sin migrar (usa `InstrumentoSectionBand`, que sí lleva banda de papel)."),
    CatalogEntry(rol: "Cápsula de acción (Hoja)", simbolo: "HojaCapsulaAccion",
                 archivo: "Entrenar/HojaCapsulaAccion.swift",
                 cuandoUsarlo: "Acción compacta sobre vidrio DENTRO de una hoja de Entrenar que no promete navegación — flecha opcional, apagada por default (FER-280·1c).",
                 cuandoNo: "No para una puerta a otra pantalla/hoja (usa `EntrenarCapsulaPuerta`); no para un CTA de pantalla completa (usa `LiquidGlassButton`/`CenitCTAButton`)."),
    // —— FER-280 · piezas que matan clases (ola 2p) ——
    CatalogEntry(rol: "Cápsula outline de acción", simbolo: "OutlineCapsule",
                 archivo: "OutlineCapsule.swift",
                 cuandoUsarlo: "Acción secundaria en cápsula con `hairlineStrong` ± fill (raise, Start/Stop, filtro, Use, Match…) — sm/md + press.",
                 cuandoNo: "No CTA de tinta a lo ancho (`CenitCTAButton`); no pill Liquid de hoja (`LiquidGlassButton`); no acción de header (`HeaderActionButton`)."),
    CatalogEntry(rol: "Pastilla de estado Liquid", simbolo: "LiquidStatePill",
                 archivo: "LiquidGlass/LiquidStatePill.swift",
                 cuandoUsarlo: "Estado vivo/listo sobre cristal (`.pastillaSolida`) o chip de valencia Δ% — sustituye `statusPill` a mano y chips de signo.",
                 cuandoNo: "No pastilla Instrumento de chrome (`StatePill`); no procedencia (`LiquidOrigenChip`/`LiquidOrigenBadge`); no filtro removible (`LiquidChipSeleccion`)."),
    // —— FER-280 · piezas que matan clases (ola 2q · avisos) ——
    CatalogEntry(rol: "Toast de deshacer", simbolo: "UndoToast",
                 archivo: "LiquidGlass/UndoToast.swift",
                 cuandoUsarlo: "Snack de tinta «X borrado · Deshacer» tras un delete reversible (rutina/carpeta/sesión) — receta de WeeklyPlanEditor.",
                 cuandoNo: "No para error de escritura (usa `.saveErrorToast`); no aviso Liquid de lectura (usa `LiquidAviso`); no confirmación (usa `.instrumentoConfirm`)."),
    CatalogEntry(rol: "Aviso Liquid", simbolo: "LiquidAviso",
                 archivo: "LiquidGlass/LiquidAviso.swift",
                 cuandoUsarlo: "Heads-up / desconexión / nudge en pantalla Liquid — `LiquidPatternBlock` + `liquidTarjetaSeccion` (receta HealthAlertBanner); icono/CTA opcionales.",
                 cuandoNo: "No snack de deshacer (`UndoToast`); no error de escritura (`.saveErrorToast`); no banner Instrumento de Hoy aún sin migrar (`TodayBanner`)."),
]

func catalogoTable() -> String {
    var lines = ["| Rol | Símbolo | Archivo | Cuándo usarlo | Cuándo no |", "|---|---|---|---|---|"]
    for e in catalogEntries {
        lines.append("| \(e.rol) | `\(e.simbolo)` | `\(e.archivo)` | \(e.cuandoUsarlo) | \(e.cuandoNo) |")
    }
    return lines.joined(separator: "\n")
}

func catalogoDoc() -> String {
    """
    # Catálogo Liquid Glass

    <!-- GENERADO por `swift run CenitDesignTokens` desde `Packages/CenitDesign/Sources/CenitDesignTokens/main.swift` — no editar a mano. `rol`/`simbolo`/valores salen del código; `archivo`/`cuándo usarlo`/`cuándo no` son la tabla curada `catalogEntries` de ese mismo archivo. -->

    Diccionario + índice del sistema **Liquid Glass · El Eje** (FER-229), leído directo del API
    público de `CenitDesign` — mismo trato que `color.instrumento` en
    [`tokens/design-tokens.json`](tokens/design-tokens.json): el código gana, este archivo solo
    lo refleja.

    ## Diccionario

    ### Color (`LiquidColor`)

    | Token | Valor | Uso |
    |---|---|---|
    \(liquidColorEntries.map { "| `\($0.name)` | `\(value($0.color))` | \($0.desc ?? "—") |" }.joined(separator: "\n"))

    ### OLED (Watch y Dynamic Island) (`LiquidOLED`)

    | Token | Valor | Uso |
    |---|---|---|
    \(liquidOLEDEntries.map { "| `\($0.name)` | `\(value($0.color))` | \($0.desc ?? "—") |" }.joined(separator: "\n"))

    ### Espaciado (`LiquidSpace` / mixtos de `LiquidLayout`)

    | Token | Valor | Uso |
    |---|---|---|
    \(liquidSpaceEntries.map { "| `\($0.0)` | \(numberValue($0.1))pt | \($0.2 ?? "—") |" }.joined(separator: "\n"))

    ### Controles (`LiquidControl`)

    | Token | Valor | Uso |
    |---|---|---|
    \(liquidControlEntries.map { "| `\($0.0)` | \(numberValue($0.1))pt | \($0.2 ?? "—") |" }.joined(separator: "\n"))

    ### Radios (`LiquidRadius`)

    | Token | Valor | Uso |
    |---|---|---|
    \(liquidRadiusEntries.map { "| `\($0.0)` | \(numberValue($0.1))pt | \($0.2 ?? "—") |" }.joined(separator: "\n"))

    ### Tipografía (`LiquidType` — familia nueva)

    `Font` no se introspecciona desde el generador; nombre + tamaño/peso/Dynamic Type curados
    del source. Solo la familia tipográfica nueva (FER-303/306/310/318).

    | Token | Tamaño | Peso | Dynamic Type |
    |---|---|---|---|
    \(liquidTypeEntries.map { "| `\($0.name)` | \($0.size) | \($0.weight) | \($0.dynamicType) |" }.joined(separator: "\n"))

    ## Índice de componentes

    Rol → símbolo → archivo → cuándo usarlo → cuándo no. `archivo` es relativo a
    `Packages/CenitDesign/Sources/CenitDesign/`, salvo piezas de app (p. ej. `Cenit/Screens/…`)
    que se anotan desde la raíz del repo. Este índice **reemplaza** las listas de componentes
    a mano de `CLAUDE.md`/`CONTRIBUTING.md`/`DESIGN.md`/`LIBRARY.md` — si buscas un componente,
    empieza aquí.

    \(catalogoTable())
    """
}

// MARK: Splicing

/// Replace the brace-balanced JSON object that follows `"<key>":`, preserving the line's leading
/// indentation. String literals are skipped so braces inside descriptions never confuse the scan.
///
/// `after`: some keys (e.g. `liquid`) repeat under different parents (`color.liquid`,
/// `space.liquid`, `radius.liquid`) — pass the parent's own key so the search starts past it,
/// otherwise a plain `range(of:)` would always hit the first occurrence in the file.
func replaceJSONObject(in text: String, key: String, after: String? = nil, with block: String) -> String? {
    let searchStart: String.Index
    if let after {
        guard let afterRange = text.range(of: "\"\(after)\":") else { return nil }
        searchStart = afterRange.upperBound
    } else {
        searchStart = text.startIndex
    }
    guard let keyRange = text.range(of: "\"\(key)\":", range: searchStart..<text.endIndex) else { return nil }
    guard let openBrace = text.range(of: "{", range: keyRange.upperBound..<text.endIndex) else { return nil }
    var depth = 0
    var i = openBrace.lowerBound
    var inString = false
    var escaped = false
    var closeIndex: String.Index?
    while i < text.endIndex {
        let ch = text[i]
        if inString {
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "\"" { inString = false }
        } else {
            if ch == "\"" { inString = true }
            else if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1; if depth == 0 { closeIndex = i; break } }
        }
        i = text.index(after: i)
    }
    guard let close = closeIndex else { return nil }
    var out = text
    out.replaceSubrange(keyRange.lowerBound...close, with: block)
    return out
}

/// Replace the text between `<!-- GENERATED:<tag>:START -->` and `<!-- GENERATED:<tag>:END -->`.
func replaceMarked(in text: String, tag: String, with body: String) -> String? {
    let start = "<!-- GENERATED:\(tag):START -->"
    let end = "<!-- GENERATED:\(tag):END -->"
    guard let s = text.range(of: start), let e = text.range(of: end), s.upperBound <= e.lowerBound else { return nil }
    var out = text
    out.replaceSubrange(s.upperBound..<e.lowerBound, with: "\n" + body + "\n")
    return out
}

// MARK: Run

#if canImport(AppKit)
let cwd = FileManager.default.currentDirectoryPath
let rootArg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : cwd + "/../.."
let root = URL(fileURLWithPath: rootArg).standardizedFileURL
let jsonURL = root.appendingPathComponent("docs/design-system/tokens/design-tokens.json")
let designURL = root.appendingPathComponent("docs/design-system/DESIGN.md")

func fail(_ msg: String) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(1) }

do {
    let json = try String(contentsOf: jsonURL, encoding: .utf8)
    var newJSON = json
    guard let afterInstrumento = replaceJSONObject(in: newJSON, key: "instrumento", with: jsonBlock()) else {
        fail("✗ could not locate the \"instrumento\" object in \(jsonURL.path)")
    }
    newJSON = afterInstrumento
    // Palette scales (H6): each color.* block re-emitted from StrandPalette. `color.recovery`/`color.strain`
    // precede the `gradient.*` ones, so the first-match splice hits the color block.
    for (key, parentDesc, entries) in paletteScales {
        guard let spliced = replaceJSONObject(in: newJSON, key: key, with: paletteBlock(key, parentDesc: parentDesc, entries)) else {
            fail("✗ could not locate the \"\(key)\" object in \(jsonURL.path)")
        }
        newJSON = spliced
    }
    guard let afterOpacity = replaceJSONObject(in: newJSON, key: "opacity", with: opacityBlock()) else {
        fail("✗ could not locate the \"opacity\" object in \(jsonURL.path)")
    }
    newJSON = afterOpacity
    // Liquid Glass (FER-267): color.liquid / space.liquid / radius.liquid. `liquid` repeats
    // three times in the file — `after:` anchors each search past its own parent key.
    guard let afterColorLiquid = replaceJSONObject(in: newJSON, key: "liquid", after: "instrumento",
                                                    with: liquidColorBlock("liquid", liquidColorEntries)) else {
        fail("✗ could not locate the \"color.liquid\" object in \(jsonURL.path)")
    }
    newJSON = afterColorLiquid
    // `after:` ancla en la clave PADRE: `"opacity"` → space.liquid; `"radius"` → radius.liquid.
    // NO usar `after: "space"` para el radio: `"space":` queda ANTES de su propio `"liquid":`,
    // así que el splice reescribía space.liquid con los radios y dejaba radius.liquid vacío.
    guard let afterSpaceLiquid = replaceJSONObject(in: newJSON, key: "liquid", after: "opacity",
                                                    with: numberBlock("liquid", liquidSpaceEntries)) else {
        fail("✗ could not locate the \"space.liquid\" object in \(jsonURL.path)")
    }
    newJSON = afterSpaceLiquid
    guard let afterRadiusLiquid = replaceJSONObject(in: newJSON, key: "liquid", after: "radius",
                                                     with: numberBlock("liquid", liquidRadiusEntries)) else {
        fail("✗ could not locate the \"radius.liquid\" object in \(jsonURL.path)")
    }
    newJSON = afterRadiusLiquid
    if newJSON != json { try newJSON.write(to: jsonURL, atomically: true, encoding: .utf8) }

    let design = try String(contentsOf: designURL, encoding: .utf8)
    guard let newDesign = replaceMarked(in: design, tag: "INSTRUMENTO-COLORS", with: designTable()) else {
        fail("✗ could not find <!-- GENERATED:INSTRUMENTO-COLORS:START/END --> markers in \(designURL.path)")
    }
    if newDesign != design { try newDesign.write(to: designURL, atomically: true, encoding: .utf8) }

    let catalogoURL = root.appendingPathComponent("docs/design-system/CATALOGO.md")
    let newCatalogo = catalogoDoc() + "\n"
    let existingCatalogo = try? String(contentsOf: catalogoURL, encoding: .utf8)
    if existingCatalogo != newCatalogo { try newCatalogo.write(to: catalogoURL, atomically: true, encoding: .utf8) }

    print("✓ Instrumento tokens regenerated from Instrumento.swift (\(roles.count) roles)")
    print("✓ Liquid Glass catálogo regenerated (\(liquidColorEntries.count) colors, \(liquidOLEDEntries.count) oled, \(liquidSpaceEntries.count) space, \(liquidControlEntries.count) control, \(liquidRadiusEntries.count) radius, \(liquidTypeEntries.count) type, \(catalogEntries.count) components)")
    print("  · \(jsonURL.path)")
    print("  · \(designURL.path)")
    print("  · \(catalogoURL.path)")
} catch {
    fail("✗ \(error)")
}
#else
print("CenitDesignTokens generator runs on macOS only")
fatalError("CenitDesignTokens generator runs on macOS only")
#endif
