"""언더독 (Underdog) through its shipped Lua: every held collectible gives the
stat of its quality while Underdog is held (user design 2026-11-15: quality 0
damage +1, 1 tears +0.3, 2 range +0.5, 3 luck -0.5, 4 and above speed -0.1;
items held before it count too). Covers what counts, clamping, held copies,
items leaving, a swap that keeps the total, owner isolation and the EID
preview. These are Lua regressions with doubles, not proof of engine
behaviour (`cb test underdog`).
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
EntityType={ENTITY_PICKUP=5}
PickupVariant={PICKUP_COLLECTIBLE=100}
ItemConfig={TAG_QUEST=1<<14}
UNDERDOG=12
items={}
local function item(id,quality,tags,hidden)
    local entry={Quality=quality,Hidden=hidden or false,tags=tags or 0}
    function entry:HasTags(t) return (self.tags & t)~=0 end
    items[id]=entry
end
item(UNDERDOG,2)
item(1,0); item(2,1); item(3,2); item(4,3); item(5,4); item(6,5); item(7,99999); item(8,-1)
item(9,0,ItemConfig.TAG_QUEST); item(10,1,0,true)
frame=0
Isaac={GetItemIdByName=function(n) return n=="Underdog" and UNDERDOG or -1 end,
    GetItemConfig=function() return {GetCollectible=function(_,id) return items[id] end,
        GetCollectibles=function() return {Size=13} end} end}
function Game() return {GetFrameCount=function() return frame end} end
serial=0
function GetPtrHash(e) return e.hash end
ConchBlessing={ItemData={},Locale={text=function(path,...) return path.."|"..table.concat({...},"|") end}}
applied={}
ConchBlessing.stats={}
for _,f in ipairs({"damage","tears","range","luck","speed"}) do
    ConchBlessing.stats[f]={applyAddition=function(p,amount) applied[#applied+1]={field=f,amount=amount} end}
end
function player()
    serial=serial+1
    local p={hash=serial,inv={},evaluated=0}
    function p:GetCollectibleNum(id) return self.inv[id] or 0 end
    function p:GetCollectibleCount() local n=0 for _,c in pairs(self.inv) do n=n+c end return n end
    function p:AddCacheFlags() end
    function p:EvaluateItems() self.evaluated=self.evaluated+1 end
    function p:ToPlayer() return self end
    return p
end
function give(p,id,n) p.inv[id]=(p.inv[id] or 0)+(n or 1) end
function take(p,id) p.inv[id]=(p.inv[id] or 0)-1 if p.inv[id]<=0 then p.inv[id]=nil end end
M=ConchBlessingRequire("scripts.items.collectibles.underdog")
T=M._test
function evaluate(p)
    applied={}
    for _,f in ipairs({CacheFlag.CACHE_DAMAGE,CacheFlag.CACHE_FIREDELAY,CacheFlag.CACHE_RANGE,CacheFlag.CACHE_LUCK,CacheFlag.CACHE_SPEED}) do
        M.onEvaluateCache(nil,p,f)
    end
    local out={}
    for _,a in ipairs(applied) do out[a.field]=(out[a.field] or 0)+a.amount end
    return out
end
function tick(p,n) for _=1,(n or 1) do frame=frame+1; M.onPlayerUpdate(nil,p) end end
'''


class UnderdogTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().loadsource = source
        self.lua.execute(SETUP)

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_each_quality_gives_its_own_stat(self):
        result = self.run_lua('''
            local p=player(); give(p,UNDERDOG)
            for id=1,5 do give(p,id) end
            local o=evaluate(p)
            return o.damage,o.tears,o.range,o.luck,o.speed
        ''')
        damage, tears, range_, luck, speed = result
        self.assertAlmostEqual(damage, 1)
        self.assertAlmostEqual(tears, 0.3)
        self.assertAlmostEqual(range_, 20)       # half a tile in TearRange units
        self.assertAlmostEqual(luck, -0.5)
        self.assertAlmostEqual(speed, -0.1)

    def test_items_held_before_count_and_every_copy_counts(self):
        result = self.run_lua('''
            local p=player(); give(p,1,3); give(p,4)
            local before=evaluate(p)
            give(p,UNDERDOG)
            local after=evaluate(p)
            return next(before)==nil, after.damage, after.luck
        ''')
        self.assertEqual(result, (True, 3, -0.5))

    def test_qualities_outside_zero_to_four_clamp_and_what_never_counts(self):
        result = self.run_lua('''
            local p=player(); give(p,UNDERDOG); give(p,UNDERDOG)
            give(p,6); give(p,7); give(p,8)        -- quality 5, 99999 and -1
            give(p,9); give(p,10)                  -- a quest item and a hidden item
            local o=evaluate(p)
            return o.speed, o.damage, o.range, T.bucket(5), T.bucket(-1), T.bucket(nil)
        ''')
        speed, damage, range_, b5, bneg, bnil = result
        self.assertAlmostEqual(speed, -0.2)       # quality 5 and 99999
        self.assertAlmostEqual(damage, 1)         # quality -1 only; the quest item does not count
        self.assertIsNone(range_)                 # Underdog itself is quality 2 and never counts
        self.assertEqual((b5, bneg, bnil), (5, 1, 1))

    def test_an_item_leaving_takes_its_share_and_a_swap_is_caught_by_the_sweep(self):
        result = self.run_lua('''
            local p=player(); give(p,UNDERDOG); give(p,1); give(p,2)
            tick(p); local before=evaluate(p)
            take(p,2); tick(p)                    -- the total changed: counted at once
            local left=evaluate(p)
            local refreshes=p.evaluated
            take(p,1); give(p,5); tick(p)         -- same total: waits for the sweep
            local early=evaluate(p)
            tick(p,M.sweep)
            local swept=evaluate(p)
            return before.tears, left.tears, refreshes>0, early.damage, swept.damage, swept.speed
        ''')
        before_tears, left_tears, refreshed, early_damage, swept_damage, swept_speed = result
        self.assertAlmostEqual(before_tears, 0.3)
        self.assertIsNone(left_tears)
        self.assertTrue(refreshed)
        self.assertAlmostEqual(early_damage, 1)
        self.assertIsNone(swept_damage)
        self.assertAlmostEqual(swept_speed, -0.1)

    def test_nothing_applies_without_it_and_players_are_separate(self):
        result = self.run_lua('''
            local a,b=player(),player()
            give(a,UNDERDOG); give(a,1); give(b,1); give(b,4)
            local oa,ob=evaluate(a),evaluate(b)
            take(a,UNDERDOG); tick(a)
            local gone=evaluate(a)
            return oa.damage, oa.luck, next(ob)==nil, next(gone)==nil, T.state()[a.hash]==nil
        ''')
        self.assertEqual(result, (1, None, True, True, True))

    def test_a_tally_changed_inside_one_stat_reevaluates_all_on_the_next_update(self):
        result = self.run_lua('''
            local p=player(); give(p,UNDERDOG); give(p,1)
            tick(p); evaluate(p)
            give(p,2)
            M.onEvaluateCache(nil,p,CacheFlag.CACHE_DAMAGE)   -- the engine evaluates one flag
            local before=p.evaluated
            tick(p)
            return p.evaluated-before
        ''')
        self.assertEqual(result, 1)

    def test_preview_signs(self):
        result = self.run_lua('return T.signed(M.data[1]),T.signed(M.data[2]),T.signed(M.data[3]),T.signed(M.data[4]),T.signed(M.data[5])')
        self.assertEqual(result, ('+1', '+0.3', '+0.5', '-0.5', '-0.1'))

    def test_eid_preview_for_the_closest_holder(self):
        result = self.run_lua('''
            local p=player(); give(p,UNDERDOG)
            EID={ClosestPlayerTo=function() return p end}
            local function obj(sub)
                local pickup={}
                function pickup:ToPickup() return self end
                return {ObjType=5,ObjVariant=100,ObjSubType=sub,Entity=pickup,Description="base"}
            end
            local a=M.describe(obj(5)).Description
            local b=M.describe(obj(9)).Description
            local c=M.describe(obj(UNDERDOG)).Description
            take(p,UNDERDOG)
            local d=M.describe(obj(1)).Description
            return a,b,c,d
        ''')
        self.assertEqual(result, ('baseui.underdog.q4|12|-0.1', 'base', 'base', 'base'))


if __name__ == '__main__':
    unittest.main()
