import numpy as np
def l_lhu(x,y): return y-236
def l_rhu(x,y): return 940-x
def l_rhd(x,y): return (y-255)-(x-1360)*0.52
def l_lhd(x,y): return y-227
def l_lho(x,y): return y-222
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-14))(f) for k,f in LN.items()}
BANDW={}; CLAWS=False; RECOL=False
def SKIN(g,dist):
    r,gg,b=g[...,0],g[...,1],g[...,2]
    gold=(r-b>40)&(gg>0.74*r)
    return ((b<r-5)&~gold&(dist<90))|(gg-r>60)
