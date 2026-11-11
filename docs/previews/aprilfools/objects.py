"""Constructed objects, with authored sides, backs and source-registered ink.

Anatomy, containers, shells, mechanisms and hardware are built from actual
parts. No silhouette inflation, Poisson field or RGB displacement is used.
The reference supplies front markings only after construction is complete.
"""
import math
from functools import lru_cache
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage.measure import find_contours,approximate_polygon,marching_cubes
from recipes import Model, MATS, recipe as old_recipe, horn, scissors, hourglass, flame
from mesh3d import Part,T,R,S,move,lathe,sphere,material,Camera,render


MATS.update({
 'hide':material((177,122,59),spec=.14,rough=.8),
 'muzzle':material((204,176,130),spec=.12,rough=.8),
 'fur':material((224,218,199),spec=.14,rough=.8),
 'wool':material((226,217,192),spec=.09,rough=.85),
 'greyfur':material((119,126,124),spec=.12,rough=.8),
 'mane':material((99,133,162),spec=.18,rough=.7),
    'cloth':material((121,101,77),spec=.08,rough=.95),
 'paper':material((237,235,224),spec=.08,rough=.9),
 'parchment':material((218,168,47),spec=.08,rough=.9),
 'conchpaper':material((234,230,238),spec=.08,rough=.9),
 'leather':material((71,49,34),spec=.12,rough=.85),
 'sealmetal':material((87,78,72),spec=.4,metal=True,rough=.5),
 'blade':material((183,29,17),spec=.5,metal=True,rough=.33),
 'lens':material((15,27,31),spec=.85,rough=.12),
 'shellbody':material((167,191,230),spec=.4,rough=.34),
 'shellgroove':material((98,132,184),spec=.35,rough=.38),
 'crabbody':material((34,27,38),spec=.04,rough=.9),
 'zip':material((148,185,202),spec=.32,rough=.48),
    'bagfilm':material((169,202,214),spec=.42,rough=.28,alpha=.18),
 'ink_black':material((15,12,18),spec=.08,rough=.85),
 'ink_white':material((241,235,217),spec=.1,rough=.8),
 'ink_red':material((213,18,10),spec=.08,rough=.85),
 'ink_gold':material((234,191,58),spec=.18,rough=.6),
 'ink_brown':material((93,59,21),spec=.08,rough=.85),
 'ink_violet':material((118,100,176),spec=.1,rough=.8),
 'ink_lavender':material((176,164,224),spec=.16,rough=.6),
 'ink_pink':material((238,168,198),spec=.14,rough=.65),
 'mealblue':material((92,103,150),spec=.18,rough=.65),
 'mealgreen':material((68,130,48),spec=.16,rough=.7),
 'mealgrey':material((150,151,155),spec=.15,rough=.7),
 'mealred':material((166,9,14),spec=.2,rough=.6),
})


def new():
    m=Model();m.materials=MATS;m.axis=(0.,0.,0.);m.components=[]
    return m


def component(m,name,other,matrix=None):
    start=len(m.parts);m.add(other,matrix);m.components.append({'name':name,'start':start,'end':len(m.parts)})
    return m


def pipe_ring(m,z,rx,ry,width,mat):
    m.ring((0,0,z),rx,ry,width,mat,'xy');return m


def ear(side,x,z,skin='fur',inside='pink',height=5):
    m=Model()
    # A thick tapered auricle with a recessed front surface and a full back.
    m.tube([(x,0,z),(x+side*.6,.15,z+height*.6),(x+side*1.1,.5,z+height)],
           [1.8,1.2,.06],skin)
    m.plate([(x-1,z+.3),(x+1,z+.3),(x+side*.75,z+height-1)],.22,inside,-1.05,.08)
    return m


