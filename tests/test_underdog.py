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
players={}
Isaac.GetPlayer=function(i) return players[i+1] end
-- An item pool double: a weighted pick decided by the seed alone, every call
-- recorded, and the engine's PRE_GET_COLLECTIBLE run first like the game does.
poolItems={}
poolCalls={}
removed={}
preHook=nil
pool={}
function pool:GetCollectible(poolType, decrease, seed)
    poolCalls[#poolCalls+1]={pool=poolType, decrease=decrease, seed=seed}
    if preHook then
        local r=preHook(nil, poolType, decrease, seed)
        if r then return r end
    end
    local total=0
    for _,e in ipairs(poolItems) do total=total+e.weight end
    if total<=0 then return 25 end
    local x=((seed*2654435761)%4294967296)/4294967296*total
    for _,e in ipairs(poolItems) do
        x=x-e.weight
        if x<0 then return e.id end
    end
    return poolItems[#poolItems].id
end
function pool:RemoveCollectible(id) removed[#removed+1]=id end
function RNG()
    local r={s=1}
    function r:SetSeed(s) self.s=math.floor(s)%4294967296 if self.s==0 then self.s=1 end end
    function r:Next()
        local x=self.s
        x=x ~ ((x<<13)&0xffffffff); x=x ~ (x>>17); x=x ~ ((x<<5)&0xffffffff)
        self.s=x&0xffffffff
        if self.s==0 then self.s=1 end
        return self.s
    end
    function r:RandomFloat() return self:Next()/4294967296 end
    return r
end
function Game() return {GetFrameCount=function() return frame end,
    GetNumPlayers=function() return #players end, GetItemPool=function() return pool end} end
serial=0
function GetPtrHash(e) return e.hash end
ConchBlessing={ItemData={},Locale={text=function(path,...) return path.."|"..table.concat({...},"|") end},
    printDebug=function(fmt,...) if select("#",...)>0 then return string.format(fmt,...) end return fmt end,
    printError=function(message) error(message) end}
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
        self.assertAlmostEqual(range_, 40)       # half a tile each: item 3 and Underdog itself (quality 2)
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

    def test_qualities_outside_zero_to_four_clamp_and_every_item_counts(self):
        # Only the quality is read (user decision 2026-11-20): quest items,
        # hidden items and Underdog itself count like any other item.
        result = self.run_lua('''
            local p=player(); give(p,UNDERDOG); give(p,UNDERDOG)
            give(p,6); give(p,7); give(p,8)        -- quality 5, 99999 and -1
            give(p,9); give(p,10)                  -- a quest item (quality 0) and a hidden item (quality 1)
            local o=evaluate(p)
            return o.speed, o.damage, o.tears, o.range, T.bucket(5), T.bucket(-1), T.bucket(nil)
        ''')
        speed, damage, tears, range_, b5, bneg, bnil = result
        self.assertAlmostEqual(speed, -0.2)       # quality 5 and 99999
        self.assertAlmostEqual(damage, 2)         # quality -1 and the quest item's quality 0
        self.assertAlmostEqual(tears, 0.3)        # the hidden item's quality 1
        self.assertAlmostEqual(range_, 40)        # both Underdog copies, quality 2
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
        # A quest item and another Underdog show their quality's line too.
        self.assertEqual(result, ('baseui.underdog.q4|12|-0.1', 'baseui.underdog.q0|12|+1',
                                  'baseui.underdog.q2|12|+0.5', 'base'))


    # ----------------------------------------------------------- item pools
    # Quality 0-1 items are lowWeight (3) times as likely in item pool draws
    # while a living player holds Underdog (user decision 2026-11-21).
    POOL = '''
        poolItems={{id=1,weight=1},{id=2,weight=1},{id=3,weight=1},{id=4,weight=1},{id=5,weight=1}}
        poolCalls={}; removed={}; preHook=nil; ConchBlessing.conchpearl=nil
        holder=player(); give(holder,UNDERDOG); players={holder}
        T.resetEvidence()
    '''

    def test_keep_rule(self):
        result = self.run_lua('''
            return T.keeps(0,0.99,3), T.keeps(1,0.99,3), T.keeps(-2,0.99,3), T.keeps(nil,0.99,3),
                T.keeps(2,0.33,3), T.keeps(2,0.34,3), T.keeps(4,0.0,3), T.keeps(99,0.5,3)
        ''')
        self.assertEqual(result, (True, True, True, True, True, False, True, False))

    def test_choose_peeks_until_kept_and_falls_back_to_the_last_peek(self):
        result = self.run_lua('''
            local function run(ids, rolls, peeks)
                local i, r, asked = 0, 0, 0
                local function draw() i = i + 1; asked = asked + 1; return ids[i] end
                local function quality(id) return id // 100 end
                local function roll() r = r + 1; return rolls[r] or 0.9 end
                local id, fallback = T.choose(draw, quality, roll, 3, peeks)
                return id, fallback, asked
            end
            local a1, b1, c1 = run({ 301, 402, 5 }, { 0.9, 0.9, 0.9 }, 20)
            local a2, b2, c2 = run({ 301, 202 }, { 0.9, 0.1 }, 20)
            local a3, b3, c3 = run({ 301, 302, 303 }, {}, 3)
            local a4, b4, c4 = run({ 301 }, { 0.9 }, 20)
            return a1, b1, c1, a2, b2, c2, a3, b3, c3, a4, c4
        ''')
        self.assertEqual(result[:3], (5, False, 3))      # quality 0 kept at once
        self.assertEqual(result[3:6], (202, False, 2))   # quality 2 kept on a low roll
        self.assertEqual(result[6:9], (303, True, 3))    # none kept: the last peek
        self.assertEqual(result[9], None)                # the pool left it to the engine
        self.assertEqual(result[10], 2)

    def test_quality_0_1_draws_are_three_times_as_likely(self):
        result = self.run_lua(self.POOL + '''
            local count={}
            local n=6000
            for s=1,n do
                local id=M.onPreGetCollectible(nil,0,false,s*7919+13)
                count[id]=(count[id] or 0)+1
            end
            return (count[1] or 0)/n, (count[2] or 0)/n, (count[3] or 0)/n, (count[5] or 0)/n
        ''')
        q0, q1, q2, q4 = result
        # weights 3,3,1,1,1 out of 9
        self.assertAlmostEqual(q0, 3 / 9, delta=0.03)
        self.assertAlmostEqual(q1, 3 / 9, delta=0.03)
        self.assertAlmostEqual(q2, 1 / 9, delta=0.02)
        self.assertAlmostEqual(q4, 1 / 9, delta=0.02)

    def test_peeks_take_nothing_out_and_only_the_kept_item_leaves(self):
        result = self.run_lua(self.POOL + '''
            local idKept=M.onPreGetCollectible(nil,0,true,12345)
            local decreased=0
            for _,c in ipairs(poolCalls) do if c.decrease then decreased=decreased+1 end end
            local removedAfterTrue=#removed
            local first=removed[1]
            removed={}
            M.onPreGetCollectible(nil,0,false,999)
            return decreased, removedAfterTrue, first==idKept, #removed, #poolCalls>0
        ''')
        self.assertEqual(result, (0, 1, True, 0, True))

    def test_nested_draws_leave_our_callback_out(self):
        result = self.run_lua(self.POOL + '''
            local nested=0
            preHook=function(_, poolType, decrease, seed)
                local r=M.onPreGetCollectible(nil,poolType,decrease,seed)
                if T.peeking() and r==nil then nested=nested+1 end
                return r
            end
            local id=pool:GetCollectible(0,true,4242)
            return type(id), nested>0, T.peeking()
        ''')
        self.assertEqual(result, ('number', True, False))

    def test_left_to_the_engine(self):
        result = self.run_lua(self.POOL + '''
            local a=M.onPreGetCollectible(nil,0,true,77)~=nil
            -- nobody living holds it
            holder.IsDead=function() return true end
            local dead=M.onPreGetCollectible(nil,0,true,77)
            holder.IsDead=nil
            players={}
            local none=M.onPreGetCollectible(nil,0,true,77)
            players={holder}
            -- Conch Pearl never lets quality 0-1 appear: Underdog stands aside
            ConchBlessing.conchpearl={isActive=function() return true end}
            local pearl=M.onPreGetCollectible(nil,0,true,77)
            ConchBlessing.conchpearl=nil
            -- an empty pool answers Breakfast
            poolItems={}
            local empty=M.onPreGetCollectible(nil,0,true,77)
            return a, dead, none, pearl, empty, T.evidence().left
        ''')
        self.assertEqual(result, (True, None, None, None, None, 1))

    def test_a_pool_of_only_good_items_still_answers(self):
        result = self.run_lua(self.POOL + '''
            poolItems={{id=5,weight=1}}
            local ids={}
            for s=1,200 do ids[M.onPreGetCollectible(nil,0,false,s)]=true end
            local only=true
            for id in pairs(ids) do if id~=5 then only=false end end
            return only, T.evidence().draws
        ''')
        self.assertEqual(result, (True, 200))


if __name__ == '__main__':
    unittest.main()
