import numpy as np
def l_lhu(x,y): return y-583
def l_rhu(x,y): return 826-x
def l_rhd(x,y): return (y-460)-(x-1350)*(95/105)
def l_lhd(x,y): return y-(558+(x-1830)*0.03)
def l_lho(x,y): return y-543
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-4))(f) for k,f in LN.items()}
BANDW={}
CLAWS=True
