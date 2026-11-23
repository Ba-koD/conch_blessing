"""Aging Curve (에이징 커브): the item icon, a first draft on the native grid.

A chart card: pale paper with a faint grid and two axes, and a thick red
curve that climbs steeply to a peak marked with a small gold star and then
slides down for the rest of the card (the prime early, the long decline).
Built like vanilla paper items: a near-black (8,0,0) outline two pixels thick
on the outside, one pixel between parts, top-left light, three or four tones
per material. Drawn 2026-11-24; the user has not reviewed it.
`python docs/previews/aging-curve/author.py` writes the runtime PNG and an
enlarged preview into .tmp/aging-curve/.
"""
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUTLINE = (8, 0, 0, 255)
PAPER_LIT = (248, 242, 226, 255)
PAPER = (228, 216, 188, 255)
PAPER_SHADE = (190, 174, 140, 255)
GRID = (208, 194, 162, 255)
AXIS = (96, 72, 52, 255)
RED_DARK = (110, 0, 0, 255)
RED = (196, 28, 28, 255)
RED_LIT = (240, 92, 64, 255)
GOLD = (226, 170, 40, 255)
GOLD_LIT = (255, 232, 130, 255)

# The curve's top pixel per column: a steep climb, a short prime, a long slide.
CURVE = {9: 22, 10: 19, 11: 16, 12: 13, 13: 11, 14: 10, 15: 10, 16: 10, 17: 11, 18: 12,
         19: 13, 20: 15, 21: 16, 22: 18, 23: 19, 24: 21}


def draw():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    px = img.load()
    left, top, right, bottom = 4, 4, 27, 27
    # Outline block with rounded corners, then the paper inside it.
    for y in range(top, bottom + 1):
        for x in range(left, right + 1):
            corner = (x in (left, right)) and (y in (top, bottom))
            if not corner:
                px[x, y] = OUTLINE
    for y in range(top + 2, bottom - 1):
        for x in range(left + 2, right - 1):
            px[x, y] = PAPER
    # Light from the top left: a lit top row and left column, a shaded right
    # column and bottom row.
    for x in range(left + 2, right - 1):
        px[x, top + 2] = PAPER_LIT
        px[x, bottom - 2] = PAPER_SHADE
    for y in range(top + 2, bottom - 1):
        px[left + 2, y] = PAPER_LIT
        px[right - 2, y] = PAPER_SHADE
    # A faint grid.
    for g in (12, 17, 22):
        for y in range(top + 3, bottom - 2):
            if px[g, y] == PAPER:
                px[g, y] = GRID
    for g in (11, 16, 21):
        for x in range(left + 3, right - 2):
            if px[x, g] == PAPER:
                px[x, g] = GRID
    # Axes: up the left, along the bottom.
    for y in range(8, 24):
        px[8, y] = AXIS
    for x in range(8, 25):
        px[x, 23] = AXIS
    # The curve, two pixels thick with a dark underside.
    for x, y in CURVE.items():
        px[x, y] = RED
        px[x, y + 1] = RED_DARK if y + 1 < 23 else AXIS
    # Fill the steep climb so the line stays unbroken.
    xs = sorted(CURVE)
    for a, b in zip(xs, xs[1:]):
        ya, yb = CURVE[a], CURVE[b]
        for y in range(min(ya, yb) + 1, max(ya, yb)):
            column = a if ya > yb else b
            if px[column, y] not in (RED, RED_DARK):
                px[column, y] = RED
    for x in (14, 15, 16):
        px[x, 10] = RED_LIT
    # The peak's gold star.
    star = {(15, 6): GOLD, (14, 7): GOLD, (15, 7): GOLD_LIT, (16, 7): GOLD, (15, 8): GOLD}
    for (x, y), c in star.items():
        px[x, y] = c
    return img


def main():
    img = draw()
    out = os.path.join(ROOT, "resources", "gfx", "items", "collectibles", "aging_curve.png")
    img.save(out)
    preview_dir = os.path.join(ROOT, ".tmp", "aging-curve")
    os.makedirs(preview_dir, exist_ok=True)
    img.resize((32 * 12, 32 * 12), Image.NEAREST).save(os.path.join(preview_dir, "icon_x12.png"))
    print(out)


if __name__ == "__main__":
    main()
