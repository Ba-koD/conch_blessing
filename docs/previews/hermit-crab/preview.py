"""Compose review sheets. Original item PNGs stay whole and unmodified.

Original PNGs are sampled only for display; no tiny substitute is baked into
the crab art. Display scales match the shipped attachment manifest.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import csv,argparse

D=Path(__file__).resolve().parent;R=D.parents[2]
FONT='C:/Windows/Fonts/malgun.ttf'
TITLE=ImageFont.truetype(FONT,24);LABEL=ImageFont.truetype(FONT,18);SMALL=ImageFont.truetype(FONT,14)
ATLAS=Image.open(D/'directions_sheet.png').convert('RGBA')
GRIPS=Image.open(D/'grip_sheet.png').convert('RGBA')
with (D/'attachments.tsv').open(encoding='utf-8') as manifest:
 DATA={(r['mode'],int(r['step'])):r for r in csv.DictReader(manifest,delimiter='\t')}
FILES=['trinket_035_curvedhorn.png','trinket_001_swallowedpenny.png']
ICONS=[Image.open(R/'../../extracted_resources/resources/gfx/items/trinkets'/f).convert('RGBA') for f in FILES]

def source(mode,step=0):
 row=DATA[mode,step];s=int(row['size']);x=int(row['cell_x']);y=int(row['cell_y'])
 if s==32:x+=8;y+=12
 box=(x,y,x+s,y+s)
 return row,ATLAS.crop(box),GRIPS.crop(box)

def render(mode,zoom,step=0,body_override=None):
 row,body,grip=source(mode,step);body=body_override if body_override is not None else body;s=body.width
 # Margin allows a complete independently rendered item even outside a body cel.
 margin=6*zoom;img=Image.new('RGBA',((s+12)*zoom,(s+12)*zoom))
 img.alpha_composite(body.resize((s*zoom,s*zoom),Image.Resampling.NEAREST),(margin,margin))
 for i,original in enumerate(ICONS,1):
  if not row[f'slot{i}_x']:continue
  scale=float(row[f'slot{i}_scale'])*zoom
  ratio=scale;item=original.resize((round(original.width*ratio),round(original.height*ratio)),Image.Resampling.NEAREST)
  b=original.getbbox();pivot=((b[0]+b[2])/2,b[3])
  x=margin+round(float(row[f'slot{i}_x'])*zoom-pivot[0]*ratio)
  top=float(row[f'slot{i}_bottom'])*zoom-pivot[1]*ratio
  if row.get(f'slot{i}_min_top'):
   top=max(top,float(row[f'slot{i}_min_top'])*zoom-b[1]*ratio)
  y=margin+round(top)
  img.alpha_composite(item,(x,y))
 img.alpha_composite(grip.resize((s*zoom,s*zoom),Image.Resampling.NEAREST),(margin,margin))
 return img

def board(panels,title,sub,step=0):
 sheet=Image.new('RGB',(1140,540),'#ddd5c5');dr=ImageDraw.Draw(sheet)
 dr.text((22,14),title,font=TITLE,fill='#25212a');dr.text((23,49),sub,font=SMALL,fill='#645b58')
 for ci,(mode,label,zoom,override) in enumerate(panels):
  x=12+ci*376;y=87
  dr.rounded_rectangle((x,y,x+363,505),8,fill='#f1e9d9')
  dr.text((x+12,y+12),label,font=LABEL,fill='#25212a')
  im=render(mode,zoom,step,override);sheet.paste(im,(x+(364-im.width)//2,y+40),im)
  thumb=im.resize((im.width//zoom,im.height//zoom),Image.Resampling.NEAREST)
  tx=x+280-thumb.width//2;ty=497-thumb.height
  dr.rectangle((tx-4,ty-4,tx+thumb.width+4,ty+thumb.height+4),fill='#27252e');sheet.paste(thumb,(tx,ty),thumb)
  dr.text((x+12,477),f'{zoom}배 / 오른쪽 아래 1배',font=SMALL,fill='#645b58')
 dr.text((22,516),'정면 전용 · 장신구 원본 1.5배 확대 · 게임 적용 파일 기준',font=SMALL,fill='#645b58')
 return sheet

parser=argparse.ArgumentParser();parser.add_argument('--before',type=Path);args=parser.parse_args()
before=Image.open(args.before).convert('RGBA') if args.before else None
panels=[('shell-base','수정 전 기본형' if before else '기본형 · 빈 집게',8,before),('shell-base','수정 후 기본형 · 32×32',8,None),('bffs-claws','BFFS · 디테일 참고',6,None)]
board(panels,'소라게 · 정면 껍데기 디테일','나선의 감긴 층과 명암을 기본형의 32×32 격자에 보강').save(D/'comparison.png')
board([('bffs-empty','BFFS · 빈손',6,None),('bffs-one','BFFS · 한 개 / 한쪽만 올림',6,None),('bffs-claws','BFFS · 두 개 / 양쪽 올림',6,None)],'소라게 · BFFS 소지 개수별 자세','빈 집게는 중앙에 내려두고, 장신구가 있는 집게만 올립니다.').save(D/'bffs-comparison.png')
walk_panels=[('carry-one','기본형 · 장신구 한 개',8,None),('bffs-one','BFFS · 장신구 한 개',6,None),('bffs-claws','BFFS · 장신구 두 개',6,None)]
walk=[board(walk_panels,'소라게 · 정면 걷기','다리의 교대 디딤과 몸통 움직임 · 8프레임 반복',step) for step in range(8)]
palette=walk[0].quantize(colors=256,method=Image.Quantize.MEDIANCUT)
gif=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in walk]
gif[0].save(D/'walking-preview.gif',save_all=True,append_images=gif[1:],duration=100,loop=0,disposal=2,optimize=False)

# Show the exact unmodified source art beside the attached version.
sheet=Image.new('RGB',(1100,470),'#ddd5c5');dr=ImageDraw.Draw(sheet)
dr.text((22,14),'실제 장신구 PNG · 원본과 소지 모습',font=TITLE,fill='#25212a')
dr.text((22,51),'몸에 작은 아이콘을 다시 그리지 않고, 원본 PNG를 독립적으로 표시합니다.',font=SMALL,fill='#645b58')
for i,(im,name) in enumerate(zip(ICONS,['Curved Horn 원본','Swallowed Penny 원본'])):
 x=15+i*190;dr.rounded_rectangle((x,89,x+180,440),8,fill='#f1e9d9');dr.text((x+10,100),name,font=SMALL,fill='#25212a')
 q=im.resize((160,160),Image.Resampling.NEAREST);sheet.paste(q,(x+10,167),q);sheet.paste(im,(x+74,358),im)
 dr.text((x+35,407),'5배 / 아래 1배',font=SMALL,fill='#645b58')
for mode,x,zoom,label in [('carry-one',400,8,'기본형 · 56.25% 표시'),('bffs-claws',734,6,'확대형 · 75% 표시')]:
 dr.rounded_rectangle((x,89,x+351,440),8,fill='#f1e9d9');dr.text((x+12,100),label,font=LABEL,fill='#25212a')
 im=render(mode,zoom);sheet.paste(im,(x+(352-im.width)//2,118),im)
sheet.save(D/'trinket-check.png')
print('Saved front shell comparison, BFFS poses, original-icon comparison and walking GIF')
