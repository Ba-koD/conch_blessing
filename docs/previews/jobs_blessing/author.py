"""Job's Blessing (욥의 축복): the item icon, finished grid.

The even balance of Job 31:6 ("Let me be weighed in an even balance, that God
may know mine integrity") tipped by the double portion of 42:10 ("the LORD
gave Job twice as much as he had before"): one penny on the high pan, two on
the low one, laid like the vanilla penny and double penny pickups (the back
coin's upper left shows past the front one). A nimbus stands behind the
beam's head the way Sworn Protector's halo does (a 1px pale yellow ring with
no outline, behind the art): only its arc above the beam shows, the rest is
behind the scale; under it a soft glow is drawn the way Crown of Light's is. The user chose this direction (H, the scale) on
2026-11-19 out of rounds of sheep, potsherd, whirlwind and Job himself, after
asking for a design from Job's story with the focus on "double", and asked for
the halo behind it.

Built in the vanilla language, measured on Damocles, Holy Grail, Midas Touch,
Ankh and others: a near-black (8,0,0) outline 2px around the outside of the
silhouette and 1px between its parts, a footprint 26px wide, top-left light,
the scale in a gold ramp near Midas Touch's, the pans in a darker bronze so the
bright gold coins stand out, cords as bare dark lines. Authored on the native
32x32 grid. `python docs/previews/jobs_blessing/author.py` writes the runtime
PNG and an enlarged preview into .tmp/jobs_blessing/.
"""
import math
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PAL = {
    "0": (8, 0, 0),        # outline
    "H": (255, 246, 196),  # gold, highlight
    "A": (246, 200, 84),   # gold, lit
    "B": (222, 160, 44),   # gold
    "C": (168, 110, 26),   # gold, shadow
    "E": (120, 72, 16),    # gold, deep shadow (the foot)
    "D": (104, 64, 18),    # cords and hooks
    "a": (206, 150, 74),   # pan, lit
    "b": (160, 104, 44),   # pan
    "c": (106, 62, 26),    # pan, shadow
    "d": (66, 38, 16),     # inside of a pan
    "w": (255, 255, 255),  # coin glint
    "Q": (255, 240, 150),  # coin, lit
    "q": (255, 208, 56),   # coin
    "M": (214, 150, 24),   # coin, shadow
    "k": (150, 96, 14),    # coin edge
    "h": (255, 255, 135),  # the nimbus (Sworn Protector's halo yellow)
}
ROWS = [
"................................",  # 0
"................................",  # 1
".............hhhhh..............",  # 2
"...........hh..00.hh............",  # 3
".........hh...0000..hh..........",  # 4
".........h...00HA00..h..........",  # 5
"......000000.0AHBC00..h.........",  # 6
".....00000000.0BC0....h.........",  # 7
"....00HHAAAAA00AC00..00000......",  # 8
"....00CCCCCCCAAHAAA00000000.....",  # 9
".....00000000CABBCCAAAAAAB00....",  # 10
"........D....0BBCC0CCCCCCC00....",  # 11
".......D.D....0CC0.00000000.....",  # 12
"......D000D...0AC0.....D........",  # 13
".....00wQq0...0AC0...000D.......",  # 14
"....00QqqqM0..0AC0..0wQq00......",  # 15
"....00kkkkk0..0AC0.0Qqq00000....",  # 16
"...00ddddddd0.0AC0.0kk0wQq000...",  # 17
"...00aaaabbb0.0AC0..00QqqqM000..",  # 18
"....00bbccc0..0AC0..00kkkkk000..",  # 19
".....000000...0AC0.0dd0000000...",  # 20
"......000.....0AC0.0aaaabbb00...",  # 21
"..............0AC0..0bbccc00....",  # 22
".............0ABBC0..000000.....",  # 23
"...........00AABBCC0...000......",  # 24
"..........00BBBBCCEE00..........",  # 25
"...........0000000000...........",  # 26
"............00000000............",  # 27
"................................",  # 28
"................................",  # 29
"................................",  # 30
"................................",  # 31
]
# The soft glow behind everything: centred on the nimbus, fading out past it.
GLOW_CENTRE = (15.5, 10.5)
GLOW_RADIUS = 11.0
GLOW_COLOUR = (255, 236, 140)
GLOW_STRENGTH = 0.45


def icon():
    assert len(ROWS) == 32 and all(len(row) == 32 for row in ROWS), "icon must be 32x32"
    image = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    cx, cy = GLOW_CENTRE
    for y in range(32):
        for x in range(32):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / GLOW_RADIUS
            if d < 1:
                alpha = int(255 * GLOW_STRENGTH * (1 - d) ** 1.3)
                if alpha > 0:
                    image.putpixel((x, y), GLOW_COLOUR + (alpha,))
    art = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    for y, row in enumerate(ROWS):
        for x, ch in enumerate(row):
            if ch != ".":
                art.putpixel((x, y), PAL[ch] + (255,))
    image.alpha_composite(art)
    return image


def main():
    image = icon()
    image.save(os.path.join(ROOT, "resources", "gfx", "items", "collectibles", "jobs_blessing.png"))
    preview = os.path.join(ROOT, ".tmp", "jobs_blessing")
    os.makedirs(preview, exist_ok=True)
    image.resize((256, 256), Image.NEAREST).save(os.path.join(preview, "icon_x8.png"))
    print("wrote jobs_blessing.png and", os.path.join(preview, "icon_x8.png"))


if __name__ == "__main__":
    main()
