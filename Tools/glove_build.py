from PIL import Image; import numpy as np
from scipy import ndimage as nd
exec(open('build.py').read().split('for n,f in src.items():\n    O=')[0])
for n,f in src.items():
    O=np.array(Image.open(f'/mnt/user-data/uploads/{f}-image.jpg').convert('RGB')).astype(float)
    h,w=O.shape[:2]; _,ox,oy,s=res[n]
    g,cov=down(ox-P*s,oy-P*s,s,w+2*P,h+2*P)
    r,gg,b=g[...,0],g[...,1],g[...,2]
    gfg=cov>0.5
    YY,XX=np.mgrid[0:h+2*P,0:w+2*P]; gx=ox-P*s+(XX+.5)*s; gy=oy-P*s+(YY+.5)*s
    L={'lhu':lambda x,y:y>=562,'rhu':lambda x,y:x<=768,'lhd':lambda x,y:y>=567,'lho':lambda x,y:y>=522,
       'rhd':lambda x,y:(y-700)-(x-1295)*(770-700)/(1420-1295)>=-4}
    handside=L[n](gx,gy)
    Op=np.full((h+2*P,w+2*P,3),(0,255,255.)); Op[P:P+h,P:P+w]=O
    om=~isbg(Op)
    near=nd.binary_dilation(~handside,iterations=2)
    outm=handside&gfg&~(near&((g[...,0]-g[...,1])<20))
    out=np.where(handside[...,None],g,Op); out[~outm]=(0,255,255)
    yy,xx=np.nonzero(outm)
    print(n,w,h,'bbox',xx.min()-P,xx.max()-P,yy.min()-P,yy.max()-P)
    outc=out[P:P+h,P:P+w]; mc=outm[P:P+h,P:P+w]; yy,xx=np.nonzero(mc); x0,x1,y0,y1=xx.min(),xx.max()+1,yy.min(),yy.max()+1
    Image.fromarray(outc[y0:y1,x0:x1].clip(0,255).astype('uint8')).save(f'g_{n}.png'); open(f'g_{n}.off','w').write(f'{x0} {y0}')
    np.save(f'{n}_m.npy',outm)
