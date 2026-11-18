import numpy as np
from PIL import Image
from scipy import ndimage as nd
def zombify(img, seed=7, mode='warm', decay=0.0, eyes=None, ref=None, skinref=None):
    a=np.asarray(img.convert('RGB')).astype(float)/255
    r,g,b=a[...,0],a[...,1],a[...,2]
    mx=a.max(-1); mn=a.min(-1); s=np.where(mx>0,(mx-mn)/np.maximum(mx,1e-6),0)
    lum=0.3*r+0.59*g+0.11*b
    if mode=='goblin':   # green-yellow skin
        skin=np.sqrt(np.clip((g-b-0.02)*8,0,1)*np.clip((s-0.15)*8,0,1)*np.clip((lum-0.18)*5,0,1))
    else:
        warm=np.clip((r-g)*5,0,1)*np.clip((g-b+0.15)*6,0,1)
        skin=np.sqrt(warm*np.clip((lum-0.12)*5,0,1)*np.clip((s-0.12)*5,0,1))
    if skinref is not None:   # body and hands: only what is coloured like the face's skin
        sr=np.asarray(skinref); src=sr/max(sr.sum(),1e-3)
        ch=a/np.maximum(a.sum(-1,keepdims=True),1e-3)   # colour without brightness
        dist=np.sqrt(((ch-src)**2).sum(-1))
        skin=np.clip(skin*1.6,0,1)*np.clip(1-(dist-0.05)/0.07,0,1)
    key=(a[...,0]<0.1)&(a[...,1]>0.9)&(a[...,2]>0.9)
    skin=nd.gaussian_filter(skin,0.6)
    face0=nd.binary_closing(skin>0.4,iterations=3)
    red=(np.clip((r-g-0.15)*5,0,1)*np.clip((s-0.3)*4,0,1)*face0) if mode!='goblin' else 0*skin
    red=nd.gaussian_filter(red,0.5)
    # a frame tinted red all over (rage, a hit): no lips to find
    if mode!='goblin' and (red>0.5).sum() > 0.2*max(1,(skin>0.4).sum()):
        red=0*red
    L=lum*0.78+0.09   # ashen: dark skin goes grey, light skin a little duller
    # pallor: dull grey with a faint green cast (goblins: a cold grey)
    if mode=='goblin':
        pale=np.stack([L*0.86+0.02, L*0.88+0.03, L*0.86+0.03],-1)
    else:
        pale=np.stack([L*(0.86+0.03*decay)+0.03, L*(0.92-0.01*decay)+0.035, L*(0.78-0.10*decay)+0.02],-1)
    # sunken: shadows deepen and go purple-brown (eye sockets, cheeks, mouth)
    # sunken: what is darker than the face's own middle tone deepens (so dark skin isn't
    # darkened all over)
    med=np.median(lum[skin>0.5]) if (skin>0.5).sum()>20 else 0.5
    shade=np.clip(((med*(1+0.12*decay))-lum)/max(med,0.15)*(2.2+0.8*decay),0,1)[...,None]
    # dark skin: lifted to ashen grey (the pallor reads on it)
    lift=np.clip((0.42-med)*2.5,0,0.5)
    L=L+lift*(0.55-L)*0.8
    pale=pale*(1-(0.45+0.25*decay)*shade)+shade*np.array([0.11,0.04,0.07])*(0.7+0.4*decay)
    # mottling (fixed per portrait: the same on every frame)
    rng=np.random.default_rng(seed); H,W=lum.shape
    n=nd.gaussian_filter(rng.random((H,W)),1.6); n=(n-n.mean())/n.std()
    blot=np.clip(n-0.5+0.2*decay,0,2)[...,None]*(0.16+0.12*decay)
    pale=pale*(1-blot)+blot*np.array([0.30,0.30,0.16])
    dark=np.clip(-n-1.0+0.3*decay,0,2)[...,None]*(0.12+0.14*decay)
    pale=pale*(1-dark)+dark*np.array([0.16,0.13,0.07])
    # veins: thin dark ridges of a second noise
    if decay>0:
        n2=nd.gaussian_filter(rng.random((H,W)),1.3); n2=(n2-n2.mean())/n2.std()
        ridge=np.clip(1-np.abs(n2)/0.18,0,1)*np.clip((lum-0.35)*4,0,1)
        vv=(ridge*0.35*decay)[...,None]
        pale=pale*(1-vv)+vv*np.array([0.22,0.17,0.26])
    # lips: cold dark blue-grey
    bruise=np.stack([L*0.62+0.04,L*0.52+0.03,L*0.70+0.06],-1)
    if decay>0:   # cracked lips: dark lines across them
        xs=np.arange(W)[None,:].repeat(H,0)
        ys=np.arange(H)[:,None].repeat(W,1)
        crack=((xs+seed)%3==0)&(red>0.6)&(ys>H*0.6)
        bruise=np.where(crack[...,None],bruise*(1-0.45*decay),bruise)
    pale=pale*(1-red[...,None])+bruise*red[...,None]
    w=np.maximum(skin,red)[...,None]
    out=a*(1-w)+pale*w
    # eye whites / teeth: yellowed, faintly bloodshot
    face=nd.binary_dilation(skin>0.3,iterations=3)
    # whites: brighter than the skin around them and not very colourful
    band=np.zeros_like(face); band[int(H*0.33):int(H*0.56),:]=True   # where the eyes are
    white=(lum>0.42)&(s<0.32)&face&band&(lum-nd.gaussian_filter(lum,2.5)>0.06)
    # lifeless eyes: in each eye box (marked per portrait on its first frame) the pixels
    # unlike the skin around the box (white, iris, glint) turn a dull, milky grey; the
    # darkest (pupil, lashes) only greyed a little. A frame whose eye area doesn't match the
    # first frame (head turned, eyes shut) is left alone (ref = the first frame).
    for (x0,y0,x1,y1) in (eyes or []):
        X0,Y0,X1,Y1=max(0,x0-3),max(0,y0-3),min(W,x1+4),min(H,y1+4)
        if ref is not None:
            if np.abs(lum[Y0:Y1,X0:X1]-ref[Y0:Y1,X0:X1]).mean()>0.07: continue
        box=np.zeros_like(face); box[y0:y1+1,x0:x1+1]=True
        ring=nd.binary_dilation(box,iterations=2)&~box
        sref=np.median(a[ring],axis=0)
        dist=np.sqrt(((a-sref)**2).sum(-1))
        eye=box&(dist>0.16)
        if eye.sum()==0: continue
        dark=eye&(lum<0.13)
        e2=eye&~dark
        if e2.sum():
            cut=np.percentile(lum[e2],50)
            bright=e2&(lum>=cut); dim=e2&~bright
            out[bright]=out[bright]*0.2+0.8*np.array([0.64,0.63,0.52])*(0.72+0.3*lum[bright][:,None])
            out[dim]=out[dim]*0.2+0.8*np.array([0.55,0.57,0.55])*(0.72+0.45*lum[dim][:,None])
        out[dark]=out[dark]*0.6+0.4*np.array([0.30,0.31,0.30])
        if decay>0:
            rim=nd.binary_dilation(eye,iterations=1)&~eye&box
            out[rim]=out[rim]*(1-0.25*decay)+np.array([0.42,0.12,0.12])*0.25*decay
    out[key]=a[key]   # the transparent colour stays exact
    return Image.fromarray((out.clip(0,1)*255).astype('uint8'))
