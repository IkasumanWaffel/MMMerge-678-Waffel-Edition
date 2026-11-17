from PIL import Image; import numpy as np
from scipy import ndimage as nd
G=np.array(Image.open('/mnt/user-data/uploads/0939522c-image.jpg').convert('RGB')).astype(float)
src={'lhu':'91b6720e','rhu':'1290314b','rhd':'4c3445cb','lhd':'b4eff942','lho':'0f3b8017'}
box={'lhu':(12,27),'rhu':(52,42),'rhd':(110,12),'lhd':(166,28),'lho':(207,23)}
def isbg(a): return (a[...,1]>180)&(a[...,2]>180)&(a[...,0]<120)
S0=2576/2008*8
def sample(ox,oy,s,w,h,img=G):
    # original pixel (x,y) center -> generated coords; box-filter average
    out=np.zeros((h,w,3)); k=s
    for y in range(h):
        for x in range(w):
            x0=ox+x*k; y0=oy+y*k
            out[y,x]=img[int(y0):int(y0+k)+1, int(x0):int(x0+k)+1].reshape(-1,3).mean(0) if True else 0
    return out
res={}
for n,f in src.items():
    O=np.array(Image.open(f'/mnt/user-data/uploads/{f}-image.jpg').convert('RGB')).astype(float)
    h,w=O.shape[:2]; om=~isbg(O)
    bx,by=box[n]; best=None
    for ds in np.linspace(0.94,1.06,7):
      s=S0*ds
      for dx in range(-6,7,2):
        for dy in range(-6,7,2):
          ox=bx*S0+dx*s/8*4 -0; oy=by*S0+dy*s/8*4
          ox=bx*S0+dx*1.5; oy=by*S0+dy*1.5
          # mask via nearest sampling
          ys=(oy+(np.arange(h)+.5)*s).astype(int); xs=(ox+(np.arange(w)+.5)*s).astype(int)
          ys=ys.clip(0,G.shape[0]-1); xs=xs.clip(0,G.shape[1]-1)
          gm=~isbg(G[ys][:,xs])
          iou=(gm&om).sum()/(gm|om).sum()
          if best is None or iou>best[0]: best=(iou,ox,oy,s)
    print(n,best)
    res[n]=best
np.save('fit.npy',res,allow_pickle=True)
