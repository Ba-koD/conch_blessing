"""Execute cleanup/target fixtures; these doubles do not establish engine behavior."""
import unittest
import test_item_bench as shared


class CleanupContracts(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua

    def setUp(self):
        shared.BenchTests.setUp(self)
        self.run_lua('''
            EntityType={ENTITY_PLAYER=1,ENTITY_PICKUP=5,ENTITY_EFFECT=1000}
            ItemType={ITEM_ACTIVE=3}; CacheFlag={CACHE_ALL=1}
            entities={}; inventory={}; charge={}; frame=0
            player.Damage=3.5; player.MaxFireDelay=9; player.TearRange=260
            player.Luck=0; player.MoveSpeed=1; player.ShotSpeed=1
            player.CanFly=false; player.TearFlags=0; player.hash=1
            GetPtrHash=function(e) return e.hash end
            for _,method in ipairs({'GetTrinket','GetActiveItem','GetBatteryCharge','GetNumCoins',
                'GetNumBombs','GetNumKeys','GetHearts','GetMaxHearts','GetSoulHearts','GetBlackHearts'}) do
                player[method]=function() return 0 end
            end
            for _,method in ipairs({'AddCoins','AddBombs','AddKeys','AddHearts','AddMaxHearts','AddCacheFlags','EvaluateItems'}) do
                player[method]=function() end
            end
            player.GetActiveCharge=function(_,slot) return charge[slot] or 0 end
            player.SetActiveCharge=function(_,value,slot) charge[slot]=value end
            player.GetCollectibleNum=function(_,id) return inventory[id] or 0 end
            player.RemoveCollectible=function(_,id) inventory[id]=0 end
            player.HasCollectible=function(_,id) return (inventory[id] or 0)>0 end
            player.GetEffects=function() return {GetEffectsList=function() return {Size=0} end} end
            player.GetData=function() return {} end
            player.IsDead=function() return false end
            player.IsItemQueueEmpty=function() return true end
            Isaac.GetItemConfig=function() return {GetCollectibles=function() return {Size=10} end} end
            Isaac.GetRoomEntities=function()
                local live={}; for _,e in ipairs(entities) do if e.alive then live[#live+1]=e end end; return live
            end
            local room={IsClear=function() return true end}
            local level={GetStage=function() return 1 end,GetCurrentRoomDesc=function() return {ListIndex=80} end,
                GetDimension=function() return 0 end}
            Game=function() return {GetRoom=function() return room end,GetLevel=function() return level end,
                GetFrameCount=function() return frame end} end
            ConchBlessing.getUnifiedMultiplierState=function() return {} end
            function entity(hash,kind,seed)
                local e={hash=hash,Type=kind,Variant=1,SubType=2,InitSeed=seed,alive=true,
                    OptionsPickupIndex=7,Price=0,ShopItemId=-1,AutoUpdatePrice=false,shop=false}
                function e:IsShopItem() return self.shop end
                function e:ToPickup() if self.Type==5 then return self end end
                function e:Remove() self.alive=false; if self.onRemove then self.onRemove() end end
                function e:Exists() return self.alive end
                entities[#entities+1]=e;return e
            end
            H=require('scripts.dev.item_test_support')
            Isolation=require('scripts.dev.test_isolation')
            ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE,function()
                frame=frame+1
                for _,e in ipairs(entities) do if e.untilFrame and frame>=e.untilFrame then e.alive=false end end
            end)
            function scenario(change)
                bench.register({command='cleanup',reuseGroup='fixture',cleanup=H.cleanup,build=function(p)
                    Isolation.begin(p,true);p.act(change);Isolation.finish(p,'CEIL',9)
                end})
                bench.start('cleanup',true);drain()
            end
        ''')

    def test_empty_pocket_charge_is_restored_as_fixture_state(self):
        self.run_lua('''
            scenario(function() charge[2]=3 end)
            assert(charge[2]==0 and #restarts==1,output())
        ''')

    def test_empty_slot_charge_uses_guarded_descriptor_when_setter_is_a_noop(self):
        self.run_lua('''
            player.SetActiveCharge=function() end -- native empty-slot no-op
            player.GetActiveItemDesc=function(_,slot)
                return setmetatable({Item=0,BatteryCharge=0}, {
                    __index=function(_,key) if key=='Charge' then return charge[slot] or 0 end end,
                    __newindex=function(t,key,value)
                        if key=='Charge' then charge[slot]=value else rawset(t,key,value) end
                    end})
            end
            scenario(function() charge[2]=3 end)
            assert(charge[2]==0 and #restarts==1,output())
        ''')

    def test_unsupported_empty_slot_restore_blocks_reuse_instead_of_passing(self):
        self.run_lua('''
            player.SetActiveCharge=function() end
            scenario(function() charge[2]=3 end)
            assert(charge[2]==3 and #restarts==2,output())
            assert(output():find('active slot 2',1,true),output())
        ''')

    def test_native_pickup_rebind_preserves_same_identity_and_does_not_delete_it(self):
        self.run_lua('''
            local original=entity(2,5,200);local restored
            scenario(function() original.alive=false;restored=entity(3,5,200) end)
            assert(restored.alive and #restarts==1,output())
        ''')

    def test_changed_pickup_contract_is_not_accepted_by_equal_pointer_or_seed(self):
        self.run_lua('''
            local original=entity(2,5,200)
            scenario(function() original.OptionsPickupIndex=0 end)
            assert(#restarts==2 and output():find('baseline entity disappeared: 5:1:2:200:7',1,true),output())
        ''')

    def test_deferred_visual_must_expire_naturally_before_reuse(self):
        self.run_lua('''
            local effect
            scenario(function()
                local fixture=entity(2,5,200)
                fixture.onRemove=function() effect=entity(3,1000,300);effect.untilFrame=frame+8 end
            end)
            assert(not effect.alive and #restarts==1,output())
        ''')

    def test_automatic_price_drift_blocks_reuse_even_when_price_is_unchanged(self):
        self.run_lua('''
            local original=entity(2,5,200)
            scenario(function() original.AutoUpdatePrice=true end)
            assert(#restarts==2 and output():find('baseline entity disappeared:',1,true),output())
        ''')

    def test_shop_contract_drift_blocks_reuse_even_when_id_and_price_match(self):
        self.run_lua('''
            local original=entity(2,5,200)
            scenario(function() original.shop=true end)
            assert(#restarts==2 and output():find('baseline entity disappeared:',1,true),output())
        ''')

    def test_persistent_respawn_is_not_deleted_to_manufacture_clean_baseline(self):
        self.run_lua('''
            local orphan
            scenario(function()
                local fixture=entity(2,5,200)
                fixture.onRemove=function() orphan=entity(3,1000,300) end
            end)
            assert(orphan.alive and #restarts==2,output())
            assert(output():find('orphan gameplay entity: 1000:1:2:300 ptr=3',1,true),output())
        ''')

    def test_long_native_removal_visual_settles_without_repeated_deletion(self):
        self.run_lua('''
            local visual
            scenario(function()
                local fixture=entity(2,5,200)
                fixture.onRemove=function() visual=entity(3,1000,300);visual.untilFrame=frame+80 end
            end)
            assert(not visual.alive and #restarts==1,output())
        ''')


class TargetContracts(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua

    def setUp(self):
        shared.BenchTests.setUp(self)
        self.run_lua('''
            EntityType={ENTITY_ATTACKFLY=18,ENTITY_MAGGOT=21}; EntityFlag={FLAG_APPEAR=1}
            EntityCollisionClass={ENTCOLL_NONE=0,ENTCOLL_ALL=4}
            local vector={__add=function(a,b) return a end}
            Vector=setmetatable({Zero={}}, {__call=function() return setmetatable({},vector) end})
            player.Position=Vector(); targets={}; kills=0
            GetPtrHash=function(e) return e.hash end
            EntityRef=function(e) return {Entity=e} end
            ModCallbacks.MC_POST_ENTITY_KILL=51;ModCallbacks.MC_POST_ENTITY_REMOVE=52
            Isaac.Spawn=function()
                local e={FrameCount=0,alive=true,ready=false,data={},hash=#targets+1,InitSeed=#targets+101}
                function e:ToNPC() return self end
                function e:GetData() return self.data end
                function e:ClearEntityFlags() end
                function e:Exists() return self.alive end
                function e:IsDead() return self.dead==true end
                function e:IsActiveEnemy() return self.ready end
                function e:IsVulnerableEnemy() return self.ready and self.EntityCollisionClass~=0 end
                function e:Kill() error('fixture must use actual lethal damage') end
                function e:TakeDamage(amount,flags,ref)
                    assert(self.ready and self.FrameCount>0 and ref.Entity==player and amount>self.HitPoints)
                    kills=kills+1
                    if self.reject then return false end
                    self.HitPoints=self.HitPoints-amount
                    return true
                end
                function e:Remove() self.alive=false;dispatch(ModCallbacks.MC_POST_ENTITY_REMOVE,self) end
                targets[#targets+1]=e;return e
            end
            H=require('scripts.dev.item_test_support')
        ''')

    def test_kill_waits_for_initialization_and_each_real_death_is_observed(self):
        self.run_lua('''
            local a,b={},{};H.killTarget(player,a);H.killTarget(player,b)
            for _,e in ipairs(targets) do assert(e.EntityCollisionClass==4 and e.CollisionDamage==0) end
            assert(kills==0 and not H.deathObserved(nil,a))
            dispatch(ModCallbacks.MC_POST_UPDATE);assert(kills==0)
            for _,e in ipairs(targets) do e.FrameCount=1;e.ready=true end
            dispatch(ModCallbacks.MC_POST_UPDATE)
            assert(kills==2 and not H.deathObserved(nil,a) and not H.deathObserved(nil,b))
            dispatch(ModCallbacks.MC_POST_ENTITY_KILL,targets[1])
            assert(not H.deathObserved(nil,a),'kill alone is not completed NPC death')
            for _,e in ipairs(targets) do dispatch(ModCallbacks.MC_POST_NPC_DEATH,e) end
            assert(H.deathObserved(nil,a) and H.deathObserved(nil,b))
            dispatch(ModCallbacks.MC_POST_UPDATE);assert(kills==2)
        ''')

    def test_cancelled_damage_and_removal_keep_failure_evidence_without_retrying(self):
        self.run_lua('''
            local ctx={};H.killTarget(player,ctx)
            local npc=targets[1];npc.FrameCount=1;npc.ready=true;npc.reject=true
            dispatch(ModCallbacks.MC_POST_UPDATE)
            local ok,detail=H.deathObserved(nil,ctx)
            assert(not ok and detail:find('accepted=false',1,true),detail)
            dispatch(ModCallbacks.MC_POST_UPDATE);assert(kills==1)
            npc:Remove()
            ok,detail=H.deathObserved(nil,ctx)
            assert(not ok and detail:find('removeEvent=true',1,true),detail)
            H.cleanup(ctx);assert(not H.deathObserved(nil,ctx))
        ''')

    def test_removed_target_is_not_a_death_and_cleanup_cancels_pending_kills(self):
        self.run_lua('''
            local a,b={},{};H.killTarget(player,a);H.killTarget(player,b)
            targets[1]:Remove();H.cleanup(b)
            for _,e in ipairs(targets) do e.FrameCount=1;e.ready=true end
            dispatch(ModCallbacks.MC_POST_UPDATE)
            assert(kills==0 and not H.deathObserved(nil,a) and not H.deathObserved(nil,b))
        ''')

    def test_instant_lethal_hit_needs_both_native_kill_and_removal(self):
        self.run_lua('''
            local ctx={};H.killTarget(player,ctx)
            local npc=targets[1];npc.FrameCount=1;npc.ready=true
            dispatch(ModCallbacks.MC_POST_UPDATE)
            dispatch(ModCallbacks.MC_POST_ENTITY_KILL,npc)
            assert(not H.deathObserved(nil,ctx),'kill alone must not complete the fixture')
            npc:Remove()
            local ok,detail=H.deathObserved(nil,ctx)
            assert(ok and detail:find('npcDeathEvents=0',1,true),detail)
        ''')

    def test_death_identity_survives_lost_data_but_rejects_copied_tags_and_reused_pointers(self):
        self.run_lua('''
            local ctx={};H.killTarget(player,ctx)
            local npc=targets[1]
            local impostor=Isaac.Spawn();impostor.data=npc.data
            dispatch(ModCallbacks.MC_POST_NPC_DEATH,impostor)
            assert(not H.deathObserved(nil,ctx),'copied marker counted as target death')
            impostor.hash=npc.hash
            dispatch(ModCallbacks.MC_POST_NPC_DEATH,impostor)
            assert(not H.deathObserved(nil,ctx),'reused pointer with different seed matched')
            npc.data={}
            dispatch(ModCallbacks.MC_POST_NPC_DEATH,npc)
            assert(H.deathObserved(nil,ctx),'death identity depended on GetData surviving')
        ''')

    def test_successful_lethal_fixture_does_not_pass_missing_item_reward(self):
        self.run_lua('''
            ConchBlessing.SaveManager={GetRunSave=function() return {tyrfing={accumulatedDamage=0}} end}
            bench.register({command='reward',cleanup=H.cleanup,build=function(p)
                H.kill(p,'tyrfing','accumulatedDamage',0.05)
            end})
            ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE,function()
                for _,npc in ipairs(targets) do
                    npc.FrameCount=1;npc.ready=true
                    if npc.alive and npc.HitPoints<0 then
                        dispatch(ModCallbacks.MC_POST_ENTITY_KILL,npc);npc:Remove()
                    end
                end
            end)
            bench.start('reward',false);drain()
            assert(output():find('PASS native enemy death confirmed independently',1,true),output())
            assert(output():find('FAIL real enemy death contribution (actual=0 expected=0.05)',1,true),output())
        ''')

    def test_room_unload_cannot_complete_or_execute_an_old_kill_fixture(self):
        self.run_lua('''
            local ctx={};H.killTarget(player,ctx)
            local npc=targets[1];npc.FrameCount=1;npc.ready=true
            dispatch(ModCallbacks.MC_POST_NEW_ROOM)
            dispatch(ModCallbacks.MC_POST_UPDATE)
            assert(kills==0,'queued kill survived a room boundary')
            dispatch(ModCallbacks.MC_POST_ENTITY_KILL,npc);npc:Remove()
            dispatch(ModCallbacks.MC_POST_NPC_DEATH,npc)
            local ok,detail=H.deathObserved(nil,ctx)
            assert(not ok and detail:find('room changed',1,true),detail)
        ''')


if __name__ == '__main__':
    unittest.main()
