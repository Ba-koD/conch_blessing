"""Cereal (시리얼): builds the bowl UI preview page.

`python docs/previews/cereal/build.py` reads the vanilla item list, names,
pools and icons from the extracted resources (read in place, never copied into
the runtime package), this mod's own items from content/items.xml and the
locale files, and writes `cereal-ui-preview.html` beside this script with every
picture embedded, so the page opens without a server. The page itself lives in
`template.html`; the cereal digits, the milk bowl and the HUD marks are drawn by
its script from the pixel maps there.
"""
import base64
import io
import os
import sys
import xml.etree.ElementTree as ET

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GAME = os.path.abspath(os.path.join(ROOT, "..", ".."))
RES = os.path.join(GAME, "extracted_resources", "resources")
sys.path.insert(0, ROOT)
import lua_data  # noqa: E402

VANILLA_LAST = 732  # the last vanilla collectible; ours follow it when no other mod loads first


def png_uri(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def vanilla_items():
    st = ET.parse(os.path.join(RES, "stringtable.sta")).getroot()
    names = {}
    for key in st.iter("key"):
        strings = key.findall("string")
        if len(strings) >= 3:
            names[key.get("name")] = (strings[0].text or "", strings[2].text or strings[0].text or "")
    quality = {}
    for e in ET.parse(os.path.join(RES, "items_metadata.xml")).getroot():
        if e.tag == "item":
            quality[int(e.get("id"))] = int(e.get("quality") or 0)
    pooled = set()
    for pool in ET.parse(os.path.join(RES, "itempools.xml")).getroot():
        for it in pool:
            pooled.add(int(it.get("Id")))
    rows = []
    for e in ET.parse(os.path.join(RES, "items.xml")).getroot():
        if e.tag not in ("passive", "active", "familiar") or not e.get("id"):
            continue
        cid = int(e.get("id"))
        key = (e.get("name") or "").lstrip("#")
        en, kr = names.get(key, (e.get("name"), e.get("name")))
        gfx = e.get("gfx")
        path = None
        for folder in ("collectibles",):
            for cand in (gfx, gfx.lower()):
                p = os.path.join(RES, "gfx", "items", folder, cand)
                if os.path.exists(p):
                    path = p
                    break
        rows.append({
            "id": cid, "en": en, "kr": kr, "q": quality.get(cid, 0),
            "active": e.tag == "active", "craft": cid in pooled and e.get("hidden") != "true",
            "path": path,
        })
    return rows


def own_items():
    tree = ET.parse(os.path.join(ROOT, "content", "items.xml")).getroot()
    pooled = set()
    for pool in ET.parse(os.path.join(ROOT, "content", "itempools.xml")).getroot():
        for it in pool:
            pooled.add(it.get("Name"))
    en_items = lua_data.load(os.path.join(ROOT, "scripts", "locale", "en.lua")).get("items", {})
    kr_items = lua_data.load(os.path.join(ROOT, "scripts", "locale", "kr.lua")).get("items", {})
    by_name = {v.get("name"): k for k, v in en_items.items() if isinstance(v, dict)}
    rows = []
    n = 0
    for e in tree:
        if e.tag not in ("passive", "active", "familiar"):
            continue
        n += 1
        name = e.get("name")
        key = by_name.get(name)
        kr = (kr_items.get(key) or {}).get("name", name) if key else name
        path = os.path.join(ROOT, "resources", "gfx", "items", "collectibles", e.get("gfx"))
        rows.append({
            "id": VANILLA_LAST + n, "en": name, "kr": kr, "q": int(e.get("quality") or 0),
            "active": e.tag == "active", "craft": name in pooled and e.get("hidden") != "true",
            "path": path if os.path.exists(path) else None, "own": True,
        })
    return rows


def main():
    rows = vanilla_items() + own_items()
    cols = 32
    atlas = Image.new("RGBA", (cols * 32, ((len(rows) + cols - 1) // cols) * 32), (0, 0, 0, 0))
    items = []
    for i, r in enumerate(rows):
        if r["path"]:
            icon = Image.open(r["path"]).convert("RGBA")
            if icon.size != (32, 32):
                icon = icon.crop((0, 0, 32, 32))
            atlas.alpha_composite(icon, ((i % cols) * 32, (i // cols) * 32))
        items.append([r["id"], r["en"], r["kr"], r["q"], 1 if r["active"] else 0, 1 if r["craft"] else 0, i,
                      1 if r.get("own") else 0])

    gfx = os.path.join(RES, "gfx")
    isaac = Image.open(os.path.join(gfx, "characters", "costumes", "character_001_isaac.png")).convert("RGBA")
    hud = Image.open(os.path.join(gfx, "ui", "hudpickups.png")).convert("RGBA").crop((0, 0, 32, 32))
    hearts = Image.open(os.path.join(gfx, "ui", "ui_hearts.png")).convert("RGBA").crop((0, 0, 16, 16))
    altar = Image.open(os.path.join(gfx, "items", "levelitem_001_itemaltar.png")).convert("RGBA").crop((0, 0, 32, 32))
    anims = {}
    walk = {"WalkDown": "1", "WalkUp": "1", "WalkLeft": "1", "WalkRight": "1",
            "PickupWalkDown": "12", "PickupWalkUp": "12", "PickupWalkLeft": "12", "PickupWalkRight": "12",
            "HeadDown": "4", "HeadUp": "4", "HeadLeft": "4", "HeadRight": "4"}
    for a in ET.parse(os.path.join(gfx, "001.000_player.anm2")).getroot().iter("Animation"):
        name = a.get("Name")
        if name not in walk:
            continue
        layers = {}
        for la in a.iter("LayerAnimation"):
            frames = []
            for f in la.findall("Frame"):
                frames.append([int(float(f.get(k))) for k in ("XCrop", "YCrop", "Width", "Height", "XPivot", "YPivot",
                                                              "XPosition", "YPosition", "Delay")]
                              + [1 if float(f.get("XScale")) < 0 else 0])
            if frames:
                layers[la.get("LayerId")] = frames
        anims[name] = {"body": layers.get(walk[name]) if not name.startswith("Head") else None,
                       "head": layers.get("4")}
    sys.path.insert(0, HERE)
    import author  # noqa: E402  (the UI sheet's layout, shared with the runtime art)
    ui = Image.open(os.path.join(ROOT, "resources", "gfx", "ui", "conch_cereal_ui.png")).convert("RGBA")
    data = {
        "ui": png_uri(ui),
        "uiParts": {name: list(box) for name, box in author.UI_PARTS.items()},
        "digit": {"y": author.DIGIT_Y, "w": author.DIGIT_W, "h": author.DIGIT_H},
        "anims": anims,
        "items": items,
        "atlas": png_uri(atlas),
        "atlasCols": cols,
        "isaac": png_uri(isaac),
        "hud": png_uri(hud),
        "hearts": png_uri(hearts),
        "altar": png_uri(altar),
        "vanillaLast": VANILLA_LAST,
    }
    import json
    template = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
    out = template.replace("/*DATA*/null", json.dumps(data, ensure_ascii=False))
    target = os.path.join(HERE, "cereal-ui-preview.html")
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("wrote", target, len(out) // 1024, "KB,", len(items), "items")


if __name__ == "__main__":
    main()
