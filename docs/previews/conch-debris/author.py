"""Conch Debris (소라 잔해) trinket icon, the finished 32x32 grid.

The Magic Conch's shell smashed into a heap: a tall plate of the outer shell
with its spiral ridges (left), the spire tip resting on the heap (right), the
pink-lined aperture split by a crack (front), a wedge and two chips, and crumbs
at the foot. Broken edges show the shell's pale cross-section (W). Authored on
the native grid (user request 2026-11-15: "really smashed into debris"); this
text grid is the source. `python docs/previews/conch-debris/author.py` writes
the runtime PNG and an enlarged preview into .tmp/conch-debris/.
"""
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PAL = {
    "K": (22, 14, 26),     # outline
    "D": (118, 116, 168),  # shell shadow / spiral ridges
    "M": (168, 174, 220),  # shell
    "L": (208, 214, 244),  # lit shell
    "H": (248, 250, 255),  # highlight
    "W": (240, 232, 244),  # broken edge: the shell's cross-section
    "R": (244, 198, 222),  # nacre, lit
    "P": (226, 150, 190),  # nacre
    "Q": (176, 96, 146),   # nacre, deep
}
ROWS = [
    "................................",  # 0
    "................................",  # 1
    "................................",  # 2
    "................................",  # 3
    "................................",  # 4
    "................................",  # 5
    "....KKK..............KKKK.......",  # 6
    "....KWKK.......KKK..KKLMKK......",  # 7
    "....KLWKK.....KKWK.KKLHMDKK.....",  # 8
    "....KLHWKK....KWLKKKLHMMMDK.....",  # 9
    "....KLHLWKKKKKKLMKKDDDDDDDK.....",  # 10
    "....KLHLMWKKLLMKKKLHHMMMMDK.....",  # 11
    "....KLLMDMKLHLMMDKWWWWWWWKKK....",  # 12
    "....KLLMMDKLRRKMMDKKDMDKKWLK....",  # 13
    "....KLMMMMKLPPPKQMDKDDKKWLMK....",  # 14
    "....KLMDMMKRPPQKQQMDKKKWLMDK....",  # 15
    "....KMMMDMKPPQQQKQQDWKWLMDDK....",  # 16
    "....KDMMMDDKPQQQPKQQKWMMDDKK....",  # 17
    "....KKDDMMMKPPQQQKDWKDDDKKK.....",  # 18
    ".....KKKDDDDKPPQDWWKKKKKK.......",  # 19
    ".....KKWKKKKKKWWWKKK............",  # 20
    "....KKWLK....KKKKK..............",  # 21
    "....KWMDK................W......",  # 22
    "....KKKKKM.....LD...W....K......",  # 23
    ".........K.....KK...K...........",  # 24
    "................................",  # 25
    "................................",  # 26
    "................................",  # 27
    "................................",  # 28
    "................................",  # 29
    "................................",  # 30
    "................................",  # 31
]


def image():
    assert len(ROWS) == 32 and all(len(row) == 32 for row in ROWS)
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    for y, row in enumerate(ROWS):
        for x, ch in enumerate(row):
            if ch != ".":
                im.putpixel((x, y), PAL[ch] + (255,))
    return im


if __name__ == "__main__":
    im = image()
    im.save(os.path.join(ROOT, "resources", "gfx", "items", "trinkets", "conch_debris.png"))
    out = os.path.join(ROOT, ".tmp", "conch-debris")
    os.makedirs(out, exist_ok=True)
    im.resize((32 * 12, 32 * 12), Image.NEAREST).save(os.path.join(out, "conch_debris_x12.png"))
