import sys; sys.path.insert(0,'.')
from robegen import get, keymask, dilate
from PIL import Image, ImageFilter
import numpy as np
def is_bg(a): return ((a[:,:,0]<90)&(a[:,:,1]>180)&(a[:,:,2]>180)) | ((a[:,:,1]>140)&(a[:,:,2]>140)&(a[:,:,0]<a[:,:,1]-70))
def fit(gen_path, ref_path, canvas, body, body_off, base, armor_off, waist, scale=4):
    g=Image.open(gen_path).convert('RGB'); ref=Image.open(ref_path).convert('RGB')
    W4,H4=ref.size
    best=None
    rf=np.asarray(ref).astype(float)
    # register on the head: rows above the armor
    hy0,hy1=(body_off[1])*scale, (armor_off[1]+10)*scale
    for sc in np.arange(0.96,1.045,0.01):
        gs=g.resize((int(W4*sc),int(H4*sc)),Image.LANCZOS)
        ga=np.asarray(gs).astype(float)
        for dy in range(-30,31,3):
            for dx in range(-30,31,3):
                # place gs at (ox,oy) so that its centre scaling keeps the top-left aligned
                ox=int((W4-gs.size[0])/2)+dx; oy=int((H4-gs.size[1])/2)+dy
                ys=slice(max(hy0,oy),min(hy1,oy+gs.size[1])); 
                xs=slice(max(0,ox),min(W4,ox+gs.size[0]))
                a=rf[ys,xs]; b=ga[ys.start-oy:ys.stop-oy, xs.start-ox:xs.stop-ox]
                m=~is_bg(a.astype(int))
                if m.sum()<500: continue
                e=np.abs(a-b)[m].mean()
                if best is None or e<best[0]: best=(e,sc,ox,oy)
    e,sc,ox,oy=best
    gs=g.resize((int(W4*sc),int(H4*sc)),Image.LANCZOS)
    big=Image.new('RGB',(W4,H4),(0,252,252)); big.paste(gs,(ox,oy))
    return big,best

from scipy import ndimage
def downscale(big, s=4):
    a=np.asarray(big).astype(float); fgm=~is_bg(a.astype(int))
    H,W=fgm.shape; h,w=H//s,W//s
    a=a[:h*s,:w*s]; f=fgm[:h*s,:w*s].astype(float)
    num=(a*f[...,None]).reshape(h,s,w,s,3).sum(axis=(1,3)); den=f.reshape(h,s,w,s).sum(axis=(1,3))
    rgb=num/np.maximum(den,1)[...,None]
    return rgb, den/(s*s)
def cut(big, base, bod, body_off, armor_off, waist, extra_torso=3, ref=None, tol=22):
    rgb,alpha=downscale(big)
    same=None
    if ref is not None:
        rr,ra=downscale(ref)
        same=(np.abs(rgb-rr).mean(axis=2)<tol)&(ra>=0.5)
    CH,CW=alpha.shape
    fgm=alpha>=0.75
    if same is not None:
        lab,n=ndimage.label(ndimage.binary_opening(same, iterations=1))
        if n:
            sizes=ndimage.sum(same,lab,range(1,n+1))
            big_same=np.isin(lab,[i+1 for i,v in enumerate(sizes) if v>=25])
            fgm=fgm & ~ndimage.binary_dilation(big_same, iterations=1)
    A=keymask(get(base)); Bm=keymask(get(bod))
    def place(m,off):
        z=np.zeros((CH,CW),bool); h,w=m.shape; x0,y0=off
        z[y0:y0+h, x0:x0+w]=m[:max(0,min(h,CH-y0)), :max(0,min(w,CW-x0))]
        return z
    Ac=place(A,armor_off); Bc=place(Bm,body_off)
    wy=armor_off[1]+waist
    torso=Ac & dilate(Bc,5); torso[wy:,:]=False
    widths=torso.sum(axis=1); sh=[y for y in range(CH) if widths[y]>=20]
    if sh: torso[:max(0,sh[0]-2),:]=False
    torso=dilate(torso,extra_torso) & fgm
    torso[wy:,:]=False
    sk=fgm.copy(); sk[:wy,:]=False
    lab,n=ndimage.label(sk)
    if n:
        sizes=ndimage.sum(sk,lab,range(1,n+1)); sk=lab==(1+int(np.argmax(sizes)))
    # the hem: drop the legs below the last wide row
    wd=sk.sum(axis=1); mx=wd.max()
    wide=[y for y in range(CH) if wd[y]>=0.45*mx]
    hem=max(wide)+1 if wide else CH
    sk[hem:,:]=False
    M=torso|sk
    lab,n=ndimage.label(M)
    if n>1:
        sizes=ndimage.sum(M,lab,range(1,n+1))
        M=np.isin(lab,[i+1 for i,v in enumerate(sizes) if v>=40])
    # holes inside the robe: back from the generated picture
    Mc=ndimage.binary_closing(M, iterations=3)
    M=(ndimage.binary_fill_holes(Mc) & (alpha>=0.5)) | M
    M[:max(0,(sh[0]-2) if sh else 0),:]=False
    M[hem:,:]=False
    # the sprite's own frame (it may reach beyond the cuirass's): bounding box of the robe
    ys,xs=np.where(M)
    x0,x1,y0,y1=xs.min(),xs.max()+1,ys.min(),ys.max()+1
    return rgb, M, (x0,y0,x1,y1), Bc, wy

