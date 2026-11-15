"""Pose-render new actors while retaining the source animation's stage cues."""
import importlib.util
from functools import lru_cache
import numpy as np
from PIL import Image,ImageDraw
from additions import jeon_woochi,talisman
from recipes import Model,MATS
from mesh3d import T,R,export_glb,material
from build import ROOT,OUT,clean


@lru_cache(None)
def jeon_effect():
    # Reuse our own animation score: source crop, feet, stretch, sparks,
    # triggers and compositing order must agree. Only physical drawings change.
    from actors import native
    spec=importlib.util.spec_from_file_location('af3d_jeon_source',OUT.parent/'jeonwoochi/author.py')
    source=importlib.util.module_from_spec(spec);spec.loader.exec_module(source)
    cache={};directory=OUT/'models/entities';directory.mkdir(exist_ok=True)
    def posed(pose):
        key=tuple(sorted(pose.items()))
        if key not in cache:
            m=jeon_woochi(**pose)
            cache[key]=native(m,40,58,20,56)
            name='_'.join(str(pose.get(k,default)) for k,default in [('fan_state','a'),('arm','behind'),('flare',0),('sway',0)])
            export_glb(clean(m.parts),MATS,directory/f'conch_jeonwoochi_{name}.glb')
        return cache[key]
    original_slip=source.slip
    def slip(k,burning):
        m=talisman().transform(R('z',(0,80,165)[k%3]))
        im=native(m,7,15,3.5,9.5)
        if burning:
            # Flames remain light, on exactly the source's top five rows.
            flame=original_slip(k,True).crop((0,0,7,5));im.alpha_composite(flame,(0,0))
        return im
    def smoke_frame(t):
        m=Model()
        for i,(cy,cx,r,alpha) in enumerate(source.smoke_puffs(t)):
            mat=f'jeon_smoke_{t}_{i}'
            MATS[mat]=material((216,219,235),alpha=alpha,spec=.02,rough=1)
            m.ball((cx-32,(cy-32)*.12,32-cy),(r,r*.8,r),mat,16)
        im=native(m,64,64,32,32) if m.parts else Image.new('RGBA',(64,64))
        if t<=1:
            d=ImageDraw.Draw(im);d.ellipse((28,28,35,35),fill=(255,248,222,220))
        if t==4:export_glb(clean(m.parts),MATS,directory/'conch_jeonwoochi_smoke.glb')
        return im
    source.posed=posed;source.slip=slip;source.smoke_frame=smoke_frame
    return source.effect_sheet(source.effect_frames())
