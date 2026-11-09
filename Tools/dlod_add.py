"""Add or replace bitmaps in an MM8 "D" lod (waffel.D.lod: 64-character names).

    python Tools/dlod_add.py <in.lod> <out.lod> name=picture.png [name=picture.jpg ...]

Each picture is quantized to 256 colours (no transparent colour: the D.lod buttons have none)
and stored as the game's bitmap: name (64), bitmap size, data size, width, height, ...,
unpacked size (32), zlib data, palette (768). The directory is kept sorted by name.
"""
import struct, sys, zlib
import numpy as np
from PIL import Image

ENTRY = 0x4C
DIR = 0x120


def read(path):
    d = open(path, 'rb').read()
    off, n = struct.unpack_from('<I', d, 0x110)[0], struct.unpack_from('<I', d, 0x11C)[0]
    files = {}
    for i in range(n):
        e = d[off + i * ENTRY: off + (i + 1) * ENTRY]
        name = e[:64].split(b'\0')[0].decode('latin1')
        o, s = struct.unpack_from('<II', e, 64)
        files[name] = d[off + o: off + o + s]
    return d[:DIR], files


def bitmap(name, path):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    q = im.quantize(256, method=Image.MEDIANCUT, dither=Image.NONE)
    px = np.array(q, np.uint8).tobytes()
    pal = bytes(q.getpalette()[:768]).ljust(768, b'\0')
    comp = zlib.compress(px, 9)
    hdr = bytearray(32)
    struct.pack_into('<IIHH', hdr, 0, len(px), len(comp), w, h)
    struct.pack_into('<I', hdr, 24, len(px))
    return name.encode('latin1').ljust(64, b'\0') + bytes(hdr) + comp + pal


def write(path, head, files):
    names = sorted(files, key=lambda s: s.lower())
    table = bytearray()
    data = bytearray()
    base = len(names) * ENTRY
    for n in names:
        e = bytearray(ENTRY)
        e[:64] = n.encode('latin1').ljust(64, b'\0')
        struct.pack_into('<II', e, 64, base + len(data), len(files[n]))
        table += e
        data += files[n]
    head = bytearray(head)
    struct.pack_into('<I', head, 0x110, DIR)
    struct.pack_into('<I', head, 0x114, len(table) + len(data))
    struct.pack_into('<I', head, 0x11C, len(names))
    open(path, 'wb').write(bytes(head) + bytes(table) + bytes(data))


if __name__ == '__main__':
    src, out = sys.argv[1:3]
    head, files = read(src)
    for arg in sys.argv[3:]:
        name, pic = arg.split('=', 1)
        files[name] = bitmap(name, pic)
    write(out, head, files)
    print(len(files), 'files ->', out)
