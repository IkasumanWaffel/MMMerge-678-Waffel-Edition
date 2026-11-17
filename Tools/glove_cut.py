# generic: python3 gb.py GEN SHEETLAYOUT OUTPREFIX name=srcpath ...
import sys, numpy as np
from PIL import Image
from scipy import ndimage as nd
gen, layout, outp = sys.argv[1:4]
exec(open(sys.argv[4]).read())
src = dict(a.split('=',1) for a in sys.argv[5:])
G=np.array(Image.open(gen).convert('RGB')).astype(float)
L=[l.split() for l in open(layout).read().splitlines()[1:] if l.strip()]
box={l[0]:(int(l[1]),int(l[2])) for l in L}
sheetW=(max(int(l[1])+int(l[3]) for l in L)+12)*8
def isbg(a): return (a[...,1]>180)&(a[...,2]>180)&(a[...,0]<120)
S0=G.shape[1]/sheetW*8
P=4
def down(ox,oy,s,w,h):
    out=np.zeros((h,w,3)); cov=np.zeros((h,w))
    for y in range(h):
        for x in range(w):
            x0=ox+x*s; y0=oy+y*s
            blk=G[max(0,int(y0)):max(0,int(y0+s)), max(0,int(x0)):max(0,int(x0+s))].reshape(-1,3)
            if len(blk)==0: continue
            fg=~isbg(blk); cov[y,x]=fg.mean()
            out[y,x]=blk[fg].mean(0) if fg.any() else (0,255,255)
    return out,cov
for n,f in src.items():
    O=np.array(Image.open(f).convert('RGB')).astype(float)
    h,w=O.shape[:2]; om=~isbg(O); bx,by=box[n]; best=None
    for ds in np.linspace(0.94,1.06,7):
      s=S0*ds
      for dx in range(-8,9,2):
        for dy in range(-8,9,2):
          ox=bx*S0+dx*1.5; oy=by*S0+dy*1.5
          ys=(oy+(np.arange(h)+.5)*s).astype(int).clip(0,G.shape[0]-1); xs=(ox+(np.arange(w)+.5)*s).astype(int).clip(0,G.shape[1]-1)
          gm=~isbg(G[ys][:,xs]); iou=(gm&om).sum()/(gm|om).sum()
          if best is None or iou>best[0]: best=(iou,ox,oy,s)
    _,ox,oy,s=best
    g,cov=down(ox-P*s,oy-P*s,s,w+2*P,h+2*P)
    r,gg,b=g[...,0],g[...,1],g[...,2]; gfg=cov>0.5
    YY,XX=np.mgrid[0:h+2*P,0:w+2*P]; gx=ox-P*s+(XX+.5)*s; gy=oy-P*s+(YY+.5)*s
    hs=CUT[n](gx,gy)
    outm=gfg&hs&~((r>175)&(b>100))
    lab,k=nd.label(outm); sz=nd.sum(outm,lab,range(1,k+1)); outm=lab==(np.argmax(sz)+1)
    out=np.where(outm[...,None],g,(0,255,255))
    oc=out[P:P+h,P:P+w]; mc=outm[P:P+h,P:P+w]; yy,xx=np.nonzero(mc)
    x0,x1,y0,y1=xx.min(),xx.max()+1,yy.min(),yy.max()+1
    print(n,'iou %.3f'%best[0],'off',x0,y0,'size',x1-x0,y1-y0,'cut outside frame px',outm.sum()-mc.sum())
    Image.fromarray(oc[y0:y1,x0:x1].clip(0,255).astype('uint8')).save(f'{outp}_{n}.png'); open(f'{outp}_{n}.off','w').write(f'{x0} {y0}')
