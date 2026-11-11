"""The April Fools 3D models of this mod's items (user requests 2026-11-11:
real 3D models, "완전 1:1 매칭" with the shipped icons, for every item).

Every icon is read into solids (auto.py; Kronos has its own recipe below),
modelled as closed meshes with their own materials (relief.py, mesh3d.py) and
rendered straight from the front on the exact 32x32 grid. The April Fools icon
keeps the shipped icon's ink outline, glow and alpha pixel for pixel and takes
every object pixel's colour from that render, so its shape matches 1:1 while
the shading is the 3D lighting's. Run from the repository root:

    python docs/previews/aprilfools/models.py [key ...]

It writes each model as a .glb under docs/previews/aprilfools/models/, the
April Fools icons under resources/gfx/items/collectibles/notused/aprilfools/
(trinkets in its trinkets/ folder; left out of the Workshop package, and
nothing switches to them) and an overview sheet under .tmp/aprilfools/.
"""
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from auto import auto_spec  # noqa: E402
from mesh3d import Camera, export_glb, icon, material, render  # noqa: E402
from relief import front_view, spin_view  # noqa: E402
from sculpt import sculpt  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
MODELS = Path(__file__).resolve().parent / 'legacy_models'  # retired experiments; build.py owns models/
PREVIEW = ROOT / '.tmp/aprilfools'
ICONS = ROOT / 'resources/gfx/items/collectibles/notused/aprilfools'
GFX = ROOT / 'resources/gfx/items'
SKIP = {'tmp', 'time_template'}


def items():
    """{key: (kind, shipped icon path)} for every collectible and trinket icon."""
    out = {}
    for kind in ('collectibles', 'trinkets'):
        for p in sorted((GFX / kind).glob('*.png')):
            if p.stem not in SKIP:
                out[p.stem] = (kind, p)
    return out


# Kronos: the Saturn sign as a gold sickle. Its dark gold, gold and cream are
# the sickle's own light and shadow (the user, 2026-11-11), so the blade is one
# gold plate; the X is a second gold body of round bars, kept apart so the
# sickle's mouth stays open.
KRONOS = {
    'blade': {'colors': [(140, 96, 4), (205, 150, 8), (255, 248, 214)], 'mat': 'gold', 'body': 'blade',
              'profile': 'plate', 'thickness': 1.6, 'slope': 0.9},
    'cross': {'colors': [(255, 214, 0), (255, 243, 120)], 'mat': 'gold', 'body': 'cross', 'profile': 'round',
              'thickness': 2.6, 'depth': -0.3, 'grow': 2, 'smooth': 0.75},
}
KRONOS_MATS = {'gold': material((232, 176, 30), spec=0.9, shine=45, metal=True)}

# Items the automatic reading gets wrong. `groups` lists colours (hex) that are
# one material's light and shadow, where colour alone cannot tell a part from
# a shade; `thickness` changes the rounded profile's cap.
OVERRIDES = {
    'conch_pearl': {'thickness': 20.0},  # a whole sphere, not a cushion
    'ox': {'groups': [['b9823e', '936030'], ['ceb184', 'b69360'], ['ede0b8']]},  # hide, muzzle, horns
    'monkey': {'groups': [['815638', '5d3e2d'], ['cfac7b', 'e7d6ae'], ['b64547'], ['efb7a0']]},  # fur, face
    'rabbit': {'groups': [['b98088'], ['8f3338', 'c15e56']]},  # inner ears, eyes
}
# Flat things keep a thin profile (`flat`: half the thickness in icon pixels)
# instead of the round sculpt: paper, a coin, symbols, blades, a crown band.
for key, half in (('appraisal_certificate', 0.7), ('a_minus', 0.6), ('b_minus', 0.6), ('c_minus', 0.6),
                  ('f_minus', 0.6), ('wrong_answer_note', 1.8), ('two_faced_penny', 1.2), ('ceil', 1.5),
                  ('floor', 1.5), ('round', 1.5), ('tyrfing', 1.1), ('sealed_demon_sword', 1.1),
                  ('void_dagger', 1.1), ('severed_oath', 0.8), ('atropos', 0.8), ('angels_crown', 1.4),
                  ('utility_belt', 1.4), ('oral_steroids', 1.8), ('real_eyes', 1.8)):
    OVERRIDES.setdefault(key, {})['flat'] = half


