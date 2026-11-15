import sys; sys.path.insert(0,'.')
from robe_make import *
from robefit import fit
import json
REF='/mnt/user-data/outputs/robe_refs/'
DOLLS={  # key: (ref file, base, body, body_off, armor_off, waist (armor-relative))
 'm': ('doll0_male_dressed_x4.png','item337v1','pc01bod',(30,33),(29,57),100),
 'f': ('doll1_female_dressed_x4.png','item337v2','pc02bod',(60,47),(47,70),89),
 't2':('doll2_minotaur_dressed_x4.png','item337v3','pc21bod',(47,62),(27,100),100),
 't3':('doll3_troll_dressed_x4.png','item337v4','pc23bod',(43,43),(0,0),177),
 't4':('doll4_type5_dressed_x4.png','item337v5','7pc13bod',(43,43),(33,96),94),
}
def build(k, gen_path, opts):
    reff,base,bod,boff,aoff,waist=DOLLS[k]
    big,best=fit(gen_path,REF+reff,None,bod,boff,base,aoff,waist)
    al=f'gen_{opts["tag"]}_{k}_x4.png'; big.save(al)
    W=aoff[1]+waist   # canvas row of the sash
    spr,box=make(al,REF+reff,base,bod,boff,aoff,waist,hang_rows=0,tol=opts.get('tol',22))
    box=[int(x) for x in box]
    blue=opts.get('drop_blue',True); notch=opts.get('dark_notch',True)
    if k=='m':
        spr=cleanup(spr,W-box[1],open_it=1,drop_blue=blue)
    elif k=='f':
        spr=drop_specks(drop_skin(spr) if opts.get('skin',True) else spr); spr=cleanup(spr,W-box[1],open_it=2,drop_blue=blue)
        spr=diagonal_side(spr,W-box[1])
    elif k=='t2':
        spr=drop_specks(drop_fur(spr,W-box[1]) if opts.get('fur',True) else spr); spr=cut_at_elbow(spr,box,bod,boff,W); spr=drop_specks(spr,10)
        a=np.asarray(spr); kk=(a[...,0]<20)&(a[...,1]>230)&(a[...,2]>230); ys,xs=np.where(~kk)
        spr=spr.crop((xs.min(),ys.min(),xs.max()+1,ys.max()+1)); box=[box[0]+int(xs.min()),box[1]+int(ys.min())]
        spr=cleanup(spr,W-box[1],open_it=1,drop_blue=blue)
    else:
        spr=drop_specks(drop_fur(spr,W-box[1]) if opts.get('fur',True) else spr); spr=cut_at_elbow(spr,box,bod,boff,W)
        spr=cleanup(spr,W-box[1],open_it=1,close=8,drop_blue=blue)
        spr=cover_side(spr,box,bod,boff,W,recolor=opts.get('recolor',True)); spr=drop_specks(spr,10)
    spr=smooth_outline(spr,dark_notch=notch)
    return spr,[int(box[0]),int(box[1])],best
