"""Builds 장승's art: the pair of statues, the 금줄 strung between them, the
trodden earth and the item icon.

Authored directly on the native grid (AGENTS.md: no larger concept resized
down). The statues are wooden posts as they stand at a village mouth, seen as
each wall shows them (see the block above `CHEONHA_HEAD`): 천하대장군 with a
winged official's cap, round bulging eyes under angry brows, a fist nose, bared
teeth with tusks and a carved beard; 지하여장군 with a topknot, round eyes, red
cheeks and lips. Below the face each post carries its name as carved marks.
A 금줄 is strung between the pair's heads across the door (see `rope_frame`),
with the room's own minimap icon hanging from its middle on a short string. The earth is a half circle two tiles (80 world units) in radius, half
transparent so it darkens whatever floor it lies on: packed village dirt with
a wandering rim, a trodden path, pebbles and hairline cracks. The icon is the
two front statues, cut short to fit.

Run from the repository root; it writes the runtime PNGs and ANM2 files and a
preview under .tmp/jangseung:

    python docs/previews/jangseung/author.py
"""
import math
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
EFFECTS = ROOT / 'resources/gfx/effects'
ICON = ROOT / 'resources/gfx/items/collectibles/jangseung.png'
PREVIEW = ROOT / '.tmp/jangseung'
LUA = ROOT / 'scripts/items/collectibles/jangseung.lua'
SCALE = 26 / 40  # world units to screen pixels


def lua_data():
    """jangseung.lua's M.data numbers: where the game stands the pair and hangs the rope."""
    block = LUA.read_text(encoding='utf-8').split('M.data = {')[1].split('\n}')[0]
    return {k: float(v) for k, v in re.findall(r'^\s+(\w+) = (-?[\d.]+),', block, re.M)}

PALETTE = {
    '.': None,
    'K': (30, 22, 20, 255),     # outline
    'H': (40, 36, 44, 255),     # hat
    'h': (86, 80, 96, 255),     # hat highlight
    'g': (62, 58, 72, 255),     # hat, half lit
    'i': (118, 110, 132, 255),  # hat, brightest
    'W': (92, 60, 40, 255),     # wood shadow
    'M': (138, 96, 60, 255),    # wood
    'L': (178, 132, 84, 255),   # wood lit
    'S': (210, 170, 116, 255),  # wood highlight
    'D': (74, 48, 32, 255),     # wood, the core of the shadow (the top wall's rounded posts)
    'E': (238, 230, 208, 255),  # eye white, fangs
    'e': (190, 182, 164, 255),  # eye white and teeth in shadow
    'T': (70, 44, 30, 255),     # carved marks
    'R': (178, 46, 38, 255),    # cheeks, lips
    'r': (122, 30, 28, 255),    # red shadow
    'o': (214, 96, 72, 255),    # red light
}

# 장승 as the room's own camera shows it against each wall (user decisions
# 2026-11-10): docs/previews/jangseung/model3d.py builds the statues as solids,
# stands each one against its wall and renders the room from above its middle;
# the top wall's pair was then finished by hand on the pixel grid below, with
# a little of the render's light (user request): the cap's crown lit at its
# upper left and shaded toward the lower right, the post lit on its left and
# in shadow down its right side, darker toward the foot, and the eye whites
# and teeth shaded at their lower right. The bottom wall's pair is the top
# wall's upside down; the right wall's is drawn for that wall (see
# CHEONHA_SIDE) and the left wall's is that mirrored. The faces are fierce like carved 장승 (user correction): round
# bulging eyes under angry brows, a fist nose, bared teeth with corner tusks
# and a carved beard for 천하대장군; round eyes, red cheeks and lips and small
# fangs for 지하여장군. The upright front heads below are kept for the item
# icon and scene3d.py's model.

# 천하대장군 standing, from the front (icon and 3D model).
CHEONHA_HEAD = [
    ".....KKKKKKKK.....",
    "....KHhhHHHHHK....",
    "....KHhHHHHHHK....",
    "....KHHHHHHHHK....",
    "KKKKKHHHHHHHHKKKKK",
    "KhhhKHHHHHHHHKHHHK",
    "KKKKKHHHHHHHHKKKKK",
    "..KKKKKKKKKKKKKK..",
    "..KSLLLLLLLLMMWK..",
    "..KKKLLLLLLMMKKK..",
    "..KLLKKKLMKKKMWK..",
    "..KLEEEKLMKEEEWK..",
    "..KLEKKELMEKKEWK..",
    "..KLEKKELMEKKEWK..",
    "..KLEEEELMEEEEWK..",
    "..KLKKKKLMKKKKWK..",
    "..KSLLKSLLMKMMWK..",
    "..KLLLKLLMMKMMWK..",
    "..KLLKKKMMKKKMWK..",
    "..KLLLLLMMMMMMWK..",
    "..KLKKKKKKKKKKWK..",
    "..KKEEKEEEEKEEKK..",
    "..KEKKKKKKKKKKEK..",
    "..KEKKKKKKKKKKEK..",
    "..KLLKKKKKKKKMWK..",
    "..KLLWLWLLWLWMWK..",
    "..KSLWLWLLWLWMWK..",
    "..KLLLWLLLLWMMWK..",
]

