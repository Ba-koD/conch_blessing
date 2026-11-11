"""Authored, all-around volumes for the April Fools collection.

Units are design units, Z up, front -Y. No sprite is used as a height map,
texture, or silhouette extrusion. Identity comes from the shipped reference:
anatomy, construction, colour families and recognizable secondary details.
This is a procedural mesh source, editable without a proprietary DCC.
"""
import math
import numpy as np
from mesh3d import Part, T, R, S, move, sphere, sweep, lathe, extrude, rounded_rect, material

MATS = {
    'ratfur': material((110,116,114),spec=.12,rough=.85),
    'ivory': material((230,224,191), spec=.22, rough=.65),
    'white': material((226,229,239), spec=.4, rough=.38),
    'pearl': material((202,204,220), spec=.6, shine=44, rough=.24,
                      sheen=((.65,.3,.65),(.2,.7,.7))),
    'black': material((24,23,31), spec=.24, rough=.55),
    'pupil': material((11,9,18), spec=.75, rough=.18),
    'brown': material((146,91,46), spec=.17, rough=.8),
    'darkbrown': material((73,46,32), spec=.16, rough=.8),
    'wood': material((130,94,54), spec=.15, rough=.85),
    'skin': material((217,158,145), spec=.22, rough=.6),
    'pink': material((192,111,133), spec=.26, rough=.55),
    'red': material((174,34,38), spec=.38, rough=.38),
    'green': material((47,112,58), spec=.25, rough=.6),
    'olive': material((91,99,64), spec=.2, rough=.62),
    'blue': material((34,100,164), spec=.4, rough=.38),
    'cyan': material((66,187,205), spec=.5, rough=.28),
    'shell': material((151,174,221), spec=.52, rough=.28),
    'shellrim': material((196,213,239), spec=.5, rough=.3),
    'purple': material((92,48,127), spec=.4, rough=.35),
    'gold': material((211,153,29), metal=True, spec=.62, rough=.28),
    'steel': material((135,152,163), metal=True, spec=.62, rough=.28),
    'iron': material((68,72,77), metal=True, spec=.44, rough=.45),
    'glass': material((141,196,209), alpha=.23, spec=.75, rough=.12),
    'plastic': material((156,199,210), alpha=.18, spec=.65, rough=.25),
    'amber': material((234,158,27), spec=.55, rough=.28),
    'fire': material((243,115,16), glow=.3, spec=.1),
    'light': material((255,221,100), glow=.45, spec=.2),
}


class Model:
    def __init__(self):
        self.parts = []

    def ball(self, p, radii, mat, seg=24):
        self.parts.append(sphere(1, mat, seg=seg, rings=16, center=p, squash=radii))
        return self

    def tube(self, pts, radius, mat, closed=False):
        self.parts += sweep(pts, radius, mat, seg=12, closed=closed)
        return self

    def plate(self, outline, depth, mat, y=0, bevel=.15):
        self.parts += move(extrude(outline, depth, mat, bevel=bevel), T(y=y))
        return self

    def box(self, p, dims, mat, radius=.4):
        x,y,z=p; w,d,h=dims
        poly=[(a+x,b+z) for a,b in rounded_rect(w,h,min(radius,w/3,h/3))]
        return self.plate(poly,d,mat,y, min(.18,d/4))

    def ring(self, p, rx, rz, radius, mat, plane='xz'):
        x,y,z=p
        a=np.linspace(0,2*math.pi,48,endpoint=False)
        pts=[(x+rx*math.cos(t),y,z+rz*math.sin(t)) if plane=='xz'
             else (x+rx*math.cos(t),y+rz*math.sin(t),z) for t in a]
        return self.tube(pts,radius,mat,True)

    def transform(self, matrix):
        self.parts=move(self.parts,matrix)
        return self

    def add(self, other, matrix=None):
        self.parts += move(other.parts,matrix) if matrix is not None else other.parts
        return self


