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
            K.onNewLevel(); assert(per.kronos.lostSoulRewardPending==2)
            K.onPostUpdate()
            assert(#spawnedRewards==2 and per.kronos.lostSoulRewardPending==nil)
            assert(savedPer.kronos.lostSoulRewardPending==nil)
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
            assert(per.kronos.hurtSerial==per.kronos.floorSerial)
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
            assert(#spawnedRewards==2 and per.kronos.lostSoulRewardPending==nil)
            K.onGameStarted(); K.onPostUpdate(); assert(#spawnedRewards==2)
        """)

    def test_removing_kronos_cancels_its_unpaid_absorption_reward(self):
        self.lua.execute("""
            K.onNewLevel(); assert(per.kronos.lostSoulRewardPending==2)
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
            per.kronos.absorbed['fam_'..fam].count=2
            per.kronos.totalAbsorbed=2
            K._handleFamiliarToItemConversion(player,fam,2,1)
            assert(player:GetCollectibleNum(heart)==2,'grant cap duplicated Sacred Heart')
            local evaluate=player.EvaluateItems
            local recached=false
            function player:AddCacheFlags(flags)
                self.dirtyCaches=(self.dirtyCaches or 0)|flags
            end
            function player:EvaluateItems()
                if self.dirtyCaches==CacheFlag.CACHE_ALL then
                    recached=self:GetCollectibleNum(heart)==1 and per.kronos.totalAbsorbed==0
                        and next(per.kronos.itemGrants)==nil
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


class KronosPerPlayerLedgerTests(unittest.TestCase):
    """Every player owns their own Kronos ledger (co-op, an added second player,
    Strawman). Doubles key run saves and StatsAPI state by player, as the
    providers do; they do not prove the engine's addplayer or entity removal."""

    def setUp(self):
        kronos_tests.KronosRoomEffectsTests.setUp(self)
        self.lua.execute("""
            C=CollectibleType
            BOBBY,ANGEL,ROBO,TECH=C.COLLECTIBLE_BROTHER_BOBBY,C.COLLECTIBLE_GUARDIAN_ANGEL,
                C.COLLECTIBLE_ROBO_BABY,C.COLLECTIBLE_TECHNOLOGY
            -- The familiar collectibles the inventory sweep may absorb.
            local familiarIds={[BOBBY]=true,[ANGEL]=true,[ROBO]=true,[C.COLLECTIBLE_GB_BUG]=true}
            Isaac.GetItemConfig=function()
                return {GetCollectible=function(_,id)
                    if familiarIds[id] then return {ID=id,Type=ItemType.ITEM_FAMILIAR} end
                end}
            end
            K._familiarCollectibleIds=nil
            local function rng()
                return {Next=function() return 123 end,RandomFloat=function() return 0.999 end,
                    RandomInt=function() return 0 end}
            end
            local function newEffects()
                local e={GetEffectsList=function() return {Size=0} end}
                function e:GetCollectibleEffectNum(id) return self[id] or 0 end
                function e:AddCollectibleEffect(id,_,count) self[id]=(self[id] or 0)+count end
                return e
            end
            function player:GetCollectibleRNG() return rng() end
            function player:ToPlayer() return self end
            two=makePlayer({hash=2,inventory={[9999]=1},effects=newEffects(),Position=Vector(7,8)})
            function two:GetCollectibleRNG() return rng() end
            function two:ToPlayer() return self end
            players={player,two}
            -- These cases run inside a started run, as MC_POST_GAME_STARTED leaves it.
            K._runReady=true
            function update(p) frameCount=(frameCount or 0)+1; K.onPlayerUpdate(nil,p) end
            function ledger(p) local s=runSaves[GetPtrHash(p)]; return s and s.kronos end
            spawned={}
            Game().GetRoom().FindFreePickupSpawnPosition=function(_,position) return position end
            Game().Spawn=function(_,kind,variant,position,velocity,owner,subtype,seed)
                spawned[#spawned+1]={variant=variant,subtype=subtype,position=position}
            end
        """)

    def test_a_player_update_before_game_start_absorbs_nothing(self):
        # MC_POST_PLAYER_UPDATE can run before MC_POST_GAME_STARTED, while an older
        # save's shared ledger has not moved yet.
        self.lua.execute("""
            K._runReady=false
            player:AddCollectible(BOBBY)
            for _=1,3 do update(player) end
            assert(player:GetCollectibleNum(BOBBY)==1,'absorbed before game start')
            assert(K._getAbsorbedCount(player,BOBBY)==0)
            K._runReady=true
            update(player)
            assert(player:GetCollectibleNum(BOBBY)==0 and K._getAbsorbedCount(player,BOBBY)==1)
        """)

    def test_the_soul_uses_the_forgottens_ledger(self):
        # The Soul is a sub-player: its own entity, outside the player list, with
        # The Forgotten's inventory.
        self.lua.execute("""
            soul=makePlayer({hash=3,inventory=player.inventory,effects=player.effects})
            function soul:ToPlayer() return self end
            function player:GetSubPlayer() return soul end
            player:AddCollectible(BOBBY)
            update(soul)
            assert(player:GetCollectibleNum(BOBBY)==1,'the sub-player scanned')
            update(player)
            assert(K._getAbsorbedCount(player,BOBBY)==1)
            assert(K._getAbsorbedCount(soul,BOBBY)==1,'the Soul reads its own ledger')
            assert(K._getLedger(soul)==K._getLedger(player))
        """)

    def test_each_holder_absorbs_only_their_own_familiars_and_damage(self):
        self.lua.execute("""
            player:AddCollectible(BOBBY); two:AddCollectible(ANGEL)
            update(player); update(two); update(player); update(two)
            assert(K._getAbsorbedCount(player,BOBBY)==1 and K._getAbsorbedCount(player,ANGEL)==0)
            assert(K._getAbsorbedCount(two,ANGEL)==1 and K._getAbsorbedCount(two,BOBBY)==0)
            assert(player:GetCollectibleNum(BOBBY)==0 and two:GetCollectibleNum(ANGEL)==0)
            assert(ledger(player)~=ledger(two) and run.kronos==nil,'no shared ledger')
            near(damageBonus(player),2); near(damageBonus(two),2)
            player:EvaluateItems(); two:EvaluateItems()
            near(player.Tears,30/11+2); near(player.MoveSpeed,1)
            near(two.Tears,30/11); near(two.MoveSpeed,1.3)
        """)

    def test_another_holders_inventory_never_reads_as_a_lost_conversion(self):
        self.lua.execute("""
            player:AddCollectible(ROBO); update(player)
            assert(player:GetCollectibleNum(TECH)==1 and ledger(player).itemGrants['fam_'..ROBO]==1)
            two:AddCollectible(BOBBY)
            for _=1,3 do update(two); update(player) end
            assert(K._getAbsorbedCount(player,ROBO)==1,'the other holder made the grant look removed')
            assert(ledger(player).itemGrants['fam_'..ROBO]==1 and ledger(two).itemGrants['fam_'..ROBO]==nil)
            assert(two:GetCollectibleNum(TECH)==0)
            -- A real loss is charged to the ledger whose grant it was.
            player:RemoveCollectible(TECH); update(player); update(two)
            assert(K._getAbsorbedCount(player,ROBO)==0 and K._getAbsorbedCount(two,BOBBY)==1)
            near(damageBonus(player),0); near(damageBonus(two),2)
        """)

    def test_losing_kronos_hands_back_only_that_players_own_ledger(self):
        self.lua.execute("""
            player:AddCollectible(BOBBY); two:AddCollectible(ANGEL)
            update(player); update(two)
            player:RemoveCollectible(9999); update(player); update(two)
            assert(player:GetCollectibleNum(BOBBY)==1,'returned although another player still holds Kronos')
            assert(player:GetCollectibleNum(ANGEL)==0 and two:GetCollectibleNum(BOBBY)==0)
            assert(K._getAbsorbedCount(two,ANGEL)==1 and next(ledger(player).absorbed)==nil)
            near(damageBonus(player),0); near(damageBonus(two),2)
            two:RemoveCollectible(9999); update(two)
            assert(two:GetCollectibleNum(ANGEL)==1 and player:GetCollectibleNum(ANGEL)==0)
            near(damageBonus(two),0)
        """)

    def test_box_of_friends_doubles_only_its_users_abilities(self):
        self.lua.execute("""
            absorb('BROTHER_BOBBY',1); absorb('GUARDIAN_ANGEL',1,two)
            useBox(two)
            near(damageBonus(player),2); near(damageBonus(two),4)
            assert(K._getRoomTemporary(player).double==0 and K._getRoomTemporary(two).double==1)
            two:EvaluateItems(); near(two.MoveSpeed,1.6)
            player:EvaluateItems(); near(player.Tears,30/11+2)
            K.onNewRoom()
            near(damageBonus(two),2); near(damageBonus(player),2)
        """)

    def test_a_rune_fed_second_player_owns_paschal_and_lost_soul(self):
        self.lua.execute("""
            two.inventory[9999]=nil
            local paschal,lost=C.COLLECTIBLE_PASCHAL_CANDLE,C.COLLECTIBLE_LOST_SOUL
            ConchBlessing.SaveManager.GetRunSave(two).thurisaz={absorbed={['fam_'..paschal]=1,['fam_'..lost]=1},generic=0,grants={}}
            K.onGameStarted()
            near(damageBonus(two),4); near(damageBonus(player),0)
            K.onRoomClear(nil,nil,Vector.Zero)
            assert(ledger(two).paschalHundredths==3,'a second rune-fed player earned nothing')
            assert(ledger(player).paschalHundredths==nil)
            two:EvaluateItems(); near(two.Tears,30/11+0.03)
            player:EvaluateItems(); near(player.Tears,30/11)
            K.onNewLevel()
            assert(ledger(two).lostSoulRewardPending==1 and ledger(player).lostSoulRewardPending==nil)
            K.onPostUpdate()
            assert(#spawned==1 and spawned[1].position==two.Position,'the reward went to its own player')
            K.onPostUpdate(); assert(#spawned==1)
        """)

    def test_floor_and_gb_bug_releases_touch_only_their_owner(self):
        self.lua.execute("""
            K._runReady=true
            -- Player one's Monster Manual Robo-Baby (and its Technology) lasts the floor;
            -- player two owns a Technology of their own.
            K._getAbsorbedCount(player,ROBO)
            local rs=ledger(player)
            rs.tempFloor={serial=0,counts={['fam_'..ROBO]=1},grants={['fam_'..ROBO]=1}}
            rs.itemGrants['fam_'..ROBO]=1; rs.itemGrantBaselines['item_'..TECH]=0
            player.inventory[TECH]=1; two.inventory[TECH]=1
            absorb('GUARDIAN_ANGEL',4,two)
            K.onNewLevel()
            assert(player:GetCollectibleNum(TECH)==0 and two:GetCollectibleNum(TECH)==1)
            -- GB Bug hands back half of its own holder's other familiars, nobody else's.
            absorb('BROTHER_BOBBY',2)
            assert(K._releaseRandomHalf(player)==1)
            assert(player:GetCollectibleNum(BOBBY)==1 and two:GetCollectibleNum(ANGEL)==0)
            assert(K._getAbsorbedCount(two,ANGEL)==4 and ledger(player).spared['fam_'..BOBBY]==1)
            update(two); update(player)
            assert(player:GetCollectibleNum(BOBBY)==1,'the spared copy stays with its player')
            assert(ledger(two).spared==nil or next(ledger(two).spared)==nil)
        """)

    def test_an_added_player_starts_with_an_empty_ledger(self):
        self.lua.execute("""
            players={player}
            absorb('BROTHER_BOBBY',1)
            -- First Page style: a same-type second player joins mid-run with copies
            -- of the passives, Kronos included, but none of the absorbed familiars.
            players[2]=two
            update(two)
            assert(K._getAbsorbedCount(two,BOBBY)==0); near(damageBonus(two),0); near(damageBonus(player),2)
            two:AddCollectible(ANGEL); update(two)
            assert(K._getAbsorbedCount(two,ANGEL)==1 and K._getAbsorbedCount(player,ANGEL)==0)
            near(damageBonus(two),2); near(damageBonus(player),2)
        """)

    def test_a_removed_player_takes_only_its_own_runtime(self):
        self.lua.execute("""
            absorb('BROTHER_BOBBY',1); absorb('GUARDIAN_ANGEL',1,two)
            useBox(player); useBox(two)
            local function stand() local f={alive=true}
                function f:Exists() return self.alive end; function f:Remove() self.alive=false end; return f end
            local mine,theirs=stand(),stand()
            player.data.__kronosIncubi={mine}; two.data.__kronosIncubi={theirs}
            callbacks[ModCallbacks.MC_POST_ENTITY_REMOVE][EntityType.ENTITY_PLAYER](nil,two)
            table.remove(players,2)
            assert(not theirs:Exists() and two.data.__kronosIncubi==nil)
            assert(mine:Exists() and #player.data.__kronosIncubi==1)
            assert(K._getRoomTemporary(player).double==1,"another player's room state survived")
            near(damageBonus(player),4)
            assert(K._getAbsorbedCount(player,BOBBY)==1)
        """)

    def test_dead_players_and_ghosts_are_never_chosen_as_holders(self):
        self.lua.execute("""
            function player:IsDead() return true end
            run.kronos={absorbed={['fam_'..BOBBY]={id=BOBBY,count=2}},totalAbsorbed=2,
                itemGrants={},itemGrantTotals={},itemGrantBaselines={}}
            K.onGameStarted()
            assert(run.kronos==nil and ledger(two).absorbed['fam_'..BOBBY].count==2,
                'the shared ledger went to a dead holder')
            near(damageBonus(two),4); near(damageBonus(player),0)
            ConchBlessing.Locale={formatPercent=function(v) return v..'%' end}
            absorb('HALO_OF_FLIES',3,two)
            function two:IsCoopGhost() return false end
            assert(ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK()=='3%')
            function two:IsCoopGhost() return true end
            assert(ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK()=='0%','a ghost was described')
        """)

    def test_eid_describes_the_tab_holding_player_else_the_first_with_abilities(self):
        self.lua.execute("""
            ConchBlessing.Locale={formatPercent=function(v) return v..'%' end}
            player.inventory[9999]=nil
            absorb('HALO_OF_FLIES',3,two)
            local block=ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK
            assert(block()=='3%' and block(player)=='0%' and block(two)=='3%')
            EID={holdTabPlayer=player}; assert(block()=='0%'); EID=nil
            per.kronos=per.kronos or {absorbed={}}; per.kronos.prettyFlies=2
            assert(K._getPrettyFlyCount(player)==0,'Pretty Flies block without Kronos')
        """)


class KronosLedgerMigrationTests(unittest.TestCase):
    """Saves from before per-player ledgers kept one shared ledger in the global
    run save; it moves once, whole, to the player who used it."""

    def setUp(self):
        KronosPerPlayerLedgerTests.setUp(self)
        self.lua.execute("""
            function old(count)
                return {absorbed={['fam_'..BOBBY]={id=BOBBY,count=count}},totalAbsorbed=count,
                    itemGrants={},itemGrantTotals={},itemGrantBaselines={},paschalHundredths=6}
            end
        """)

    def test_shared_ledger_moves_to_the_lowest_index_holder(self):
        self.lua.execute("""
            player.inventory[9999]=nil
            run.kronos=old(2)
            K.onGameStarted()
            assert(run.kronos==nil and ledger(two).absorbed['fam_'..BOBBY].count==2)
            assert(ledger(two).paschalHundredths==6 and ledger(player)==nil)
            assert(player:GetCollectibleNum(BOBBY)==0 and two:GetCollectibleNum(BOBBY)==0)
            near(damageBonus(two),4); near(damageBonus(player),0)
            assert(savedPer and savedRun.kronos==nil,'the move was saved')
        """)

    def test_older_names_move_too_and_both_players_holding_picks_player_one(self):
        self.lua.execute("""
            run.cronus=old(1); run.chronus=old(5)
            K.onGameStarted()
            assert(run.kronos==nil and run.cronus==nil and run.chronus==nil)
            assert(ledger(player).absorbed['fam_'..BOBBY].count==1,'the newest old name wins')
            assert(ledger(two)==nil or next(ledger(two).absorbed)==nil)
            near(damageBonus(player),2); near(damageBonus(two),0)
        """)

    def test_nobody_holding_keeps_the_dormant_handback_to_player_one(self):
        self.lua.execute("""
            player.inventory[9999]=nil; two.inventory[9999]=nil
            run.kronos=old(2)
            K.onGameStarted()
            assert(run.kronos==nil and player:GetCollectibleNum(BOBBY)==2 and two:GetCollectibleNum(BOBBY)==0)
            assert(next(ledger(player).absorbed)==nil and ledger(player).paschalHundredths==nil)
            near(damageBonus(player),0)
        """)

    def test_merge_with_an_existing_own_ledger_and_hourglass_rewind(self):
        self.lua.execute("""
            K._getAbsorbedCount(player,BOBBY)
            ledger(player).absorbed['fam_'..ANGEL]={id=ANGEL,count=1}; ledger(player).totalAbsorbed=1
            run.kronos=old(2)
            local before=copy(run); local beforePer=copy(per)
            K.onGameStarted()
            local rs=ledger(player)
            assert(rs.absorbed['fam_'..BOBBY].count==2 and rs.absorbed['fam_'..ANGEL].count==1)
            assert(rs.totalAbsorbed==3 and rs.paschalHundredths==6)
            near(damageBonus(player),6)
            -- Glowing Hourglass restores the run save from before the move: it moves again.
            run.kronos=before.kronos; per.kronos=beforePer.kronos
            assert(K._getAbsorbedCount(player,BOBBY)==2 and run.kronos==nil)
        """)

    def test_oldest_per_player_ledger_is_adopted_by_its_own_player(self):
        self.lua.execute("""
            ConchBlessing.SaveManager.GetRunSave(two).chronus={absorbed={['fam_'..ANGEL]={count=1}},totalAbsorbed=1}
            assert(K._getAbsorbedCount(two,ANGEL)==1 and ConchBlessing.SaveManager.GetRunSave(two).chronus==nil)
            assert(K._getAbsorbedCount(player,ANGEL)==0)
            K.onGameStarted(); near(damageBonus(two),2); near(damageBonus(player),0)
        """)


if __name__ == '__main__':
    unittest.main()
