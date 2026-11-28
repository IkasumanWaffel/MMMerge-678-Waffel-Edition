"""A horse for the towns (28.11.26): a jointed 3D model rendered into monster sprites, like the thrown
weapons (Tools/thrown_models.py, whose renderer it uses).

Model space: x forward (the head), y up, z to the horse's left; the ground is y = 0; 1 unit is a game
unit (a man is about 180 tall; the horse is about 160 at the withers).

The trunk is one lofted body (TRUNK stations along its length, with the shoulder and hip muscles as
swellings of the sides); neck, head (with a jaw and cheek), tail and the legs are tapered capsules,
with knee / hock and fetlock joints as small swellings. Each leg has three joints posed by angles, so
walking, rearing and falling are poses of the same model. The model is built twice, in the pose and at
rest: the rest positions are each point's texture place, so the coat (painted per pixel by COATS)
stays on the body whatever the pose. Coats after the reference pictures: a chestnut with a blaze and
two socks, a dark draught horse with a blaze and white feathering, an appaloosa (dark forehand, white
spotted hindquarters).
"""
import math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from thrown_models import Mesh

# ---------------------------------------------------------------- geometry recorder

class Geo:
    """Collects triangles as (p0, p1, p2, part); built twice (pose, rest) with the same topology."""
    def __init__(self):
        self.t = []
    def tri(self, a, b, c, part):
        self.t.append((np.asarray(a, float), np.asarray(b, float), np.asarray(c, float), part))
    def quad(self, a, b, c, d, part):
        self.tri(a, b, c, part); self.tri(a, c, d, part)

def frame_from(axis):
    a = np.asarray(axis, float); a = a / np.linalg.norm(a)
    up = np.array([0, 0, 1.0]) if abs(a[2]) < 0.9 else np.array([0, 1.0, 0])
    u = np.cross(a, up); u /= np.linalg.norm(u)
    v = np.cross(a, u)
    return a, u, v

def limb(g, p0, p1, r0, r1, part, n=12, k=9, flat=1.0, cap=0.35):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    a, u, v = frame_from(p1 - p0)
    rings = []
    for i in range(k + 1):
        t = i / k
        r = (r0 + (r1 - r0) * t) * max(0.05, math.sin(math.pi * (0.04 + 0.92 * t))) ** cap
        c = p0 + (p1 - p0) * t
        ring = []
        for j in range(n):
            ang = 2 * math.pi * j / n
            d = u * math.cos(ang) * r + v * math.sin(ang) * r
            d[2] *= flat
            ring.append(c + d)
        rings.append(ring)
    for i in range(k):
        for j in range(n):
            g.quad(rings[i][j], rings[i + 1][j], rings[i + 1][(j + 1) % n], rings[i][(j + 1) % n], part)
    for ring, ctr in ((rings[0], p0), (rings[-1], p1)):
        for j in range(n):
            g.tri(ctr, ring[j], ring[(j + 1) % n], part)

def ellipsoid(g, c, rx, ry, rz, part, n=10, k=6):
    c = np.asarray(c, float); pts = []
    for i in range(k + 1):
        th = math.pi * i / k
        pts.append([c + (rx * math.cos(th), ry * math.sin(th) * math.cos(2 * math.pi * j / n),
                         rz * math.sin(th) * math.sin(2 * math.pi * j / n)) for j in range(n)])
    for i in range(k):
        for j in range(n):
            g.quad(pts[i][j], pts[i + 1][j], pts[i + 1][(j + 1) % n], pts[i][(j + 1) % n], part)

def cone(g, base, tip, r, part, n=8, flat=1.0):
    base, tip = np.asarray(base, float), np.asarray(tip, float)
    a, u, v = frame_from(tip - base)
    ring = []
    for j in range(n):
        d = u * math.cos(2 * math.pi * j / n) * r + v * math.sin(2 * math.pi * j / n) * r * flat
        ring.append(base + d)
    for j in range(n):
        g.tri(tip, ring[j], ring[(j + 1) % n], part)
        g.tri(base, ring[(j + 1) % n], ring[j], part)

