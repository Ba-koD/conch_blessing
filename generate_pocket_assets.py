"""Generate the runtime art of Conch Blessing's cards and runes.

Thurisaz (the Kronos rune) is a charcoal stone shard with the Saturn sign
inlaid in gold and a dim crimson glow under it. The Conch Ticket is a cream
claim ticket tilted like the vanilla floor cards, with a red stub behind a
perforation and the Magic Conch's lavender spiral shell printed on it. Both
are drawn on the native 32x32 grid from plain geometry with no randomness, so
the outputs are reproducible. Run from any working directory:

    python generate_pocket_assets.py

Outputs (all generator-owned; edit this file, not the outputs). Every sheet
holds the body at x=0, a glow at x=32 (empty for cards) and the pocket-slot art
at x=64, each 32x32; the pocket slot reads that third frame through
content/gfx/ui_cardfronts.anm2, which generate_xml.py writes from the registry.
    resources/gfx/items/pick ups/pickup_thurisaz.png, resources/gfx/005.300_thurisaz.anm2
    resources/gfx/items/pick ups/pickup_conch_ticket.png, resources/gfx/005.300_conch_ticket.anm2
Each floor pickup has Idle, Appear, Collect, Sparkle, HUD and HUDSmall.
"""
import math
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
GFX = ROOT / 'resources/gfx'
THURISAZ_SHEET = 'items/pick ups/pickup_thurisaz.png'
THURISAZ_ANM2 = '005.300_thurisaz.anm2'
TICKET_SHEET = 'items/pick ups/pickup_conch_ticket.png'
TICKET_ANM2 = '005.300_conch_ticket.anm2'
FRAME = 32
BODY_X, GLOW_X, HUD_X = 0, 32, 64

# Stone: near-black outline, three greys with a cool tint and one sparse
# highlight. Gold inlay: dark edge, gold and a bright top-left gleam.
O = (12, 10, 14, 255)
D = (34, 32, 40, 255)
M = (54, 51, 62, 255)
L = (80, 77, 90, 255)
H = (132, 128, 146, 255)
GOLD_DARK = (120, 78, 24, 255)
GOLD = (214, 160, 52, 255)
GOLD_LIGHT = (255, 224, 116, 255)
GLOW = (214, 52, 46)
HUD_SHADOW = (0, 0, 0, 96)

# The shard leans a little like the vanilla runes; hand-placed vertices.
SHARD = [(14, 4), (19, 6), (23, 11), (22, 19), (18, 26), (12, 24), (9, 17), (10, 9)]
RIDGE = ((14, 4), (14, 25))           # left of this: the lit face
RIDGE2 = ((19, 6), (20, 25))          # right of this: the shaded face
HIGHLIGHT = ((13, 5), (12, 6), (11, 8), (14, 5), (15, 6), (11, 9))
CRACK = ((21, 13), (21, 14), (20, 15), (20, 16), (21, 17))

# The Saturn sign, 7x11 with a 2px stem: the cross, then the sickle hooking
# down to the right. Large enough to read in the pocket slot.
GLYPH = [
    "..##...",
    "######.",
    "######.",
    "..##...",
    "..####.",
    "..##.##",
    "..##..#",
    "..##..#",
    "......#",
    ".....##",
    "....##.",
]
GLYPH_AT = (12, 9)

NEIGHBOURS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def inside(poly, x, y):
    hit = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            hit = not hit
    return hit


def side(a, b, p):
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])


def stone():
    img = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    px = img.load()
    fill = {(x, y) for y in range(FRAME) for x in range(FRAME) if inside(SHARD, x + 0.5, y + 0.5)}
    # Three faces: lit on the left, mid in front, shaded on the right.
    for x, y in fill:
        p = (x + 0.5, y + 0.5)
        if side(RIDGE[0], RIDGE[1], p) > 0:
            px[x, y] = L
        elif side(RIDGE2[0], RIDGE2[1], p) > 0:
            px[x, y] = M
        else:
            px[x, y] = D
    # Shadow along the lower-right edge, a few bright pixels at the top left.
    for x, y in fill:
        if ((x + 1, y) not in fill or (x, y + 1) not in fill) and y > 8:
            px[x, y] = D
    for x, y in HIGHLIGHT:
        if (x, y) in fill:
            px[x, y] = H
    for x, y in CRACK:
        if (x, y) in fill:
            px[x, y] = O
    # The inlaid sign: a dark groove round it so it stands clear of the stone,
    # then gold lit from the top left with a darker lower-right edge.
    gx, gy = GLYPH_AT
    marks = {(gx + c, gy + r) for r, row in enumerate(GLYPH) for c, ch in enumerate(row) if ch == '#'}
    for x, y in marks:
        for dx, dy in NEIGHBOURS + ((1, 1),):
            q = (x + dx, y + dy)
            if q not in marks and q in fill:
                px[q] = O
    for x, y in marks:
        lit = (x - 1, y) not in marks or (x, y - 1) not in marks
        shade = (x + 1, y) not in marks and (x, y + 1) not in marks
        px[x, y] = GOLD_DARK if shade else (GOLD_LIGHT if lit else GOLD)
    for x, y in [(x, y) for y in range(FRAME) for x in range(FRAME) if (x, y) not in fill]:
        if any((x + dx, y + dy) in fill for dx, dy in NEIGHBOURS):
            px[x, y] = O
    return img


