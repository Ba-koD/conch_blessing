"""선녀 (Heavenly Maiden): the Magic Conch's positive answer to Succubus
(user concept 2026-11-13). Authored directly on the native 32x32 grid.

    python docs/previews/seonnyeo/author.py        writes the review sheets
                                                   to .tmp/seonnyeo/
    python docs/previews/seonnyeo/author.py apply  also writes the icon, the
                                                   familiar sheet and anm2
"""
import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, ".tmp", "seonnyeo")
VANILLA = os.path.abspath(os.path.join(ROOT, "..", "..", "extracted_resources", "resources", "gfx"))

PALETTE = {
    ".": (0, 0, 0, 0),
    "K": (28, 20, 30, 255),     # outline
    "H": (40, 34, 50, 255),     # hair
    "h": (96, 88, 120, 255),    # hair sheen
    "S": (250, 222, 206, 255),  # skin
    "s": (226, 182, 170, 255),  # skin shade
    "E": (74, 46, 52, 255),     # closed eyes
    "R": (222, 56, 70, 255),    # 곤지, red stripe
    "r": (246, 172, 178, 255),  # cheek blush
    "M": (200, 112, 120, 255),  # smile corners
    "e": (150, 110, 112, 255),  # thin brows, soft so the closed eyes lead
    "Q": (214, 52, 70, 255),    # lips
    "q": (236, 118, 128, 255),  # lower lip, lighter
    "m": (234, 170, 166, 255),  # a mouth corner, barely lifted
    "j": (246, 194, 192, 255),  # soft 연지
    "Y": (252, 214, 82, 255),   # 색동 yellow
    "N": (86, 184, 122, 255),   # 색동 green
    "U": (92, 146, 226, 255),   # 색동 blue
    "G": (250, 210, 92, 255),   # gold band
    "g": (196, 146, 50, 255),   # gold shade
    "W": (250, 250, 247, 255),  # white robe
    "w": (206, 212, 230, 255),  # robe shade
    "V": (72, 176, 156, 255),   # collar trim
    "P": (240, 140, 168, 255),  # sash
    "p": (198, 96, 128, 255),   # sash shade
    "T": (214, 72, 104, 255),   # sash tie
    "L": (255, 255, 255, 235),  # scarf, lit edge
    "B": (232, 240, 252, 175),  # scarf, translucent body
    "b": (172, 192, 224, 225),  # scarf, shaded edge or inner side
    "o": (118, 142, 186, 215),  # scarf outline: pale, so the silk reads light
    "f": (242, 248, 255, 140),  # the silk wrapped behind her: faint, no outline
    "F": (208, 222, 246, 160),  # its shaded edge
}


def blank():
    return [["."] * 32 for _ in range(32)]


def put(g, y, cells):
    """cells: 'x:ch' runs, e.g. put(g, 3, {7: 'K', (8, 10): 'H'})"""
    for key, ch in cells.items():
        x0, x1 = key if isinstance(key, tuple) else (key, key)
        for x in range(x0, x1 + 1):
            g[y][x] = ch


# The familiar (user direction 2026-11-13: more like Isaac's own familiars).
# Seraphim, Guardian Angel and the Brother Bobby family are a big round head
# over a small body that tapers to a point, drawn at 100% with the
# near-black (8, 0, 0) outline two pixels thick at the sides and flat colour
# in two or three tones lit from the top left; Isaac's own skin tones and
# Eve's dark hair are used here. 선녀 keeps what the user chose: small round
# 쌍계 with a hole, the gold band with its red jewel and 색동, 곤지, closed
# lowered eyes and a small red mouth, a pink jeogori with a white 동정, hands
# folded into 색동 cuffs and the white skirt floating to a point. Her body
# stays still; only her silk moves (user request).
FAMILIAR_PALETTE = {
    ".": (0, 0, 0, 0),
    "K": (8, 0, 0, 255),        # the vanilla outline
    "H": (51, 51, 51, 255),     # hair (Eve's)
    "D": (31, 31, 31, 255),     # hair shade (Eve's)
    "l": (92, 90, 104, 255),    # hair sheen
    "S": (227, 198, 197, 255),  # Isaac's skin
    "s": (207, 156, 155, 255),  # its shade
    "E": (74, 46, 52, 255),     # closed eyes, as on the icon
    "R": (214, 32, 50, 255),    # 곤지, lips, jewel, the tie, 색동 red
    "j": (236, 150, 150, 255),  # 연지
    "G": (248, 204, 72, 255),   # gold band, 색동 yellow
    "U": (72, 132, 222, 255),   # 색동 blue
    "N": (78, 178, 112, 255),   # 색동 green
    "P": (242, 150, 178, 255),  # jeogori
    "p": (206, 104, 140, 255),  # its shade
    "W": (252, 252, 252, 255),  # skirt, 동정
    "w": (192, 198, 216, 255),  # its shade
    # the 피백: fine translucent silk with a soft edge instead of an outline
    "L": (255, 255, 255, 235),  # the sheen along it
    "B": (210, 232, 255, 172),  # its translucent body, faintly sky
    "F": (172, 200, 242, 185),  # the side turned from the light, a fold
    "o": (150, 186, 240, 118),  # its soft edge, barely there
    "t": (230, 242, 255, 110),  # the end, thinning and fading
    "T": (196, 216, 248, 90),   # the end's soft edge
}

