"""Builds the oxen's sleeping pose from their idle frames in conch_ox.png.

An ox with nowhere left to go lies down where it stands (user request
2026-10-31): the body and head drop onto the ground, the legs tuck under
it, the eye closes and two small z's drift up above the horns. The sheet is
four 48x34 frames a row, 누렁소 on top and 검은소 below, read by the
Sleep animations of conch_ox.anm2 through their own layer. Run from the
repository root after conch_ox.png changes:

    python docs/previews/ox-revision/sleep.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SHEET = ROOT / 'resources/gfx/effects/conch_ox.png'
OUT = ROOT / 'resources/gfx/effects/conch_ox_sleep.png'
W, H = 48, 34
IDLE_X = 8 * W          # the idle pose is the ninth cell of each row
DROP = 6                # the body sinks onto the ground by the leg height
LEG_TOP = 25            # first row of the legs in the idle pose
EYE = [(35, 14), (36, 14)]  # the open eye; closed it is a short dark line
Z = ['####', '..#.', '.#..', '####']
Z_PATH = [(33, 6), (36, 4), (39, 2), (42, 0)]  # each z rises along these
GLYPH = (236, 232, 252, 255)


def darkest(frame):
    """The contour colour: the darkest opaque pixel."""
    best = None
    for p in frame.getdata():
        if p[3] and (best is None or sum(p[:3]) < sum(best[:3])):
            best = p
    return best


def lying(idle):
    outline = darkest(idle)
    leg = idle.getpixel((12, 27))
    hoof = idle.getpixel((11, 30))
    body = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for y in range(LEG_TOP):
        for x in range(W):
            p = idle.getpixel((x, y))
            if p[3]:
                body.putpixel((x, y + DROP), p)
    for x, y in EYE:
        body.putpixel((x, y + DROP), outline)
    # Legs tucked under the belly: a dark fold with a hoof at each end.
    for left, right in ((10, 17), (27, 34)):
        for x in range(left, right + 1):
            body.putpixel((x, LEG_TOP + DROP - 1), leg)
            body.putpixel((x, LEG_TOP + DROP), outline)
        body.putpixel((left - 1, LEG_TOP + DROP - 1), outline)
        body.putpixel((right + 1, LEG_TOP + DROP - 1), outline)
        body.putpixel((right, LEG_TOP + DROP - 1), hoof)
    return body, outline


def with_z(base, outline, spots):
    frame = base.copy()
    for ox, oy in spots:
        ink = {(ox + i, oy + j) for j, row in enumerate(Z) for i, c in enumerate(row) if c == '#'}
        for x, y in ink:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q not in ink and 0 <= q[0] < W and 0 <= q[1] < H:
                        frame.putpixel(q, outline)
        for x, y in ink:
            frame.putpixel((x, y), GLYPH)
    return frame


def main():
    sheet = Image.open(SHEET).convert('RGBA')
    out = Image.new('RGBA', (W * 4, H * 2), (0, 0, 0, 0))
    for row in range(2):
        idle = sheet.crop((IDLE_X, row * H, IDLE_X + W, row * H + H))
        base, outline = lying(idle)
        for k in range(4):
            # Two z's half a cycle apart, each rising one step a frame.
            spots = [Z_PATH[k], Z_PATH[(k + 2) % 4]]
            out.paste(with_z(base, outline, spots), (k * W, row * H))
    out.save(OUT)
    print('saved', OUT.relative_to(ROOT), out.size)


if __name__ == '__main__':
    main()
