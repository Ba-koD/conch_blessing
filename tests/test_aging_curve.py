"""에이징 커브 (Aging Curve) through its shipped Lua: the user's design
(2026-11-24) is Growth Hormones' neutral answer where every stat but luck falls
by the same step every stage, nothing on stage 6 and below nothing after it
(damage 9 - 1.5 x stage, tears 3 - 0.5 x stage, range 6 - stage tiles, shot
speed and speed 0.6 - 0.1 x stage) with no floor of the item's own, while
luck rises by 1 a stage from stage 4. Covers the curve, Greed Mode and the
Ascent, copies, the cache evaluation through StatsAPI and the new-floor
refresh. These are Lua regressions with doubles,
not proof of engine behaviour (`cb test aging_curve`).
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / (name.replace('.', '/') + '.lua')).read_text(encoding='utf-8')


SETUP = r'''
package=nil
local cache={}
function ConchBlessingRequire(name)
    if not cache[name] then cache[name]=load(loadsource(name),name)() end
    return cache[name]
end
CacheFlag={CACHE_DAMAGE=1,CACHE_FIREDELAY=2,CACHE_SHOTSPEED=4,CACHE_RANGE=8,CACHE_SPEED=16,CACHE_LUCK=1024}
AGING=31
added={}
local function stat(name)
    return {applyAddition=function(player,amount) added[#added+1]={player=player,stat=name,amount=amount} end}
end
ConchBlessing={stats={damage=stat('damage'),tears=stat('tears'),speed=stat('speed'),range=stat('range'),
    shotSpeed=stat('shotSpeed'),luck=stat('luck')}}
Isaac={GetItemIdByName=function(name) return name=='Aging Curve' and AGING or -1 end}
level={stage=1,ascent=false}
function level:GetStage() return self.stage end
function level:IsAscent() return self.ascent end
greed=false
players={}
function Game() return {GetLevel=function() return level end,IsGreedMode=function() return greed end,
    GetNumPlayers=function() return #players end,GetPlayer=function(_,i) return players[i+1] end} end
-- Isaac's own stats: damage 3.5, 2.73 shots a second, speed 1, range 6.5 tiles,
-- shot speed 1, luck 0.
function player(copies)
    local p={copies=copies or 1,flags=0,evaluated=0,Damage=3.5,MaxFireDelay=10,MoveSpeed=1,TearRange=260,
        ShotSpeed=1,Luck=0}
    function p:GetCollectibleNum(id) return id==AGING and self.copies or 0 end
    function p:AddCacheFlags(f) self.flags=self.flags|f end
    function p:EvaluateItems() self.evaluated=self.evaluated+1 end
    players[#players+1]=p
    return p
end
M=ConchBlessingRequire('scripts.items.collectibles.aging_curve')
T=M._test
function amounts(field)
    local out={}
    for s=1,13 do out[s]=string.format('%g',T.amount(field,s,1)) end
    return table.concat(out,',')
end
function evaluate(p)
    added={}
    for _,flag in ipairs({1,2,4,8,16,1024}) do M.onEvaluateCache(nil,p,flag) end
    local out={}
    for _,a in ipairs(added) do out[#out+1]=a.stat..'='..string.format('%.4f',a.amount) end
    return table.concat(out,' ')
end
'''


class AgingCurveTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().loadsource = source
        self.lua.execute(SETUP)

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_registry_row_and_text(self):
        registry = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        row = registry[registry.index('    AGING_CURVE = {'):registry.index('    -- The twelve zodiac items')]
        self.assertIn('origin = { id = CollectibleType.COLLECTIBLE_GROWTH_HORMONES, type = "collectible" }', row)
        self.assertIn('flag = "neutral"', row)
        self.assertIn('stackable = true', row)
        self.assertIn('evaluateCache = "agingCurve.onEvaluateCache"', row)
        self.assertIn('postNewLevel = "agingCurve.onNewLevel"', row)
        for flag in ('damage', 'firedelay', 'speed', 'range', 'shotspeed', 'luck'):
            self.assertIn(flag, row[row.index('cache = '):].split('\n')[0])
        for lang in ('en', 'kr', 'urimal'):
            text = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
            entry = text[text.index('AGING_CURVE = {'):]
            entry = entry[:entry.index('\n        },\n')]
            self.assertNotIn('REPENTOGON', entry, lang)
            for number in ('+7.5', '+2.5', '+5', '+0.5', '+1', '6', '4'):
                self.assertIn(number, entry, (lang, number))

    def test_the_user_formulas(self):
        # damage 9 - 1.5s, tears 3 - 0.5s, range 6 - s tiles, shot speed
        # and speed 0.6 - 0.1s: nothing on stage 6, on below it.
        self.assertEqual(self.run_lua("return amounts('damage')"),
                         '7.5,6,4.5,3,1.5,0,-1.5,-3,-4.5,-6,-7.5,-9,-10.5')
        self.assertEqual(self.run_lua("return amounts('tears')"),
                         '2.5,2,1.5,1,0.5,0,-0.5,-1,-1.5,-2,-2.5,-3,-3.5')
        self.assertEqual(self.run_lua("return amounts('range')"),
                         '200,160,120,80,40,0,-40,-80,-120,-160,-200,-240,-280')
        self.assertEqual(self.run_lua("return amounts('shotSpeed')"),
                         '0.5,0.4,0.3,0.2,0.1,0,-0.1,-0.2,-0.3,-0.4,-0.5,-0.6,-0.7')
        self.assertEqual(self.run_lua("return amounts('speed')"),
                         '0.5,0.4,0.3,0.2,0.1,0,-0.1,-0.2,-0.3,-0.4,-0.5,-0.6,-0.7')

    def test_luck_rises_by_one_from_stage_four(self):
        self.assertEqual(self.run_lua("return amounts('luck')"), '0,0,0,1,2,3,4,5,6,7,8,9,10')

    def test_greed_floors_count_twice_and_the_ascent_is_late(self):
        result = self.run_lua('''
            return T.stageOf(1,false,false), T.stageOf(4,false,false), T.stageOf(1,true,false),
                T.stageOf(4,true,false), T.stageOf(7,true,false), T.stageOf(2,false,true), T.stageOf(nil,false,false)
        ''')
        self.assertEqual(result, (1, 4, 1, 7, 13, 12, 1))

    def test_first_floor_prime_through_statsapi(self):
        result = self.run_lua('local p=player(1); return evaluate(p)')
        self.assertEqual(result, 'damage=7.5000 tears=2.5000 shotSpeed=0.5000 range=200.0000 speed=0.5000')

    def test_stage_six_leaves_only_luck(self):
        result = self.run_lua('level.stage=6; local p=player(1); return evaluate(p)')
        self.assertEqual(result, 'luck=3.0000')

    def test_past_stage_six_the_stats_go_below_nothing(self):
        result = self.run_lua('level.stage=7; local p=player(1); return evaluate(p)')
        self.assertEqual(result, 'damage=-1.5000 tears=-0.5000 shotSpeed=-0.1000 range=-40.0000 '
                                 'speed=-0.1000 luck=4.0000')

    def test_late_floors_ask_the_whole_fall(self):
        # The item sets no floor of its own (user decision 2026-11-24): the
        # engine keeps damage, shot speed and range at its own lowest values.
        result = self.run_lua('level.stage=13; local p=player(1); return evaluate(p)')
        self.assertEqual(result, 'damage=-10.5000 tears=-3.5000 shotSpeed=-0.7000 range=-280.0000 '
                                 'speed=-0.7000 luck=10.0000')

    def test_copies_add_up(self):
        result = self.run_lua('level.stage=4; local p=player(3); return evaluate(p)')
        self.assertEqual(result, 'damage=9.0000 tears=3.0000 shotSpeed=0.6000 range=240.0000 speed=0.6000 '
                                 'luck=3.0000')

    def test_ascent_counts_as_the_late_game(self):
        # The Ascent counts as stage 12.
        result = self.run_lua('level.stage=2; level.ascent=true; local p=player(1); return evaluate(p)')
        self.assertEqual(result, 'damage=-9.0000 tears=-3.0000 shotSpeed=-0.6000 range=-240.0000 '
                                 'speed=-0.6000 luck=9.0000')

    def test_non_holders_get_nothing(self):
        result = self.run_lua('local p=player(0); return evaluate(p)')
        self.assertEqual(result, '')

    def test_a_new_floor_reevaluates_every_holder(self):
        result = self.run_lua('''
            local a=player(1); local b=player(0); local c=player(2)
            M.onNewLevel()
            return a.evaluated, b.evaluated, c.evaluated, a.flags
        ''')
        self.assertEqual(result, (1, 0, 1, 1 | 2 | 4 | 8 | 16 | 1024))


if __name__ == '__main__':
    unittest.main()
