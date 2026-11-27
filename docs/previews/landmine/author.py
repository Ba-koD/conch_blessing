"""Landmine (지뢰): the item icon and the mine lying on the floor, finished grids.

The icon is a round pressure mine seen a little from above: an olive top face
lit from the top left, a red pressure button in a grey collar, a darker side
band with yellow warning stripes, sitting on a puddle of Ipecac's green (the
item answers Ipecac). It was redrawn in Isaac's style on 2026-11-25 (the
vanilla 2-pixel outline, larger flat clusters; the user chose the olive draft
over a grey one and asked for the puddle as an even, rounded oval). The
floor mine is the same object at gameplay size with a smaller puddle, so it
reads on dark floors too; its button blinks red once a second when armed. A
tear drops it from its own height (user request 2026-11-19): it falls as the
bare mine (Fall), sinks into the puddle it splashes on landing and settles
(Land), then idles. With Bobby-Bomb a lying mine stands up on four thin legs
and creeps toward enemies (Walk, two strides; a first draft of 2026-11-27).
Authored on the native grid (user request 2026-11-15); these text grids are
the source. `python docs/previews/landmine/author.py` writes the runtime PNGs
and anm2 and enlarged previews into .tmp/landmine/.
"""
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PAL = {
    "K": (22, 16, 12),     # outline
    "H": (208, 220, 140),  # top face, highlight
    "L": (150, 168, 88),   # top face, lit
    "M": (110, 126, 62),   # top face
    "S": (76, 88, 44),     # top face, shadow
    "E": (96, 110, 54),    # side band, lit
    "D": (62, 72, 36),     # side band
    "d": (40, 46, 24),     # side band, shadow
    "R": (216, 56, 46),    # button
    "W": (255, 190, 170),  # button highlight
    "r": (140, 28, 28),    # button, shadow
    "C": (150, 150, 150),  # collar, lit
    "c": (92, 92, 96),     # collar
    "G": (176, 230, 108),  # Ipecac ooze, lit
    "g": (104, 176, 52),   # Ipecac ooze
    "q": (56, 110, 30),    # Ipecac ooze, shadow
    "Y": (222, 186, 64),   # warning stripe, lit
    "y": (170, 136, 44),   # warning stripe
    "z": (112, 88, 28),    # warning stripe, shadow
}
# The icon's own palette (2026-11-25 redraw, the user's olive choice): the
# vanilla (8,0,0) outline and flatter, wider colour clusters than the floor
# mine, which keeps PAL.
ICON_PAL = {
    "K": (8, 0, 0),       # outline (vanilla near-black)
    "H": (182, 192, 108), # top face, highlight
    "L": (148, 158, 84),  # top face, lit
    "M": (112, 122, 60),  # top face
    "S": (82, 90, 44),    # top face, shadow
    "E": (74, 82, 40),    # side band, lit
    "B": (56, 62, 30),    # side band
    "D": (40, 44, 22),    # side band, shadow
    "R": (214, 39, 39),   # button
    "W": (255, 206, 196), # button highlight
    "P": (176, 32, 32),   # button, shade
    "r": (133, 19, 19),   # button, shadow
    "C": (160, 160, 160), # collar, lit
    "c": (96, 96, 100),   # collar
    "G": (184, 236, 112), # Ipecac ooze, lit
    "g": (124, 194, 60),  # Ipecac ooze
    "q": (70, 130, 36),   # Ipecac ooze, shadow
    "Y": (230, 192, 62),  # warning stripe, lit
    "y": (164, 126, 36),  # warning stripe
}
ICON = [
    "................................",  # 0
    "................................",  # 1
    "................................",  # 2
    "................................",  # 3
    "................................",  # 4
    ".............KKKKKK.............",  # 5
    "...........KKKKKKKKKK...........",  # 6
    "..........KKKRWWRRPKKK..........",  # 7
    "......KKKKKKKRWRRRPKKKKKKK......",  # 8
    ".....KKKKKLLKrrrrrrKMMKKKKK.....",  # 9
    "....KKKLHLLCKrrrrrrKcMMSSKKK....",  # 10
    "...KKKLLLLCCKKKKKKKKccMSSSKKK...",  # 11
    "...KKLLLLLKCCCCCcccccKMSSSSKK...",  # 12
    "...KKYLLLLLKKKKKKKKKKMSSSSyKK...",  # 13
    "...KKYEHHHHLMMMMMMMSSMMMMyDKK...",  # 14
    "...KKEEEYYBHHHHHHHMMMDDyyDDKK...",  # 15
    "...KKEEYYBBBYYBBBYYBBDyyDDDKK...",  # 16
    "...KKEYYEBBYYBBBYYBBByyDDDyKK...",  # 17
    "...KKKYEEBYYBBBYYBBByyDDDyKKK...",  # 18
    "...KKKKEEYYBBBYYBBBYyDDDyKKKK...",  # 19
    "..KKGGgKKKKBBYYBBBYYBKKKKggqKK..",  # 20
    ".KKGGggggggKKKKKKKKKKggggggqqKK.",  # 21
    ".KKGGgggggggggggggggggggggqqqKK.",  # 22
    ".KKggggggggggggggggggggqqqqqqKK.",  # 23
    "..KKKgggggggggggggqqqqqqqqqKKK..",  # 24
    "...KKKKKqqqqqqqqqqqqqqqqKKKKK...",  # 25
    ".....KKKKKKKKKKKKKKKKKKKKKK.....",  # 26
    ".........KKKKKKKKKKKKKK.........",  # 27
    "................................",  # 28
    "................................",  # 29
    "................................",  # 30
    "................................",  # 31
]
# The floor mine, 17x11; its foot (the puddle line) is row 8.
MINE = [
    "......KKKKK......",  # 0
    "....KKKRRrKKK....",  # 1
    "..KKLLKrrrKMMKK..",  # 2
    ".KLLLLLKKKMMMSSK.",  # 3
    ".KELLLMMMMMMSSdK.",  # 4
    ".KEEEELLMMMSDddK.",  # 5
    ".KEYYEDDyyDDDzdK.",  # 6
    "KgKKYEDyyDDzdKKgK",  # 7
    "KGgggKKKKKKKgggqK",  # 8
    ".KKgggggggggggKK.",  # 9
    "...KKKKKKKKKKK...",  # 10
]
PUDDLE_ROWS = 7  # rows 7-10 are the puddle around the mine's foot
CELL = (17, 11)
PIVOT = (8, 8)
OFF = {"R": (150, 40, 36)}                       # the button unlit
ON = {"R": (255, 110, 80), "r": (196, 48, 40)}   # the button lit
GLOW = {(7, 0): (255, 132, 96), (8, 0): (255, 132, 96), (9, 0): (255, 132, 96), (7, 1): (255, 214, 190)}
# The bare mine as it falls from the tear: no puddle yet, its foot closed.
FALL_BODY = MINE[:7] + [
    "..KKYEDyyDDzdKK..",  # 7
    "....KKKKKKKKK....",  # 8
]