def glow():
    """A soft crimson disc under the stone; the anm2 pulses its size and alpha."""
    img = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    for y in range(FRAME):
        for x in range(FRAME):
            d = math.hypot((x + 0.5 - 16.5) / 15, (y + 0.5 - 16) / 15)
            if d < 1:
                img.putpixel((x, y), GLOW + (round(255 * (1 - d) ** 1.15),))
    return img


# ---------------------------------------------------------------- the Conch Ticket
# Paper: lit and shaded cream with a darker edge; a red stub; the Magic Conch
# printed as the provider's pale lavender shell with a dark opening.
PAPER_LIT, PAPER_SHADE, PAPER_EDGE = (250, 238, 202, 255), (229, 208, 160, 255), (181, 150, 100, 255)
STUB_LIT, STUB_SHADE = (204, 64, 58, 255), (150, 42, 40, 255)
TICKET_OUTLINE = (14, 10, 12, 255)
SHELL = {'O': TICKET_OUTLINE, 'L': (226, 228, 255, 255), 'M': (160, 160, 222, 255), 'A': (64, 60, 104, 255)}
TICKET_ANGLE = math.radians(34)                     # tilted down to the right like vanilla floor cards
TICKET_CENTRE = (15.6, 16.0)
TICKET_HALF = (9.6, 5.7)                            # half length, half width
TICKET_CUT = TICKET_HALF[0] - 4.4                   # the perforation before the stub
# The spiral conch the user picked (2026-10-12), printed in screen space.
SHELL_ROWS = [
    "..OOOO....",
    ".OLLLLOO..",
    "OLLAALLLO.",
    "OLALLALLO.",
    "OLLAALMLLO",
    ".OLLLMMLLO",
    "..OOMMLLO.",
    "....OMLLO.",
    ".....OMLO.",
    "......OO..",
]


def ticket_local(x, y):
    u = (math.cos(TICKET_ANGLE), math.sin(TICKET_ANGLE))
    dx, dy = x + 0.5 - TICKET_CENTRE[0], y + 0.5 - TICKET_CENTRE[1]
    return dx * u[0] + dy * u[1], -dx * u[1] + dy * u[0]


def shell_offset(fill, edge):
    """The offset that keeps every shell pixel on the paper, clear of the stub,
    with the most room to the outline."""
    marks = [(c, r) for r, row in enumerate(SHELL_ROWS) for c, ch in enumerate(row) if ch != '.']
    best, best_margin = None, -1
    for oy in range(FRAME):
        for ox in range(FRAME):
            margin = 99
            for c, r in marks:
                x, y = ox + c, oy + r
                if (x, y) not in fill or ticket_local(x, y)[0] > TICKET_CUT - 0.6:
                    margin = -1
                    break
                margin = min(margin, min(abs(x - ex) + abs(y - ey) for ex, ey in edge))
            if margin > best_margin:
                best, best_margin = (ox, oy), margin
    return best


