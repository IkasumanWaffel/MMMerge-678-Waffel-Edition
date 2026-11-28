"""Thrown weapon sprites rendered from simple 3D models (28.11.26).

The javelin, hand axe and throwing dagger are built as small polygon models after the MM7 item
pictures (7item031 Crude Spear, 7item023 Crude Axe, 7item015 Dagger), coloured with colours taken
from those pictures, and rendered by a little z-buffer renderer for every view the game needs:

  views 0-4: the weapon flying at the eye (0), at 45 degrees (1), from the side pointing right (2),
             at 45 degrees away (3) and away from the eye (4); 5-7 are mirrors (SFT). The eye looks
             down a little (PITCH), as the game's arrow sprites were drawn.
  frames:    the javelin flies straight (one frame); the axe and the dagger tumble, a turn in
             TUMBLE_FRAMES steps, the top turning towards the target.

Each frame is rendered at 3x and reduced (antialiased edges, alpha 50% cut), then put to the
picture's own palette (pal2103-2105, as before). The sprites replace the wjav/waxe/wdag sprites in
waffel.sprites.lod; the SFT rows are printed (scale and frame count).
usage: thrown_models.py mm7.icons.lod waffel.sprites.lod waffel.bitmaps.lod outdir [preview.png]
"""
import math, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from thrown_weapons import lod_entries, lod_write, icon, sprite

PITCH = math.radians(10)
# the eye looks down more for the views straight at or away from the weapon, so that a weapon lying
# along its flight still shows some of its length there, as the arrow's views 0 and 4 do
PITCH_BY_VIEW = {0: 24, 1: 10, 2: 10, 3: 10, 4: 24}
SS = 3                                   # supersampling
LIGHT = np.array([-0.45, 0.75, 0.5]); LIGHT = LIGHT / np.linalg.norm(LIGHT)
TUMBLE_FRAMES = 8

# ---------------------------------------------------------------- mesh building (x forward, y up, z side)

class Mesh:
    def __init__(self):
        self.tris = []      # (p0, p1, p2, colour, shininess)

    def tri(self, a, b, c, col, shine=0.0):
        self.tris.append((np.array(a, float), np.array(b, float), np.array(c, float), col, shine))

    def quad(self, a, b, c, d, col, shine=0.0):
        self.tri(a, b, c, col, shine); self.tri(a, c, d, col, shine)

    def add(self, other):
        self.tris += other.tris

def cylinder(m, x0, x1, r0, r1, col, n=10, shine=0.0, bands=None, caps=True):
    # along x; bands: list of (xa, xb, colour, radius growth)
    def ring(x, r):
        return [(x, r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n)) for k in range(n)]
    xs = [x0, x1]
    if bands:
        for a, b, _, _ in bands: xs += [a, b]
    xs = sorted(set(xs))
    def rad(x):
        r = r0 + (r1 - r0) * (x - x0) / (x1 - x0)
        return r
    for xa, xb in zip(xs, xs[1:]):
        c, grow = col, 0.0
        if bands:
            for a, b, bc, g in bands:
                if a <= xa and xb <= b: c, grow = bc, g
        ra, rb = ring(xa, rad(xa) + grow), ring(xb, rad(xb) + grow)
        for k in range(n):
            m.quad(ra[k], rb[k], rb[(k + 1) % n], ra[(k + 1) % n], c, shine)
    if caps:
        for x, outward in ((x0, -1), (x1, 1)):
            r = ring(x, rad(x)); ctr = (x, 0, 0)
            for k in range(n):
                a, b = r[k], r[(k + 1) % n]
                m.tri(ctr, b, a, col, shine) if outward < 0 else m.tri(ctr, a, b, col, shine)

def blade(m, x0, x1, width, thick, col, shine=0.6, steps=12, y0=0.0):
    # a diamond cross-section blade along x: half width width(t), half thickness thick(t), t 0..1
    prev = None
    for i in range(steps + 1):
        t = i / steps; x = x0 + (x1 - x0) * t
        w, th = width(t), thick(t)
        st = [(x, y0 + w, 0), (x, y0, th), (x, y0 - w, 0), (x, y0, -th)]
        if prev:
            for k in range(4):
                m.quad(prev[k], st[k], st[(k + 1) % 4], prev[(k + 1) % 4], col, shine)
        else:
            m.quad(st[0], st[1], st[2], st[3], col, shine)
        prev = st
    m.quad(prev[3], prev[2], prev[1], prev[0], col, shine)

def box(m, x0, x1, y0, y1, z0, z1, col, shine=0.0):
    p = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for a, b, c, d in f:
        m.quad(p[a], p[b], p[c], p[d], col, shine)

def extrude(m, profile, thick, col, shine=0.0):
    # a polygon in x-y (convex pieces by fan from the first point), half thickness thick(x, y)
    c = np.mean(profile, axis=0)
    top = [(x, y, thick(x, y)) for x, y in profile]
    bot = [(x, y, -thick(x, y)) for x, y in profile]
    ct, cb = (c[0], c[1], thick(*c)), (c[0], c[1], -thick(*c))
    n = len(profile)
    for k in range(n):
        a, b = k, (k + 1) % n
        m.tri(ct, top[a], top[b], col, shine)
        m.tri(cb, bot[b], bot[a], col, shine)
        m.quad(top[a], bot[a], bot[b], top[b], col, shine)

