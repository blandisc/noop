#!/usr/bin/env python3
"""Verde local = verde CI, verificable (FER-265, épico FER-261).

Las tres patas del linter de diseño — el hook pre-commit, `Tools/verify.sh` y
`.github/workflows/design-lint.yml` — deben correr las mismas reglas sobre las mismas raíces, o
declarar la divergencia. Antes esto era una esperanza (emdash/shadow/sheet-glass corrían en CI y no
en local; un agente se creía verde y el PR reventaba). Ahora es un check: este script contrasta la
REALIDAD (parsea las invocaciones de `check-design-drift.py` en los tres archivos) contra lo
DECLARADO (el bloque `gate-matrix` de docs/design-system/CONTRATO.md) y falla si divergen.

Falla si:
  - una regla de ALL_RULES del linter no tiene fila en la matriz (una regla nueva no puede nacer
    sin declararse);
  - una invocación real usa una regla que la matriz no declara para esa pata;
  - una regla de trinquete (tree+baseline) falta en alguna pata, o sus raíces literales no son
    EXACTAMENTE las declaradas;
  - cualquier `--baseline` apunta a otra ruta que la canónica (retargetear el flag a un JSON gordo
    esquivaría el job de monotonía — review Grok de FER-264, hallazgo #1).

Convención que este script hace cumplir: toda invocación va en la forma canónica
`python3 [<ruta>/]check-design-drift.py --rules <r1,r2> [--baseline <json>] <paths…>`,
con continuaciones `\\` permitidas (se normalizan antes de parsear).

Usage: check-gate-parity.py [--repo <root>]   (exit 0 = paridad; 1 = divergencia; 2 = error)
"""
import ast
import json
import os
import re
import sys

LEGS = {
    "pre-commit": "Tools/git-hooks/pre-commit",
    "verify-quick": "Tools/verify.sh",
    "design-lint": ".github/workflows/design-lint.yml",
}
LINTER = "Tools/check-design-drift.py"
CONTRACT = "docs/design-system/CONTRATO.md"
RE_MATRIX = re.compile(r"<!-- gate-matrix:begin -->\s*```json\s*(.*?)```\s*<!-- gate-matrix:end -->", re.S)
RE_INVOKE = re.compile(r"check-design-drift\.py(?P<args>[^\n|;]*)")
RE_ALL_RULES = re.compile(r"^ALL_RULES\s*=\s*(\[.*?\])", re.M | re.S)


def _read(root, rel):
    try:
        return open(os.path.join(root, rel), encoding="utf-8").read()
    except FileNotFoundError:
        return None


def parse_matrix(text):
    m = RE_MATRIX.search(text)
    if not m:
        return None
    return json.loads(m.group(1))


def parse_invocations(text):
    """[(rules, baseline_or_None, literal_paths, has_var_paths)] por archivo, con `\\`-continuaciones unidas."""
    text = re.sub(r"\\\s*\n", " ", text)
    out = []
    for m in RE_INVOKE.finditer(text):
        args = m.group("args")
        # la invocación termina donde empieza la plomería del shell: `) || fail=1`, `|| ok=1`, `>`…
        args = re.split(r"\)|\|\||&&|>", args)[0]
        toks = args.split()
        rules, baseline, paths, has_var = [], None, [], False
        it = iter(range(len(toks)))
        i = 0
        while i < len(toks):
            t = toks[i]
            if t == "--rules" and i + 1 < len(toks):
                rules = toks[i + 1].split(",")
                i += 2
            elif t == "--baseline" and i + 1 < len(toks):
                baseline = toks[i + 1]
                i += 2
            elif t.startswith("--"):
                i += 2 if t in ("--write-baseline",) else 1
            elif t in (")", "||", "&&"):
                i += 1
            else:
                if "$" in t or t.startswith('"'):
                    has_var = True
                else:
                    paths.append(t)
                i += 1
        if rules:
            out.append((rules, baseline, paths, has_var))
    return out


def resolve_roots(matrix, spec):
    """'tree:spacing+baseline' → (roots, needs_baseline); 'tree:Cenit/Screens Cenit/Onboarding' → literal."""
    body = spec.split(":", 1)[1]
    needs_baseline = body.endswith("+baseline")
    if needs_baseline:
        body = body[: -len("+baseline")]
    roots = matrix["tree_roots"].get(body)
    if roots is None:
        roots = body.split()
    return roots, needs_baseline


def check(root):
    problems = []
    contract = _read(root, CONTRACT)
    linter = _read(root, LINTER)
    if contract is None or linter is None:
        return [f"falta {CONTRACT if contract is None else LINTER}"]
    matrix = parse_matrix(contract)
    if matrix is None:
        return [f"{CONTRACT} no tiene bloque gate-matrix parseable"]
    mrules = matrix["rules"]
    canonical = matrix["baseline_path"]

    m = RE_ALL_RULES.search(linter)
    all_rules = ast.literal_eval(m.group(1)) if m else []
    for r in all_rules:
        if r not in mrules:
            problems.append(f"regla `{r}` existe en ALL_RULES del linter y NO tiene fila en la matriz")

    for leg, rel in LEGS.items():
        text = _read(root, rel)
        if text is None:
            problems.append(f"falta la pata {leg} ({rel})")
            continue
        found = {}
        for rules, baseline, paths, has_var in parse_invocations(text):
            for r in rules:
                if r not in mrules:
                    problems.append(f"{leg}: invoca `{r}`, que la matriz no declara")
                found.setdefault(r, []).append((baseline, paths, has_var))
            if baseline and baseline != canonical:
                problems.append(f"{leg}: --baseline apunta a `{baseline}` (canónico: `{canonical}`)")
        for r, spec_by_leg in mrules.items():
            spec = spec_by_leg.get(leg)
            if not spec or spec == "-":
                continue
            if r not in found:
                problems.append(f"{leg}: la matriz declara `{r}` y ninguna invocación lo corre")
                continue
            if spec.startswith("tree"):
                if spec == "tree-default":
                    if not any(not paths and not has_var for _b, paths, has_var in found[r]):
                        problems.append(f"{leg}: `{r}` declarado tree-default pero toda invocación pasa paths")
                    continue
                roots, needs_baseline = resolve_roots(matrix, spec)
                ok = False
                for baseline, paths, has_var in found[r]:
                    if has_var:
                        continue
                    if paths == roots and (baseline == canonical) == needs_baseline:
                        ok = True
                if not ok:
                    problems.append(
                        f"{leg}: `{r}` declarado `{spec}` pero ninguna invocación literal coincide "
                        f"(esperaba raíces {roots}{' + --baseline canónico' if needs_baseline else ''})")
    return problems


def main(argv):
    root = "."
    it = iter(argv)
    for a in it:
        if a == "--repo":
            root = next(it, ".")
    problems = check(root)
    if problems:
        print("❌ paridad de gates rota — la matriz de CONTRATO.md y las patas divergen:")
        for p in problems:
            print(f"   · {p}")
        return 1
    print("✅ paridad de gates: las tres patas coinciden con la matriz de CONTRATO.md")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
