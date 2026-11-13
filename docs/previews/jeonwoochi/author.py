"""전우치 (Jeon Woo-chi): the Taoist who steals a set's missing items (user
design 2026-11-13). This draws his arrival presentation for review:

    python docs/previews/jeonwoochi/author.py          review files
    python docs/previews/jeonwoochi/author.py apply    the runtime assets

apply writes resources/gfx/effects/conch_jeonwoochi.png and .anm2 (one
"Steal" animation with the events the runtime listens for) and the item icon
resources/gfx/items/collectibles/jeon_woochi.png. The review run writes into
.tmp/jeonwoochi/:
    sprite_review.png   every pose at 1x and 8x
    smoke_review.png    every smoke frame at 6x
    preview.gif         the scene in a basement room at 3x, real speed
    preview_slow.gif    the same at a third of the speed
    frames.png          chosen frames side by side

At each spot an item will be placed, 전우치 in a 도포 and 갓 drops in on a
streak of light as if teleported, a folding fan at his cheek and the
face (user requests: a mysterious, well proportioned stranger, relaxed, a
fan in one hand and the other behind his back, broad sleeves, and the
gestures of a 도사 from film and drama), snaps the fan shut, brings a 부적
out from behind his back, casts and flings it down, and vanishes in a small "펑" of
smoke about the size of an item; the smoke clears and the stolen item stands
there on its pedestal. Vanilla art (floor, Isaac, pedestal, item icons) is
read in place for the preview only and never goes into the runtime assets.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, ".tmp", "jeonwoochi")
VANILLA = os.path.abspath(os.path.join(ROOT, "..", "..", "extracted_resources", "resources", "gfx"))

W, H = 40, 58          # sprite canvas
FOOT = (20, 56)        # the point that stands on the floor

# Pixel-art rules this sprite follows (studied 2026-11-13, see
# docs/isaac_item_sprite_study.md): the silhouette alone must say 갓, fan and
# an arm behind the back; flat clusters, never lone noise pixels; a pure black
# outline as small Isaac sprites use; three or four tones per material, the
# light from the top left and the shadows shifted cool; no banding or pillow
# shading. The user wants a mysterious, well proportioned stranger (about
# four and a half heads tall): the brim's deep shadow hides his eyes
# entirely and thins in two soft steps below them (the user found the old
# beady eyes petty and chose no eyes, 2026-11-13), the fan hides his mouth,
# and the 도포's wide sleeves keep his arms broad.
PAL = {
    ".": (0, 0, 0, 0),
    "K": (14, 8, 12, 255),       # outline, Isaac's near black
    "H": (32, 30, 40, 255),      # 갓 crown
    "h": (78, 80, 100, 255),     # crown sheen
    "B": (46, 44, 58, 255),      # 갓 brim, dark horsehair
    "b": (88, 90, 112, 255),     # brim's lit rim, crown band
    "A": (26, 22, 30, 255),      # hair, 망건
    "S": (240, 216, 202, 255),   # skin
    "s": (206, 168, 162, 255),   # skin shade
    "e": (22, 16, 28, 255),      # the brim's deep shadow over the eyes
    "d": (78, 64, 82, 255),      # the shadow thinning below them
    "t": (176, 142, 150, 255),   # its last soft step into the skin
    "E": (20, 12, 20, 255),      # eyes
    "G": (236, 244, 255, 255),   # the glint in his eyes
    "c": (132, 156, 196, 255),   # its dimmer tail
    "m": (150, 84, 92, 255),     # the smile behind the fan
    "L": (246, 247, 251, 255),   # 도포 lit
    "W": (222, 226, 236, 255),   # 도포, moonlit white
    "w": (168, 176, 204, 255),   # robe shade, cool
    "v": (114, 120, 156, 255),   # robe deep shade, inside the sleeves
    "N": (40, 44, 92, 255),      # collar
    "D": (252, 252, 250, 255),   # 동정 and the inner robe
    "U": (58, 64, 128, 255),     # 세조대, deep indigo
    "u": (34, 38, 84, 255),      # belt shade
    "R": (178, 42, 62, 255),     # tassel, dull crimson
    "r": (118, 24, 44, 255),     # tassel shade
    "F": (34, 30, 40, 255),      # shoes
    "f": (214, 214, 224, 255),   # the shoes' white trim
    "n": (92, 78, 70, 255),      # 갓끈 string
    "o": (226, 172, 82, 255),    # 갓끈 amber beads
    "P": (250, 242, 222, 255),   # white fan leaf
    "q": (222, 208, 180, 255),   # its folds
    "x": (40, 38, 52, 255),      # black fan leaf
    "z": (68, 66, 86, 255),      # its folds
    "g": (214, 178, 92, 255),    # the black fan's gold rim
    "k": (118, 82, 50, 255),     # bamboo sticks
    "Y": (248, 218, 98, 255),    # 부적 paper
    "y": (212, 168, 62, 255),    # paper shade
    "X": (206, 36, 40, 255),     # 부적 script
}


def grid():
    return [["."] * W for _ in range(H)]


def inside_ellipse(x, y, cx, cy, rx, ry):
    return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0


def paint_part(g, mask, fill):
    """Fill a part and outline its own edge, so a later part keeps a dark
    seam against an earlier one, as layered Isaac sprites do."""
    for y in range(H):
        for x in range(W):
            if not mask(x, y):
                continue
            edge = any(not (0 <= x + dx < W and 0 <= y + dy < H) or not mask(x + dx, y + dy)
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            g[y][x] = "K" if edge else fill(x, y)


def put(g, pts, ch):
    for x, y in pts:
        if 0 <= x < W and 0 <= y < H:
            g[y][x] = ch


def run(g, y, x0, x1, ch):
    for x in range(x0, x1 + 1):
        g[y][x] = ch


def segment(ax, ay, bx, by, r0, r1):
    def m(x, y):
        t = max(0.0, min(1.0, ((x + 0.5 - ax) * (bx - ax) + (y + 0.5 - ay) * (by - ay))
                         / ((bx - ax) ** 2 + (by - ay) ** 2)))
        px, py = ax + t * (bx - ax), ay + t * (by - ay)
        return math.hypot(x + 0.5 - px, y + 0.5 - py) <= r0 + (r1 - r0) * t
    return m


def union(*masks):
    return lambda x, y: any(m(x, y) for m in masks)


# ---- parts ---------------------------------------------------------------

# half widths of the face from the band under the brim to the chin
FACE = {11: 5.2, 12: 5.4, 13: 5.4, 14: 5.4, 15: 5.3, 16: 5.1, 17: 4.8, 18: 4.4,
        19: 3.9, 20: 3.3, 21: 2.6, 22: 1.8}
SHOULDER = (13.4, 25.6)            # the arm that is behind his back


def face_mask(x, y):
    return y in FACE and abs(x + 0.5 - 20) <= FACE[y]


def face_fill(x, y):
    if y == 11:
        return "A"                  # 망건, the black band under the 갓
    if y <= 16 and abs(x + 0.5 - 20) > 4.0:
        return "A"                  # hair at the temples
    # The brim casts a deep shadow over the eyes that thins as it comes down,
    # reaching lower on his shaded right (user request 2026-11-13: dark over
    # the eyes, a soft shade below, so he looks sharp rather than petty).
    right = x >= 21
    if y <= 14 or (y == 15 and right):
        return "e"
    if y == 15 or (y == 16 and right):
        return "d"
    if y == 16 or (y == 17 and right):
        return "t"
    return "s" if x >= 22 else "S"


def robe_half(y, flare=0):
    if y == 23:
        return 5.0
    if y == 24:
        return 7.2
    half = 8.2 + 2.4 * (y - 25) / 28
    if flare and y > 40:
        half += flare * (y - 40) / 13        # the hem blown out by his landing
    return half


def robe_mask(flare):
    return lambda x, y: 23 <= y <= 53 and abs(x + 0.5 - 20) <= robe_half(y, flare)


def robe_fill(flare):
    def f(x, y):
        right = 20 + robe_half(y, flare)
        if x + 0.5 > right - 2.4 or y >= 52:
            return "w"
        if x <= 16 and y <= 32:
            return "L"
        return "W"
    return f


def shoe_mask(x, y):
    return 53 <= y <= 57 and (inside_ellipse(x, y, 16.4, 55.4, 2.9, 1.7)
                              or inside_ellipse(x, y, 23.6, 55.4, 2.9, 1.7))


def brim_mask(x, y):
    return inside_ellipse(x, y, 20.0, 9.4, 13.6, 2.8)


def crown_mask(x, y):
    if not (16 <= x <= 23 and 1 <= y <= 9):
        return False
    return not (y == 1 and x in (16, 23))


def hat(g):
    paint_part(g, brim_mask, lambda x, y: "b" if y >= 11 else "B")
    paint_part(g, crown_mask, lambda x, y: "b" if y == 8 else ("h" if x == 18 and y <= 6 else "H"))


def gatkkeun(g, sway=0):
    """The beaded 갓끈 hanging from the brim in a loop over the chest; sway
    swings the bottom of the loop sideways."""
    pts = []
    for i in range(41):
        t = i / 40
        x = (1 - t) ** 2 * 13.6 + 2 * (1 - t) * t * (20.0 + sway) + t ** 2 * 26.4
        y = (1 - t) ** 2 * 12.0 + 2 * (1 - t) * t * 42.0 + t ** 2 * 12.0
        p = (int(x), int(y))
        if not pts or pts[-1] != p:
            pts.append(p)
    for i, p in enumerate(pts):
        put(g, [p], "o" if i % 3 == 1 else "n")


def body(g, flare, behind):
    if behind:
        # 뒷짐: the forearm turning in behind the waist and the far end of
        # the wide sleeve hanging behind the hip; the robe covers most of it
        paint_part(g, union(segment(8.4, 34.0, 13.0, 37.0, 2.8, 2.6),
                            lambda x, y: inside_ellipse(x, y, 9.8 - 0.6 * flare, 40.0 - 1.5 * flare, 3.0, 4.2)),
                   lambda x, y: "v")
    paint_part(g, robe_mask(flare), robe_fill(flare))
    # skirt folds
    put(g, [(17, 41), (17, 42), (17, 43), (17, 44), (16, 45), (16, 46), (16, 47)], "w")
    put(g, [(23, 42), (23, 43), (23, 44), (23, 45), (24, 46), (24, 47)], "w")
    # collar V with the white 동정 and inner robe; the outer panel's edge
    # runs on down to the waist
    for y, (l, r) in zip(range(23, 29), ((16, 23), (16, 23), (17, 22), (18, 21), (19, 20), (19, 20))):
        run(g, y, l + 1, r - 1, "D")
        put(g, [(l, y), (r, y)], "N")
    put(g, [(19, 29), (20, 29), (21, 30), (22, 31), (23, 32)], "N")
    # 세조대 at the waist, its knot and two long strands
    run(g, 33, 12, 28, "U")
    run(g, 34, 12, 28, "u")
    put(g, [(11, 33), (11, 34), (29, 33), (29, 34)], "K")
    put(g, [(21, 35), (22, 35), (21, 36), (22, 36)], "R")
    sw = 1 if flare >= 2 else 0
    put(g, [(21, 37), (21 + sw, 38), (21 + sw, 39), (21 + sw, 40), (22, 37), (22 + sw, 38), (22 + sw, 39),
            (22 + sw, 40), (22 + sw, 41)], "R")
    put(g, [(21 + sw, 41), (21 + sw, 42), (22 + sw, 42), (22 + 2 * sw, 43)], "r")
    paint_part(g, shoe_mask, lambda x, y: "f" if y == 54 else "F")


def back_arm(g, state):
    """The arm that starts behind his back. behind: 뒷짐, the elbow poking
    out at the side. reach: the hand comes out at the hip with a 부적. raise:
    the 부적 on its way up. seal: held upright before his face between two
    fingers. throw: the arm swung down, the hand open, the 부적 gone."""
    sx, sy = SHOULDER
    sleeve = lambda x, y: "L" if y <= 28 and x <= 12 else ("W" if y <= 31 else "w")
    if state == "behind":
        paint_part(g, segment(sx, sy, 8.6, 33.6, 3.4, 3.2), sleeve)
        put(g, [(11, 30), (10, 31)], "w")
        return
    if state == "reach":
        paint_part(g, union(segment(sx, sy, 10.6, 32.0, 3.4, 3.2), segment(10.6, 32.0, 15.0, 35.4, 3.0, 2.6)), sleeve)
        paper(g, 15, 28)
        hand(g, 15, 35)
        return
    if state == "raise":
        paint_part(g, union(segment(sx, sy, 10.0, 31.4, 3.4, 3.2), segment(10.0, 31.4, 12.4, 25.0, 3.0, 2.6),
                            lambda x, y: inside_ellipse(x, y, 8.4, 33.6, 2.6, 4.2)),
                   lambda x, y: "v" if y >= 34 else sleeve(x, y))
        paper(g, 11, 16)
        hand(g, 11, 23)
        return
    if state == "seal":
        paint_part(g, union(segment(sx, sy, 10.2, 30.6, 3.4, 3.2), segment(10.2, 30.6, 13.8, 23.0, 3.0, 2.4),
                            lambda x, y: inside_ellipse(x, y, 8.2, 33.4, 2.6, 4.8)),
                   lambda x, y: "v" if y >= 34 else sleeve(x, y))
        paper(g, 12, 10)
        # two fingers up along the slip: the 결인 of a 도사 casting
        put(g, [(13, 19), (13, 20), (14, 20), (13, 21), (14, 21)], "S")
        put(g, [(12, 19), (12, 20), (12, 21), (15, 21), (13, 22), (14, 22)], "K")
        return
    if state == "throw":
        paint_part(g, union(segment(sx, sy, 9.4, 30.0, 3.4, 3.2), segment(9.4, 30.0, 11.6, 37.0, 3.0, 2.6),
                            lambda x, y: inside_ellipse(x, y, 8.0, 34.0, 2.4, 4.0)),
                   lambda x, y: "v" if y >= 35 and x <= 9 else sleeve(x, y))
        # the hand open after the flick
        put(g, [(10, 38), (11, 38), (12, 38), (11, 39), (12, 39)], "S")
        put(g, [(9, 38), (10, 39), (13, 38), (13, 39), (11, 40), (12, 40), (10, 37), (13, 37)], "K")
        return
    raise ValueError(state)


def paper(g, x0, y0):
    """A 부적 slip, 5 x 10, its top left at (x0, y0)."""
    paint_part(g, lambda x, y: x0 <= x <= x0 + 4 and y0 <= y <= y0 + 9,
               lambda x, y: "y" if x == x0 + 4 or y == y0 + 8 else "Y")
    cx = x0 + 2
    put(g, [(cx, y0 + 2), (cx, y0 + 3), (cx, y0 + 4), (cx, y0 + 5), (cx, y0 + 6), (cx, y0 + 7)], "X")
    put(g, [(cx - 1, y0 + 3), (cx + 1, y0 + 3), (cx - 1, y0 + 5), (cx + 1, y0 + 5), (cx + 1, y0 + 7)], "X")


def hand(g, x0, y0):
    put(g, [(x0, y0), (x0 + 1, y0), (x0, y0 + 1), (x0 + 1, y0 + 1)], "S")
    put(g, [(x0 - 1, y0), (x0 - 1, y0 + 1), (x0 + 2, y0), (x0 + 2, y0 + 1), (x0, y0 + 2), (x0 + 1, y0 + 2)], "K")


def face(g, smile=False):
    paint_part(g, face_mask, face_fill)
    if EYES == "glint":
        # deep in the brim's shadow only his eyes catch the light: two narrow
        # glints whose outer ends rise, sharp rather than beady
        put(g, [(17, 14), (22, 14)], "G")
        put(g, [(16, 13), (23, 13)], "c")
    # EYES == "none": no eyes at all, only the shadow (the user's other idea)
    if smile:
        # the fan shut: a thin smile at one corner of the mouth
        put(g, [(18, 19), (19, 19), (20, 19), (21, 18)], "m")


# His eyes under the brim: "glint" (two sharp slits of light) or "none"
# (only the shadow). The user chose "none" over both the glint and the old
# beady eyes (2026-11-13).
EYES = "none"

FAN_PIVOT = (25.6, 24.4, 8.4)
FAN_ANGLES = {"a": (66, 192), "b": (76, 200), "half": (112, 196)}


def fan(g, state, style):
    """The 합죽선 in the other hand, held at the chin under its broad sleeve.
    a and b: open, fanning; half: folding; closed: shut, upright by the
    cheek."""
    paint_part(g, union(segment(26.8, 25.6, 30.0, 31.0, 3.4, 3.2),
                        segment(30.0, 31.0, 26.4, 25.4, 3.2, 2.6),
                        lambda x, y: inside_ellipse(x, y, 31.0, 37.0, 3.4, 6.4)),
               lambda x, y: "v" if y >= 40 else ("W" if y <= 28 and x <= 28 else "w"))
    if state == "closed":
        # shut, the folded leaf stands up beside his cheek like a stick
        paint_part(g, segment(25.2, 24.6, 23.6, 15.2, 1.5, 1.3),
                   lambda x, y: "k" if y >= 21 else ("q" if x >= 24 else "P"))
        hand(g, 24, 24)
        return
    px, py, r = FAN_PIVOT
    a0, a1 = FAN_ANGLES[state]
    leaf, fold = ("x", "z") if style == "black" else ("P", "q")

    def polar(x, y):
        dx, dy = x + 0.5 - px, py - (y + 0.5)
        return math.hypot(dx, dy), math.degrees(math.atan2(dy, dx)) % 360

    def sector(x, y):
        d, a = polar(x, y)
        return 0.8 <= d <= r and a0 <= a <= a1

    def fill(x, y):
        d, a = polar(x, y)
        if d < 3.6 or a - a0 < 4.5 or a1 - a < 4.5:
            return "k"              # sticks at the rivet and the guard sticks
        if style == "black" and d > r - 1.6:
            return "g"              # a gold rim along the leaf
        return fold if (a - a0) % 18 < 3.5 else leaf
    paint_part(g, sector, fill)
    hand(g, 24, 24)


FAN_STYLE = "white"


def build(flare=0, sway=0, fan_state="a", arm="behind", style=None):
    style = style or FAN_STYLE
    g = grid()
    body(g, flare, behind=arm == "behind")
    if arm == "behind":
        back_arm(g, "behind")
    face(g, smile=fan_state == "closed")
    gatkkeun(g, sway)
    hat(g)
    fan(g, fan_state, style)
    if arm != "behind":
        back_arm(g, arm)
    return g


def pose(name, style=None):
    """The named poses of the review sheet."""
    specs = {
        "stand": {}, "fan_b": {"fan_state": "b"},
        "land": {"flare": 3, "sway": 2},
        "half": {"fan_state": "half"}, "closed": {"fan_state": "closed"},
        "reach": {"fan_state": "closed", "arm": "reach"},
        "raise": {"fan_state": "closed", "arm": "raise"},
        "seal": {"fan_state": "closed", "arm": "seal"},
        "throw": {"fan_state": "closed", "arm": "throw"},
    }
    return build(style=style, **specs[name])


# where the 부적 sits in the seal pose (for its glow) and where the right
# eye's glint is (for the flash)
SEAL_PAPER = (12, 10, 16, 19)
EYE = (23, 14)
FAN_TIP = (23, 15)
THROW_HAND = (11, 38)


def image(g):
    im = Image.new("RGBA", (W, H))
    px = im.load()
    for y in range(H):
        for x in range(W):
            px[x, y] = PAL[g[y][x]]
    return im


def silhouette(im):
    out = Image.new("RGBA", im.size, (20, 16, 20, 0))
    out.putalpha(im.split()[3])
    return out


POSES = ("land", "stand", "fan_b", "half", "closed", "reach", "raise", "seal", "throw")


def sprite_review():
    """Every pose at 1x beside Isaac and at 4x, with the stand silhouette."""
    ims = [image(pose(p)) for p in POSES]
    small = [isaac_alone()] + ims + [silhouette(ims[1]), silhouette(ims[7])]
    scale = 4
    width = max(sum(i.width + 8 for i in small) + 16, len(ims) * (W * scale + 10) + 16)
    sheet = Image.new("RGBA", (width, H + 40 + H * scale + 40), (150, 134, 120, 255))
    dark = Image.new("RGBA", (sum(i.width + 8 for i in small) + 8, H + 16), (58, 52, 48, 255))
    sheet.alpha_composite(dark, (4, 4))
    x = 12
    for im in small:
        sheet.alpha_composite(im, (x, 12 + H - im.height))
        x += im.width + 8
    font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 13)
    d = ImageDraw.Draw(sheet)
    names = {"land": "착지(바람)", "stand": "부채질 1", "fan_b": "부채질 2", "half": "부채 접기",
             "closed": "탁! 미소", "reach": "부적 꺼냄", "raise": "올림", "seal": "결인", "throw": "던짐"}
    x = 12
    for p, im in zip(POSES, ims):
        sheet.alpha_composite(im.resize((W * scale, H * scale), Image.NEAREST), (x, H + 36))
        d.text((x + 4, H + 40 + H * scale), names[p], font=font, fill=(30, 24, 26))
        x += W * scale + 10
    return sheet


# ---- the smoke: a "펑" about the size of an item ---------------------------

SMOKE = {
    "L": (255, 255, 255, 255),   # lit top of a puff
    "C": (238, 238, 246, 255),   # puff body
    "M": (194, 198, 218, 255),   # puff shade and the seams between puffs
    "O": (150, 156, 184, 255),   # the cloud's outer rim
    "P": (255, 250, 214, 255),   # the pop's hot core
}
SW, SH = 64, 64                  # smoke canvas, centred on the item
SMOKE_FRAMES = 30
HOLD = 6                         # frames the full cloud holds before it breaks


def _puffs():
    """One central puff and a loose cluster around it. Each puff breaks up
    on its own schedule (delay, shrink, drift), so the cloud thins into
    rising wisps instead of an even ring."""
    import random
    rnd = random.Random(1307)
    out = [dict(ang=0, dist=0, r=10.0, delay=0, life=8, dx=0, dy=-4)]
    for ang, dist, r in ((90, 11, 8.0), (35, 11, 7.0), (145, 11, 7.0), (205, 11, 7.0), (335, 11, 7.0),
                         (270, 10, 7.5), (5, 13, 6.0), (175, 13, 6.0), (62, 16, 6.0), (118, 16, 6.0),
                         (245, 15, 6.0), (295, 15, 6.0), (95, 20, 5.0), (275, 19, 5.0)):
        a = math.radians(ang)
        up = math.sin(a)
        # puffs rise as smoke does; the low ones spread along the floor
        dx = math.cos(a) * rnd.uniform(7, 12) + (rnd.choice((-1, 1)) * 6 if up < -0.5 else 0)
        dy = -rnd.uniform(6, 12) * (1.2 if up > 0.3 else 0.7)
        out.append(dict(ang=ang, dist=dist, r=r, delay=rnd.randint(0, 6), life=rnd.randint(12, 19),
                        dx=dx, dy=dy))
    return out


PUFFS = _puffs()


def smoke_puffs(t):
    """The puffs of smoke frame t as (cy, cx, radius, alpha)."""
    cx0, cy0 = SW / 2, 32.0
    out = []
    grow = 1.0 if t >= 3 else (0.35, 0.6, 0.85)[t]
    for p in PUFFS:
        a = math.radians(p["ang"])
        k = 0.0
        start = 3 + HOLD + p["delay"]
        if t > start:
            k = min(1.0, (t - start) / p["life"])
        ease = k * k * (3 - 2 * k)
        wob = 0.6 * math.sin(t * 1.3 + p["ang"]) if 3 <= t <= start else 0.0
        d = p["dist"] * grow
        cx = cx0 + math.cos(a) * d + p["dx"] * ease
        cy = cy0 - math.sin(a) * d * 1.2 + p["dy"] * ease
        rr = p["r"] * (0.55 + 0.45 * grow) * (1.0 - 0.85 * ease) + wob
        if p["dist"] == 0 and t > 3 + HOLD:
            rr = p["r"] * max(0.0, 1.0 - (t - 3 - HOLD) / p["life"])     # the middle clears first
        alpha = 1.0 - ease ** 1.6
        if rr >= 1.0 and alpha > 0.04:
            out.append((cy, cx, rr, alpha))
    return out


def smoke_frame(t):
    """One frame of the smoke on SW x SH, its centre at (32, 32)."""
    cx0, cy0 = SW / 2, 32.0
    puffs = sorted(smoke_puffs(t))                   # back (higher) puffs first
    owner = [[-1] * SW for _ in range(SH)]
    for k, (cy, cx, rr, _) in enumerate(puffs):
        for y in range(SH):
            for x in range(SW):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= rr * rr:
                    owner[y][x] = k
    im = Image.new("RGBA", (SW, SH))
    px = im.load()
    for y in range(SH):
        for x in range(SW):
            k = owner[y][x]
            if k < 0:
                continue
            cy, cx, rr, alpha = puffs[k]
            u, v = (x + 0.5 - cx) / rr, (y + 0.5 - cy) / rr
            outer = any(not (0 <= x + dx < SW and 0 <= y + dy < SH) or owner[y + dy][x + dx] < 0
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            seam = any(0 <= x + dx < SW and 0 <= y + dy < SH and 0 <= owner[y + dy][x + dx] < k
                       for dx, dy in ((0, -1), (-1, 0)))
            if outer:
                ch = "O"
            elif u * 0.55 + v * 0.83 > 0.42:
                ch = "M"
            elif (u + 0.32) ** 2 + (v + 0.36) ** 2 < 0.13:
                ch = "L"
            elif seam and u * 0.55 + v * 0.83 > -0.2:
                ch = "M"
            else:
                ch = "C"
            r, g, b, a = SMOKE[ch]
            px[x, y] = (r, g, b, round(a * alpha))
    if t <= 1:
        # the pop: a hot core and short lines flying out
        d = ImageDraw.Draw(im)
        core = 5 if t == 0 else 3
        d.ellipse((cx0 - core, cy0 - core, cx0 + core - 1, cy0 + core - 1), fill=SMOKE["P"])
        for ang in range(0, 360, 45):
            a = math.radians(ang + 22)
            r0, r1 = (8, 14) if t == 0 else (17, 22)
            x0, y0 = cx0 + math.cos(a) * r0, cy0 - math.sin(a) * r0 * 0.85
            x1, y1 = cx0 + math.cos(a) * r1, cy0 - math.sin(a) * r1 * 0.85
            d.line((round(x0), round(y0), round(x1), round(y1)), fill=SMOKE["L"], width=1)
    return im


def smoke_review():
    scale = 6
    frames = [smoke_frame(t) for t in range(SMOKE_FRAMES)]
    cols = 10
    rows = math.ceil(len(frames) / cols)
    sheet = Image.new("RGBA", (cols * (SW * scale + 8) + 8, rows * (SH * scale + 8) + 8), (58, 52, 48, 255))
    for i, im in enumerate(frames):
        sheet.alpha_composite(im.resize((SW * scale, SH * scale), Image.NEAREST),
                              (8 + (i % cols) * (SW * scale + 8), 8 + (i // cols) * (SH * scale + 8)))
    return sheet


# ---- the scene -------------------------------------------------------------

def vanilla(path):
    return Image.open(os.path.join(VANILLA, path)).convert("RGBA")


def isaac_alone():
    """Isaac standing, at native size, for the size comparison."""
    sheet = vanilla("characters/costumes/character_001_isaac.png")
    im = Image.new("RGBA", (32, 44))
    im.alpha_composite(sheet.crop((0, 32, 32, 64)), (0, 42 + 2 - 25))
    im.alpha_composite(sheet.crop((0, 0, 32, 32)), (0, 42 - 5 - 28))
    return im


def squash(im, sx, sy):
    """Scale about the feet, nearest neighbour."""
    w, h = max(1, round(im.width * sx)), max(1, round(im.height * sy))
    return im.resize((w, h), Image.NEAREST), (FOOT[0] * sx, FOOT[1] * sy)


def tinted(im, rgb, alpha):
    r, g, b = rgb
    out = Image.new("RGBA", im.size, (r, g, b, 0))
    out.putalpha(im.split()[3].point(lambda v: round(v * alpha)))
    return out


# The beats of one arrival, in spot-local frames at 30 a second. The gestures
# are the 도사 of Korean film and drama: he lands lightly with his sleeves and
# hem blown out, fans himself at leisure, snaps the fan shut (탁) to show a
# thin smile, brings a 부적 out from behind his back, holds it up before his
# face in a 결인 while a 진법 circle lights under his feet, his eye flashes,
# and he flings the 부적 down at his feet: 펑, and he is gone.
#    0-1  a streak of light falls          17     the fan folds
#    2-8  he lands, robe blown, settles    18     탁: shut, a smile shows
#    9-16 he fans himself                  19-20  the 부적 comes out and up
#                                          21-28  결인, the circle, 26-27 eye flash
#                                          29-32  the throw, the 부적 falls burning
#                                          33     it strikes the floor
#                                          34     펑
POP = 34            # local frame of the "펑"; he is gone from here
ITEM = POP + 4      # the pedestal is spawned under the full cloud
SPOT_FRAMES = POP + SMOKE_FRAMES
ARRIVE = 2
LAND = {2: (0.45, 1.6), 3: (0.75, 1.25), 4: (1.2, 0.86), 5: (1.06, 0.95)}
FLARE = {2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1}
SWAY = {2: 2, 3: 2, 4: 1, 5: -1, 6: -1, 7: -1, 8: 1}
SEAL, FLASH, THROW, STRIKE = 21, 26, 29, 33
GOLD = (255, 224, 140)


def beat(t):
    """The pose and the stretch for spot-local frame t."""
    spec = dict(flare=FLARE.get(t, 0), sway=SWAY.get(t, 0))
    if t <= 16:
        spec["fan_state"] = "a" if t < 9 or ((t - 9) // 3) % 2 == 0 else "b"
    elif t == 17:
        spec["fan_state"] = "half"
    else:
        spec["fan_state"] = "closed"
        spec["arm"] = ("behind" if t == 18 else "reach" if t == 19 else "raise" if t == 20
                       else "seal" if t < THROW else "throw")
    stretch = LAND.get(t, (1.0, 1.0))
    if t == THROW:
        stretch = (1.04, 0.97)          # the snap of the throw
    return spec, stretch


_POSE_CACHE = {}


def posed(spec):
    key = (FAN_STYLE,) + tuple(sorted(spec.items()))
    if key not in _POSE_CACHE:
        _POSE_CACHE[key] = image(build(**spec))
    return _POSE_CACHE[key]


def layer(f):
    return Image.new("RGBA", f.size), None


def magic_circle(f, feet, t):
    """A 진법 circle of light under his feet while he casts."""
    k = min(1.0, (t - SEAL + 1) / 4)
    if t >= STRIKE - 1:
        k = 1.3
    a = round(170 * min(1.0, k))
    im = Image.new("RGBA", f.size)
    d = ImageDraw.Draw(im)
    x, y = feet
    d.ellipse((x - 16, y - 5, x + 16, y + 5), outline=GOLD + (a,), width=1)
    d.ellipse((x - 11, y - 3, x + 11, y + 3), outline=GOLD + (a // 2,), width=1)
    for n in range(8):
        ang = math.radians(t * 12 + n * 45)
        px, py = x + math.cos(ang) * 16, y + math.sin(ang) * 5
        d.rectangle((round(px) - 1, round(py), round(px), round(py)), fill=(255, 246, 210, a))
    f.alpha_composite(im)


def star(d, x, y, arm, color):
    d.point((x, y), fill=(255, 255, 255, 255))
    for i in range(1, arm + 1):
        for px, py in ((x + i, y), (x - i, y), (x, y + i), (x, y - i)):
            d.point((px, py), fill=color)


def slip(k, burning):
    """The thrown 부적 in flight: full, edge on, then turned over; a flame
    eats it from the top."""
    im = Image.new("RGBA", (7, 15))
    d = ImageDraw.Draw(im)
    if k % 3 == 1:
        d.rectangle((2, 5, 3, 14), fill=PAL["K"])
        d.line((3, 6, 3, 13), fill=PAL["y"])
    else:
        d.rectangle((1, 5, 5, 14), fill=PAL["K"])
        d.rectangle((2, 6, 4, 13), fill=PAL["Y"])
        d.line((3, 7, 3, 12), fill=PAL["X"])
        d.point((2 if k % 3 == 0 else 4, 9), fill=PAL["X"])
    if burning:
        h = 2 + k % 2
        d.rectangle((2, 5 - h, 4, 5), fill=(255, 140, 40, 255))
        d.rectangle((3, 4 - h, 3, 5), fill=(255, 230, 120, 255))
    return im


def jeonwoochi_layer(f, t, spot, top):
    """Draw spot-local frame t of one arrival onto f. spot is the pedestal's
    screen position, top the room's top edge for the streak."""
    x, y = spot
    feet = (x, y + 6)
    if 0 <= t <= 5:
        # the streak of light he arrives on
        tip = top + (feet[1] - top) * (0.55 if t == 0 else 1.0)
        width = {0: 3, 1: 3, 2: 5, 3: 3, 4: 1, 5: 1}[t]
        alpha = {0: 255, 1: 255, 2: 255, 3: 170, 4: 110, 5: 60}[t]
        glow = Image.new("RGBA", f.size)
        gd = ImageDraw.Draw(glow)
        gd.rectangle((x - width // 2 - 1, top, x + width // 2 + 1, tip), fill=(150, 226, 255, alpha // 2))
        gd.rectangle((x - width // 2, top, x + width // 2, tip), fill=(232, 250, 255, alpha))
        f.alpha_composite(glow)
    if not ARRIVE <= t < POP:
        return
    sh = Image.new("RGBA", f.size)
    ImageDraw.Draw(sh).ellipse((feet[0] - 10, feet[1] - 3, feet[0] + 10, feet[1] + 2), fill=(0, 0, 0, 80))
    f.alpha_composite(sh)
    if t >= SEAL:
        magic_circle(f, feet, t)
    for k, (rx, ry, a) in ((0, (12, 4, 230)), (1, (17, 5, 120))):
        if t == ARRIVE + k:
            ring = Image.new("RGBA", f.size)
            ImageDraw.Draw(ring).ellipse((feet[0] - rx, feet[1] - ry, feet[0] + rx, feet[1] + ry),
                                         outline=(220, 248, 255, a), width=1)
            f.alpha_composite(ring)
    spec, (sx, sy) = beat(t)
    im, (ax, ay) = squash(posed(spec), sx, sy)
    left, top_y = round(feet[0] - ax), round(feet[1] - ay)
    if t in (2, 3, 4):
        # afterimages trailing above him while he lands
        for k, a in ((1, 0.45), (2, 0.22)):
            ghost = tinted(im, (150, 226, 255), a * (1.0 if t == 2 else 0.6 if t == 3 else 0.3))
            f.alpha_composite(ghost, (left, top_y - 12 * k))
    f.alpha_composite(im, (left, top_y))
    fx = Image.new("RGBA", f.size)
    d = ImageDraw.Draw(fx)
    if t == 18:
        # 탁: the fan snaps shut
        tx, ty = left + FAN_TIP[0], top_y + FAN_TIP[1]
        for dx0, dy0, dx1, dy1 in ((2, -3, 4, -5), (3, 0, 6, 0), (2, 3, 4, 5)):
            d.line((tx + dx0, ty + dy0, tx + dx1, ty + dy1), fill=(255, 255, 255, 230))
    if SEAL <= t < THROW:
        # the 부적 glows, sparks gather on it
        pulse = 0.5 + 0.5 * math.sin((t - SEAL) * 0.9)
        x0, y0, x1, y1 = SEAL_PAPER
        d.rectangle((left + x0 - 1, top_y + y0 - 1, left + x1 + 1, top_y + y1 + 1),
                    outline=GOLD + (round(110 + 130 * pulse),))
        if t >= SEAL + 3:
            for k in range(3):
                a = math.radians(t * 37 + k * 120)
                d.point((round(left + 14 + math.cos(a) * 6), round(top_y + 14 + math.sin(a) * 8)),
                        fill=(255, 255, 220, 255))
    if t in (FLASH, FLASH + 1):
        # 번쩍: a glint flares in his eye
        star(d, left + EYE[0], top_y + EYE[1], 3 if t == FLASH else 2, (220, 236, 255, 230))
    f.alpha_composite(fx)
    if THROW <= t <= STRIKE:
        # the 부적, flung down, falls burning to his feet
        hx, hy = left + THROW_HAND[0], top_y + THROW_HAND[1] - 8
        gx, gy = feet[0] - 3, feet[1] - 12
        k = (t - THROW) / (STRIKE - THROW)
        px, py = hx + (gx - hx) * k * k, hy + (gy - hy) * k * k
        if t < STRIKE:
            f.alpha_composite(slip(t - THROW, t > THROW), (round(px), round(py)))
        else:
            hit = Image.new("RGBA", f.size)
            hd = ImageDraw.Draw(hit)
            hd.ellipse((feet[0] - 6, feet[1] - 3, feet[0] + 6, feet[1] + 2), fill=(255, 230, 150, 220))
            for n in range(6):
                a = math.radians(n * 60 + 30)
                hd.line((round(feet[0] + math.cos(a) * 8), round(feet[1] - 1 + math.sin(a) * 4),
                         round(feet[0] + math.cos(a) * 12), round(feet[1] - 1 + math.sin(a) * 6)),
                        fill=(255, 250, 220, 230))
            f.alpha_composite(hit)


def pedestal_layer(f, t, spot, icon, frame):
    if t < ITEM:
        return
    x, y = spot
    altar = vanilla("items/levelitem_001_itemaltar.png").crop((0, 0, 32, 32))
    f.alpha_composite(altar, (x - 16, y - 16))
    bob = [-6, -7, -8, -9, -10, -9, -8, -7][(frame // 2) % 8]
    f.alpha_composite(icon, (x - 16, y + bob - 32))


def smoke_layer(f, t, spot):
    st = t - POP
    if 0 <= st < SMOKE_FRAMES:
        x, y = spot
        f.alpha_composite(smoke_frame(st), (x - SW // 2, y - 15 - 32))


def isaac(f, pos, lifting, held):
    sheet = vanilla("characters/costumes/character_001_isaac.png")
    x, y = pos
    sh = Image.new("RGBA", f.size)
    ImageDraw.Draw(sh).ellipse((x - 9, y - 3, x + 9, y + 2), fill=(0, 0, 0, 80))
    f.alpha_composite(sh)
    if lifting:
        f.alpha_composite(sheet.crop((64, 192, 128, 256)), (x - 32, y - 56 + 1))
        f.alpha_composite(held, (x - 16, y - 66))
    else:
        f.alpha_composite(sheet.crop((0, 32, 32, 64)), (x - 16, y + 2 - 25))
        f.alpha_composite(sheet.crop((0, 0, 32, 32)), (x - 16, y - 5 - 28))


def stand_in_icon():
    """No item icon yet: the 갓 alone stands in while Isaac lifts the item."""
    im = image(pose("stand"))
    out = Image.new("RGBA", (32, 32))
    out.alpha_composite(im.crop((4, 0, 36, 13)), (0, 10))
    return out


def preview_gif(path, scale=3, duration=33):
    room_w, room_h = 338, 182
    floor = vanilla("backdrop/01_basement_nfloor.png")
    base = Image.new("RGBA", (room_w, room_h))
    base.alpha_composite(floor.crop((0, 0, 169, 182)), (0, 0))
    base.alpha_composite(floor.crop((0, 0, 169, 182)).transpose(Image.FLIP_LEFT_RIGHT), (169, 0))
    collect = "items/collectibles/"
    icons = [vanilla(collect + "collectibles_134_guppystail.png"), vanilla(collect + "collectibles_133_guppyspaw.png")]
    isaac_pos = (118, 122)
    spots = [(196, 98), (248, 98)]
    lift = 26
    starts = [lift + 4, lift + 14]
    total = starts[-1] + SPOT_FRAMES + 45
    font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 15)
    held = stand_in_icon()
    frames = []
    for frame in range(total):
        f = base.copy()
        layers = [(isaac_pos[1], lambda f=f: isaac(f, isaac_pos, frame < lift, held))]
        for spot, icon, start in zip(spots, icons, starts):
            t = frame - start
            layers.append((spot[1] - 1, lambda f=f, t=t, spot=spot, icon=icon: pedestal_layer(f, t, spot, icon, frame)))
            layers.append((spot[1] + 6, lambda f=f, t=t, spot=spot: jeonwoochi_layer(f, t, spot, 0)))
        for _, draw in sorted(layers, key=lambda v: v[0]):
            draw()
        for spot, start in zip(spots, starts):
            smoke_layer(f, frame - start, spot)
        big = f.resize((room_w * scale, room_h * scale), Image.NEAREST)
        d = ImageDraw.Draw(big)
        caption = ("전우치 획득 (아이콘은 임시)" if frame < lift
                   else "목표 세트 Guppy, 1/3 → 모자란 2개를 훔쳐 옴")
        d.text((14, room_h * scale - 28), caption, font=font, fill=(255, 240, 200),
               stroke_width=2, stroke_fill=(20, 14, 16))
        frames.append(big.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=duration, loop=0)
    return frames


def contact_sheet(frames, picks):
    """Selected scene frames side by side, to review the motion as stills."""
    shots = [(k, frames[k].convert("RGB").crop((300, 60, 900, 430))) for k in picks]
    w, h = shots[0][1].size
    cols = 5
    rows = math.ceil(len(shots) / cols)
    sheet = Image.new("RGB", (cols * (w + 6) + 6, rows * (h + 26) + 6), (30, 26, 28))
    font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 14)
    d = ImageDraw.Draw(sheet)
    for i, (k, im) in enumerate(shots):
        x, y = 6 + (i % cols) * (w + 6), 6 + (i // cols) * (h + 26)
        sheet.paste(im, (x, y + 20))
        d.text((x, y), "frame %d (%.2fs)" % (k, k / 30), font=font, fill=(240, 230, 210))
    return sheet


# ---- runtime assets ------------------------------------------------------------

RUNTIME = {
    "sheet": os.path.join(ROOT, "resources", "gfx", "effects", "conch_jeonwoochi.png"),
    "anm2": os.path.join(ROOT, "resources", "gfx", "effects", "conch_jeonwoochi.anm2"),
    "icon": os.path.join(ROOT, "resources", "gfx", "items", "collectibles", "jeon_woochi.png"),
}
FRAME_W, FRAME_H = 64, 168
FRAME_SPOT = (32, 140)      # the pedestal's place in a frame (his feet 6 below it)
SHEET_COLS = 8
# anm2 events the runtime listens for (scripts/items/collectibles/jeon_woochi.lua)
EVENTS = (("Land", ARRIVE), ("Snap", 18), ("Charm", 19), ("Flash", FLASH), ("Throw", THROW),
          ("Pop", POP), ("Item", ITEM))


def effect_frames():
    """Every frame of one arrival as the game draws it: the figure, the
    streak, the circle, the 부적 and the smoke, centred on the pedestal's spot.
    The pedestal itself is the game's, placed at the Item event."""
    frames = []
    for t in range(SPOT_FRAMES):
        f = Image.new("RGBA", (FRAME_W, FRAME_H))
        jeonwoochi_layer(f, t, FRAME_SPOT, 0)
        smoke_layer(f, t, FRAME_SPOT)
        frames.append(f)
    return frames


def effect_sheet(frames):
    rows = math.ceil(len(frames) / SHEET_COLS)
    sheet = Image.new("RGBA", (SHEET_COLS * FRAME_W, rows * FRAME_H))
    for t, f in enumerate(frames):
        sheet.alpha_composite(f, ((t % SHEET_COLS) * FRAME_W, (t // SHEET_COLS) * FRAME_H))
    return sheet


def effect_anm2(count):
    tint = ('RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" '
            'RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false"')

    def frame(t, visible=True):
        x, y = (t % SHEET_COLS) * FRAME_W, (t // SHEET_COLS) * FRAME_H
        return ('          <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="%s" %s '
                'XPivot="%d" YPivot="%d" XCrop="%d" YCrop="%d" Width="%d" Height="%d" />'
                % ("true" if visible else "false", tint, FRAME_SPOT[0], FRAME_SPOT[1], x, y, FRAME_W, FRAME_H))

    def root(n):
        return ('      <RootAnimation>\n        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" '
                'Delay="%d" Visible="true" %s />\n      </RootAnimation>' % (n, tint))

    lines = ['<AnimatedActor>',
             '  <Info CreatedBy="ConchBlessing docs/previews/jeonwoochi/author.py" Version="20" Fps="30" />',
             '  <Content>', '    <Spritesheets>',
             '      <Spritesheet Id="0" Path="conch_jeonwoochi.png" />',
             '    </Spritesheets>', '    <Layers>', '      <Layer Id="0" Name="main" SpritesheetId="0" />',
             '    </Layers>', '    <Nulls />', '    <Events>']
    lines += ['      <Event Id="%d" Name="%s" />' % (i, name) for i, (name, _) in enumerate(EVENTS)]
    lines += ['    </Events>', '  </Content>', '  <Animations DefaultAnimation="Wait">',
              '    <Animation Name="Wait" FrameNum="1" Loop="true">', root(1), '      <LayerAnimations>',
              '        <LayerAnimation LayerId="0" Visible="true">', frame(0, visible=False),
              '        </LayerAnimation>', '      </LayerAnimations>', '      <NullAnimations />',
              '      <Triggers />', '    </Animation>',
              '    <Animation Name="Steal" FrameNum="%d" Loop="false">' % count, root(count),
              '      <LayerAnimations>', '        <LayerAnimation LayerId="0" Visible="true">']
    lines += [frame(t) for t in range(count)]
    lines += ['        </LayerAnimation>', '      </LayerAnimations>', '      <NullAnimations />', '      <Triggers>']
    lines += ['        <Trigger EventId="%d" AtFrame="%d" />' % (i, at) for i, (_, at) in enumerate(EVENTS)]
    lines += ['      </Triggers>', '    </Animation>', '  </Animations>', '</AnimatedActor>', '']
    return "\n".join(lines)


def icon_image():
    """The item icon, a first draft: his head and shoulders from the standing
    pose on the native 32x32 grid, the 갓 brim across the top, the shadowed
    eyes and the fan."""
    stand = image(pose("stand"))
    out = Image.new("RGBA", (32, 32))
    out.alpha_composite(stand.crop((4, 0, 36, 29)), (0, 1))
    # close the bust with the outline along its cut and round its corners, so
    # the icon keeps transparent padding below like any Isaac item
    px = out.load()
    bottom = 29
    filled = [x for x in range(32) if px[x, bottom][3] > 0]
    for x in filled:
        px[x, bottom] = PAL["K"]
    if filled:
        for x in (filled[0], filled[-1]):
            px[x, bottom] = (0, 0, 0, 0)
            px[x + (1 if x == filled[0] else -1), bottom] = PAL["K"]
            px[x, bottom - 1] = PAL["K"]
    return out


def apply():
    frames = effect_frames()
    effect_sheet(frames).save(RUNTIME["sheet"])
    with open(RUNTIME["anm2"], "w", encoding="utf-8", newline="\n") as f:
        f.write(effect_anm2(len(frames)))
    icon_image().save(RUNTIME["icon"])
    for path in RUNTIME.values():
        print(path)


def main(gif=True):
    os.makedirs(OUT, exist_ok=True)
    for name, im in (("sprite_review.png", sprite_review()), ("smoke_review.png", smoke_review())):
        im.save(os.path.join(OUT, name))
        print(os.path.join(OUT, name))
    if gif:
        path = os.path.join(OUT, "preview.gif")
        frames = preview_gif(path)
        print(path)
        slow = os.path.join(OUT, "preview_slow.gif")
        frames[0].save(slow, save_all=True, append_images=frames[1:], duration=100, loop=0)
        print(slow)
        start = 30
        picks = [start + t for t in (1, 2, 4, 6, 10, 13, 17, 18, 19, 20, 22, 26, 29, 30, 32, 33, 34, 36, 44, 52)]
        contact_sheet(frames, picks).save(os.path.join(OUT, "frames.png"))
        print(os.path.join(OUT, "frames.png"))


if __name__ == "__main__":
    import sys
    if "apply" in sys.argv[1:]:
        apply()
    else:
        main(gif="nogif" not in sys.argv[1:])
