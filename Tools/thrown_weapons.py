"""Thrown weapon projectiles (27.11.26): javelins, hand axes and throwing daggers made from the
MM7 item pictures (mm7.icons.lod 7item031 Crude Spear, 7item023 Crude Axe, 7item015 Dagger).

The side view (frame 2, the weapon pointing right) is the picture turned on its side; the angled
views are the same picture narrowed in proportion to the look angle (frames 1 and 3: 0.7, frames 0
and 4, straight at or away from the eye: almost flat). Axes and daggers tumble: four frames, a
quarter turn each, before the narrowing. Frames 5-7 are mirrors (SFT).

Writes waffel.sprites.lod (the existing entries kept), waffel.bitmaps.lod (palettes pal2103-2105,
the pictures' own) and prints the SFT.txt and ObjList.txt rows.
usage: thrown_weapons.py mm7.icons.lod waffel.sprites.lod waffel.bitmaps.lod outdir
"""
import struct, zlib, sys, os

def lod_entries(b):
    cnt = struct.unpack_from('<I', b, 0x11c)[0]
    out = {}
    for i in range(cnt):
        o = 0x120 + i * 32
        n = b[o:o + 16].split(b'\0')[0].decode('latin1')
        off, size = struct.unpack_from('<II', b, o + 16)
        out[n] = b[0x120 + off:0x120 + off + size]
    return out

def lod_write(path, template, entries):
    names = sorted(entries, key=str.lower)
    dirsize = 32 * len(names)
    blob = bytearray(); table = bytearray()
    for n in names:
        d = entries[n]
        table += n.encode('latin1').ljust(16, b'\0') + struct.pack('<IIII', dirsize + len(blob), len(d), 0, 0)
        blob += d
    head = bytearray(template[:0x120])
    struct.pack_into('<II', head, 0x114, len(table) + len(blob), 0)
    struct.pack_into('<I', head, 0x11c, len(names))
    open(path, 'wb').write(bytes(head) + bytes(table) + bytes(blob))

def icon(d):
    usize = struct.unpack_from('<I', d, 40)[0]
    dsize, w, h = struct.unpack_from('<IHH', d, 20)
    raw = d[48:48 + dsize]
    pix = zlib.decompress(raw) if usize else raw
    return w, h, [list(pix[y * w:(y + 1) * w]) for y in range(h)], d[48 + dsize:48 + dsize + 768]

def rot90cw(img):          # rows -> rotated 90 degrees clockwise
    h, w = len(img), len(img[0])
    return [[img[h - 1 - x][y] for x in range(h)] for y in range(w)]

def trim(img):
    rows = [y for y, r in enumerate(img) if any(r)]
    cols = [x for x in range(len(img[0])) if any(r[x] for r in img)]
    return [r[cols[0]:cols[-1] + 1] for r in img[rows[0]:rows[-1] + 1]]

def resize(img, w2, h2):   # nearest neighbour
    h, w = len(img), len(img[0])
    return [[img[min(h - 1, y * h // h2)][min(w - 1, x * w // w2)] for x in range(w2)] for y in range(h2)]

def pad_square(img):
    h, w = len(img), len(img[0]); s = max(w, h)
    out = [[0] * s for _ in range(s)]
    oy, ox = (s - h) // 2, (s - w) // 2
    for y in range(h):
        out[oy + y][ox:ox + w] = img[y]
    return out

def narrow(img, f):
    h, w = len(img), len(img[0]); w2 = max(3, round(w * f))
    out = resize(img, w2, h)
    if f < 0.3:   # keep the outline readable when seen end-on: a thin silhouette
        out = [[v for v in r] for r in out]
    return out

def sprite(name, img, pal):
    h, w = len(img), len(img[0])
    lines = []; data = bytearray()
    for r in img:
        xs = [x for x, v in enumerate(r) if v]
        if not xs:
            lines.append((-1, -1, 0)); continue
        s, e = xs[0], xs[-1]
        lines.append((s, e, len(data))); data += bytes(r[s:e + 1])
    last = max(y for y, l in enumerate(lines) if l[0] >= 0)
    z = zlib.compress(bytes(data), 9)
    head = name.encode('latin1').ljust(12, b'\0') + struct.pack('<IHHHHHHI', len(z), w, h, pal, 0, h - 1 - last, 0, len(data))
    return head + b''.join(struct.pack('<hhI', *l) for l in lines) + z

VIEWS = {0: 0.12, 1: 0.7, 2: 1.0, 3: 0.7, 4: 0.12}
WEAPONS = [
    # base name, icon, palette, length in pixels of the side view, SFT scale, tumbling
    ('wjav', '7item031', 2103, 240, 65536, False),
    ('waxe', '7item023', 2104, 114, 52000, True),
    ('wdag', '7item015', 2105, 100, 45000, True),
]

def main(icons_lod, sprites_lod, bitmaps_lod, outdir):
    icons = lod_entries(open(icons_lod, 'rb').read())
    sb = open(sprites_lod, 'rb').read(); sprites = lod_entries(sb)
    bb = open(bitmaps_lod, 'rb').read(); bitmaps = lod_entries(bb)
    sft = []
    for base, ic, palid, length, scale, tumble in WEAPONS:
        w, h, img, pal = icon(icons[ic])
        bitmaps['pal%d' % palid] = ('pal%d' % palid).encode().ljust(48, b'\0') + pal
        side = trim(rot90cw(img))                     # point to the right
        sh = max(1, round(len(side) * length / len(side[0])))
        side = resize(side, length, sh)
        frames = []
        if tumble:
            sq = pad_square(side)
            f = sq
            for k in range(4):
                frames.append(f); f = rot90cw(f)
            # a throw turns forward (top towards the target): clockwise in the right-pointing view
        else:
            frames = [side]
        letters = 'abcd'
        for fi, fr in enumerate(frames):
            sname = base + (letters[fi] if tumble else 'a')
            for v, f in VIEWS.items():
                sprites[sname + str(v)] = sprite(sname + str(v), narrow(fr, f), palid)
            group = ('Thrown' + base[1:]) if fi == 0 else ''
            sft.append([group, sname, str(scale), '-', 'x' if fi == 0 else '-', '-', 'x', '-', '-',
                        '-', '-', '-', '-', '-', 'x', 'x', 'x', '-', '-', '-', '0', str(palid), '3' if tumble else '2'])
    os.makedirs(outdir, exist_ok=True)
    lod_write(os.path.join(outdir, 'waffel.sprites.lod'), sb, sprites)
    lod_write(os.path.join(outdir, 'waffel.bitmaps.lod'), bb, bitmaps)
    return sft

if __name__ == '__main__':
    for row in main(*sys.argv[1:5]):
        print('\t'.join(row))
