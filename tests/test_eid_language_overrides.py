"""Shipped EID adapter with a double matching the installed public registration API.

This verifies only owned descriptions and language transitions; actual EID rendering
is covered by conch_test locale in the game.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class EIDLanguageTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            effective='kr';native='ko_kr';selected='auto';callbacks={};errors={}
            package.loaded['scripts.conch_blessing_config']={
                GetCurrentLanguage=function() return effective end,
                GetEIDLanguage=function() return native end,
                GetSelectedLanguage=function() return selected end}
            package.loaded['scripts.lib.isaacscript-common']={ModCallbackCustom={PRE_ITEM_PICKUP=12}}
            ModCallbacks={MC_POST_GAME_STARTED=1,MC_POST_UPDATE=2,MC_POST_RENDER=3}
            ConchBlessing={printDebug=function() end,printError=function(msg) errors[#errors+1]=msg end,
                AddCallback=function(_,key,fn) callbacks[key]=fn end,AddCallbackCustom=function() end}
            function makeItem(id,kind)
                local item={id=id,type=kind,name={},description={},eid={}}
                for _,lang in ipairs({'en','kr','urimal'}) do
                    item.name[lang]=kind..' '..lang;item.description[lang]='HUD '..lang
                    item.eid[lang]={'Line '..lang..' 1','Next '..lang..' 2'}
                end
                return item
            end
            ConchBlessing.ItemData={C=makeItem(900,'passive'),T=makeItem(900,'trinket'),F=makeItem(901,'trinket')}
            ConchBlessing.ItemData.T.specials={en={append={'EN gold','EN box','EN both'}},
                kr={append={'KR gold','KR box','KR both'}},urimal={append={'URI gold','URI box','URI both'}}}
            ConchBlessing.ItemData.F.specials={en={normal={2,3},moms_box={4,5},both={6,7}},
                kr={normal={2,3},moms_box={4,5},both={6,7}},urimal={normal={2,3},moms_box={4,5},both={6,7}}}
            function makeProvider()
                local p={Config={Language=native},descriptions={},ItemNames={},GoldenTrinketData={},_currentMod='Other Mod',writes=0,goldWrites=0}
                for _,lang in ipairs({'en_us','ko_kr','ja_jp','zh_cn'}) do
                    p.descriptions[lang]={custom={['5.100.1']={1,'vanilla','unchanged','Vanilla'},
                        ['5.100.9999']={9999,'other','untouched','Other Mod'}},goldenTrinketEffects={[9999]={'other gold'}}}
                    p.ItemNames[lang]={['5.100.9999']='other'}
                end
                function p:CreateDescriptionTableIfMissing(kind,lang)
                    self.descriptions[lang]=self.descriptions[lang] or {}
                    self.descriptions[lang][kind]=self.descriptions[lang][kind] or {}
                    self.ItemNames[lang]=self.ItemNames[lang] or {}
                end
                function p:addCollectible(id,desc,name,lang)
                    if self.fail then error('registration failure') end
                    self:CreateDescriptionTableIfMissing('custom',lang)
                    self.descriptions[lang].custom['5.100.'..id]={id,name,desc,self._currentMod}
                    self.ItemNames[lang]['5.100.'..id]=name;self.writes=self.writes+1
                end
                function p:addTrinket(id,desc,name,lang)
                    self:CreateDescriptionTableIfMissing('custom',lang)
                    self.descriptions[lang].custom['5.350.'..id]={id,name,desc,self._currentMod}
                    self.ItemNames[lang]['5.350.'..id]=name;self.writes=self.writes+1
                end
                function p:addGoldenTrinketTable(id,data) self.GoldenTrinketData[id]=data;self.goldWrites=self.goldWrites+1 end
                return p
            end
            EID=makeProvider()
            function tick() callbacks[2]() end
            function entry(lang,key) return EID.descriptions[lang].custom[key] end
        ''')
        self.source=(ROOT/'scripts/eid_language.lua').read_text(encoding='utf-8')
        self.load()

    def load(self):
        self.lua.execute(self.source)

    def test_holiday_overlay_changes_only_our_rows_and_golden_effects(self):
        self.lua.execute('''
            effective='urimal';callbacks[3]() -- also refresh while paused
            assert(entry('ko_kr','5.100.900')[2]=='passive urimal')
            assert(entry('ko_kr','5.350.900')[2]=='trinket urimal')
            assert(entry('en_us','5.100.900')[2]=='passive en')
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[900][2]=='URI box')
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[901][2]:find('urimal',1,true))
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[901][2]:find('{{ColorGold}}4',1,true))
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[9999][1]=='other gold')
            assert(entry('ko_kr','5.100.9999')[3]=='untouched' and entry('ko_kr','5.100.1')[3]=='unchanged')
            assert(EID.Config.Language=='ko_kr' and EID._currentMod=='Other Mod')
            assert(EID.descriptions.urimal==nil and EID.ItemNames.urimal==nil)
        ''')

    def test_manual_english_then_korean_restores_canonical_entries(self):
        self.lua.execute('''
            effective='en';tick();assert(entry('ko_kr','5.100.900')[2]=='passive en')
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[900][1]=='EN gold')
            effective='kr';tick();assert(entry('ko_kr','5.100.900')[2]=='passive kr')
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[900][1]=='KR gold')
        ''')

    def test_native_eid_switch_restores_previous_slot_and_overlays_new_slot(self):
        self.lua.execute('''
            effective='urimal';tick();native='en_us';EID.Config.Language='en_us';tick()
            assert(entry('en_us','5.100.900')[2]=='passive urimal')
            assert(entry('ko_kr','5.100.900')[2]=='passive kr')
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[900][1]=='KR gold')
            assert(EID.descriptions.en_us.goldenTrinketEffects[900][1]=='URI gold')
            assert(EID.GoldenTrinketData[900].append and EID.GoldenTrinketData[901].fullReplace)
            effective='en';tick();assert(entry('en_us','5.100.900')[2]=='passive en')
        ''')

    def test_unchanged_update_and_render_do_not_register_again(self):
        self.lua.execute('''
            local before,gold=EID.writes,EID.goldWrites
            for i=1,100 do tick();callbacks[3]() end
            assert(EID.writes==before and EID.goldWrites==gold)
        ''')

    def test_manual_urimal_overlays_polish_then_restores_english_fallback(self):
        self.lua.execute('''
            native='pl';EID.Config.Language='pl';effective='urimal'
            EID.descriptions.pl={custom={['5.100.9999']={9999,'polish other','unchanged','Other Mod'}},
                goldenTrinketEffects={[9999]={'foreign gold'}}}
            EID.ItemNames.pl={['5.100.9999']='polish other'}
            tick()
            assert(entry('pl','5.100.900')[2]=='passive urimal')
            assert(entry('pl','5.350.900')[2]=='trinket urimal')
            assert(EID.descriptions.pl.goldenTrinketEffects[900][1]=='URI gold')
            assert(entry('pl','5.100.9999')[2]=='polish other')
            assert(EID.descriptions.pl.goldenTrinketEffects[9999][1]=='foreign gold')
            native='en_us';EID.Config.Language='en_us';tick()
            assert(entry('en_us','5.100.900')[2]=='passive urimal')
            assert(entry('pl','5.100.900')[2]=='passive en')
            assert(EID.descriptions.pl.goldenTrinketEffects[900][1]=='EN gold')
            assert(EID.Config.Language=='en_us' and EID._currentMod=='Other Mod')
        ''')

    def test_extra_native_targets_restore_after_reload_and_do_not_leak_to_new_provider(self):
        self.lua.execute("native='pl';effective='urimal';EID.Config.Language='pl';tick();native='ko_kr'")
        self.load()
        self.lua.execute('''
            assert(entry('pl','5.100.900')[2]=='passive en')
            assert(entry('ko_kr','5.100.900')[2]=='passive urimal')
            EID=makeProvider();tick();assert(EID.descriptions.pl==nil)
        ''')

    def test_replaced_late_or_partial_provider_rebuilds_owned_registration(self):
        self.lua.execute('''
            effective='urimal';EID=nil;tick();EID=makeProvider();tick()
            assert(entry('ko_kr','5.100.900')[2]=='passive urimal')
            local new=makeProvider();local addGold=new.addGoldenTrinketTable;new.addGoldenTrinketTable=nil
            EID=new;tick();assert(entry('ko_kr','5.100.900')[2]=='passive urimal')
            EID.addGoldenTrinketTable=addGold;tick()
            assert(EID.descriptions.ko_kr.goldenTrinketEffects[900][1]=='URI gold')
        ''')

    def test_registration_error_restores_context_and_retries_without_log_spam(self):
        self.lua.execute('''
            EID=makeProvider();EID.fail=true;tick();tick()
            assert(EID._currentMod=='Other Mod' and #errors==1)
            EID.fail=false;tick();assert(entry('ko_kr','5.100.900')[2]=='passive kr')
        ''')

    def test_reload_rebuilds_changed_text_and_fallback_never_claims_unknown_native_code(self):
        self.lua.execute("ConchBlessing.ItemData.C.name.kr='new Korean name'")
        self.load()
        self.lua.execute('''
            assert(entry('ko_kr','5.100.900')[2]=='new Korean name')
            effective='missing';assert(ConchBlessing.EID.refreshLanguage())
            assert(entry('ko_kr','5.100.900')[2]=='passive en')
            assert(EID.descriptions.missing==nil)
        ''')


if __name__=='__main__': unittest.main()
