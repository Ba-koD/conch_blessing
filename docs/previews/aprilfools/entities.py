"""The April Fools 3D sheets of this mod's entities (user request
2026-11-11: "엔티티같은건 3D로").

Every frame an entity's anm2 crops from its sheet is read into solids the way
an item icon is (auto.py: the outline round the drawing stays line art, dark
features inside it are modelled, its shading carved as relief), built as real
meshes and rendered straight from the front on that frame's own grid. Each
frame keeps its outline, glow and alpha pixel for pixel, so the new sheet has
the shipped sheet's exact layout: an April Fools switch only has to swap the
sheet (Sprite:ReplaceSpritesheet), like the 장승 set. Run from the repository
root:

    python docs/previews/aprilfools/entities.py [anm2 ...]

The sheets go to resources/gfx/effects/notused/aprilfools/entities/ under
their shipped file names (left out of the Workshop package; nothing switches
to them), with a preview under .tmp/aprilfools/.
"""
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from auto import auto_spec  # noqa: E402
from relief import front_view, one_to_one  # noqa: E402
from sculpt import sculpt  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GFX = ROOT / 'resources/gfx'
OUT = GFX / 'effects/notused/aprilfools/entities'
PREVIEW = ROOT / '.tmp/aprilfools'

# the entities: familiars, the ox and its rice, the running rat, the 금줄, the
# rabbit's tracks, and the card and rune pickups (장승 has its own 3D set,
# made from its real model in docs/previews/jangseung/model3d.py)
ANIMATIONS = [
    'dragon.anm2', 'hermit_crab.anm2', 'time_money.anm2',
    'effects/conch_ox.anm2', 'effects/conch_ox_rice.anm2', 'effects/conch_rat_run.anm2',
    'effects/conch_jangseung_ward.anm2', 'effects/conch_rabbit_tracks.anm2',
    '005.300_conch_ticket.anm2', '005.300_thurisaz.anm2', '005.300_uruz.anm2',
]


def frames_of(anm2):
    """{sheet path: set of (x, y, w, h)} for every frame the animation crops,
    for the sheets this mod ships (vanilla sheets are left alone)."""
    root = ET.parse(GFX / anm2).getroot()
    sheets = {s.get('Id'): (GFX / anm2).parent / s.get('Path') for s in root.iter('Spritesheet')}
    layers = {l.get('Id'): l.get('SpritesheetId') for l in root.iter('Layer')}
    out = {}
    for la in root.iter('LayerAnimation'):
        sheet = sheets.get(layers.get(la.get('LayerId')))
        if sheet is None or not sheet.exists():
            continue
        for f in la.iter('Frame'):
            if f.get('XCrop') is not None:
                rect = tuple(int(f.get(k)) for k in ('XCrop', 'YCrop', 'Width', 'Height'))
                if rect[2] > 1 and rect[3] > 1:
                    out.setdefault(sheet.resolve(), set()).add(rect)
    return out


def frame_3d(sub):
    """One frame, rendered in 3D on its own grid; an empty frame, or one that
    is mostly soft glow (a card's flash), stays as it is."""
    seen = sub[..., 3] > 0
    if not (sub[..., 3] >= 128).any() or (sub[..., 3] == 255).sum() < 0.3 * seen.sum():
        return sub
    h, w = sub.shape[:2]
    labels, info, mats, obj, detail = auto_spec(sub)
    if not obj.any():
        return sub
    parts = sculpt(labels, info, mats, detail)
    hero = front_view(parts, mats, size=max(w, h) * 8, ss=2, w=w, h=h)
    april, _ = one_to_one(sub, hero, coloured=obj)
    return np.array(april)


def convert(anm2):
    done = []
    for sheet, rects in frames_of(anm2).items():
        src = np.array(Image.open(sheet).convert('RGBA'))
        out = src.copy()
        for x, y, w, h in sorted(rects):
            sub = src[y:y + h, x:x + w]
            if sub.shape[0] != h or sub.shape[1] != w:
                continue
            out[y:y + h, x:x + w] = frame_3d(sub.copy())
        OUT.mkdir(parents=True, exist_ok=True)
        Image.fromarray(out, 'RGBA').save(OUT / sheet.name)
        done.append((sheet, len(rects)))
    return done


def preview(sheets):
    rows = []
    for sheet in sheets:
        a = Image.open(sheet).convert('RGBA')
        b = Image.open(OUT / sheet.name).convert('RGBA')
        k = max(1, min(4, 900 // max(a.width, 1)))
        rows.append((sheet.name, a.resize((a.width * k, a.height * k), Image.NEAREST),
                     b.resize((b.width * k, b.height * k), Image.NEAREST)))
    width = max(r[1].width for r in rows) * 2 + 36
    height = sum(r[1].height + 24 for r in rows) + 10
    img = Image.new('RGBA', (width, height), (52, 45, 40, 255))
    d = ImageDraw.Draw(img)
    y = 6
    for name, a, b in rows:
        d.text((8, y), name, fill=(225, 215, 195, 255))
        img.alpha_composite(a, (8, y + 14))
        img.alpha_composite(b, (8 + a.width + 20, y + 14))
        y += a.height + 24
    return img


def main(names):
    started = time.time()
    sheets = []
    for anm2 in names or ANIMATIONS:
        for sheet, n in convert(anm2):
            sheets.append(sheet)
            print(f'{anm2}: {sheet.name} {n} frames ({time.time() - started:.0f}s)', flush=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    preview(sheets).save(PREVIEW / 'entities_sheet.png')
    print('preview', PREVIEW / 'entities_sheet.png')


if __name__ == '__main__':
    main(sys.argv[1:])
