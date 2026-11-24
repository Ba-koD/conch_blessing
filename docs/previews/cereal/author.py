"""시리얼 (Cereal): the item icon, the number-cereal pickups and the bowl UI.

`python docs/previews/cereal/author.py` writes, from the pixel maps below:

- resources/gfx/items/collectibles/cereal.png: the icon, a cereal box as sold
  in shops (user request 2026-11-24) with a label reading 025 (Breakfast is
  item 025) and a bowl of cereal on its front;
- resources/gfx/items/pick ups/pickup_conch_cereal.png and one
  resources/gfx/005.7792_conch_cereal_{d}.anm2 a digit (each subtype's own
  entity row names its own, so the engine plays the usual Appear and Idle):
  the floor pickups, chunky number cereal with a grainy, toasted surface (user
  request 2026-11-24: real cereal texture), one colour per digit, built like
  the vanilla key's;
- resources/gfx/ui/conch_cereal_ui.png and .anm2: the bowl Isaac holds (its far
  half with the empty inside, the milk drawn only while milk is held, and its
  near half drawn over the cereal in it), the digits for the picker and the
  HUD marks.

The palettes and bowl drive the preview page's script (template.html) too, the
layout the user approved on 2026-11-24. The box icon and the textured cereal
are first drafts the user has not seen in game. Enlarged previews go to
.tmp/cereal/.
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GFX = os.path.join(ROOT, "resources", "gfx")
PREVIEW = os.path.join(ROOT, ".tmp", "cereal")

GLYPHS = {
    0: ['.####.', '##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '.####.'],
    1: ['..##..', '.###..', '####..', '..##..', '..##..', '..##..', '..##..', '######'],
    2: ['.####.', '##..##', '....##', '...##.', '..##..', '.##...', '##....', '######'],
    3: ['.####.', '##..##', '....##', '..###.', '....##', '....##', '##..##', '.####.'],
    4: ['...##.', '..###.', '.####.', '##.##.', '######', '...##.', '...##.', '...##.'],
    5: ['######', '##....', '##....', '#####.', '....##', '....##', '##..##', '.####.'],
    6: ['.####.', '##....', '##....', '#####.', '##..##', '##..##', '##..##', '.####.'],
    7: ['######', '....##', '...##.', '...##.', '..##..', '..##..', '.##...', '.##...'],
    8: ['.####.', '##..##', '##..##', '.####.', '##..##', '##..##', '##..##', '.####.'],
    9: ['.####.', '##..##', '##..##', '##..##', '.#####', '....##', '...##.', '.###..'],
}
RING = ['..###..', '.#####.', '##...##', '##...##', '##...##', '.#####.', '..###..']

# One colour per digit (out, shade, base, light): 0 plain milk white, 1 red,
# 2 orange, 3 yellow, 4 green, 5 teal, 6 blue, 7 purple, 8 pink, 9 chocolate.
PAL = [
    ((92, 70, 48), (208, 188, 150), (242, 230, 200), (255, 252, 238)),
    ((84, 14, 14), (176, 36, 36), (226, 66, 58), (255, 138, 116)),
    ((92, 40, 8), (204, 98, 24), (244, 142, 42), (255, 198, 112)),
    ((90, 68, 8), (204, 164, 28), (246, 210, 60), (255, 242, 152)),
    ((18, 62, 18), (50, 138, 46), (96, 190, 72), (172, 234, 132)),
    ((10, 58, 66), (28, 138, 150), (60, 192, 196), (152, 238, 234)),
    ((16, 30, 92), (46, 84, 190), (84, 130, 234), (162, 198, 255)),
    ((52, 20, 82), (118, 62, 176), (164, 104, 222), (212, 172, 252)),
    ((92, 24, 62), (198, 78, 138), (240, 124, 180), (255, 192, 222)),
    ((38, 18, 8), (96, 56, 28), (138, 84, 46), (196, 140, 92)),
]
GOLD = ((70, 34, 10), (180, 108, 38), (228, 164, 64), (255, 222, 132))
INK = (20, 10, 10)
OUTLINE = (8, 0, 0)
N8 = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)]


def puffy(rows, pal):
    """A 2px stroke glyph, lit from the top left, outlined in its own dark tone."""
    out, shade, base, light = pal
    gw, gh = len(rows[0]), len(rows)
    img = Image.new("RGBA", (gw + 2, gh + 2), (0, 0, 0, 0))
    px = img.load()

    def f(x, y):
        return 0 <= y < gh and 0 <= x < gw and rows[y][x] == "#"

    for y in range(-1, gh + 1):
        for x in range(-1, gw + 1):
            if f(x, y):
                lit = not f(x, y - 1) or not f(x - 1, y)
                dark = not f(x, y + 1) or not f(x + 1, y)
                col = light if lit and not dark else shade if dark and not lit else base
                px[x + 1, y + 1] = col + (255,)
            elif any(f(x + dx, y + dy) for dx, dy in N8):
                px[x + 1, y + 1] = out + (255,)
    return img


# The number cereal looks like real cereal (user request 2026-11-24): chunky
# puffed strokes (three pixels across, two down), a grainy surface, toasted
# spots and a sugar glint, in each digit's own colour toasted a little. 8x10
# glyphs, 10x12 with the outline.
CHUNKY = {
    0: ['.######.', '########', '###..###', '###..###', '###..###', '###..###', '###..###', '###..###',
        '########', '.######.'],
    1: ['...###..', '..####..', '.#####..', '...###..', '...###..', '...###..', '...###..', '...###..',
        '.#######', '.#######'],
    2: ['.######.', '########', '##...###', '.....###', '...####.', '..####..', '.####...', '###.....',
        '########', '########'],
    3: ['.######.', '########', '.....###', '.....###', '..#####.', '..######', '.....###', '.....###',
        '########', '.######.'],
    4: ['##...###', '##...###', '##...###', '##...###', '########', '########', '.....###', '.....###',
        '.....###', '.....###'],
    5: ['########', '########', '###.....', '###.....', '#######.', '########', '.....###', '.....###',
        '########', '#######.'],
    6: ['.######.', '########', '###.....', '###.....', '#######.', '########', '###..###', '###..###',
        '########', '.######.'],
    7: ['########', '########', '.....###', '....###.', '...###..', '..###...', '..###...', '..###...',
        '..###...', '..###...'],
    8: ['.######.', '###..###', '###..###', '###..###', '.######.', '########', '###..###', '###..###',
        '########', '.######.'],
    9: ['.######.', '########', '###..###', '###..###', '########', '.#######', '.....###', '.....###',
        '########', '.######.'],
}
TOASTED = (196, 140, 74)


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


def grain(x, y, d):
    """A fixed pseudo-random value per pixel, so the texture never flickers."""
    h = (x * 73856093) ^ (y * 19349663) ^ (d * 83492791)
    h = (h ^ (h >> 13)) * 1274126177 & 0xffffffff
    return (h >> 8) % 100


def cereal(d):
    out, shade, base, light = (mix(c, TOASTED, 0.18) for c in PAL[d])
    toast = mix(shade, (110, 64, 30), 0.45)
    sugar = mix(light, (255, 255, 255), 0.6)
    rows = CHUNKY[d]
    gw, gh = len(rows[0]), len(rows)
    img = Image.new("RGBA", (gw + 2, gh + 2), (0, 0, 0, 0))
    px = img.load()

    def f(x, y):
        return 0 <= y < gh and 0 <= x < gw and rows[y][x] == "#"

    for y in range(-1, gh + 1):
        for x in range(-1, gw + 1):
            if f(x, y):
                lit = not f(x, y - 1) or not f(x - 1, y)
                dark = not f(x, y + 1) or not f(x + 1, y)
                col = light if lit and not dark else shade if dark and not lit else base
                g = grain(x, y, d)
                if not lit and not dark:
                    # the puffed surface: dimples and bumps, a few toasted spots
                    col = (toast if g < 13 else mix(base, shade, 0.6) if g < 40
                           else mix(base, light, 0.6) if g > 74 else base)
                elif lit and g < 20:
                    col = sugar
                elif dark and g < 25:
                    col = toast
                px[x + 1, y + 1] = col + (255,)
            elif any(f(x + dx, y + dy) for dx, dy in N8):
                # a crumbly rim: here and there a little lighter
                px[x + 1, y + 1] = (mix(out, shade, 0.35) if grain(x, y, d + 17) < 18 else out) + (255,)
    return img


# The bowl Isaac holds, drawn the Isaac way at the user's request (2026-11-24):
# a cream ceramic bowl with a muted blue band and a foot, a near-black outline
# round it, lit from the top left, grimy shade on the right and underneath.
# It comes in three parts drawn over one another: its far half with the empty
# inside, the milk (drawn only while milk is held, so with none the bowl is
# plainly empty), and its near half drawn over the cereal in it.
BOWL_W, BOWL_H = 56, 28
B_CX, B_RC = 28.0, 8.0                 # centre column, rim centre row
B_RX, B_RY = 26.0, 7.0                 # outer rim
B_IRX, B_IRY, B_IOFF = 23.0, 5.0, 0.3  # the opening
B_MRX, B_MRY, B_MOFF = 21.5, 4.2, 0.9  # the milk surface, just under the rim
B_DEPTH = 15.5                         # how far the body reaches below the rim centre
B_FOOT = (22.5, 25.5, 9.5)             # foot rows (from, to) and half width
BOWL_C = {
    "rim_hi": (246, 240, 226), "rim": (226, 216, 198), "rim_sh": (196, 184, 166),
    "wall": (204, 192, 174), "wall_sh": (176, 162, 146), "floor": (156, 142, 128), "deep": (122, 108, 98),
    "body_hi": (240, 232, 216), "body": (214, 202, 184), "body_sh": (172, 158, 142), "body_dk": (138, 124, 112),
    "band": (98, 126, 166), "band_sh": (68, 90, 128),
    "foot": (178, 164, 148), "foot_sh": (140, 126, 114),
    "milk": (246, 244, 236), "milk_hi": (255, 255, 252), "milk_sh": (216, 216, 222), "milk_edge": (230, 228, 228),
}


def _in(fx, fy, cx, cy, rx, ry):
    return ((fx - cx) / rx) ** 2 + ((fy - cy) / ry) ** 2 <= 1


def _bowl_cells():
    cat = {}
    for y in range(BOWL_H):
        for x in range(BOWL_W):
            fx, fy = x + 0.5, y + 0.5
            if _in(fx, fy, B_CX, B_RC + B_IOFF, B_IRX, B_IRY):
                cat[x, y] = "in"
            elif _in(fx, fy, B_CX, B_RC, B_RX, B_RY):
                cat[x, y] = "rimB" if fy < B_RC + B_IOFF else "rimF"
            elif fy >= B_RC and _in(fx, fy, B_CX, B_RC, B_RX, B_DEPTH):
                cat[x, y] = "body"
            elif B_FOOT[0] <= fy <= B_FOOT[1] and abs(fx - B_CX) <= B_FOOT[2]:
                cat[x, y] = "foot"
    return cat


def bowl_parts():
    """(far half with the empty inside, milk, near half), each BOWL_W x BOWL_H."""
    C = BOWL_C
    cat = _bowl_cells()
    back, milk, front = (Image.new("RGBA", (BOWL_W, BOWL_H), (0, 0, 0, 0)) for _ in range(3))
    pb, pm, pf = back.load(), milk.load(), front.load()
    for y in range(BOWL_H):
        for x in range(BOWL_W):
            c = cat.get((x, y))
            t = (x + 0.5 - B_CX) / B_RX
            fx, fy = x + 0.5, y + 0.5
            if c == "in":
                # the far wall lit, the bottom in shade, darkest under the near rim
                if cat.get((x, y - 1)) == "rimB":
                    col = C["wall_sh"]
                elif fy < B_RC + B_IOFF - 0.5:
                    col = C["wall"] if t < 0.45 else C["wall_sh"]
                elif cat.get((x, y + 1)) == "rimF" or cat.get((x, y + 2)) == "rimF":
                    col = C["deep"]
                else:
                    col = C["floor"] if t < 0.4 else C["deep"]
                pb[x, y] = col + (255,)
                if _in(fx, fy, B_CX, B_RC + B_MOFF, B_MRX, B_MRY):
                    if not _in(fx, fy - 1, B_CX, B_RC + B_MOFF, B_MRX, B_MRY):
                        mc = C["milk_sh"]          # in the far rim's shadow
                    elif _in(fx, fy, B_CX - 8, B_RC - 0.2, 6.5, 1.1):
                        mc = C["milk_hi"]          # the sheen, top left
                    elif t > 0.55 or not _in(fx, fy + 1, B_CX, B_RC + B_MOFF, B_MRX, B_MRY):
                        mc = C["milk_edge"]
                    else:
                        mc = C["milk"]
                    pm[x, y] = mc + (255,)
            elif c == "rimB":
                pb[x, y] = (C["rim"] if t < 0.5 else C["rim_sh"]) + (255,)
            elif c == "rimF":
                if cat.get((x, y - 1)) == "in":
                    col = C["rim_sh"]                # where the near rim meets the inside
                else:
                    col = C["rim_hi"] if t < -0.2 else C["rim"] if t < 0.55 else C["rim_sh"]
                pf[x, y] = col + (255,)
            elif c == "body":
                band = B_RC + 5.0 <= fy <= B_RC + 6.9
                low = not _in(fx, fy + 1.5, B_CX, B_RC, B_RX, B_DEPTH)
                if band:
                    col = C["band"] if t < 0.35 else C["band_sh"]
                elif t < -0.62:
                    col = C["body_hi"]
                elif t > 0.5 or low:
                    col = C["body_dk"] if (t > 0.5 and low) else C["body_sh"]
                else:
                    col = C["body"]
                pf[x, y] = col + (255,)
            elif c == "foot":
                pf[x, y] = (C["foot"] if t < 0.15 else C["foot_sh"]) + (255,)
            elif any(cat.get((x + dx, y + dy)) for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]):
                (pb if fy < B_RC else pf)[x, y] = INK + (255,)
    # a glint of glaze on the lit side
    for gx, gy in ((int(B_CX - 20), int(B_RC + 2)), (int(B_CX - 19), int(B_RC + 2)), (int(B_CX - 20), int(B_RC + 3))):
        if cat.get((gx, gy)) == "body":
            pf[gx, gy] = (255, 252, 244, 255)
    return back, milk, front


CARTON = ['..OOOO..', '.OWWWWO.', 'OWWWWWGO', 'OOOOOOOO', 'OWWWWWGO', 'OWBBBBGO', 'OWBBBBGO', 'OWWWWWGO',
          'OWWWWWGO', 'OOOOOOOO']
CARTON_PAL = {"O": INK, "W": (240, 240, 244), "G": (176, 180, 196), "B": (96, 140, 206)}
UNKNOWN = ['.OOOOOOOOOOOOOOOOOO.'] + ['O' + 'G' * 18 + 'O'] * 18 + ['.OOOOOOOOOOOOOOOOOO.']
QMARK = ['..WWWW..', '.WW..WW.', '.....WW.', '....WW..', '...WW...', '...WW...', '........', '...WW...']
SPARKLE = ['...W...', '...W...', '..WWW..', 'WWWWWWW', '..WWW..', '...W...', '...W...']


def paint(img, rows, at, pal):
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in pal:
                px[at[0] + x, at[1] + y] = pal[ch] + (255,)


def outline_silhouette(img, passes=2):
    """Isaac's outline: near-black, two pixels round the whole silhouette."""
    for _ in range(passes):
        src = img.copy().load()
        px = img.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                if src[x, y][3]:
                    continue
                if any(0 <= x + dx < w and 0 <= y + dy < h and src[x + dx, y + dy][3]
                       for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]):
                    px[x, y] = OUTLINE + (255,)


