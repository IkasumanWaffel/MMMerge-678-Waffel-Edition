import numpy as np
from portrait_eye_track import *
SKIP={2,4,11,12,13,35,36,37,38,39,47,54}   # eyes shut or out of place (as left in the zpc50 redraw)
PALE=np.array([200,205,172.])
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
def blank_eyes(zimg, orig_lum, ref_lum, pupils, n, hw=1):
    if n in SKIP or not pupils: return zimg
    t=track_pair(ref_lum, orig_lum, pupils, maxerr=0.06) if len(pupils)==2 else None
    if len(pupils)==2 and not t: return zimg
    dy,dx=(t[1],t[2]) if t else (0,0)
    a=np.asarray(zimg).astype(float).copy()
    for cy,cx in pupils: paint(a, cy+dy, cx+dx, hw)
    from PIL import Image
    return Image.fromarray(a.clip(0,255).astype('uint8'))
