"""artifact_icons.py - item icons from reference pictures (07.11.26)

Cuts the item out of a picture (dark, flat or painted background), turns it upright
(principal axis vertical, the heavier end - the head - on top), scales it to an icon size and
quantizes it to the icons.lod format (256 colours, index 0 = (0,252,252) transparent).
Also recolours an existing icon (hue shift) for the cestus artifacts.
"""
import struct, sys, zlib, math
import numpy as np, cv2
from PIL import Image

TRANSP = (0, 252, 252)

def cutout(path, crop=None, mode='dark', thr=30, grab=False, keep_frac=0.05):
    im = np.array(Image.open(path).convert('RGB'))
    if crop:
        x0, y0, x1, y1 = crop
        im = im[y0:y1, x0:x1]
    f = im.astype(int)
    if mode == 'dark':
        m = (f.max(2) > thr)
    elif mode == 'flat':
        bg = np.median(np.concatenate([f[0], f[-1], f[:, 0], f[:, -1]]), 0)
        m = np.abs(f - bg).max(2) > thr
    else:   # 'paint': light background, the object is darker or more saturated
        hsv = cv2.cvtColor(im, cv2.COLOR_RGB2HSV).astype(int)
        m = (hsv[..., 1] > thr) | (hsv[..., 2] < 150)
    m = m.astype(np.uint8)
    if grab:
        gm = np.where(m > 0, cv2.GC_PR_FGD, cv2.GC_PR_BGD).astype(np.uint8)
        bgr, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
        cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), gm, None, bgr, fgd, 5, cv2.GC_INIT_WITH_MASK)
        m = ((gm == cv2.GC_FGD) | (gm == cv2.GC_PR_FGD)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    areas = st[1:, cv2.CC_STAT_AREA]
    keep = [i + 1 for i, a in enumerate(areas) if a >= keep_frac * areas.max()]
    m = np.isin(lab, keep).astype(np.uint8)
    # fill holes (flood the background from the border of a padded copy)
    h, w = m.shape
    ff = np.zeros((h + 2, w + 2), np.uint8); ff[1:-1, 1:-1] = m
    cv2.floodFill(ff, np.zeros((h + 4, w + 4), np.uint8), (0, 0), 2)
    m = (ff[1:-1, 1:-1] != 2).astype(np.uint8)
    return im, m

def upright(im, m, angle=None, flip=None):
    ys, xs = np.nonzero(m)
    if angle is None:
        pts = np.stack([xs, ys], 1).astype(float); pts -= pts.mean(0)
        ev, evec = np.linalg.eigh(np.cov(pts.T))
        vx, vy = evec[:, 1]
        angle = math.degrees(math.atan2(vx, vy))   # rotate so the axis is vertical
    rgba = np.dstack([im, m * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, 'RGBA').rotate(-angle, resample=Image.BICUBIC, expand=True)
    a = np.array(img)
    ys, xs = np.nonzero(a[..., 3] > 128)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    if flip is None:   # the wider end on top
        al = a[..., 3] > 128; h = al.shape[0]
        flip = al[h * 2 // 3:].sum() > al[:h // 3].sum()
    if flip: a = a[::-1, ::-1]
    return Image.fromarray(a, 'RGBA')

def to_icon(img, size, name, sharpen=True):
    w, h = size
    img = img.resize((w, h), Image.LANCZOS)
    a = np.array(img)
    alpha = a[..., 3] > 110
    rgb = Image.fromarray(a[..., :3])
    if sharpen:
        from PIL import ImageFilter
        rgb = rgb.filter(ImageFilter.UnsharpMask(1, 60, 2))
    q = rgb.quantize(255, method=Image.MEDIANCUT, dither=Image.NONE)
    idx = np.array(q).astype(np.uint8) + 1
    idx[~alpha] = 0
    pal = list(TRANSP) + q.getpalette()[:255 * 3]
    pal += [0] * (768 - len(pal))
    return blob(name, idx, bytes(pal))

def blob(name, idx, pal):
    h, w = idx.shape
    raw = idx.tobytes(); comp = zlib.compress(raw, 9)
    hdr = bytearray(48)
    hdr[:16] = name.encode('latin1').ljust(16, b'\0')
    struct.pack_into('<IIHH', hdr, 16, len(raw), len(comp), w, h)
    struct.pack_into('<I', hdr, 40, len(raw))
    return bytes(hdr) + comp + pal

def decode(b):
    bs, ds, w, h = struct.unpack('<IIHH', b[16:28])
    us = struct.unpack('<I', b[40:44])[0]
    px = zlib.decompress(b[48:48 + ds]) if us else b[48:48 + bs]
    pal = b[48 + ds:48 + ds + 768]
    return np.frombuffer(px[:w * h], np.uint8).reshape(h, w), pal

def recolour(b, name, hue=None, sat=1.0, val=1.0, tint=None, only=None):
    """hue: new hue in degrees for the coloured pixels (None keeps); tint (r,g,b) multiplies;
    only (h0, h1): change only the palette colours with a hue in that range (degrees)"""
    idx, pal = decode(b)
    p = np.frombuffer(pal, np.uint8).reshape(256, 3).copy()
    hsv0 = cv2.cvtColor(p[None].astype(np.uint8), cv2.COLOR_RGB2HSV)[0].astype(float)
    hsv = hsv0.copy()
    if hue is not None: hsv[:, 0] = hue / 2
    hsv[:, 1] = np.clip(hsv[:, 1] * sat, 0, 255)
    hsv[:, 2] = np.clip(hsv[:, 2] * val, 0, 255)
    if only:
        h = hsv0[:, 0] * 2
        sel = (h >= only[0]) & (h <= only[1]) & (hsv0[:, 1] > 25)
        hsv[~sel] = hsv0[~sel]
    q = cv2.cvtColor(hsv[None].astype(np.uint8), cv2.COLOR_HSV2RGB)[0]
    if tint is not None: q = np.clip(q.astype(float) * np.array(tint) / 255, 0, 255).astype(np.uint8)
    q[0] = TRANSP
    return blob(name, idx, q.tobytes())

def preview(b, scale=2):
    idx, pal = decode(b)
    p = np.frombuffer(pal, np.uint8).reshape(256, 3)
    rgb = p[idx].copy(); rgb[idx == 0] = (60, 50, 40)
    return Image.fromarray(rgb).resize((idx.shape[1] * scale, idx.shape[0] * scale), Image.NEAREST)

# the reference pictures of 07.11.26 (the warhammers and the Ancient battleaxe)
REFS = {
    # icon name: (picture, crop, background, threshold, grabcut, icon height)
    'dwrunwh2': ('89dbf913-image.jpg', None, 'dark', 30, False, 200),
    'mjolnir':  ('adc712b2-image.jpg', None, 'dark', 22, False, 215),
    'dawnbr':   ('dcb35ac8-image.jpg', None, 'dark', 14, False, 215),
    'warscyth': ('34c8dca0-image.jpg', (350, 20, 570, 860), 'flat', 22, True, 270),
    'rimefall': ('35ee4b92-image.jpg', (0, 90, 735, 700), 'paint', 60, True, 205),
}
KEEP = {'rimefall': 1.0}   # the largest part only (the brush strokes of the picture stay out)

def ref_icon(folder, name):
    p, crop, mode, thr, grab, h = REFS[name]
    im, m = cutout(folder + '/' + p, crop, mode, thr, grab, KEEP.get(name, 0.05))
    u = upright(im, m)
    w = max(1, round(u.width * h / u.height))
    b = to_icon(u, (w, h), name)
    idx, _ = decode(b)
    rows = idx[int(h * 0.7):] > 0                       # the handle: the lower 30%
    cols = np.nonzero(rows)[1]
    grip = int(round(cols.mean())) if len(cols) else w // 2
    return b, (w, h, grip)

# the redraws of 08.11.26: upright pictures on a cyan background (0,255,255)
REDRAWS = {
    # icon name: (picture, icon height)
    'warscyth': ('f6aa3f5f-image.jpg', 270),
    'rimefall': ('2b4e3864-image.jpg', 205),
    'mjolnir':  ('d526a0c2-image.jpg', 215),
    'dwrunwh2': ('77318e27-image.jpg', 200),   # the runic hammer: now the Dwarven Runic Warhammer
    'dawnbr':   ('6246a410-image.jpg', 215),   # the paladin hammer
}

# how cyan a pixel may be at the edge before it counts as the background showing through
# (Rimefall is cyan itself: only the strongest fringe goes)
FRINGE = {'rimefall': 110}
# the pale halo where a glow fades into the background: peeled too (the Warscythe)
HALO = {'warscyth': 185}

def cyanness(c):
    c = c.astype(int)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    # cyan: green and blue alike, both above red (the Warscythe's blue glow is not)
    return np.where(np.abs(g - b) < 45, np.minimum(g, b) - r, 0)

def edge_of(m):
    return (m > 0) & (cv2.dilate((m == 0).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)

def cyan_cutout(path, fringe=45, halo=None):
    im = np.array(Image.open(path).convert('RGB'))
    f = im.astype(int)
    cy = cyanness(im)
    m = ~((np.minimum(f[..., 1], f[..., 2]) - f[..., 0] > 140) & (f[..., 1] > 190) & (f[..., 2] > 190))
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    areas = st[1:, cv2.CC_STAT_AREA]
    m = np.isin(lab, [i + 1 for i, a in enumerate(areas) if a >= 0.002 * areas.sum()]).astype(np.uint8)
    # peel the cyan fringe off the edge (the JPEG blends the background into it)
    for _ in range(6 if halo else 4):
        peel = edge_of(m) & (cy > fringe)
        if halo:
            peel |= edge_of(m) & (np.minimum(f[..., 1], f[..., 2]) > halo)
        if not peel.any(): break
        m[peel] = 0
    return im, m

def clean_fringe(idx, pal, fringe):
    """the icon: edge pixels still cyan take the colour of their inner neighbours, or go"""
    p = np.frombuffer(pal, np.uint8).reshape(256, 3).astype(int)
    for _ in range(2):
        cy = cyanness(p[idx]); cy[idx == 0] = 0
        bad = edge_of(idx > 0) & (cy > fringe)
        if not bad.any(): break
        good = (idx > 0) & ~bad & (cy <= fringe)
        h, w = idx.shape
        for y, x in zip(*np.nonzero(bad)):
            ys, xs = slice(max(0, y - 1), y + 2), slice(max(0, x - 1), x + 2)
            g = good[ys, xs]
            if g.sum() >= 3:
                c = p[idx[ys, xs][g]].mean(0)
                idx[y, x] = 1 + np.argmin(((p[1:] - c) ** 2).sum(1))
            else:
                idx[y, x] = 0
    return idx

def redraw_icon(folder, name):
    p, h = REDRAWS[name]
    fr = FRINGE.get(name, 45)
    im, m = cyan_cutout(folder + '/' + p, fr, HALO.get(name))
    ys, xs = np.nonzero(m)
    im, m = im[ys.min():ys.max() + 1, xs.min():xs.max() + 1], m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    img = Image.fromarray(np.dstack([im, m * 255]).astype(np.uint8), 'RGBA').convert('RGBa')
    w = max(1, round(img.width * h / img.height))
    img = img.resize((w, h), Image.LANCZOS).convert('RGBA')
    b = to_icon(img, (w, h), name, sharpen=False)
    idx, pal = decode(b)
    idx = clean_fringe(idx.copy(), pal, fr - 10)
    if name != 'rimefall':   # stray specks left by the peeling (Rimefall's droplets stay)
        n, lab, st, _ = cv2.connectedComponentsWithStats((idx > 0).astype(np.uint8))
        for i in range(1, n):
            if st[i, cv2.CC_STAT_AREA] < 6: idx[lab == i] = 0
    b = blob(name, idx, pal)
    cols = np.nonzero(idx[int(h * 0.7):] > 0)[1]
    grip = int(round(cols.mean())) if len(cols) else w // 2
    return b, (w, h, grip)