def head(key,paint=False):
    m=new()
    skin={'ox':'hide','dog':'fur','tiger':'amber','pig':'pink','dragon':'blue','azure_dragon':'blue'}.get(key,'fur')
    skull=Model().ball((0,.3,0),(7,5.6,7),skin,40)
    component(m,'skull and rear cranium',skull)
    if key=='ox':
        component(m,'protruding muzzle',Model().ball((0,-4.6,-3.7),(5.5,3.2,2.8),'muzzle',32))
        for s in [-1,1]:
            component(m,'horn',Model().tube([(s*5,0,5),(s*7,0,7),(s*7.7,.4,10),(s*6.8,1,11)],
                      [1.7,1.45,.8,.04],'ivory'))
            component(m,'ear',Model().ball((s*7.4,-.2,.4),(3,1.2,1.5),'hide'))
        if not paint:
            for s in [-1,1]:
                m.ball((s*3,-5.5,1.5),(1,.55,1),'ivory').ball((s*3,-6,1.4),(.45,.3,.6),'pupil')
                m.ball((s*2.5,-7.6,-3.5),(.6,.25,.55),'darkbrown')
    elif key=='dog':
        component(m,'tapered cheeks',Model().ball((0,-2,-3.5),(5.5,4.8,4),'fur'))
        component(m,'forward muzzle',Model().ball((0,-5.5,-3.8),(3.1,2.7,2.5),'fur'))
        for s in [-1,1]:component(m,'upright ear',ear(s,s*4.8,4.1,'fur','muzzle',6))
        m.ball((0,-8,-3.1),(1.15,.8,.65),'pupil')
    elif key=='tiger':
        for s in [-1,1]:
            m.ball((s*2.7,-4.9,-3),(3.4,2.3,2.6),'ivory')
            e=Model().ball((s*5.6,0,5.6),(2.3,1.7,2.4),'amber').ball((s*5.6,-1.6,5.6),(1.4,.3,1.5),'ivory')
            component(m,'rounded ear',e)
            # Stripes continue around the flanks and occiput, not a reflected face.
            for z in [-3,0,3]:
                m.tube([(s*6,-1,z),(s*6.7,1,z+.3),(s*5.7,3.4,z+1)],[.7,.7,.05],'black')
        for x in [-3,0,3]:m.tube([(x,4,4),(x*.8,5.8,1),(x*.6,4.8,-3)],[.7,.6,.05],'black')
    elif key=='pig':
        m.ball((-1.6,-4.6,-.5),(3.5,3.2,3),'skin')
        for s in [-1,1]:
            e=Model().tube([(s*5,0,4),(s*7,-.3,6),(s*8,-1.6,4.3)],[1.8,1.5,.12],'pink')
            component(m,'folded ear',e)
        m.ring((1.8,-7.5,-1.6),1,1.5,.42,'gold')
    elif key in ['dragon','azure_dragon']:
        m.ball((0,-5,-3),(3.8,3.1,3),'blue')
        for s in [-1,1]:
            h=Model()
            if key=='azure_dragon':
                m.tube([(s*3,-.5,5),(s*4,0,8),(s*3.7,1,11)],[1.8,1,.03],'blue')
                m.tube([(s*5,-2,3),(s*7,-1,7),(s*8,1,8)],[1.8,1,.03],'blue')
                m.ball((s*2.8,-5.2,1.4),(1.15,.6,1.1),'gold')
                for z in [-4,-1,2,5]:
                    m.tube([(s*5,0,z),(s*8,1,z+2),(s*7,3,z+4)],[1.3,.8,.03],'blue')
            else:
                h.tube([(s*4,0,5),(s*5,1,8),(s*6,2,11),(s*4.5,2,13)],[1,.8,.5,.03],'gold')
                h.tube([(s*5,1,8),(s*8,1.7,9),(s*9,2,11)],[.6,.5,.03],'gold')
                component(m,'branched antler',h)
                m.tube([(s*3,-6,-3),(s*7,-6,-1),(s*9,-4,-3)],[.55,.4,.03],'gold')
        for z in [-4,0,4]:m.tube([(0,4,z),(0,7,z+2),(0,4,z+4)],[1.4,.8,.03],'cyan')
    return m


def horse():
    m=new()
    component(m,'neck',Model().ball((3,.8,-3),(3.6,3.7,6.7),'fur',32))
    component(m,'skull',Model().ball((0,0,3),(4.6,3.6,5.1),'fur',32))
    component(m,'long sloping muzzle',Model().tube([(-1,0,3),(-3,-.4,0),(-6,-.8,-3)],[3.4,2.8,2.1],'fur'))
    for y in [-2.5,1]:m.ball((-6.6,y,-3),(.4,.3,.55),'darkbrown')
    m.ball((-2,-3.35,4),(.65,.35,.8),'pupil').ball((-2.15,-3.63,4.3),(.2,.12,.25),'white')
    for x,y in [(-.5,-1.7),(2,1.4)]:component(m,'ear',ear(-1,x,6.2,'fur','muzzle',5))
    # A real mane down the poll and rear neck, visible in a complete turn.
    component(m,'continuous flowing mane',Model().plate([(3,9),(5,8),(6,4),(7,2),(6,-1),(7,-3),(6,-5),(5,-8),(3,-8)],3.2,'mane',.5,.35))
    for y in [-.9,.5,1.9]:m.tube([(4,y,8),(5.8,y,4),(5.9,y,0),(4.8,y,-7)],.12,'blue')
    return m


def sheep():
    m=new();p=sphere(1,'wool',seg=64,rings=40)
    theta=np.arctan2(p.v[:,1],p.v[:,0]);phi=np.arccos(np.clip(p.v[:,2],-1,1))
    bumps=np.zeros(len(p.v))
    for i in range(38):
        z=1-2*(i+.5)/38;a=i*math.pi*(3-math.sqrt(5));r=math.sqrt(1-z*z)
        direction=np.array([r*math.cos(a),r*math.sin(a),z])
        bumps+=np.exp((p.v@direction-1)/.04)
    lobes=1+.10*(bumps-bumps.mean())
    p.v=p.v*lobes[:,None]*[7.3,5.5,6.4]+[1,0,-1]
    body=Model();body.parts.append(p);component(m,'continuous softly tufted wool coat',body)
    for x,z in [(-3,4.2),(-4,2),(-3,-.2)]:m.ball((x,-2.5,z),(2,2,2),'wool')
    component(m,'head and muzzle',Model().ball((-5,-2,1),(3,2.6,3.2),'iron').ball((-7,-2.8,.1),(2,2,1.8),'iron'))
    for x in [-3,4]:
        for y in [-2.9,2.9]:m.tube([(x,y,-4),(x,y,-7)],[.8,.65],'black')
    for side in [-1,1]:
        y=-2+side*2.7;m.ball((-5.5,y,2.4),(.5,.25,.7),'ivory').ball((-5.65,y+side*.2,2.4),(.25,.16,.4),'pupil')
    m.ball((-2,-3.1,2),(1.2,.6,.7),'iron')
    m.ball((7.2,1,-1),(1.8,1.5,1.6),'wool')
    return m


