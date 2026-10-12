"""Generate the Dragon familiar's runtime art.

The long azure dragon (profile head with antlers, a spine-symmetric body and
tail, hanging five-clawed legs, a floor shadow and the small sparks of current
that crackle along its body) and its lightning strike are drawn here at native pixel size with fixed seeds, so the PNG and ANM2 outputs
are reproducible. Run from any working directory:

    python generate_dragon_assets.py

Outputs (all generator-owned; edit this file, not the outputs):
    resources/gfx/familiar/familiar_dragon.png
    resources/gfx/dragon.anm2
    resources/gfx/effects/conch_dragon_lightning.png
    resources/gfx/effects/conch_dragon_lightning.anm2
    resources/sfx/conch_dragon_bolt_1..5.wav     (registered in content/sounds.xml)
    resources/sfx/conch_dragon_thunder_1..2.wav  (registered in content/sounds.xml)
    resources/sfx/conch_dragon_twister.wav   (registered in content/sounds.xml)
"""
import math
import random
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

from generate_upgrade_visual_assets import SAMPLE_RATE, biquad, normalized, write_wav

ROOT = Path(__file__).resolve().parent
GFX = ROOT / 'resources/gfx'

# Azure dragon palette, matched to the item icon: near-black outline, three
# azure tones with one sparse highlight, gold horns/eyes/whiskers, cream belly
# and pale cloud fins.
K = (14, 12, 30, 255)
D = (1, 40, 122, 255)
M = (0, 83, 184, 255)
L = (0, 135, 221, 255)
HI = (130, 205, 255, 255)
GD, G, GL = (150, 101, 23, 255), (227, 165, 6, 255), (255, 220, 9, 255)
CR, CRD = (232, 205, 132, 255), (184, 146, 74, 255)
FW, FC = (214, 240, 255, 255), (126, 188, 244, 255)
RED = (150, 30, 40, 255)
EYE = (255, 252, 230, 255)


def inside(x, y, pts):
    hit = False
    for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            hit = not hit
    return hit


