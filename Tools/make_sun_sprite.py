"""Builds the sun sprite (sunwe) into Data/waffel.sprites.lod (05.11.26, 06.11.26).

    python make_sun_sprite.py <bitmaps.lod> <template sprites lod> <out lod> [size=128] [palette=230]
    python make_sun_sprite.py --image <picture> <cx> <cy> <radius> <bitmaps.lod> <template sprites lod> <out lod> [size=256] [palette=536] [edge=0.85] [falloff=1]

--image: the sun is cut from a picture: the circle at cx, cy (pixels) of the given radius,
scaled to size x size. Sprites have no partial transparency, so the outer part of the circle
(from EDGE of the radius) is dithered: fewer and fewer pixels are kept toward the edge, which
reads as a soft edge from afar. falloff above 1 thins the dots out faster (a softer halo). Palette 536 matches a white and yellow-orange sun closely.

    python make_sun_sprite.py --set <picture> <cx> <cy> <radius> <bitmaps.lod> <template sprites lod> <out lod> [size=256] [edge] [falloff]

--set: the four suns by height (sunwe white, sunwe1 golden, sunwe2 orange, sunwe3 red: TINTS),
each with the palette of bitmaps.lod that matches its colours best.

The suns of 06.11.26: --set sun_photo.jpg 941.5 542.5 360 bitmaps.lod mm6.sprites.lod waffel.sprites.lod 256 0.64 1.6

Without --image, the placeholder:
The picture: a white core, a yellow-orange glow fading to black. Palette index 0 is
transparent; the SFT frame draws it with Glow (added light), so the dark edge melts into
the sky. Colours are the nearest of the palette (palNNN in bitmaps.lod).
"""
import struct, sys, zlib, math

def lod_entries(d):
    n = struct.unpack('<I', d[0x11C:0x120])[0]
    for i in range(n):
        e = d[0x120 + i*32: 0x120 + (i+1)*32]
        name = e[:16].split(b'\0')[0].decode('latin1'); o, s = struct.unpack('<II', e[16:24])
        yield name, d[0x120 + o: 0x120 + o + s]

def palette(bitmaps, pal):
    for name, b in lod_entries(open(bitmaps, 'rb').read()):
        if name.lower() == 'pal%03d' % pal:
            return [tuple(b[48 + i*3: 51 + i*3]) for i in range(256)]
    raise SystemExit('no palette %d' % pal)

def sun_rgb(r, R):
    """colour at distance r of a sun of half-size R (0..1 brightness ramp)"""
    core = 0.18 * R
    if r <= core:
        return (255, 255, 235)
    t = (r - core) / (R - core)
    if t >= 1: return None
    k = (1 - t) ** 2.2                      # glow falloff
    g = 235 - 135 * t                       # whiter inside, oranger outside
    b = 120 * (1 - t) ** 4
    return (int(255 * k), int(g * k), int(b * k))

EDGE = 0.85

