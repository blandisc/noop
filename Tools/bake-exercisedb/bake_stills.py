#!/usr/bin/env python3
"""Stage 6 of the ExerciseDB bake — bake the row thumbnails offline + prune dead media (FER-800).

NOOP is offline: exercise ROW thumbnails must exist without the network or the opt-in media
toggle. This step takes each catalog `gifUrl`, downloads the GIF once at build time, extracts its
FIRST FRAME, and writes a small JPG to:

    Packages/StrandTraining/.../Resources/exercise-stills/{id}.jpg

Those baked stills ship in the bundle (~10–20 MB for ~1324 exercises) and feed every exercise row
(Library, routine builder) with zero requests. The animated GIF stays an opt-in download for the
detail hero only (FER-722/FER-790) — this does NOT bake the GIF binary.

It also PRUNES dead media: ~12% of the ExerciseDB CDN `gifUrl`s return 404 (dead OSS assets). For
each 404 the script sets `gifUrl: null` in exercises.json so the runtime never re-GETs it (the
coordinator already treats a nil `gifUrl` as "no media" → YouTube fallback in the detail sheet).

Idempotent + resumable: an id whose still already exists on disk is skipped; re-running only fills
gaps. Uses `curl` per file (the OSS CDN's TLS is flaky with urllib, same as pull.py).

Usage:  python3 bake_stills.py
"""
import io, json, os, subprocess
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "StrandTraining", "Sources", "StrandTraining", "Resources"))
CATALOG = os.path.join(RES, "exercises.json")
STILLS_DIR = os.path.join(RES, "exercise-stills")

MAX_SIDE = 240        # longest edge in px — covers a 54pt row @3x with margin; rows are the only consumer
JPEG_QUALITY = 82
CONCURRENCY = 16


def fetch(url: str) -> tuple[int, bytes]:
    """GET via curl. Returns (http_code, body). Body is empty on non-200."""
    # -w writes the status to stderr-free stdout tail; simpler: use --write-out with -o to a pipe.
    proc = subprocess.run(
        ["curl", "-sS", "--max-time", "30", "--retry", "2", "-w", "%{http_code}", url],
        capture_output=True)
    body = proc.stdout
    # The 3-digit status is appended to stdout by -w; split it off the tail.
    if len(body) >= 3 and body[-3:].isdigit():
        code = int(body[-3:]); body = body[:-3]
    else:
        code = 0
    return code, body


def bake_one(ex: dict) -> tuple[str, str]:
    """Download + extract still for one exercise. Returns (id, outcome): 'ok' | 'skip' | 'dead' | 'fail'."""
    eid = ex["id"]
    url = ex.get("gifUrl")
    if not url:
        return eid, "dead"                      # already pruned / no media
    out = os.path.join(STILLS_DIR, f"{eid}.jpg")
    if os.path.exists(out):
        return eid, "skip"                      # resumable: already baked
    code, body = fetch(url)
    if code == 404:
        return eid, "dead"                      # prune this gifUrl
    if code != 200 or not body:
        return eid, "fail"                      # transient — leave gifUrl, retry next run
    try:
        im = Image.open(io.BytesIO(body))
        im.seek(0)                              # first frame of the GIF
        im = im.convert("RGB")
        im.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
        im.save(out, "JPEG", quality=JPEG_QUALITY, optimize=True)
    except Exception as e:                       # noqa: BLE001 — a corrupt asset shouldn't abort the batch
        print(f"  ! {eid}: decode failed ({e})")
        return eid, "fail"
    return eid, "ok"


def main() -> None:
    os.makedirs(STILLS_DIR, exist_ok=True)
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)

    outcomes: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
        for i, (eid, outcome) in enumerate(pool.map(bake_one, catalog), 1):
            outcomes[eid] = outcome
            if i % 100 == 0:
                print(f"  {i}/{len(catalog)}…")

    ok = sum(v == "ok" for v in outcomes.values())
    skip = sum(v == "skip" for v in outcomes.values())
    dead = {k for k, v in outcomes.items() if v == "dead"}
    fail = sum(v == "fail" for v in outcomes.values())
    print(f"stills: {ok} baked, {skip} already on disk, {len(dead)} dead (pruned), {fail} failed")

    # Prune dead media in the catalog: set gifUrl=null so the runtime never re-GETs a 404.
    pruned = 0
    for ex in catalog:
        if ex["id"] in dead and ex.get("gifUrl"):
            ex["gifUrl"] = None
            pruned += 1
    if pruned:
        with open(CATALOG, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=1)   # match transform.py exactly (minimal diff)
        print(f"catalog: pruned {pruned} dead gifUrl → null in exercises.json")

    if fail:
        print(f"NOTE: {fail} transient failures — re-run to fill them before committing.")


if __name__ == "__main__":
    main()
