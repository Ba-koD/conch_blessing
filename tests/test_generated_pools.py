"""Generated item pools never offer a hidden (console-only) item.

An item with no pool field would otherwise default to the treasure pool, which
let Inf D6 and Azure Dragon turn up on pedestals and in rotating choices.
"""
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from generate_xml import create_itempools_xml

ROOT = Path(__file__).resolve().parents[1]


class GeneratedPoolTests(unittest.TestCase):
    def test_shipped_pools_hold_no_hidden_item(self):
        items = ET.parse(ROOT / 'content/items.xml').getroot()
        hidden = {e.get('name') for e in items if e.get('hidden') == 'true'}
        self.assertIn('Inf D6', hidden)
        self.assertIn('Azure Dragon', hidden)
        pools = ET.parse(ROOT / 'content/itempools.xml').getroot()
        pooled = {i.get('Name') for pool in pools for i in pool}
        self.assertEqual(hidden & pooled, set())

    def test_generator_skips_hidden_items_even_without_a_pool_field(self):
        out = ROOT / '.tmp' / 'test_generated_pools.xml'
        out.parent.mkdir(exist_ok=True)
        create_itempools_xml({
            'SHOWN': {'name': 'Shown', 'type': 'passive'},
            'CONSOLE': {'name': 'Console', 'type': 'active', 'hidden': True},
            'LISTED': {'name': 'Listed', 'type': 'passive', 'hidden': True, 'pools': ['ROOM_SHOP']},
        }, str(out))
        pooled = {i.get('Name') for pool in ET.parse(out).getroot() for i in pool}
        self.assertEqual(pooled, {'Shown'})


if __name__ == '__main__':
    unittest.main()
