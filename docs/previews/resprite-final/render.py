"""Render the approved shipped selection at exact integer pixel scale."""
from io import BytesIO
from PIL import Image,ImageDraw,ImageFont
from verify_selection import HERE, ROOT, load_selection, original_bytes, verify

selection=load_selection()
verify(selection)
rows=selection['items']
title=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',28)
label=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',15)
small=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',12)
labels={'original':'원본 유지','original_edit':'원본 수정 적용','new_design':'새 디자인 적용','selected_v1':'선택 시안 적용'}
for dark in (False,True):
    bg,card,ink,muted=('#24232b','#35333d','#f2eadc','#bdb5ac') if dark else ('#ded7c8','#f1eadc','#29232a','#776c60')
    out=Image.new('RGB',(1236,1500),bg);d=ImageDraw.Draw(out)
    d.text((22,17),'Conch’s Blessing · 전체 47종 적용 확정',font=title,fill=ink)
    d.text((22,59),'티르핑·봉인된 마검·경구형 스테로이드·적사단지 원본 / 총 19종 수정·28종 원본 유지 / 실제 PNG 4배',font=label,fill=ink)
    for n,row in enumerate(rows):
        x=20+n%7*172;y=100+n//7*198
        d.rounded_rectangle((x,y,x+164,y+188),7,fill=card)
        name=row['name'];font=label if d.textlength(name,font=label)<=148 else small
        d.text((x+8,y+8),name,font=font,fill=ink)
        im=Image.open(ROOT/row['source']).convert('RGBA')
        big=im.resize((128,128),Image.Resampling.NEAREST);out.paste(big,(x+18,y+34),big)
        d.text((x+8,y+167),labels[row['mode']],font=small,fill=muted)
    out.save(HERE/('all-items-dark.png' if dark else 'all-items.png'))

changed=[row for row in rows if row['original_sha256']!=row['selected_sha256']]
out=Image.new('RGB',(1280,100+((len(changed)+3)//4)*240),'#ded7c8')
d=ImageDraw.Draw(out)
d.text((20,17),'Conch’s Blessing · 변경된 19종 원본 / 적용본',font=title,fill='#29232a')
d.text((20,59),'각 칸 왼쪽: 변경 전 원본 / 오른쪽: 실제 적용 PNG · 4배 확대와 실제 크기',font=label,fill='#29232a')
for n,row in enumerate(changed):
    x=20+n%4*316;y=100+n//4*240
    d.rounded_rectangle((x,y,x+304,y+230),7,fill='#f1eadc')
    d.text((x+9,y+8),row['name'],font=label,fill='#29232a')
    pair=(Image.open(BytesIO(original_bytes(selection,row))).convert('RGBA'),
          Image.open(ROOT/row['source']).convert('RGBA'))
    for side,im in enumerate(pair):
        left=x+14+side*150
        big=im.resize((128,128),Image.Resampling.NEAREST)
        out.paste(big,(left,y+37),big)
        out.paste(im,(left+48,y+173),im)
        d.text((left+44,y+210),'원본' if side==0 else '적용본',font=small,fill='#776c60')
out.save(HERE/'comparison.png')
