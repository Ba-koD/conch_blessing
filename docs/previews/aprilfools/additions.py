"""Constructed November additions. Coordinates follow the authored front view.

Hair, cloth, hat, fan and broken shell walls have independent depth, edges and
reverse surfaces. Painted shading is never used to determine their geometry.
"""
import math
import numpy as np
from scipy.interpolate import CubicSpline
from recipes import Model, MATS
from mesh3d import Part, T, R, S, lathe, material, move

MATS.update({
    'fairskin': material((250,222,206),spec=.12,rough=.78),
    'fairhair': material((40,34,50),spec=.22,rough=.6),
    'fairpink': material((240,140,168),spec=.12,rough=.8),
    'fairwhite': material((250,250,247),spec=.16,rough=.7),
    'fairteal': material((72,176,156),spec=.12,rough=.75),
    'silk': material((210,232,255),alpha=.62,spec=.32,rough=.42),
    'silkedge': material((245,249,255),alpha=.76,spec=.3,rough=.4),
    'eyepaint': material((74,46,52),spec=.04,rough=.9),
    'lip': material((214,52,70),spec=.12,rough=.8),
    'gat': material((32,30,40),spec=.28,rough=.62),
    'gatband': material((78,80,100),spec=.2,rough=.65),
    'jeonskin': material((240,216,202),spec=.12,rough=.8),
    'jeonshade': material((38,28,40),spec=.06,rough=.88),
    'jeonshadeedge': material((112,88,103),spec=.07,rough=.85),
    'robe': material((222,226,236),spec=.16,rough=.75),
    'robefold': material((168,176,204),spec=.12,rough=.8),
    'indigo': material((40,44,92),spec=.12,rough=.8),
    'fanpaper': material((250,242,222),spec=.1,rough=.9),
    'bamboo': material((118,82,50),spec=.18,rough=.7),
    'debrisouter': material((168,174,220),spec=.36,rough=.38),
    'debrisridge': material((118,116,168),spec=.3,rough=.46),
    'debrisedge': material((240,232,244),spec=.34,rough=.4),
    'debrisinner': material((226,150,190),spec=.45,rough=.28),
})


def model():
    m=Model();m.materials=MATS;m.axis=(0.,0.,0.);m.components=[]
    return m


def part(m,name,p):
    start=len(m.parts);m.add(p)
    m.components.append({'name':name,'start':start,'end':len(m.parts)})


def ribbon(points,width=1.2,phase=0):
    """An airy, twisted strip with a continuous reverse, not a solid rope."""
    p=np.array(points,float);t=np.linspace(0,1,len(p));u=np.linspace(0,1,64)
    c=CubicSpline(t,p)(u);tangent=CubicSpline(t,p)(u,1)
    v=[]
    for i,(q,d) in enumerate(zip(c,tangent)):
        side=np.cross(d,[0,1,0]);side/=max(np.linalg.norm(side),1e-9)
        twist=.65*math.sin(u[i]*2*math.pi+phase)
        side=side*math.cos(twist)+np.array([0,1,0])*math.sin(twist)
        w=width*min(1,(1-u[i])*10+.05)
        v.extend([q-side*w/2,q+side*w/2])
    f=[]
    for i in range(len(c)-1):
        k=2*i;f.extend([(k,k+1,k+2),(k+1,k+3,k+2)])
    m=Model();m.parts=[Part(v,f,'silk',True)]
    edge=np.array(v)[::2];m.tube(edge,np.linspace(.09,.025,len(edge)),'silkedge')
    return m


