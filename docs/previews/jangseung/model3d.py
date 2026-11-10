"""장승 built as real 3D geometry and rendered in the room's own camera (user
request 2026-11-10: "no pictures pasted on boxes; model the 장승 we designed,
roughly, lean it on the wall and work from that").

Each statue is a round wooden post with its features made of solids:
천하대장군 wears a winged official's cap (a crown, a band and two flat wings
at the back), angry brows, bulging eyes with dark pupils, a fist nose, an open
mouth with a row of teeth and two corner tusks, a carved beard and his name
carved down the post; 지하여장군 has her hair and topknot, round eyes, red
cheeks and lips and small fangs. The red-route pair wears a red cloth. Each
post stands on the floor beside a door, facing into the room, and leans back
until its head rests on the wall.

The camera is the one scene3d.py matches to the basement backdrop: a pinhole
above the room's middle, the floor at the game's 26 px per 40 units. Triangles
are flat-shaded in three tones per material from a light at the top left,
depth-tested, and drawn twice: at the game's own pixel size with a 1 px dark
outline (the sprite's reference) and four times larger (to see the form).

    python docs/previews/jangseung/model3d.py [camera height] [lean degrees]
    python docs/previews/jangseung/model3d.py april    (the April Fools set)
"""
import importlib.util
import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / '.tmp/jangseung'


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    saved = sys.argv
    sys.argv = [saved[0]]
    spec.loader.exec_module(module)
    sys.argv = saved
    return module


placement = load('placement', 'docs/previews/jangseung/placement.py')
author = load('author', 'docs/previews/jangseung/author.py')

SCALE = 26 / 40
CENTER = np.array([320.0, 280.0])
IMG_CENTER = np.array([234.0, 156.0])
LIGHT = np.array([-0.55, 0.25, 0.80])  # from the top left, and from above the room
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# material: (shadow, mid, lit) colours, matching the sprite palette
MATERIALS = {
    'wood': ((92, 60, 40), (138, 96, 60), (178, 132, 84)),
    'dark': ((30, 22, 20), (30, 22, 20), (52, 40, 34)),
    'hat': ((30, 28, 34), (40, 36, 44), (86, 80, 96)),
    'white': ((190, 182, 164), (238, 230, 208), (250, 246, 232)),
    'red': ((122, 30, 28), (178, 46, 38), (214, 96, 72)),
    'carve': ((60, 38, 26), (70, 44, 30), (84, 54, 36)),
}
MAT_IDS = {name: i + 1 for i, name in enumerate(MATERIALS)}

# ---------------------------------------------------------------- solids
# Local frame: x to the statue's right as seen from the front, y toward its
# front (into the room), z up from its foot. Each solid is a list of
# triangles (3x3 local points) with one material.


def cylinder(r, z0, z1, mat, seg=18, x=0.0, y=0.0, caps=True):
    tris = []
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        p0 = (x + r * math.cos(a0), y + r * math.sin(a0))
        p1 = (x + r * math.cos(a1), y + r * math.sin(a1))
        tris.append(((p0[0], p0[1], z0), (p1[0], p1[1], z0), (p1[0], p1[1], z1)))
        tris.append(((p0[0], p0[1], z0), (p1[0], p1[1], z1), (p0[0], p0[1], z1)))
        if caps:
            tris.append(((x, y, z1), (p0[0], p0[1], z1), (p1[0], p1[1], z1)))
            tris.append(((x, y, z0), (p1[0], p1[1], z0), (p0[0], p0[1], z0)))
    return [(t, mat) for t in tris]


def sphere(cx, cy, cz, r, mat, seg=10, rings=7, squash=(1, 1, 1)):
    tris = []
    for j in range(rings):
        t0, t1 = math.pi * j / rings, math.pi * (j + 1) / rings
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg

            def p(t, a):
                return (cx + squash[0] * r * math.sin(t) * math.cos(a), cy + squash[1] * r * math.sin(t) * math.sin(a),
                        cz + squash[2] * r * math.cos(t))
            tris.append((p(t0, a0), p(t1, a0), p(t1, a1)))
            tris.append((p(t0, a0), p(t1, a1), p(t0, a1)))
    return [(t, mat) for t in tris]


