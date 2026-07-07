#!/usr/bin/env python3
"""Stage 1 of the ExerciseDB bake — pull the full OSS catalog to a local cache.

NOOP is offline: this runs at BAKE time (dev machine), never in the app. It fetches every
exercise from the free ExerciseDB OSS endpoint (oss.exercisedb.dev, no key) into a raw
ndjson cache that `transform.py` then normalizes into the bundled catalog.

Reanudable/idempotente: re-running overwrites the cache with a fresh full pull. The `after`
cursor loops back to the start once exhausted, so we dedupe by exerciseId (1500 unique).

Usage:  python3 pull.py            # writes ./cache/oss_pages.ndjson
"""
import json, os, subprocess, time

HOST = "https://oss.exercisedb.dev/api/v1/exercises"
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")
OUT = os.path.join(OUT_DIR, "oss_pages.ndjson")


def fetch(url):
    # urllib's TLS is flaky against this host on some Pythons; curl is reliable.
    for _ in range(8):
        r = subprocess.run(["curl", "-s", "-m", "30", url], capture_output=True, text=True)
        if r.stdout.strip():
            try:
                return json.loads(r.stdout)
            except json.JSONDecodeError:
                pass
        time.sleep(1.5)
    raise SystemExit(f"gave up fetching {url}")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    seen, pages, after = set(), [], None
    while True:
        url = HOST + "?limit=100" + (f"&after={after}" if after else "")
        d = fetch(url)
        data = d.get("data", [])
        new = [e for e in data if e["exerciseId"] not in seen]
        for e in new:
            seen.add(e["exerciseId"])
        if new:
            pages.append(data)
        meta = d.get("meta", {})
        after = meta.get("nextCursor")
        print(f"total unique: {len(seen)}", flush=True)
        if not meta.get("hasNextPage") or not after or not new:
            break
        time.sleep(0.15)
    with open(OUT, "w") as f:
        for p in pages:
            f.write(json.dumps({"data": p}) + "\n")
    print(f"DONE — {len(seen)} unique exercises → {OUT}")


if __name__ == "__main__":
    main()