# centred on the frame (pivot 16, 16), where her light is measured from
FAMILIAR_BODY = [
    "................................",
    ".......KKK............KKK.......",  # the 쌍계, small round loops with a hole
    "......KlHHK..........KHHDK......",
    "......KH.HK.KKKKKKKK.KH.DK......",
    ".......KHHKllHHHHHHHHKHDK.......",
    ".......KKKHlHGGRRGGHHDKKK.......",  # the gold band, its red jewel
    "........KHNUGHHHHHHGUNDK........",  # 색동 at its ends
    ".......KHHHHHHHHHHHHHHDDK.......",
    ".......KHHHHSSSSSSSSHHHDK.......",
    ".......KHHHSSSSRRSSSSHHDK.......",  # 곤지
    ".......KHHSESSESSESSEsHDK.......",  # closed eyes, lowered and calm
    ".......KHHSSEESSSSEESsHDK.......",
    ".......KHHSjSSSSSSSSjsHDK.......",  # 연지
    ".......KHHHSSSSRRSSSsHHDK.......",  # a small red mouth
    "........KHHKSSSSSSSsKHDK........",
    ".........KHHKKssssKKHDK.........",
    "........KPPPPPWssWPPPPpK........",  # the jeogori and its white 동정
    ".......KPPPPPPPWWPPPPPppK.......",
    ".......KPPPpPPPRRPPPpPPpK.......",  # the red tie
    ".......KPPPPRGUSSUGRPPppK.......",  # hands folded into 색동 cuffs
    "........KPPPRGUssUGRPppK........",
    ".........KpKWWWWWWWWKpK.........",
    "..........KWWWWWWWWWwK..........",  # the white skirt, floating to a point
    "..........KWWWWWWWWwwK..........",
    "...........KWWWWWWwwK...........",
    "...........KWWWWWWwwK...........",
    "............KWWWWwwK............",
    ".............KWWwwK.............",
    "..............KwwK..............",
    "...............KK...............",
    "................................",
    "................................",
]


def sym(g, y, x0, x1, ch, mirror_ch=None):
    """x0..x1 on the left half and its mirror on the right."""
    for x in range(x0, x1 + 1):
        g[y][x] = ch
        g[y][31 - x] = mirror_ch or ch


def span(g, y, x0, x1, ch):
    for x in range(x0, x1 + 1):
        g[y][x] = ch


# The icon's face: an oval, widest across the cheekbones, tapering to a small
# chin; the hair covers the crown and sweeps down over the forehead corners
# so the forehead stays narrow, its top level under the hair with no parting
# showing (user corrections 2026-11-13: first a point, then a parting line).
# (row, left x of the skin); the right side mirrors it.
ICON_FACE = {11: 13, 12: 12, 13: 11, 14: 10, 15: 9, 16: 9, 17: 9, 18: 9,
             19: 10, 20: 10, 21: 11, 22: 12, 23: 13, 24: 14}