def eyes(m, sep=3.3, y=-5.1, z=1.4, white=True, stern=False):
    for sign in [-1,1]:
        x=sign*sep
        if white: m.ball((x,y,z),(1.65,.65,1.65),'ivory')
        m.ball((x,y-.58,z),(1,.5,1.2),'pupil')
        m.ball((x-.25,y-.98,z+.4),(.25,.15,.3),'white',16)
        if stern: m.tube([(x-sign*1.4,y-.6,z+1),(x+sign*1.5,y-.4,z+2)],.6,'darkbrown')


def horn(m, x, z, side=1, mat='ivory', ram=False):
    if ram:
        pts=[(x+side*2.5*math.cos(t),-.4-1.6*math.sin(t),z+2.5*math.sin(t))
             for t in np.linspace(0,5.1,26)]
        m.tube(pts,np.linspace(1.4,.15,len(pts)),mat)
    else:
        m.tube([(x,0,z),(x+side*2,0,z+2),(x+side*2.3,-.2,z+4),(x+side*1.5,-.4,z+5)],
               [1.8,1.4,.8,.08],mat)


def head(key):
    m=Model()
    skins={'ox':'brown','tiger':'amber','dog':'ivory','pig':'pink','monkey':'brown',
           'rabbit':'ivory','horse':'ivory','dragon':'cyan','azure_dragon':'blue'}
    skin=skins.get(key,'brown')
    m.ball((0,0,0),(7,4.7,6.5),skin)
    muzzle='skin' if key=='pig' else 'ivory' if key in ('tiger','monkey','rabbit') else 'brown' if key=='ox' else skin
    m.ball((0,-4,-2.5),(4.9,2.7,3),muzzle)
    eyes(m, white=key not in ('rabbit',), stern=key in ('dog','tiger'))
    if key in ('ox','pig','horse'):
        for x in [-2,2]: m.ball((x,-6.5,-2.5),(.55,.3,.75),'darkbrown')
    else:
        m.ball((0,-6.6,-2),(1.2,.65,.8),'pupil')
        m.tube([(-1.5,-6.5,-4),(0,-6.7,-4.3),(1.5,-6.5,-4)],.18,'darkbrown')
    if key=='rabbit':
        for x in [-4,4]:
            e=Model().ball((0,0,0),(1.8,1.35,6),'ivory').ball((0,-1.1,.3),(.9,.4,4),'pink')
            m.add(e,T(x,0,8)@R('y',-x*4))
        m.box((0,-6,-4.3),(1.1,.6,1.8),'white')
    elif key in ('dog','tiger','pig','horse'):
        for side in [-1,1]:
            if key=='tiger':
                m.ball((side*5.8,0,5),(2.2,1.6,2.4),'amber')
                m.ball((side*5.8,-1.4,5),(1.15,.45,1.4),'darkbrown')
            else:
                ear=Model().plate([(-2,-1),(0,5),(2,-1)],2,skin).plate([(-1,-.2),(0,3.6),(1,-.2)],.25,'pink',-1.2)
                m.add(ear,T(side*5,0,5)@R('y',side*17))
    elif key=='monkey':
        for x in [-7,7]:
            m.ball((x,0,1),(2.5,1.5,3),'brown').ball((x,-1.25,1),(1.5,.5,2),'skin')
        m.ball((0,-4.6,2),(4.5,.6,3),'ivory')
        eyes(m,sep=2.8,y=-5.3,z=1.7)
    if key=='ox':
        for s in [-1,1]:
            horn(m,s*5.5,4,s)
            m.ball((s*7,0,.5),(2.8,1,1.5),'brown')
    if key=='tiger':
        for s in [-1,1]:
            for z in [-1,2,4]:
                m.tube([(s*6.5,-2.5,z+1),(s*4.7,-4.5,z),(s*4,-4.7,z-.5)],[.85,.65,.05],'black')
        for x in [-2,0,2]: m.tube([(x,-3.2,5.8),(x*.6,-4.4,3.7)],[.7,.1],'black')
    if key=='horse':
        m.ball((0,-4,-3),(3.5,4,4),'ivory')
        for z in np.linspace(-3,7,7): m.ball((0,2,z),(1.4,3,2),'iron')
    if key in ('dragon','azure_dragon'):
        for s in [-1,1]:
            horn(m,s*4,5,s,'gold')
            m.tube([(s*4,-4,-3),(s*8,-4,-2),(s*10,-3,-4)],[.6,.45,.1],'gold')
            for z in [-2,1,4]: horn(m,s*6,z,s,skin)
    return m


