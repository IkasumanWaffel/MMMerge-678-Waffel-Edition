import sys; sys.path.insert(0,'.')
from robefit import *
def comp(bod,bx,by,armor,ax,ay,W=200,H=400):
    c=Image.new('RGBA',(W,H),(40,40,50,255))
    for im,(x,y) in ((get(bod),(bx,by)),(armor,(ax,ay))):
        a=np.asarray(im.convert('RGB')).astype(int); k=keymask(im.convert('RGB'))
        c.alpha_composite(Image.fromarray(np.dstack([a,(k*255)]).astype('uint8'),'RGBA'),(x,y))
    return c
def make(aligned, ref, base, bod, body_off, armor_off, waist, side='right', dark=0.55, **kw):
    big=Image.open(aligned); refim=Image.open(ref).convert('RGB')
    rgb,M,box,Bc,wy=cut(big,base,bod,body_off,armor_off,waist,ref=refim,hang=('left' if side=='right' else 'right'),**kw)
    rgb,M=fill_sleeve_hollow(rgb,M,Bc,wy,side,dark=dark)
    rgb=shade_sleeve(rgb,M,Bc,wy,side)
    ys,xs=np.where(M); box=(int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1))
    return sprite(rgb,M,box), box

def drop_skin(spr, minsize=6, side='left', frac=0.22):
    """the generated hand of the hanging arm (the game draws that arm on its own)"""
    a=np.asarray(spr).astype(int); r,g,b=a[...,0],a[...,1],a[...,2]
    key=(r<20)&(g>230)&(b>230)
    skin=(~key)&(r-b>45)&(g-b<60)&(r-g>22)&(r>95)
    ys,xs=np.where(~key); H,W=key.shape
    # the torso's centre and width at the chest (a third of the way down)
    yc=int(ys.min()+0.18*(ys.max()-ys.min()))
    row=np.where(~key[yc])[0]; cx=(row.min()+row.max())/2; w=row.max()-row.min()
    zone=np.zeros_like(key)
    if side=='left': zone[:, :int(cx-frac*w)]=True
    else: zone[:, int(cx+frac*w):]=True
    skin&=zone
    lab,n=ndimage.label(skin)
    out=a.copy()
    if n:
        sizes=ndimage.sum(skin,lab,range(1,n+1))
        kill=np.isin(lab,[i+1 for i,v in enumerate(sizes) if v>=minsize])
        kill=ndimage.binary_dilation(kill,iterations=1)&~key
        out[kill]=(0,252,252)
    return Image.fromarray(out.astype('uint8'))


def drop_fur(spr, waist_row, rb=28, rg=5, minsize=4):
    """a furred doll (minotaur): the generated fur of the neck and the hand above the sash"""
    a=np.asarray(spr).astype(int); r,g,b=a[...,0],a[...,1],a[...,2]
    key=(r<20)&(g>230)&(b>230)
    fur=(~key)&(r-b>rb)&(r>g+rg)
    fur[max(0,waist_row-3):,:]=False
    lab,n=ndimage.label(fur)
    out=a.copy()
    if n:
        sizes=ndimage.sum(fur,lab,range(1,n+1))
        kill=np.isin(lab,[i+1 for i,v in enumerate(sizes) if v>=minsize])
        kill=ndimage.binary_dilation(kill,iterations=1)&~key
        kill[max(0,waist_row-3):,:]=False
        # the rest of the hand around it: darker than the cloth
        lum=a.sum(axis=2)
        robe=(~key)&(~kill)
        med=np.median(lum[robe]) if robe.any() else 300
        near=ndimage.binary_dilation(kill,iterations=4)&(lum<0.72*med)&~key
        near[max(0,waist_row-3):,:]=False
        kill=kill|near
        out[kill]=(0,252,252)
    # holes left inside the cloth: painted over from around
    import cv2
    k2=(out[...,0]<20)&(out[...,1]>230)&(out[...,2]>230)
    holes=ndimage.binary_fill_holes(~k2)&k2
    if holes.any():
        img=out.astype('uint8')
        out=cv2.inpaint(img,holes.astype('uint8')*255,3,cv2.INPAINT_TELEA).astype(int)
    return Image.fromarray(out.astype('uint8'))

def drop_specks(spr, minsize=30):
    a=np.asarray(spr).astype(int)
    key=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230)
    lab,n=ndimage.label(~key)
    if n>1:
        sizes=ndimage.sum(~key,lab,range(1,n+1))
        small=np.isin(lab,[i+1 for i,v in enumerate(sizes) if v<minsize])
        # thin bits hanging off the robe: an opening removes them
        thin=(~key)&~ndimage.binary_opening(~key,iterations=1)
        a[small|thin]=(0,252,252)
    return Image.fromarray(a.astype('uint8'))

def fill_cuff(spr, waist_row, side='right', close=5, dark=0.55, lining=4):
    """the inside of an empty sleeve opening (the game draws the forearm from it)"""
    a=np.asarray(spr).astype(float)
    key=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230)
    m=~key; H,W=m.shape
    ys,xs=np.where(m[:waist_row]); cx=(xs.min()+xs.max())/2; w=xs.max()-xs.min()
    zone=np.zeros_like(m); zone[:waist_row]=True
    if side=='right': zone[:, :int(cx+0.15*w)]=False
    else: zone[:, int(cx-0.15*w):]=False
    sl=m&zone
    from scipy.spatial import ConvexHull
    from PIL import ImageDraw
    pts=np.argwhere(sl)[:, ::-1]
    hull=ConvexHull(pts)
    poly=[tuple(map(float,pts[v])) for v in hull.vertices]
    hm=Image.new('L',(W,H),0); ImageDraw.Draw(hm).polygon(poly,fill=255)
    closed=np.asarray(hm)>0
    hol=closed&~m&zone
    if hol.any():
        med=np.median(a[sl],axis=0)
        d=ndimage.distance_transform_edt(~sl)
        hol=hol&(d<=lining)
        f=dark*(0.7+0.3*np.exp(-d/3))
        a[hol]=(med[None,:]*f[hol][:,None])
    return Image.fromarray(np.clip(a,0,255).astype('uint8'))