def rabbit():
    m=new();component(m,'body and haunches',Model().ball((0,1,-6),(4.7,3.7,4.4),'fur'))
    component(m,'head',Model().ball((0,-.7,0),(5.5,4,4.6),'fur',32))
    for s in [-1,1]:
        e=Model().ball((0,0,0),(1.6,1.3,7),'fur').ball((0,-1.18,.3),(.65,.2,5.4),'pink')
        component(m,'long ear',e,T(s*3,0,8)@R('y',s*10))
        m.ball((s*3,0,-9),(2,3,1.2),'fur').ball((s*3.6,-2,-5),(1.2,1,2),'fur')
    m.ball((0,4,-5),(1.8,1.8,1.8),'white')
    m.ball((1,-3.7,-6),(2.1,1.2,1.6),'red')
    return m


def monkey():
    m=new();component(m,'torso',Model().ball((0,.7,-6),(4.8,3.4,4.2),'brown'))
    component(m,'head',Model().ball((0,0,1.8),(6.6,4.5,6),'brown',32))
    # Face is a shallow anatomical mask over a complete cranium.
    m.ball((0,-3.9,2),(5,.9,4.4),'muzzle').ball((0,-4,-.7),(3.6,1.7,2),'muzzle')
    for s in [-1,1]:
        m.ball((s*6.5,0,2),(2,1.3,2.5),'brown').ball((s*6.5,-1.1,2),(1.1,.35,1.4),'muzzle')
        m.tube([(s*3,0,-4),(s*4.3,-2,-6),(s*2.5,-3,-7)],[1.3,1.1,.8],'brown')
        m.ball((s*2.5,-1,-9),(1.8,2,1),'darkbrown')
    m.tube([(2,2,-6),(5,4,-5),(5,5,-2),(3,5,-1)],[.65,.6,.45,.08],'brown')
    m.ball((3.7,-3.5,-5),(2,1.7,2.4),'red')
    return m


@lru_cache(maxsize=1)
def shell_surface():
    """An authored hollow shell, including the real aperture and tunnel wall.

    These are 3D radial/elliptical construction fields, independent of PNGs.
    The cavity removes actual shell volume; a dark disk is not a fake opening.
    """
    step=.3;x=np.arange(-9,10,step);y=np.arange(-8,9,step);z=np.arange(-7,15,step)
    X,Y,Z=np.meshgrid(x,y,z,indexing='ij')
    t=np.clip((Z+5.5)/19,0,1);angle=np.arctan2((Y-1)/.8,X-.16*Z)
    radius=(7.6*(1-t)**.72+.08)*(1+.10*np.cos(2*math.pi*t*3.3-angle))
    radial=np.sqrt((X-.16*Z)**2+((Y-1)/.8)**2)
    cone=np.maximum.reduce([radial-radius,-5.5-Z,Z-13.5])
    inner=np.maximum.reduce([radial-(radius-1),-4.5-Z,Z-12.4])
    ellipse=np.sqrt((X/5.1)**2+((Z+.3)/4.9)**2)
    tunnel=np.maximum((ellipse-1)*4.9,np.abs(Y+3.9)-.8)
    hole=np.maximum((ellipse-.81)*4.9,Y-.8)
    field=np.maximum(np.minimum(cone,tunnel),-np.minimum(inner,hole))
    v,f,_,_=marching_cubes(field.astype(np.float32),0,spacing=(step,step,step))
    v+=np.array([x[0],y[0],z[0]])
    tri=v[f];volume=np.einsum('ij,ij->i',tri[:,0],np.cross(tri[:,1],tri[:,2])).sum()/6
    if volume<0:f=f[:,::-1]
    m=Model();m.parts.append(Part(v,f,'shellbody',True));return m


def crab(big=False,hold=0,phase=0,grip=False,limb='pink'):
    m=new()
    if not grip:
        component(m,'continuous spiral shell',shell_surface())
        # The lip of each growth whorl wraps all the way round the shell.
        whorl=[]
        for t in np.linspace(.10,.97,150):
            a=2*math.pi*t*3.3;z=-5.5+19*t;r=(7.6*(1-t)**.72+.08)*1.1
            whorl.append((.16*z+r*math.cos(a),1+.8*r*math.sin(a),z))
        segment=[]
        for p in whorl:
            across_opening=p[1]<-2 and (p[0]/5.1)**2+((p[2]+.3)/4.9)**2<1
            if across_opening:
                if len(segment)>1:m.tube(segment,.26,'shellgroove')
                segment=[]
            else:segment.append(p)
        if len(segment)>1:m.tube(segment,.26,'shellgroove')
        # The mouth has a projecting lip, dark depth and two eyes at its back.
        m.ball((0,-1.4,-.3),(3.9,2.4,3.8),'crabbody')
        m.ring((0,-4.65,-.3),4.65,4.45,.3,'shellrim')
        for x in [-1.8,1.8]:m.ball((x,-4.5,1.6),(.9,.35,.9),'ivory')
        for s in [-1,1]:
            for n in range(3):
                lift=.5*math.sin(phase+n+s)
                m.tube([(s*3.5,-.5,-3),(s*(5.6+n*.5),-n,-4.4+lift),
                        (s*(6.3+n*.5),-n-1,-7.5+lift)],[.8,.65,.28],limb)
    for s in [-1,1]:
        raised=big and (hold==2 or hold==1 and s==-1)
        x,z=(s*9.4,7.1) if raised else (s*2.8,-4)
        if not grip:m.tube([(s*4.4,-1,-3),(s*6.7,-3,-2),(x,-5,z)],[.9,.7,.65],limb)
        m.ball((x,-5.6,z),(1.45,1,1.3),limb)
        for sign in [-1,1]:
            m.tube([(x+sign*.8,-5.7,z+.1),(x+sign*1,-5.8,z+1.5),
                    (x+sign*.35,-6,z+2.1)],[.58,.42,.04],limb)
    return m


