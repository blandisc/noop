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


# FER-272: el YAML se parsea como YAML (vía ruby, presente en macOS y en los runners de ubuntu —
# python no trae yaml en stdlib). El texto ejecutable de la pata CI son EXACTAMENTE los bloques
# `run:` de sus jobs; `name:`/comentarios/strings sueltas dejan de existir para el parser, y las
# llaves que convierten un step en teatro (`if:` no permitido, `continue-on-error`,
# `working-directory`) se detectan ESTRUCTURALMENTE por step, no por grep. Fail-closed: si ruby
# falla o el YAML no parsea, la paridad FALLA — nunca se degrada al escaneo de texto (la clase
# «fallback silencioso en jobs de seguridad», FER-276).
def parse_workflow(root, rel):
    """→ (run_text, problems). run_text = los bloques run: ejecutables concatenados."""
    import subprocess
    path = os.path.join(root, rel)
    try:
        out = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e", "puts YAML.load_file(ARGV[0]).to_json", path],
            capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        return "", [f"design-lint: no pude parsear el YAML como YAML ({e}) — fail-closed"]
    if out.returncode != 0:
        return "", [f"design-lint: YAML inválido según ruby ({out.stderr.strip()[:120]}) — fail-closed"]
    try:
        doc = json.loads(out.stdout)
    except json.JSONDecodeError:
        return "", ["design-lint: la conversión YAML→JSON no produjo JSON — fail-closed"]
    problems, runs = [], []
    jobs = doc.get("jobs") or {}
    if not isinstance(jobs, dict) or not jobs:
        return "", ["design-lint: el workflow no declara jobs — fail-closed"]
    for jname, job in jobs.items():
        if not isinstance(job, dict):
            continue
        jif = str(job.get("if", ""))
        if jif and not YML_IF_ALLOWED.search(jif):
            problems.append(f"design-lint: job `{jname}` con if: `{jif}` — solo se permite el guard de pull_request")
        for step in job.get("steps") or []:
            if not isinstance(step, dict):
                continue
            label = step.get("name") or step.get("uses") or "step"
            for k in ("continue-on-error", "working-directory"):
                if k in step:
                    problems.append(f"design-lint: step `{label}` usa {k} — prohibido (teatro de gate)")
            if "if" in step:
                problems.append(f"design-lint: step `{label}` usa if: — prohibido a nivel step")
            run = step.get("run")
            if isinstance(run, str):
                runs.append(run)
    run_text = "\n".join(runs)
    if "check-baseline-monotony.py" not in run_text:
        problems.append("design-lint: ningún run: invoca check-baseline-monotony.py")
    return run_text, problems


def _strip_dead_text(text, is_yaml):
    """Quita el texto NO ejecutable antes de parsear (review Grok FER-265: una invocación canónica
    en un comentario bash o en un `name:` de YAML era un señuelo que satisfacía la matriz mientras
    el `run:` real corría otra cosa)."""
    text = re.sub(r"\\\s*\n", " ", text)
    kept = []
    for line in text.splitlines():
        s = line.strip()
        if not is_yaml and s.startswith("#"):
            continue
        if is_yaml and (s.startswith("- name:") or s.startswith("name:") or s.startswith("#")):
            continue
        kept.append(line)
    return "\n".join(kept)


# En el YAML, estas llaves convierten un step canónico en teatro: `if: false` no corre,
# `continue-on-error` no gatea, `working-directory` escanea otra carpeta. Se prohíben, con la
# única excepción del guard del job de monotonía.
YML_FORBIDDEN = re.compile(r"continue-on-error|working-directory\s*:")
YML_IF_ALLOWED = re.compile(r"^\s*github\.event_name\s*==\s*'pull_request'\s*$")


def parse_invocations(text, is_yaml=False):
    """[(rules, baseline_or_None, literal_paths, has_var_paths)] por archivo. Acepta las MISMAS
    formas de flag que el linter (`--rules x` y `--rules=x`; ídem `--baseline`)."""
    text = _strip_dead_text(text, is_yaml)
    out = []
    for m in RE_INVOKE.finditer(text):
        args = m.group("args")
        # la invocación termina donde empieza la plomería del shell: `) || fail=1`, `|| ok=1`, `>`…
        args = re.split(r"\)|\|\||&&|>", args)[0]
        toks = args.split()
        rules, baseline, paths, has_var = [], None, [], False
        i = 0
        while i < len(toks):
            t = toks[i]
            if t == "--rules" and i + 1 < len(toks):
                rules = toks[i + 1].split(",")
                i += 2
            elif t.startswith("--rules="):
                rules = t.split("=", 1)[1].split(",")
                i += 1
            elif t == "--baseline" and i + 1 < len(toks):
                baseline = toks[i + 1]
                i += 2
            elif t.startswith("--baseline="):
                baseline = t.split("=", 1)[1]
                i += 1
            elif t.startswith("--"):
                i += 2 if t in ("--write-baseline",) else 1
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
    if not m:
        # Si ALL_RULES deja de ser una lista literal, este check quedaría ciego a reglas nuevas —
        # falla cerrado (review Grok FER-265, hallazgo 5).
        return problems + ["ALL_RULES del linter ya no es una lista literal parseable — el check de "
                           "reglas nuevas quedaría ciego; restaurar la forma `ALL_RULES = [...]`"]
    all_rules = ast.literal_eval(m.group(1))
    for r in all_rules:
        if r not in mrules:
            problems.append(f"regla `{r}` existe en ALL_RULES del linter y NO tiene fila en la matriz")

    for leg, rel in LEGS.items():
        text = _read(root, rel)
        if text is None:
            problems.append(f"falta la pata {leg} ({rel})")
            continue
        is_yaml = rel.endswith((".yml", ".yaml"))
        if is_yaml:
            # FER-272: el YAML se parsea como YAML — el texto ejecutable son los run: reales, y las
            # llaves de teatro (if:/continue-on-error/working-directory) se detectan por estructura.
            text, yml_problems = parse_workflow(root, rel)
            problems.extend(yml_problems)
        found = {}
        for rules, baseline, paths, has_var in parse_invocations(text, is_yaml=False):
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
                # TODAS las invocaciones ejecutables de la regla deben coincidir, no «alguna»:
                # un duplicado débil junto al canónico debe fallar (review Grok FER-265, caso A).
                literal = [(b, p) for b, p, hv in found[r] if not hv]
                bad = [p for b, p in literal
                       if not (p == roots and (b == canonical) == needs_baseline)]
                if not literal or bad:
                    problems.append(
                        f"{leg}: `{r}` declarado `{spec}` pero hay invocaciones que no coinciden "
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
