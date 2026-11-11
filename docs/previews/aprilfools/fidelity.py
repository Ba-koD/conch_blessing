"""Reference-constrained, closed volumes with source-aligned detail.

The original's projection is the construction drawing, not a diffuse texture
on a billboard. Smooth volume comes from a Poisson inflation field (independent
of the image's luminance); semantic relief is added only at named landmarks.
Material regions retain original eyes, insignia, lettering and colour breaks.
Outer ink is replaced by the adjacent body's material, not extruded black.
The surface has a complete round back. Paper/metal plates have bounded depth.
"""
from dataclasses import dataclass
import colorsys
import numpy as np
from PIL import Image
from scipy import ndimage, sparse
from scipy.sparse.linalg import spsolve
from skimage.measure import marching_cubes
from mesh3d import Part, material, sphere

UP=4

# Depths are authored in source-pixel units, not inferred from painted light.
# Each item retains its own source view, angle, scale, spacing and markings.
PLATES={
 'appraisal_certificate':.6,'a_minus':.6,'b_minus':.6,'c_minus':.6,'f_minus':.6,
 'wrong_answer_note':1.1,'tyrfing':.7,'sealed_demon_sword':.85,'void_dagger':.7,
 'atropos':.75,'severed_oath':.65,'two_faced_penny':1.1,
 'ceil':1.1,'floor':1.1,'round':1.1,'angels_crown':1.3,
 'real_eyes':1.3,'ar_glasses':1.2,
 'jangseung':2.4,'soflam':2.8,
}
CAPS={'kronos':1.7,'utility_belt':3.2,'oral_steroids':2.4,'injectable_steroids':2.3,'soflam':5,
      'jangseung':3.3,'kids_menu':5.5,'hermit_crab':6.5,'money_tear':2.5,
      'time_luck':2.8,'time_power':2.8,'time_tear':2.8,'power_training':4}
METAL={'kronos','tyrfing','sealed_demon_sword','void_dagger','atropos','severed_oath',
       'two_faced_penny','angels_crown','power_training','time_money'}
PAPER={'appraisal_certificate','wrong_answer_note','a_minus','b_minus','c_minus','f_minus'}
ANIMALS={'ox','dog','tiger','horse','pig','monkey','rabbit','rat','goat','snake','chicken',
         'dragon','azure_dragon','hermit_crab','kids_menu','hemispatial_neglect','polycoria','live_eye','jangseung'}

# Real material boundaries, not light/dark variants of one surface. Explicit
# swatch families prevent gold becoming orange or a pale muzzle merging into fur.
GROUPS={
 'kronos':[['8c6004','cd9608','fff8d6','ffd600','fff378']],
 'ox':[['b9823e','936030'],['ceb184','b69360'],['ede0b8']],
 'monkey':[['815638','5d3e2d'],['cfac7b','e7d6ae'],['b64547'],['efb7a0']],
 'rabbit':[['b98088'],['8f3338','c15e56']],
}
GROUPS.update({
 'ox':[['b9823e','936030'],['ceb184','b69360'],['ede0b8','faf6e8']],
 'dog':[['e5decc','a59f92','fff3dc']],
 'tiger':[['d79535','a85a29'],['e7d6a6','b59b78','f5edca']],
 'pig':[['c78291','8b5263'],['d5ab4d','967034']],
 'horse':[['9cbad2','526d8a'],['e3e1d3','b3b4ae','fff4db']],
 'rabbit':[['e9e1cb','aba89f','fff4db'],['c15e56','8f3338']],
 'rat':[['8b8d8b','4e5554'],['bc8a93','926875']],
 'goat':[['65616a','34313d'],['e8dfca','b4ac9b','fff3db']],
 'hermit_crab':[['0e0c16','1e1a2c','242038'],['b2c8ee','96aee2','d6e2f8','e8f0fc','f4faff','ccb6e6'],['7e98d6','6e80ba']],
 'dragon':[['2083ca','195b96','85cee4'],['dfb42c','f0d364','fff0ba']],
 'azure_dragon':[['104389','0b2354','176cb5','2b98d3'],['e9bd39','967025','fff0a0']],
 'chicken':[['c84940','8d2d32'],['d3a232','94712d'],['e9e3ce','b0aaa0']],
 'kids_menu':[['616999','4b5277','8b91b5'],['478733','235b13','77b367'],
              ['b30000','6b0000','9b0000','cb0000'],['e3c6c5','b97371','cf9c9b'],
              ['f8f7f2','ffffff','dedbd3'],['acacac','a7a7a7','dbdbdb']],
})

