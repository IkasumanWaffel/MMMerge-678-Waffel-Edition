"""Make the game's bitmap fonts (*.fnt of EnglishT.lod) anew from a TrueType font, for a
language whose letters the original fonts don't have (Cyrillic in Windows-1251 for Russian).

    python Tools/make_fonts.py <folder with the original .fnt files> <font.ttf> <out folder> [code page]

Each new font keeps the original's height, baseline, cap height, space width and kind of shadow
(none, a drop shadow to the right and below, or an outline), so the game's layouts still fit;
the letters come from the TrueType font, in the given code page (default cp1251).
MMMWE_Fonts.lua loads them from Data\\Text localization\\<Language>\\Fonts when that language
is chosen.
"""
import os, sys, struct
from PIL import Image, ImageDraw, ImageFont

HDR = 32
SKIP = {'calig.fnt'}       # not a font of this format (its metrics are garbage), unused


def load(path):
    b = open(path, 'rb').read()
    h = b[5]
    abc = [list(struct.unpack_from('<iii', b, HDR + i * 12)) for i in range(256)]
    offs = struct.unpack_from('<256I', b, HDR + 3072)
    glyphs = {}
    for c in range(b[0], b[1] + 1):
        l, w, r = abc[c]
        o = HDR + 3072 + 1024 + offs[c]
        if w < 0 or o + w * h > len(b):
            continue
        glyphs[c] = [list(b[o + y * w:o + y * w + w]) for y in range(h)]
    return b, h, abc, glyphs


def rows_of(g):
    return [y for y in range(len(g)) if any(g[y])]


def style(glyphs, ink):
    """'none', 'drop' (shadow right/below) or 'outline' (shadow around) and the shadow value"""
    left = right = total = 0
    for g in glyphs.values():
        h = len(g)
        w = len(g[0]) if h else 0
        for y in range(h):
            for x in range(w):
                if g[y][x] == ink:
                    total += 1
                    if x > 0 and g[y][x - 1] == 1: left += 1
                    if x + 1 < w and g[y][x + 1] == 1: right += 1
    if ink == 1 or right < total * 0.05:
        return 'none'
    return 'outline' if left > right * 0.5 else 'drop'


_cmap = {}
def has_glyph(ttf, ch):
    if ttf not in _cmap:
        from fontTools.ttLib import TTFont
        _cmap[ttf] = set(TTFont(ttf).getBestCmap())
    return ord(ch) in _cmap[ttf]


def render(ttf, size, ch):
    f = ImageFont.truetype(ttf, size)
    asc, desc = f.getmetrics()
    W = size * 3
    img = Image.new('L', (W, asc + desc + 4), 0)
    ImageDraw.Draw(img).text((size, 2), ch, font=f, fill=255)
    return img, asc + 2, f


