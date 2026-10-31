"""Builds 축's furrow, ditch and rice.

The furrow is the line the plough's share cuts (user request 2026-10-31:
not tiles, a line drawn behind the plough). It is stamped into the room's
floor, an effect with FLAG_RENDER_FLOOR being drawn into the floor and then
removed by the engine (measured 2026-10-31), a quarter of a grid cell at a
time as the share passes, so no spot is stamped twice and nothing darkens.
The ox walks along rows and columns and turns in a quarter circle of half a
cell, so the line is made of straight halves (from a cell's edge to its
middle) and quarter-circle arcs (from one edge round the corner to the next),
each cut into quarters along the line: 8 straight quarters and 16 arc
quarters. A piece is one 26x26 floor tile (the vanilla tile size) holding its
stretch of an 8-pixel trench with a lip of turned soil on each bank, half
transparent so it darkens whatever floor it lies on. Light comes from the top
left; on a curve the walls' light turns with the line, so the shading has no
seam. Each colour has two variants with their own ragged edge and specks.

Pieces are numbered as ox.lua numbers them: sides N, E, S, W are 0-3; a
straight quarter is side * 2 + (0 at the edge, 1 at the middle); an arc
quarter is 8 + corner * 4 + k, corners N-E, E-S, S-W, W-N being 0-3 and k
counted from the first side to the second.

Nothing is drawn on the holder (user request 2026-10-31): the rice where
the two lines meet is the only thing that grows, on the floor.

Run from the repository root; it writes the PNGs, their ANM2 files and a
preview under .tmp/ox_furrow:

    python docs/previews/ox-revision/furrow.py
"""
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'resources/gfx/effects'
PREVIEW = ROOT / '.tmp/ox_furrow'

T = 26                 # one grid cell in sprite pixels (vanilla pit frames are 26x26)
HALF = T / 2           # the middle, and the radius of a turn
HW = 4.0               # half the trench's width: 8 pixels across
LIP = 2.0              # the turned soil on each bank
N, E, S, W = 1, 2, 4, 8
SIDES = (N, E, S, W)
EDGE = {N: (HALF, 0.0), E: (T, HALF), S: (HALF, T), W: (0.0, HALF)}
CORNERS = ((N, E), (E, S), (S, W), (W, N))
PIECES = 24
COLORS = ('yellow', 'black')
VARIANTS = 2

# The two lines must never be mistaken for each other on any floor (user
# requests 2026-10-31): 누렁소 ploughs a furrow of golden ochre soil with
# straw-coloured lips; 검은소 cuts a ditch filled with water between dark wet
# banks, its surface catching the light, which also keeps it visible on the
# darkest floors (Sheol, Gehenna, the Dark Room).
PALETTE = {
    'yellow': {
        'shadow': (92, 60, 12, 140), 'shadow2': (122, 84, 22, 115), 'bed': (156, 112, 36, 85),
        'lit': (238, 198, 92, 95), 'lip': (190, 146, 56, 60), 'liphi': (244, 210, 112, 85),
        'specks': [(250, 222, 120, 225), (255, 244, 180, 235)],
    },
    'black': {
        'shadow': (12, 16, 24, 190), 'shadow2': (30, 56, 86, 165), 'bed': (52, 98, 146, 145),
        'lit': (156, 204, 240, 160), 'lip': (26, 24, 22, 95), 'liphi': (62, 60, 56, 95),
        'specks': [(206, 234, 255, 230), (255, 255, 255, 235)],
    },
}


def chance(*keys):
    """A fixed pseudo-random number in [0, 1) for these keys."""
    h = 2166136261
    for k in keys:
        for byte in str(k).encode():
            h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return h / 2 ** 32