# 8x8 ordered dithering thresholds (0..1)
BAYER = [[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
         [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
         [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
         [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]

def image_pixels(picture, cx, cy, radius, size, edge=EDGE, falloff=1.0):
    from PIL import Image
    im = Image.open(picture).convert('RGB')
    im = im.crop((round(cx - radius), round(cy - radius), round(cx + radius), round(cy + radius)))
    im = im.resize((size, size), Image.LANCZOS)
    px = im.load()
    R = size / 2
    def pixel(x, y):
        r = math.hypot(x + 0.5 - R, y + 0.5 - R) / R
        if r >= 1: return None
        if r > edge:
            keep = (1 - (r - edge) / (1 - edge)) ** falloff   # 1 at edge .. 0 at the rim
            if BAYER[y % 8][x % 8] / 64 >= keep: return None
        return px[x, y]
    return pixel

def sprite_bytes(name, P, pal, size, pixel=None):
    """a sprite of size x size; pixel(x, y) gives the colour or None (transparent)"""
    def nearest(c):
        return min(range(1, 256), key=lambda i: (P[i][0]-c[0])**2 + (P[i][1]-c[1])**2 + (P[i][2]-c[2])**2)
    cache = {}
    R = size / 2
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            if pixel:
                c = pixel(x, y)
            else:
                c = sun_rgb(math.hypot(x + 0.5 - R, y + 0.5 - R), R)
                if c and max(c) < 8: c = None
            if c is None:
                row.append(0)
            else:
                if c not in cache: cache[c] = nearest(c)
                row.append(cache[c])
        rows.append(row)
    # sprite: name[12], packed size, w, h, palette, 0, yskip, 0, unpacked size; line table; zlib data
    table = b''; data = b''
    for row in rows:
        nz = [i for i, v in enumerate(row) if v]
        if not nz:
            table += struct.pack('<hhI', -1, -1, 0)
            continue
        x1, x2 = nz[0], nz[-1]
        table += struct.pack('<hhI', x1, x2, len(data))
        data += bytes(row[x1:x2 + 1])
    packed = zlib.compress(data, 9)
    hdr = name.encode().ljust(12, b'\0') + struct.pack('<IHHHHHHI', len(packed), size, size, pal, 0, 0, 0, len(data))
    return hdr + table + packed

def write_lod(template, out, sprites):
    """archive: the 0x100-byte header of a sprites lod, the directory, the sprites. The
    directory must be sorted by name: the game looks names up by binary search (07.11.26:
    with the moon's sprites written after the sun's, the sun's weren't found)"""
    sprites = sorted(sprites, key=lambda e: e[0].lower())
    t = open(template, 'rb').read()
    head = bytearray(t[:0x120])
    dirsize = 32 * len(sprites)
    entries = b''; blobs = b''
    for name, b in sprites:
        entries += name.encode().ljust(16, b'\0') + struct.pack('<IIII', dirsize + len(blobs), len(b), 0, 0)
        blobs += b
    struct.pack_into('<I', head, 0x114, dirsize + len(blobs))
    struct.pack_into('<I', head, 0x11C, len(sprites))
    open(out, 'wb').write(bytes(head) + entries + blobs)

def build(bitmaps, template, out, size=128, pal=230, pixel=None):
    b = sprite_bytes('sunwe', palette(bitmaps, pal), pal, size, pixel)
    write_lod(template, out, [('sunwe', b)])
    return len(b)

# --set: the sun by its height: white high up, golden, orange and red toward the horizon.
# A colour of the picture is multiplied by the tint (the white disc becomes the tint).
TINTS = [('sunwe',  (1.00, 1.00, 1.00)),
         ('sunwe1', (1.00, 0.88, 0.58)),
         ('sunwe2', (1.00, 0.64, 0.30)),
         ('sunwe3', (1.00, 0.40, 0.16))]

def all_palettes(bitmaps):
    pals = {}
    for name, b in lod_entries(open(bitmaps, 'rb').read()):
        n = name.lower()
        if n.startswith('pal') and n[3:].isdigit() and len(b) >= 48 + 768:
            pals[int(n[3:])] = [tuple(b[48 + i*3: 51 + i*3]) for i in range(256)]
    return pals

def best_palette(pals, colours):
    """the palette closest to the colours (a list of (colour, count))"""
    best = None
    for k, P in pals.items():
        err = 0
        for c, n in colours:
            err += n * min((P[i][0]-c[0])**2 + (P[i][1]-c[1])**2 + (P[i][2]-c[2])**2 for i in range(1, 256))
        if best is None or err < best[0]: best = (err, k)
    return best[1]

def build_set(picture, cx, cy, radius, bitmaps, template, out, size=256, edge=EDGE, falloff=1.0):
    base = image_pixels(picture, cx, cy, radius, size, edge, falloff)
    pals = all_palettes(bitmaps)
    sprites = []
    for name, (tr, tg, tb) in TINTS:
        def pixel(x, y, tr=tr, tg=tg, tb=tb):
            c = base(x, y)
            return c and (round(c[0]*tr), round(c[1]*tg), round(c[2]*tb))
        hist = {}
        for y in range(0, size, 2):
            for x in range(0, size, 2):
                c = pixel(x, y)
                if c:
                    q = (c[0] // 8 * 8 + 4, c[1] // 8 * 8 + 4, c[2] // 8 * 8 + 4)
                    hist[q] = hist.get(q, 0) + 1
        pal = best_palette(pals, list(hist.items()))
        sprites.append((name, sprite_bytes(name, pals[pal], pal, size, pixel)))
        print(name, 'palette', pal)
    write_lod(template, out, sprites)

if __name__ == '__main__':
    a = sys.argv[1:]
    if a and a[0] == '--set':
        pic, cx, cy, rad = a[1], float(a[2]), float(a[3]), float(a[4])
        size = int(a[8]) if len(a) > 8 else 256
        edge = float(a[9]) if len(a) > 9 else EDGE
        falloff = float(a[10]) if len(a) > 10 else 1.0
        build_set(pic, cx, cy, rad, a[5], a[6], a[7], size, edge, falloff)
    elif a and a[0] == '--image':
        pic, cx, cy, rad = a[1], float(a[2]), float(a[3]), float(a[4])
        size = int(a[8]) if len(a) > 8 else 256
        pal = int(a[9]) if len(a) > 9 else 536
        edge = float(a[10]) if len(a) > 10 else EDGE
        falloff = float(a[11]) if len(a) > 11 else 1.0
        print(build(a[5], a[6], a[7], size, pal, image_pixels(pic, cx, cy, rad, size, edge, falloff)))
    else:
        print(build(a[0], a[1], a[2], *(int(x) for x in a[3:])))
