import sys; sys.path.insert(0,'/tmp/claude-0/-home-claude/ec75bc74-21d8-5efd-8e01-3e7a24881005/scratchpad')
import lod32, numpy as np
from PIL import Image
from scipy import ndimage as nd
PRE=sys.argv[1]; PORTS=[int(v) for v in sys.argv[2].split(',')]
d,e=lod32.entries('/mnt/user-data/uploads/Data/mmmerge.icons.lod')
for p in ['lhu','rhu','rhd','lhd','lho']:
    g=np.array(Image.open(f'{PRE}_{p}.png').convert('RGB')).astype(int)
    ox,oy=map(int,open(f'{PRE}_{p}.off').read().split())
    Q=8; h0,w0=g.shape[:2]
    gm=~((g[...,0]<20)&(g[...,1]>230)&(g[...,2]>230))
    # work canvas in hand-frame coords with margin Q
    hands=[np.array(lod32.bitmap(d,e[f'7pc{n}{p}'][0]).convert('RGB')).astype(int) for n in PORTS]
    H,W=max(a.shape[0] for a in hands)+2*Q, max(a.shape[1] for a in hands)+2*Q
    H=max(H,oy+Q+h0+Q); W=max(W,ox+Q+w0+Q)
    C=np.zeros((H,W,3),int); M=np.zeros((H,W),bool)
    C[oy+Q:oy+Q+h0,ox+Q:ox+Q+w0]=g; M[oy+Q:oy+Q+h0,ox+Q:ox+Q+w0]=gm
    near=nd.binary_dilation(M,iterations=4)
    top=oy+Q+3   # stay below the cuff band rows
    add=np.zeros_like(M)
    for a in hands:
        A=np.zeros((H,W,3),int); A[Q:Q+a.shape[0],Q:Q+a.shape[1]]=a
        fg=~((A[...,0]<40)&(A[...,1]>200)&(A[...,2]>200))&(A.sum(2)>0)
        skin=fg&(A[...,0]>120)&(A[...,0]-A[...,2]>35)
        cand=skin&near&~M
        cand[:top]=False
        add|=cand
    add=nd.binary_dilation(add,iterations=1)&near&~M; add[:top]=False
    idx=nd.distance_transform_edt(~M,return_distances=False,return_indices=True)
    C[add]=C[idx[0][add],idx[1][add]]*0.92
    M2=M|add
    ys,xs=np.nonzero(M2); y0,y1,x0,x1=ys.min(),ys.max()+1,xs.min(),xs.max()+1
    out=np.where(M2[...,None],C,(0,255,255))[y0:y1,x0:x1]
    Image.fromarray(out.astype('uint8')).save(f'{PRE}_{p}.png'); open(f'{PRE}_{p}.off','w').write(f'{x0-Q} {y0-Q}')
    print(p,'added',add.sum(),'off',x0-Q,y0-Q,'size',x1-x0,y1-y0)