def box(cx, cy, cz, sx, sy, sz, mat, tilt=0.0):
    """An axis box (sizes sx, sy, sz), turned by `tilt` degrees about its own
    y axis (a brow sloping toward the nose)."""
    c, s = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    pts = []
    for dx in (-sx / 2, sx / 2):
        for dy in (-sy / 2, sy / 2):
            for dz in (-sz / 2, sz / 2):
                x, z = dx * c - dz * s, dx * s + dz * c
                pts.append((cx + x, cy + dy, cz + z))
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = []
    for a, b, c_, d in faces:
        tris.append((pts[a], pts[b], pts[c_]))
        tris.append((pts[a], pts[c_], pts[d]))
    return [(t, mat) for t in tris]


R = 11.0      # the post's radius
WALL_FACE = 8.0  # where the wall's face meets the floor, from the wall's middle, as the backdrop draws it
H = 57.0      # its height to the top of the head: the side walls' caps reach the wall's rim
FRONT = R     # the front surface


def name_marks():
    """The name carved down the front below the beard: short strokes."""
    out = []
    for k in range(3):
        z = H - 42 - k * 4.6
        out += box(-1.2, FRONT - 0.3, z, 2.6, 1.6, 1.1, 'carve')
        out += box(1.0, FRONT - 0.3, z - 1.8, 1.3, 1.6, 1.1, 'carve')
    return out


def cheonha(red=False):
    s = cylinder(R, 0, H, 'wood')
    # cap: band, crown, the two flat wings at the back
    s += cylinder(R + 0.8, H - 3, H, 'hat')
    s += cylinder(R - 2.5, H, H + 8, 'hat')
    s += box(-14, -4, H + 4.5, 9, 1.4, 3.6, 'hat')
    s += box(14, -4, H + 4.5, 9, 1.4, 3.6, 'hat')
    # angry brows sloping down to the nose
    s += box(-5.2, FRONT, H - 8.5, 8.0, 2.8, 2.4, 'dark', tilt=-20)
    s += box(5.2, FRONT, H - 8.5, 8.0, 2.8, 2.4, 'dark', tilt=20)
    # bulging eyes and their pupils
    for x in (-5.0, 5.0):
        s += sphere(x, FRONT - 0.8, H - 14, 4.4, 'white')
        s += sphere(x, FRONT + 3.0, H - 14.6, 2.2, 'dark')
    # the fist nose with its nostrils
    s += sphere(0, FRONT + 0.8, H - 21, 4.4, 'wood', squash=(1.1, 0.9, 1.0))
    s += box(-1.9, FRONT + 3.2, H - 24, 1.8, 1.4, 1.4, 'dark')
    s += box(1.9, FRONT + 3.2, H - 24, 1.8, 1.4, 1.4, 'dark')
    # the open mouth: dark, a row of teeth, two corner tusks
    s += box(0, FRONT - 0.1, H - 30, 15, 2.0, 6.4, 'dark')
    s += box(0, FRONT + 0.6, H - 27.6, 13, 1.4, 1.8, 'white')
    s += box(-6.3, FRONT + 0.7, H - 30.6, 2.2, 1.4, 5.4, 'white')
    s += box(6.3, FRONT + 0.7, H - 30.6, 2.2, 1.4, 5.4, 'white')
    # the carved beard
    for x in (-4.2, -1.4, 1.4, 4.2):
        s += box(x, FRONT - 0.3, H - 37, 1.4, 1.6, 4.6, 'carve')
    s += name_marks()
    if red:
        s += cloth()
    return s


def jiha(red=False):
    s = cylinder(R, 0, H, 'wood')
    # hair: a round crown over the top and back of the head, the topknot on top
    s += sphere(0, -2.5, H - 3, 12.4, 'hat', squash=(1.0, 0.92, 0.72))
    s += sphere(0, -1.5, H + 5.5, 4.0, 'hat')
    # gentle arched brows, round eyes, red cheeks
    for x in (-5.0, 5.0):
        s += box(x, FRONT, H - 10, 6.0, 2.4, 1.6, 'dark')
        s += sphere(x, FRONT - 0.8, H - 15, 4.0, 'white')
        s += sphere(x, FRONT + 2.6, H - 15.4, 2.0, 'dark')
        s += sphere(x * 1.5, FRONT - 1.4, H - 21, 2.6, 'red', squash=(1, 0.5, 1))
    s += sphere(0, FRONT + 0.4, H - 21.5, 3.2, 'wood')
    s += box(0, FRONT - 0.1, H - 28, 10, 2.0, 3.6, 'dark')
    s += box(0, FRONT + 0.5, H - 29.4, 8.6, 1.4, 1.6, 'red')
    s += box(-3.2, FRONT + 0.6, H - 27.2, 1.6, 1.4, 2.2, 'white')
    s += box(3.2, FRONT + 0.6, H - 27.2, 1.6, 1.4, 2.2, 'white')
    s += name_marks()
    if red:
        s += cloth()
    return s


