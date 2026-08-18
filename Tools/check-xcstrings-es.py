#!/usr/bin/env python3
"""Dos guardas sobre el catálogo de strings del app. Ambas fallan el CI (`i18n-guard`).

1. **missing-es** — una clave del catálogo sin traducción `es`.
   La auditoría de Hoy (FER-audit) encontró strings en inglés que veía un usuario es-MX
   («Getting to know you», «Unloading»…): no había ningún gate para «falta es». Este lo cierra
   sin exigir traducir las 129 heredadas de golpe — usa una línea base (`Tools/i18n-es-baseline.txt`)
   y solo falla sobre las que se agreguen de ahora en adelante. Para bajar la base: traduce y
   quita su clave del archivo.

2. **missing-key** — una clave que el CÓDIGO usa y que NO existe en el catálogo (FER-123).
   El chequeo 1 tenía un falso negativo estructural: solo itera las claves que YA están en el
   catálogo. Una clave nueva (`String(localized: "prep.titulo", defaultValue: "Preparation")`)
   que nunca se agregó al catálogo es invisible para él —no está, luego no se itera, luego pasa
   en verde—. Y ese es justo el error más común al agregar copy: en FER-119 entraron 6 strings
   nuevos sin catálogo y el gate quedó verde; los cazó a mano el verificador independiente.
   Este chequeo va en la dirección contraria: extrae del Swift las claves que se usan y falla si
   alguna no está en su catálogo. Su línea base es `Tools/i18n-keys-baseline.txt`.

   (`Tools/find-dead-strings.py` recorre el mismo eje al revés: claves del catálogo que el código
   ya no usa. Aquel decide qué sobra; este, qué falta.)

Recordatorio de la regla dura del repo: una clave nueva va SIEMPRE bajo la llave `es`, nunca bajo
`es-MX` — una clave es-MX secuestra el idioma y tira el app entero a inglés.
"""
import json, sys, os, re, glob

HERE = os.path.dirname(os.path.abspath(__file__))
CAT = "Cenit/Resources/Localizable.xcstrings"
BASELINE = os.path.join(HERE, "i18n-es-baseline.txt")
KEYS_BASELINE = os.path.join(HERE, "i18n-keys-baseline.txt")

# ---------------------------------------------------------------------------- 1. missing-es

def missing_es():
    strings = json.load(open(CAT, encoding="utf-8")).get("strings", {})
    out = set()
    for key, entry in strings.items():
        # una clave vacía "" no necesita traducción; el resto sí.
        if key.strip() == "": continue   # claves de formato/espaciado no son copy
        es = entry.get("localizations", {}).get("es", {}).get("stringUnit", {}).get("value")
        if not es:
            out.add(key)
    return out

# ---------------------------------------------------------------------------- 2. missing-key

# Cada target embebido tiene SU catálogo, y `String(localized:)`/`Text(_:)` resuelven contra el
# bundle principal de quien los hospeda. Por eso una clave del widget no se busca en el catálogo
# del app: se buscaría siempre en vano.
CATALOGS = {
    "app":     "Cenit/Resources/Localizable.xcstrings",
    "widgets": "CenitWidgets/Resources/Localizable.xcstrings",
    "watch":   "CenitWatch/Resources/Localizable.xcstrings",
}
# El código compartido (CenitShared, Packages) se compila DENTRO de varios targets, así que su
# clave puede vivir legítimamente en cualquiera de los tres catálogos: ahí se acepta la unión.
SCOPES = [
    ("CenitWidgets", ("widgets",)),
    ("CenitWatch",   ("watch",)),
    ("CenitShared",  ("app", "widgets", "watch")),
    ("Packages",     ("app", "widgets", "watch")),
    ("CenitApp",     ("app",)),
    ("Cenit",        ("app",)),
]
SKIP_PATH = re.compile(r"/\.build/|/Tests/|/Preview Content/")

