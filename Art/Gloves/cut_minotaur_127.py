def l_lhu(x,y): return y-550
def l_rhu(x,y): return 878-x
def l_rhd(x,y): return (y-455)-(x-1335)*(85/133)
def l_lhd(x,y): return y-(545+(x-1790)*0.1)
def l_lho(x,y): return y-(528+(x-2280)*0.08)
LN={'lhu':l_lhu,'rhu':l_rhu,'rhd':l_rhd,'lhd':l_lhd,'lho':l_lho}
CUT={k:(lambda f:(lambda x,y:f(x,y)>=-4))(f) for k,f in LN.items()}
BANDW={'lhu':38,'rhd':34}   # synthesize an orange band this many gen px deep

CLAWS=True
from PIL import Image as _I, ImageDraw as _D
def PRE(G):
    # remove the extra (sixth) digit on the open left hand
    m=_I.new('L',(G.shape[1],G.shape[0]),0)
    _D.Draw(m).polygon([(2150+272,600+222),(2150+335,600+200),(2150+335,600+345),(2150+266,600+345),(2150+261,600+300)],fill=255)
    G[np.array(m)>0]=(0,255,255)
import numpy as np
