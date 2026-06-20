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
    Role(key: "ink",            color: t.ink,            isSurface: false, desc: "primary text & the hero numeral"),
    Role(key: "inkSecondary",   color: t.inkSecondary,   isSurface: false, desc: "supporting copy & labels"),
    Role(key: "inkTertiary",    color: t.inkTertiary,    isSurface: false, desc: "overlines, captions, axis"),
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
    guard let newJSON = replaceJSONObject(in: json, key: "instrumento", with: jsonBlock()) else {
        fail("✗ could not locate the \"instrumento\" object in \(jsonURL.path)")
    }
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
