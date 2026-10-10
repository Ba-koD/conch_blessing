"""Native costume identity follows generated item IDs, never a hardcoded ID."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

import generate_xml

ROOT = Path(__file__).resolve().parents[1]
COSTUME = 'characters/conch_neglect_toggle.anm2'


class ItemCostumeTests(unittest.TestCase):
    def test_registry_and_committed_costume_binding_match(self):
        with contextlib.redirect_stdout(io.StringIO()):
            items = generate_xml.parse_lua_file(str(ROOT / 'scripts/conch_blessing_items.lua'))
        self.assertEqual(items['HEMISPATIAL_NEGLECT']['costume'], COSTUME)
        self.assertEqual(items['HEMISPATIAL_NEGLECT']['costume_priority'], -1)
        native = ET.parse(ROOT / 'content/items.xml').getroot()
        item = next(row for row in native if row.get('name') == 'Hemispatial Neglect')
        costumes = ET.parse(ROOT / 'content/costumes2.xml').getroot()
        self.assertEqual(costumes.get('anm2root'), 'gfx/')
        row = next(row for row in costumes if row.get('anm2path') == COSTUME)
        self.assertEqual((row.get('id'), row.get('type')), (item.get('id'), item.tag))
        self.assertEqual(row.get('priority'), '-1')

    def test_reordering_and_multiple_item_types_keep_exact_local_binding(self):
        types = ['trinket', 'passive', 'familiar', 'active']
        for order in (types, list(reversed(types))):
            items = {'FIRST': {'type': 'passive', 'name': 'No costume'}}
            items.update({kind: {'type': kind, 'name': kind, 'costume': COSTUME} for kind in order})
            with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
                itemfile, costumes = Path(folder) / 'items.xml', Path(folder) / 'costumes2.xml'
                generate_xml.create_items_xml(items, str(itemfile))
                generate_xml.create_costumes_xml(items, str(costumes))
                first = costumes.read_bytes()
                generate_xml.create_costumes_xml(items, str(costumes))
                self.assertEqual(first, costumes.read_bytes())
                for item, costume in zip(list(ET.parse(itemfile).getroot())[1:], ET.parse(costumes).getroot()):
                    self.assertEqual((item.get('id'), item.tag), (costume.get('id'), costume.get('type')))

    def test_invalid_binding_fails_before_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'costumes2.xml'
            for path in ('characters/missing.anm2', '../outside.anm2', 'characters/../file.anm2',
                         'characters\\file.anm2', 'characters/bad.png', 42):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    generate_xml.create_costumes_xml({'TEST': {'costume': path}}, str(output))
            self.assertFalse(output.exists())

    def test_control_costume_cannot_cover_or_tint_native_layers(self):
        from PIL import Image
        root = ET.parse(ROOT / 'resources/gfx' / COSTUME).getroot()
        layers = root.findall('./Content/Layers/Layer')
        sheets = root.findall('./Content/Spritesheets/Spritesheet')
        self.assertEqual(len(layers), 1)
        self.assertEqual(layers[0].get('Name'), 'extra')
        self.assertEqual(layers[0].get('SpritesheetId'), sheets[0].get('Id'))
        with Image.open(ROOT / 'resources/gfx/characters' / sheets[0].get('Path')) as image:
            self.assertEqual(image.mode, 'RGBA')
            self.assertIsNone(image.getchannel('A').getbbox(), 'control texture must be fully transparent')
        names = {a.get('Name') for a in root.findall('./Animations/Animation')}
        self.assertEqual(names, {'HeadDown', 'HeadUp', 'HeadLeft', 'HeadRight'})
        for anim in root.findall('./Animations/Animation'):
            tracks = anim.findall('./LayerAnimations/LayerAnimation')
            self.assertEqual(len(tracks), 1)
            self.assertEqual(tracks[0].get('LayerId'), layers[0].get('Id'))
            self.assertEqual(anim.find('./RootAnimation/Frame').get('AlphaTint'), '255')

    def test_native_crash_regression_rejects_layerless_and_broken_costumes(self):
        source = ROOT / 'resources/gfx' / COSTUME
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test.anm2'
            for broken in ('layers', 'sheet', 'reference', 'track', 'duration', 'default'):
                with self.subTest(broken=broken):
                    tree = ET.parse(source)
                    sheet = tree.find('./Content/Spritesheets/Spritesheet')
                    sheet.set('Path', str((source.parent / sheet.get('Path')).resolve()))
                    if broken == 'layers': tree.find('./Content/Layers').clear()
                    elif broken == 'sheet': sheet.set('Path', 'missing.png')
                    elif broken == 'reference': tree.find('./Content/Layers/Layer').set('SpritesheetId', '99')
                    elif broken == 'track': tree.find('./Animations/Animation/LayerAnimations').clear()
                    elif broken == 'duration': tree.find('./Animations/Animation/LayerAnimations/LayerAnimation/Frame').set('Delay', '0')
                    elif broken == 'default': tree.find('./Animations').set('DefaultAnimation', 'missing')
                    tree.write(path)
                    with self.assertRaises(ValueError):
                        generate_xml.validate_costume_anm2(str(path))


if __name__ == '__main__':
    unittest.main()
