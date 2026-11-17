import numpy as np
def l_lhu(x,y): return y-(398-(x-215)*0.076)
def l_rhu(x,y): return 838-x
def l_rhd(x,y): return (y-320)-(x-1320)*0.955
def l_lhd(x,y): return y-(415-(x-1860)*(20/165))
def l_lho(x,y): return y-(390-(x-2290)*(25/165))
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-4))(f) for k,f in LN.items()}
BANDW={}
CLAWS=False
