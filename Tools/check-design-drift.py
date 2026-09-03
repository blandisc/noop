#!/usr/bin/env python3
"""Guard against design-system drift in the screens (auditoría jul-2026).

`Packages/CenitDesign` is the single source of visual truth. A screen must not re-introduce a raw
hex, an ad-hoc `.font(.system(size:))`, a literal corner radius, or a magic opacity — each is a token
in the package (see `CenitMetrics`, `StrandFont.glyph`/`.micro`, `InstrumentoCardRadius`, `CenitOpacity`).
This linter fails with concrete `file:line: rule — snippet` lines when it finds one.

Rules (each activated in the PR that finishes its migration — pass `--rules` to opt in incrementally):

    no-hex             `Color(hex:` outside Packages/CenitDesign            (already clean — on by default)
    no-adhoc-font      `.font(.system(size:`                                 (after task 02)
    no-radius-literal  `cornerRadius: <number>` not using a CenitMetrics token (after task 01)
    no-opacity-literal `.opacity(<number>)` not using CenitOpacity/helpers   (after task 03)
    no-emdash-string   em-dash (—) inside a Swift string literal (copy rule)   (FER-878/879; on for Screens+Onboarding)
    no-spacing-literal `.padding(<n>)`, `spacing: <n>`, `lineWidth: <n>`       (FER-258; ratchet over Cenit/Screens…App)
    no-legacy-api      call-site of a retired-generation symbol (Instrumento*/Paper*/…) (FER-263; ratchet)
    no-deprecated-metrics  a retired `CenitMetrics` member (space1/space2/gap/…) — pure prohibition (FER-306)
    no-instrumento-theme   `theme.ink/paper/…` / `StrandFont.*` access outside the Watch/Widget carve-out (FER-306; ratchet)
    no-weight-on-grotesk   `.weight(...)` on a grotesk `LiquidType` token — a silent no-op on `.custom` fonts (FER-308; pure)
    no-iphone-tone-on-oled  an iPhone data tone (`LiquidColor.rosa/negativo/…`) painted in `CenitWatch/` — OLED wants `LiquidOLED.*` (retro FER-309; pure)
    no-capsule-a-mano      `Capsule().fill/stroke/strokeBorder` drawn by hand (same line or the next) — the catalog has OutlineCapsule / HojaCapsulaAccion / LiquidStatePill; data tracks carry `token-exempt(dato)` (FER-338; pure)
    no-confirmation-dialog  a native `.confirmationDialog(` — the catalog has `.liquidConfirm` (FER-338; pure)
    no-native-menu          a native `Menu {` / `Menu(` — the catalog has `.liquidMenu` (FER-338; pure)
    no-native-material      a bare SwiftUI `Material` (`.ultraThinMaterial`, …) outside `LiquidGlassRecipes.swift` — glass is a recipe, `liquidGlass(_:)` (FER-340; pure)
    token-exempt       pseudo-rule: counts the escape hatches themselves        (FER-263; ratchet — an exemption
                       is frozen debt too, so a NEW `token-exempt` fails unless its budget allows it)

Per-line escape: a trailing `// token-exempt: <reason>` silences every rule on that line (geometry of
data — bars, legends, swatches, keypad, Dynamic-Island widget — that legitimately needs a literal).
New exemptions use `// token-exempt(<categoria>): <reason>` where <categoria> is one of
dato · sistema · falta-pieza · optico · paridad · unico (CONTRATO.md) so the ×3 rule is auditable;
the bare legacy form is still matched (the 248 pre-existing ones are grandfathered, not rewritten).

Ratchet: `--baseline <json>` grandfathers the hits a rule already has, per file. A file may keep the
count the baseline records for it; one hit MORE fails. That is how a rule turns on green over a tree
that is only partly migrated (FER-258): the debt stops growing while the sweeps continue. When a file
drops below its allowance the run stays green and prints a note to re-record the baseline (tighten it),
so the number can only go down. `--write-baseline <json>` records the current tree for the rules that
ran, MERGING into the existing file — keys of rules not in `--rules` survive untouched (FER-263).

Usage:
    python3 Tools/check-design-drift.py                       # scan default roots, all rules
    python3 Tools/check-design-drift.py --rules no-hex        # only these rules
    python3 Tools/check-design-drift.py Cenit/Screens/X.swift # scan given files (pre-commit passes staged paths)

Exits non-zero on any hit.
"""
import re, sys, os, json

