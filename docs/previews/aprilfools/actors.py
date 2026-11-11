"""Reference-registered 3D pose exports; movement follows the source frames.

Render into the shipped ANM2 rectangles. Pivots, timing, layers and collision
remain owned by the original animation/gameplay. Closed volumes, not billboards.
"""
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image,ImageDraw
from recipes import Model, MATS, head, crab, rat, recipe, horn
from mesh3d import T,R,S,Camera,render,move,export_glb
from build import ROOT,OUT,PREVIEW,clean
from objects import head,crab,pouch

GFX=ROOT/'resources/gfx'


def ox(phase=0,black=False,sleep=False):
    m=Model();skin='iron' if black else 'brown'
    # Shoulder girdle, barrel and rump give the ox real depth and weight.
    m.ball((0,0,6),(8.8,4.6,5.2),skin).ball((3,0,8),(5.4,4.8,4.8),skin)
    m.ball((-6,0,6),(4.3,4.2,4.4),skin)
    for x in [-6,5]:
        for y in [-3,3]:
            stride=math.sin(phase+(0 if x*y>0 else math.pi))
            knee=(x+stride,y,2.8 if not sleep else 2)
            foot=(x+2*stride,y,-1 if not sleep else 1)
            m.tube([(x,y,6),knee,foot],[1.6,1.05,.75],skin)
            m.ball(foot,(1.15,1,.65),'darkbrown')
    h=head('ox').transform(S(.58))
    if black:
        for p in h.parts:
            if p.mat in {'brown','hide','muzzle'}:p.mat='iron'
    h.transform(T(10,0,6 if not sleep else 3)@R('z',90))
    m.add(h)
    m.tube([(-9,1,7),(-12,1,4),(-12.5,0,1)],[.5,.4,.2],skin)
    m.ball((-12.5,0,1),(.6,.7,1.3),'darkbrown')
    # Fitted yoke and straps remain on the sleeping animal.
    m.tube([(4,-5,6),(4,-4,10),(4,0,12),(4,4,10),(4,5,6)],.65,'wood')
    for y in [-4.2,4.2]:m.tube([(-7,y,7),(4,y,9)],.4,'darkbrown')
    if not sleep:
        for y in [-3,3]:m.tube([(2,y,6),(-15,y,3)],.35,'wood')
        m.tube([(-15,-3,3),(-18,0,1),(-22,0,8)],.65,'wood')
        m.plate([(-21,-1),(-15,-1),(-16,1),(-19,2)],4,'steel',bevel=.3)
    else:
        m.transform(S(1,1,.75))
        m.tube([(10,-2,12),(13,-2,12),(10,-2,9),(13,-2,9)],.22,'ivory')
    return m


def rice(stage):
    m=Model();height=2+min(stage,5)*1.5
    for s in [-1,0,1]:
        m.tube([(s,0,0),(s*1.5,0,height*.5),(s*2,0,height)],.25,'green')
        if stage>=3:
            for j in range(3):
                m.ball((s*2+(j%2-.5),-.2,height-j*.7),(.55,.4,.85),'gold')
    return m


def dragon_piece(name,phase):
    m=Model()
    if name=='Head':
        m.ball((-4,0,1),(7,4,4),'blue').ball((5,0,-.5),(7,3,2.1),'cyan')
        m.ball((5,0,-3),(6,2.7,.8),'blue')
        m.tube([(-1,-3,-1.8),(6,-2.8,-1.8),(11,-1.6,-1.8)],.45,'red')
        m.ball((0,-3.8,1.8),(1.8,.5,.9),'gold').ball((.5,-4.2,1.8),(.4,.3,.8),'pupil')
        m.tube([(-4,0,4),(-5,0,7),(-4,0,10)],[.8,.55,.03],'gold')
        m.tube([(-5,0,7),(-8,0,8)],[.4,.03],'gold')
        for z in [-2,0,2,4]:m.tube([(-7,0,z),(-12,0,z+1.8)],[1.2,.02],'cyan')
        for s in [-1,1]:m.tube([(6,s*2.5,-2),(1,s*5,-4),(-5,s*6,-5)],[.4,.3,.02],'ivory')
    elif name=='Body':
        m.ball((0,0,0),(5,4,4),'blue')
        for x in [-3,0,3]:m.ball((x,-3.7,0),(.65,.3,.6),'gold')
        m.tube([(-4,-2,2),(0,-3,3),(4,-2,2)],.35,'cyan')
    elif name=='Legs':
        for s in [-1,1]:
            m.tube([(s*3,s*2,1),(s*5,s*3,-1),(s*5+math.sin(phase),s*4,-5)],[1.2,.8,.65],'blue')
            for n in range(3):m.tube([(s*5,s*4,-5),(s*(3+n),s*4-.8,-7)],[.45,.04],'gold')
    elif name=='Tail':
        m.tube([(-9,0,0),(-3,0,0),(2,0,math.sin(phase)),(8,0,2)],[3,2,1,.04],'cyan')
        for z in [-5,0,5]:m.tube([(-3,0,0),(-9,0,z),(-12,0,z*1.2)],[1,.55,.03],'shellrim')
    return m