def sheep():
    m=Model().ball((1,0,0),(7,4.8,5.6),'ivory')
    # Wool is separate rounded clumps, not noise derived from sprite lighting.
    for a in np.linspace(0,2*math.pi,12,endpoint=False):
        m.ball((1+5*math.cos(a),-.8,3.7*math.sin(a)),(2.6,4.2,2.5),'ivory')
    for x in [-3,4]:
        for y in [-2.5,2.5]: m.tube([(x,y,-3.8),(x,y,-7)],.85,'black')
    m.ball((-5,-2,1),(3,2.6,3.6),'iron')
    m.ball((-7,-3,0),(2,1.7,2),'iron')
    m.ball((-5.6,-4.4,2),(.65,.4,.9),'ivory').ball((-5.7,-4.8,2),(.3,.2,.5),'pupil')
    horn(m,-3,3,-1,'wood',ram=True)
    return m


def rat(phase=0):
    m=Model().ball((1,0,0),(7,3.4,3.4),'ratfur').ball((-5,-.2,.5),(3.8,3.1,2.8),'ratfur')
    for y in [-2,2]:
        m.ball((-3,y,3.4),(1.8,1,2.5),'ratfur').ball((-3,y-.7,3.5),(1.1,.4,1.6),'pink')
        m.ball((-6,-.2+y*1.6,1),(.7,.35,.8),'ivory').ball((-6.2,-.2+y*1.78,1),(.4,.2,.5),'pupil')
    m.ball((-8,-.2,.1),(.7,.7,.6),'pink')
    m.tube([(6,1,-1),(10,2,-1),(11,2,2),(10,1,3)],[.6,.5,.35,.05],'pink')
    for x in [-4,4]:
        for y in [-2,2]:
            m.tube([(x,y,-2),(x+math.sin(phase+x+y),y,-4)],.6,'pink')
    return m


def crab(big=False, hold=0, phase=0, grip=False, limb='shellrim'):
    m=Model()
    if not grip:
        m.ball((0,1,0),(6.6,5.3,6),'shell')
        # A spiral swept shell, tapering towards its apex, with a real cavity lip.
        for j in range(3):
            m.ball((1+j*.55,1.5,4+j*2.4),(4.7-j,4-j*.6,3.6-j*.5),'shell')
        a=np.linspace(0,math.pi*6,100)
        pts=[((5.7-.24*t)*math.cos(t)+.1*t,1+(4.6-.18*t)*math.sin(t),1+.52*t) for t in a]
        m.tube(pts,np.linspace(.65,.3,len(pts)),'shellrim')
        m.ball((0,-4.5,.9),(4.7,1.5,4.5),'black')
        m.ring((0,-5,1.3),5.4,5,.6,'shellrim')
        # Eyes stay above the native central trinket slot; hands/feet keep
        # their existing anchors, including the larger BFFS side slots.
        for x in [-2,2]: m.ball((x,-5.9,2.4),(.9,.5,1),'white')
        for s in [-1,1]:
            for n in range(3):
                z=-5.2+.35*math.sin(phase+n+s)
                m.tube([(s*3,0,-3),(s*(5+n*.7),-n,z+.8),(s*(6+n*.6),-n-.5,z-1)],.65,limb)
    for s in [-1,1]:
        raised=big and (hold==2 or hold==1 and s==-1)
        x,z=(s*9.4,7.1) if raised else (s*2.8,-4)
        if not grip: m.tube([(s*5,-1,-3),(s*7,-3,-2),(x,-5,z)],.9,limb)
        m.ball((x,-5.5,z),(1.5,1,1.35),limb)
        m.tube([(x-.9,-5.7,z+.3),(x-1,-5.8,z+1.8),(x-.4,-6,z+2.3)],[.6,.5,.1],limb)
        m.tube([(x+.8,-5.7,z+.1),(x+1,-5.8,z+1.8),(x+.4,-6,z+2.3)],[.65,.5,.1],limb)
    return m