# Broad default list — used by `no-hex` (workflow invokes it with no explicit roots) and as
# fallback for any rule missing from DEFAULT_ROOTS_BY_RULE. Includes CenitApp (FER-282).
DEFAULT_ROOTS = [
    "Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App",
    "CenitApp", "CenitWidgets", "CenitWatch",
]
DESIGN_PKG = "Packages/CenitDesign"
EXEMPT = re.compile(r"//\s*token-exempt\b")

ALL_RULES = ["no-hex", "no-adhoc-font", "no-radius-literal", "no-opacity-literal", "no-emdash-string", "no-raw-shadow", "no-sheet-glass", "no-spacing-literal", "no-legacy-api", "token-exempt", "no-raw-color", "no-edgeinsets-literal", "no-token-arithmetic", "no-motion-literal", "no-dt-cap-adhoc", "no-deprecated-metrics", "no-instrumento-theme", "no-weight-on-grotesk", "no-iphone-tone-on-oled", "no-capsule-a-mano", "no-confirmation-dialog", "no-native-menu", "no-native-material", "no-raw-contrast"]

# Per-rule default roots — mirrors `.github/workflows/design-lint.yml` exactly (FER-282).
# A bare `python3 Tools/check-design-drift.py --baseline …` (no roots) must not paint red on
# files/roots CI never scans for that rule (e.g. no-spacing-literal over CenitWidgets).
_ROOTS_FONT_RADIUS_OPACITY = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "CenitApp"]
_ROOTS_ANTI_EVASION = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "Cenit/Data", "Cenit/LiveActivity", "Cenit/Media", "CenitApp"]
_ROOTS_SPACING_MOTION = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "CenitApp"]
_ROOTS_DT = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "Cenit/Data", "Cenit/LiveActivity", "Cenit/Media", "CenitWidgets", "CenitWatch", "CenitApp"]
_ROOTS_LEGACY = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "Cenit/Data", "Cenit/LiveActivity", "Cenit/Media", "CenitApp", "CenitWidgets", "CenitWatch"]
_ROOTS_TOKEN_EXEMPT = ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "Cenit/Data", "Cenit/LiveActivity", "Cenit/Media", "Packages/CenitDesign/Sources", "CenitApp"]
_ROOTS_SHEET_GLASS = ["Packages/CenitDesign/Sources", "Cenit", "CenitApp", "CenitShared", "CenitWidgets"]

DEFAULT_ROOTS_BY_RULE = {
    "no-hex": list(DEFAULT_ROOTS),
    "no-adhoc-font": list(_ROOTS_FONT_RADIUS_OPACITY),
    "no-radius-literal": list(_ROOTS_FONT_RADIUS_OPACITY),
    "no-opacity-literal": list(_ROOTS_FONT_RADIUS_OPACITY),
    "no-raw-color": list(_ROOTS_ANTI_EVASION),
    "no-edgeinsets-literal": list(_ROOTS_ANTI_EVASION),
    "no-token-arithmetic": list(_ROOTS_ANTI_EVASION),
    "no-emdash-string": ["Cenit/Screens", "Cenit/Onboarding"],
    "no-raw-shadow": ["Cenit/Screens"],
    "no-spacing-literal": list(_ROOTS_SPACING_MOTION),
    "no-motion-literal": list(_ROOTS_SPACING_MOTION),
    "no-dt-cap-adhoc": list(_ROOTS_DT),
    "no-legacy-api": list(_ROOTS_LEGACY),
    "token-exempt": list(_ROOTS_TOKEN_EXEMPT),
    "no-sheet-glass": list(_ROOTS_SHEET_GLASS),
    "no-deprecated-metrics": list(_ROOTS_LEGACY),
    "no-instrumento-theme": list(_ROOTS_LEGACY),
    "no-weight-on-grotesk": list(_ROOTS_LEGACY),
    "no-iphone-tone-on-oled": ["CenitWatch"],
    "no-capsule-a-mano": list(_ROOTS_SPACING_MOTION),
    "no-confirmation-dialog": list(_ROOTS_SPACING_MOTION),
    "no-native-menu": list(_ROOTS_SPACING_MOTION),
    "no-raw-contrast": ["Cenit/Screens", "Cenit/Onboarding", "Cenit/System", "Cenit/App", "CenitApp", "Packages/CenitDesign/Sources"],
    "no-native-material": list(_ROOTS_SPACING_MOTION) + ["Packages/CenitDesign/Sources"],
}
# no-emdash-string: an em-dash (—, U+2014) inside a user-facing Swift string literal. ADN copy rule
# (FER-878): on-screen copy uses «:», «·» or a comma, never an em-dash. Scoped to STRING LITERALS so the
# thousands of legitimate em-dashes in comments/doc-comments are ignored, and the bare «—» no-data
# placeholder glyph (a string with no letters) is allowed — only em-dashes used as a copy connector
# (a quoted span that also contains a letter) are flagged.
RE_STRING_SPAN = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')
RE_HAS_LETTER = re.compile(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]")