def cloth(z=12.0):
    """The red route's cloth tied round the post below the face (as the 2D
    frames wear it), its knot on the right with a short tail hanging down."""
    s = cylinder(R + 0.9, z, z + 4.5, 'red', caps=False)
    s += box(R + 1.5, 2, z + 2, 3, 3, 3.4, 'red')
    s += box(R + 2.5, 4, z - 1, 2, 2, 4, 'red')
    return s


# ---------------------------------------------------------------- placing


def place_solids(solids, foot, facing, lean):
    """Local triangles to world: stand at `foot` (x, y on the floor), facing
    `facing` (unit x, y into the room), leaning back by `lean` degrees."""
    f = np.array([facing[0], facing[1], 0.0])
    r = np.array([facing[1], -facing[0], 0.0])  # the viewer's right, looking at its front
    up = np.array([0.0, 0.0, 1.0])
    c, s = math.cos(math.radians(lean)), math.sin(math.radians(lean))
    base = np.array([foot[0], foot[1], 0.0])
    out = []
    for tri, mat in solids:
        pts = []
        for x, y, z in tri:
            yy, zz = y * c - z * s, y * s + z * c  # the top tips back toward the wall
            pts.append(base + r * x + f * yy + up * zz)
        out.append((np.array(pts), mat))
    return out


def scene(lean, spread=46):
    tris = []
    for (wx, wy), (ix, iy), _ in placement.DOORS.values():
        # the post stands right against the wall's face, leaning back just enough to rest its head on it
        reach = R + H * math.sin(math.radians(lean)) + 0.5
        fx, fy = wx + ix * (WALL_FACE + reach), wy + iy * (WALL_FACE + reach)
        sx, sy = -iy, ix
        a = (fx + sx * spread, fy + sy * spread)
        b = (fx - sx * spread, fy - sy * spread)
        first = a[0] < b[0] if iy != 0 else a[1] < b[1]
        left, right = (a, b) if first else (b, a)
        tris += place_solids(cheonha(), left, (ix, iy), lean)
        tris += place_solids(jiha(), right, (ix, iy), lean)
    return tris


# ---------------------------------------------------------------- render