def frame_records(anm2):
    path=GFX/anm2; tree=ET.parse(path)
    sheets={s.get('Id'):(path.parent/s.get('Path')).resolve() for s in tree.iter('Spritesheet')}
    layers={l.get('Id'):sheets[l.get('SpritesheetId')] for l in tree.iter('Layer')}
    records={}
    for a in tree.iter('Animation'):
        for la in a.iter('LayerAnimation'):
            src=layers[la.get('LayerId')]
            if not src.is_file():continue
            for i,f in enumerate(la.iter('Frame')):
                rect=tuple(int(f.get(k,0)) for k in ['XCrop','YCrop','Width','Height'])
                if rect[2]<=1 or rect[3]<=1:continue
                if a.get('Name')=='Trinket':continue # this is replaced with the held icon at runtime
                records.setdefault(src,{}) .setdefault(rect,(a.get('Name'),i,f))
    return records


def native(model,w,h,x,y,scale=1,pitch=0,yaw=0):
    model.parts=clean(model.parts)
    pts=move(model.parts,T(x,0,-y)@S(scale)@R('x',pitch)@R('z',yaw))
    side=max(w,h); size=side*3
    img=render(pts,MATS,Camera(yaw=0,pitch=0,dist=400,ortho=side,target=(w/2,0,-h/2)),size=size,ss=1)
    dx=(side-w)*3//2;dy=(side-h)*3//2
    return img.crop((dx,dy,dx+w*3,dy+h*3)).resize((w,h),Image.Resampling.LANCZOS)


def fitted(model,src,w,h,yaw=0,pitch=0):
    box=src.getbbox()
    if not box:return Image.new('RGBA',(w,h))
    pts=np.vstack([p.v for p in model.parts]); pts=pts@R('z',yaw)[:3,:3].T
    lo,hi=pts.min(0),pts.max(0)
    scale=min((box[2]-box[0])/(hi[0]-lo[0]),(box[3]-box[1])/(hi[2]-lo[2]))
    x=(box[0]+box[2])/2-(lo[0]+hi[0])/2*scale
    y=(box[1]+box[3])/2+(lo[2]+hi[2])/2*scale
    return native(model,w,h,x,y,scale,pitch,yaw)


def actor_frame(src,name,i,rect,sheet):
    frame,m=primitive_actor_frame(src,name,i,rect,sheet)
    if m:m.materials=MATS
    return frame,m


