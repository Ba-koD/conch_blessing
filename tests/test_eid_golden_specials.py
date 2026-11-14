"""Golden / Mom's Box text of our trinkets as EID shows it.

EID's own golden trinket modifier runs first and puts the registered per-state
text in place (1 golden, 2 Mom's Box, 3 both); our description modifier then
scales only `specials.normal` numbers EID left alone. A per-state trinket such as
Wrong Answer Note must not be scaled a second time, while C- (normal only) still
is. Real EID rendering stays an in-game check.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class GoldenSpecialsText(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        for lang in ('en', 'kr', 'urimal'):
            g['locale_' + lang] = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
        self.lua.execute('''
            effective='kr';native='ko_kr';callbacks={};errors={}
            package.loaded['scripts.conch_blessing_config']={
                GetCurrentLanguage=function() return effective end,
                GetEIDLanguage=function() return native end,
                GetSelectedLanguage=function() return 'auto' end}
            package.loaded['scripts.lib.isaacscript-common']={ModCallbackCustom={PRE_ITEM_PICKUP=12}}
            ModCallbacks={MC_POST_GAME_STARTED=1,MC_POST_UPDATE=2,MC_POST_RENDER=3}
            ConchBlessing={printDebug=function() end,printError=function(msg) errors[#errors+1]=msg end,
                AddCallback=function(_,key,fn) callbacks[key]=fn end,AddCallbackCustom=function() end}
            locales={en=load(locale_en,'en')(),kr=load(locale_kr,'kr')(),urimal=load(locale_urimal,'urimal')()}
            ids={WRONG_ANSWER_NOTE=201,C_MINUS=202,B_MINUS=203,TIME_POWER=204,F_MINUS=205}
            -- Locale.applyItemData turns {own:KEY} into the item's EID icon, whose id is a number.
            local function item(key,specials)
                local data={id=ids[key],type='trinket',eid={},specials=specials}
                for lang,t in pairs(locales) do
                    local entry=t.items[key]
                    local lines={}
                    for i,line in ipairs(entry.eid) do
                        lines[i]=line:gsub('{own:([%w_]+)}',function(k) return '{{Trinket'..ids[k]..'}}' end)
                    end
                    data.eid[lang]=lines
                    if entry.specials then specials[lang]=entry.specials end
                end
                return data
            end
            ConchBlessing.ItemData={
                WRONG_ANSWER_NOTE=item('WRONG_ANSWER_NOTE',{normal={100,50},moms_box={100,50},both={150,75}}),
                C_MINUS=item('C_MINUS',{normal={4,2.0}}),
                TIME_POWER=item('TIME_POWER',{normal=0.006}),
                F_MINUS=item('F_MINUS',{normal=5}),
            }
            EID={Config={Language=native},descriptions={},ItemNames={},GoldenTrinketData={},_currentMod='Other Mod'}
            function EID:CreateDescriptionTableIfMissing(kind,lang)
                self.descriptions[lang]=self.descriptions[lang] or {}
                self.descriptions[lang][kind]=self.descriptions[lang][kind] or {}
                self.ItemNames[lang]=self.ItemNames[lang] or {}
            end
            function EID:addCollectible() end
            function EID:addTrinket(id,desc,name,lang)
                self:CreateDescriptionTableIfMissing('custom',lang)
                self.descriptions[lang].custom['5.350.'..id]={id,name,desc,self._currentMod}
            end
            function EID:addGoldenTrinketTable(id,data) self.GoldenTrinketData[id]=data end
            -- What EID's GoldenTrinketCallback leaves before our modifier: the full
            -- replacement for this state, or its own multiplier on the registered
            -- numbers (goldenTrinketData, read through the en_us fallback).
            local STATES={golden={choice=1,scale=2},box={choice=2,scale=2},both={choice=3,scale=3}}
            function shown(key,lang,state)
                local data=ConchBlessing.ItemData[key]
                local s=STATES[state]
                local text=table.concat(data.eid[lang] or data.eid.en,'\\n')
                local rule=EID.GoldenTrinketData[data.id]
                local numbers=(EID.descriptions.en_us.goldenTrinketData or {})[data.id]
                if rule and rule.fullReplace then
                    text=EID.descriptions[native].goldenTrinketEffects[data.id][s.choice]
                elseif numbers and numbers.t then
                    text=text:gsub('%d*%.?%d+',function(found)
                        for _,v in ipairs(numbers.t) do
                            if found==tostring(v) then
                                return '{{ColorGold}}'..string.format('%.4g',v*s.scale)..'{{CR}}'
                            end
                        end
                    end)
                end
                return ConchBlessing.EID.scaleSpecialsText(text,data.specials,lang,s.scale)
            end
            function has(text,needle) return text:find(needle,1,true)~=nil end
        ''')
        self.lua.execute((ROOT / 'scripts/eid_language.lua').read_text(encoding='utf-8'))

    def test_golden_wrong_answer_note_in_korean_is_not_scaled_twice(self):
        self.lua.execute(r'''
            local golden=shown('WRONG_ANSWER_NOTE','kr','golden')
            assert(has(golden,'100%') and has(golden,'50%'),golden)
            assert(not has(golden,'200') and not has(golden,'ColorYellow'),golden)
            local box=shown('WRONG_ANSWER_NOTE','kr','box')
            assert(has(box,'{{ColorGold}}100{{CR}}%') and has(box,'{{ColorGold}}50{{CR}}%'),box)
            assert(not has(box,'200'),box)
            local both=shown('WRONG_ANSWER_NOTE','kr','both')
            assert(has(both,'{{ColorGold}}150{{CR}}%') and has(both,'{{ColorGold}}75{{CR}}%'),both)
            assert(#errors==0,errors[1])
        ''')

    def test_english_and_urimal_read_their_own_numbers(self):
        self.lua.execute(r'''
            effective='en';native='en_us';EID.Config.Language='en_us';ConchBlessing.EID.refreshLanguage()
            local golden=shown('WRONG_ANSWER_NOTE','en','golden')
            assert(has(golden,'100% more damage') and has(golden,'by 50%') and not has(golden,'200'),golden)
            effective='urimal';native='ko_kr';EID.Config.Language='ko_kr';ConchBlessing.EID.refreshLanguage()
            golden=shown('WRONG_ANSWER_NOTE','urimal','golden')
            assert(has(golden,'10할 늘어납니다') and has(golden,'10할의 절반'),golden)
            local both=shown('WRONG_ANSWER_NOTE','urimal','both')
            assert(has(both,'{{ColorGold}}15{{CR}}할') and not has(both,'ColorYellow'),both)
        ''')

    def test_c_minus_still_scales_its_plain_numbers(self):
        self.lua.execute(r'''
            local golden=shown('C_MINUS','kr','golden')
            assert(has(golden,'{{ColorYellow}}8{{CR}}') and has(golden,'{{ColorYellow}}4.0{{CR}}'),golden)
            local both=shown('C_MINUS','kr','both')
            assert(has(both,'{{ColorYellow}}12{{CR}}') and has(both,'{{ColorYellow}}6.0{{CR}}'),both)
            -- The evolution line's icon keeps its id.
            assert(has(golden,'{{Trinket203}}'),golden)
        ''')

    def test_plain_numbers_keep_eids_own_multiplier_and_colour(self):
        self.lua.execute(r'''
            local golden=shown('TIME_POWER','kr','golden')
            assert(has(golden,'{{ColorGold}}0.012{{CR}}') and not has(golden,'ColorYellow'),golden)
            local both=shown('TIME_POWER','kr','both')
            assert(has(both,'{{ColorGold}}0.018{{CR}}') and not has(both,'ColorYellow'),both)
            golden=shown('F_MINUS','kr','golden')
            assert(has(golden,'{{ColorGold}}10{{CR}}') and not has(golden,'ColorYellow'),golden)
        ''')

    def test_without_golden_or_box_nothing_changes(self):
        self.lua.execute(r'''
            local data=ConchBlessing.ItemData.C_MINUS
            local text=table.concat(data.eid.kr,'\n')
            assert(ConchBlessing.EID.scaleSpecialsText(text,data.specials,'kr',1)==text)
        ''')

    def test_the_description_modifier_uses_the_shared_scaling(self):
        source = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        self.assertIn('ConchBlessing.EID.scaleSpecialsText', source)
        self.assertNotIn('itemData.specials.normal', source)


if __name__ == '__main__':
    unittest.main()