def curve(pid):
    """The centreline a piece lies on and its stretch of it: (kind, data, u0, u1, length)."""
    if pid < 8:
        side, part = SIDES[pid // 2], pid % 2
        return 'line', side, part * HALF / 2, (part + 1) * HALF / 2, HALF
    corner, k = CORNERS[(pid - 8) // 4], (pid - 8) % 4
    length = math.pi / 2 * HALF
    return 'arc', corner, k * length / 4, (k + 1) * length / 4, length


def coords(kind, data, x, y):
    """(u, s, normal) of a point: how far along the centreline, how far across
    it, and the unit normal that +s points along."""
    if kind == 'line':
        ex, ey = EDGE[data]
        tx, ty = (HALF - ex) / HALF, (HALF - ey) / HALF
        nx, ny = -ty, tx
        rx, ry = x - ex, y - ey
        return rx * tx + ry * ty, rx * nx + ry * ny, (nx, ny)
    a, b = data
    (ax, ay), (bx, by) = EDGE[a], EDGE[b]
    cx, cy = ax + bx - HALF, ay + by - HALF          # the corner the line turns round
    vx, vy = x - cx, y - cy
    r = math.hypot(vx, vy) or 1e-9
    phi = math.atan2(vx * (bx - cx) + vy * (by - cy), vx * (ax - cx) + vy * (ay - cy))
    return phi * HALF, r - HALF, (vx / r, vy / r)


def wobble(kind, data, variant, bank, u, length):
    """A ragged bank, -1, 0 or +1 pixel, straight near a stretch's ends so pieces meet."""
    if u < 3 or u > length - 3:
        return 0
    v = chance('wobble', kind, data, variant, bank, int(u // 3))
    return -1 if v < 0.18 else 1 if v > 0.86 else 0


def piece(color, pid, variant):
    pal = PALETTE[color]
    kind, data, u0, u1, length = curve(pid)
    img = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    bed = []
    for y in range(T):
        for x in range(T):
            u, s, (nx, ny) = coords(kind, data, x + 0.5, y + 0.5)
            if not (u0 <= u < u1):
                continue
            bank = 1 if s > 0 else -1
            hw = HW + wobble(kind, data, variant, bank, u, length)
            d = abs(s)
            if d > hw + LIP:
                continue
            # How much this bank's wall turns away from the light (top left):
            # the wall faces the trench, against its bank's normal.
            away = bank * (nx * -1 + ny * -1) / math.sqrt(2)
            if d <= hw:
                depth = hw - d
                if away > 0.35:
                    tone = 'shadow' if depth < 1 else 'shadow2' if depth < 2 else 'bed'
                elif away > 0.1:
                    tone = 'shadow2' if depth < 1 else 'bed'
                elif away < -0.35:
                    tone = 'lit' if depth < 1 else 'bed'
                else:
                    tone = 'bed'
                if tone == 'bed':
                    bed.append((x, y))
            else:
                inner = d <= hw + 1
                if away > 0.35:
                    tone = 'lip' if inner else 'liphi'
                elif away < -0.35:
                    tone = 'liphi' if inner else 'lip'
                else:
                    tone = 'lip'
            img.putpixel((x, y), pal[tone])
    # A speck on the bed of every other piece, so the line is not dotted evenly.
    if bed and chance('speck?', color, pid, variant) < 0.6:
        x, y = bed[int(chance('speck', color, pid, variant) * len(bed))]
        tone = pal['specks'][0 if chance('glint', color, pid, variant) < 0.7 else 1]
        img.putpixel((x, y), tone)
        if color == 'yellow' and (x + 1, y) in bed:
            img.putpixel((x + 1, y), tone)   # a short bit of straw
    return img


def furrow_sheet():
    sheet = Image.new('RGBA', (T * PIECES, T * len(COLORS) * VARIANTS), (0, 0, 0, 0))
    for c, color in enumerate(COLORS):
        for v in range(VARIANTS):
            for pid in range(PIECES):
                sheet.paste(piece(color, pid, v), (pid * T, (c * VARIANTS + v) * T))
    return sheet


def quarter_piece(a, b, q):
    """The piece for quarter q (0-3) of a cell the line enters by side a and
    leaves by side b (None at a stretch's end in the middle), as ox.lua has it."""
    index = {N: 0, E: 1, S: 2, W: 3}
    opposite = {N: S, S: N, E: W, W: E}
    if a and b and opposite[a] == b:
        return index[a] * 2 + q if q < 2 else index[b] * 2 + (3 - q)
    if a and b:
        if (a, b) in CORNERS:
            return 8 + CORNERS.index((a, b)) * 4 + q
        return 8 + CORNERS.index((b, a)) * 4 + (3 - q)
    if a and q < 2:
        return index[a] * 2 + q
    if b and q >= 2:
        return index[b] * 2 + (3 - q)
    return None


# ------------------------------------------------------------------ rice
# Rice grows where the two lines meet (user request 2026-10-31): a small
# clump, smaller than Isaac so it never hides him, rising in five stages
# from a muddy, watery foot and swaying once grown, its ears turning gold.
RW, RH = 18, 20
RICE = {
    'dark': (44, 98, 42, 255), 'light': (92, 162, 70, 255), 'leaf': (126, 190, 86, 255),
    'green': (150, 196, 92, 255), 'gold': (226, 186, 82, 255), 'goldhi': (252, 226, 136, 255),
    'golddark': (160, 118, 40, 255), 'mud': (64, 46, 30, 200), 'water': (150, 202, 236, 210),
    'ripe': (168, 186, 84, 255),
}
# Stalks: foot x, full height, lean (-1 left, +1 right), whether it bears an ear.
STALKS = [(5, 9, -1, False), (7, 13, -1, True), (9, 15, 0, True), (11, 13, 1, True), (13, 9, 1, False)]
GROWN = (0.25, 0.45, 0.7, 0.88, 1.0)


def rice(stage, sway):
    img = Image.new('RGBA', (RW, RH), (0, 0, 0, 0))
    base = RH - 2
    for x in range(4, 15):
        img.putpixel((x, RH - 1), RICE['mud'])
    for x in (6, 12):
        img.putpixel((x, RH - 1), RICE['water'])
    for i, (x0, height, lean, ear) in enumerate(STALKS):
        h = max(2, round(height * GROWN[stage]))
        top = None
        for k in range(h):
            y = base - k
            dx = lean if k > h // 2 else 0
            if k >= h - 2 and sway:
                dx += sway if i % 2 == 0 else -sway // 2 if sway < 0 else 0
            x = x0 + dx
            ripe = stage >= 4 and k >= h * 2 // 3
            img.putpixel((x, y), RICE['dark'] if k < h // 3 else RICE['ripe'] if ripe else RICE['light'])
            top = (x, y)
        if stage >= 1 and h >= 5:
            # A leaf blade springing out of the stalk.
            lx, ly = x0 - lean, base - h // 2
            if 0 <= lx < RW:
                img.putpixel((lx, ly), RICE['leaf'])
                if 0 <= lx - lean < RW:
                    img.putpixel((lx - lean, ly - 1), RICE['leaf'])
        if ear and stage >= 3 and top:
            # The ear nods over the tip and hangs down, heavy with grain.
            d = lean or 1
            gold = stage >= 4
            grains = ((0, -1), (d, -1), (d, 0), (2 * d, 1), (2 * d, 2), (2 * d, 3)) if gold else ((d, 0), (d, 1), (2 * d, 2))
            for k, (gx, gy) in enumerate(grains):
                ex, ey = top[0] + gx, top[1] + gy
                if 0 <= ex < RW and 0 <= ey < RH:
                    tone = ('goldhi' if k < 2 else 'gold' if k % 2 == 0 else 'golddark') if gold else 'green'
                    img.putpixel((ex, ey), RICE[tone])
    return img


GROW_FRAMES = len(GROWN)
IDLE_SWAY = (0, 1, 0, -1)


def rice_sheet():
    frames = [rice(stage, 0) for stage in range(GROW_FRAMES)] + [rice(GROW_FRAMES - 1, sway) for sway in IDLE_SWAY]
    sheet = Image.new('RGBA', (RW * len(frames), RH), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i * RW, 0))
    return sheet


# ------------------------------------------------------------------ anm2
FRAME = ('<Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" '
         'RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" '
         'BlueOffset="0" Rotation="0" Interpolated="false" XCrop="{x}" YCrop="{y}" Width="{w}" Height="{h}" '
         'XPivot="{px}" YPivot="{py}" />')


def anm2(sheet, layer, animation, frames, w, h, px, py):
    rows = '\n'.join('          ' + FRAME.format(x=x, y=y, w=w, h=h, px=px, py=py) for x, y in frames)
    return f'''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="{sheet}" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="{layer}" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="{animation}">
    <Animation Name="{animation}" FrameNum="{len(frames)}" Loop="false">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="{len(frames)}" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
{rows}
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>
  </Animations>
</AnimatedActor>
'''


def anm2_animations(sheet, layer, animations, w, h, px, py):
    """An ANM2 with several animations: (name, loop, [(x, y, delay), ...])."""
    blocks = []
    for name, loop, frames in animations:
        total = sum(delay for _, _, delay in frames)
        rows = '\n'.join('          ' + FRAME.format(x=x, y=y, w=w, h=h, px=px, py=py).replace('Delay="1"', f'Delay="{delay}"')
                         for x, y, delay in frames)
        blocks.append(f'''    <Animation Name="{name}" FrameNum="{total}" Loop="{'true' if loop else 'false'}">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="{total}" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
{rows}
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>''')
    body = '\n'.join(blocks)
    return f'''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="{sheet}" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="{layer}" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="{animations[0][0]}">
{body}
  </Animations>
</AnimatedActor>
'''


# ------------------------------------------------------------------ preview
FLOORS = {'basement': (118, 92, 66), 'caves': (96, 90, 84), 'depths': (58, 56, 60), 'womb': (120, 48, 44)}
# A sample walk: in at the left door, round two corners, out at the bottom;
# a second ox crosses it and stops in a dead end.
WALK_A = [(0, 2), (1, 2), (2, 2), (3, 2), (3, 3), (3, 4), (4, 4), (5, 4), (6, 4), (6, 5), (6, 6)]
WALK_B = [(5, 0), (5, 1), (5, 2), (5, 3), (5, 4), (5, 5), (4, 5), (3, 5)]


def stroke(walk, door_start, door_end):
    """Every (cell, piece) of a stroke along `walk`, as the plough lays it."""
    side = {(0, -1): N, (1, 0): E, (0, 1): S, (-1, 0): W}
    out = []
    for i, (x, y) in enumerate(walk):
        a = side[(walk[i - 1][0] - x, walk[i - 1][1] - y)] if i > 0 else door_start or None
        b = side[(walk[i + 1][0] - x, walk[i + 1][1] - y)] if i < len(walk) - 1 else door_end or None
        for q in range(4):
            pid = quarter_piece(a, b, q)
            if pid is not None:
                out.append(((x, y), pid))
    return out


def preview(sheet, rice_art=None):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    cols, rows = 7, 7
    tiles = []
    for name, floor in FLOORS.items():
        room = Image.new('RGBA', (cols * T, rows * T), floor + (255,))
        for x in range(0, cols * T, 4):          # a faint floor texture
            for y in range(0, rows * T, 4):
                if chance('floor', name, x, y) < 0.25:
                    room.putpixel((x, y), tuple(max(0, v - 14) for v in floor) + (255,))
        for color, walk, a, b in (('yellow', WALK_A, W, S), ('black', WALK_B, N, 0)):
            c = COLORS.index(color)
            for (x, y), pid in stroke(walk, a, b):
                v = (y * cols + x) % VARIANTS
                crop = sheet.crop((pid * T, (c * VARIANTS + v) * T, pid * T + T, (c * VARIANTS + v) * T + T))
                room.alpha_composite(crop, (x * T, y * T))
        tiles.append(room)
    out = Image.new('RGBA', (len(tiles) * (cols * T + 6), rows * T), (0, 0, 0, 0))
    for i, room in enumerate(tiles):
        out.paste(room, (i * (cols * T + 6), 0))
    out.save(PREVIEW / 'furrow_rooms_x1.png')
    out.resize((out.width * 3, out.height * 3), Image.NEAREST).save(PREVIEW / 'furrow_rooms_x3.png')
    back = Image.new('RGBA', sheet.size, FLOORS['basement'] + (255,))
    back.alpha_composite(sheet)
    back.resize((back.width * 3, back.height * 3), Image.NEAREST).save(PREVIEW / 'furrow_sheet_x3.png')
    if rice_art is not None:
        rback = Image.new('RGBA', rice_art.size, FLOORS['basement'] + (255,))
        rback.alpha_composite(rice_art)
        rback.resize((rback.width * 6, rback.height * 6), Image.NEAREST).save(PREVIEW / 'rice_x6.png')


def main():
    sheet = furrow_sheet()
    sheet.save(OUT / 'conch_ox_furrow.png')
    frames = [(k * T, row * T) for row in range(len(COLORS) * VARIANTS) for k in range(PIECES)]
    (OUT / 'conch_ox_furrow.anm2').write_text(
        anm2('conch_ox_furrow.png', 'soil', 'Furrow', frames, T, T, T // 2, T // 2), encoding='utf-8')
    rice_art = rice_sheet()
    rice_art.save(OUT / 'conch_ox_rice.png')
    grow = [(i * RW, 0, 4) for i in range(GROW_FRAMES)]
    idle = [((GROW_FRAMES + i) * RW, 0, 10) for i in range(len(IDLE_SWAY))]
    (OUT / 'conch_ox_rice.anm2').write_text(
        anm2_animations('conch_ox_rice.png', 'rice', [('Grow', False, grow), ('Idle', True, idle)], RW, RH, RW // 2, RH - 1),
        encoding='utf-8')
    preview(sheet, rice_art)
    print('furrow', sheet.size, 'rice', rice_art.size, '->', PREVIEW.relative_to(ROOT))


if __name__ == '__main__':
    main()
