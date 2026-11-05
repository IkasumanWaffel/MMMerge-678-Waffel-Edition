"""Builds the placeholder sun sprite (sunwe) into Data/waffel.sprites.lod (05.11.26).

    python make_sun_sprite.py <bitmaps.lod> <template sprites lod> <out lod> [size=128] [palette=230]

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

def build(bitmaps, template, out, size=128, pal=230):
    P = palette(bitmaps, pal)
    def nearest(c):
        return min(range(1, 256), key=lambda i: (P[i][0]-c[0])**2 + (P[i][1]-c[1])**2 + (P[i][2]-c[2])**2)
    cache = {}
    R = size / 2
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            r = math.hypot(x + 0.5 - R, y + 0.5 - R)
            c = sun_rgb(r, R)
            if c is None or max(c) < 8:
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
    print(build(a[0], a[1], a[2], *(int(x) for x in a[3:])))
