import sys; sys.path.insert(0,'/home/claude/mmmerge-678-waffel-edition/Tools'); sys.path.insert(0,'.')
from offhand_icons import read_lod, write_lod
import numpy as np
from PIL import Image, ImageFilter
from artifact_icons import blob
TR=(0,252,252)
def to_blob(img, name, sharpen=False):
    a=np.asarray(img.convert('RGB')).astype(int)
    key=(a[:,:,0]<20)&(a[:,:,1]>230)&(a[:,:,2]>230)
    rgb=img.convert('RGB')
    if sharpen: rgb=rgb.filter(ImageFilter.UnsharpMask(1,50,2))
    flat=Image.fromarray(np.where(key[...,None], np.array([128,128,128]), np.asarray(rgb)).astype('uint8'))
    q=flat.quantize(255, method=Image.MEDIANCUT, dither=Image.NONE)
    idx=np.asarray(q).astype(np.uint8)+1; idx[key]=0
    pal=list(TR)+q.getpalette()[:255*3]; pal+=[0]*(768-len(pal))
    return blob(name, idx, bytes(pal))
def pack(base_lod, out_lod, new):
    head,ents=read_lod(base_lod)
    ents=[e for e in ents if e[0].lower() not in new]
    for n,b in new.items(): ents.append([n,b,b'\0'*8])
    write_lod(head,ents,out_lod)
