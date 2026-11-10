"""Builds 장승's art: the pair of statues, the trodden earth and the item icon.

Authored directly on the native grid (AGENTS.md: no larger concept resized
down). The statues are wooden posts as they stand at a village mouth, seen as
each wall shows them (see the block above `CHEONHA_HEAD`): 천하대장군 with a
winged official's cap, round bulging eyes under angry brows, a fist nose, bared
teeth with tusks and a carved beard; 지하여장군 with a topknot, round eyes, red
cheeks and lips. Below the face each post carries its name as carved marks.
The red-route pair (where a Red Key opens toward the ultra secret room) wears
a red cloth tied round the post. The earth is a half circle two tiles (80
world units) in radius, half transparent so it darkens whatever floor it lies
on: packed village dirt with a wandering rim, a trodden path, pebbles and
hairline cracks. The icon is the two front statues, cut short to fit.

Run from the repository root; it writes the runtime PNGs and ANM2 files and a
preview under .tmp/jangseung:

    python docs/previews/jangseung/author.py
"""
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
EFFECTS = ROOT / 'resources/gfx/effects'
ICON = ROOT / 'resources/gfx/items/collectibles/jangseung.png'
PREVIEW = ROOT / '.tmp/jangseung'

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
    'E': (238, 230, 208, 255),  # eye white, fangs
    'e': (190, 182, 164, 255),  # eye white and teeth in shadow
    'T': (70, 44, 30, 255),     # carved marks
    'R': (178, 46, 38, 255),    # red cloth / cheeks
    'r': (122, 30, 28, 255),    # red shadow
    'o': (214, 96, 72, 255),    # red cloth light
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
    ".....KLLLHHHHHHHHHLMWK.....",
    ".....KLLLLKKKKKKKLLMWK.....",
    ".....KLSSLLLLLLLLLLMWK.....",
    ".....KKKKLLLLLLLLLKKKK.....",
    ".....KLLKKKKLLLKKKKMWK.....",
    ".....KKEEEKKLLLKKEEEKK.....",
    ".....KKEKKEKLMLKEKKEKK.....",
    ".....KKEKKeKLMLKEKKeKK.....",
    ".....KKEEEeKLMLKEEEeKK.....",
    ".....KLKKKKLLMLLKKKKWK.....",
    ".....KLLLLKSLLLMKLMMWK.....",
    ".....KLLLKSLLLLMWKMMWK.....",
    ".....KLLLKKKLMLKKKMMWK.....",
    ".....KLKKKKKKKKKKKKKWK.....",
    ".....KLKEEKEEEEeKEEKWK.....",
    ".....KLKEKKKKKKKKKEKWK.....",
    ".....KLKEKKKKKKKKKeKWK.....",
    ".....KLLKKKKKKKKKKKMWK.....",
    ".....KLLLTLTLLLTMTMWWK.....",
    ".....KLLLTLTLLLTMTMWWK.....",
    ".....KLLLLTLLLLLTMMWWK.....",
    ".....KMLLLLTTMMMMMWWWK.....",
    ".....KMLLLLMTMMMMMWWWK.....",
    ".....KMLLLTTMMMMMMWWWK.....",
    "......KMLLLMTMMMMWWWK......",
    ".......KMLLTTMMMWWWK.......",
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
    "..KLLKEEKLLLKEEKMWK..",
    "..KLKEKKEKLKEKKEKWK..",
    "..KLKEKKeKLKEKKeKWK..",
    "..KLLKEeKLLLKEeKMWK..",
    "..KRRLLLKSLMKLLRrWK..",
    "..KLLLLLKKMKKLLMMWK..",
    "..KLLLKKKKKKKKKMMWK..",
    "..KLLLKEKKKKKeKMMWK..",
    "..KLLLLoRRRRRrMMWWK..",
    "..KLLLLLLMMMMMMMWWK..",
    "..KLLLLTTMMMMMMMWWK..",
    "..KLLLLLTMMMMMMMWWK..",
    "..KMLLLTTMMMMMMWWWK..",
    "..KMLLLLTMMMMMMWWWK..",
    "..KMLLLTTMMMMMMWWWK..",
    "...KMLLTTMMMMMWWWK...",
    "....KMLLTMMMMWWWK....",
    ".....KKKKKKKKKKK.....",
]

# The red-route pair's cloth: rows of each wall map, from the lip down, that
# become a red band with a knot hanging off its right side.
CLOTH_ROWS = {'Cheonha': 33, 'Jiha': 23}

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

# Where each side map's red cloth goes: the first post row below the face.
SIDE_CLOTH_ROWS = {'Cheonha': 45, 'Jiha': 35}

