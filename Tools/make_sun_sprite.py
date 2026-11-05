"""Builds the sun sprite (sunwe) into Data/waffel.sprites.lod (05.11.26, 06.11.26).

    python make_sun_sprite.py <bitmaps.lod> <template sprites lod> <out lod> [size=128] [palette=230]
    python make_sun_sprite.py --image <picture> <cx> <cy> <radius> <bitmaps.lod> <template sprites lod> <out lod> [size=256] [palette=536] [edge=0.85] [falloff=1]

--image: the sun is cut from a picture: the circle at cx, cy (pixels) of the given radius,
scaled to size x size. Sprites have no partial transparency, so the outer part of the circle
(from EDGE of the radius) is dithered: fewer and fewer pixels are kept toward the edge, which
reads as a soft edge from afar. falloff above 1 thins the dots out faster (a softer halo). Palette 536 matches a white and yellow-orange sun closely.

The sun of 06.11.26: --image sun_photo.jpg 941.5 542.5 360 ... 256 536 0.64 1.6

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

def build(bitmaps, template, out, size=128, pal=230, pixel=None):
    P = palette(bitmaps, pal)
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
    hdr = b'sunwe'.ljust(12, b'\0') + struct.pack('<IHHHHHHI', len(packed), size, size, pal, 0, 0, 0, len(data))
    sprite = hdr + table + packed
    # archive: the 0x100-byte header of a sprites lod, one directory entry, the sprite
    t = open(template, 'rb').read()
    head = bytearray(t[:0x120])
    struct.pack_into('<I', head, 0x114, 32 + len(sprite))
    struct.pack_into('<I', head, 0x11C, 1)
    entry = b'sunwe'.ljust(16, b'\0') + struct.pack('<IIII', 32, len(sprite), 0, 0)
    open(out, 'wb').write(bytes(head) + entry + sprite)
    return len(sprite)

if __name__ == '__main__':
    a = sys.argv[1:]
    if a and a[0] == '--image':
        pic, cx, cy, rad = a[1], float(a[2]), float(a[3]), float(a[4])
        size = int(a[8]) if len(a) > 8 else 256
        pal = int(a[9]) if len(a) > 9 else 536
        edge = float(a[10]) if len(a) > 10 else EDGE
        falloff = float(a[11]) if len(a) > 11 else 1.0
        print(build(a[5], a[6], a[7], size, pal, image_pixels(pic, cx, cy, rad, size, edge, falloff)))
    else:
        print(build(a[0], a[1], a[2], *(int(x) for x in a[3:])))