# (x,y,rx,ry,amount): a physical muzzle, brow, inset or cavity in the source
# coordinate system. Nothing here reads RGB brightness as geometry.
LANDMARKS={
 'ox':[(16,23,6,3,1.7)],'dog':[(16,22,4,3,1.1)],
 'tiger':[(16,22,5,3,1.1)],'pig':[(16,20,5,4,1.4)],
 'horse':[(11,23,5,3,1.8)],'monkey':[(16,22,4,3,.7)],
 'hermit_crab':[(16,23,5.2,5,-1.1)],'live_eye':[(16,15,5,5,.7)],
 'polycoria':[(16,15,7,7,.6)],
 'oral_steroids':[(12,12,2,3,.45),(20,12,2,3,.45),(16,17,2,3,.5),
                  (11,21,2,3,.45),(22,20,2,3,.45),(16,25,2,3,.5)],
}

# Primary volumes follow the source drawing's anatomy. A mask alone creates
# a pinched cushion wherever two silhouette lobes meet; these ellipsoids give
# the skull/body a continuous back and let ears/horns stay secondary forms.
# (centre x/y, silhouette radii x/y, depth radius), in native source pixels.
VOLUMES={
 'ox':[(16,20,8.5,8,6.3)],'dog':[(16,19,10,9,6.5)],
 'tiger':[(16,20,10,10,7)],'pig':[(16,18,10,10,6.5)],
 'monkey':[(16,15,8,8,5),(16,25,6,4,3)],
 'goat':[(18,17,11,11,7)],'horse':[(15,19,7,10,5)],
 'rat':[(17,22,10,7,5.5)],'rabbit':[(15,21,7,6,5),(15,28,6,3,3)],
 'dragon':[(16,21,6,8,4.5)],'azure_dragon':[(16,17,10,12,6.5)],
 'hermit_crab':[(16,20,9,10,6.5),(20,11,6,8,4)],
 'polycoria':[(16,16,12,12,11.5)],'live_eye':[(16,16,8,8,7)],
 'hemispatial_neglect':[(1,16,14,13,10)],
 'chicken':[(16,20,6,7,4)],'snake':[(18,21,10,8,4)],
 'kids_menu':[(13,7,6,6,3),(9,17,7,7,5),(24,14,6,7,4.5),
              (16,25,6,6,6),(25,24,5,5,5)],
}


@dataclass
class Model:
    parts:list
    materials:dict
    source_mask:np.ndarray
    labels:np.ndarray
    axis:tuple=(0.,0.,0.)


def source(path):
    return path.copy() if isinstance(path,np.ndarray) else np.array(Image.open(path).convert('RGBA'))