def hourglass(colour='cyan', orbit=True):
    m=Model()
    m.parts += lathe([(0,-8),(4.3,-8),(4.5,-7),(0,-7)],'gold')
    m.parts += lathe([(0,7),(4.5,7),(4.3,8),(0,8)],'gold')
    m.parts += lathe([(0,-6.8),(3.5,-6.8),(3.4,-5),(1,0),(3.4,5),(3.5,6.8),(0,6.8)],'glass')
    m.parts += lathe([(0,-6.5),(3,-6.5),(0,-3),(0,0),(2.8,4),(3,5),(0,5)],colour)
    m.tube([(0,-.2,-3),(0,-.2,3)],.16,colour)
    for x,y in [(-4,0),(4,0),(0,4)]: m.tube([(x,y,-7),(x,y,7)],.45,'wood')
    if orbit:
        for z in [-4,4]: m.ring((0,0,z),9.2,5,.45,colour,'xy')
    return m


def sword(key):
    m=Model(); cursed=key=='tyrfing'; void=key=='void_dagger'
    blade='red' if cursed else 'iron'; trim='gold' if cursed else 'darkbrown'
    poly=[(-2,-3),(-2.5,5),(-1.5,8),(0,12),(1.5,8),(2.5,5),(2,-3)]
    if void: poly=[(-1.4,-2),(-2,5),(0,10),(2,5),(1.4,-2)]
    m.plate(poly,1.2,blade,bevel=.25)
    # Raised medial ridge gives the blade a diamond cross section.
    m.plate([(-.35,-3),(0,11),(.35,-3)],1.7,'gold' if cursed else 'steel',bevel=.12)
    m.tube([(-4,-.1,-3),(-3,-.1,-4),(0,-.1,-4),(3,-.1,-4),(4,-.1,-3)],.8,trim)
    m.tube([(0,0,-4),(0,0,-9)],1,'darkbrown')
    for z in [-5,-6,-7,-8]: m.ring((0,0,z),1.05,1.05,.15,trim,'xy')
    m.ball((0,0,-9.7),(1.2,1,1.3),'purple' if void else trim)
    if key=='sealed_demon_sword':
        for z in [-1,2,5]:
            m.tube([(-2.4,-.9,z-1),(2.4,-.9,z+1),(2.4,.9,z+1),(-2.4,.9,z-1)],.55,'wood',True)
        m.box((.3,-1.7,1.5),(2.7,.6,4.4),'ivory')
        m.tube([(-.4,-2.05,3),(.7,-2.05,2),(0,-2.05,1),(.6,-2.05,0)],.22,'red')
    if void:
        m.ring((0,-1,-3),2.1,2.1,.4,'purple')
        m.ring((0,0,-10),1.8,1.8,.45,'iron')
    return m.transform(R('y',35 if not void else 0))


def scissors(red_thread=False):
    m=Model(); mat='steel' if red_thread else 'gold'
    for s in [-1,1]:
        m.ring((s*3,0,-6),2.2,3,.65,mat)
        blade=Model().plate([(-.65,-5),(-.8,7),(0,11),(.8,7),(.65,-5)],.75,mat,bevel=.15)
        m.add(blade,R('y',s*27))
    m.ball((0,-.6,0),(.85,.4,.85),'iron')
    if red_thread:
        m.tube([(-10,-1,1),(-5,-1,2),(-1,-1,3)],.55,'red')
        m.tube([(1,-1,3),(4,-1,2),(5,-1,-1),(9,-1,-2)],.55,'red')
        m.transform(R('y',30))
    return m