def shade_sleeve(rgb, M, Bc, wy, side='right', reach=9, under=5):
    """darken the sleeve's opening toward the hand and its underside"""
    rgb=rgb.copy()
    H,W=M.shape
    ys,xs=np.where(M[:wy])
    cx=(xs.min()+xs.max())/2
    zone=np.zeros_like(M); 
    if side=='right': zone[:wy, int(cx+0.25*(xs.max()-xs.min())):]=True
    else: zone[:wy, :int(cx-0.25*(xs.max()-xs.min()))]=True
    sleeve=M&zone
    # the opening: sleeve pixels next to the bare arm
    arm=Bc&~M
    edge=sleeve & ndimage.binary_dilation(arm, iterations=1)
    if edge.any():
        d=ndimage.distance_transform_edt(~edge)
        f=np.clip(0.3+0.7*(d/reach)**1.3,0.3,1.0)
        rgb[sleeve]*=f[sleeve][:,None]
    # underside: the lowest rows of the sleeve in each column
    for x in range(W):
        col=np.where(sleeve[:,x])[0]
        if len(col):
            bottom=col.max()
            for k in range(under):
                y=bottom-k
                if y>=0 and sleeve[y,x]: rgb[y,x]*=0.42+0.13*k
    return rgb

def sprite(rgb, M, box):
    x0,y0,x1,y1=box
    spr=np.zeros((y1-y0,x1-x0,3),np.uint8); spr[:]=(0,252,252)
    sub=M[y0:y1,x0:x1]; col=rgb[y0:y1,x0:x1]
    spr[sub]=np.clip(col[sub],0,255).astype(np.uint8)
    return Image.fromarray(spr)

def fill_sleeve_hollow(rgb, M, Bc, wy, side='right', close=6, dark=0.28):
    """the open space between a hanging sleeve and the arm: the sleeve's dark inside"""
    rgb=rgb.copy(); M=M.copy()
    H,W=M.shape
    ys,xs=np.where(M[:wy]); cx=(xs.min()+xs.max())/2
    zone=np.zeros_like(M)
    if side=='right': zone[:wy, int(cx+0.25*(xs.max()-xs.min())):]=True
    else: zone[:wy, :int(cx-0.25*(xs.max()-xs.min()))]=True
    sleeve=M&zone
    both=(sleeve|(Bc&zone))
    closed=ndimage.binary_closing(both, structure=np.ones((3,3)), iterations=close)
    closed=ndimage.binary_fill_holes(closed)
    hollow=closed & ~M & ~Bc & zone
    if hollow.any():
        base=np.median(rgb[sleeve],axis=0)
        d=ndimage.distance_transform_edt(~sleeve)
        for y,x in zip(*np.where(hollow)):
            f=dark*(0.7+0.3*np.exp(-d[y,x]/3))
            rgb[y,x]=base*f
        M=M|hollow
    return rgb, M
