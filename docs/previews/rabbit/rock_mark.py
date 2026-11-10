"""묘 (Rabbit): the rabbit tracks drawn on the hidden rock, and their preview.

Authored on the native grid: two hops of four prints each (the two long hind
feet side by side in front, the two small fore feet behind), crossing the
rock's top face toward its upper right, as if the rabbit hopped over the rock
it hid under. The prints are dark and half transparent so they read on every
stage's rock without standing out more than a tinted rock's mark.

python docs/previews/rabbit/rock_mark.py          writes the runtime sheet and ANM2
python docs/previews/rabbit/rock_mark.py preview  also lays it on every stage's
    ordinary rock (each normal and alt look) beside that stage's tinted rock,
    read in place from extracted_resources, into .tmp/rabbit/rock_mark_preview.png
python docs/previews/rabbit/rock_mark.py kinds    lays the chosen draft on every
    obstacle kind the hidden rock can be (rock, alt rock, its marked look, bomb
    rock, spiked rock, fool's gold) on every stage, into .tmp/rabbit/rock_mark_kinds.png
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'resources' / 'gfx' / 'effects'
NAME = 'conch_rabbit_tracks'
VANILLA = ROOT.parents[1] / 'extracted_resources' / 'resources' / 'gfx' / 'grid'

# Three drafts (user request 2026-11-10: on the rock itself, checked on every
# stage's rock). Each is (palette, rows), heading up and right across the
# rock's top face; the pairs are staggered so they never read as a pair of eyes.
DRAFTS = {
    # A: muddy prints, two hops, the hind feet long with a toe dot
    'A': ({'.': (0, 0, 0, 0), 'D': (58, 38, 22, 190), 'd': (58, 38, 22, 110)}, [
        "...........d.....",
        "..........DD.d...",
        "..........DD.DD..",
        "..........dD.DD..",
        "..............d..",
        "...........dd....",
        "..........dd.....",
        "..d..............",
        ".DD.d............",
        ".DD.DD...........",
        ".dD.DD...........",
        ".....d...........",
        "..dd.............",
        ".dd..............",
    ]),
    # B: pale dust prints, the same two hops
    'B': ({'.': (0, 0, 0, 0), 'D': (236, 226, 204, 150), 'd': (236, 226, 204, 85)}, [
        "...........d.....",
        "..........DD.d...",
        "..........DD.DD..",
        "..........dD.DD..",
        "..............d..",
        "...........dd....",
        "..........dd.....",
        "..d..............",
        ".DD.d............",
        ".DD.DD...........",
        ".dD.DD...........",
        ".....d...........",
        "..dd.............",
        ".dd..............",
    ]),
    # C: one larger muddy hop across the middle
    'C': ({'.': (0, 0, 0, 0), 'D': (58, 38, 22, 190), 'd': (58, 38, 22, 110)}, [
        "......d..d...",
        ".....DDd.DD..",
        ".....DDD.DDd.",
        ".....DDD.DDD.",
        ".....dDD.DDD.",
        "......dd.dDD.",
        ".........dd..",
        "....ddd......",
        "...ddd.......",
        ".............",
        "..ddd........",
        ".ddd.........",
    ]),
}
CHOSEN = 'A'
PALETTE, MARK = DRAFTS[CHOSEN]
# Where the mark's middle sits from the rock's grid position, in pixels: the
# rock's top face (its frames are drawn 17-20 pixels above the cell's middle).
OFFSET = (0, -6)

ANM2 = '''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="{name}.png" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="tracks" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="Tracks">
    <Animation Name="Tracks" FrameNum="1" Loop="false">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
          <Frame XPosition="{ox}" YPosition="{oy}" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" XCrop="0" YCrop="0" Width="{w}" Height="{h}" XPivot="{px}" YPivot="{py}" />
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>
  </Animations>
</AnimatedActor>
'''


def mark_image(draft=CHOSEN):
    palette, rows = DRAFTS[draft]
    width, height = len(rows[0]), len(rows)
    assert all(len(row) == width for row in rows), 'ragged rows'
    image = Image.new('RGBA', (width, height))
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            image.putpixel((x, y), palette[key])
    return image


def write_runtime():
    image = mark_image()
    image.save(OUT / f'{NAME}.png')
    (OUT / f'{NAME}.anm2').write_text(
        ANM2.format(name=NAME, w=image.width, h=image.height, px=image.width // 2, py=image.height // 2,
                    ox=OFFSET[0], oy=OFFSET[1]), encoding='utf-8')
    print(f'{NAME}: {image.width}x{image.height}')
    return image


def rock_frames():
    """{animation: [(crop box, draw offset)]} for the looks an ordinary rock and a tinted rock use."""
    root = ET.parse(VANILLA / 'grid_rock.anm2').getroot()
    frames = {}
    for anim in root.iter('Animation'):
        name = anim.get('Name')
        if name not in ('normal', 'alt', 'alt2', 'tinted', 'bombrock', 'spiked', 'foolsgold'):
            continue
        layer = next(la for la in anim.iter('LayerAnimation') if la.get('LayerId') == '0')
        frames[name] = []
        for f in layer.iter('Frame'):
            x, y, w, h = (int(f.get(k)) for k in ('XCrop', 'YCrop', 'Width', 'Height'))
            frames[name].append(((x, y, x + w, y + h), (int(f.get('XPosition')), int(f.get('YPosition')))))
    return frames


def preview():
    """Every stage's ordinary rock (its three normal looks; the alt looks belong
    to the alt rock, a different grid entity) plain, under each draft, and the
    stage's tinted rock for comparison."""
    frames = rock_frames()
    looks = list(range(len(frames['normal'])))
    drafts = sorted(DRAFTS)
    sheets = sorted(VANILLA.glob('rocks_*.png'))
    cell, label, gap = 36, 108, 8
    groups = ['plain'] + drafts
    width = label + len(groups) * (len(looks) * cell + gap) + cell
    image = Image.new('RGBA', (width, 20 + len(sheets) * cell), (52, 44, 40, 255))
    draw = ImageDraw.Draw(image)
    marks = {d: mark_image(d) for d in drafts}
    x = label
    for g in groups:
        draw.text((x + 2, 4), 'rock' if g == 'plain' else 'draft ' + g, fill=(240, 228, 200, 255))
        x += len(looks) * cell + gap
    draw.text((x + 2, 4), 'tinted', fill=(240, 228, 200, 255))
    for r, sheet_path in enumerate(sheets):
        sheet = Image.open(sheet_path).convert('RGBA')
        y0 = 20 + r * cell
        draw.text((4, y0 + 12), sheet_path.stem.replace('rocks_', ''), fill=(240, 228, 200, 255))
        x = label
        for g in groups:
            for i in looks:
                box, (dx, dy) = frames['normal'][i]
                tile = Image.new('RGBA', (cell, cell), (74, 62, 54, 255))
                tile.alpha_composite(sheet.crop(box), (18 + dx, 21 + dy))
                if g != 'plain':
                    mark = marks[g]
                    tile.alpha_composite(mark, (18 + OFFSET[0] - mark.width // 2, 21 + OFFSET[1] - mark.height // 2))
                image.alpha_composite(tile, (x, y0))
                x += cell
            x += gap
        box, (dx, dy) = frames['tinted'][0]
        tile = Image.new('RGBA', (cell, cell), (74, 62, 54, 255))
        tile.alpha_composite(sheet.crop(box), (18 + dx, 21 + dy))
        image.alpha_composite(tile, (x, y0))
    out = ROOT / '.tmp' / 'rabbit'
    out.mkdir(parents=True, exist_ok=True)
    image.resize((image.width * 3, image.height * 3), Image.NEAREST).save(out / 'rock_mark_preview.png')
    # a closer look at three stages
    rows = [0, 1, 12, 22]
    close = image.crop((0, 0, image.width, 20)).copy()
    strip = Image.new('RGBA', (image.width, 20 + len(rows) * cell), (52, 44, 40, 255))
    strip.alpha_composite(close, (0, 0))
    names = [p.stem.replace('rocks_', '') for p in sheets]
    for k, r in enumerate(rows):
        strip.alpha_composite(image.crop((0, 20 + r * cell, image.width, 20 + (r + 1) * cell)), (0, 20 + k * cell))
    strip.resize((strip.width * 5, strip.height * 5), Image.NEAREST).save(out / 'rock_mark_close.png')
    print('preview:', out / 'rock_mark_preview.png', f'{len(sheets)} stages x {len(looks)} looks;',
          'close-up:', [names[r] for r in rows])


# The obstacles a room's hidden rock can be (rabbit.lua's KINDS): each kind's
# grid_rock.anm2 animation and the frames it shows.
KIND_LOOKS = [('rock', 'normal', 0), ('rock', 'normal', 1), ('rock', 'normal', 2),
              ('alt', 'alt', 0), ('alt', 'alt', 1), ('alt', 'alt', 2), ('alt2', 'alt2', 0),
              ('bomb', 'bombrock', 0), ('spiked', 'spiked', 0),
              ('gold', 'foolsgold', 0), ('gold', 'foolsgold', 1), ('gold', 'foolsgold', 2)]


def preview_kinds():
    """The chosen draft on every obstacle kind of every stage, each plain then
    marked, with the stage's tinted rock last for comparison."""
    frames = rock_frames()
    mark = mark_image()
    sheets = sorted(VANILLA.glob('rocks_*.png'))
    cell, label = 36, 108
    columns = len(KIND_LOOKS) * 2 + 1
    image = Image.new('RGBA', (label + columns * cell, 20 + len(sheets) * cell), (52, 44, 40, 255))
    draw = ImageDraw.Draw(image)
    for c, (kind, anim, i) in enumerate(KIND_LOOKS):
        draw.text((label + 2 * c * cell + 2, 4), f'{kind}{i}', fill=(240, 228, 200, 255))
    draw.text((label + (columns - 1) * cell + 2, 4), 'tinted', fill=(240, 228, 200, 255))
    for r, sheet_path in enumerate(sheets):
        sheet = Image.open(sheet_path).convert('RGBA')
        y0 = 20 + r * cell
        draw.text((4, y0 + 12), sheet_path.stem.replace('rocks_', ''), fill=(240, 228, 200, 255))
        x = label
        for kind, anim, i in KIND_LOOKS:
            box, (dx, dy) = frames[anim][i]
            for marked in (False, True):
                tile = Image.new('RGBA', (cell, cell), (74, 62, 54, 255))
                tile.alpha_composite(sheet.crop(box), (18 + dx, 21 + dy))
                if marked:
                    tile.alpha_composite(mark, (18 + OFFSET[0] - mark.width // 2, 21 + OFFSET[1] - mark.height // 2))
                image.alpha_composite(tile, (x, y0))
                x += cell
        box, (dx, dy) = frames['tinted'][0]
        tile = Image.new('RGBA', (cell, cell), (74, 62, 54, 255))
        tile.alpha_composite(sheet.crop(box), (18 + dx, 21 + dy))
        image.alpha_composite(tile, (x, y0))
    out = ROOT / '.tmp' / 'rabbit'
    out.mkdir(parents=True, exist_ok=True)
    image.resize((image.width * 2, image.height * 2), Image.NEAREST).save(out / 'rock_mark_kinds.png')
    rows = [1, 3, 12, 22]
    strip = Image.new('RGBA', (image.width, 20 + len(rows) * cell), (52, 44, 40, 255))
    strip.alpha_composite(image.crop((0, 0, image.width, 20)), (0, 0))
    for k, r in enumerate(rows):
        strip.alpha_composite(image.crop((0, 20 + r * cell, image.width, 20 + (r + 1) * cell)), (0, 20 + k * cell))
    strip.resize((strip.width * 4, strip.height * 4), Image.NEAREST).save(out / 'rock_mark_kinds_close.png')
    print('kinds:', out / 'rock_mark_kinds.png', [sheets[r].stem for r in rows])


if __name__ == '__main__':
    write_runtime()
    if len(sys.argv) > 1 and sys.argv[1] == 'preview':
        preview()
    if len(sys.argv) > 1 and sys.argv[1] == 'kinds':
        preview_kinds()