# ---------------------------------------------------------------- the three weapons

WOOD, WOOD_DARK = (112, 72, 44), (80, 46, 30)
LASH = (150, 120, 70)
STEEL = (150, 152, 150)
LEATHER = (70, 48, 30)
STONE = (112, 106, 80)

def javelin():
    m = Mesh()
    cylinder(m, -120, 85, 2.6, 3.0, WOOD, bands=[(-120, -108, WOOD_DARK, 0.4), (-20, 5, LASH, 0.5), (70, 85, LASH, 0.6)])
    blade(m, 85, 122, lambda t: 6.5 * math.sin(math.pi * min(1, (t + 0.12) * 0.95)) * (1 - t) ** 0.25,
          lambda t: 2.2 * (1 - t) + 0.3, STEEL, shine=0.8)
    return m

def dagger():
    m = Mesh()
    blade(m, 0, 44, lambda t: 5.0 * (1 - t) ** 0.85 + 0.1, lambda t: 1.6 * (1 - t) + 0.2, STEEL, shine=0.9)
    box(m, -2.5, 0, -8, 8, -2, 2, (120, 110, 80), shine=0.5)              # cross guard
    cylinder(m, -18, -2.5, 2.4, 2.2, LEATHER, n=8)
    cylinder(m, -22, -18, 3.2, 3.2, (120, 110, 80), n=8, shine=0.5)       # pommel
    return m

def axe():
    m = Mesh()
    cylinder(m, -48, 36, 3.2, 3.6, WOOD, bands=[(-48, -30, WOOD_DARK, 0.6), (-10, -6, LASH, 0.4)])
    # the head: an eye block round the haft's front end and a flared blade to +y
    box(m, 24, 40, -6, 6, -5, 5, STONE, shine=0.2)
    prof = [(26, 4), (38, 4), (44, 30), (40, 34), (20, 34), (16, 30)]
    extrude(m, prof, lambda x, y: max(0.6, 4.5 * (1 - (y - 4) / 32)), STONE, shine=0.3)
    return m

# ---------------------------------------------------------------- renderer

def transform(points, yaw, tumble, roll=0.0, pitch=PITCH):
    # roll about the weapon's own length (the flat of a blade turned partly towards the eye, so that
    # neither the side nor the head-on view shows only an edge), tumble about the side axis (the
    # top turning forward), then the view: forward -> (sin a, 0, cos a)
    x, y, z = points[..., 0], points[..., 1], points[..., 2]
    cr, sr = math.cos(roll), math.sin(roll)
    y, z = y * cr - z * sr, y * sr + z * cr
    ct, st = math.cos(tumble), math.sin(tumble)
    x, y = x * ct + y * st, -x * st + y * ct
    b = yaw - math.pi / 2
    cb, sb = math.cos(b), math.sin(b)
    x, z = x * cb + z * sb, -x * sb + z * cb
    cp, sp = math.cos(pitch), math.sin(pitch)
    y, z = y * cp - z * sp, y * sp + z * cp
    return np.stack([x, y, z], -1)

def render(mesh, yaw, tumble, scale, roll=0.0, pitch=PITCH):
    P = np.array([[t[0], t[1], t[2]] for t in mesh.tris])            # (n, 3, 3)
    cols = np.array([t[3] for t in mesh.tris], float)
    shine = np.array([t[4] for t in mesh.tris])
    Q = transform(P, yaw, tumble, roll, pitch)
    nrm = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
    ln = np.linalg.norm(nrm, axis=1); keep = ln > 1e-9
    Q, cols, shine, nrm = Q[keep], cols[keep], shine[keep], nrm[keep] / ln[keep][:, None]
    nrm[nrm[:, 2] < 0] *= -1                                         # two-sided
    diff = np.clip(nrm @ LIGHT, 0, 1)
    half = LIGHT + np.array([0, 0, 1.0]); half /= np.linalg.norm(half)
    spec = np.clip(nrm @ half, 0, 1) ** 24 * shine
    shade = cols * (0.38 + 0.72 * diff)[:, None] + 255 * spec[:, None] * 0.8
    s = scale * SS
    xy = Q[..., :2] * s
    xmin, xmax = xy[..., 0].min() - 2, xy[..., 0].max() + 2
    ymin, ymax = xy[..., 1].min() - 2, xy[..., 1].max() + 2
    W, H = int(math.ceil(xmax - xmin)), int(math.ceil(ymax - ymin))
    W += (-W) % SS; H += (-H) % SS
    img = np.zeros((H, W, 3)); z = np.full((H, W), -1e9); a = np.zeros((H, W))
    for t in range(len(Q)):
        v = xy[t] - [xmin, ymin]; v[:, 1] = H - v[:, 1]
        zz = Q[t, :, 2]
        x0, x1 = max(0, int(v[:, 0].min())), min(W - 1, int(v[:, 0].max()) + 1)
        y0, y1 = max(0, int(v[:, 1].min())), min(H - 1, int(v[:, 1].max()) + 1)
        if x1 < x0 or y1 < y0: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = v
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-12: continue
        l0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / d
        l1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / d
        l2 = 1 - l0 - l1
        inside = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        depth = l0 * zz[0] + l1 * zz[1] + l2 * zz[2]
        sub = z[y0:y1 + 1, x0:x1 + 1]
        win = inside & (depth > sub)
        sub[win] = depth[win]
        img[y0:y1 + 1, x0:x1 + 1][win] = shade[t]
        a[y0:y1 + 1, x0:x1 + 1][win] = 1
    # reduce
    h, w = H // SS, W // SS
    a2 = a.reshape(h, SS, w, SS).mean((1, 3))
    rgb = (img * a[..., None]).reshape(h, SS, w, SS, 3).sum((1, 3)) / np.maximum(a.reshape(h, SS, w, SS).sum((1, 3)), 1e-9)[..., None]
    return np.clip(rgb, 0, 255), a2 >= 0.5