# The slant (user corrections 2026-11-10: the angle should match the render,
# and bend as much at the head as at the foot). Seen from above the room's
# middle, the pair on a side wall leans in toward the door from the cap to the
# foot, 천하대장군 (the upper one) down and 지하여장군 (the lower one) up,
# about one pixel in eight or nine. Each step is a map row where the post
# moves one pixel further, spaced evenly from the cap's end to the foot: the
# crown and hair discs take steps too (a disc stepped once or twice reads as
# tilted), while no step falls inside an eye, a nose, a fang or a lid.
SIDE_STEPS = {'Cheonha': ((4, 12, 20, 29, 37, 45, 53), 1), 'Jiha': ((6, 13, 19, 25, 34, 41, 48), -1)}


def wall_rows(who):
    rows = list(CHEONHA_WALL if who == 'Cheonha' else JIHA_WALL)
    assert all(len(r) == len(rows[0]) for r in rows), (who, [len(r) for r in rows])
    return rows


def add_cloth(rows, y):
    """A red band three rows deep from row `y`, its knot hanging off the right."""
    rows, width = list(rows), len(rows[0])
    for k in range(3):
        row = list(rows[y + k])
        left, right = row.index('K'), len(row) - 1 - row[::-1].index('K')
        n = right - left - 1
        row[left + 1:right] = list(('o' + 'R' * (n - 2) + 'r', 'R' * (n - 1) + 'r', 'r' * n)[k])
        rows[y + k] = ''.join(row)
    for k, knot in enumerate(('K', 'RK', 'rK')):
        row = list(rows[y + 1 + k])
        right = len(row) - 1 - row[::-1].index('K')
        for j, ch in enumerate(knot):
            if right + 1 + j < width:
                row[right + 1 + j] = ch
        rows[y + 1 + k] = ''.join(row)
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


def wall_frame(who, side=False, red=False):
    """(image, foot pixel): the top wall's view, or the right wall's (its cap
    to the right); the game mirrors these for the bottom and left walls."""
    if side:
        rows = list(CHEONHA_SIDE if who == 'Cheonha' else JIHA_SIDE)
        if red:
            rows = add_cloth(rows, SIDE_CLOTH_ROWS[who])
        starts, sign = SIDE_STEPS[who]
        rows, foot = slant(turn_cw(rows), tuple(len(rows) - r for r in starts), sign)
        return paint(rows), foot
    rows, cloth = wall_rows(who), CLOTH_ROWS[who]
    if red:
        rows = add_cloth(rows, cloth)
    # the foot (the post's base centre) sits a little above the outline's
    # lowest point, which is the base's near edge (model3d.py)
    return paint(rows), (len(rows[0]) // 2, len(rows) - 6)


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


def statue(view, who, red=False):
    width, height, post_right = SIZES[view]
    head = HEADS[view][0 if who == 'Cheonha' else 1]
    rows = list(head) + body(width, post_right, len(head), height - len(head))
    assert len(rows) == height and all(len(r) == width for r in rows), (view, who, [len(r) for r in rows])
    if red:
        y = len(head) + 1
        n = post_right - 3
        for k, fill in enumerate(('o' + 'R' * (n - 2) + 'r', 'R' * (n - 1) + 'r', 'r' * n)):
            row = list(rows[y + k])
            row[3:3 + n] = fill
            rows[y + k] = ''.join(row)
        for k, knot in enumerate(('K', 'RK', 'rK')):
            row = list(rows[y + 1 + k])
            row[post_right + 1:post_right + 1 + len(knot)] = knot
            rows[y + 1 + k] = ''.join(row[:width])
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


# Runtime frames: each statue's top-wall and right-wall views, plain and red-clothed.
NAMES = [f'{who}{view}{red}' for red in ('', 'Red') for view in ('Top', 'Side') for who in ('Cheonha', 'Jiha')]


def statues():
    frames = []
    for name in NAMES:
        who = 'Cheonha' if name.startswith('Cheonha') else 'Jiha'
        frames.append(wall_frame(who, 'Side' in name, name.endswith('Red')))
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


def preview(sheet, earth, item):
    scale = 8
    pad = 8
    width = max(sheet.width, earth.width, item.width) * scale + pad * 2
    height = (sheet.height + earth.height + item.height) * scale + pad * 4
    out = Image.new('RGBA', (width, height), (58, 50, 44, 255))
    y = pad
    for part in (sheet, earth, item):
        big = part.resize((part.width * scale, part.height * scale), Image.NEAREST)
        out.alpha_composite(big, (pad, y))
        y += big.height + pad
    return out


def main():
    frames, sheet = statues()
    earth = ground()
    item = icon(frames)
    EFFECTS.mkdir(parents=True, exist_ok=True)
    sheet.save(EFFECTS / 'conch_jangseung.png')
    (EFFECTS / 'conch_jangseung.anm2').write_text(statue_anm2(frames), encoding='utf-8')
    earth.save(EFFECTS / 'conch_jangseung_ground.png')
    (EFFECTS / 'conch_jangseung_ground.anm2').write_text(ground_anm2(), encoding='utf-8')
    item.save(ICON)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    preview(sheet, earth, item).save(PREVIEW / 'preview.png')
    print('wrote', EFFECTS / 'conch_jangseung.png', ICON, PREVIEW / 'preview.png')


if __name__ == '__main__':
    main()
