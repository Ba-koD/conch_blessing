"""욥의 축복 (Job's Blessing) through its shipped Lua: everything its holder
acquires comes twice (user rules 2026-11-18): a first-time passive or
familiar acquisition brings one more copy, every trinket absorption is
repeated, every pickup absorbed on touch adds its numbers once more (nothing
is ever spawned: the user, 2026-11-19), every heal doubles; actives, cards,
runes and pills, heart containers and broken hearts do not; a copy, and
another mod's answer to it, never doubles again. These are
Lua regressions with engine doubles, not proof of engine behaviour
(`cb test jobs_blessing`).
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
JOB=900
EntityType={ENTITY_PICKUP=5}
PickupVariant={PICKUP_HEART=10,PICKUP_COIN=20,PICKUP_KEY=30,PICKUP_BOMB=40,PICKUP_GRAB_BAG=69,PICKUP_PILL=70,
    PICKUP_COLLECTIBLE=100,PICKUP_TAROTCARD=300,PICKUP_TRINKET=350}
TrinketType={TRINKET_GOLDEN_FLAG=32768}
ItemType={ITEM_PASSIVE=1,ITEM_TRINKET=2,ITEM_ACTIVE=3,ITEM_FAMILIAR=4}
ItemConfig={TAG_QUEST=1<<14}
AddHealthType={NONE=0,RED=1,MAX=2,SOUL=4,BLACK=8,ETERNAL=16,GOLDEN=32,BONE=64,ROTTEN=128,BROKEN=256}
ModCallbacks={MC_PRE_ADD_COLLECTIBLE=1004,MC_POST_ADD_COLLECTIBLE=1005,MC_POST_TRIGGER_TRINKET_ADDED=1096,
    MC_POST_TRIGGER_TRINKET_REMOVED=1097,MC_PRE_PICKUP_COLLISION=38,MC_POST_PICKUP_COLLISION=1239,
    MC_PRE_PLAYER_ADD_HEARTS=1009,MC_POST_PLAYER_ADD_HEARTS=1010}
CacheFlag={CACHE_LUCK=1024}
CallbackPriority={IMPORTANT=-200,LATE=100}
items={}
local function item(id,kind,tags,hidden)
    local entry={Type=kind,Hidden=hidden or false,tags=tags or 0}
    function entry:HasTags(t) return (self.tags & t)~=0 end
    items[id]=entry
end
item(JOB,ItemType.ITEM_PASSIVE)
item(1,ItemType.ITEM_PASSIVE); item(2,ItemType.ITEM_FAMILIAR); item(3,ItemType.ITEM_ACTIVE)
item(4,ItemType.ITEM_PASSIVE,ItemConfig.TAG_QUEST); item(5,ItemType.ITEM_PASSIVE,0,true)
item(-5,ItemType.ITEM_PASSIVE)  -- a glitched item
frame=0
Isaac={GetItemConfig=function() return {GetCollectible=function(_,id) return items[id] end} end}
gamePlayers={}
Vector=setmetatable({Zero={X=0,Y=0}},{__call=function(_,x,y) return {X=x,Y=y} end})
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
function newPickup(variant,subtype)
    local p={Variant=variant,SubType=subtype,anim="Idle",dead=false,gone=false}
    local sprite={}
    function sprite:GetAnimation() return p.anim end
    function p:GetSprite() return sprite end
    function p:IsDead() return self.dead end
    function p:Exists() return not self.gone end
    return p
end
function Game()
    return {GetFrameCount=function() return frame end,
        GetNumPlayers=function() return #gamePlayers end,
        GetPlayer=function(_,i) return gamePlayers[i+1] end,
        Spawn=function() error("Job's Blessing must never spawn anything") end}
end
runSaves={}
luckApplied={}
saveCallbacks={}
ConchBlessing={ItemData={JOBS_BLESSING={id=JOB}},
    printError=function(m) errors=(errors or 0)+1 end, printDebug=function() end,
    SaveManager={IsLoaded=function() return true end,
        SaveCallbacks={POST_DATA_LOAD="DATA_LOAD",POST_GLOWING_HOURGLASS_RESET="HOURGLASS"},
        GetRunSave=function(p) runSaves[p.hash]=runSaves[p.hash] or {}; return runSaves[p.hash] end},
    originalMod={AddCallback=function(_,id,fn) saveCallbacks[id]=fn end},
    stats={luck={applyAddition=function(p,amount) luckApplied[p.hash]=(luckApplied[p.hash] or 0)+amount end}}}
registered={}
function ConchBlessing:AddPriorityCallback(id,priority,fn) registered[#registered+1]={id=id,priority=priority} end
pserial=0
function player()
    pserial=pserial+1
    local p={hash=pserial,inv={},queueEmpty=true,dead=false,ghost=false,Position=Vector(10,20),smelted={},adds={},smelts={},
        coins=0,keys=0,bombs=0,giga=0,poop=0,Luck=0,active={},charge={},battery={},evaluated=0}
    function p:GetNumCoins() return self.coins end
    function p:AddCoins(n) self.coins=math.min(99,self.coins+n) end
    function p:GetNumKeys() return self.keys end
    function p:AddKeys(n) self.keys=self.keys+n end
    function p:GetNumBombs() return self.bombs end
    function p:AddBombs(n) self.bombs=self.bombs+n end
    function p:GetNumGigaBombs() return self.giga end
    function p:AddGigaBombs(n) self.giga=self.giga+n end
    function p:GetPoopMana() return self.poop end
    function p:AddPoopMana(n) self.poop=self.poop+n end
    function p:GetActiveItem(slot) return self.active[slot] or 0 end
    function p:GetActiveCharge(slot) return self.charge[slot] or 0 end
    function p:GetBatteryCharge(slot) return self.battery[slot] or 0 end
    function p:GetActiveMaxCharge() return 6 end
    -- The engine's own rule: an item takes charge below its top, or with The
    -- Battery until the battery is full too.
    function p:NeedsCharge(slot)
        return self:GetActiveCharge(slot) < 6 or (self.hasBattery and self:GetBatteryCharge(slot) < 6) or false
    end
    -- Charge stops at the top unless the add may overcharge.
    function p:AddActiveCharge(n,slot,flash,overcharge)
        self.chargeAdds=self.chargeAdds or {}
        self.chargeAdds[#self.chargeAdds+1]={n,slot,overcharge}
        local charge=self.charge[slot] or 0
        local into=math.min(n,6-charge)
        self.charge[slot]=charge+into
        if overcharge then self.battery[slot]=math.min(6,(self.battery[slot] or 0)+n-into) end
        return n
    end
    function p:AddCacheFlags() self.flagged=(self.flagged or 0)+1 end
    function p:EvaluateItems() self.evaluated=self.evaluated+1 end
    function p:Exists() return true end
    function p:IsDead() return self.dead end
    function p:IsCoopGhost() return self.ghost end
    function p:GetCollectibleNum(id) return self.inv[id] or 0 end
    function p:IsItemQueueEmpty() return self.queueEmpty end
    function p:ToPlayer() return self end
    -- The engine's add: PRE (ours LATE), the item and whatever it gives as it
    -- arrives (`onItemAdded`, Breakfast's hearts), then POST: ours that closes
    -- the add first of all, the doubling LATE.
    function p:AddCollectible(id,charge,first)
        M.onPreAddCollectible(nil,id,charge,first,0,0,self)
        self.inv[id]=(self.inv[id] or 0)+1
        self.adds[#self.adds+1]={id,charge,first}
        if self.onItemAdded then self.onItemAdded(self,id) end
        M.onAddCollectibleOpened(nil,id,charge,first,0,0,self)
        M.onAddCollectible(nil,id,charge,first,0,0,self)
    end
    function p:GetSmeltedTrinkets()
        local out={}
        for id,c in pairs(self.smelted) do out[id]={trinketAmount=c[1],goldenTrinketAmount=c[2]} end
        return out
    end
    function p:AddSmeltedTrinket(t,first)
        local id=t & ~32768
        self.smelted[id]=self.smelted[id] or {0,0}
        if t & 32768 ~= 0 then self.smelted[id][2]=self.smelted[id][2]+1 else self.smelted[id][1]=self.smelted[id][1]+1 end
        self.smelts[#self.smelts+1]=t
        M.onTrinketAdded(nil,self,t,first,false)  -- REPENTOGON reports it after the count rose
        return true
    end
    return p
end
-- The Smelter's own path: the event comes before the smelted count rises.
function smelterSmelt(p,t)
    M.onTrinketAdded(nil,p,t,false,false)
    local id=t & ~32768
    p.smelted[id]=p.smelted[id] or {0,0}
    p.smelted[id][1]=p.smelted[id][1]+1
end
function removeSmelted(p,id)
    p.smelted[id][1]=p.smelted[id][1]-1
    M.onTrinketRemoved(nil,p,id)
end
function tick(p,n) for _=1,(n or 1) do frame=frame+1; M.onPlayerUpdate(nil,p); M.onUpdate() end end
M=ConchBlessingRequire("scripts.items.collectibles.jobs_blessing")
T=M._test
-- The engine's collision of `pickup` with `p`: `gain` is what the engine
-- itself adds to `p` while taking it; `taken` false leaves it untaken.
function collide(p,pickup,gain,taken)
    M.onPrePickupCollision(nil,pickup,p)
    if taken ~= false then
        pickup.anim="Collect"
        if gain then gain(p) end
    end
    M.onPickupCollision(nil,pickup,p)
end
'''


class JobsBlessingTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().loadsource = source
        self.lua.execute(SETUP)

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_every_event_is_registered_late_and_the_windows_first(self):
        result = self.run_lua('''
            local late,first=0,{}
            for _,r in ipairs(registered) do
                if r.priority==CallbackPriority.LATE then late=late+1 end
                if r.priority==CallbackPriority.IMPORTANT then first[#first+1]=r.id end
            end
            table.sort(first)
            return M.available, #registered, late, table.concat(first," "),
                saveCallbacks.DATA_LOAD==M.onDataLoad, saveCallbacks.HOURGLASS==M.onHourglassReset
        ''')
        # the collision's numbers are read first, and an add closes first
        self.assertEqual(result, (True, 9, 7, '38 1005', True, True))

    def test_which_collectibles_double(self):
        result = self.run_lua('''
            local function d(id) return T.collectibleDoubles(id, items[id]) end
            return d(1), d(2), d(4), d(5), d(JOB), d(-5), d(3), d(77), d(0)
        ''')
        # passive, familiar, quest, hidden, the item itself, glitched | active, unknown, none
        self.assertEqual(result, (True, True, True, True, True, True, False, False, False))

    def test_a_first_time_acquisition_brings_one_copy_after_the_queue_settles(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            p.queueEmpty=false
            M.onAddCollectible(nil,1,0,true,0,0,p)       -- a pedestal's item lands
            tick(p,3)                                     -- still holding something up
            local held=p.inv[1] or 0
            p.queueEmpty=true
            tick(p)                                       -- one empty update: not yet
            local early=p.inv[1] or 0
            tick(p)
            local copy=p.adds[#p.adds]
            return held, early, p.inv[1], copy[2], copy[3]
        ''')
        self.assertEqual(result, (0, 0, 1, 0, True))

    def test_handed_back_actives_and_non_holders_stay_single(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            M.onAddCollectible(nil,1,0,false,0,0,p)       -- handed back (Kronos, a reroll)
            M.onAddCollectible(nil,3,0,true,0,0,p)        -- an active
            local q=player()
            M.onAddCollectible(nil,1,0,true,0,0,q)        -- no Job's Blessing
            local dead=player(); dead.inv[JOB]=1; dead.dead=true
            M.onAddCollectible(nil,1,0,true,0,0,dead)
            tick(p,3); tick(q,3); tick(dead,3)
            return #p.adds, #q.adds, #dead.adds, T.evidence().queued
        ''')
        self.assertEqual(result, (0, 0, 0, 0))

    def test_a_copy_and_any_add_while_it_is_given_never_double(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            -- another mod answers the copy at once (Two Faced Penny claims the next item)
            local answered=false
            local add=p.AddCollectible
            function p:AddCollectible(id,charge,first)
                add(self,id,charge,first)
                if id==1 and not answered then answered=true; add(self,1,0,true) end
            end
            M.onAddCollectible(nil,1,0,true,0,0,p)
            tick(p,2)
            tick(p,5)
            return p.inv[1], T.evidence().ignored
        ''')
        self.assertEqual(result, (2, 2))

    def test_another_mods_later_answer_to_a_copy_is_not_doubled_but_a_later_pickup_is(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            M.onAddCollectible(nil,1,0,true,0,0,p)
            tick(p,2)                                     -- the copy arrives at this frame
            local given=frame
            M.onAddCollectible(nil,1,0,true,0,0,p)        -- the same update: Multiplier Get's answer
            frame=frame+1
            M.onAddCollectible(nil,1,0,true,0,0,p)        -- the next update: still an answer
            local reactions=T.evidence().reactions
            frame=frame+1
            M.onAddCollectible(nil,1,0,true,0,0,p)        -- later: a new acquisition again
            local queued=#T.pending()[p.hash].list
            M.onAddCollectible(nil,2,0,true,0,0,p)        -- another item at once: its own acquisition
            return reactions, queued, #T.pending()[p.hash].list
        ''')
        self.assertEqual(result, (2, 1, 2))

    def test_healing_doubles_and_containers_broken_hearts_and_losses_do_not(self):
        result = self.run_lua('''
            local h=AddHealthType
            local out={}
            for _,k in ipairs({h.RED,h.SOUL,h.BLACK,h.ETERNAL,h.GOLDEN,h.BONE,h.ROTTEN}) do out[#out+1]=T.healAmount(2,k) end
            out[#out+1]=T.healAmount(2,h.MAX) or "nil"
            out[#out+1]=T.healAmount(1,h.BROKEN) or "nil"
            out[#out+1]=T.healAmount(-2,h.RED) or "nil"
            out[#out+1]=T.healAmount(0,h.RED) or "nil"
            out[#out+1]=T.healAmount(2,h.RED|h.MAX) or "nil"
            return table.concat(out," ")
        ''')
        self.assertEqual(result, '4 4 4 4 4 4 4 nil nil nil nil nil')

    def test_a_heart_addition_inside_another_doubles_only_once(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            -- a black heart: the engine adds its soul hearts through an inner add
            local outer=M.onAddHearts(nil,p,2,AddHealthType.BLACK)
            local inner=M.onAddHearts(nil,p,outer,AddHealthType.SOUL)
            M.onAddedHearts(nil,p); M.onAddedHearts(nil,p)
            local after=M.onAddHearts(nil,p,2,AddHealthType.SOUL)    -- the next addition is its own
            M.onAddedHearts(nil,p)
            -- a closing callback that never came is forgotten by the next update
            M.onAddHearts(nil,p,2,AddHealthType.RED)
            M.onUpdate()
            local fresh=M.onAddHearts(nil,p,2,AddHealthType.RED)
            return outer, inner or "nil", after, fresh
        ''')
        self.assertEqual(result, (4, 'nil', 4, 4))

    def test_hearts_an_item_gives_as_it_is_added_come_with_the_item_and_its_copy(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            local heals={}
            -- Breakfast-like: the item heals as it is added
            p.onItemAdded=function(self,id)
                if id==1 then
                    heals[#heals+1]=M.onAddHearts(nil,self,4,AddHealthType.RED) or 4
                    M.onAddedHearts(nil,self)
                end
            end
            p:AddCollectible(1,0,true)             -- the engine's own add of the pickup
            tick(p,2)                              -- the copy arrives
            local after=M.onAddHearts(nil,p,2,AddHealthType.RED)   -- a heal outside any add
            M.onAddedHearts(nil,p)
            -- an add another mod cancelled after ours opened it is forgotten next update
            M.onPreAddCollectible(nil,1,0,true,0,0,p)
            M.onUpdate()
            local cancelled=M.onAddHearts(nil,p,2,AddHealthType.RED)
            return p.inv[1], #heals, heals[1], heals[2], T.evidence().itemHearts, after, cancelled
        ''')
        self.assertEqual(result, (2, 2, 4, 4, 2, 4, 4))

    def test_a_heal_inside_a_pickup_collision_doubles_too(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            local heart=newPickup(PickupVariant.PICKUP_HEART,1)
            M.onPrePickupCollision(nil,heart,p)
            local inside=M.onAddHearts(nil,p,2,AddHealthType.RED)
            local q=player()
            local none=M.onAddHearts(nil,q,2,AddHealthType.RED)
            return inside, none or "nil"
        ''')
        self.assertEqual(result, (4, 'nil'))

    def test_a_pickup_adds_once_more_every_number_it_raised(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            p.active[0]=50; p.charge[0]=1; p.battery[0]=0
            collide(p,newPickup(PickupVariant.PICKUP_COIN,2),function(x) x.coins=x.coins+5 end)        -- a nickel
            collide(p,newPickup(PickupVariant.PICKUP_KEY,3),function(x) x.keys=x.keys+2 end)           -- a key ring
            collide(p,newPickup(PickupVariant.PICKUP_BOMB,2),function(x) x.bombs=x.bombs+2 end)        -- a double bomb
            collide(p,newPickup(PickupVariant.PICKUP_BOMB,7),function(x) x.giga=x.giga+1 end)          -- a giga bomb
            collide(p,newPickup(42,1),function(x) x.poop=x.poop+1 end)                                 -- a poop
            collide(p,newPickup(90,2),function(x) x.charge[0]=x.charge[0]+2 end)                       -- a micro battery
            local add=p.chargeAdds[1]
            return p.coins, p.keys, p.bombs, p.giga, p.poop, p.charge[0], add[2], add[3]
        ''')
        self.assertEqual(result, (10, 4, 4, 2, 2, 5, 0, False))

    def test_an_overcharge_is_repeated_only_when_the_pickup_overcharged(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            p.active[0]=50; p.charge[0]=6; p.battery[0]=0
            collide(p,newPickup(90,1),function(x) x.battery[0]=3 end)  -- full already: The Battery takes it
            return p.chargeAdds[1][1], p.chargeAdds[1][3]
        ''')
        self.assertEqual(result, (3, True))

    def test_a_bought_pickup_removed_in_its_collision_repeats_its_numbers(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1; p.coins=20
            -- measured: a key for sale is dead and gone in its POST collision, with no Collect
            local key=newPickup(PickupVariant.PICKUP_KEY,1)
            M.onPrePickupCollision(nil,key,p)
            p.coins=p.coins-5; p.keys=p.keys+1; key.dead=true; key.gone=true
            M.onPickupCollision(nil,key,p)
            -- only touched (too poor to buy): alive, nothing rose
            local other=newPickup(PickupVariant.PICKUP_KEY,1)
            M.onPrePickupCollision(nil,other,p)
            M.onPickupCollision(nil,other,p)
            return p.coins, p.keys
        ''')
        self.assertEqual(result, (15, 2))

    def test_a_pickup_that_fills_the_item_overcharges_its_repeat_only_with_the_battery(self):
        result = self.run_lua('''
            local out={}
            for _,battery in ipairs({true,false}) do
                local p=player(); p.inv[JOB]=1; p.hasBattery=battery
                p.active[0]=50; p.charge[0]=4; p.battery[0]=0
                collide(p,newPickup(90,2),function(x) x.charge[0]=6 end)   -- a micro battery fills it to the top
                out[#out+1]=string.format("%d/%d/%s",p.charge[0],p.battery[0],tostring(p.chargeAdds[1][3]))
            end
            return table.concat(out," ")
        ''')
        self.assertEqual(result, '6/2/true 6/0/false')

    def test_a_snapshot_left_by_a_cancelled_collision_never_reaches_the_next_one(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            M.onPrePickupCollision(nil,newPickup(PickupVariant.PICKUP_COIN,1),p)   -- another mod cancels: no POST
            p.coins=p.coins+3                                                       -- coins for another reason
            collide(p,newPickup(PickupVariant.PICKUP_TAROTCARD,1))                  -- a card taken the same update
            return p.coins, T.touching()[p.hash]==nil
        ''')
        self.assertEqual(result, (3, True))

    def test_saved_luck_is_applied_as_soon_as_the_save_loads(self):
        result = self.run_lua('''
            local p=player(); local q=player(); gamePlayers={p,q}
            saveCallbacks.DATA_LOAD(nil,{},false)
            return p.flagged, p.evaluated, q.evaluated
        ''')
        self.assertEqual(result, (1, 1, 1))

    def test_glowing_hourglass_starts_the_records_again(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1; gamePlayers={p}
            tick(p)                                       -- smelted baseline: none
            M.onAddCollectible(nil,1,0,true,0,0,p)        -- a copy on its way
            p.smelted[7]={1,0}                            -- the rewind gives back an absorbed trinket
            saveCallbacks.HOURGLASS()
            local queued=T.pending()[p.hash]
            for _=1,M.smeltSweep+2 do tick(p) end
            return queued==nil, p.inv[1] or 0, p.smelted[7][1], p.evaluated
        ''')
        self.assertEqual(result, (True, 0, 1, 1))

    def test_a_price_is_not_repeated_and_an_untaken_pickup_adds_nothing(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1; p.coins=20
            collide(p,newPickup(PickupVariant.PICKUP_KEY,1),function(x) x.coins=x.coins-5; x.keys=x.keys+1 end)
            local coins,keys=p.coins,p.keys
            collide(p,newPickup(PickupVariant.PICKUP_COIN,1),nil,false)   -- touched, not taken
            return coins, keys, p.coins
        ''')
        self.assertEqual(result, (15, 2, 15))

    def test_cards_pills_items_trinkets_and_non_holders_add_nothing(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            for _,v in ipairs({PickupVariant.PICKUP_TAROTCARD,PickupVariant.PICKUP_PILL,
                PickupVariant.PICKUP_COLLECTIBLE,PickupVariant.PICKUP_TRINKET}) do
                collide(p,newPickup(v,1),function(x) x.coins=x.coins+1 end)
            end
            local q=player()
            collide(q,newPickup(PickupVariant.PICKUP_COIN,2),function(x) x.coins=x.coins+5 end)
            local ghost=player(); ghost.inv[JOB]=1; ghost.ghost=true
            collide(ghost,newPickup(PickupVariant.PICKUP_COIN,2),function(x) x.coins=x.coins+5 end)
            return p.coins, q.coins, ghost.coins
        ''')
        self.assertEqual(result, (4, 5, 5))

    def test_a_lucky_pennys_luck_is_repeated_and_kept(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            collide(p,newPickup(PickupVariant.PICKUP_COIN,5),function(x) x.coins=x.coins+1; x.Luck=x.Luck+1 end)
            local now=runSaves[p.hash].jobsBlessing.luck
            collide(p,newPickup(PickupVariant.PICKUP_COIN,5),function(x) x.coins=x.coins+1; x.Luck=x.Luck+1 end)
            local later=runSaves[p.hash].jobsBlessing.luck
            p.inv[JOB]=nil
            M.onEvaluateCache(nil,p,CacheFlag.CACHE_LUCK)            -- kept without the item
            return p.coins, now, later, luckApplied[p.hash]
        ''')
        self.assertEqual(result, (4, 1, 2, 2))

    def test_luck_that_rises_later_for_another_reason_is_not_doubled(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            collide(p,newPickup(PickupVariant.PICKUP_COIN,1),function(x) x.coins=x.coins+1 end)
            p.Luck=p.Luck+1; tick(p)                                 -- an unrelated luck up next update
            return runSaves[p.hash]==nil or runSaves[p.hash].jobsBlessing==nil or runSaves[p.hash].jobsBlessing.luck==nil
        ''')
        self.assertTrue(result)

    def test_every_absorption_is_repeated_whenever_the_count_rises(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            tick(p)                                        -- the baseline
            p:AddSmeltedTrinket(7,true)                    -- seen at the event
            tick(p)
            local direct=p.smelted[7][1]
            smelterSmelt(p,7)                              -- seen only after the event
            tick(p)
            local smelter=p.smelted[7][1]
            p:AddSmeltedTrinket(7|32768,false)             -- golden
            tick(p)
            return direct, smelter, p.smelted[7][2], #p.smelts
        ''')
        self.assertEqual(result, (2, 4, 2, 5))

    def test_a_removal_in_the_same_update_never_hides_an_absorption(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            tick(p)
            p:AddSmeltedTrinket(9,false); p:AddSmeltedTrinket(9,false)   -- two absorptions
            removeSmelted(p,9)                                            -- a Conch Debris trio leaves
            tick(p)
            local after=p.smelted[9][1]
            for _=1,M.smeltSweep+1 do tick(p) end
            return after, p.smelted[9][1]
        ''')
        self.assertEqual(result, (3, 3))

    def test_trinkets_held_before_the_item_and_smelts_without_it_are_not_doubled(self):
        result = self.run_lua('''
            local p=player()
            p.smelted[4]={2,0}
            p:AddSmeltedTrinket(4,true)                    -- no Job's Blessing yet
            p.inv[JOB]=1
            tick(p)                                        -- baseline: three smelted
            for _=1,M.smeltSweep+1 do tick(p) end
            local kept=p.smelted[4][1]
            p.inv[JOB]=nil; tick(p)
            p:AddSmeltedTrinket(4,true)
            for _=1,M.smeltSweep+1 do tick(p) end
            return kept, p.smelted[4][1], T.smelted()[p.hash]==nil
        ''')
        self.assertEqual(result, (3, 4, True))

    def test_a_silent_absorption_is_caught_by_the_sweep(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            tick(p)
            p.smelted[6]={1,0}                             -- no event at all
            tick(p)
            local early=p.smelted[6][1]
            for _=1,M.smeltSweep do tick(p) end
            return early, p.smelted[6][1]
        ''')
        self.assertEqual(result, (1, 2))

    def test_game_start_and_exit_forget_every_runtime_record(self):
        result = self.run_lua('''
            local p=player(); p.inv[JOB]=1
            M.onAddCollectible(nil,1,0,true,0,0,p)
            collide(p,newPickup(PickupVariant.PICKUP_COIN,1),function(x) x.coins=x.coins+1 end)
            tick(p)
            M.onGameExit()
            return next(T.pending())==nil, next(T.smelted())==nil
        ''')
        self.assertEqual(result, (True, True))


class RegistryTests(unittest.TestCase):
    def test_registry_row_locale_and_xml(self):
        items = (ROOT / 'scripts' / 'conch_blessing_items.lua').read_text(encoding='utf-8')
        start = items.index('    JOBS_BLESSING = {')
        row = items[start:items.index('\n    },', start)]
        self.assertIn('id = Isaac.GetItemIdByName("Job\'s Blessing")', row)
        self.assertIn('origin = { id = CollectibleType.COLLECTIBLE_DAMOCLES, type = "collectible" }', row)
        self.assertIn('flag = "positive"', row)
        self.assertIn('type = "passive"', row)
        self.assertNotIn('stackable', row)            # one copy or many: always twice
        # Before the zodiac block (new collectibles go there).
        self.assertLess(start, items.index('    RAT = {'))
        kr = (ROOT / 'scripts' / 'locale' / 'kr.lua').read_text(encoding='utf-8')
        self.assertIn('description = "이전 모든 소유보다 갑절을 주신지라"', kr)   # user-designated, verbatim
        self.assertIn('name = "욥의 축복"', kr)
        xml = (ROOT / 'content' / 'items.xml').read_text(encoding='utf-8')
        self.assertIn('name="Job\'s Blessing" gfx="jobs_blessing.png" quality="4"', xml)
        self.assertTrue((ROOT / 'resources' / 'gfx' / 'items' / 'collectibles' / 'jobs_blessing.png').is_file())

    def test_every_locale_names_the_repentogon_requirement(self):
        for lang, line in (('en', 'Requires REPENTOGON!'), ('kr', 'REPENTOGON이 필요합니다!'),
                           ('urimal', '덧붙임 도우미(REPENTOGON)가 있어야 합니다!')):
            text = (ROOT / 'scripts' / 'locale' / (lang + '.lua')).read_text(encoding='utf-8')
            start = text.index('        JOBS_BLESSING = {')
            block = text[start:text.index('\n        },', start)]
            self.assertIn(line, block, lang)


if __name__ == '__main__':
    unittest.main()
