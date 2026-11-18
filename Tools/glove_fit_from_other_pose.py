# python3 fit_any.py SRC_PNG TARGET_ORIG OUT_PREFIX [mirror]
import sys, numpy as np
from PIL import Image
from scipy import ndimage as nd
src,tgt,outp=sys.argv[1:4]; mir=len(sys.argv)>4
F0=np.array(Image.open(tgt).convert('RGB')).astype(int)
Fm=~((F0[...,0]<90)&(F0[...,1]>200)&(F0[...,2]>200))
Gi=Image.open(src).convert('RGB')
if mir: Gi=Gi.transpose(Image.FLIP_LEFT_RIGHT)
Ga=np.array(Gi).astype(int); Gm=~((Ga[...,0]<20)&(Ga[...,1]>230)&(Ga[...,2]>230))
H,W=Fm.shape; P=10
Fp=np.zeros((H+2*P,W+2*P),bool); Fp[P:P+H,P:P+W]=Fm
Fd=nd.binary_dilation(Fp,iterations=1)
tip=Fp.copy(); tip[:P+H-16]=False
GA=Image.fromarray(np.dstack([Ga,Gm*255]).astype('uint8'),'RGBA')
best=None
for sc in np.arange(0.8,1.21,0.05):
  for ang in range(-80,81,5):
    im=GA.resize((max(1,int(GA.width*sc)),max(1,int(GA.height*sc))),Image.LANCZOS).rotate(ang,resample=Image.BICUBIC,expand=True)
    m=np.array(im)[...,3]>128; h,w=m.shape
    if h>H+2*P or w>W+2*P: continue
    for dy in range(0,H+2*P-h+1):
      for dx in range(0,W+2*P-w+1):
        C=np.zeros_like(Fp); C[dy:dy+h,dx:dx+w]=m
        s=(C&Fp).sum()-3*(C&~Fd).sum()+2*(C&tip).sum()
        if best is None or s>best[0]: best=(s,sc,ang,dx,dy)
print(best)
s,sc,ang,dx,dy=best
im=GA.resize((int(GA.width*sc),int(GA.height*sc)),Image.LANCZOS).rotate(ang,resample=Image.BICUBIC,expand=True)
a=np.array(im).astype(int); m=a[...,3]>128; h,w=m.shape
C=np.zeros((H+2*P,W+2*P),bool); C[dy:dy+h,dx:dx+w]=m; C&=Fd
rgb=np.zeros((H+2*P,W+2*P,3),int); rgb[dy:dy+h,dx:dx+w]=a[...,:3]
ys,xs=np.nonzero(C); y0,y1,x0,x1=ys.min(),ys.max()+1,xs.min(),xs.max()+1
out=np.where(C[...,None],rgb,(0,255,255))[y0:y1,x0:x1]
Image.fromarray(out.astype('uint8')).save(outp+'.png'); open(outp+'.off','w').write(f'{x0-P} {y0-P}')
print('off',x0-P,y0-P,'size',x1-x0,y1-y0,'tip uncovered',(tip&~C).sum())
