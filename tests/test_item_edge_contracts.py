"""Boundary regressions against shipped item modules (Lua 5.3).

Engine doubles supply inputs and observe effects; gameplay functions and predicates
are loaded unchanged. These do not prove engine TrySplit/death/Continue behavior.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class ItemFixture(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("package.path = './?.lua;' .. package.path")

    def load(self, name):
        self.lua.execute((ROOT / 'scripts/items/collectibles' / (name + '.lua')).read_text(encoding='utf-8'))


class SwordEdges(ItemFixture):
    def setUp(self):
        super().setUp()
        self.lua.execute('''
            EntityType={ENTITY_EFFECT=1000,ENTITY_FIREPLACE=33,ENTITY_SHOPKEEPER=17,ENTITY_SLOT=6}
            EntityFlag={FLAG_FRIENDLY=1}; EffectVariant={POOF01=1}
            CacheFlag={CACHE_SPEED=4}; CollectibleType={COLLECTIBLE_MEAT_CLEAVER=631}
            UseFlag={USE_NOANIM=1,USE_NOCOSTUME=2}; SoundEffect={SOUND_POWERUP_SPEWER=1}
            Vector={Zero={}}; REPENTOGON={Real=true}; EID=nil
            errors={}; debug={}; stock={}; saves={}; roomSaves={}; roomIndex=1; writes=0; serial=0; roomClear=false
            room={IsClear=function() return roomClear end}
            players={}
            function newPlayer(copies)
                local p={swords=copies,tyrfing=0,Position={},MoveSpeed=1,cacheCalls=0,uses=0}
                function p:HasCollectible(id) return id==7 and self.swords>0 end
                function p:GetCollectibleNum(id) return id==7 and self.swords or self.tyrfing end
                function p:RemoveCollectible(id) assert(id==7); self.swords=self.swords-1 end
                function p:AddCollectible(id) assert(id==8); self.tyrfing=self.tyrfing+1 end
                function p:AddCacheFlags() self.cacheCalls=self.cacheCalls+1 end
                function p:EvaluateItems() end
                function p:UseActiveItem(id,flags) assert(id==631 and flags==3); self.uses=self.uses+1 end
                players[#players+1]=p; saves[p]={}; return p
            end
            game={GetRoom=function() return room end,GetNumPlayers=function() return #players end,
                GetLevel=function() return {GetCurrentRoomDesc=function() return {ListIndex=roomIndex} end} end,
                GetPlayer=function(_,i) return players[i+1] end}
            Game=function() return game end
            Isaac={GetItemIdByName=function(n) return n=='Tyrfing' and 8 or 7 end,
                GetPlayer=function(i) return players[i+1] end,GetRoomEntities=function() return stock end,Spawn=function() end}
            SFXManager=function() return {Play=function() end} end
            GetPtrHash=function(n) return n.serial end; EntityRef=function(p) return {Entity=p} end
            ConchBlessing={printDebug=function(x) debug[#debug+1]=x end,printError=function(x) errors[#errors+1]=x end,
                originalMod={__SAVEMANAGER_UNIQUE_KEY='edge',AddCallback=function(_,key,fn) callbacks[key]=fn end}}
            callbacks={}
            package.loaded['scripts.lib.save_manager']={
                SaveCallbacks={POST_GLOWING_HOURGLASS_RESET='hourglass'},
                GetRunSave=function(p) return saves[p] end,Save=function() writes=writes+1 end,
                GetRoomSave=function(_,noHourglass,index)
                    assert(noHourglass==false and index==roomIndex)
                    roomSaves[index]=roomSaves[index] or {}; return roomSaves[index]
                end}
            function npc(options)
                serial=serial+1
                local n={serial=serial,InitSeed=serial,Type=10,Variant=0,SubType=0,MaxHitPoints=100,
                    calls=0,enemy=true,vulnerable=true,active=true}
                for k,v in pairs(options or {}) do n[k]=v end
                function n:ToNPC() return self end
                function n:IsEnemy() return self.enemy end
                function n:HasEntityFlags() return self.friendly==true end
                function n:IsDead() return self.dead==true end
                function n:IsVulnerableEnemy() return self.vulnerable end
                function n:IsActiveEnemy() return self.active end
                function n:IsBoss() return self.boss==true end
                function n:GetChampionColorIdx() return self.champion or -1 end
                function n:GetData() self.data=self.data or {}; return self.data end
                function n:TrySplit(damage,source,ignoreBoss)
                    self.calls=self.calls+1; self.damage=damage; self.source=source.Entity
                    assert(ignoreBoss==false)
                    if self.raise then error('engine split unavailable') end
                    return self.splitResult
                end
                stock[#stock+1]=n; return n
            end
            p=newPlayer(1)
        ''')
        self.load('sealed_demon_sword')
        self.lua.execute('M=ConchBlessing.sealeddemonsword')

    def test_real_shared_predicate_rejects_furniture_allies_dead_and_inactive(self):
        self.lua.execute('''
            a=npc(); excluded={npc({Type=33}),npc({Type=17}),npc({Type=6}),npc({friendly=true}),
                npc({dead=true}),npc({vulnerable=false}),npc({active=false}),npc({enemy=false}),npc({boss=true})}
            M.onUpdate(); assert(a.calls==1 and a.damage==25 and a.source==p)
            for _,n in ipairs(excluded) do assert(n.calls==0,'ineligible NPC split') end
            M.data.splitBosses=true; M.onUpdate(); assert(excluded[9].calls==1)
        ''')

    def test_late_spawns_split_once_but_halves_do_not(self):
        self.lua.execute('''
            a=npc(); M.onUpdate(); M.onUpdate(); assert(a.calls==1)
            half=npc({MaxHitPoints=40}); late=npc(); M.onUpdate()
            assert(half.calls==0 and late.calls==1)
            champion=npc({champion=2,MaxHitPoints=200}); M.onUpdate()
            championHalf=npc({champion=2,MaxHitPoints=80}); M.onUpdate()
            assert(champion.calls==1 and championHalf.calls==0)
        ''')

    def test_budget_limits_sixty_and_new_room_resets_budget(self):
        self.lua.execute('''
            for i=1,65 do npc() end; M.onUpdate(); M.onUpdate()
            local total=0; for _,n in ipairs(stock) do total=total+n.calls end
            assert(total==60 and #debug==1,'room split budget or warning repeated')
            stock={}; roomIndex=2; M.onNewRoom(); a=npc(); M.onUpdate(); assert(a.calls==1)
        ''')

    def test_failed_missing_and_refused_split_apis_are_not_retried(self):
        self.lua.execute('''
            bad=npc({raise=true}); absent=npc(); absent.TrySplit=nil; refused=npc({splitResult=false})
            M.onUpdate(); M.onUpdate()
            assert(bad.calls==1 and #errors==1 and absent.calls==0 and refused.calls==1)
        ''')

    def test_clear_room_owner_loss_and_coop_acquisition_gate_splitting(self):
        self.lua.execute('''
            a=npc(); roomClear=true; M.onUpdate(); assert(a.calls==0)
            roomClear=false; p.swords=0; M.onUpdate(); assert(a.calls==0)
            b=newPlayer(2); M.onUpdate(); assert(a.calls==1 and a.source==b)
            b.swords=0; late=npc(); M.onUpdate(); assert(late.calls==0)
            b.swords=1; M.onUpdate(); assert(late.calls==1)
        ''')

    def test_base_fallback_once_per_room_and_no_spawner_loop(self):
        self.lua.execute('''
            REPENTOGON=nil; a=npc(); M.onNewRoom(); for i=1,10 do M.onUpdate() end
            assert(p.uses==1 and a.calls==0)
            roomClear=true; M.onNewRoom(); assert(p.uses==1)
            roomClear=false; p.swords=0; M.onNewRoom(); assert(p.uses==1)
        ''')

    def test_actual_monster_predicate_kill_ledger_and_evolution_preserve_tyrfing(self):
        self.lua.execute('''
            saves[p]={sealedDemonSword={killCount=299},tyrfing={accumulatedDamage=17}}
            M.onNPCDeath(nil,npc({Type=33,dead=true})); M.onNPCDeath(nil,npc({friendly=true,dead=true}))
            assert(saves[p].sealedDemonSword.killCount==299)
            p.swords=0; M.onNPCDeath(nil,npc({dead=true})); assert(saves[p].sealedDemonSword.killCount==299)
            p.swords=3; M.onPickup(p); M.onNPCDeath(nil,npc({dead=true,active=false,vulnerable=false}))
            assert(p.swords==0 and p.tyrfing==3 and saves[p].tyrfing.accumulatedDamage==17)
            assert(saves[p].sealedDemonSword==nil)
        ''')

    def test_speed_penalty_applies_once_and_withdraws_without_a_copy(self):
        self.lua.execute('''
            p.swords=5; M.onEvaluateCache(nil,p,4); assert(p.MoveSpeed==0.8)
            p.MoveSpeed=1; p.swords=0; M.onEvaluateCache(nil,p,4); assert(p.MoveSpeed==1)
            p.swords=1; M.onEvaluateCache(nil,p,999); assert(p.MoveSpeed==1)
        ''')


    def test_revisit_and_serialized_continue_preserve_handled_seed_and_half_baseline(self):
        self.lua.execute('''
            a=npc(); M.onUpdate(); local originalSeed=a.InitSeed
            half=npc({MaxHitPoints=40}); M.onUpdate(); assert(half.calls==0)
            stock={}; roomIndex=2; M.onNewRoom(); M.onUpdate()
            roomIndex=1; M.onNewRoom()
            restored=npc({InitSeed=originalSeed}); unseenHalf=npc({MaxHitPoints=40})
            M.onUpdate(); assert(restored.calls==0 and unseenHalf.calls==0)
            function copy(t) local n={}; for k,v in pairs(t) do n[k]=type(v)=='table' and copy(v) or v end; return n end
            roomSaves=copy(roomSaves); stock={}; M.onGameStarted(nil,true)
            restored=npc({InitSeed=originalSeed}); half=npc({MaxHitPoints=40}); fresh=npc()
            M.onUpdate(); assert(restored.calls==0 and half.calls==0 and fresh.calls==1)
        ''')

    def test_virtual_room_storage_cannot_alias_underlying_native_room(self):
        self.lua.execute('''
            a=npc(); M.onUpdate()
            local virtual={PersistentData={}}; providerWrites=0
            StageAPI={InExtraRoom=function() return true end,GetCurrentRoom=function() return virtual end,
                SaveModData=function() providerWrites=providerWrites+1 end}
            stock={}; M.onNewRoom(); virtualNpc=npc({InitSeed=a.InitSeed}); M.onUpdate()
            assert(virtualNpc.calls==1 and providerWrites==1)
            StageAPI=nil; stock={}; M.onNewRoom(); nativeAgain=npc({InitSeed=a.InitSeed}); M.onUpdate()
            assert(nativeAgain.calls==0,'virtual room overwrote native identity')
        ''')

    def test_unavailable_room_save_prevents_untracked_repeated_damage(self):
        self.lua.execute('''
            package.loaded['scripts.lib.save_manager'].GetRoomSave=function() return nil end
            a=npc(); M.onUpdate(); M.onUpdate(); assert(a.calls==0 and #errors==1)
        ''')


    def test_hourglass_table_replacement_after_room_entry_invalidates_cached_ledger(self):
        self.lua.execute('''
            a=npc(); M.onUpdate(); local oldRoom=roomSaves[1]
            M.onNewRoom() -- can precede SaveManager's restore callback
            roomSaves[1]={}; callbacks.hourglass()
            stock={}; restored=npc({InitSeed=a.InitSeed}); M.onUpdate()
            assert(restored.calls==1,'stale future ledger suppressed a rewound original')
            assert(roomSaves[1].__ConchBlessingSealedDemonSword.splits==1)
            assert(oldRoom.__ConchBlessingSealedDemonSword.splits==1,'abandoned room table was mutated')
            M.onUpdate(); assert(restored.calls==1,'rewound target processed twice')
        ''')


class SteroidEdges(ItemFixture):
    def setUp(self):
        super().setUp()
        self.lua.execute('''
            EID=nil; CacheFlag={CACHE_ALL=255,CACHE_DAMAGE=1,CACHE_FIREDELAY=2,CACHE_SPEED=4,CACHE_RANGE=8,CACHE_LUCK=16}
            SoundEffect={SOUND_ISAAC_HURT_GRUNT=1}; writes=0; saves={}; floorSave={}; players={}; events={}
            math.random=function(a,b) return a and 100 or 0.5 end
            RNG=function() return {} end; SFXManager=function() return {Play=function() end} end
            game={GetNumPlayers=function() return #players end,GetSeeds=function() return {GetStartSeedString=function() return 'ABCD EFGH' end} end}
            Game=function() return game end
            function newPlayer()
                local p={Position={},copies=1,MoveSpeed=1,cacheCalls=0,kills=0,invincible=true,shield=true}
                function p:GetPlayerType() return 0 end
                function p:HasCollectible() return self.copies>0 end
                function p:AnimateCollectible() end
                function p:AddCacheFlags() self.cacheCalls=self.cacheCalls+1 end
                function p:EvaluateItems() end
                function p:Kill() self.kills=self.kills+1; events[#events+1]='kill' end
                function p:TakeDamage() error('instant death must not be simulated with damage') end
                players[#players+1]=p; saves[p]={}; return p
            end
            Isaac={GetItemIdByName=function() return 7 end,GetPlayer=function(i) return players[i+1] end}
            package.loaded['scripts.lib.save_manager']={
                GetRunSave=function(p) return saves[p] end,GetFloorSave=function() return floorSave end,Save=function() writes=writes+1 end}
            UM={}
            function UM:RemoveItemAddition(p,id,stat) p.mult=p.mult or {}; p.mult[stat]={} end
            function UM:SetItemAdditiveMultiplier(p,id,stat,value,source)
                p.mult[stat][source]=value; events[#events+1]='reward'
            end
            function UM:SaveToSaveManager() end
            function UM:LoadFromSaveManager(p) p.loaded=true end
            function total(p,stat) local n=1; for _,v in pairs(p.mult[stat]) do n=n+v-1 end; return n end
            ConchBlessing={printDebug=function() end,printError=function(x) events[#events+1]='error' end,
                getUnifiedStatTotal=function(p,stat) return total(p,stat) end,
                stats={unifiedMultipliers=UM,multiplierDisplay={ForceDisplay=function() end},
                speed={applyAddition=function(p,v) p.MoveSpeed=p.MoveSpeed+v end}}}
            p=newPlayer()
        ''')
        self.load('injectable_steroids')
        self.lua.execute('M=ConchBlessing.injectablsteroids; function use() return M.onUseItem(nil,7,nil,p,0,0) end')

    def test_wrong_item_and_invalid_player_do_not_roll_or_reward(self):
        self.lua.execute('''
            math.random=function() error('unexpected RNG') end
            assert(M.onUseItem(nil,8,nil,p)==nil)
            assert(M.onUseItem(nil,7,nil,nil)==nil)
            assert(writes==0 and #events==1 and events[1]=='error')
        ''')

    def test_death_enters_canonical_kill_before_any_stat_reward(self):
        self.lua.execute('''
            math.random=function(a,b) return a and 1 or 0 end
            function p:Kill()
                assert(floorSave.injectableSteroidsRisk.uses==1,'risk not saved before engine death')
                self.kills=self.kills+1; events[#events+1]='kill'
            end
            local result=use()
            assert(result.Discharge and p.kills==1 and #events==1 and events[1]=='kill')
            assert(saves[p].injectableSteroids==nil and writes==1 and floorSave.injectableSteroidsRisk.uses==1)
            assert(M.data.currentInstantDeathPercent==4 and M.data.currentFloorUseCount==1)
        ''')

    def test_success_increments_floor_risk_and_survives_item_loss(self):
        self.lua.execute('''
            assert(use().Discharge); assert(#saves[p].injectableSteroids==1)
            assert(M.data.currentInstantDeathPercent==4 and M.data.currentFloorUseCount==1)
            use(); assert(#saves[p].injectableSteroids==2 and M.data.currentInstantDeathPercent==7)
            p.copies=0; M.onEvaluateCache(nil,p,1)
            for _,stat in ipairs({'Damage','Tears','Range','Luck'}) do assert(total(p,stat)==1.5) end
            assert(p.MoveSpeed==1,'undocumented speed roll applied')
        ''')

    def test_room_clear_quarters_floor_reset_and_absence(self):
        self.lua.execute('''
            use(); M.onRoomClear(); assert(M.data.currentInstantDeathPercent==3.75)
            p.copies=0; M.onRoomClear(); assert(M.data.currentInstantDeathPercent==3.75)
            p.copies=1; for i=1,40 do M.onRoomClear() end
            assert(M.data.currentInstantDeathPercent==1)
            use(); M.onNewLevel(); assert(M.data.currentInstantDeathPercent==1 and M.data.currentFloorUseCount==0)
            assert(#saves[p].injectableSteroids==2,'floor reset erased earned stats')
        ''')

    def test_roll_boundaries_and_additive_floor_with_removal(self):
        self.lua.execute('''
            math.random=function() return 0 end
            local rng={RandomFloat=function() return 0.99 end}
            use=function() return M.onUseItem(nil,7,rng,p,0,0) end
            assert(M.rollStat()==0.5)
            use(); use(); use(); use()
            for _,stat in ipairs({'Damage','Tears','Range','Luck'}) do assert(total(p,stat)==0.25) end
            local before=p.cacheCalls; M.removeLastUse(p,3,false)
            assert(#saves[p].injectableSteroids==1 and p.cacheCalls==before)
            for _,stat in ipairs({'Damage','Tears','Range','Luck'}) do assert(total(p,stat)==0.5) end
            M.removeLastUse(p,999,true); assert(#saves[p].injectableSteroids==0 and p.cacheCalls==before+1)
            for _,stat in ipairs({'Damage','Tears','Range','Luck'}) do assert(total(p,stat)==1) end
            math.random=function() return 0.999999 end; assert(M.rollStat()==1.99)
        ''')

    def test_remove_zero_negative_absent_and_nil_are_noops(self):
        self.lua.execute('''
            M.removeLastUse(nil,1); M.removeLastUse(p,0); M.removeLastUse(p,-5)
            M.removeLastUse(p,1); assert(writes==0 and p.cacheCalls==0)
        ''')

    def test_restore_saved_arrays_does_not_rescale_or_repeat_rolls(self):
        self.lua.execute('''
            use(); use(); p.copies=0
            math.random=function() error('restore rolled a new multiplier') end
            p.mult={}; M.onGameStarted(nil,true)
            for _,stat in ipairs({'Damage','Tears','Range','Luck'}) do assert(total(p,stat)==1.5) end
            M.onGameStarted(nil,true)
            for _,stat in ipairs({'Damage','Tears','Range','Luck'}) do assert(total(p,stat)==1.5) end
        ''')


    def test_death_probability_respects_fractional_percent_and_exact_boundary(self):
        self.lua.execute('''
            M.data.currentInstantDeathPercent=3.75
            math.random=function() return 0.5 end
            local rng={RandomFloat=function() return 0.03749 end}
            M.onUseItem(nil,7,rng,p,0,0)
            assert(p.kills==1 and saves[p].injectableSteroids==nil)
            M.data.currentInstantDeathPercent=3.75
            rng.RandomFloat=function() return 0.0375 end
            M.onUseItem(nil,7,rng,p,0,0)
            assert(p.kills==1 and #saves[p].injectableSteroids==1,'boundary used <= instead of <')
        ''')

    def test_floor_risk_serialization_restore_new_floor_and_fallback_rng(self):
        self.lua.execute('''
            use(); M.onRoomClear()
            assert(floorSave.injectableSteroidsRisk.chance==3.75 and floorSave.injectableSteroidsRisk.uses==1)
            M.data.currentInstantDeathPercent=999; M.data.currentFloorUseCount=999
            M.onGameStarted(nil,true)
            assert(M.data.currentInstantDeathPercent==3.75 and M.data.currentFloorUseCount==1)
            math.random=function() return 0 end
            M.onUseItem(nil,7,{RandomFloat=function() error('unsupported RNG') end},p,0,0)
            assert(p.kills==1 and floorSave.injectableSteroidsRisk.chance==6.75)
            floorSave={}; M.onNewLevel()
            assert(floorSave.injectableSteroidsRisk.chance==1 and floorSave.injectableSteroidsRisk.uses==0)
        ''')

    def test_second_coop_holder_clears_shared_risk_without_first_player_item(self):
        self.lua.execute('''
            use(); p.copies=0; q=newPlayer(); M.onRoomClear()
            assert(M.data.currentInstantDeathPercent==3.75)
        ''')


    def test_rng_probe_measures_shipped_fractional_death_function_without_gameplay(self):
        self.lua.execute('''
            lines={}; Isaac.ConsoleOutput=function(x) lines[#lines+1]=x end
            Isaac.DebugString=function() end
            require('scripts.dev.rng_probe').injectableDeath()
            local passes=0
            for _,line in ipairs(lines) do
                assert(not line:find('FAIL'),'RNG probe predicate failure: '..line)
                if line:find('PASS death predicate') then passes=passes+1 end
            end
            assert(passes==8 and p.kills==0 and writes==0 and next(floorSave)==nil)
        ''')


class FlameEdges(ItemFixture):
    def setUp(self):
        super().setUp()
        self.lua.execute('''
            CacheFlag={CACHE_DAMAGE=1,CACHE_FIREDELAY=2,CACHE_SPEED=4}
            LevelCurse={NONE=0,DARKNESS=1,LABYRINTH=2,LOST=4,UNKNOWN=8,CURSED=16,MAZE=32,BLIND=64,GIANT=128,NUM_CURSES=9}
            EntityType={ENTITY_EFFECT=1000}; Vector={Zero={}}
            curses=0; saves={}; players={}; writes=0; spawned={}
            level={GetCurses=function() return curses end,RemoveCurses=function(_,mask) curses=curses&(~mask) end}
            Game=function() return {GetLevel=function() return level end,GetNumPlayers=function() return #players end} end
            Isaac={GetItemIdByName=function() return 7 end,GetPlayer=function(i) return players[i+1] end,
                Spawn=function()
                    local e={alive=true}
                    function e:GetSprite() return {Load=function() end,Play=function() end} end
                    function e:SetTimeout(n) self.timeout=n end
                    function e:Exists() return self.alive end
                    function e:Remove() self.alive=false end
                    spawned[#spawned+1]=e; return e
                end}
            package.loaded['scripts.lib.save_manager']={GetRunSave=function(p) saves[p]=saves[p] or {}; return saves[p] end,
                Save=function() writes=writes+1 end}
            ConchBlessing={printDebug=function() end,stats={damage={applyAddition=function(p,x) p.Damage=p.Damage+x end},
                tears={applyAddition=function(p,x) p.Tears=p.Tears+x end}}}
            function newPlayer(copies)
                local p={copies=copies,hearts=0,Position={}}
                function p:GetCollectibleNum() return self.copies end
                function p:HasCollectible() return self.copies>0 end
                function p:AddCacheFlags() end
                function p:AddEternalHearts(n) self.hearts=self.hearts+n end
                function p:EvaluateItems()
                    self.Damage,self.Tears=3.5,3
                    M.onEvaluateCache(nil,self,1); M.onEvaluateCache(nil,self,2)
                end
                players[#players+1]=p; return p
            end
        ''')
        self.load('eternal_flame')
        self.lua.execute('M=ConchBlessing.eternalflame; p=newPlayer(1); function ticks(n) for i=1,n do M.onUpdate() end end')

    def test_pickup_cache_reentry_and_continue_cannot_duplicate_eternal_heart(self):
        self.lua.execute('''
            M.onPickup(p); p:EvaluateItems(); assert(p.hearts==1)
            for i=1,10 do M.onEvaluateCache(nil,p,4); p:EvaluateItems(); M.onNewRoom() end
            p.copies=0; p:EvaluateItems(); p.copies=5; M.onPickup(p); p:EvaluateItems()
            M.onGameStarted(nil,true); assert(p.hearts==1 and p.Damage==3.5 and p.Tears==3)
        ''')

    def test_each_curse_bit_including_unknown_bits_earns_once(self):
        self.lua.execute('''
            M.onGameStarted()
            for i=0,10 do
                curses=1<<i; ticks(32)
                assert(curses==0 and saves[p].eternalFlame.earnedUnits==i+1,'curse bit '..i)
                M.onNewRoom(); ticks(40)
                assert(saves[p].eternalFlame.earnedUnits==i+1,'reentry paid twice')
            end
            assert(p.Damage==36.5 and p.Tears==14)
        ''')

    def test_pending_curse_removed_externally_earns_nothing(self):
        self.lua.execute('''
            M.onGameStarted(); curses=3; ticks(1); curses=0; ticks(31)
            assert(saves[p].eternalFlame.earnedUnits==0 and #spawned==0)
            assert(M.data.curseRemovalTimer==nil and M.data.pendingCurses==nil)
        ''')

    def test_last_holder_lost_during_delay_cancels_without_payment(self):
        self.lua.execute('''
            M.onGameStarted(); curses=1; ticks(1); p.copies=0; ticks(40)
            assert(curses==1 and saves[p].eternalFlame.earnedUnits==0)
            p.copies=2; M.onPickup(p); ticks(31)
            assert(curses==0 and saves[p].eternalFlame.earnedUnits==2)
        ''')

    def test_current_copies_and_actual_removed_mask_define_nonretroactive_award(self):
        self.lua.execute('''
            M.onGameStarted(); curses=1; ticks(1)
            p.copies=3; curses=7; ticks(30)
            assert(saves[p].eternalFlame.earnedUnits==9)
            p.copies=1; p:EvaluateItems(); assert(p.Damage==30.5 and p.Tears==12)
            p.copies=0; M.onGameStarted(nil,true); assert(p.Damage==30.5 and p.Tears==12)
        ''')

    def test_effect_timeout_removed_entity_and_new_run_cleanup(self):
        self.lua.execute('''
            M.onGameStarted(); curses=1; ticks(31)
            assert(#spawned==1 and spawned[1].timeout==60 and #M.activeEffects==1)
            ticks(59); assert(spawned[1].alive); ticks(1)
            assert(not spawned[1].alive and #M.activeEffects==0)
            curses=2; ticks(32); spawned[2].alive=false; ticks(1); assert(#M.activeEffects==0)
            saves[p]={}; M.onGameStarted(nil,false)
            assert(p.Damage==3.5 and p.Tears==3 and M.data.pendingCurses==nil)
        ''')


if __name__ == '__main__':
    unittest.main()