# A walking mine (Bobby-Bomb): the bare mine lifted out of its puddle on four
# thin legs, two strides. Rows 0-8 are the body (FALL_BODY), rows 9-10 the legs;
# its feet stand on the ground point (WALK_PIVOT).
WALK_LEGS = [
    [
        "...KK.......KK...",  # 9
        "..K..K.....K..K..",  # 10
    ],
    [
        "....KK.....KK....",  # 9
        "...K..K...K..K...",  # 10
    ],
]
WALK_PIVOT = (8, 10)


def paint(image, rows, at, palette, skip_rows=()):
    px = image.load()
    for y, row in enumerate(rows):
        if y in skip_rows:
            continue
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            tx, ty = at[0] + x, at[1] + y
            if 0 <= tx < image.width and 0 <= ty < image.height:
                px[tx, ty] = (palette[ch] if ch in palette else PAL[ch]) + (255,)


def mine_frame(rise=0, lit=False):
    """The mine sunk `rise` rows into its puddle (positive) or bounced up (negative)."""
    cell = Image.new("RGBA", CELL)
    palette = dict(PAL, **(ON if lit else OFF))
    body, puddle = MINE[:PUDDLE_ROWS], MINE[PUDDLE_ROWS:]
    paint(cell, MINE, (0, 0), palette, skip_rows=range(PUDDLE_ROWS))
    visible = body[:len(body) - rise] if rise > 0 else body
    paint(cell, visible, (0, rise), palette)
    if rise > 0:
        # A sunk body sits inside the puddle: its front lip covers the body's foot.
        paint(cell, puddle, (0, PUDDLE_ROWS), palette)
    if lit and rise == 0:
        # The lit button glows a pixel past its rim.
        px = cell.load()
        for (x, y), colour in GLOW.items():
            px[x, y] = colour + (255,)
    return cell


def fall_frame():
    cell = Image.new("RGBA", CELL)
    paint(cell, FALL_BODY, (0, 0), dict(PAL, **OFF))
    return cell


def walk_frame(stride, lit=False):
    cell = Image.new("RGBA", CELL)
    paint(cell, FALL_BODY, (0, 0), dict(PAL, **(ON if lit else OFF)))
    paint(cell, WALK_LEGS[stride], (0, len(FALL_BODY)), PAL)
    return cell


