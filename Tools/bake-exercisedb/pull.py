#!/usr/bin/env python3
"""Stage 1 of the exercise bake — pull the free-exercise-db catalog to a local cache (FER-923).

Cénit is offline: this runs at BAKE time (dev machine), never in the app. It fetches the whole
free-exercise-db dataset (yuhonas, The Unlicense / public domain) — a single JSON file, 873
exercises — into a local cache that `transform.py` then normalizes into the bundled catalog.

We migrated off ExerciseDB OSS (~1500, non-commercial license + lots of junk) to this cleaner,
public-domain source. The app ships its OWN art (FER-919), so the base only needs clean data +
a sane license, not media.

Idempotente: re-running overwrites the cache with a fresh full pull.

Usage:  python3 pull.py            # writes ./cache/free-exercise-db.json
"""
import json, os, subprocess

SRC = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")
OUT = os.path.join(OUT_DIR, "free-exercise-db.json")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # urllib's TLS is flaky on some Pythons; curl is reliable.
    r = subprocess.run(["curl", "-s", "-m", "60", SRC], capture_output=True, text=True)
    if not r.stdout.strip():
        raise SystemExit(f"gave up fetching {SRC}")
    data = json.loads(r.stdout)
    if not isinstance(data, list) or not data:
        raise SystemExit(f"unexpected payload from {SRC}: not a non-empty list")
    with open(OUT, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    print(f"DONE — {len(data)} exercises → {OUT}")


if __name__ == "__main__":
    main()
