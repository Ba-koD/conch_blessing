"""선녀 (Heavenly Maiden): the Magic Conch's positive answer to Succubus
(user concept 2026-11-13). Authored directly on the native 32x32 grid.

    python docs/previews/seonnyeo/author.py      writes the review sheet to
                                                 .tmp/seonnyeo/review.png

Nothing here is a runtime asset yet; the user reviews the draft first.
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


def entity_rows(hem="right"):
    """선녀, full length (the familiar): a small oval face under the loops, a
    pink jeogori with 색동 sleeves, a long white skirt floating at the hem."""
    g = blank()
    # Matched to the item icon (user choice 2026-11-13): small round 쌍계 with
    # a hole, leaning a little outward from the crown; a slim gold band with
    # a red jewel and a touch of 색동; hair covering the crown and swept down
    # over the forehead corners; an oval face with calm, lowered closed eyes
    # and a small closed mouth.
    put(g, 0, {(10, 12): "K", (19, 21): "K"})
    put(g, 1, {9: "K", 10: "h", 11: ".", 12: "H", 13: "K", 18: "K", 19: "H", 20: ".", 21: "H", 22: "K"})
    put(g, 2, {9: "K", (10, 12): "H", (13, 18): "K", (19, 21): "H", 22: "K"})
    put(g, 3, {10: "K", 11: "H", 12: "N", (13, 14): "G", (15, 16): "R", (17, 18): "G", 19: "U", 20: "H", 21: "K"})
    # the hair covers the crown down to a small, level forehead
    put(g, 4, {10: "K", 11: "h", 12: "h", (13, 20): "H", 21: "K"})
    put(g, 5, {10: "K", 11: "h", (12, 20): "H", 21: "K"})
    put(g, 6, {10: "K", 11: "h", (12, 20): "H", 21: "K"})
    put(g, 7, {10: "K", 11: "h", 12: "H", (13, 14): "S", (15, 16): "R", (17, 18): "S", 19: "H", 20: "H", 21: "K"})
    put(g, 8, {10: "K", 11: "H", (12, 18): "S", 19: "s", 20: "H", 21: "K"})
    # closed eyes, lowered and calm
    put(g, 9, {10: "K", 11: "H", 12: "S", (13, 14): "E", (15, 16): "S", (17, 18): "E", 19: "s", 20: "H", 21: "K"})
    # faint 연지, the nose's shadow
    put(g, 10, {10: "K", 11: "H", 12: "j", (13, 15): "S", 16: "s", (17, 18): "S", 19: "j", 20: "H", 21: "K"})
    # a small closed mouth
    put(g, 11, {10: "K", 11: "H", (12, 14): "S", (15, 16): "Q", (17, 18): "S", 19: "s", 20: "H", 21: "K"})
    # the jaw narrows to a small chin; the hair falls behind it
    put(g, 12, {10: "K", 11: "H", 12: "K", (13, 17): "S", 18: "s", 19: "K", 20: "H", 21: "K"})
    put(g, 13, {10: "K", (11, 12): "H", 13: "K", (14, 16): "S", 17: "s", 18: "K", (19, 20): "H", 21: "K"})
    # pink jeogori with a white collar and a slender neck; hair over the shoulders
    put(g, 14, {10: "K", 11: "H", 12: "P", 13: "W", (14, 17): "K", 18: "W", 19: "P", 20: "H", 21: "K"})
    put(g, 15, {9: "K", 10: "P", 11: "H", (12, 13): "P", 14: "W", (15, 16): "S", 17: "W", (18, 19): "P", 20: "H", 21: "P", 22: "K"})
    put(g, 16, {8: "K", (9, 10): "P", 11: "H", (12, 14): "P", (15, 16): "W", (17, 19): "P", 20: "H", (21, 22): "p", 23: "K"})
    put(g, 17, {7: "K", (8, 15): "P", 16: "T", (17, 23): "P", 24: "K"})
    # wide sleeves at the sides; the long white skirt below a red tie
    put(g, 18, {6: "K", (7, 9): "P", 10: "K", (11, 15): "W", 16: "T", (17, 20): "W", 21: "K", (22, 23): "P", 24: "p", 25: "K"})
    put(g, 19, {6: "K", (7, 9): "P", 10: "K", (11, 15): "W", 16: "T", (17, 20): "W", 21: "K", (22, 23): "P", 24: "p", 25: "K"})
    put(g, 20, {6: "K", (7, 9): "R", 10: "K", (11, 20): "W", 21: "K", (22, 24): "R", 25: "K"})
    put(g, 21, {6: "K", (7, 9): "Y", 10: "K", (11, 14): "W", 15: "w", (16, 20): "W", 21: "K", (22, 24): "Y", 25: "K"})
    put(g, 22, {6: "K", (7, 9): "U", 10: "K", (11, 14): "W", 15: "w", (16, 19): "W", 20: "w", 21: "K", (22, 24): "U", 25: "K"})
    # hands peeking from the sleeves
    put(g, 23, {7: "K", 8: "S", 9: "K", (10, 14): "W", 15: "w", (16, 19): "W", 20: "w", 21: "W", 22: "K", 23: "S", 24: "K"})
    put(g, 24, {8: "K", 9: "K", (10, 14): "W", 15: "w", (16, 19): "W", 20: "w", 21: "W", 22: "K", 23: "K"})
    # the skirt flares and floats; its hem sways (HEMS)
    put(g, 25, {8: "K", (9, 14): "W", 15: "w", (16, 19): "W", 20: "w", (21, 22): "W", 23: "K"})
    for y, cells in HEMS[hem].items():
        put(g, y, cells)
    return ["".join(r) for r in g]


# The hem as it sways: lifted to her right, level, lifted to her left. The
# shaded side stays on the right (light from the top left).
HEMS = {
    "right": {
        26: {8: "K", (9, 13): "W", 14: "w", (15, 19): "W", 20: "w", (21, 22): "W", 23: "w", 24: "K"},
        27: {7: "K", (8, 13): "W", 14: "w", (15, 20): "W", 21: "w", 22: "W", (23, 24): "w", 25: "K"},
        28: {7: "K", (8, 13): "W", 14: "w", (15, 20): "W", 21: "w", (22, 23): "W", (24, 25): "w", 26: "K"},
        29: {6: "K", (7, 25): "w", 26: "K"},
        30: {(7, 26): "K"},
    },
    "level": {
        26: {7: "K", (8, 13): "W", 14: "w", (15, 19): "W", 20: "w", (21, 22): "W", 23: "w", 24: "K"},
        27: {7: "K", (8, 13): "W", 14: "w", (15, 20): "W", 21: "w", 22: "W", 23: "w", 24: "K"},
        28: {6: "K", (7, 13): "W", 14: "w", (15, 20): "W", 21: "w", (22, 23): "W", 24: "w", 25: "K"},
        29: {6: "K", (7, 24): "w", 25: "K"},
        30: {(6, 25): "K"},
    },
    "left": {
        26: {6: "K", (7, 13): "W", 14: "w", (15, 19): "W", 20: "w", 21: "W", 22: "w", 23: "K"},
        27: {5: "K", (6, 13): "W", 14: "w", (15, 20): "W", 21: "w", 22: "w", 23: "K"},
        28: {4: "K", (5, 13): "W", 14: "w", (15, 20): "W", 21: "w", 22: "w", 23: "K"},
        29: {4: "K", (5, 22): "w", 23: "K"},
        30: {(5, 22): "K"},
    },
}


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


def bust_rows():
    """The item icon: 선녀 close up, from the bands to the sleeves. Larger
    hair loops, the same face given more room, and her body as the entity's
    from the chin down, cut at the sleeves."""
    g = blank()
    left = {
        0: {(6, 8): "K"},
        1: {5: "K", 6: "h", 7: "H", 8: "H", 9: "K"},
        2: {4: "K", 5: "h", 6: "H", 7: "K", 8: "H", 9: "H", 10: "K"},
        3: {4: "K", 5: "H", 6: "K", 8: "K", 9: "H", 10: "K"},
        4: {4: "K", 5: "H", 6: "K", 8: "K", 9: "H", 10: "H", 11: "K"},
        5: {5: "K", 6: "H", 7: "K", 8: "K", 9: "H", 10: "H", 11: "K"},
        6: {6: "K", 7: "H", 8: "H", 9: "H", 10: "H", 11: "H", 12: "K"},
    }
    for y, cells in left.items():
        shifted = {}
        for key, ch in cells.items():
            x0, x1 = key if isinstance(key, tuple) else (key, key)
            shifted[(x0 + 1, x1 + 1)] = ch
        put(g, y, shifted)
        put(g, y, {(30 - x1, 30 - x0): ("H" if ch == "h" else ch)
                   for (x0, x1), ch in ((k if isinstance(k, tuple) else (k, k), c) for k, c in cells.items())})
    g[1][21] = "h"
    g[2][20] = "h"
    put(g, 7, {10: "K", 11: "R", 12: "Y", 13: "N", 14: "U", 15: "R", 16: "Y", 17: "N", 18: "U", 19: "R", 20: "Y", 21: "K"})
    put(g, 8, {9: "K", (10, 14): "G", (15, 16): "R", (17, 20): "G", 21: "g", 22: "K"})
    put(g, 9, {9: "K", 10: "H", (11, 12): "h", (13, 21): "H", 22: "K"})
    put(g, 10, {9: "K", 10: "h", (11, 13): "H", (14, 17): "S", (18, 21): "H", 22: "K"})
    put(g, 11, {9: "K", 10: "h", 11: "H", (12, 14): "S", (15, 16): "R", (17, 19): "S", (20, 21): "H", 22: "K"})
    put(g, 12, {9: "K", 10: "h", 11: "H", (12, 18): "S", 19: "s", (20, 21): "H", 22: "K"})
    put(g, 13, {9: "K", 10: "H", 11: "H", (12, 18): "S", 19: "s", (20, 21): "H", 22: "K"})
    put(g, 14, {9: "K", 10: "H", 11: "H", 12: "S", (13, 14): "E", (15, 16): "S", (17, 18): "E", 19: "s", (20, 21): "H", 22: "K"})
    put(g, 15, {9: "K", 10: "H", 11: "H", (12, 18): "S", 19: "s", (20, 21): "H", 22: "K"})
    put(g, 16, {9: "K", 10: "H", 11: "H", 12: "r", (13, 15): "S", 16: "s", (17, 18): "S", 19: "r", (20, 21): "H", 22: "K"})
    put(g, 17, {9: "K", 10: "H", 11: "H", (12, 14): "S", (15, 16): "Q", (17, 18): "S", 19: "s", (20, 21): "H", 22: "K"})
    put(g, 18, {9: "K", 10: "H", 11: "H", 12: "K", (13, 17): "S", 18: "s", 19: "K", (20, 21): "H", 22: "K"})
    put(g, 19, {9: "K", (10, 12): "H", 13: "K", (14, 16): "S", 17: "s", 18: "K", (19, 21): "H", 22: "K"})
    # the entity's body from the chin down, a column of hair either side
    body = entity_rows("level")
    for y in range(14, 26):
        row = list(body[y])
        g[y + 6] = row
    for y in (20, 21):
        g[y][9], g[y][10] = "K", "H"
        g[y][21], g[y][22] = "H", "K"
    return ["".join(r) for r in g]


# The 피백 scarf: a long, light silk ribbon on each side. It rises from
# behind the shoulder into a loop beside the head and flutters down in a
# wave past the sleeve to a free end. The shape is a smooth spline whose
# width swells and thins and which twists once (its shaded inner side shows);
# the hand-placed control points are the art. It is translucent and outlined
# in pale blue rather than black, so it reads as silk, not rope.
import math

SCARF_PATHS = [
    # (control points, widths along the ribbon, twist range)
    # the left streamer: up from behind the shoulder, a curl beside the head,
    # then a wave down past the sleeve to its free end
    ([(9.0, 16.5), (6.0, 13.5), (3.6, 10.0), (2.6, 6.6), (4.4, 4.4), (5.6, 6.4),
      (3.2, 9.0), (1.0, 12.5), (2.8, 16.6), (4.0, 20.5), (1.8, 24.2), (0.8, 27.4), (2.6, 30.4)],
     [1.1, 1.4, 1.5, 1.2, 1.2, 1.5, 1.6, 1.3, 1.5, 1.2, 1.6], (0.55, 0.61)),
    ([(22.0, 16.5), (25.0, 13.5), (27.4, 10.0), (28.4, 6.6), (26.6, 4.4), (25.4, 6.4),
      (27.8, 9.0), (30.0, 12.5), (28.2, 16.6), (27.0, 20.5), (29.2, 24.2), (30.2, 27.4), (28.6, 30.4)],
     [1.1, 1.4, 1.5, 1.2, 1.2, 1.5, 1.6, 1.3, 1.5, 1.2, 1.6], (0.66, 0.72)),
    # the silk wrapped round behind her: a faint loop behind the head and
    # shoulders, seen only between her and the streamers
    ([(15.5, 6.6), (22.0, 7.4), (25.6, 10.6), (26.2, 15.0), (24.6, 19.4), (20.0, 22.6),
      (15.5, 23.4), (11.0, 22.6), (6.4, 19.4), (4.8, 15.0), (5.4, 10.6), (9.0, 7.4), (15.5, 6.6)],
     [1.8] * 11, (2.0, 2.0)),
]


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


SCARF_BACK = {y: [(x, "F" if ch == "b" else "f") for x, ch in cells]
              for y, cells in scarf_cells(SCARF_PATHS[2]).items()}


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


def image(rows):
    assert len(rows) == 32 and all(len(r) == 32 for r in rows), [len(r) for r in rows]
    im = Image.new("RGBA", (32, 32))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            im.putpixel((x, y), PALETTE[ch])
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


# The familiar: the same 선녀, her silk fluttering. Each frame moves the
# streamers' control points along a travelling wave, the shoulder end held
# still and the free end moving most, the two sides out of step; the faint
# loop behind her stays. The anm2 bobs her gently and lays the vanilla
# Censer/Succubus halo (referenced in place, never copied) under her in gold
# as the aura in which her owner's tears are faster.
FRAMES = 8
FRAME_DELAY = 3
# her hem sways over the cycle while the silk waves
HEM_CYCLE = ["right", "right", "level", "left", "left", "left", "level", "right"]
# drawn smaller than the icon: the entity is the full figure at 80%
ENTITY_SCALE = 80


def fluttered(path, phase):
    points, widths, twist = path
    n = len(points)
    moved = [points[0]]
    for i, (x, y) in enumerate(points[1:], 1):
        reach = i / (n - 1)
        moved.append((min(31.3, max(0.3, x + 0.9 * reach * math.sin(phase + i * 0.8))),
                      min(31.3, max(0.3, y + 0.4 * reach * math.cos(phase + i * 0.8)))))
    return (moved, widths, twist)


def familiar_frame(k):
    phase = 2 * math.pi * k / FRAMES
    return image(compose(entity_rows(HEM_CYCLE[k]), scarf_cells(fluttered(SCARF_PATHS[0], phase)),
                         scarf_cells(fluttered(SCARF_PATHS[1], phase + math.pi)), SCARF_BACK))


def shifted(path, dy):
    points, widths, twist = path
    return ([(x, y + dy) for x, y in points], widths, twist)


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
BOB = [0, -1, -2, -2, -1, 0, 1, 1]
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
    """A room-sized preview: the basement floor, her gold halo, her drift and
    lean computed as `seonnyeo.lua` does (speed 2.2 world units an update,
    turning back 12 units inside the walls, leaning up to 7 degrees), Isaac
    standing still, and the tears multiplier he gets. Screen pixels are world
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
    lean = 0.0
    frames = []
    for update in range(seconds * 30):
        if pos[0] + vel[0] < margin or pos[0] + vel[0] > room_w - margin:
            vel[0] = -vel[0]
        if pos[1] + vel[1] < margin or pos[1] + vel[1] > room_h - margin:
            vel[1] = -vel[1]
        pos[0] += vel[0]
        pos[1] += vel[1]
        lean += (max(-7, min(7, vel[0] / (2.2 * k) * 7)) - lean) * 0.15
        if update % (30 // fps):
            continue
        f = base.copy()
        f.alpha_composite(gold, (round(pos[0]) - 112, round(pos[1]) - 112))
        d = ImageDraw.Draw(f)
        inside = math.hypot(isaac[0] - pos[0], isaac[1] - pos[1]) <= radius
        d.ellipse((isaac[0] - 6, isaac[1] - 3, isaac[0] + 6, isaac[1] + 3), fill=(0, 0, 0, 90))
        d.ellipse((isaac[0] - 7, isaac[1] - 20, isaac[0] + 7, isaac[1] - 6), fill=(236, 196, 186, 255), outline=(30, 20, 24, 255))
        d.text((isaac[0] - 14, isaac[1] - 34), "x1.2" if inside else "x1.0",
               fill=(255, 226, 120, 255) if inside else (230, 230, 230, 255))
        frame = sheet.crop((32 * ((update // FRAME_DELAY) % FRAMES), 0, 32 * ((update // FRAME_DELAY) % FRAMES) + 32, 32))
        frame = frame.resize((size, size), Image.NEAREST)
        pad = Image.new("RGBA", (size * 2, size * 2))
        pad.alpha_composite(frame, (size // 2, size // 2))
        pad = pad.rotate(-lean, resample=Image.NEAREST, center=(size, size))
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
