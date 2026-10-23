"""Production callback regressions with a tail-only cycle/persistence double.

These exercise Lua logic, not native dice, provider acquisition callbacks, or a real Continue.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class SeveredOathTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            package=nil
            CollectibleType={COLLECTIBLE_NULL=0}; ActiveSlot={}; PickupVariant={PICKUP_COLLECTIBLE=100}
            EntityType={ENTITY_PICKUP=5}; ItemPoolType={POOL_TREASURE=0}
            function copy(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and copy(v) or v end return o end
            saves={}; writes=0; draws=0; preview=0; stock={}; roomIndex=1; frame=10; serial=0; errors={}
            function key(p) return tostring(p.identity)..":"..tostring(p.InitSeed) end
            function GetPtrHash(p) return p.identity end
            function EntityPtr(p)
                local generation=p.generation
                return setmetatable({}, {__index=function(_,k)
                    if k=="Ref" and not p.removed and p.generation==generation then return p end
                end})
            end
            player={held=true}
            function player:GetActiveItem() return self.held and 999 or 0 end
            function player:HasCollectible(id) return id==999 and self.held or id==619 end
            players={player}
            pool={GetLastPool=function() return 0 end,GetPoolForRoom=function() return 0 end}
            function pool:GetCollectible(_,decrease,seed)
                if decrease then draws=draws+1 else preview=preview+1 end
                return 1000 + seed % 10000
            end
            room={GetType=function() return 1 end,GetSpawnSeed=function() return 17 end,IsFirstVisit=function() return false end}
            level={GetCurrentRoomIndex=function() return roomIndex end,GetStage=function() return 1 end,
                GetStageType=function() return 0 end,GetDimension=function() return 0 end}
            game={GetRoom=function() return room end,GetLevel=function() return level end,
                GetNumPlayers=function() return #players end,GetPlayer=function(_,i) return players[i+1] end,
                GetItemPool=function() return pool end,GetFrameCount=function() return frame end}
            function Game() return game end
            Isaac={DebugString=function() end,GetItemIdByName=function() return 999 end,
                GetItemConfig=function() return {GetCollectible=function(_,id) return id>0 and {} or nil end} end,
                GetRoomEntities=function() return stock end}
            ConchBlessing={printError=function(s) errors[#errors+1]=s end,printDebug=function() end,print=function() end,SaveManager={
                GetNoRerollPickupSave=function(p) saves[key(p)]=saves[key(p)] or {}; return saves[key(p)] end,
                TryGetNoRerollPickupSave=function(p) return saves[key(p)] end,
                Save=function() writes=writes+1; disk=copy(saves) end}}
            function pedestal(seed,head,tail)
                serial=serial+1
                local p={identity=serial,Type=5,Variant=100,InitSeed=seed,SubType=head or 1,tail=tail or {},data={},Price=15,OptionsPickupIndex=777}
                function p:GetData() return self.data end
                function p:GetCollectibleCycle() return copy(self.tail) end
                function p:AddCollectibleCycle(id)
                    if #self.tail>=8 then return false end
                    self.tail[#self.tail+1]=id; return true
                end
                function p:RemoveCollectibleCycle() self.tail={} end
                function p:Exists() return not self.removed end
                function p:ToPickup() return self end
                function p:rotate()
                    self.tail[#self.tail+1]=self.SubType; self.SubType=table.remove(self.tail,1)
                end
                stock[#stock+1]=p; return p
            end
            function goldenProvider()
                -- Standalone provider contract: one public, run-wide active-ID ledger.
                GoldenItems={goldActiveList={}}
                function GoldenItems:HasGoldenItem(id) return self.goldActiveList[tostring(id)]==true end
                function GoldenItems:SetGoldenItem(id) self.goldActiveList[tostring(id)]=true end
                function GoldenItems:ExaustGoldenItem(id) self.goldActiveList[tostring(id)]=false end
            end
            function epiphanyProvider()
                Epiphany={}
                function Epiphany:HasGoldenItem(id,p,slot)
                    return p.goldenSlots and p.goldenSlots[tostring(slot)]==id or false
                end
                function Epiphany:SetGoldenItem(id,p,slot)
                    p.goldenSlots=p.goldenSlots or {}; p.goldenSlots[tostring(slot)]=id
                end
                function Epiphany:ExaustGoldenItem(id,p,slot)
                    if p.goldenSlots then p.goldenSlots[tostring(slot)]=nil end
                end
            end
        ''')
        self.lua.execute((ROOT / 'scripts/items/collectibles/severed_oath.lua').read_text(encoding='utf-8'))
        self.lua.execute('M=ConchBlessing.severedoath; M.onGameStarted(nil,false); function update(p) M.onPostPickupUpdate(nil,p) end')

    def test_seeded_transition_stress_preserves_foreign_occurrences_and_charges_only_delivered_slots(self):
        # 256 independent fixtures, 64 transitions each. This is a Lua state
        # regression, NOT proof of native dice, serialization or actual Continue.
        self.lua.execute('''
            goldenProvider()
            local randomState=104729
            local function choose(n) randomState=(randomState*48271)%2147483647; return randomState%n end
            for sample=1,256 do
                stock={}; saves={}; M.onGameStarted(nil,false); player.held=true
                local target=sample%2+1
                if target==2 then GoldenItems:SetGoldenItem(999) else GoldenItems:ExaustGoldenItem(999) end
                local tail={}; for n=1,choose(9) do tail[n]=2+choose(3) end
                local p=pedestal(sample*100,1,tail)
                local spent=0
                local stepLabel='initial'
                local function verify()
                    frame=frame+31
                    local head,old,before=p.SubType,copy(p.tail),draws
                    local due=player.held and math.min(target-spent,8-#old) or 0
                    update(p)
                    assert(p.SubType==head,'stress: displayed head replaced')
                    assert(#p.tail==#old+due,string.format('stress sample=%d step=%s seed=%d held=%s spent=%d target=%d old=%d due=%d actual=%d',
                        sample,stepLabel,p.InitSeed,tostring(player.held),spent,target,#old,due,#p.tail))
                    for i,id in ipairs(old) do assert(p.tail[i]==id,'stress: foreign occurrence/order overwritten') end
                    assert(draws-before==due,'stress: pool draw without delivered bonus or duplicate charge')
                    spent=spent+due
                    for _=1,3 do frame=frame+1; update(p) end
                    assert(draws-before==due and #p.tail==#old+due,'stress: unstable repeated update')
                end
                verify()
                for step=1,64 do
                    local event=choose(7)
                    stepLabel=step..'/event'..event
                    if event==0 and #p.tail>0 then p:rotate()
                    elseif event==1 then
                        p.SubType=20+choose(5); p.tail={}
                        for i=1,choose(9) do p.tail[i]=30+choose(4) end
                    elseif event==2 then p.generation=(p.generation or 0)+1
                    elseif event==3 then
                        player.held=not player.held
                        -- Existing unowned stock becomes eligible on held room
                        -- entry; acquisition alone is not that gameplay event.
                        if player.held then roomIndex=2; M.onPostNewRoom(); roomIndex=1; M.onPostNewRoom() end
                    elseif event==4 then
                        roomIndex=2; M.onPostNewRoom(); roomIndex=1; M.onPostNewRoom()
                    elseif event==5 and #p.tail<8 then p.tail[#p.tail+1]=40+choose(3)
                    elseif event==6 then
                        p.InitSeed=p.InitSeed+1; p.SubType=1; p.tail={}; spent=0
                    end
                    verify()
                end
            end
        ''')

    def test_ordinary_birthright_does_not_block_and_existing_order_is_untouched(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2,3,4}); update(p)
            assert(#p.tail==5 and table.concat(p.tail,',',1,4)=='2,2,3,4')
            assert(draws==1 and p.Price==15 and p.OptionsPickupIndex==777)
            q=pedestal(72,10); update(q)
            assert(#q.tail==1 and draws==2,'Isaac Birthright prevented +1')
        ''')

    def test_bonus_uses_current_room_pool_not_unrelated_last_draw(self):
        self.lua.execute('''
            local requested={}
            pool.GetPoolForRoom=function() return 3 end -- current room's pool
            pool.GetLastPool=function() return 1 end -- unrelated previous shop draw
            function pool:GetCollectible(kind,decrease,seed)
                requested[#requested+1]=kind
                if decrease then draws=draws+1 end
                return 200+kind
            end
            p=pedestal(71,1,{2,2,3}); update(p)
            assert(#requested==2 and requested[1]==3 and requested[2]==3,'bonus followed stale GetLastPool instead of current room')
            assert(p.tail[4]==203 and draws==1)
        ''')

    def test_golden_topup_uses_current_room_not_saved_historical_pool(self):
        self.lua.execute('''
            goldenProvider(); local currentPool=0
            pool.GetPoolForRoom=function() return currentPool end
            function pool:GetCollectible(kind,decrease,seed)
                if decrease then draws=draws+1 end
                return 200+kind
            end
            p=pedestal(71,1); update(p); assert(p.tail[1]==200)
            currentPool=3; pool.GetLastPool=function() return 1 end
            GoldenItems:SetGoldenItem(999); update(p)
            assert(#p.tail==2 and p.tail[1]==200 and p.tail[2]==203 and draws==2,'top-up reused saved pool or replaced a paid choice')
        ''')

    def test_gold_active_adds_two_and_late_upgrade_adds_only_one_more(self):
        self.lua.execute('''
            goldenProvider(); GoldenItems:SetGoldenItem(999)
            p=pedestal(71,1,{2,3,4}); update(p)
            assert(#p.tail==5 and draws==2 and p.tail[4]~=p.tail[5])
            GoldenItems:ExaustGoldenItem(999)
            q=pedestal(72,10); update(q); assert(#q.tail==1)
            GoldenItems:SetGoldenItem(999); update(q); assert(#q.tail==2 and draws==4)
            for i=1,30 do p:rotate(); update(p); q:rotate(); update(q) end
            assert(#p.tail==5 and #q.tail==2 and draws==4,'rotation duplicated choices')
        ''')

    def test_external_rebuild_is_authoritative_without_pool_draws(self):
        self.lua.execute('''
            goldenProvider(); p=pedestal(71,1,{2,3}); GoldenItems:SetGoldenItem(999); update(p)
            local a,b=p.tail[3],p.tail[4]; p.tail={5,5,6}; update(p)
            assert(table.concat(p.tail,',')=='5,5,6','external choices overwritten')
            assert(draws==2,'repair consumed the pool again')
            p.tail={5,5,6,b}; p.SubType=a; update(p)
            assert(#p.tail==4,'displayed bonus was appended a second time')
        ''')

    def test_revisit_and_serialized_reload_keep_both_gold_identities(self):
        self.lua.execute('''
            goldenProvider(); p=pedestal(71,1); GoldenItems:SetGoldenItem(999); update(p)
            local a,b=p.tail[1],p.tail[2]
            roomIndex=2; M.onPostNewRoom(); roomIndex=1; M.onPostNewRoom(); update(p)
            assert(#p.tail==2 and draws==2)
            saves=copy(disk); p.data={}; M.onGameStarted(nil,true); update(p)
            assert(#p.tail==2 and p.tail[1]==a and p.tail[2]==b and draws==2)
            p.tail={}; update(p); assert(#p.tail==0 and draws==2,'external clearing resurrected historical IDs')
        ''')

    def test_unmodified_visited_room_gains_bonus_on_entry_while_held(self):
        self.lua.execute('''
            player.held=false; p=pedestal(71,1); update(p); assert(#p.tail==0)
            roomIndex=2; M.onPostNewRoom(); player.held=true
            roomIndex=1; M.onPostNewRoom(); update(p); assert(#p.tail==1 and draws==1)
            q=pedestal(72,2); M.onGameStarted(nil,true); update(p); update(q)
            assert(#p.tail==1 and #q.tail==1 and draws==2,'continue skipped unmodified room stock')
        ''')

    def test_owner_loss_keeps_existing_choices_but_grants_no_new_choices(self):
        self.lua.execute('''
            goldenProvider(); p=pedestal(71,1); update(p); player.held=false
            GoldenItems:SetGoldenItem(999); update(p); q=pedestal(72,2); GoldenItems:SetGoldenItem(999); update(q)
            assert(#p.tail==1 and #q.tail==0 and draws==1)
            player.held=true; update(p); assert(#p.tail==2 and draws==2)
        ''')

    def test_legacy_save_and_both_magic_conch_replacements_are_migrated(self):
        self.lua.execute('''
            goldenProvider(); p=pedestal(71,1,{20}); GoldenItems:SetGoldenItem(999)
            saves[key(p)]={severedOath={bonusItem=20,poolType=0}}
            update(p); assert(#p.tail==2 and draws==1)
            local b=p.tail[2]; p.tail={30,40}
            M.onCollectibleCycleRewritten(p,{[20]=30,[b]=40}); update(p)
            assert(#p.tail==2 and draws==1)
            assert(saves[key(p)].severedOath.bonusItems[1]==30 and saves[key(p)].severedOath.bonusItems[2]==40)
        ''')

    def test_full_duplicate_queue_and_missing_capability_do_not_consume_pool(self):
        self.lua.execute('''
            goldenProvider(); p=pedestal(71,1,{2,2,2,2,2,2,2,2}); GoldenItems:SetGoldenItem(999); update(p)
            assert(#p.tail==8 and draws==0 and preview==0)
            q=pedestal(72,2); q.AddCollectibleCycle=nil; update(q)
            assert(draws==0 and preview==0)
            bad=pedestal(74,5); bad.GetCollectibleCycle=function() error('incompatible API') end; update(bad)
            assert(draws==0 and preview==0 and #bad.tail==0)
            r=pedestal(73,3,{4,4,4,4,4,4,4}); GoldenItems:SetGoldenItem(999); update(r)
            assert(#r.tail==8 and draws==1,'overflow consumed an unaddable second item')
        ''')

    def test_optional_provider_error_falls_back_and_split_products_do_not_regrow(self):
        self.lua.execute('''
            GoldenItems={HasGoldenItem=function() error('not ready') end}
            p=pedestal(71,1); update(p); assert(#p.tail==1)
            q=pedestal(72,2); saves[key(q)]={severedOath={split=true,splitItem=2}}
            goldenProvider(); GoldenItems:SetGoldenItem(999); update(q); assert(#q.tail==0 and draws==1)
            q.SubType=3; update(q); assert(#q.tail==2 and draws==3,'rerolled split item never became eligible')
        ''')

    def test_coop_holder_and_reroll_seed_use_new_pedestal_state(self):
        self.lua.execute('''
            player.held=false; players[2]={GetActiveItem=function() return 999 end}
            p=pedestal(71,1); update(p); assert(#p.tail==1)
            p.InitSeed=72; p.SubType=10; p.tail={}; update(p)
            assert(#p.tail==1 and draws==2,'a new reroll inherited stale bonus state')
            for _=1,20 do update(p) end; assert(#p.tail==1 and draws==2)
        ''')


    def test_golden_target_pedestal_and_other_golden_actives_do_not_double(self):
        self.lua.execute('''
            goldenProvider(); GoldenItems:SetGoldenItem(666)
            GoldenItems.Pickup={GOLDEN_ITEM={IsGoldenPedestal=function() return true end}}
            p=pedestal(71,1); p.gold=true; update(p)
            assert(#p.tail==1 and draws==1,'target gold incorrectly enabled +2')
        ''')

    def test_downgrade_affects_new_stock_without_erasing_committed_choices(self):
        self.lua.execute('''
            goldenProvider(); GoldenItems:SetGoldenItem(999)
            p=pedestal(71,1); update(p); assert(#p.tail==2)
            GoldenItems:ExaustGoldenItem(999); update(p)
            q=pedestal(72,2); update(q)
            assert(#p.tail==2 and #q.tail==1 and draws==3)
            player.held=false; update(p); update(q)
            r=pedestal(73,3); update(r); assert(#r.tail==0)
            player.held=true; roomIndex=2; M.onPostNewRoom(); update(r)
            assert(#r.tail==1 and draws==4,'normal reacquisition inherited golden bonus')
        ''')

    def test_slot_scoped_provider_ignores_other_owner_and_stale_slot(self):
        self.lua.execute('''
            epiphanyProvider(); player.slots={[0]=999}
            function player:GetActiveItem(slot) return self.slots[slot] or 0 end
            other={slots={[0]=666},goldenSlots={["0"]=999}}
            function other:GetActiveItem(slot) return self.slots[slot] or 0 end
            players[2]=other
            p=pedestal(71,1); update(p); assert(#p.tail==1,'nonholder gold leaked')
            Epiphany:SetGoldenItem(999,player,1); update(p)
            assert(#p.tail==1,'stale secondary gold upgraded normal primary')
            Epiphany:SetGoldenItem(999,player,0); update(p); assert(#p.tail==2)
            player.slots={}; player.held=false
            q=pedestal(72,2); update(q); assert(#q.tail==0,'removed active still grants')
            other.slots[0]=999; roomIndex=2; M.onPostNewRoom(); update(q)
            assert(#q.tail==2 and draws==4,'second actual holder not recognized')
        ''')

    def test_player_slot_provider_precedes_standalone_global_ledger(self):
        self.lua.execute('''
            goldenProvider(); GoldenItems:SetGoldenItem(999); epiphanyProvider()
            player.slots={[2]=999}
            function player:GetActiveItem(slot) return self.slots[slot] or 0 end
            p=pedestal(71,1); update(p); assert(#p.tail==1)
            Epiphany:SetGoldenItem(999,player,2); update(p); assert(#p.tail==2)
            Epiphany:ExaustGoldenItem(999,player,2)
            q=pedestal(72,2); update(q); assert(#q.tail==1)
        ''')

    def test_provider_query_never_writes_or_upgrades_an_ordinary_active(self):
        self.lua.execute('''
            goldenProvider()
            GoldenItems.SetGoldenItem=function() error('production mutated provider') end
            p=pedestal(71,1); for _=1,10 do update(p) end
            assert(#p.tail==1 and next(GoldenItems.goldActiveList)==nil)
        ''')

    def test_same_seed_copies_have_independent_ownership_and_saves(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2}); update(p); local bonus=p.tail[3]
            q=pedestal(71,1,copy(p.tail)); saves[key(q)]=copy(saves[key(p)])
            update(q); p.tail={2,2,55}
            M.onCollectibleCycleRewritten(p,{[bonus]=55}); update(p); update(q)
            assert(table.concat(q.tail,',')==table.concat({2,2,bonus},','))
            assert(saves[key(p)].severedOath.bonusItems[1]==55)
            assert(saves[key(q)].severedOath.bonusItems[1]==bonus and draws==1)
            roomIndex=2; M.onPostNewRoom(); roomIndex=1; M.onPostNewRoom()
            saves=copy(disk); M.onGameStarted(nil,true); update(q); update(p)
            assert(#q.tail==3 and #p.tail==3 and draws==1)
        ''')

    def test_fresh_wrappers_share_one_state_but_reused_addresses_do_not(self):
        self.lua.execute('''
            p=pedestal(71,1); update(p)
            local wrapper=setmetatable({}, {__index=p,__newindex=p})
            update(wrapper); assert(#p.tail==1 and draws==1)
            p.removed=true; saves[key(p)]=nil
            q=pedestal(71,1); q.identity=p.identity; update(q)
            assert(#q.tail==1 and draws==2,'expired pointer claimed a new pedestal')
        ''')

    def test_display_only_native_copy_keeps_spent_ledger_without_resurrecting_source_bonus(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2}); update(p)
            local sourceTail=table.concat(p.tail,',')
            local sourceBonus=saves[key(p)].severedOath.bonusItems[1]
            q=pedestal(71,2,{}); saves[key(q)]=copy(saves[key(p)])
            update(q)
            assert(#q.tail==0 and draws==1,'native displayed-only copy resurrected source bonus')
            q.SubType=3; q.tail={2,2}; update(q); update(p)
            assert(table.concat(q.tail,',')=='2,2' and table.concat(p.tail,',')==sourceTail)
            assert(saves[key(p)].severedOath.bonusItems[1]==sourceBonus and draws==1)
        ''')

    def test_external_same_seed_transform_never_restores_old_bonus_even_after_reload(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2,3}); update(p)
            local old=p.tail[4]; p.tail={2,2,3,55}; p.data={}
            for i=1,1000 do p:rotate(); update(p) end
            assert(#p.tail==4 and draws==1)
            for _,id in ipairs(p.tail) do assert(id~=old) end
            assert(p.SubType~=old)
            saves=copy(disk); M.onGameStarted(nil,true); update(p)
            assert(#p.tail==4 and draws==1)
        ''')

    def test_legitimate_duplicates_are_preserved_within_and_between_pedestals(self):
        self.lua.execute('''
            function pool:GetCollectible(_,decrease)
                if decrease then draws=draws+1 end; return 200
            end
            p=pedestal(71,1,{2,2,3}); q=pedestal(72,1,{2,2,3})
            update(p); update(q); assert(p.tail[4]==200 and q.tail[4]==200 and draws==2)
            p:AddCollectibleCycle(200)
            for i=1,1000 do p:rotate(); update(p); q:rotate(); update(q) end
            assert(#p.tail==5 and #q.tail==4 and draws==2)
        ''')

    def test_failed_append_never_depletes_and_retries_after_recovery(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2,3}); local add=p.AddCollectibleCycle
            p.AddCollectibleCycle=function() return false end
            update(p); assert(draws==0 and #p.tail==3)
            for _=1,100 do update(p) end; assert(preview==1,'retry busy loop')
            p.AddCollectibleCycle=add; update(p)
            assert(draws==1 and #p.tail==4)
            for _=1,100 do update(p) end; assert(draws==1)
        ''')

    def test_transient_append_error_retries_without_repeated_pool_charges(self):
        self.lua.execute('''
            p=pedestal(71,1); local add=p.AddCollectibleCycle; local fail=true
            p.AddCollectibleCycle=function(self,id) if fail then error('unready') end; return add(self,id) end
            update(p); assert(draws==0 and #p.tail==0)
            fail=false; frame=frame+30; update(p)
            assert(draws==1 and #p.tail==1)
        ''')

    def test_capacity_becoming_available_grants_only_the_unpaid_slots(self):
        self.lua.execute('''
            goldenProvider(); GoldenItems:SetGoldenItem(999)
            p=pedestal(71,1,{2,2,2,2,2,2,2,2}); update(p)
            assert(draws==0); p.tail={2,2,2,2,2,2,2}; update(p)
            assert(draws==1 and #p.tail==8)
            table.remove(p.tail,1); update(p)
            assert(draws==2 and #p.tail==8)
            for i=1,100 do p:rotate(); update(p) end; assert(draws==2)
        ''')

    def test_commit_override_delivers_actual_duplicate_and_preserves_foreign_order(self):
        self.lua.execute('''
            function pool:GetCollectible(_,decrease)
                if decrease then
                    draws=draws+1
                    assert(#p.tail==4 and p.tail[4]==200,'depletion preceded delivery')
                    update(p) -- Provider callback re-entry must not grant another bonus.
                    return 2
                end
                return 200
            end
            p=pedestal(71,1,{2,2,3}); update(p)
            assert(table.concat(p.tail,',')=='2,2,3,2' and draws==1)
            assert(saves[key(p)].severedOath.bonusItems[1]==2)
            for i=1,100 do p:rotate(); update(p) end
            saves=copy(disk); M.onGameStarted(nil,true); update(p)
            assert(#p.tail==4 and draws==1)
        ''')

    def test_preview_callback_source_mutation_does_not_charge_or_append(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2})
            function pool:GetCollectible(_,decrease)
                assert(not decrease,'charged changed source'); p.SubType=50; return 200
            end
            update(p); assert(#p.tail==2 and p.SubType==50 and draws==0)
        ''')

    def test_pool_exception_keeps_delivered_reward_without_second_charge(self):
        self.lua.execute('''
            function pool:GetCollectible(_,decrease)
                if decrease then draws=draws+1; error('provider failed after decrement') end
                return 200
            end
            p=pedestal(71,1); update(p)
            for i=1,100 do frame=frame+30; update(p) end
            assert(p.tail[1]==200 and #p.tail==1 and draws==1 and #errors==1)
            saves=copy(disk); M.onGameStarted(nil,true); update(p); assert(draws==1)
        ''')

    def test_delayed_paid_swap_survives_save_without_redraw(self):
        self.lua.execute('''
            function pool:GetCollectible(_,decrease)
                if decrease then draws=draws+1; return 55 end
                return 200
            end
            p=pedestal(71,1,{2,2}); local add=p.AddCollectibleCycle
            p.AddCollectibleCycle=function(self,id) if id==55 then return false end; return add(self,id) end
            update(p); assert(table.concat(p.tail,',')=='2,2,200' and draws==1)
            assert(saves[key(p)].severedOath.pendingSwap.to==55)
            saves=copy(disk); M.onGameStarted(nil,true); p.AddCollectibleCycle=add; update(p)
            assert(table.concat(p.tail,',')=='2,2,55' and draws==1)
            assert(saves[key(p)].severedOath.pendingSwap==nil)
        ''')

    def test_external_replacement_cancels_delayed_swap_instead_of_resurrection(self):
        self.lua.execute('''
            function pool:GetCollectible(_,decrease)
                if decrease then draws=draws+1; return 55 end; return 200
            end
            p=pedestal(71,1); local add=p.AddCollectibleCycle
            p.AddCollectibleCycle=function(self,id) if id==55 then return false end; return add(self,id) end
            update(p); p.tail={66}; p.AddCollectibleCycle=add; update(p)
            assert(#p.tail==1 and p.tail[1]==66 and draws==1)
            assert(saves[key(p)].severedOath.pendingSwap==nil)
        ''')

    def test_duplicate_only_preview_does_not_consume_pool_or_spin_each_frame(self):
        self.lua.execute('''
            function pool:GetCollectible(_,decrease)
                if decrease then draws=draws+1 else preview=preview+1 end; return 2
            end
            p=pedestal(71,1,{2,2}); update(p)
            for i=1,100 do p:rotate(); update(p) end
            assert(preview==12 and draws==0 and #p.tail==2)
        ''')

    def test_pool_dump_includes_room_blacklist_and_reports_unknown_capabilities(self):
        self.lua.execute('''
            local output={}; Isaac.ConsoleOutput=function(s) output[#output+1]=s end
            function pool:GetCollectiblesFromPool() return {{itemID=123,weight=1,removeOn=0.1,isUnlocked=true}} end
            function pool:GetRemovedCollectibles() return {} end
            function pool:GetRoomBlacklistedCollectibles() return {[123]=true} end
            M.onExecuteCmd(nil,'cb_pool','0 123')
            assert(output[1]:find('available=0') and output[1]:find('roomBlacklisted=true'))
            output={}; M.onExecuteCmd(nil,'cb_excluded','0')
            assert(table.concat(output):find('excluded count=1'))
            pool.GetRoomBlacklistedCollectibles=nil; output={}
            M.onExecuteCmd(nil,'cb_pool','0 123')
            assert(output[1]:find('available=n/a') and output[1]:find('roomBlacklisted=n/a'))
        ''')

    def test_native_reference_expiry_and_reentrant_callbacks_do_not_duplicate_gold_grants(self):
        self.lua.execute('''
            goldenProvider(); GoldenItems:SetGoldenItem(999)
            local original=pool.GetCollectible
            function pool:GetCollectible(poolType,decrease,seed)
                if decrease then
                    p.generation=(p.generation or 0)+1; p.data={}
                    M.onPostPickupInit(nil,p); update(p)
                end
                return original(self,poolType,decrease,seed)
            end
            p=pedestal(71,1,{2,2}); update(p); update(p)
            assert(#p.tail==4 and draws==2)
            local a,b=p.tail[3],p.tail[4]
            p.generation=p.generation+1; p.tail={2,2,55,66}
            M.onCollectibleCycleRewritten(p,{[a]=55,[b]=66}); update(p)
            assert(#p.tail==4 and draws==2)
            assert(saves[key(p)].severedOath.bonusItems[1]==55)
            assert(saves[key(p)].severedOath.bonusItems[2]==66)
        ''')

    def test_append_that_throws_after_delivery_is_not_granted_twice(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2}); local add=p.AddCollectibleCycle
            p.AddCollectibleCycle=function(self,id) add(self,id); error('after native append') end
            update(p); p.AddCollectibleCycle=add; frame=frame+30; update(p)
            assert(#p.tail==3 and draws==1)
        ''')

    def test_golden_second_append_failure_keeps_one_reward_and_only_one_charge(self):
        self.lua.execute('''
            goldenProvider(); GoldenItems:SetGoldenItem(999)
            p=pedestal(71,1); local add=p.AddCollectibleCycle
            p.AddCollectibleCycle=function(self,id) if #self.tail==1 then return false end; return add(self,id) end
            update(p); assert(#p.tail==1 and draws==1)
            p.AddCollectibleCycle=add; update(p)
            assert(#p.tail==2 and draws==2)
        ''')

    def test_unreadable_foreign_queue_is_left_intact_without_pool_selection(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,0,3}); update(p)
            q=pedestal(72,1,{[1]=2,[3]=3}); update(q)
            assert(draws==0 and preview==0)
            assert(#p.tail==3 and p.tail[2]==0 and q.tail[3]==3)
        ''')

    def test_use_without_a_player_is_rejected_instead_of_borrowing_player_zero(self):
        self.lua.execute('''
            Isaac.GetPlayer=function() error('must not fall back to player 0') end
            local p=pedestal(71,1,{2})
            for _,missing in ipairs({false,true}) do
                local result=M.onUseItem(nil,999,nil,missing and {} or nil)
                assert(result.Discharge==false and result.ShowAnim==false and result.Remove==false)
            end
            assert(#errors==2 and draws==0 and #stock==1 and #p.tail==1,'nothing split, nothing drawn')
        ''')

    def test_room_entry_diagnostics_stay_silent_when_debug_is_off(self):
        self.lua.execute('''
            Isaac.DebugString=function() error('unconditional diagnostic') end
            ConchBlessing.print=function() error('unconditional diagnostic') end
            M.onGameStarted(nil,false); p=pedestal(71,1); update(p)
            roomIndex=2; M.onPostNewRoom(); update(p)
            assert(draws==1)
        ''')


if __name__ == '__main__':
    unittest.main()
