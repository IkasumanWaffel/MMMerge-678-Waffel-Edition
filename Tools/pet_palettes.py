"""Pet palettes (26.11.26): the B and C colourings of the cats, chickens, dogs and rats,
which share palette 545 (warm: ginger, tan, brown, buff; grey: grey, grey, grey, speckled hen)."""
import colorsys
def hls(c): return colorsys.rgb_to_hls(*(v/255 for v in c))
def rgb(h,l,s): return tuple(max(0,min(255,round(v*255))) for v in colorsys.hls_to_rgb(h,l,s))
def keep(h,l,s):
    hd=h*360
    if s>0.40 and (hd<40 or hd>330) and 0.15<l<0.95: return True   # pink skin, comb, legs, tail
    if s>0.25 and 70<hd<170 and l>0.08: return True              # green eyes
    return False
def make(pal, variant):
    out=list(pal)
    for i,c in enumerate(pal):
        if i==0: continue
        h,l,s=hls(c)
        if keep(h,l,s): continue
        if variant=='B':      # warm: ginger cat, tan dog, brown rat, buff hen
            if l>0.72:
                out[i]=rgb(34/360, l*0.80, 0.55)
            else:
                L=l**0.72
                out[i]=rgb(26/360, L, 0.55*min(1,L*2.2))
        elif variant=='C':    # grey: grey tabby cat, grey dog, grey rat, speckled hen
            if l>0.72:
                out[i]=rgb(24/360, 0.22+(1-l)*0.7, 0.30)
            else:
                L=0.10+0.62*l**0.6
                out[i]=rgb(30/360, L, 0.06)
    return out

# --- builds Data/waffel.bitmaps.lod: pal2101 (B, warm) and pal2102 (C, grey) from pal545 ---
#     python Tools/pet_palettes.py <mm7.bitmaps.lod> <out waffel.bitmaps.lod>
def _entries(path):
    import struct
    d = open(path, 'rb').read()
    n = struct.unpack('<I', d[0x11C:0x120])[0]
    for i in range(n):
        e = d[0x120 + i*32: 0x120 + (i+1)*32]
        o, s = struct.unpack('<II', e[16:24])
        yield e[:16].split(b'\0')[0].decode('latin1').lower(), d[0x120 + o: 0x120 + o + s]

if __name__ == '__main__':
    import struct, sys
    src = dict(_entries(sys.argv[1]))['pal545']
    pal = [tuple(src[48 + i*3: 51 + i*3]) for i in range(256)]
    files = {}
    for pid, v in ((2101, 'B'), (2102, 'C')):
        hdr = bytearray(src[:48]); hdr[:16] = ('pal%d' % pid).encode().ljust(16, b'\0')
        files['pal%d' % pid] = bytes(hdr) + bytes(sum((list(c) for c in make(pal, v)), [])) + src[48 + 768:]
    names = sorted(files); ents = b''; data = b''
    for nm in names:
        ents += nm.encode().ljust(16, b'\0') + struct.pack('<IIII', len(names)*32 + len(data), len(files[nm]), 0, 0)
        data += files[nm]
    head = b'LOD\0MMVI'.ljust(0x100, b'\0')
    dirhdr = b'bitmaps'.ljust(16, b'\0') + struct.pack('<IIII', 0x120, len(ents) + len(data), 0, len(names))
    open(sys.argv[2], 'wb').write(head + dirhdr + ents + data)
