"""소라 증명서 (Conch Certificate): production Lua with engine doubles.

The real Death Certificate adapter (death_certificate_gallery_rooms.lua) runs on
a fake dimension-2 room list, and the shipped item module converts its rooms.
These doubles cannot show the engine's own item order, its way home or the
pedestals' look; `conch_test conch_certificate` covers those in game.
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
REPENTOGON={Real=true}
EntityType={ENTITY_PICKUP=5}
PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350}
ItemType={ITEM_TRINKET=2,ITEM_PASSIVE=1}
CollectibleType={COLLECTIBLE_DEATH_CERTIFICATE=628}
UseFlag={USE_NOANIM=1,USE_NOCOSTUME=2,USE_ALLOWNONMAIN=8,USE_NOANNOUNCER=1<<5,USE_NOHUD=1<<10}
ModCallbacks={MC_POST_NEW_ROOM=19}
CallbackPriority={EARLY=-100}
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
Vector.Zero=Vector(0,0)

WIDTH=15
local room={}
function room:GetGridWidth() return WIDTH end
function room:GetGridIndex(p) return math.floor(p.X/40)+math.floor(p.Y/40)*WIDTH end
function room:GetGridPosition(i) return Vector((i%WIDTH)*40+20,math.floor(i/WIDTH)*40+20) end

-- Death Certificate layouts: the entrance (subtype 33) and stock rooms (34)
-- whose collectible spawns sit on (x,y) layout cells (grid cell x+1,y+1).
local function layout(subtype,variant,cells)
    local spawns={}
    for i,c in ipairs(cells) do
        spawns[i]={X=c[1],Y=c[2],EntryCount=1,PickEntry=function() return {Type=5,Variant=100} end}
    end
    return {Shape=1,Variant=variant,Subtype=subtype,Type=1,StageID=35,Name='Death Certificate',Doors=15,
        Spawns={Size=#spawns,Get=function(_,i) return spawns[i+1] end}}
end
CELLS={{0,0},{2,0},{4,0},{6,0}}
function descriptor(listIndex,grid,data)
    return {ListIndex=listIndex,GridIndex=grid,SafeGridIndex=grid,SpawnSeed=1000+listIndex,Data=data,
        DisplayFlags=0,GetDimension=function() return 2 end}
end
descs={descriptor(0,80,layout(33,100,{})),descriptor(1,81,layout(34,101,CELLS)),descriptor(2,82,layout(34,102,CELLS))}
dimension=0; mode=0; current=nil
local level={}
function level:GetDimension() return dimension end
function level:GetRooms() return {Size=#descs,Get=function(_,i) return descs[i+1] end} end
function level:UpdateVisibility() end
function level:GetCurrentRoomDesc() return current or {ListIndex=99,Data={},GetDimension=function() return 0 end} end
function level:GetStage() return stage or 1 end
function level:GetStageType() return 0 end
function level:GetDungeonPlacementSeed() return 4242 end
RoomTransition={GetTransitionMode=function() return mode end}

pickups={}; local nextSeed=500
function pickup(variant,subtype,grid,seed)
    nextSeed=nextSeed+1
    local p={Type=5,Variant=variant,SubType=subtype,InitSeed=seed or nextSeed,Price=0,exists=true,
        Position=room:GetGridPosition(grid)}
    function p:Exists() return self.exists end
    function p:Remove() self.exists=false end
    function p:ToPickup() return self end
    function p:Morph(t,v,s,keepPrice,keepSeed,ignore)
        assert(t==5 and keepSeed==true and ignore==true,'Morph keeps the seed and ignores modifiers')
        self.Variant,self.SubType=v,s
    end
    pickups[#pickups+1]=p
    return p
end
function live(variant)
    local out={}
    for _,p in ipairs(pickups) do if p.exists and p.Variant==variant then out[#out+1]=p end end
    return out
end
function at(variant,grid)
    for _,p in ipairs(live(variant)) do if room:GetGridIndex(p.Position)==grid then return p end end
end
function slotGrid(slot) return (CELLS[slot][1]+1)+(CELLS[slot][2]+1)*WIDTH end
-- The engine fills a room's pedestals when it loads.
function stock(firstId)
    pickups={}
    for slot=1,#CELLS do pickup(100,firstId+slot-1,slotGrid(slot)) end
end

local game={}
function game:GetLevel() return level end
function game:GetRoom() return room end
function game:GetSeeds() return {GetStartSeed=function() return 777 end} end
function game:Spawn(t,v,pos,vel,spawner,subtype,seed)
    local p=pickup(v,subtype,room:GetGridIndex(pos),seed)
    return p
end
Game=function() return game end
Isaac={FindByType=function(t,v) return live(v) end}

errors={}; prints={}
runSave={}
ConchBlessing={
    print=function(s) prints[#prints+1]=s end,
    printError=function(s) errors[#errors+1]=s end,
    printDebug=function() end,
    AddCallback=function() end,
    AddPriorityCallback=function(_,id,prio,fn) assert(id==19 and prio==-100); onRoom=fn end,
    AddCallbackCustom=function() end,
    originalMod={AddCallback=function() end},
    SaveManager={IsLoaded=function() return true end,GetRunSave=function() return runSave end,
        TryGetRunSave=function() return runSave end,SaveCallbacks={POST_DATA_LOAD='POST_LOAD'}},
    ItemData={
        LIVE_EYE={type='passive',id=970}, VOID_DAGGER={type='passive',id=971},
        CONCH_CERTIFICATE={type='active',id=975}, SNAKE={type='passive',id=976,WorkingNow=true,hidden=true},
        TIME_POWER={type='trinket',id=200}, ATROPOS={type='trinket',id=207},
        BROKEN={type='passive',id=-1},
    },
}
local stubs={['scripts.lib.isaacscript-common']={ModCallbackCustom={POST_ITEM_PICKUP=1}}}
require=function(name)
    if stubs[name] then return stubs[name] end
    if name=='scripts.lib.run_save_cache' then return dofile(root..'/scripts/lib/run_save_cache.lua') end
    assert(name=='scripts.rooms.death_certificate_gallery_rooms','unexpected require '..name)
    return dofile(root..'/scripts/rooms/death_certificate_gallery_rooms.lua')
end
M=dofile(root..'/scripts/items/collectibles/conch_certificate.lua')
M._ready=true

dcCalls={}
player={}
function player:UseActiveItem(id,flags,slot)
    dcCalls[#dcCalls+1]={id=id,flags=flags,slot=slot}
    if transitions~=false then mode=1 end
end
function player:AnimateCollectible() end
function arrive(listIndex)
    mode=0; dimension=2; current=descs[listIndex+1]; onRoom()
end
function ledger() return runSave.conchCertificate end
"""


class ConchCertificateTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_catalog_is_our_collectibles_by_id_then_our_trinkets(self):
        self.run_lua(r'''
            local list=M.buildCatalog(ConchBlessing.ItemData,'CONCH_CERTIFICATE')
            local got={}
            for _,e in ipairs(list) do got[#got+1]=e.kind:sub(1,1)..e.id end
            -- the WIP preview is in, the certificate itself and an unresolved row are out
            assert(table.concat(got,',')=='c970,c971,c976,t200,t207',table.concat(got,','))
        ''')

    def test_slots_take_the_catalog_in_layout_order(self):
        self.run_lua(r'''
            local catalog={{kind='collectible',id=1},{kind='collectible',id=2},{kind='trinket',id=3}}
            local manifest={catalogStart=3,slotCount=1}
            assert(M.entryFor(catalog,manifest,1).id==3)
            assert(M.entryFor(catalog,manifest,2)==nil,'past the room share')
            assert(M.entryFor(catalog,manifest,0)==nil)
            local a,b=M.slotSeed(5,1,1),M.slotSeed(5,1,2)
            assert(a==M.slotSeed(5,1,1) and a~=b and a>=1 and a<=2147483646)
        ''')

    def test_use_calls_the_real_death_certificate_and_opens_a_visit(self):
        self.run_lua(r'''
            local result=M.onUseItem(nil,975,nil,player)
            assert(result.Discharge==false and result.Remove==false and result.ShowAnim==false)
            assert(#dcCalls==1 and dcCalls[1].id==628 and dcCalls[1].slot==-1)
            local f=dcCalls[1].flags
            assert(f&UseFlag.USE_NOANIM==0,'Death Certificate keeps its own hold-up')
            assert(f&UseFlag.USE_NOCOSTUME~=0 and f&UseFlag.USE_NOANNOUNCER~=0 and f&UseFlag.USE_NOHUD~=0)
            assert(ledger().visiting==true and ledger().graph==nil)
            assert(#ledger().catalog==5)
        ''')

    def test_a_use_whose_transition_never_starts_closes_the_visit(self):
        self.run_lua(r'''
            transitions=false
            M.onUseItem(nil,975,nil,player)
            assert(ledger().visiting==false and #errors==1, tostring(errors[1]))
        ''')

    def test_rooms_fill_from_the_first_pedestal_and_the_rest_go(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player)
            pickups={}; arrive(0)
            assert(ledger().graph and ledger().graph.entrance.listIndex==0,'adopted on arrival')
            assert(next(ledger().rooms)==nil,'the entrance is left alone')
            -- room 1: four engine pedestals 1..4 and one stray off the slots
            stock(1); local stray=pickup(100,99,3+5*WIDTH)
            local seeds={}
            for slot=1,4 do seeds[slot]=at(100,slotGrid(slot)).InitSeed end
            arrive(1)
            for slot,id in ipairs({970,971,976}) do
                local p=at(100,slotGrid(slot))
                assert(p and p.SubType==id and p.InitSeed==seeds[slot],'slot '..slot..' Morphed in place')
            end
            assert(at(100,slotGrid(4))==nil and at(350,slotGrid(4)).SubType==200,'a trinket where the pedestal stood')
            assert(not stray:Exists(),'a stray collectible goes')
            local state=ledger().rooms['ConchBlessing:DeathCertificate:1']
            assert(table.concat(state.original,',')=='1,2,3,4','the engine items are kept as evidence')
            -- room 2: the last trinket, then every pedestal past the catalog goes
            stock(5); arrive(2)
            assert(at(350,slotGrid(1)).SubType==207 and at(100,slotGrid(1))==nil)
            for slot=2,4 do assert(at(100,slotGrid(slot))==nil and at(350,slotGrid(slot))==nil,'slot '..slot) end
            assert(table.concat(ledger().rooms['ConchBlessing:DeathCertificate:2'].original,',')=='5,6,7,8')
        ''')

    def test_a_pedestal_taken_before_gets_a_new_one_with_a_fixed_seed(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0)
            stock(1); at(100,slotGrid(2)).exists=false
            arrive(1)
            local p=at(100,slotGrid(2))
            assert(p and p.SubType==971 and p.InitSeed==M.slotSeed(ledger().seed,1,2))
            assert(ledger().rooms['ConchBlessing:DeathCertificate:1'].original[2]==0)
        ''')

    def test_a_revisit_keeps_ours_removes_others_and_puts_back_what_was_not_taken(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0); stock(1); arrive(1)
            local state=ledger().rooms['ConchBlessing:DeathCertificate:1']
            local seed2,seed4=state.seeds[2],state.seeds[4]
            -- slot 1 taken for real, slot 2 and the trinket on slot 4 gone with the
            -- room the engine emptied, slot 3 still there
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_PASSIVE,subType=970})
            at(100,slotGrid(1)).exists=false
            at(100,slotGrid(2)).exists=false
            at(350,slotGrid(4)).exists=false
            local third=at(100,slotGrid(3))
            local foreign=pickup(100,555,6+3*WIDTH)     -- something else turned up
            local dropped=pickup(350,5,7+3*WIDTH)       -- a trinket a player dropped
            arrive(1)
            assert(not foreign:Exists(),'a foreign collectible goes')
            assert(dropped:Exists(),'a dropped trinket stays')
            assert(at(100,slotGrid(1))==nil,'the taken item came back')
            local second=at(100,slotGrid(2))
            assert(second and second.SubType==971 and second.InitSeed==seed2,'slot 2 not put back with its seed')
            assert(at(100,slotGrid(3))==third and third:Exists(),'a present item was touched')
            local trinket=at(350,slotGrid(4))
            assert(trinket and trinket.SubType==200 and trinket.InitSeed==seed4,'the trinket not put back')
            assert(ledger().taken.c970==true and ledger().taken.c971==nil and ledger().taken.t200==nil)
            -- once more: nothing is doubled
            local count=#live(100)+#live(350)
            arrive(1)
            assert(#live(100)+#live(350)==count,'a second revisit added pedestals')
        ''')

    def test_a_trinket_taken_on_the_way_is_not_put_back(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0); stock(1); arrive(1)
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_TRINKET,subType=200})
            at(350,slotGrid(4)).exists=false
            arrive(1)
            assert(at(350,slotGrid(4))==nil and ledger().taken.t200==true)
        ''')

    def test_leaving_the_area_ends_the_visit(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0)
            dimension=0; current=nil; onRoom()
            assert(ledger().visiting==false)
            stock(1); dimension=2; current=descs[2]; onRoom()
            assert(at(100,slotGrid(1)).SubType==1,'a later vanilla Death Certificate visit is not converted')
        ''')

    def test_taking_a_catalog_collectible_is_noted(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0)
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_TRINKET,subType=5})
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_PASSIVE,subType=12})
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_TRINKET,subType=970})
            assert(next(ledger().taken)==nil,'a foreign item, or a trinket with a collectible ID, is not a catalog take')
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_PASSIVE,subType=971})
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_TRINKET,subType=207|32768})
            assert(ledger().taken.c971==true and ledger().taken.t207==true,'golden or not, a catalog trinket is noted')
            dimension=0
            M.onPostItemPickup(nil,player,{itemType=ItemType.ITEM_PASSIVE,subType=970})
            assert(ledger().taken.c970==nil,'only inside the area')
        ''')

    def test_uses_are_refused_when_they_cannot_work(self):
        self.run_lua(r'''
            M._ready=false
            assert(M.blockReason(player)=='run_not_ready')
            M._ready=true
            assert(M.blockReason(player)==nil,'an ordinary room on a fresh floor')
            dimension=2; assert(M.blockReason(player)=='inside'); dimension=0
            mode=1; assert(M.blockReason(player)=='transition_busy'); mode=0
            ConchBlessing.GalleryManager={isVisitActive=function() return true end}
            assert(M.blockReason(player)=='appraisal_visit')
            ConchBlessing.GalleryManager=nil
            local r=M.onPreUseItem(nil,975,nil,player)
            assert(r==nil)
            dimension=2
            r=M.onPreUseItem(nil,975,nil,player)
            assert(type(r)=='table' and r.Discharge==false,'cancelled before it is accepted')
            dimension=0
        ''')

    def test_nothing_left_to_take_refuses_the_use(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0)
            dimension=0; current=nil; onRoom()
            for _,id in ipairs({970,971,976}) do ledger().taken['c'..id]=true end
            assert(M.blockReason(player)=='empty','only trinkets left: no way home')
        ''')

    def test_foreign_rooms_in_dimension_two_are_refused_before_use(self):
        self.run_lua(r'''
            descs[2].Data.Name='Somebody else'
            assert(tostring(M.blockReason(player)):find('^foreign_rooms'))
        ''')

    def test_a_new_floor_drops_the_record(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0)
            stage=2; M.onPostNewLevel()
            assert(ledger()==nil)
        ''')

    def test_a_continued_run_inside_the_area_converts_the_current_room(self):
        self.run_lua(r'''
            M.onUseItem(nil,975,nil,player); pickups={}; arrive(0)
            M._ready=false
            stock(1); dimension=2; current=descs[2]; onRoom()
            assert(at(100,slotGrid(1)).SubType==1,'gated before game start')
            M.onGameStarted(nil,true)
            assert(at(100,slotGrid(1)).SubType==970)
        ''')


if __name__ == '__main__':
    unittest.main()