def ribbon(g, pts, offs, part):
    for i in range(len(pts) - 1):
        a, b = np.asarray(pts[i], float), np.asarray(pts[i + 1], float)
        g.quad(a, b, b + offs[i + 1], a + offs[i], part)

# trunk stations: x, centre height, radius up, radius down, half width
TRUNK = [(-102, 141, 5, 7, 5), (-98, 141, 17, 20, 16), (-90, 140, 24, 28, 25), (-76, 139, 26, 34, 30),
         (-58, 137, 25, 37, 31), (-38, 134, 21, 35, 31), (-12, 131, 20, 39, 32), (14, 131, 22, 42, 32),
         (36, 134, 25, 44, 30), (54, 137, 28, 43, 27), (70, 139, 25, 40, 24), (82, 140, 18, 32, 19),
         (91, 141, 10, 20, 12), (97, 142, 3, 6, 4)]
# the shoulder (front) and the hip (back) stand out from the sides: (x, y, rx, ry, extra width)
MUSCLES = [(56, 120, 20, 26, 3.5), (-64, 132, 24, 26, 4.0)]

def trunk(g, xf, heavy, n=32, k=46):
    st = np.array(TRUNK, float)
    xs = np.linspace(st[0, 0], st[-1, 0], k)
    prof = np.stack([np.interp(xs, st[:, 0], st[:, i]) for i in range(5)], 1)
    rings = []
    for x, cy, ru, rd, rz in prof:
        ring = []
        for j in range(n):
            ang = 2 * math.pi * j / n
            s, c = math.sin(ang), math.cos(ang)
            y = cy + (ru if s > 0 else rd) * heavy * s
            w = rz * heavy
            for mx, my, mrx, mry, mw in MUSCLES:
                q = ((x - mx) / mrx) ** 2 + ((y - my) / mry) ** 2
                if q < 1: w += mw * heavy * (1 - q) ** 2
            ring.append(xf((x, y, w * c)))
        rings.append(ring)
    for i in range(k - 1):
        for j in range(n):
            g.quad(rings[i][j], rings[i + 1][j], rings[i + 1][(j + 1) % n], rings[i][(j + 1) % n], 'body')
    for ring in (rings[0], rings[-1]):
        ctr = np.mean(ring, axis=0)
        for j in range(n):
            g.tri(ctr, ring[j], ring[(j + 1) % n], 'body')

# ---------------------------------------------------------------- the horse

FRONT_X, HIND_X, LEG_Z = 58, -62, 15
FRONT = (46, 38, 24)          # forearm, cannon, pastern (elbow to the ground)
HIND = (52, 42, 24)           # gaskin, cannon, pastern (stifle to the ground)

def leg_points(top, lengths, angles):
    pts = [np.asarray(top, float)]; a = 0.0
    for L, d in zip(lengths, angles):
        a += d
        pts.append(pts[-1] + (L * math.sin(a), -L * math.cos(a), 0))
    return pts