GLYPHS={
 'A':[[(0,0),(1.5,5),(3,0)],[(.6,2),(2.4,2)]],
 'B':[[(0,0),(0,5),(2,5),(3,4),(2,2.5),(0,2.5)],[(2,2.5),(3,1),(2,0),(0,0)]],
 'C':[[(3,4.6),(2,5),(0,4),(0,1),(2,0),(3,.4)]],
 'F':[[(0,0),(0,5),(3,5)],[(0,2.5),(2.5,2.5)]],
 'X':[[(0,0),(3,5)],[(0,5),(3,0)]],
}


def glyph(m,letter,p=(0,-1,0),scale=1,mat='red'):
    x,y,z=p
    for stroke in GLYPHS[letter]: m.tube([(x+a*scale,y,z+b*scale) for a,b in stroke],.32*scale,mat)


def badge(key):
    m=Model().box((0,0,0),(12,.65,17),'white',.25)
    m.ring((0,-.55,0),4.8,6,.42,'red')
    glyph(m,key[0].upper(),(-3.5,-.8,-4),1.4)
    m.tube([(1.8,-.8,0),(3.5,-.8,0)],.55,'red')
    return m.transform(R('y',-10))


def flame(blue=False):
    m=Model(); outer='blue' if blue else 'fire'; inner='cyan' if blue else 'light'
    m.tube([(0,0,-7),(-1,0,-4),(0,0,0),(2,0,4),(1,0,8),(3,0,12)],
           [.1,5,5.3,3,1.8,.02],outer)
    m.tube([(0,-2,-7),(1,-3,-4),(0,-3,0),(1,-2,4)],[.1,3.3,2,.02],inner)
    m.tube([(-3,0,-3),(-5,0,1),(-4,0,5)],[2,1.5,.02],outer)
    return m


def shell_icon():
    m=Model()
    ts=np.linspace(0,math.pi*5,90)
    m.tube([(math.cos(t)*(6-.32*t),math.sin(t)*(6-.32*t),-.8*t+6) for t in ts],
           np.linspace(2.8,.2,len(ts)),'shell')
    return m


