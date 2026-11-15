"""Underdog (언더독): the item icon, finished grid.

A bronze medal (the underdog's prize) hung by a ring from a short red ribbon,
with a dog's bone across its face. Built the way vanilla coins are (A Quarter,
Wooden Nickel): a near-black (8,0,0) outline two pixels thick on the sides, a
bevelled rim, the coin's reeded edge showing below the face, a small glint and
an emblem outlined in black; four tones per material (bronze, Champion Belt's
reds, Brittle Bones' whites). Redrawn on the native grid at the user's request
of 2026-11-15 (more Isaac-like detail, a black outline); this text grid is the
source. `python docs/previews/underdog/author.py` writes the runtime PNG and an
enlarged preview into .tmp/underdog/.
"""
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PAL = {
    "0": (8, 0, 0),        # outline
    "1": (74, 38, 12),     # bronze, deep
    "2": (128, 72, 26),    # bronze, shadow
    "3": (184, 112, 46),   # bronze
    "4": (230, 166, 88),   # bronze, lit
    "5": (255, 236, 190),  # glint
    "r": (83, 0, 0),       # ribbon, shadow
    "q": (131, 0, 0),      # ribbon stripe
    "R": (179, 0, 0),      # ribbon
    "Q": (231, 0, 0),      # ribbon, lit
    "c": (167, 167, 167),  # bone, shadow
    "b": (219, 219, 219),  # bone
    "w": (255, 255, 254),  # bone, lit
}
ROWS = [
    "...........0000000000...........",  # 0
    "..........000000000000..........",  # 1
    ".........00QQRRqqRRrr00.........",  # 2
    ".........00QQRRqqRRrr00.........",  # 3
    ".........00QRRRqqRRrr00.........",  # 4
    ".........00QRRRqqRRrr00.........",  # 5
    ".........00QRRRqqRRrr00.........",  # 6
    ".........00QRRRqqRRrr00.........",  # 7
    "..........00RRRqqRRr00..........",  # 8
    "...........00RRqqRr00...........",  # 9
    "............00RqqR00............",  # 10
    ".............004200.............",  # 11
    ".............000000.............",  # 12
    "...........002222200............",  # 13
    "..........02211111220...........",  # 14
    ".........0211543331220..........",  # 15
    "........001154330032200.........",  # 16
    ".......002144330ww032100........",  # 17
    ".......001443330wbw03200........",  # 18
    ".......0014333330wbw0200........",  # 19
    ".......001333330wccc0300........",  # 20
    ".......00130030wc0003300........",  # 21
    ".......0010ww0wc03333300........",  # 22
    ".......0010wbwc033333300........",  # 23
    ".......00220wbc033333100........",  # 24
    ".......012220wc033333000........",  # 25
    "........012220033333110.........",  # 26
    "........010112333311110.........",  # 27
    ".........0011111111010..........",  # 28
    "..........01101101100...........",  # 29
    "...........000110000............",  # 30
    "..............000...............",  # 31
]


def icon():
    assert len(ROWS) == 32 and all(len(row) == 32 for row in ROWS), "icon must be 32x32"
    image = Image.new("RGBA", (32, 32))
    for y, row in enumerate(ROWS):
        for x, ch in enumerate(row):
            if ch != ".":
                image.putpixel((x, y), PAL[ch] + (255,))
    return image


def main():
    image = icon()
    image.save(os.path.join(ROOT, "resources", "gfx", "items", "collectibles", "underdog.png"))
    preview = os.path.join(ROOT, ".tmp", "underdog")
    os.makedirs(preview, exist_ok=True)
    image.resize((256, 256), Image.NEAREST).save(os.path.join(preview, "icon_x8.png"))
    print("wrote underdog.png and", os.path.join(preview, "icon_x8.png"))


if __name__ == "__main__":
    main()