def maiden_head(familiar=False):
    m=model()
    # The face tapers at the chin; a separate rounded cranium closes the back.
    skin=Model().ball((0,-1,-1.6),(7.6,4.8,8),'fairskin',32)
    part(m,'oval face and closed cranium',skin)
    # Hair cap follows the crown, ends above the forehead and runs farther
    # down at the temples/back. Its edge is buried in the side locks.
    verts=[];faces=[];n=64;rows=20
    for j in range(rows):
        for i in range(n):
            a=2*math.pi*i/n;angle=abs((a+math.pi)%(2*math.pi)-math.pi)
            end=5.5-20*min(1,max(0,(angle-.48)/.68))
            z=10.99+(end-10.99)*j/(rows-1)
            r=math.sqrt(max(.001,1-((z-2)/9)**2)) if z>2 else 1
            rx=10*r+(max(0,-z-8)*.08);ry=(5.65 if z>0 else 4.8)*r
            verts.append((rx*math.sin(a),-ry*math.cos(a),z))
    for j in range(rows-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;c=a+n;d=b+n
            faces.extend([(a,c,b),(b,c,d)])
    hair=Model();outer=np.array(verts);inner=outer.copy();inner[:,:2]*=.92
    hair.parts=[Part(outer,faces,'fairhair',True),Part(inner,np.array(faces)[:,::-1],'fairhair',True)]
    edges=[]
    for i in range(n):
        a=(rows-1)*n+i;b=(rows-1)*n+(i+1)%n
        edges.extend([(a,b,a+rows*n),(b,b+rows*n,a+rows*n)])
    hair.parts.append(Part(np.vstack([outer,inner]),edges,'fairhair',True))
    for s in [-1,1]:
        # 쌍계: small hollow loops leaning outward, with a complete back.
        loop=Model().ring((s*5.8,.6,13),2,2.1,.78,'fairhair')
        loop.transform(T(s*5.8,0,11)@R('y',s*-18)@T(-s*5.8,0,-11))
        hair.add(loop)
        hair.tube([(s*5.4,.6,8.7),(s*5.8,.6,10.4)],.7,'fairhair')
    part(m,'crown cap, long locks and paired loop buns',hair)
    band=Model()
    def bandpoint(a):
        z=8.5+1.7*math.cos(a);r=math.sqrt(1-((z-2)/9)**2)
        return (10.2*r*math.sin(a),-5.85*r*math.cos(a),z)
    pts=[bandpoint(a) for a in np.linspace(-math.pi,math.pi,65)]
    band.tube(pts,.36,'gold')
    x,y,z=bandpoint(0);band.ball((x,y-.2,z),(.6,.24,.45),'lip')
    for s in [-1,1]:
        for j,mat in enumerate(['gold','blue','green']):
            x,y,z=bandpoint(s*(.62+j*.16));band.ball((x,y-.15,z),(.45,.22,.38),mat)
    part(m,'gold headband, red jewel and saekdong',band)
    return m


def seonnyeo(familiar=False,phase=0):
    m=model();head=maiden_head(familiar)
    if familiar:
        # Large head / small floating body as in the actual familiar sprite.
        head.parts=[p for p in head.parts if not (p.mat=='fairhair' and p.v[:,2].max() < -7)]
        # Shorten the long locks/back into the familiar's round head.
        for p in head.parts:
            p.v[:,2]=np.maximum(p.v[:,2],-7.7)
        head.transform(T(0,0,5)@S(.78,.8,.57))
        part(m,'familiar head',head)
        body=Model()
        body.parts+=lathe([(0,-13.5),(.8,-12.8),(3,-10),(5,-6),(5.6,-4),(4.5,-3),(0,-3)],'fairwhite')
        body.transform(S(1,.7,1))
        body.ball((0,0,-2),(6.5,3.4,3),'fairpink')
        for s in [-1,1]:
            body.ball((s*5,-1.5,-3),(2.4,2,2.4),'fairpink')
            for j,mat in enumerate(['lip','gold','blue']):
                body.box((s*(3.7-j*.75),-3.7,-3.5),(.78,.5,2),mat,.15)
        body.ball((0,-3.9,-3.5),(1.7,.6,.7),'fairskin')
        body.tube([(-2,-3.1,.1),(0,-3.9,-1.8),(2,-3.1,.1)],.42,'fairwhite')
        body.tube([(0,-4,-1.8),(0,-4.1,-3)],.35,'lip')
        part(m,'jeogori, folded sleeves and tapered white skirt',body)
        for s in [-1,1]:
            swing=.55*math.sin(phase)
            p=[(s*6,1,-2),(s*11,1,3),(s*(13+swing),.3,6),(s*11.7,.2,8),
               (s*9,1,7.3),(s*9.6,1,2),(s*9.3,.2,-4),(s*(11+.7*math.sin(phase-.5)),0,-12)]
            part(m,'moving silk ribbon',ribbon(p,1.25,phase*.18))
        # Rendered markings curve with the face; position follows the source.
        face=Model()
        for s in [-1,1]:
            face.tube([(s*2.1,-4.55,5.5),(s*2.8,-4.65,4.7),(s*3.6,-4.35,5.4)],.27,'eyepaint')
        face.ball((0,-4.7,7),(.6,.13,.35),'lip').ball((0,-4.6,2.5),(.65,.14,.27),'lip')
        part(m,'closed eyes, gonji and small mouth',face)
    else:
        part(m,'maiden head',head)
        body=Model().tube([(0,0,-8),(0,0,-13)],2.2,'fairskin')
        body.ball((0,1,-16),(12.2,4.7,3.2),'fairpink')
        body.tube([(-3,-3,-13),(0,-4.1,-16.8),(3,-3,-13)],.55,'fairwhite')
        body.tube([(-2.5,-3.5,-13.5),(0,-4.6,-16.8),(2.5,-3.5,-13.5)],.3,'fairteal')
        # A bust ends flat, like the icon, but remains solid from behind.
        for p in body.parts:p.v[:,2]=np.maximum(p.v[:,2],-15.5)
        part(m,'neck and pink hanbok bust',body)
        for s in [-1,1]:
            part(m,'silk behind shoulders',ribbon([(s*10,2,-13),(s*13,1,-8),(s*13,1,0),(s*13,1,6),(s*11,1,8),(s*10,2,6)],1.35))
    m.aligned=True
    return m


def fan(state='a'):
    m=Model();pivot=np.array([5.6,-6.1,31.6])
    if state=='closed':
        m.tube([(5.2,-5.3,31.4),(3.6,-5.3,40.8)],[.65,.8],'fanpaper')
        for dy in [-.7,.7]:m.tube([(5.2,-5.3+dy,31.4),(3.6,-5.3+dy,40.8)],.18,'bamboo')
        return m
    a0,a1={'a':(66,192),'b':(76,200),'half':(112,196)}[state]
    verts=[];faces=[];n=22
    for radius in [3.1,8.4]:
        for i,a in enumerate(np.linspace(math.radians(a0),math.radians(a1),n+1)):
            verts.append(pivot+[radius*math.cos(a),(-1 if i%2 else 1)*.32,radius*math.sin(a)])
    for i in range(n):faces.extend([(i,i+1,i+n+1),(i+1,i+n+2,i+n+1)])
    m.parts.append(Part(verts,faces,'fanpaper',False))
    for a in np.linspace(math.radians(a0),math.radians(a1),12):
        end=pivot+[8.4*math.cos(a),.4,8.4*math.sin(a)]
        m.tube([pivot,end],.13,'bamboo')
    m.ball(pivot,(.6,.6,.6),'gold')
    return m


def talisman():
    m=Model().box((0,0,0),(4,.18,9),'gold',.1)
    m.tube([(0,-.15,-3),(0,-.15,3)],.18,'lip')
    for z in [-1.4,1.3]:m.tube([(-1,-.15,z),(1,-.15,z)],.18,'lip')
    return m


def jeon_woochi(bust=False,flare=0,sway=0,fan_state='a',arm='behind'):
    m=model()
    # All poses share the source's feet (20,56) and hand attachment locations.
    head=Model().ball((0,0,39),(4.8,3.7,5.5),'jeonskin')
    skin=head.parts.pop();tri=skin.v[skin.f].max(1)
    labels=np.where(tri[:,2]>39.8,'jeonshade',np.where(tri[:,2]>38.4,'jeonshadeedge','jeonskin'))
    for mat in ['jeonshade','jeonshadeedge','jeonskin']:
        head.parts.append(Part(skin.v,skin.f[labels==mat],mat,True,skin.vertex_normals()))
    head.ball((0,1.2,40.5),(4.8,3.5,5.5),'gat')
    head.tube([(0,0,33),(0,0,36)],2,'jeonskin')
    if fan_state=='closed':head.tube([(-1.5,-3.4,36.7),(0,-3.8,36.4),(1.7,-3.2,37)],.15,'lip')
    part(m,'head, hair and deep hat shadow over hidden eyes',head)
    hat=Model();hat.parts+=lathe([(0,46),(12.7,46),(13.6,46.5),(13.3,47),(0,47)],'gat')
    hat.parts+=lathe([(0,47),(4.4,47),(4.1,48),(3.8,54.5),(3.3,55),(0,55)],'gat')
    hat.ring((0,0,47.5),4.25,4.25,.27,'gatband','xy')
    # A slight tilt exposes the shallow brim surface in the fixed front view.
    hat.transform(T(0,0,46)@R('x',8)@S(1,.7,1)@T(0,0,-46))
    part(m,'thin circular gat brim and tapered cylindrical crown',hat)
    robe=Model();bottom=27 if bust else 2.6
    profile=[(0,bottom),(10.5+flare,bottom),(10,8),(8.8,26),(8,31),(4.5,33),(0,33)] if not bust else [(0,27),(9.8,27),(8,31),(4.5,33),(0,33)]
    robe.parts+=lathe(profile,'robe');robe.transform(S(1,.48,1))
    robe.tube([(-3.7,-3,33),(0,-4.6,27),(3.7,-3,33)],.7,'indigo')
    robe.tube([(-3,-3.5,33),(0,-5,28),(3,-3.5,33)],.4,'fairwhite')
    if not bust:
        robe.ring((0,0,25),8.6,4.3,.5,'indigo','xy')
        for s in [-1,1]:
            robe.tube([(s*2,-4.4,24),(s*3,-4.6,15),(s*5,-4.7,4)],.25,'robefold')
            robe.ball((s*3.6,-1,1),(2.8,4,1),'gat')
        robe.tube([(3,-4.6,25),(5,-5,20),(5,-4.9,15)],.45,'lip')
    part(m,'closed robe, overlapping collar, hem folds and shoes',robe)
    arms=Model()
    if not bust:
        arms.tube([(6.8,0,30.4),(10,-1,25),(6.4,-3.8,30.6)],[3.2,3.1,2.4],'robe')
        arms.ball((11,-.4,19),(3.2,3,6),'robe')
        points={'behind':[(-6.8,1,30),(-11,1,22),(-5,4,20)],
                'reach':[(-6.8,0,30),(-9.4,-1,24),(-5,-4.5,20.6)],
                'raise':[(-6.8,0,30),(-10,-1,24.6),(-7.6,-4.5,31)],
                'seal':[(-6.8,0,30),(-9.8,-1,25.4),(-6.2,-4.5,33)],
                'throw':[(-6.8,0,30),(-10.6,-1,26),(-8.4,-4.5,19)]}[arm]
        arms.tube(points,[3.3,3.1,2.3],'robe')
        if arm!='behind':arms.ball(points[-1],(1.1,1,1.3),'jeonskin')
        paper_at={'reach':(-3,-5,23),'raise':(-7,-5,35),'seal':(-6,-5,41)}.get(arm)
        if paper_at:arms.add(talisman().transform(T(*paper_at)))
    arms.ball((5,-5.3,31),(1.1,1,1.1),'jeonskin')
    part(m,'posed broad sleeves, hands and held talisman',arms)
    part(m,'pleated folding fan with bamboo reverse ribs',fan(fan_state))
    string=Model()
    pts=[]
    for t in np.linspace(0,1,35):
        pts.append(((-6.4)*(1-t)**2+2*(1-t)*t*sway+6.4*t*t,-3.8,44-60*t*(1-t)))
    string.tube(pts,.13,'bamboo')
    for p in pts[1::3]:string.ball(p,(.32,.32,.45),'gold')
    part(m,'hanging beaded gat strings',string)
    if bust:
        m.parts=move(m.parts,T(0,0,-41));m.aligned=True
    return m


def shell_patch(outline,y,bulge=1.8,inside='debrisedge'):
    """A curved shell wall with inner nacre and a pale broken cross-section."""
    poly=np.array(outline,float)
    if np.cross(poly[1]-poly[0],poly[2]-poly[1])<0:poly=poly[::-1]
    center=poly.mean(0);n=len(poly);verts=[]
    for t in [0,.25,.5,.75,1]:
        for p in poly:
            x,z=center+(p-center)*t
            verts.append((x,y-bulge*(1-t*t),z))
    faces=[]
    for j in range(4):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;c=a+n;d=b+n
            faces.extend([(a,b,c),(b,d,c)])
    front=np.array(verts);back=front+[0,.85,0]
    m=Model();m.parts=[Part(front,faces,inside,True),Part(back,np.array(faces)[:,::-1],'debrisouter',True)]
    edge=[]
    for i in range(n):
        a=4*n+i;b=4*n+(i+1)%n;edge.extend([(a,a+5*n,b),(b,a+5*n,b+5*n)])
    m.parts.append(Part(np.vstack([front,back]),edge,'debrisedge',False))
    return m


def conch_debris():
    m=model()
    wall=shell_patch([(-11,9.5),(-7,5),(-4,1),(-3,-5),(-8,-4),(-11,-2)],1.3,3,'debrisouter')
    # Growth ridges are constructed on the curved wall, with a pale cut edge.
    surface=wall.parts[0];triangles=surface.v[surface.f]
    for z in [-2,1,4]:
        path=CubicSpline([0,1,2,3],[(-10.7,z+1),(-9,z),(-7,z-1),(-5.7,z-1.8)])(np.linspace(0,3,28))
        ridge=[]
        for x,zp in path:
            for tri in triangles:
                a,b,c=tri[:,[0,2]];ab=b-a;ac=c-a
                mat=np.column_stack([ab,ac])
                if abs(np.linalg.det(mat))<1e-8:continue
                u,v=np.linalg.solve(mat,[x-a[0],zp-a[1]])
                if u>=-1e-6 and v>=-1e-6 and u+v<=1+1e-6:
                    y=(1-u-v)*tri[0,1]+u*tri[1,1]+v*tri[2,1]
                    ridge.append((x,y-.12,zp));break
        if len(ridge)>1:wall.tube(ridge,.14,'debrisridge')
    part(m,'tall broken outer wall with visible shell thickness',wall)
    # A detached spire: three tapering spiral whorls, with a broken base.
    tip=Model();profile=[(0,3),(3.7,3),(4,3.6),(3.9,4.4),(2.4,4.8),(2.9,5.3),(2.8,6.3),(1.6,6.7),(2,7.2),(1.7,8.4),(.6,9.2),(0,9.6)]
    tip.parts+=lathe(profile,'debrisouter');tip.transform(T(6.8,3.5,0)@S(1,.8,1))
    for z,r in [(4.5,3.8),(6.4,2.8),(8.35,1.6)]:tip.ring((6.8,3.5,z),r,r*.8,.22,'debrisridge','xy')
    part(m,'detached three-whorl spire and fracture base',tip)
    # The pink opening is physically split; its dark gap is open space.
    part(m,'left pink aperture fragment',shell_patch([(-4,2),(-1,3),(.6,0),(-.4,-1.5),(1,-4.9),(-1,-5),(-3.8,-2.5)],-2.4,1.4,'debrisinner'))
    part(m,'right pink aperture fragment',shell_patch([(1.5,2),(3,1),(5,-3),(3.5,-4.7),(2,-5),(.6,-1.8),(1.5,-.8)],-1.7,1,'debrisinner'))
    part(m,'curled rim on the right',shell_patch([(5,-3.5),(7,-1),(10,3),(11.5,2.5),(11,0),(8,-3.5)],.4,1.7,'debrisouter'))
    part(m,'rear shell shard',shell_patch([(-2,2),(-1,7),(1,7.8),(1.3,6),(0,4),(3,1)],2.8,.7,'debrisouter'))
    part(m,'foreground wedge',shell_patch([(-10,-7),(-8,-5),(-7,-6.7),(-7.5,-8)],-1,.2))
    for x,z,s in [(-5.7,-8.2,.6),(.5,-8.1,.65),(4.5,-8,.4),(9.4,-7.5,.45)]:
        chip=Model().plate([(x-s,z-s),(x+s,z-s*.4),(x+.2,z+s)],s,'debrisedge',-.3,.08)
        part(m,'loose shell chip',chip)
    return m
