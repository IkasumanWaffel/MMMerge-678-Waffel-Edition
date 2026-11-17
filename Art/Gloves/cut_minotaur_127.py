def l_lhu(x,y): return y-550
def l_rhu(x,y): return 878-x
def l_rhd(x,y): return (y-455)-(x-1335)*(85/133)
def l_lhd(x,y): return y-(545+(x-1790)*0.1)
def l_lho(x,y): return y-(528+(x-2280)*0.08)
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-4))(f) for k,f in LN.items()}
BANDW={'lhu':38,'rhd':34}   # synthesize an orange band this many gen px deep