def palette(a,key):
    """Remove perimeter ink; conserve interior details and material locations."""
    rgb=a[...,:3].astype(float);alpha=a[...,3]
    solid=alpha>=128
    # Soft breath/flame sheets still have an opaque core. Their glow is not a
    # second solid shell; light remains a material/emission property.
    if not solid.any():solid=alpha>=max(20,int(alpha.max()*.55))
    light=rgb@np.array([.299,.587,.114])
    dark=light<42
    outline=dark & (ndimage.distance_transform_edt(solid)<=2.5)
    # Perimeter ink is filled from adjacent substance; enclosed pupils remain.
    inkless=solid&~outline
    if not inkless.any():inkless=solid.copy();outline[:]=False
    # Preserve the original painted material/detail palette. Collapsing hue
    # families erased the pills, shell turns, fur patches and blade engravings.
    # This is surface colour only: the volume never reads painted luminance.
    colours,counts=np.unique(rgb[inkless],axis=0,return_counts=True)
    if len(colours)>64:
        im=Image.fromarray(a[...,:3]).quantize(colors=64,method=Image.Quantize.MAXCOVERAGE)
        rgb=np.array(im.convert('RGB')).astype(float)
        colours,counts=np.unique(rgb[inkless],axis=0,return_counts=True)
    grouped=[([tuple(c)],tuple(c)) for c in colours]
    explicit=[];taken=set()
    for group in GROUPS.get(key,[]):
        swatches=[tuple(int(c[j:j+2],16) for j in (0,2,4)) for c in group]
        explicit.append((swatches,swatches[0]));taken.update(swatches)
    grouped=explicit+[(cs,mid) for cs,mid in grouped if mid not in taken]
    if key=='kronos':
        # Its cream and brown bands are gold's painted lighting, not inlays.
        gold=[tuple(c) for c in colours if c@np.array([.299,.587,.114])>=45]
        darks=[([tuple(c)],tuple(c)) for c in colours if tuple(c) not in gold]
        grouped=[(gold,(205,150,8))]+darks
    labels=np.zeros(solid.shape,dtype=np.int32);mats={};bases=[]
    for i,(colours,mid) in enumerate(grouped,1):
        for c in colours:labels[inkless & np.all(rgb==c,axis=2)]=i
        mid=np.asarray(mid,float)
        # Unlike the earlier heuristic, yellow animal fur is matte, not gold.
        h,s,v=colorsys.rgb_to_hsv(*(mid/255))
        metal=key in METAL and mid.mean()>45 and key not in PAPER
        emissive=key in {'eternal_flame','fire_breath','ice_breath'}
        # The studio renderer adds sky reflection to metal: leave highlight
        # headroom instead of clipping a saturated gold face to pure yellow.
        render_base=mid*.76 if metal else mid
        mats[f'm{i}']=material(render_base,spec=.36 if metal else .13,shine=38 if metal else 18,
                               metal=metal,rough=.36 if metal else .72,glow=.2 if emissive else 0)
        bases.append(mid)
    # Colour the silhouette with adjacent substance, not a black outline.
    near=ndimage.distance_transform_edt(labels==0,return_distances=False,return_indices=True)
    labels[solid& (labels==0)]=labels[near[0],near[1]][solid & (labels==0)]
    return labels,mats,np.asarray(bases),solid


def inflation(mask,up=UP):
    """Solve -Laplacian(phi)=2 with zero boundary, then depth=sqrt(2*phi).

    For a circle this is a hemisphere. For irregular forms it produces a
    smooth, positive volume without skeleton ridges or a shading height map.
    """
    ids=np.full(mask.shape,-1,dtype=np.int32);ids[mask]=np.arange(mask.sum())
    ys,xs=np.nonzero(mask);n=len(xs)
    row=[np.arange(n)];col=[np.arange(n)];val=[np.full(n,4.)]
    for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
        yy=np.clip(ys+dy,0,mask.shape[0]-1);xx=np.clip(xs+dx,0,mask.shape[1]-1)
        neighbour=ids[yy,xx];inside=neighbour>=0
        row.append(ids[ys[inside],xs[inside]]);col.append(neighbour[inside]);val.append(np.full(inside.sum(),-1.))
    mat=sparse.csr_matrix((np.concatenate(val),(np.concatenate(row),np.concatenate(col))),shape=(n,n))
    phi=np.zeros(mask.shape);phi[mask]=spsolve(mat,np.full(n,2/up**2))
    return np.sqrt(np.maximum(2*phi,0))