def ticket():
    img = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    px = img.load()
    half_l, half_w = TICKET_HALF
    fill = set()
    for y in range(FRAME):
        for x in range(FRAME):
            along, across = ticket_local(x, y)
            if abs(along) <= half_l and abs(across) <= half_w:
                fill.add((x, y))
    for x, y in fill:
        along, across = ticket_local(x, y)
        lit = across < 1.2
        if along > TICKET_CUT + 0.6:
            px[x, y] = STUB_LIT if lit else STUB_SHADE
        else:
            px[x, y] = PAPER_LIT if lit else PAPER_SHADE
    for x, y in fill:
        if ticket_local(x, y)[0] <= TICKET_CUT and ((x, y + 1) not in fill or (x + 1, y) not in fill):
            px[x, y] = PAPER_EDGE
    # The perforation: short dark dashes across the ticket.
    for x, y in fill:
        along, across = ticket_local(x, y)
        if abs(along - TICKET_CUT) < 0.6 and math.floor(across + 10) % 2 == 0:
            px[x, y] = TICKET_OUTLINE
    edge = [(x, y) for y in range(FRAME) for x in range(FRAME)
            if (x, y) not in fill and any((x + dx, y + dy) in fill for dx, dy in NEIGHBOURS)]
    gx, gy = shell_offset(fill, edge)
    for r, row in enumerate(SHELL_ROWS):
        for c, ch in enumerate(row):
            if ch in SHELL and (gx + c, gy + r) in fill:
                px[gx + c, gy + r] = SHELL[ch]
    for x, y in edge:
        px[x, y] = TICKET_OUTLINE
    return img


def pocket(body):
    """The pocket-slot art: the body with a drop shadow, like the vanilla runes."""
    img = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    mask = body.getchannel('A')
    shadow = Image.new('RGBA', (FRAME, FRAME), HUD_SHADOW)
    img.paste(shadow, (2, 2), mask)
    img.alpha_composite(body)
    return img


# ---------------------------------------------------------------- ANM2
FRAME_DEFAULTS = dict(XPosition='0', YPosition='0', XScale='100', YScale='100', Delay='1', Visible='true',
                      RedTint='255', GreenTint='255', BlueTint='255', AlphaTint='255',
                      RedOffset='0', GreenOffset='0', BlueOffset='0', Rotation='0', Interpolated='false')
BODY_PIVOT = (16, 22)                 # near the stone's foot, so squashes land on the floor
CARD_PIVOT = (16, 24)                 # the ticket's lower edge, as the vanilla floor cards
GLOW_PIVOT = (16, 16)
GLOW_Y = -6
STAR_SHEET = 'effects/effect_023_starflash.png'   # vanilla texture, referenced in place


def key(delay, y=0, sx=100, sy=100, tint=255, alpha=255, offset=0, visible=True, x=0, rot=0):
    return dict(delay=delay, x=x, y=y, sx=sx, sy=sy, tint=tint, alpha=alpha, offset=offset, visible=visible, rot=rot)


def frame_attrs(k, crop, pivot, interpolated):
    cx, cy, w, h = crop
    return {**FRAME_DEFAULTS,
            'XPosition': str(k['x']), 'YPosition': str(k['y']),
            'XScale': str(k['sx']), 'YScale': str(k['sy']), 'Delay': str(k['delay']),
            'Visible': 'true' if k['visible'] else 'false',
            'RedTint': str(k['tint']), 'GreenTint': str(k['tint']), 'BlueTint': str(k['tint']),
            'AlphaTint': str(k['alpha']),
            'RedOffset': str(k['offset']), 'GreenOffset': str(k['offset']), 'BlueOffset': str(k['offset']),
            'Rotation': str(k['rot']),
            'Interpolated': 'true' if interpolated else 'false',
            'XPivot': str(pivot[0]), 'YPivot': str(pivot[1]),
            'XCrop': str(cx), 'YCrop': str(cy), 'Width': str(w), 'Height': str(h)}


# Each animation: name, loop, [(layer id, crop, pivot, interpolated, keys)], triggers.
# Layers listed first draw first, so the glow sits under the stone.
BODY_CROP = (BODY_X, 0, FRAME, FRAME)
GLOW_CROP = (GLOW_X, 0, FRAME, FRAME)
HUD_CROP = (HUD_X, 0, FRAME, FRAME)
LAYER_BODY, LAYER_GLOW, LAYER_HUD, LAYER_STAR = 0, 1, 2, 3
THURISAZ_LAND = 21                    # the Appear frame the thrown stone hits the floor
TICKET_LAND = 21                      # the Appear frame the ticket lands flat

