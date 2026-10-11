"""Generate the runtime art of Conch Blessing's runes.

Thurisaz (the Kronos rune) is a charcoal stone shard with the Saturn sign
inlaid in gold and a dim crimson glow under it, drawn on the native 32x32 grid.
Everything is plain geometry with no randomness, so the outputs are
reproducible. Run from any working directory:

    python generate_rune_assets.py

Outputs (all generator-owned; edit this file, not the outputs):
    resources/gfx/items/pick ups/pickup_thurisaz.png
        body at x=0, glow at x=32, pocket-slot art at x=64 (each 32x32). The
        pocket slot reads the third frame through content/gfx/ui_cardfronts.anm2,
        which generate_xml.py writes from ConchBlessing.PocketData.
    resources/gfx/005.300_thurisaz.anm2
        the floor pickup: Idle, Appear, Collect, Sparkle, HUD, HUDSmall.
"""
import math
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
GFX = ROOT / 'resources/gfx'
SHEET = 'items/pick ups/pickup_thurisaz.png'
ANM2 = '005.300_thurisaz.anm2'
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


def pocket(body):
    """The pocket-slot art: the stone with a drop shadow, like the vanilla runes."""
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
GLOW_PIVOT = (16, 16)
GLOW_Y = -6
STAR_SHEET = 'effects/effect_023_starflash.png'   # vanilla texture, referenced in place


def key(delay, y=0, sx=100, sy=100, tint=255, alpha=255, offset=0, visible=True, x=0):
    return dict(delay=delay, x=x, y=y, sx=sx, sy=sy, tint=tint, alpha=alpha, offset=offset, visible=visible)


def frame_attrs(k, crop, pivot, interpolated):
    cx, cy, w, h = crop
    return {**FRAME_DEFAULTS,
            'XPosition': str(k['x']), 'YPosition': str(k['y']),
            'XScale': str(k['sx']), 'YScale': str(k['sy']), 'Delay': str(k['delay']),
            'Visible': 'true' if k['visible'] else 'false',
            'RedTint': str(k['tint']), 'GreenTint': str(k['tint']), 'BlueTint': str(k['tint']),
            'AlphaTint': str(k['alpha']),
            'RedOffset': str(k['offset']), 'GreenOffset': str(k['offset']), 'BlueOffset': str(k['offset']),
            'Interpolated': 'true' if interpolated else 'false',
            'XPivot': str(pivot[0]), 'YPivot': str(pivot[1]),
            'XCrop': str(cx), 'YCrop': str(cy), 'Width': str(w), 'Height': str(h)}


# Each animation: name, loop, [(layer id, crop, pivot, interpolated, keys)], triggers.
# Layers listed first draw first, so the glow sits under the stone.
BODY_CROP = (BODY_X, 0, FRAME, FRAME)
GLOW_CROP = (GLOW_X, 0, FRAME, FRAME)
HUD_CROP = (HUD_X, 0, FRAME, FRAME)
LAYER_BODY, LAYER_GLOW, LAYER_HUD, LAYER_STAR = 0, 1, 2, 3

ANIMATIONS = [
    # The glow breathes and the stone catches the light once per cycle.
    ('Idle', True, [
        (LAYER_GLOW, GLOW_CROP, GLOW_PIVOT, True, [
            key(10, y=GLOW_Y, sx=92, sy=92, alpha=150), key(8, y=GLOW_Y, sx=112, sy=112, alpha=220),
            key(8, y=GLOW_Y, sx=118, sy=118, alpha=230), key(8, y=GLOW_Y, sx=100, sy=100, alpha=175)]),
        (LAYER_BODY, BODY_CROP, BODY_PIVOT, True, [
            key(10, tint=190), key(8, tint=255), key(8, tint=255), key(8, tint=210)]),
    ], ()),
    # Dropped from above: a fall, one squash on landing, a small rebound.
    ('Appear', False, [
        (LAYER_GLOW, GLOW_CROP, GLOW_PIVOT, True, [
            key(15, y=GLOW_Y, sx=70, sy=70, alpha=0, visible=False), key(9, y=GLOW_Y, sx=80, sy=80, alpha=40),
            key(6, y=GLOW_Y, sx=105, sy=105, alpha=200)]),
        (LAYER_BODY, BODY_CROP, BODY_PIVOT, True, [
            key(6, y=-30, visible=False), key(6, y=-30, sx=80, sy=120), key(3, y=0, sx=80, sy=120),
            key(3, y=2, sx=135, sy=65), key(3, y=-4, sx=90, sy=112), key(3, y=0, sx=110, sy=92),
            key(6, y=0, tint=230)]),
    ], (('DropSound', 15),)),
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
STAR_CELLS = [(c * 32, r * 32, 32, 32) for r in range(3) for c in range(4)]


def write_anm2(path):
    root = ET.Element('AnimatedActor')
    ET.SubElement(root, 'Info', CreatedBy='ConchBlessing', Version='20', Fps='30')
    content = ET.SubElement(root, 'Content')
    sheets = ET.SubElement(content, 'Spritesheets')
    ET.SubElement(sheets, 'Spritesheet', Id='0', Path=SHEET)
    ET.SubElement(sheets, 'Spritesheet', Id='1', Path=STAR_SHEET)
    layers = ET.SubElement(content, 'Layers')
    for layer_id, name, sheet in ((LAYER_BODY, 'body', 0), (LAYER_GLOW, 'glow', 0), (LAYER_HUD, 'ui', 0),
                                  (LAYER_STAR, 'Sparkle', 1)):
        ET.SubElement(layers, 'Layer', Id=str(layer_id), Name=name, SpritesheetId=str(sheet))
    ET.SubElement(content, 'Nulls')
    events = ET.SubElement(content, 'Events')
    ET.SubElement(events, 'Event', Id='0', Name='DropSound')
    anims = ET.SubElement(root, 'Animations', DefaultAnimation='Idle')
    for name, loop, tracks, triggers in ANIMATIONS:
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


def main():
    body = stone()
    sheet = Image.new('RGBA', (FRAME * 3, FRAME), (0, 0, 0, 0))
    sheet.alpha_composite(body, (BODY_X, 0))
    sheet.alpha_composite(glow(), (GLOW_X, 0))
    sheet.alpha_composite(pocket(body), (HUD_X, 0))
    out = GFX / SHEET
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    write_anm2(GFX / ANM2)
    print('wrote', out.relative_to(ROOT), 'and', (GFX / ANM2).relative_to(ROOT))


if __name__ == '__main__':
    main()
