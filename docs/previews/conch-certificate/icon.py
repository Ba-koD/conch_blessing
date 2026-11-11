# Conch Certificate (소라 증명서) collectible icon, authored on the native 32x32
# grid: Death Certificate's tilted sheet of paper in the Magic Conch's colours,
# a lavender conch with a pink mouth where the skull would be, and three lines
# of writing. A first draft the user has not reviewed (2026-11-11).
#
#   python docs/previews/conch-certificate/icon.py          writes the runtime PNG
#   python docs/previews/conch-certificate/icon.py preview  also writes an x8 view
#                                                           into .tmp/conch-certificate/
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "resources", "gfx", "items", "collectibles", "conch_certificate.png")

PALETTE = {
    ".": (0, 0, 0, 0),
    "K": (26, 20, 34, 255),     # outline
    "W": (252, 250, 246, 255),  # paper, lit edge
    "P": (234, 230, 238, 255),  # paper
    "Q": (206, 200, 218, 255),  # paper shade
    "R": (172, 164, 190, 255),  # paper deep shade
    "L": (128, 108, 182, 255),  # writing
    "l": (184, 170, 222, 255),  # writing, lower half
    "A": (246, 244, 255, 255),  # conch highlight
    "B": (208, 200, 242, 255),  # conch light
    "C": (160, 148, 214, 255),  # conch mid
    "D": (106, 92, 166, 255),   # conch dark
    "I": (238, 168, 198, 255),  # conch mouth
}

GRID = [
    "................................",
    "................................",
    "................................",
    "...................KKKKK........",
    "..............KKKKKKWWQKK.......",
    ".........KKKKKKWWWWWPPQKK.......",
    ".......KKKWWWWWPPPPPPPQKK.......",
    ".......KWWPPPKKKPPPPPPQKK.......",
    ".......KWPPPKAABKKPPPPQKK.......",
    ".......KWPPKAIIBBCKKPPPQKK......",
    ".......KWPPKAIIIBCCDKKPQKK......",
    ".......KWPPPKAIIBCCDDDKQKK......",
    ".......KKWPPPKKAKBCDDKPQKK......",
    "........KWPPPPPKKKDDKPPQKK......",
    "........KWPPPPPPPKKKPPPQKK......",
    "........KWPPPPPPPPPPPPPQKK......",
    "........KWPPPPPPLLLLLPPQKK......",
    "........KWPLLLLLlllllPPQKK......",
    "........KWPlllllPPPPPPPQKK......",
    "........KWPPPPPPLLLLPPPQKK......",
    "........KWPLLLLLllllPPPPQKK.....",
    "........KWPlllllPPPPPPPPQKK.....",
    "........KWPPPPPPLLLLLPPPQKK.....",
    "........KKWLLLLLlllllPPPQKK.....",
    ".........KWlllllPPPPPPQQRKK.....",
    ".........KWPPPPPPQQQQRKKKKK.....",
    ".........KWPQQQQRKKKKKKKKK......",
    ".........KQRKKKKKKKKKKK.........",
    ".........KKKKKKKKK..............",
    "..........KKK...................",
    "................................",
    "................................",
]


def render():
    assert len(GRID) == 32 and all(len(row) == 32 for row in GRID), "icon grid must be 32x32"
    image = Image.new("RGBA", (32, 32))
    for y, row in enumerate(GRID):
        for x, key in enumerate(row):
            image.putpixel((x, y), PALETTE[key])
    return image


def main():
    image = render()
    image.save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT))
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        folder = os.path.join(ROOT, ".tmp", "conch-certificate")
        os.makedirs(folder, exist_ok=True)
        image.resize((256, 256), Image.NEAREST).save(os.path.join(folder, "icon_x8.png"))
        print("wrote", os.path.relpath(os.path.join(folder, "icon_x8.png"), ROOT))


if __name__ == "__main__":
    main()
