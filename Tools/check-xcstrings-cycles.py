#!/usr/bin/env python3
"""Guard against reference cycles in String Catalogs (.xcstrings).

Background — FER-395: Xcode 26.3 enters infinite recursion (EXC_BAD_ACCESS /
SIGBUS) in IDEXCStringsSupportCore · StringTraceGraph.predecessorNodesTowardsUsages
while indexing a catalog that contains a cycle. The runaway recursion balloons
Xcode's memory until the Mac reports "system has run out of application memory".
The CLI `xcodebuild` compiles fine, so this is invisible to the build — only the
GUI/indexer crashes. This script is the cheap guard the build can't give us.

A cycle is formed by "mirror" entries: a Spanish-literal key whose `en` value is
the English translation, plus a key named with that English text whose `es` value
points back — e.g. "Atrás".en = "Back" and "Back".es = "Atrás". We model the
catalog as a graph (node = key; edge K -> V when some localized value of K is
itself another key V) and fail if any strongly-connected component has size > 1.

Usage:
    python3 Tools/check-xcstrings-cycles.py [catalog.xcstrings ...]

With no arguments it discovers every Localizable.xcstrings under the repo root
(skipping build artifacts and git worktrees). Exit code 0 = clean, 1 = cycle(s).
"""
import json
import os
import sys

SKIP_DIRS = {".build", "build", "DerivedData", ".git", "worktrees", "Pods"}


def discover(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(".xcstrings"):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


def collect_values(unit):
    """Every string value inside a localization node (stringUnit or variations)."""
    out = []
    if not isinstance(unit, dict):
        return out
    su = unit.get("stringUnit")
    if isinstance(su, dict) and "value" in su:
        out.append(su["value"])
    var = unit.get("variations")
    if isinstance(var, dict):
        for axis in var.values():
            if isinstance(axis, dict):
                for sub in axis.values():
                    out.extend(collect_values(sub))
    return out


def find_cycles(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    strings = data.get("strings", {})
    keys = set(strings.keys())

    # edge K -> V when a localized value of K equals another key V (V != K)
    edges = {}
    for k, entry in strings.items():
        locs = (entry or {}).get("localizations", {}) or {}
        targets = {v for unit in locs.values() for v in collect_values(unit)
                   if v in keys and v != k}
        if targets:
            edges[k] = targets

    # Tarjan strongly-connected components (iterative — catalogs are large)
    index, low, on_stack, stack, sccs = {}, {}, {}, [], []
    counter = 0
    for start in list(edges.keys()):
        if start in index:
            continue
        work = [(start, iter(edges.get(start, ())))]
        while work:
            v, it = work[-1]
            if v not in index:
                index[v] = low[v] = counter
                counter += 1
                stack.append(v)
                on_stack[v] = True
            advanced = False
            for w in it:
                if w not in index:
                    work.append((w, iter(edges.get(w, ()))))
                    advanced = True
                    break
                elif on_stack.get(w):
                    low[v] = min(low[v], index[w])
            if advanced:
                continue
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stack.pop()
                    on_stack[w] = False
                    comp.append(w)
                    if w == v:
                        break
                if len(comp) > 1:
                    sccs.append(comp)
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])
    return sccs


def main():
    args = sys.argv[1:]
    if args:
        paths = args
    else:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        paths = discover(root)

    total = 0
    for path in paths:
        try:
            cycles = find_cycles(path)
        except (OSError, json.JSONDecodeError) as e:
            print(f"⚠️  no se pudo leer {path}: {e}", file=sys.stderr)
            continue
        rel = os.path.relpath(path)
        if cycles:
            total += len(cycles)
            print(f"❌ {rel}: {len(cycles)} ciclo(s) — crashean Xcode 26.3 (FER-395):")
            for comp in cycles:
                print("   " + " ↔ ".join(repr(k) for k in comp))
        else:
            print(f"✅ {rel}: sin ciclos")

    if total:
        print(f"\n{total} ciclo(s) en total. Rompe el ciclo poniendo el valor `en` de "
              f"la clave cíclica = su propio nombre (patrón FER-395).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
