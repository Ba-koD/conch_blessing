"""Shows where 장승 stands at each door of a 1x1 room, with the 금줄 strung
between each pair and the room's minimap icon hanging from it, using the numbers in
scripts/items/collectibles/jangseung.lua and the vanilla basement backdrop,
door and minimap icon art read in place from extracted_resources (nothing is
copied).

World units map to sprite pixels at 26/40, with the room's centre (320, 280)
at the backdrop's centre; door slot positions are the wall cells' centres.

    python docs/previews/jangseung/placement.py

writes .tmp/jangseung/placement.png (four special rooms), placement_red.png
(the red ropes: red special rooms and the way to the ultra secret room) and
tags.png (every room's icon on the rope, as jangseung.lua picks and hangs it).
"""
import importlib.util
import math
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location('jangseung_author', Path(__file__).with_name('author.py'))
author = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(author)
VANILLA = ROOT.parents[1] / 'extracted_resources/resources/gfx'
EFFECTS = ROOT / 'resources/gfx/effects'
OUT = ROOT / '.tmp/jangseung'
SCALE = 26 / 40

source = (ROOT / 'scripts/items/collectibles/jangseung.lua').read_text(encoding='utf-8')
data = {k: float(v) for k, v in
        re.findall(r'^\s+(\w+) = (-?[\d.]+),', source.split('M.data = {')[1].split('\n}')[0], re.M)}

DOORS = {  # slot: wall cell centre (world), inward direction, door sprite rotation
    0: ((40, 280), (1, 0), -90),
    1: ((320, 120), (0, 1), 0),
    2: ((600, 280), (-1, 0), 90),
    3: ((320, 440), (0, -1), 180),
}
# each wall's frame and its flips, as jangseung.lua's frameOf picks them
VIEWS = {(0, 1): ('Top', False, False), (0, -1): ('Top', False, True),
         (-1, 0): ('Side', False, False), (1, 0): ('Side', True, False)}


def px(x, y):
    return 234 + (x - 320) * SCALE, 156 + (y - 280) * SCALE


# The game draws each quarter of the backdrop this many pixels in toward the
# room's middle: its wall-floor seam then lies at world 140 on the top wall,
# where a door's threshold is (the door itself is drawn 15 pixels in from its
# slot). Measured 2026-11-16 against the game; without it the walls came out
# 15 pixels too thick and every door hung below its seam.
BACKDROP_IN = 15


def backdrop():
    sheet = Image.open(VANILLA / 'backdrop/01_basement.png').convert('RGBA')
    quarter = sheet.crop((0, 0, 234, 156))
    room = Image.new('RGBA', (468, 312), (0, 0, 0, 255))
    k = BACKDROP_IN
    for img, (x, y) in ((quarter.transpose(Image.ROTATE_180), (234 - k, 156 - k)),
                        (quarter.transpose(Image.FLIP_TOP_BOTTOM), (k, 156 - k)),
                        (quarter.transpose(Image.FLIP_LEFT_RIGHT), (234 - k, k)),
                        (quarter, (k, k))):
        room.alpha_composite(img, (x, y))
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


def frames_of(anm2_path):
    """{animation: (image, pivot)} as the ANM2 crops its one sheet."""
    anm2 = Path(anm2_path).read_text(encoding='utf-8')
    sheet_name = re.search(r'Spritesheet Id="0" Path="([^"]+)"', anm2).group(1)
    sheet = Image.open(Path(anm2_path).parent / sheet_name).convert('RGBA')
    frames = {}
    for name, x, w, h, px_, py_ in re.findall(r'Animation Name="(\w+)".*?XCrop="(\d+)" YCrop="0" Width="(\d+)" '
                                            r'Height="(\d+)" XPivot="(\d+)" YPivot="(\d+)"', anm2, re.S):
        x, w, h = int(x), int(w), int(h)
        frames[name] = (sheet.crop((x, 0, x + w, h)), (int(px_), int(py_)))
    return frames


def minimap_icons():
    """{animation: 16x16 image} from the vanilla minimap_icons.anm2, read in place."""
    anm2 = (VANILLA / 'ui/minimap_icons.anm2').read_text(encoding='utf-8')
    sheet = Image.open(VANILLA / 'ui/minimap_icons.png').convert('RGBA')
    icons = {}
    for name, body in re.findall(r'<Animation Name="(\w+)".*?>(.*?)</Animation>', anm2, re.S):
        crop = re.search(r'XCrop="(\d+)" YCrop="(\d+)" Width="(\d+)" Height="(\d+)"', body)
        if crop:
            x, y, w, h = map(int, crop.groups())
            icons[name] = rimmed(sheet.crop((x, y, x + w, y + h)))
    return icons


def rimmed(icon):
    """The icon as jangseung.lua draws it: its own shape in solid straw one pixel
    out each way (rimR/G/B), then the icon over it."""
    straw = Image.new('RGBA', icon.size, (int(data['rimR']), int(data['rimG']), int(data['rimB']), 255))
    straw.putalpha(icon.getchannel('A'))
    out = Image.new('RGBA', icon.size)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        shifted = Image.new('RGBA', icon.size)
        shifted.paste(straw, (dx, dy))
        out.alpha_composite(shifted)
    out.alpha_composite(icon)
    return out


def flipped(entry, fx, fy):
    img, (px_, py_) = entry
    if fx:
        img, px_ = img.transpose(Image.FLIP_LEFT_RIGHT), img.width - px_
    if fy:
        img, py_ = img.transpose(Image.FLIP_TOP_BOTTOM), img.height - py_
    return img, (px_, py_)