def _emdash_string_hit(line):
    for m in RE_STRING_SPAN.finditer(line):
        content = m.group(1)
        if "—" in content and RE_HAS_LETTER.search(content):
            return True
    return False

# no-hex: any Color(hex: … outside the design package.
RE_HEX = re.compile(r"Color\(hex:")
# no-adhoc-font: a font built from a *literal* point size. Like no-radius-literal / no-opacity-literal,
# it only flags a bare digit — `.font(.system(size: WidgetMetrics.hero))` / `.system(size: M.name)` source
# the size from a design token and pass; `.font(.system(size: 13))` is the magic number it's meant to catch.
RE_FONT = re.compile(r"\.font\(\.system\(size:\s*[0-9]")
# no-radius-literal: cornerRadius: followed by a bare number (a token ref like CenitMetrics.cardRadius,
# radius.value, or M.foo is a name, not a digit, so it's allowed).
RE_RADIUS = re.compile(r"cornerRadius:\s*[0-9]")
# no-opacity-literal: .opacity( followed by a bare number. `.opacity(CenitOpacity.x)`,
# `.opacity(theme.tint(...))`, `.opacity(someVar)` all start with a non-digit and pass.
RE_OPACITY = re.compile(r"\.opacity\(\s*[0-9.]")
# no-raw-shadow: an inline `.shadow(` in a screen. Elevation is a token now (`.strandElevation(_:ink:)`);
# a hand-rolled drop shadow in a screen should either use it or be a documented exception. Deliberate
# non-standard shadows (the thermal receipt, upward-casting sheets, ambient glows) carry `// token-exempt:`.
RE_SHADOW = re.compile(r"\.shadow\(")
# no-sheet-glass: `.liquidGlass(.superficie)` / `.pastilla` en una superficie INTERNA de hoja.
# Es el defecto de las «tablas grises» (FER-29/FER-33): esas recetas muestrean el fondo, y dentro
# de una hoja —que ya es vidrio— el resultado salta de gris a blanco al arrastrarla. Las tarjetas
# internas van en PAPEL OPACO (`.superficieSolida` / `.pastillaSolida`); el vidrio de verdad se
# reserva para la hoja misma (`LiquidSheetFondo`), el dock y el orbe. Nada lo detectaba, y por eso
# se coló tres veces. Una superficie que de verdad quiera vidrio lleva `// token-exempt:` con la razón.
RE_SHEET_GLASS = re.compile(r"\.liquidGlass\(\.(superficie|pastilla)\)")
# no-spacing-literal: the class of defect that ate four deliveries in three days (FER-205/207/208/164)
# and kept coming back because nothing watched the spacing numbers. Flags a bare digit in the three
# places a screen writes distance by hand: `.padding(14)` / `.padding(.top, 14)`, `spacing: 14` (stacks
# and grids) and `lineWidth: 2` (strokes). A token reference — `CenitMetrics.space2`, `LiquidSpace.s400`,
# `M.gap` — is a name, not a digit, so it passes. Real data geometry carries `// token-exempt:`.
RE_SPACING = re.compile(
    r"\.padding\(\s*[0-9]"                    # .padding(14)
    r"|\.padding\(\s*\.[a-zA-Z]+\s*,\s*[0-9]"  # .padding(.top, 14)
    r"|\bspacing:\s*[0-9]"                     # VStack(spacing: 14)
    r"|\blineWidth:\s*[0-9]"                   # .stroke(_, lineWidth: 2)
)