# Lo que vive tras `#if DEBUG` o dentro de un `#Preview` no llega al usuario (mismo recorte que
# `check-hardcoded-strings.py`), conservando los saltos de línea para no mover los números.
PREVIEW = re.compile(r"#if DEBUG.*?#endif|#Preview\([^)]*\)\s*\{.*?\n\}", re.S)

# Un literal de una línea, seguido de `,` o `)`. El lookahead es la defensa contra el falso
# positivo clásico: `Text(" · " + otro)` NO localiza nada (es el init de String, no el de
# LocalizedStringKey), y sin él lo reportaríamos como clave faltante.
LIT = r'"((?:[^"\\\n]|\\.)*)"\s*(?=[,)])'
PATTERNS = [
    re.compile(r'String\(\s*localized:\s*' + LIT + r'\s*,\s*defaultValue:'),  # la clave es el 1er literal
    re.compile(r'String\(\s*localized:\s*' + LIT),                            # la clave ES el texto
    re.compile(r'\bText\(\s*' + LIT),
    re.compile(r'\bLocalizedStringKey\(\s*' + LIT),
]

_ESC = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}
_UNI = re.compile(r"\\u\{([0-9A-Fa-f]+)\}")

def unescape(lit):
    """Del literal como se escribe en Swift al texto que Xcode guarda como clave."""
    lit = _UNI.sub(lambda m: chr(int(m.group(1), 16)), lit)
    out, i = [], 0
    while i < len(lit):
        if lit[i] == "\\" and i + 1 < len(lit):
            out.append(_ESC.get(lit[i + 1], lit[i + 1])); i += 2
        else:
            out.append(lit[i]); i += 1
    return "".join(out)

def extract(src):
    """{clave: línea} de cada clave que un archivo Swift usa. Aquí vive TODA la heurística
    (y `--self-test` la clava contra una tabla de casos, para que nadie la deje ciega sin notarlo)."""
    src = PREVIEW.sub(lambda m: "\n" * m.group(0).count("\n"), src)
    # Las líneas de comentario (`//`, `///`) se vacían, no se borran: los números siguen ciertos.
    src = "\n".join("" if l.lstrip().startswith("//") else l for l in src.splitlines())
    out, seen = {}, set()
    for pat in PATTERNS:
        for m in pat.finditer(src):
            if m.start() in seen: continue     # `defaultValue:` gana sobre el patrón corto
            seen.add(m.start())
            raw = m.group(1)
            # Un literal interpolado no se puede resolver estáticamente (la clave real lleva
            # `%@`/`%lld`): fuera. Igual el espaciado puro, que no es copy.
            if "\\(" in raw: continue
            key = unescape(raw)
            if not key.strip(): continue
            out.setdefault(key, src.count("\n", 0, m.start()) + 1)
    return out

def used_keys():
    """{clave: {cats, sites}} de cada clave que el Swift usa, con el catálogo donde puede vivir."""
    found = {}
    for root, cats in SCOPES:
        for path in sorted(glob.glob(f"{root}/**/*.swift", recursive=True)):
            if SKIP_PATH.search("/" + path): continue
            for key, line in extract(open(path, encoding="utf-8").read()).items():
                found.setdefault(key, {"cats": set(), "sites": []})
                found[key]["cats"].update(cats)
                found[key]["sites"].append(f"{path}:{line}")
    return found

def missing_keys():
    catalogs = {name: set(json.load(open(p, encoding="utf-8")).get("strings", {}))
                for name, p in CATALOGS.items() if os.path.exists(p)}
    out = {}
    for key, info in used_keys().items():
        if any(key in catalogs.get(c, set()) for c in info["cats"]): continue
        out[key] = info["sites"]
    return out

# ---------------------------------------------------------------------------- main

def read_baseline(path):
    if not os.path.exists(path): return set()
    return {l.rstrip("\n") for l in open(path, encoding="utf-8")
            if l.strip() and not l.startswith("#")}

