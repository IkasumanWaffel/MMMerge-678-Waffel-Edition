import numpy as np
from PIL import Image
from scipy import ndimage as nd
KEY=np.array([0,252,252])
def arr(im):
    a=np.asarray(im.convert('RGB')).astype(float)
    key=(a[...,0]<8)&(a[...,1]>240)&(a[...,2]>240)
    return a/255,key
def chroma(a):
    s=a.sum(-1,keepdims=True); return (a/np.maximum(s,1e-3))[...,:2]
def lumof(a): return a@[0.3,0.59,0.11]
def ref_map(imgs):
    """lum -> zombie skin colour, from the original zombie's hands"""
    px=[]
    for im in imgs:
        a,key=arr(im); l=lumof(a); m=(~key)&(l>0.06)
        px.append(a[m])
    px=np.concatenate(px); l=lumof(px)
    lo,hi=np.percentile(l,[5,95]); bins=np.linspace(0,1,65); tab=np.zeros((64,3))
    for i in range(64):
        sel=(l>=bins[i]-0.03)&(l<bins[i+1]+0.03)
        tab[i]=np.median(px[sel],0) if sel.sum()>8 else np.nan
    idx=np.arange(64); ok=~np.isnan(tab[:,0])
    for c in range(3): tab[:,c]=np.interp(idx,idx[ok],tab[ok,c])
    tab=nd.uniform_filter1d(tab,5,axis=0)
    return tab,(lo,hi)
def skin_model(hands):
    px=[]
    for im in hands:
        a,key=arr(im); l=lumof(a); s=a.max(-1)-a.min(-1)
        m=(~key)&(l>0.15)&(s>0.06); px.append(chroma(a)[m])
    px=np.concatenate(px)
    h,xe,ye=np.histogram2d(px[:,0],px[:,1],bins=60,range=[[0.2,0.8],[0.2,0.5]])
    h=nd.gaussian_filter(h,1.5); i,j=np.unravel_index(h.argmax(),h.shape)
    mu=np.array([(xe[i]+xe[i+1])/2,(ye[j]+ye[j+1])/2])   # the commonest colour: the skin
    d=np.sqrt(((px-mu)**2).sum(-1))
    return mu,float(np.clip(np.percentile(d[d<0.08],75),0.035,0.06))
def recolor(im, model, ref, seed=1, strength=1.0):
    a,key=arr(im); l=lumof(a); mu,rad=model; tab,(rlo,rhi)=ref
    d=np.sqrt(((chroma(a)-mu)**2).sum(-1))
    sat=a.max(-1)-a.min(-1)
    bg=a[...,2]/np.maximum(a[...,1],1e-3)
    m=np.clip(1-(d-rad)/(rad*0.8),0,1)*np.clip((bg-0.5)*12,0,1)*np.clip((l-0.07)*8,0,1)*np.clip((sat-0.03)*20,0,1)
    m[key]=0; m=nd.gaussian_filter(m,0.7); m[key]=0
    sk=m>0.5
    if sk.sum()<20: return im
    slo,shi=np.percentile(l[sk],[5,95])
    t=np.clip((l-slo)/max(shi-slo,0.05)*(rhi-rlo)+rlo,0,0.999)
    out=tab[(t*64).astype(int)]/255 if tab.max()>1.5 else tab[(t*64).astype(int)]
    rng=np.random.default_rng(seed); H,W=l.shape
    n=nd.gaussian_filter(rng.random((H,W)),1.6); n=(n-n.mean())/n.std()
    blot=np.clip(n-0.6,0,2)[...,None]*0.18; out=out*(1-blot)+blot*np.array([0.30,0.30,0.16])
    dk=np.clip(-n-1.1,0,2)[...,None]*0.2; out=out*(1-dk)+dk*np.array([0.14,0.12,0.08])
    w=(m*strength)[...,None]; res=a*(1-w)+out*w
    res=(res*255).clip(0,255).astype('uint8'); res[key]=KEY
    return Image.fromarray(res)