def build(path,key,plate=None,cap=None,landmarks=True):
    a=source(path);h,w=a.shape[:2]
    if key=='conch_pearl':return pearl(a)
    if key=='inf_d6':return die(a)
    labels,mats,bases,mask=palette(a,key)
    if not mask.any():return Model([],mats,mask,labels)
    # Round the contour on a subpixel grid. Colour/lettering is assigned
    # separately, at its original coordinates, after the volume is built.
    padded=np.pad(mask,2)
    up=1 if max(h,w)>160 else UP
    fine=ndimage.gaussian_filter(np.repeat(np.repeat(padded.astype(float),up,0),up,1),2.0 if up==UP else .6)>=.5
    half=PLATES.get(key) if plate is None else plate
    depth=inflation(fine,up) if half is None else np.zeros_like(fine,dtype=float)
    limit=CAPS.get(key,float('inf')) if cap is None else cap
    if half is not None:
        # Rounded/bevelled edge with a planar centre for paper, blades, coins.
        d=ndimage.distance_transform_edt(fine)/up
        depth=np.minimum(half,np.sqrt(np.maximum(2*d*half-d*d,0)))
        depth[d>=half]=half
    yy,xx=np.indices(fine.shape);sx=(xx+.5)/up-2;sy=(yy+.5)/up-2
    if half is None:
        if key in VOLUMES:
            depth*=.6
            for x,y,rx,ry,rz in VOLUMES[key]:
                body=rz*np.sqrt(np.maximum(0,1-((sx-x)/rx)**2-((sy-y)/ry)**2))
                # Smooth maximum avoids a visible join where a small muzzle
                # or ear meets the main volume.
                k=.7;blend=np.clip(.5+.5*(body-depth)/k,0,1)
                depth=depth*(1-blend)+body*blend+k*blend*(1-blend)
            depth=ndimage.gaussian_filter(depth,1)
            depth*=np.minimum(1,ndimage.distance_transform_edt(fine)/(up*.7))
        depth*=min(1,limit/max(float(depth.max()),1e-6))
    # Thin weapons have a bevelled blade but a rounded grip and crossguard.
    if key in {'tyrfing','sealed_demon_sword','void_dagger'}:
        grip=(sy>22) if key!='void_dagger' else (sy<16)
        depth=np.where(grip,np.maximum(depth,np.minimum(inflation(fine,up),1.5)),depth)
    front=depth.copy()
    if landmarks:
        for x,y,rx,ry,amount in LANDMARKS.get(key,[]):
            bump=np.maximum(0,1-((sx-x)/rx)**2-((sy-y)/ry)**2)**2
            front+=amount*bump
    # The full turn must fit the same native frame. This limits only side depth,
    # never rescales the reference composition to a generic thumbnail size.
    ys,xs=np.nonzero(mask);cx=(xs.min()+xs.max()+1)/2
    radial=max(1,min(cx,w-cx)-.6)
    allowance=np.sqrt(np.maximum(radial**2-(sx-cx)**2,.04))
    front=np.minimum(np.maximum(front,.05),allowance)
    back=np.minimum(depth,allowance)
    front=np.where(fine,front,0);back=np.where(fine,back,0)
    reach=max(float(front.max()),float(back.max()))+1
    yydepth=np.arange(-reach,reach+.25,.25)
    sd=(ndimage.distance_transform_edt(~fine)-ndimage.distance_transform_edt(fine))/up
    # Quadratic profile creates a continuous rounded seam (no vertical skirt).
    Y=yydepth[None,None,:]
    limits=np.where(Y<0,front[...,None],back[...,None])
    # Use the squared radial profile. abs(Y)-depth has a cusp where the two
    # halves meet: even a circular mask then rendered with a ribbed side seam.
    # A circle's Poisson solution now yields x²+y²+z²-r² on the inside.
    outside_distance,nearest=ndimage.distance_transform_edt(~fine,return_indices=True)
    def extend(values):
        positive=values**2
        negative=-positive[nearest[0],nearest[1]]*outside_distance
        signed=np.where(fine,positive,negative)
        return ndimage.gaussian_filter(signed,2.5 if half is None else .65)
    potential=np.where(Y<0,extend(front)[...,None],extend(back)[...,None])
    field=Y**2-potential
    field=np.pad(field,1,constant_values=10)
    if field.min()>=0:
        # A light filament thinner than the meshing grid is not a solid body.
        # Its original light sprite is retained by native_frame.
        return Model([],mats,mask,labels)
    verts,faces,_,_=marching_cubes(field.astype(np.float32),0)
    row=(verts[:,0]-1+.5)/up-2;col=(verts[:,1]-1+.5)/up-2
    dep=yydepth[0]+(verts[:,2]-1)*.25
    v=np.stack([col-w/2,dep,h/2-row],axis=1)
    # Subpixel contour smoothing. Material positions are assigned afterwards,
    # so details stay registered rather than drifting with vertex smoothing.
    edges=np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]])
    edges=np.unique(np.sort(edges,axis=1),axis=0)
    adjacency=sparse.csr_matrix((np.ones(len(edges)*2),
        (np.r_[edges[:,0],edges[:,1]],np.r_[edges[:,1],edges[:,0]])),shape=(len(v),len(v)))
    degree=np.asarray(adjacency.sum(axis=1)).ravel()[:,None]
    for _ in range(8):
        for rate in (.38,-.39):v+=rate*(adjacency@v/np.maximum(degree,1)-v)
    # Material data is geometric face groups, not a sprite bitmap on a plane.
    mids=v[faces].mean(axis=1)
    fx=np.clip(mids[:,0]+w/2,0,w-1e-4);fy=np.clip(h/2-mids[:,2],0,h-1e-4)
    flabel=labels[np.floor(fy).astype(int),np.floor(fx).astype(int)]
    near=ndimage.distance_transform_edt(labels==0,return_distances=False,return_indices=True)
    labfill=labels[near[0],near[1]]
    empty=flabel==0;flabel[empty]=labfill[np.floor(fy[empty]).astype(int),np.floor(fx[empty]).astype(int)]
    # Back skin/material: local edge materials continue around horns and bars;
    # front-facing eyes/letters do not reappear as a mirrored face on the back.
    weights=np.bincount(labels[mask],minlength=len(bases)+1).astype(float)
    for i,c in enumerate(bases,1):
        if c@np.array([.299,.587,.114])<48:weights[i]*=.08
    base=int(weights.argmax())
    dist=ndimage.distance_transform_edt(mask)
    behind=mids[:,1]>0.05
    lum=np.array([0]+[c@np.array([.299,.587,.114]) for c in bases])
    if key in PAPER:
        base=int(np.argmax([c.mean() if c.max()-c.min()<40 else 0 for c in bases]))+1 if key!='wrong_answer_note' else base
    backlabels=np.full_like(labels,base)
    for i in range(1,len(bases)+1):
        patches,n=ndimage.label(labels==i)
        for j in range(1,n+1):
            patch=patches==j
            if lum[i]>=45 and ((key not in ANIMALS and key not in PAPER) or
                (patch.sum()<mask.sum()*.14 and (patch&(dist<=2.5)).any())):
                backlabels[patch]=i
    if key=='kids_menu':
        # The back of the plated familiars has the same five body colours,
        # not the white plate stretched across the whole collection.
        centres=[(13,7,(88,87,97)),(9,17,(82,85,137)),(24,14,(40,119,47)),
                 (16,25,(157,0,0)),(25,24,(238,185,180))]
        by,bx=np.indices(labels.shape)
        nearest=np.argmin([(bx-x)**2+(by-y)**2 for x,y,_ in centres],axis=0)
        for j,(_,_,colour) in enumerate(centres):
            idx=np.linalg.norm(bases-np.asarray(colour),axis=1).argmin()+1
            backlabels[nearest==j]=idx
        backlabels[by>=28]=np.argmax(bases.mean(axis=1))+1
    body_colours={'ox':'b9823e','dog':'e5decc','tiger':'d79535','pig':'c78291',
        'horse':'e3e1d3','rabbit':'e9e1cb','rat':'8b8d8b','goat':'e8dfca',
        'dragon':'2083ca','azure_dragon':'104389','monkey':'815638'}
    if key in body_colours:
        def colour_index(hx):
            rgb=np.array([int(hx[j:j+2],16) for j in (0,2,4)])
            return np.linalg.norm(bases-rgb,axis=1).argmin()+1
        by,bx=np.indices(labels.shape)
        backlabels[:]=colour_index(body_colours[key])
        if key=='ox':backlabels[(by<13)&((bx<10)|(bx>22))]=colour_index('ede0b8')
        if key=='dragon':backlabels[(by<15)|((by>23)&((bx<9)|(bx>22)))]=colour_index('dfb42c')
        if key=='horse':backlabels[(bx>21)&(by<25)]=colour_index('9cbad2')
        if key=='goat':
            backlabels[(bx<15)&(by>13)&(by<25)]=colour_index('65616a')
            backlabels[by>27]=colour_index('08080b')
    if key=='jangseung':
        by,bx=np.indices(labels.shape)
        backlabels[:]=np.linalg.norm(bases-[140,101,60],axis=1).argmin()+1
        backlabels[by<9]=np.linalg.norm(bases-[41,39,49],axis=1).argmin()+1
    tri=v[faces];volume=np.einsum('ij,ij->i',tri[:,0],np.cross(tri[:,1],tri[:,2])).sum()/6
    if volume<0:faces=faces[:,::-1]
    normals=Part(v,faces,'surface').vertex_normals()
    for _ in range(3):
        normals=.5*normals+.5*(adjacency@normals/np.maximum(degree,1))
        normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-9)
    # An eye/letter is a front marking, not a band circling the whole volume.
    # Use the body's local back material once the surface turns away from us.
    facing=normals[faces].mean(axis=1)[:,1]
    side=behind | (facing>-.38)
    flabel[side]=backlabels[np.floor(fy[side]).astype(int),np.floor(fx[side]).astype(int)]
    parts=[]
    for i in np.unique(flabel):
        fs=faces[flabel==i];used=np.unique(fs);remap=np.full(len(v),-1,dtype=np.int32);remap[used]=np.arange(len(used))
        parts.append(Part(v[used],remap[fs],f'm{i}',True,normals[used]))
    result=Model(parts,mats,mask,labels,(cx-w/2,0,0))
    if key=='angels_crown':bend_crown(result)
    return result


