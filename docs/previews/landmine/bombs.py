"""Landmine (지뢰): builds the bomb synergy preview (short Brimstone, ghosts).

`python docs/previews/landmine/bombs.py` reads the vanilla basement backdrop,
the Gaper, the bomb explosion, the thick red laser and its impact, the
red Enemy Ghost and its explosion, and the hungry soul from the extracted
resources (read in place, never copied into the runtime package) and this
mod's own floor mine sheet, and writes `bombs-preview.html` beside this script
with every picture embedded, so the page opens without a server. The page
itself lives in `bombs-template.html`: four small rooms side by side compare
Brimstone Bombs' beams as they are now (across the room) with four short
beams as long as the mine's blast reaches, and Ghost Bombs' chasing ghost with the red ghost that
bursts on the first enemy it reaches.
"""
import json
import os

from feel import GFX, OWN, backdrop, png_uri, read_anm2

HERE = os.path.dirname(os.path.abspath(__file__))

SPECS = {
    "gaper": (os.path.join(GFX, "010.001_gaper.anm2"), ["WalkHori", "WalkVert", "Head"], None),
    "blood": (os.path.join(GFX, "1000.002_blood explosion.anm2"), ["Poof"], None),
    "boom": (os.path.join(GFX, "1000.001_bomb explosion.anm2"), ["Explosion"], None),
    "mine": (os.path.join(OWN, "effects", "conch_landmine.anm2"), ["Fall", "Land", "Idle"], None),
    "laser": (os.path.join(GFX, "007.001_thick red laser.anm2"), ["LargeRedLaser"], None),
    "impact": (os.path.join(GFX, "1000.050_brimstoneimpact.anm2"), ["Start", "Loop"], None),
    "eghost": (os.path.join(GFX, "1000.144_enemy ghost.anm2"),
               ["Idle1", "Idle2", "Idle3", "Idle4", "Explode", "Explosion"], None),
    "hsoul": (os.path.join(GFX, "1000.186_hungry soul.anm2"), ["Appear", "Idle", "Die"], None),
}


def main():
    sheets, sheet_index, anims = [], {}, {}
    for key, (path, wanted, layer_names) in SPECS.items():
        anims[key] = read_anm2(path, wanted, layer_names, sheets, sheet_index)
    data = {"sheets": sheets, "anims": anims, "room": png_uri(backdrop())}
    with open(os.path.join(HERE, "bombs-template.html"), encoding="utf-8") as handle:
        page = handle.read()
    page = page.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
    out = os.path.join(HERE, "bombs-preview.html")
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)
    print("wrote", out, "%.0f KB" % (len(page) / 1024))


if __name__ == "__main__":
    main()