def geometry(pose, heavy=1.0, feathers=False):
    g = Geo()
    pitch = pose.get('body', 0.0); lift = pose.get('height', 0.0)
    piv = np.array(pose.get('pivot', (0, 120, 0)), float)

    def xf(p):
        p = np.asarray(p, float) - piv
        c, s = math.cos(pitch), math.sin(pitch)
        return np.array([p[0] * c - p[1] * s, p[0] * s + p[1] * c, p[2]]) + piv + (0, lift, 0)

    trunk(g, xf, heavy)
    # neck
    na, ha = pose.get('neck', 0.0), pose.get('head', 0.0)
    base = xf((76, 148, 0))
    a1 = math.radians(60) + na + pitch
    ndir = np.array([math.cos(a1), math.sin(a1), 0])
    nup = np.array([-ndir[1], ndir[0], 0])                  # towards the crest
    top = base + ndir * 64
    limb(g, base - ndir * 22 - nup * 8, top, 31 * heavy, 14 * heavy, 'neck', n=20, k=14, flat=0.56, cap=0.1)
    # head: skull to muzzle, with the round cheek (jaw) below and behind the eye
    a2 = math.radians(-58) + ha + na + pitch
    hd = np.array([math.cos(a2), math.sin(a2), 0])
    up = np.array([-hd[1], hd[0], 0])
    if up[1] < 0: up = -up                                  # towards the forehead
    muzzle = top + hd * 54
    limb(g, top - hd * 5 + up * 1, muzzle, 12.5, 9.0, 'head', n=16, k=12, flat=0.66, cap=0.3)
    ellipsoid(g, top + hd * 12 - up * 7, 13, 11, 9.5 * 0.9, 'head', n=14, k=8)
    limb(g, muzzle - hd * 12 - up * 1, muzzle + hd * 3, 9.8, 8.2, 'muzzle', n=14, k=6, flat=0.84, cap=0.55)
    for zs in (1, -1):
        ellipsoid(g, top + hd * 15 + up * 4 + (0, 0, zs * 8.0), 3.0, 3.0, 1.6, 'eye', n=10, k=5)
        ellipsoid(g, muzzle + hd * 1.5 + up * 3 + (0, 0, zs * 5.2), 2.0, 2.6, 1.2, 'nostril', n=8, k=4)
        ear = top - hd * 3 + up * 8 + (0, 0, zs * 5)
        cone(g, ear, ear + up * 12 - hd * 3 + (0, 0, zs * 1.8), 3.4, 'ear', n=8, flat=0.6)
    # mane: strands falling from the crest to both sides, and a forelock
    for side, drop in ((1, 17), (-1, 13)):
        for s in range(4):
            crest = [base + ndir * (66 * t) + nup * (17 - 8 * t) * heavy + (0, 0, side * (s - 1) * 1.2)
                     for t in np.linspace(0, 1, 11)]
            ribbon(g, crest, [np.array((-1.5 - s, -drop + 4 * t + s, side * (6 + s))) for t in np.linspace(0, 1, 11)], 'mane')
    f0 = top + up * 8
    ribbon(g, [f0, f0 + hd * 14], [np.array((0, 0, 4.5)), np.array((0, 0, -4.5))], 'mane')
    # tail: a dock and a fall of hair
    ta, ts = pose.get('tail', 0.0), pose.get('tail_side', 0.0)
    t0 = xf((-97, 146, 0))
    t1 = t0 + np.array([-math.sin(math.radians(28) + ta), -math.cos(math.radians(28) + ta), ts * 0.3]) * 26
    t2 = t1 + np.array([-0.18 + 0.4 * math.sin(ta), -1, ts]) / 1.05 * 68
    limb(g, t0, t1, 6, 8, 'tail', n=8, k=5)
    limb(g, t1, t2, 8.5, 12.5, 'tail', n=12, k=8, flat=0.55, cap=0.7)
    # legs
    for name, x, z, lengths, ur in (('lf', FRONT_X, LEG_Z, FRONT, 14.0), ('rf', FRONT_X, -LEG_Z, FRONT, 14.0),
                                     ('lh', HIND_X, LEG_Z, HIND, 19.0), ('rh', HIND_X, -LEG_Z, HIND, 19.0)):
        topp = xf((x, 110 if name[1] == 'f' else 116, z))
        pts = leg_points(topp, lengths, pose['legs'][name])
        part = 'leg_' + name
        limb(g, pts[0] + (0, 26, 0), pts[1], ur * heavy, 7.4 * heavy, part, n=14, k=10, cap=0.25)
        u1 = (pts[2] - pts[1]) / np.linalg.norm(pts[2] - pts[1])
        limb(g, pts[1] - u1 * 5, pts[2] + u1 * 3, 6.6 * heavy, 5.6 * heavy, part, n=12, k=7, cap=0.45)   # knee / hock to fetlock
        limb(g, pts[2] - u1 * 3, pts[3] + (pts[2] - pts[3]) * 0.12, 6.0 * heavy, 5.6 * heavy, part, n=12, k=5, cap=0.45)
        d = pts[3] - pts[2]; d /= np.linalg.norm(d)
        limb(g, pts[3] - d * 5, pts[3] + d * 2.5, 6.6 * heavy, 7.6 * heavy, 'hoof', n=14, k=3, cap=0.12)
        if feathers:
            limb(g, pts[2] + (pts[1] - pts[2]) * 0.5, pts[3] + d * 1.2, 6.5 * heavy, 13 * heavy, 'feather',
                 n=16, k=7, cap=0.08)
    return g

