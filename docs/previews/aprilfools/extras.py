"""Modelled props, floor marks and effect art beyond items and actors."""
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage
from recipes import Model,recipe,MATS
from actors import GFX,frame_records,fitted,native
from mesh3d import R,T,S,Part,material,export_glb
from build import ROOT,OUT,clean


def architectural_panel(src):
    """Thin machined/painted boards, including actual openings and reverse.

    A flat front with source paint, constant board thickness and boundary walls.
    Grid triangulation preserves disconnected trims and holes; it never turns
    lighting or a colour value into a displacement or rounded volume.
    """
    a=np.array(src.convert('RGBA'));h,w=a.shape[:2];mask=a[...,3]>=128
    m=Model();m.materials=dict(MATS);verts=[];faces={};backs=[];walls=[]
    for y,x in zip(*np.nonzero(mask)):
        base=len(verts)
        for depth in [-.9,.9]:
            verts.extend([(x-w/2,depth,h/2-y),(x+1-w/2,depth,h/2-y),
                          (x+1-w/2,depth,h/2-y-1),(x-w/2,depth,h/2-y-1)])
        colour=tuple((a[y,x,:3]//16*16+8).clip(0,255));name='paint_'+'_'.join(map(str,colour))
        m.materials[name]=material(colour,spec=.15,rough=.7)
        faces.setdefault(name,[]).extend([(base,base+2,base+1),(base,base+3,base+2)])
        backs.extend([(base+4,base+5,base+6),(base+4,base+6,base+7)])
        for q,(dy,dx) in enumerate([(-1,0),(0,1),(1,0),(0,-1)]):
            yy,xx=y+dy,x+dx
            if 0<=yy<h and 0<=xx<w and mask[yy,xx]:continue
            b=base+q;c=base+(q+1)%4;walls.extend([(b,c,c+4),(b,c+4,b+4)])
    for name,f in list(faces.items())+[('wood',backs),('iron',walls)]:
        if f:m.parts.append(Part(verts,f,name,False))
    return m


def prop(name,rect,index):
    x,y,w,h=rect;m=Model()
    if name.startswith('conch_upgrade_clock'):
        if 'rim' in name:
            m.ring((0,0,0),10,10,.65,'gold')
            for a in np.linspace(0,2*math.pi,12,endpoint=False):
                m.ball((9*math.sin(a),-.4,9*math.cos(a)),(.35,.35,.55),'ivory')
            m.box((0,0,11.5),(3,2,1.5),'gold')
        else:
            m.tube([(0,0,-6),(0,0,5)],.3,'gold')
            m.plate([(-1,3),(0,7),(1,3)],.6,'gold')
            m.ring((0,0,-6),.8,.8,.3,'gold')
    elif name=='flame':
        m=recipe('eternal_flame');m.transform(S(1+.08*math.sin(index),1,1+.1*math.cos(index)))
    elif name=='conch_ox_furrow':
        m.tube([(-3,0,-6),(-3.5,0,0),(-3,0,6)],1.1,'brown')
        m.tube([(3,0,-6),(3.5,0,0),(3,0,6)],1.1,'brown')
        m.tube([(0,.5,-6),(0,.5,6)],1,'darkbrown')
        m.transform(R('y',index*7))
    elif name=='conch_jangseung_ground':
        m.ring((0,0,0),10,4,.55,'wood')
    elif name=='conch_dragon_lightning':
        m.tube([(0,0,14),(-2,0,8),(2,0,4),(-1,0,-2),(2,0,-6),(0,0,-12)],.55,'cyan')
        for s in [-1,1]:m.tube([(0,0,4),(s*4,0,2),(s*6,0,-2)],.25,'white')
    else:raise ValueError(name)
    return m


def door(sheet):
    # Doors are constructed boards/metal plates with exactly positioned holes.
    # Only their colour regions supply construction contours; no painted light
    # is baked as a height. Extrusion is appropriate for these thin hard parts.
    src=Image.open(sheet).convert('RGBA');arr=np.array(src)
    out=Image.new('RGBA',src.size); exported=[];materials={}
    connected,n=ndimage.label(arr[...,3]>128)
    for i,sl in enumerate(ndimage.find_objects(connected),1):
        if sl is None:continue
        yy,xx=sl; crop=arr[yy,xx].copy();crop[connected[yy,xx]!=i]=0
        if (crop[...,3]>0).sum()<3:
            out.paste(Image.fromarray(crop),(xx.start,yy.start));continue
        sub=Image.fromarray(crop);model=architectural_panel(sub)
        # Rendering the native face preserves its animation panel registration.
        from mesh3d import Camera,render
        side=max(sub.size);large=render(model.parts,model.materials,Camera(yaw=0,pitch=0,ortho=side,dist=100),size=side*3,ss=1)
        dx=(side-sub.width)*3//2;dy=(side-sub.height)*3//2
        img=large.crop((dx,dy,dx+sub.width*3,dy+sub.height*3)).resize(sub.size,Image.Resampling.LANCZOS)
        out.paste(img,(xx.start,yy.start))
        if model is None:continue
        for p in model.parts:
            name=f'part{i}_{p.mat}';materials[name]=model.materials[p.mat];p.mat=name
            p=p.moved(T(xx.start+crop.shape[1]/2,0,-yy.start-crop.shape[0]/2));exported.append(p)
    dest=sheet.with_stem(sheet.stem+'_af3d');out.save(dest)
    export_glb(clean(exported),materials,OUT/'models'/f'{sheet.stem}.glb')
    return {'source':sheet.relative_to(ROOT/'resources').as_posix(),'still':dest.relative_to(ROOT/'resources').as_posix()}


def main():
    rows=[]
    for name in ['conch_upgrade_clock_rim','conch_upgrade_clock_hour','conch_upgrade_clock_minute',
                 'conch_ox_furrow','conch_jangseung_ground','conch_dragon_lightning','flame']:
        for sheet,records in frame_records('effects/'+name+'.anm2').items():
            original=Image.open(sheet).convert('RGBA');dest=sheet.with_stem(sheet.stem+'_af3d')
            out=Image.open(dest).convert('RGBA') if name.startswith('conch_upgrade_clock') and dest.exists() else Image.new('RGBA',original.size)
            for index,(rect,(anim,i,_)) in enumerate(records.items()):
                x,y,w,h=rect;sub=original.crop((x,y,x+w,y+h))
                if not sub.getbbox():continue
                m=prop(name,rect,index);m.materials=MATS;img=fitted(m,sub,w,h)
                # Ground decals keep their authored opacity; they are not obstacles.
                if name in ['conch_jangseung_ground','conch_ox_furrow']:
                    a=np.array(img);a[...,3]=(a[...,3].astype(float)*np.array(sub)[...,3]/255).astype('uint8');img=Image.fromarray(a)
                out.paste(img,(x,y))
                if index==0 and m:export_glb(clean(m.parts),m.materials,OUT/'models'/f'{name}.glb')
            out.save(dest)
            rows.append({'source':sheet.relative_to(ROOT/'resources').as_posix(),'still':dest.relative_to(ROOT/'resources').as_posix()})
            print(name,flush=True)
    for name in ['door_01x_ghostexit_green','door_02_treasureroomdoor_angel']:
        rows.append(door(GFX/'grid'/f'{name}.png'));print(name,flush=True)
    p=GFX/'ui/MagicConch.png';dest=p.with_stem(p.stem+'_af3d')
    src=Image.open(p);m=recipe('magic_conch');m.materials=MATS;fitted(m,src,*src.size).save(dest)
    export_glb(clean(m.parts),m.materials,OUT/'models/magic_conch.glb')
    rows.append({'source':p.relative_to(ROOT/'resources').as_posix(),'still':dest.relative_to(ROOT/'resources').as_posix()})
    (OUT/'extras.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
