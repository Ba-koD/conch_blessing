"""전우치 (Jeon Woo-chi) through its shipped Lua: which transformation he steals
for, which items, where, when the pedestal stands, and what survives leaving
the room. The user's design (2026-11-13): on pickup, among the unfinished
transformations collected the most toward, one at random, as many of its items
as it still needs; each copy on its own, even two in the same update. These are
Lua regressions with doubles, not proof of engine behaviour.
"""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / (name.replace('.', '/') + '.lua')).read_text(encoding='utf-8')


class JeonWoochiTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().loadsource = source
        self.lua.execute(r'''
            package=nil
            local cache={}
            function ConchBlessingRequire(name)
                if not cache[name] then cache[name]=load(loadsource(name),name)() end
                return cache[name]
            end
            local V={}; V.__index=V
            V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
            V.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
            V.__mul=function(a,k) return Vector(a.X*k,a.Y*k) end
            function V:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
            Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
            Vector.Zero=Vector(0,0)
            function Vector.FromAngle(a) local r=math.rad(a) return Vector(math.cos(r),math.sin(r)) end
            ModCallbacks={MC_POST_EFFECT_UPDATE=55}
            EntityType={ENTITY_PICKUP=5,ENTITY_EFFECT=1000}
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350,PICKUP_PILL=70}
            ItemPoolType={POOL_TREASURE=0}
            SoundEffect={SOUND_HELL_PORTAL1=6,SOUND_HELL_PORTAL2=7,SOUND_PAPER_OUT=2,SOUND_PAPER_IN=3,SOUND_FIRE_BURN=4,
                SOUND_SUMMON_POOF=5}
            -- twelve tagged transformations, as playerforms.xml has them
            PlayerForm={PLAYERFORM_GUPPY=0,PLAYERFORM_LORD_OF_THE_FLIES=1,PLAYERFORM_MUSHROOM=2,PLAYERFORM_ANGEL=3,
                PLAYERFORM_BOB=4,PLAYERFORM_DRUGS=5,PLAYERFORM_MOM=6,PLAYERFORM_BABY=7,PLAYERFORM_EVIL_ANGEL=8,
                PLAYERFORM_POOP=9,PLAYERFORM_BOOK_WORM=10,PLAYERFORM_SPIDERBABY=12}
            ItemConfig={TAG_GUPPY=1,TAG_FLY=2,TAG_MUSHROOM=4,TAG_ANGEL=8,TAG_BOB=16,TAG_SYRINGE=32,TAG_MOM=64,
                TAG_BABY=128,TAG_DEVIL=256,TAG_POOP=512,TAG_BOOK=1024,TAG_SPIDER=2048,TAG_QUEST=4096}
            JWC=900
            -- items 1-12 guppy (12 hidden, 11 a quest item), 20-23 bob, 30-32 fly, 40 untagged
            items={}
            for id=1,60 do items[id]={Hidden=false,tags=0,available=true} end
            for id=1,12 do items[id].tags=ItemConfig.TAG_GUPPY end
            items[12].Hidden=true; items[11].tags=ItemConfig.TAG_GUPPY|ItemConfig.TAG_QUEST; items[10].available=false
            for id=20,23 do items[id].tags=ItemConfig.TAG_BOB end
            for id=30,32 do items[id].tags=ItemConfig.TAG_FLY end
            items[50].tags=ItemConfig.TAG_GUPPY|ItemConfig.TAG_FLY   -- counts toward two sets
            for _,item in pairs(items) do
                function item:HasTags(t) return self.tags & t ~= 0 end
                function item:IsAvailable() return self.available end
            end
            config={GetCollectibles=function() return {Size=61} end,GetCollectible=function(_,id) return items[id] end}
            -- one pool listing items 1-9, 20-23, 30-32 and 40; removals tracked
            removed={}; weights={}
            for _,id in ipairs({1,2,3,4,5,6,7,8,9,20,21,22,23,30,31,32,40,50}) do weights[id]=1 end
            pool={}
            function pool:GetNumItemPools() return 1 end
            function pool:GetCollectiblesFromPool()
                local list={}
                for id,w in pairs(weights) do list[#list+1]={itemID=id,weight=w,isUnlocked=true} end
                table.sort(list,function(a,b) return a.itemID<b.itemID end)
                return list
            end
            function pool:GetRemovedCollectibles() local m={} for id in pairs(removed) do m[id]=true end return m end
            function pool:RemoveCollectible(id) removed[id]=true end
            function pool:GetPoolForRoom() return 0 end
            function pool:GetCollectible(kind,decrease)
                for _,id in ipairs({40,1,2}) do
                    if not removed[id] then if decrease then removed[id]=true end return id end
                end
                return 25
            end
            room={}
            function room:FindFreePickupSpawnPosition(p) return p end
            function room:IsPositionInRoom(p) return p.X>=60 and p.X<=580 and p.Y>=140 and p.Y<=420 end
            function room:GetType() return 1 end
            pedestals={}
            gameFrame=0
            game={GetItemPool=function() return pool end,GetRoom=function() return room end,
                GetFrameCount=function() return gameFrame end}
            function game:Spawn(t,v,pos,vel,spawner,sub,seed)
                pedestals[#pedestals+1]={type=t,variant=v,x=pos.X,y=pos.Y,id=sub,seed=seed}
                return pedestals[#pedestals]
            end
            function Game() return game end
            effects={}; sounds={}
            function makeEffect(pos)
                local e={Position=pos,data={},removed=false,DepthOffset=0}
                local s={anim=nil,events={},finished=false,frame=0}
                function s:Play(name) self.anim=name; self.frame=0 end
                function s:GetFrame() return self.frame end
                function s:SetFrame(name,f) self.anim=name; self.frame=f; self.stopped=true end
                function s:IsEventTriggered(n) return self.events[n]==true end
                function s:IsFinished(n) return self.finished and self.anim==n end
                function e:GetSprite() return s end
                function e:GetData() return self.data end
                function e:ToEffect() return self end
                function e:Remove() self.removed=true end
                e.sprite=s
                return e
            end
            Isaac={GetItemIdByName=function() return JWC end,GetItemConfig=function() return config end,
                GetEntityTypeByName=function() return 1000 end,GetEntityVariantByName=function() return 7789 end}
            function Isaac.Spawn(t,v,sub,pos) local e=makeEffect(pos); effects[#effects+1]=e; return e end
            function Isaac.FindByType(t,v)
                local list={} for _,e in ipairs(effects) do if not e.removed then list[#list+1]=e end end
                return list
            end
            function SFXManager() return {Play=function(_,id) sounds[#sounds+1]=id end} end
            function RNG(seed)
                local r={state=seed or 7}
                function r:Next() self.state=(self.state*1103515245+12345)%2147483648; return self.state end
                function r:RandomInt(n) return self:Next()%n end
                return r
            end
            counters={}; done={}; heldItems={}
            player={Position=Vector(320,280),ControllerIndex=0,rng=RNG(11)}
            function player:GetPlayerFormCounter(f) return counters[f] or 0 end
            function player:HasPlayerForm(f) return done[f]==true end
            function player:HasCollectible(id) return heldItems[id]==true end
            function player:GetCollectibleRNG() return self.rng end
            roomSaves={}; roomIndex=1; saves=0; errors={}; callbacks={}
            ConchBlessing={ItemData={JEON_WOOCHI={id=JWC}},printError=function(s) errors[#errors+1]=s end,
                printDebug=function() end,Config={},
                SaveManager={SaveCallbacks={POST_DATA_LOAD=901},IsLoaded=function() return true end,
                    GetRoomSave=function() roomSaves[roomIndex]=roomSaves[roomIndex] or {} return roomSaves[roomIndex] end,
                    TryGetRoomSave=function() return roomSaves[roomIndex] end,
                    Save=function() saves=saves+1 end}}
            ConchBlessing.originalMod={AddCallback=function(_,id,fn) callbacks[id]=fn end}
            function ConchBlessing:AddCallback(id,fn,param) callbacks[id]=fn end
        ''')
        self.lua.execute(source('scripts.items.collectibles.jeon_woochi'))
        self.lua.execute(r'''
            M=ConchBlessing.jeonwoochi
            function pickup(first) M.onAddCollectible(nil,JWC,0,first~=false,0,0,player) end
            function pending() local n=0 for _ in pairs(M.pending()) do n=n+1 end return n end
            function live() local list={} for _,e in ipairs(effects) do if not e.removed then list[#list+1]=e end end return list end
            -- n game updates: every live effect's update callback, in order
            function run(n)
                for _=1,n do
                    gameFrame=gameFrame+1
                    for _,e in ipairs(effects) do if not e.removed then M.onEffectUpdate(nil,e) end end
                end
            end
            function state(e) return e.data[M._test.data] end
            function guppy(id) return items[id] and items[id].tags & ItemConfig.TAG_GUPPY ~= 0 end
        ''')
        M = self.lua.globals().M
        M.onGameStarted(None)

    def run_lua(self, code):
        self.lua.execute(code)

    def test_rule_one_keeps_the_sets_with_the_least_left(self):
        self.run_lua(r'''
            local a,b,c={left=1},{left=1},{left=2}
            local list,least=M.closest({c,a,b})
            assert(least==1 and #list==2 and list[1]==a and list[2]==b, 'kept '..#list..' at '..least)
        ''')

    def test_rule_one_picks_among_the_closest_entirely_at_random(self):
        self.run_lua(r'''
            -- Guppy 2 and Bob 2 (one left each), Beelzebub 1: every pick is Guppy
            -- or Bob, and over many seeds both come up
            counters[PlayerForm.PLAYERFORM_GUPPY]=2
            counters[PlayerForm.PLAYERFORM_BOB]=2
            counters[PlayerForm.PLAYERFORM_LORD_OF_THE_FLIES]=1
            local seen={}
            for seed=1,60 do
                local plan=M.plan(player,RNG(seed))
                assert(plan.form=="GUPPY" or plan.form=="BOB", 'picked '..tostring(plan.form))
                seen[plan.form]=(seen[plan.form] or 0)+1
            end
            assert((seen.GUPPY or 0)>5 and (seen.BOB or 0)>5, 'guppy '..tostring(seen.GUPPY)..' bob '..tostring(seen.BOB))
        ''')

    def test_left_is_each_sets_threshold_minus_its_counter(self):
        self.run_lua(r'''
            -- Guppy 1 (two left) against Bob 2 (one left): Bob is closer
            counters[PlayerForm.PLAYERFORM_GUPPY]=1
            counters[PlayerForm.PLAYERFORM_BOB]=2
            local plan=M.plan(player,RNG(3))
            assert(plan.form=="BOB" and plan.left==1 and #plan.items==1, tostring(plan.form)..' '..tostring(plan.left))
            -- a threshold other than three is followed, not a fixed three
            local forms=ConchBlessingRequire("scripts.lib.player_forms").list()
            for _,f in ipairs(forms) do if f.key=="GUPPY" then f.threshold=5 end end
            counters[PlayerForm.PLAYERFORM_GUPPY]=4
            plan=M.plan(player,RNG(3))
            assert(plan.form=="GUPPY" and plan.left==1, tostring(plan.form)..' '..tostring(plan.left))
        ''')

    def test_rule_two_draws_the_items_entirely_at_random_from_the_set(self):
        self.run_lua(r'''
            local set={1,2,3,4}
            local p=M.chooseItems(set,3,function(n) return n end)
            assert(#p==3 and p[1]==4 and p[2]==3 and p[3]==2, table.concat(p,','))
            p=M.chooseItems({7},3,function() return 1 end)
            assert(#p==3 and p[1]==7 and p[3]==7, 'a one-item set repeats to finish')
            -- every member comes up over many seeds, held or in a pool or not
            heldItems[1]=true; removed[2]=true
            counters[PlayerForm.PLAYERFORM_GUPPY]=2
            local seen={}
            for seed=1,200 do
                local plan=M.plan(player,RNG(seed))
                for _,item in ipairs(plan.items) do seen[item.id]=true end
            end
            for _,id in ipairs({1,2,3,4,5,6,7,8,9,50}) do assert(seen[id],'never drew '..id) end
        ''')

    def test_he_steals_what_the_closest_set_still_needs(self):
        self.run_lua(r'''
            counters[PlayerForm.PLAYERFORM_GUPPY]=2
            counters[PlayerForm.PLAYERFORM_BOB]=1
            pickup()
            assert(#effects==1, 'one arrival for one missing item, got '..#effects)
            local rec=effects[1].data[M._test.data].rec
            assert(guppy(rec.id), 'stole '..rec.id..', not a guppy item')
            assert(next(removed)==nil, 'the item pools were touched')
            assert(pending()==1, 'no record kept while he comes')
            assert(#pedestals==0, 'the pedestal stood before the smoke')
        ''')

    def test_hidden_quest_and_locked_items_are_never_stolen(self):
        self.run_lua(r'''
            local idx=M.index()
            local guppyAt
            for i,f in ipairs(idx.forms) do if f.key=="GUPPY" then guppyAt=i end end
            for _,id in ipairs(idx.members[guppyAt]) do assert(id~=11 and id~=12,'indexed '..id) end
            counters[PlayerForm.PLAYERFORM_GUPPY]=0
            for seed=1,100 do
                local plan=M.plan(player,RNG(seed))
                for _,item in ipairs(plan.items) do assert(item.id~=10 and item.id~=11 and item.id~=12,'stole '..item.id) end
            end
        ''')

    def test_transformations_are_read_from_the_games_playerform_data(self):
        self.run_lua(r'''
            local Forms=ConchBlessingRequire("scripts.lib.player_forms")
            Forms.reset()
            XMLNode={PLAYERFORM=29}
            local entries={{id="0",name="#TRANSFORMATION_GUPPY",tags="guppy"},{id="11",name="#TRANSFORMATION_ADULT"},
                {id="40",name="Modded",tags="book spider"},{id="13",name="#TRANSFORMATION_STOMPY"}}
            XMLData={GetNumEntries=function(node) assert(node==29) return #entries end,
                GetEntryByOrder=function(node,i) return entries[i] end}
            local list=Forms.list()
            assert(#list==2 and list[1].form==0 and list[1].key=="GUPPY" and list[2].form==40
                and list[2].tag==(ItemConfig.TAG_BOOK|ItemConfig.TAG_SPIDER), 'read '..#list)
            assert(Forms.threshold(list[1])==Forms.THRESHOLD, 'threshold')
            XMLData=nil; XMLNode=nil; Forms.reset()
            assert(#Forms.list()==12, 'the vanilla table without XMLData')
        ''')

    def test_two_copies_in_one_update_each_steal_on_their_own(self):
        self.run_lua(r'''
            counters[PlayerForm.PLAYERFORM_GUPPY]=1
            pickup(); pickup()
            assert(#effects==4, 'two copies, two missing each: '..#effects)
            for _,e in ipairs(effects) do
                local id=e.data[M._test.data].rec.id
                assert(guppy(id), 'not a guppy item: '..id)
            end
        ''')

    # The sets no tag describes (user decision 2026-11-13: include them).
    def special(self):
        self.run_lua(r"""
            PlayerForm.PLAYERFORM_ADULTHOOD=11; PlayerForm.PLAYERFORM_STOMPY=13
            PillEffect={PILLEFFECT_PUBERTY=9,PILLEFFECT_LARGER=32}
            TrinketType={TRINKET_MISSING_PAGE=5}
            CollectibleType={COLLECTIBLE_BUM_FRIEND=41,COLLECTIBLE_DARK_BUM=42,COLLECTIBLE_KEY_BUM=43,
                COLLECTIBLE_LEO=44,COLLECTIBLE_MAGIC_MUSHROOM=45,COLLECTIBLE_NECRONOMICON=46,COLLECTIBLE_MISSING_PAGE_2=47}
            -- Necromancer has no PlayerForm name here: found by its playerforms.xml name
            XMLNode={PLAYERFORM=29}
            XMLData={GetNumEntries=function() return 1 end,GetEntryByOrder=function() return {id="15",name="Necromancer!"} end,
                GetEntryById=function(_,id) if id==15 then return {id="15",name="Necromancer!"} end end}
            trinkets={[5]={available=true}}
            for _,t in pairs(trinkets) do function t:IsAvailable() return self.available end end
            function config:GetTrinket(id) return trinkets[id] end
            heldTrinkets={}
            function player:HasTrinket(id) return heldTrinkets[id]==true end
            pillEffects={[7]=9,[3]=32}
            function pool:GetPillEffect(color) return pillEffects[color] or 0 end
            ConchBlessingRequire("scripts.lib.player_forms").reset()
            function only(plan) return plan.items[1] end
        """)

    def test_special_sets_are_read_with_their_pieces(self):
        self.special()
        self.run_lua(r"""
            local list=ConchBlessingRequire("scripts.lib.player_forms").special()
            local by={}
            for _,set in ipairs(list) do by[set.key]=set end
            assert(by.ADULTHOOD.form==11 and by.ADULTHOOD.supplies[1].kind=="pill", 'adult')
            assert(by.STOMPY.form==13 and #by.STOMPY.supplies==3, 'stompy')
            assert(by.NECROMANCER.form==15 and by.NECROMANCER.unique and by.NECROMANCER.supplies[3].kind=="trinket", 'necro')
            assert(by.SUPER_BUM.held and by.SUPER_BUM.form==nil and by.SUPER_BUM.threshold==3, 'super bum')
        """)

    def test_necromancer_is_left_out_where_the_game_has_no_such_form(self):
        self.special()
        self.run_lua(r"""
            XMLData.GetEntryById=function() return nil end
            XMLData.GetEntryByOrder=function() return {id="13",name="Stompy!"} end
            local Forms=ConchBlessingRequire("scripts.lib.player_forms")
            Forms.reset()
            for _,set in ipairs(Forms.special()) do assert(set.key~="NECROMANCER", 'Necromancer kept') end
        """)

    def test_super_bum_steals_the_bum_still_missing(self):
        self.special()
        self.run_lua(r"""
            heldItems[41]=true; heldItems[42]=true
            local plan=M.plan(player,RNG(5))
            assert(plan.form=="SUPER_BUM" and plan.left==1 and only(plan).kind=="collectible" and only(plan).id==43,
                tostring(plan.form)..' '..tostring(plan.left))
        """)

    def test_necromancer_steals_the_piece_still_missing(self):
        self.special()
        self.run_lua(r"""
            counters[15]=2; heldItems[46]=true; heldItems[47]=true
            local plan=M.plan(player,RNG(5))
            assert(plan.form=="NECROMANCER" and plan.left==1 and only(plan).kind=="trinket" and only(plan).id==5,
                tostring(plan.form))
        """)

    def test_adult_steals_this_runs_puberty_pill_or_is_left_out(self):
        self.special()
        self.run_lua(r"""
            counters[11]=2
            local plan=M.plan(player,RNG(5))
            assert(plan.form=="ADULTHOOD" and only(plan).kind=="pill" and only(plan).id==7, tostring(plan.form))
            pillEffects[7]=nil   -- no pill of this run has Puberty
            plan=M.plan(player,RNG(5))
            assert(plan.form~="ADULTHOOD", 'Adult chosen with no Puberty pill in the run')
        """)

    def test_stompy_draws_from_its_items_and_its_pill(self):
        self.special()
        self.run_lua(r"""
            counters[13]=2
            local seen={}
            for seed=1,80 do
                local plan=M.plan(player,RNG(seed))
                assert(plan.form=="STOMPY", tostring(plan.form))
                local item=only(plan)
                seen[item.kind..item.id]=true
            end
            assert(seen.collectible44 and seen.collectible45 and seen.pill3, 'not every piece came up')
        """)

    def test_a_pill_and_a_trinket_are_placed_as_such(self):
        self.special()
        self.run_lua(r"""
            counters[11]=2
            pickup(); run(120)
            assert(pedestals[1].variant==PickupVariant.PICKUP_PILL and pedestals[1].id==7, 'pill variant '..pedestals[1].variant)
            counters[11]=3; done[11]=true
            counters[15]=2; heldItems[46]=true; heldItems[47]=true
            pickup(); run(120)
            assert(pedestals[2].variant==PickupVariant.PICKUP_TRINKET and pedestals[2].id==5, 'trinket')
        """)

    def test_he_comes_with_isaacs_own_teleport_sounds(self):
        self.run_lua(r"""
            counters[PlayerForm.PLAYERFORM_GUPPY]=1
            pickup()
            assert(sounds[1]==SoundEffect.SOUND_HELL_PORTAL2, 'the first arrival did not start with the leaving sound')
            run(12)
            local landed=false
            for _,id in ipairs(sounds) do if id==SoundEffect.SOUND_HELL_PORTAL1 then landed=true end end
            assert(landed, 'no arriving sound at the landing')
            local starts=0
            for _,id in ipairs(sounds) do if id==SoundEffect.SOUND_HELL_PORTAL2 then starts=starts+1 end end
            assert(starts==2, 'the staggered second arrival did not start with its own sound: '..starts)
        """)

    def test_they_arrive_in_turn_and_vanish_together(self):
        self.run_lua(r"""
            pickup()
            assert(#effects==3, 'a fresh player needs three')
            local started, items, frames, pops = {}, {}, {}, 0
            for tick=1,220 do
                gameFrame=gameFrame+1
                for i,e in ipairs(effects) do
                    if not e.removed then
                        local before=#sounds
                        M.onEffectUpdate(nil,e)
                        for k=before+1,#sounds do if sounds[k]==SoundEffect.SOUND_SUMMON_POOF then pops=pops+1 end end
                        local st=state(e)
                        if st.frame and not started[i] then started[i]=tick end
                        frames[i]=frames[i] or {}
                        if st.frame then frames[i][#frames[i]+1]=st.frame end
                        if st.placed and not items[i] then items[i]=tick end
                    end
                end
            end
            assert(started[1]<started[2] and started[2]<started[3], 'they did not arrive in turn')
            assert(items[1] and items[1]==items[2] and items[2]==items[3],
                'pedestals at '..tostring(items[1])..','..tostring(items[2])..','..tostring(items[3]))
            -- every one fans until the last is down (its frame 9), then after
            -- the pause they all snap the fan shut and go on (frame 17 to the
            -- Item frame 38)
            local lastDown = started[3] + M.data.hold.from
            assert(items[1] >= lastDown + M.data.hold.pause + (38 - M.data.hold.to - 1),
                'no wait for the last one: items at '..items[1]..', last down at '..lastDown)
            -- after the release each one plays every frame of the cast in order
            for i=1,3 do
                local seq, from = frames[i], nil
                for k=1,#seq do if seq[k]==M.data.hold.to+1 then from=k break end end
                assert(from, 'effect '..i..' never went on')
                for f=M.data.hold.to+1,63 do
                    assert(seq[from+(f-M.data.hold.to-1)]==f, 'effect '..i..' skipped frame '..f)
                end
            end
            assert(#pedestals==3 and pending()==0, 'pedestals '..#pedestals)
            assert(pops==1, 'the group popped '..pops..' times')
            for _,e in ipairs(effects) do assert(e.removed, 'one stayed') end
        """)

    def test_spots_are_apart_and_off_the_player(self):
        self.run_lua(r'''
            pickup()
            assert(#effects==3, 'a fresh player needs three items of a set: '..#effects)
            for i,a in ipairs(effects) do
                assert(a.Position:Distance(player.Position)>=M.data.nearest, 'spot on the player')
                for j,b in ipairs(effects) do
                    if i~=j then assert(a.Position:Distance(b.Position)>=M.data.gap, 'spots overlap') end
                end
            end
            assert(effects[1].sprite.anim=="Steal" and effects[2].sprite.anim=="Wait", 'arrivals are not staggered')
        ''')

    def test_the_pedestal_stands_at_the_item_frame_and_its_record_goes(self):
        self.run_lua(r"""
            counters[PlayerForm.PLAYERFORM_GUPPY]=2
            pickup()
            local e=effects[1]
            local placedAt
            for _=1,200 do
                run(1)
                if #pedestals>0 and not placedAt then placedAt=state(e).frame end
                if e.removed then break end
            end
            assert(placedAt==38, 'placed at frame '..tostring(placedAt))
            assert(#pedestals==1 and pending()==0, 'pedestals '..#pedestals..' pending '..pending())
            local rec=state(e).rec
            assert(pedestals[1].id==rec.id and pedestals[1].x==rec.x and pedestals[1].seed==rec.seed, 'wrong pedestal')
            assert(e.removed and state(e).frame==63, 'the effect stopped at '..tostring(state(e).frame))
        """)

    def test_leaving_during_the_show_places_the_item_on_the_next_entry(self):
        self.run_lua(r'''
            counters[PlayerForm.PLAYERFORM_GUPPY]=1
            pickup()
            assert(pending()==2, 'records '..pending())
            for _,e in ipairs(effects) do e.removed=true end   -- the room is left
            roomIndex=2; M.onNewRoom()
            assert(#pedestals==0, 'placed in another room')
            roomIndex=1; M.onNewRoom()
            assert(#pedestals==2 and pending()==0, 'pedestals '..#pedestals..' pending '..pending())
        ''')

    def test_only_a_first_pickup_steals(self):
        self.run_lua(r'''
            pickup(false)
            assert(#effects==0, 'a returned copy stole')
        ''')

    def test_with_every_set_complete_nothing_is_stolen(self):
        self.run_lua(r'''
            for _,f in pairs(PlayerForm) do done[f]=true end
            pickup()
            assert(#effects==0 and next(removed)==nil and #errors==0, 'effects '..#effects)
        ''')

    def test_eid_shows_how_many_items_he_would_summon(self):
        # user request 2026-11-13: the set is random, the count is not
        self.run_lua(r'''
            ConchBlessing.Locale={text=function(path,n)
                assert(path=='ui.jeon_woochi.summon_count', path); return '#COUNT '..n end}
            EID={ClosestPlayerTo=function() return player end}
            local function shown(text)
                return M.describe({Description=text}).Description
            end
            local base='Picks a set#Summons items#{{Warning}} Requires REPENTOGON!'
            -- Guppy 1 (two left) and Bob 2 (one left): he would summon one
            counters[PlayerForm.PLAYERFORM_GUPPY]=1
            counters[PlayerForm.PLAYERFORM_BOB]=2
            assert(M.summonCount(player)==1, 'count '..tostring(M.summonCount(player)))
            assert(shown(base)=='Picks a set#Summons items#COUNT 1#{{Warning}} Requires REPENTOGON!', shown(base))
            -- the same count whichever of the closest sets he would pick
            counters[PlayerForm.PLAYERFORM_BOB]=1
            gameFrame=gameFrame+1
            assert(M.summonCount(player)==2, 'two left in both closest sets')
            -- the count is what a pickup really summons
            for seed=1,20 do assert(#M.plan(player,RNG(seed)).items==M.summonCount(player)) end
            -- every set complete: zero, and no line without REPENTOGON
            for _,f in pairs(PlayerForm) do done[f]=true end
            gameFrame=gameFrame+1
            assert(M.summonCount(player)==0, 'complete sets still count')
            assert(shown('x')=='x#COUNT 0', shown('x'))
            player.GetPlayerFormCounter=nil
            assert(shown('x')=='x', 'a line without REPENTOGON')
        ''')

    def test_without_repentogon_nothing_is_stolen_and_one_error_is_reported(self):
        self.run_lua(r'''
            player.GetPlayerFormCounter=nil
            pickup(); pickup()
            assert(#effects==0 and #errors==1, 'effects '..#effects..' errors '..#errors)
        ''')

    def test_a_reload_places_what_is_on_its_way(self):
        self.run_lua(r'''
            counters[PlayerForm.PLAYERFORM_GUPPY]=1
            pickup()
            M.onModUnload(nil, ConchBlessing)
            assert(#pedestals==2 and pending()==0, 'pedestals '..#pedestals..' pending '..pending())
            for _,e in ipairs(effects) do assert(e.removed,'an effect stayed') end
        ''')

    def test_the_animation_carries_the_events_the_runtime_listens_for(self):
        tree = ET.parse(ROOT / 'resources/gfx/effects/conch_jeonwoochi.anm2')
        events = {e.get('Id'): e.get('Name') for e in tree.iter('Event')}
        steal = tree.find('./Animations/Animation[@Name="Steal"]')
        self.assertEqual(tree.find('./Animations').get('DefaultAnimation'), 'Wait')
        self.assertEqual(int(steal.get('FrameNum')), len(steal.findall('./LayerAnimations/LayerAnimation/Frame')))
        at = {events[t.get('EventId')]: int(t.get('AtFrame')) for t in steal.iter('Trigger')}
        self.assertEqual(set(at), {'Land', 'Snap', 'Charm', 'Flash', 'Throw', 'Pop', 'Item'})
        self.assertLess(at['Pop'], at['Item'])
        self.assertLess(at['Item'], int(steal.get('FrameNum')))
        module = source('scripts.items.collectibles.jeon_woochi')
        # the module draws the frames itself, so its event table must be the anm2's
        table = re.search(r'local EVENTS = \{([^}]*)\}', module)[1]
        self.assertEqual({k: int(v) for k, v in re.findall(r'(\w+) = (\d+)', table)}, at)
        last = re.search(r'local LAST = (\d+)', module)[1]
        self.assertEqual(int(last), int(steal.get('FrameNum')) - 1)
        for name in ('Land', 'Snap', 'Charm', 'Throw', 'Pop'):
            self.assertIn(name + ' = {', module)

    def test_kronos_and_jeon_woochi_share_one_form_table(self):
        self.assertIn('Rune.FORM_TAGS = require("scripts.lib.player_forms").TAGS',
                      source('scripts.items.collectibles.kronos'))


if __name__ == '__main__':
    unittest.main()
