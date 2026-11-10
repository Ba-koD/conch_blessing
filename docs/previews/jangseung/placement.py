"""Shows where 장승 stands at each door of a 1x1 room, using the numbers in
scripts/items/collectibles/jangseung.lua and the vanilla basement backdrop
and door art read in place from extracted_resources (nothing is copied).

World units map to sprite pixels at 26/40, with the room's centre (320, 280)
at the backdrop's centre; door slot positions are the wall cells' centres.

    python docs/previews/jangseung/placement.py
"""
import math
import re
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
VANILLA = ROOT.parents[1] / 'extracted_resources/resources/gfx'
OUT = ROOT / '.tmp/jangseung'
SCALE = 26 / 40

source = (ROOT / 'scripts/items/collectibles/jangseung.lua').read_text(encoding='utf-8')
data = {k: float(v) for k, v in re.findall(r'^\s+(\w+) = ([\d.]+),', source.split('M.data = {')[1].split('}')[0], re.M)}

DOORS = {  # slot: wall cell centre (world), inward direction, door sprite rotation
    0: ((40, 280), (1, 0), -90),
    1: ((320, 120), (0, 1), 0),
    2: ((600, 280), (-1, 0), 90),
    3: ((320, 440), (0, -1), 180),
}


def px(x, y):
    return 234 + (x - 320) * SCALE, 156 + (y - 280) * SCALE


def backdrop():
    sheet = Image.open(VANILLA / 'backdrop/01_basement.png').convert('RGBA')
    quarter = sheet.crop((0, 0, 234, 156))
    room = Image.new('RGBA', (468, 312))
    room.paste(quarter, (0, 0))
    room.paste(quarter.transpose(Image.FLIP_LEFT_RIGHT), (234, 0))
    room.paste(quarter.transpose(Image.FLIP_TOP_BOTTOM), (0, 156))
    room.paste(quarter.transpose(Image.ROTATE_180), (234, 156))
    return room


def door_sprite():
    sheet = Image.open(VANILLA / 'grid/door_01_normaldoor.png').convert('RGBA')
    frame = Image.new('RGBA', (64, 48))
    frame.alpha_composite(sheet.crop((64, 0, 128, 48)))   # background (opened)
    frame.alpha_composite(sheet.crop((0, 0, 64, 48)))     # frame
    return frame


def place(canvas, sprite, x, y, pivot, rotation=0):
    """Draws `sprite` with its `pivot` at world (x, y), turned clockwise."""
    px0, py0 = px(x, y)
    if rotation:
        # turn about the pivot: pad so the pivot is the centre, then rotate
        w, h = sprite.size
        size = int(2 * max(pivot[0], w - pivot[0], pivot[1], h - pivot[1])) + 2
        pad = Image.new('RGBA', (size, size))
        pad.alpha_composite(sprite, (size // 2 - pivot[0], size // 2 - pivot[1]))
        sprite = pad.rotate(-rotation, resample=Image.NEAREST)
        pivot = (size // 2, size // 2)
    canvas.alpha_composite(sprite, (round(px0 - pivot[0]), round(py0 - pivot[1])))


def main(bottom=None, out_name=None, anm2_path=ROOT / 'resources/gfx/effects/conch_jangseung.anm2'):
    """`bottom`: an optional (천하대장군, 지하여장군) pair of (image, pivot[, rotation])
    drawn at the bottom wall instead of the shipped view, for comparisons.
    `anm2_path`: the statue ANM2 to draw (the April Fools set, for one)."""
    room = backdrop()
    door = door_sprite()
    anm2 = Path(anm2_path).read_text(encoding='utf-8')
    sheet_name = re.search(r'Spritesheet Id="0" Path="([^"]+)"', anm2).group(1)
    statues = Image.open(Path(anm2_path).parent / sheet_name).convert('RGBA')
    earth = Image.open(ROOT / 'resources/gfx/effects/conch_jangseung_ground.png').convert('RGBA')
    # the frames as the ANM2 crops them, with their own sizes and pivots
    frames = {}
    for name, x, w, h, px_, py_ in re.findall(r'Animation Name="(\w+)".*?XCrop="(\d+)" YCrop="0" Width="(\d+)" '
                                            r'Height="(\d+)" XPivot="(\d+)" YPivot="(\d+)"', anm2, re.S):
        x, w, h = int(x), int(w), int(h)
        frames[name] = (statues.crop((x, 0, x + w, h)), (int(px_), int(py_)))

    # each wall's frame and its flips, as jangseung.lua's frameOf picks them
    views = {(0, 1): ('Top', False, False), (0, -1): ('Top', False, True),
             (-1, 0): ('Side', False, False), (1, 0): ('Side', True, False)}

    def flipped(entry, fx, fy):
        img, (px_, py_) = entry
        if fx:
            img, px_ = img.transpose(Image.FLIP_LEFT_RIGHT), img.width - 1 - px_
        if fy:
            img, py_ = img.transpose(Image.FLIP_TOP_BOTTOM), img.height - 1 - py_
        return img, (px_, py_)
    drawn = []
    for slot, ((wx, wy), (ix, iy), turn) in DOORS.items():
        rot = math.degrees(math.atan2(iy, ix)) - 90
        place(room, earth, wx + ix * data['groundInset'], wy + iy * data['groundInset'], (52, 0), rot)
        place(room, door, wx, wy, (32, 42), turn)
        sx, sy = -iy, ix
        spread, stand = data['spread'], data['stand']
        a = (wx + ix * stand + sx * spread, wy + iy * stand + sy * spread)
        b = (wx + ix * stand - sx * spread, wy + iy * stand - sy * spread)
        first = a[0] < b[0] if iy != 0 else a[1] < b[1]
        left, right = (a, b) if first else (b, a)
        view, fx, fy = views[(ix, iy)]
        pair = (flipped(frames['Cheonha' + view], fx, fy), flipped(frames['Jiha' + view], fx, fy))
        drawn += [(left, pair[0]), (right, pair[1])]
    for (x, y), entry in sorted(drawn, key=lambda d: d[0][1]):  # depth by Y, like entities
        sprite, pivot = entry[0], entry[1]
        place(room, sprite, x, y, pivot, entry[2] if len(entry) > 2 else 0)
    OUT.mkdir(parents=True, exist_ok=True)
    big = room.resize((room.width * 3, room.height * 3), Image.NEAREST)
    big.save(OUT / (out_name or 'placement.png'))
    print(OUT / (out_name or 'placement.png'), data)


if __name__ == '__main__':
    main()