# The default scene: four special rooms, one at each wall.
SPECIAL = {0: ('IconShop', False), 1: ('IconTreasureRoom', False), 2: ('IconBoss', False), 3: ('IconSacrificeRoom', False)}
# The red ropes: a Red Key's red treasure room and red shop, the ultra secret
# room's red door and the wall to dig toward it (a red route marker).
RED = {0: ('IconShop', True), 1: ('IconTreasureRoom', True), 2: ('IconUltraSecretRoom', True),
       3: ('IconUltraSecretRoom', True)}


def main(bottom=None, out_name=None, anm2_path=EFFECTS / 'conch_jangseung.anm2', tags=SPECIAL):
    """`bottom`: an optional (천하대장군, 지하여장군) pair of (image, pivot[, rotation])
    drawn at the bottom wall instead of the shipped view, for comparisons.
    `anm2_path`: the statue ANM2 to draw (the April Fools set, for one).
    `tags`: {slot: (minimap icon, red)} for the 금줄 at each door, or None."""
    room = backdrop()
    door = door_sprite()
    earth = Image.open(EFFECTS / 'conch_jangseung_ground.png').convert('RGBA')
    frames = frames_of(anm2_path)
    ropes = frames_of(EFFECTS / 'conch_jangseung_rope.anm2') if tags else {}
    icons = minimap_icons() if tags else {}
    boxes = author.icon_boxes()
    drawn, hung = [], []
    for slot, ((wx, wy), (ix, iy), turn) in DOORS.items():
        rot = math.degrees(math.atan2(iy, ix)) - 90
        place(room, earth, wx + ix * data['groundInset'], wy + iy * data['groundInset'], (52, 0), rot)
        # the game draws a door 15 pixels in from its slot (its sprite's Offset,
        # measured 2026-11-16), so the doorway reaches down to the pair's feet
        place(room, door, wx + ix * 15 / SCALE, wy + iy * 15 / SCALE, (32, 42), turn)
        sx, sy = -iy, ix
        spread, stand = data['spread'], data['stand']
        a = (wx + ix * stand + sx * spread, wy + iy * stand + sy * spread)
        b = (wx + ix * stand - sx * spread, wy + iy * stand - sy * spread)
        first = a[0] < b[0] if iy != 0 else a[1] < b[1]
        left, right = (a, b) if first else (b, a)
        view, fx, fy = VIEWS[(ix, iy)]
        pair = (flipped(frames['Cheonha' + view], fx, fy), flipped(frames['Jiha' + view], fx, fy))
        if bottom and slot == 3:
            pair = bottom
        drawn += [(left, pair[0]), (right, pair[1])]
        if tags and slot in tags and tags[slot][0]:  # a room with no icon gets no rope
            icon, red = tags[slot]
            hang = data['hang' + view]
            hung.append(((wx + ix * hang, wy + iy * hang), flipped(ropes['Rope' + view + ('Red' if red else '')], fx, fy),
                         author.icon_pixels(icons[icon], boxes[icon], view, fx if view == 'Side' else fy)))
    for (x, y), entry in sorted(drawn, key=lambda d: d[0][1]):  # depth by Y, like entities
        sprite, pivot = entry[0], entry[1]
        place(room, sprite, x, y, pivot, entry[2] if len(entry) > 2 else 0)
    for (x, y), entry, pixels in hung:  # the rope draws over everything (jangseung.lua's DepthOffset)
        place(room, entry[0], x, y, entry[1])
        hx, hy = px(x, y)
        hx, hy = round(hx - entry[1][0]) + entry[1][0], round(hy - entry[1][1]) + entry[1][1]  # the hook, as place puts it
        for (dx, dy), colour in pixels.items():  # turned with the wall, its top toward the rope
            if 0 <= hx + dx < room.width and 0 <= hy + dy < room.height:
                room.putpixel((hx + dx, hy + dy), colour)
    OUT.mkdir(parents=True, exist_ok=True)
    big = room.resize((room.width * 3, room.height * 3), Image.NEAREST)
    big.save(OUT / (out_name or 'placement.png'))
    print(OUT / (out_name or 'placement.png'))
    return room


def tag_gallery():
    """Every room's icon hanging from the middle of the top wall's rope, plain and
    red, in jangseung.lua's order."""
    lua = (ROOT / 'scripts/items/collectibles/jangseung.lua').read_text(encoding='utf-8')
    names = re.findall(r'^\s+ROOM_\w+ = "(Icon\w+)"', lua.split('local ICONS = {')[1].split('\n}')[0], re.M)
    names = list(dict.fromkeys(names + ['IconTreasureRoomRed', 'IconBossAmbushRoom']))
    ropes, icons, boxes = frames_of(EFFECTS / 'conch_jangseung_rope.anm2'), minimap_icons(), author.icon_boxes()
    cell, half = 30, 14
    out = Image.new('RGBA', (cell * len(names) + 4, cell * 2 + 4), (74, 56, 48, 255))
    for row, red in enumerate((False, True)):
        for i, name in enumerate(names):
            rope, (rx, ry) = ropes['RopeTop' + ('Red' if red else '')]
            piece = rope.crop((rx - half, 0, rx + half, rope.height))
            x, y = 2 + i * cell + cell // 2, 2 + row * cell + 18
            out.alpha_composite(piece, (x - half, y - ry))
            for (dx, dy), colour in author.icon_pixels(icons[name], boxes[name], 'Top', False).items():
                out.putpixel((x + dx, y + dy), colour)
    out.resize((out.width * 4, out.height * 4), Image.NEAREST).save(OUT / 'tags.png')
    print(OUT / 'tags.png', names)


if __name__ == '__main__':
    main()
    main(out_name='placement_red.png', tags=RED)
    tag_gallery()
