"""Native 32-pixel finishing of the generated concepts; no downscaling.

Coordinates below are authored directly on the final grid. This is an art
source, not a runtime dependency. Run from the repository root.
"""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path('resources/gfx/items/collectibles')
ink = '#201b22'

def canvas():
    im = Image.new('RGBA', (32, 32))
    return im, ImageDraw.Draw(im)

# Cleaned final grids preserve the generated/approved shapes. This data is
# self-contained: regenerating the assets never needs the high-resolution drafts.
import json
from PIL import ImageColor
art = json.loads(Path(__file__).with_name('eye-item-pixels.json').read_text(encoding='utf-8'))
for name, spec in art.items():
    im, d = canvas()
    assert len(spec['rows']) == 32 and all(len(row) == 32 for row in spec['rows'])
    palette = {key: ImageColor.getrgb(color) + (255,) for key, color in spec['palette'].items()}
    for y, row in enumerate(spec['rows']):
        for x, cell in enumerate(row):
            if cell != '.': im.putpixel((x, y), palette[cell])
    im.save(OUT / (name + '.png'))

im, d = canvas()
# The viewer's left half is absent, matching the leading blank flavor text.
# It is deliberately not re-centered: the transparent half is the concept.
d.polygon([(16,4),(20,4),(24,6),(27,10),(28,15),(27,20),(24,25),(20,28),(16,28),
           (16,25),(17,24),(16,23),(16,17),(17,16),(16,15),(16,10),(17,9),(16,8)], fill=ink)
d.polygon([(17,6),(20,6),(23,8),(25,11),(26,16),(25,20),(23,23),(20,26),(17,26),
           (17,24),(18,23),(17,22),(17,18),(18,16),(17,14),(17,11),(18,9),(17,8)], fill='#b87d80')
d.polygon([(17,6),(20,6),(22,8),(24,10),(25,14),(24,20),(21,24),(18,25),(17,23),
           (17,18),(18,16),(17,14),(17,11),(18,9),(17,8)], fill='#e5b4b1')
d.line([(18,7),(20,7),(22,9)], fill='#f1cdbe', width=1)
d.rectangle((19,14,24,18), fill=ink)
d.rectangle((20,13,23,19), fill=ink)
d.rectangle((20,14,21,15), fill='#f6f1df')
d.rectangle((21,20,23,22), fill='#58a7b5')
d.rectangle((21,20,22,21), fill='#a3dbdf')
d.rectangle((17,22,19,23), fill=ink)
im.save(OUT/'hemispatial_neglect.png')

if __name__ == '__main__':
    for name in ('real_eyes','ar_glasses','hemispatial_neglect'):
        im=Image.open(OUT/(name+'.png'))
        assert im.size==(32,32) and set(im.getchannel('A').get_flattened_data())=={0,255}
        print(name, im.size, len(im.getcolors()))
