"""Render the directly editable native pixel grids; never resample AI drafts."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageColor
import json

ROOT=Path(__file__).resolve().parent
art=json.loads((ROOT/'pixels.json').read_text(encoding='utf-8'))
(ROOT/'icons').mkdir(exist_ok=True)
font_path=Path('C:/Windows/Fonts/malgun.ttf')
font=ImageFont.truetype(str(font_path),19)
small=ImageFont.truetype(str(font_path),13)
title=ImageFont.truetype(str(font_path),28)
sheet=Image.new('RGB',(1080,948),'#d9d2c1')
d=ImageDraw.Draw(sheet)
d.text((30,20),'십이지 · 아이템 스프라이트 2차 시안',font=title,fill='#252329')
d.text((31,62),'각 아이콘 32×32  ·  위 5배 / 아래 실제 크기  ·  콘셉트 검토용',font=small,fill='#655e55')
summary=[]
for i,(key,spec) in enumerate(art.items()):
    assert len(spec['rows'])==32 and all(len(r)==32 for r in spec['rows'])
    pal={k:ImageColor.getrgb(v)+(255,) for k,v in spec['palette'].items()}
    im=Image.new('RGBA',(32,32))
    for y,row in enumerate(spec['rows']):
        for x,c in enumerate(row):
            if c!='.':im.putpixel((x,y),pal[c])
    assert set(im.getchannel('A').get_flattened_data())<={0,255}
    im.save(ROOT/'icons'/(key+'.png'))
    col=i%4; row=i//4; x=30+col*263; y=109+row*274
    d.rounded_rectangle((x,y,x+245,y+258),radius=8,fill='#e6dfcf')
    sheet.paste(im.resize((160,160),Image.Resampling.NEAREST),(x+43,y+9),im.resize((160,160),Image.Resampling.NEAREST))
    sheet.paste(im,(x+107,y+175),im)
    d.text((x+12,y+218),spec['name'],font=font,fill='#2c2826')
    used=len(set(c for c in im.get_flattened_data() if c[3]))
    summary.append({'key':key,'size':[32,32],'colors':used,'bbox':list(im.getbbox()),'cleanup':spec['cleanup']})
sheet.save(ROOT/'zodiac-overview.png')
dark=Image.new('RGB',(800,500),'#393438')
dd=ImageDraw.Draw(dark)
for i,key in enumerate(art):
    im=Image.open(ROOT/'icons'/(key+'.png')).convert('RGBA')
    x=18+(i%6)*130; y=20+(i//6)*235
    big=im.resize((128,128),Image.Resampling.NEAREST)
    dark.paste(big,(x,y),big)
    dark.paste(im,(x+45,y+144),im)
    dd.text((x+10,y+190),key,font=small,fill='#eee7d7')
dark.save(ROOT/'zodiac-dark.png')
(ROOT/'validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Rendered',len(art),'native icons and exact nearest-neighbor contact sheet.')
