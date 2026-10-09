"""Locale bench state-restoration and effective-language checks, without a game."""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


class LocaleProbeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r"""
            package.path=root..'/?.lua;'..package.path
            selection='auto'; holiday=true; refreshed={}; switches={}
            local config={}
            function config.GetSelectedLanguage() return selection end
            function config.SetLanguage(code)
                assert(code=='auto' or code=='en' or code=='kr' or code=='urimal' or code=='kr_standard')
                selection=code;switches[#switches+1]=code;return true
            end
            function config.GetCurrentLanguage()
                if selection=='kr_standard' then return 'kr' end
                local base=selection=='auto' and 'kr' or selection
                return base=='kr' and holiday and 'urimal' or base
            end
            function config.GetEIDLanguage() return 'ko_kr' end
            package.loaded['scripts.conch_blessing_config']=config
            package.loaded['scripts.dev.test_bench']={register=function(def) probe=def end}
            EntityType={ENTITY_PICKUP=5}; PickupVariant={PICKUP_COLLECTIBLE=100}
            EID={Config={Language='ko_kr'},UserConfig={Language='auto'}}
            function EID:getDescriptionObj() return {Description=config.GetCurrentLanguage()..' first line'} end
            local locale={tables={},problems={}}
            function locale.languages() return {'en','kr','urimal'} end
            function locale.get(path,lang) return {lang..' first line'} end
            for _,lang in ipairs(locale.languages()) do locale.tables[lang]={items={LIVE_EYE={name=lang}}} end
            ConchBlessing={Locale=locale,ItemData={LIVE_EYE={id=1,name={en='en',kr='kr',urimal='urimal'}}},EID={}}
            function ConchBlessing.EID.refreshLanguage()
                refreshed[#refreshed+1]=config.GetCurrentLanguage()
            end
            player={AddCollectible=function() end}
            require('scripts.dev.locale_probe')
            steps={};ctx={}
            local plan={}
            for _,kind in ipairs({'act','check','section','wait'}) do
                plan[kind]=function(a,b)
                    steps[#steps+1]={kind=kind,label=type(a)=='string' and a or nil,
                        fn=type(a)=='function' and a or type(b)=='function' and b or nil}
                end
            end
            probe.build(plan)
            function actUntil(lang)
                for _,step in ipairs(steps) do
                    if step.kind=='act' then
                        step.fn(player,ctx)
                        if selection==lang and ctx.localeLanguage then return end
                    end
                end
                error('requested selection was not exercised: '..lang)
            end
            function check(label)
                for _,step in ipairs(steps) do
                    if step.kind=='check' and step.label==label then return step.fn(player,ctx) end
                end
                error('missing check: '..label)
            end
        """)

    def test_all_three_sources_are_checked_without_date_override(self):
        self.lua.execute("""
            assert(check('English, Korean and Urimal locale files load'))
            assert(check('every item has a name from each explicit locale file'))
            ConchBlessing.ItemData.LIVE_EYE.name.kr='wrong'
            assert(not check('every item has a name from each explicit locale file'))
        """)

    def test_korean_preference_checks_effective_urimal_on_holiday(self):
        self.lua.execute(r"""
            actUntil('kr')
            assert(selection=='kr' and ctx.localeLanguage=='urimal')
            assert(check('kr: Live Eye\'s description is its locale text'))
            assert(EID.Config.Language=='ko_kr' and EID.UserConfig.Language=='auto')
            probe.cleanup(ctx)
            assert(selection=='auto' and refreshed[#refreshed]=='urimal')
        """)

    def test_interrupted_english_check_restores_manual_urimal(self):
        self.lua.execute("""
            selection='urimal'
            actUntil('en');assert(selection=='en')
            probe.cleanup(ctx)
            assert(selection=='urimal' and refreshed[#refreshed]=='urimal')
            assert(EID.Config.Language=='ko_kr' and EID.UserConfig.Language=='auto')
            probe.cleanup(ctx);assert(selection=='urimal')
        """)

    def test_completed_actions_restore_preference_without_touching_eid(self):
        self.lua.execute(r"""
            for _,step in ipairs(steps) do if step.kind=='act' then step.fn(player,ctx) end end
            assert(table.concat(switches,',')=='en,kr,urimal,kr_standard,auto')
            assert(check('the original mod language preference is restored'))
            assert(check('EID\'s global language still matches the player\'s setting'))
        """)

    def test_standard_korean_render_and_cleanup_preserve_fixed_preference(self):
        self.lua.execute(r"""
            actUntil('kr_standard')
            assert(ctx.localeLanguage=='kr')
            assert(check('kr_standard: selected and effective language resolve'))
            assert(check('kr_standard: Live Eye\'s description is its locale text'))
            probe.cleanup(ctx);assert(selection=='auto')
            selection='kr_standard';actUntil('en')
            probe.cleanup(ctx)
            assert(selection=='kr_standard' and refreshed[#refreshed]=='kr')
            assert(EID.Config.Language=='ko_kr' and EID.UserConfig.Language=='auto')
        """)

    def test_cleanup_before_setup_and_without_eid_is_safe(self):
        self.lua.execute("""
            probe.cleanup({});assert(selection=='auto')
            EID=nil;actUntil('en');probe.cleanup(ctx)
            assert(selection=='auto')
        """)

    def test_nil_eid_preferences_are_preserved(self):
        self.lua.execute("""
            EID.Config.Language=nil;EID.UserConfig.Language=nil
            actUntil('urimal');probe.cleanup(ctx)
            assert(selection=='auto' and EID.Config.Language==nil and EID.UserConfig.Language==nil)
        """)


if __name__ == '__main__':
    unittest.main()
