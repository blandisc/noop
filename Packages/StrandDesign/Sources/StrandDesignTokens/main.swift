import Foundation
import SwiftUI
import StrandDesign
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
// `#147C8C` in code since FER-206). Run it with `swift run StrandDesignTokens` from this package
// dir after changing any token; CI re-runs it and fails if the committed files differ
// (see .github/workflows/design-tokens.yml). It is intentionally NOT shipped in the app — it only
// builds against `StrandDesign`'s PUBLIC API and does its own sRGB/WCAG math (macOS-only), so the
// package's own surface stays unchanged.

// MARK: sRGB hex + WCAG contrast (self-contained; no internal StrandDesign API)

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
        "      \"$description\": \"«Instrumento diurno» (FER-131) — the light, warm-paper language; .base daytime anchor (the by-the-hour engine FER-132 varies these roles). GENERATED from Instrumento.swift by `swift run StrandDesignTokens` — do not edit by hand.\",",
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

/// The `opacity` object (numbers, not colors): the shared `disabled` value plus the `StrandOpacity`
/// scale added by the auditoría (H4).
func opacityBlock() -> String {
    let entries: [(String, Double, String)] = [
        ("disabled",       StrandPalette.disabledOpacity, "dimmed/disabled sections (= StrandOpacity.dim)"),
        ("tintFill",       StrandOpacity.tintFill,        "chip/badge tint fill (absorbs 0.10–0.12)"),
        ("tintFillStrong", StrandOpacity.tintFillStrong,  "emphasized tint (absorbs 0.14–0.18)"),
        ("strokeSoft",     StrandOpacity.strokeSoft,      "soft tinted stroke (absorbs 0.28–0.40)"),
        ("dim",            StrandOpacity.dim,             "dimmed value (absorbs 0.40–0.52)"),
        ("muted",          StrandOpacity.muted,           "secondary over color (absorbs 0.55–0.70)"),
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

// MARK: Splicing

/// Replace the brace-balanced JSON object that follows `"<key>":`, preserving the line's leading
/// indentation. String literals are skipped so braces inside descriptions never confuse the scan.
func replaceJSONObject(in text: String, key: String, with block: String) -> String? {
    guard let keyRange = text.range(of: "\"\(key)\":") else { return nil }
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
    if newJSON != json { try newJSON.write(to: jsonURL, atomically: true, encoding: .utf8) }

    let design = try String(contentsOf: designURL, encoding: .utf8)
    guard let newDesign = replaceMarked(in: design, tag: "INSTRUMENTO-COLORS", with: designTable()) else {
        fail("✗ could not find <!-- GENERATED:INSTRUMENTO-COLORS:START/END --> markers in \(designURL.path)")
    }
    if newDesign != design { try newDesign.write(to: designURL, atomically: true, encoding: .utf8) }

    print("✓ Instrumento tokens regenerated from Instrumento.swift (\(roles.count) roles)")
    print("  · \(jsonURL.path)")
    print("  · \(designURL.path)")
} catch {
    fail("✗ \(error)")
}
