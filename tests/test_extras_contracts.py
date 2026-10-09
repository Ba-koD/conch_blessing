"""Shipped Void Dagger / Angel's Crown clauses with deterministic provider doubles.

This checks callback decisions and emitted parameters, not real engine HP,
room art, item-pool identity, native heart drops, or save/Continue on disk.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime
import test_soflam_contracts as soflam_tests

ROOT = Path(__file__).resolve().parents[1]


class VoidContracts(unittest.TestCase):
    def setUp(self):
        soflam_tests.SoflamContracts.setUp(self)
        self.lua.execute(r"""
            local mt={__sub=function(a,b) return Vector(a.X-b.X,a.Y-b.Y) end}
            Vector=setmetatable({}, {__call=function(_,x,y) return setmetatable({X=x,Y=y},mt) end})
            Vector.Zero=Vector(0,0); player.Position=Vector(100,100);npc.Position=Vector(240,160)
            player.MaxFireDelay=10;player.TearRange=260;player.Luck=200;player.roll=.5
            rings={};ringMode='method'; EID=nil
            function player:SpawnMawOfVoid(angle)
                assert(angle==0);if ringMode=='nil' then return nil end
                local e=entity(7,self);e.Radius=50;e.BlackHpDropChance=.03;e.CollisionDamage=self.Damage
                e.Velocity=Vector(1,1);e.DisableFollowParent=false
                function e:ToLaser() if ringMode=='wrong_cast' then return nil end return self end
                if ringMode~='property' then function e:SetBlackHpDropChance(n) self.blackSet=n;self.BlackHpDropChance=n end end
                if ringMode=='no_timeout' then e.SetTimeout=nil end
                rings[#rings+1]=e;return e
            end
            require('scripts.items.collectibles.void_dagger'); V=ConchBlessing.voiddagger
            function voidHit(a,target,amount)
                V.onPostEntityTakeDamage(nil,target or npc,amount or 1,0,{Entity=player},0,{Entity=a})
            end
        """)

    def test_all_damage_duration_bucket_edges_are_applied_to_actual_spawned_ring(self):
        self.lua.execute(r"""
            for _,row in ipairs({{-1,20},{0,20},{9.999,20},{10,25},{19.999,25},{20,30},
                {29.999,30},{30,35},{39.999,35},{40,40},{10000,40}}) do
                player.Damage=row[1];voidHit(laser());assert(rings[#rings].Timeout==row[2],tostring(row[1]))
            end
        """)

    def test_black_heart_suppression_uses_method_or_property_and_timeout_property_fallback(self):
        self.lua.execute(r"""
            for _,mode in ipairs({'method','property','no_timeout'}) do
                ringMode=mode;voidHit(laser());local r=rings[#rings]
                assert(r.BlackHpDropChance==0 and r.Timeout==25)
                if mode~='property' then assert(r.blackSet==0) end
            end
        """)

    def test_ring_is_locked_to_hit_position_with_fixed_radius_and_causal_lineage(self):
        self.lua.execute(r"""
            voidHit(laser());local r=rings[1]
            assert(r.Position==npc.Position and r.ParentOffset.X==140 and r.ParentOffset.Y==60)
            assert(r.Velocity.X==0 and r.Velocity.Y==0 and r.DisableFollowParent and r.Radius==15)
            local provenance=P.getSnapshot(r)
            assert(provenance.procChain.void_dagger and provenance.origin=='void_dagger_void_ring')
            voidHit(r);assert(#rings==1,'ring recursively spawned another ring')
            player.TearRange=1000;voidHit(laser());assert(rings[2].Radius==15)
        """)

    def test_rate_floor_luck_clamp_and_strict_roll_boundary_use_shipped_proc_path(self):
        self.lua.execute(r"""
            for _,row in ipairs({{29,0,.29},{0,0,.05},{-.5,0,.05},{-1,0,.05},{29,-9,.29},
                {29,1,.319},{29,200,1}}) do
                player.MaxFireDelay=row[1];player.Luck=row[2]
                player.roll=row[3];local before=#rings;voidHit(laser());assert(#rings==before,'boundary must fail')
                player.roll=row[3]-.00001;voidHit(laser());assert(#rings==before+1,'just below boundary must succeed')
            end
        """)

    def test_failed_attack_claim_is_not_rerolled_on_next_target_tick_or_luck_change(self):
        self.lua.execute(r"""
            player.Luck=0;player.roll=.99;local a=laser();voidHit(a);local rolls=player.rolls
            player.Luck=200;player.roll=0;voidHit(a);voidHit(a,entity(10))
            assert(#rings==0 and player.rolls==rolls)
            voidHit(laser());assert(#rings==1)
        """)

    def test_invalid_targets_and_item_loss_reject_but_owned_familiar_attacks_proc(self):
        self.lua.execute(r"""
            V.onPostEntityTakeDamage(nil,nil,1,0,nil,0,nil)
            voidHit(laser(),npc,0);npc.friendly=true;voidHit(laser());npc.friendly=false
            npc.vulnerable=false;voidHit(laser());npc.vulnerable=true
            player.items[77]=0;voidHit(laser());player.items[77]=1
            assert(#rings==0 and player.rolls==0)
            local familiar=entity(3,player);familiar.Player=player;voidHit(laser(familiar))
            assert(#rings==1 and player.rolls==1,'owned familiar attack lost player provenance')
        """)

    def test_item_loss_stops_new_procs_and_reacquisition_handles_new_attacks(self):
        self.lua.execute(r"""
            voidHit(laser());assert(#rings==1);player.items[77]=0;V.onPlayerUpdate(nil,player)
            voidHit(laser());assert(#rings==1);player.items[77]=1
            V.onPlayerUpdate(nil,player);voidHit(laser());assert(#rings==2)
            assert(not rings[1].removed,'previously fired attack was retracted')
        """)

    def test_missing_ring_or_wrong_cast_does_not_retry_or_consume_multiple_rolls(self):
        self.lua.execute(r"""
            for _,mode in ipairs({'nil','wrong_cast'}) do
                ringMode=mode;local a=laser();local before=player.rolls;voidHit(a);voidHit(a)
                assert(player.rolls==before+1)
            end
        """)

    def test_collision_fallback_is_disabled_with_confirmed_damage_and_honors_claims_without_it(self):
        self.lua.execute(r"""
            local tear=entity(2,player);V.onTearCollision(nil,tear,npc);assert(#rings==0)
            ModCallbacks.MC_POST_ENTITY_TAKE_DMG=nil
            V.onTearCollision(nil,tear,npc);V.onTearCollision(nil,tear,npc);assert(#rings==1)
            V.onTearCollision(nil,nil,npc);V.onTearCollision(nil,entity(2,player),nil)
            V.onTearCollision(nil,rings[1],npc);assert(#rings==1)
        """)


class AngelContracts(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute(r"""
            package.path=root..'/?.lua;'..package.path
            EntityType={ENTITY_PICKUP=5,ENTITY_EFFECT=1000,ENTITY_FIREPLACE=33}
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_HEART=10};HeartSubType={HEART_ETERNAL=4}
            EffectVariant={POOF01=15};RoomType={ROOM_TREASURE=4,ROOM_DEFAULT=1,
                ROOM_SECRET=7,ROOM_SUPERSECRET=8,ROOM_ULTRASECRET=29}
            RoomDescriptor={FLAG_DEVIL_TREASURE=1}; DoorSlot={NUM_DOOR_SLOTS=8};BackdropType={CATHEDRAL=1}
            SoundEffect={SOUND_CHOIR_UNLOCK=1};Vector=setmetatable({}, {__call=function(_,x,y) return {X=x,Y=y} end})
            Vector.Zero=Vector(0,0);serial=0;entities={};poolDraws={};rngRolls=0;rngNexts=0;roll=.5
            saves=0;roomSaves={};pickupSaves={};errors={};roomIndex=1;roomType=4;firstVisit=true
            currentDesc={ListIndex=1,SpawnSeed=123,Flags=0,VisitedCount=0};coins={}
            players={{normal=1,golden=0,box=false}};roomMissing=false;pickupMissing=false
            function makePickup(variant,id,seed)
                serial=serial+1;local p={Type=5,Variant=variant,SubType=id,InitSeed=seed or serial,
                    Position=Vector(100,100),Price=0,OptionsPickupIndex=77,AutoUpdatePrice=true,Touched=false}
                function p:ToPickup() return self end
                function p:Morph(kind,v,sub,keepPrice,keepSeed,ignore)
                    assert(kind==5 and v==100 and not keepPrice and keepSeed)
                    self.SubType=sub;self.morphed=(self.morphed or 0)+1
                end
                entities[#entities+1]=p;return p
            end
            pickup=makePickup(100,1,10)
            function GetPtrHash(p) return p end
            room={GetType=function() return roomType end,GetDoor=function() return nil end,
                GetGridSize=function() return 0 end,SetBackdropType=function() end,
                IsFirstVisit=function() return firstVisit end,GetSpawnSeed=function() return 456 end,
                FindFreePickupSpawnPosition=function(_,p) return p end,GetCenterPos=function() return Vector(100,100) end}
            level={GetCurrentRoomDesc=function() return currentDesc end,IsAscent=function() return ascent==true end}
            pool={GetCollectible=function(_,kind,decrease,seed)
                poolDraws[#poolDraws+1]={kind=kind,decrease=decrease,seed=seed}
                if poolThrows then error('pool failed') end
                if poolEmpty then return 0 end
                return 200+#poolDraws
            end}
            game={GetRoom=function() return room end,GetLevel=function() return level end,
                GetItemPool=function() return pool end,GetNumPlayers=function() return #players end,
                GetPlayer=function(_,i) return players[i+1] end,IsGreedMode=function() return greed==true end,
                Spawn=function(_,kind,variant,pos,vel,spawner,id,seed)
                    assert(kind==5 and seed~=0);return makePickup(variant,id,seed)
                end}
            function Game() return game end
            ItemPoolType={POOL_ANGEL=15,POOL_TREASURE=0}
            Isaac={GetItemConfig=function() return {GetCollectible=function(_,id)
                    return {ShopPrice=prices and prices[id] or 15} end} end,
                FindByType=function(kind,variant)
                    local result={};for _,e in ipairs(entities) do
                        if e.Type==kind and (variant==-1 or e.Variant==variant) then result[#result+1]=e end
                    end;return result
                end,
                Spawn=function() end}
            function RNG() return {SetSeed=function(_,seed,shift) assert(seed>0 and shift==35) end,
                RandomFloat=function() rngRolls=rngRolls+1;return roll end,
                Next=function() rngNexts=rngNexts+1;return zeroRngSeed and 0 or 1000+rngNexts end} end
            function SFXManager() return {Play=function() end} end
            SM={GetRoomSave=function(_,_,index)
                    if roomMissing then return nil end
                    index=index or roomIndex;roomSaves[index]=roomSaves[index] or {};return roomSaves[index]
                end,
                TryGetRoomSave=function(_,_,index) return roomSaves[index or roomIndex] end,
                GetRerollPickupSave=function(p)
                    if pickupMissing then return nil end
                    pickupSaves[p]=pickupSaves[p] or {};return pickupSaves[p]
                end,
                TryGetRerollPickupSave=function(p) return pickupSaves[p] end,
                Save=function() saves=saves+1 end}
            ConchBlessing={ItemData={ANGELS_CROWN={id=9}},SaveManager=SM,
                TrinketUtils={getTrinketCounts=function(p,id) assert(id==9);return p.normal,p.golden,p.box end},
                printDebug=function() end,printError=function(e) errors[#errors+1]=e end}
            require('scripts.items.trinkets.angels_crown');A=ConchBlessing.angelscrown
            function rewards()
                local items,hearts=0,0
                for _,p in ipairs(entities) do
                    if p.Variant==100 then items=items+1 elseif p.Variant==10 and p.SubType==4 then hearts=hearts+1 end
                end
                return items,hearts
            end
        """)

    def test_chance_table_is_capped_by_modifier_presence_not_copy_count(self):
        self.lua.execute(r"""
            for _,row in ipairs({{0,false,0},{0,true,.25},{1,false,.25},{1,true,.33},
                {20,false,.25},{20,true,.33},{-1,false,0}}) do
                assert(A._test.getBlessedChance(row[1],row[2])==row[3])
            end
            assert(A._test.getBlessedChance(nil,false)==0)
        """)

    def test_actual_room_conversion_blessed_threshold_and_exact_extra_rewards(self):
        for normal,golden,box,chance in ((1,0,False,0),(1,0,True,.25),(0,1,False,.25),(0,1,True,.33),(0,20,True,.33)):
            for success in (False,True):
                with self.subTest(normal=normal,golden=golden,box=box,chance=chance,success=success):
                    self.setUp()
                    self.lua.globals().normal=normal;self.lua.globals().golden=golden;self.lua.globals().box=box
                    self.lua.globals().chosen_roll=max(0,chance-.00001) if success else chance
                    self.lua.globals().blessed=bool(success and chance>0)
                    self.lua.execute(r"""
                        players={{normal=normal,golden=golden,box=box}};roll=chosen_roll;A.onGameStarted()
                        local items,hearts=rewards();assert(items==(blessed and 2 or 1) and hearts==(blessed and 1 or 0))
                        assert(roomSaves[1].angelsCrown.converted and roomSaves[1].angelsCrown.blessed==blessed)
                        for _,p in ipairs(entities) do
                            if p.Variant==100 then assert(p.Price==15 and p.ShopItemId==-1 and not p.AutoUpdatePrice and p.OptionsPickupIndex==0) end
                        end
                        for _,draw in ipairs(poolDraws) do assert(draw.kind==15 and draw.decrease and draw.seed>0) end
                    """)

    def test_revisit_in_memory_restore_and_trinket_loss_never_reroll_or_duplicate_rewards(self):
        self.lua.execute(r"""
            players[1].golden=1;players[1].box=true;roll=0;A.onGameStarted()
            local draws,rolls,nexts=#poolDraws,rngRolls,rngNexts
            firstVisit=false;players[1].normal=0;players[1].golden=0;players[1].box=false
            pickup.Price=0;A.onPostNewRoom();A.onPostUpdate();A.onPreGameExit();A.onGameStarted()
            assert(#poolDraws==draws and rngRolls==rolls and rngNexts==nexts)
            local items,hearts=rewards();assert(items==2 and hearts==1 and pickup.Price==15)
        """)

    def test_already_visited_unowned_greed_ascent_devil_and_non_treasure_rooms_do_not_convert(self):
        for setup in ('firstVisit=false','players[1].normal=0','greed=true','ascent=true','currentDesc.Flags=1','roomType=1'):
            with self.subTest(setup=setup):
                self.setUp();self.lua.execute(setup+';A.onGameStarted();assert(#poolDraws==0 and rngRolls==0 and pickup.SubType==1)')

    def test_best_single_holder_wins_without_combining_modifiers_across_players(self):
        self.lua.execute(r"""
            players={{normal=0,golden=1,box=false},{normal=1,golden=0,box=true}};roll=.28
            A.onGameStarted();assert(not roomSaves[1].angelsCrown.blessed)
            roomIndex=2;currentDesc.ListIndex=2;players[2].golden=1;entities={};pickup=makePickup(100,1)
            A.onPostNewRoom();assert(roomSaves[2].angelsCrown.blessed)
            local items,hearts=rewards();assert(items==2 and hearts==1)
        """)

    def test_changed_quote_refreshes_price_but_active_swap_releases_it_permanently(self):
        self.lua.execute(r"""
            A.onGameStarted();local draws=#poolDraws
            pickup.SubType=300;prices={[300]=23.9};A.onPostUpdate()
            assert(pickup.Price==23 and pickupSaves[pickup].angelsCrownDeal.item==300 and #poolDraws==draws)
            pickup.Touched=true;pickup.SubType=301;A.onPostUpdate()
            assert(pickup.Price==0 and pickupSaves[pickup].angelsCrownDeal==nil)
            A.onPostNewRoom();A.onPostUpdate();assert(pickup.Price==0 and #poolDraws==draws)
        """)

    def test_touched_but_unchanged_item_is_still_a_deal_and_foreign_seed_is_never_adopted(self):
        self.lua.execute(r"""
            A.onGameStarted();pickup.Touched=true;pickup.Price=0;A.onPostUpdate();assert(pickup.Price==15)
            pickup.InitSeed=999;pickup.SubType=350;pickup.Price=0;A.onPostUpdate();A.onPostNewRoom()
            assert(pickup.Price==0 and pickup.SubType==350)
        """)

    def test_override_targets_owned_treasure_requests_after_loss_and_recovers_after_pool_errors(self):
        self.lua.execute(r"""
            assert(A.onPreGetCollectible(nil,0,true,1)==nil)
            A.onGameStarted();players[1].normal=0
            assert(A.onPreGetCollectible(nil,15,true,1)==nil)
            assert(A.onPreGetCollectible(nil,0,false,7)>0)
            local d=poolDraws[#poolDraws];assert(d.kind==15 and d.decrease==false and d.seed==7)
            poolThrows=true;assert(A.onPreGetCollectible(nil,0,true,1)==nil)
            poolThrows=false;assert(A.onPreGetCollectible(nil,0,true,1)>0)
            poolEmpty=true;assert(A.onPreGetCollectible(nil,0,true,1)==nil)
            A.onPreGameExit();assert(A.onPreGetCollectible(nil,0,true,1)==nil)
        """)

    def test_missing_room_save_fails_before_inventory_pool_or_rng_mutation(self):
        self.lua.execute('roomMissing=true;A.onGameStarted();assert(#poolDraws==0 and rngRolls==0 and #errors==1)')

    def test_zero_rng_seed_is_replaced_and_missing_price_uses_documented_coin_fallback(self):
        self.lua.execute(r"""
            players[1].golden=1;roll=0;zeroRngSeed=true;currentDesc.SpawnSeed=0;pickup.InitSeed=0
            prices=setmetatable({},{__index=function() return -1 end});A.onGameStarted()
            local items,hearts=rewards();assert(items==2 and hearts==1 and pickup.Price==15)
            for _,draw in ipairs(poolDraws) do assert(draw.seed>0) end
        """)

if __name__=='__main__': unittest.main()
