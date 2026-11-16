import sys, json; sys.path.insert(0,'.')
import numpy as np
from PIL import Image
from robe_make import comp, get, keymask
src=Image.open('hat_icon_src.png')
DOCS={'m':('pc01bod',30,33),'f':('pc02bod',60,47),'t2':('pc21bod',47,62),'t3':('pc23bod',43,43),'t4':('7pc13bod',43,43)}
def sprite(w,h):
    s=src.resize((w,h),Image.LANCZOS); al=np.asarray(s.split()[3]); rgb=np.asarray(s.convert('RGB'))
    return Image.fromarray(np.where((al>110)[...,None],rgb,np.array([0,252,252])).astype('uint8'))
def head(k, probe):
    bd,bx,by=DOCS[k]; im=get(bd).convert('RGB'); m=keymask(im).astype(bool)
    top=np.where(m.any(1))[0].min(); y=top+probe; xs=np.where(m[y])[0]
    return bx+(xs.min()+xs.max())/2, by+top
def build(P):
    out={}
    for k,(probe,w,aspect,drop,dx) in P.items():
        cx,top=head(k,probe); h=int(w*aspect)
        x=int(round(cx-w/2+dx)); y=int(top+drop-h)
        out[k]=(sprite(w,h),x,y)
    return out
def preview(out,path):
    o=Image.new('RGB',(1000,200))
    for i,k in enumerate(['m','f','t2','t3','t4']):
        bd,bx,by=DOCS[k]; sp,x,y=out[k]
        c=comp(bd,bx,by,sp,x,y,H=420).convert('RGB').crop((0,0,200,200)); o.paste(c,(i*200,0))
    o.resize((2000,400),0).save(path)
