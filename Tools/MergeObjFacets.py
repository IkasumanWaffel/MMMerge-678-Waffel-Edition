"""MergeObjFacets.py — fewer facets for models exported from CAD (Siemens NX) and the editor

Usage:  python MergeObjFacets.py in.obj out.obj [all]

Merges neighbouring triangles that lie in (almost) the same plane into convex polygons,
the way MM facets are: same material, convex, at most 19 corners (the editor triangulates
facets with more), corners at most BENT units from the facet's plane (the editor
triangulates facets bent more than 5 outdoors and 2 indoors). Duplicate vertices are
welded first. With "all", the parts the editor split a model into (name_1, name_2... of at
most 64 facets each) are merged as one model named after the first part.

Keeps vertices, texture coordinates, groups and materials. Polygons are merged only when
they lie in the same plane, use the same material and the same texture mapping, and the
result stays convex with at most MAXV corners."""
import sys, math
from collections import defaultdict
MAXV = 19          # the editor triangulates facets with more (Editor Import.lua)
ANG = 0.985        # normals' cosine pre-filter (about 10 degrees)
BENT = 4.0         # max distance of a merged facet's corners from its plane (the editor
                   # triangulates facets bent more than 5 outdoors, 2 indoors)
UVTOL = 0.5        # texture coordinate tolerance (texels)

