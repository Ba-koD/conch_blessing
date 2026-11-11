"""Exact native PNG comparison; optional previous-build ZIP stays outside Git."""
import argparse
import io
import json
import zipfile
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from lupa.lua53 import LuaRuntime
from build import ROOT,OUT,PREVIEW


def main(baseline=None):
    rows=json.loads((OUT/'items.json').read_text(encoding='utf-8'))
    korean=LuaRuntime().execute((ROOT/'scripts/locale/kr.lua').read_text(encoding='utf-8'))['items']
    fontpath=Path('C:/Windows/Fonts/malgun.ttf')
    font=lambda n:ImageFont.truetype(str(fontpath),n) if fontpath.exists() else ImageFont.load_default()
    old=zipfile.ZipFile(baseline) if baseline else None
    labels=['원본','이전 3D','수정 3D'] if old else ['원본','수정 3D']
    cols=6;tw=240 if old else 174;th=145
    out=Image.new('RGB',(cols*tw,80+((len(rows)+cols-1)//cols)*th),(29,30,36));d=ImageDraw.Draw(out)
    d.text((16,10),'원본 기준 3D 수정 · 전체 아이템',font=font(24),fill='#f2eee5')
    d.text((16,46),'실제 32×32 PNG의 정면 · 각 2배 확대',font=font(15),fill='#b1b7c5')
    for i,r in enumerate(rows):
        x=i%cols*tw;y=80+i//cols*th
        entry=korean[r['key'].upper()];name=entry['name'] if entry else r['key']
        name=name.replace('(WIP)','').strip()
        d.text((x+9,y+3),name,font=font(15),fill='#e8e4dd')
        images=[Image.open(ROOT/'resources'/r['source']).convert('RGBA')]
        if old:images.append(Image.open(io.BytesIO(old.read('resources/'+r['still']))).convert('RGBA'))
        images.append(Image.open(ROOT/'resources'/r['still']).convert('RGBA'))
        for j,(label,im) in enumerate(zip(labels,images)):
            dx=x+9+j*77;out.paste(im.resize((64,64),Image.Resampling.NEAREST),(dx,y+33),im.resize((64,64),Image.Resampling.NEAREST))
            d.text((dx,y+105),label,font=font(12),fill='#9dcdbb' if j==len(images)-1 else '#a7acb6')
    out.save(PREVIEW/'fidelity_comparison.png')
    # A compact selection gives the chat a legible view before opening all 53.
    keys=['kronos','tyrfing','sealed_demon_sword','oral_steroids',
          'hermit_crab','kids_menu','two_faced_penny','a_minus',
          'ox','goat','dog','conch_pearl']
    selected=Image.new('RGB',(4*tw,65+3*th),(29,30,36));sd=ImageDraw.Draw(selected)
    sd.text((14,12),'원본 / 이전 3D / 수정 3D' if old else '원본 / 수정 3D',font=font(22),fill='#eee9df')
    indexes={r['key']:i for i,r in enumerate(rows)}
    for k,key in enumerate(keys):
        i=indexes[key];x=i%cols*tw;y=80+i//cols*th
        selected.paste(out.crop((x,y,x+tw,y+th)),(k%4*tw,65+k//4*th))
    selected.save(PREVIEW/'fidelity_selected.png')
    angles=Image.new('RGB',(660,55+8*145),(29,30,36));ad=ImageDraw.Draw(angles)
    for j,label in enumerate(['원본','정면','45도','측면','뒷면']):
        ad.text((j*132+10,12),label,font=font(17),fill='#dedbd4')
    lookup={r['key']:r for r in rows}
    for i,key in enumerate(['kronos','tyrfing','hermit_crab','kids_menu','ox','angels_crown','inf_d6','conch_pearl']):
        r=lookup[key];sheet=Image.open(ROOT/'resources'/r['spin'])
        frames=[Image.open(ROOT/'resources'/r['source'])]+[sheet.crop((f*32,0,f*32+32,32)) for f in [0,4,8,16]]
        for j,im in enumerate(frames):
            im=im.convert('RGBA').resize((128,128),Image.Resampling.NEAREST)
            angles.paste(im,(j*132,55+i*145),im)
    angles.save(PREVIEW/'front_side_back.png')
    if old:old.close()
    print('Wrote native comparisons for',len(rows),'items')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path);main(p.parse_args().baseline)
