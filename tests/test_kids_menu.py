"""Family Combo (the Magic Conch's Binge Eater) through its shipped Lua callbacks.

Binge Eater measured in game on 2026-11-07 follows Birthright's rules exactly
(`cb test kids_menu parity`, Binge Eater arm): only a pedestal created while
someone holds it gains a choice. Family Combo gives a familiar item instead of
food, from the pedestal's own seed, never drawn from an item pool (the pools
only say which familiars count: one no pool lists never comes up), so
familiars may repeat. These are Lua regressions with doubles, not proof of engine behaviour.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class KidsMenuTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            package=nil
            PickupVariant={PICKUP_COLLECTIBLE=100,PICKUP_COIN=20}
            EntityType={ENTITY_PICKUP=5}; ItemType={ITEM_PASSIVE=1,ITEM_FAMILIAR=4}; ItemConfig={TAG_QUEST=4096}
            KIDS=900
            function copy(t) local o={} for k,v in pairs(t) do o[k]=type(v)=='table' and copy(v) or v end return o end
            saves={}; writes=0; stock={}; roomIndex=1; serial=0; errors={}; firstVisit=true; dimension=0
            poolCalls=0; frozen={}
            -- Items: 10-14 familiars (13 hidden, 14 quest), 20 a passive, 30 a locked familiar.
            items={}
            for id=1,40 do items[id]={Type=ItemType.ITEM_PASSIVE,Hidden=false,tags=0,available=true} end
            for id=10,14 do items[id].Type=ItemType.ITEM_FAMILIAR end
            items[13].Hidden=true; items[14].tags=ItemConfig.TAG_QUEST
            items[30].Type=ItemType.ITEM_FAMILIAR; items[30].available=false
            for _,item in pairs(items) do
                function item:HasTags(t) return self.tags & t ~= 0 end
                function item:IsAvailable() return self.available end
            end
            config={GetCollectibles=function() return {Size=41} end,GetCollectible=function(_,id) return items[id] end}
            function GetPtrHash(p) return p.identity end
            player={held=true,dead=false,ghost=false}
            function player:HasCollectible(id) return id==KIDS and self.held end
            function player:IsDead() return self.dead end
            function player:IsCoopGhost() return self.ghost end
            players={player}
            pool={GetCollectible=function() poolCalls=poolCalls+1; return 1 end}
            room={IsFirstVisit=function() return firstVisit end}
            level={GetCurrentRoomIndex=function() return roomIndex end,GetStage=function() return 1 end,
                GetStageType=function() return 0 end,GetDimension=function() return dimension end,
                GetCurrentRoomDesc=function() return {Data={StageID=dimension==2 and 35 or 1,Subtype=dimension==2 and 33 or 0}} end}
            game={GetRoom=function() return room end,GetLevel=function() return level end,GetItemPool=function() return pool end,
                GetNumPlayers=function() return #players end,GetPlayer=function(_,i) return players[i+1] end}
            function Game() return game end
            function RNG()
                local r={state=1}
                function r:SetSeed(seed,shift) assert(seed~=0) self.state=seed+shift end
                function r:RandomInt(n) self.state=(self.state*1103515245+12345)%2147483648; return self.state%n end
                return r
            end
            Isaac={GetItemIdByName=function() return KIDS end,GetItemConfig=function() return config end,
                GetRoomEntities=function() return stock end}
            ConchBlessing={printError=function(s) errors[#errors+1]=s end,printDebug=function() end,
                upgrade={isCycleFrozen=function(p) return frozen[p.identity]==true end},
                SaveManager={
                    GetNoRerollPickupSave=function(p) local k=p.InitSeed; saves[k]=saves[k] or {}; return saves[k] end,
                    TryGetNoRerollPickupSave=function(p) return saves[p.InitSeed] end,
                    Save=function() writes=writes+1 end}}
            function pedestal(seed,head,tail)
                serial=serial+1
                local p={identity=serial,Type=5,Variant=100,InitSeed=seed,SubType=head or 1,tail=copy(tail or {}),data={},Touched=false}
                function p:GetData() return self.data end
                function p:GetCollectibleCycle() return copy(self.tail) end
                function p:AddCollectibleCycle(id) if #self.tail>=8 then return false end self.tail[#self.tail+1]=id return true end
                function p:Exists() return not self.removed end
                function p:ToPickup() return self end
                stock[#stock+1]=p
                return p
            end
        ''')
        self.lua.execute((ROOT / 'scripts/items/collectibles/kids_menu.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            M=ConchBlessing.kidsmenu
            function update(p) M.onPickupUpdate(nil,p) end
            -- A pickup appearing in the room: its init callback, then updates.
            function appear(p) M.onPickupInit(nil,p); update(p); update(p) end
            function enter(index,first)
                roomIndex=index; firstVisit=first
                M.onNewRoom()
                for _,p in ipairs(stock) do update(p) end
            end
            function familiar(id) return items[id] and items[id].Type==ItemType.ITEM_FAMILIAR end
        ''')

    def start(self, continued=False):
        self.lua.execute(f'M.onGameStarted(nil,{str(continued).lower()}); for _,p in ipairs(stock) do update(p) end')

    def test_the_familiar_list_holds_only_available_unhidden_familiars(self):
        self.lua.execute('''
            local list=M.familiarItems()
            assert(table.concat(list,',')=='10,11,12', table.concat(list,','))
        ''')

    def test_a_familiar_no_pool_lists_is_never_offered(self):
        self.lua.execute('''
            -- pool 0 lists 10 (taken out already: weight 0), pool 2 lists 12;
            -- 11 is in no pool, like another mod's upgrade-only item
            lists={[0]={{itemID=10,weight=0},{itemID=20,weight=1}},[1]={},[2]={{itemID=12,weight=1}}}
            pool.GetNumItemPools=function() return 3 end
            pool.GetCollectiblesFromPool=function(_,kind) return lists[kind] end
            local list=M.familiarItems()
            assert(table.concat(list,',')=='10,12', table.concat(list,','))
            for seed=1,40 do assert(M.familiarFor(seed)~=11,'a pool-less familiar was offered') end
            assert(poolCalls==0,'the pools are only read')
        ''')

    def test_without_pool_lists_every_familiar_stays(self):
        self.lua.execute('''
            assert(pool.GetCollectiblesFromPool==nil)
            assert(table.concat(M.familiarItems(),',')=='10,11,12')
        ''')

    def test_a_seed_always_names_the_same_familiar_and_familiars_may_repeat(self):
        self.lua.execute('''
            local seen, repeats = {}, 0
            for seed=1,60 do
                local id=M.familiarFor(seed)
                assert(id==M.familiarFor(seed) and familiar(id))
                if seen[id] then repeats=repeats+1 end
                seen[id]=true
            end
            assert(repeats>0, 'duplicates across pedestals are allowed')
            assert(M.familiarFor(0)~=nil, 'a zero seed still picks')
            assert(poolCalls==0, 'no item pool is touched')
        ''')

    def test_first_visit_stock_gains_one_familiar_at_the_end_of_its_circle(self):
        self.lua.execute('a=pedestal(101,1,{5}); b=pedestal(102,2)')
        self.start()
        self.lua.execute('''
            assert(#a.tail==2 and a.tail[1]==5 and familiar(a.tail[2]), 'after the native choice')
            assert(#b.tail==1 and familiar(b.tail[1]))
            for i=1,5 do update(a); update(b) end
            assert(#a.tail==2 and #b.tail==1, 'only once')
            assert(saves[101].kidsMenu.granted==a.tail[2] and poolCalls==0)
        ''')

    def test_items_seen_before_never_gain_even_when_held_later(self):
        self.lua.execute('player.held=false; a=pedestal(201,1)')
        self.start()
        self.lua.execute('''
            assert(#a.tail==0)
            player.held=true
            enter(2,true); stock={a}; enter(1,false)
            assert(#a.tail==0, 'a revisit with the item adds nothing')
            local b=pedestal(202,3); appear(b)
            assert(#b.tail==1 and familiar(b.tail[1]), 'a pedestal created now gains one')
        ''')

    def test_gaining_the_item_mid_room_reaches_only_later_pedestals(self):
        self.lua.execute('player.held=false; old=pedestal(301,1)')
        self.start()
        self.lua.execute('''
            player.held=true
            for i=1,3 do update(old) end
            assert(#old.tail==0, 'an existing pedestal stays')
            local new=pedestal(302,2); appear(new)
            assert(#new.tail==1)
        ''')

    def test_a_dropped_active_and_the_death_certificate_area_never_gain(self):
        self.start()
        self.lua.execute('''
            local dropped=pedestal(401,58); dropped.Touched=true; appear(dropped)
            assert(#dropped.tail==0, 'an active dropped onto a pedestal')
            dimension=2; enter(5,true)
            local dc=pedestal(402,7); appear(dc)
            assert(#dc.tail==0, 'Death Certificate stock')
        ''')

    def test_a_reroll_is_a_new_pedestal_and_a_turn_is_not(self):
        self.start()
        self.lua.execute('''
            local p=pedestal(501,1); appear(p)
            assert(#p.tail==1)
            -- A native turn re-initializes the same pedestal and seed.
            p.tail[#p.tail+1]=p.SubType; p.SubType=table.remove(p.tail,1)
            M.onPickupInit(nil,p); update(p)
            assert(#p.tail==1, 'a turn adds nothing')
            -- A reroll gives the same entity a new seed and a new item.
            p.InitSeed=777; p.SubType=40; p.tail={}
            M.onPickupInit(nil,p); update(p)
            assert(#p.tail==1 and familiar(p.tail[1]), 'the rerolled pedestal gains one')
        ''')

    def test_a_copy_gets_its_own_choice_and_a_twin_turn_keeps_its_record(self):
        self.start()
        self.lua.execute('''
            local source=pedestal(601,1); appear(source)
            -- Diplopia: a fresh entity with the same seed; SaveManager copied the
            -- record before the init callback.
            local copyP=pedestal(601,1)
            assert(M.onDupePickupDataLoad(nil,nil,copyP)==nil)
            M.onPickupInit(nil,copyP); update(copyP)
            assert(#copyP.tail==1 and copyP.tail[1]==source.tail[1], 'the copy shows the same familiar, like Binge Eater')
            -- A native turn of a pedestal already seen refuses a twin's record.
            assert(M.onDupePickupDataLoad(nil,nil,source)==true)
        ''')

    def test_a_held_upgrade_and_a_full_circle_wait(self):
        self.start()
        self.lua.execute('''
            local p=pedestal(701,1)
            frozen[p.identity]=true
            appear(p)
            assert(#p.tail==0, 'nothing is added while an upgrade holds the queue')
            frozen[p.identity]=nil; update(p)
            assert(#p.tail==1)
            local full=pedestal(702,1,{2,3,4,5,6,7,8,9}); appear(full)
            assert(#full.tail==8, 'a full circle waits')
            table.remove(full.tail); update(full)
            assert(#full.tail==8 and familiar(full.tail[8]), 'and gains once there is room')
        ''')

    def test_a_severed_oath_split_product_never_gains(self):
        self.start()
        self.lua.execute('''
            local p=pedestal(801,1)
            M.onPickupInit(nil,p)
            saves[801].severedOath={split=true}
            update(p); update(p)
            assert(#p.tail==0 and saves[801].kidsMenu.eligible==false)
        ''')

    def test_losing_the_item_keeps_given_choices_and_stops_new_ones(self):
        self.start()
        self.lua.execute('''
            local p=pedestal(901,1); appear(p)
            player.held=false
            for i=1,3 do update(p) end
            assert(#p.tail==1, 'the given choice stays')
            local later=pedestal(902,2); appear(later)
            assert(#later.tail==0)
            -- A dead holder or a co-op ghost does not count.
            player.held=true; player.dead=true
            local q=pedestal(903,2); appear(q); assert(#q.tail==0)
            player.dead=false; player.ghost=true
            local r=pedestal(904,2); appear(r); assert(#r.tail==0)
        ''')

    def test_continue_reads_the_saved_answers(self):
        self.start()
        self.lua.execute('''
            local p=pedestal(1001,1); appear(p)
            local granted=p.tail[1]
            -- Continue: the run's state is reloaded; the room is not a first visit.
            M.onGameExit()
            stock={}; local again=pedestal(1001,1,{granted}); local other=pedestal(1002,3)
        ''')
        self.start(continued=True)
        self.lua.execute('''
            assert(#stock[1].tail==1, 'the saved grant is not repeated')
            assert(#stock[2].tail==0, 'a pedestal with no record seen on Continue gains nothing')
        ''')

    def test_nothing_happens_before_game_start(self):
        self.lua.execute('''
            local p=pedestal(1101,1)
            M.onPickupInit(nil,p); update(p); M.onNewRoom()
            assert(#p.tail==0 and next(saves)==nil)
        ''')


if __name__ == '__main__':
    unittest.main()