def sub(a,b): return (a[0]-b[0],a[1]-b[1],a[2]-b[2])
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def dot(a,b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def norm(a):
    l=math.sqrt(dot(a,a)); return (a[0]/l,a[1]/l,a[2]/l) if l>1e-12 else None

def read(path):
    V=[];T=[];items=[]   # items: ('g',name) / ('m',mtl) / ('f',[(vi,ti)]) / ('x',line)
    for line in open(path,encoding='latin1'):
        s=line.strip()
        if s.startswith('v '): V.append(tuple(float(x) for x in s.split()[1:4]))
        elif s.startswith('vt '): T.append(tuple(float(x) for x in s.split()[1:3]))
        elif s.startswith('f '):
            c=[]
            for p in s.split()[1:]:
                q=p.split('/'); c.append((int(q[0])-1, int(q[1])-1 if len(q)>1 and q[1] else -1))
            items.append(('f',c))
        elif s.startswith('g '): items.append(('g',s[2:]))
        elif s.startswith('usemtl '): items.append(('m',s[7:]))
        else: items.append(('x',line.rstrip('\n')))
    return V,T,items

def plane(V,poly):
    # Newell normal
    n=[0,0,0]
    for i in range(len(poly)):
        a=V[poly[i][0]]; b=V[poly[(i+1)%len(poly)][0]]
        n[0]+=(a[1]-b[1])*(a[2]+b[2]); n[1]+=(a[2]-b[2])*(a[0]+b[0]); n[2]+=(a[0]-b[0])*(a[1]+b[1])
    n=norm(tuple(n))
    if not n: return None
    return n, dot(n,V[poly[0][0]])

def uvmap(V,T,tri):
    # affine map p -> uv from a triangle: uv = uv0 + M (p - p0), M from the edge basis
    (a,ta),(b,tb),(c,tc)=tri[:3]
    if ta<0: return None
    p0,p1,p2=V[a],V[b],V[c]; e1=sub(p1,p0); e2=sub(p2,p0)
    n=cross(e1,e2); nn=dot(n,n)
    if nn<1e-12: return None
    # dual basis
    d1=tuple(x/nn for x in cross(e2,n)); d2=tuple(x/nn for x in cross(n,e1))
    u0,u1,u2=T[ta],T[tb],T[tc]
    du1=(u1[0]-u0[0],u1[1]-u0[1]); du2=(u2[0]-u0[0],u2[1]-u0[1])
    def f(p):
        d=sub(p,p0); s=dot(d,d1); t=dot(d,d2)
        return (u0[0]+s*du1[0]+t*du2[0], u0[1]+s*du1[1]+t*du2[1])
    return f

def convex(V,poly,n):
    k=len(poly)
    if k<3: return False
    for i in range(k):
        a=V[poly[i][0]]; b=V[poly[(i+1)%k][0]]; c=V[poly[(i+2)%k][0]]
        if dot(cross(sub(b,a),sub(c,b)),n) < -1e-6: return False
    return len(set(p[0] for p in poly))==k

def merge_two(P,Q,i,j):
    # P edge (i,i+1) equals Q edge (j+1,j) reversed
    k=len(P); m=len(Q)
    out=P[:i+1]
    # walk Q from j+2 ... j-1 (excluding the shared edge vertices j, j+1)
    for s in range(2,m):
        out.append(Q[(j+s)%m])
    out+=P[i+1:]
    return out

def process(V,T,polys,mtl):
    # polys: list of corner lists (one material, one group)
    info=[]
    for p in polys:
        pl=plane(V,p)
        info.append(pl)
    alive=[pl is not None for pl in info]   # degenerate ones dropped
    maps=[uvmap(V,T,p) if alive[i] else None for i,p in enumerate(polys)]
    changed=True
    while changed:
        changed=False
        edge={}
        for i,p in enumerate(polys):
            if not alive[i]: continue
            for k in range(len(p)):
                edge[(p[k][0],p[(k+1)%len(p)][0])]=(i,k)
        for i,p in enumerate(polys):
            if not alive[i]: continue
            done=False
            for k in range(len(p)):
                a,b=p[k][0],p[(k+1)%len(p)][0]
                hit=edge.get((b,a))
                if not hit: continue
                j,l=hit
                if j==i or not alive[j]: continue
                n1,d1=info[i]; n2,d2=info[j]
                if dot(n1,n2)<ANG: continue
                q=polys[j]
                # same texture mapping (and same uv on the shared corners)
                if maps[i] and maps[j]:
                    if any(abs(maps[i](V[c[0]])[0]-T[c[1]][0])>UVTOL or abs(maps[i](V[c[0]])[1]-T[c[1]][1])>UVTOL for c in q): continue
                if len(p)+len(q)-2>MAXV: continue
                new=merge_two(p,q,k,l)
                pl=plane(V,new)
                if not pl or not convex(V,new,pl[0]): continue
                if max(abs(dot(pl[0],V[c[0]])-pl[1]) for c in new) > BENT: continue
                polys[i]=new; alive[j]=False; info[i]=pl
                changed=done=True
                break
            if done:
                # rebuild the edge map after a merge
                edge={}
                for ii,pp in enumerate(polys):
                    if not alive[ii]: continue
                    for kk in range(len(pp)):
                        edge[(pp[kk][0],pp[(kk+1)%len(pp)][0])]=(ii,kk)
    return [p for i,p in enumerate(polys) if alive[i]]

def weld(V,faces):
    key={}; remap={}; NV=[]
    for i,v in enumerate(V):
        k=(round(v[0],3),round(v[1],3),round(v[2],3))
        if k not in key: key[k]=len(NV); NV.append(v)
        remap[i]=key[k]
    return NV,[[(remap[a],b) for a,b in f] for f in faces]

def main(src,dst,across_groups=False):
    V,T,items=read(src)
    import re
    order=[]; buckets={}; g=None; m=None; faces=[]; tags=[]
    base=None
    for it in items:
        if it[0]=='g':
            g=it[1]
            if base is None: base=re.sub(r'_\d+$','',g)   # the editor's parts of one model: name_1, name_2...
        elif it[0]=='m': m=it[1]
        elif it[0]=='f':
            faces.append(it[1]); tags.append((base if across_groups else g, m))
    V,faces=weld(V,faces)
    before=len(faces)
    for f,t in zip(faces,tags):
        if t not in buckets: buckets[t]=[]; order.append(t)
        buckets[t].append(f)
    res={t:process(V,T,buckets[t],t[1]) for t in order}
    after=sum(len(r) for r in res.values())
    with open(dst,'w',encoding='latin1',newline='\n') as f:
        f.write('# Coplanar triangles merged into convex facets (%d -> %d)\n' % (before, after))
        for h in items_header(src): f.write(h+'\n')
        for v in V: f.write('v %g %g %g\n' % v)
        for t in T: f.write('vt %.8g %.8g\n' % t)
        lastg=object()
        for t in order:
            if t[0]!=lastg:
                f.write('g %s\n' % (t[0] or 'model')); lastg=t[0]
            f.write('usemtl %s\n' % t[1])
            for p in res[t]:
                f.write('f '+' '.join('%d/%d'%(a+1,b+1) if b>=0 else '%d'%(a+1) for a,b in p)+'\n')
    return before, after

def items_header(src):
    h=[]
    for line in open(src,encoding='latin1'):
        s=line.strip()
        if s.startswith('mtllib'): h.append(s)
    return h

if __name__=='__main__':
    b,a=main(sys.argv[1],sys.argv[2],len(sys.argv)>3); print('facets',b,'->',a)