# 지하여장군 standing, from the front (icon and 3D model).
JIHA_HEAD = [
    "..................",
    ".......KKKK.......",
    "......KHhHHK......",
    "......KHHHHK......",
    ".......KKKK.......",
    ".....KKKKKKKK.....",
    "....KHhHHHHHHK....",
    "...KHhHHHHHHHHK...",
    "..KHhHHHHHHHHHHK..",
    "..KHSLLLLLLLLMHK..",
    "..KHLKKKLLKKKMHK..",
    "..KLKEEKLMKEEKWK..",
    "..KLEKKELMEKKEWK..",
    "..KLEKKELMEKKEWK..",
    "..KLKEEKLMKEEKWK..",
    "..KRRLLLLMMMRRWK..",
    "..KRLLKSLLKMMRWK..",
    "..KLLLKLLMKMMMWK..",
    "..KLLLKKMKKMMMWK..",
    "..KLLLLLMMMMMMWK..",
    "..KLLKKKKKKKKMWK..",
    "..KLLKEKKKKEKMWK..",
    "..KLLKRRRRRRKMWK..",
    "..KLLLKKKKKKMMWK..",
    "..KSLLLLMMMMMMWK..",
    "..KLLLLLMMMMMMWK..",
]

# 천하대장군 standing against the top wall, seen from the room's camera above
# (hand-finished on the pixel grid from model3d.py's render, user decision
# 2026-11-10): the winged cap's crown seen from above with the wings behind
# it, the head's top showing round the crown, then the face (angry brows,
# round bulging eyes, fist nose, bared teeth with corner tusks, carved beard)
# and the post down to its foot, nearest the room's middle.
CHEONHA_WALL = [
    "..........KKKKKKK..........",
    "........KKiiihhhhKK........",
    ".......KiiihhhhhhhgK.......",
    "......KhiihhhhhhhhggK......",
    "KKKKKKKhhhhhhhhhhhggKKKKKKK",
    "KhhgHHKhhhhhhhhhhhggKHHHHHK",
    "KKKKKKKhhhhhhhhhhgggKKKKKKK",
    "......KghhhhhhhhhggHK......",
    "......KHgghhhhhhggHHK......",
    "......KHHHggggggHHHHK......",
    ".....KLHHHHHHHHHHHHHMK.....",
    ".....KLLHHHHHHHHHHHLMK.....",
    ".....KLLLHHHHHHHHHLDWK.....",
    ".....KLLLLKKKKKKKLLDWK.....",
    ".....KLSSLLLLLLLLLLDWK.....",
    ".....KKKKLLLLLLLLLKKKK.....",
    ".....KLLKKKKLLLKKKKDWK.....",
    ".....KKEEEKKLLLKKEEEKK.....",
    ".....KKEKKEKLMLKEKKEKK.....",
    ".....KKEKKeKLMLKEKKeKK.....",
    ".....KKEEEeKLMLKEEEeKK.....",
    ".....KLKKKKLLMLLKKKKWK.....",
    ".....KLSLLKSLLLMKLMDWK.....",
    ".....KLSLKSLLLLMWKMDWK.....",
    ".....KLSLKKKLMLKKKMDWK.....",
    ".....KLKKKKKKKKKKKKKWK.....",
    ".....KLKEEKEEEEeKEEKWK.....",
    ".....KLKEKKKKKKKKKEKWK.....",
    ".....KLKEKKKKKKKKKeKWK.....",
    ".....KLLKKKKKKKKKKKDWK.....",
    ".....KLSLTLTLLLTMTMDWK.....",
    ".....KLSLTLTLLLTMTMDWK.....",
    ".....KLSLLTLLLLLTMMDWK.....",
    ".....KMLLLLTTMMMMMWDWK.....",
    ".....KMLLLLMTMMMMMWDWK.....",
    ".....KMLLLTTMMMMMMWDWK.....",
    "......KMLLLMTMMMMWDWK......",
    ".......KMLLTTMMMWDWK.......",
    "........KKKKKKKKKKK........",
]

# 지하여장군 against the top wall, from the same camera: the topknot and the
# crown of her hair seen from above, the hairline, then her face (gentle
# arched brows, round eyes, red cheeks, small fangs, red lips) and the post.
JIHA_WALL = [
    ".........KKK.........",
    "........KihhK........",
    "........KhgHK........",
    "......KKKKKKKKK......",
    "....KKiihhhhhhgKK....",
    "...KiiihhhhhhhhggK...",
    "..KhiihhhhhhhhhhgHK..",
    "..KhhhhhhhhhhhhhgHK..",
    "..KghhhhhhhhhhhggHK..",
    "..KHgghhhhhhhggHHHK..",
    "..KHHHgggggggHHHHHK..",
    "..KHSLLLLLLLLLLLHHK..",
    "..KHLKKKLLLLLKKKMHK..",
    "..KLLKEEKLLLKEEKDWK..",
    "..KLKEKKEKLKEKKEKWK..",
    "..KLKEKKeKLKEKKeKWK..",
    "..KLLKEeKLLLKEeKDWK..",
    "..KRRLLLKSLMKLLRrWK..",
    "..KLSLLLKKMKKLLMDWK..",
    "..KLSLKKKKKKKKKMDWK..",
    "..KLSLKEKKKKKeKMDWK..",
    "..KLSLLoRRRRRrMMDWK..",
    "..KLSLLLLMMMMMMMDWK..",
    "..KLSLLTTMMMMMMMDWK..",
    "..KLSLLLTMMMMMMMDWK..",
    "..KMSLLTTMMMMMMWDWK..",
    "..KMSLLLTMMMMMMWDWK..",
    "..KMLLLTTMMMMMMWDWK..",
    "...KMLLTTMMMMMWDWK...",
    "....KMLLTMMMMWDWK....",
    ".....KKKKKKKKKKK.....",
]