def pouch(metal=False):
    m=new();mat='gold' if metal else 'iron'
    # Cloth folds extend around the bag, with a pinched neck and tied mouth.
    seg=56;profile=[(0,-8),(2.5,-7.8),(4.7,-6),(5.6,-3),(5.1,.3),(3.3,3.2),(2,4.8),(2.5,6.4),(0,7.1)]
    ps=lathe(profile,mat,seg);p=ps[0];v=p.v.copy()
    angle=np.arctan2(v[:,1],v[:,0]);weight=np.clip((v[:,2]+5)/10,0,1)
    r=1+.045*np.cos(angle*9)*weight;v[:,:2]*=r[:,None]
    p.v=v;component(m,'pouch with radial cloth folds',Model().add(type('P',(),{'parts':ps})()))
    pipe_ring(m,4.3,2.2,2.2,.45,'darkbrown')
    m.tube([(-1.8,-2,4.3),(-3,-2.5,2.8),(-1.6,-2.8,1.6)],.3,'darkbrown')
    m.tube([(1.3,-2.1,4.3),(3,-2.4,2.8),(2,-2.9,1.2)],.3,'darkbrown')
    return m


def pill_bag():
    m=new()
    for i,(x,z,tilt,y) in enumerate([(-3,4,40,.1),(1.3,4,-25,.4),(3,1.5,45,.2),(-2,0,-30,-.3),
                                     (1,-1,10,-.4),(-3,-4,55,.2),(2,-5,-35,.1),(0,-6,70,.8),
                                     (-1,3,70,1.2),(2,-2,50,1.2),(-2,-3,-20,1.1),(3.3,-5.3,70,1)]):
        pill=Model().ball((0,0,0),(1,1,2.1),'white',24)
        pill.tube([(-.85,-.9,0),(.85,-.9,0)],.07,'zip')
        component(m,'individual scored tablet',pill,T(x,y,z)@R('y',tilt))
    # Two film panels, separate perimeter welds and a double zipper rail.
    for side in [-1,1]:
        v=[];f=[];nx=18;nz=24
        for iz in range(nz):
            z=-7.3+14.7*iz/(nz-1)
            for ix in range(nx):
                x=-5.5+11*ix/(nx-1)
                wrinkle=.16*math.sin(x*2.2+z*.7)+.12*math.sin(z*2-x)
                y=side*(1.65+wrinkle*(abs(x)/5.5)**2+.35*math.cos(x*.28)*math.cos(z*.2))
                v.append((x,y,z))
        for iz in range(nz-1):
            for ix in range(nx-1):
                a=iz*nx+ix;f.extend([(a,a+1,a+nx),(a+1,a+nx+1,a+nx)])
        panel=Model();panel.parts.append(Part(v,f,'bagfilm',True));component(m,'creased translucent film panel',panel)
    for x in [-5.5,5.5]:m.tube([(x,-1.4,-7),(x*.94,-1.4,7.5)],.18,'zip')
    m.tube([(-5.5,-1.4,-7),(5.5,-1.4,-7)],.18,'zip')
    for z in [7,7.7]:m.box((0,0,z),(11.8,3.2,.45),'zip',.15)
    m.box((0,0,8.6),(12,3.1,1.2),'shell',.25)
    for x,z in [(-4.8,2),(4.8,-3)]:m.tube([(x,-1.5,z+2),(x*.8,-1.55,z),(x,-1.5,z-2)],.09,'white')
    return m.transform(R('y',-8))


def blade(outline,mat,depth=1.15):
    # A sharpened diamond cross section with a raised medial ridge.
    zlevels=sorted(set(z for x,z in outline));zmin,zmax=zlevels[0],zlevels[-1]
    zs=np.unique(np.r_[zlevels,np.linspace(zmin,zmax,24)])
    v=[];f=[]
    for z in zs:
        hits=[]
        for (x1,z1),(x2,z2) in zip(outline,outline[1:]+outline[:1]):
            if z1==z2:
                if abs(z-z1)<1e-6:hits.extend([x1,x2])
            elif min(z1,z2)<=z<=max(z1,z2):hits.append(x1+(x2-x1)*(z-z1)/(z2-z1))
        left,right=min(hits),max(hits);centre=(left+right)/2
        ridge=depth*.65*min(1,max(.02,(zmax-z)*1.5))
        v.extend([(left,0,z),(centre,-ridge,z),(right,0,z),(centre,ridge,z)])
    for i in range(len(zs)-1):
        for j in range(4):
            a=i*4+j;b=i*4+(j+1)%4;c=a+4;d=b+4;f.extend([(a,c,b),(b,c,d)])
    f.extend([(0,1,2),(0,2,3)]);q=len(v)-4;f.extend([(q,q+2,q+1),(q,q+3,q+2)])
    v=np.asarray(v);f=np.asarray(f);tri=v[f]
    if np.einsum('ij,ij->i',tri[:,0],np.cross(tri[:,1],tri[:,2])).sum()<0:f=f[:,::-1]
    m=Model();m.parts.append(Part(v,f,mat,False));return m


