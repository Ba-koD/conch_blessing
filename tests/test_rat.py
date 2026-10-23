"""자 (Rat): production Lua with engine and REPENTOGON doubles.

One fake per copy: the holder's character, controller, passives and health (as
they were at that moment), Parent set to the holder; a fall empties that place
until the next floor; item loss and a lost holder remove fakes without a fall.
These doubles cannot show what the engine really does with a Parent helper
(revives, pickups, Continue, HUD); `conch_test rat` covers those in game.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from lupa.lua53 import LuaRuntime
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
package=nil
ModCallbacks={MC_TRIGGER_PLAYER_DEATH_POST_CHECK_REVIVES=1051}
CallbackPriority={LATE=100}
ActiveSlot={SLOT_PRIMARY=0,SLOT_SECONDARY=1,SLOT_POCKET=2}
ItemType={ITEM_PASSIVE=1,ITEM_ACTIVE=3,ITEM_FAMILIAR=4}
EntityType={ENTITY_PLAYER=1,ENTITY_EFFECT=1000}
EffectVariant={POOF01=15}
HealthType={DEFAULT=0,RED=0,SOUL=1,LOST=2,NO_HEALTH=2,COIN=3,KEEPER=3,BONE=4}
RAT,ONION,BOBBY,D6,LUCKY,UP=900,1,8,105,46,11
local V={}; V.__index=V
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},V) end})
V.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
V.__mul=function(a,k) return Vector(a.X*k,a.Y*k) end
function Color(r,g,b,a) return {r,g,b,a} end
draws={}; spriteFails=false
function Sprite()
    local s={FlipX=false}
    function s:Load(path) self.path=path; if spriteFails then error('missing '..path) end end
    function s:IsLoaded() return true end
    function s:SetFrame(anim,frame) self.anim,self.frame=anim,frame end
    function s:Render(pos) draws[#draws+1]={x=pos.X,y=pos.Y,flip=self.FlipX,frame=self.frame,alpha=self.Color[4],path=self.path} end
    return s
end
function V:Distance(o) return math.sqrt((self.X-o.X)^2+(self.Y-o.Y)^2) end
Vector.Zero=Vector(0,0)
function GetPtrHash(e) return e.hash end
function EntityPtr(e) return {Ref=e} end
errors={}; debug={}; callbacks={}; puffs=0; huds=0; removed={}
shared={coins=3,bombs=1,keys=0}
list={}
inGame=false
local actives={[D6]=true}
Isaac={GetItemIdByName=function(name) return name=='Rat' and RAT or -1 end,
    IsInGame=function() return inGame end,
    GetItemConfig=function() return {GetCollectible=function(_,id)
        return {Type=actives[id] and ItemType.ITEM_ACTIVE or ItemType.ITEM_PASSIVE} end} end,
    GetFreeNearPosition=function(pos) return Vector(pos.X+20,pos.Y) end,
    WorldToScreen=function(pos) return Vector(pos.X,pos.Y) end}
local game={}
function game:GetNumPlayers() return #list end
function game:GetPlayer(i) return list[i+1] end
function game:GetHUD() return {AssignPlayerHUDs=function() huds=huds+1 end} end
function game:Spawn() puffs=puffs+1 end
local room={}
function room:GetClampedPosition(pos) return Vector(math.min(math.max(pos.X,40),600),math.min(math.max(pos.Y,40),400)) end
function game:GetRoom() return room end
function Game() return game end
-- SaveManager: players keyed by seed; floor saves reset per floor.
runSaves={}; floorSaves={}
local function index(p) return 'PLAYER_'..tostring(p.seed) end
ConchBlessing={printError=function(m) errors[#errors+1]=m end,
    printDebug=function(m) debug[#debug+1]=m end,
    SaveManager={IsLoaded=function() return true end,
        Utility={GetSaveIndex=function(p) return index(p) end},
        GetRunSave=function(p) runSaves[index(p)]=runSaves[index(p)] or {}; return runSaves[index(p)] end,
        TryGetRunSave=function(p) return runSaves[index(p)] end,
        GetFloorSave=function(p) floorSaves[index(p)]=floorSaves[index(p)] or {}; return floorSaves[index(p)] end,
        TryGetFloorSave=function(p) return floorSaves[index(p)] end}}
ConchBlessing.originalMod=ConchBlessing
function ConchBlessing:AddPriorityCallback(id,priority,fn) callbacks[#callbacks+1]={id=id,priority=priority,fn=fn} end

local P={}; P.__index=P
nextHash=1
function makePlayer(kind,options)
    options=options or {}
    local p=setmetatable({Type=EntityType.ENTITY_PLAYER,hash=nextHash,seed=options.seed or nextHash*1000,kind=kind or 0,
        ControllerIndex=options.controller or 0,Position=Vector(100,100),Velocity=Vector(1,1),InitSeed=7,
        inventory={},slots={},trinkets={0,0},cards={},pills={},max=0,red=0,soul=0,bone=0,golden=0,eternal=0,broken=0,
        alive=true,dead=false,ghost=false,health=options.health},P)
    nextHash=nextHash+1
    return p
end
function P:Exists() return self.alive end
function P:IsDead() return self.dead end
function P:IsCoopGhost() return self.ghost end
function P:ToPlayer() return self end
function P:GetPlayerType() return self.kind end
function P:GetCollectibleNum(id) return self.inventory[id] or 0 end
function P:GetCollectiblesList() local t={}; for id,n in pairs(self.inventory) do t[id]=n end; return t end
function P:AddCollectible(id,charge,first,slot)
    self.inventory[id]=(self.inventory[id] or 0)+1
    if actives[id] then self.slots[slot or 0]=id end
    self.firstTimes=(self.firstTimes or 0)+(first==false and 0 or 1)
end
function P:RemoveCollectible(id,ignore,slot)
    if (self.inventory[id] or 0)>0 then self.inventory[id]=self.inventory[id]-1 end
    if self.inventory[id]==0 then self.inventory[id]=nil end
    for s,v in pairs(self.slots) do if v==id then self.slots[s]=nil end end
end
function P:GetActiveItem(slot) return self.slots[slot] or 0 end
function P:GetTrinket(slot) return self.trinkets[slot+1] or 0 end
function P:TryRemoveTrinket(id) for i,v in ipairs(self.trinkets) do if v==id then self.trinkets[i]=0; return true end end end
function P:SetCard(slot,v) self.cards[slot]=v end
function P:SetPill(slot,v) self.pills[slot]=v end
function P:GetMaxHearts() return self.max end
function P:GetHearts() return self.red end
function P:GetSoulHearts() return self.soul end
function P:GetBoneHearts() return self.bone end
function P:GetGoldenHearts() return self.golden end
function P:GetEternalHearts() return self.eternal end
function P:GetBrokenHearts() return self.broken end
function P:AddMaxHearts(n) self.max=math.max(0,self.max+n); self.red=math.min(self.red,self.max) end
function P:AddHearts(n) self.red=math.max(0,math.min(self.max+self.bone*2,self.red+n)) end
function P:AddSoulHearts(n) self.soul=math.max(0,self.soul+n) end
function P:AddBoneHearts(n) self.bone=math.max(0,self.bone+n) end
function P:AddGoldenHearts(n) self.golden=math.max(0,self.golden+n) end
function P:AddEternalHearts(n) self.eternal=math.max(0,self.eternal+n) end
function P:AddBrokenHearts(n) self.broken=math.max(0,self.broken+n) end
-- Black hearts: a bit per full soul heart; rotten hearts count among the red.
function P:GetBlackHearts() return self.black or 0 end
function P:AddBlackHearts(n)
    for _=1,n do self.black=(self.black or 0)|(1<<(self.soul//2)); self.soul=self.soul+1 end
end
function P:GetRottenHearts() return self.rotten or 0 end
function P:AddRottenHearts(n) self.rotten=math.max(0,(self.rotten or 0)+n); self.red=self.red+n end
function P:GetSubPlayer() return self.sub end
function P:GetEffects()
    local p=self
    p.fx=p.fx or {}
    return {GetCollectibleEffectNum=function(_,id) return p.fx[id] or 0 end,
        RemoveCollectibleEffect=function(_,id,n) p.fx[id]=math.max(0,(p.fx[id] or 0)-(n or 1)) end}
end
local plainAddHearts=P.AddHearts
-- Tainted Magdalene-like healing: what is given counts double.
function P:AddHearts(n) if self.double and n>0 then n=n*2 end plainAddHearts(self,n) end
function P:GetHealthType() return self.health or HealthType.RED end
function P:SetControllerIndex(i) self.ControllerIndex=i end
function P:GetOtherTwin() return self.twin end
CacheFlag={CACHE_ALL=0xFFFF}
for _,stat in ipairs({'Damage','FireDelay','Luck','Range','ShotSpeed','Speed'}) do
    P['GetEden'..stat]=function(self) return (self.eden or {})[stat] or 0 end
    P['SetEden'..stat]=function(self,v) self.eden=self.eden or {}; self.eden[stat]=v end
end
function P:AddCacheFlags(f) self.cacheFlags=f end
function P:EvaluateItems() self.evaluations=(self.evaluations or 0)+1 end
function P:IsPostLevelInitFinished() return self.postInit ~= false end
function P:InitPostLevelInitStats() self.postInit=true; self.postInitBeforeStrip=(self.inventory[D6] or 0)>0 end
function P:AnimateAppear() self.appeared=true end
function P:GetNumCoins() return shared.coins end
function P:GetNumBombs() return shared.bombs end
function P:GetNumKeys() return shared.keys end
function P:AddCoins(n) shared.coins=shared.coins+n end
function P:AddBombs(n) shared.bombs=shared.bombs+n end
function P:AddKeys(n) shared.keys=shared.keys+n end

-- A joining character arrives with its own loadout and pickups, controller 0.
spawnSeed=nil
PlayerManager={}
function PlayerManager.SpawnCoPlayer2(kind)
    local p=makePlayer(kind,{seed=spawnSeed})
    p.inventory={[D6]=1,[LUCKY]=1}; p.slots={[0]=D6,[2]=D6}; p.trinkets={19,0}; p.cards={[0]=1}; p.pills={[0]=2}
    p.max=6; p.red=6; p.soul=2; p.golden=1
    shared.coins=shared.coins+5; shared.bombs=shared.bombs+1
    list[#list+1]=p
    return p
end
function PlayerManager.RemoveCoPlayer(p)
    removed[#removed+1]=p
    p.alive=false
    for i,q in ipairs(list) do if q==p then table.remove(list,i); break end end
    M.onEntityRemove(nil,p)
    runSaves[index(p)]=nil
end
function engineRemove(p)
    p.alive=false
    for i,q in ipairs(list) do if q==p then table.remove(list,i); break end end
    M.onEntityRemove(nil,p)
    runSaves[index(p)]=nil
end
function newFloor() floorSaves={}; M.onNewLevel(); M.onNewRoom() end
function step(n) for _=1,(n or 1) do M.onUpdate() end end
function fakes() return M.fakesOf(holder) end
function fallen() return M.fallen(holder) end

holder=makePlayer(3,{controller=2})
holder.inventory={[RAT]=1,[ONION]=1,[BOBBY]=1,[D6]=1}; holder.slots={[0]=D6}
holder.max=6; holder.red=6
list={holder}
"""


class RatTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(HARNESS)
        self.lua.globals().source = (ROOT / 'scripts/items/collectibles/rat.lua').read_text(encoding='utf-8')

    def load(self, started=True):
        self.lua.execute('M=load(source,"rat")()')
        if started:
            self.lua.execute('M.onGameStarted(nil,false)')

    def run_lua(self, code):
        self.lua.execute(code)

    def test_pure_rules(self):
        self.load(False)
        self.run_lua("""
            local T=M._test
            assert(T.wantedFakes(2,0)==2 and T.wantedFakes(2,1)==1 and T.wantedFakes(1,3)==0 and T.wantedFakes(0,0)==0)
            assert(T.settleFallen(1,2,1)==0,'a lost copy takes the fallen place first')
            assert(T.settleFallen(1,1,1)==1 and T.settleFallen(2,2,2)==2)
            assert(T.settleFallen(2,3,1)==0 and T.settleFallen(1,nil,1)==1)
            assert(T.settleFallen(3,nil,1)==1,'never more falls than places')
            local ids=T.passivesToCopy({[8]=2,[1]=1,[105]=1,[900]=3,[0]=4,[5]=0},
                function(id) return id==105 end,900)
            assert(table.concat(ids,',')=='1,8,8','sorted, repeated, no active, no Rat: '..table.concat(ids,','))
        """)

    def test_a_copy_makes_one_fake_of_the_holder(self):
        self.load()
        self.run_lua("""
            step()
            local f=fakes()
            assert(#f==1 and #list==2,'one fake')
            local fake=f[1]
            assert(fake:GetPlayerType()==3 and fake.ControllerIndex==2,'character and controller')
            assert(fake.Parent==holder,'Parent is the holder')
            assert(fake.inventory[ONION]==1 and fake.inventory[BOBBY]==1,'passives copied')
            assert(fake.inventory[RAT]==nil and fake.inventory[D6]==nil and fake.inventory[LUCKY]==nil,
                'no Rat, no actives, no starting items')
            assert(fake.firstTimes==0,'copies are not first pickups')
            assert(fake:GetActiveItem(0)==0 and fake:GetActiveItem(2)==0 and fake:GetTrinket(0)==0)
            assert(fake.cards[0]==0 and fake.pills[0]==0,'pockets emptied')
            assert(fake.max==6 and fake.red==6 and fake.soul==0 and fake.golden==0,"the holder's health, not its own")
            assert(shared.coins==3 and shared.bombs==1 and shared.keys==0,'no pickups brought along')
            assert(runSaves['PLAYER_'..fake.seed].ratFake.owner=='PLAYER_'..holder.seed,'mark in the fake save')
            assert(runSaves['PLAYER_'..holder.seed]==nil or runSaves['PLAYER_'..holder.seed].ratFake==nil)
            assert(fake.appeared and puffs==1 and huds>=1)
            assert(M.isFake(fake) and not M.isFake(holder))
            step(3); assert(#fakes()==1 and #list==2,'no second fake from repeated updates')
        """)

    def test_snapshot_is_taken_once(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            holder.inventory[UP]=1; holder.inventory[ONION]=nil
            step(3)
            assert(fake.inventory[UP]==nil and fake.inventory[ONION]==1,'later changes do not reach the fake')
        """)

    def test_copies_add_and_remove_fakes_without_falls(self):
        self.load()
        self.run_lua("""
            step(); local first=fakes()[1]
            holder.inventory[RAT]=2; step()
            local f=fakes(); assert(#f==2 and f[1]==first,'second copy, second fake')
            local second=f[2]
            holder.inventory[RAT]=1; step()
            f=fakes(); assert(#f==1 and f[1]==first and removed[1]==second,'the newest fake goes first')
            assert(fallen()==0,'item loss is not a fall')
            holder.inventory[RAT]=nil; step()
            assert(#fakes()==0 and #list==1 and fallen()==0)
            holder.inventory[RAT]=1; step()
            assert(#fakes()==1,'reacquired on the same floor')
        """)

    def test_a_fall_empties_the_place_until_the_next_floor(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            fake.dead=true
            callbacks[1].fn(nil,fake)
            assert(callbacks[1].id==1051 and callbacks[1].priority==100,'post-revive death hook, LATE')
            assert(#removed==0,'never removed inside the death callback')
            step()
            assert(removed[1]==fake and #list==1 and fallen()==1,'fell on the next update')
            assert(runSaves['PLAYER_'..fake.seed]==nil,'its save went with it')
            step(5); M.onNewRoom(); step(2)
            assert(#fakes()==0,'no new fake on the same floor')
            newFloor(); step()
            assert(#fakes()==1 and fallen()==0,'transforms again on the next floor')
        """)

    def test_a_revived_fake_is_kept(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            fake.dead=true; callbacks[1].fn(nil,fake)
            fake.dead=false
            step()
            assert(#removed==0 and #fakes()==1 and fallen()==0)
        """)

    def test_a_ghost_fake_falls(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            fake.ghost=true; step(); step()
            assert(removed[1]==fake and fallen()==1)
        """)

    def test_the_holders_real_death_takes_the_fakes(self):
        self.load()
        self.run_lua("""
            holder.inventory[RAT]=2; step()
            assert(#fakes()==2)
            holder.dead=true; callbacks[1].fn(nil,holder)
            step()
            assert(#removed==2 and #list==1 and fallen()==2)
        """)

    def test_a_revived_holder_keeps_the_fakes(self):
        self.load()
        self.run_lua("""
            step()
            holder.dead=true; callbacks[1].fn(nil,holder)
            holder.dead=false; step()
            assert(#removed==0 and #fakes()==1)
            holder.ghost=true; step(); step()
            assert(#removed==1,'a holder turned co-op ghost has really died')
        """)

    def test_losing_a_copy_after_a_fall_keeps_the_live_fake(self):
        self.load()
        self.run_lua("""
            holder.inventory[RAT]=2; step()
            local f=fakes(); local keep=f[2]
            f[1].dead=true; callbacks[1].fn(nil,f[1]); step()
            assert(#fakes()==1 and fallen()==1)
            holder.inventory[RAT]=1; step()
            assert(#fakes()==1 and fakes()[1]==keep and fallen()==0)
            holder.inventory[RAT]=2; step()
            assert(#fakes()==2,'a newly gained copy transforms at once')
        """)

    def test_continue_finds_saved_fakes_and_makes_no_duplicates(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            M.onPreGameExit(nil,true)
            assert(not M._test.ready())
            step(); assert(#list==2,'nothing happens while exiting')
            M.onGameStarted(nil,true)
            assert(#fakes()==0,'runtime cleared until rebuilt')
            step()
            assert(#fakes()==1 and fakes()[1]==fake and #list==2,'the restored fake is recognised')
            M.onUnload(nil,ConchBlessing); step()
            assert(#fakes()==1 and #list==2,'a reload finds it again')
        """)

    def test_fakes_of_a_holder_who_left_are_removed_without_a_fall(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            engineRemove(holder)
            step()
            assert(removed[1]==fake and #list==0)
            assert((floorSaves['PLAYER_'..holder.seed].rat.fallen or 0)==0)
        """)

    def test_engine_removal_of_a_dead_fake_counts_as_a_fall(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            fake.dead=true; engineRemove(fake)
            assert(fallen()==1 and M._test.lastRemoval().by=='engine')
            step(); assert(#fakes()==0)
        """)

    def test_a_dead_fake_left_unsettled_at_a_floor_change_is_replaced(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            fake.dead=true
            step(); assert(#removed==0 and #fakes()==0 and #list==2,'still deciding: holds its place')
            newFloor(); step()
            assert(removed[1]==fake,'stale fake taken away'); step()
            assert(#fakes()==1 and fallen()==0,'the new floor makes a fresh one')
        """)

    def test_the_fake_takes_the_holders_health_exactly(self):
        self.load()
        self.run_lua("""
            -- Hurt, with soul, black, bone, golden, eternal, rotten and broken hearts.
            holder.max=8; holder.red=5; holder.soul=0; holder.bone=1; holder.golden=1; holder.eternal=1; holder.broken=1
            holder:AddSoulHearts(2); holder:AddBlackHearts(2); holder:AddRottenHearts(2)
            local want=string.format('%d %d %d %d %d %d %d %d %d',holder.max,holder.red,holder.soul,holder.black,
                holder.bone,holder.golden,holder.eternal,holder.rotten,holder.broken)
            step(); local fake=fakes()[1]
            local got=string.format('%d %d %d %d %d %d %d %d %d',fake.max,fake.red,fake.soul,fake.black or 0,
                fake.bone,fake.golden,fake.eternal,fake.rotten or 0,fake.broken)
            assert(got==want,'got '..got..' want '..want)
            assert(holder.max==8 and holder.red==7,"the holder's own health is untouched")
        """)

    def test_a_low_health_item_never_sees_an_empty_body(self):
        self.load()
        self.run_lua("""
            -- Like Eve's Whore of Babylon: held at one heart or less, it switches on.
            local WHORE=122
            local P=getmetatable(holder)
            local function watch(p)
                if (p.inventory[WHORE] or 0)>0 and p.red+p.soul<=2 then p.whoreOn=true end
            end
            for _,name in ipairs({'AddMaxHearts','AddHearts','AddSoulHearts','AddBoneHearts'}) do
                local base=P[name]
                P[name]=function(self,n) base(self,n); watch(self) end
            end
            local add=P.AddCollectible
            P.AddCollectible=function(self,id,...) add(self,id,...); watch(self) end
            holder.inventory[WHORE]=1
            local spawn=PlayerManager.SpawnCoPlayer2
            -- Born low with the item, its effect already on and outliving the item.
            PlayerManager.SpawnCoPlayer2=function(t)
                local p=spawn(t); p.inventory[WHORE]=1; p.fx={[WHORE]=1,[ONION]=1}; return p
            end
            step(); local fake=fakes()[1]
            assert(fake.inventory[WHORE]==1 and fake.max==6 and fake.red==6)
            assert(not fake.whoreOn,'the item saw the fake with no hearts')
            assert(fake.fx[WHORE]==0,"the starting item's leftover effect was cleared")
            assert(fake.fx[ONION]==1,'effects of items it never had stay alone')
        """)

    def test_an_innate_low_health_effect_sees_only_the_final_health(self):
        self.load()
        self.run_lua("""
            -- Like Eve: the character itself switches on at one heart or less, no item listed.
            local P=getmetatable(holder)
            local function watch(p) if p.kind==5 and p.red+p.soul<=2 then p.innateOn=true end end
            for _,name in ipairs({'AddMaxHearts','AddHearts','AddSoulHearts','AddBoneHearts','AddBlackHearts'}) do
                local base=P[name]
                P[name]=function(self,n) base(self,n); watch(self) end
            end
            holder.kind=5; holder.max=4; holder.red=4
            step(); local fake=fakes()[1]
            assert(fake.max==4 and fake.red==4)
            assert(not fake.innateOn,'the fake passed through low health')
            -- A holder really at one heart: the fake is there too, and so is the effect.
            M.removeAll('test'); holder.inventory[RAT]=nil; step()
            holder.red=2; holder.inventory[RAT]=1; step()
            local low=fakes()[1]
            assert(low.red==2 and low.innateOn,'a low holder gives a low fake')
        """)

    def test_soul_and_black_hearts_keep_the_holders_order(self):
        self.load()
        self.run_lua("""
            holder.max=0; holder.red=0; holder.soul=0
            holder:AddSoulHearts(2); holder:AddBlackHearts(2); holder:AddSoulHearts(1)
            local spawn=PlayerManager.SpawnCoPlayer2
            PlayerManager.SpawnCoPlayer2=function(t)
                local p=spawn(t); p.max=0; p.red=0; p.soul=0; p.black=0; p:AddSoulHearts(6); return p
            end
            step(); local fake=fakes()[1]
            assert(fake.soul==5 and fake.black==holder.black,'soul '..fake.soul..' black '..tostring(fake.black)..' want '..holder.black)
        """)

    def test_double_healing_and_the_soul_sub_player_settle_exactly(self):
        self.load()
        self.run_lua("""
            holder.max=8; holder.red=4
            holder.sub=makePlayer(17); holder.sub.soul=5
            local spawn=PlayerManager.SpawnCoPlayer2
            PlayerManager.SpawnCoPlayer2=function(t)
                local p=spawn(t); p.double=true; p.sub=makePlayer(17); p.sub.soul=6; return p
            end
            step(); local fake=fakes()[1]
            assert(fake.max==8 and fake.red==4,'doubled healing settled: red '..fake.red)
            assert(fake.sub.soul==5,"the Soul's hearts too: "..fake.sub.soul)
        """)

    def test_shared_save_identity_fails_closed(self):
        self.load()
        self.run_lua("""
            spawnSeed=holder.seed
            step()
            assert(#fakes()==0 and #list==1,'colliding fake removed')
            assert(errors[#errors]:find('transformation cancelled',1,true))
            assert(runSaves['PLAYER_'..holder.seed]==nil or runSaves['PLAYER_'..holder.seed].ratFake==nil,
                'no mark written into the holder save')
        """)

    def test_without_repentogon_nothing_happens_and_it_says_so_once(self):
        self.run_lua('PlayerManager=nil')
        self.load()
        self.run_lua("""
            step(); holder.inventory[RAT]=2; step(); M.onNewRoom(); step()
            assert(#list==1 and #errors==1 and errors[1]:find('requires REPENTOGON',1,true))
        """)

    def test_no_work_before_game_start(self):
        self.load(False)
        self.run_lua("""
            M.onNewLevel(); M.onNewRoom(); step(3)
            assert(#list==1 and puffs==0,'pre-start callbacks are no-ops')
            M.onGameStarted(nil,false); step()
            assert(#fakes()==1)
        """)

    def test_a_rat_runs_off_where_a_fake_went(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            fake.dead=true; callbacks[1].fn(nil,fake); step()
            local runners=M._test.runners()
            assert(#runners==1,'one rat for the fallen fake')
            local r=runners[1]
            assert(r.dir.X>0,'runs away from the holder (the fake stood to the right)')
            assert(math.abs(r.dir.Y)<=M.data.ratDrift,'mostly sideways')
            local x=r.pos.X; step(); assert(r.pos.X>x,'it moves each update')
            M.onRoomRender()
            assert(#draws==1 and draws[1].path=='gfx/effects/conch_rat_run.anm2' and draws[1].flip==false)
            assert(draws[1].alpha==1)
            for _=1,M.data.ratLife do step() end
            assert(#M._test.runners()==0,'gone after its run')
            draws={}; M.onRoomRender(); assert(#draws==0)
        """)

    def test_runner_frames_fade_and_direction(self):
        self.load(False)
        self.run_lua("""
            local T,d=M._test,M.data
            assert(T.runnerFrame(0)==0 and T.runnerFrame(d.ratFrames*d.ratFrameDelay)==0,'the run loops')
            assert(T.runnerFrame(5)==5)
            assert(T.runnerAlpha(0)==1 and T.runnerAlpha(d.ratLife-d.ratFade)==1)
            assert(T.runnerAlpha(d.ratLife)==0 and T.runnerAlpha(d.ratLife-d.ratFade/2)==0.5)
            local x,y=T.fleeDirection(50,100,3); assert(x<0,'left of the holder runs left')
            local x2,y2=T.fleeDirection(50,100,3); assert(x==x2 and y==y2,'no randomness')
            assert(math.abs(x*x+y*y-1)<1e-9,'unit length')
            local a=T.fleeDirection(100,nil,1); local b=T.fleeDirection(100,nil,2)
            assert(math.abs(a)>0.9 and math.abs(b)>0.9,'no holder: sideways all the same')
        """)

    def test_rats_are_cleared_and_drawn_flipped_and_a_missing_sprite_is_reported_once(self):
        self.load()
        self.run_lua("""
            holder.Position=Vector(300,100)
            step(); local fake=fakes()[1]
            fake.Position=Vector(200,100)
            fake.dead=true; callbacks[1].fn(nil,fake); step()
            assert(#M._test.runners()==1)
            M.onRoomRender(); assert(draws[1].flip==true,'running left is mirrored')
            M.onNewRoom(); assert(#M._test.runners()==0,'a new room clears them')
            M.removeAll('test'); holder.inventory[RAT]=nil; step(); holder.inventory[RAT]=1; step()
            M.removeAll('test'); assert(#M._test.runners()==1)
            M.onPreGameExit(nil,true); assert(#M._test.runners()==0,'exit clears them')
        """)
        self.lua.execute('M=nil; spriteFails=true; errors={}')
        self.load()
        self.run_lua("""
            step(); M.removeAll('test'); M.onRoomRender(); M.onRoomRender()
            local n=0; for _,e in ipairs(errors) do if e:find('rat art unavailable',1,true) then n=n+1 end end
            assert(n==1,'reported once')
        """)

    def test_rat_sprite_assets(self):
        anm2 = ROOT / 'resources/gfx/effects/conch_rat_run.anm2'
        tree = ET.parse(anm2)
        sheet = tree.find('.//Spritesheet').get('Path')
        png = anm2.parent / sheet
        self.assertTrue(png.exists(), sheet)
        image = Image.open(png)
        anim = tree.find('.//Animation[@Name="Run"]')
        self.assertEqual(anim.get('Loop'), 'true')
        frames = anim.findall('.//LayerAnimation/Frame')
        self.load(False)
        data = self.lua.eval('M.data')
        self.assertEqual(len(frames), data.ratFrames)
        self.assertEqual(int(anim.get('FrameNum')), data.ratFrames * data.ratFrameDelay)
        for i, frame in enumerate(frames):
            self.assertEqual(int(frame.get('Delay')), data.ratFrameDelay)
            w, h = int(frame.get('Width')), int(frame.get('Height'))
            self.assertEqual(int(frame.get('XCrop')), i * w)
            self.assertLessEqual(int(frame.get('XCrop')) + w, image.width)
            self.assertEqual(h, image.height)
        self.assertEqual(image.width, data.ratFrames * w)
        colors = {c for c in image.convert('RGBA').getdata() if c[3]}
        self.assertTrue(all(c[3] == 255 for c in colors), 'hard pixels only')
        self.assertIn((233, 223, 182, 255), colors, 'the fingernail is drawn')

    def test_eden_rolls_and_post_level_init_follow_the_holder(self):
        self.load()
        self.run_lua("""
            holder.eden={Damage=1.25,FireDelay=-0.5,Luck=2,Range=0.75,ShotSpeed=0.1,Speed=-0.05}
            local spawn=PlayerManager.SpawnCoPlayer2
            PlayerManager.SpawnCoPlayer2=function(t)
                local p=spawn(t); p.postInit=false; p.eden={Damage=0.3,Luck=-1}; return p
            end
            step(); local fake=fakes()[1]
            for stat,v in pairs(holder.eden) do assert(fake['GetEden'..stat](fake)==v,'Eden '..stat) end
            assert(fake.cacheFlags==CacheFlag.CACHE_ALL and fake.evaluations==1,'one cache refresh for the new rolls')
            assert(fake.postInit==true and fake.postInitBeforeStrip,'post-level init finished before the loadout is stripped')
            assert(fake.inventory[D6]==nil,'and what it granted was stripped')
        """)

    def test_a_two_body_character_fakes_both_bodies(self):
        self.load()
        self.run_lua("""
            -- Real Jacob holds Rat; real Esau carries a different passive.
            holder.kind=19
            local esau=makePlayer(20,{controller=2}); esau.inventory={[UP]=1}; esau.max=6; esau.red=6
            holder.twin=esau; esau.twin=holder
            list={holder,esau}
            -- The engine spawns Jacob with his Esau, listing Esau only on the next update.
            local deferred
            local spawn=PlayerManager.SpawnCoPlayer2
            PlayerManager.SpawnCoPlayer2=function(t)
                local jacob=spawn(t)
                local twin=makePlayer(20); twin.inventory={[LUCKY]=1}; twin.max=6; twin.red=6
                jacob.twin=twin; twin.twin=jacob
                deferred=twin
                return jacob
            end
            step()
            assert(#fakes()==1,'the listed body first')
            list[#list+1]=deferred
            step()
            local f=fakes(); assert(#f==2,'the late Esau joins the same fake')
            local fakeEsau=deferred
            assert(M.isFake(fakeEsau) and fakeEsau.Parent==holder and fakeEsau.ControllerIndex==2)
            assert(fakeEsau.inventory[UP]==1 and fakeEsau.inventory[LUCKY]==nil,'Esau copies the real Esau')
            assert(f[1].inventory[ONION]==1 and f[1].inventory[UP]==nil,'Jacob copies Jacob')
            assert(fakeEsau.max==6 and fakeEsau.red==6,"each body takes its own original's health")
            local mark=runSaves['PLAYER_'..fakeEsau.seed].ratFake
            assert(mark.group==runSaves['PLAYER_'..f[1].seed].ratFake.group,'one group')
            assert(not M.isFake(esau) and esau.Parent==nil,'the real Esau is left alone')
            f[1].dead=true; callbacks[1].fn(nil,f[1]); step()
            assert(#removed==2 and #list==2 and fallen()==1,'the pair falls together, one fall')
        """)

    def test_ordinary_characters_need_no_eden_refresh(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            assert(fake.evaluations==nil,'no cache refresh when nothing changed')
            assert(M._test.copyEdenStats(holder,fake)==false)
        """)

    def test_a_far_fake_is_brought_to_its_holder_on_room_entry(self):
        self.load()
        self.run_lua("""
            step(); local fake=fakes()[1]
            fake.Position=Vector(900,900); M.onNewRoom()
            assert(fake.Position.X==120 and fake.Position.Y==100)
        """)


if __name__ == '__main__':
    unittest.main()
