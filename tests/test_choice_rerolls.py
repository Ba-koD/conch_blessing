"""Reroll identity regressions against shipped Lua with SaveManager doubles.

These prove Lua state transitions, not native dice, payment or real Continue.
"""
from pathlib import Path
import unittest
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class AtroposOptionRerollTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            stock={}; run={}; disk=nil; saveOK=true; writes=0; callbacks={}
            function clone(t) local r={} for k,v in pairs(t) do r[k]=type(v)=='table' and clone(v) or v end return r end
            ConchBlessing={printError=function() end,originalMod={AddCallback=function(_,id,fn) callbacks[id]=fn end}}
            ConchBlessing.SaveManager={IsLoaded=function() return true end,
                GetRunSave=function() return run end,TryGetRunSave=function() return run end,
                GetRerollPickupSave=function(p) p.save=p.save or {};return p.save end,
                TryGetRerollPickupSave=function(p) return p.save end,
                SaveCallbacks={POST_DATA_SAVE=90},Save=function()
                    if saveOK then writes=writes+1;disk=clone(run);callbacks[90]() end
                end}
            roomIndex=84
            desc={ListIndex=4,GridIndex=84,SafeGridIndex=84,SpawnSeed=51,DecorationSeed=61,Data={Type=1,Variant=4}}
            level={GetDimension=function() return 0 end,GetStage=function() return 1 end,
                GetStageType=function() return 0 end,GetCurrentRoomIndex=function() return roomIndex end,
                GetCurrentRoomDesc=function() return desc end}
            function Game() return {GetLevel=function() return level end} end
            Isaac={GetRoomEntities=function() return stock end}
            ModCallbacks={}; CollectibleType={}; PickupVariant={PICKUP_COLLECTIBLE=100}
            package.loaded['scripts.rooms.native_return_door']={}
            package.loaded['scripts.rooms.gallery_exit_door']={}
            package.loaded['scripts.lib.isaacscript-common']={}
            function pedestal(seed,option)
                local p={InitSeed=seed,OptionsPickupIndex=option,Exists=function() return true end}
                function p:ToPickup() return self end
                stock[#stock+1]=p;return p
            end
        ''')
        source=(ROOT/'scripts/items/trinkets/atropos.lua').read_text(encoding='utf-8')
        before,after=source.rsplit('return M',1)
        self.lua.execute(before+'M.updateChoice=updateChoiceOptionGroups; return M'+after)
        self.lua.execute('M=ConchBlessing.atropos')

    def test_reroll_changed_seed_restores_each_original_group_after_last_owner_loss(self):
        self.lua.execute('''
            a=pedestal(10,777); b=pedestal(11,888)
            assert(M.updateChoice(true) and a.OptionsPickupIndex==0 and b.OptionsPickupIndex==0)
            a.InitSeed=20;b.InitSeed=21 -- provider preserves RerollSave on real seed morph
            assert(M.updateChoice(true));a.InitSeed=30;b.InitSeed=31
            assert(M.updateChoice(false))
            assert(a.OptionsPickupIndex==777 and b.OptionsPickupIndex==888)
            assert(a.save.atroposChoiceOptionSource==nil and b.save.atroposChoiceOptionSource==nil)
        ''')

    def test_continue_rebind_uses_provider_save_not_runtime_pointer_or_position(self):
        self.lua.execute('''
            a=pedestal(10,777);assert(M.updateChoice(true));local saved=clone(a.save)
            stock={};a=pedestal(99,0);a.save=saved
            assert(M.updateChoice(false) and a.OptionsPickupIndex==777)
        ''')

    def test_migrates_old_seed_ledger_before_the_next_reroll(self):
        self.lua.execute('''
            run.atroposChoiceOptionGroups={version=1,rooms={['1:0:84:4:51:61:0']={['10']=777}}}
            a=pedestal(10,0);assert(M.updateChoice(true));assert(a.save.atroposChoiceOptionSource)
            a.InitSeed=20;assert(M.updateChoice(false) and a.OptionsPickupIndex==777)
        ''')

    def test_foreign_nonzero_group_and_unrelated_zero_remain_untouched_on_loss(self):
        self.lua.execute('''
            a=pedestal(10,777);b=pedestal(11,0);assert(M.updateChoice(true))
            a.OptionsPickupIndex=999;a.InitSeed=20
            assert(M.updateChoice(false));assert(a.OptionsPickupIndex==999 and b.OptionsPickupIndex==0)
            a.OptionsPickupIndex=0;assert(M.updateChoice(false));assert(a.OptionsPickupIndex==0)
        ''')

    def test_missing_pickup_storage_and_failed_disk_save_never_unlink_new_choices(self):
        for setup in ('ConchBlessing.SaveManager.GetRerollPickupSave=nil', 'saveOK=false'):
            with self.subTest(setup=setup):
                self.setUp()
                self.lua.execute(setup+'''
                    a=pedestal(10,777);assert(not M.updateChoice(true));assert(a.OptionsPickupIndex==777)
                    assert(not a.save or a.save.atroposChoiceOptionSource==nil)
                ''')

    def test_failed_save_while_adding_a_new_group_restores_previous_owned_zero(self):
        self.lua.execute('''
            a=pedestal(10,777);assert(M.updateChoice(true));a.InitSeed=20
            b=pedestal(11,888);saveOK=false
            assert(not M.updateChoice(true));assert(a.OptionsPickupIndex==777 and b.OptionsPickupIndex==888)
        ''')


class AngelsCrownRerollTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            ConchBlessing={printDebug=function() end,printError=function() end,TrinketUtils={}}
            ConchBlessing.SaveManager={GetRerollPickupSave=function(p) return p.save end,
                TryGetRerollPickupSave=function(p) return p.save end,Save=function() end}
            EffectVariant={POOF01=1};RoomType={ROOM_SECRET=7,ROOM_SUPERSECRET=8,ROOM_ULTRASECRET=29}
            BackdropType={CATHEDRAL=1};EntityType={ENTITY_PICKUP=5};PickupVariant={PICKUP_COLLECTIBLE=100}
            Isaac={GetItemConfig=function() return {GetCollectible=function(_,id) return {ShopPrice=id==2 and 25 or 15} end} end,
                FindByType=function() return stock end}
            function GetPtrHash(p) return p end
            stock={}
            function pedestal(seed,id)
                local p={InitSeed=seed,SubType=id,Price=0,AutoUpdatePrice=true,ShopItemId=5,OptionsPickupIndex=7,save={}}
                function p:ToPickup() return self end
                stock[#stock+1]=p; return p
            end
        ''')
        source=(ROOT/'scripts/items/trinkets/angels_crown.lua').read_text(encoding='utf-8')
        self.lua.execute(source+'''
            M=ConchBlessing.angelscrown
            M.test={mark=markDeal,restore=restoreDeals,refresh=refreshRerolledDeals}
        ''')

    def test_d6_seed_change_keeps_deal_and_new_item_price(self):
        self.lua.execute('''
            p=pedestal(10,1);assert(M.test.mark(p));M.test.restore()
            p.InitSeed=99;p.SubType=2;p.Price=15;p.AutoUpdatePrice=true
            M.test.refresh();assert(p.Price==25 and p.AutoUpdatePrice==false and p.ShopItemId==-1)
        ''')

    def test_metadata_drift_is_repaired_even_when_item_and_positive_price_do_not_change(self):
        for drift in ('p.AutoUpdatePrice=true', 'p.ShopItemId=1', 'p.Price=1', 'p.OptionsPickupIndex=777'):
            with self.subTest(drift=drift):
                self.setUp()
                self.lua.execute('p=pedestal(10,1);M.test.mark(p);M.test.restore();'+drift+'''
                    M.test.refresh();assert(p.Price==15 and p.AutoUpdatePrice==false
                        and p.ShopItemId==-1 and p.OptionsPickupIndex==0)
                ''')

    def test_unmarked_replacement_does_not_inherit_an_old_deal(self):
        self.lua.execute('''
            p=pedestal(10,1);M.test.mark(p);M.test.restore()
            p.save={};p.SubType=2;p.Price=0;p.AutoUpdatePrice=true
            M.test.refresh();assert(p.Price==0 and p.AutoUpdatePrice==true)
        ''')

    def test_purchased_active_replacement_is_released_and_never_repriced(self):
        self.lua.execute('''
            p=pedestal(10,1);M.test.mark(p);M.test.restore()
            p.SubType=2;p.InitSeed=99;p.Touched=true
            M.test.refresh();assert(p.Price==0 and p.save.angelsCrownDeal==nil)
            M.test.restore();assert(p.Price==0)
        ''')


class FixtureOracleTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            builders={};checks={};requires={};acts={};waits={}
            S={add=function(key,name,_,build) builders[key..' '..name]=build end,sequenceBundle=function() end,link=function() end}
            H={fireWeaponAtTarget=function() end,target=function() return {Size=17,HitPoints=100} end}
            package.loaded['scripts.dev.item_scenarios']=S
            package.loaded['scripts.dev.item_test_support']=H
            ModCallbacks={}; CollectibleType={COLLECTIBLE_GLITCHED_CROWN=689,COLLECTIBLE_BINGE_EATER=664,COLLECTIBLE_BIRTHRIGHT=619}
            ConchBlessing={soflam={_pendingStrikes={}}};EntityType={ENTITY_BOMB=4,ENTITY_PICKUP=5};PickupVariant={PICKUP_COLLECTIBLE=100}
            EntityCollisionClass={ENTCOLL_ALL=4}
            function Vector(x,y) return setmetatable({X=x,Y=y},{__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end}) end
            Vector=setmetatable({Zero=Vector(0,0)}, {__call=function(_,x,y)
                return setmetatable({X=x,Y=y},{__add=function(a,b) return Vector(a.X+b.X,a.Y+b.Y) end}) end})
            frame=0;function Game() return {GetFrameCount=function() return frame end} end
            Isaac={FindByType=function() return stock or {} end}
            plan={section=function() end,wait=function() end,note=function() end,
                act=function(fn) acts[#acts+1]=fn end,
                require=function(label,fn) requires[label]=fn end,
                check=function(label,fn) checks[label]=checks[label] or {};table.insert(checks[label],fn) end,
                waitUntil=function(fn,_,label) waits[label]=waits[label] or fn end}
        ''')

    def prepare_soflam(self):
        self.lua.execute((ROOT/'scripts/dev/item_test_synergies.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            builders['SOFLAM mr_mega_and_multishot'](plan,999)
            ctx={target={HitPoints=100},weaponTargetPosition=Vector(0,0),weaponHitAt=100}
            acts[4]({},ctx)
        ''')

    def test_soflam_native_radius_17_separates_all_range_witnesses(self):
        self.prepare_soflam()
        self.lua.execute('''
            assert(ctx.nearDistance-ctx.nearTarget.Size>75)
            assert(ctx.nearDistance+ctx.nearTarget.Size<112.5)
            assert(ctx.outsideDistance-ctx.outsideTarget.Size>112.5)
            local range=checks['Mr. Mega extends range once; outside enemy remains unharmed']
            assert(range[1](nil,ctx));assert(not range[2](nil,ctx)) -- Mega must actually hit
            ctx.nearTarget.HitPoints=90
            assert(not range[1](nil,ctx));assert(range[2](nil,ctx))
            ctx.outsideTarget.HitPoints=90;assert(not range[2](nil,ctx))
        ''')

    def test_soflam_lockon_observes_rocket_then_damage_and_rejects_wrong_delay(self):
        self.prepare_soflam()
        self.lua.execute('''
            frame=145;ConchBlessing.soflam._pendingStrikes={{phase='rocket',rocketEffect={Exists=function() return true end}}}
            assert(not waits['all real missiles explode'](nil,ctx));assert(ctx.firstRocket==145)
            frame=159;ctx.target.HitPoints=90;ConchBlessing.soflam._pendingStrikes={}
            assert(waits['all real missiles explode'](nil,ctx))
            local timing=checks['missiles respect the 45-update lock-on delay'][1]
            assert(timing(nil,ctx));ctx.firstRocket=130;assert(not timing(nil,ctx))
            ctx.firstRocket=150;assert(not timing(nil,ctx))
            ctx.firstRocket=145;ctx.firstDamage=144;assert(not timing(nil,ctx))
        ''')

    def test_isaac_birthright_requires_one_native_alternate_before_oath(self):
        self.lua.execute((ROOT/'scripts/dev/item_test_pools.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            builders['SEVERED_OATH cycle_stacking'](plan,999)
            tail={22};local p={SubType=11,ToPickup=function(self) return self end,GetCollectibleCycle=function() return tail end}
            stock={p};local player={HasCollectible=function() return false end,GetPlayerType=function() return 0 end}
            local baseline=requires['Isaac Birthright native baseline before Severed Oath']
            assert(baseline(player,{}));tail={};assert(not baseline(player,{}))
            tail={22,33};assert(not baseline(player,{}))
            tail={22};player.HasCollectible=function() return true end;assert(not baseline(player,{}))
        ''')

    def test_oath_reroll_bench_requires_a_new_seed_and_its_own_grants_in_the_same_room(self):
        self.lua.execute('package=nil')
        self.lua.execute((ROOT/'scripts/dev/item_test_pools.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            builders['SEVERED_OATH dice_copy_split'](plan,999)
            builders['SEVERED_OATH golden_cycle'](plan,999)
            room=5;function Game() return {GetLevel=function() return {GetCurrentRoomDesc=function() return {ListIndex=room} end} end} end
            saves={};ConchBlessing.SaveManager={TryGetNoRerollPickupSave=function(p) return saves[p] end}
            function GetPtrHash(p) return p.hash end
            function pedestal(seed,head,tail,grants)
                local p={InitSeed=seed,SubType=head,tail=tail,hash=seed,ToPickup=function(self) return self end,
                    GetCollectibleCycle=function(self) return self.tail end,Exists=function() return true end}
                saves[p]=grants and {severedOath={bonusItems=grants}} or nil
                return p
            end
            local ctx={rollSeeds={[1]=true},rollSeedList={'1'},rollRoom=5}
            local settle=waits['rerolled pedestals settle: D6 1']
            local regrant=checks['a new-seed pedestal gets its own Oath choice again: D6 1'][1]
            stock={pedestal(2,10,{50},{50})}; assert(settle(nil,ctx) and regrant(nil,ctx))
            stock={pedestal(2,50,{10},{50})}; assert(regrant(nil,ctx), 'a turned circle still shows the grant')
            stock={pedestal(1,10,{50},{50})}; assert(not settle(nil,ctx), 'a kept seed is not a reroll')
            stock={pedestal(2,10,{},nil)}; assert(not settle(nil,ctx) and not regrant(nil,ctx), 'no new grant')
            stock={pedestal(2,10,{},{50})}; assert(not regrant(nil,ctx), 'grant not on the pedestal')
            stock={pedestal(2,10,{50,51},{50,51})}; assert(not regrant(nil,ctx), 'a normal Oath grants one')
            stock={pedestal(2,10,{50},{50})}; room=6; assert(not regrant(nil,ctx), 'granted only after leaving'); room=5
            local golden=checks['a new-seed pedestal gets its own Oath choices again: golden D6'][1]
            stock={pedestal(2,10,{50,51},{50,51})}; assert(golden(nil,ctx))
            stock={pedestal(2,10,{50},{50})}; assert(not golden(nil,ctx), 'a golden Oath grants two')
            local copies=checks['Diplopia copies only the shown item while each source keeps its choice'][1]
            local source,copy=pedestal(7,10,{50},{50}),pedestal(8,10,{},nil)
            local copyCtx={beforeCopy=1,copySources={[7]={tail=1,seed=7}}}
            stock={source,copy}; assert(copies(nil,copyCtx))
            copy.tail={60}; assert(not copies(nil,copyCtx), 'a copy gained a choice'); copy.tail={}
            source.tail={}; assert(not copies(nil,copyCtx), 'the source lost its choice'); source.tail={50}
            stock={source}; assert(not copies(nil,copyCtx), 'no copy')
            local morph=checks['a seed-keeping Morph is not a reroll: no new Oath choice'][1]
            local m=pedestal(9,1,{},{50})
            local morphCtx={morphed=m,morphSeed=9,morphGrants='50',morphTail=1}
            assert(morph(nil,morphCtx))
            saves[m]={severedOath={bonusItems={50,70}}}; assert(not morph(nil,morphCtx), 'a Morph re-granted')
            saves[m]={severedOath={bonusItems={50}}}; m.tail={50,70}; assert(not morph(nil,morphCtx), 'choices grew')
        ''')

    def test_oath_ownership_bench_rejects_resurrection_and_sibling_contamination(self):
        self.lua.execute('package=nil')
        self.lua.execute((ROOT/'scripts/dev/item_test_pools.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            builders['SEVERED_OATH cycle_ownership'](plan,999)
            function pickup(head,tail)
                return {SubType=head,tail=tail,ToPickup=function(self) return self end,
                    GetCollectibleCycle=function(self) return self.tail end}
            end
            function EntityPtr(p) return {Ref=p} end
            function GetPtrHash(p) return p.hash end
            local source=pickup(1,{2,2,200}); local sibling=pickup(1,{})
            source.hash=10; sibling.hash=20; source.InitSeed=77; sibling.InitSeed=77
            stock={sibling,source}; local ctx={draws={},copySource=EntityPtr(source),
                copySourceHash=10,copySourceSeed=77,copyHead=1,
                copySourceCycle={total=4,counts={[1]=1,[2]=2,[200]=1}}}
            local copied=requires['native copy retains the displayed choice while source keeps its queue']
            assert(copied(nil,ctx)); assert(ctx.changed.ptr.Ref==source and ctx.untouched.ptr.Ref==sibling)
            sibling.tail={2,2,200}; assert(not copied(nil,ctx))
            sibling.tail={}; sibling.SubType=2; assert(not copied(nil,ctx)); sibling.SubType=1
            source.tail={2,3,200}; assert(not copied(nil,ctx)); source.tail={2,2,200}
            source.hash=30; assert(not copied(nil,ctx)); source.hash=10
            ctx.copySource.Ref=nil; assert(not copied(nil,ctx)); ctx.copySource=EntityPtr(source)
            stock={source,sibling}; assert(copied(nil,ctx))
            source.tail={2,2,55}; ctx.expectedChanged={total=4,counts={[1]=1,[2]=2,[55]=1}}
            local check=checks['foreign same-seed rewrite neither revives old choice nor changes sibling'][1]
            assert(check(nil,ctx))
            source.tail={2,2,55,200}; assert(not check(nil,ctx))
            source.tail={2,2,55}; sibling.tail={2,2,55}; assert(not check(nil,ctx))
            sibling.tail={}; ctx.draws={{id=77}}; assert(not check(nil,ctx)); ctx.draws={}
            -- A native turn expires the source's EntityPtr; its hash and seed still find it.
            ctx.changed.ptr={}; assert(check(nil,ctx), 'a turned pedestal is still the fixture')
            source.hash=30; assert(not check(nil,ctx), 'another pedestal is not the fixture'); source.hash=10
            source.InitSeed=78; assert(not check(nil,ctx), 'a rerolled pedestal is not the fixture')
        ''')


if __name__=='__main__': unittest.main()
