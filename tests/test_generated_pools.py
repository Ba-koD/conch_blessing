"""Generated item pools never offer a hidden (console-only) item.

An item with no pool field would otherwise default to the treasure pool, which
let Inf D6 and Azure Dragon turn up on pedestals and in rotating choices.
"""
import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from generate_xml import create_itempools_xml, id_order, parse_lua_file

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


class GeneratedIdOrderTests(unittest.TestCase):
    """WIP previews are numbered last in their ID space; the registry keeps its own order."""

    def test_wip_rows_follow_finished_rows_in_each_id_space(self):
        ordered = id_order({
            'A': {'type': 'passive'}, 'WIP1': {'type': 'passive', 'wip': True}, 'B': {'type': 'active'},
            'WIP2': {'type': 'passive', 'wip': True}, 'C': {'type': 'passive'}, 'F': {'type': 'familiar'},
            'T': {'type': 'trinket'}, 'TWIP': {'type': 'trinket', 'wip': True}, 'U': {'type': 'trinket'},
        })
        self.assertEqual(list(ordered), ['A', 'B', 'C', 'F', 'WIP1', 'WIP2', 'T', 'U', 'TWIP'])

    def test_shipped_ids_put_rat_and_dragon_before_the_familiars_and_the_previews_last(self):
        registry = parse_lua_file(str(ROOT / 'scripts/conch_blessing_items.lua'))
        source = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        keys = re.findall(r'^    ([A-Z_0-9]+) = \{', source, re.M)
        zodiac = ['RAT', 'OX', 'TIGER', 'RABBIT', 'DRAGON', 'SNAKE', 'HORSE', 'GOAT', 'MONKEY', 'CHICKEN', 'DOG', 'PIG']
        start = keys.index('RAT')
        self.assertEqual(keys[start:start + 12], zodiac, 'the registry keeps 자 … 해 together')
        self.assertEqual(keys[start + 12], 'TIME_MONEY')
        rows = [(e.tag, e.get('name')) for e in ET.parse(ROOT / 'content/items.xml').getroot()]
        names = [name for _, name in rows]
        i = names.index('Rat')
        self.assertEqual(names[i:i + 4], ['Rat', 'Dragon', 'Time = Money', 'Azure Dragon'])
        wip = ['Ox (WIP)', 'Tiger (WIP)', 'Rabbit (WIP)', 'Snake (WIP)', 'Horse (WIP)', 'Goat (WIP)',
               'Monkey (WIP)', 'Chicken (WIP)', 'Dog (WIP)', 'Pig (WIP)']
        self.assertEqual(names[i + 4:i + 14], wip)
        self.assertEqual(rows[i + 14][0], 'trinket')
        self.assertTrue(all(tag != 'trinket' for tag, _ in rows[:i + 14]))
        self.assertEqual([info.get('name') for info in registry.values()], names)


if __name__ == '__main__':
    unittest.main()