def bend_crown(model):
    """Wrap the reference's visible band/spikes into a wearable circular crown."""
    centre=model.axis[0]
    radius=max(np.abs(p.v[:,0]-centre).max() for p in model.parts)+.3
    curved=[]
    for p in model.parts:
        v=p.v.copy();x=v[:,0]-centre;arc=np.sqrt(np.maximum(radius**2-x*x,.01))
        v[:,1]-=arc
        n=p.vertex_normals().copy();n[:,0]-=x/arc*n[:,1]
        n/=np.maximum(np.linalg.norm(n,axis=1,keepdims=True),1e-9)
        curved.append(Part(v,p.f,p.mat,True,n))
        v=v.copy();v[:,1]*=-1;n=n.copy();n[:,1]*=-1
        curved.append(Part(v,p.f[:,::-1],p.mat,True,n))
    model.parts=curved
    from recipes import Model as Shapes
    model.materials['crown_side']=material((230,226,211),spec=.2,rough=.55)
    model.materials['crown_blue']=material((151,201,228),spec=.2,rough=.55)
    ends=Shapes()
    for sign in [-1,1]:
        ends.box((centre+sign*(radius-.65),0,-3.5),(1.2,6.5,2.2),'crown_side',.3)
        ends.box((centre+sign*(radius-.65),0,-3.2),(1.22,6.55,.48),'crown_blue',.15)
    model.parts+=ends.parts