THURISAZ_ANIMATIONS = [
    # The glow breathes and the stone catches the light once per cycle. The last
    # key repeats the first, so the loop has no seam.
    ('Idle', True, [
        (LAYER_GLOW, GLOW_CROP, GLOW_PIVOT, True, [
            key(10, y=GLOW_Y, sx=92, sy=92, alpha=150), key(8, y=GLOW_Y, sx=112, sy=112, alpha=220),
            key(8, y=GLOW_Y, sx=118, sy=118, alpha=230), key(7, y=GLOW_Y, sx=100, sy=100, alpha=175),
            key(1, y=GLOW_Y, sx=92, sy=92, alpha=150)]),
        (LAYER_BODY, BODY_CROP, BODY_PIVOT, True, [
            key(10, tint=190), key(8, tint=255), key(8, tint=255), key(7, tint=205), key(1, tint=190)]),
    ], ()),
    # Tossed out like a vanilla rune: it springs up from the floor, tumbles over the
    # top of its arc, falls faster and faster, lands squashed and rebounds once.
    # Linear keys between closer frames approximate the arc's easing. The glow
    # lights as it lands, and both layers end on Idle's first pose.
    ('Appear', False, [
        (LAYER_GLOW, GLOW_CROP, GLOW_PIVOT, True, [
            key(THURISAZ_LAND, y=GLOW_Y, sx=70, sy=70, alpha=0, visible=False),
            key(4, y=GLOW_Y, sx=80, sy=80, alpha=60), key(4, y=GLOW_Y, sx=118, sy=118, alpha=220),
            key(2, y=GLOW_Y, sx=92, sy=92, alpha=150)]),
        (LAYER_BODY, BODY_CROP, BODY_PIVOT, True, [
            key(6, visible=False),
            key(2, y=0, sx=55, sy=145),                     # springs out of the floor
            key(2, y=-10, sx=85, sy=118, rot=-12),
            key(2, y=-16, sx=100, sy=104, rot=-22),         # slowing as it rises
            key(3, y=-19, sx=104, sy=97, rot=-28),          # the top of the arc
            key(2, y=-18, rot=-20),
            key(2, y=-13, sx=94, sy=108, rot=-6),           # falling, faster each frame
            key(2, y=-5, sx=82, sy=122, rot=6),
            key(2, y=1, sx=138, sy=66),                     # lands, squashed flat
            key(2, y=-4, sx=90, sy=114),                    # one small rebound
            key(2, y=0, sx=108, sy=93),
            key(4, y=0, tint=190)]),
    ], (('DropSound', THURISAZ_LAND),)),
    # Picked up: the stone stretches, flashes white and is gone.
    ('Collect', False, [
        (LAYER_GLOW, GLOW_CROP, GLOW_PIVOT, True, [
            key(1, y=GLOW_Y, alpha=230), key(6, y=GLOW_Y, sx=150, sy=150, alpha=0), key(7, y=GLOW_Y, alpha=0, visible=False)]),
        (LAYER_BODY, BODY_CROP, BODY_PIVOT, True, [
            key(1), key(2, sx=70, sy=135, offset=60), key(2, sx=150, sy=55, offset=160),
            key(2, sx=200, sy=15, offset=255), key(7, sx=200, sy=15, visible=False)]),
    ], ()),
    # A brief star twinkle at the stone's top corner.
    ('Sparkle', False, [
        (LAYER_STAR, None, (16, 16), False, [
            key(6, x=4, y=-20, visible=False)] + [key(2, x=4, y=-20) for _ in range(12)]),
    ], ()),
    ('HUD', False, [(LAYER_HUD, HUD_CROP, (16, 16), False, [key(1)])], ()),
    ('HUDSmall', False, [(LAYER_HUD, HUD_CROP, (16, 16), False, [key(1, sx=50, sy=50)])], ()),
]

# Cards sit still on the floor (vanilla's Idle is one frame). Thrown, a ticket
# flicks up out of the floor, opens out at the top, flutters like paper as it
# hangs, drops, lands flat and settles; it has no glow.
TICKET_ANIMATIONS = [
    ('Idle', True, [(LAYER_BODY, BODY_CROP, CARD_PIVOT, False, [key(1)])], ()),
    ('Appear', False, [
        (LAYER_BODY, BODY_CROP, CARD_PIVOT, True, [
            key(5, visible=False),
            key(2, y=0, sx=25, sy=175),                     # flicks up out of the floor
            key(2, y=-12, sx=70, sy=135),
            key(2, y=-20, sx=115, sy=88, rot=-8),           # opens out at the top
            key(3, y=-17, rot=6),                           # flutters like paper
            key(3, y=-15, rot=-5),
            key(2, y=-13, sx=96, sy=104, rot=3),
            key(2, y=-7, sx=78, sy=122),                    # drops
            key(2, y=1, sx=150, sy=55),                     # lands flat
            key(2, y=0, sx=85, sy=115),
            key(2, y=0, sx=104, sy=96),
            key(4, y=0)]),
    ], (('DropSound', TICKET_LAND),)),
    ('Collect', False, [
        (LAYER_BODY, BODY_CROP, CARD_PIVOT, True, [
            key(1), key(2, sx=70, sy=135, offset=60), key(2, sx=150, sy=55, offset=160),
            key(2, sx=200, sy=15, offset=255), key(7, sx=200, sy=15, visible=False)]),
    ], ()),
    ('Sparkle', False, [
        (LAYER_STAR, None, (16, 16), False, [
            key(6, x=6, y=-18, visible=False)] + [key(2, x=6, y=-18) for _ in range(12)]),
    ], ()),
    ('HUD', False, [(LAYER_HUD, HUD_CROP, (16, 16), False, [key(1)])], ()),
    ('HUDSmall', False, [(LAYER_HUD, HUD_CROP, (16, 16), False, [key(1, sx=50, sy=50)])], ()),
]
STAR_CELLS = [(c * 32, r * 32, 32, 32) for r in range(3) for c in range(4)]