def recipe(key):
    m=Model()
    if key=='conch_pearl': return m.ball((0,0,0),(9,9,9),'pearl',64)
    if key in ['ox','tiger','dog','pig','monkey','rabbit','horse','dragon','azure_dragon']: return head(key)
    if key=='goat': return sheep()
    if key=='rat': return rat()
    if key=='hermit_crab': return crab()
    if key in ['tyrfing','sealed_demon_sword','void_dagger']: return sword(key)
    if key in ['severed_oath','atropos']: return scissors(key=='severed_oath')
    if key in ['a_minus','b_minus','c_minus','f_minus']: return badge(key)
    if key in ['eternal_flame','fire_breath','ice_breath']: return flame(key=='ice_breath')
    if key in ['time_luck','time_power','time_tear']: return hourglass({'time_luck':'green','time_power':'red','time_tear':'cyan'}[key])
    if key=='time_money':
        m.parts+=lathe([(0,-8),(4,-8),(5,-5),(4,0),(3,2),(3,5),(0,5)],'gold')
        m.ball((0,0,7),(3,3,2),'gold')
        m.tube([(-3,-4,0),(3,-4,0)],.5,'wood'); return m
    if key=='power_training':
        m.tube([(-8,0,0),(8,0,0)],1,'steel')
        for x in [-7,7]:
            for dx,r in [(-1,3.5),(0,4),(1,3.5)]:
                m.add(Model().ball((0,0,0),(1,r,r),'iron'),T(x+dx,0,0))
        return m
    if key=='injectable_steroids':
        m.parts+=lathe([(0,-5),(2.2,-5),(2.2,4),(0,4)],'glass')
        m.parts+=lathe([(0,-4.5),(1.8,-4.5),(1.8,1),(0,1)],'amber')
        m.box((0,0,4),(7,2,1),'steel').tube([(0,0,4),(0,0,8)],.7,'steel')
        m.box((0,0,8),(5,2,1),'iron').tube([(0,0,-5),(0,0,-11)],[.45,.04],'steel')
        for z in [-3,-1,1,3]: m.tube([(-1,-2.2,z),(.3,-2.2,z)],.13,'iron')
        return m.transform(R('y',35))
    if key=='oral_steroids':
        for x,z,t in [(-3,-4,30),(1,-5,-25),(3,-2,40),(-2,0,-30),(1,2,25),(-3,4,65),(3,4,-20)]:
            pill=Model().ball((0,0,0),(1,1,2.4),'white').ball((0,0,1),(1.03,1.03,1.4),'cyan')
            m.add(pill,T(x,0,z)@R('y',t))
        m.box((0,.2,0),(11,3.5,15),'plastic',.8)
        m.box((0,0,8),(12,1.8,1.4),'shell').tube([(-5,-1,7.6),(5,-1,7.6)],.15,'white')
        for s in [-1,1]: m.tube([(s*5,-1.8,6),(s*4,-2,1),(s*5,-1.8,-6)],.12,'white')
        return m.transform(R('y',-8))
    if key in ['live_eye','polycoria']:
        skin='blue' if key=='live_eye' else 'white'
        m.ball((0,0,0),(8,8,8),skin)
        m.ball((0,-7.3,0),(4.6,1.7,4.6),'cyan' if key=='live_eye' else 'purple')
        m.ball((0,-8.8,0),(2.4,.8,2.5),'pupil')
        if key=='polycoria':
            for x,z in [(-2,1.5),(1.5,2),(1,-2)]: m.ball((x,-8.8,z),(1.4,.7,1.5),'pupil')
            for s in [-1,1]:
                for z in [-4,1,4]: m.tube([(s*6,-4,z),(s*5.8,-5,z+1),(s*4.5,-6,z+1.5)],.17,'red')
        else: m.tube([(0,0,-8),(0,0,-10)],.9,'blue')
        return m
    if key=='hemispatial_neglect':
        # True half head: cut the mesh at its median plane and close the cut.
        from scipy.spatial import ConvexHull
        p=sphere(8,'skin',seg=32,rings=24); v=p.v[p.v[:,0]>=-1e-8]
        hull=ConvexHull(v); f=hull.simplices.copy()
        for i,eq in enumerate(hull.equations):
            a,b,c=v[f[i]]
            if np.dot(np.cross(b-a,c-a),eq[:3])<0:f[i]=f[i][::-1]
        m.parts.append(Part(v,f,'skin',True)); m.ball((3.4,-6.8,1),(1.7,.8,2.2),'pupil')
        m.tube([(3.5,-7,-1),(3.5,-6,-4)],.65,'cyan'); return m
    if key=='inf_d6':
        m.box((0,0,0),(12,12,12),'red',1.3)
        for x,z in [(-3,3),(0,0),(3,-3)]:m.ball((x,-6.05,z),(.7,.25,.7),'black')
        for x in [-3,3]:
            for y in [-3,0,3]:m.ball((x,y,6.05),(.7,.7,.25),'black')
            for z in [-3,3]:m.ball((x,6.05,z),(.7,.25,.7),'black')
        for y,z in [(-3,-3),(3,3)]:m.ball((6.05,y,z),(.25,.7,.7),'black')
        for y,z in [(-3,-3),(-3,3),(0,0),(3,-3),(3,3)]:m.ball((-6.05,y,z),(.25,.7,.7),'black')
        m.ball((0,0,-6.05),(.7,.7,.25),'black')
        return m.transform(R('z',-20)@R('x',18))
    if key=='utility_belt':
        m.ring((0,0,0),9,6,1.8,'darkbrown','xy')
        for x in [-5,5]: m.box((x,-4,-1),(4,3,4),'brown',.6).box((x,-5.7,.5),(4.2,.7,1.5),'wood')
        m.box((0,-6.7,0),(3,1,3),'steel').box((0,-7.3,0),(1.6,.25,1.6),'darkbrown'); return m
    if key=='soflam':
        m.box((0,0,0),(13,8,8),'olive',1).box((0,0,5),(10,6,2),'olive')
        for x in [-3.5,3.5]:
            m.ball((x,-4.5,0),(2.4,1.3,2.4),'iron').ball((x,-5.4,0),(1.7,.4,1.7),'cyan')
        m.box((4,0,7),(2.2,2,2),'iron').tube([(-6,1,-3),(-9,1,-5),(7,1,-5),(6,1,-3)],.55,'black')
        return m.transform(R('y',-12))
    if key=='ar_glasses':
        for s in [-1,1]:
            m.ring((s*4,-1,0),3.4,2.7,.55,'iron')
            m.ball((s*4,-1,0),(3, .3,2.3),'cyan')
            m.tube([(s*7,-1,1),(s*7,4,1),(s*6,6,0)],.5,'iron')
        m.tube([(-1,-1,0),(0,-1,.6),(1,-1,0)],.4,'steel'); return m.transform(R('y',-12))
    if key=='angels_crown':
        m.ring((0,0,-2),8,6,1.2,'gold','xy')
        for t in np.linspace(0,2*math.pi,9,endpoint=False):
            x,y=8*math.cos(t),6*math.sin(t)
            m.tube([(x,y,-2),(x,y,3)],[.8,.06],'gold')
            m.ball((x,y,-1.5),(.6,.6,.9),'white')
        return m
    if key=='real_eyes':
        m.tube([(-9,0,-7),(0,0,10),(9,0,-7)],.9,'gold',True)
        m.ball((0,0,0),(3.6,2.2,4.3),'ivory').ball((0,-2,0),(1.8,.7,2.2),'cyan').ball((0,-2.6,0),(.55,.3,1.5),'pupil')
        return m
    if key in ['ceil','floor','round']:
        for s in [-1,1]:
            pts=[(s*9,0,-9),(s*9,0,9)]
            m.tube(pts,.9,'ivory')
            if key!='floor':m.tube([(s*9,0,9),(s*5,0,9)],.9,'ivory')
            if key!='ceil':m.tube([(s*9,0,-9),(s*5,0,-9)],.9,'ivory')
        glyph(m,'X',(-3,-.2,-5),2,{'ceil':'green','floor':'red','round':'gold'}[key]); return m
    if key in ['appraisal_certificate','wrong_answer_note']:
        book=key=='wrong_answer_note'; mat='blue' if book else 'gold'
        m.box((0,0,0),(13,2 if book else .5,18),mat,.4)
        if book:
            m.box((0,-1.1,1),(9,.4,14),'ivory'); glyph(m,'X',(-2.5,-1.5,2),1.6)
            for z in [-7,-4,-1,2,5,8]:m.ring((-6.5,-.4,z),.9,.5,.2,'steel')
        else:
            for z,w in [(5,8),(2,7),(-1,9),(-4,6)]:m.tube([(-4,-.4,z),(-4+w,-.4,z)],.2,'darkbrown')
            m.ball((3,-.8,-6),(1.5,.5,1.5),'red')
        return m.transform(R('y',-8))
    if key=='two_faced_penny':
        m.add(Model().ring((0,0,0),9,9,.55,'gold'))
        m.parts+=move(lathe([(0,-.7),(8.7,-.7),(8.7,.7),(0,.7)],'gold'),R('x',90))
        # The two faces are relief medallions on opposite sides, not a mirrored floating image.
        for side in [-1,1]:
            m.ball((0,side*.9,0),(3.5,.7,5),'brown')
            for x in [-1.4,1.4]:m.ball((x,side*1.55,1),(.5,.3,.7),'gold')
            m.tube([(-2,side*1.6,-1),(0,side*1.6,-2*side),(2,side*1.6,-1)],.3,'gold')
        return m
    if key=='kronos':
        # Saturn's open sickle and crossed stem, round gold stock with a bevelled blade.
        m.tube([(-2,0,-9),(-2,0,6),(-1,0,10),(3,0,12),(6,0,10)],[1,1,1.2,1.2,.15],'gold')
        m.tube([(-6,0,-5),(3,0,-9)],.85,'gold')
        m.tube([(-6,0,-9),(3,0,-5)],.85,'gold')
        m.tube([(-2,0,2),(2,0,5),(6,0,4),(6,0,0),(2,0,-2)],[1.2,1.6,1.5,1.2,.1],'gold'); return m
    if key=='snake':
        m.tube([(5,1,-6),(-5,1,-6),(-6,0,-3),(1,0,-2),(3,0,1),(0,0,5)],
               [1.8,2.3,2.1,2,1.8,2.4],'green')
        m.ball((0,-.5,5),(3.7,2.8,2.6),'green'); eyes(m,1.6,-2.8,5.4,False)
        m.tube([(0,-3,4),(0,-5,3.7)],.18,'red'); return m
    if key=='chicken':
        m.ball((0,0,-1),(5.5,4,6),'ivory').ball((-3,-1,5),(3,2.8,3.5),'ivory')
        m.ball((-4,-3.65,5.4),(.6,.4,.75),'pupil').tube([(-5,-2.7,3.8),(-8,-3,3.5)],[1,.02],'gold')
        for x in [-5,-3,-1]:m.ball((x,0,8),(1.2,1.1,2),'red')
        for x in [-2,2]:m.tube([(x,0,-5),(x,-1,-9),(x+1,-2,-9)],.5,'gold')
        m.tube([(3,2,0),(5,3,4),(5,3,7)],[2,1.5,.1],'darkbrown'); return m
    if key=='money_tear':
        m=hourglass('cyan',True)
        m.parts=[p for p in m.parts if p.mat=='cyan'];m.ball((0,0,0),(4,3,6),'iron')
        m.tube([(-2,-3.1,4),(2,-3.1,4),(-2,-3.1,-4),(2,-3.1,-4)],.5,'gold'); return m
    if key=='jangseung':
        for x in [-5,5]:
            m.box((x,0,0),(7,5,19),'wood',.7)
            for dx in [-1.6,1.6]:m.box((x+dx,-2.7,4),(2,.4,2.7),'ivory').ball((x+dx,-3,4),(.55,.25,.9),'pupil')
            m.box((x,-2.7,-1),(4.6,.5,2.6),'black')
            for dx in [-1.3,0,1.3]:m.box((x+dx,-3,-.5),(1,.3,1.2),'ivory',.1)
            m.box((x,0,10),(9,7,1.7),'iron')
        return m
    if key=='kids_menu':
        m.parts+=lathe([(0,-6),(8,-6),(10,-5.6),(11,-4.8),(10.8,-4.3),(8,-4.8),(0,-4.8)],'white')
        # Seven distinct familiar heads on a shallow plate, staggered rather than rows.
        for x,y,z,skin in [(-4,2,0,'white'),(1,3,1,'skin'),(5,1,-.1,'green'),
                            (-6,-2,-1,'purple'),(-1,-1,-.5,'red'),(4,-3,-1.4,'ivory'),(-1,-4,-2,'blue')]:
            baby=Model().ball((0,0,0),(2.7,2.4,3.1),skin)
            for xx in [-1,1]:baby.ball((xx,-2.2,.3),(.6,.45,.9),'pupil')
            baby.ball((0,-2.4,-1.3),(.5,.3,.4),'pupil')
            if skin in ['red','purple']: 
                for s in [-1,1]:baby.tube([(s*1.8,0,2),(s*2.5,0,4)],[.8,.03],'ivory')
            m.add(baby,T(x,y,z))
        return m
    if key=='magic_conch': return shell_icon()
    raise KeyError('An explicit modelling recipe is required: '+key)


def fit(model, extent=25):
    """One fixed all-angle framing; never refit individual turntable frames."""
    v=np.vstack([p.v for p in model.parts]); lo,hi=v.min(0),v.max(0)
    centre=(lo+hi)/2
    radial=np.linalg.norm(v[:,:2]-centre[:2],axis=1).max()*2
    scale=extent/max(radial,hi[2]-lo[2])
    return model.transform(S(scale)@T(*(-centre)))