# ---------------------------------------------------------------- coats (per pixel, at rest)

def _hash(c, seed):
    c = c.astype(np.int64)
    h = (c[:, 0] * 73856093) ^ (c[:, 1] * 19349663) ^ (c[:, 2] * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xffff) / 65535.0

def spots(P, size, density, seed=1, rmin=0.18, rmax=0.42):
    cell = np.floor(P / size)
    hit = np.zeros(len(P), bool)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                c = cell + (dx, dy, dz)
                ok = _hash(c, seed) < density
                o = (c + np.stack([_hash(c, seed + 11), _hash(c, seed + 23), _hash(c, seed + 37)], 1)) * size
                r = size * (rmin + (rmax - rmin) * _hash(c, seed + 51))
                hit |= ok & (np.linalg.norm(P - o, axis=1) < r)
    return hit

def mix(mask, a, b):
    return np.where(mask[:, None], np.array(a, float), np.array(b, float))

REST = {'legs': {'lf': (0.0, 0.0, 0.08), 'rf': (0.0, 0.0, 0.08), 'lh': (0.1, -0.3, 0.24), 'rh': (0.1, -0.3, 0.24)}}
_a1 = math.radians(60); _a2 = math.radians(-58)
REST_HEAD_TOP = np.array((76, 148, 0)) + np.array([math.cos(_a1), math.sin(_a1), 0]) * 64
REST_HD = np.array([math.cos(_a2), math.sin(_a2), 0])
REST_UP = np.array([-REST_HD[1], REST_HD[0], 0]) * (1 if REST_HD[0] >= 0 else -1)

def blaze(P, width):
    d = P - REST_HEAD_TOP
    along = d @ REST_HD; upness = d @ REST_UP
    return (np.abs(P[:, 2]) < width * (0.7 + 0.5 * np.clip(1 - along / 50, 0, 1))) & (upness > -2) & (along > -4)

def shade_y(base, P, lo=0.9):
    return base * (lo + (1 - lo) * np.clip((P[:, 1] - 90) / 70, 0, 1))[:, None]

def coat_chestnut(P, part):
    n = len(P); base = shade_y(np.tile((176, 90, 46), (n, 1)).astype(float), P)
    if part == 'hoof': return np.tile((76, 64, 54), (n, 1))
    if part in ('mane', 'tail'): return np.tile((96, 50, 30), (n, 1))
    if part == 'eye': return np.tile((25, 18, 14), (n, 1))
    if part == 'nostril': return np.tile((60, 36, 30), (n, 1))
    if part == 'muzzle': return mix(blaze(P, 3.5), (214, 190, 176), np.tile((130, 78, 56), (n, 1)))
    if part == 'head': return mix(blaze(P, 4.5), (238, 232, 222), base)
    if part in ('leg_lf', 'leg_rh'): return mix(P[:, 1] < 24, (232, 226, 214), base * 0.9)
    if part.startswith('leg_'): return base * 0.9
    return base

def coat_draught(P, part):
    n = len(P); base = shade_y(np.tile((48, 36, 34), (n, 1)).astype(float), P, 0.85)
    if part == 'hoof': return np.tile((84, 74, 64), (n, 1))
    if part in ('mane', 'tail'): return np.tile((32, 25, 23), (n, 1))
    if part == 'eye': return np.tile((14, 10, 10), (n, 1))
    if part == 'nostril': return np.tile((90, 60, 56), (n, 1))
    if part == 'feather': return np.tile((236, 232, 226), (n, 1))
    if part == 'muzzle': return mix(blaze(P, 3.8), (196, 160, 150), np.tile((140, 104, 94), (n, 1)))
    if part == 'head': return mix(blaze(P, 5.2), (236, 232, 226), base)
    if part.startswith('leg_'): return mix(P[:, 1] < 34, (236, 232, 226), base)
    return base

