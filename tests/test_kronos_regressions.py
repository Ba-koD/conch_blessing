"""Kronos lifecycle regressions with production Lua and narrow engine doubles.

These checks exercise callback ordering and conversion ownership. They do not
claim to reproduce native enemy initialization, aura behavior, or game Continue.
"""
import unittest

import test_kronos_room_effects as kronos_tests


class KronosRewardOrderingTests(unittest.TestCase):
    def setUp(self):
        kronos_tests.KronosRoomEffectsTests.setUp(self)
        self.lua.execute("""
            spawnedRewards={}
            function player:Exists() return true end
            function player:ToPlayer() return self end
            function player:GetCollectibleRNG()
                return {Next=function() return 123 end,RandomFloat=function() return 0.999 end}
            end
        """)
        self.lua.execute("""
            Game().GetRoom().FindFreePickupSpawnPosition=function(_,position) return position end
            Game().Spawn=function(_,kind,variant,position,velocity,owner,subtype,seed)
                assert(kind==EntityType.ENTITY_PICKUP and variant==PickupVariant.PICKUP_HEART)
                assert(subtype==HeartSubType.HEART_ETERNAL and seed~=0)
                spawnedRewards[#spawnedRewards+1]={kind=kind,variant=variant,subtype=subtype}
            end
            absorb('LOST_SOUL',2)
            K.onGameStarted()
        """)

    def test_room_before_level_pays_first_update_without_another_room(self):
        self.lua.execute("""
            K.onNewRoom(); assert(#spawnedRewards==0)
            K.onNewLevel(); assert(run.kronos.lostSoulRewardPending==2)
            K.onPostUpdate()
            assert(#spawnedRewards==2 and run.kronos.lostSoulRewardPending==nil)
            assert(savedRun.kronos.lostSoulRewardPending==nil)
            K.onPostUpdate(); K.onNewRoom(); assert(#spawnedRewards==2)
        """)

    def test_opposite_callback_order_cannot_pay_twice(self):
        self.lua.execute("""
            K.onNewLevel(); K.onNewRoom(); assert(#spawnedRewards==2)
            K.onPostUpdate(); K.onNewRoom(); assert(#spawnedRewards==2)
        """)

    def test_confirmed_hit_only_cancels_the_current_floor_reward(self):
        self.lua.execute("""
            K.onNewRoom(); K.onNewLevel(); K.onPostUpdate()
            K.onPostEntityTakeDamage(nil,player,1,0,nil,0,nil)
            K.onPostUpdate()
            assert(run.kronos.hurtSerial==run.kronos.floorSerial)
            K.onNewRoom(); K.onNewLevel(); K.onPostUpdate()
            assert(#spawnedRewards==2,'hit floor paid an extra reward')
            K.onNewRoom(); K.onNewLevel(); K.onPostUpdate()
            assert(#spawnedRewards==4,'later clean floor did not recover')
        """)

    def test_saved_pending_reward_survives_start_and_drains_once(self):
        self.lua.execute("""
            K.onNewLevel()
            K.onPreGameExit()
            K.onPostUpdate(); assert(#spawnedRewards==0)
            K.onGameStarted(); K.onPostUpdate()
            assert(#spawnedRewards==2 and run.kronos.lostSoulRewardPending==nil)
            K.onGameStarted(); K.onPostUpdate(); assert(#spawnedRewards==2)
        """)

    def test_removing_kronos_cancels_its_unpaid_absorption_reward(self):
        self.lua.execute("""
            K.onNewLevel(); assert(run.kronos.lostSoulRewardPending==2)
            player:RemoveCollectible(9999); K._revertAll(player)
            K.onPostUpdate(); assert(#spawnedRewards==0)
            player:AddCollectible(9999); K.onGameStarted(); K.onPostUpdate()
            assert(#spawnedRewards==0)
        """)

    def test_box_multiplier_does_not_inflate_next_floor_reward(self):
        self.lua.execute("""
            useBox(); useBox()
            K.onNewRoom(); K.onNewLevel(); K.onPostUpdate()
            assert(#spawnedRewards==2,'room multiplier leaked into floor reward')
        """)


class KronosConversionOwnershipTests(unittest.TestCase):
    setUp = kronos_tests.KronosRoomEffectsTests.setUp

    def test_seraphim_removal_returns_familiars_and_preserves_original_heart(self):
        self.lua.execute("""
            local heart=CollectibleType.COLLECTIBLE_SACRED_HEART
            player:AddCollectible(heart)
            local fam=absorb('SERAPHIM',1)
            K._handleFamiliarToItemConversion(player,fam,1,1)
            assert(player:GetCollectibleNum(heart)==2)
            run.kronos.absorbed['fam_'..fam].count=2
            run.kronos.totalAbsorbed=2
            K._handleFamiliarToItemConversion(player,fam,2,1)
            assert(player:GetCollectibleNum(heart)==2,'grant cap duplicated Sacred Heart')
            local evaluate=player.EvaluateItems
            local recached=false
            function player:AddCacheFlags(flags)
                self.dirtyCaches=(self.dirtyCaches or 0)|flags
            end
            function player:EvaluateItems()
                if self.dirtyCaches==CacheFlag.CACHE_ALL then
                    recached=self:GetCollectibleNum(heart)==1 and run.kronos.totalAbsorbed==0
                        and next(run.kronos.itemGrants)==nil
                end
                evaluate(self)
            end
            player:RemoveCollectible(9999); K._revertAll(player)
            assert(player:GetCollectibleNum(heart)==1,'original Sacred Heart was removed')
            assert(player:GetCollectibleNum(fam)==2)
            assert(recached,'converted item caches did not observe the final inventory and ledger')
            K._revertAll(player)
            assert(player:GetCollectibleNum(heart)==1 and player:GetCollectibleNum(fam)==2)
            assert(damageBonus()==0)
        """)


if __name__ == '__main__':
    unittest.main()
