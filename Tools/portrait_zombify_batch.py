import sys; sys.path.insert(0,'/tmp/zom'); from common import *; from eyes import EYES
import numpy as np, os
from PIL import Image
from zombify import zombify as zf
os.makedirs('/tmp/zom/out',exist_ok=True)
def rgb(im):
    a=np.array(im.convert('RGBA')).astype(int); c=a[...,:3].copy()
    c[(a[...,3]<128)]=(0,252,252); return Image.fromarray(c.astype('uint8'))
done=set(); rows=[]
for p in P:
    if p['id'] not in EYES: continue
    mode='goblin' if p['race']==30 else 'warm'
    f1=np.asarray(frame(p,1).convert('RGB')).astype(float)/255
    lum1=0.3*f1[...,0]+0.59*f1[...,1]+0.11*f1[...,2]
    # the face's skin colour for the body and hands
    r,g,b=f1[...,0],f1[...,1],f1[...,2]
    sk=(r-g>0.05)&(lum1>0.2) if mode=='warm' else (g-b>0.05)&(lum1>0.2)
    sk[:20]=False; sk[60:]=False
    sref=np.median(f1[sk],axis=0) if sk.sum()>30 else None
    for i in range(1,57):
        im=frame(p,i)
        if im is None: continue
        z=zf(rgb(im),seed=p['id']+1,mode=mode,decay=1.0,eyes=EYES[p['id']],ref=lum1)
        z.save(f"/tmp/zom/out/z{p['pre']}{i:02d}.png")
    for k,n in p['pics'].items():
        if n.lower()=='none' or n.lower() in done: continue
        im=bm(n)
        if im is None: continue
        done.add(n.lower())
        zf(rgb(im),seed=p['id']+1,mode=mode,decay=1.0,skinref=sref).save(f"/tmp/zom/out/z{n.lower()}.png")
    rows.append(p['id'])
print(len(rows), len(os.listdir('/tmp/zom/out')))