def face_rows():
    """The item icon (user choice 2026-11-13, draft A): 선녀's face close up.
    The first face was too wide and boxy, its tall loops and straight band
    read as horns over a hood and its smile was too much. This one is an oval
    face with a gentle, holy look (closed eyes lowered like a bodhisattva's,
    a small closed mouth with level corners), hair covering the crown and
    swept down over the forehead corners and the ears, small round 쌍계 on the
    crown and a slim gold band."""
    g = blank()
    # hair: the dome, outlined, then down beside the cheeks and behind the jaw
    dome = {6: (10, 15), 7: (8, 15), 8: (7, 15), 9: (6, 15), 10: (6, 15), 11: (5, 15), 12: (5, 15)}
    for y, (x0, x1) in dome.items():
        sym(g, y, x0, x1, "H")
        g[y][x0 - 1] = "K"
        g[y][32 - x0] = "K"
    sym(g, 5, 10, 15, "K")
    sym(g, 6, 8, 9, "K")
    sym(g, 7, 7, 7, "K")
    for y in range(13, 28):
        x0 = 5 if y < 22 else 4
        inner = (ICON_FACE[y] - 1) if y in ICON_FACE else 13
        if y >= 19:
            inner = ICON_FACE[y] - 2 if y in ICON_FACE else 12
        for x in range(x0, inner + 1):
            if g[y][x] == ".":
                g[y][x] = "H"
            if g[y][31 - x] == ".":
                g[y][31 - x] = "H"
        g[y][x0 - 1] = "K"
        g[y][32 - x0] = "K"
    for y in range(25, 28):
        for x in range(4, 14):
            if g[y][x] == ".":
                g[y][x] = "H"
            if g[y][31 - x] == ".":
                g[y][31 - x] = "H"
    for (y, x) in ((7, 10), (7, 11), (8, 9), (8, 10), (9, 8), (10, 7), (11, 6), (12, 6), (13, 6), (14, 6)):
        g[y][x] = "h"
    # the face
    for y, x0 in ICON_FACE.items():
        sym(g, y, x0, 15, "S")
        g[y][31 - x0] = "s"         # light from the upper left
    for y in range(19, 25):
        g[y][ICON_FACE[y] - 1] = "K"
        g[y][32 - ICON_FACE[y]] = "K"
    sym(g, 25, 14, 15, "K")
    g[24][14], g[24][17] = "K", "K"
    sym(g, 24, 15, 15, "S")
    g[24][16] = "s"
    sym(g, 12, 15, 15, "R")      # 곤지
    span(g, 14, 11, 13, "e")     # long soft brows
    span(g, 14, 18, 20, "e")
    # closed eyes, lowered: a calm lid with the lashes resting a pixel lower
    # in the middle, never the arched happy squint
    span(g, 16, 10, 13, "E")
    span(g, 16, 18, 21, "E")
    span(g, 17, 11, 12, "E")
    span(g, 17, 19, 20, "E")
    span(g, 18, 10, 11, "j")     # faint 연지
    span(g, 18, 20, 21, "j")
    g[19][16] = "s"              # the nose
    # a small closed mouth, its corners level and soft: a quiet smile
    g[21][14], g[21][17] = "m", "m"
    span(g, 21, 15, 16, "Q")
    sym(g, 26, 14, 15, "s")      # the neck
    sym(g, 27, 14, 15, "s")
    # the slim gold band on the crown, a red jewel at its middle and a few
    # 색동 stripes either side
    for y, (x0, x1) in {7: (8, 9), 6: (10, 12), 5: (13, 14)}.items():
        sym(g, y, x0, x1, "G")
    sym(g, 5, 15, 15, "R")
    g[6][10], g[6][11], g[6][12] = "N", "U", "Y"
    g[6][21], g[6][20], g[6][19] = "N", "U", "Y"
    # the 쌍계: small round rings set back on the crown, a hole in each
    for y, (x0, x1) in {0: (9, 11), 1: (8, 12), 2: (8, 12), 3: (9, 12), 4: (10, 13)}.items():
        sym(g, y, x0, x1, "H")
        g[y][x0 - 1] = "K"
        g[y][32 - x0] = "K"
    sym(g, 0, 9, 11, "K")
    sym(g, 2, 10, 10, ".")
    sym(g, 1, 9, 9, "h", "H")
    g[1][22] = "h"
    # the hair falls behind the shoulders; the white 동정, teal collar and
    # pink jeogori
    span(g, 28, 4, 27, "H")
    g[28][3], g[28][28] = "K", "K"
    sym(g, 28, 13, 13, "W")
    sym(g, 28, 14, 15, "S")
    span(g, 29, 9, 11, "P")
    g[29][12], g[29][13] = "W", "V"
    span(g, 29, 14, 17, "S")
    g[29][18], g[29][19] = "V", "W"
    span(g, 29, 20, 22, "P")
    span(g, 29, 4, 8, "H")
    span(g, 29, 23, 27, "H")
    g[29][3], g[29][28] = "K", "K"
    span(g, 30, 7, 12, "P")
    g[30][13], g[30][14] = "W", "V"
    span(g, 30, 15, 16, "S")
    g[30][17], g[30][18] = "V", "W"
    span(g, 30, 19, 24, "P")
    span(g, 30, 3, 6, "H")
    span(g, 30, 25, 28, "H")
    g[30][2], g[30][29] = "K", "K"
    span(g, 31, 5, 13, "P")
    g[31][14] = "W"
    span(g, 31, 15, 16, "V")
    g[31][17] = "W"
    span(g, 31, 18, 26, "P")
    span(g, 31, 2, 4, "H")
    span(g, 31, 27, 29, "H")
    g[31][1], g[31][30] = "K", "K"
    return ["".join(r) for r in g]


