#!/usr/bin/env python3
"""
gauntlet_gen.py - make Visible Gauntlets bitmaps from the paperdoll hand bitmaps

Each gauntlet pose is cut from the hand bitmap of the same pose (pc02RHd, pc02LHo, ...):
the part of the arm farthest from the shoulder (forearm and hand) is repainted with the
gauntlet's colours, keeping the arm's own shading, and made a little bulkier, with a cuff
at the top. The result has the frame of the hand bitmap plus a margin, so for every
generated set the gauntlet position is the hand position minus that margin: place one set
with the Paperdoll Tuner and copy its rows in "Visible gauntlets.txt" to the next ones.

Requires Python 3 with Pillow and numpy:  pip install pillow numpy

Typical use (hand bitmaps exported from icons.lod with MMArchive):

  python gauntlet_gen.py --hands hands --prefix pc02 --doll 1 --item 600 ^
         --from-image gauntlet_icon.bmp --out out

  writes out/600v2RHd.bmp, 600v2RHu.bmp, 600v2LHd.bmp, 600v2LHu.bmp, 600v2LHo.bmp
  (8-bit, cyan 0,255,255 = transparent, palette entry 0) and out/600v2_preview.png.
  Import the .bmp files into icons.lod with MMArchive.

Material (pick one):
  --from-image FILE     dark / mid / light colours taken from an image (the gauntlet's
                        item icon, or a gauntlet bitmap you like); cyan is ignored
  --colors D,M,L        three hex colours, e.g. 2b1a10,6b4226,b07a48
  --swatch FILE         a small texture, tiled and shaded by the arm (e.g. chain mail)

Shape:
  --cover F             share of the arm length covered, from the hand up (default 0.55)
  --cover POSE=F        per pose, e.g. --cover RHu=0.7 (repeatable)
  --shoulder POSE=X,Y   where the arm starts, if not at the top of the bitmap
  --bulk N              pixels added around the covered part (default 1)
  --cuff N              cuff height in pixels (default 3), --no-cuff to leave it out
  Bitmaps smaller than --small-height (default 30) rows are covered whole (fist pieces).
"""

import argparse
import glob
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

CYAN = np.array([0, 255, 255])
POSES = ["RHd", "RHu", "LHd", "LHu", "LHo"]


# ---------------------------------------------------------------------------
# input

def load_rgb(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int32)


def opaque_mask(rgb, tolerance=60):
    """True where the pixel is not the cyan background (tolerant, for JPEG copies)."""
    d = np.sqrt(((rgb - CYAN) ** 2).sum(axis=2))
    return d > tolerance


def find_hand(hands_dir, prefix, pose):
    for ext in ("bmp", "png", "jpg", "jpeg", "gif"):
        for name in (f"{prefix}{pose}.{ext}", f"{prefix}{pose.lower()}.{ext}"):
            p = os.path.join(hands_dir, name)
            if os.path.exists(p):
                return p
    hits = [p for p in glob.glob(os.path.join(hands_dir, f"{prefix}*"))
            if os.path.splitext(os.path.basename(p))[0].lower() == (prefix + pose).lower()]
    return hits[0] if hits else None


# ---------------------------------------------------------------------------
# material

