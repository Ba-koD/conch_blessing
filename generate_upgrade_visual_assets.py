"""Build presentation-only ANM2s from native textures and authored effect art.

No vanilla texture is copied into the mod. Mouth and clock PNGs are original
authored inputs; this generator never rewrites them. Run from any working directory.
"""
from pathlib import Path
import math
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parent
DEST = ROOT / 'resources/gfx/effects'
MAW_CROP = (114, 104, 1146, 942)
MAW_LOGICAL_WIDTH = 64
CLOCK_PARTS = {
    # Atlas rectangles and pivots keep the centre open and each hand separate.
    'rim': ((56, 40, 590, 664, 295, 371), 100 * 42 / 584),
    'minute': ((292, 778, 104, 416, 52, 366), 100 * 15 / 360),
    'hour': ((852, 920, 116, 274, 58, 224), 100 * 11 / 218),
}


def actor(name, sheet, frames, strips=False, scale=100):
    root = ET.Element('AnimatedActor')
    ET.SubElement(root, 'Info', CreatedBy='ConchBlessing', Version='20', Fps='30')
    content = ET.SubElement(root, 'Content')
    ET.SubElement(ET.SubElement(content, 'Spritesheets'), 'Spritesheet', Id='0', Path=sheet)
    layers = ET.SubElement(content, 'Layers')
    for i in range(len(frames) if strips else 1):
        ET.SubElement(layers, 'Layer', Id=str(i), Name=f'Visual{i}' if strips else 'Visual', SpritesheetId='0')
    ET.SubElement(content, 'Nulls')
    ET.SubElement(content, 'Events')
    animations = ET.SubElement(root, 'Animations', DefaultAnimation='Idle')
    count = 1 if strips else len(frames)
    animation = ET.SubElement(animations, 'Animation', Name='Idle', FrameNum=str(count), Loop='true')
    common = dict(XPosition='0', YPosition='0', XScale='100', YScale='100',
                  Delay='1', Visible='true', RedTint='255', GreenTint='255', BlueTint='255',
                  AlphaTint='255', RedOffset='0', GreenOffset='0', BlueOffset='0',
                  Rotation='0', Interpolated='false')
    ET.SubElement(ET.SubElement(animation, 'RootAnimation'), 'Frame', **{**common, 'Delay': str(count)})
    animations = ET.SubElement(animation, 'LayerAnimations')
    layer = None
    for i, (x, y, w, h, px, py) in enumerate(frames):
        if strips or layer is None:
            layer = ET.SubElement(animations, 'LayerAnimation', LayerId=str(i if strips else 0), Visible='true')
        ET.SubElement(layer, 'Frame', **{**common, 'XScale': str(scale), 'YScale': str(scale)}, XCrop=str(x), YCrop=str(y), Width=str(w),
                      Height=str(h), XPivot=str(px), YPivot=str(py))
    ET.SubElement(animation, 'NullAnimations')
    ET.SubElement(animation, 'Triggers')
    ET.indent(root, space='  ')
    (DEST / f'conch_upgrade_{name}.anm2').write_text(ET.tostring(root, encoding='unicode') + '\n', encoding='utf-8')


def mouth_frames(part):
    # Trim transparent padding through ANM2 coordinates, leaving the PNG and
    # its alpha intact. Splitting in the dark cavity keeps teeth on rigid jaws.
    x, y, w, h = MAW_CROP
    if part == 'all': return [(x, y, w, h, w // 2, h // 2)]
    # The soft outer corners fold with the bite; separating them prevents the
    # rigid tooth rows from leaving detached vertical pieces at either edge.
    corner = round(w * 8 / MAW_LOGICAL_WIDTH)
    if part == 'sides':
        return [(x, y, corner, h, w//2, h//2),
                (x+w-corner, y, corner, h, corner-w//2, h//2)]
    image = Image.open(DEST / 'conch_upgrade_maw.png').convert('RGBA')
    spans = []
    # A half-image would put the opaque throat IN FRONT of the heart. Trace
    # tooth/gum edges into narrow source rectangles instead. This is ANM2
    # geometry, not a destructive alpha edit or a second texture copy.
    for column in range(8, MAW_LOGICAL_WIDTH - 8):
        left = round(column * w / MAW_LOGICAL_WIDTH)
        right = round((column + 1) * w / MAW_LOGICAL_WIDTH)
        scan = range(0, h // 2) if part == 'upper' else range(h // 2, h)
        ink = [row for row in scan if any(max(image.getpixel((x + px, y + row))[:3]) >= 90
               and image.getpixel((x + px, y + row))[3] >= 128
               for px in range(left, right, 4))]
        if not ink: continue
        edge = min(h // 2, max(ink) + 10) if part == 'upper' else max(h // 2, min(ink) - 10)
        top, bottom = (0, edge) if part == 'upper' else (edge, h)
        if spans and spans[-1][1:3] == [top, bottom] and spans[-1][3] == left:
            spans[-1][3] = right
        else:
            spans.append([left, top, bottom, right])
    return [(x+left, y+top, right-left, bottom-top, w//2-left, h//2-top)
            for left, top, bottom, right in spans]


def spotlight_mask():
    """Analytic alpha aperture, like the white line primitive, not authored art."""
    mask = Image.new('RGBA', (160, 160))
    pixels = []
    for y in range(160):
        for x in range(160):
            radius = math.hypot(x + 0.5 - 80, y + 0.5 - 80)
            p = max(0, min(1, (radius - 24) / 52))
            pixels.append((255, 255, 255, round(255 * p * p * (3 - 2 * p))))
    mask.putdata(pixels)
    mask.save(DEST / 'conch_upgrade_spotlight.png')
    actor('spotlight', 'conch_upgrade_spotlight.png', [(0, 0, 160, 160, 80, 80)])


if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    Image.new('RGBA', (1, 1), (255, 255, 255, 255)).save(DEST / 'conch_upgrade_pixel.png')
    actor('pixel', 'conch_upgrade_pixel.png', [(0, 0, 1, 1, 0, 0)])
    spotlight_mask()
    # Replaced with ItemConfig.GfxFileName before drawing; placeholder is owned art.
    actor('icon', '../items/collectibles/void_dagger.png', [(0, 0, 32, 32, 16, 16)])
    actor('smoke', 'effect_088_darksmoke.png', [(0, 0, 48, 48, 24, 24)])
    for name, sheet in [('fire', 'effect_005_fire_red.png'), ('ice', 'effect_005_fire_blue.png')]:
        actor(name, sheet, [(i % 5 * 48, i // 5 * 48, 48, 48, 24, 40) for i in range(6)])
    actor('floor', '../backdrop/14_the drowned caves.png', [(96, 64, 40, 40, 20, 20)])
    actor('halo', '../items/collectibles/collectibles_101_thehalo.png', [(0, 0, 32, 32, 16, 16)])
    for part, (frame, scale) in CLOCK_PARTS.items():
        actor('clock_' + part, 'conch_upgrade_clock.png', [frame], scale=scale)
    for part in ('all', 'upper', 'lower', 'sides'):
        actor('maw_' + part, 'conch_upgrade_maw.png', mouth_frames(part), strips=True,
              scale=100 * MAW_LOGICAL_WIDTH / MAW_CROP[2])
