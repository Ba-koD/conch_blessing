"""Custom entity XML survives generation without changing familiar identity."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

import generate_xml
import lua_data


class EntityDefinitionsTests(unittest.TestCase):
    def test_marker_and_familiar_survive_two_generations(self):
        definitions = lua_data.load('scripts/entities/definitions.lua')
        items = {'TIME_MONEY': {'type': 'familiar', 'name': 'Time = Money',
                               'entity': {'variant': 777}, 'anm2': 'time_money.anm2'}}
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            path = Path(folder) / 'entities2.xml'
            generate_xml.create_entities2_xml(items, str(path), definitions, {})
            first = path.read_bytes()
            generate_xml.create_entities2_xml(items, str(path), definitions, {})
            self.assertEqual(first, path.read_bytes())
            rows = ET.parse(path).getroot().findall('entity')
            self.assertEqual(len(rows), 8)
            self.assertEqual((rows[0].get('id'), rows[0].get('variant')), ('3', '777'))
            marker = rows[1]
            ox = rows[2]
            self.assertEqual((ox.get('name'), ox.get('id')), (definitions['OX']['name'], '1000'))
            self.assertEqual(ox.get('variant'), '7783', 'an effect without a variant is left at 0')
            self.assertEqual(ox.get('anm2path'), 'effects/conch_ox.anm2')
            self.assertTrue((Path('resources/gfx') / ox.get('anm2path')).is_file())
            furrow = rows[3]
            self.assertEqual((furrow.get('name'), furrow.get('variant'), furrow.get('shadowSize')),
                             (definitions['OX_FURROW']['name'], '7784', '0'))
            rice = rows[4]
            self.assertEqual((rice.get('name'), rice.get('variant'), rice.get('shadowSize')),
                             (definitions['OX_RICE']['name'], '7785', '0'))
            self.assertTrue((Path('resources/gfx') / rice.get('anm2path')).is_file())
            # 장승's statues and the earth in front of them (2026-11-10).
            statue, ground = rows[5], rows[6]
            self.assertEqual((statue.get('name'), statue.get('variant')), (definitions['JANGSEUNG']['name'], '7786'))
            self.assertEqual((ground.get('name'), ground.get('variant'), ground.get('shadowSize')),
                             (definitions['JANGSEUNG_GROUND']['name'], '7787', '0'))
            for row in (statue, ground):
                self.assertTrue((Path('resources/gfx') / row.get('anm2path')).is_file())
            # 묘's rabbit tracks into its hidden rock (2026-11-10).
            tracks = rows[7]
            self.assertEqual((tracks.get('name'), tracks.get('variant'), tracks.get('shadowSize')),
                             (definitions['RABBIT_TRACKS']['name'], '7788', '0'))
            self.assertTrue((Path('resources/gfx') / tracks.get('anm2path')).is_file())
            self.assertEqual(marker.get('id'), '2')
            self.assertEqual(marker.get('name'), definitions['NEGLECT_TEAR']['name'])
            self.assertNotIn('variant', marker.attrib)  # engine allocates it
            self.assertEqual(marker.get('collisionRadius'), '0')
            self.assertEqual(marker.get('shadowSize'), '0')

    def test_rejects_ambiguous_or_invalid_definitions(self):
        good = lua_data.load('scripts/entities/definitions.lua')['NEGLECT_TEAR']
        invalid = [dict(good, id=0), dict(good, name='vanilla'),
                   dict(good, mystery=1), dict(good, anm2path='../bad.anm2')]
        with tempfile.TemporaryDirectory() as folder:
            path = str(Path(folder) / 'entities2.xml')
            for definition in invalid:
                with self.assertRaises(ValueError):
                    generate_xml.create_entities2_xml({}, path, {'BAD': definition})
            with self.assertRaises(ValueError):
                generate_xml.create_entities2_xml({}, path, {'A': good, 'B': good})


if __name__ == '__main__':
    unittest.main()