# The right wall's pair, drawn for that wall (user correction 2026-11-10: the
# top wall's picture turned and lengthened did not match the 3D render). Drawn
# here cap up, foot down, and turned a quarter clockwise into the game's frame
# (cap to the right, against the wall). From above, a post standing against a
# side wall is seen along its height, so, as in model3d.py's render, its cap
# end (nearest the camera) is the biggest part: the cap's crown is a full round
# disc two pixels wider than the post, lit at its lower left here (the upper
# left once turned), and the face is drawn longer (an extra forehead, nose,
# mouth and beard row). The post keeps one thickness from the band to the foot
# (user correction: narrowing it toward the foot, with a waist under the crown,
# made it look bent and thick in the middle), so both its edges stay straight
# once it is slanted (SIDE_STEPS below).
CHEONHA_SIDE = [
    "..........KKKKKKK..........",
    "........KKHHHHHHHKK........",
    "......KKHHHHHHHHHHHKK......",
    ".....KgHHHHHHHHHHHHHHK.....",
    "....KghhHHHHHHHHHHHHHHK....",
    "KKKKKghhhhHHHHHHHHHHHHKKKKK",
    "KhhgKhhhhhhhHHHHHHHHHHKHHHK",
    "KKKKKhhhhhhhhhHHHHHHHHKKKKK",
    "....KhhhhhhhhhhhhgHHHHK....",
    "....KihhhhhhhhhhhhgHHHK....",
    "....KiihhhhhhhhhhhhgHHK....",
    "....KiiihhhhhhhhhhhggHK....",
    "....KiiihhhhhhhhhhhhggK....",
    ".....KiihhhhhhhhhhhggK.....",
    ".....KKKKKKKKKKKKKKKKK.....",
    ".....KLHHHHHHHHHHHHHMK.....",
    ".....KLLHHHHHHHHHHHLMK.....",
    ".....KLLLHHHHHHHHHLMWK.....",
    ".....KLLLLKKKKKKKLLMWK.....",
    ".....KLSSLLLLLLLLLLMWK.....",
    ".....KLSLLLLLLLLLLLMWK.....",
    ".....KLLLLLLLLLLLLLMWK.....",
    ".....KKKKLLLLLLLLLKKKK.....",
    ".....KLLKKKKLLLKKKKMWK.....",
    ".....KKEEEKKLLLKKEEEKK.....",
    ".....KKEKKEKLMLKEKKEKK.....",
    ".....KKEKKeKLMLKEKKeKK.....",
    ".....KKEEEeKLMLKEEEeKK.....",
    ".....KLKKKKLLMLLKKKKWK.....",
    ".....KLLLLKSLLLMKLMMWK.....",
    ".....KLLLKSLLLLMWKMMWK.....",
    ".....KLLLKSLLLLMWKMMWK.....",
    ".....KLLLKSLLLLMWKMMWK.....",
    ".....KLLLKKKLMLKKKMMWK.....",
    ".....KLKKKKKKKKKKKKKWK.....",
    ".....KLKEEKEEEEeKEEKWK.....",
    ".....KLKEKKKKKKKKKEKWK.....",
    ".....KLKEKKKKKKKKKEKWK.....",
    ".....KLKEKKKKKKKKKeKWK.....",
    ".....KLLKKKKKKKKKKKMWK.....",
    ".....KLLLTLTLLLTMTMWWK.....",
    ".....KLLLTLTLLLTMTMWWK.....",
    ".....KLLLTLTLLLTMTMWWK.....",
    ".....KLLLTLTLLLTMTMWWK.....",
    ".....KLLLLTLLLLLTMMWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLTTMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLTTMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLTTMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLTTMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    ".....KMLLLLLMMMMMMWWWK.....",
    "......KMLLLLMMMMMWWWK......",
    ".......KKKKKKKKKKKKK.......",
]

