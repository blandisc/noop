#!/usr/bin/env python3
"""The baseline only goes down (FER-264, épico FER-261).

`Tools/design-drift-baseline.json` freezes the design debt per (rule, file). The ratchet in
`check-design-drift.py` stops a PR from adding hits — but nothing stopped a PR from simply
RAISING the baseline itself in passing («the baseline never grows» was a print, not a check).
This script closes that valve: it compares the PR's baseline against the merge-base's and fails
if ANY count rises or any new (rule, file) appears with a count > 0. Drops and vanished keys pass.

Legal path for a raise (the ONLY one): a dedicated baseline-raise PR — it carries the
`baseline-alta` label (applied by the owner, per docs/design-system/CONTRATO.md) AND its diff
touches nothing but the baseline JSON and docs/**. Both conditions are checked HERE, mechanically:
a PR that introduces debt necessarily touches Swift, so it can never bless itself, and the
dedicated raise PR can never smuggle code. «If the JSON comes in the PR, allow it» is exactly
the valve this exists to close — never implement that.

Usage:
    check-baseline-monotony.py <base.json> <pr.json> [--labels a,b,c] [--diff-files f1,f2,...]

Exit 0 = monotone (or legally raised). Exit 1 = a count rose. Exit 2 = bad input.
"""
import json
import sys

BYPASS_LABEL = "baseline-alta"
BASELINE_FILE = "Tools/design-drift-baseline.json"


def _load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return {}  # no baseline at the base yet (first PR of the epic): everything is a raise
    except json.JSONDecodeError as e:
        print(f"monotony: {path} is not valid JSON ({e})")
        return None


def rises(base, pr):
    out = []
    for rule, files in pr.items():
        if rule not in base:
            # Alta ESTRUCTURAL (FER-276): una regla que no existía en la base está naciendo — su
            # baseline inicial congela deuda vieja, no crea nueva; sin esto, estrenar un gate
            # exigiría un baile de 3 PRs. La garantía protege las reglas EXISTENTES: un archivo
            # nuevo dentro de una regla vigente sigue siendo subida.
            continue
        for f, count in files.items():
            before = base.get(rule, {}).get(f, 0)
            if count > before:
                out.append((rule, f, before, count))
    return sorted(out)


def bypass_applies(labels, diff_files):
    if BYPASS_LABEL not in labels:
        return False
    if not diff_files:
        return False
    for f in diff_files:
        if f == BASELINE_FILE or f.startswith("docs/"):
            continue
        return False  # any code/CI/tooling file in the diff voids the bypass, label or not
    return True


def main(argv):
    args = []
    labels, diff_files = [], []
    it = iter(argv)
    for a in it:
        if a == "--labels":
            labels = [x.strip() for x in next(it, "").split(",") if x.strip()]
        elif a.startswith("--labels="):
            labels = [x.strip() for x in a.split("=", 1)[1].split(",") if x.strip()]
        elif a == "--diff-files":
            diff_files = [x.strip() for x in next(it, "").split(",") if x.strip()]
        elif a.startswith("--diff-files="):
            diff_files = [x.strip() for x in a.split("=", 1)[1].split(",") if x.strip()]
        else:
            args.append(a)
    if len(args) != 2:
        print("usage: check-baseline-monotony.py <base.json> <pr.json> [--labels …] [--diff-files …]")
        return 2
    base, pr = _load(args[0]), _load(args[1])
    if base is None or pr is None:
        return 2
    up = rises(base, pr)
    if not up:
        print("✅ baseline monotone: no (rule, file) count rises")
        return 0
    if bypass_applies(labels, diff_files):
        print(f"⚠️  baseline raised LEGALLY ({BYPASS_LABEL} + baseline/docs-only diff):")
        for rule, f, before, count in up:
            print(f"   {rule}/{f}: {before} → {count}")
        return 0
    print("❌ el baseline solo puede bajar — este PR SUBE la deuda congelada:")
    for rule, f, before, count in up:
        print(f"   {rule}/{f}: {before} → {count}")
    print(f"   Alta legal: PR dedicado SOLO-baseline con label `{BYPASS_LABEL}` del dueño "
          "(docs/design-system/CONTRATO.md). Un PR con código no puede bendecirse solo.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
