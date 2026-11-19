import numpy as np
from scipy import ndimage as nd
def L(im): a=np.asarray(im.convert('RGB')).astype(float)/255; return a@[0.3,0.59,0.11]
def pupil(lum, box):
    x0,y0,x1,y1=box
    sm=nd.uniform_filter(lum,3)
    sub=sm[y0:y1+1,x0:x1+1]; cy,cx=np.unravel_index(np.argmin(sub),sub.shape)
    return (cy+y0,cx+x0)
def track(ref, lum, c, r=12, ph=3, pw=5, maxerr=0.012):
    cy,cx=c; H,W=ref.shape
    if cy-ph<0 or cy+ph>=H or cx-pw<0 or cx+pw>=W: return None
    t=ref[cy-ph:cy+ph+1,cx-pw:cx+pw+1]; t=t-t.mean()
    best=None
    for dy in range(-r,r+1):
        for dx in range(-r,r+1):
            y,x=cy+dy,cx+dx
            if y-ph<0 or y+ph>=H or x-pw<0 or x+pw>=W: continue
            p=lum[y-ph:y+ph+1,x-pw:x+pw+1]; p=p-p.mean()
            e=((p-t)**2).mean()+0.00002*(dx*dx+dy*dy)
            if best is None or e<best[0]: best=(e,y,x)
    if best and best[0]<maxerr: return best[1],best[2],best[0]
    return None
def track_pair(ref, lum, cs, r=14, maxerr=0.02):
    (ay,ax),(by,bx)=cs
    y0,y1=min(ay,by)-6,max(ay,by)+4; x0,x1=min(ax,bx)-6,max(ax,bx)+6
    H,W=ref.shape
    y0,x0=max(0,y0),max(0,x0); y1,x1=min(H-1,y1),min(W-1,x1)
    t=ref[y0:y1+1,x0:x1+1]; t=t-t.mean()
    best=None
    for dy in range(-r,r+1):
        for dx in range(-r,r+1):
            if y0+dy<0 or y1+dy>=H or x0+dx<0 or x1+dx>=W: continue
            p=lum[y0+dy:y1+dy+1,x0+dx:x1+dx+1]; p=p-p.mean()
            e=((p-t)**2).mean()+0.00003*(dx*dx+dy*dy)
            if best is None or e<best[0]: best=(e,dy,dx)
    if best and best[0]<maxerr: return best
    return None
def open_at(lum, y, x):
    H,W=lum.shape
    if not (2<=y<H-2 and 3<=x<W-3): return False
    c=lum[y-1:y+2,x-1:x+2].min()
    ring=np.concatenate([lum[y-3,x-3:x+4],lum[y+3 if y+3<H else H-1,x-3:x+4]])
    return c < np.median(ring)-0.06
