"""Lays 축's furrow, ditch and rice over every stage's real floor.

The furrow pieces are half transparent, so how they read depends on the
floor under them. This tiles a 7x7-cell piece of each vanilla floor texture
(`extracted_resources/resources/gfx/backdrop/*_nfloor.png`, read in place and
never copied into the repository) and stamps the same sample walk as
furrow.py on it: the yellow ox's furrow in from the left and round two
corners, the black ox's crossing it to a dead end. Run from the repository
root after furrow.py; it writes .tmp/ox_furrow/stages_*.png:

    python docs/previews/ox-revision/furrow_stages.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

import furrow as F

BACKDROP = F.ROOT.parents[1] / 'extracted_resources/resources/gfx/backdrop'
STAGES = [
    ('basement', '01_basement'), ('downpour', '01x_downpour'), ('cellar', '02_cellar'), ('dross', '02x_dross'),
    ('burning', '13_the burning basement'), ('caves', '03_caves'), ('mines', '03x_mines'),
    ('catacombs', '04_catacombs'), ('ashpit', '04x_ashpit'), ('drowned', '14_the drowned caves'),
    ('depths', '05_depths'), ('mausoleum', '05x_mausoleum'), ('necropolis', '06_necropolis'),
    ('gehenna', '06x_gehenna'), ('dank', '15_the dank depths'), ('womb', '07_the womb'),
    ('corpse', '07x_corpse'), ('utero', '08_utero'), ('scarred', '16_the scarred womb'),
    ('blue womb', '18_blue womb'), ('sheol', '09_sheol'), ('cathedral', '10_cathedral'),
    ('dark room', '12_darkroom'), ('chest', '11_chest'), ('shop', '0b_shop'), ('library', '0a_library'),
    ('secret', '0f_secretroom'),
]
CELLS = 7
SIDE = CELLS * F.T


def room(stem, sheet, rice_art):
    floor = Image.open(BACKDROP / f'{stem}_nfloor.png').convert('RGBA')
    out = floor.crop((26, 26, 26 + SIDE, 26 + SIDE))
    for color, walk, a, b in (('yellow', F.WALK_A, F.W, F.S), ('black', F.WALK_B, F.N, 0)):
        c = F.COLORS.index(color)
        for (x, y), pid in F.stroke(walk, a, b):
            v = (y * CELLS + x) % F.VARIANTS
            crop = sheet.crop((pid * F.T, (c * F.VARIANTS + v) * F.T, pid * F.T + F.T, (c * F.VARIANTS + v) * F.T + F.T))
            out.alpha_composite(crop, (x * F.T, y * F.T))
    # Rice where the two lines cross.
    ripe = rice_art.crop(((F.GROW_FRAMES - 1) * F.RW, 0, F.GROW_FRAMES * F.RW, F.RH))
    out.alpha_composite(ripe, (5 * F.T + F.T // 2 - F.RW // 2, 4 * F.T + F.T // 2 - F.RH + 1))
    return out


def main():
    sheet = Image.open(F.OUT / 'conch_ox_furrow.png').convert('RGBA')
    rice_art = Image.open(F.OUT / 'conch_ox_rice.png').convert('RGBA')
    F.PREVIEW.mkdir(parents=True, exist_ok=True)
    per_page, columns, scale, label = 9, 3, 2, 14
    for page in range(0, len(STAGES), per_page):
        chunk = STAGES[page:page + per_page]
        rows = (len(chunk) + columns - 1) // columns
        cell_w, cell_h = SIDE * scale + 8, SIDE * scale + label + 8
        canvas = Image.new('RGBA', (columns * cell_w, rows * cell_h), (24, 24, 24, 255))
        draw = ImageDraw.Draw(canvas)
        for i, (name, stem) in enumerate(chunk):
            x, y = (i % columns) * cell_w, (i // columns) * cell_h
            canvas.paste(room(stem, sheet, rice_art).resize((SIDE * scale, SIDE * scale), Image.NEAREST), (x + 4, y + label + 4))
            draw.text((x + 6, y + 2), name, fill=(230, 230, 230, 255))
        out = F.PREVIEW / f'stages_{page // per_page + 1}.png'
        canvas.save(out)
        print('saved', out.relative_to(F.ROOT))


if __name__ == '__main__':
    main()