# no-legacy-api: a NEW call-site of a retired visual generation (FER-263, épico FER-261). The symbols
# are the papel-cálido / dark-legacy surface still consumed by the app; each one that reaches 0 in the
# gated roots leaves this list and becomes a plain prohibition. Definitions inside Packages/CenitDesign
# are exempt (same guard as no-hex): the package still IS the implementation while the debt drains.
# CenitWidgets/CenitWatch are NOT gated roots for this rule (FER-219: `InstrumentoTheme` is the
# canonical Live-Activity/watch theme there); CenitShared never imports CenitDesign.
RE_LEGACY_API = re.compile(
    r"\b(InstrumentoTheme|InstrumentoFlowTitle|InstrumentoToolChip|InstrumentoTabHeader"
    r"|PaperStepper|SectionBand|InstrumentoSectionBand|StrandPalette)\b"
    r"|\.instrumentoTheme\("
    # FER-280·1b — el contrabando tipográfico que la auditoría B2 midió fuera del gate:
    # el sistema de tipos Instrumento (130 usos) y sus helpers de composición. `theme.*`
    # queda al censo (regex ambiguo). instrumentoCard tiene 0 usos: prohibición gratis.
    r"|\bInstrumentoType\b"
    r"|\.instrumento(?:Overline|OverlineProminent|Confirm|Hero|Input|Card)\("
)

# FER-276 — reglas anti-evasión del colador del censo (CENSO.md §1). Solo las regex-ables con
# baja tasa de falso positivo; `.frame(width/height:)` decorativo, `.offset` y `Color.clear`
# quedan FUERA a propósito (dato vs chrome es indecidible por regex — los vigila el censo).
# no-raw-color: deriva cromática de sistema que no-hex no ve — Color.white/black/Color(red:) y
# `.foregroundStyle(.white)` fuera de token, sobre el lienzo canónico blanco. 7 hits congelados.
RE_RAW_COLOR = re.compile(
    r"\bColor\.white\b|\bColor\.black\b|\bColor\(red:"
    r"|\.foregroundStyle\(\.white\)"
)
# no-edgeinsets-literal: EdgeInsets con un dígito pelón — el mismo defecto de no-spacing-literal
# con otra API (el regex de spacing no lo ve).
RE_EDGEINSETS = re.compile(r"EdgeInsets\([^)]*:\s*[0-9]")
# no-token-arithmetic: `CenitMetrics.space1 + 2` — un token corregido a mano es un rol que falta
# o deuda disfrazada (CONTRATO.md prohíbe resolverlo minteando roles basura).
RE_TOKEN_ARITH = re.compile(r"\b(?:LiquidSpace|LiquidRadius|CenitMetrics|WidgetMetrics)\.[A-Za-z0-9]+\s*[-+]\s*[0-9]")

# no-motion-literal (FER-269, Fase 3): una curva/duración de animación escrita a mano — el set
# cerrado vive en LiquidMotion (brief/soft/measured, ambient/settle/dismiss y las transiciones por
# rol). Un `.easeInOut(0.3)` o un `.spring(response: 0.4, …)` suelto es el mismo defecto que un
# `padding(14)`: deuda que el trinquete congela. Los ya envueltos por FER-269a pasan (token = nombre).
RE_MOTION = re.compile(r"\.ease(?:In|Out|InOut)\(\s*(?:duration:\s*)?[0-9.]|\.spring\([^)]*[0-9]")
# no-dt-cap-adhoc (FER-269, oráculo de Dynamic Type): la app CAPA Dynamic Type a propósito
# (decisión FER-118) y el cap bendecido es UNO: `.dynamicTypeSize(.accessibility5)` — los 6 usos
# del árbol son exactamente ese. Cualquier otro argumento (un cap más chico, un rango ad-hoc, un
# tamaño fijo) es una restricción de accesibilidad nueva que requiere veredicto del dueño, no un
# default de agente. Cero deuda al estreno: prohibición pura, sin baseline.
RE_DT_CAP = re.compile(r"\.dynamicTypeSize\(\s*(?!\.accessibility5\s*\))")

# no-deprecated-metrics (FER-306, auditoría de tokens 2026-09-02 hallazgo 2): los 8 miembros de
# `CenitMetrics` retirados en FER-287 (1A) ya eran alias de LiquidSpace/LiquidRadius/LiquidControl y
# el gate los contaba como token válido — 335 usos de API retirada en verde. FER-300 los drenó a 0
# en la app iOS; desde aquí es prohibición pura. CenitWatch conserva el carve-out (FER-219).
RE_DEPRECATED_METRICS = re.compile(
    r"\bCenitMetrics\.(?:space1|space2|gap|cardPadding|screenPadding|controlRadius|chipRadius|touchTarget)\b"
)
# no-instrumento-theme (FER-306, hallazgo 1): el acceso `theme.ink` / `theme.paper` / … de
# `InstrumentoTheme` y la tipografía `StrandFont.*` — el idioma visual de la generación anterior —
# que no-legacy-api no ve (solo mira el símbolo `InstrumentoTheme`). Las rampas de DATO
# (`hrZoneRamp`, `muscleLoadRamp`, `muscleLoadColor`, `movementFamilyTint`) y el pass-through
# `theme: theme` a piezas del catálogo quedan fuera a propósito. Ratchet con baseline.
RE_INSTRUMENTO_THEME = re.compile(
    r"\btheme\.(?:ink|inkSecondary|inkTertiary|inkQuaternary|paper|surface|surfaceRaised|hairline|hairlineStrong"
    r"|data[A-Z][A-Za-z]*|verdict|critical|warning|positive|onPaper|accent)\b"
    r"|\bStrandFont\."
)
RE_DATA_RAMP = re.compile(r"hrZoneRamp|muscleLoadRamp|muscleLoadColor|movementFamilyTint|ensureFontsRegistered")

