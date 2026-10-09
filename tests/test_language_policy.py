"""Calendar language policy, persisted choice and MCM selection (not engine render)."""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class LanguagePolicyTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Options={Language='kr'}
            calendar={year=2026,month=10,day=8}
            os={date=function(format) assert(format=='*t');return calendar end}
            ConchBlessing={Config={language='auto',debugMode=false,spawnCollectibles=false,spawnTrinkets=false},
                printDebug=function() end,printError=function(message) error(message) end}
            Isaac={ConsoleOutput=function() end,DebugString=function() end}
            Config=require('scripts.conch_blessing_config')
        ''')

    def run_lua(self, script):
        self.lua.execute(script)

    def test_calendar_boundaries_do_not_change_the_saved_korean_choice(self):
        self.run_lua('''
            for _,selected in ipairs({'auto','kr'}) do
                assert(Config.SetLanguage(selected))
                calendar.month=10;calendar.day=8;assert(Config.GetCurrentLanguage()=='kr')
                calendar.day=9;assert(Config.GetCurrentLanguage()=='urimal')
                assert(ConchBlessing.Config.language==selected)
                calendar.day=10;assert(Config.GetCurrentLanguage()=='kr')
                calendar.month=9;calendar.day=9;assert(Config.GetCurrentLanguage()=='kr')
                calendar.month=11;assert(Config.GetCurrentLanguage()=='kr')
                calendar.year=2027;calendar.month=10;assert(Config.GetCurrentLanguage()=='urimal')
                assert(ConchBlessing.Config.language==selected)
            end
        ''')

    def test_manual_urimal_stays_selected_after_midnight_and_module_reload(self):
        self.run_lua('''
            calendar.day=9;assert(Config.SetLanguage('urimal'))
            Options.Language='en';EID={Config={Language='en_us'}}
            for _,day in ipairs({8,9,10,31}) do
                calendar.day=day;assert(Config.GetCurrentLanguage()=='urimal')
            end
            package.loaded['scripts.conch_blessing_config']=nil
            Config=require('scripts.conch_blessing_config')
            assert(Config.GetCurrentLanguage()=='urimal' and ConchBlessing.Config.language=='urimal')
        ''')

    def test_standard_korean_bypasses_calendar_and_survives_saved_settings_reload(self):
        self.run_lua('''
            assert(Config.SetLanguage('kr_standard'))
            Options.Language='en';EID={Config={Language='en_us'}}
            for _,day in ipairs({8,9,10,31}) do
                calendar.day=day
                assert(Config.GetBaseLanguage()=='kr' and Config.GetCurrentLanguage()=='kr')
            end
            ConchBlessing.HasData=function() error('legacy JSON must not override settings') end
            ConchBlessing.SaveManager={IsLoaded=function() return true end,
                GetSettingsSave=function() return {config={language='kr_standard'}} end}
            package.loaded['scripts.conch_blessing_config']=nil
            Config=require('scripts.conch_blessing_config')
            calendar.day=9;Config.Init(ConchBlessing)
            assert(Config.GetSelectedLanguage()=='kr_standard' and Config.GetCurrentLanguage()=='kr')
            assert(EID.Config.Language=='en_us' and Options.Language=='en')
            assert(Config.GetEIDLanguage()=='en_us')
        ''')

    def test_config_init_restores_manual_preference_from_authoritative_settings(self):
        self.run_lua('''
            ConchBlessing.HasData=function() error('legacy JSON must not override settings') end
            ConchBlessing.SaveManager={IsLoaded=function() return true end,
                GetSettingsSave=function() return {config={language='urimal',debugMode=false}} end}
            calendar.day=10;Config.Init(ConchBlessing)
            assert(Config.GetCurrentLanguage()=='urimal')
            ConchBlessing.SaveManager.GetSettingsSave=function() return {config={language='kr'}} end
            calendar.day=9;Config.Init(ConchBlessing)
            assert(Config.GetCurrentLanguage()=='urimal' and ConchBlessing.Config.language=='kr')
            calendar.day=10;Config.Init(ConchBlessing)
            assert(Config.GetCurrentLanguage()=='kr')
        ''')

    def test_eid_precedence_and_non_korean_languages_are_unchanged(self):
        self.run_lua('''
            calendar.day=9
            EID={Config={Language='en_us'}};assert(Config.GetCurrentLanguage()=='en')
            EID.Config.Language='ko_kr';Options.Language='en';assert(Config.GetCurrentLanguage()=='urimal')
            EID.Config.Language='auto';assert(Config.GetCurrentLanguage()=='en')
            for _,language in ipairs({'en','ja','zh'}) do
                Config.SetLanguage(language);assert(Config.GetCurrentLanguage()==language)
            end
            Config.SetLanguage('kr');assert(Config.GetCurrentLanguage()=='urimal')
            assert(EID.Config.Language=='auto' and Options.Language=='en')
        ''')

    def test_missing_or_failing_date_api_leaves_korean_and_manual_urimal_usable(self):
        self.run_lua('''
            for _,provider in ipairs({false,{}, {date=function() error('sandbox') end},
                {date=function() return false end}, {date=function() return {} end}}) do
                os=provider;Config.SetLanguage('kr');assert(Config.GetCurrentLanguage()=='kr')
                Config.SetLanguage('urimal');assert(Config.GetCurrentLanguage()=='urimal')
            end
            os=nil;Config.SetLanguage('kr');assert(Config.GetCurrentLanguage()=='kr')
        ''')

    def test_invalid_preferences_fall_back_without_rewriting_other_settings(self):
        self.run_lua('''
            ConchBlessing.Config.language='removed-locale';calendar.day=8
            assert(Config.GetSelectedLanguage()=='auto' and Config.GetCurrentLanguage()=='kr')
            assert(not Config.SetLanguage('missing') and not Config.SetLanguage(nil))
            assert(ConchBlessing.Config.language=='removed-locale')
            assert(Config.SetLanguage('ko_kr') and Config.GetSelectedLanguage()=='kr')
        ''')

    def test_eid_target_slot_is_independent_and_invalid_eid_preference_is_not_mutated(self):
        self.run_lua('''
            Config.SetLanguage('urimal')
            EID={Config={Language='pl'},descriptions={pl={}},getLanguage=function() return 'pl' end}
            assert(Config.GetEIDLanguage()=='pl' and EID.Config.Language=='pl')
            EID.Config.Language='invalid'
            EID.getLanguage=function() error('must not call mutating invalid-language resolver') end
            assert(Config.GetEIDLanguage()=='ko_kr' and EID.Config.Language=='invalid')
            EID={Config={Language='auto'},getLanguage=function() return 'ja_jp' end}
            assert(Config.GetEIDLanguage()=='ja_jp' and Config.GetCurrentLanguage()=='urimal')
        ''')

    def test_mcm_persists_preference_instead_of_holiday_result_and_can_select_urimal(self):
        self.run_lua('''
            calendar.day=9;settings={};settingsSave={};writes=0;refreshes=0
            ModConfigMenu={OptionType={BOOLEAN=1,NUMBER=2},RemoveCategory=function() end,
                AddSpace=function() end,AddText=function() end,
                AddSetting=function(_,_,setting) settings[#settings+1]=setting end}
            ConchBlessing.SaveManager={IsLoaded=function() return true end,
                GetSettingsSave=function() return settingsSave end,Save=function() writes=writes+1 end}
            ConchBlessing.EID={refreshLanguage=function() refreshes=refreshes+1 end}
            local mcm=require('scripts.conch_blessing_mcm');mcm.Setup(ConchBlessing)
            local language=settings[1]
            assert(language.Type==2 and language.Minimum==1 and language.Maximum==5)
            assert(language.CurrentSetting()==1 and language.Display():find('October 9',1,true))
            language.OnChange(3)
            assert(settingsSave.config.language=='kr' and Config.GetCurrentLanguage()=='urimal')
            language.OnChange(4)
            assert(settingsSave.config.language=='urimal' and refreshes==2)
            calendar.day=10
            assert(Config.GetCurrentLanguage()=='urimal' and language.CurrentSetting()==4)
            ConchBlessing.Config.language='auto';mcm.loadConfigFromSaveManager(ConchBlessing)
            assert(Config.GetCurrentLanguage()=='urimal')
            assert(writes==2,'calendar read wrote settings')
            language.OnChange(3);assert(Config.GetCurrentLanguage()=='kr')
            calendar.day=9;assert(Config.GetCurrentLanguage()=='urimal')
            calendar.day=10;assert(Config.GetCurrentLanguage()=='kr' and settingsSave.config.language=='kr')
            calendar.day=9;language.OnChange(5)
            assert(language.Display()=='Language: Korean (Standard)')
            assert(language.CurrentSetting()==5 and settingsSave.config.language=='kr_standard')
            assert(Config.GetCurrentLanguage()=='kr')
            ConchBlessing.Config.language='auto';mcm.loadConfigFromSaveManager(ConchBlessing)
            assert(Config.GetCurrentLanguage()=='kr' and language.CurrentSetting()==5)
        ''')

    def test_locale_is_independent_and_exposes_every_korean_item(self):
        self.run_lua('''
            local locale=require('scripts.locale.init')
            assert(table.concat(locale.languages(),',')=='en,kr,urimal')
            assert(locale.tables.kr~=locale.tables.urimal,'new locale must be independently editable')
            for key,entry in pairs(locale.tables.kr.items) do
                local translated=assert(locale.tables.urimal.items[key],key)
                for field in pairs(entry) do assert(translated[field]~=nil,key..'.'..field) end
            end
        ''')


if __name__ == '__main__':
    unittest.main()
