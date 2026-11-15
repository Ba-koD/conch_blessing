"""Landmine (지뢰): the item icon and the mine lying on the floor, finished grids.

The icon is a round pressure mine seen a little from above: an olive top face
lit from the top left, a red pressure button in a grey collar, a darker side
band, sitting in a puddle of Ipecac's green (the item answers Ipecac). The
floor mine is the same object at gameplay size with a smaller puddle, so it
reads on dark floors too; its button blinks red once a second when armed.
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
ICON = [
    "................................",  # 0
    "................................",  # 1
    "................................",  # 2
    "................................",  # 3
    "................................",  # 4
    "................................",  # 5
    "................................",  # 6
    "................................",  # 7
    "..............KKKK..............",  # 8
    "...........KKKWRRRKKK...........",  # 9
    "........KKKLKrRRRrrKMKKK........",  # 10
    "......KKHLLLKrrrrrrKMMMMKK......",  # 11
    ".....KHHLLLLKCCccccKMMMMSSK.....",  # 12
    ".....KLLLLLLLKKKKKKMMMSSSSK.....",  # 13
    ".....KLLLLLMMMMMMMMMSSSSSSK.....",  # 14
    ".....KLLLMMMMMMMMMSSSSSSSSK.....",  # 15
    ".....KEEHHLMMMMMMSSSSSSSddK.....",  # 16
    ".....KEEEEEHHLLLMMMSSDddddK.....",  # 17
    ".....KEEYYEEDyyDDDyyDDdzzdK.....",  # 18
    ".....KEYYEEEyyDDDyyDDDzzddK.....",  # 19
    "....KgKKEEEYyDDDyyDDDyzdKKgK....",  # 20
    "..KKGGggKKKYDDDyyDDDyKKKggggKK..",  # 21
    ".KGGgggggggKKKKKKKKKKgggggggqqK.",  # 22
    "..KKgggggGgggggggggggggqqqqqKK..",  # 23
    "....KKKKKgggggggggqqqqqKKKKK....",  # 24
    ".........KKKKKKKKKKKKKK.........",  # 25
    "................................",  # 26
    "................................",  # 27
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
SPLATS = [
    [".....", ".GgG.", "KgggK", ".KKK."],
    ["..GG.....", ".GgggGg..", "KgggggggK", ".KKqqqKK.", "...KKK..."],
]
# The tear's splash spread into the puddle, before the mine rises from it.
PUDDLE = [
    "...KKKKKKKKKKK...",  # 7
    ".KKGGgggggggqqKK.",  # 8
    ".KKgggggggggggKK.",  # 9
    "...KKKKKKKKKKK...",  # 10
]


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
                px[tx, ty] = palette.get(ch, PAL[ch]) + (255,)


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


def splat_frame(index):
    cell = Image.new("RGBA", CELL)
    rows = SPLATS[index]
    paint(cell, rows, ((CELL[0] - len(rows[0])) // 2, PIVOT[1] + 3 - len(rows)), PAL)
    return cell


def puddle_frame():
    cell = Image.new("RGBA", CELL)
    paint(cell, PUDDLE, (0, PUDDLE_ROWS), PAL)
    return cell


# Sheet cells in order. Appear plays 0-7 one update each (the mine arms as it
# ends); Idle shows the lit button for 4 updates and the dark one for 26.
CELLS = [splat_frame(0), splat_frame(1), puddle_frame(), mine_frame(3), mine_frame(1),
         mine_frame(0), mine_frame(0, lit=False), mine_frame(0, lit=True)]
APPEAR = [(i, 1) for i in range(8)]
IDLE = [(7, 4), (6, 26)]


def frame_xml(cell, delay):
    return ('          <Frame XPosition="0" YPosition="0" XPivot="%d" YPivot="%d" XCrop="%d" YCrop="0" '
            'Width="%d" Height="%d" XScale="100" YScale="100" Delay="%d" Visible="true" RedTint="255" '
            'GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" '
            'Rotation="0" Interpolated="false" />' % (PIVOT[0], PIVOT[1], cell * CELL[0], CELL[0], CELL[1], delay))


def animation_xml(name, frames, loop):
    total = sum(delay for _, delay in frames)
    lines = ['    <Animation Name="%s" FrameNum="%d" Loop="%s">' % (name, total, "true" if loop else "false"),
             '      <RootAnimation>',
             '        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="%d" Visible="true" '
             'RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" '
             'BlueOffset="0" Rotation="0" Interpolated="false" />' % total,
             '      </RootAnimation>',
             '      <LayerAnimations>',
             '        <LayerAnimation LayerId="0" Visible="true">']
    lines += [frame_xml(cell, delay) for cell, delay in frames]
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
             '  <Animations DefaultAnimation="Appear">']
    lines += animation_xml("Appear", APPEAR, False)
    lines += animation_xml("Idle", IDLE, True)
    lines += ['  </Animations>', '</AnimatedActor>', '']
    return "\n".join(lines)


def icon():
    image = Image.new("RGBA", (32, 32))
    paint(image, ICON, (0, 0), PAL)
    return image


def sheet():
    image = Image.new("RGBA", (CELL[0] * len(CELLS), CELL[1]))
    for index, cell in enumerate(CELLS):
        image.alpha_composite(cell, (index * CELL[0], 0))
    return image


def check():
    assert len(ICON) == 32 and all(len(row) == 32 for row in ICON), "icon must be 32x32"
    assert len(MINE) == CELL[1] and all(len(row) == CELL[0] for row in MINE), "mine must fit its cell"
    for rows in [ICON, MINE, PUDDLE] + SPLATS:
        assert len({len(row) for row in rows}) == 1, "ragged grid"
        for row in rows:
            for ch in row:
                assert ch == "." or ch in PAL, "unknown colour %r" % ch


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