# no-weight-on-grotesk (FER-308, retro de la corrida FER-299): `Font.weight(_:)` NO cambia la cara de una
# fuente `.custom` nombrada por PostScript (SpaceGrotesk-Medium se queda Medium), así que
# `LiquidType.caption.weight(.bold)` es un no-op silencioso. La lista de tokens grotesk se LEE de
# LiquidType.swift (los `static let X = InstrumentoType.grotesk(...)`) para que no se pudra a mano;
# los tokens `.system(` quedan fuera: ahí el peso sí funciona. Prohibición pura (deuda 0 al estreno).
_LIQUID_TYPE_SWIFT = os.path.join(DESIGN_PKG, "Sources", "CenitDesign", "LiquidGlass", "LiquidType.swift")


def _grotesk_tokens():
    try:
        src = open(_LIQUID_TYPE_SWIFT, encoding="utf-8").read()
    except FileNotFoundError:
        return []
    return re.findall(r"static let ([A-Za-z0-9_]+)\s*=\s*InstrumentoType\.grotesk", src)


def _weight_on_grotesk_re():
    toks = _grotesk_tokens()
    if not toks:
        return re.compile(r"(?!x)x")  # never matches: sin catálogo no hay regla
    return re.compile(r"\bLiquidType\.(?:" + "|".join(sorted(toks, key=len, reverse=True)) + r")\s*\.weight\(")


RE_WEIGHT_ON_GROTESK = _weight_on_grotesk_re()


def _font_grotesk_re():
    """`.font(LiquidType.<grotesk>)` — para cazar el escape `.fontWeight(` en la misma línea o la siguiente
    (FER-314: la auditoría 2 midió 7 escapes que `.weight(` no veía)."""
    toks = _grotesk_tokens()
    if not toks:
        return re.compile(r"(?!x)x")
    return re.compile(r"\.font\(\s*LiquidType\.(?:" + "|".join(sorted(toks, key=len, reverse=True)) + r")\s*\)")


RE_FONT_GROTESK = _font_grotesk_re()
RE_FONTWEIGHT = re.compile(r"\.fontWeight\(")

# no-iphone-tone-on-oled (retro FER-309): el QA cazó tres veces tintas del iPhone (`rosa` 4.4:1,
# `negativo` 3.7:1) como texto sobre el negro del Watch. Sobre OLED el texto y el dato pintan con
# `LiquidOLED.*` (calibrado ≥4.5:1, ver `LiquidOLEDContrasteTests`). Solo `CenitWatch/` (en
# `CenitWidgets/` conviven la pantalla bloqueada clara y la isla negra en el mismo archivo).
RE_IPHONE_TONE_ON_OLED = re.compile(r"\bLiquidColor\.(?:rosa|negativo|ambar|atencion|atencionTexto|verdePrimario|verdeProfundo|indigo|cian|azul|oro|teal|tinta900|tinta700|tinta500)\b")