def sword(key):
    m=new()
    if key=='void_dagger':
        component(m,'wrapped grip',Model().tube([(0,0,2),(0,0,8)],1,'leather'))
        for z in np.arange(2.3,8,.9):pipe_ring(m,z,1.03,1.03,.16,'steel')
        # The shipped icon has its open ring pommel above its short ritual blade.
        a=np.linspace(.4,math.pi*2-.4,36)
        m.tube([(3*math.sin(t),0,11+3*math.cos(t)) for t in a],.7,'steel')
        m.ring((0,0,-3),3.4,3.5,.7,'purple')
        m.ring((0,-.5,-3),2.4,2.5,.32,'iron')
        component(m,'short pointed blade',blade([(-1.5,-5),(0,-11),(1.5,-5)],'iron',1.2))
        for s in [-1,1]:m.tube([(s*2.5,0,-5),(s*2.8,0,-8)],[.5,.03],'purple')
        return m
    cursed=key=='tyrfing'
    outline=[(-2,-1),(-2.8,3),(-1.7,5),(-2.6,9),(-2.2,12),(.5,14),(3.6,12),(2.5,8),(1.1,4),(1.7,-1)] if cursed else [(-2.3,-1),(-2.6,3),(-2.1,4),(-2.4,8),(-1.6,11),(.4,14),(2,14),(2.4,10),(1.6,7),(2.8,6),(2,2),(2.2,-1)]
    component(m,'bevelled blade with a separate cutting edge',blade(outline,'blade' if cursed else 'sealmetal'))
    m.tube([(-3.8,0,-1.5),(-2,0,-2.3),(0,0,-2.4),(3.4,0,-2)],[.6,.7,.8,.45],'gold' if cursed else 'iron')
    component(m,'leather grip',Model().tube([(0,0,-2.4),(0,0,-9.2)],[1,.85],'leather'))
    for z in np.arange(-8.7,-2.5,.9):pipe_ring(m,z,.9,.9,.15,'darkbrown')
    m.ball((0,0,-9.6),(1,1,.65),'darkbrown')
    if cursed:
        for side in [-1,1]:
            m.tube([(0,side*.85,-.3),(-.1,side*.85,3),(1,side*.85,7),(.4,side*.85,11)],.24,'gold')
            m.plate([(-1,10),(.7,12),(2,11),(.6,9.4)],.16,'amber',side*.85,.05)
    else:
        # Flat binding bands pass over the front, around the edges and across
        # the reverse of the blade; a knot and tails live on the reverse.
        for z in [0,2.3,4.6,6.9,9.2]:
            pts=[(-2.45,-1,z-1),(2.45,-1,z+.6),(2.45,1,z+.8),(-2.45,1,z-.8)]
            m.tube(pts,.44,'cloth',True)
        m.ball((.3,1.2,3.8),(.8,.6,.7),'cloth')
        m.tube([(.3,1.2,3.7),(1.3,1.5,1.5),(1.7,1.4,.7)],[.4,.3,.06],'cloth')
    return m.transform(R('y',37))


def kronos():
    m=new()
    # The sickle is a broad, bevelled crescent; the crossed grip is round stock.
    poly=[(-3,2),(-5,5),(-5,8),(-2,11),(2,12),(6,10),(3,9),(1,10),(-1,8),(-2,5),(0,3),(3,5),(4,3),(1,0)]
    component(m,'crescent blade',blade(poly,'gold',1.3))
    component(m,'crossed grip',Model().tube([(-1,1,1),(-6,1,-7)],1.25,'gold'))
    m.tube([(-8,1,-1),(-2,1,-5)],1.15,'gold')
    m.tube([(-8,1,-6),(-3,1,-8)],1,'gold')
    # Polished cutting bevel rather than a cream-coloured physical stripe.
    m.tube([(-3.8,-.55,7.8),(-1.6,-.55,10),(2,-.55,10.8)],[.18,.2,.1],'gold')
    return m


def ring_band(rx,ry,z0,z1,thick,mat):
    m=Model();profile=[(rx-thick,z0),(rx,z0),(rx,z1),(rx-thick,z1),(rx-thick,z0)]
    m.parts+=move(lathe(profile,mat,64),S(1,ry/rx,1));return m


def crown():
    m=new();component(m,'continuous hollow crown band',ring_band(9,7,-2,1.3,.65,'white'))
    component(m,'blue enamel band',ring_band(9.05,7.04,-.6,-.05,.15,'cyan'))
    for t in np.linspace(0,2*math.pi,10,endpoint=False):
        x,y=8.6*math.cos(t),6.6*math.sin(t)
        m.tube([(x,y,1),(x,y,3.8)],[.75,.04],'gold')
        m.ball((x,y,1.2),(.5,.5,.65),'ivory')
    m.camera_pitch=14;return m


def belt():
    m=new();component(m,'continuous leather belt',ring_band(9,6,-1.4,1.4,.65,'leather'))
    for x in [-5.2,5.2]:
        p=Model().box((x,-4.8,-1.6),(3.8,3.5,4.1),'darkbrown',.5)
        p.box((x,-6.65,.3),(4,.4,1.8),'brown',.3).ball((x,-6.95,.1),(.28,.15,.28),'steel')
        component(m,'stitched tool pouch and flap',p)
    m.box((0,-6.4,0),(3.1,.7,2.8),'steel',.2).box((0,-6.85,0),(1.7,.12,1.5),'leather',.1)
    m.tube([(0,-7,-1),(0,-7,1)],.2,'steel')
    for a in np.linspace(.25,2.9,9):
        x,y=8.9*math.cos(a),5.9*math.sin(a)
        m.ball((x,y,.1),(.15,.15,.2),'black')
    m.camera_pitch=24;return m


