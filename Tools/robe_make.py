import sys; sys.path.insert(0,'.')
from robefit import *
def comp(bod,bx,by,armor,ax,ay,W=200,H=400):
    c=Image.new('RGBA',(W,H),(40,40,50,255))
    for im,(x,y) in ((get(bod),(bx,by)),(armor,(ax,ay))):
        a=np.asarray(im.convert('RGB')).astype(int); k=keymask(im.convert('RGB'))
        c.alpha_composite(Image.fromarray(np.dstack([a,(k*255)]).astype('uint8'),'RGBA'),(x,y))
    return c
def make(aligned, ref, base, bod, body_off, armor_off, waist, side='right', dark=0.55):
    big=Image.open(aligned); refim=Image.open(ref).convert('RGB')
    rgb,M,box,Bc,wy=cut(big,base,bod,body_off,armor_off,waist,ref=refim)
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
