"""Landmine (지뢰): builds the play-feel preview of the tear-bomber idea.

`python docs/previews/landmine/feel.py` reads the vanilla basement backdrop,
Isaac, the Gaper, tears, tear poofs, blood and bomb explosions from the
extracted resources (read in place, never copied into the runtime package) and
this mod's own floor mine sheet, and writes `feel-preview.html` beside this
script with every picture and every animation frame embedded, so the page opens
without a server. The page itself lives in `feel-template.html`; its script is
a small simulation at the game's 30 updates a second and 26/40 pixels a world
unit, for judging numbers by feel before any of them reach landmine.lua.
"""
import base64
import io
import json
import os
import xml.etree.ElementTree as ET

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GAME = os.path.abspath(os.path.join(ROOT, "..", ".."))
GFX = os.path.join(GAME, "extracted_resources", "resources", "gfx")
OWN = os.path.join(ROOT, "resources", "gfx")

SPECS = {
    "isaac": (os.path.join(GFX, "001.000_player.anm2"),
              ["WalkDown", "WalkUp", "WalkLeft", "WalkRight", "HeadDown", "HeadUp", "HeadLeft", "HeadRight"],
              {"body", "head"}),
    "gaper": (os.path.join(GFX, "010.001_gaper.anm2"), ["WalkHori", "WalkVert", "Head"], None),
    "tear": (os.path.join(GFX, "002.000_tear.anm2"), ["RegularTear%d" % i for i in range(1, 14)], None),
    "poof": (os.path.join(GFX, "1000.012_tear poofa.anm2"), ["Poof"], None),
    "blood": (os.path.join(GFX, "1000.002_blood explosion.anm2"), ["Poof"], None),
    "boom": (os.path.join(GFX, "1000.001_bomb explosion.anm2"), ["Explosion"], None),
    "mine": (os.path.join(OWN, "effects", "conch_landmine.anm2"), ["Fall", "Land", "Idle"], None),
}
BACKDROP_IN = 15  # as docs/previews/jangseung/placement.py measured it


def png_uri(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def backdrop():
    sheet = Image.open(os.path.join(GFX, "backdrop", "01_basement.png")).convert("RGBA")
    quarter = sheet.crop((0, 0, 234, 156))
    room = Image.new("RGBA", (468, 312), (0, 0, 0, 255))
    k = BACKDROP_IN
    for img, (x, y) in ((quarter.transpose(Image.ROTATE_180), (234 - k, 156 - k)),
                        (quarter.transpose(Image.FLIP_TOP_BOTTOM), (k, 156 - k)),
                        (quarter.transpose(Image.FLIP_LEFT_RIGHT), (234 - k, k)),
                        (quarter, (k, k))):
        room.alpha_composite(img, (x, y))
    return room


def read_anm2(path, wanted, layer_names, sheets, sheet_index):
    root = ET.parse(path).getroot()
    base = os.path.dirname(path)
    sheet_of = {}
    for s in root.iter("Spritesheet"):
        full = os.path.normpath(os.path.join(base, s.get("Path")))
        if full not in sheet_index:
            sheet_index[full] = len(sheets)
            sheets.append(png_uri(Image.open(full).convert("RGBA")))
        sheet_of[s.get("Id")] = sheet_index[full]
    layers = {l.get("Id"): (l.get("Name"), l.get("SpritesheetId")) for l in root.iter("Layer")}
    out = {}
    for anim in root.iter("Animation"):
        name = anim.get("Name")
        if name not in wanted:
            continue
        entry = {"frames": int(anim.get("FrameNum")), "loop": anim.get("Loop") == "true", "layers": []}
        for la in anim.iter("LayerAnimation"):
            lname, sid = layers[la.get("LayerId")]
            if layer_names and lname not in layer_names:
                continue
            if la.get("Visible") != "true":
                continue
            frames = []
            for f in la.findall("Frame"):
                a = f.attrib
                frames.append([int(float(a["XCrop"])), int(float(a["YCrop"])), int(float(a["Width"])),
                               int(float(a["Height"])), float(a["XPivot"]), float(a["YPivot"]),
                               float(a["XPosition"]), float(a["YPosition"]), float(a["XScale"]) / 100,
                               float(a["YScale"]) / 100, float(a.get("Rotation", 0)), int(a["Delay"]),
                               1 if a["Visible"] == "true" else 0, float(a.get("AlphaTint", 255)) / 255])
            if frames:
                entry["layers"].append({"name": lname, "sheet": sheet_of[sid], "frames": frames})
        out[name] = entry
    return out


def main():
    sheets, sheet_index, anims = [], {}, {}
    for key, (path, wanted, layer_names) in SPECS.items():
        anims[key] = read_anm2(path, wanted, layer_names, sheets, sheet_index)
    data = {"sheets": sheets, "anims": anims, "room": png_uri(backdrop())}
    with open(os.path.join(HERE, "feel-template.html"), encoding="utf-8") as handle:
        page = handle.read()
    page = page.replace("/*DATA*/null", json.dumps(data, separators=(",", ":")))
    out = os.path.join(HERE, "feel-preview.html")
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)
    print("wrote", out, "%.0f KB" % (len(page) / 1024))


if __name__ == "__main__":
    main()
