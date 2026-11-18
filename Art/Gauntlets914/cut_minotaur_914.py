import numpy as np
def l_lhu(x,y): return y-436
def l_rhu(x,y): return 968-x
def l_rhd(x,y): return (y-365)-(x-1395)*1.26
def l_lhd(x,y): return y-428
def l_lho(x,y): return y-422
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-14))(f) for k,f in LN.items()}
BANDW={}; CLAWS=False; RECOL=False
def SKIN(g,dist):
    r,gg,b=g[...,0],g[...,1],g[...,2]
    return (r-b>15)&(gg<0.74*r)&(dist<90)