def luminance(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def kmeans_colors(pixels, k=3, iters=20):
    pixels = pixels.astype(np.float64)
    lum = luminance(pixels)
    order = np.argsort(lum)
    centers = np.array([pixels[order[int((i + 0.5) * len(order) / k)]] for i in range(k)])
    for _ in range(iters):
        d = ((pixels[:, None, :] - centers[None, :, :]) ** 2).sum(axis=2)
        lab = d.argmin(axis=1)
        for i in range(k):
            if (lab == i).any():
                centers[i] = pixels[lab == i].mean(axis=0)
    centers = centers[np.argsort(luminance(centers))]
    return centers


def material_from_image(path):
    rgb = load_rgb(path)
    # leave out the background and its blend into the edges (cyan-tinted pixels)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = opaque_mask(rgb, 150) & ~((g > r + 40) & (b > r + 40))
    px = rgb[m]
    if len(px) < 3:
        sys.exit(f"{path}: no opaque pixels")
    return kmeans_colors(px, 3)


def material_from_hex(s):
    cols = []
    for h in s.split(","):
        h = h.strip().lstrip("#")
        cols.append([int(h[i:i + 2], 16) for i in (0, 2, 4)])
    if len(cols) != 3:
        sys.exit("--colors needs three colours: dark,mid,light")
    return np.array(cols, dtype=np.float64)


def gradient(colors, t):
    """t 0..1 -> dark..mid..light"""
    t = np.clip(t, 0, 1)[..., None]
    lo = colors[0] + (colors[1] - colors[0]) * np.clip(t * 2, 0, 1)
    hi = colors[1] + (colors[2] - colors[1]) * np.clip(t * 2 - 1, 0, 1)
    return np.where(t < 0.5, lo, hi)


# ---------------------------------------------------------------------------
# shape

def geodesic(mask, start):
    """distance in steps (8-connected) from start through mask; -1 outside / unreachable"""
    h, w = mask.shape
    dist = np.full((h, w), -1, dtype=np.int32)
    q = deque()
    for (y, x) in start:
        if mask[y, x]:
            dist[y, x] = 0
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and dist[ny, nx] < 0:
                    dist[ny, nx] = dist[y, x] + 1
                    q.append((ny, nx))
    return dist


def shoulder_points(mask, given=None):
    if given:
        x, y = given
        ys, xs = np.nonzero(mask)
        i = ((ys - y) ** 2 + (xs - x) ** 2).argmin()
        return [(ys[i], xs[i])]
    top = np.nonzero(mask.any(axis=1))[0][0]
    return [(top, x) for x in np.nonzero(mask[top])[0]]


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        m = out.copy()
        m[1:, :] |= out[:-1, :]
        m[:-1, :] |= out[1:, :]
        m[:, 1:] |= out[:, :-1]
        m[:, :-1] |= out[:, 1:]
        out = m
    return out


def border(mask):
    inner = mask.copy()
    inner[1:, :] &= mask[:-1, :]
    inner[:-1, :] &= mask[1:, :]
    inner[:, 1:] &= mask[:, :-1]
    inner[:, :-1] &= mask[:, 1:]
    return mask & ~inner


# ---------------------------------------------------------------------------

def make_gauntlet(hand_rgb, colors, swatch, cover, shoulder, bulk, cuff, small_height, margin):
    hand = opaque_mask(hand_rgb)
    h, w = hand.shape
    # work on a frame with a margin, so bulk and cuff fit
    H, W = h + 2 * margin, w + 2 * margin
    arm = np.zeros((H, W), bool)
    arm[margin:margin + h, margin:margin + w] = hand
    rgb = np.zeros((H, W, 3), np.int32)
    rgb[margin:margin + h, margin:margin + w] = hand_rgb

    if h < small_height:
        covered = arm.copy()
        cut = np.zeros_like(arm)
    else:
        sp = shoulder_points(arm, (shoulder[0] + margin, shoulder[1] + margin) if shoulder else None)
        dist = geodesic(arm, sp)
        far = dist.max()
        limit = far * (1 - cover)
        covered = dist >= limit
        cut = covered & (dist < limit + max(cuff, 1)) if cuff else np.zeros_like(arm)

    # shading from the arm
    lum = luminance(rgb.astype(np.float64))
    vals = lum[covered]
    lo, hi = np.percentile(vals, 5), np.percentile(vals, 95)
    t = (lum - lo) / max(hi - lo, 1)

    grown = dilate(covered, bulk) if bulk else covered.copy()
    if bulk:
        # the added rim takes the shading of the nearest covered pixel (approximate: blur of t)
        t_src = np.where(covered, t, np.nan)
        for _ in range(bulk):
            pad = np.pad(t_src, 1, constant_values=np.nan)
            stack = np.stack([pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
                              for dy in (-1, 0, 1) for dx in (-1, 0, 1)])
            cnt = (~np.isnan(stack)).sum(axis=0)
            fill = np.where(cnt > 0, np.nansum(stack, axis=0) / np.maximum(cnt, 1), np.nan)
            t_src = np.where(np.isnan(t_src), fill, t_src)
        t = np.where(covered, t, np.nan_to_num(t_src, nan=0.4))
        # never grow above the cuff line (toward the shoulder)
        if not (h < small_height):
            above = arm & ~covered
            grown &= ~above

    out = gradient(colors, t * 0.8 + 0.1)
    if swatch is not None:
        sh, sw = swatch.shape[:2]
        yy, xx = np.mgrid[0:H, 0:W]
        tex = swatch[yy % sh, xx % sw].astype(np.float64)
        out = tex * (0.55 + 0.9 * np.clip(t, 0, 1))[..., None]

    # cuff: a lighter band with a dark edge at the cut
    if cuff and cut.any():
        band = dilate(cut, 1) & grown
        out[band] = gradient(colors, np.full(band.sum(), 0.85))
    # outline
    edge = border(grown)
    out[edge] = out[edge] * 0.55

    img = np.zeros((H, W, 3), np.uint8)
    img[:] = CYAN
    img[grown] = np.clip(out[grown], 0, 254).astype(np.uint8)   # 254: never pure cyan
    return img, grown


def to_bmp8(rgb_img, path):
    im = Image.fromarray(rgb_img, "RGB")
    q = im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette()[:768]
    idx = np.asarray(q).copy()
    bg = np.all(rgb_img == CYAN, axis=2)
    if bg.any():
        bi = int(np.bincount(idx[bg]).argmax())
        # foreground pixels quantized to the background's colour: send them to the nearest other entry
        stray = (~bg) & (idx == bi)
        pal[bi * 3:bi * 3 + 3] = [0, 255, 255]
        # swap entry bi with 0
        a, b = idx == bi, idx == 0
        idx[a], idx[b] = 0, bi
        pal[0:3], pal[bi * 3:bi * 3 + 3] = pal[bi * 3:bi * 3 + 3], pal[0:3]
        if stray.any():
            colors = np.array(pal).reshape(-1, 3)[1:]
            for y, x in zip(*np.nonzero(stray)):
                c = rgb_img[y, x].astype(np.int32)
                idx[y, x] = 1 + int(((colors - c) ** 2).sum(axis=1).argmin())
    out = Image.fromarray(idx.astype(np.uint8), "P")
    out.putpalette(pal)
    out.save(path)


def preview(pairs, path, scale=4):
    tiles = []
    for hand_rgb, g, margin in pairs:
        h, w = hand_rgb.shape[:2]
        H, W = g.shape[:2]
        canvas = np.zeros((H, W * 3 + 4, 3), np.uint8)
        canvas[:] = (40, 40, 40)
        hand_pad = np.full((H, W, 3), CYAN, np.uint8)
        hand_pad[margin:margin + h, margin:margin + w] = hand_rgb
        canvas[:, :W] = hand_pad
        canvas[:, W + 2:2 * W + 2] = g
        over = hand_pad.copy()
        m = ~np.all(g == CYAN, axis=2)
        over[m] = g[m]
        canvas[:, 2 * W + 4:] = over
        tiles.append(canvas)
    Ht = max(t.shape[0] for t in tiles)
    Wt = sum(t.shape[1] for t in tiles) + 8 * len(tiles)
    sheet = np.zeros((Ht, Wt, 3), np.uint8)
    sheet[:] = (25, 25, 25)
    x = 0
    for t in tiles:
        sheet[:t.shape[0], x:x + t.shape[1]] = t
        x += t.shape[1] + 8
    Image.fromarray(sheet).resize((Wt * scale, Ht * scale), Image.NEAREST).save(path)


def parse_pose_values(items, conv):
    out = {}
    for it in items or []:
        if "=" in it:
            k, v = it.split("=", 1)
            out[k] = conv(v)
        else:
            out["*"] = conv(it)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hands", required=True, help="folder with the hand bitmaps")
    ap.add_argument("--prefix", required=True, help="hand bitmap name prefix, e.g. pc02")
    ap.add_argument("--doll", type=int, required=True, help="doll type (0..5)")
    ap.add_argument("--item", type=int, required=True, help="gauntlet item id")
    ap.add_argument("--out", default="out")
    ap.add_argument("--poses", default=",".join(POSES))
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--from-image")
    g.add_argument("--colors")
    g.add_argument("--swatch")
    ap.add_argument("--cover", action="append")
    ap.add_argument("--shoulder", action="append")
    ap.add_argument("--bulk", type=int, default=1)
    ap.add_argument("--cuff", type=int, default=3)
    ap.add_argument("--no-cuff", action="store_true")
    ap.add_argument("--small-height", type=int, default=30)
    a = ap.parse_args()

    if a.from_image:
        colors = material_from_image(a.from_image)
    elif a.colors:
        colors = material_from_hex(a.colors)
    else:
        colors = material_from_image(a.swatch)
    swatch = load_rgb(a.swatch) if a.swatch else None

    covers = parse_pose_values(a.cover, float)
    shoulders = parse_pose_values(a.shoulder, lambda v: tuple(int(n) for n in v.split(",")))
    cuff = 0 if a.no_cuff else a.cuff
    margin = max(a.bulk, 1) + 1

    os.makedirs(a.out, exist_ok=True)
    pairs = []
    for pose in a.poses.split(","):
        hp = find_hand(a.hands, a.prefix, pose)
        if not hp:
            print(f"{pose}: no hand bitmap {a.prefix}{pose} in {a.hands}, skipped")
            continue
        hand = load_rgb(hp)
        img, _ = make_gauntlet(hand, colors, swatch, covers.get(pose, covers.get("*", 0.55)),
                               shoulders.get(pose), a.bulk, cuff, a.small_height, margin)
        name = f"{a.item}v{a.doll + 1}{pose}.bmp"
        to_bmp8(img, os.path.join(a.out, name))
        pairs.append((hand.astype(np.uint8), img, margin))
        print(f"{name}: {img.shape[1]}x{img.shape[0]}  (draw at the {pose} hand position - {margin}, - {margin})")
    if pairs:
        pv = os.path.join(a.out, f"{a.item}v{a.doll + 1}_preview.png")
        preview(pairs, pv)
        print("preview:", pv)


if __name__ == "__main__":
    main()