def model(key, path):
    """(parts, materials, object mask) of one item, sculpted (sculpt.py)."""
    if key == 'kronos':
        ship = np.array(Image.open(path).convert('RGBA'))
        labels = np.zeros((32, 32), dtype=np.int64)
        info = []
        for i, s in enumerate(KRONOS.values(), 1):
            for c in s['colors']:
                labels[np.all(ship[..., :3] == np.array(c), axis=2) & (ship[..., 3] == 255)] = i
            info.append(dict(s))
        return sculpt(labels, info, KRONOS_MATS), KRONOS_MATS, labels > 0
    labels, info, mats, obj, detail = auto_spec(path, overrides=OVERRIDES.get(key))
    return sculpt(labels, info, mats, detail), mats, obj


def _fit(img, size):
    box = img.getbbox()
    if not box:
        return Image.new('RGBA', (size, size))
    part = img.crop(box)
    scale = size * 0.9 / max(part.width, part.height)
    part = part.resize((max(1, round(part.width * scale)), max(1, round(part.height * scale))), Image.LANCZOS)
    out = Image.new('RGBA', (size, size))
    out.alpha_composite(part, ((size - part.width) // 2, (size - part.height) // 2))
    return out


def view_of(parts, mats, yaw, pitch, size=256, ss=2):
    pts = np.vstack([p.v for p in parts])
    mid = (pts.min(axis=0) + pts.max(axis=0)) / 2
    span = float(np.linalg.norm(pts.max(axis=0) - pts.min(axis=0)))
    cam = Camera(yaw=yaw, pitch=pitch, dist=span * 3.2, fov=22, target=mid)
    return render(parts, mats, cam, size=size, zoom=0.62, ss=ss)


SPIN_FRAMES = 16  # one turn
SPIN_DELAY = 3    # updates per frame: a turn every 48 updates, 1.6 seconds


def spin_anm2(key, frames=SPIN_FRAMES, delay=SPIN_DELAY):
    """A looping 'Spin' animation over the strip, placed the way the vanilla
    pedestal places an item (pivot 16, 32 and 6 pixels up), so it can stand
    in for the pedestal's item picture."""
    rows = '\n'.join(
        f'          <Frame XPosition="0" YPosition="-6" XPivot="16" YPivot="32" XCrop="{k * 32}" YCrop="0" '
        f'Width="32" Height="32" XScale="100" YScale="100" Delay="{delay}" Visible="true" RedTint="255" '
        f'GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" '
        f'Rotation="0" Interpolated="false" />' for k in range(frames))
    return f'''<AnimatedActor>
  <Info CreatedBy="ConchBlessing" Version="20" Fps="30" />
  <Content>
    <Spritesheets>
      <Spritesheet Id="0" Path="{key}_spin.png" />
    </Spritesheets>
    <Layers>
      <Layer Id="0" Name="head" SpritesheetId="0" />
    </Layers>
    <Nulls />
    <Events />
  </Content>
  <Animations DefaultAnimation="Spin">
    <Animation Name="Spin" FrameNum="{frames * delay}" Loop="true">
      <RootAnimation>
        <Frame XPosition="0" YPosition="0" XScale="100" YScale="100" Delay="{frames * delay}" Visible="true" RedTint="255" GreenTint="255" BlueTint="255" AlphaTint="255" RedOffset="0" GreenOffset="0" BlueOffset="0" Rotation="0" Interpolated="false" />
      </RootAnimation>
      <LayerAnimations>
        <LayerAnimation LayerId="0" Visible="true">
{rows}
        </LayerAnimation>
      </LayerAnimations>
      <NullAnimations />
      <Triggers />
    </Animation>
  </Animations>
</AnimatedActor>
'''


def build(key, kind, path):
    """The model, its .glb, its April Fools icon (the model straight from the
    front, fully rendered: the user's choice A of 2026-11-11) and its spin (the
    model turning on the spot, for the pedestal)."""
    parts, mats, obj = model(key, path)
    MODELS.mkdir(parents=True, exist_ok=True)
    faces = export_glb(parts, mats, MODELS / f'{key}.glb')
    still = icon(front_view(parts, mats, size=256, ss=2), outline=False)
    pts = np.vstack([p.v for p in parts])
    centre = ((pts[:, 0].min() + pts[:, 0].max()) / 2, (pts[:, 1].min() + pts[:, 1].max()) / 2)
    frames = [icon(spin_view(parts, mats, 360.0 * k / SPIN_FRAMES, size=128, ss=2, centre=centre), outline=False)
              for k in range(SPIN_FRAMES)]
    strip = Image.new('RGBA', (32 * SPIN_FRAMES, 32))
    for k, f in enumerate(frames):
        strip.alpha_composite(f, (32 * k, 0))
    out_dir = ICONS / 'trinkets' if kind == 'trinkets' else ICONS
    out_dir.mkdir(parents=True, exist_ok=True)
    still.save(out_dir / f'{key}.png')
    strip.save(out_dir / f'{key}_spin.png')
    (out_dir / f'{key}_spin.anm2').write_text(spin_anm2(key), encoding='utf-8')
    three = _fit(view_of(parts, mats, -35, 22, size=200, ss=2), 128)
    return {'key': key, 'faces': faces, 'still': still, 'frames': frames, 'three': three, 'path': path,
            'parts': len(parts), 'mats': len(mats)}


def sheet(rows, per_row=2):
    S = 3
    tile_w = 32 * S * 2 + 8 * (32 * 2 + 4) + 128 + 40
    tile_h = max(32 * S, 128) + 24
    out = Image.new('RGBA', (per_row * (tile_w + 12) + 12, ((len(rows) + per_row - 1) // per_row) * (tile_h + 10) + 10),
                    (52, 45, 40, 255))
    d = ImageDraw.Draw(out)
    for i, r in enumerate(rows):
        x0 = 12 + (i % per_row) * (tile_w + 12)
        y0 = 10 + (i // per_row) * (tile_h + 10)
        shipped = Image.open(r['path']).convert('RGBA')
        out.alpha_composite(shipped.resize((32 * S, 32 * S), Image.NEAREST), (x0, y0))
        out.alpha_composite(r['still'].resize((32 * S, 32 * S), Image.NEAREST), (x0 + 32 * S + 6, y0))
        x = x0 + 2 * (32 * S + 6)
        for f in r['frames'][::2]:
            out.alpha_composite(f.resize((64, 64), Image.NEAREST), (x, y0 + 16))
            x += 68
        out.alpha_composite(r['three'], (x + 6, y0))
        d.text((x0, y0 + tile_h - 18), f"{r['key']}  {r['faces']} tris, {r['mats']} mats", fill=(225, 215, 195, 255))
    return out


def main(keys):
    catalogue = items()
    keys = keys or list(catalogue)
    rows = []
    started = time.time()
    for n, key in enumerate(keys, 1):
        kind, path = catalogue[key]
        r = build(key, kind, path)
        rows.append(r)
        print(f"[{n}/{len(keys)}] {key}: {r['faces']} triangles, {r['parts']} parts, {r['mats']} materials "
              f"({time.time() - started:.0f}s)", flush=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    sheet(rows).save(PREVIEW / 'models_sheet.png')
    print('sheet', PREVIEW / 'models_sheet.png')


if __name__ == '__main__':
    main(sys.argv[1:])
