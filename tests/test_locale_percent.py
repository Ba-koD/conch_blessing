"""Urimal percentage display through the shipped locale/config modules.

Inputs are percentage points, not fractions. Date changes are confined to each
isolated Lua runtime; these checks do not modify the computer's calendar.
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

import test_kronos_room_effects as kronos_tests


ROOT = Path(__file__).resolve().parents[1]


class LocalePercentTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r"""
            package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
            today={year=2026,month=10,day=8}
            os.date=function(format) assert(format=='*t');return today end
            Options={Language='kr'}
            ConchBlessing={Config={language='auto'}}
            function ConchBlessing.printError(message) error(message) end
            Config=require('scripts.conch_blessing_config')
            Locale=require('scripts.locale.init')
        """)
        self.locale = self.lua.globals().Locale

    def test_urimal_units_and_boundaries_have_independent_expected_strings(self):
        cases = [
            (0, "0할"),
            (1, "1푼"),
            (5, "5푼"),
            (10, "1할"),
            (25, "2할 5푼"),
            (37.5, "3할 7푼 5리"),
            (50, "5할"),
            (75, "7할 5푼"),
            (99.99, "9할 9푼 9리 9모"),
            (100, "10할"),
            (125, "12할 5푼"),
            (0.25, "2리 5모"),
            (0.01, "1모"),
        ]
        for value, expected in cases:
            with self.subTest(value=value):
                self.assertEqual(self.locale.formatPercent(value, "urimal"), expected)

    def test_rounding_uses_one_hundredth_of_a_percentage_point_and_carries(self):
        cases = [
            (0.004, "0할"),
            (0.005, "1모"),
            (0.014, "1모"),
            (0.015, "2모"),
            (1.005, "1푼 1모"),
            (9.995, "1할"),
            (0.145, "1리 5모"),
            (9.994, "9푼 9리 9모"),
            (9.999, "1할"),
            (99.999, "10할"),
        ]
        for value, expected in cases:
            with self.subTest(value=value):
                self.assertEqual(self.locale.formatPercent(value, "urimal"), expected)

    def test_negative_values_put_one_sign_before_the_largest_nonzero_unit(self):
        for value, expected in [(-25, "-2할 5푼"), (-0.25, "-2리 5모"),
                                (-0.01, "-1모"), (-9.999, "-1할")]:
            with self.subTest(value=value):
                self.assertEqual(self.locale.formatPercent(value, "urimal"), expected)

    def test_english_and_korean_preserve_numeric_text_and_percent_sign(self):
        for lang in ("en", "kr"):
            for value, expected in [(0, "0%"), (50, "50%"), (37.5, "37.5%"),
                                    (125, "125%"), ("5.0", "5.0%"),
                                    ("05.00", "05.00%"), (-25, "-25%")]:
                with self.subTest(lang=lang, value=value):
                    self.assertEqual(self.locale.formatPercent(value, lang), expected)
        self.assertEqual(self.locale.formatPercent("5.0", "urimal"), "5푼")

    def test_invalid_input_falls_back_without_rounding_errors(self):
        # Lua's spelling of NaN varies by runtime, so compare with the previous
        # literal tostring-plus-percent contract instead of choosing one spelling.
        self.lua.execute(r"""
            for _,lang in ipairs({'en','kr','urimal'}) do
                for _,value in ipairs({'not-a-number',false,0/0,math.huge,-math.huge}) do
                    assert(Locale.formatPercent(value,lang)==tostring(value)..'%',
                        'invalid value did not preserve its literal percentage form')
                end
                assert(Locale.formatPercent(nil,lang)=='nil%')
            end
        """)

    def test_automatic_calendar_switch_and_recovery_leave_preference_unchanged(self):
        self.lua.execute(r"""
            assert(Config.GetSelectedLanguage()=='auto')
            assert(Locale.formatPercent(25)=='25%')
            today.day=9
            assert(Locale.formatPercent(25)=='2할 5푼')
            assert(Config.GetSelectedLanguage()=='auto')
            today.day=10
            assert(Locale.formatPercent(25)=='25%')
            assert(Config.GetSelectedLanguage()=='auto')
        """)

    def test_manual_urimal_persists_and_en_kr_selection_recovers(self):
        self.lua.execute(r"""
            assert(Config.SetLanguage('urimal'))
            assert(Locale.formatPercent(50)=='5할')
            today.day=9;assert(Locale.formatPercent(50)=='5할')
            today.day=10;assert(Locale.formatPercent(50)=='5할')
            assert(Config.GetSelectedLanguage()=='urimal')
            assert(Config.SetLanguage('en'));today.day=9
            assert(Locale.formatPercent(50)=='50%')
            assert(Config.SetLanguage('kr'))
            assert(Locale.formatPercent(50)=='5할')
            assert(Config.GetSelectedLanguage()=='kr')
            today.day=10;assert(Locale.formatPercent(50)=='50%')
            assert(Config.GetSelectedLanguage()=='kr')
        """)

    def test_explicit_language_beats_implicit_calendar_selection(self):
        self.lua.execute(r"""
            today.day=9
            assert(Config.GetCurrentLanguage()=='urimal')
            assert(Locale.formatPercent('5.0','en')=='5.0%')
            assert(Locale.formatPercent('5.0','kr')=='5.0%')
            assert(Locale.formatPercent('5.0','urimal')=='5푼')
        """)

    def test_all_four_ui_templates_consume_one_formatted_percentage(self):
        expected = {
            "en": {
                "ui.kronos.transfer_pretty_fly": "Projectile ignore chance +5%",
                "ui.injectable_steroids.death_chance": "#{{ColorRed}}Current Death Chance: 5%{{CR}}",
                "ui.void_dagger.proc_chance": "#{{ColorYellow}}Current Proc Chance: 5%{{CR}}",
                "ui.void_dagger.proc_detail": " (Base: 5%, {{Luck}}x1.5)",
            },
            "kr": {
                "ui.kronos.transfer_pretty_fly": "탄환 무시 확률 +5%",
                "ui.injectable_steroids.death_chance": "#{{ColorRed}}현재 즉사 확률: 5%{{CR}}",
                "ui.void_dagger.proc_chance": "#{{ColorYellow}}현재 발동 확률: 5%{{CR}}",
                "ui.void_dagger.proc_detail": " (기본: 5%, {{Luck}}x1.5)",
            },
            "urimal": {
                "ui.kronos.transfer_pretty_fly": "탄알에 다치지 않을 확률 +5푼",
                "ui.injectable_steroids.death_chance": "#{{ColorRed}}곧바로 죽을 확률: 5푼{{CR}}",
                "ui.void_dagger.proc_chance": "#{{ColorYellow}}지금 나타날 확률: 5푼{{CR}}",
                "ui.void_dagger.proc_detail": " (기본: 5푼, {{Luck}}x1.5)",
            },
        }
        for lang, rows in expected.items():
            for path, text in rows.items():
                with self.subTest(lang=lang, path=path):
                    percentage = self.locale.formatPercent(5, lang)
                    arguments = (percentage, "1.5") if path.endswith("proc_detail") else (percentage,)
                    self.assertEqual(self.locale.textIn(lang, path, *arguments), text)
        self.assertEqual(len(self.locale.problems), 0)

    def test_current_ui_text_uses_the_same_effective_language_as_its_value(self):
        self.lua.execute(r"""
            today.day=9
            local text=Locale.text('ui.injectable_steroids.death_chance',Locale.formatPercent(37.5))
            assert(text=='#{{ColorRed}}곧바로 죽을 확률: 3할 7푼 5리{{CR}}')
            today.day=10
            text=Locale.text('ui.injectable_steroids.death_chance',Locale.formatPercent(37.5))
            assert(text=='#{{ColorRed}}현재 즉사 확률: 37.5%{{CR}}')
        """)

    def test_kronos_live_block_token_uses_real_locale_formatter_and_chance_cap(self):
        # Reuse the production Kronos callbacks fixture, then install the actual
        # config and locale modules. Expected values are independent of both the
        # formatter and Kronos's exported constants: each Halo contributes 1%.
        for count, percent, urimal in [(0, "0%", "0할"), (1, "1%", "1푼"),
                                       (50, "50%", "5할"), (100, "100%", "10할"),
                                       (125, "100%", "10할")]:
            fixture = kronos_tests.KronosRoomEffectsTests()
            fixture.setUp()
            lua = fixture.lua
            lua.execute(r"""
                today={year=2026,month=10,day=8}
                os.date=function(format) assert(format=='*t');return today end
                Options={Language='kr'}
                ConchBlessing.Config={language='en'}
                Config=require('scripts.conch_blessing_config')
                ConchBlessing.Locale=require('scripts.locale.init')
            """)
            if count:
                lua.globals().absorb("HALO_OF_FLIES", count)
            token = lua.globals().ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK
            for lang, expected in [("en", percent), ("kr", percent), ("urimal", urimal)]:
                with self.subTest(count=count, lang=lang):
                    self.assertTrue(lua.globals().Config.SetLanguage(lang))
                    self.assertEqual(token(lua.globals().player), expected)
            # A single live token follows the effective holiday language and
            # recovers without altering the user's saved Korean preference.
            lua.globals().Config.SetLanguage("kr")
            lua.globals().today.day = 9
            self.assertEqual(token(lua.globals().player), urimal)
            self.assertEqual(lua.globals().Config.GetSelectedLanguage(), "kr")
            lua.globals().today.day = 10
            self.assertEqual(token(lua.globals().player), percent)


if __name__ == '__main__':
    unittest.main()
