#!/usr/bin/env python3
"""Stage 3 of the ExerciseDB bake — assemble the es-MX overlay from the translated batches.

Reads the per-batch en->es files produced by the translation workflow (translated at bake time by
Sonnet), plus `pending-es.json` (which string belongs to which exercise/field), and writes
`exercises.es.json` — the [{id, name, instructions}] overlay `ExerciseCatalog` layers over the
English catalog. A string with no translation falls back to its English (no gap), and the run
reports coverage so misses can be re-translated.

Usage:  python3 build_es_overlay.py <trans_dir> [<trans_dir> ...]
"""
import json, glob, os, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "StrandTraining", "Sources", "StrandTraining", "Resources"))
PENDING = os.path.join(HERE, "cache", "pending-es.json")
OUT = os.path.join(RES, "exercises.es.json")
OUT_ZLIB = os.path.join(RES, "exercises.es.json.zlib")


def write_zlib(path, obj):
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    co = zlib.compressobj(9, zlib.DEFLATED, -15)   # raw DEFLATE == Apple Compression .zlib
    open(path, "wb").write(co.compress(data) + co.flush())


def load_en2es(dirs):
    en2es = {}
    for d in dirs:
        for f in glob.glob(os.path.join(d, "batch-*.json")):
            try:
                data = json.load(open(f))
            except Exception:
                continue
            if isinstance(data, dict):
                for en, es in data.items():
                    if isinstance(es, str) and es.strip():
                        en2es[en] = es
    return en2es


def main():
    dirs = sys.argv[1:]
    if not dirs:
        sys.exit("usage: build_es_overlay.py <trans_dir> [<trans_dir> ...]")
    en2es = load_en2es(dirs)
    pending = json.load(open(PENDING))
    # group by exercise id
    by_id = {}
    for p in pending:
        by_id.setdefault(p["id"], {"name": None, "instructions": {}})
        if p["field"] == "name":
            by_id[p["id"]]["name"] = p["en"]
        else:
            by_id[p["id"]]["instructions"][p["idx"]] = p["en"]
    overlay = []
    miss = 0
    total = 0
    for eid, fields in by_id.items():
        name_en = fields["name"] or ""
        name_es = en2es.get(name_en, name_en)
        total += 1
        if name_en not in en2es:
            miss += 1
        ins = []
        for i in sorted(fields["instructions"]):
            en = fields["instructions"][i]
            total += 1
            if en not in en2es:
                miss += 1
            ins.append(en2es.get(en, en))
        overlay.append({"id": eid, "name": name_es, "instructions": ins})
    overlay.sort(key=lambda e: e["id"])
    with open(OUT, "w") as f:
        json.dump(overlay, f, ensure_ascii=False, indent=1)
    write_zlib(OUT_ZLIB, overlay)   # the app reads the .zlib; the .json stays for review
    print(f"overlay: {len(overlay)} exercises -> {OUT} (+ .zlib {os.path.getsize(OUT_ZLIB)} B)")
    print(f"strings: {total}, untranslated (fell back to EN): {miss} ({100*(total-miss)//total}% translated)")


if __name__ == "__main__":
    main()
