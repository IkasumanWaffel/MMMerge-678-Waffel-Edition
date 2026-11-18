import sys; sys.path.insert(0,'/tmp/rw'); from comp import *
import numpy as np
from scipy import ndimage as nd
from PIL import Image
def mask_of(im):
    a=np.array(im); return ~((a[...,0]<40)&(a[...,1]>200)&(a[...,2]>200))
def fitclip(k,pre,boff,box,hands,waist,ankle=None,src=None,redfix=True):
    a=np.array(Image.open(src or f'rw3_{k}.png').convert('RGB')).astype(int); H,W=a.shape[:2]
    C=np.zeros((440,260),bool)
    Bm=mask_of(bm(pre+'bod')); C[boff[1]:boff[1]+Bm.shape[0],boff[0]:boff[0]+Bm.shape[1]]|=Bm
    for n,(x,y) in hands:
        m=mask_of(bm(pre+n)); C[y:y+m.shape[0],x:x+m.shape[1]]|=m
    body=C[box[1]:box[1]+H,box[0]:box[0]+W]
    YY,XX=np.mgrid[0:H,0:W]
    d1=nd.binary_dilation(body,iterations=1); d2=nd.binary_dilation(body,iterations=2); d4=nd.binary_dilation(body,iterations=4); d6=nd.binary_dilation(body,iterations=6)
    r,g,b=a[...,0],a[...,1],a[...,2]
    key=(r<20)&(g>230)&(b>230)
    brown=~key&(r-b>25)&(r-g>8)&(r-g<45)&(YY>=waist-5)
    allow=np.where(YY<45,d4,np.where(YY<waist,d2,d1))|(brown&d6)
    red=~key&(r>1.45*g+8)&(YY<waist+10)&redfix
    red=nd.binary_dilation(red,iterations=1)&~key&(YY<waist+10)&(r>g+6)
    lum=0.3*r+0.59*g+0.11*b; v=np.clip(lum*0.6,18,70)
    a[red]=np.stack([v*1.03,v,v*0.96],-1)[red]
    a[~allow&~key]=(0,252,252)
    m=~((a[...,0]<20)&(a[...,1]>230))
    if ankle is not None:
        m&=~ankle(XX,YY)
        m=np.where(YY>195,nd.binary_opening(m,np.ones((3,3))),m)
    a[~m]=(0,252,252)
    lab,n=nd.label(m); sz=nd.sum(m,lab,range(1,n+1)); keep=lab==(np.argmax(sz)+1)
    a[m&~keep]=(0,252,252)
    return a