def write_anm2(path, sheet, animations):
    root = ET.Element('AnimatedActor')
    ET.SubElement(root, 'Info', CreatedBy='ConchBlessing', Version='20', Fps='30')
    content = ET.SubElement(root, 'Content')
    sheets = ET.SubElement(content, 'Spritesheets')
    ET.SubElement(sheets, 'Spritesheet', Id='0', Path=sheet)
    ET.SubElement(sheets, 'Spritesheet', Id='1', Path=STAR_SHEET)
    layers = ET.SubElement(content, 'Layers')
    for layer_id, name, sheet_id in ((LAYER_BODY, 'body', 0), (LAYER_GLOW, 'glow', 0), (LAYER_HUD, 'ui', 0),
                                     (LAYER_STAR, 'Sparkle', 1)):
        ET.SubElement(layers, 'Layer', Id=str(layer_id), Name=name, SpritesheetId=str(sheet_id))
    ET.SubElement(content, 'Nulls')
    events = ET.SubElement(content, 'Events')
    ET.SubElement(events, 'Event', Id='0', Name='DropSound')
    anims = ET.SubElement(root, 'Animations', DefaultAnimation='Idle')
    for name, loop, tracks, triggers in animations:
        length = max(sum(k['delay'] for k in keys) for *_, keys in tracks)
        anim = ET.SubElement(anims, 'Animation', Name=name, FrameNum=str(length), Loop='true' if loop else 'false')
        ET.SubElement(ET.SubElement(anim, 'RootAnimation'), 'Frame', **{**FRAME_DEFAULTS, 'Delay': str(length)})
        layer_anims = ET.SubElement(anim, 'LayerAnimations')
        for layer_id, crop, pivot, interpolated, keys in tracks:
            assert sum(k['delay'] for k in keys) == length, (name, layer_id)
            track = ET.SubElement(layer_anims, 'LayerAnimation', LayerId=str(layer_id), Visible='true')
            for index, k in enumerate(keys):
                cell = crop if crop else STAR_CELLS[max(0, index - 1) % len(STAR_CELLS)]
                ET.SubElement(track, 'Frame', **frame_attrs(k, cell, pivot, interpolated))
        ET.SubElement(anim, 'NullAnimations')
        trigger_parent = ET.SubElement(anim, 'Triggers')
        for event, at in triggers:
            ET.SubElement(trigger_parent, 'Trigger', EventId='0', AtFrame=str(at))
            assert event == 'DropSound'
    ET.indent(root, space='  ')
    path.write_text(ET.tostring(root, encoding='unicode') + '\n', encoding='utf-8')


# key -> (sheet, anm2, body drawer, glow drawer or None, animations)
POCKETS = {
    'THURISAZ': (THURISAZ_SHEET, THURISAZ_ANM2, stone, glow, THURISAZ_ANIMATIONS),
    'CONCH_TICKET': (TICKET_SHEET, TICKET_ANM2, ticket, None, TICKET_ANIMATIONS),
}


def write(key):
    sheet_path, anm2, draw, draw_glow, animations = POCKETS[key]
    body = draw()
    sheet = Image.new('RGBA', (FRAME * 3, FRAME), (0, 0, 0, 0))
    sheet.alpha_composite(body, (BODY_X, 0))
    if draw_glow:
        sheet.alpha_composite(draw_glow(), (GLOW_X, 0))
    sheet.alpha_composite(pocket(body), (HUD_X, 0))
    out = GFX / sheet_path
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    write_anm2(GFX / anm2, sheet_path, animations)
    print('wrote', out.relative_to(ROOT), 'and', (GFX / anm2).relative_to(ROOT))


def main():
    for key in POCKETS:
        write(key)


if __name__ == '__main__':
    main()
