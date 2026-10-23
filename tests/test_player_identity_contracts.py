"""Per-player identity contracts for the steroid actives/passive, Time items,
minus trinkets and trinket multipliers, under Lua engine doubles (Lua 5.3).

Two players of one character (a second player of the same type and controller,
Jacob & Esau, Strawman) must keep separate state; a character change (Lazarus,
Clicker) must keep it; Continue must reload it from the player's own save,
including state that older saves kept under the PlayerType. These do not
replace in-game verification.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

PRELUDE = r'''
package.path=root..'/?.lua;'..package.path
CacheFlag={CACHE_DAMAGE=1,CACHE_FIREDELAY=2,CACHE_SPEED=4,CACHE_RANGE=8,CACHE_LUCK=16,CACHE_FAMILIARS=32,CACHE_ALL=255}
CollectibleType={COLLECTIBLE_MOMS_BOX=439,COLLECTIBLE_D6=105,COLLECTIBLE_BFFS=247}
TrinketType={TRINKET_GOLDEN_FLAG=32768}
UseFlag={USE_NOANIM=1,USE_OWNED=4,USE_MIMIC=128}
ModCallbacks={MC_POST_GAME_STARTED=15,MC_PRE_GAME_EXIT=17,MC_POST_NEW_LEVEL=18}
EntityType={ENTITY_PICKUP=5,ENTITY_FAMILIAR=3,ENTITY_EFFECT=1000}
PickupVariant={PICKUP_TRINKET=350,PICKUP_COIN=20}
SoundEffect={SOUND_BATTERYCHARGE=1,SOUND_ISAAC_HURT_GRUNT=2}
local vmt={}; vmt.__index=vmt
Vector=setmetatable({},{__call=function(_,x,y) return setmetatable({X=x,Y=y},vmt) end})
vmt.__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
Vector.Zero=Vector(0,0)
Color=function(...) return {...} end
SFXManager=function() return {Play=function() end} end
RNG=function()
    local r={seed=1}
    function r:SetSeed(s) self.seed=s end
    function r:RandomFloat() self.seed=(self.seed*1103515245+12345)%2147483648; return self.seed/2147483648 end
    return r
end
GOLD=32768; SELF=99 -- a damage flag value the hit filter treats as self-damage
ids={['Oral Steroids']=901,['Power Training']=902,['Injectable Steroids']=903,['Inf D6']=904}
tids={['F -']=11,['C -']=12,['B -']=13,['A -']=14,['Time = Power']=21}
frame=0; spawned={}; saves=0; runSaves={}; floorSaves={}; callbacks={}; hits={}
local function add(id,fn) callbacks[id]=callbacks[id] or {}; table.insert(callbacks[id],fn) end
function fire(id,...) for _,fn in ipairs(callbacks[id] or {}) do fn(nil,...) end end
mod={__SAVEMANAGER_UNIQUE_KEY='t'}; function mod:AddCallback(id,fn) add(id,fn) end
players={}
game={GetFrameCount=function() return frame end,GetNumPlayers=function() return #players end,
    GetPlayer=function(_,i) return players[i+1] end,
    GetSeeds=function() return {GetStartSeed=function() return 1234 end,GetStartSeedString=function() return 'ABCD' end} end}
Game=function() return game end
Isaac={GetPlayer=function(i) return players[(i or 0)+1] end,
    GetItemIdByName=function(n) return ids[n] or -1 end,GetTrinketIdByName=function(n) return tids[n] or -1 end,
    Spawn=function(t,v,s) spawned[#spawned+1]={t,v,s}; return {ToEffect=function() return nil end} end,
    FindByType=function() return {} end}
GetPtrHash=function(e) return e.hash end
SM={SaveCallbacks={PRE_DATA_SAVE='pre_save',PRE_FLOOR_DATA_RESET='pre_floor',POST_GLOWING_HOURGLASS_RESET='hourglass'},
    Utility={GetSaveIndex=function(p) return 'PLAYER_'..p.seed end},
    GetRunSave=function(p) local k=p and p.seed or 'global'; runSaves[k]=runSaves[k] or {}; return runSaves[k] end,
    GetFloorSave=function(p) local k=p and p.seed or 'global'; floorSaves[k]=floorSaves[k] or {}; return floorSaves[k] end,
    Save=function() saves=saves+1 end}
package.loaded['scripts.lib.save_manager']=SM
package.loaded['scripts.lib.player_hits']={register=function(key,fn) hits[key]=fn end,counts=function(flags) return flags~=SELF end}
UM={writes=0}
local function bucket(p,group,id,stat) UM[p.hash]=UM[p.hash] or {}; local t=UM[p.hash]
    t[group]=t[group] or {}; t[group][id]=t[group][id] or {}; return t[group][id] end
function UM:RemoveItemAddition(p,id,stat) bucket(p,'add',id)[stat]={} end
function UM:SetItemAdditiveMultiplier(p,id,stat,v,src) local b=bucket(p,'add',id); b[stat]=b[stat] or {}; b[stat][src]=v end
function UM:SetItemMultiplier(p,id,stat,v) bucket(p,'mult',id)[stat]=v; self.writes=self.writes+1 end
function UM:RemoveItemMultiplier(p,id,stat) bucket(p,'mult',id)[stat]=nil end
function UM:SaveToSaveManager() self.writes=self.writes+1 end
function UM:LoadFromSaveManager() end
function UM:InitPlayer() end
ConchBlessing={originalMod=mod,SaveManager=SM,Config={debugMode=false},errors={},
    printDebug=function() end,printError=function(e) table.insert(ConchBlessing.errors,e) end,
    ItemData={TIME_POWER={id=21}},
    getUnifiedStatTotal=function() return 1 end,
    stats={unifiedMultipliers=UM,multiplierDisplay={ForceDisplay=function() end},
        damage={applyAddition=function(p,v) p.Damage=p.Damage+v end},
        luck={applyAddition=function(p,v) p.Luck=p.Luck+v end},
        tears={applyAddition=function(p,v) p.Tears=p.Tears+v end},
        speed={applyAddition=function() end}}}
function ConchBlessing:AddCallback(id,fn) add(id,fn) end
local nextHash=0
-- An engine-like player: GetTrinketMultiplier counts +1 per normal and +2 per
-- golden copy held or smelted, and Mom's Box +1 once.
function newPlayer(kind,seed,keep)
    nextHash=nextHash+1
    local p={kind=kind,seed=seed,hash=nextHash,counts={},slots={0,0},smelted={},uses={},evals=0,
        Damage=3.5,Luck=0,Tears=2.73,Position=Vector(0,0),ControllerIndex=0,colors=0}
    function p:GetPlayerType() return self.kind end
    function p:GetCollectibleNum(id) return self.counts[id] or 0 end
    function p:HasCollectible(id) return (self.counts[id] or 0)>0 end
    function p:GetTrinket(slot) return self.slots[slot+1] end
    function p:HasTrinket(id) return self:GetTrinketMultiplier(id)>0 end
    function p:GetTrinketMultiplier(id)
        local n=0
        for _,raw in ipairs(self.slots) do
            if raw==id then n=n+1 elseif raw==id+GOLD then n=n+2 end
        end
        local s=self.smelted[id]; if s then n=n+s.trinketAmount+2*s.goldenTrinketAmount end
        if n>0 and self:HasCollectible(439) then n=n+1 end
        return n
    end
    function p:TryRemoveTrinket(id)
        for i=1,2 do
            if self.slots[i]==id then table.remove(self.slots,i); table.insert(self.slots,0); return true end
        end
        return false
    end
    function p:AddCacheFlags() end
    function p:EvaluateItems() self.evals=self.evals+1 end
    function p:AnimateCollectible() end
    function p:UseActiveItem(id,flags,slot) self.uses[#self.uses+1]={id=id,flags=flags,slot=slot} end
    function p:ToPlayer() return self end
    function p:SetColor() self.colors=self.colors+1 end
    function p:GetCollectibleRNG() return RNG() end
    if not keep then players[#players+1]=p end
    return p
end
function enableSmeltApi(p)
    function p:GetSmeltedTrinkets() return self.smelted end
    function p:TryRemoveSmeltedTrinket(id)
        local base=id>=GOLD and id-GOLD or id; local s=self.smelted[base]
        local field=id>=GOLD and 'goldenTrinketAmount' or 'trinketAmount'
        if s and s[field]>0 then s[field]=s[field]-1 end
    end
    function p:AddSmeltedTrinket(id)
        local base=id>=GOLD and id-GOLD or id
        self.smelted[base]=self.smelted[base] or {trinketAmount=0,goldenTrinketAmount=0}
        local field=id>=GOLD and 'goldenTrinketAmount' or 'trinketAmount'
        self.smelted[base][field]=self.smelted[base][field]+1; return true
    end
end
function near(a,b) return math.abs(a-b)<1e-9 end
-- A Continue: new player entities (new hashes) with the same save identity.
function continueWith(list) players={}; for _,p in ipairs(list) do players[#players+1]=p end end
'''


class PlayerIdentity(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(PRELUDE)

    def run_lua(self, code):
        self.lua.execute(code)

    def test_use_item_handlers_follow_mc_use_item_argument_order(self):
        self.run_lua('''
            require('scripts.items.collectibles.inf_d6'); require('scripts.items.collectibles.power_training')
            math.random=function() return 0.5 end
            local first=newPlayer(0,11); local user=newPlayer(0,22)
            -- (mod, collectible, rng, player, useFlags, activeSlot, customVarData)
            local result=ConchBlessing.infd6.onUse(mod,904,RNG(),user,UseFlag.USE_OWNED,0,0)
            assert(result and result.Discharge==false,'Inf D6 did not answer its own use')
            assert(#first.uses==0 and #user.uses==1,'Inf D6 rerolled for player 0 instead of the user')
            assert(user.uses[1].id==105 and user.uses[1].flags==(1|4|128),'use flags dropped: '..user.uses[1].flags)
            assert(ConchBlessing.infd6.onUse(mod,904,RNG(),nil,0,0,0)==nil and #first.uses==0)
            assert(#ConchBlessing.errors==1,'missing player must be reported, not replaced by player 0')
            assert(ConchBlessing.infd6.onUse(mod,999,RNG(),user,0,0,0)==nil and #user.uses==1)

            result=ConchBlessing.powertraining.onUseItem(mod,902,RNG(),user,0,0,0)
            assert(result and result.Discharge,'Power Training use not accepted')
            assert(#runSaves[22].powerTraining==1 and (runSaves[11] or {}).powerTraining==nil,'roll went to the wrong player')
            assert(UM[user.hash] and UM[first.hash]==nil,'stats registered on the wrong player')
            assert(ConchBlessing.powertraining.onUseItem(mod,902,RNG(),nil,0,0,0)==nil)
            assert(#ConchBlessing.errors==2 and #runSaves[22].powerTraining==1)
        ''')

    def test_oral_steroids_same_type_players_keep_their_own_rolls(self):
        self.run_lua('''
            require('scripts.items.collectibles.oral_steroids'); local O=ConchBlessing.oralsteroids
            local rolls=0; math.random=function() rolls=rolls+1; return 0.5 end
            local a=newPlayer(0,11); local b=newPlayer(0,22)
            a.counts[901]=1; b.counts[901]=2
            O.onEvaluateCache(nil,a,1); O.onPlayerUpdate(nil,a)
            assert(rolls==0 and next(runSaves)==nil,'rolled before game start reconciled the run')
            O.onGameStarted(nil,false)
            assert(#runSaves[11].oralSteroids==1 and #runSaves[22].oralSteroids==2 and rolls==12)
            for _=1,10 do
                O.onPlayerUpdate(nil,a); O.onPlayerUpdate(nil,b)
                O.onEvaluateCache(nil,a,1); O.onEvaluateCache(nil,b,1)
            end
            assert(rolls==12,'same-type players rerolled each other: '..rolls)
            local first=runSaves[11].oralSteroids[1]
            b.counts[901]=1; O.onPlayerUpdate(nil,b)
            assert(#runSaves[22].oralSteroids==1 and #runSaves[11].oralSteroids==1,'removal crossed players')
            a.kind=11; O.onPlayerUpdate(nil,a); O.onEvaluateCache(nil,a,1)
            assert(rolls==12 and runSaves[11].oralSteroids[1]==first,'a character change rerolled')

            -- Continue: new entities, same saves; nothing rerolls and the stats come back.
            local a2=newPlayer(11,11,true); a2.counts[901]=1
            local b2=newPlayer(0,22,true); b2.counts[901]=1
            continueWith({a2,b2}); O.onPreGameExit(); O.onGameStarted(nil,true)
            assert(rolls==12,'Continue rerolled')
            assert(UM[a2.hash].add[901].Damage['Oral Steroids #1']==first.damage,'Continue lost the roll')
            assert(O._lastItemCount[a2.hash]==1 and O._lastItemCount[b2.hash]==1)
        ''')

    def test_oral_steroids_follow_a_glowing_hourglass_rewind(self):
        # A rewind restores the run save but not StatsAPI, so each copy-count
        # change re-registers exactly the saved rolls.
        self.run_lua('''
            require('scripts.items.collectibles.oral_steroids'); local O=ConchBlessing.oralsteroids
            local rolls=0; math.random=function() rolls=rolls+1; return 0.5 end
            local a=newPlayer(0,11); a.counts[901]=1
            O.onGameStarted(nil,false)
            local first=runSaves[11].oralSteroids[1]
            assert(UM[a.hash].add[901].Damage['Oral Steroids #1']==first.damage)
            local function registered()
                local add=UM[a.hash].add[901]
                return add and add.Damage and add.Damage['Oral Steroids #1']
            end
            -- Rewound to before the pickup: no copy and no saved roll.
            runSaves[11].oralSteroids=nil; a.counts[901]=0
            O.onPlayerUpdate(nil,a)
            assert(registered()==nil,'the rewound copy kept its stats')
            -- Rewound to a room where it was held again: the saved roll comes back.
            runSaves[11].oralSteroids={first}; a.counts[901]=1
            O.onPlayerUpdate(nil,a)
            assert(registered()==first.damage and rolls==4,'the held copy lost or rerolled its stats')
        ''')

    def test_time_power_players_grow_and_pause_on_their_own(self):
        self.run_lua('''
            require('scripts.items.trinkets.time_power'); local T=ConchBlessing.timepowertrinket
            local a=newPlayer(0,11); local b=newPlayer(0,22)
            a.slots={21,0}; b.slots={21,0}
            T.onGameStarted(nil,false)
            for _=1,30 do frame=frame+1; T.onUpdate() end
            assert(near(T.getPlayerState(a).damageBonus,0.006) and near(T.getPlayerState(b).damageBonus,0.006),
                'same-type players shared one growth: '..T.getPlayerState(a).damageBonus)
            assert(hits.TIME_POWER(nil,a,1,0,nil,30)==true)
            for _=1,30 do frame=frame+1; T.onUpdate() end
            assert(near(T.getPlayerState(a).damageBonus,0.006),'hit player kept growing')
            assert(near(T.getPlayerState(b).damageBonus,0.012),'a hit paused the other player')
            -- Lazarus / Clicker: the same player under a new character keeps what it earned.
            local earned=T.getPlayerState(b).damageBonus
            b.kind=8; frame=frame+1; T.onUpdate()
            assert(T.getPlayerState(b).damageBonus>earned,'character change reset the bonus')
            assert(runSaves[22].timePower.damageBonus~=nil and runSaves[22].timePower['0']==nil)
        ''')

    def test_time_power_mom_box_follows_the_engine_multiplier(self):
        self.run_lua('''
            require('scripts.items.trinkets.time_power'); local T=ConchBlessing.timepowertrinket
            local U=require('scripts.lib.trinket_utils')
            local p=newPlayer(0,11); p.counts[439]=1
            p.slots={21,21}; p.smelted[21]={trinketAmount=1,goldenTrinketAmount=0}
            assert(p:GetTrinketMultiplier(21)==4)
            T.onGameStarted(nil,false)
            for _=1,30 do frame=frame+1; T.onUpdate() end
            assert(near(T.getPlayerState(p).damageBonus,0.006*4),
                'Mom\\'s Box counted per copy: '..T.getPlayerState(p).damageBonus/0.006)
            -- Counts always add back up to the engine multiplier.
            local n,g,box=U.getTrinketCounts(p,21); assert(n==3 and g==0 and box==true)
            enableSmeltApi(p); p.slots={21+GOLD,0}; p.smelted[21]={trinketAmount=1,goldenTrinketAmount=1}
            n,g,box=U.getTrinketCounts(p,21); assert(n==1 and g==2 and box and n+2*g+1==p:GetTrinketMultiplier(21))
            local q=newPlayer(0,22); q.slots={21+GOLD,21}
            n,g=U.getTrinketCounts(q,21); assert(n==1 and g==1,'two held copies read as one golden')
        ''')

    def test_time_power_continue_migrates_player_type_records(self):
        self.run_lua('''
            require('scripts.items.trinkets.time_power'); local T=ConchBlessing.timepowertrinket
            -- Saved under Lazarus (8), then Lazarus Risen (11) after the revive.
            runSaves[33]={timePower={['8']={damageBonus=0.5,permanentBonus=0.25,pauseFramesRemaining=0},
                ['11']={damageBonus=0.1,permanentBonus=0.05,pauseFramesRemaining=900,data={keepOnDrop=true}}}}
            local c=newPlayer(11,33); c.slots={21,0}; frame=1000
            T.onGameStarted(nil,true)
            local rec=runSaves[33].timePower; local ps=T.getPlayerState(c)
            assert(rec['8']==nil and rec['11']==nil,'legacy records not folded in')
            assert(near(ps.permanentBonus,0.8) and near(ps.damageBonus,0.1),'earned bonus lost: '..ps.permanentBonus)
            assert(ps.pausedUntilFrame==1900,'saved pause not resumed')
            c.Damage=3.5; T.onEvaluateCache(nil,c,CacheFlag.CACHE_DAMAGE); assert(near(c.Damage,3.5+0.9))
            -- The exit save writes this player's remaining pause into its own record.
            frame=1100
            local copy={game={run={PLAYER_33={timePower={pauseFramesRemaining=0}}}}}
            fire('pre_save',copy); assert(copy.game.run.PLAYER_33.timePower.pauseFramesRemaining==800)
            -- A second Continue reads the flat record and migrates nothing.
            local c2=newPlayer(11,33,true); c2.slots={21,0}; continueWith({c2})
            T.onGameStarted(nil,true); assert(near(T.getPlayerState(c2).permanentBonus,0.8))
        ''')

    def test_minus_chain_hit_belongs_to_the_hit_player(self):
        self.run_lua('''
            require('scripts.items.trinkets.minus_chain'); local MC=ConchBlessing.minuschain
            local jacob=newPlayer(19,11); local esau=newPlayer(20,22) -- one controller
            jacob.slots={11,0}; esau.slots={11,0}
            local function newLevel() fire('pre_floor'); floorSaves={}; fire(ModCallbacks.MC_POST_NEW_LEVEL) end
            newLevel(); assert(#spawned==0 and jacob.slots[1]==11,'evolved before game start')
            fire(ModCallbacks.MC_POST_GAME_STARTED,false)
            hits.MINUS_CHAIN(nil,jacob,1,0)
            assert(not MC.noHit(jacob) and MC.noHit(esau),'one hit marked both players')
            assert(hits.MINUS_CHAIN(nil,esau,1,SELF)==nil and MC.noHit(esau),'self-damage counted')
            newLevel()
            assert(jacob.slots[1]==11,'hit player evolved')
            assert(esau.slots[1]==0 and #spawned==1 and spawned[1][3]==12,'clean player did not evolve')
            -- Continue keeps an earlier hit on this floor.
            hits.MINUS_CHAIN(nil,jacob,1,0)
            fire(ModCallbacks.MC_PRE_GAME_EXIT)
            local j2=newPlayer(19,11,true); j2.slots={11,0}; continueWith({j2})
            fire(ModCallbacks.MC_POST_NEW_LEVEL) -- a Continue's own level event changes nothing
            fire(ModCallbacks.MC_POST_GAME_STARTED,true)
            assert(not MC.noHit(j2),'Continue forgot the hit')
            newLevel(); assert(j2.slots[1]==11 and #spawned==1)
        ''')

    def test_minus_chain_evolves_both_carried_trinkets_after_slot_shift(self):
        self.run_lua('''
            require('scripts.items.trinkets.minus_chain')
            local p=newPlayer(0,11); p.slots={11,12+GOLD}
            fire(ModCallbacks.MC_POST_GAME_STARTED,false)
            fire('pre_floor'); floorSaves={}; fire(ModCallbacks.MC_POST_NEW_LEVEL)
            assert(p.slots[1]==0 and p.slots[2]==0,'second trinket skipped after slot shift')
            assert(#spawned==2 and spawned[1][3]==12 and spawned[2][3]==13+GOLD)
        ''')

    def test_a_minus_holders_on_one_controller_each_get_their_split(self):
        self.run_lua('''
            require('scripts.items.trinkets.a_minus'); local A=ConchBlessing.aminus
            local p1=newPlayer(19,11); local p2=newPlayer(20,22); local idle=newPlayer(0,33)
            p1.slots={14,0}; p2.slots={14,0}
            fire(ModCallbacks.MC_POST_GAME_STARTED,false)
            for _=1,10 do
                A.onPostPEffectUpdate(nil,p1); A.onPostPEffectUpdate(nil,p2); A.onPostPEffectUpdate(nil,idle)
            end
            assert(UM[p1.hash].mult[14].Damage and UM[p2.hash].mult[14].Damage,'second holder got no multipliers')
            assert(runSaves[11].aMinus.split and runSaves[22].aMinus.split)
            assert(p1.evals==1 and p2.evals==1 and idle.evals==0,'re-evaluated every frame')
            local writes=UM.writes
            for _=1,5 do A.onPostPEffectUpdate(nil,idle); A.onPostPEffectUpdate(nil,p1) end
            assert(UM.writes==writes,'a non-holder churned the holders\\' multipliers')
            -- Losing it removes only that player's multipliers, once.
            p2.slots={0,0}; A.onPostPEffectUpdate(nil,p2); A.onPostPEffectUpdate(nil,p2)
            assert(UM[p2.hash].mult[14].Damage==nil and UM[p1.hash].mult[14].Damage and p2.evals==2)
        ''')

    def test_a_minus_hit_demotes_every_held_copy_and_never_a_smelted_one(self):
        self.run_lua('''
            require('scripts.items.trinkets.a_minus')
            local p=newPlayer(0,11); p.slots={14,14+GOLD}
            assert(hits.A_MINUS(nil,p,1,0)==true)
            assert(p.slots[1]==0 and p.slots[2]==0,'second A- skipped after slot shift')
            assert(#spawned==2 and spawned[1][3]==13 and spawned[2][3]==13+GOLD)
            -- A smelted A- is fixed for good, with or without the smelt API.
            local s=newPlayer(0,22); enableSmeltApi(s)
            s.smelted[14]={trinketAmount=1,goldenTrinketAmount=1}
            assert(hits.A_MINUS(nil,s,1,0)==false)
            assert(s.smelted[14].trinketAmount==1 and s.smelted[14].goldenTrinketAmount==1,'smelted A- changed')
            assert(s.smelted[13]==nil and #spawned==2,'a smelted A- made a B-')
            local base=newPlayer(0,33); base.smelted[14]={trinketAmount=1,goldenTrinketAmount=0}
            assert(hits.A_MINUS(nil,base,1,0)==false and base.smelted[14].trinketAmount==1)
            -- Holding one and having smelted another demotes only the held copy.
            local both=newPlayer(0,55); enableSmeltApi(both); both.slots={14,0}
            both.smelted[14]={trinketAmount=1,goldenTrinketAmount=0}
            assert(hits.A_MINUS(nil,both,1,0)==true and both.slots[1]==0 and #spawned==3)
            assert(both.smelted[14].trinketAmount==1 and both.smelted[13]==nil)
            assert(hits.A_MINUS(nil,newPlayer(0,44),1,0)==nil,'a player without A- reported a demotion')
        ''')

    def test_injectable_steroids_tints_its_user_and_keeps_floor_risk_on_continue(self):
        self.run_lua('''
            require('scripts.items.collectibles.injectable_steroids'); local I=ConchBlessing.injectablsteroids
            math.random=function() return 0.5 end
            floorSaves.global={injectableSteroidsRisk={chance=7,uses=2}}
            local a=newPlayer(0,11); local b=newPlayer(0,22)
            I.onNewLevel() -- a Continue's level event comes before game start
            assert(floorSaves.global.injectableSteroidsRisk.chance==7,'Continue overwrote the saved risk')
            I.onGameStarted(nil,true)
            assert(I.data.currentInstantDeathPercent==7 and I.data.currentFloorUseCount==2)
            local rng={RandomFloat=function() return 0.99 end}
            assert(I.onUseItem(nil,903,rng,b,0,0).Discharge)
            I.onUpdate(); I.onUpdate()
            assert(b.colors==2 and a.colors==0,'tint drawn on the wrong player')
            assert(#runSaves[22].injectableSteroids==1 and (runSaves[11] or {}).injectableSteroids==nil)
            I.onNewLevel(); assert(I.data.currentInstantDeathPercent==1,'new floor did not reset the risk')
            I.onPreGameExit(); floorSaves.global.injectableSteroidsRisk={chance=4,uses=1}
            I.onNewLevel(); assert(floorSaves.global.injectableSteroidsRisk.chance==4)
        ''')


if __name__ == '__main__':
    unittest.main()
