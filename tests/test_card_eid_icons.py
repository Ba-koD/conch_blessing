"""Our cards' EID icons sit where their pocket art really is.

EID shows a blank card for a modded card with no "Card<id>" icon. Each of ours
registers its floor pickup's HUDSmall frame (the pocket-slot art at half size),
placed by scripts/items/cards/eid_icons.lua, which generate_pocket_assets.py
measures from the art. The look in EID, Inventory Descriptions and Item Pool
Manager is checked in game, not here.
"""
from pathlib import Path
import importlib.util
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(ROOT))
import lua_data  # noqa: E402


def generator():
    spec = importlib.util.spec_from_file_location('pocket_assets', ROOT / 'generate_pocket_assets.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CardEidIconTests(unittest.TestCase):
    def test_every_card_has_a_placement_measured_from_its_art(self):
        gen = generator()
        icons = lua_data.load('scripts/items/cards/eid_icons.lua')
        definitions = lua_data.load('scripts/items/cards/definitions.lua')
        self.assertEqual(set(icons), set(definitions))
        for key, card in definitions.items():
            sheet = Image.open(ROOT / 'resources/gfx' / card['gfx']).convert('RGBA')
            hud = sheet.crop((gen.HUD_X, 0, gen.HUD_X + gen.FRAME, gen.FRAME))
            self.assertEqual(icons[key], gen.eid_icon(hud), key)
            # the art starts at the cursor and just under the line top
            self.assertGreaterEqual(icons[key]['left'], 0)
            self.assertLessEqual(icons[key]['width'], 16)

    def test_every_pickup_anm2_has_the_hudsmall_frame(self):
        definitions = lua_data.load('scripts/items/cards/definitions.lua')
        for key, card in definitions.items():
            anm2 = (ROOT / 'resources/gfx' / card['anm2']).read_text(encoding='utf-8')
            self.assertIn('Animation Name="HUDSmall"', anm2, key)


if __name__ == '__main__':
    unittest.main()
