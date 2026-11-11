"""Build the authored April Fools meshes and Isaac turntables; no game required.

python docs/previews/aprilfools/build.py [key ...]
Generated assets live beside their vanilla-layout counterparts, with an
_af3d suffix. Legacy experiments under notused are never runtime inputs.
"""
import json
import sys
import time
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from mesh3d import Camera, render, export_glb
from objects import build as reference_model
from models import items, spin_anm2

ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
PREVIEW=ROOT/'.tmp/aprilfools'
FRAMES=32
DELAY=2


def clean(parts):
    """Remove degenerates; preserve independent material parts and hard edges."""
    for p in parts:
        tri=p.v[p.f]
        keep=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-9
        p.f=p.f[keep]
    return [p for p in parts if len(p.f)]


def frame_for_turn(model):
    """Only crowded source canvases need a small inset for the full turn."""
    from mesh3d import T,S,move
    from mesh3d import R
    v=np.vstack([p.v for p in model.parts]);ax=model.axis[0]
    cam=Camera(yaw=0,pitch=getattr(model,'camera_pitch',0),dist=100,ortho=32)
    xs=[];zs=[]
    for a in range(0,360,6):
        q=(v-[ax,0,0])@R('z',a)[:3,:3].T+[ax,0,0]
        xs.extend([q[:,0].min(),q[:,0].max()]);up=q@cam.up;zs.extend([up.min(),up.max()])
    mid=(min(zs)+max(zs))/2
    scale=min(1,(29.2-2*abs(ax))/(max(xs)-min(xs)),29.2/(max(zs)-min(zs)))
    model.parts=move(model.parts,T(ax,0,mid/max(cam.up[2],.1))@S(scale)@T(-ax,0,-mid/max(cam.up[2],.1)))
    v=np.vstack([p.v for p in model.parts]);z=v@cam.up
    # Remove only the common turn's vertical centre offset when it would clip.
    lo=mid+(min(zs)-mid)*scale;hi=mid+(max(zs)-mid)*scale
    dz=(max(0,-14.6-lo)-max(0,hi-14.6))/max(cam.up[2],.1)
    if dz:model.parts=move(model.parts,T(0,0,dz))
    return scale


def view(model, yaw=0, pitch=None, size=96):
    # Fixed lighting and camera; rotate the object, not the light rig.
    from mesh3d import R, T, move
    axis=model.axis
    if pitch is None:pitch=getattr(model,'camera_pitch',0)
    return render(move(model.parts,T(*axis)@R('z',yaw)@T(*(-a for a in axis))),model.materials,
                  Camera(yaw=0,pitch=pitch,dist=100,ortho=32),size=size,ss=1)


def build(key, kind, path):
    start=time.time()
    model=reference_model(path,key);model.parts=clean(model.parts)
    inset=frame_for_turn(model)
    models=OUT/'models'; models.mkdir(exist_ok=True)
    triangles=export_glb(model.parts,model.materials,models/f'{key}.glb')
    frames=[view(model,360*k/FRAMES).resize((32,32),Image.Resampling.LANCZOS) for k in range(FRAMES)]
    sheet=Image.new('RGBA',(32*FRAMES,32))
    for k,im in enumerate(frames):sheet.alpha_composite(im,(32*k,0))
    dest=path.with_stem(path.stem+'_af3d')
    frames[0].save(dest)
    sheet.save(path.with_stem(path.stem+'_af3d_spin'))
    templates=OUT/'isaac';templates.mkdir(exist_ok=True)
    anm=spin_anm2(key+'_af3d',FRAMES,DELAY)
    texture=path.with_stem(path.stem+'_af3d_spin').relative_to(ROOT/'resources').as_posix()
    anm=anm.replace(f'Path="{key}_af3d_spin.png"',f'Path="{texture}"')
    (templates/f'{key}_spin.anm2').write_text(anm,encoding='utf-8')
    hero=view(model,-30,size=192)
    PREVIEW.mkdir(parents=True,exist_ok=True)
    hero.save(PREVIEW/f'{key}_hero.png')
    print(f'{key}: {triangles} triangles, {len(model.parts)} parts ({time.time()-start:.1f}s)',flush=True)
    return {'key':key,'kind':kind,'source':path.relative_to(ROOT/'resources').as_posix(),
            'still':dest.relative_to(ROOT/'resources').as_posix(),
            'spin':path.with_stem(path.stem+'_af3d_spin').relative_to(ROOT/'resources').as_posix(),
            'frames':FRAMES,'delay':DELAY,'triangles':triangles,'parts':len(model.parts),
            'sourceScale':round(inset,5),'rotationAxis':list(model.axis),
            'cameraPitch':getattr(model,'camera_pitch',0),'construction':getattr(model,'components',[])}


def preview(rows):
    cols=6;tw=210;th=190
    out=Image.new('RGB',(cols*tw,((len(rows)+cols-1)//cols)*th),(38,36,40))
    d=ImageDraw.Draw(out)
    for i,row in enumerate(rows):
        x=i%cols*tw;y=i//cols*th
        orig=Image.open(ROOT/'resources'/row['source']).convert('RGBA').resize((64,64),Image.Resampling.NEAREST)
        hero=Image.open(PREVIEW/f"{row['key']}_hero.png").resize((136,136),Image.Resampling.LANCZOS)
        still=Image.open(ROOT/'resources'/row['still']).convert('RGBA').resize((64,64),Image.Resampling.NEAREST)
        out.paste(orig,(x+4,y+5),orig);out.paste(still,(x+4,y+76),still);out.paste(hero,(x+73,y+3),hero)
        d.text((x+5,y+152),row['key'],fill=(240,230,210))
        d.text((x+5,y+167),'original / 32px / model',fill=(165,165,175))
    out.save(PREVIEW/'authored_collection.png')
    # Animated overview makes bad side/back construction visible before shipping.
    animated=[]
    for k in range(FRAMES):
        f=Image.new('RGB',(cols*128,((len(rows)+cols-1)//cols)*128),(38,36,40));d=ImageDraw.Draw(f)
        for i,row in enumerate(rows):
            sheet=Image.open(ROOT/'resources'/row['spin'])
            im=sheet.crop((k*32,0,(k+1)*32,32)).resize((96,96),Image.Resampling.NEAREST)
            x=i%cols*128;y=i//cols*128
            f.paste(im,(x+16,y+4),im);d.text((x+3,y+105),row['key'][:20],fill=(230,220,210))
        animated.append(f)
    animated[0].save(PREVIEW/'turntables.gif',save_all=True,append_images=animated[1:],duration=67,loop=0,disposal=2)


def main(keys):
    catalogue={k:v for k,v in items().items() if '_af3d' not in k}
    rows=[build(key,*catalogue[key]) for key in keys or catalogue]
    if keys and (OUT/'items.json').exists():
        previous={r['key']:r for r in json.loads((OUT/'items.json').read_text(encoding='utf-8'))}
        previous.update({r['key']:r for r in rows})
        rows=[previous[k] for k in catalogue if k in previous]
    (OUT/'items.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    preview(rows)


if __name__=='__main__':main(sys.argv[1:])
