"""소라게 (Hermit Crab): production Lua with engine doubles.

The crab wanders the room on its own (never following its owner), walks over
to the trinkets its own owner puts down (a pickup whose spawner is that player)
and takes them on arrival unless the owner stands within two tiles of them or a
Magic Conch upgrade is changing them, holds them as innate trinkets of its owner, puts the oldest down when its
claws are full, lets go of the newest when it loses room, and, once Kronos has
absorbed it, keeps what it held and smelts the next trinkets in hand at once.
These doubles cannot show the engine's drop, smelt or drawing;
`conch_test hermit_crab` covers those in game.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
import importlib.util
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
TrinketType={TRINKET_GOLDEN_FLAG=32768}
CollectibleType={COLLECTIBLE_BFFS=247}
CacheFlag={CACHE_FAMILIARS=1<<9}
EntityType={ENTITY_PICKUP=5,ENTITY_EFFECT=1000,ENTITY_FAMILIAR=3}
EffectVariant={POOF01=15}
SoundEffect={SOUND_SCAMPER=1}
ModCallbacks={MC_POST_PICKUP_INIT=34}
EntityGridCollisionClass={GRIDCOLL_WALLS=3}
GridCollisionClass={COLLISION_NONE=0,COLLISION_SOLID=3,COLLISION_WALL=4,COLLISION_WALL_EXCEPT_PLAYER=5}
CRAB=900; VARIANT=779; GOLD=32768
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
V.__mul=function(a,b) return Vector(a.X*b,a.Y*b) end
V.__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
function V:Length() return math.sqrt(self.X*self.X+self.Y*self.Y) end
function RNG()
    local r={seed=1}
    function r:SetSeed(s) self.seed=s%2147483648 end
    function r:Next() self.seed=(self.seed*1103515245+12345)%2147483648; return self.seed end
    function r:RandomFloat() return self:Next()/2147483648 end
    function r:RandomInt(n) return self:Next()%n end
    return r
end
Vector.Zero=Vector(0,0)
function Color(...) return {A=1} end
rendered={}; sampleCount=0; sampleTextures=true
function Sprite()
    local s={animation='',frame=0,sheets={},Scale=Vector(1,1)}
    function s:Load(path) self.path=path end
    function s:LoadGraphics() end
    function s:ReplaceSpritesheet(i,path) self.sheets[i]=path end
    function s:Play(name) self.animation=name;self.frame=0 end
    function s:GetAnimation() return self.animation end
    function s:GetFrame() return self.frame end
    function s:SetFrame(name,f) self.animation=name;self.frame=f end
    if sampleTextures then
        function s:GetTexel(pos)
            sampleCount=sampleCount+1
            return {Alpha=(pos.X>=8 and pos.X<24 and pos.Y>=4 and pos.Y<28) and 1 or 0}
        end
    end
    function s:Render(pos)
        rendered[#rendered+1]={animation=self.animation,frame=self.frame,x=pos.X,y=pos.Y,
            sx=self.Scale.X,sy=self.Scale.Y,sheet=self.sheets[0]}
    end
    return s
end
local nextHash=0
function GetPtrHash(e) return e.hash end
function EntityPtr(e)
    local generation=e.generation or 0
    return setmetatable({},{__index=function(_,k)
        if k=='Ref' and (e.generation or 0)==generation then return e end
    end})
end
function morph(e,subtype)
    M.onPrePickupMorph(nil,e)
    e.generation=(e.generation or 0)+1; e.SubType=subtype
    M.onPostPickupMorph(nil,e)
end
function SFXManager() return {Play=function() end} end
errors={}; spawned={}; familiars={}
local function entity(fields)
    nextHash=nextHash+1
    local e={hash=nextHash,data={},exists=true,Position=Vector(0,0)}
    for k,v in pairs(fields or {}) do e[k]=v end
    function e:GetData() return self.data end
    function e:Exists() return self.exists end
    function e:Remove() self.exists=false end
    function e:ToPickup() return self.Variant==350 and self or nil end
    function e:ToPlayer() return self.isPlayer and self or nil end
    function e:ToFamiliar() return self.isFamiliar and self or nil end
    return e
end
function newPlayer(copies)
    local p=entity({isPlayer=true,copies=copies or 0,bffs=0,absorbed=0,smelted={},innate={},slots={0,0},save={},dead=false,refuse=false,
        Position=Vector(500,350)})
    function p:IsDead() return self.dead end
    function p:IsCoopGhost() return false end
    function p:GetCollectibleNum(id) return id==CRAB and self.copies or id==247 and self.bffs or 0 end
    function p:HasCollectible(id) return self:GetCollectibleNum(id)>0 end
    function p:AddSmeltedTrinket(id) self.smelted[id]=(self.smelted[id] or 0)+1 end
    function p:AddInnateTrinket(id,n,group)
        assert(group=='ConchBlessingHermitCrab','the crabs keep to their own group')
        self.innate[id]=(self.innate[id] or 0)+(n or 1)
    end
    function p:RemoveInnateTrinket(id,n,group)
        assert(group=='ConchBlessingHermitCrab')
        if self.refuse then return 0 end
        local have=self.innate[id] or 0; local k=math.min(have,n or 1)
        self.innate[id]=have-k; return k
    end
    function p:GetInnateTrinketCount(id,group)
        assert(group=='ConchBlessingHermitCrab'); return self.innate[id] or 0
    end
    function p:TryRemoveSmeltedTrinket(id)
        if self.refuse or (self.smelted[id] or 0)<=0 then return false end
        self.smelted[id]=self.smelted[id]-1; return true
    end
    function p:GetTrinket(slot) return self.slots[slot+1] end
    function p:TryRemoveTrinket(id)
        for i=1,2 do if self.slots[i]==id then self.slots[i]=0; return true end end
        return false
    end
    return p
end
function newPickup(id,spawner)
    return entity({Variant=350,SubType=id,SpawnerEntity=spawner,Position=Vector(10,20)})
end
function newCrab(owner,seed)
    local f=entity({isFamiliar=true,Player=owner,InitSeed=seed,Variant=VARIANT,
        SpriteScale=Vector(1,1),PositionOffset=Vector.Zero,Velocity=Vector.Zero,Color=Color(),sprite=Sprite()})
    function f:GetSprite() return self.sprite end
    function f:AddToFollowers() self.follower=true end
    function f:FollowParent() self.followed=true end
    familiars[#familiars+1]=f
    return f
end
players={}
-- a 600x400 room; wall(pos) marks solid cells the crab cannot walk through
wall=function() return false end
local function inside(pos) return pos.X>=0 and pos.X<=600 and pos.Y>=0 and pos.Y<=400 end
local room={FindFreePickupSpawnPosition=function(_,pos) return pos end,
    GetTopLeftPos=function() return Vector(0,0) end,
    GetBottomRightPos=function() return Vector(600,400) end,
    IsPositionInRoom=function(_,pos) return inside(pos) end,
    GetGridCollisionAtPos=function(_,pos) return wall(pos) and 4 or 0 end}
local game={GetNumPlayers=function() return #players end,GetRoom=function() return room end}
Game=function() return game end
Isaac={GetItemIdByName=function(n) return n=='Hermit Crab' and CRAB or -1 end,
    GetEntityVariantByName=function(n) return n=='Hermit Crab' and VARIANT or -1 end,
    WorldToRenderPosition=function(p) return p end,
    GetItemConfig=function() return {GetTrinket=function(_,id)
        if id&~32768==145 then return {GfxFileName='gfx/items/trinkets/Trinket_145_Perfection.png'} end
        return {GfxFileName='gfx/items/trinkets/fixture_'..id..'.png'} end} end,
    GetPlayer=function(i) return players[i+1] end,
    FindByType=function(t,v) if t==3 and v==VARIANT then return familiars end return {} end,
    Spawn=function(t,v,s,pos,vel,spawner)
        local e=entity({Type=t,Variant=v,SubType=s,Position=pos,SpawnerEntity=spawner})
        spawned[#spawned+1]=e; return e end}
saveCallbacks={}
ConchBlessing={printError=function(e) errors[#errors+1]=e end,printDebug=function() end,
    AddCallback=function() end,
    originalMod={__SAVEMANAGER_UNIQUE_KEY='test',AddCallback=function(_,id,fn) saveCallbacks[id]=fn end},
    SaveManager={GetRunSave=function(p) return p.save end,SaveCallbacks={POST_DATA_LOAD='POST_DATA_LOAD'}},
    kronos={_getEffectCount=function(p,id) return id==CRAB and p.absorbed or 0 end}}
local stubs={
    ['scripts.items.familiars.hermit_crab_visuals']=dofile(root..'/scripts/items/familiars/hermit_crab_visuals.lua'),
    ['scripts.lib.sound_volume']={volume=function(v) return v end},
    ['scripts.lib.trinket_utils']={getSmeltedCounts=function(p,base)
        return p.smelted[base] or 0, p.smelted[base|GOLD] or 0 end},
}
require=function(name) return assert(stubs[name],'unexpected require '..name) end
M=dofile(root..'/scripts/items/familiars/hermit_crab.lua')
T=M._test
function held(p) return table.concat(p.save.hermitCrab and p.save.hermitCrab.held or {},',') end
function onFloor(id)
    local n=0
    for _,e in ipairs(spawned) do if e.Variant==350 and e.SubType==id and e.exists then n=n+1 end end
    return n
end
-- one engine update: every crab moves, sliding along walls the way grid
-- collision does, then MC_POST_UPDATE
local function free(pos) return inside(pos) and not wall(pos) end
function step()
    for _,f in ipairs(familiars) do
        if f.exists then
            M.onFamiliarUpdate(nil,f)
            local v=f.Velocity
            for _,try in ipairs({v,Vector(v.X,0),Vector(0,v.Y)}) do
                if free(f.Position+try) then f.Position=f.Position+try; break end
            end
        end
    end
    M.onUpdate()
end
function crabOf(p)
    for _,f in ipairs(familiars) do if f.Player==p and f.exists then return f end end
    if p.copies>0 then local f=newCrab(p,100+#familiars); M.onFamiliarInit(nil,f); return f end
end
-- the owner puts a trinket down; the crab walks over and takes it (bounded)
function drop(p,id,at)
    crabOf(p)
    local pk=newPickup(id,p); if at then pk.Position=at end
    M.onPickupInit(nil,pk); M.onUpdate()
    for _=1,3000 do if not pk.exists then break end; step() end
    return pk
end
function stepsUntil(pk,limit) local n=0; while pk.exists and n<limit do step(); n=n+1 end; return n end
"""


class HermitCrabTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_takes_its_owners_drop_as_a_smelt(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local pk=drop(p,5)
            assert(not pk.exists and p.innate[5]==1 and held(p)=='5' and (p.smelted[5] or 0)==0, 'taken: '..held(p))
            assert(T.evidence().taken==1)
        ''')

    def test_nothing_happens_before_the_game_has_started(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}
            local pk=drop(p,5)
            assert(pk.exists and (p.innate[5] or 0)==0 and p.save.hermitCrab==nil)
        ''')

    def test_room_trinkets_and_other_players_drops_are_ignored(self):
        self.run_lua(r'''
            local p=newPlayer(1); local other=newPlayer(0); players={p,other}; M.onGameStarted()
            local roomTrinket=newPickup(5,nil); M.onPickupInit(nil,roomTrinket)
            local othersDrop=newPickup(6,other); M.onPickupInit(nil,othersDrop)
            M.onUpdate()
            assert(roomTrinket.exists and othersDrop.exists and held(p)=='' and T.evidence().taken==0)
        ''')

    def test_a_full_crab_puts_the_oldest_down_and_never_retakes_it(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            drop(p,5); drop(p,6)
            assert(held(p)=='6' and p.innate[5]==0 and p.innate[6]==1, held(p))
            assert(onFloor(5)==1 and T.evidence().putDown==1)
            local putDown=spawned[#spawned]
            for _,e in ipairs(spawned) do if e.Variant==350 and e.SubType==5 then putDown=e end end
            assert(putDown.SpawnerEntity==nil and putDown.data.__ConchBlessingCrabPutDown, 'put down without a spawner')
            M.onPickupInit(nil,putDown); M.onUpdate()
            assert(held(p)=='6', 'not taken back')
        ''')

    def test_golden_trinkets_stay_golden(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            drop(p,5|GOLD)
            assert(p.innate[5|GOLD]==1 and (p.innate[5] or 0)==0)
        ''')

    def test_bffs_doubles_the_room_and_losing_it_lets_go_of_the_newest(self):
        self.run_lua(r'''
            local p=newPlayer(1); p.bffs=1; players={p}; M.onGameStarted()
            drop(p,5); drop(p,6)
            assert(held(p)=='5,6' and p.innate[5]==1 and p.innate[6]==1)
            p.bffs=0; M.onUpdate()
            assert(held(p)=='5' and p.innate[6]==0 and onFloor(6)==1, held(p))
        ''')

    def test_losing_the_crab_gives_everything_back(self):
        self.run_lua(r'''
            local p=newPlayer(2); players={p}; M.onGameStarted()
            drop(p,5); drop(p,6)
            p.copies=0; M.onUpdate()
            assert(held(p)=='' and p.innate[5]==0 and p.innate[6]==0 and onFloor(5)==1 and onFloor(6)==1)
        ''')

    def test_a_trinket_that_cannot_be_let_go_keeps_its_effect_and_is_reported_once(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            drop(p,5)
            p.refuse=true; p.copies=0; M.onUpdate(); M.onUpdate()
            assert(p.innate[5]==1 and onFloor(5)==0 and #errors==1, #errors)
        ''')

    def test_kronos_keeps_what_was_held_then_smelts_the_next_in_hand(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            drop(p,5)
            -- Kronos absorbs the crab: the collectible goes, the absorbed count rises
            p.copies=0; p.absorbed=1; M.onUpdate()
            local data=p.save.hermitCrab
            assert(p.smelted[5]==1 and (p.innate[5] or 0)==0 and held(p)=='' and data.kept==1 and onFloor(5)==0, 'kept: smelted for good')
            -- room used up: a trinket in hand stays there
            p.slots={7,0}; M.onUpdate()
            assert(p.slots[1]==7 and (p.smelted[7] or 0)==0)
            -- a second absorbed crab: the trinket in hand is smelted at once
            p.absorbed=2; M.onUpdate()
            assert(p.slots[1]==0 and p.smelted[7]==1 and data.kept==2 and T.evidence().smeltedAtOnce==1)
        ''')

    def test_each_crab_draws_its_own_share_in_seed_order(self):
        self.run_lua(r'''
            local p=newPlayer(2); p.bffs=1; players={p}; M.onGameStarted()
            local late=newCrab(p,20); local early=newCrab(p,10)
            drop(p,5); drop(p,6); drop(p,7)
            local layout=T.layout()
            assert(table.concat(layout[early.hash],',')=='5,6' and table.concat(layout[late.hash],',')=='7')
        ''')

    def test_it_wanders_the_room_on_its_own_and_never_follows(self):
        self.run_lua(r"""
            local a=newPlayer(1); local b=newPlayer(1); players={a,b}; M.onGameStarted()
            -- two crabs with the same seed and start, owners far apart
            local ca=newCrab(a,10); local cb=newCrab(b,10)
            ca.Position=Vector(300,200); cb.Position=Vector(300,200)
            a.Position=Vector(40,40); b.Position=Vector(560,360)
            M.onFamiliarInit(nil,ca); M.onFamiliarInit(nil,cb)
            local far,rested,walked,outside=0,0,0,false
            for i=1,1500 do
                if i%200==0 then a.Position=Vector(40+i%400,40) end -- the owner moves; the crab does not care
                step()
                assert(ca.Position.X==cb.Position.X and ca.Position.Y==cb.Position.Y, 'owner position changed the stroll')
                local d=(ca.Position-Vector(300,200)):Length(); if d>far then far=d end
                if ca.Velocity:Length()==0 then rested=rested+1 else walked=walked+1 end
                if ca.Position.X<0 or ca.Position.X>600 or ca.Position.Y<0 or ca.Position.Y>400 then outside=true end
            end
            assert(not ca.follower and not ca.followed, 'never a follower')
            assert(far>150 and not outside, 'wandered '..far)
            assert(rested>100 and walked>300, 'strolls and rests: '..rested..'/'..walked)
            assert(ca.Velocity:Length()<=M.data.wanderSpeed+1e-9, 'an amble, not a dash')
        """)

    def test_it_walks_to_the_owners_drop_and_takes_it_on_arrival(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(560,360)
            p.Position=Vector(300,100) -- dropped it and walked off
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate(); step()
            assert(pk.exists and held(p)=='' and T.walkState(crab).claim, 'claimed, not taken from afar')
            local n=stepsUntil(pk,600)
            assert(not pk.exists and held(p)=='5' and p.innate[5]==1, 'taken after '..n)
            local e=T.evidence()
            assert(e.fetchFrom>500 and e.fetchAt<=M.data.reach, 'walked from '..e.fetchFrom..' to '..e.fetchAt)
            assert(n+1>=(e.fetchFrom-M.data.reach)/M.data.fetchSpeed, 'it walked the way: '..n)
            assert((crab.Position-Vector(100,100)):Length()<=M.data.reach and crab.Velocity:Length()==0)
            assert(#T.claims()==0 and not T.walkState(crab).claim)
        """)

    def test_a_trinket_picked_back_up_first_is_left_alone(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(560,360)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate()
            for _=1,10 do step() end
            pk:Remove() -- the owner picked it back up
            for _=1,10 do step() end
            assert(held(p)=='' and (p.innate[5] or 0)==0 and T.evidence().taken==0)
            assert(#T.claims()==0 and not T.walkState(crab).claim, 'back to strolling')
        """)

    def test_the_nearest_free_crab_fetches(self):
        self.run_lua(r"""
            local p=newPlayer(2); players={p}; M.onGameStarted()
            local far=newCrab(p,10); local near=newCrab(p,20)
            M.onFamiliarInit(nil,far); M.onFamiliarInit(nil,near)
            far.Position=Vector(560,360); near.Position=Vector(120,120)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate()
            assert(T.walkState(near).claim and not T.walkState(far).claim)
            -- a second drop while the near crab is busy goes to the other one
            local pk2=newPickup(6,p); pk2.Position=Vector(110,100)
            M.onPickupInit(nil,pk2); M.onUpdate()
            assert(T.walkState(far).claim, 'the free crab takes the second')
            stepsUntil(pk,600); stepsUntil(pk2,600)
            assert(held(p)=='5,6', held(p))
        """)

    def test_a_wall_corner_in_the_way_is_walked_around(self):
        self.run_lua(r"""
            -- a solid bar between the crab and the trinket, open at the bottom
            wall=function(pos) return pos.X>=280 and pos.X<=320 and pos.Y<=260 end
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(500,100)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate()
            local n=stepsUntil(pk,3000)
            assert(not pk.exists and held(p)=='5' and n<360, 'went around the bar in '..n)
            assert(T.evidence().fetchAt<=M.data.reach)
        """)

    def test_a_new_room_forgets_the_fetch(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(560,360)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate(); step()
            M.onNewRoom(); step()
            assert(#T.claims()==0 and not T.walkState(crab).claim and pk.exists and T.evidence().taken==0)
        """)

    def test_it_leaves_the_trinket_while_the_owner_stands_within_two_tiles(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(500,300)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            p.Position=Vector(100+M.data.ownerNear,100) -- exactly two tiles away
            M.onPickupInit(nil,pk); M.onUpdate()
            for _=1,300 do step() end
            assert(pk.exists and held(p)=='' and not T.walkState(crab).claim, 'nobody sets out')
            assert(T.evidence().waitedNear>0)
            p.Position=Vector(100+M.data.ownerNear+1,100) -- one step further
            local n=stepsUntil(pk,600)
            assert(not pk.exists and held(p)=='5', 'fetched once the owner left: '..n)
        """)

    def test_a_crab_on_its_way_stops_when_the_owner_comes_back(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(500,300)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate()
            for _=1,20 do step() end
            assert(T.walkState(crab).claim and crab.Velocity:Length()>1, 'on its way')
            p.Position=Vector(120,110)
            for _=1,40 do step() end
            local at=Vector(crab.Position.X,crab.Position.Y)
            for _=1,200 do step() end
            assert(pk.exists and held(p)=='' and crab.Velocity:Length()==0, 'waits')
            assert(crab.Position.X==at.X and crab.Position.Y==at.Y, 'stands where it stopped')
            p.Position=Vector(500,350)
            stepsUntil(pk,600)
            assert(not pk.exists and held(p)=='5')
        """)

    def test_it_waits_out_a_magic_conch_upgrade_and_carries_the_result(self):
        self.run_lua(r"""
            local animating=true
            ConchBlessing.upgrade={isAnimatingPickup=function(pk) return animating end}
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(500,300)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate()
            for _=1,300 do step() end
            assert(pk.exists and held(p)=='' and T.evidence().waitedUpgrade>0, 'left alone while upgrading')
            -- the upgrade morphs it (expiring the old reference), which may run
            -- its init again: still one claim, and it follows the morphed pickup
            M.onPrePickupMorph(nil,pk)
            pk.generation=1; pk.SubType=77
            M.onPickupInit(nil,pk)
            M.onPostPickupMorph(nil,pk); M.onUpdate()
            assert(#T.claims()==1 and T.claims()[1].ref.Ref==pk, 'one claim, following the morphed trinket')
            animating=false
            stepsUntil(pk,600)
            assert(not pk.exists and held(p)=='77' and p.innate[77]==1, 'carries the upgraded one: '..held(p))
        """)

    def test_a_claim_on_a_trinket_morphed_into_something_else_ends(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(500,300)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate()
            M.onPrePickupMorph(nil,pk); pk.generation=1; pk.Variant=100; pk.SubType=1; M.onPostPickupMorph(nil,pk)
            for _=1,10 do step() end
            assert(#T.claims()==0 and not T.walkState(crab).claim and held(p)=='')
        """)

    def test_without_the_morph_callbacks_an_expired_claim_is_dropped(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(500,300)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            M.onPickupInit(nil,pk); M.onUpdate()
            pk.generation=1 -- expired, never proven: not recovered by searching
            for _=1,300 do step() end
            assert(pk.exists and held(p)=='' and #T.claims()==0)
        """)

    def test_a_luamod_reload_mid_run_starts_it_once_savemanager_reloads(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab); crab.Position=Vector(500,300)
            local pk=newPickup(5,p); pk.Position=Vector(100,100)
            saveCallbacks.POST_DATA_LOAD(ConchBlessing.originalMod,{},false) -- an ordinary load
            M.onPickupInit(nil,pk); M.onUpdate(); for _=1,100 do step() end
            assert(not T.started() and pk.exists and held(p)=='', 'idle before the run is known')
            pk:Remove()
            saveCallbacks.POST_DATA_LOAD(ConchBlessing.originalMod,{},true) -- luamod during a run
            assert(T.started())
            local pk2=newPickup(6,p); pk2.Position=Vector(100,100)
            M.onPickupInit(nil,pk2); M.onUpdate(); stepsUntil(pk2,600)
            assert(not pk2.exists and held(p)=='6', 'fetches after the reload: '..held(p))
        """)

    def test_a_trinket_taken_from_the_group_leaves_the_claws(self):
        self.run_lua(r"""
            local p=newPlayer(1); p.bffs=1; players={p}; M.onGameStarted()
            local crab=crabOf(p)
            drop(p,5); drop(p,6)
            assert(held(p)=='5,6')
            p.innate[5]=0 -- something (another mod) took it away
            M.onUpdate()
            assert(held(p)=='6' and onFloor(5)==0 and T.evidence().vanished==1 and T.evidence().released==0)
            assert(table.concat(T.layout()[crab.hash],',')=='6', 'no longer drawn')
            p.innate[6]=3 -- and stray extra copies in the crabs' group go
            M.onUpdate()
            assert(held(p)=='6' and p.innate[6]==1)
        """)

    def test_the_owners_own_smelted_copy_is_never_touched(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            p.smelted[5]=1 -- smelted by the owner before (a Gulp! pill, say)
            drop(p,5)
            assert(held(p)=='5' and p.innate[5]==1 and p.smelted[5]==1)
            p.copies=0; M.onUpdate()
            assert(held(p)=='' and p.innate[5]==0 and p.smelted[5]==1 and onFloor(5)==1)
        """)

    def test_golden_and_normal_copies_are_held_apart(self):
        self.run_lua(r"""
            local p=newPlayer(1); p.bffs=1; players={p}; M.onGameStarted()
            drop(p,5|GOLD); drop(p,5)
            assert(p.innate[5|GOLD]==1 and p.innate[5]==1)
            p.innate[5|GOLD]=0; M.onUpdate()
            assert(held(p)=='5', held(p))
        """)

    def test_a_continue_restores_the_group_from_the_ledger(self):
        self.run_lua(r"""
            local p=newPlayer(1); p.bffs=1; players={p}
            -- the run save kept the ledger, but the group came back empty
            p.save.hermitCrab={held={5,6},kept=0,innate=true}
            M.onGameStarted(); M.onUpdate()
            assert(held(p)=='5,6' and p.innate[5]==1 and p.innate[6]==1 and T.evidence().vanished==0)
            -- the group already right: nothing added twice
            M.onGameStarted(); M.onUpdate()
            assert(p.innate[5]==1 and p.innate[6]==1)
        """)

    def test_an_older_smelt_ledger_moves_over_to_innate_once(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}
            p.save.hermitCrab={held={5},kept=0}
            p.smelted[5]=1
            M.onGameStarted(); M.onUpdate()
            assert(p.smelted[5]==0 and p.innate[5]==1 and held(p)=='5' and p.save.hermitCrab.innate==true)
            M.onGameStarted(); M.onUpdate()
            assert(p.smelted[5]==0 and p.innate[5]==1, 'moved once')
        """)

    def test_a_new_ledger_is_innate_from_the_start(self):
        self.run_lua(r"""
            local p=newPlayer(1); players={p}; M.onGameStarted()
            p.smelted[5]=1 -- the owner's own
            drop(p,5)
            assert(p.save.hermitCrab.innate==true)
            M.onGameStarted(); M.onUpdate() -- a Continue later never treats it as old
            assert(p.smelted[5]==1 and p.innate[5]==1)
        """)

    def test_registry_row_and_generated_entity(self):
        items = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8')
        start = items.index('HERMIT_CRAB = {')
        row = items[start:items.index('\n    },', start)]
        for needle in ('type = "familiar"', 'COLLECTIBLE_MOMS_PURSE', 'flag = "positive"', 'kronosAbsorb = true',
                       'stackable = true', 'variant = 779'):
            self.assertIn(needle, row)
        entities = (ROOT / 'content/entities2.xml').read_text(encoding='utf-8')
        self.assertIn('name="Hermit Crab" id="3" variant="779" anm2path="hermit_crab.anm2"', entities)
        kronos = (ROOT / 'scripts/items/collectibles/kronos.lua').read_text(encoding='utf-8')
        self.assertIn('row.kronosAbsorb == true', kronos)

    def test_front_walk_stops_and_uses_the_original_trinket_at_1_5_times_preview_scale(self):
        self.run_lua(r'''
            local p=newPlayer(1); players={p}; M.onGameStarted()
            local crab=newCrab(p,10); M.onFamiliarInit(nil,crab)
            assert(not crab.follower and crab.GridCollisionClass==3 and crab.sprite.animation=='NormalEmptyIdle')
            drop(p,123); crab.Velocity=Vector(1,0); M.onFamiliarUpdate(nil,crab)
            assert(crab.sprite.animation=='NormalOneWalk' and crab.sprite.FlipX==false)
            crab.sprite.frame=6; M.onFamiliarRender(nil,crab,Vector.Zero)
            assert(#rendered==2 and rendered[1].sheet=='gfx/items/trinkets/fixture_123.png')
            assert(rendered[1].sx==0.375*1.5 and rendered[1].sy==0.375*1.5)
            assert(rendered[2].animation=='GripNormalOneWalk' and rendered[2].frame==6)
            local liftedY=rendered[1].y
            crab.sprite.frame=0; rendered={}; M.onFamiliarRender(nil,crab,Vector.Zero)
            assert(rendered[1].y==liftedY+1 and sampleCount==0, 'same bob; bounds come from the data, never sampled')
            crab.Velocity=Vector.Zero; M.onFamiliarUpdate(nil,crab)
            assert(crab.sprite.animation=='NormalOneIdle', 'stationary crab must stop walking')
        ''')

    def test_bffs_selects_empty_one_raised_and_two_raised_without_double_growth(self):
        self.run_lua(r'''
            local p=newPlayer(1); p.bffs=1; players={p}; M.onGameStarted()
            local crab=newCrab(p,10); crab.SpriteScale=Vector(1.25,1.25)
            M.onFamiliarInit(nil,crab)
            assert(crab.sprite.animation=='BffsEmptyIdle' and crab.SpriteScale.X==1)
            crab.SpriteScale=Vector(1.25,1.25); M.onPreFamiliarRender(nil,crab)
            assert(crab.SpriteScale.X==1 and crab.SpriteScale.Y==1, 'the engine growth is undone before the draw')
            drop(p,12); M.onFamiliarUpdate(nil,crab); M.onFamiliarRender(nil,crab,Vector.Zero)
            assert(crab.sprite.animation=='BffsOneIdle' and #rendered==2)
            assert(rendered[1].sx==0.5*1.5 and rendered[2].animation=='GripBffsOneIdle')
            drop(p,13); M.onFamiliarUpdate(nil,crab); rendered={}; M.onFamiliarRender(nil,crab,Vector.Zero)
            assert(crab.sprite.animation=='BffsTwoIdle' and #rendered==3)
            assert(rendered[1].x<rendered[2].x and rendered[1].y==rendered[2].y)
            assert(rendered[1].sx==0.75 and rendered[2].sx==0.75 and T.drawnScale(crab)==1)
            p.bffs=0; M.onUpdate(); M.onFamiliarUpdate(nil,crab)
            assert(crab.sprite.animation=='NormalOneIdle' and held(p)=='12')
        ''')

    def test_render_uses_the_held_snapshot_that_matches_its_body_and_bounds_fallback(self):
        self.run_lua(r'''
            sampleTextures=false
            local p=newPlayer(1); p.bffs=1; players={p}; M.onGameStarted()
            local crab=newCrab(p,10); drop(p,12); M.onFamiliarUpdate(nil,crab)
            drop(p,13) -- relayout after the body update: wait until next update to show it
            M.onFamiliarRender(nil,crab,Vector.Zero)
            assert(#rendered==2 and rendered[2].animation=='GripBffsOneIdle')
            assert(rendered[1].sx==0.75 and sampleCount==0, 'bounds come from the data')
            M.onFamiliarUpdate(nil,crab); rendered={}; M.onFamiliarRender(nil,crab,Vector.Zero)
            assert(#rendered==3 and rendered[3].animation=='GripBffsTwoIdle')
            p.bffs=0; M.onUpdate(); M.onFamiliarUpdate(nil,crab); rendered={}
            M.onFamiliarRender(nil,crab,Vector.Zero)
            assert(rendered[1].sx==0.5625 and rendered[1].y>=-10,
                'even a full-height original stays below the normal eyes without shrinking')
        ''')

    def test_trinkets_sit_by_their_measured_bounds_top_just_under_the_eyes(self):
        self.run_lua(r"""
            local V=dofile(root..'/scripts/items/familiars/hermit_crab_visuals.lua')
            local perfection=V.trinketBounds['trinket_145_perfection.png']
            assert(perfection and perfection[2]>0 and perfection[3]<32, 'measured, not the full frame')
            assert(V.defaultBounds[2]>0 and V.defaultBounds[3]<32)
            local function topOf(id)
                local p=newPlayer(1); players={p}; M.onGameStarted()
                local crab=newCrab(p,10+id); M.onFamiliarInit(nil,crab); crab.Position=Vector(0,0)
                drop(p,id); M.onFamiliarUpdate(nil,crab); rendered={}
                M.onFamiliarRender(nil,crab,Vector.Zero)
                return rendered[1].y-crab.Position.Y, crab -- relative to the crab's feet
            end
            -- the icon's opaque top lands on the slot's minTop (just under the eyes)
            local y=topOf(145)
            local slot=V.poses.NormalOne.frames[1][1]
            local top=y+perfection[2]*slot.scale
            assert(math.abs(top-slot.minTop)<1e-6, 'Perfection top '..top..' want '..slot.minTop)
            -- an unknown (another mod's) icon uses the typical vanilla box
            local y2=topOf(9001)
            assert(math.abs(y2+V.defaultBounds[2]*slot.scale-slot.minTop)<1e-6)
        """)

    def test_shipped_native_art_and_animation_slots_are_current(self):
        spec = importlib.util.spec_from_file_location('crab_assets', ROOT / 'generate_hermit_crab_assets.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        for path, data in module.build_outputs().items():
            self.assertEqual(path.read_bytes(), data, str(path))
        actor = ET.parse(ROOT / 'resources/gfx/hermit_crab.anm2')
        animations = {a.attrib['Name']: a for a in actor.findall('./Animations/Animation')}
        self.assertEqual(len(animations), 21)
        for _, pose in module.POSES:
            for prefix in ('', 'Grip'):
                frames = animations[prefix + pose + 'Walk'].findall('./LayerAnimations/LayerAnimation/Frame')
                self.assertEqual(len(frames), 8)
                self.assertEqual(sum(int(f.attrib['Delay']) for f in frames), 24)
                self.assertEqual(animations[prefix + pose + 'Idle'].attrib['FrameNum'], '1')


if __name__ == '__main__':
    unittest.main()
