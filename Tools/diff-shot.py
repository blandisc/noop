#!/usr/bin/env python3
"""diff-shot.py — visual diff for two iOS screenshot PNGs.

Compares BEFORE and AFTER screenshots and produces:
  - a side-by-side composite PNG: [BEFORE | AFTER | DIFF]
    where DIFF is the AFTER image dimmed, with changed pixels highlighted
    in magenta.
  - stdout stats: changed pixel count, % of frame, and the bounding box
    of the changed region (useful to confirm "the change was only in
    the hero area").

Exit codes:
  0 — differences detected
  2 — images are identical (within --threshold)
  1 — usage/IO error

Backend: pure PIL (Pillow), no numpy required. Per-pixel work is done with
PIL's C-level ImageChops/point operations (no Python-level pixel loops),
so a 1206x2622 frame compares in well under a second.

Usage:
  python3 Tools/diff-shot.py before.png after.png -o diff.png [--threshold 24]
"""

import argparse
import sys

from PIL import Image, ImageChops, ImageEnhance

MAGENTA = (255, 0, 255)
DIM_FACTOR = 0.35  # how dark the untouched areas of the DIFF panel get
GUTTER = 8  # px between panels in the composite
DEFAULT_THRESHOLD = 24  # per-channel distance tolerated as antialiasing noise


def build_diff_mask(before: Image.Image, after: Image.Image, threshold: int) -> Image.Image:
    """Return a single-band 'L' mask image: 255 where pixels changed beyond
    threshold (checked per-channel, taking the max channel delta), 0 elsewhere.
    """
    diff = ImageChops.difference(before, after)
    r, g, b = diff.split()[:3]
    max_channel = ImageChops.lighter(ImageChops.lighter(r, g), b)
    mask = max_channel.point(lambda p: 255 if p > threshold else 0)
    return mask


def make_composite(before: Image.Image, after: Image.Image, mask: Image.Image) -> Image.Image:
    w, h = before.size

    dimmed_after = ImageEnhance.Brightness(after).enhance(DIM_FACTOR)
    magenta_layer = Image.new("RGB", (w, h), MAGENTA)
    diff_panel = Image.composite(magenta_layer, dimmed_after, mask)

    composite = Image.new("RGB", (w * 3 + GUTTER * 2, h), (0, 0, 0))
    composite.paste(before, (0, 0))
    composite.paste(after, (w + GUTTER, 0))
    composite.paste(diff_panel, (2 * (w + GUTTER), 0))
    return composite


def main() -> int:
    parser = argparse.ArgumentParser(description="Visual diff of two screenshot PNGs.")
    parser.add_argument("before", help="path to the BEFORE screenshot (PNG)")
    parser.add_argument("after", help="path to the AFTER screenshot (PNG)")
    parser.add_argument("-o", "--output", required=True, help="path to write the composite PNG")
    parser.add_argument(
        "--threshold",
        type=int,
        default=DEFAULT_THRESHOLD,
        help=f"per-channel distance tolerated as antialiasing noise (default: {DEFAULT_THRESHOLD})",
    )
    args = parser.parse_args()

    try:
        before = Image.open(args.before).convert("RGB")
    except Exception as exc:
        print(f"error: could not open BEFORE image '{args.before}': {exc}", file=sys.stderr)
        return 1

    try:
        after = Image.open(args.after).convert("RGB")
    except Exception as exc:
        print(f"error: could not open AFTER image '{args.after}': {exc}", file=sys.stderr)
        return 1

    if before.size != after.size:
        print(
            f"notice: size mismatch (before={before.size[0]}x{before.size[1]}, "
            f"after={after.size[0]}x{after.size[1]}) — scaling AFTER to BEFORE's size",
        )
        after = after.resize(before.size, Image.LANCZOS)

    w, h = before.size
    total_pixels = w * h

    mask = build_diff_mask(before, after, args.threshold)

    hist = mask.histogram()
    changed_pixels = hist[255] if len(hist) > 255 else 0
    percent = (changed_pixels / total_pixels) * 100 if total_pixels else 0.0

    bbox = mask.getbbox()
    if bbox is not None:
        left, top, right, bottom = bbox
        bbox_w, bbox_h = right - left, bottom - top
    else:
        left = top = bbox_w = bbox_h = 0

    composite = make_composite(before, after, mask)
    try:
        composite.save(args.output)
    except Exception as exc:
        print(f"error: could not write output image '{args.output}': {exc}", file=sys.stderr)
        return 1

    print(f"frame: {w}x{h} ({total_pixels} px)")
    print(f"threshold: {args.threshold}")
    print(f"changed pixels: {changed_pixels} ({percent:.4f}% of frame)")
    print(f"bounding box: x={left} y={top} w={bbox_w} h={bbox_h}")
    print(f"composite written: {args.output} ({composite.size[0]}x{composite.size[1]})")

    if changed_pixels == 0:
        print("result: IDENTICAL (no differences above threshold)")
        return 2

    print("result: DIFFERENT")
    return 0


if __name__ == "__main__":
    sys.exit(main())