# ------------------------------------------------------------------ icon
BOX_DIGITS = {0: ['###', '#.#', '#.#', '#.#', '###'], 2: ['###', '..#', '###', '#..', '###'],
              5: ['###', '#..', '###', '..#', '###']}


def icon():
    """A cereal box as sold in shops (user request 2026-11-24): an original
    generic box, front with a label reading 025 (Breakfast is item 025) and a
    bowl of cereal, the right side in shade, the top flaps closed. Kept to
    about 22x24 with its outline (user request: smaller than the first draft,
    which filled 27x29), drawn on the 32x32 grid."""
    from PIL import ImageDraw
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    red, red_light, red_dark = (204, 62, 50), (232, 98, 78), (168, 44, 36)
    side, side_dark = (148, 38, 32), (118, 28, 24)
    top, top_dark = (238, 132, 104), (204, 96, 74)
    t = 9      # top of the front face
    b = 26     # bottom of the front face
    # faces: front (x 8-20), right side receding up (x 21-25), top
    draw.polygon([(8, t), (20, t), (20, b), (8, b)], fill=red + (255,))
    draw.polygon([(21, t), (25, t - 2), (25, b - 2), (21, b)], fill=side + (255,))
    draw.polygon([(8, t - 1), (11, t - 3), (25, t - 3), (21, t - 1)], fill=top + (255,))
    px = img.load()
    for y in range(t, b + 1):
        px[8, y] = red_light + (255,)
        px[20, y] = red_dark + (255,)
    for y in range(t - 2, b - 1):
        px[25, y] = side_dark + (255,)
    for x in range(10, 23):
        px[x, t - 2] = top_dark + (255,)        # the seam of the closed flaps
    # the label: a cream band with 025 in the digits' own colours
    for y in range(t + 2, t + 9):
        for x in range(9, 20):
            px[x, y] = ((250, 236, 200) if t + 2 < y < t + 8 else (226, 206, 160)) + (255,)
    for i, d in enumerate((0, 2, 5)):
        ink = mix(PAL[d][0], PAL[d][1], 0.35)
        for y, row in enumerate(BOX_DIGITS[d]):
            for x, ch in enumerate(row):
                if ch == "#":
                    px[9 + i * 4 + x, t + 3 + y] = ink + (255,)
    # the bowl on the front, with cereal on the milk
    cy = t + 12.6
    for y in range(t + 11, b):
        for x in range(9, 20):
            fx, fy = x + 0.5 - 14.5, y + 0.5 - cy
            if fy < 0 and (fx / 4.8) ** 2 + (fy / 1.3) ** 2 <= 1:
                px[x, y] = (246, 246, 250) + (255,)
            elif fy >= 0 and (fx / 4.8) ** 2 + (fy / 3.6) ** 2 <= 1:
                px[x, y] = ((104, 146, 210) if y == t + 14 else (230, 230, 238) if fx < 1.5 else (176, 180, 196)) + (255,)
    for x, d in ((11, 1), (13, 4), (15, 6), (17, 2)):
        px[x, t + 11] = PAL[d][2] + (255,)
        px[x + 1 if d in (4, 2) else x, t + 10 if d in (4, 2) else t + 11] = PAL[d][1] + (255,)
    # the side's nutrition panel
    for y in range(t + 3, t + 10):
        for x in range(22, 24):
            px[x, y - (x - 21) // 2] = ((236, 226, 210) if y % 2 else (200, 188, 170)) + (255,)
    # a dark line between the faces, then the two-pixel outline round it all
    for y in range(t, b + 1):
        px[21, y] = INK + (255,)
    for x in range(8, 21):
        px[x, t] = mix(red, INK, 0.55) + (255,)
    outline_silhouette(img, 2)
    return img


# ------------------------------------------------------------------ pickups
CELL = 16          # one cell a digit in the pickup sheet
PIVOT = (8, 13)    # bottom centre of the cereal in its cell
SPARK_Y = 16       # the sparkle shown as it is collected (row under the digits)


def pickup_sheet():
    img = Image.new("RGBA", (CELL * 10, CELL * 2), (0, 0, 0, 0))
    for d in range(10):
        img.alpha_composite(cereal(d), (d * CELL + 3, 2))
    paint(img, SPARKLE, (4, SPARK_Y + 4), {"W": (255, 255, 255)})
    return img


def frame(x, y, cell_x, cell_y, w, h, sx=100, sy=100, delay=1, interp=True, alpha=255, visible=True,
          pivot=PIVOT):
    return ('          <Frame XPosition="%d" YPosition="%d" XPivot="%d" YPivot="%d" XCrop="%d" YCrop="%d" '
            'Width="%d" Height="%d" XScale="%d" YScale="%d" Delay="%d" Visible="%s" RedTint="255" '
            'GreenTint="255" BlueTint="255" AlphaTint="%d" RedOffset="0" GreenOffset="0" BlueOffset="0" '
            'Rotation="0" Interpolated="%s" />' % (x, y, pivot[0], pivot[1], cell_x, cell_y, w, h, sx, sy, delay,
                                                   "true" if visible else "false", alpha,
                                                   "true" if interp else "false"))


def animation(name, layers, loop):
    total = max(sum(int(f.split('Delay="')[1].split('"')[0]) for f in frames) for frames in layers.values() if frames)
    out = ['    <Animation Name="%s" FrameNum="%d" Loop="%s">' % (name, total, "true" if loop else "false"),
           '      <RootAnimation>',
           '        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="%d" Visible="true" '
           'RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" '
           'BlueOffset="0" Rotation="0" Interpolated="false" />' % total,
           '      </RootAnimation>', '      <LayerAnimations>']
    for layer_id in sorted(layers):
        frames = layers[layer_id]
        if frames:
            out.append('        <LayerAnimation LayerId="%d" Visible="true">' % layer_id)
            out += frames
            out.append('        </LayerAnimation>')
        else:
            out.append('        <LayerAnimation LayerId="%d" Visible="true" />' % layer_id)
    out += ['      </LayerAnimations>', '      <NullAnimations />', '      <Triggers />', '    </Animation>']
    return out


def pickup_animations(d):
    cx = d * CELL
    body = lambda y, sx=100, sy=100, delay=1, interp=True: frame(0, y, cx, 0, CELL, CELL, sx, sy, delay, interp)
    # Appear: a hop like the vanilla key's, squashing as it lands.
    appear = [body(0, 60, 140, 2), body(0, 30, 190, 2), body(-14, 130, 80, 2), body(-20, 100, 100, 3),
              body(-12, 90, 110, 2), body(0, 140, 65, 2), body(0, 80, 120, 2), body(0, 108, 94, 2),
              body(0, 100, 100, 1, False)]
    idle = [body(0, delay=60, interp=False)]
    glint = [frame(0, 0, 0, 0, 1, 1, delay=50, interp=False, visible=False),
             frame(-2, -10, 4 * 1, SPARK_Y + 4 + 3, 1, 1, delay=3, interp=False, pivot=(0, 0)),
             frame(-2, -10, 4 * 1, SPARK_Y + 4 + 3, 1, 1, delay=7, interp=False, visible=False, pivot=(0, 0))]
    # Collect: stretched up and thinned like the key, then a sparkle where it was.
    collect = [body(0, 100, 100, 1), body(0, 110, 90, 1), body(0, 170, 80, 1), body(0, 220, 40, 1),
               body(0, 400, 15, 1), frame(0, 0, cx, 0, CELL, CELL, delay=7, interp=False, visible=False)]
    spark = [frame(0, 0, 0, 0, 1, 1, delay=5, interp=False, visible=False),
             frame(0, -6, 0, SPARK_Y, CELL, CELL, 100, 100, 3, False),
             frame(0, -8, 0, SPARK_Y, CELL, CELL, 70, 70, 3, False, alpha=160)]
    return [
        animation("Appear", {0: appear, 1: []}, False),
        animation("Idle", {0: idle, 1: glint}, True),
        animation("Collect", {0: collect, 1: spark}, False),
    ]


def pickup_anm2(d):
    lines = ['<AnimatedActor>', '  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />', '  <Content>',
             '    <Spritesheets>', '      <Spritesheet Id="0" Path="items/pick ups/pickup_conch_cereal.png" />',
             '    </Spritesheets>', '    <Layers>', '      <Layer Id="0" Name="body" SpritesheetId="0" />',
             '      <Layer Id="1" Name="effect" SpritesheetId="0" />', '    </Layers>', '    <Nulls />',
             '    <Events />', '  </Content>', '  <Animations DefaultAnimation="Idle">']
    for anim in pickup_animations(d):
        lines += anim
    lines += ['  </Animations>', '</AnimatedActor>', '']
    return "\n".join(lines)


# ------------------------------------------------------------------ UI
# Sheet layout (x, y, w, h) for the UI parts; each frame's pivot is its top left.
UI_PARTS = {
    "BowlBack": (0, 0, 56, 28),
    "BowlFront": (56, 0, 56, 28),
    "Milk": (100, 28, 56, 28),  # drawn between the halves only while milk is held
    "Ring": (112, 0, 9, 9),
    "Carton": (122, 0, 8, 10),
    "Unknown": (132, 0, 20, 20),
    "ArrowLR": (0, 44, 13, 9),
    "ArrowUp": (14, 44, 9, 9),
    "ArrowDown": (24, 44, 9, 9),
    "Empty": (159, 59, 1, 1),   # a clear pixel: what Isaac lifts while the mod draws the bowl
}
DIGIT_Y = 30       # the ten digits, 10x12 each, in a row under the bowl
DIGIT_W, DIGIT_H = 10, 12

# The picker's keys drawn as arrows, since "<>", "^" and "v" in the hint did
# not read as arrows (user screenshot 2026-11-24).
LEFT = ['...#', '..##', '.###', '####', '.###', '..##', '...#']
RIGHT = [row[::-1] for row in LEFT]
ARROW_LR = [l + '...' + r for l, r in zip(LEFT, RIGHT)]
ARROW_UP = ['...#...', '..###..', '.#####.', '#######', '..###..', '..###..', '..###..']
ARROW_DOWN = ARROW_UP[::-1]


def arrow(rows):
    """A key arrow: light fill, the ink outline round it."""
    w, h = len(rows[0]), len(rows)
    img = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    px = img.load()
    cells = {(x, y) for y, row in enumerate(rows) for x, c in enumerate(row) if c == "#"}
    for y in range(-1, h + 1):
        for x in range(-1, w + 1):
            if (x, y) in cells:
                px[x + 1, y + 1] = ((255, 250, 238) if y < h // 2 else (226, 218, 204)) + (255,)
            elif any((x + dx, y + dy) in cells for dx, dy in N8):
                px[x + 1, y + 1] = INK + (255,)
    return img


def ui_sheet():
    img = Image.new("RGBA", (160, 60), (0, 0, 0, 0))
    img.alpha_composite(arrow(ARROW_LR), UI_PARTS["ArrowLR"][:2])
    img.alpha_composite(arrow(ARROW_UP), UI_PARTS["ArrowUp"][:2])
    img.alpha_composite(arrow(ARROW_DOWN), UI_PARTS["ArrowDown"][:2])
    back, milk, front = bowl_parts()
    img.alpha_composite(back, UI_PARTS["BowlBack"][:2])
    img.alpha_composite(front, UI_PARTS["BowlFront"][:2])
    img.alpha_composite(milk, UI_PARTS["Milk"][:2])
    img.alpha_composite(puffy(RING, GOLD), (112, 0))
    paint(img, CARTON, (122, 0), CARTON_PAL)
    paint(img, UNKNOWN, (132, 0), {"O": INK, "G": (92, 84, 104)})
    paint(img, QMARK, (138, 6), {"W": (240, 236, 228)})
    for d in range(10):
        img.alpha_composite(cereal(d), (d * DIGIT_W, DIGIT_Y))
    return img


def ui_anm2():
    lines = ['<AnimatedActor>', '  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />', '  <Content>',
             '    <Spritesheets>', '      <Spritesheet Id="0" Path="conch_cereal_ui.png" />', '    </Spritesheets>',
             '    <Layers>', '      <Layer Id="0" Name="part" SpritesheetId="0" />', '    </Layers>', '    <Nulls />',
             '    <Events />', '  </Content>', '  <Animations DefaultAnimation="Digit">']
    digits = [frame(0, 0, d * DIGIT_W, DIGIT_Y, DIGIT_W, DIGIT_H, delay=1, interp=False, pivot=(0, 0))
              for d in range(10)]
    lines += animation("Digit", {0: digits}, False)
    for name, (x, y, w, h) in UI_PARTS.items():
        lines += animation(name, {0: [frame(0, 0, x, y, w, h, delay=1, interp=False, pivot=(0, 0))]}, False)
    lines += ['  </Animations>', '</AnimatedActor>', '']
    return "\n".join(lines)


def main():
    os.makedirs(PREVIEW, exist_ok=True)
    art = icon()
    art.save(os.path.join(GFX, "items", "collectibles", "cereal.png"))
    sheet = pickup_sheet()
    sheet.save(os.path.join(GFX, "items", "pick ups", "pickup_conch_cereal.png"))
    for d in range(10):
        path = os.path.join(GFX, "005.7792_conch_cereal_%d.anm2" % d)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(pickup_anm2(d))
    ui = ui_sheet()
    ui.save(os.path.join(GFX, "ui", "conch_cereal_ui.png"))
    with open(os.path.join(GFX, "ui", "conch_cereal_ui.anm2"), "w", encoding="utf-8", newline="\n") as f:
        f.write(ui_anm2())
    for name, im, k in (("icon_x10.png", art, 10), ("pickups_x6.png", sheet, 6), ("ui_x5.png", ui, 5)):
        big = im.resize((im.width * k, im.height * k), Image.NEAREST)
        bg = Image.new("RGBA", big.size, (70, 60, 56, 255))
        bg.alpha_composite(big)
        bg.save(os.path.join(PREVIEW, name))
    print("wrote cereal.png, pickup_conch_cereal.png/.anm2, conch_cereal_ui.png/.anm2; previews in", PREVIEW)


if __name__ == "__main__":
    main()
