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

def cut_at_elbow(spr, box, bod, body_off, waist_canvas, side='right', margin=1):
    """dolls whose body ends at the elbow (the game draws the forearms on their own): the
    outstretched sleeve ends there too"""
    a=np.asarray(spr).astype(int)
    key=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230)
    Bm=keymask(get(bod)); x0,y0=box[0],box[1]
    H,W=key.shape
    # the body in sprite coordinates
    B=np.zeros((H,W),bool); bh,bw=Bm.shape; dx=body_off[0]-x0; dy=body_off[1]-y0
    for y in range(bh):
        yy=y+dy
        if 0<=yy<H:
            xs=np.where(Bm[y])[0]+dx; xs=xs[(xs>=0)&(xs<W)]; B[yy,xs]=True
    ys,xs=np.where(~key[:max(1,waist_canvas-y0)]); cx=(xs.min()+xs.max())/2; w=xs.max()-xs.min()
    cols=np.arange(W)
    zone=(cols>cx+0.25*w) if side=='right' else (cols<cx-0.25*w)
    # the elbow: the lowest row of the body's arm in that zone above the waist
    rows=[y for y in range(min(H,waist_canvas-y0)) if (B[y]&zone).any()]
    if not rows: return spr
    elbow=max(rows)+margin
    for y in range(elbow,min(H,waist_canvas-y0)):
        a[y,zone]=(0,252,252)
    # an arm held out sideways: the sleeve ends where the body's arm ends
    armx=np.where((B&zone[None,:]).any(axis=0))[0]
    if len(armx):
        endx=(armx.max()+margin+2) if side=='right' else (armx.min()-margin-2)
        for y in range(min(H,waist_canvas-y0)):
            if side=='right': a[y,endx+1:]=np.where(zone[endx+1:,None], (0,252,252), a[y,endx+1:])
            else: a[y,:max(0,endx)]=np.where(zone[:max(0,endx),None], (0,252,252), a[y,:max(0,endx)])
    # the new edge a little darker, as the inside of the sleeve
    key2=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230)
    for x in np.where(zone)[0]:
        col=np.where(~key2[:elbow,x])[0]
        if len(col) and col.max()>=elbow-3:
            for k,f in enumerate((0.55,0.7,0.85)):
                y=elbow-1-k
                if y>=0 and not key2[y,x]: a[y,x]=(a[y,x]*f).astype(int)
    return Image.fromarray(a.astype('uint8'))

def cleanup(spr, waist_row, drop_blue=True, close=4, open_it=2):
    """final pass: loose specks and slivers, holes under the arms, cuirass-blue leftovers,
    the cyan fringe of the generated picture's background"""
    import cv2
    a=np.asarray(spr).astype(int)
    key=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230)
    M=~key
    # 1) the robe is the main body: slivers narrower than ~5 px that hang off it go
    core=ndimage.binary_opening(M,iterations=open_it)
    lab,n=ndimage.label(core)
    if n:
        sizes=ndimage.sum(core,lab,range(1,n+1)); core=lab==(1+int(np.argmax(sizes)))
    M=ndimage.binary_dilation(core,iterations=open_it+1)&M
    # 2) holes between the sleeves and the body (above the sash): closed and painted over
    up=np.zeros_like(M); up[:waist_row]=True
    closed=ndimage.binary_fill_holes(ndimage.binary_closing(M,structure=np.ones((3,3)),iterations=close))
    add=closed&~M&up
    paint=add.copy()
    # 3) bluish leftovers of the cuirass (the robe has no blue)
    if drop_blue:
        blue=M&(a[...,2]>a[...,0]+18)&(a[...,2]>a[...,1]+8)
        paint|=blue
    M=M|add
    img=np.where(M[...,None],a,0).astype('uint8')
    if paint.any():
        img=cv2.inpaint(img,paint.astype('uint8')*255,3,cv2.INPAINT_TELEA)
    a=img.astype(int)
    # 4) the cyan fringe: edge pixels tinted toward cyan take their inner neighbours' colour
    edge=M&ndimage.binary_dilation(~M,iterations=1)
    for it in range(2):
        tint=edge&((a[...,1]-a[...,0]>12)&(a[...,2]-a[...,0]>12))
        if not tint.any(): break
        inner=M&~tint
        for y,x in zip(*np.where(tint)):
            y0,y1,x0,x1=max(0,y-2),y+3,max(0,x-2),x+3
            nb=inner[y0:y1,x0:x1]
            if nb.any(): a[y,x]=a[y0:y1,x0:x1][nb].mean(axis=0)
            else: M[y,x]=False
        edge=M&ndimage.binary_dilation(~M,iterations=1)
    out=np.where(M[...,None],a,np.array([0,252,252])).astype('uint8')
    return Image.fromarray(out)

