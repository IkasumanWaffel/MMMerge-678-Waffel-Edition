import numpy as np
def l_lhu(x,y): return y-(443-(x-233)*0.109)
def l_rhu(x,y): return (777-(y-340)*0.134)-x
def l_rhd(x,y): return (y-368)-(x-1265)*0.8
def l_lhd(x,y): return y-412
def l_lho(x,y): return y-(437-(x-2293)*0.048)
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-2))(f) for k,f in LN.items()}
BANDW={}
CLAWS=False
