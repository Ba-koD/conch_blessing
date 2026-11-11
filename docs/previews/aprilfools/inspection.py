"""Offline inspection artifacts made from the exact meshes/runtime frames."""
import json
from PIL import Image,ImageDraw,ImageFont
from build import ROOT,OUT,PREVIEW,view,frame_for_turn
from objects import build


def main():
    rows=json.loads((OUT/'items.json').read_text(encoding='utf-8'))
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',16)
    small=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',12)
    bg=(30,32,39)
    # Every exported angle, in order, at its actual 32px resolution.
    for page in range((len(rows)+8)//9):
        subset=rows[page*9:page*9+9]
        out=Image.new('RGB',(1056,32+len(subset)*64),bg);d=ImageDraw.Draw(out)
        d.text((16,4),'실제 게임용 32프레임 · 0° → 348.75°',font=font,fill='white')
        for i,r in enumerate(subset):
            y=32+i*64;d.text((16,y),r['key'],font=small,fill='#bbccdc')
            im=Image.open(ROOT/'resources'/r['spin']).convert('RGBA');out.paste(im,(16,y+23),im)
        out.save(PREVIEW/f'rotation_check_{page+1}.png')
    lookup={r['key']:r for r in rows}
    keys=['tyrfing','oral_steroids','hermit_crab','kids_menu',
          'utility_belt','soflam','angels_crown','two_faced_penny']
    frames=[]
    for f in range(32):
        out=Image.new('RGB',(640,350),bg);d=ImageDraw.Draw(out)
        for i,key in enumerate(keys):
            r=lookup[key];sheet=Image.open(ROOT/'resources'/r['spin'])
            im=sheet.crop((32*f,0,32*f+32,32)).convert('RGBA').resize((128,128),Image.Resampling.NEAREST)
            x=i%4*160;y=i//4*175;out.paste(im,(x+16,y+8),im)
            d.text((x+10,y+143),key,font=small,fill='white')
        frames.append(out)
    frames[0].save(PREVIEW/'constructed_rotation.gif',save_all=True,append_images=frames[1:],duration=67,loop=0,disposal=2)
    keys=['tyrfing','oral_steroids','hermit_crab','kids_menu','utility_belt','soflam']
    out=Image.new('RGB',(800,36+len(keys)*166),bg);d=ImageDraw.Draw(out)
    for i,label in enumerate(['원본','정면','45°','측면','뒷면']):d.text((i*160+12,6),label,font=font,fill='white')
    for i,key in enumerate(keys):
        r=lookup[key];source=ROOT/'resources'/r['source'];m=build(source,key);frame_for_turn(m)
        images=[Image.open(source).resize((128,128),Image.Resampling.NEAREST)]+[view(m,a,size=144) for a in [0,45,90,180]]
        for j,im in enumerate(images):out.paste(im,(j*160+8,36+i*166),im)
        d.text((12,36+i*166+145),key,font=small,fill='#c9d1df')
    out.save(PREVIEW/'constructed_views.png')
    print('Wrote all-angle inspection pages, native rotation GIF and multi-view models')


if __name__=='__main__':main()