JIHA_SIDE = [
    ".........KKK.........",
    "........KHHHK........",
    "........KhgHK........",
    "......KKKKKKKKK......",
    "....KKgHHHHHHHHKK....",
    "...KghhHHHHHHHHHHK...",
    "..KghhhhHHHHHHHHHHK..",
    ".KghhhhhhHHHHHHHHHHK.",
    ".KhhhhhhhhhhhgHHHHHK.",
    ".KihhhhhhhhhhhgHHHHK.",
    ".KiihhhhhhhhhhhgHHHK.",
    ".KiiihhhhhhhhhhhgHHK.",
    ".KiiihhhhhhhhhhhggHK.",
    ".KHiiihhhhhhhhhhggHK.",
    "..KHiihhhhhhhhggHHK..",
    "..KHHHgggggggHHHHHK..",
    "..KHSLLLLLLLLLLLHHK..",
    "..KHLLLLLLLLLLLLMHK..",
    "..KHLKKKLLLLLKKKMHK..",
    "..KLLKEEKLLLKEEKMWK..",
    "..KLKEKKEKLKEKKEKWK..",
    "..KLKEKKeKLKEKKeKWK..",
    "..KLLKEeKLLLKEeKMWK..",
    "..KLLLLLLLLLLLLLMWK..",
    "..KLLLLLLLLLLLLLMWK..",
    "..KRRLLLKSLMKLLRrWK..",
    "..KRRLLLKSLMKLLRrWK..",
    "..KRRLLLKSLMKLLRrWK..",
    "..KLLLLLKKMKKLLMMWK..",
    "..KLLLKKKKKKKKKMMWK..",
    "..KLLLKEKKKKKeKMMWK..",
    "..KLLLKEKKKKKeKMMWK..",
    "..KLLLKKKKKKKKKMMWK..",
    "..KLLLLoRRRRRrMMWWK..",
    "..KLLLLLLMMMMMMMWWK..",
    "..KLLLLLLMMMMMMMWWK..",
    "..KLLLLLLMMMMMMMWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLTTMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLTTMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLTTMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLTTMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "..KMLLLLLMMMMMMWWWK..",
    "...KMLLLLMMMMMWWWK...",
    "....KKKKKKKKKKKKK....",
]

# The slant (user corrections 2026-11-10: the angle should match the render,
# and bend as much at the head as at the foot). Seen from above the room's
# middle, the pair on a side wall leans in toward the door from the cap to the
# foot, 천하대장군 (the upper one) down and 지하여장군 (the lower one) up,
# about one pixel in eight or nine. Each step is a map row where the post
# moves one pixel further, spaced evenly from the cap's end to the foot: the
# crown and hair discs take steps too (a disc stepped once or twice reads as
# tilted), while no step falls inside an eye, a nose, a fang or a lid.
SIDE_STEPS = {'Cheonha': ((4, 12, 20, 29, 37, 45, 53), 1), 'Jiha': ((6, 13, 19, 25, 34, 41, 48), -1)}


# The top wall's pair leans with the wall's view angle (user request
# 2026-11-16: "built into the wall", the side walls kept as they are): the
# doorway between them narrows toward the room, so each post leans out at its
# cap, 천하대장군 (on the left) to the left and 지하여장군 to the right, about one
# pixel in five. Each step is a row above which the post sits one pixel
# further out. The steps run evenly from the base's bottom to the cap's top,
# four or five rows apart, so the post rises in one straight line (user
# correction: steps only between the face's bands, with none in the base, bent
# it), and each falls between the picture's bands or inside a smooth one (the
# cap, the hair, the carved name), never through an eye, a nose or the teeth.
# The bottom wall draws this upside down.
TOP_STEPS = {'Cheonha': ((4, 9, 13, 17, 21, 25, 30, 34), -1), 'Jiha': ((3, 8, 12, 17, 22, 27), 1)}


def lean_offsets(height, steps, sign):
    """How far right each row of a leaning frame is drawn: each row above a
    step one pixel further out (sign -1 to the left, 1 to the right)."""
    n = len(steps)
    shifts = [sum(1 for s in steps if y < s) for y in range(height)]
    return [n - s if sign < 0 else s for s in shifts]


def lean(rows, steps, sign):
    """Leans a top-wall frame. Returns the rows and each row's offset."""
    n = len(steps)
    offsets = lean_offsets(len(rows), steps, sign)
    return ['.' * o + row + '.' * (n - o) for o, row in zip(offsets, rows)], offsets


def lean_image(img, steps, sign):
    """The same lean on a picture of the unleaned frame (the April Fools
    sheet's renders, docs/previews/aprilfools/actors.py)."""
    offsets = lean_offsets(img.height, steps, sign)
    out = Image.new('RGBA', (img.width + len(steps), img.height))
    for y, o in enumerate(offsets):
        out.paste(img.crop((0, y, img.width, y + 1)), (o, y))
    return out


def wall_rows(who):
    rows = list(CHEONHA_WALL if who == 'Cheonha' else JIHA_WALL)
    assert all(len(r) == len(rows[0]) for r in rows), (who, [len(r) for r in rows])
    return rows