def check_es():
    missing = missing_es()
    base = read_baseline(BASELINE)
    nuevas = sorted(missing - base)
    if nuevas:
        print(f"❌ {len(nuevas)} clave(s) NUEVA(s) sin traducción es-MX (agrégalas al catálogo):")
        print("\n".join(f"  {k!r}" for k in nuevas[:40]))
        return 1
    # Aviso amable si la base bajó (para poder recortarla).
    resueltas = base - missing
    if resueltas:
        print(f"ℹ️  {len(resueltas)} de la base ya tienen es — quítalas de i18n-es-baseline.txt.")
    print(f"✅ sin claves nuevas sin es ({len(missing)} heredadas en la base)")
    return 0

def check_keys():
    missing = missing_keys()
    base = read_baseline(KEYS_BASELINE)
    # La línea base se escribe con `repr()` para que un salto de línea o un espacio al final
    # sean visibles en el archivo (y en el diff) en vez de perderse.
    nuevas = sorted(k for k in missing if repr(k) not in base)
    if nuevas:
        print(f"❌ {len(nuevas)} clave(s) usada(s) en el código que NO están en el catálogo.")
        print("   Agrégalas a Cenit/Resources/Localizable.xcstrings con su valor `es`")
        print("   (SIEMPRE bajo la llave «es», nunca «es-MX»), o —si de verdad no se traduce—")
        print("   añade su repr a Tools/i18n-keys-baseline.txt con una razón.")
        for k in nuevas[:40]:
            print(f"  {missing[k][0]}\n      {k!r}")
        if len(nuevas) > 40: print(f"  … y {len(nuevas) - 40} más")
        return 1
    resueltas = base - {repr(k) for k in missing}
    if resueltas:
        print(f"ℹ️  {len(resueltas)} de la base de claves ya no falta(n) — quítalas de i18n-keys-baseline.txt.")
    print(f"✅ toda clave usada existe en su catálogo ({len(missing)} excepciones en la base)")
    return 0

# ---------------------------------------------------------------------------- --self-test

# Lo que el extractor DEBE ver y lo que DEBE ignorar. La primera mitad son los seis strings que
# FER-119 metió sin catálogo; la segunda, cada falso positivo que costó trabajo descartar.
CASES = [
    (r'String(localized: "prep.titulo", defaultValue: "Preparation")', {"prep.titulo"}),
    (r'String(localized: "Not enough signal")', {"Not enough signal"}),
    (r'Text("Preparation").font(InstrumentoType.grotesk(12))', {"Preparation"}),
    (r'LocalizedStringKey("hero.title.full")', {"hero.title.full"}),
    (r'String(' + "\n" + r'    localized: "multi.linea",' + "\n" + r'    defaultValue: "x")', {"multi.linea"}),
    (r'Text("linea\nrota")', {"linea\nrota"}),                        # escapes resueltos…
    (r'Text("punto\u{00B7}medio")', {"punto\u00b7medio"}),            # …también los unicode
    (r'String(localized: "Confidence: \(n) of \(t) nights")', set()), # interpolado: irresoluble
    (r'Text(" \u{00B7} " + String(localized: "x"))', {"x"}),           # la concatenación NO localiza
    (r'Text(verbatim: "crudo")', set()),
    (r'// Text("comentado")', set()),
    ("#if DEBUG\nText(\"solo debug\")\n#endif", set()),
    (r'Text("")', set()),
    (r'Text(titulo)', set()),
]

def self_test():
    malos = [(src, esperado, set(extract(src)))
             for src, esperado in CASES if set(extract(src)) != esperado]
    for src, esperado, real in malos:
        print(f"❌ {src!r}\n   esperaba {esperado!r}\n   obtuvo   {real!r}")
    if malos:
        print(f"❌ self-test: {len(malos)}/{len(CASES)} caso(s) del extractor fallaron.")
        return 1
    print(f"✅ self-test: {len(CASES)} casos del extractor OK")
    return 0

if "--self-test" in sys.argv:
    sys.exit(self_test())
sys.exit(check_es() | check_keys())