def quantize(rgb, mask, pal):
    p = np.frombuffer(pal, np.uint8).reshape(256, 3).astype(float)
    usable = np.arange(1, 256)
    p = p[usable]
    flat = rgb.reshape(-1, 3)
    dist = ((flat[:, None, :] - p[None, :, :]) ** 2).sum(-1)
    idx = usable[dist.argmin(1)].reshape(mask.shape)
    idx[~mask] = 0
    # crop to the drawn pixels, keep the centre
    return [list(map(int, r)) for r in idx]

WEAPONS = [
    # sprite base, model, icon (palette source), palette id, pixels per world unit, tumbles, SFT group, roll
    ('wjav', javelin, '7item031', 2103, 1.0, False, 'Thrownjav', 0),
    ('waxe', axe, '7item023', 2104, 1.5, True, 'Thrownaxe', 30),
    ('wdag', dagger, '7item015', 2105, 1.5, True, 'Throwndag', 40),
]

def main(icons_lod, sprites_lod, bitmaps_lod, outdir, preview=None):
    icons = lod_entries(open(icons_lod, 'rb').read())
    sb = open(sprites_lod, 'rb').read(); sprites = lod_entries(sb)
    bb = open(bitmaps_lod, 'rb').read(); bitmaps = lod_entries(bb)
    for k in [k for k in sprites if k[:4] in ('wjav', 'waxe', 'wdag')]:
        del sprites[k]
    sft = []; shots = []
    letters = 'abcdefgh'
    for base, model, ic, palid, ppu, tumble, group, roll in WEAPONS:
        _, _, _, pal = icon(icons[ic])
        bitmaps['pal%d' % palid] = ('pal%d' % palid).encode().ljust(48, b'\0') + pal
        mesh = model()
        frames = TUMBLE_FRAMES if tumble else 1
        row_imgs = []
        for f in range(frames):
            sname = base + letters[f]
            for v in range(5):
                rgb, mask = render(mesh, math.radians(45 * v), 2 * math.pi * f / frames, ppu, math.radians(roll),
                                   math.radians(PITCH_BY_VIEW[v]))
                img = quantize(rgb, mask, pal)
                sprites[sname + str(v)] = sprite(sname + str(v), img, palid)
                if preview:
                    p = np.frombuffer(pal, np.uint8).reshape(256, 3)
                    arr = p[np.array(img)]; arr[np.array(img) == 0] = (255, 0, 255)
                    pim = Image.fromarray(arr.astype(np.uint8))
                    pim = pim.resize((max(1, round(pim.width / ppu)), max(1, round(pim.height / ppu))))
                    row_imgs.append(pim)
            sft.append([group if f == 0 else '', sname, str(round(65536 / ppu)), '-', 'x' if f == 0 else '-', '-', 'x',
                        '-', '-', '-', '-', '-', '-', '-', 'x', 'x', 'x', '-', '-', '-', '0', str(palid), '2' if tumble else '2'])
        shots.append(row_imgs)
    os.makedirs(outdir, exist_ok=True)
    lod_write(os.path.join(outdir, 'waffel.sprites.lod'), sb, sprites)
    lod_write(os.path.join(outdir, 'waffel.bitmaps.lod'), bb, bitmaps)
    if preview:
        rows = []
        for r in shots:
            for i in range(0, len(r), 5):
                rows.append(r[i:i + 5])
        W = max(sum(i.width + 8 for i in r) for r in rows); H = sum(max(i.height for i in r) + 8 for r in rows)
        out = Image.new('RGB', (W, H), (255, 0, 255)); y = 0
        for r in rows:
            x = 0
            for i in r:
                out.paste(i, (x, y)); x += i.width + 8
            y += max(i.height for i in r) + 8
        out.resize((out.width * 2, out.height * 2), Image.NEAREST).save(preview)
    return sft

if __name__ == '__main__':
    for row in main(*sys.argv[1:6]):
        print('\t'.join(row))
