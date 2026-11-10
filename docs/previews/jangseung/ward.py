"""Builds the mark that shows a player is inside a 장승 village.

While a player stands inside the half circle in front of a 장승 pair, nothing
hurts them (user request 2026-11-10). The user asked for a sign of that which is
not overdone and feels Korean, and turned down a talisman (부적) over the head.
The drafts here:

  A  금줄: the twisted straw rope a village hung at its mouth beside the 장승
     to keep evil out, laid round the player's feet with red peppers, charcoal
     and white paper strips tied on.
  B  오방색: a thin ring round the feet in the five cardinal colours.
  C  솟대: the wooden bird that stands on a pole beside the 장승, hovering over
     the player's head.

Authored on the native grid: the ring is the feet's ellipse band, its twist and
ties placed by hand. Run from the repository root; it writes the chosen draft's
runtime PNG and ANM2 and a preview of every draft over Isaac on a basement
floor (both read in place from the extracted vanilla files) under
.tmp/jangseung:

    python docs/previews/jangseung/ward.py
"""
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
EFFECTS = ROOT / 'resources/gfx/effects'
PREVIEW = ROOT / '.tmp/jangseung'
VANILLA = ROOT.parents[1] / 'extracted_resources/resources/gfx'
CHOSEN = 'A'

# the ring round the feet: outer and inner half axes in pixels
RING_W, RING_H = 31, 15
CX, CY = 15, 6  # the feet (the anm2 pivot) inside the frame
OUTER = (14.6, 5.4)
INNER = (11.4, 3.0)

STRAW = {
    'K': (58, 40, 22),
    'd': (122, 88, 42),
    'm': (176, 136, 70),
    'l': (220, 186, 112),
}
TIES = {
    'R': (192, 36, 28),   # red pepper
    'r': (132, 24, 22),   # pepper in shadow
    'g': (70, 118, 44),   # pepper stalk, pine
    'C': (34, 30, 32),    # charcoal
    'c': (70, 64, 66),    # charcoal, lit
    'W': (238, 234, 222), # paper strip
    'w': (192, 186, 170), # paper in shadow
}
OBANG = [(46, 92, 170), (194, 42, 36), (228, 184, 54), (238, 236, 226), (44, 40, 46)]


def band():
    """The pixels of the ring's band, each with its angle round the ellipse and
    how far across the band it lies (0 inner edge, 1 outer)."""
    cells = {}
    for y in range(RING_H):
        for x in range(RING_W):
            dx, dy = x + 0.5 - (CX + 0.5), y + 0.5 - (CY + 0.5)
            outer = (dx / OUTER[0]) ** 2 + (dy / OUTER[1]) ** 2
            inner = (dx / INNER[0]) ** 2 + (dy / INNER[1]) ** 2
            if outer <= 1 and inner > 1:
                angle = math.atan2(dy / OUTER[1], dx / OUTER[0])
                ro, ri = math.sqrt(outer), math.sqrt(inner)
                across = (ri - 1) / max(1e-6, (ri - 1) + (1 - ro))
                cells[(x, y)] = (angle, across)
    return cells


def put(img, x, y, colour, alpha=255):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), colour + (alpha,))


def ring_geumjul():
    img = Image.new('RGBA', (RING_W, RING_H))
    cells = band()
    for (x, y), (angle, across) in cells.items():
        # a left-laid twist: the strands cross the rope on a slant, light,
        # middle and dark in turn, and the upper left arc catches the light
        strand = (x + 2 * y) % 3
        lit = math.cos(angle + math.pi * 0.75) > 0.2
        tone = ('l', 'm', 'd')[strand] if lit else ('m', 'd', 'd')[strand]
        if across > 0.8 and angle > 0:
            tone = 'K'  # the near edge's contour, where the rope meets the floor
        put(img, x, y, STRAW[tone])
    # the rope's shadow on the floor just below its near half
    for (x, y), (angle, across) in cells.items():
        if angle > 0.35 and angle < math.pi - 0.35 and (x, y + 1) not in cells and img.getpixel((x, y + 1))[3] == 0:
            put(img, x, y + 1, (0, 0, 0), 70)
    # the ties hang from the front arc, a few pixels apart, symmetric about the middle
    ties = {
        -10: ['W', 'W', 'w'],
        -6: ['g', 'R', 'R', 'r'],
        -2: ['c', 'C'],
        2: ['W', 'W', 'w'],
        6: ['g', 'R', 'R', 'r'],
        10: ['c', 'C'],
    }
    for dx, column in ties.items():
        x = CX + dx
        # tied on at the rope's lowest pixel in this column, hanging below it
        base = max(y for (cx, y) in cells if cx == x)
        for i, ch in enumerate(column):
            put(img, x, base + i, TIES[ch])
        put(img, x + 1, base + len(column), (0, 0, 0), 60)
    return img