# The icon's silk (`FACE_SILK`): a smooth spline whose width swells and
# thins and which twists once (its shaded inner side shows); the hand-placed
# control points are the art. It is translucent and outlined in pale blue
# rather than black, so it reads as silk, not rope.
import math


def _spline(points, n=600):
    pts = [points[0]] + points + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(n // (len(points) - 1)):
            t = k / (n // (len(points) - 1))
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(points[-1])
    return out


def _width(widths, u):
    f = u * (len(widths) - 1)
    i = min(int(f), len(widths) - 2)
    return widths[i] + (widths[i + 1] - widths[i]) * (f - i)


def scarf_cells(path):
    points, widths, twist = path
    curve = _spline(points)
    cells = {}
    for y in range(32):
        for x in range(32):
            cx, cy = x + 0.5, y + 0.5
            best = None
            for i in range(len(curve) - 1):
                (ax, ay), (bx, by) = curve[i], curve[i + 1]
                dx, dy = bx - ax, by - ay
                L2 = dx * dx + dy * dy or 1e-9
                t = max(0.0, min(1.0, ((cx - ax) * dx + (cy - ay) * dy) / L2))
                px, py = ax + t * dx, ay + t * dy
                d = math.hypot(cx - px, cy - py)
                if best is None or d < best[0]:
                    side = dx * (cy - ay) - dy * (cx - ax)
                    best = (d, (i + t) / (len(curve) - 1), side, dx, dy)
            d, u, side, dx, dy = best
            w = _width(widths, u)
            if d > w / 2:
                continue
            # light from the top left: the edge facing it is lit
            nx, ny = -dy, dx
            facing = (nx * -1 + ny * -1) * (1 if side > 0 else -1)
            if twist[0] <= u <= twist[1]:
                ch = "b"
            elif d > w / 2 - 0.75:
                ch = "L" if facing > 0 else "b"
            else:
                ch = "B"
            cells.setdefault(y, []).append((x, ch))
    return cells


def compose(rows, *scarves):
    grid = [list(r) for r in rows]
    for scarf in scarves:
        for y, cells in scarf.items():
            for x, ch in cells:
                if grid[y][x] == ".":
                    grid[y][x] = ch
    # outline the scarf where it meets the background
    out = [row[:] for row in grid]
    for y in range(32):
        for x in range(32):
            if grid[y][x] != ".":
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 32 and 0 <= ny < 32 and grid[ny][nx] in "LBb":
                    out[y][x] = "o"
                    break
    return ["".join(r) for r in out]


def image(rows, palette=PALETTE):
    assert len(rows) == 32 and all(len(r) == 32 for r in rows), [len(r) for r in rows]
    im = Image.new("RGBA", (32, 32))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            im.putpixel((x, y), palette[ch])
    return im


def review(icon):
    refs = ["collectibles_417_succubus.png", "collectibles_390_seraphim.png",
            "collectibles_112_guardianangel.png", "collectibles_331_godhead.png"]
    scale = 8
    sheet = Image.new("RGBA", (32 * scale * (1 + len(refs)) + 16 * (len(refs) + 2), 32 * scale + 32 + 48),
                      (58, 52, 48, 255))
    x = 16
    for im in [icon] + [Image.open(os.path.join(VANILLA, "items", "collectibles", r)).convert("RGBA") for r in refs]:
        sheet.alpha_composite(im.resize((32 * scale, 32 * scale), Image.NEAREST), (x, 16))
        x += 32 * scale + 16
    # native size, on the game's floor tone
    x = 16
    for k, im in enumerate([icon]):
        sheet.alpha_composite(im, (x, 32 * scale + 32))
        sheet.alpha_composite(im.resize((64, 64), Image.NEAREST), (x + 48, 32 * scale + 24))
    return sheet


# The familiar's silk: one ribbon of even width on each side, like the
# original 피백 (user requests 2026-11-13). It arcs out from behind the
# shoulder over the top beside her head and down the outside, the upper wing
# of a butterfly, tucks in at the shoulder and falls almost straight, not
# bulging out, to an end that thins and fades. Fine silk: a sheen along it
# that crosses to the other side where it turns, a translucent body and a
# soft edge. Her left side as (x, y, colour); the right mirrors it with the
# sheen on the same side, so the pair reads as wings.
SILK_ARC = {
    "open": [
        (3, 8, "L"), (4, 8, "L"), (5, 8, "B"), (6, 8, "B"), (2, 9, "L"), (3, 9, "B"),
        (4, 9, "F"), (5, 9, "F"), (6, 9, "F"), (1, 10, "L"), (2, 10, "B"), (1, 11, "L"),
        (2, 11, "B"), (1, 12, "B"), (2, 12, "L"), (1, 13, "F"), (2, 13, "L"), (1, 14, "F"),
        (2, 14, "L"), (2, 15, "F"), (3, 15, "L"), (3, 16, "L"), (4, 16, "B"), (4, 17, "L"),
        (5, 17, "B"), (5, 18, "L"), (6, 18, "B"),
    ],
    "shut": [
        (4, 8, "L"), (5, 8, "B"), (6, 8, "B"), (3, 9, "L"), (4, 9, "B"), (5, 9, "F"),
        (6, 9, "F"), (2, 10, "L"), (3, 10, "B"), (2, 11, "L"), (3, 11, "B"), (2, 12, "B"),
        (3, 12, "L"), (2, 13, "F"), (3, 13, "L"), (2, 14, "F"), (3, 14, "L"), (3, 15, "F"),
        (4, 15, "L"), (4, 16, "L"), (5, 16, "B"), (4, 17, "L"), (5, 17, "B"), (5, 18, "L"),
        (6, 18, "B"),
    ],
}
# the hanging end, nearly straight: (row, left x, its cells)
SILK_HANG = [(19, 5, 'LB'), (20, 5, 'LB'), (21, 5, 'LB'), (22, 4, 'LB'), (23, 4, 'BL'), (24, 4, 'FL'), (25, 4, 'LB'), (26, 3, 'Lt'), (27, 3, 't'), (28, 3, 't')]
FRAMES = 8
FRAME_DELAY = 3
# the arc breathes and the free end swings out and back, its lower rows a
# frame behind
SILK_ARC_CYCLE = ['open', 'open', 'open', 'shut', 'shut', 'shut', 'shut', 'open']
SILK_TIP = [0, -1, -1, -1, 0, 1, 1, 0]  # outward is negative on her left
# drawn at 100% like the vanilla familiars (80% gave uneven pixels)
ENTITY_SCALE = 100


def silk_cells(k):
    left = {(x, y): ch for x, y, ch in SILK_ARC[SILK_ARC_CYCLE[k]]}
    tip, lag = SILK_TIP[k], SILK_TIP[(k - 1) % FRAMES]
    for y, x, chs in SILK_HANG:
        dx = tip if y >= 26 else (lag if y >= 24 else 0)
        for i, ch in enumerate(chs):
            left[(x + dx + i, y)] = ch
    cells = {}
    for (x, y), ch in left.items():
        cells[(x, y)] = ch
        cells[(31 - x, y)] = ch
    return cells


def familiar_rows(k):
    """Frame k: the still body with the silk behind it and its soft edge."""
    grid = [list(r) for r in FAMILIAR_BODY]
    silk = silk_cells(k)
    for (x, y), ch in silk.items():
        if grid[y][x] == ".":
            grid[y][x] = ch
    out = [r[:] for r in grid]
    for y in range(32):
        for x in range(32):
            if grid[y][x] != ".":
                continue
            near = [silk.get((x + dx, y + dy)) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            if any(c and c in "LBF" for c in near):
                out[y][x] = "o"
            elif "t" in near:
                out[y][x] = "T"
    return ["".join(r) for r in out]


def familiar_frame(k):
    return image(familiar_rows(k), FAMILIAR_PALETTE)


# The silk behind her face on the icon (user request): from behind each
# shoulder it rises past her hair and curls beside the loops, showing only in
# the narrow space either side of her.
FACE_SILK = [
    ([(6.0, 30.5), (3.6, 26.5), (2.0, 22.0), (2.8, 18.0), (1.6, 14.0), (2.4, 10.4), (4.0, 8.2), (5.0, 10.0)],
     [1.2, 1.5, 1.7, 1.4, 1.6, 1.4, 1.2], (0.45, 0.52)),
    ([(25.0, 30.5), (27.4, 26.0), (29.0, 21.6), (28.2, 17.6), (29.4, 13.6), (28.6, 10.0), (27.0, 8.0), (26.0, 9.8)],
     [1.2, 1.5, 1.7, 1.4, 1.6, 1.4, 1.2], (0.55, 0.62)),
]


def icon_image():
    """The item icon: her face close up (`face_rows`)."""
    return image(compose(face_rows(), scarf_cells(FACE_SILK[0]), scarf_cells(FACE_SILK[1])))


# she floats centred on her halo: the frame centre is the entity position
# her body stays still; only her silk moves (user request 2026-11-13)
BOB = [0] * FRAMES
HALO_TINT = (255, 226, 150, 45)  # a little dimmer than first drawn (user request 2026-11-13)


def anm2():
    body = "\n".join(
        f'\t\t\t\t\t<Frame XPosition="0" YPosition="{BOB[k]}" XPivot="16" YPivot="16" XCrop="{32 * k}" YCrop="0" '
        f'Width="32" Height="32" XScale="{ENTITY_SCALE}" YScale="{ENTITY_SCALE}" Delay="{FRAME_DELAY}" Visible="true" RedTint="255" '
        f'GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" '
        f'Interpolated="false"/>' for k in range(FRAMES))
    r, g, b, a = HALO_TINT
    total = FRAMES * FRAME_DELAY
    return f'''<AnimatedActor>
	<Info CreatedBy="ConchBlessing docs/previews/seonnyeo/author.py" Version="1" Fps="30"/>
	<Content>
		<Spritesheets>
			<Spritesheet Id="0" Path="familiar/familiar_seonnyeo.png"/>
			<Spritesheet Id="1" Path="censer halo.png"/>
		</Spritesheets>
		<Layers>
			<Layer Id="0" Name="body" SpritesheetId="0"/>
			<Layer Id="1" Name="halo" SpritesheetId="1"/>
		</Layers>
		<Nulls/>
		<Events/>
	</Content>
	<Animations DefaultAnimation="Float">
		<Animation Name="Float" FrameNum="{total}" Loop="true">
			<RootAnimation>
				<Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="{total}" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false"/>
			</RootAnimation>
			<LayerAnimations>
				<LayerAnimation LayerId="1" Visible="true">
					<Frame XPosition="0" YPosition="0" XPivot="112" YPivot="112" XCrop="0" YCrop="0" Width="224" Height="224" XScale="100" YScale="100" Delay="{total}" Visible="true" RedTint="{r}" GreenTint="{g}" BlueTint="{b}" AlphaTint="{a}" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false"/>
				</LayerAnimation>
				<LayerAnimation LayerId="0" Visible="true">
{body}
				</LayerAnimation>
			</LayerAnimations>
			<NullAnimations/>
			<Triggers/>
		</Animation>
	</Animations>
</AnimatedActor>
'''


RUNTIME = {
    "icon": os.path.join(ROOT, "resources", "gfx", "items", "collectibles", "seonnyeo.png"),
    "sheet": os.path.join(ROOT, "resources", "gfx", "familiar", "familiar_seonnyeo.png"),
    "anm2": os.path.join(ROOT, "resources", "gfx", "seonnyeo.anm2"),
}


def preview_gif(path, seconds=10, fps=15, scale=2):
    """A room-sized preview: the basement floor, her gold halo, her drift
    (speed 2.2 world units an update, turning back 12 units inside the walls;
    she stays upright like the vanilla familiars), Isaac standing still, and
    the tears multiplier he gets. Screen pixels are world
    units x 26/40."""
    from PIL import ImageDraw
    k = 26 / 40
    floor = Image.open(os.path.join(VANILLA, "backdrop", "01_basement_nfloor.png")).convert("RGBA")
    room_w, room_h = 338, 182
    base = Image.new("RGBA", (room_w, room_h))
    base.alpha_composite(floor.crop((0, 0, 169, 182)), (0, 0))
    base.alpha_composite(floor.crop((0, 0, 169, 182)).transpose(Image.FLIP_LEFT_RIGHT), (169, 0))
    halo = Image.open(os.path.join(VANILLA, "censer halo.png")).convert("RGBA")
    r, g, b, a = HALO_TINT
    gold = Image.new("RGBA", halo.size, (r, g, b, 0))
    gold.putalpha(halo.split()[3].point(lambda v: v * a // 255))
    sheet = Image.new("RGBA", (32 * FRAMES, 32))
    for i in range(FRAMES):
        sheet.alpha_composite(familiar_frame(i), (32 * i, 0))
    size = round(32 * ENTITY_SCALE / 100)
    isaac = (room_w * 0.38, room_h * 0.55)
    pos = [room_w * 0.62, room_h * 0.45]
    vel = [2.2 * k * math.cos(math.radians(45)), 2.2 * k * math.sin(math.radians(45))]
    margin = 12 * k
    radius = 87
    frames = []
    for update in range(seconds * 30):
        if pos[0] + vel[0] < margin or pos[0] + vel[0] > room_w - margin:
            vel[0] = -vel[0]
        if pos[1] + vel[1] < margin or pos[1] + vel[1] > room_h - margin:
            vel[1] = -vel[1]
        pos[0] += vel[0]
        pos[1] += vel[1]
        if update % (30 // fps):
            continue
        f = base.copy()
        f.alpha_composite(gold, (round(pos[0]) - 112, round(pos[1]) - 112))
        d = ImageDraw.Draw(f)
        inside = math.hypot(isaac[0] - pos[0], isaac[1] - pos[1]) <= radius
        d.ellipse((isaac[0] - 6, isaac[1] - 3, isaac[0] + 6, isaac[1] + 3), fill=(0, 0, 0, 90))
        d.ellipse((isaac[0] - 7, isaac[1] - 20, isaac[0] + 7, isaac[1] - 6), fill=(236, 196, 186, 255), outline=(30, 20, 24, 255))
        d.text((isaac[0] - 14, isaac[1] - 34), "x1.3" if inside else "x1.0",
               fill=(255, 226, 120, 255) if inside else (230, 230, 230, 255))
        frame = sheet.crop((32 * ((update // FRAME_DELAY) % FRAMES), 0, 32 * ((update // FRAME_DELAY) % FRAMES) + 32, 32))
        frame = frame.resize((size, size), Image.NEAREST)
        pad = Image.new("RGBA", (size * 2, size * 2))
        pad.alpha_composite(frame, (size // 2, size // 2))
        bob = BOB[(update // FRAME_DELAY) % FRAMES]
        f.alpha_composite(pad, (round(pos[0]) - size, round(pos[1]) - size + bob))
        frames.append(f.resize((room_w * scale, room_h * scale), Image.NEAREST).convert("RGB")
                      .quantize(colors=255, method=Image.Quantize.MEDIANCUT))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=round(1000 / fps), loop=0)


def main(apply=False):
    os.makedirs(OUT, exist_ok=True)
    icon = icon_image()
    icon.save(os.path.join(OUT, "icon.png"))
    review(icon).save(os.path.join(OUT, "review.png"))
    sheet = Image.new("RGBA", (32 * FRAMES, 32))
    for k in range(FRAMES):
        sheet.alpha_composite(familiar_frame(k), (32 * k, 0))
    sheet.save(os.path.join(OUT, "familiar.png"))
    strip = Image.new("RGBA", (sheet.width * 8 + 8 * (FRAMES + 1), 32 * 8 + 16), (58, 52, 48, 255))
    for k in range(FRAMES):
        strip.alpha_composite(sheet.crop((32 * k, 0, 32 * k + 32, 32)).resize((256, 256), Image.NEAREST), (8 + k * 264, 8))
    strip.save(os.path.join(OUT, "familiar_review.png"))
    if apply:
        icon.save(RUNTIME["icon"])
        sheet.save(RUNTIME["sheet"])
        with open(RUNTIME["anm2"], "w", encoding="utf-8", newline="\n") as f:
            f.write(anm2())
        for path in RUNTIME.values():
            print(path)
    print(os.path.join(OUT, "review.png"))


if __name__ == "__main__":
    import sys
    main(apply="apply" in sys.argv[1:])