def soflam():
    m=new();component(m,'machined optical housing',Model().box((0,0,0),(13,8,6.2),'olive',.65))
    for y in [-2.35,2.35]:
        component(m,'separate objective barrel',Model().tube([(4,y,0),(8.2,y,0)],1.8,'iron'))
        m.ball((8.3,y,0),(.18,1.35,1.35),'lens')
        m.tube([(-5.6,y,-3.2),(4.8,y,-3.2)],.35,'black')
    component(m,'top panel',Model().box((-.5,0,3.25),(10.5,6,.65),'olive',.25))
    m.box((4.5,0,3.8),(1.8,2,1.2),'iron',.2).ball((4.5,-.2,4.45),(.55,.6,.2),'red')
    for x in [-4,3]:
        for y in [-2.5,2.5]:m.ball((x,y,3.65),(.2,.2,.12),'steel')
    m.tube([(-5,3,-1),(-6,5,-4),(3,5,-4),(4,3,-1)],.4,'leather')
    m.camera_pitch=22;return m.transform(R('y',-22)@R('z',-28))


def glasses():
    m=new()
    for s in [-1,1]:
        x=s*3.7
        pts=[(x-2.9,-1,-1.7),(x+2.9,-1,-1.7),(x+2.9,-1,1.7),(x-2.9,-1,1.7)]
        m.tube(pts,.38,'iron',True)
        m.box((x,-1,0),(5.3,.3,2.8),'cyan',.45)
        m.tube([(s*6.7,-1,1),(s*6.8,4,1),(s*6,7,.2),(s*5.7,7,-1)],.4,'iron')
    m.tube([(-.8,-1,.3),(0,-1,.8),(.8,-1,.3)],.35,'steel')
    m.camera_pitch=13;return m.transform(R('y',-24))


def paper(path,key):
    a=np.array(Image.open(path).convert('RGBA'));mask=a[...,3]>=128
    contours=find_contours(np.pad(mask.astype(float),1),.5)
    c=max(contours,key=len)-1
    c=approximate_polygon(c,tolerance=.9)
    outline=[(x+.5-a.shape[1]/2,a.shape[0]/2-y-.5) for y,x in c[:-1]]
    m=new();mat={'appraisal_certificate':'parchment','conch_certificate':'conchpaper'}.get(key,'paper')
    component(m,'thin paper with a real reverse and edge',Model().plate(outline,1.05,mat,bevel=.15))
    # Mild curl is geometric and continues onto the back; print stays separate.
    for p in m.parts:
        p.v[:,1]+=.28*np.sin(p.v[:,2]*.18)+.12*np.cos(p.v[:,0]*.3)
    m.aligned=True
    yy,xx=np.nonzero(mask);m.axis=((xx.min()+xx.max()+1-a.shape[1])/2,0,0)
    return m


def book():
    m=new();component(m,'page block',Model().box((0,0,0),(12.7,3.5,18.5),'paper',.15))
    for y in [-2,2]:m.box((0,y,0),(14,.65,20),'mane',.35)
    component(m,'rounded bound spine',Model().box((-6.5,0,0),(1.6,4.4,20),'iron',.65))
    for y in [-1.2,-.6,0,.6,1.2]:m.tube([(6.4,y,-8.7),(6.4,y,8.7)],.05,'muzzle')
    m.box((.4,-2.4,2),(9.2,.16,12.2),'paper',.1)
    for z in [-8,-5,-2,1,4,7]:m.ring((-6.7,-1.5,z),.6,.45,.17,'steel')
    return m


def coin():
    m=new();profile=[(0,-.85),(8.5,-.85),(9,-.5),(9,.5),(8.5,.85),(0,.85)]
    component(m,'bevelled coin blank',Model().add(type('P',(),{'parts':move(lathe(profile,'gold',80),R('x',90))})()))
    for y in [-.95,.95]:m.ring((0,y,0),8.3,8.3,.27,'gold')
    for t in np.linspace(0,2*math.pi,64,endpoint=False):
        x,z=8.9*math.cos(t),8.9*math.sin(t)
        m.tube([(x,-.4,z),(x,.4,z)],.075,'darkbrown')
    return m


def family():
    m=new();m.camera_pitch=22;m.aligned=True
    plate=Model();plate.parts+=lathe([(0,-8.3),(10,-8.3),(13.7,-7.9),(14.6,-7.1),(14.4,-6.7),(12.9,-7.3),(0,-7.5)],'white',64)
    plate.transform(T(0,0,-4.9))
    component(m,'shallow ceramic plate with underside and foot',plate)
    m.ring((0,0,-13.2),7,7,.35,'white','xy')
    # Centres and visible front sizes of the original five figures. Their
    # full depths and backs are separately modelled; the front is not inflated.
    for name,screen,depth,radii,mat in [
        ('ghost',(11,7.8),3.8,(4.6,3.7,5.8),'mealgrey'),
        ('blue',(6.5,18),-.8,(5.3,3.7,6.2),'mealblue'),
        ('green',(23.5,14),2.2,(4.8,3.9,6.8),'mealgreen'),
        ('red',(16,25),-5,(5.9,3.6,4.7),'mealred'),
        ('pink',(26,25),-4.4,(3.8,3,4.3),'skin')]:
        x=screen[0]-16;z=(16-screen[1]-depth*math.sin(math.radians(22)))/math.cos(math.radians(22))
        p=(x,depth,z);body=Model().ball(p,radii,mat,40)
        if name in ['ghost','blue','green']:
            # Rounded torsos, not support posts. Their lower bodies are
            # partly occluded by the foreground figures and plate rim.
            top=z+1;bottom=-12.3;centre=(top+bottom)/2
            body.ball((x*.9,depth,centre),(radii[0]*.82,radii[1]*.92,(top-bottom)/2),mat,40)
        if name=='ghost':body.ball((x-.8,depth,z+4.1),(3.4,2.6,2),mat)
        if name=='green':
            body.tube([(x-1,depth,z+5),(x-2,depth,z+7),(x-3,depth,z+7.5)],[1,.6,.05],mat)
        component(m,name+' familiar with complete back',body)
    return m


