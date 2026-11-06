"""Left-hand (off-hand) versions of item icons: the icon turned 90 degrees counter-clockwise,
added to an icons lod as <name>L (06.11.26, the blaster pistols held in the left hand).

    python offhand_icons.py <out icons.lod> <in icons.lod> <src lod>:<icon>[:<degrees>] ...

<degrees>: counter-clockwise, 90 by default (-90: clockwise); ":m" after it mirrors the
turned icon left to right. <src lod>:<icon>:mirror adds the icon itself mirrored left to
right, under its own name (it then overrides the original in the earlier lods).
The pistols of 06.11.26: mmmerge.icons.lod:7item064 waffel.icons.lod:anc07 mm6.icons.lod:raygun1:-90:m
and the MM6 blasters mirrored: mm6.icons.lod:raygun1:mirror mm6.icons.lod:raygun2:mirror

<in icons.lod> is the archive the icons are added to (written to <out>, the directory kept
sorted by name); each source icon keeps its palette.
"""
import struct, sys, zlib
from PIL import Image

def read_lod(path):
    d = open(path, 'rb').read()
    n = struct.unpack('<I', d[0x11C:0x120])[0]
    ents = []
    for i in range(n):
        e = d[0x120 + i * 32: 0x120 + (i + 1) * 32]
        name = e[:16].split(b'\0')[0].decode('latin1')
        o, s = struct.unpack('<II', e[16:24])
        ents.append([name, d[0x120 + o: 0x120 + o + s], e[24:32]])
    return d[:0x120], ents

def find(path, name):
    for n, b, _ in read_lod(path)[1]:
        if n.lower() == name.lower(): return b
    raise SystemExit('no %s in %s' % (name, path))

def rotated(blob, newname, degrees=90, mirror=False):
    bs, ds, w, h = struct.unpack('<IIHH', blob[16:28])
    us = struct.unpack('<I', blob[40:44])[0]
    px = zlib.decompress(blob[48:48 + ds]) if us else blob[48:48 + bs]
    pal = blob[48 + ds: 48 + ds + 768]
    im = Image.frombytes('P', (w, h), px[:w * h]).rotate(degrees, expand=True)   # counter-clockwise
    if mirror: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    w2, h2 = im.size
    raw = im.tobytes()
    comp = zlib.compress(raw, 9)
    hdr = bytearray(blob[:48])
    hdr[:16] = newname.encode('latin1').ljust(16, b'\0')
    struct.pack_into('<IIHH', hdr, 16, len(raw), len(comp), w2, h2)
    struct.pack_into('<I', hdr, 40, len(raw))
    return bytes(hdr) + comp + pal, (w, h, w2, h2)

def write_lod(head, ents, out):
    ents.sort(key=lambda e: e[0].lower())
    dirsize = 32 * len(ents)
    body = b''; dirs = b''
    for name, b, tail in ents:
        dirs += name.encode('latin1').ljust(16, b'\0') + struct.pack('<II', dirsize + len(body), len(b)) + tail
        body += b
    head = bytearray(head)
    struct.pack_into('<I', head, 0x114, dirsize + len(body))
    struct.pack_into('<I', head, 0x11C, len(ents))
    open(out, 'wb').write(bytes(head) + dirs + body)

if __name__ == '__main__':
    out, base = sys.argv[1], sys.argv[2]
    head, ents = read_lod(base)
    for spec in sys.argv[3:]:
        parts = spec.split(':')
        src, name = parts[0], parts[1]
        if len(parts) > 2 and parts[2] == 'mirror':
            newname, degrees, mirror = name, 0, True
        else:
            degrees = int(parts[2]) if len(parts) > 2 else 90
            newname, mirror = name + 'L', len(parts) > 3 and parts[3] == 'm'
        blob, dims = rotated(find(src, name), newname, degrees, mirror)
        ents = [e for e in ents if e[0].lower() != newname.lower()]
        ents.append([newname, blob, b'\0' * 8])
        print(newname, 'from %dx%d to %dx%d' % dims)
    write_lod(head, ents, out)