def cover_side(spr, box, bod, body_off, waist_canvas, side='right'):
    """the doll's own side showing between the outstretched sleeve and the sash: cloth;
    bright spike tips left at the cuff: gone"""
    import cv2
    a=np.asarray(spr).astype(int)
    key=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230); M=~key; H,W=M.shape
    Bm=keymask(get(bod)); x0,y0=box[0],box[1]
    B=np.zeros((H,W),bool); bh,bw=Bm.shape; dx=body_off[0]-x0; dy=body_off[1]-y0
    for y in range(bh):
        yy=y+dy
        if 0<=yy<H:
            xs=np.where(Bm[y])[0]+dx; xs=xs[(xs>=0)&(xs<W)]; B[yy,xs]=True
    wy=waist_canvas-y0
    ys,xs=np.where(M[:wy]); cx=(xs.min()+xs.max())/2; w=xs.max()-xs.min()
    cols=np.arange(W); zone=(cols>cx-0.05*w) if side=='right' else (cols<cx+0.05*w)
    show=B&~M; show[wy:]=False; show[:, ~zone]=False
    # only below the sleeve: rows under the lowest sleeve pixel of each column
    fill=np.zeros_like(show)
    for x in np.where(show.any(axis=0))[0]:
        top=np.where(M[:wy,x])[0]
        if len(top):
            fill[:wy,x]=show[:wy,x]&(np.arange(wy)>top.min())
    fill=ndimage.binary_dilation(fill,iterations=1)&~M
    fill[wy:]=False
    # bright spike tips at the cuff end only (the last few columns of the sleeve)
    lum=a.sum(axis=2)
    if M.any():
        xs_s=np.where((M[:wy]&zone[None,:]).any(axis=0))[0]
        if len(xs_s):
            endz=np.zeros_like(M)
            if side=='right': endz[:wy, xs_s.max()-6:]=True
            else: endz[:wy, :xs_s.min()+7]=True
            bright=M&endz&(lum>np.percentile(lum[M],97))
            a[bright]=(0,252,252); M=M&~bright
    # cloth greener or bluer than the robe on that side (cuirass leftovers): repainted
    off=M&((a[...,1]>a[...,0]+3)|(a[...,2]>a[...,0]+5)); off[wy:]=False; off[:, ~zone]=False
    off=ndimage.binary_dilation(off,iterations=1)&M
    off[wy:]=False
    fill=fill|off
    M2=M|fill
    img=np.where(M2[...,None],a,0).astype('uint8')
    img[fill]=0
    if fill.any(): img=cv2.inpaint(img,fill.astype('uint8')*255,4,cv2.INPAINT_TELEA)
    out=np.where(M2[...,None],img,np.array([0,252,252])).astype('uint8')
    return Image.fromarray(out)

def smooth_outline(spr, sigma=1.4, thr=0.5, dark_notch=True):
    """stair steps and nicks of the outline: the mask is blurred and traced again; pixels it
    adds take the colour of the cloth next to them"""
    import cv2
    a=np.asarray(spr).astype(np.uint8)
    key=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230)
    M=~key
    pad=6
    Mp=np.pad(M.astype(float),pad)
    Ms=ndimage.gaussian_filter(Mp,sigma)[pad:-pad,pad:-pad]>thr
    Ms=ndimage.binary_fill_holes(Ms)
    lab,n=ndimage.label(Ms)
    if n>1:
        sizes=ndimage.sum(Ms,lab,range(1,n+1)); Ms=lab==(1+int(np.argmax(sizes)))
    add=Ms&~M
    img=np.where(M[...,None],a,0).astype(np.uint8)
    if add.any():
        img=cv2.inpaint(img,add.astype(np.uint8)*255,3,cv2.INPAINT_TELEA)
    if dark_notch:
        # near-black specks on the outline (notches of shadow): the cloth's colour
        lum=img.astype(int).sum(axis=2)
        med=np.median(lum[Ms]) if Ms.any() else 300
        edge=Ms&ndimage.binary_dilation(~Ms,iterations=2)
        blk=edge&(lum<0.35*med)
        if blk.any():
            img=cv2.inpaint(img,blk.astype(np.uint8)*255,3,cv2.INPAINT_TELEA)
    out=np.where(Ms[...,None],img,np.array([0,252,252],np.uint8)).astype(np.uint8)
    return Image.fromarray(out)

def diagonal_side(spr, waist_row, side='left', up=14, down=45):
    """the hanging arm's side between the armpit and the skirt: cut along a straight line
    from the body's edge above to the skirt's edge below (no steps, no cuff)"""
    a=np.asarray(spr).copy()
    key=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230); M=~key; H,W=M.shape
    r1=max(0,waist_row-up); r2=min(H-1,waist_row+down)
    def edge(r):
        xs=np.where(M[r])[0]
        return (xs.min() if side=='left' else xs.max()) if len(xs) else None
    e1,e2=edge(r1),edge(r2)
    if e1 is None or e2 is None: return spr
    for y in range(r1,r2+1):
        t=(y-r1)/(r2-r1); lim=e1+(e2-e1)*t
        if side=='left': a[y,:max(0,int(np.floor(lim)))]=(0,252,252)
        else: a[y,int(np.ceil(lim))+1:]=(0,252,252)
    return Image.fromarray(a)
