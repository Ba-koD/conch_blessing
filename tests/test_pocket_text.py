"""Cards and runes show their pickup/use banner in the mod's language.

Production scripts/conch_blessing_pockets.lua with doubles for the locale data,
the HUD and REPENTOGON's MC_PRE_ITEM_TEXT_DISPLAY. The banner's look in game and
the engine's call order are not proven here.
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class PocketTextTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r"""
            package.path = root .. '/?.lua;' .. package.path
            package.loaded['scripts.items.cards.thurisaz'] = true
            package.loaded['scripts.items.cards.conch_ticket'] = true
            lang = 'kr'
            package.loaded['scripts.conch_blessing_config'] = { GetCurrentLanguage = function() return lang end }
            ModCallbacks = { MC_PRE_ITEM_TEXT_DISPLAY = 1484 }
            callbacks, shown, errors = {}, {}, {}
            local text = {
                THURISAZ = { name = { en = 'Thurisaz', kr = '투리사즈', urimal = '투리사즈' },
                             description = { en = 'Devour', kr = '포식', urimal = '집어삼킴' } },
                CONCH_TICKET = { name = { en = 'Conch Ticket', kr = '소라 예약권', urimal = '소라 예약권' },
                                 description = { en = 'Reserved', kr = '예약됨', urimal = '미리 잡아 둠' } },
            }
            ConchBlessing = {
                Locale = { applyPocketData = function(data)
                    for key, entry in pairs(data) do entry.name = text[key].name; entry.description = text[key].description end
                end },
                printError = function(message) errors[#errors + 1] = message end,
            }
            function ConchBlessing:AddCallback(id, fn) callbacks[id] = fn end
            Isaac = { GetCardIdByName = function(name) return name == 'Thurisaz' and 98 or 99 end }
            hud = {}
            function hud:ShowItemText(name, description)
                -- The engine raises the callback again for our own banner.
                local again = callbacks[1484](nil, name, description, false, false)
                shown[#shown + 1] = { name = name, description = description, again = again }
            end
            function Game() return { GetHUD = function() return hud end } end
            require('scripts.conch_blessing_pockets')
            banner = callbacks[1484]
        """)

    def test_korean_and_urimal_replace_the_english_banner(self):
        self.lua.execute("""
            assert(banner(nil, 'Thurisaz', 'Devour', false, false) == false, 'the English banner is cancelled')
            assert(#shown == 1 and shown[1].name == '투리사즈' and shown[1].description == '포식')
            assert(shown[1].again == nil, 'our own banner passes through')
            lang = 'urimal'
            assert(banner(nil, 'Conch Ticket', 'Reserved', false, false) == false)
            assert(shown[2].name == '소라 예약권' and shown[2].description == '미리 잡아 둠')
        """)

    def test_english_other_banners_and_sticky_text_pass_through(self):
        self.lua.execute("""
            lang = 'en'
            assert(banner(nil, 'Thurisaz', 'Devour', false, false) == nil, 'English stays as the engine shows it')
            lang = 'kr'
            assert(banner(nil, 'Sad Onion', 'Tears up', false, false) == nil)
            assert(banner(nil, 'Thurisaz', 'Devour', true, false) == nil, 'sticky text is not a pickup banner')
            assert(banner(nil, 'Thurisaz', 'Devour', false, true) == nil, 'nor is a curse display')
            assert(#shown == 0 and #errors == 0)
        """)

    def test_a_failing_hud_keeps_the_english_banner(self):
        self.lua.execute("""
            function hud:ShowItemText() error('no HUD yet') end
            assert(banner(nil, 'Thurisaz', 'Devour', false, false) == nil, 'the engine banner is not cancelled')
            assert(#errors == 1)
        """)


if __name__ == '__main__':
    unittest.main()
