"""묘 (Rabbit): production Lua with engine doubles.

The pure rules run here: which room the hidden rock goes to (four doors from
the start room, else the farthest nearer, else the nearest farther, rooms
whose layout has rocks first), which of a room's own rocks can carry the
tracks (rocks of every look a player can walk up to; never tinted rocks, metal
blocks or poop), how the revived holder's half heart is
made up, how Raw Livers become livers (only while holding Rabbit, at most
four), what the ladder does with the floor's crawlspace, which cell takes the
rock, an older save's livers, and the floor
graph's door distances. The revive itself, the rock, the ladder, the crawlspace
passage and the black market's Raw Liver need the engine: `cb test rabbit`
covers those in game.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
RoomShape={ROOMSHAPE_1x1=1,ROOMSHAPE_IH=2,ROOMSHAPE_IV=3,ROOMSHAPE_1x2=4,ROOMSHAPE_IIV=5,ROOMSHAPE_2x1=6,
    ROOMSHAPE_IIH=7,ROOMSHAPE_2x2=8,ROOMSHAPE_LTL=9,ROOMSHAPE_LTR=10,ROOMSHAPE_LBL=11,ROOMSHAPE_LBR=12}
RoomType={ROOM_DEFAULT=1,ROOM_SHOP=2,ROOM_TREASURE=4,ROOM_BOSS=5,ROOM_SECRET=7,ROOM_SUPERSECRET=8,ROOM_DUNGEON=16,
    ROOM_BLACK_MARKET=22,ROOM_ULTRASECRET=29}
GridRooms={ROOM_DUNGEON_IDX=-4,ROOM_BLACK_MARKET_IDX=-6}
GridEntityType={GRID_ROCK=2,GRID_ROCKB=3,GRID_ROCKT=4,GRID_ROCK_BOMB=5,GRID_ROCK_ALT=6,GRID_POOP=14,GRID_STAIRS=18,
    GRID_ROCK_SS=22,GRID_PILLAR=24,GRID_ROCK_SPIKED=25,GRID_ROCK_ALT2=26,GRID_ROCK_GOLD=27}
CollectibleType={COLLECTIBLE_RAW_LIVER=16}
ModCallbacks={MC_PRE_TRIGGER_PLAYER_DEATH=1050,MC_POST_PLAYER_REVIVE=1482}
errors={}
Isaac={GetItemIdByName=function(name) return ({Rabbit=960,Dragon=951})[name] or -1 end,
    GetEntityTypeByName=function() return 1000 end,
    GetEntityVariantByName=function(name) return name=='Conch Blessing Rabbit Tracks' and 7788 or -1 end}
callbacks={}
SM={IsLoaded=function() return true end,GetRunSave=function(player) return player.save end,
    GetFloorSave=function(player) return player and player.floor end}
SoundEffect={SOUND_THUNDER=1}
played={}
function SFXManager() return {Play=function(_,id) played[#played+1]=id end} end
function Game() return {GetHUD=function() return nil end} end
um={set={},removed={}}
function um:SetItemMultiplier(player,id,stat,value) self.set[#self.set+1]={player=player,id=id,stat=stat,value=value} end
function um:RemoveItemMultiplier(player,id,stat) self.removed[#self.removed+1]={player=player,id=id,stat=stat} end
ConchBlessing={printError=function(e) errors[#errors+1]=e end,printDebug=function() end,SaveManager=SM,
    stats={unifiedMultipliers=um},Locale={text=function(path) return path end},
    getUnifiedMultiplierState=function(player) return {itemMultipliers=player.multipliers} end,
    AddCallback=function(_,id,fn) callbacks[#callbacks+1]={id=id,fn=fn} end}
function GetPtrHash(entity) return entity.hash end

-- A player with `copies` Rabbits, `raw` Raw Livers and the run save `save`;
-- its effects count livers at hand.
local serial=0
function holder(copies, raw, save)
    local effects={n=0}
    function effects:GetCollectibleEffectNum() return self.n end
    function effects:AddCollectibleEffect(_,_,count) self.n=self.n+(count or 1) end
    function effects:RemoveCollectibleEffect(_,count) self.n=self.n-(count or 1) end
    serial=serial+1
    return {hash=serial,save=save,floor={},copies=copies,raw=raw,effects=effects,dragon=false,
        GetCollectibleNum=function(self,id) if id==16 then return self.raw end return self.copies end,
        HasCollectible=function(self,id) return id==951 and self.dragon end,
        GetEffects=function(self) return self.effects end}
end
local loaded={}
require=function(name)
    if name=='scripts.lib.save_manager' then return {} end
    if name=='scripts.lib.sound_volume' then return {volume=function(v) return v end} end
    if loaded[name]==nil then loaded[name]=dofile(root..'/'..name:gsub('%.','/')..'.lua') end
    return loaded[name]
end
M=dofile(root..'/scripts/items/collectibles/rabbit.lua')
T=M._test
LR=require('scripts.lib.level_rooms')

-- A fake level: rooms by safe grid index, 1x1, connected by their door cells.
function level(rooms)
    for idx,r in pairs(rooms) do
        r.SafeGridIndex=idx; r.GridIndex=idx; r.ListIndex=idx
        r.Data={Shape=RoomShape.ROOMSHAPE_1x1,Doors=255,Type=r.type or RoomType.ROOM_DEFAULT}
    end
    return {GetRoomByIdx=function(_,i) return rooms[i] end}
end
"""


class RabbitTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = str(ROOT).replace('\\', '/')
        self.lua.execute(HARNESS)

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_the_tracks_effect_resolves(self):
        self.run_lua("""
            assert(T.tracksVariant()==7788)
            assert(#errors==0, errors[1])
        """)

    def test_the_rock_goes_four_rooms_away_else_to_the_farthest(self):
        self.run_lua("""
            local first=function() return 0 end
            local c={{index=10,distance=1},{index=20,distance=4},{index=30,distance=4},{index=40,distance=6}}
            assert(T.chooseTarget(c,4,first).index==20,'exactly four doors, lowest index on pick 0')
            assert(T.chooseTarget(c,4,function(n) assert(n==2) return 1 end).index==30,'pick among the exact ones')
            c={{index=10,distance=1},{index=11,distance=3},{index=12,distance=3},{index=13,distance=2}}
            assert(T.chooseTarget(c,4,first).index==11,'none four away: the farthest nearer')
            assert(T.chooseTarget({{index=5,distance=7}},4,first)==nil,'only farther rooms: none')
            assert(T.chooseTarget({},4,first)==nil)
            local far={{index=5,distance=7},{index=6,distance=5},{index=7,distance=5}}
            assert(T.chooseTarget(far,4,first,true).index==6,'allowed farther: the nearest farther')
            assert(T.chooseTarget(far,4,function(n) assert(n==2) return 1 end,true).index==7)
            assert(T.chooseTarget({{index=1,distance=2},{index=2,distance=6}},4,first,true).index==1,
                'a nearer room before a farther one')
        """)

    def test_the_tracks_go_on_a_rock_of_the_room_a_player_can_walk_up_to(self):
        self.run_lua("""
            local k=T.kinds()
            for _,name in ipairs({'GRID_ROCK','GRID_ROCK_ALT','GRID_ROCK_ALT2','GRID_ROCK_BOMB','GRID_ROCK_SPIKED',
                'GRID_ROCK_GOLD'}) do assert(k[GridEntityType[name]],name..' can be the hidden rock') end
            for _,name in ipairs({'GRID_ROCKT','GRID_ROCK_SS','GRID_ROCKB','GRID_PILLAR','GRID_POOP','GRID_STAIRS'}) do
                assert(not k[GridEntityType[name]],name..' never is') end
            -- a 7x5 room: the door's inner cell at the left middle (2*7+1)
            local W=7
            local walk={}
            for y=1,3 do for x=1,5 do walk[y*W+x]=true end end
            -- a wall of rocks down column 3 cuts off the right side
            local rocks={1*W+3,2*W+3,3*W+3, 1*W+5}
            for _,c in ipairs(rocks) do walk[c]=nil end
            local reached=T.reachable(W,walk,{2*W+1})
            assert(reached[2*W+1] and reached[1*W+2] and not reached[2*W+4],'the wall stops the walk')
            local list=T.eligibleRocks(W,rocks,reached)
            assert(#list==3 and list[1]==1*W+3 and list[3]==3*W+3,'the wall rocks face the reachable side')
            -- the rock in the cut-off corner is never chosen: its ladder could not be walked onto
            for _,c in ipairs(list) do assert(c~=1*W+5) end
            -- rows do not wrap: a rock at a row's end is not beside the next row's start
            assert(#T.eligibleRocks(W,{1*W+6},{[2*W+0]=true})==0,'no wrap from one row into the next')
        """)

    def test_a_room_layout_counts_the_spots_that_can_be_a_rock(self):
        self.run_lua("""
            assert(T.countLayoutRocks({{1000},{1002},{20},{1300},{1500,1000},{1900},{1010}})==4,
                'rock, alt rock, a spot that may be a rock and a spiked rock; not TNT, poop or metal')
            assert(T.countLayoutRocks({})==0)
            -- the engine's layout list read through RoomConfig: entries picked across each spot's weights
            local spots={{1000},{20,1002},{1500}}
            local data={Spawns={Size=#spots,Get=function(_,i)
                local types=spots[i+1]
                return {EntryCount=#types,PickEntry=function(_,r) return {Type=types[math.floor(r*#types)+1]} end}
            end}}
            local types=T.layoutTypes(data)
            assert(#types==3 and types[2][2]==1002 and T.countLayoutRocks(types)==2)
            assert(T.layoutTypes({})==nil,'no layout: unknown')
        """)

    def test_half_a_heart_red_when_a_container_is_free_else_soul(self):
        self.run_lua("""
            assert(M.data.halves==1,'half a heart')
            local r,s=T.topUp(0,0,6,1); assert(r==1 and s==0,'a free container: red')
            r,s=T.topUp(0,0,0,1); assert(r==0 and s==1,'no free container: soul')
            r,s=T.topUp(1,0,5,1); assert(r==0 and s==0,'already half a heart: nothing added')
        """)

    def test_raw_livers_are_livers_only_with_rabbit_and_at_most_four(self):
        self.run_lua("""
            local l,c=T.credit(0,0,1,true,4); assert(l==1 and c==1,'one Raw Liver with Rabbit')
            l,c=T.credit(0,1,1,true,4); assert(l==0 and c==1,'nothing new: nothing')
            l,c=T.credit(3,0,5,true,4); assert(l==4 and c==5,'at most four')
            l,c=T.credit(2,1,2,false,4); assert(l==2 and c==2,'taken without Rabbit: counted, no liver')
            l,c=T.credit(2,3,1,true,4); assert(l==2 and c==1,'a lost copy only moves the count')
            l,c=T.credit(2,1,2,true,4); assert(l==3 and c==2,'taken again: a liver again')
            local o
            l,c,o=T.credit(4,1,2,true,4); assert(l==4 and o==1,'past four: one overflows')
            l,c,o=T.credit(3,0,3,true,4); assert(l==4 and o==2,'three at once onto three: two overflow')
            l,c,o=T.credit(4,1,2,false,4); assert(o==0,'without Rabbit nothing overflows')
        """)

    def test_the_ladder_makes_an_unvisited_crawlspace_the_passage_else_leads_on(self):
        self.run_lua("""
            assert(T.crawlspacePlan(0,RoomType.ROOM_DUNGEON,7)=='write','never visited: write the passage')
            assert(T.crawlspacePlan(nil,RoomType.ROOM_DUNGEON,7)=='write')
            assert(T.crawlspacePlan(0,RoomType.ROOM_DUNGEON,1)=='ready','already the passage')
            assert(T.crawlspacePlan(2,RoomType.ROOM_DUNGEON,1)=='ready','visited passage stays usable')
            assert(T.crawlspacePlan(1,RoomType.ROOM_DUNGEON,7)=='direct','visited with its own layout: lead on')
        """)

    def test_the_rock_keeps_clear_of_doors_and_players_and_never_cuts_a_door_off(self):
        self.run_lua("""
            local W=7
            local free={}
            for y=1,3 do for x=1,5 do free[y*W+x]=true end end
            local doors={2*W+1, 1*W+3, 2*W+5, 3*W+3}
            local order={}
            for c in pairs(free) do order[#order+1]=c end
            table.sort(order)
            local cell=T.chooseCell(W,free,doors,{},1,order)
            assert(cell==nil or (cell~=2*W+3),'the middle cell joins all four doors')
            assert(T.chooseCell(W,free,doors,{},0,{1*W+1})==1*W+1,'a corner never cuts a door off')
            free={[1*W+1]=true,[1*W+2]=true,[1*W+3]=true}
            assert(T.chooseCell(W,free,{1*W+1,1*W+3},{},0,{1*W+2})==nil,'the corridor stays open')
            free={}
            for y=1,3 do for x=1,5 do free[y*W+x]=true end end
            assert(T.chooseCell(W,free,{},{2*W+3},0,{2*W+3,2*W+4,1*W+1})==1*W+1,'not under or next to a player')
        """)

    def test_inward_steps_point_into_the_room(self):
        self.run_lua("""
            assert(T.inward(0,15)==1 and T.inward(4,15)==1,'left wall: right')
            assert(T.inward(1,15)==15 and T.inward(5,15)==15,'top wall: down')
            assert(T.inward(2,15)==-1 and T.inward(6,15)==-1,'right wall: left')
            assert(T.inward(3,15)==-15 and T.inward(7,15)==-15,'bottom wall: up')
        """)

    def test_door_distances_walk_round_secret_rooms(self):
        self.run_lua("""
            local L=level({[40]={},[41]={},[42]={},[43]={},[44]={},[30]={type=RoomType.ROOM_SECRET},
                [31]={}})
            local d=LR.distances(L,40)
            assert(d[44]==4,'four doors along the row')
            assert(d[30]==nil,'never walks into a secret room')
            assert(d[31]==nil or d[31]>=2,'the room beyond a secret room is not one door away')
        """)

    def test_livers_follow_raw_livers_and_an_older_save_keeps_those_at_hand(self):
        self.run_lua("""
            T.setStarted(true)
            -- a Raw Liver held before Rabbit is not counted
            local p=holder(1,1,{})
            T.reconcile(p)
            assert(p.save.rabbit.livers==0 and p.save.rabbit.counted==1 and p.effects.n==0)
            p.raw=2; T.reconcile(p)
            assert(p.save.rabbit.livers==1 and p.effects.n==1,'the next one is a liver at hand')
            -- without Rabbit the livers are kept but not at hand
            p.copies=0; T.reconcile(p)
            assert(p.save.rabbit.livers==1 and p.effects.n==0)
            p.raw=3; T.reconcile(p)
            assert(p.save.rabbit.livers==1 and p.save.rabbit.counted==3,'taken without Rabbit: no liver')
            p.copies=1; T.reconcile(p)
            assert(p.effects.n==1,'back with Rabbit')
            -- a player who never held Rabbit gets no record
            local q=holder(0,2,{})
            T.reconcile(q)
            assert(q.save.rabbit==nil)
            -- the earlier Rabbit: a liver per copy, some on rocks; those at hand stay
            local old=holder(1,0,{rabbit={out={{room=1}},held=2}})
            T.reconcile(old)
            assert(old.save.rabbit.livers==1 and old.save.rabbit.out==nil and old.save.rabbit.held==nil
                and old.effects.n==1)
            T.setStarted(false)
        """)

    def test_each_liver_past_four_offered_with_the_dragon_adds_0_4_to_damage_for_the_floor(self):
        self.run_lua("""
            T.setStarted(true)
            -- without 진 the overflowing liver is just lost
            local p=holder(1,0,{})
            T.reconcile(p)
            p.raw=5; T.reconcile(p)
            assert(p.save.rabbit.livers==4 and p.floor.rabbitOffering==nil and #um.set==0,'no Dragon: nothing')
            -- with 진 it is offered: x1.4 damage for the floor
            p.dragon=true; p.raw=6; T.reconcile(p)
            assert(p.floor.rabbitOffering==1 and #um.set==1 and um.set[1].stat=='Damage'
                and math.abs(um.set[1].value-1.4)<1e-9 and um.set[1].id==960,'offered: Damage x1.4')
            assert(T.evidence().offered==1 and played[1]==SoundEffect.SOUND_THUNDER)
            -- a second offering on the same floor adds 0.4 more: x1.8
            p.raw=7; T.reconcile(p)
            assert(#um.set==2 and math.abs(um.set[2].value-1.8)<1e-9 and p.floor.rabbitOffering==2
                and T.evidence().offered==2,'added up: x1.8')
            -- two at once add 0.8: x2.6
            p.raw=9; T.reconcile(p)
            assert(math.abs(um.set[3].value-2.6)<1e-9 and p.floor.rabbitOffering==4,'two at once: x2.6')
            -- an older save's true is one offering
            assert(T.offerings({rabbitOffering=true})==1 and T.offerings({})==0)
            -- the next floor's save is new: the multiplier goes
            p.floor={}; p.multipliers={[960]={Damage={value=2.6}}}
            M.onNewLevel()
            T.syncOffering(p)
            assert(#um.removed==1 and um.removed[1].stat=='Damage' and T.offered(p)==0,'the next floor takes it away')
            T.setStarted(false)
        """)

    def test_revives_are_registered_on_the_death_callback_before_vanilla_revives(self):
        self.run_lua("""
            local ids={}
            for _,c in ipairs(callbacks) do ids[c.id]=true end
            assert(ids[1050],'MC_PRE_TRIGGER_PLAYER_DEATH (before 1UP and the like)')
            assert(ids[1482],'MC_POST_PLAYER_REVIVE sets the health')
            assert(M.data.rooms==4 and M.data.livers==4 and M.data.invincible==240,'fours: four doors, four livers, four seconds')
        """)


if __name__ == '__main__':
    unittest.main()