class Canvas:
    def __init__(self, w, h):
        self.w, self.h, self.px = w, h, {}

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[(x, y)] = c

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(self.h):
            for x in range(self.w):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1:
                    self.put(x, y, c)

    def poly(self, pts, c):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            for x in range(int(min(xs)), int(max(xs)) + 1):
                if inside(x + .5, y + .5, pts):
                    self.put(x, y, c)

    def line(self, a, b, c):
        (x0, y0), (x1, y1) = a, b
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            self.put(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), c)

    def shade(self, base, light, dark):
        """Top-left light: exposed upper/left edges brighten, lower/right edges darken."""
        new = dict(self.px)
        for (x, y), c in self.px.items():
            if c != base:
                continue
            if (x, y - 1) not in self.px or (x - 1, y) not in self.px:
                new[(x, y)] = light
            elif (x, y + 1) not in self.px or (x + 1, y + 1) not in self.px:
                new[(x, y)] = dark
        self.px = new

    def outline(self):
        new = dict(self.px)
        for y in range(self.h):
            for x in range(self.w):
                if (x, y) not in self.px and any((x + dx, y + dy) in self.px
                                                 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    new[(x, y)] = K
        self.px = new

    def image(self):
        img = Image.new('RGBA', (self.w, self.h), (0, 0, 0, 0))
        for (x, y), c in self.px.items():
            img.putpixel((x, y), c)
        return img


# ---------------------------------------------------------------- dragon
# The body and tail are symmetric along the spine, so the game only rotates
# them; the profile head and the hanging legs are mirrored while they point
# steeply up or down.
CL = (255, 246, 214, 255)      # claw tips
SHADOW = (0, 0, 0, 90)


def disc(c, x, y, r, col):
    for dy in range(-math.ceil(r), math.ceil(r) + 1):
        for dx in range(-math.ceil(r), math.ceil(r) + 1):
            if dx * dx + dy * dy <= r * r + 0.3:
                c.put(round(x + dx), round(y + dy), col)


def thick(c, a, b, r, col):
    (x0, y0), (x1, y1) = a, b
    n = max(int(max(abs(x1 - x0), abs(y1 - y0)) * 2), 1)
    for i in range(n + 1):
        disc(c, x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n, r, col)


def rot(p, origin, deg):
    a = math.radians(deg)
    x, y = p[0] - origin[0], p[1] - origin[1]
    return (origin[0] + x * math.cos(a) - y * math.sin(a), origin[1] + x * math.sin(a) + y * math.cos(a))


def mirror(c, cy):
    """Copy the upper half onto the lower half (the spine row stays)."""
    for (x, y), col in list(c.px.items()):
        if y < cy:
            c.px[(x, 2 * cy - y)] = col


def round_shade(c, cy, half):
    """A body seen from above: the spine is the highest, brightest line, the flanks fall into shadow."""
    for (x, y), col in list(c.px.items()):
        if col != M:
            continue
        d = abs(y - cy) / max(half, 1)
        if d < 0.25:
            c.px[(x, y)] = L
        elif d > 0.75:
            c.px[(x, y)] = D


def flank_scales(c, cy, x0, x1, offset):
    for x in range(x0, x1, 3):
        for y in (cy - offset, cy + offset):
            if c.px.get((x, y)) in (M, L):
                c.px[(x, y)] = D


def ridge(c, cy, x0, x1):
    """Gold dorsal spikes along the spine, each leaning back toward the tail."""
    for x in range(x0, x1, 4):
        c.put(x, cy, GD); c.put(x + 1, cy, G); c.put(x + 2, cy, GL)


# ------------------------------------------------------------------ body
BODY_W, BODY_H, BODY_CY = 14, 15, 7


def body():
    c = Canvas(BODY_W, BODY_H)
    c.ellipse(7, BODY_CY + 0.5, 7, 6, M)
    round_shade(c, BODY_CY, 6)
    flank_scales(c, BODY_CY, 2, 13, 3)
    ridge(c, BODY_CY, 1, 12)
    c.put(4, BODY_CY - 2, HI); c.put(9, BODY_CY - 2, HI)
    c.outline()
    return c.image()


# Legs are a layer of their own, drawn under a plain body part. They hang to
# the belly side and are mirrored per leg while it heads steeply up or down.
LEGS_W, LEGS_H = 22, 24
LEGS_PIVOT = (11, 7)             # the body part's pivot, so legs sit under it


def claws(c, wrist, heading, open_, colour, tip):
    """Five gold claws fanned from the palm: the imperial five-clawed dragon."""
    disc(c, wrist[0], wrist[1], 1.0, colour)
    for k in range(5):
        ang = heading + (k - 2) * (15 + open_)
        mid = rot((wrist[0] + 2.2, wrist[1]), wrist, ang)
        end = rot((wrist[0] + 3.5, wrist[1]), wrist, ang)
        c.put(round(mid[0]), round(mid[1]), G if colour == M else GD)
        c.put(round(end[0]), round(end[1]), tip)


def hanging_leg(c, shoulder, swing, near, open_):
    """A short thigh down and back, a forearm forward, a foot of five claws."""
    colour = M if near else D
    elbow = rot((shoulder[0] - 3, shoulder[1] + 4), shoulder, swing)
    wrist = rot((shoulder[0] + 1, shoulder[1] + 8), shoulder, swing)
    thick(c, shoulder, elbow, 1.6 if near else 1.3, colour)
    thick(c, elbow, wrist, 1.1 if near else 0.9, colour)
    if near:
        c.put(round(elbow[0]), round(elbow[1]) - 1, L)
        tuft = rot((elbow[0] - 3, elbow[1] + 1), elbow, swing * 0.5)
        c.line((round(elbow[0]), round(elbow[1])), (round(tuft[0]), round(tuft[1])), FC)
        c.put(round(tuft[0]), round(tuft[1]), FW)
    claws(c, wrist, 25 + swing * 0.4, open_, colour, CL if near else G)


def legs(frame):
    c = Canvas(LEGS_W, LEGS_H)
    swing = (-20, 2, 22, 2)[frame]
    open_ = (0, 4, 8, 4)[frame]
    # The far leg strokes out of step behind the near one.
    hanging_leg(c, (8, LEGS_PIVOT[1] + 4), -swing * 0.8, False, 8 - open_)
    hanging_leg(c, (13, LEGS_PIVOT[1] + 4), swing, True, open_)
    c.outline()
    return c.image()


# ------------------------------------------------------------------ head (profile)
# The head alone is drawn in profile; it is mirrored only while it points
# steeply up or down, where the flip is hardest to see.
RED = (150, 30, 40, 255)
CR, CRD = (232, 205, 132, 255), (184, 146, 74, 255)
HEAD_W, HEAD_H = 41, 31
HEAD_PIVOT = (10, 14)            # the neck joint, centred on the body tube
NECK_TOP, NECK_BOTTOM = 8, 19


def side_tube(c, x0, x1, top, bottom):
    for y in range(top, bottom + 1):
        edge = min(y - top, bottom - y)
        inset = 2 if edge == 0 else 1 if edge == 1 else 0
        for x in range(x0 + inset, x1 + 1):
            c.put(x, y, M)


def side_scales(c, x0, x1, rows):
    for r, y in enumerate(rows):
        for x in range(x0 + (2 if r % 2 else 0), x1 - 1, 4):
            for px, py in ((x, y), (x + 1, y + 1), (x + 2, y + 1), (x + 3, y)):
                if c.px.get((px, py)) == M:
                    c.put(px, py, D)


def jaw_plates(c, x0, x1, top, bottom):
    for y in range(top, bottom + 1):
        for x in range(x0, x1 + 1):
            if (x, y) in c.px:
                c.put(x, y, CRD if (x - x0) % 3 == 1 or y == bottom else CR)


def antler(c, root):
    thick(c, root, (root[0] - 7, root[1] - 6), 0.6, G)
    thick(c, (root[0] - 3, root[1] - 3), (root[0] - 1, root[1] - 6), 0.5, G)
    thick(c, (root[0] - 6, root[1] - 5), (root[0] - 9, root[1] - 5), 0.5, G)
    c.put(root[0] - 7, root[1] - 7, GL); c.put(root[0] - 1, root[1] - 7, GL); c.put(root[0] - 10, root[1] - 5, GL)


def head():
    c = Canvas(HEAD_W, HEAD_H)
    # Cloud mane flowing back from the skull and jaw.
    c.poly([(14, 8), (3, 4), (8, 10), (1, 12), (9, 14), (2, 19), (11, 17), (6, 24), (15, 19)], FC)
    c.poly([(12, 9), (6, 6), (9, 11), (4, 13), (10, 14)], FW)
    c.poly([(12, 17), (7, 21), (13, 19)], FW)
    # Neck stub matching the body tube, then the skull and the long snout.
    side_tube(c, 8, 16, NECK_TOP, NECK_BOTTOM)
    c.poly([(12, 10), (15, 7), (21, 6), (25, 8), (31, 9), (35, 8), (37, 8), (39, 10), (39, 13), (33, 14),
            (25, 15), (17, 18), (12, 18)], M)
    # Lower jaw, dropped open.
    c.poly([(17, 18), (25, 17), (35, 17), (37, 19), (34, 21), (25, 22), (18, 21)], M)
    c.shade(M, L, D)
    jaw_plates(c, 18, 34, 21, 22)
    # Mouth: dark red gap with fangs.
    for x in range(24, 38):
        for y in (15, 16):
            if x - 24 >= (16 - y) * 3:
                c.put(x, y, RED)
    for x, y in ((29, 15), (34, 15), (37, 15), (31, 16)):
        c.put(x, y, EYE)
    # Heavy brow over a gold eye with a slit pupil; flared nostril; snout highlight.
    for x, y in ((19, 9), (20, 9), (21, 9), (22, 9), (23, 10), (24, 10), (25, 11)):
        c.put(x, y, D)
    for x, y in ((20, 10), (21, 10), (22, 10), (20, 11), (21, 11), (22, 11), (23, 11)):
        c.put(x, y, GL)
    c.put(23, 11, G); c.put(21, 10, K); c.put(21, 11, K); c.put(20, 10, EYE)
    c.put(37, 10, K); c.put(36, 9, D)
    for x in (29, 30, 31):
        c.put(x, 10, HI)
    c.put(17, 8, HI); c.put(18, 8, HI)
    side_scales(c, 13, 19, (13,))
    # Beard tuft under the chin.
    c.poly([(20, 22), (16, 27), (22, 24), (21, 29), (25, 23)], FW)
    c.poly([(21, 23), (19, 26), (23, 24)], FC)
    antler(c, (19, 8))
    # The long whisker trailing from the upper lip.
    for a, b in (((37, 14), (36, 18)), ((36, 18), (32, 22)), ((32, 22), (27, 25))):
        c.line(a, b, GL)
    c.outline()
    return c.image()


# ------------------------------------------------------------------ tail
TAIL_W, TAIL_H, TAIL_CY = 26, 21, 10
TAIL_PIVOT = (20, TAIL_CY)


def tail(frame):
    c = Canvas(TAIL_W, TAIL_H)
    wave = (0, 2)[frame]
    c.poly([(11, TAIL_CY - 1), (1, TAIL_CY - 9 + wave), (5, TAIL_CY - 3), (0, TAIL_CY - 1 + wave // 2), (11, TAIL_CY)], FC)
    c.poly([(10, TAIL_CY - 1), (4, TAIL_CY - 5 + wave), (8, TAIL_CY - 1)], FW)
    for x in range(9, 26):
        t = (x - 9) / 16
        half = 1.5 + t * 4
        for y in range(round(TAIL_CY - half), TAIL_CY + 1):
            c.put(x, y, M)
    mirror(c, TAIL_CY)
    round_shade(c, TAIL_CY, 5)
    flank_scales(c, TAIL_CY, 15, 25, 2)
    ridge(c, TAIL_CY, 12, 24)
    c.outline()
    return c.image()


def shadow():
    c = Canvas(14, 7)
    c.ellipse(7, 3.5, 7, 3.5, SHADOW)
    return c.image()


# ---------------------------------------------------------------- lightning
BOLT_W, BOLT_H = 96, 320
BOLT_PIVOT = (48, 296)
HALO, BDEEP, BMID, BPALE, BCORE = ((40, 70, 200, 90), (40, 80, 210, 200), (90, 160, 255, 255),
                                   (196, 236, 255, 255), (255, 255, 255, 255))
# A stepped leader feels its way down, the return stroke lights every branch,
# the channel flashes, strikes again once, then flickers out.
BOLT_FRAMES = ('leader', 'strike', 'flash', 'restrike', 'flicker', 'thin', 'fade')
# Bolt shapes, one row of frames each: the classic forked bolt, a channel that
# splits in two halfway down, a wide spray of short branches, and a slender bolt
# that swings far out to one side. Runtime picks one per strike.
BOLT_VARIANTS = (
    dict(seed=11, forks=5, length=80, jitter=14, start=14),
    dict(seed=47, forks=3, length=70, jitter=12, start=10, split=True),
    dict(seed=83, forks=9, length=46, jitter=10, start=8),
    dict(seed=131, forks=2, length=60, jitter=22, start=26, swing=True),
)
SCORCH_W, SCORCH_H = 40, 18
SCORCH_FRAMES = 3


def bolt_path(rng, x0, y0, x1, y1, step=(14, 30), jitter=14):
    pts = [(x0, y0)]
    n = max(2, int(abs(y1 - y0) / ((step[0] + step[1]) / 2)))
    for i in range(1, n):
        t = i / n
        big = rng.random() < 0.3
        x = x0 + (x1 - x0) * t + rng.uniform(-jitter, jitter) * (1.8 if big else 1.0)
        pts.append((x, y0 + (y1 - y0) * t + rng.uniform(-4, 4)))
    pts.append((x1, y1))
    return [(round(x), round(y)) for x, y in pts]


def stamp(img, x, y, r, col):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r + r * 0.6:
                px, py = x + dx, y + dy
                if 0 <= px < BOLT_W and 0 <= py < BOLT_H:
                    cur = img.getpixel((px, py))
                    if col[3] >= cur[3] or cur[3] == 0:
                        img.putpixel((px, py), col)


def bolt_line(img, a, b, r, col):
    (x0, y0), (x1, y1) = a, b
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        stamp(img, round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), r, col)


def stroke(img, pts, layers):
    for r, col in layers:
        for a, b in zip(pts, pts[1:]):
            bolt_line(img, a, b, r, col)


def forks(rng, main, count, length):
    """Branches off the main channel, each with its own twigs (two levels deep)."""
    out = []
    for _ in range(count):
        x, y = main[rng.randint(1, len(main) - 3)]
        side = rng.choice((-1, 1))
        end = (max(6, min(BOLT_W - 6, x + side * rng.randint(length // 3, length // 2))), y + rng.randint(length // 2, length))
        branch = bolt_path(rng, x, y, end[0], end[1], step=(8, 14), jitter=6)
        out.append(branch)
        for _ in range(rng.randint(1, 2)):
            tx, ty = branch[rng.randint(1, len(branch) - 1)]
            twig = bolt_path(rng, tx, ty, max(3, min(BOLT_W - 3, tx + side * rng.randint(6, 14))),
                             ty + rng.randint(8, 18), step=(6, 10), jitter=3)
            out.append(twig)
    return out


def leader_path(main, reach):
    """The stepped leader: the main channel's upper part, as far down as `reach`."""
    return [pt for pt in main if pt[1] <= BOLT_PIVOT[1] * reach]


def sparks(img, rng, count, size):
    """Bright chips flung up and out of the strike point."""
    cx, cy = BOLT_PIVOT
    for _ in range(count):
        a = rng.uniform(math.pi * 1.05, math.pi * 1.95)
        d = rng.uniform(size * 0.9, size * 2.0)
        px, py = round(cx + math.cos(a) * d), round(cy + math.sin(a) * d * 0.8)
        if 0 <= px < BOLT_W - 1 and 0 <= py < BOLT_H - 1:
            img.putpixel((px, py), BCORE)
            img.putpixel((px + 1, py), BPALE)


def impact(img, rng, size, bright=True):
    cx, cy = BOLT_PIVOT
    for grow, col in ((5, HALO), (3, BDEEP), (1, BMID), (-1, BPALE), (-3, BCORE)):
        rx, ry = size + grow, (size + grow) * 0.45
        if rx <= 0:
            continue
        for dy in range(-int(ry) - 1, int(ry) + 2):
            for dx in range(-int(rx) - 1, int(rx) + 2):
                if (dx / rx) ** 2 + (dy / max(ry, 0.5)) ** 2 <= 1 and 0 <= cx + dx < BOLT_W and 0 <= cy + dy < BOLT_H:
                    img.putpixel((cx + dx, cy + dy), col)
    for angle in range(0, 360, 30):
        a = math.radians(angle + rng.uniform(-8, 8))
        length = size * (1.9 if abs(math.cos(a)) > 0.7 else 1.3) * rng.uniform(0.8, 1.2)
        tip = (round(cx + math.cos(a) * length), round(cy + math.sin(a) * length * 0.45 - (6 if math.sin(a) < 0 else 0)))
        bolt_line(img, (cx, cy), tip, 0, BPALE if bright else BMID)
    for _ in range(10 if bright else 5):
        a = rng.uniform(math.pi, 2 * math.pi)
        d = rng.uniform(size * 0.8, size * 2.2)
        px, py = round(cx + math.cos(a) * d), round(cy + math.sin(a) * d * 0.7)
        if 0 <= px < BOLT_W and 0 <= py < BOLT_H:
            img.putpixel((px, py), BCORE if bright else BPALE)


def swing_path(rng, x0, y0, x1, y1, jitter):
    """A channel that bows far out to one side before coming down on the pivot."""
    side = rng.choice((-1, 1))
    pts = bolt_path(rng, x0, y0, x1, y1, jitter=jitter)
    n = len(pts) - 1
    return [(max(4, min(BOLT_W - 4, round(x + side * 26 * math.sin(math.pi * i / n)))), y) for i, (x, y) in enumerate(pts)]


def bolt_frame(kind, variant=0):
    v = BOLT_VARIANTS[variant]
    seed = v['seed']
    rng = random.Random(seed)
    img = Image.new('RGBA', (BOLT_W, BOLT_H), (0, 0, 0, 0))
    start = BOLT_PIVOT[0] + rng.randint(-v['start'], v['start'])
    if v.get('swing'):
        main = swing_path(rng, start, -10, BOLT_PIVOT[0], BOLT_PIVOT[1], v['jitter'])
    else:
        main = bolt_path(rng, start, -10, BOLT_PIVOT[0], BOLT_PIVOT[1], jitter=v['jitter'])
    branches = forks(random.Random(seed * 31 + 1), main, v['forks'], v['length'])
    if v.get('split'):
        # A second channel peels off halfway and lands beside the first.
        x, y = main[len(main) // 2]
        twin = bolt_path(random.Random(seed * 7 + 3), x, y, BOLT_PIVOT[0] + rng.choice((-14, 14)), BOLT_PIVOT[1] - 2,
                         step=(10, 20), jitter=8)
        branches = [twin] + branches
    if kind == 'leader':
        # Faint, thin and not yet grounded, with stubby feelers off it.
        stroke(img, leader_path(main, 0.7), [(1, BDEEP), (0, BMID)])
        for f in branches[:3]:
            stub = [pt for pt in f[:3] if pt[1] <= BOLT_PIVOT[1] * 0.7]
            if len(stub) > 1:
                stroke(img, stub, [(0, BDEEP)])
    elif kind == 'strike':
        stroke(img, main, [(7, HALO)])
        for f in branches:
            stroke(img, f, [(3, HALO), (2, BDEEP), (1, BMID), (0, BCORE)])
        stroke(img, main, [(5, BDEEP), (4, BMID), (2, BPALE), (1, BCORE)])
        impact(img, rng, 15)
        sparks(img, rng, 14, 15)
    elif kind == 'restrike':
        # The same channel lights again, a little thinner, with fewer branches.
        stroke(img, main, [(5, HALO)])
        for f in branches[:4]:
            stroke(img, f, [(1, BDEEP), (0, BPALE)])
        stroke(img, main, [(3, BDEEP), (2, BMID), (1, BPALE), (0, BCORE)])
        impact(img, rng, 11)
        sparks(img, rng, 8, 12)
    elif kind == 'flash':
        stroke(img, main, [(6, HALO)])
        for f in branches:
            stroke(img, f, [(2, BDEEP), (1, BMID), (0, BPALE)])
        stroke(img, main, [(4, BDEEP), (3, BMID), (2, BPALE), (1, BCORE)])
        impact(img, rng, 12)
    elif kind == 'flicker':
        for f in branches[:2]:
            stroke(img, f, [(1, BMID), (0, BPALE)])
        stroke(img, main, [(3, BDEEP), (2, BMID), (1, BPALE), (0, BCORE)])
        impact(img, rng, 9, bright=False)
    elif kind == 'thin':
        stroke(img, main, [(1, BMID), (0, BPALE)])
        impact(img, rng, 6, bright=False)
    else:
        stroke(img, main, [(0, BDEEP)])
    return img


def scorch(frame, seed=23):
    """A burnt patch left on the floor, its embers dying over three frames."""
    rng = random.Random(seed)
    img = Image.new('RGBA', (SCORCH_W, SCORCH_H), (0, 0, 0, 0))
    cx, cy = SCORCH_W / 2, SCORCH_H / 2
    for y in range(SCORCH_H):
        for x in range(SCORCH_W):
            d = ((x + 0.5 - cx) / (SCORCH_W / 2)) ** 2 + ((y + 0.5 - cy) / (SCORCH_H / 2)) ** 2
            if d <= 1:
                alpha = round(150 * (1 - d) ** 0.6)
                img.putpixel((x, y), (24, 20, 30, alpha))
    embers = [(round(cx + rng.uniform(-14, 14)), round(cy + rng.uniform(-5, 5))) for _ in range(9)]
    for i, (x, y) in enumerate(embers):
        if i < 9 - frame * 3:
            img.putpixel((x, y), (255, 190, 90, 255) if frame == 0 else (220, 120, 60, 220))
    return img


# ---------------------------------------------------------------- sparks
# A small zigzag of current: a thin white crackle in a faint glow, a second
# pale zigzag, then a few dim pixels as it dies. Drawn at runtime on random
# body parts and turned any way, so one shape per frame is enough.
SPARK_W, SPARK_H = 15, 9
SPARK_PIVOT = (7, 4)
SPARK_PATHS = ([(1, 5), (4, 2), (6, 6), (9, 2), (11, 6), (13, 3)],
               [(1, 3), (3, 6), (6, 2), (8, 6), (11, 2), (13, 5)])
SPARK_GLOW = (60, 110, 230, 110)


def line_points(a, b):
    (x0, y0), (x1, y1) = a, b
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    return [(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n)) for i in range(n + 1)]


def spark(frame):
    img = Image.new('RGBA', (SPARK_W, SPARK_H), (0, 0, 0, 0))
    path = SPARK_PATHS[min(frame, 1)]
    core = []
    for a, b in zip(path, path[1:]):
        for pt in line_points(a, b):
            if pt not in core:
                core.append(pt)
    if frame >= 2:
        # Dying: every other pixel, dim.
        for k, (x, y) in enumerate(core):
            if k % 2 == 0:
                img.putpixel((x, y), BMID)
        return img
    if frame == 0:
        # A thin white crackle with a faint blue glow around it.
        for x, y in core:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    px, py = x + dx, y + dy
                    if 0 <= px < SPARK_W and 0 <= py < SPARK_H and (px, py) not in core:
                        img.putpixel((px, py), SPARK_GLOW)
    for x, y in core:
        img.putpixel((x, y), BCORE if frame == 0 else BPALE)
    return img


# ---------------------------------------------------------------- weather sounds
# 진's bolts come several times a second for a whole fight, so they follow what
# makes a repeated sound grating (Zwicker and Fastl's annoyance terms and game
# audio practice) and avoid each part of it: loudness (they are played quiet),
# roughness (no crackling clicks), pulsing near 4 Hz (a soft onset and a tail
# long enough that bolts blend into one rolling rumble), sharpness (almost
# nothing above 1 kHz) and identical repeats (five takes, a small pitch spread).
def loudest_db(samples):
    """The tests' measure: the loudest 50 ms, as RMS in dB."""
    window, energy, best = int(SAMPLE_RATE * .05), 0.0, 0.0
    for i, v in enumerate(samples):
        energy += v * v
        if i >= window:
            energy -= samples[i - window] ** 2
        best = max(best, energy / window)
    return 10 * math.log10(max(best, 1e-12))


def at_level(samples, target=-10.0):
    """Scale so the loudest 50 ms sits at `target` dB, every take alike; the
    cue volume in dragon.lua then sets the level the game plays it at."""
    gain = 10 ** ((target - loudest_db(samples)) / 20)
    gain = min(gain, 0.98 / max(abs(v) for v in samples))
    return [v * gain for v in samples]


def fade_end(x, seconds, tail):
    return 1.0 if x < seconds - tail else 0.5 + 0.5 * math.cos(math.pi * (x - seconds + tail) / tail)


def brown(rng, n, keep=0.99, step=0.14):
    last, out = 0.0, []
    for _ in range(n):
        last = keep * last + step * (rng.random() * 2 - 1)
        out.append(last)
    return out


def small_thunder(seed, seconds=0.85):
    """One bolt: a quiet, muffled roll, a soft swell and a smaller roll after it."""
    rng = random.Random(seed)
    n = int(SAMPLE_RATE * seconds)
    low = normalized(biquad(biquad(brown(rng, n), 'low', 320), 'high', 40))
    mid = normalized(biquad(biquad([rng.random() * 2 - 1 for _ in range(n)], 'low', 750), 'high', 260))
    second = 0.2 + 0.12 * rng.random()
    mix = []
    for i in range(n):
        x = i / SAMPLE_RATE
        swell = min(1, x / 0.02) * math.exp(-x / 0.22)
        if x > second:
            d = x - second
            swell += 0.42 * min(1, d / 0.07) * math.exp(-d / 0.24)
        mix.append((low[i] * 0.85 + mid[i] * 0.28) * swell * fade_end(x, seconds, 0.22))
    return normalized(biquad(mix, 'high', 35))


def rolling_thunder(seed, seconds=2.4):
    """The thunderclap every few seconds: the same smooth roll, larger, with no
    sharp crack: a muffled break, a low boom and three slow rolls that fade."""
    rng = random.Random(seed)
    n = int(SAMPLE_RATE * seconds)
    low = normalized(biquad(biquad(brown(rng, n, 0.992, 0.12), 'low', 200), 'high', 30))
    mid = normalized(biquad(biquad([rng.random() * 2 - 1 for _ in range(n)], 'low', 700), 'high', 150))
    rolls = [(0.0, 0.35, 1.0)] + [(0.35 + 0.38 * k + 0.2 * rng.random(), 0.45 + 0.2 * rng.random(), 0.6 - 0.15 * k)
                                  for k in range(3)]
    mix = []
    for i in range(n):
        x = i / SAMPLE_RATE
        swell = sum(h * min(1, (x - s) / 0.07) * math.exp(-(x - s) / w) for s, w, h in rolls if x >= s)
        mix.append((low[i] * 0.72 + mid[i] * 0.35) * swell * min(1, x / 0.025) * fade_end(x, seconds, 0.5))
    return normalized(biquad(mix, 'high', 30))


BOLT_TAKES = 5
THUNDER_TAKES = 2


def twister_wind(seconds=5.3, seed=0x7417):
    """The roar of a dragon twister for its whole life: wind swirling round.

    Band-limited noise whose loudness and brightness sweep round about three
    times a second, over a low roar, with a soft whistle that rises as it
    winds up. It fades in as the pillar rises and out as it falls.
    """
    rng = random.Random(seed)
    n = int(SAMPLE_RATE * seconds)

    def noise():
        return rng.random() * 2 - 1

    hiss = normalized(biquad(biquad([noise() for _ in range(n)], 'high', 350), 'low', 1800))
    last, roar = 0.0, []
    for _ in range(n):
        last = 0.985 * last + 0.15 * noise()
        roar.append(last)
    roar = normalized(biquad(biquad(roar, 'low', 260), 'high', 40))
    mix = []
    phase = 0.0
    for i in range(n):
        x = i / SAMPLE_RATE
        swirl = 0.55 + 0.45 * math.sin(2 * math.pi * 2.8 * x + 0.6 * math.sin(2 * math.pi * 0.4 * x))
        phase += 2 * math.pi * (520 + 160 * min(1, x / 1.5) + 40 * math.sin(2 * math.pi * 2.8 * x)) / SAMPLE_RATE
        whistle = math.sin(phase) * 0.06 * swirl
        envelope = min(1, x / 0.35) * (1 if x < seconds - 0.6 else 0.5 + 0.5 * math.cos(math.pi * (x - seconds + 0.6) / 0.6))
        mix.append((hiss[i] * 0.55 * swirl + roar[i] * 0.6 + whistle) * envelope)
    return [v * 0.8 for v in normalized(biquad(mix, 'high', 45))]


# ---------------------------------------------------------------- ANM2
COMMON = dict(XPosition='0', YPosition='0', XScale='100', YScale='100', Delay='1', Visible='true',
              RedTint='255', GreenTint='255', BlueTint='255', AlphaTint='255',
              RedOffset='0', GreenOffset='0', BlueOffset='0', Rotation='0', Interpolated='false')


def write_anm2(path, sheet, default, animations):
    """animations: list of (name, [frames]) where a frame is (x, y, w, h, px, py) or None (hidden)."""
    root = ET.Element('AnimatedActor')
    ET.SubElement(root, 'Info', CreatedBy='ConchBlessing', Version='20', Fps='30')
    content = ET.SubElement(root, 'Content')
    ET.SubElement(ET.SubElement(content, 'Spritesheets'), 'Spritesheet', Id='0', Path=sheet)
    ET.SubElement(ET.SubElement(content, 'Layers'), 'Layer', Id='0', Name='body', SpritesheetId='0')
    ET.SubElement(content, 'Nulls')
    ET.SubElement(content, 'Events')
    anims = ET.SubElement(root, 'Animations', DefaultAnimation=default)
    for name, frames in animations:
        anim = ET.SubElement(anims, 'Animation', Name=name, FrameNum=str(len(frames)), Loop='false')
        ET.SubElement(ET.SubElement(anim, 'RootAnimation'), 'Frame', **{**COMMON, 'Delay': str(len(frames))})
        layer = ET.SubElement(ET.SubElement(anim, 'LayerAnimations'), 'LayerAnimation', LayerId='0', Visible='true')
        for frame in frames:
            x, y, w, h, px, py = frame or (0, 0, 1, 1, 0, 0)
            ET.SubElement(layer, 'Frame', **{**COMMON, 'Visible': 'true' if frame else 'false'},
                          XCrop=str(x), YCrop=str(y), Width=str(w), Height=str(h), XPivot=str(px), YPivot=str(py))
        ET.SubElement(anim, 'NullAnimations')
        ET.SubElement(anim, 'Triggers')
    ET.indent(root, space='  ')
    path.write_text(ET.tostring(root, encoding='unicode') + '\n', encoding='utf-8')


# Pivots sit on the spine where each part joins the trail. Legs stroke through
# four poses and the tail tuft flutters between two; the shadow is drawn on
# the floor under the floating body. Only the head and legs are ever mirrored.
PARTS = [('Head', [head()], HEAD_PIVOT),
         ('Body', [body()], (7, BODY_CY)),
         ('Legs', [legs(f) for f in range(4)], LEGS_PIVOT),
         ('Tail', [tail(f) for f in range(2)], TAIL_PIVOT),
         ('Shadow', [shadow()], (7, 3)),
         ('Spark', [spark(f) for f in range(3)], SPARK_PIVOT)]


def main():
    width = sum(img.size[0] for _, imgs, _ in PARTS for img in imgs)
    height = max(img.size[1] for _, imgs, _ in PARTS for img in imgs)
    sheet = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    animations, x = [('Hidden', [None])], 0
    for name, imgs, (px, py) in PARTS:
        frames = []
        for img in imgs:
            sheet.alpha_composite(img, (x, 0))
            frames.append((x, 0, img.size[0], img.size[1], px, py))
            x += img.size[0]
        animations.append((name, frames))
    (GFX / 'familiar').mkdir(parents=True, exist_ok=True)
    sheet.save(GFX / 'familiar/familiar_dragon.png')
    write_anm2(GFX / 'dragon.anm2', 'familiar/familiar_dragon.png', 'Hidden', animations)

    # One row per bolt shape; the burnt patch frames sit after the first row.
    bolts = Image.new('RGBA', (BOLT_W * len(BOLT_FRAMES) + SCORCH_W * SCORCH_FRAMES, BOLT_H * len(BOLT_VARIANTS)),
                      (0, 0, 0, 0))
    animations = []
    for v in range(len(BOLT_VARIANTS)):
        frames = []
        for i, kind in enumerate(BOLT_FRAMES):
            bolts.alpha_composite(bolt_frame(kind, v), (i * BOLT_W, v * BOLT_H))
            frames.append((i * BOLT_W, v * BOLT_H, BOLT_W, BOLT_H, BOLT_PIVOT[0], BOLT_PIVOT[1]))
        animations.append(('Strike' if v == 0 else 'Strike%d' % (v + 1), frames))
    burns, left = [], BOLT_W * len(BOLT_FRAMES)
    for f in range(SCORCH_FRAMES):
        bolts.alpha_composite(scorch(f), (left + f * SCORCH_W, 0))
        burns.append((left + f * SCORCH_W, 0, SCORCH_W, SCORCH_H, SCORCH_W // 2, SCORCH_H // 2))
    animations.append(('Scorch', burns))
    bolts.save(GFX / 'effects/conch_dragon_lightning.png')
    write_anm2(GFX / 'effects/conch_dragon_lightning.anm2', 'conch_dragon_lightning.png', 'Strike', animations)
    (ROOT / 'resources/sfx').mkdir(parents=True, exist_ok=True)
    for k in range(BOLT_TAKES):
        write_wav(ROOT / f'resources/sfx/conch_dragon_bolt_{k + 1}.wav', at_level(small_thunder(0xE500 + k)))
    for k in range(THUNDER_TAKES):
        write_wav(ROOT / f'resources/sfx/conch_dragon_thunder_{k + 1}.wav', at_level(rolling_thunder(0xF600 + k)))
    write_wav(ROOT / 'resources/sfx/conch_dragon_twister.wav', twister_wind())
    print('dragon assets written')


if __name__ == '__main__':
    main()