# FER-338 — gate de «pieza reinventada»: el gate revisaba ingredientes (tokens), no recetas. Un chip
# hecho a mano con tokens válidos pasaba; el catálogo ya tiene la pieza. Tres patrones con deuda 0 al
# estreno (prohibición pura). Los tracks de DATO (barra de progreso, rampa) llevan `token-exempt(dato)`
# en la línea del `Capsule()` o en la del modifier. `Capsule(style: .continuous)` cuenta igual
# (Grok lo usó para esquivar la primera versión de la regla, FER-338).
# FER-342: `.background(color, in: Capsule())` y `.clipShape(Capsule())` sobre un fill son la misma cápsula a mano.
# FER-358: `.clipShape(Capsule())` sobre un fondo de color es la misma cápsula a mano (las piezas del catálogo
# viven en el paquete, que esta regla no vigila).
RE_CAPSULE_INLINE = re.compile(r"\bCapsule\([^)]*\)\s*\.(?:fill|stroke|strokeBorder)\(|\bin:\s*Capsule\(|\.clipShape\(\s*Capsule\(")
RE_CAPSULE_ALONE = re.compile(r"\bCapsule\([^)]*\)\s*$")
RE_CAPSULE_MODIFIER = re.compile(r"^\s*\.(?:fill|stroke|strokeBorder)\(")
RE_CONFIRMATION_DIALOG = re.compile(r"\.confirmationDialog\(")
RE_NATIVE_MENU = re.compile(r"(?<![A-Za-z.])Menu\s*(?:\{|\()")
# no-native-material (FER-340, auditoría 6 de principios): el vidrio es una RECETA (`liquidGlass(_:)`,
# LIQUID-GLASS.md); un `.ultraThinMaterial` suelto en un diálogo es vidrio fuera de sistema. La única
# casa legítima del Material es `LiquidGlassRecipes.swift`.
RE_NATIVE_MATERIAL = re.compile(r"\.(?:ultraThin|thin|regular|thick|ultraThick|bar)Material\b")

# no-raw-contrast (A1/FER-345): `OKLab.darkened/lightened(` es algoritmo de contraste solo-para-claro
# (darkened) o su espejo (lightened). El único camino sancionado es el helper mode-aware
# `LiquidColor.contrastTuned`, que vive en LiquidContrast.swift; `tonoCampo` vive en LiquidColor.swift.
# Fuera de esos dos archivos, un uso crudo re-introduce oscurecer-sobre-negro (rompe AA en oscuro).
RE_RAW_CONTRAST = re.compile(r"\bOKLab\.(?:darkened|lightened)\(")

RULE_PATTERNS = {
    "no-hex": RE_HEX,
    "no-adhoc-font": RE_FONT,
    "no-radius-literal": RE_RADIUS,
    "no-opacity-literal": RE_OPACITY,
    "no-raw-shadow": RE_SHADOW,
    "no-sheet-glass": RE_SHEET_GLASS,
    "no-spacing-literal": RE_SPACING,
    "no-legacy-api": RE_LEGACY_API,
    "no-raw-color": RE_RAW_COLOR,
    "no-raw-contrast": RE_RAW_CONTRAST,
    "no-edgeinsets-literal": RE_EDGEINSETS,
    "no-token-arithmetic": RE_TOKEN_ARITH,
    "no-motion-literal": RE_MOTION,
    "no-dt-cap-adhoc": RE_DT_CAP,
    "no-deprecated-metrics": RE_DEPRECATED_METRICS,
    "no-instrumento-theme": RE_INSTRUMENTO_THEME,
    "no-weight-on-grotesk": RE_WEIGHT_ON_GROTESK,
    "no-iphone-tone-on-oled": RE_IPHONE_TONE_ON_OLED,
    "no-capsule-a-mano": RE_CAPSULE_INLINE,
    "no-confirmation-dialog": RE_CONFIRMATION_DIALOG,
    "no-native-menu": RE_NATIVE_MENU,
    "no-native-material": RE_NATIVE_MATERIAL,
}


def iter_swift_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                for f in files:
                    if f.endswith(".swift"):
                        yield os.path.join(root, f)
        elif p.endswith(".swift"):
            yield p


def _strip_line_comments(line):
    """Remove same-line comments so rules match code only (FER-271).

    Deletes every complete `/* … */` span that opens and closes on this line, and everything
    from a `//` that is not inside a string literal. Character scan (no regex): a leading
    `/* x */` must not let the rest of the line escape every rule, and a trailing
    `// InstrumentoTheme` must not count as a legacy call-site.
    """
    out = []
    i = 0
    n = len(line)
    in_string = False
    escape = False
    while i < n:
        c = line[i]
        if in_string:
            out.append(c)
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n:
            nxt = line[i + 1]
            if nxt == "/":
                break
            if nxt == "*":
                end = line.find("*/", i + 2)
                if end == -1:
                    out.append(c)
                    i += 1
                    continue
                i = end + 2
                continue
        out.append(c)
        i += 1
    return "".join(out)


