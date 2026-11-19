import numpy as np
from portrait_eye_track import *
SKIP={2,4,9,11,12,13,35,36,37,38,39,47,54}   # eyes shut or out of place (as left in the zpc50 redraw)
PALE=np.array([228,226,178.])
def paint(arr, cy, cx, hw=1):
    H,W,_=arr.shape
    for dy in (-1,0,1):
        for dx in range(-hw-1,hw+2):
            y,x=cy+dy,cx+dx
            if not (0<=y<H and 0<=x<W): continue
            edge=abs(dx)>hw
            corner=(dy!=0 and abs(dx)>=hw)
            w=0.0 if (edge and dy!=0) else (0.45 if edge else (0.7 if corner else 1.0))
            if w>0: arr[y,x]=arr[y,x]*(1-w)+PALE*(0.92 if corner or edge else 1.0)*w
def refine(lum, y, x):
    # the iris: darker than the eye on both sides of it; a cheek or brow is not
    H,W=lum.shape; best=None
    for yy in (y-1,y,y+1):
        for xx in (x-1,x,x+1):
            if not (1<=yy<H-1 and 5<=xx<W-5): continue
            core=lum[yy,xx-1:xx+2].mean()
            sc=min(lum[yy,xx-4:xx-1].max(),lum[yy,xx+2:xx+5].max())-core-0.01*(abs(yy-y)+abs(xx-x))
            if best is None or sc>best[0]: best=(sc,yy,xx)
    return best[1:] if best and best[0]>0.06 else None
BRIGHT={9,10,77,81}   # glowing irises: the dark-iris check can't apply
def blank_eyes(zimg, orig_lum, ref_lum, pupils, n, hw=1, pid=None):
    if n in SKIP or not pupils: return zimg
    tp=pupils if len(pupils)==2 else [pupils[0],(pupils[0][0],pupils[0][1]+21)]   # one eye (eye patch): track it with the patch
    t=track_pair(ref_lum, orig_lum, tp, maxerr=0.06)
    if not t: return zimg
    err,dy,dx=t[0],t[1],t[2]
    spots=[]
    for cy,cx in pupils:
        q=refine(orig_lum, cy+dy, cx+dx)
        if q is None and (err<=0.03 or pid in BRIGHT): q=(cy+dy,cx+dx)
        spots.append(q)
    if any(q is None for q in spots): return zimg   # both eyes or neither
    a=np.asarray(zimg).astype(float).copy()
    for q in spots: paint(a, q[0], q[1], hw)
    from PIL import Image
    return Image.fromarray(a.clip(0,255).astype('uint8'))
