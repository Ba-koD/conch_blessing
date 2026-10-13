"""The MCM sound settings (user, 2026-10-13) reach every sound this mod plays.

scripts/lib/sound_volume.lua scales each cue by the overall setting, and 진's
rain by the rain setting on top; missing or broken settings sound as before.
"""
import re
import unittest
from pathlib import Path

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
# A sound call on the SFX manager, however the manager is named at the site:
# a method call, or the method handed to pcall with the manager first.
SOUND_CALL = re.compile(r'(?:SFXManager\(\)|\bsfx|\bsfxManager):Play\((.*)|\bsfx\.Play, *\w+, *(.*)')


class SoundSettingsTests(unittest.TestCase):
    def test_settings_scale_volumes_in_ten_percent_steps(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('package.path=[[%s/?.lua;]]..package.path; package=nil' % ROOT.as_posix())
        lua.execute('''
            local S=require('scripts.lib.sound_volume')
            local function near(a,b) assert(math.abs(a-b)<1e-9, tostring(a)..' vs '..tostring(b)) end
            ConchBlessing=nil; near(S.volume(0.6),0.6)
            ConchBlessing={Config={}}; near(S.volume(0.6),0.6); near(S.volume(nil),1); near(S.volume(0.6,'rain'),0.6)
            ConchBlessing.Config={soundVolume=5}; near(S.volume(0.6),0.3); near(S.volume(0.6,'rain'),0.3)
            ConchBlessing.Config={soundVolume=5, rainVolume=4}; near(S.volume(1,'rain'),0.2); near(S.volume(1),0.5)
            ConchBlessing.Config={rainVolume=0}; near(S.volume(1,'rain'),0); near(S.volume(1),1)
            ConchBlessing.Config={soundVolume=0}; near(S.volume(1),0); near(S.volume(1,'rain'),0)
            ConchBlessing.Config={soundVolume=99, rainVolume=-3}; near(S.volume(1),1); near(S.volume(1,'rain'),0)
            ConchBlessing.Config={soundVolume='junk'}; near(S.volume(0.8),0.8)
            ConchBlessing.Config={soundVolume=6.6}; near(S.volume(1),0.7)
            assert(S.ALL=='soundVolume' and S.RAIN=='rainVolume' and S.STEPS==10)
        ''')

    def test_every_sound_call_goes_through_the_settings(self):
        checked = 0
        for path in sorted((ROOT / 'scripts').rglob('*.lua')):
            rel = path.relative_to(ROOT).as_posix()
            if rel.startswith('scripts/dev/') or '/notused/' in rel or rel.endswith('isaacscript-common.lua'):
                continue
            text = path.read_text(encoding='utf-8')
            for number, line in enumerate(text.splitlines(), 1):
                found = SOUND_CALL.search(line)
                if not found:
                    continue
                checked += 1
                with self.subTest(at=f'{rel}:{number}'):
                    self.assertIn('sound_volume', text, 'the file never reaches scripts/lib/sound_volume.lua')
                    args = found[1] if found[1] is not None else found[2]
                    volume = args.split(',')[1] if ',' in args else ''
                    self.assertIn('volume', volume, 'the cue volume does not pass through Sound.volume')
        self.assertGreater(checked, 20)

    def test_the_menu_offers_both_settings_with_defaults_at_full(self):
        config = (ROOT / 'scripts/conch_blessing_config.lua').read_text(encoding='utf-8')
        self.assertRegex(config, r'soundVolume = 10,')
        self.assertRegex(config, r'rainVolume = 10,')
        menu = (ROOT / 'scripts/conch_blessing_mcm.lua').read_text(encoding='utf-8')
        for key in ('Sound.ALL', 'Sound.RAIN', 'tab_sound', 'sound_title'):
            self.assertIn(key, menu)


if __name__ == '__main__':
    unittest.main()