def coat_appaloosa(P, part):
    n = len(P); dark = np.array((42, 33, 31), float); white = np.array((236, 232, 224), float)
    if part == 'hoof': return np.tile((206, 178, 140), (n, 1))
    if part in ('mane', 'tail'): return np.tile((30, 24, 22), (n, 1))
    if part == 'eye': return np.tile((14, 10, 10), (n, 1))
    if part == 'nostril': return np.tile((20, 16, 14), (n, 1))
    if part in ('head', 'muzzle', 'ear'): return np.tile(dark, (n, 1))
    x, y = P[:, 0], P[:, 1]
    if part.startswith('leg_'):
        w = np.full(n, 0.02) + (part[-1] == 'h') * np.clip((y - 80) / 30, 0, 0.8)
        w = w + (part in ('leg_lh', 'leg_rh')) * (y < 20) * 0.95                # white hind socks
    elif part == 'neck':
        w = np.full(n, 0.22)
    else:
        w = np.clip(0.5 + 0.5 * np.tanh((22 - x) / 9 + (y - 122) / 20), 0, 1)
    patch = _hash(np.floor(P / 2.2), 7) < w                                       # roaned blanket edge
    out = mix(patch, white, dark)
    dark_spots = spots(P, 9, 0.6, seed=3, rmin=0.16, rmax=0.34)
    flecks = spots(P, 7, 0.25, seed=5, rmin=0.1, rmax=0.2)
    out = np.where((patch & dark_spots)[:, None], dark, out)
    out = np.where((~patch & flecks)[:, None], white, out)
    return out

COATS = {'a': (coat_chestnut, 1.0, False), 'b': (coat_draught, 1.1, True), 'c': (coat_appaloosa, 1.0, False)}

def build(coat, pose):
    shader, heavy, feathers = COATS[coat]
    g = geometry(pose, heavy, feathers)
    r = geometry(REST, heavy, feathers)
    m = Mesh()
    for (a, b, c, part), (ra, rb, rc, _) in zip(g.t, r.t):
        m.tri(a, b, c, (128, 128, 128), 0.0, (ra, rb, rc), part)
    return m, shader

# ---------------------------------------------------------------- poses

STAND = REST['legs']

def walk_pose(phase):
    """Four-beat walk: left hind, left fore, right hind, right fore a quarter apart; a leg spends
    35% of the cycle in the air, its knee / hock folding and the hoof flipping back."""
    legs = {}
    for name, off in (('lh', 0.0), ('lf', 0.25), ('rh', 0.5), ('rf', 0.75)):
        ph = (phase + off) % 1.0
        if ph < 0.35:                                    # swing
            s = math.sin(math.pi * ph / 0.35); u = ph / 0.35
            if name[1] == 'f':
                legs[name] = (-0.22 + 0.62 * u, -1.05 * s, -0.35 * s + 0.08)
            else:
                legs[name] = (-0.22 + 0.58 * u, -0.3 - 0.55 * s, 0.24 + 0.55 * s)
        else:                                            # stance: the hoof stays, the body passes over
            u = (ph - 0.35) / 0.65
            if name[1] == 'f':
                legs[name] = (0.4 - 0.62 * u, 0.0, 0.08 + 0.12 * u)
            else:
                legs[name] = (0.36 - 0.58 * u, -0.3, 0.24)
    return {'legs': legs, 'neck': 0.05 * math.sin(4 * math.pi * phase), 'head': 0.0,
            'tail': 0.06 * math.sin(2 * math.pi * phase), 'height': 1.2 * math.cos(4 * math.pi * phase)}