def render(tris, cam_h, size, scale, turn=0.0, pivot=(0.0, 0.0), shift=(0.0, 0.0)):
    """Colour and material buffers of `size` (w, h) at `scale` times the
    backdrop's pixels. `turn` turns the picture clockwise by that many degrees
    about the backdrop pixel `pivot`, which then moves by `shift`, so a turned
    sprite is drawn on the pixel grid rather than resampled."""
    w, h = size
    f = SCALE * cam_h
    cam = np.array([CENTER[0], CENTER[1], cam_h])
    zbuf = np.full((h, w), np.inf)
    color = np.zeros((h, w, 3), dtype=np.uint8)
    matbuf = np.zeros((h, w), dtype=np.int16)
    for pts, mat in tris:
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        norm = np.linalg.norm(n)
        if norm == 0:
            continue
        n = n / norm
        centroid = pts.mean(axis=0)
        if np.dot(n, cam - centroid) <= 0:
            continue
        d = cam_h - pts[:, 2]
        sx = (IMG_CENTER[0] + f * (pts[:, 0] - CENTER[0]) / d) * scale
        sy = (IMG_CENTER[1] + f * (pts[:, 1] - CENTER[1]) / d) * scale
        if turn or shift != (0.0, 0.0):
            c, sn = math.cos(math.radians(turn)), math.sin(math.radians(turn))
            px, py = pivot[0] * scale, pivot[1] * scale
            sx, sy = (px + (sx - px) * c - (sy - py) * sn + shift[0] * scale,
                      py + (sx - px) * sn + (sy - py) * c + shift[1] * scale)
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(w - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(h - 1, math.ceil(sy.max())))
        if x0 > x1 or y0 > y1:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, bx, cx), (ay, by, cy) = sx, sy
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-9:
            continue
        w0 = ((bx - gx) * (cy - gy) - (cx - gx) * (by - gy)) / area
        w1 = ((cx - gx) * (ay - gy) - (ax - gx) * (cy - gy)) / area
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        depth = w0 * d[0] + w1 * d[1] + w2 * d[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        hit = inside & (depth < sub)
        if not hit.any():
            continue
        # a light mostly from the eye (so what faces the camera reads, as a
        # sprite would) with a top-left bias that splits lit and shaded sides
        eye = cam - centroid
        eye = eye / np.linalg.norm(eye)
        lamp = 0.65 * eye + 0.35 * LIGHT
        light = float(np.dot(n, lamp / np.linalg.norm(lamp)))
        tone = 0 if light < 0.45 else 1 if light < 0.8 else 2
        sub[hit] = depth[hit]
        color[y0:y1 + 1, x0:x1 + 1][hit] = MATERIALS[mat][tone]
        matbuf[y0:y1 + 1, x0:x1 + 1][hit] = MAT_IDS[mat]
    return color, matbuf


def outline(color, matbuf):
    """A 1 px near-black outline round every statue, the Isaac way."""
    mask = matbuf > 0
    edge = np.zeros_like(mask)
    edge[1:, :] |= mask[1:, :] & ~mask[:-1, :]
    edge[:-1, :] |= mask[:-1, :] & ~mask[1:, :]
    edge[:, 1:] |= mask[:, 1:] & ~mask[:, :-1]
    edge[:, :-1] |= mask[:, :-1] & ~mask[:, 1:]
    # ring the whites (eyes, teeth) with dark wherever wood touches them
    white = matbuf == MAT_IDS['white']
    ring = np.zeros_like(mask)
    ring[1:, :] |= white[:-1, :]
    ring[:-1, :] |= white[1:, :]
    ring[:, 1:] |= white[:, :-1]
    ring[:, :-1] |= white[:, 1:]
    ring &= (matbuf == MAT_IDS['wood'])
    out = color.copy()
    out[edge | ring] = (30, 22, 20)
    return out, mask


def room_base():
    room = placement.backdrop()
    door = placement.door_sprite()
    earth = Image.open(ROOT / 'resources/gfx/effects/conch_jangseung_ground.png').convert('RGBA')
    for (wx, wy), (ix, iy), turn in placement.DOORS.values():
        placement.place(room, earth, wx, wy, (52, 0), math.degrees(math.atan2(iy, ix)) - 90)
        placement.place(room, door, wx, wy, (32, 42), turn)
    return room


def composite(room, color, mask):
    img = room.copy()
    over = Image.fromarray(np.dstack([color, (mask * 255).astype(np.uint8)]), 'RGBA')
    img.alpha_composite(over)
    return img


SIDE_TURN = 65  # degrees a side wall's statue is turned from upright toward its wall (user: not all the way)


def foot_pixel(cam_h, foot):
    f = SCALE * cam_h
    return (IMG_CENTER[0] + f * (foot[0] - CENTER[0]) / cam_h, IMG_CENTER[1] + f * (foot[1] - CENTER[1]) / cam_h)


WALLS = {1: 'Top', 3: 'Bottom', 0: 'Left', 2: 'Right'}


def pair_feet(slot, lean, spread=46):
    """The feet of the pair beside door `slot`, 천하대장군 first (left, or above)."""
    (wx, wy), (ix, iy), _ = placement.DOORS[slot]
    reach = R + H * math.sin(math.radians(lean)) + 0.5
    fx, fy = wx + ix * (WALL_FACE + reach), wy + iy * (WALL_FACE + reach)
    sx, sy = -iy, ix
    a = (fx + sx * spread, fy + sy * spread)
    b = (fx - sx * spread, fy - sy * spread)
    first = a[0] < b[0] if iy != 0 else a[1] < b[1]
    return ((a, b) if first else (b, a)), (ix, iy)


def statue_sprite(build, red, foot, facing, cam_h, lean):
    """One statue rendered where it stands, in the room's one camera, at the
    game's pixels with its outline, cut out: (image, foot pixel)."""
    tris = place_solids(build(red), foot, facing, lean)
    color, mats = render(tris, cam_h, (468, 312), 1)
    color, mask = outline(color, mats)
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    img = Image.fromarray(np.dstack([color, (mask * 255).astype(np.uint8)]), 'RGBA').crop((x0, y0, x1, y1))
    fx, fy = foot_pixel(cam_h, foot)
    return img, (int(round(fx - x0)), int(round(fy - y0)))


def sprite_set(cam_h, lean):
    """Every frame the game uses: each wall's pair as the one camera sees it
    against that wall (no turning), plain and red-clothed."""
    frames = {}
    for slot, wall in WALLS.items():
        (first, second), facing = pair_feet(slot, lean)
        for red in (False, True):
            for name, build, foot in (('Cheonha', cheonha, first), ('Jiha', jiha, second)):
                frames[name + wall + ('Red' if red else '')] = statue_sprite(build, red, foot, facing, cam_h, lean)
    return frames


def framed_room(frames, lean):
    """The room with every wall's frames drawn at their feet, as the game would."""
    room = room_base()
    drawn = []
    for slot, wall in WALLS.items():
        (first, second), _ = pair_feet(slot, lean)
        for name, foot in (('Cheonha', first), ('Jiha', second)):
            drawn.append((foot, frames[name + wall]))
    for (x, y), (img, pivot) in sorted(drawn, key=lambda d: d[0][1]):
        placement.place(room, img, x, y, pivot)
    return room


# ---------------------------------------------------------------- April Fools
# The user liked the raw 3D look as well and asked to keep it for April Fools
# (2026-11-10): the same frames the game uses (each statue against the top
# wall and the right wall, plain and red-clothed, mirrored by the game for the
# other walls), rendered straight from this model. They are drawn four times
# finer and brought down to the game's pixels by majority, so a feature keeps
# its shape instead of breaking up where a single sample point falls. Nothing
# loads them: they wait in resources/gfx/effects/notused, left out of the
# Workshop package, under the same animation names as the shipped sheet.

APRIL = ROOT / 'resources/gfx/effects/notused'
APRIL_NAME = 'conch_jangseung_aprilfools'
FEATURES = ('dark', 'white', 'red', 'carve')


def fine_sprite(build, red, foot, facing, cam_h, lean, ss=4):
    """One statue rendered `ss` times finer and reduced to the game's pixels:
    a pixel is drawn when the statue covers 40% of it; a feature (eyes, mouth,
    brows, cloth, carving) taking 30% of it wins over the wood or the cap
    round it. Returns (image, foot pixel) like statue_sprite."""
    tris = place_solids(build(red), foot, facing, lean)
    color, mats = render(tris, cam_h, (468 * ss, 312 * ss), ss)
    ys, xs = np.nonzero(mats)
    x0, x1 = xs.min() // ss - 1, xs.max() // ss + 2
    y0, y1 = ys.min() // ss - 1, ys.max() // ss + 2
    w, h = x1 - x0, y1 - y0
    small = np.zeros((h, w, 3), dtype=np.uint8)
    small_mat = np.zeros((h, w), dtype=np.int16)
    n = ss * ss
    for y in range(h):
        for x in range(w):
            bm = mats[(y0 + y) * ss:(y0 + y + 1) * ss, (x0 + x) * ss:(x0 + x + 1) * ss].ravel()
            bc = color[(y0 + y) * ss:(y0 + y + 1) * ss, (x0 + x) * ss:(x0 + x + 1) * ss].reshape(-1, 3)
            if bm.size < n or np.count_nonzero(bm) < 0.4 * n:
                continue
            counts = {mid: int(np.count_nonzero(bm == mid)) for mid in set(bm.tolist()) if mid}
            feature = [mid for mid in counts if mid in (MAT_IDS[f] for f in FEATURES) and counts[mid] >= 0.3 * n]
            pick = max(feature or counts, key=lambda mid: counts[mid])
            tones = [tuple(c) for c, mid in zip(bc, bm) if mid == pick]
            small[y, x] = max(set(tones), key=tones.count)
            small_mat[y, x] = pick
    small, mask = outline(small, small_mat)
    img = Image.fromarray(np.dstack([small, (mask * 255).astype(np.uint8)]), 'RGBA')
    fx, fy = foot_pixel(cam_h, foot)
    return img, (int(round(fx - x0)), int(round(fy - y0)))


def april_fools(cam_h=300.0, lean=3.0):
    """Writes the April Fools sheet and ANM2 (same names and contract as the
    shipped conch_jangseung.anm2) and a room preview."""
    walls = {'Top': 1, 'Side': 2}  # frameOf: the top wall's view and the right wall's
    frames = []
    for name in author.NAMES:
        who = 'Cheonha' if name.startswith('Cheonha') else 'Jiha'
        view = 'Side' if 'Side' in name else 'Top'
        (first, second), facing = pair_feet(walls[view], lean)
        build, foot = (cheonha, first) if who == 'Cheonha' else (jiha, second)
        frames.append(fine_sprite(build, name.endswith('Red'), foot, facing, cam_h, lean))
    sheet = Image.new('RGBA', (sum(f.width for f, _ in frames), max(f.height for f, _ in frames)))
    x = 0
    for frame, _ in frames:
        sheet.paste(frame, (x, 0))
        x += frame.width
    APRIL.mkdir(parents=True, exist_ok=True)
    sheet.save(APRIL / f'{APRIL_NAME}.png')
    (APRIL / f'{APRIL_NAME}.anm2').write_text(author.statue_anm2(frames, f'{APRIL_NAME}.png'), encoding='utf-8')
    OUT.mkdir(parents=True, exist_ok=True)
    big = Image.new('RGBA', (sheet.width + 4, sheet.height + 4), (116, 70, 56, 255))
    big.alpha_composite(sheet, (2, 2))
    big.resize((big.width * 6, big.height * 6), Image.NEAREST).save(OUT / 'aprilfools_sheet.png')
    placement.main(out_name='placement_aprilfools.png', anm2_path=APRIL / f'{APRIL_NAME}.anm2')
    return APRIL / f'{APRIL_NAME}.png'


def main():
    if sys.argv[1:2] == ['april']:
        print(april_fools())
        return
    cam_h = float(sys.argv[1]) if len(sys.argv) > 1 else 300.0
    lean = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    OUT.mkdir(parents=True, exist_ok=True)
    room = room_base()
    big_room = room.resize((room.width * 4, room.height * 4), Image.NEAREST)
    color, mats = render(scene(lean), cam_h, big_room.size, 4)
    composite(big_room, color, mats > 0).save(OUT / 'model3d_fine.png')
    frames = sprite_set(cam_h, lean)
    framed = framed_room(frames, lean)
    framed.resize((framed.width * 3, framed.height * 3), Image.NEAREST).save(OUT / 'model3d_pixels.png')
    names = [n for n in frames if not n.endswith('Red')]
    sheet = Image.new('RGBA', (sum(frames[n][0].width + 4 for n in names), max(frames[n][0].height for n in names)))
    x = 0
    for n in names:
        sheet.paste(frames[n][0], (x, 0))
        x += frames[n][0].width + 4
    sheet.resize((sheet.width * 6, sheet.height * 6), Image.NEAREST).save(OUT / 'model3d_sprites.png')
    print(OUT / 'model3d_pixels.png', export_maps(cam_h, lean))


CHARS = {
    (92, 60, 40): 'W', (138, 96, 60): 'M', (178, 132, 84): 'L',
    (30, 22, 20): 'K', (52, 40, 34): 'K',
    (30, 28, 34): 'H', (40, 36, 44): 'H', (86, 80, 96): 'h',
    (190, 182, 164): 'E', (238, 230, 208): 'E', (250, 246, 232): 'E',
    (122, 30, 28): 'r', (178, 46, 38): 'R', (214, 96, 72): 'o',
    (60, 38, 26): 'T', (70, 44, 30): 'T', (84, 54, 36): 'T',
}


def to_map(img):
    rows = []
    for y in range(img.height):
        row = ''
        for x in range(img.width):
            r, g, b, a = img.getpixel((x, y))
            row += '.' if a == 0 else CHARS[(r, g, b)]
        rows.append(row)
    return rows


def export_maps(cam_h=300.0, lean=3.0, path=OUT / 'frames_3d.txt'):
    """Writes every frame as a palette map with its foot pixel: the reference
    the hand-finished maps in author.py start from."""
    frames = sprite_set(cam_h, lean)
    with open(path, 'w', encoding='utf-8') as out:
        for name, (img, foot) in frames.items():
            out.write(f'{name} {img.size} foot {foot}' + chr(10))
            for row in to_map(img):
                out.write(f'    "{row}",' + chr(10))
    return path


if __name__ == '__main__':
    main()