# Sheet cells in order. Fall holds the bare mine while it drops; Land sinks it
# into its puddle and lets it settle over 8 updates (the mine arms as it ends);
# Idle shows the lit button for 4 updates and the dark one for 26.
# Walk strides every 4 updates with the button lit on the first stride.
CELLS = [fall_frame(), mine_frame(3), mine_frame(1), mine_frame(0), mine_frame(0, lit=True), walk_frame(0, lit=True),
         walk_frame(1)]
FALL = [(0, 1)]
LAND = [(1, 2), (2, 2), (3, 2), (4, 2)]
IDLE = [(4, 4), (3, 26)]
WALK = [(5, 4), (6, 4)]


def frame_xml(cell, delay, pivot=PIVOT):
    return ('          <Frame XPosition="0" YPosition="0" XPivot="%d" YPivot="%d" XCrop="%d" YCrop="0" '
            'Width="%d" Height="%d" XScale="100" YScale="100" Delay="%d" Visible="true" RedTint="255" '
            'GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" '
            'Rotation="0" Interpolated="false" />' % (pivot[0], pivot[1], cell * CELL[0], CELL[0], CELL[1], delay))


def animation_xml(name, frames, loop, pivot=PIVOT):
    total = sum(delay for _, delay in frames)
    lines = ['    <Animation Name="%s" FrameNum="%d" Loop="%s">' % (name, total, "true" if loop else "false"),
             '      <RootAnimation>',
             '        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="%d" Visible="true" '
             'RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" '
             'BlueOffset="0" Rotation="0" Interpolated="false" />' % total,
             '      </RootAnimation>',
             '      <LayerAnimations>',
             '        <LayerAnimation LayerId="0" Visible="true">']
    lines += [frame_xml(cell, delay, pivot) for cell, delay in frames]
    lines += ['        </LayerAnimation>', '      </LayerAnimations>', '      <NullAnimations />',
              '      <Triggers />', '    </Animation>']
    return lines


def anm2():
    lines = ['<AnimatedActor>',
             '  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />',
             '  <Content>',
             '    <Spritesheets>',
             '      <Spritesheet Id="0" Path="conch_landmine.png" />',
             '    </Spritesheets>',
             '    <Layers>',
             '      <Layer Id="0" Name="mine" SpritesheetId="0" />',
             '    </Layers>',
             '    <Nulls />',
             '    <Events />',
             '  </Content>',
             '  <Animations DefaultAnimation="Fall">']
    lines += animation_xml("Fall", FALL, True)
    lines += animation_xml("Land", LAND, False)
    lines += animation_xml("Idle", IDLE, True)
    lines += animation_xml("Walk", WALK, True, WALK_PIVOT)
    lines += ['  </Animations>', '</AnimatedActor>', '']
    return "\n".join(lines)


def icon():
    image = Image.new("RGBA", (32, 32))
    paint(image, ICON, (0, 0), ICON_PAL)
    return image


def sheet():
    image = Image.new("RGBA", (CELL[0] * len(CELLS), CELL[1]))
    for index, cell in enumerate(CELLS):
        image.alpha_composite(cell, (index * CELL[0], 0))
    return image


def check():
    assert len(ICON) == 32 and all(len(row) == 32 for row in ICON), "icon must be 32x32"
    assert len(MINE) == CELL[1] and all(len(row) == CELL[0] for row in MINE), "mine must fit its cell"
    assert all(len(FALL_BODY) + len(legs) == CELL[1] for legs in WALK_LEGS), "a walking mine must fit its cell"
    for rows, palette in [(ICON, ICON_PAL), (MINE, PAL), (FALL_BODY, PAL)] + [(legs, PAL) for legs in WALK_LEGS]:
        assert len({len(row) for row in rows}) == 1, "ragged grid"
        for row in rows:
            for ch in row:
                assert ch == "." or ch in palette, "unknown colour %r" % ch
    # The icon's outline is left-right symmetric (user request 2026-11-25:
    # the base rounded off evenly, like the first icon's).
    for row in ICON:
        shape = "".join("." if ch == "." else "x" for ch in row)
        assert shape == shape[::-1], "icon outline not symmetric: " + row


def main():
    check()
    out = os.path.join(ROOT, "resources", "gfx")
    icon().save(os.path.join(out, "items", "collectibles", "landmine.png"))
    sheet().save(os.path.join(out, "effects", "conch_landmine.png"))
    with open(os.path.join(out, "effects", "conch_landmine.anm2"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(anm2())
    preview = os.path.join(ROOT, ".tmp", "landmine")
    os.makedirs(preview, exist_ok=True)
    icon().resize((256, 256), Image.NEAREST).save(os.path.join(preview, "icon_x8.png"))
    strip = sheet()
    strip.resize((strip.width * 8, strip.height * 8), Image.NEAREST).save(os.path.join(preview, "mine_x8.png"))
    print("wrote landmine.png, conch_landmine.png/.anm2 and previews in", preview)


if __name__ == "__main__":
    main()