def constructed(key,path):
    if key in ['ox','dog','tiger','pig','dragon','azure_dragon']:return head(key,True)
    if key=='horse':return horse()
    if key=='goat':return sheep()
    if key=='rabbit':return rabbit()
    if key=='monkey':return monkey()
    if key=='hermit_crab':return crab()
    if key=='eternal_flame':
        m=new();body=old_recipe(key)
        for p in body.parts:
            if p.mat=='fire':p.mat='ivory'
        component(m,'ivory outer flame and warm core',body);return m
    if key in ['tyrfing','sealed_demon_sword','void_dagger']:return sword(key)
    if key=='kronos':return kronos()
    if key=='oral_steroids':return pill_bag()
    if key=='utility_belt':return belt()
    if key=='soflam':return soflam()
    if key=='ar_glasses':return glasses()
    if key=='angels_crown':return crown()
    if key=='kids_menu':return family()
    if key in ['a_minus','b_minus','c_minus','f_minus','appraisal_certificate','conch_certificate']:return paper(path,key)
    if key=='wrong_answer_note':return book()
    if key=='two_faced_penny':return coin()
    if key in ['live_eye','polycoria']:
        m=new();component(m,'eyeball sclera, cornea and iris',old_recipe(key))
        m.tube([(0,7,0),(1,10,-.5),(2,11.5,-2)],[1.2,.9,.5],'red' if key=='polycoria' else 'blue')
        if key=='polycoria':
            for a in np.linspace(0,2*math.pi,7,endpoint=False):
                m.tube([(6*math.cos(a),5,6*math.sin(a)),(4*math.cos(a+.2),7,4*math.sin(a+.2)),(0,8,0)],[.15,.12,.08],'red')
        return m
    if key=='hemispatial_neglect':
        m=new();h=old_recipe(key);h.parts=[h.parts[0]];component(m,'closed half cranium and planar cut',h);return m
    if key in ['time_money','money_tear']:
        m=pouch(key=='time_money')
        if key=='money_tear':
            pts=[(8.3*math.cos(t),6*math.sin(t),-10+20*t/(6*math.pi)) for t in np.linspace(0,6*math.pi,150)]
            m.tube(pts,.34,'cyan')
        return m
    m=new();component(m,'authored all-around construction',old_recipe(key))
    return m


def align(m,path):
    if getattr(m,'aligned',False):return
    a=np.array(Image.open(path).convert('RGBA'));mask=a[...,3]>=128
    y,x=np.nonzero(mask);vertices=np.vstack([p.v for p in m.parts]);lo=vertices.min(0);hi=vertices.max(0)
    pitch=math.radians(getattr(m,'camera_pitch',0));up=np.array([0,math.sin(pitch),math.cos(pitch)])
    vertical=vertices@up
    sx=(x.max()-x.min())/(hi[0]-lo[0]);sz=(y.max()-y.min())/np.ptp(vertical)
    # Preserve real depth; independent X/Z fitting only matches the drawing's aspect.
    centre=(lo+hi)/2;dest=((x.min()+x.max()+1-a.shape[1])/2,0,(a.shape[0]-y.min()-y.max()-1)/2)
    m.parts=move(m.parts,S(sx,sz,sz)@T(*(-centre)))
    vertices=np.vstack([p.v for p in m.parts]);vertical=vertices@up
    dz=(dest[2]-(vertical.min()+vertical.max())/2)/max(math.cos(pitch),.1)
    m.parts=move(m.parts,T(dest[0],0,dz))
    m.axis=(dest[0],0,0)


INK_KEYS={'ox','dog','tiger','pig','monkey','rabbit',
          'dragon','azure_dragon','kids_menu','a_minus','b_minus','c_minus','f_minus',
          'appraisal_certificate','conch_certificate','wrong_answer_note','two_faced_penny','jangseung','hemispatial_neglect'}