def height_of(ttf, size, chars, thr):
    hs = []
    for ch in chars:
        bb = render(ttf, size, ch)[0].point(lambda v: 255 if v >= thr else 0).getbbox()
        if bb: hs.append(bb[3] - bb[1])
    hs.sort()
    return hs[len(hs) // 2] if hs else 0


def pick_size(ttf, cap, xh):
    """the pixel size whose capitals and small letters come closest to the original's"""
    best = None
    for s in range(6, 60):
        thr = threshold(s)
        c, x = height_of(ttf, s, 'EFHILNT', thr), height_of(ttf, s, 'xzvwnmu', thr)
        err = abs(c - cap) + 1.5 * abs(x - xh)
        if best is None or err < best[1]:
            best = (s, err)
        if c > cap + 4: break
    return best[0]


def threshold(size):
    return 60 if size < 18 else (85 if size < 26 else 110)


# letters the TrueType font may lack, drawn from others
FALLBACK = {'\u2014': '\u2013', '\u2013': '-', '\u2116': 'N\u00b0', '\u2026': '...', '\u2122': 'TM',
            '\u201e': ',,', '\u201c': '"', '\u201d': '"', '\u2018': "'", '\u2019': "'"}


def make(src, ttf, out, cp='cp1251'):
    b, h, abc, glyphs = load(src)
    first, last = b[0], b[1]
    ink = 255 if any(255 in row for g in glyphs.values() for row in g) else 1
    st = style(glyphs, ink)
    def med(chars):
        hs = sorted(len(rows_of(glyphs[ord(c)])) for c in chars if ord(c) in glyphs and rows_of(glyphs[ord(c)]))
        return hs[len(hs) // 2]
    H = rows_of(glyphs[ord('H')])
    base = H[-1]                          # the original's baseline row
    cap, xh = med('EFHILNT'), med('xzvwnmu')
    if st != 'none':                      # the shadow adds a row to the originals' letters
        cap, xh = cap - 1, xh - 1
    size = pick_size(ttf, cap, xh)
    thr = threshold(size)
    newg, newabc = {}, [list(x) for x in abc]
    for c in range(max(first, 0x21), last + 1):
        try:
            ch = bytes([c]).decode(cp)
        except UnicodeDecodeError:
            continue
        if ch.isspace() or not ch.isprintable():
            continue
        font = ImageFont.truetype(ttf, size)
        while ch and not all(has_glyph(ttf, x) for x in ch):
            ch = FALLBACK.get(ch)
        if not ch:
            continue                     # the TrueType font has no such letter: keep the old one
        img, ybase, font = render(ttf, size, ch)
        mono = img.point(lambda v: 255 if v >= thr else 0)
        bb = mono.getbbox()
        if not bb:
            continue
        x0, x1 = bb[0], bb[2]
        # the H baseline of the rendering: the bottom of 'H' at this size
        hb = render(ttf, size, 'H')[0].point(lambda v: 255 if v >= thr else 0).getbbox()[3] - 1 + (1 if st == 'drop' else 0)
        dy = base - hb
        pad = 1 if st != 'none' else 0
        w = x1 - x0 + pad * (2 if st == 'outline' else 1)
        g = [[0] * w for _ in range(h)]
        px = mono.load()
        for y in range(mono.size[1]):
            ty = y + dy
            if not 0 <= ty < h: continue
            for x in range(x0, x1):
                if px[x, y]:
                    g[ty][x - x0 + (pad if st == 'outline' else 0)] = ink
        if st != 'none':
            sh = [row[:] for row in g]
            for y in range(h):
                for x in range(w):
                    if g[y][x] != ink: continue
                    nb = [(1, 0), (0, 1), (1, 1)] if st == 'drop' else \
                        [(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)]
                    for dx, dyy in nb:
                        xx, yy = x + dx, y + dyy
                        if 0 <= xx < w and 0 <= yy < h and sh[yy][xx] == 0:
                            sh[yy][xx] = 1
            g = sh
        newg[c] = g
        newabc[c] = [0, w, 1 if st == 'none' else 0]
    # keep within the original's size where possible (the game then gets the new font in the
    # buffer it loaded the old one into): drop the rare signs of the code page first
    def total():
        return sum(len(g) * len(g[0]) if g and g[0] else 0 for g in newg.values()) + \
            sum(h * abc[c][1] for c in glyphs if c not in newg)
    keep = set('«»–—…№Ёё“”‘’„•')
    rare = [c for c in range(0x80, 0xC0) if c in newg and bytes([c]).decode(cp, 'replace') not in keep]
    while HDR + 4096 + total() > len(b) and rare:
        c = rare.pop()
        newg[c] = [[] for _ in range(h)]
        newabc[c] = [0, 0, 0]
    # build: the old glyphs where no new one was made
    data, offs = bytearray(), [0] * 256
    for c in range(256):
        if c in newg:
            g, (l, w, r) = newg[c], newabc[c]
        elif c in glyphs:
            g, (l, w, r) = glyphs[c], abc[c]
            newabc[c] = [l, w, r]
        else:
            offs[c] = len(data)
            continue
        offs[c] = len(data)
        if w > 0:
            for row in g:
                data += bytes(row)
    hdr = bytearray(b[:HDR])
    body = b''.join(struct.pack('<iii', *x) for x in newabc) + struct.pack('<256I', *offs)
    open(out, 'wb').write(bytes(hdr) + body + bytes(data))
    return size, st, ink, len(b), HDR + len(body) + len(data)


if __name__ == '__main__':
    src, ttf, outdir = sys.argv[1:4]
    cp = sys.argv[4] if len(sys.argv) > 4 else 'cp1251'
    os.makedirs(outdir, exist_ok=True)
    for f in sorted(os.listdir(src)):
        if not f.lower().endswith('.fnt') or f.lower() in SKIP:
            continue
        r = make(os.path.join(src, f), ttf, os.path.join(outdir, f), cp)
        print(f, 'size %d, %s shadow, ink %d, %d -> %d bytes' % r)
