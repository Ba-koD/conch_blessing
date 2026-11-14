"""소라 잔해 (Conch Debris): production Lua with engine doubles.

A failed Magic Conch evolution in Delete Mode leaves one free debris on the
deleted item's spot; touching it smelts it at once without touching the hand,
and three smelted copies become one Conch Ticket. The doubles stand in for
REPENTOGON's smelted-trinket list and the engine's spawns; `cb test
conch_debris` checks the real engine and the real Magic Conch.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

import test_morph_viewer as viewer_harness

ROOT = Path(__file__).resolve().parents[1]
DEBRIS, TICKET, GOLDEN = 55, 77, 32768

HARNESS = r"""
package=nil
EntityType={ENTITY_PICKUP=5,ENTITY_EFFECT=1000}
PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_TRINKET=350,PICKUP_TAROTCARD=300}
EffectVariant={POOF01=15}
SoundEffect={SOUND_VAMP_GULP=1,SOUND_THUMBSUP=2}
CollectibleType={COLLECTIBLE_MOMS_BOX=439}
TrinketType={TRINKET_GOLDEN_FLAG=32768}
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
V.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
function V:Length() return math.sqrt(self.X*self.X+self.Y*self.Y) end
function V:Resized(n) local l=self:Length(); return Vector(self.X/l*n,self.Y/l*n) end
function V:Distance(o) return (self-o):Length() end
Vector.Zero=Vector(0,0)
local nextHash=0
function GetPtrHash(e) return e.hash end
function RNG()
    local r={s=0}
    function r:SetSeed(seed,shift) self.s=seed end
    function r:Next() self.s=(self.s*1103515245+12345)%4294967296; return self.s end
    return r