def surface_ink(m,path,key):
    """Conform the original's markings to the *visible constructed surface*.

    A depth pass finds the actual first-hit surface. Ink triangles sit on that
    surface and turn with it; nothing is projected onto a hidden rear surface.
    No source shading supplies shape, and the perimeter is never transferred.
    """
    a=np.array(Image.open(path).convert('RGBA'));rgb=a[...,:3].astype(float);mask=a[...,3]>=128
    lum=rgb@np.array([.299,.587,.114]);inside=ndimage.distance_transform_edt(mask)>2.0
    ink=np.zeros(mask.shape,np.uint8)
    # Only actual features, not interior remnants of thick pixel perimeter ink.
    rois={
      'dog':[(8,13,13,19),(18,13,24,19),(12,20,20,27)],
      'ox':[(9,13,14,19),(18,13,23,19)],
      'tiger':[(8,9,24,19),(11,18,21,27)],
      'pig':[(6,14,14,21),(17,11,25,17),(11,22,24,26)],
      'dragon':[(8,15,14,20),(18,15,24,20),(13,23,20,28)],
      'azure_dragon':[(10,14,23,20),(12,23,21,27)],
      'monkey':[(11,12,22,17),(12,18,21,22)],
      'rabbit':[(8,16,24,22),(11,22,22,25)],
      'kids_menu':[(8,4,15,11),(2,12,11,21),(18,9,28,19),(11,21,20,27),(22,21,30,28)],
    }
    region=np.ones(mask.shape,bool)
    if key in rois:
        region[:]=False
        for x0,y0,x1,y1 in rois[key]:region[y0:y1,x0:x1]=True
    black=(lum<28)&inside&region;ink[black]=1
    white=(rgb.min(axis=2)>205)&ndimage.binary_dilation(black,iterations=2)&inside&region
    regions,n=ndimage.label(white)
    for i in range(1,n+1):
        region=regions==i
        if region.sum()<28:ink[region]=2
    if key in ['dragon','azure_dragon']:
        ink[(rgb[...,0]>190)&(rgb[...,1]>140)&(rgb[...,2]<130)&region]=5
    if key in ['a_minus','b_minus','c_minus','f_minus','wrong_answer_note']:
        ink[:]=0;ink[(rgb[...,0]>145)&(rgb[...,1]<100)&(rgb[...,2]<100)&mask]=3
    if key=='appraisal_certificate':
        ink[:]=0;ink[(lum<130)&inside]=4
    if key=='conch_certificate':
        # The certificate's own colours (docs/previews/conch-certificate/icon.py):
        # violet writing and conch shadow, lavender conch, pink mouth.
        ink[:]=0
        def near(*cols):
            return np.any([np.abs(rgb-c).max(axis=2)<4 for c in cols],axis=0)&mask
        ink[near((128,108,182),(106,92,166))]=6;ink[near((184,170,222),(160,148,214),(208,200,242))]=7
        ink[near((238,168,198))]=8;ink[near((246,244,255))]=2
        top=np.zeros(mask.shape,bool);top[:14]=True  # the conch's own outline, not the sheet's ragged edge
        ink[near((26,20,34))&inside&top]=1
    if key=='two_faced_penny':
        ink[:]=0;ink[(lum<110)&(ndimage.distance_transform_edt(mask)>3)]=4
    up=4;size=32*up;cam=Camera(yaw=0,pitch=getattr(m,'camera_pitch',0),dist=100,ortho=32)
    _,depth=render(m.parts,m.materials,cam,size=size,ss=1,return_depth=True)
    allowed=np.ones(depth.shape,bool)
    if key=='kids_menu':
        targets=[p for p in m.parts if p.mat.startswith('meal') or p.mat=='skin']
        _,face_depth=render(targets,m.materials,cam,size=size,ss=1,return_depth=True)
        allowed=np.isfinite(face_depth)&np.isfinite(depth)&(np.abs(np.where(np.isfinite(face_depth),face_depth,0)-np.where(np.isfinite(depth),depth,0))<.02)
    iy,ix=np.indices((size,size));px=(ix+.5)/up-16;pz=16-(iy+.5)/up
    safe_depth=np.where(np.isfinite(depth),depth,0)
    v=cam.eye+(safe_depth[...,None]-.035)*cam.fwd+px[...,None]*cam.right+pz[...,None]*cam.up
    ids=np.arange(size*size).reshape(size,size);faces=[];materials=[]
    label=np.repeat(np.repeat(ink,up,0),up,1)
    for y in range(size-1):
        for x in range(size-1):
            mat=label[y,x]
            if not mat or not allowed[y:y+2,x:x+2].all():continue
            z=depth[y:y+2,x:x+2]
            if not np.isfinite(z).all() or np.ptp(z)>1.3:continue
            p,q,r,s=ids[y,x],ids[y,x+1],ids[y+1,x],ids[y+1,x+1]
            faces.extend([(p,r,q),(q,r,s)]);materials.extend([mat,mat])
    if not faces:return
    faces=np.asarray(faces);materials=np.asarray(materials);verts=v.reshape(-1,3)
    for i,name in [(1,'ink_black'),(2,'ink_white'),(3,'ink_red'),(4,'ink_brown'),(5,'ink_gold'),(6,'ink_violet'),(7,'ink_lavender'),(8,'ink_pink')]:
        f=faces[materials==i]
        if not len(f):continue
        used=np.unique(f);remap=np.full(len(verts),-1,np.int32);remap[used]=np.arange(len(used))
        p=Part(verts[used],remap[f],name,True);m.parts.append(p)
        if key=='two_faced_penny':m.parts.append(p.moved(R('z',180)))


def build(path,key):
    m=constructed(key,path);m.materials=MATS;m.axis=getattr(m,'axis',(0.,0.,0.))
    if key=='conch_pearl':
        a=np.array(Image.open(path).convert('RGBA'));lab,n=ndimage.label(a[...,3]>=128)
        counts=np.bincount(lab.ravel());counts[0]=0;y,x=np.nonzero(lab==counts.argmax())
        cx=(x.min()+x.max()+1-a.shape[1])/2;cz=(a.shape[0]-y.min()-y.max()-1)/2
        r=(max(np.ptp(x),np.ptp(y))+1)/2-.25
        m.parts=move(m.parts,T(cx,0,cz)@S(r/9));m.axis=(cx,0,0)
    else:align(m,path)
    if key in INK_KEYS:surface_ink(m,path,key)
    return m
