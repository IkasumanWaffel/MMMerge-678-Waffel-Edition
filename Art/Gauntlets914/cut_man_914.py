import numpy as np
def l_lhu(x,y): return y-322
def l_rhu(x,y): return 963-x
def l_rhd(x,y): return (y-505)-(x-1360)*0.66
def l_lhd(x,y): return y-342
def l_lho(x,y): return y-298
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-14))(f) for k,f in LN.items()}
BANDW={}; CLAWS=False; RECOL=False
def SKIN(g,dist):
    r,gg,b=g[...,0],g[...,1],g[...,2]
    return (r-b>15)&(gg<0.74*r)&(dist<90)
# right-down: line in hand-frame pixels through (21,37) and (37,45); band kept, arm above dropped
def l_rhd(x,y): return ((y-37)-(x-21)*0.47)*10
LN['rhd']=l_rhd; CUT['rhd']=lambda x,y:l_rhd(x,y)>=-30
FRAME_CUT={'rhd'}
