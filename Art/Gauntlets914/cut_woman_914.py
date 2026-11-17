import numpy as np
def l_lhu(x,y): return y-488
def l_rhu(x,y): return 862-x
def l_rhd(x,y): return 1000+0*x
def l_lhd(x,y): return y-481
def l_lho(x,y): return (y-465)-(x-2200)*0.29
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-14))(f) for k,f in LN.items()}
BANDW={}; CLAWS=False; RECOL=False
def SKIN(g,dist):
    r,gg,b=g[...,0],g[...,1],g[...,2]
    return (r-b>15)&(gg<0.74*r)&(dist<90)