def ring_obang():
    """The four directions on the ring where they lie (청 east to the right, 적
    south toward the viewer, 백 west, 흑 north behind) and 황, the middle, as a
    soft glow under the feet."""
    img = Image.new('RGBA', (RING_W, RING_H))
    blue, red, yellow, white, black = OBANG
    for y in range(RING_H):
        for x in range(RING_W):
            dx, dy = x - CX, y - CY
            d = (dx / 9.5) ** 2 + (dy / 3.2) ** 2
            if d < 1:
                put(img, x, y, yellow, int(90 * (1 - d)))
    for (x, y), (angle, across) in band().items():
        if across < 0.35 or across > 0.8:
            continue  # a thinner ring than the rope
        quarter = (angle + math.pi / 4) % (2 * math.pi)
        colour = (blue, red, white, black)[int(quarter / (math.pi / 2)) % 4]
        put(img, x, y, colour, 235)
    return img


SOTDAE = [
    '.KKK.........',
    'KLLLK........',
    'KLEKLK.......',
    'TKLLLK.......',
    '.KKLLK...KKK.',
    '...KLLKKKLLMK',
    '...KLLLLLLMMK',
    '....KMMMMMMK.',
    '.....KKKKKK..',
    '.......KK....',
    '.......KK....',
]
SOTDAE_COLOURS = {'K': (40, 28, 20), 'L': (190, 146, 92), 'M': (140, 98, 60), 'W': (100, 68, 40),
                  'E': (238, 230, 208), 'T': (210, 120, 40)}


def sotdae():
    img = Image.new('RGBA', (len(SOTDAE[0]), len(SOTDAE)))
    for y, row in enumerate(SOTDAE):
        for x, ch in enumerate(row):
            if ch != '.':
                put(img, x, y, SOTDAE_COLOURS[ch])
    return img


DRAFTS = {
    'A': ('금줄', ring_geumjul, 'feet'),
    'B': ('오방색', ring_obang, 'feet'),
    'C': ('솟대', sotdae, 'head'),
}


def anm2(width, height, px, py, sheet):
    return f'''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="{sheet}" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="ward" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="Idle">
    <Animation Name="Idle" FrameNum="1" Loop="false">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
          <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="1" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" XCrop="0" YCrop="0" Width="{width}" Height="{height}" XPivot="{px}" YPivot="{py}" />
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>
  </Animations>
</AnimatedActor>
'''


def isaac_scene(ward, place, floor):
    """Isaac placed as 001.000_player.anm2 places him (body pivot (16, 25) 2 below
    the feet, head pivot (16, 28) 5 above), the ward under him at his feet or
    over his head, on a patch of basement floor."""
    scene = floor.copy() if floor else Image.new('RGBA', (48, 60), (92, 78, 66, 255))
    fx, fy = 24, 50
    if place == 'feet':
        scene.alpha_composite(ward, (fx - CX, fy - CY))
    sheet = VANILLA / 'characters/costumes/character_001_isaac.png'
    shadow = Image.new('RGBA', (16, 4))
    for x in range(16):
        for y in range(4):
            if ((x - 7.5) / 8) ** 2 + ((y - 1.5) / 2) ** 2 <= 1:
                shadow.putpixel((x, y), (0, 0, 0, 90))
    scene.alpha_composite(shadow, (fx - 8, fy - 2))
    if sheet.exists():
        isaac = Image.open(sheet).convert('RGBA')
        scene.alpha_composite(isaac.crop((0, 32, 32, 64)), (fx - 16, fy + 2 - 25))
        scene.alpha_composite(isaac.crop((0, 0, 32, 32)), (fx - 16, fy - 5 - 28))
    if place == 'head':
        scene.alpha_composite(ward, (fx - ward.width // 2, fy - 36 - ward.height))
    return scene


def basement():
    path = VANILLA / 'backdrop/01_basement.png'
    if not path.exists():
        return None
    tex = Image.open(path).convert('RGBA')
    return tex.crop((60, 60, 108, 120))


def preview():
    floor = basement()
    scale = 5
    tiles = []
    for key, (name, build, place) in DRAFTS.items():
        scene = isaac_scene(build(), place, floor)
        big = scene.resize((scene.width * scale, scene.height * scale), Image.NEAREST)
        tile = Image.new('RGBA', (scene.width + 6 + big.width, big.height), (36, 30, 28, 255))
        tile.alpha_composite(scene, (0, 0))
        tile.alpha_composite(big, (scene.width + 6, 0))
        tiles.append(tile)
    out = Image.new('RGBA', (max(t.width for t in tiles), sum(t.height for t in tiles) + 12 * len(tiles)),
                    (24, 20, 18, 255))
    y = 0
    for tile in tiles:
        out.alpha_composite(tile, (0, y))
        y += tile.height + 12
    return out


def main():
    name, build, place = DRAFTS[CHOSEN]
    art = build()
    EFFECTS.mkdir(parents=True, exist_ok=True)
    art.save(EFFECTS / 'conch_jangseung_ward.png')
    if place == 'feet':
        pivot = (CX, CY)
    else:
        pivot = (art.width // 2, art.height + 36)
    (EFFECTS / 'conch_jangseung_ward.anm2').write_text(
        anm2(art.width, art.height, pivot[0], pivot[1], 'conch_jangseung_ward.png'), encoding='utf-8')
    PREVIEW.mkdir(parents=True, exist_ok=True)
    preview().save(PREVIEW / 'ward_drafts.png')
    print('wrote', CHOSEN, name, EFFECTS / 'conch_jangseung_ward.png', PREVIEW / 'ward_drafts.png')


if __name__ == '__main__':
    main()
