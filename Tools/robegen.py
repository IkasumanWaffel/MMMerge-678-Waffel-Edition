import sys, math, random
sys.path.insert(0,'.')
from lod32 import entries,bitmap
from PIL import Image, ImageFilter
import numpy as np
LODS=['/mnt/user-data/uploads/Data/mmmerge.icons.lod','/mnt/user-data/uploads/Data/mm8.icons.lod','/mnt/user-data/uploads/Data/icons.lod','/mnt/user-data/uploads/Data/mm7.icons.lod','/mnt/user-data/uploads/Data/mm6.icons.lod']
_L=None
def get(n):
    global _L
    if _L is None: _L=[entries(f) for f in LODS]
    for d,es in _L:
        if n.lower() in es: return bitmap(d,es[n.lower()][0]).convert('RGB')
def keymask(im):
    a=np.asarray(im).astype(int)
    k=((a[:,:,0]<20)&(a[:,:,1]>230)&(a[:,:,2]>230))|((a[:,:,0]>230)&(a[:,:,1]<20)&(a[:,:,2]>230))
    return ~k
def dilate(m,r):
    im=Image.fromarray((m*255).astype('uint8')).filter(ImageFilter.MaxFilter(2*r+1))
    return np.asarray(im)>127

def make_robe(base, bod, off_armor, off_body, waist, hem, scheme, seed=1):
    random.seed(seed); np.random.seed(seed)
    A_im=get(base); A=keymask(A_im); H,W=A.shape
    lum=np.asarray(A_im.convert('L').filter(ImageFilter.GaussianBlur(2))).astype(float)/255
    lum=0.35+0.65*np.clip(lum/ (lum[A].mean()*2 if A.any() else 1),0,1)
    # body silhouette in armor space
    B_im=get(bod); Bm=keymask(B_im)
    B=np.zeros_like(A)
    dx=off_body[0]-off_armor[0]; dy=off_body[1]-off_armor[1]
    bh,bw=Bm.shape
    for y in range(bh):
        ay=y+dy
        if 0<=ay<H:
            for x in range(bw):
                ax=x+dx
                if 0<=ax<W and Bm[y,x]: B[ay,ax]=True
    torso=A & dilate(B,5)
    torso[waist:,:]=False
    widths=torso.sum(axis=1)
    sh=[y for y in range(H) if widths[y]>=20]
    if sh:
        torso[:max(0,sh[0]-2),:]=False
    # legs / skirt
    M=torso.copy()
    rows=[y for y in range(waist,hem) if A[y].any()]
    lw=min(np.where(A[waist])[0]); rw=max(np.where(A[waist])[0])
    xsl=[np.where(A[y])[0].min() for y in range(waist,hem) if A[y].any()]
    xsr=[np.where(A[y])[0].max() for y in range(waist,hem) if A[y].any()]
    hemL=min(xsl)-2; hemR=max(xsr)+2
    edges={}
    for y in range(waist,hem):
        t=(y-waist)/max(1,hem-waist)
        tt=t**0.8
        el=int(round(lw+(hemL-lw)*tt)); er=int(round(rw+(hemR-rw)*tt))
        y0,y1=max(waist,y-18),min(hem,y+18)
        cov=(A|B)[y0:y1]
        cl=[np.where(r_)[0].min() for r_ in cov if r_.any()]
        cr=[np.where(r_)[0].max() for r_ in cov if r_.any()]
        if cl: el=min(el,min(cl)-1)
        if cr: er=max(er,max(cr)+1)
        el=max(0,el); er=min(W-1,er)
        edges[y]=(el,er); M[y,el:er+1]=True
    # below the hem: the suit's own legs (trousers) and feet
    legs=A.copy(); legs[:hem,:]=False
    out=np.zeros((H,W,3))
    cx_w=(lw+rw)/2
    top_rows=[y for y in range(H) if torso[y].any()]
    nrow=top_rows[0] if top_rows else 0
    xs0=np.where(torso[nrow])[0] if top_rows else np.array([cx_w])
    tops=[np.where(torso[y])[0] for y in range(nrow,min(H,nrow+8)) if torso[y].any()]
    cx_neck=float(np.mean([t.mean() for t in tops])) if tops else cx_w
    navy=np.array(scheme['outer']); white=np.array(scheme['panel']); silver=np.array(scheme['trim'])
    noise=np.random.rand(H,W)*0.08
    for y in range(H):
        for x in range(W):
            if legs[y,x]:
                out[y,x]=np.array(scheme['legs'])*(0.5+0.8*lum[y,x]); continue
            if not M[y,x]: continue
            if y<waist:
                # torso: the suit's shading, a white V under the coat, silver edging
                sh=0.45+0.9*lum[y,x]
                xs=np.where(M[y])[0]; tl,tr=xs.min(),xs.max(); cx=(tl+tr)/2
                top=min(np.where(M.any(axis=1))[0])
                f=(y-top)/max(1,waist-top)
                cx=cx_neck+(cx_w-cx_neck)*f
                vw=(tr-tl)*(0.15*(1-f)+0.05)
                d=abs(x-cx)
                cyl=1-0.35*((x-(tl+tr)/2)/max(1,(tr-tl)/2))**2
                sh=sh*cyl
                if d<vw-1: c=white*(0.7+0.3*cyl)
                elif d<vw+1.2: c=silver*sh
                else: c=navy*sh
                if x<=tl+1 or x>=tr-1: c=silver*0.8
                out[y,x]=c
            else:
                el,er=edges[y]; cx=cx_w; hw=(er-el)/2
                rel=(x-(el+er)/2)/max(1,hw)
                fold=0.16*math.sin((x-el)/(2.6+0.02*(y-waist))+ (y-waist)/50.0)+0.05*math.sin((x-el)/1.3)
                sh=(1-0.45*rel*rel)+fold+noise[y,x]
                sh=max(0.25,min(1.25,sh))
                t_=(y-waist)/max(1,hem-waist)
                pcx=cx_w+((hemL+hemR)/2-cx_w)*t_
                pw=(rw-lw)*0.17+((hemR-hemL)*0.15-(rw-lw)*0.17)*t_
                d=abs(x-pcx)
                if y<waist+10:
                    c=navy*0.8*sh
                    if y in (waist,waist+9): c=silver*0.9
                    elif y in (waist+2,waist+7) and (x//3)%2==0: c=silver*0.75
                    elif 3<=y-waist<=6 and ((x+ (y-waist)) % 7 in (0,1)): c=silver*0.6
                elif d<pw-1: c=white*(0.65+0.35*sh)
                elif d<pw+1: c=silver*sh
                else: c=navy*sh
                if y>=hem-3: c=silver*sh if d>=pw else white*0.6
                if x<=el or x>=er: c=navy*0.35
                out[y,x]=c
    out=np.clip(out,0,255).astype('uint8')
    img=Image.fromarray(out)
    keyc=Image.new('RGB',(W,H),(0,252,252))
    mask=Image.fromarray(((M|legs)*255).astype('uint8'))
    keyc.paste(img,(0,0),mask)
    return keyc, M|legs

SCHEMES={
 'archmage': dict(outer=(40,52,120), panel=(232,232,236), trim=(196,200,210), legs=(30,34,60)),
}
