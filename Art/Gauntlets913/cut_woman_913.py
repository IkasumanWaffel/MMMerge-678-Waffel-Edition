import numpy as np
def l_lhu(x,y): return y-200
def l_rhu(x,y): return 336-x
def l_rhd(x,y): return (y-216)-(x-517)*0.9
def l_lhd(x,y): return y-188
def l_lho(x,y): return y-199
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-5))(f) for k,f in LN.items()}
BANDW={}; CLAWS=False; RECOL=False