def die(a):
    """A bevelled solid cube; keep the original visible face markings in place."""
    from recipes import Model as Shapes
    from mesh3d import R,S,T,move
    labels,mats,bases,mask=palette(a,'inf_d6')
    shape=Shapes().box((0,0,0),(12,12,12),'body',.4)
    parts=move(shape.parts,R('y',-28)@R('z',-25)@R('x',20))
    allv=np.vstack([p.v for p in parts]);lo=allv.min(0);hi=allv.max(0)
    yy,xx=np.nonzero(mask);w=a.shape[1];h=a.shape[0]
    sx=(xx.max()-xx.min())/(hi[0]-lo[0]);sz=(yy.max()-yy.min())/(hi[2]-lo[2])
    cx=(xx.min()+xx.max()+1-w)/2;cz=(h-yy.min()-yy.max()-1)/2
    parts=move(parts,T(cx,0,cz)@S(sx,min(sx,sz),sz))
    maxrad=max(np.linalg.norm(p.v[:,:2]-[cx,0],axis=1).max() for p in parts)
    if maxrad>14.3:parts=move(parts,T(cx,0,0)@S(14.3/maxrad,14.3/maxrad,1)@T(-cx,0,0))
    nearest=ndimage.distance_transform_edt(labels==0,return_distances=False,return_indices=True)
    filled=labels[nearest[0],nearest[1]]
    body=np.linalg.norm(bases-[122,32,46],axis=1).argmin()+1
    result=[]
    for p in parts:
        tri=p.v[p.f]
        for _ in range(5):
            u,v,z=tri[:,0],tri[:,1],tri[:,2];uv=(u+v)/2;vz=(v+z)/2;zu=(z+u)/2
            tri=np.concatenate([np.stack(q,axis=1) for q in [(u,uv,zu),(uv,v,vz),(zu,vz,z),(uv,vz,zu)]])
        normals=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-9)
        mid=tri.mean(axis=1);x=np.clip((mid[:,0]+w/2).astype(int),0,w-1);y=np.clip((h/2-mid[:,2]).astype(int),0,h-1)
        lab=filled[y,x];lab[normals[:,1]>=-.05]=body
        for i in np.unique(lab):
            t=tri[lab==i];n=np.repeat(normals[lab==i],3,axis=0)
            result.append(Part(t.reshape(-1,3),np.arange(t.size//3).reshape(-1,3),f'm{i}',True,n))
    return Model(result,mats,mask,labels,(cx,0,0))


def pearl(a):
    mask=a[...,3]>=128;labels,n=ndimage.label(mask)
    counts=np.bincount(labels.ravel());counts[0]=0;body=labels==counts.argmax()
    y,x=np.nonzero(body);cx=(x.min()+x.max()+1)/2;cy=(y.min()+y.max()+1)/2
    r=(max(x.max()-x.min(),y.max()-y.min())+1)/2-.25
    mat=material((195,194,210),spec=.45,shine=36,rough=.25,sheen=((.5,.25,.6),(.25,.5,.65)))
    part=sphere(r,'pearl',seg=64,rings=40,center=(cx-a.shape[1]/2,0,a.shape[0]/2-cy))
    return Model([part],{'pearl':mat},body,body.astype(int),(cx-a.shape[1]/2,0,0))


def native_frame(src,key,plate=None,cap=None):
    """Source-registered pose, including sparse foreground grip layers.

    Crop only modelling work; return to the exact source frame/pivot before
    rendering. Source animation and attachment tables remain authoritative.
    """
    from mesh3d import Camera,render,move,T
    src=src.convert('RGBA');w,h=src.size;box=src.getbbox()
    if box is None:return src,None
    x0,y0,x1,y1=box;x0-=2;y0-=2;x1+=2;y1+=2
    crop=np.array(src.crop((x0,y0,x1,y1)))
    cap=min(10,min(x1-x0,y1-y0)*.35) if cap is None else cap
    m=build(crop,key,plate=plate,cap=cap,landmarks=False)
    if not m.parts:return src,None
    m.parts=move(m.parts,T((x0+x1-w)/2,0,(h-y0-y1)/2))
    side=max(w,h)
    im=render(m.parts,m.materials,Camera(yaw=0,pitch=0,dist=400,ortho=side),size=side*3,ss=1)
    dx=(side-w)*3//2;dy=(side-h)*3//2
    im=im.crop((dx,dy,dx+w*3,dy+h*3)).resize((w,h),Image.Resampling.LANCZOS)
    return im,m
