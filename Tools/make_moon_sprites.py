"""Builds the moon's phase sprites (moonwe1..moonwe7) into a sprites lod (07.11.26).

    python make_moon_sprites.py <picture> <cx> <cy> <disc radius> <bitmaps.lod> <template sprites lod> <out lod> [size=256]

The full moon is cut from the picture (the disc at cx, cy) and shaded for each phase with a
terminator: phase p of the month (0 new, 0.5 full) -> lit where x > w cos(2 pi p) while
waxing (the right side, as seen from the north) and x < -w cos(2 pi p) while waning,
w = sqrt(1 - y^2) for the disc's unit coordinates. The unlit part is transparent (the night
sky shows through); the terminator is dithered over a narrow band. Phases 1..7 =
1/8 .. 7/8 (waxing crescent, first quarter, waxing gibbous, full, waning gibbous, last
quarter, waning crescent); the new moon isn't drawn.

A halo (07.11.26): the lit part, blurred, shows as pale dots around the disc (outside it
only, so a crescent's dark part stays clear), denser near the light; HALO sets how far it
reaches (the disc's radius x HALO is the sprite's half size).

The other sprites already in <out lod> are kept (the sun's): the moon's are added or
replaced. Each phase gets the palette of bitmaps.lod that matches its colours best.

The moon of 07.11.26: moon_phases.jpg 1267 475 211 bitmaps.lod mm6.sprites.lod waffel.sprites.lod
"""
import math, os, struct, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_sun_sprite import sprite_bytes, write_lod, all_palettes, best_palette, lod_entries, BAYER

BAND = 0.08          # terminator half-width (share of the disc radius), dithered
LIMB = 0.985         # the disc edge (share of the radius); the dark sky around is cut
HALO = 1.45          # the sprite's half size in disc radii (room for the halo)
GLOW_BLUR = 0.16     # the halo's blur, in disc radii
GLOW_GAIN = 2.2      # how dense the halo's dots are
GLOW_CUT = 0.05      # below this the halo ends
GLOW_COLOR = (200, 208, 226)

def build(picture, cx, cy, radius, bitmaps, template, out, size=256):
    im = Image.open(picture).convert('RGB')
    margin = radius * HALO
    im = im.crop((round(cx - margin), round(cy - margin), round(cx + margin), round(cy + margin)))
    im = im.resize((size, size), Image.LANCZOS)
    px = im.load()
    R = size / 2
    rd = R / HALO                       # disc radius in the sprite
    import numpy as np
    from PIL import ImageFilter
    pals = all_palettes(bitmaps)
    sprites = []
    for k in range(1, 8):
        p = k / 8
        c = math.cos(2 * math.pi * p)
        def lit(x, y):
            u, v = (x + 0.5 - R) / rd, (y + 0.5 - R) / rd
            if math.hypot(u, v) > LIMB: return 0
            w = math.sqrt(max(0.0, 1 - v * v))
            d = (u - w * c) if p < 0.5 else (-w * c - u)
            return 1 if (p == 0.5 or d > 0) else 0
        mask = Image.new('L', (size, size))
        mask.putdata([255 * lit(x, y) for y in range(size) for x in range(size)])
        glow = np.asarray(mask.filter(ImageFilter.GaussianBlur(GLOW_BLUR * rd)), dtype=float) / 255
        def pixel(x, y, c=c, p=p):
            u, v = (x + 0.5 - R) / rd, (y + 0.5 - R) / rd
            r = math.hypot(u, v)
            if r > LIMB:
                g = min(1.0, glow[y][x] * GLOW_GAIN)
                if g < GLOW_CUT or BAYER[y % 8][x % 8] / 64 >= g * g: return None
                k = 0.75 + 0.25 * g
                return tuple(int(ch * k) for ch in GLOW_COLOR)
            w = math.sqrt(max(0.0, 1 - v * v))
            d = (u - w * c) if p < 0.5 else (-w * c - u)     # > 0 lit
            if p == 0.5: d = 1
            if d < BAND:
                keep = (d + BAND) / (2 * BAND)               # 0 dark .. 1 lit
                if keep <= 0 or BAYER[y % 8][x % 8] / 64 >= keep: return None
            col = px[x, y]
            return col if max(col) > 6 else (8, 8, 8)
        hist = {}
        for y in range(0, size, 2):
            for x in range(0, size, 2):
                col = pixel(x, y)
                if col:
                    q = (col[0] // 8 * 8 + 4, col[1] // 8 * 8 + 4, col[2] // 8 * 8 + 4)
                    hist[q] = hist.get(q, 0) + 1
        pal = best_palette(pals, list(hist.items()))
        name = 'moonwe%d' % k
        sprites.append((name, sprite_bytes(name, pals[pal], pal, size, pixel)))
        print(name, 'palette', pal)
    # keep the sprites already in the archive (the sun's)
    kept = []
    if os.path.exists(out):
        new = {n for n, _ in sprites}
        kept = [(n, b) for n, b in lod_entries(open(out, 'rb').read()) if n not in new]
    write_lod(template, out, kept + sprites)

if __name__ == '__main__':
    a = sys.argv[1:]
    build(a[0], float(a[1]), float(a[2]), float(a[3]), a[4], a[5], a[6], *(int(x) for x in a[7:]))