def check(paths, rules):
    hits = []
    for path in iter_swift_files(paths):
        # no-hex only applies OUTSIDE the design package (the package is where hex is allowed).
        norm = path.replace("\\", "/")
        in_design_pkg = DESIGN_PKG in norm
        # Carve-out FER-219 (parcial desde FER-314): CenitWidgets/CenitWatch ya hablan Liquid (DECISIONS
        # 2026-09-03), así que no-legacy-api / no-instrumento-theme / no-deprecated-metrics /
        # no-weight-on-grotesk SÍ los vigilan. Conservan solo las exenciones de geometría fija
        # (raw-color / edgeinsets / arithmetic / motion) por la Live Activity y el watch face.
        in_widget_watch = "CenitWidgets/" in norm or "CenitWatch/" in norm
        try:
            lines = open(path, encoding="utf-8").read().splitlines()
        except FileNotFoundError:
            continue
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            # token-exempt is itself ratcheted debt (FER-263): count the hatch on the ORIGINAL
            # line (the annotation lives in the comment on purpose). A comment-only
            # `// token-exempt:` is an orphan — it silences nothing, but still counts (FER-271).
            if EXEMPT.search(line):
                if "token-exempt" in rules and not in_widget_watch:
                    hits.append((path, i, "token-exempt", stripped[:100]))
                continue
            code = _strip_line_comments(line)
            code_stripped = code.strip()
            if not code_stripped or code_stripped.startswith("*"):
                continue
            for rule in rules:
                if rule == "token-exempt":
                    continue
                if rule in ("no-hex", "no-legacy-api", "no-raw-color", "no-token-arithmetic", "no-deprecated-metrics", "no-instrumento-theme", "no-weight-on-grotesk", "no-iphone-tone-on-oled", "no-capsule-a-mano", "no-confirmation-dialog", "no-native-menu") and in_design_pkg:
                    continue
                if rule == "no-native-material" and norm.endswith("LiquidGlassRecipes.swift"):
                    continue
                if rule == "no-raw-contrast" and (norm.endswith("LiquidContrast.swift") or norm.endswith("LiquidColor.swift") or norm.endswith("Instrumento.swift")):
                    continue   # A1: sancionados (definen contrastTuned/tonoCampo) + Instrumento LEGADO (darkened contra su propio paper fijo, fuera del path dinámico; no se extiende)
                if rule in ("no-raw-color", "no-edgeinsets-literal", "no-token-arithmetic", "no-motion-literal") and in_widget_watch:
                    continue
                if rule == "no-instrumento-theme" and RE_DATA_RAMP.search(code):
                    continue
                if rule == "no-emdash-string":
                    if _emdash_string_hit(code):
                        hits.append((path, i, rule, stripped[:100]))
                    continue
                m = RULE_PATTERNS[rule].search(code)
                if not m and rule == "no-capsule-a-mano" and RE_CAPSULE_ALONE.search(code):
                    nxt_raw = lines[i] if i < len(lines) else ""
                    if RE_CAPSULE_MODIFIER.search(_strip_line_comments(nxt_raw)) and not EXEMPT.search(nxt_raw):
                        m = True
                if not m and rule == "no-weight-on-grotesk" and RE_FONT_GROTESK.search(code):
                    # `.fontWeight(` sobre un grotesk: misma línea, o la siguiente (cadena de modifiers).
                    nxt = _strip_line_comments(lines[i]) if i < len(lines) else ""
                    if RE_FONTWEIGHT.search(code) or RE_FONTWEIGHT.search(nxt):
                        m = True
                if m:
                    hits.append((path, i, rule, stripped[:100]))
    return hits


def _key(path):
    return path.replace("\\", "/").lstrip("./")


def tally(hits):
    """{rule: {file: count}} — the shape the baseline records."""
    out = {}
    for path, _i, rule, _snippet in hits:
        out.setdefault(rule, {})[_key(path)] = out.setdefault(rule, {}).get(_key(path), 0) + 1
    return out


def apply_baseline(hits, baseline, walked=None):
    """Split hits into (over-budget, stale-note). A file keeps the count the baseline allows it;
    the hits above that allowance are what fails. A stale note is only honest for a file this run
    actually WALKED (FER-263): a partial scan (e.g. the Screens-only CI step) must not report
    "fewer" for files that simply were not looked at."""
    allowed = {r: dict(f) for r, f in baseline.items()}
    over = []
    for hit in hits:
        path, _i, rule, _snippet = hit
        budget = allowed.get(rule, {}).get(_key(path), 0)
        if budget > 0:
            allowed[rule][_key(path)] = budget - 1
        else:
            over.append(hit)
    stale = [(rule, f, left) for rule, files in allowed.items() for f, left in files.items()
             if left > 0 and (walked is None or f in walked)]
    return over, stale


