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
            CollectibleType={COLLECTIBLE_NULL=0}; ActiveSlot={}; PickupVariant={PICKUP_COLLECTIBLE=100}
            EntityType={ENTITY_PICKUP=5}; ItemPoolType={POOL_TREASURE=0}
            function copy(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and copy(v) or v end return o end
            saves={}; writes=0; draws=0; preview=0; stock={}; roomIndex=1
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
                GetItemPool=function() return pool end,GetFrameCount=function() return 10 end}
            function Game() return game end
            Isaac={DebugString=function() end,GetItemIdByName=function() return 999 end,
                GetItemConfig=function() return {GetCollectible=function(_,id) return id>0 and {} or nil end} end,
                GetRoomEntities=function() return stock end}
            ConchBlessing={printDebug=function() end,print=function() end,SaveManager={
                GetNoRerollPickupSave=function(p) saves[p.InitSeed]=saves[p.InitSeed] or {}; return saves[p.InitSeed] end,
                TryGetNoRerollPickupSave=function(p) return saves[p.InitSeed] end,
                Save=function() writes=writes+1; disk=copy(saves) end}}
            function pedestal(seed,head,tail)
                local p={Type=5,Variant=100,InitSeed=seed,SubType=head or 1,tail=tail or {},data={},Price=15,OptionsPickupIndex=777}
                function p:GetData() return self.data end
                function p:GetCollectibleCycle() return copy(self.tail) end
                function p:AddCollectibleCycle(id)
                    if #self.tail>=8 then return false end
                    self.tail[#self.tail+1]=id; return true
                end
                function p:Exists() return true end
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

    def test_ordinary_birthright_does_not_block_and_existing_order_is_untouched(self):
        self.lua.execute('''
            p=pedestal(71,1,{2,2,3,4}); update(p)
            assert(#p.tail==5 and table.concat(p.tail,',',1,4)=='2,2,3,4')
            assert(draws==1 and p.Price==15 and p.OptionsPickupIndex==777)
            q=pedestal(72,10); update(q)
            assert(#q.tail==1 and draws==2,'Isaac Birthright prevented +1')
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

    def test_rebuild_repairs_only_owned_choices_without_pool_draws(self):
        self.lua.execute('''
            goldenProvider(); p=pedestal(71,1,{2,3}); GoldenItems:SetGoldenItem(999); update(p)
            local a,b=p.tail[3],p.tail[4]; p.tail={5,5,6}; update(p)
            assert(table.concat(p.tail,',')==table.concat({5,5,6,a,b},','))
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
            p.tail={}; update(p); assert(p.tail[1]==a and p.tail[2]==b and draws==2)
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
            saves[71]={severedOath={bonusItem=20,poolType=0}}
            update(p); assert(#p.tail==2 and draws==1)
            local b=p.tail[2]; p.tail={30,40}
            M.onCollectibleCycleRewritten(p,{[20]=30,[b]=40}); update(p)
            assert(#p.tail==2 and draws==1)
            assert(saves[71].severedOath.bonusItems[1]==30 and saves[71].severedOath.bonusItems[2]==40)
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
            q=pedestal(72,2); saves[72]={severedOath={split=true,splitItem=2}}
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


if __name__ == '__main__':
    unittest.main()