def primitive_actor_frame(src,name,i,rect,sheet):
    x,y,w,h=rect;phase=2*math.pi*i/8
    stem=sheet.stem
    if 'hermit_crab' in stem:
        big='Bffs' in name;held=2 if 'Two' in name else 1 if 'One' in name else 0
        grip='grip' in stem
        m=crab(big,held,phase,grip,limb='pink')
        scale=1.8 if big else 1.35
        foot=45 if big else 42
        # Shared body / foreground rig; no re-fit that would move gripping hands.
        return native(m,w,h,24,foot-7*scale,scale),m
    if 'ox_directions' in stem or 'ox_sleep_equipped' in stem:
        sleeping='Sleep' in name
        m=ox(2*math.pi*i/6,'Black' in name,sleeping)
        yaw=-90 if 'Down' in name else 90 if 'Up' in name else 0
        # The same skeleton and a fixed camera/scale across the whole walk cycle.
        img=native(m,w,h,48,44,1.35,pitch=22,yaw=yaw)
        return img,m
    if stem=='familiar_dragon':
        if name in ['Shadow','Spark']:return src,None
        m=dragon_piece(name,phase);return fitted(m,src,w,h),m
    if stem=='familiar_time_money':
        m=pouch(True);return fitted(m,src,w,h),m
    if stem=='conch_rat_run':
        m=rat(phase);return fitted(m,src,w,h),m
    if stem=='conch_ox_rice':
        m=rice(x//18);return fitted(m,src,w,h),m
    if stem=='conch_jangseung_ward':
        m=Model().ring((0,0,0),12,5,.65,'wood','xy').transform(R('x',55))
        for q in [-8,0,8]:m.tube([(q,-4,0),(q,-4,-3)],.4,'ivory' if q==0 else 'red')
        return fitted(m,src,w,h),m
    if stem=='conch_rabbit_tracks':
        m=Model()
        for s in [-1,1]:m.ball((s*3,0,0),(1.8,.5,3),'brown')
        return fitted(m,src,w,h),m
    if stem.startswith('pickup_'):
        # Preserve the additive flashes. They are light, not solid objects.
        a=np.array(src)[...,3]
        if (a==255).sum()<.2*(a>0).sum():return src,None
        if 'ticket' in stem:
            m=Model().box((0,0,0),(14,.8,20),'ivory')
            m.add(recipe('magic_conch').transform(S(.5)@T(0,-3,0)))
        else:
            m=Model().plate([(-5,-8),(-7,-1),(-5,6),(0,10),(5,6),(7,-1),(3,-9)],4,'iron',bevel=.5)
            if 'uruz' in stem:pts=[(-3,-2,-4),(-3,-2,5),(3,-2,2),(3,-2,-4)]
            else:pts=[(-2,-2,-6),(-2,-2,6),(-2,-2,4),(3,-2,1),(-2,-2,-1)]
            m.tube(pts,.65,'gold')
        return fitted(m,src,w,h),m
    raise ValueError((stem,name))


ANIMATIONS=['hermit_crab.anm2','dragon.anm2','time_money.anm2','effects/conch_ox.anm2',
            'effects/conch_ox_rice.anm2','effects/conch_rat_run.anm2','effects/conch_jangseung_ward.anm2',
            'effects/conch_rabbit_tracks.anm2','005.300_conch_ticket.anm2','005.300_thurisaz.anm2','005.300_uruz.anm2']


def main():
    rows=[];views=[]
    for anm2 in ANIMATIONS:
        for sheet,records in frame_records(anm2).items():
            original=Image.open(sheet).convert('RGBA');out=Image.new('RGBA',original.size)
            for rect,(name,i,attrs) in records.items():
                x,y,w,h=rect;sub=original.crop((x,y,x+w,y+h))
                if not sub.getbbox():continue
                frame,m=actor_frame(sub,name,i,rect,sheet)
                out.paste(frame,(x,y))
                if i==0 and m and len(m.parts):
                    directory=OUT/'models/entities';directory.mkdir(parents=True,exist_ok=True)
                    export_glb(clean(m.parts),m.materials,directory/f'{sheet.stem}_{name}.glb')
                    if not name.startswith('Grip') and len(views)<30:views.append((sheet.stem+' '+name,sub,frame))
            dest=sheet.with_stem(sheet.stem+'_af3d');out.save(dest)
            rows.append({'source':sheet.relative_to(ROOT/'resources').as_posix(),
                         'still':dest.relative_to(ROOT/'resources').as_posix(),'anm2':'gfx/'+anm2})
            print(sheet.name,len(records),'poses',flush=True)
    # Jangseung already has authored, camera-specific 3D geometry. Its frames
    # must be remapped because its high-resolution preview ANM2 uses different crops.
    src_records=frame_records('effects/notused/conch_jangseung_aprilfools.anm2')
    target_records=frame_records('effects/conch_jangseung.anm2')
    byname={}
    for sheet,records in src_records.items():
        im=Image.open(sheet)
        for (x,y,w,h),(name,i,_) in records.items():byname[name]=im.crop((x,y,x+w,y+h))
    for sheet,records in target_records.items():
        out=Image.new('RGBA',Image.open(sheet).size)
        for (x,y,w,h),(name,i,_) in records.items():
            out.paste(byname[name].resize((w,h),Image.Resampling.LANCZOS),(x,y))
        dest=sheet.with_stem(sheet.stem+'_af3d');out.save(dest)
        rows.append({'source':sheet.relative_to(ROOT/'resources').as_posix(),'still':dest.relative_to(ROOT/'resources').as_posix(),'anm2':'gfx/effects/conch_jangseung.anm2'})
    (OUT/'actors.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    preview=Image.new('RGBA',(900,((len(views)+3)//4)*130),(38,36,40));d=ImageDraw.Draw(preview)
    for i,(name,a,b) in enumerate(views):
        x=(i%4)*225;y=(i//4)*130
        for off,im in [(0,a),(110,b)]:
            box=im.getbbox();im=im.crop(box);k=min(100/im.width,95/im.height,4)
            im=im.resize((round(im.width*k),round(im.height*k)),Image.Resampling.NEAREST)
            preview.alpha_composite(im,(x+off,y))
        d.text((x,y+100),name[:28],fill='white')
    preview.save(PREVIEW/'actors_comparison.png')


if __name__=='__main__':main()