def main(argv):
    rules = ALL_RULES
    files = []
    baseline_path = None
    write_baseline = None
    it = iter(argv)
    for arg in it:
        if arg == "--rules":
            rules = next(it).split(",")
        elif arg.startswith("--rules="):
            rules = arg.split("=", 1)[1].split(",")
        elif arg == "--baseline":
            baseline_path = next(it)
        elif arg.startswith("--baseline="):
            baseline_path = arg.split("=", 1)[1]
        elif arg == "--write-baseline":
            write_baseline = next(it)
        elif arg.startswith("--write-baseline="):
            write_baseline = arg.split("=", 1)[1]
        else:
            files.append(arg)
    unknown = [r for r in rules if r not in ALL_RULES]
    if unknown:
        print(f"unknown rule(s): {', '.join(unknown)} (known: {', '.join(ALL_RULES)})")
        return 2
    # Explicit CLI roots (CI per-step, pre-commit paths) apply to every requested rule —
    # same as before. With no roots, group by DEFAULT_ROOTS_BY_RULE so a bare local run
    # matches the workflow matrix (FER-282).
    if files:
        root_groups = [(files, rules)]
        roots_label = files
    else:
        grouped = {}
        for rule in rules:
            key = tuple(DEFAULT_ROOTS_BY_RULE.get(rule, DEFAULT_ROOTS))
            grouped.setdefault(key, []).append(rule)
        root_groups = [(list(roots), group_rules) for roots, group_rules in grouped.items()]
        roots_label = sorted({r for roots, _ in root_groups for r in roots})
    hits = []
    walked = set()
    for group_roots, group_rules in root_groups:
        hits.extend(check(group_roots, group_rules))
        walked |= {_key(p) for p in iter_swift_files(group_roots)}
    if write_baseline:
        # Merge-write (FER-263), per FILE and not just per rule: a partial scan re-records only the
        # files it actually walked; budgets of un-walked files survive, deleted files drop out, and a
        # walked file that came back clean drops its key. A corrupt JSON is refused, never clobbered.
        merged = {}
        if os.path.exists(write_baseline):
            try:
                merged = json.load(open(write_baseline, encoding="utf-8"))
            except json.JSONDecodeError as e:
                print(f"refusing to write: {write_baseline} is not valid JSON ({e}) — fix it first")
                return 2
        fresh = tally(hits)
        for rule in rules:
            kept = {f: c for f, c in merged.get(rule, {}).items()
                    if f not in walked and os.path.exists(f)}
            kept.update(fresh.get(rule, {}))
            if kept:
                merged[rule] = kept
            else:
                merged.pop(rule, None)  # a rule with no debt left drops its key
        with open(write_baseline, "w", encoding="utf-8") as fh:
            json.dump(merged, fh, indent=2, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
        print(f"📝 baseline recorded in {write_baseline} ({len(hits)} grandfathered hits for {', '.join(rules)})")
        return 0
    stale = []
    if baseline_path:
        try:
            baseline = json.load(open(baseline_path, encoding="utf-8"))
        except FileNotFoundError:
            print(f"baseline not found: {baseline_path}")
            return 2
        hits, stale = apply_baseline(hits, {r: v for r, v in baseline.items() if r in rules}, walked)
    if hits:
        # The remedy depends on the rule (FER-263): suggesting a token for a legacy call-site, or an
        # exemption for an over-budget exemption, would prescribe exactly the wrong medicine.
        rules_hit = {r for _p, _i, r, _s in hits}
        print("❌ design-system drift:")
        if rules_hit - {"no-legacy-api", "token-exempt"}:
            print("   → promote the value to a CenitDesign token, "
                  "or annotate the line with `// token-exempt(<categoria>): <reason>`")
        if "no-legacy-api" in rules_hit:
            print("   → no-legacy-api: API de una generación retirada — "
                  "la pieza vigente está en docs/design-system/CATALOGO.md")
        if "token-exempt" in rules_hit:
            print("   → token-exempt: una exención nueva es deuda congelada — "
                  "el alta legal va por carve-out o issue dedicado (docs/design-system/CONTRATO.md)")
        for path, i, rule, snippet in hits:
            print(f"   {path}:{i}: {rule} — {snippet}")
        if baseline_path:
            print(f"   (these are ABOVE the debt {baseline_path} grandfathers — the baseline never grows)")
        return 1
    print(f"✅ no design drift ({', '.join(rules)}) in {', '.join(roots_label)}")
    for rule, f, left in sorted(stale):
        print(f"   ↓ {f}: {left} fewer {rule} — re-record with --write-baseline {baseline_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
