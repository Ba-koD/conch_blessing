"""Build small presentation-only ANM2s referencing the game's own textures.

No vanilla texture is copied into the mod. The sole authored texture is a white
pixel used for lines, rain and clock marks. Run from any working directory.
"""
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parent
DEST = ROOT / 'resources/gfx/effects'


def actor(name, sheet, frames):
    root = ET.Element('AnimatedActor')
    ET.SubElement(root, 'Info', CreatedBy='ConchBlessing', Version='20', Fps='30')
    content = ET.SubElement(root, 'Content')
    ET.SubElement(ET.SubElement(content, 'Spritesheets'), 'Spritesheet', Id='0', Path=sheet)
    ET.SubElement(ET.SubElement(content, 'Layers'), 'Layer', Id='0', Name='Visual', SpritesheetId='0')
    ET.SubElement(content, 'Nulls')
    ET.SubElement(content, 'Events')
    animations = ET.SubElement(root, 'Animations', DefaultAnimation='Idle')
    animation = ET.SubElement(animations, 'Animation', Name='Idle', FrameNum=str(len(frames)), Loop='true')
    common = dict(XPosition='0', YPosition='0', XScale='100', YScale='100',
                  Delay='1', Visible='true', RedTint='255', GreenTint='255', BlueTint='255',
                  AlphaTint='255', RedOffset='0', GreenOffset='0', BlueOffset='0',
                  Rotation='0', Interpolated='false')
    ET.SubElement(ET.SubElement(animation, 'RootAnimation'), 'Frame', **{**common, 'Delay': str(len(frames))})
    layer = ET.SubElement(ET.SubElement(animation, 'LayerAnimations'), 'LayerAnimation', LayerId='0', Visible='true')
    for x, y, w, h, px, py in frames:
        ET.SubElement(layer, 'Frame', **common, XCrop=str(x), YCrop=str(y), Width=str(w),
                      Height=str(h), XPivot=str(px), YPivot=str(py))
    ET.SubElement(animation, 'NullAnimations')
    ET.SubElement(animation, 'Triggers')
    ET.indent(root, space='  ')
    (DEST / f'conch_upgrade_{name}.anm2').write_text(ET.tostring(root, encoding='unicode') + '\n', encoding='utf-8')


if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    Image.new('RGBA', (1, 1), (255, 255, 255, 255)).save(DEST / 'conch_upgrade_pixel.png')
    actor('pixel', 'conch_upgrade_pixel.png', [(0, 0, 1, 1, 0, 0)])
    # Replaced with ItemConfig.GfxFileName before drawing; placeholder is owned art.
    actor('icon', '../items/collectibles/void_dagger.png', [(0, 0, 32, 32, 16, 16)])
    actor('smoke', 'effect_088_darksmoke.png', [(0, 0, 48, 48, 24, 24)])
    for name, sheet in [('fire', 'effect_005_fire_red.png'), ('ice', 'effect_005_fire_blue.png')]:
        actor(name, sheet, [(i % 5 * 48, i // 5 * 48, 48, 48, 24, 40) for i in range(6)])
    actor('floor', '../backdrop/14_the drowned caves.png', [(96, 64, 40, 40, 20, 20)])