def slant(rows, steps, sign, foot_x=5):
    """Leans a turned side frame: each column left of a step sits one pixel
    lower (sign 1) or higher (sign -1) than the columns right of it. Returns
    the rows and the foot pixel (foot_x, the post's middle at that column)."""
    h, w, n = len(rows), len(rows[0]), len(steps)

    def drop(x):
        before = sum(1 for s in steps if x < s)
        return before if sign > 0 else n - before
    out = [['.'] * w for _ in range(h + n)]
    for x in range(w):
        for y in range(h):
            out[y + drop(x)][x] = rows[y][x]
    return [''.join(r) for r in out], (foot_x, h // 2 + drop(foot_x))


def turn_cw(rows):
    """The picture turned a quarter clockwise: its top (the cap) to the right."""
    h, w = len(rows), len(rows[0])
    return [''.join(rows[h - 1 - y][x] for y in range(h)) for x in range(w)]


def wall_frame(who, side=False):
    """(image, foot pixel): the top wall's view, or the right wall's (its cap
    to the right); the game mirrors these for the bottom and left walls."""
    if side:
        rows = list(CHEONHA_SIDE if who == 'Cheonha' else JIHA_SIDE)
        starts, sign = SIDE_STEPS[who]
        rows, foot = slant(turn_cw(rows), tuple(len(rows) - r for r in starts), sign)
        return paint(rows), foot
    rows = wall_rows(who)
    width = len(rows[0])
    steps, sign = TOP_STEPS[who]
    rows, offsets = lean(rows, steps, sign)
    # the foot (the post's base centre) sits a little above the outline's
    # lowest point, which is the base's near edge (model3d.py)
    foot = len(rows) - 6
    return paint(rows), (width // 2 + offsets[foot], foot)


# Each view: (width, height, post's right outline column, heads)
SIZES = {'Upright': (18, 40, 15)}
HEADS = {
    'Upright': (CHEONHA_HEAD, JIHA_HEAD),
}
# 天下大將軍 / 地下女將軍 as carved characters: two rows of strokes and a gap each
CHARACTER = [('T', 'T'), ('M', 'T'), ('M', 'M')]


def body(width, post_right, first, rows, carved=True):
    """The post below a head: lit on the left, shaded on the right, its name
    carved down its face, ending in a dark foot."""
    n = post_right - 3
    lit = max(2, round(n * 0.35))
    out = []
    for i in range(rows - 2):
        y = first + i
        inner = ['S' if j == 0 and y % 4 == 0 else 'L' if j < lit else 'W' if j == n - 1 else 'M' for j in range(n)]
        if carved and i < 15:
            a, b = CHARACTER[i % 3]
            inner[n // 2 - 1], inner[n // 2] = a, b
        out.append('..K' + ''.join(inner) + 'K' + '.' * (width - post_right - 1))
    out.append('..K' + 'W' * n + 'K' + '.' * (width - post_right - 1))
    out.append('...' + 'K' * n + '.' * (width - 3 - n))
    return out


def statue(view, who):
    width, height, post_right = SIZES[view]
    head = HEADS[view][0 if who == 'Cheonha' else 1]
    rows = list(head) + body(width, post_right, len(head), height - len(head))
    assert len(rows) == height and all(len(r) == width for r in rows), (view, who, [len(r) for r in rows])
    return paint(rows)


def plain_post(width=18, height=40):
    """A bare post of the same wood (the 3D model's sides and back)."""
    return paint(['..K' + 'L' * 4 + 'M' * 7 + 'W' + 'K..'] * (height - 2)
                 + ['..K' + 'W' * 12 + 'K..', '...' + 'K' * 12 + '...'])


def paint(rows):
    img = Image.new('RGBA', (len(rows[0]), len(rows)))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            colour = PALETTE[ch]
            if colour:
                img.putpixel((x, y), colour)
    return img


# Runtime frames: each statue's top-wall and right-wall views. (The red-route
# pair's red cloth went on 2026-11-15: the 금줄 between the pair marks it now.)
NAMES = [f'{who}{view}' for view in ('Top', 'Side') for who in ('Cheonha', 'Jiha')]


def statues():
    frames = []
    for name in NAMES:
        who = 'Cheonha' if name.startswith('Cheonha') else 'Jiha'
        frames.append(wall_frame(who, 'Side' in name))
    sheet = Image.new('RGBA', (sum(f.width for f, _ in frames), max(f.height for f, _ in frames)))
    x = 0
    for frame, _ in frames:
        sheet.paste(frame, (x, 0))
        x += frame.width
    return frames, sheet


def statue_anm2(frames, sheet='conch_jangseung.png'):
    anims, x = [], 0
    for name, (frame, pivot) in zip(NAMES, frames):
        w, h = frame.size
        anims.append(f'''    <Animation Name="{name}" FrameNum="1" Loop="false">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
          <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" XCrop="{x}" YCrop="0" Width="{w}" Height="{h}" XPivot="{pivot[0]}" YPivot="{pivot[1]}" />
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>''')
        x += w
    return f'''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="{sheet}" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="statue" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="CheonhaTop">
{chr(10).join(anims)}
  </Animations>
</AnimatedActor>
'''


# ------------------------------------------------------------------ the 금줄

# The 금줄 strung between the pair across the door (user request 2026-11-15,
# replacing the red-route pair's red cloth): a twisted straw rope tied round
# each post high on the head, sagging a little toward the room's middle
# (from the room's camera above, "down" points that way, as the caps point at
# the wall), with a red pepper and a lump of charcoal hung near each post, and
# in its middle a short straw string from which the room's own minimap icon
# hangs, turned with its wall so its top faces the rope (jangseung.lua draws
# it; a room with no icon gets no rope). No paper tag behind the
# icon and nothing else in front of the doorway, so the door stays in sight
# (user request 2026-11-16). The red rope, straw twisted with red, marks a way a
# Red Key opened or opens: a red special room, the ultra secret room and the
# wall to dig toward it.
#
# The rope is drawn in (along, down) pixels: `along` runs with the wall,
# 천하대장군's end first, and `down` from the wall into the room, both from the
# hook, the pixel the icon's near edge hangs on at the string's end, whose
# corner is each frame's pivot. jangseung.lua stands that pivot `hangTop` or
# `hangSide` world units in from the wall's middle, half way between the pair;
# the game mirrors the top frame for the bottom wall and the side frame for the
# left wall, as it does the statues, which only flips `down`.
# Tied high, round the cap's band and the top of the hair, and drawn two
# pixels thick with a small sag: the game draws a door 15 pixels in from its
# slot, so the doorway reaches down to the pair's feet, and a rope tied lower
# or thicker hid most of it (user report 2026-11-16).
TOP_TIE_ROWS = {'Cheonha': 8, 'Jiha': 3}
SIDE_TIE_COLS = {'Cheonha': 48, 'Jiha': 46}    # ...on the side wall's frames too
ROPE_SAG = 2
ROPE_DEPTH = (0, 1)  # pixels across the rope, from its wall side
STRING = 2   # pixels of straw string between the rope and the icon
ROPE = {'K': (58, 40, 22), 'd': (122, 88, 42), 'm': (176, 136, 70), 'l': (220, 186, 112)}
ROPE_RED = {'K': (64, 16, 14), 'd': (122, 30, 28), 'm': (178, 46, 38), 'l': (214, 96, 72)}
HUNG = {
    'R': (192, 36, 28), 'r': (132, 24, 22), 'g': (70, 118, 44),   # a red pepper and its stalk
    'C': (34, 30, 32), 'c': (78, 72, 74),                          # charcoal
}
# Hung along the rope near each post, `along` pixels from its middle, clear of
# the doorway; each row lies across the rope and the rows hang down from it.
HANGINGS = [
    (16, ['g', 'R', 'RR', 'Rr', '.r']),    # a red pepper on its stalk
    (19, ['C', 'Cc', 'CC']),               # a lump of charcoal
]


def rope_ends(view, data):
    """Where the rope is tied, in screen pixels from the pair's feet midpoint:
    the edge of each post facing the door, just under the head."""
    half = round(data['spread'] * SCALE)
    ends = []
    for who, foot in (('Cheonha', -half), ('Jiha', half)):
        img, (px, py) = wall_frame(who, view == 'Side')
        if view == 'Top':
            row = TOP_TIE_ROWS[who]
            xs = [x for x in range(img.width) if img.getpixel((x, row))[3]]
            ends.append((foot + (max(xs) if who == 'Cheonha' else min(xs)) + 0.5 - px, row + 0.5 - py))
        else:
            col = SIDE_TIE_COLS[who]
            ys = [y for y in range(img.height) if img.getpixel((col, y))[3]]
            ends.append((col + 0.5 - px, foot + (max(ys) if who == 'Cheonha' else min(ys)) + 0.5 - py))
    return ends


def hook_offset(view, data):
    """How far, in pixels, the hook (the frame's pivot) stands from the feet's line into the room."""
    return round((data['hang' + view] - data['stand']) * SCALE)


def rope_canvas(view, red, data):
    """{(along, down): colour} for one frame, the hook at (0, 0)."""
    def to_rope(x, y):  # screen pixels from the feet midpoint -> (along, down) from that line
        return (x, y) if view == 'Top' else (y, -x)
    a, b = (to_rope(*end) for end in rope_ends(view, data))
    c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + 2 * ROPE_SAG)
    samples, s, last = [], 0.0, None
    for i in range(801):
        t = i / 800
        p = tuple((1 - t) ** 2 * a[k] + 2 * (1 - t) * t * c[k] + t * t * b[k] for k in (0, 1))
        if last:
            s += math.hypot(p[0] - last[0], p[1] - last[1])
        samples.append((p, s))
        last = p
    palette = ROPE_RED if red else ROPE
    canvas = {}
    for (al, dn), s in samples:
        # two pixels deep, the strands crossing on a slant, lit on the side
        # away from the room (the wall's light) and shaded toward it
        for k in ROPE_DEPTH:
            phase = math.floor(s + 1.2 * k) % 4
            tone = 'd' if phase == 0 else ('l' if k < 1 else 'm') if phase == 1 else ('m' if k < 1 else 'd')
            colours = ROPE_RED if red and phase >= 2 else ROPE
            canvas[(math.floor(al), math.floor(dn) + k)] = colours[tone]
    for (al, dn) in list(canvas):
        for q in ((al + 1, dn), (al - 1, dn), (al, dn + 1), (al, dn - 1)):
            if q not in canvas:
                canvas[q] = palette['K'] if red else ROPE['K']
    bottom = {}
    for (al, dn) in canvas:
        bottom[al] = max(bottom.get(al, dn), dn)
    for along, rows in HANGINGS:
        for sign in (-1, 1):
            at = sign * along
            for i, row in enumerate(rows):
                for j, ch in enumerate(row):
                    if ch != '.':
                        x = at + j - len(row) // 2
                        canvas[(x, bottom[at] + i)] = HUNG[ch]
    hook = bottom[0] + 1 + STRING
    for i, dn in enumerate(range(bottom[0] + 1, hook)):  # the string: a strand of plain straw, as the icon's rim
        canvas[(0, dn)] = ROPE['l' if i % 2 == 0 else 'm']
    wanted = hook_offset(view, data)
    assert hook == wanted, (view, 'the hook hangs %d pixels from the feet line, the Lua says %d: set hang%s = %.2f'
                            % (hook, wanted, view, data['stand'] + hook / SCALE))
    return {(al, dn - hook): colour for (al, dn), colour in canvas.items()}


def rope_frame(view, red, data):
    """(image, pivot): one frame in screen pixels, the pivot at the hook's corner."""
    canvas = rope_canvas(view, red, data)
    pixels = {}
    for (al, dn), colour in canvas.items():
        # a pixel covers [al, al + 1) x [dn, dn + 1); on the side wall `down`
        # runs to the left, so it covers [-dn - 1, -dn) across the screen
        pixels[(al, dn) if view == 'Top' else (-dn - 1, al)] = colour
    x0, y0 = min(p[0] for p in pixels), min(p[1] for p in pixels)
    x1, y1 = max(p[0] for p in pixels), max(p[1] for p in pixels)
    img = Image.new('RGBA', (x1 - x0 + 1, y1 - y0 + 1))
    for (x, y), colour in pixels.items():
        img.putpixel((x - x0, y - y0), colour + (255,))
    return img, (-x0, -y0)


ROPE_NAMES = ['RopeTop', 'RopeSide', 'RopeTopRed', 'RopeSideRed']


def rope_parts(name):
    """(view, red) of one rope animation."""
    return ('Side' if 'Side' in name else 'Top'), 'Red' in name


def ropes(data=None):
    data = data or lua_data()
    frames = [rope_frame(*rope_parts(name), data) for name in ROPE_NAMES]
    sheet = Image.new('RGBA', (sum(f.width for f, _ in frames), max(f.height for f, _ in frames)))
    x = 0
    for frame, _ in frames:
        sheet.paste(frame, (x, 0))
        x += frame.width
    return frames, sheet


def icon_boxes():
    """jangseung.lua's ICON_BOX: each minimap icon's opaque box (x0, y0, x1, y1) in its frame."""
    block = LUA.read_text(encoding='utf-8').split('local ICON_BOX = {')[1].split('\n}')[0]
    return {name: tuple(int(v) for v in box.split(','))
            for name, box in re.findall(r'(\w+) = \{ *([-\d, ]+?) *\}', block)}


def icon_pose(box, view, flip):
    """(rotation, dx, dy) as jangseung.lua's `iconPose`: the icon turned with its
    wall so its top faces the rope (0 on the top wall, 180 on the bottom, 90
    clockwise on the right wall, -90 on the left) and rendered at the hook plus
    (dx, dy), its frame's pivot being its top-left corner, so the middle pixel
    of its top edge lands on the hook's pixel."""
    x0, y0, x1, y1 = box
    ax, ay = x0 + (x1 - x0 - 1) // 2, y0
    if view == 'Top':
        return (180, ax + 1, ay) if flip else (0, -ax, -ay)
    return (-90, -ay, ax + 1) if flip else (90, ay, -ax)


def icon_pixels(icon, box, view, flip):
    """{(x, y): rgba} the icon's opaque pixels on screen from the hook, turned and
    placed as the game draws them (a pixel's centre turned about the render
    point, clockwise for a positive rotation, screen y pointing down)."""
    rotation, dx, dy = icon_pose(box, view, flip)
    cos, sin = round(math.cos(math.radians(rotation))), round(math.sin(math.radians(rotation)))
    out = {}
    for y in range(icon.height):
        for x in range(icon.width):
            colour = icon.getpixel((x, y))
            if colour[3]:
                cx, cy = x + 0.5, y + 0.5
                sx, sy = dx + cx * cos - cy * sin, dy + cx * sin + cy * cos
                out[(math.floor(sx), math.floor(sy))] = colour
    return out


def rope_anm2(frames):
    anims, x = [], 0
    for name, (frame, pivot) in zip(ROPE_NAMES, frames):
        w, h = frame.size
        anims.append(f'''    <Animation Name="{name}" FrameNum="1" Loop="false">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
          <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" XCrop="{x}" YCrop="0" Width="{w}" Height="{h}" XPivot="{pivot[0]}" YPivot="{pivot[1]}" />
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>''')
        x += w
    return f'''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="conch_jangseung_rope.png" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="rope" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="RopeTop">
{chr(10).join(anims)}
  </Animations>
</AnimatedActor>
'''


GW, GH = 104, 52  # the earth: a half circle two tiles (80 units, 52 pixels) in radius


def hash01(x, y, salt):
    v = (x * 374761393 + y * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return (v ^ (v >> 16)) / 0xFFFFFFFF


def smooth(x, y, cell, salt):
    """Value noise: hashed lattice values, eased between cells (0..1)."""
    gx, gy = x / cell, y / cell
    x0, y0 = math.floor(gx), math.floor(gy)
    fx, fy = gx - x0, gy - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash01(x0, y0, salt), hash01(x0 + 1, y0, salt)
    c, d = hash01(x0, y0 + 1, salt), hash01(x0 + 1, y0 + 1, salt)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


# Packed earth like a village road: tan dirt in a few flat tones, clustered by
# noise rather than speckled, a darker trodden path running out from the door,
# pebbles lit from the top left, a few hairline cracks, and a rim that wanders
# and thins out in steps instead of a drawn circle. Half transparent, so any
# floor shows through a little.
EARTH = {
    'deep': (126, 96, 64), 'dark': (138, 106, 72), 'base': (150, 118, 80), 'light': (164, 132, 92),
    'pebble': (206, 188, 156), 'pebble_shadow': (86, 64, 44), 'crack': (92, 68, 46),
}


def ground():
    img = Image.new('RGBA', (GW, GH))
    cx, r = GW / 2, GW / 2
    for y in range(GH):
        for x in range(GW):
            dx, dy = x + 0.5 - cx, y + 0.5
            d = math.hypot(dx, dy)
            # the rim wanders in and out with the angle and a little with noise
            angle = math.atan2(dy, dx)
            edge = r - 2 - 5 * smooth(angle * 7, 0, 1, 11) - 2 * smooth(x, y, 6, 12)
            if d > edge:
                continue
            body = smooth(x, y, 10, 1) * 0.7 + smooth(x, y, 4, 2) * 0.3
            # the trodden path: straight out from the door, narrowing as it goes
            path = abs(dx) < 7 + 3 * smooth(0, y, 6, 3) - y * 0.08
            if path:
                body -= 0.22
            tone = 'deep' if body < 0.3 else 'dark' if body < 0.45 else 'base' if body < 0.68 else 'light'
            # alpha steps down toward the rim, broken up so it never draws a ring
            inner = edge - d
            jitter = hash01(x, y, 4)
            alpha = (150 if inner > 8 else 128 if inner > 5 + jitter else 104 if inner > 3 + jitter
                     else 76 if inner > 1 + jitter * 1.5 else 0)
            if alpha:
                img.putpixel((x, y), (*EARTH[tone], alpha))
    # pebbles: one or two pixels with a lit top left and a shadow below
    for i in range(46):
        x = int(3 + hash01(i, 0, 5) * (GW - 6))
        y = int(1 + hash01(i, 0, 6) * (GH - 4))
        if img.getpixel((x, y))[3] < 128 or img.getpixel((min(GW - 1, x + 1), min(GH - 1, y + 1)))[3] < 128:
            continue
        img.putpixel((x, y), (*EARTH['pebble'], 210))
        if hash01(i, 1, 7) > 0.5:
            img.putpixel((x + 1, y), (*EARTH['light'], 200))
        img.putpixel((x, y + 1), (*EARTH['pebble_shadow'], 170))
    # hairline cracks: short bent lines of dark soil
    for i in range(7):
        x = 6 + hash01(i, 2, 8) * (GW - 12)
        y = 4 + hash01(i, 3, 8) * (GH - 10)
        heading = hash01(i, 4, 8) * math.pi
        for step in range(4 + int(hash01(i, 5, 8) * 5)):
            px_, py_ = int(x), int(y)
            if 0 <= px_ < GW and 0 <= py_ < GH and img.getpixel((px_, py_))[3] >= 128:
                img.putpixel((px_, py_), (*EARTH['crack'], 165))
            heading += (hash01(i, step, 9) - 0.5) * 1.2
            x += math.cos(heading)
            y += math.sin(heading)
    return img


def ground_anm2():
    return f'''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="conch_jangseung_ground.png" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="earth" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="Ground">
    <Animation Name="Ground" FrameNum="1" Loop="false">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
          <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" XCrop="0" YCrop="0" Width="{GW}" Height="{GH}" XPivot="{GW // 2}" YPivot="0" />
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>
  </Animations>
</AnimatedActor>
'''


def icon(frames):
    """The two front statues, 지하여장군 behind, cut short above the post's foot
    so they fit the 32x32 canvas: the head and the top of each post, then the foot."""
    def short(frame):
        top = frame.crop((0, 0, frame.width, 28))
        foot = frame.crop((0, frame.height - 3, frame.width, frame.height))
        out = Image.new('RGBA', (frame.width, 31))
        out.paste(top, (0, 0))
        out.paste(foot, (0, 28))
        return out
    img = Image.new('RGBA', (32, 32))
    img.alpha_composite(short(statue('Upright', 'Jiha')), (14, 1))
    img.alpha_composite(short(statue('Upright', 'Cheonha')), (0, 0))
    return img


def preview(*parts):
    scale = 8
    pad = 8
    width = max(part.width for part in parts) * scale + pad * 2
    height = sum(part.height for part in parts) * scale + pad * (len(parts) + 1)
    out = Image.new('RGBA', (width, height), (58, 50, 44, 255))
    y = pad
    for part in parts:
        big = part.resize((part.width * scale, part.height * scale), Image.NEAREST)
        out.alpha_composite(big, (pad, y))
        y += big.height + pad
    return out


def main():
    frames, sheet = statues()
    rope_frames, rope_sheet = ropes()
    earth = ground()
    item = icon(frames)
    EFFECTS.mkdir(parents=True, exist_ok=True)
    sheet.save(EFFECTS / 'conch_jangseung.png')
    (EFFECTS / 'conch_jangseung.anm2').write_text(statue_anm2(frames), encoding='utf-8')
    rope_sheet.save(EFFECTS / 'conch_jangseung_rope.png')
    (EFFECTS / 'conch_jangseung_rope.anm2').write_text(rope_anm2(rope_frames), encoding='utf-8')
    earth.save(EFFECTS / 'conch_jangseung_ground.png')
    (EFFECTS / 'conch_jangseung_ground.anm2').write_text(ground_anm2(), encoding='utf-8')
    item.save(ICON)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    preview(sheet, rope_sheet, earth, item).save(PREVIEW / 'preview.png')
    print('wrote', EFFECTS / 'conch_jangseung.png', ICON, PREVIEW / 'preview.png')


if __name__ == '__main__':
    main()
