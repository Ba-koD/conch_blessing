"""Production Kronos callbacks with engine/provider doubles, not an Isaac Continue test."""
from pathlib import Path
import re
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts/items/collectibles/kronos.lua"


class KronosRoomEffectsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        # Enum values only identify independent fixture objects. Production
        # formulas, ledgers, registered Box callback and lifecycle hooks run intact.
        enums = {}
        for namespace, name in re.findall(r"\b([A-Z]\w+)\.([A-Z][A-Z_0-9]+)\b", SOURCE.read_text(encoding="utf-8")):
            if namespace not in {"ConchBlessing", "Isaac", "Vector"}:
                enums.setdefault(namespace, set()).add(name)
        for namespace, names in enums.items():
            self.lua.globals()[namespace] = self.lua.table_from({
                name: (1 << i if namespace == "CacheFlag" else i + 1)
                for i, name in enumerate(sorted(names))
            })
        self.lua.execute(r"""
            package.path=root..'/?.lua;'..package.path
            package.loaded['scripts.lib.hidden_item_manager']={}
            package.loaded['scripts.lib.damage_provenance']={registerCallbacks=function() end}
            function copy(t)
                if type(t)~='table' then return t end
                local out={}; for k,v in pairs(t) do out[k]=copy(v) end; return out
            end
            Vector=setmetatable({Zero={X=0,Y=0}}, {__call=function(_,x,y) return {X=x,Y=y} end})
            function Color(...) return {} end
            function GetPtrHash(entity) return entity.hash or 1 end
            run, per, floor, callbacks, familiars, exitCallbacks = {}, {}, {}, {}, {}, {}
            CallbackPriority.EARLY=-100
            state={itemAdditions={}}
            player={inventory={[9999]=1}, data={}, Damage=3.5, MoveSpeed=1, MaxFireDelay=10, Position=Vector.Zero}
            function player:HasCollectible(id) return (self.inventory[id] or 0)>0 end
            function player:GetCollectibleNum(id) return self.inventory[id] or 0 end
            function player:AddCollectible(id) self.inventory[id]=(self.inventory[id] or 0)+1 end
            function player:RemoveCollectible(id) self.inventory[id]=math.max(0,(self.inventory[id] or 0)-1) end
            function player:GetData() return self.data end
            function player:AddCacheFlags() end
            function player:HasTrinket() return false end
            function player:GetCollectibleRNG() return {RandomFloat=function() return 0.999 end} end
            effects={GetEffectsList=function() return {Size=0} end, GetCollectibleEffectNum=function() return 0 end}
            function effects:AddCollectibleEffect(id,_,count) self[id]=(self[id] or 0)+count end
            function player:GetEffects() return effects end
            function player:AddMinisaac()
                local f={Player=self,data={},hash=#familiars+10,alive=true}
                function f:GetData() return self.data end
                function f:ToFamiliar() return self end
                function f:Exists() return self.alive end
                function f:Remove() self.alive=false end
                familiars[#familiars+1]=f
                return f
            end
            local room={GetCenterPos=function() return Vector.Zero end}
            local game={GetNumPlayers=function() return 1 end, GetPlayer=function() return player end,
                GetRoom=function() return room end}
            function Game() return game end
            Isaac={GetItemIdByName=function() return 9999 end, GetPlayer=function() return player end,
                FindByType=function()
                    local live={}; for _,f in ipairs(familiars) do if f:Exists() then live[#live+1]=f end end
                    return live
                end}
            local um={}
            function um:SetItemAddition(_,id,stat,delta)
                state.itemAdditions[id]=state.itemAdditions[id] or {}
                local row=state.itemAdditions[id]
                row[stat]=row[stat] or {cumulative=0}
                row[stat].cumulative=row[stat].cumulative+delta
            end
            function um:RemoveItemAddition(_,id) state.itemAdditions[id]=nil end
            function um:QueueCacheUpdate() end
            function um:SaveToSaveManager() savedStats=copy(state) end
            ConchBlessing={SaveManager={
                GetRunSave=function(p) return p and per or run end,
                GetFloorSave=function() return floor end,
                Save=function() savedRun=copy(run) end},
                stats={unifiedMultipliers=um},
                getUnifiedMultiplierState=function() return state end,
                printDebug=function() end, printError=function(message) error(message) end}
            function ConchBlessing:AddCallback(id,fn,filter)
                callbacks[id]=callbacks[id] or {}; callbacks[id][filter or 'unfiltered']=fn
                if id==ModCallbacks.MC_PRE_GAME_EXIT then exitCallbacks[#exitCallbacks+1]={priority=0,fn=fn} end
            end
            function ConchBlessing:AddPriorityCallback(id,priority,fn)
                assert(id==ModCallbacks.MC_PRE_GAME_EXIT)
                exitCallbacks[#exitCallbacks+1]={priority=priority,fn=fn}
            end
            for _,row in ipairs({{'damage','Damage'},{'speed','MoveSpeed'},{'tears','Tears'}}) do
                local stat=row[2]
                ConchBlessing.stats[row[1]]={applyAddition=function(p,amount) p[stat]=p[stat]+amount end}
            end
            function damageBonus()
                local row=state.itemAdditions[9999]
                return row and row.Damage and row.Damage.cumulative or 0
            end
            function player:EvaluateItems()
                self.Damage=3.5+damageBonus(); self.Tears=30/11; self.MoveSpeed=1
                if K then
                    for _,flag in ipairs({CacheFlag.CACHE_DAMAGE,CacheFlag.CACHE_FIREDELAY,CacheFlag.CACHE_SPEED}) do
                        K.onEvaluateCache(nil,self,flag)
                    end
                end
            end
            -- Provider is loaded first, as in the mod's dependency contract.
            -- Model its default-priority disk snapshot separately from its
            -- mutable in-memory SaveToSaveManager state.
            ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT,function()
                um:SaveToSaveManager(player); diskStats=copy(savedStats)
            end)
            require('scripts.items.collectibles.kronos')
            K=ConchBlessing.kronos
            -- Only rendering is omitted. Box, stats, state cleanup, conversion
            -- reconciliation and Mongo entity ownership remain production code.
            originalTransferQueue=K._queueTransferEffect
            K._queueTransferEffect=function() end
            function absorb(name,count)
                local id=CollectibleType['COLLECTIBLE_'..name]
                K._getAbsorbedCount(player,id) -- initialize the production save schema
                run.kronos.absorbed['fam_'..id]={id=id,count=count}
                run.kronos.totalAbsorbed=run.kronos.totalAbsorbed+count
                K._syncAbsorbedDamage(player)
                player:EvaluateItems()
                return id
            end
            function useBox()
                callbacks[ModCallbacks.MC_USE_ITEM][CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS](nil,nil,nil,player)
            end
            function near(actual,expected) assert(math.abs(actual-expected)<0.00001,actual..' expected '..expected) end
        """)

    def test_damage_and_native_stats_double_and_expire_on_room_entry(self):
        self.lua.execute("""
            absorb('BROTHER_BOBBY',1); absorb('GUARDIAN_ANGEL',1)
            near(damageBonus(),4); near(player.Tears,30/11+2); near(player.MoveSpeed,1.3)
            useBox()
            near(damageBonus(),8); near(player.Damage,11.5)
            near(player.Tears,30/11+4); near(player.MoveSpeed,1.6)
            K.onNewRoom()
            near(damageBonus(),4); near(player.Tears,30/11+2); near(player.MoveSpeed,1.3)
            K.onNewRoom(); near(damageBonus(),4)
        """)

    def test_repeated_use_does_not_change_absorptions_or_grants(self):
        self.lua.execute("""
            local id=absorb('SACK_OF_PENNIES',1)
            local key='fam_'..id
            run.kronos.itemGrants[key]=1; run.kronos.itemGrantTotals[key]=1
            player.inventory[CollectibleType.COLLECTIBLE_DOLLAR]=1
            useBox(); useBox()
            near(damageBonus(),6); assert(run.kronos.totalAbsorbed==1)
            assert(run.kronos.absorbed[key].count==1 and run.kronos.itemGrants[key]==1)
            assert(run.kronos.itemGrantTotals[key]==1 and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_DOLLAR)==1)
            K.onNewRoom(); near(damageBonus(),2)
        """)

    def test_paschal_multiplies_current_application_not_saved_earnings(self):
        self.lua.execute("""
            absorb('PASCHAL_CANDLE',1)
            K.onRoomClear(nil,nil,Vector.Zero)
            near(player.Tears,30/11+0.03)
            useBox(); near(player.Tears,30/11+0.06)
            K.onRoomClear(nil,nil,Vector.Zero)
            assert(run.kronos.paschalHundredths==6)
            near(player.Tears,30/11+0.12)
            K.onNewRoom(); near(player.Tears,30/11+0.06)
            K.onGameStarted(); near(player.Tears,30/11+0.06)
        """)

    def test_exit_withdraws_temporary_damage_before_provider_save(self):
        self.lua.execute("""
            absorb('BROTHER_BOBBY',1); useBox()
            near(savedStats.itemAdditions[9999].Damage.cumulative,4)
            table.sort(exitCallbacks,function(a,b) return a.priority<b.priority end)
            assert(#exitCallbacks==2 and exitCallbacks[1].priority<0)
            for _,row in ipairs(exitCallbacks) do row.fn(nil,true) end
            near(damageBonus(),2); near(savedStats.itemAdditions[9999].Damage.cumulative,2)
            near(diskStats.itemAdditions[9999].Damage.cumulative,2)
            near(player.Tears,30/11+2)
            assert(K._getRoomTemporary().double==0 and K._runReady==false)
            K.onGameStarted(); near(damageBonus(),2)
        """)

    def test_start_reconciles_stale_provider_damage_and_runtime_multiplier(self):
        self.lua.execute("""
            absorb('BROTHER_BOBBY',1); useBox(); useBox()
            -- Models stale serialized provider data, not the engine's Continue.
            state.itemAdditions[9999].Damage.cumulative=88
            K.onGameStarted()
            near(damageBonus(),2); near(savedStats.itemAdditions[9999].Damage.cumulative,2)
            near(player.Tears,30/11+2); assert(K._getRoomTemporary().double==0)
            K._syncAbsorbedDamage(player); near(damageBonus(),2)
        """)

    def test_floor_reward_does_not_inherit_previous_room_multiplier(self):
        self.lua.execute("""
            absorb('LOST_SOUL',1); K.onGameStarted(); useBox()
            K.onNewLevel()
            assert(run.kronos.lostSoulRewardPending==1)
            near(damageBonus(),2); assert(K._getRoomTemporary().double==0)
        """)

    def test_room_reset_preserves_manual_and_lilith_original_effects(self):
        self.lua.execute("""
            absorb('BROTHER_BOBBY',1)
            local guardian=CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL
            local guillotine=CollectibleType.COLLECTIBLE_GUILLOTINE
            run.kronos.tempFloor={serial=0,counts={['fam_'..guardian]=1}}
            run.kronos.tempPermanent={['fam_'..guillotine]=1}
            run.kronos.prettyFlies=1
            K._syncAbsorbedDamage(player); near(damageBonus(),8)
            useBox(); near(damageBonus(),16)
            assert(K._getEffectCount(player,guardian)==2 and K._getPrettyFlyCount(player)==2)
            K.onPreGameExit(); K.onGameStarted()
            near(damageBonus(),8)
            assert(K._getEffectCount(player,guardian)==1 and K._getPrettyFlyCount(player)==1)
            K.onNewLevel()
            near(damageBonus(),6)
            assert(K._getEffectCount(player,guardian)==0 and K._getEffectCount(player,guillotine)==1)
        """)

    def test_missing_priority_api_keeps_continue_reconciliation(self):
        self.lua.execute("""
            ConchBlessing.AddPriorityCallback=nil
            package.loaded['scripts.items.collectibles.kronos']=nil
            require('scripts.items.collectibles.kronos'); K=ConchBlessing.kronos
            K._queueTransferEffect=function() end
            assert(callbacks[ModCallbacks.MC_PRE_GAME_EXIT].unfiltered==K.onPreGameExit)
            absorb('BROTHER_BOBBY',1); useBox()
            callbacks[ModCallbacks.MC_PRE_GAME_EXIT].unfiltered(nil,true)
            state.itemAdditions[9999].Damage.cumulative=4
            K.onGameStarted(); near(damageBonus(),2)
        """)

    def test_mongo_extra_copies_removed_without_touching_other_minisaacs(self):
        self.lua.execute("""
            absorb('MONGO_BABY',1); K._topUpMongoMinisaacs(player)
            local original=familiars[1]
            local other=player:AddMinisaac()
            useBox(); local extra=familiars[3]
            assert(extra and extra:Exists() and #familiars==3)
            useBox(); local secondExtra=familiars[4]
            assert(secondExtra and secondExtra:Exists())
            K.onPreGameExit()
            assert(original:Exists() and other:Exists())
            assert(not extra:Exists() and not secondExtra:Exists())
            K.onGameStarted(); K.onNewRoom()
            assert(#familiars==4 and original:Exists() and other:Exists())
        """)

    def test_loss_returns_only_original_familiars(self):
        self.lua.execute("""
            local bobby=absorb('BROTHER_BOBBY',2)
            absorb('MONGO_BABY',1); K._topUpMongoMinisaacs(player); useBox()
            local extra=familiars[2]
            player:RemoveCollectible(9999); K._revertAll(player)
            assert(player:GetCollectibleNum(bobby)==2)
            assert(not extra:Exists() and K._getRoomTemporary().double==0)
            K._syncAbsorbedDamage(player); near(damageBonus(),0)
        """)


if __name__ == "__main__":
    unittest.main()