end
sounds={}; spawns={}; errors={}; texts={}
function SFXManager() return {Play=function(_,id,volume) sounds[#sounds+1]=id end} end
players={}
room={GetCenterPos=function() return Vector(320,280) end,
    FindFreePickupSpawnPosition=function(_,pos) return pos end}
game={GetRoom=function() return room end,GetNumPlayers=function() return #players end,
    Spawn=function(_,t,v,pos,vel,spawner,sub,seed)
        if gameSpawnFails then return nil end
        local e=pickup(v,sub); e.Position=pos; e.InitSeed=seed
        spawns[#spawns+1]={t=t,v=v,sub=sub,pos=pos,seed=seed,entity=e}
        return e
    end}
function Game() return game end
function pickup(v,sub)
    nextHash=nextHash+1
    local p={hash=nextHash,Variant=v,SubType=sub,Wait=0,Price=0,alive=true,Position=Vector(0,0)}
    function p:Exists() return self.alive end
    function p:Remove() self.alive=false end
    function p:IsShopItem() return self.Price~=0 end
    function p:ToPickup() return self end
    function p:ToPlayer() return nil end
    return p
end
Isaac={GetPlayer=function(i) return players[i+1] end,
    Spawn=function(t,v,sub,pos,vel,spawner)
        spawns[#spawns+1]={t=t,v=v,sub=sub,pos=pos}
        return {}
    end}
function newPlayer(noSmelt)
    nextHash=nextHash+1
    local p={hash=nextHash,hand={0,0},smelted={},Position=Vector(100,100),exists=true,dead=false,ghost=false,
        canPickup=true}
    function p:ToPlayer() return self end
    function p:Exists() return self.exists end
    function p:IsDead() return self.dead end
    function p:IsCoopGhost() return self.ghost end
    function p:CanPickupItem() return self.canPickup end
    function p:HasCollectible() return false end
    function p:GetTrinket(slot) return self.hand[slot+1] end
    function p:TryRemoveTrinket(raw)
        for i=1,2 do if self.hand[i]==raw then self.hand[i]=0; return true end end
        return false
    end
    local function entry(self,raw)
        local base=raw%32768
        self.smelted[base]=self.smelted[base] or {trinketAmount=0,goldenTrinketAmount=0}
        return self.smelted[base], raw>=32768
    end
    function p:GetTrinketMultiplier(id)
        local n=0
        for i=1,2 do
            local raw=self.hand[i]
            if raw>0 and raw%32768==id then n=n+(raw>=32768 and 2 or 1) end
        end
        local e=self.smelted[id]
        if e then n=n+e.trinketAmount+2*e.goldenTrinketAmount end
        return n
    end
    if not noSmelt then
        function p:AddSmeltedTrinket(raw)
            local e,golden=entry(self,raw)
            if golden then e.goldenTrinketAmount=e.goldenTrinketAmount+1 else e.trinketAmount=e.trinketAmount+1 end
        end
        function p:TryRemoveSmeltedTrinket(raw)
            if removeFails then return false end
            local e,golden=entry(self,raw)
            if golden and e.goldenTrinketAmount>0 then e.goldenTrinketAmount=e.goldenTrinketAmount-1; return true end
            if not golden and e.trinketAmount>0 then e.trinketAmount=e.trinketAmount-1; return true end
            return false
        end
        function p:GetSmeltedTrinkets()
            local copy={}
            for id,e in pairs(self.smelted) do copy[id]={trinketAmount=e.trinketAmount,goldenTrinketAmount=e.goldenTrinketAmount} end
            return copy
        end
    end
    players[#players+1]=p
    return p
end
ConchBlessing={printError=function(s) errors[#errors+1]=s end,printDebug=function() end,
    ItemData={CONCH_DEBRIS={id=55}},PocketData={CONCH_TICKET={id=77}},
    EID={showItemText=function(item) texts[#texts+1]=item end}}
local loaded={}
ConchBlessingRequire=function(name)
    if loaded[name]==nil then loaded[name]=dofile(root..'/'..name:gsub('%.','/')..'.lua') end
    return loaded[name]
end
M=ConchBlessingRequire('scripts.items.trinkets.conch_debris')
function smelted(p) return (M.smeltedCount(p)) end
function tickets()
    local n=0
    for _,s in ipairs(spawns) do if s.t==5 and s.v==300 and s.sub==77 then n=n+1 end end
    return n
end
function debris(sub) local d=pickup(350,sub or 55); d.Position=Vector(150,150); return d end
"""


class ConchDebrisModuleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def run_lua(self, code):
        self.lua.execute(code)
        self.assertEqual(list(self.lua.eval('errors').values()), [])

    def test_touching_free_debris_smelts_it_and_leaves_the_hand_alone(self):
        self.run_lua('''
            local p=newPlayer(); p.hand={1,0}   -- Swallowed Penny in the only slot
            local d=debris()
            assert(M.onPrePickupCollision(nil,d,p)==true, 'the engine pickup is cancelled')
            assert(not d:Exists() and smelted(p)==1 and p.hand[1]==1 and p.hand[2]==0)
            assert(#texts==1 and texts[1]==ConchBlessing.ItemData.CONCH_DEBRIS, 'the name banner shows')
            assert(tickets()==0)
        ''')

    def test_touches_left_to_the_engine(self):
        cases = {
            'a helper player': 'p.Parent={}',
            'a dead player': 'p.dead=true',
            'a co-op ghost': 'p.ghost=true',
            'a player who cannot pick up now': 'p.canPickup=false',
            'a debris for sale': 'd.Price=15',
            'a debris still waiting': 'd.Wait=10',
            'another trinket': 'd.SubType=56',
            'a card with the same number': 'd.Variant=300',
        }
        for label, setup in cases.items():
            with self.subTest(label):
                self.run_lua(f'''
                    local p=newPlayer(); local d=debris()
                    {setup}
                    assert(M.onPrePickupCollision(nil,d,p)==nil and d:Exists() and smelted(p)==0)
                ''')
        self.run_lua('''
            local p=newPlayer(true); local d=debris()
            assert(M.onPrePickupCollision(nil,d,p)==nil and d:Exists(), 'no smelt API: left to the engine')
        ''')

    def test_a_golden_debris_is_smelted_golden_and_counts_once(self):
        self.run_lua(f'''
            local p=newPlayer()
            assert(M.onPrePickupCollision(nil,debris({DEBRIS + GOLDEN}),p)==true)
            local total,normal,golden=M.smeltedCount(p)
            assert(total==1 and normal==0 and golden==1)
        ''')

    def test_three_copies_become_one_conch_ticket(self):
        self.run_lua(f'''
            local p=newPlayer()
            for i=1,2 do M.onPrePickupCollision(nil,debris(),p) end
            assert(smelted(p)==2 and tickets()==0)
            M.onPrePickupCollision(nil,debris({DEBRIS + GOLDEN}),p)
            assert(smelted(p)==0 and tickets()==1, 'normal, normal and golden make one ticket')
            local e=p.smelted[{DEBRIS}]
            assert(e.trinketAmount==0 and e.goldenTrinketAmount==0)
            assert(M._test.evidence().tickets==1)
        ''')

    def test_every_three_make_a_ticket_and_the_rest_wait(self):
        for copies, made, left in ((5, 1, 2), (6, 2, 0), (2, 0, 2)):
            with self.subTest(copies=copies):
                self.run_lua(f'''
                    spawns={{}}
                    local p=newPlayer()
                    p.smelted[{DEBRIS}]={{trinketAmount={copies},goldenTrinketAmount=0}}
                    M.settle(p)
                    assert(tickets()=={made} and smelted(p)=={left}, tickets()..' '..smelted(p))
                ''')

    def test_the_ticket_lies_a_tile_toward_the_room_middle(self):
        self.run_lua('''
            local p=newPlayer(); p.Position=Vector(100,280)
            p.smelted[55]={trinketAmount=3,goldenTrinketAmount=0}
            M.settle(p)
            local ticket
            for _,s in ipairs(spawns) do if s.v==300 then ticket=s end end
            assert(ticket and ticket.pos.X==140 and ticket.pos.Y==280, ticket and ticket.pos.X)
        ''')

    def test_a_failed_removal_makes_no_ticket_and_reports_once(self):
        self.lua.execute('''
            removeFails=true
            local p=newPlayer()
            p.smelted[55]={trinketAmount=3,goldenTrinketAmount=0}
            M.settle(p); M.settle(p)
            assert(tickets()==0 and smelted(p)==3)
        ''')
        self.assertEqual(len(self.lua.eval('errors')), 1)

    def test_a_copy_in_the_hand_is_smelted_on_the_next_update(self):
        self.run_lua(f'''
            local p=newPlayer(); p.hand={{{DEBRIS},{DEBRIS + GOLDEN}}}
            M.onPEffectUpdate(nil,p)
            assert(p.hand[1]==0 and p.hand[2]==0 and smelted(p)==2 and M._test.evidence().fromHand==2)
            p.hand={{{DEBRIS},0}}
            M.onPEffectUpdate(nil,p)
            assert(smelted(p)==0 and tickets()==1 and p.hand[1]==0)
        ''')

    def test_a_smelt_made_elsewhere_still_adds_up(self):
        self.run_lua('''
            local p=newPlayer()
            M.onPEffectUpdate(nil,p)
            p.smelted[55]={trinketAmount=3,goldenTrinketAmount=0}   -- an absorbed Hermit Crab, a console command
            M.onPEffectUpdate(nil,p)
            assert(smelted(p)==0 and tickets()==1)
            M.onPEffectUpdate(nil,p)
            assert(tickets()==1, 'settled once')
        ''')

    def test_continue_settles_a_saved_heap(self):
        self.run_lua('''
            local p=newPlayer(); local q=newPlayer()
            p.smelted[55]={trinketAmount=4,goldenTrinketAmount=0}
            q.smelted[55]={trinketAmount=1,goldenTrinketAmount=0}
            M.onGameStarted()
            assert(smelted(p)==1 and smelted(q)==1 and tickets()==1, 'each player counts their own')
        ''')

    def test_drop_lies_on_the_spot_with_a_seed_of_its_own(self):
        self.run_lua('''
            newPlayer()
            local d=M.dropAt(Vector(200,120), 4242)
            local s=spawns[#spawns]
            assert(d and s.t==5 and s.v==350 and s.sub==55 and s.pos.X==200 and s.pos.Y==120)
            assert(s.seed~=0 and s.seed~=4242, 'not the deleted pickup seed')
            assert(d.Price==0 and M._test.evidence().dropped==1)
            local again=M.dropAt(Vector(200,120), 4242)
            assert(spawns[#spawns].seed==s.seed, 'the same source gives the same seed')
        ''')

    def test_no_debris_without_the_smelt_api(self):
        self.run_lua('''
            newPlayer(true)
            assert(M.dropAt(Vector(1,1), 5)==nil and #spawns==0)
        ''')


class DeleteModeDebrisTests(unittest.TestCase):
    """The upgrade module's Delete Mode hands failed evolutions to the debris."""

    def setUp(self):
        harness = viewer_harness.MorphVisualTests
        harness.setUp(self)
        harness.viewer(self)
        self.lua.execute('''
            EntityType.ENTITY_EFFECT=1000; EffectVariant=EffectVariant or {}; EffectVariant.POOF01=15
            -- deletion spawns its poof with Vector.Zero; this harness's Vector is a bare function
            if type(Vector)=='function' then
                local make=Vector
                Vector=setmetatable({Zero=make(0,0)},{__call=function(_,x,y) return make(x,y) end})
            end
            SoundEffect.SOUND_THUMBS_DOWN=SoundEffect.SOUND_THUMBS_DOWN or 99
            local spawnPickup=Isaac.Spawn
            Isaac.Spawn=function(t,...)
                if t==1000 then poofs=(poofs or 0)+1; return {} end
                return spawnPickup(t,...)
            end
            drops={}
            ConchBlessing.conchdebris={
                dropAt=function(pos,seed) drops[#drops+1]={x=pos.X,y=pos.Y,seed=seed} end,
                isDebris=function(sub) return sub==4242 end}
            for i=1,10 do event(1) end -- Magic Conch callback registration
            origin=ConchBlessing.ItemData.DRAGON.origin.id   -- evolves on a positive answer only
            function fresh() entities={}; drops={}; poofs=0 end
        ''')

    def test_a_failed_evolution_leaves_debris_where_it_stood(self):
        self.lua.execute('''
            fresh()
            local failing=Isaac.Spawn(5,100,origin,Vector(80,90),Vector(0,0),nil)
            failing.Price=15; failing.OptionsPickupIndex=3
            local seed=failing.InitSeed
            actualConchResult({type='negative'})
            assert(not failing:Exists() and poofs==1)
            assert(#drops==1 and drops[1].x==80 and drops[1].y==90 and drops[1].seed==seed)
            assert(#ConchBlessing._upgradeJobs==0 and #errors==0)
        ''')

    def test_every_failed_item_in_the_room_leaves_its_own(self):
        self.lua.execute('''
            fresh()
            for i=1,3 do Isaac.Spawn(5,100,origin,Vector(40*i,90),Vector(0,0),nil) end
            actualConchResult({type='neutral'})
            assert(#drops==3 and #errors==0)
        ''')

    def test_items_that_cannot_evolve_and_old_debris(self):
        self.lua.execute('''
            fresh()
            local plain=Isaac.Spawn(5,100,999,Vector(10,10),Vector(0,0),nil)
            local old=Isaac.Spawn(5,350,4242,Vector(20,20),Vector(0,0),nil)
            actualConchResult({type='negative'})
            assert(not plain:Exists(), 'Delete Mode still deletes it on a negative answer')
            assert(old:Exists(), 'the debris itself is never deleted')
            assert(#drops==0 and #errors==0, 'nothing that never tried to evolve leaves debris')
        ''')

    def test_a_matching_answer_evolves_and_drops_nothing(self):
        self.lua.execute('''
            fresh()
            local p=Isaac.Spawn(5,100,origin,Vector(80,90),Vector(0,0),nil)
            actualConchResult({type='positive'})
            assert(p:Exists() and #ConchBlessing._upgradeJobs==1 and #drops==0)
        ''')

    def test_without_delete_mode_nothing_is_deleted_or_dropped(self):
        self.lua.execute('''
            fresh()
            MagicConch.API.Config.deleteMode=false
            local p=Isaac.Spawn(5,100,origin,Vector(80,90),Vector(0,0),nil)
            actualConchResult({type='negative'})
            assert(p:Exists() and #drops==0 and (poofs or 0)==0 and #errors==0)
        ''')


if __name__ == '__main__':
    unittest.main()
