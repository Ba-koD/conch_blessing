"""시리얼 (Cereal) through its shipped Lua: the user's design (2026-11-24) is
Breakfast's positive answer, a zero-charge active. Used while an item is held
up it breaks that item into its number's cereal pickups (as the number is
written; Breakfast gives three random ones); used otherwise it opens a bowl
where the shooting keys put cereal in, centred, and the use key makes the item
of that number for one milk (a passive is held up and taken, an active stands
on a pedestal), a number with no item being cancelled with nothing spent. Every
draw becomes Breakfast with chance 1/2 ^ milk while anyone holds it. These are
Lua regressions with doubles, not proof of engine behaviour (`cb test cereal`).
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / (name.replace('.', '/') + '.lua')).read_text(encoding='utf-8')


SETUP = r'''
package=nil
local cache={
    ['scripts.lib.conch_answer_view']={text=function(k,...) local a={...} return k..(#a>0 and ':'..table.concat(a,'|') or '') end,
        width=function() return 10 end,drawAt=function() end,lineHeight=function() return 8 end},
    ['scripts.lib.sound_volume']={volume=function(v) return v end},
}
function ConchBlessingRequire(name)
    if not cache[name] then cache[name]=load(loadsource(name),name)() end
    return cache[name]
end
CEREAL=780
CollectibleType={COLLECTIBLE_BREAKFAST=25}
ItemType={ITEM_PASSIVE=1,ITEM_TRINKET=2,ITEM_ACTIVE=3,ITEM_FAMILIAR=4}
ItemConfig={TAG_QUEST=1<<15}
ActiveSlot={SLOT_PRIMARY=0,SLOT_SECONDARY=1,SLOT_POCKET=2,SLOT_POCKET2=3}
ButtonAction={ACTION_SHOOTLEFT=4,ACTION_SHOOTRIGHT=5,ACTION_SHOOTUP=6,ACTION_SHOOTDOWN=7,ACTION_ITEM=9,
    ACTION_PILLCARD=10,ACTION_DROP=11,ACTION_LEFT=0,ACTION_PAUSE=12,ACTION_MENUBACK=15}
InputHook={IS_ACTION_PRESSED=0,IS_ACTION_TRIGGERED=1,GET_ACTION_VALUE=2}
UseFlag={USE_CARBATTERY=1<<5,USE_NOANIM=1<<0,USE_OWNED=1<<1}
SoundEffect={SOUND_PLOP=237,SOUND_MENU_FLIP_LIGHT=569,SOUND_MENU_FLIP_DARK=570,SOUND_BOSS2INTRO_ERRORBUZZ=187,
    SOUND_BONE_SNAP=40,SOUND_VAMP_GULP=50}
EntityType={ENTITY_PICKUP=5}
PickupVariant={PICKUP_COLLECTIBLE=100}
EntityCollisionClass={ENTCOLL_NONE=0}
GridCollisionClass={COLLISION_NONE=0}
ModCallbacks={MC_PRE_USE_ITEM=23,MC_POST_PICKUP_INIT=34,MC_POST_PICKUP_UPDATE=35,MC_PRE_PICKUP_COLLISION=38,MC_PRE_GET_COLLECTIBLE=62,
    MC_POST_ADD_COLLECTIBLE=1004,MC_POST_PLAYERHUD_RENDER_ACTIVE_ITEM=1080,MC_POST_PLAYER_INIT=9,
    MC_POST_GAME_STARTED=15,MC_PRE_GAME_EXIT=17,MC_POST_NEW_ROOM=19,MC_POST_NEW_LEVEL=18}
CallbackPriority={EARLY=-100,LATE=100}
played={}
function SFXManager() return {Play=function(_,id) played[#played+1]=id end} end
local V={}
V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
V.__mul=function(a,k) return Vector(a.X*k,a.Y*k) end
function V:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
Vector.Zero=Vector(0,0)
Vector.FromAngle=function(a) return Vector(math.cos(math.rad(a)),math.sin(math.rad(a))) end
function Color(r,g,b,a) return {r,g,b,a} end
function KColor(r,g,b,a) return {r,g,b,a} end
function EntityPtr(e) return {Ref=e} end
function GetPtrHash(e) return e.hash end
-- A small LCG so a seed always rolls the same.
function RNG()
    local r={s=1}
    function r:SetSeed(s) self.s=s % 2147483647; if self.s==0 then self.s=1 end end
    function r:Next() self.s=(self.s*48271) % 2147483647; return self.s end
    function r:RandomFloat() return self:Next()/2147483647 end
    function r:RandomInt(n) return self:Next() % n end
    return r
end
keys={}
Input={IsActionPressed=function(action) return keys[action]==true end}
items={
    [4]={Type=1}, [25]={Type=1}, [105]={Type=3}, [118]={Type=1}, [182]={Type=1}, [300]={Type=1,quest=true},
    [301]={Type=1,Hidden=true}, [302]={Type=1}, [303]={Type=1,locked=true}, [780]={Type=3},
}
for id,item in pairs(items) do
    item.ID=id; item.GfxFileName='gfx/x.png'; item.InitCharge=0
    item.HasTags=function(self,tag) return self.quest==true and tag==ItemConfig.TAG_QUEST end
    item.IsAvailable=function(self) return not self.locked end
end
pooled={4,25,105,118,182,300,303,780} -- 302 is in no pool, 301 hidden
spawned={}
regs={}
paused=false
frame=100
roomFrame=50
room={IsPositionInRoom=function() return true end,GetGridCollisionAtPos=function() return 0 end,
    FindFreePickupSpawnPosition=function(_,pos) return pos end,GetFrameCount=function() return roomFrame end}
local function entity(t,v,sub,pos,vel,spawner,seed)
    local e={Type=t,Variant=v,SubType=sub,Position=pos,Velocity=vel,Seed=seed,Spawner=spawner,removed=false}
    e.ToPickup=function(self) return self end
    spawned[#spawned+1]=e
    return e
end
hudShown={}
function Game() return {GetRoom=function() return room end,IsPaused=function() return paused end,
    GetFrameCount=function() return frame end,
    GetNumPlayers=function() return #(players or {}) end,
    Spawn=function(_,t,v,pos,vel,spawner,sub,seed) return entity(t,v,sub,pos,vel,spawner,seed) end,
    GetHUD=function() return {ShowItemText=function(_,p,c) hudShown[#hudShown+1]=c.ID end} end,
    GetItemPool=function() return {GetNumItemPools=function() return 1 end,
        GetCollectiblesFromPool=function(_,k) local out={} for _,id in ipairs(pooled) do out[#out+1]={itemID=id} end return out end}
    end} end
runSave={}
ConchBlessing={printDebug=function() end,printError=function(m) lastError=m end,ItemData={},
    SaveManager={IsLoaded=function() return true end,GetRunSave=function(e) return runSave end,
        TryGetRunSave=function(e) return runSave end},
    AddCallback=function(_,cb,fn,filter) regs[#regs+1]={cb=cb,fn=fn,filter=filter} end,
    AddPriorityCallback=function(_,cb,pri,fn,filter) regs[#regs+1]={cb=cb,fn=fn,filter=filter,pri=pri} end}
Isaac={GetItemIdByName=function(name) return name=='Cereal' and CEREAL or -1 end,
    GetEntityVariantByName=function(name) return name=='Conch Blessing Cereal 0' and 7792 or -1 end,
    GetItemConfig=function() return {GetCollectibles=function() return {Size=733} end,
        GetCollectible=function(_,id) return items[id] end} end,
    WorldToScreen=function(p) return p end,
    GetFrameCount=function() return frame end,
    Spawn=function(t,v,sub,pos,vel,spawner) return entity(t,v,sub,pos,vel,spawner) end,
    GetPlayer=function(i) return players[i+1] end}
function player(slotItem)
    local p={hash=#(players or {})+1,ControllerIndex=0,Position=Vector(100,100),dead=false,
        active={[0]=slotItem==nil and CEREAL or slotItem},queue={Item=nil},queued={},lifted={}}
    p.QueuedItem=p.queue
    function p:GetActiveItem(slot) return self.active[slot] or 0 end
    function p:HasCollectible(id) for _,a in pairs(self.active) do if a==id then return true end end return false end
    function p:IsItemQueueEmpty() return self.QueuedItem.Item==nil end
    function p:GetCollectibleRNG() local r=RNG(); r:SetSeed(12345); return r end
    function p:StopExtraAnimation() self.stopped=true end
    function p:AnimatePickup(s,hide,anim) self.lifted[#self.lifted+1]=anim end
    function p:AnimateCollectible(id,anim) self.animated=id; self.animation=anim end
    -- the engine's flush: the queue empties, then the addition goes through
    -- MC_PRE_ADD_COLLECTIBLE, which may refuse it
    function p:GetCollectibleNum(id) return (self.owned or {})[id] or 0 end
    function p:AddCollectible(id)
        if M.onPreAddCollectible(nil,id,0,true,0,0,self)==false then return end
        self.owned=self.owned or {}; self.owned[id]=(self.owned[id] or 0)+1
    end
    function p:FlushQueueItem()
        local item=self.QueuedItem.Item
        if not item then return false end
        self.QueuedItem={Item=nil}
        self:AddCollectible(item.ID)
        return true
    end
    function p:QueueItem(config) self.queued[#self.queued+1]=config.ID end
    -- the engine's use: MC_PRE_USE_ITEM may cancel it, else MC_USE_ITEM runs
    function p:UseActiveItem(id,flags,slot)
        self.uses=(self.uses or 0)+1
        if not M.onPreUseItem(nil,id,nil,self,flags,slot) then M.onUseItem(nil,id,nil,self,flags,slot) end
    end
    function p:Exists() return true end
    function p:IsDead() return self.dead end
    function p:ToPlayer() return self end
    players=players or {}
    players[#players+1]=p
    return p
end
function hold(p,id) p.QueuedItem={Item=items[id]} end
function pickup(d,age)
    local e={SubType=d,FrameCount=age or 30,Position=Vector(50,50),PositionOffset=Vector(0,0),data={},removed=false,
        EntityCollisionClass=1}
    function e:GetData() return self.data end
    function e:Remove() self.removed=true end
    return e
end
Sprite=function()
    local s={}
    function s:Load() end
    function s:SetFrame() end
    function s:Play(name) self.playing=name end
    function s:ReplaceSpritesheet() end
    function s:LoadGraphics() end
    function s:IsFinished() return false end
    function s:Update() end
    function s:Render() end
    return s
end
M=ConchBlessingRequire('scripts.items.collectibles.cereal')
T=M._test
function list(t) local out={} for i,v in ipairs(t) do out[i]=tostring(v) end return table.concat(out,',') end
function digits() local out={} for d=0,9 do out[#out+1]=M.count(d) end return table.concat(out,'') end
function subtypes() local out={} for _,e in ipairs(spawned) do if e.Variant==7792 then out[#out+1]=e.SubType end end return list(out) end
'''


class CerealTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().loadsource = source
        self.lua.execute(SETUP)

    def run_lua(self, code):
        return self.lua.execute(code)

    # -------------------------------------------------------------- numbers
    def test_numbers_are_written_as_they_are(self):
        # User request 2026-11-24: 2, not 002.
        result = self.run_lua('return list(M.digitsOf(4)), list(M.digitsOf(25)), list(M.digitsOf(118)), list(M.digitsOf(1043))')
        self.assertEqual(result, ('4', '2,5', '1,1,8', '1,0,4,3'))

    def test_the_bowl_has_as_many_slots_as_the_highest_number_needs(self):
        result = self.run_lua('return T.maxDigits(732), T.maxDigits(999), T.maxDigits(1200), T.maxDigits(12)')
        self.assertEqual(result, (3, 3, 4, 2))

    def test_a_number_never_starts_with_zero_and_fits_the_slots(self):
        result = self.run_lua('''
            return T.canAdd({},4,0), T.canAdd({},4,4), T.canAdd({1},4,0), T.canAdd({1,1,5},4,0),
                T.canAdd({1,1,5},3,0), T.canAdd({1,1,5,0},4,2)
        ''')
        self.assertEqual(result, (False, True, True, True, False, False))

    def test_what_a_number_makes(self):
        result = self.run_lua('''
            local function s(t) local st=M.lookup(t); return st end
            return s({}), s({0,0,4}), s({5,0,0}), s({3,0,1}), s({3,0,0}), s({3,0,2}), s({3,0,3}),
                s({1,1,8}), s({4}), s({9,9,9}), s({1,1})
        ''')
        # Nothing in is short; a leading 0 is no number; 500 and 999 are past
        # the last item; 301 hidden, 300 a quest item, 302 in no pool, 303
        # locked; 4 is item 4 on its own; 11 is no item in the doubles.
        self.assertEqual(result, ('short', 'none', 'none', 'nocraft', 'nocraft', 'nocraft', 'nocraft',
                                  'ok', 'ok', 'none', 'none'))

    # -------------------------------------------------------------- milk
    def test_the_milk_chance_halves_with_every_milk(self):
        result = self.run_lua('return M.milkChance(0), M.milkChance(1), M.milkChance(2), M.milkChance(5)')
        self.assertEqual(result, (1.0, 0.5, 0.25, 0.03125))

    def test_with_no_milk_every_draw_is_breakfast_and_without_a_holder_none(self):
        result = self.run_lua('''
            local none=M.onPreGetCollectible(nil,0,true,11)
            player()
            local out={}
            for seed=1,20 do out[#out+1]=M.onPreGetCollectible(nil,0,true,seed) end
            return tostring(none), list(out)
        ''')
        self.assertEqual(result[0], 'nil')
        self.assertEqual(result[1], ','.join(['25'] * 20))

    def test_draws_turn_to_breakfast_about_as_often_as_the_rule_says(self):
        result = self.run_lua('''
            player(); M.addMilk(2)
            local n=0
            for seed=1,4000 do if M.onPreGetCollectible(nil,0,true,seed*7919)==25 then n=n+1 end end
            return n
        ''')
        self.assertAlmostEqual(result / 4000, 0.25, delta=0.03)

    def test_underdog_peeks_and_conch_pearl_redraws_are_left_alone(self):
        result = self.run_lua('''
            player()
            ConchBlessing.underdog={isPeeking=function() return true end}
            local a=M.onPreGetCollectible(nil,0,false,3)
            ConchBlessing.underdog=nil
            ConchBlessing.conchpearl={isRedrawing=function() return true end}
            local b=M.onPreGetCollectible(nil,0,true,3)
            return tostring(a), tostring(b)
        ''')
        self.assertEqual(result, ('nil', 'nil'))

    def test_a_breakfast_taken_while_anyone_holds_cereal_is_one_milk(self):
        result = self.run_lua('''
            M.onAddBreakfast(nil,25,0,true)
            local before=M.milk()
            player()
            M.onAddBreakfast(nil,25,0,true)
            M.onAddBreakfast(nil,25,0,false)
            M.onAddBreakfast(nil,118,0,true)
            return before, M.milk()
        ''')
        self.assertEqual(result, (0, 1))

    # -------------------------------------------------------------- breaking
    def test_an_item_held_up_breaks_into_its_number(self):
        result = self.run_lua('''
            local p=player(); hold(p,118)
            local ok,id=M.breakHeld(p)
            return ok, id, tostring(p.QueuedItem.Item), subtypes(), p:GetCollectibleNum(118),
                tostring(p.stopped), p.animated==CEREAL and p.animation
        ''')
        # The engine empties the queue and its addition is refused; the hold-up
        # becomes Cereal's own use, never cut short (user report 2026-11-24).
        self.assertEqual(result, (True, 118, 'nil', '1,1,8', 0, 'nil', 'UseItem'))

    def test_only_the_broken_addition_is_refused(self):
        # An addition before or after a break, of the same item or another,
        # goes through.
        result = self.run_lua('''
            local p=player()
            p:AddCollectible(118)
            hold(p,118); M.breakHeld(p)
            p:AddCollectible(118); p:AddCollectible(182)
            return p:GetCollectibleNum(118), p:GetCollectibleNum(182)
        ''')
        self.assertEqual(result, (2, 1))

    def test_without_the_engine_flush_nothing_breaks(self):
        result = self.run_lua('''
            local p=player(); p.FlushQueueItem=nil; hold(p,118)
            return M.breakHeld(p), subtypes(), tostring(p.QueuedItem.Item ~= nil), lastError ~= nil
        ''')
        self.assertEqual(result, (False, '', 'true', True))

    def test_an_addition_that_is_not_refused_breaks_nothing(self):
        # Another mod could add the item before ours refuses it: fail closed.
        result = self.run_lua('''
            local p=player(); hold(p,118)
            p.FlushQueueItem=function(self)
                local item=self.QueuedItem.Item
                self.QueuedItem={Item=nil}
                self.owned={[item.ID]=1}
                return true
            end
            return M.breakHeld(p), subtypes(), lastError ~= nil
        ''')
        self.assertEqual(result, (False, '', True))

    def test_the_broken_number_lies_in_a_row_in_its_order(self):
        # Not scattered (user request): left to right in front of the player,
        # still, an even step apart.
        result = self.run_lua('''
            local p=player(); hold(p,118); M.breakHeld(p)
            local out={}
            for _,e in ipairs(spawned) do
                out[#out+1]=string.format('%d@%d,%d v%d,%d',e.SubType,e.Position.X,e.Position.Y,e.Velocity.X,e.Velocity.Y)
            end
            return table.concat(out,' ')
        ''')
        self.assertEqual(result, '1@80,140 v0,0 1@100,140 v0,0 8@120,140 v0,0')

    def test_a_blocked_front_puts_the_row_above(self):
        result = self.run_lua('''
            room.GetGridCollisionAtPos=function(_,pos) return pos.Y>100 and 1 or 0 end
            local p=player(); hold(p,182); M.breakHeld(p)
            local out={}
            for _,e in ipairs(spawned) do out[#out+1]=string.format('%d@%d,%d',e.SubType,e.Position.X,e.Position.Y) end
            return table.concat(out,' ')
        ''')
        self.assertEqual(result, '1@80,60 8@100,60 2@120,60')

    def test_item_four_breaks_into_a_single_four(self):
        result = self.run_lua('local p=player(); hold(p,4); M.breakHeld(p); return subtypes()')
        self.assertEqual(result, '4')

    def test_breakfast_breaks_into_three_random_digits(self):
        result = self.run_lua('''
            local p=player(); hold(p,25); M.breakHeld(p)
            local out={}
            for _,e in ipairs(spawned) do out[#out+1]=e.SubType end
            return #out, math.min(table.unpack(out)) >= 0 and math.max(table.unpack(out)) <= 9,
                subtypes() ~= '0,2,5'
        ''')
        self.assertEqual(result, (3, True, True))

    def test_a_held_up_item_is_watched_and_the_use_key_breaks_it(self):
        result = self.run_lua('''
            local p=player(); hold(p,182)
            M.onUpdate()
            local watched=T.watch(p) ~= nil
            local kept=M.onInputAction(nil,p,InputHook.IS_ACTION_TRIGGERED,ButtonAction.ACTION_ITEM)
            keys[ButtonAction.ACTION_ITEM]=true; M.onUpdate()
            local after=subtypes()
            local still=M.onInputAction(nil,p,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_ITEM)
            keys[ButtonAction.ACTION_ITEM]=nil; M.onUpdate()
            local released=M.onInputAction(nil,p,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_ITEM)
            return watched, kept, after, still, tostring(released), M.picking(p)
        ''')
        self.assertEqual(result, (True, False, '1,8,2', False, 'nil', False))

    def test_a_key_already_down_when_the_item_is_lifted_breaks_nothing(self):
        result = self.run_lua('''
            local p=player(); keys[ButtonAction.ACTION_ITEM]=true; hold(p,118)
            M.onUpdate(); M.onUpdate()
            return subtypes(), tostring(p.QueuedItem.Item ~= nil)
        ''')
        self.assertEqual(result, ('', 'true'))

    def test_a_use_while_holding_up_an_item_breaks_it(self):
        result = self.run_lua('''
            local p=player(); hold(p,118)
            local r=M.onUseItem(nil,CEREAL,nil,p,0,0)
            return r.Discharge, subtypes(), M.picking(p)
        ''')
        self.assertEqual(result, (False, '1,1,8', False))

    def test_a_trinket_being_picked_up_is_not_broken(self):
        result = self.run_lua('''
            local p=player(); p.QueuedItem={Item={ID=5,Type=ItemType.ITEM_TRINKET}}
            return M.breakHeld(p), subtypes()
        ''')
        self.assertEqual(result, (False, ''))

    # -------------------------------------------------------------- pickups
    def test_touching_a_cereal_takes_it_once(self):
        result = self.run_lua('''
            local p=player()
            local e=pickup(8)
            local first=M.onPickupCollision(nil,e,p)
            local second=M.onPickupCollision(nil,e,p)
            return first, second, e.removed, digits(), T.bits()
        ''')
        self.assertEqual(result, (True, True, True, '0000000010', 1))

    def test_a_cereal_just_dropped_cannot_be_taken_yet(self):
        result = self.run_lua('''
            local p=player()
            local e=pickup(3,2)
            return tostring(M.onPickupCollision(nil,e,p)), e.removed, digits()
        ''')
        self.assertEqual(result, ('nil', False, '0000000000'))

    def test_a_dead_player_takes_nothing(self):
        result = self.run_lua('''
            local p=player(); p.dead=true
            return tostring(M.onPickupCollision(nil,pickup(3),p)), digits()
        ''')
        self.assertEqual(result, ('nil', '0000000000'))

    # -------------------------------------------------------------- the bowl
    def test_without_milk_the_bowl_opens_to_look_and_makes_nothing(self):
        # The bowl is also how the cereal held are looked at (user request
        # 2026-11-24), so it opens without milk; confirming then makes nothing.
        result = self.run_lua('''
            local p=player(); M.addDigit(1,2); M.addDigit(8,1)
            local r=M.onUseItem(nil,CEREAL,nil,p,0,0)
            local open=M.picking(p)
            T.type(p,{1,1,8})
            local ok,why=T.confirm(p)
            return r.Discharge, open, ok, why, M.picking(p), T.toast(p), digits(), list(p.queued)
        ''')
        self.assertEqual(result, (False, True, False, 'NO_MILK', True, 'ui.cereal.no_milk', '0200000010', ''))

    def test_the_use_key_on_an_empty_bowl_closes_it(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            keys[ButtonAction.ACTION_ITEM]=nil; M.onUpdate()
            keys[ButtonAction.ACTION_ITEM]=true; M.onUpdate()
            return M.picking(p), M.milk(), #spawned, list(p.queued),
                M.onInputAction(nil,p,InputHook.IS_ACTION_TRIGGERED,ButtonAction.ACTION_ITEM)
        ''')
        self.assertEqual(result, (False, 1, 0, '', False))

    def test_the_bowl_makes_a_passive_and_spends_its_cereal_and_milk(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(2); M.addDigit(1,2); M.addDigit(8,1); M.addDigit(3,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            local open=M.picking(p)
            T.type(p,{1,1,8})
            local ok,id=T.confirm(p)
            return open, ok, id, list(p.queued), p.animated, list(hudShown), digits(), M.milk(), M.picking(p)
        ''')
        self.assertEqual(result, (True, True, 118, '118', 118, '118', '0001000000', 1, False))

    def test_an_active_is_set_down_on_a_pedestal_nearby(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(1,1); M.addDigit(0,1); M.addDigit(5,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            T.type(p,{1,0,5})
            T.confirm(p)
            local e=spawned[#spawned]
            return e.Variant, e.SubType, e.Position.X, e.Position.Y, list(p.queued), M.milk(), digits()
        ''')
        self.assertEqual(result, (100, 105, 100, 160, '', 0, '0000000000'))

    def test_a_number_with_no_item_is_cancelled_with_nothing_spent(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(6,3)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            T.type(p,{6,6,6})
            local ok,why=T.confirm(p)
            return ok, why, T.toast(p), M.milk(), digits(), M.picking(p), #spawned
        ''')
        self.assertEqual(result, (False, 'none', 'ui.cereal.cancel_none:666', 1, '0000003000', False, 0))

    def test_an_item_the_bowl_may_not_make_is_cancelled(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(3,1); M.addDigit(0,1); M.addDigit(2,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            T.type(p,{3,0,2})
            local ok,why=T.confirm(p)
            return ok, why, T.toast(p), M.milk(), digits()
        ''')
        self.assertEqual(result, (False, 'nocraft', 'ui.cereal.cancel_nocraft:302', 1, '1011000000'))

    def test_a_single_digit_makes_its_item(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(4,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            T.type(p,{4})
            local ok,id=T.confirm(p)
            return ok, id, list(p.queued), M.milk(), digits()
        ''')
        self.assertEqual(result, (True, 4, '4', 0, '0000000000'))

    def test_the_cereal_in_the_bowl_stay_centred(self):
        # User request 2026-11-24: whatever the count, the group sits in the
        # middle of the bowl (10 wide, 11 apart); the others slide aside.
        result = self.run_lua('''
            local out={}
            for n=1,4 do
                local left=M.centred(n,1)
                local right=M.centred(n,n)+10
                out[#out+1]=string.format('%g:%g',left,right)
            end
            return table.concat(out,' ')
        ''')
        self.assertEqual(result, '-5:5 -10.5:10.5 -16:16 -21.5:21.5')

    def test_zero_cannot_go_in_first(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(0,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            return T.type(p,{0}), #T.picker(p).entered
        ''')
        self.assertEqual(result, (False, 0))

    def test_cereal_not_held_cannot_be_put_in(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(1,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            return T.type(p,{1,1}), list(T.picker(p).entered)
        ''')
        self.assertEqual(result, (False, '1'))

    def test_the_keys_drive_the_bowl(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(1,2); M.addDigit(8,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            local function tap(action) keys[action]=true; M.onUpdate(); keys[action]=nil; M.onUpdate() end
            -- down puts the framed cereal in, up takes the last one out (user request)
            tap(ButtonAction.ACTION_SHOOTRIGHT)   -- 1
            tap(ButtonAction.ACTION_SHOOTDOWN); tap(ButtonAction.ACTION_SHOOTDOWN)
            tap(ButtonAction.ACTION_SHOOTLEFT); tap(ButtonAction.ACTION_SHOOTLEFT); tap(ButtonAction.ACTION_SHOOTLEFT) -- 8
            tap(ButtonAction.ACTION_SHOOTDOWN)
            tap(ButtonAction.ACTION_SHOOTUP)      -- take the 8 out again
            tap(ButtonAction.ACTION_SHOOTDOWN)
            local typed=list(T.picker(p).entered)
            keys[ButtonAction.ACTION_ITEM]=true; M.onUpdate()
            return typed, list(p.queued), M.picking(p)
        ''')
        self.assertEqual(result, ('1,1,8', '118', False))

    def test_the_drop_key_closes_the_bowl_with_nothing_spent(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(1,3)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            T.type(p,{1,1,1})
            keys[ButtonAction.ACTION_DROP]=true; M.onUpdate()
            return M.picking(p), M.milk(), digits(), list(p.lifted),
                M.onInputAction(nil,p,InputHook.IS_ACTION_TRIGGERED,ButtonAction.ACTION_DROP)
        ''')
        self.assertEqual(result, (False, 1, '0300000000', 'LiftItem,HideItem', False))

    def test_up_takes_out_the_last_cereal_put_in_and_shows_both_motions(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(1,1); M.addDigit(2,1); M.addDigit(3,1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            local function tap(action) keys[action]=true; M.onUpdate(); keys[action]=nil; M.onUpdate() end
            for _,d in ipairs({1,2,3}) do
                while T.picker(p).sel~=d do tap(ButtonAction.ACTION_SHOOTRIGHT) end
                tap(ButtonAction.ACTION_SHOOTDOWN)
            end
            local ins=#T.picker(p).fx
            tap(ButtonAction.ACTION_SHOOTUP)
            local fx=T.picker(p).fx
            local last=fx[#fx]
            return list(T.picker(p).entered), ins, last.kind, last.d, last.slot
        ''')
        self.assertEqual(result, ('1,2', 3, 'out', 3, 3))

    def test_esc_closes_the_bowl_and_pause_is_kept_from_the_game(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(1,3)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            T.type(p,{1,1})
            local pausedWhileOpen=M.onInputAction(nil,nil,InputHook.IS_ACTION_TRIGGERED,ButtonAction.ACTION_PAUSE)
            keys[ButtonAction.ACTION_PAUSE]=true; M.onUpdate()
            local closed=not M.picking(p)
            local stillKept=M.onInputAction(nil,nil,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_PAUSE)
            keys[ButtonAction.ACTION_PAUSE]=nil; M.onUpdate()
            local released=M.onInputAction(nil,nil,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_PAUSE)
            return pausedWhileOpen, closed, stillKept, tostring(released), M.milk(), digits()
        ''')
        self.assertEqual(result, (False, True, False, 'nil', 1, '0300000000'))

    def test_shooting_keys_belong_to_the_bowl_and_moving_stays_free(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            return M.onInputAction(nil,p,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_SHOOTLEFT),
                M.onInputAction(nil,p,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_SHOOTUP),
                tostring((M.onInputAction(nil,p,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_LEFT)))
        ''')
        self.assertEqual(result, (False, 0.0, 'nil'))

    def test_a_new_room_closes_the_bowl(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            M.onNewRoom()
            return M.picking(p), M.milk()
        ''')
        self.assertEqual(result, (False, 1))

    def test_picking_up_an_item_closes_the_bowl(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1)
            M.onUseItem(nil,CEREAL,nil,p,0,0)
            hold(p,118); M.onUpdate()
            return M.picking(p), M.milk()
        ''')
        self.assertEqual(result, (False, 1))

    def test_a_car_battery_second_use_does_nothing(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1)
            local r=M.onUseItem(nil,CEREAL,nil,p,UseFlag.USE_CARBATTERY,0)
            return r.Discharge, M.picking(p)
        ''')
        self.assertEqual(result, (False, False))

    # -------------------------------------------------------------- layout
    def test_the_bowl_rows_never_overlap(self):
        # Above the bowl from the bottom up: the counts (clear of the cereal in
        # the bowl, which reach 3 above its top), the cereal row (12 tall, the
        # framed one 4 higher), the icon (24 tall), the name and the note.
        result = self.run_lua('''
            local bad={}
            for _,active in ipairs({false,true}) do
                for _,h in ipairs({{8,6,9},{12,9,10},{6,5,7}}) do
                    local nameH,noteH,countH=h[1],h[2],h[3]
                    local L=M.layout(200,151,active,nameH,noteH,countH)
                    local rows={{L.noteY,L.noteY+noteH,'note',active},{L.nameY,L.nameY+nameH,'name',true},
                        {L.iconY-12,L.iconY+12,'icon',true},{L.digitsTop-4,L.digitsTop+12,'digits',true},
                        {L.countsY,L.countsY+countH,'counts',true},{L.bowlTop-3,L.bowlTop+21,'bowl',true}}
                    local last=nil
                    for _,r in ipairs(rows) do
                        if r[4] then
                            if last and r[1] < last[2] then bad[#bad+1]=last[3]..'/'..r[3] end
                            last=r
                        end
                    end
                    if not L.above then bad[#bad+1]='not above' end
                end
            end
            return table.concat(bad,',')
        ''')
        self.assertEqual(result, '')

    def test_near_the_top_of_the_screen_it_goes_under_the_feet(self):
        result = self.run_lua('''
            local L=M.layout(90,41,true,8,6,9)
            return L.above, L.digitsTop>90, L.countsY>=L.digitsTop+12, L.iconY-12>=L.countsY+9,
                L.nameY>=L.iconY+12, L.noteY>=L.nameY+8, L.hintY>=L.noteY+6
        ''')
        self.assertEqual(result, (False, True, True, True, True, True, True))

    # -------------------------------------------------------------- uses
    def test_opening_and_closing_the_bowl_is_no_item_use(self):
        # User request 2026-11-24: a cancelled use must not count, so the
        # engine's use is cancelled before MC_USE_ITEM.
        result = self.run_lua('''
            local p=player(); M.addMilk(1)
            local cancelled=M.onPreUseItem(nil,CEREAL,nil,p,0,0)
            local open=M.picking(p)
            keys[ButtonAction.ACTION_DROP]=true; M.onUpdate(); M.onUpdate()
            return cancelled, open, M.picking(p), T.pendingCounts(), T.countedUses(), p.uses or 0
        ''')
        self.assertEqual(result, (True, True, False, 0, 0, 0))

    def test_making_an_item_counts_one_real_use_on_the_next_update(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1); M.addDigit(1,2); M.addDigit(8,1)
            M.onPreUseItem(nil,CEREAL,nil,p,0,0)
            T.type(p,{1,1,8}); T.confirm(p)
            local queued=T.pendingCounts()
            M.onUpdate()
            return queued, T.pendingCounts(), p.uses, T.countedUses(), M.picking(p), list(p.queued)
        ''')
        self.assertEqual(result, (1, 0, 1, 1, False, '118'))

    def test_breaking_an_item_counts_one_real_use(self):
        result = self.run_lua('''
            local p=player(); hold(p,118)
            local cancelled=M.onPreUseItem(nil,CEREAL,nil,p,0,0)
            M.onUpdate()
            return cancelled, subtypes(), p.uses, T.countedUses(), M.picking(p)
        ''')
        self.assertEqual(result, (True, '1,1,8', 1, 1, False))

    def test_a_car_battery_second_use_is_cancelled_quietly(self):
        result = self.run_lua('''
            local p=player(); M.addMilk(1)
            return M.onPreUseItem(nil,CEREAL,nil,p,UseFlag.USE_CARBATTERY,0), M.picking(p), T.pendingCounts()
        ''')
        self.assertEqual(result, (True, False, 0))

    # -------------------------------------------------------------- wiring
    def test_callbacks_carry_their_filters(self):
        result = self.run_lua('''
            local out={}
            for _,r in ipairs(regs) do out[#out+1]=r.cb..':'..tostring(r.filter)..':'..tostring(r.pri) end
            return table.concat(out,' ')
        ''')
        for wanted in ('23:780:-100', '34:7792:nil', '35:7792:nil', '38:7792:nil', '62:nil:-100', '1004:25:nil', '1080:780:nil'):
            self.assertIn(wanted, result)

    def test_registry_row_and_text(self):
        registry = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        row = registry[registry.index('    CEREAL = {'):registry.index('    -- The twelve zodiac items')]
        self.assertIn('origin = { id = CollectibleType.COLLECTIBLE_BREAKFAST, type = "collectible" }', row)
        self.assertIn('flag = "positive"', row)
        self.assertIn('type = "active"', row)
        self.assertIn('maxcharges = 0', row)
        for key in ('use', 'postUpdate', 'postRender', 'inputAction', 'postNewRoom'):
            self.assertIn(key + ' = "cereal.', row)
        for lang, line in (('en', 'Requires REPENTOGON!'), ('kr', 'REPENTOGON이 필요합니다!'),
                           ('urimal', '덧붙임 도우미(REPENTOGON)가 있어야 합니다!')):
            text = (ROOT / f'scripts/locale/{lang}.lua').read_text(encoding='utf-8')
            entry = text[text.index('        CEREAL = {'):]
            entry = entry[:entry.index('\n        },\n')]
            self.assertIn(line, entry, lang)
            self.assertIn('{c:BREAKFAST}', entry, lang)
            self.assertIn('cereal = {', text, lang)

    def test_every_digit_has_its_pickup_row_and_animation(self):
        defs = (ROOT / 'scripts/entities/definitions.lua').read_text(encoding='utf-8')
        for d in range(10):
            self.assertIn('subtype = %d, anm2path = "005.7792_conch_cereal_%d.anm2"' % (d, d), defs)
            anm2 = (ROOT / ('resources/gfx/005.7792_conch_cereal_%d.anm2' % d)).read_text(encoding='utf-8')
            for anim in ('Appear', 'Idle', 'Collect'):
                self.assertIn('Animation Name="%s"' % anim, anm2)


if __name__ == '__main__':
    unittest.main()
