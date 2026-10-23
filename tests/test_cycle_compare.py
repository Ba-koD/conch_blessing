"""Independent cycle-oracle and real bench-plan regressions, not engine proof."""
import itertools
from pathlib import Path
import random
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class CycleCompareTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("package=nil")
        self.c = self.lua.execute((ROOT / "scripts/dev/cycle_compare_support.lua").read_text(encoding="utf-8"))
        self.lua.globals().C = self.c

    def row(self, ids, **kwargs):
        return self.lua.table_from(dict(ring=self.lua.table_from(ids), price=15, options=71, shop=-1, auto=False, **kwargs))

    def test_all_rotations_preserve_duplicate_multiplicity_but_not_reordering(self):
        for n in range(1, 10):
            for sequence in itertools.product((1, 2, 3), repeat=min(n, 5)):
                ring = (list(sequence) * 9)[:n]
                expected = self.c.canonical(self.lua.table_from(ring))
                for offset in range(n):
                    self.assertEqual(expected, self.c.canonical(self.lua.table_from(ring[offset:] + ring[:offset])))
        self.assertNotEqual(self.c.canonical(self.lua.table_from([1, 2, 1, 3])),
                            self.c.canonical(self.lua.table_from([1, 1, 2, 3])))

    def test_addition_accepts_native_rotations_and_duplicate_selected_bonus(self):
        rng = random.Random(104729)
        for _ in range(2500):
            before = [rng.randrange(1, 6) for _ in range(rng.randrange(1, 10))]
            extra = rng.choice([1, 2])
            after = before[:]
            for _ in range(min(extra, 9 - len(after))):
                after.insert(rng.randrange(len(after) + 1), rng.randrange(1, 6))
            offset = rng.randrange(len(after))
            self.assertTrue(self.c.addition(self.row(before), self.row(after[offset:] + after[:offset]), extra)[0])

    def test_mutation_oracles_reject_lost_duplicates_reversal_resurrection_and_metadata(self):
        for before, after, extra in [([1, 2, 2, 3], [1, 2, 3, 4], 1),
                                     ([1, 2, 3, 4], [1, 3, 2, 4, 5], 1),
                                     ([1, 2, 3], [1, 3, 2, 9], 1),
                                     ([1, 2], [1, 2, 3, 4], 1),
                                     ([1, 2, 3], [1, 2, 8, 9], 1)]:
            self.assertFalse(self.c.addition(self.row(before), self.row(after), extra)[0])
        for field, value in [("price", 0), ("options", 99), ("shop", 1), ("auto", True)]:
            after = self.row([1, 2, 3]); after[field] = value
            self.assertFalse(self.c.addition(self.row([1, 2]), after, 1)[0])

    def test_invalid_cycles_fail_closed(self):
        for ids in [[], list(range(1, 11)), [1, 0], [1, -1], [1, "2"], [1, 1.5]]:
            with self.assertRaises(Exception):
                self.c.canonical(self.lua.table_from(ids))

    def test_room_reload_allows_new_pointer_but_rejects_swapped_pedestals(self):
        self.lua.execute('''
            local a={key='ptr1:71',anchor='80,60',seed=71,ring={1,2},price=0,options=0,shop=-1,auto=false}
            local b={key='ptr2:72',anchor='160,60',seed=72,ring={3,4},price=0,options=0,shop=-1,auto=false}
            local before=C.signature({a,b},'anchor')
            a.key='ptr3:71'; b.key='ptr4:72'; a.ring={2,1}
            assert(C.signature({b,a},'anchor')==before)
            a.ring,b.ring=b.ring,a.ring
            assert(C.signature({a,b},'anchor')~=before,'cross-pedestal swap hidden by room multiset')
        ''')

    def test_per_pedestal_match_rejects_cross_copy_state_even_with_same_room_total(self):
        self.lua.execute('''
            local function row(anchor,ring) return {anchor=anchor,ring=ring,price=0,options=0,shop=-1,auto=false} end
            local old={row('a',{1,2}),row('b',{3,4})}
            assert(C.additions(old,{row('b',{3,4,7}),row('a',{1,2,7})},1))
            assert(not C.additions(old,{row('a',{1,2,7,8}),row('b',{3,4})},1))
            assert(not C.additions(old,{row('a',{1,2,7}),row('a',{3,4,7})},1))
            assert(not C.additions(old,{row('a',{1,2,7})},1))
        ''')

    def test_separate_cycle_and_metadata_oracles_keep_both_failures_visible(self):
        self.lua.execute('''
            local a={anchor='a',ring={1,2,2},price=5,options=7,shop=-1,auto=false}
            local b={anchor='a',ring={2,2,3,1},price=15,options=7,shop=-1,auto=true}
            assert(C.cycleAdditions({a},{b},1))
            assert(not C.sameMetadata({a},{b}))
            assert(not C.additions({a},{b},1),'strict combined contract weakened')
            b.ring={1,2,3,4}
            assert(not C.cycleAdditions({a},{b},1),'metadata drift hid lost duplicate')
            assert(not C.sameMetadata({a},{b}))
            b.anchor='foreign'
            assert(not C.sameMetadata({a},{b}),'missing pedestal metadata accepted')
        ''')

    def test_unknown_pool_evidence_never_passes_zero_charge(self):
        self.lua.execute('''
            local w={events={},callbackKnown=true}
            assert(C.noCharge(w)==nil)
            w.poolBefore={entries={},removed={}}; w.poolAfter={entries={},removed={}}
            assert(C.noCharge(w)==nil,'missing blacklist was treated as empty')
            w.poolBefore.blacklist={}; w.poolAfter.blacklist={}; w.callbackKnown=false
            assert(C.noCharge(w)==nil,'missing observer was treated as no draws')
            w.callbackKnown=true; assert(C.noCharge(w)==true)
            w.events={{decrease=true}}; assert(C.noCharge(w)==false)
        ''')

    def test_weight_gains_cannot_cancel_losses_and_all_native_pools_are_observed(self):
        self.lua.execute('''
            local pool={}
            function pool:GetNumItemPools() return 3 end
            function pool:GetCollectiblesFromPool(kind)
                return {{itemID=kind+1,weight=1,removeOn=0.1,isUnlocked=true,decreaseBy=1,initialWeight=1}}
            end
            function pool:GetRemovedCollectibles() return {[1]=false,[99]=true} end
            function pool:GetRoomBlacklistedCollectibles() return {[1]=false,[7]=true,[8]=true} end
            Game=function() return {GetItemPool=function() return pool end} end
            local a=C.poolSnapshot(); local b=C.poolSnapshot()
            assert(a.entries['2:3:1'] and a.removed[99] and not a.removed[1] and a.blacklist[7] and a.blacklist[8])
            b.entries['0:1:1'].weight=0; b.entries['1:2:1'].weight=10
            b.removed[4]=true; b.blacklist[5]=true
            local d=C.poolDelta(a,b)
            assert(d.lost==1 and d.changed==2 and d.removed==1 and d.blocked==1)
            assert(C.noCharge({events={},callbackKnown=true,poolBefore=a,poolAfter=b})==false)
            pool.GetRemovedCollectibles=function() return {bad='schema'} end
            assert(C.poolSnapshot().removed==nil)
        ''')

    def load_plans(self):
        self.lua.execute('''
            S={rows={}}; H={}; callbacks={}; callbackLists={}
            function S.add(key,name,groups,build)
                S.rows[#S.rows+1]={key=key,name=name,groups=groups,build=build}
                return 'conch_test severed_oath '..name
            end
            function require(name)
                if name=='scripts.dev.item_scenarios' then return S end
                if name=='scripts.dev.item_test_support' then return H end
                if name=='scripts.dev.cycle_compare_support' then return C end
                error('unexpected module '..name)
            end
            ModCallbacks={MC_POST_GET_COLLECTIBLE=1,MC_PRE_PICKUP_UPDATE=2,MC_POST_PICKUP_UPDATE=3,MC_POST_ENTITY_REMOVE=4}
            EntityType={ENTITY_PICKUP=5}; PickupVariant={PICKUP_COLLECTIBLE=100}
            ConchBlessing={AddCallback=function(_,id,fn)
                callbacks[id]=fn; callbackLists[id]=callbackLists[id] or {}
                table.insert(callbackLists[id],fn)
            end}
            function build(name)
                ops={}; plan={}
                for _,kind in ipairs({'act','check','require','note','wait','waitUntil','section'}) do
                    plan[kind]=function(a,b,c) ops[#ops+1]={kind=kind,a=a,b=b,c=c} end
                end
                for _,row in ipairs(S.rows) do if row.name==name then row.build(plan); return ops end end
                error('missing plan '..name)
            end
        ''')
        self.m = self.lua.execute((ROOT / "scripts/dev/item_test_cycle_compare.lua").read_text(encoding="utf-8"))

    def test_50_registered_plans_are_built_without_gameplay_or_host_package(self):
        self.load_plans()
        self.assertEqual(len(self.m.commands), 50)
        self.lua.execute('''
            assert(package==nil)
            for _,row in ipairs(S.rows) do
                local ops=build(row.name)
                assert(#ops>25 and row.groups.cycle_compare)
                local notes,checks=0,0
                for _,op in ipairs(ops) do
                    if op.kind=='note' and op.a=='CYCLE_COMPARE' then notes=notes+1 end
                    if op.kind=='check' or op.kind=='require' then checks=checks+1 end
                end
                assert(notes>=3 and checks>=6,row.name)
            end
        ''')

    def test_native_arm_calls_real_card_and_oath_arm_does_not(self):
        self.load_plans()
        self.lua.execute('''
            Card={CARD_SOUL_ISAAC=93}; UseFlag={USE_NOANIM=1,USE_NOANNOUNCER=2}
            local player={UseCard=function(_,id,flags) assert(id==93 and flags==3); calls=calls+1 end}
            -- The action immediately after the treasure-entry wait is the arm's
            -- native operation; no mocked gameplay callback supplies its result.
            for _,case in ipairs({{'capacity0_native',1},{'golden0_native',2},{'capacity0_oath',0}}) do
                calls=0; local ops=build('compare_'..case[1]); local lastWait
                for i,op in ipairs(ops) do
                    if op.kind=='waitUntil' and op.c=='native room transition: roomGrid' then lastWait=i end
                    if op.kind=='note' and op.a=='CYCLE_COMPARE' then break end
                end
                assert(ops[lastWait+1].kind=='act'); ops[lastWait+1].a(player,{})
                assert(calls==case[2],case[1]..' routed to wrong operation')
            end
        ''')

    def test_transition_wait_requires_arrival_and_idle_native_transition(self):
        self.load_plans()
        self.lua.execute('''
            Direction={NO_DIRECTION=-1}; RoomTransitionAnim={FADE=5}
            local index, mode, age=1,0,10
            local game={GetLevel=function() return {GetCurrentRoomIndex=function() return index end} end,
                GetRoom=function() return {GetFrameCount=function() return age end} end}
            function game:StartRoomTransition(target) index=target;mode=1;age=0 end
            Game=function() return game end
            RoomTransition={GetTransitionMode=function() return mode end}
            local ops=build('compare_capacity0_native'); local ctx={rooms=3,roomGrid=7}
            for i,op in ipairs(ops) do
                if op.kind=='waitUntil' and op.c=='native room transition: roomGrid' then
                    ops[i-1].a({},ctx)
                    assert(index==7 and not op.a({},ctx),'early destination index accepted before arrival')
                    mode=0;age=1
                    assert(not op.a({},ctx),'idle mode accepted without a new room callback')
                    ctx.rooms=4;mode=1
                    assert(not op.a({},ctx),'room callback accepted during unfinished transition')
                    mode=0;age=0
                    assert(not op.a({},ctx),'uninitialized room accepted')
                    age=1;assert(op.a({},ctx))
                    index=8;assert(not op.a({},ctx),'foreign arrival accepted')
                    break
                end
            end
        ''')

    def test_isolated_travel_removes_only_maze_and_verifies_native_result(self):
        self.load_plans()
        self.lua.execute('''
            LevelCurse={CURSE_OF_MAZE=32}
            local mask, calls=97,0
            local level={GetCurses=function() return mask end,
                RemoveCurses=function(_,bits) assert(bits==32);calls=calls+1;mask=mask & ~bits end}
            Game=function() return {GetLevel=function() return level end} end
            local ops=build('compare_capacity0_native'); local ctx={}
            for i,op in ipairs(ops) do
                if op.a=='isolated travel curse control available' then
                    assert(op.b({},ctx))
                    ops[i+1].a({},ctx); assert(mask==65 and calls==1 and ops[i+2].b({},ctx))
                    ops[i+1].a({},ctx); assert(mask==65 and calls==1 and ops[i+2].b({},ctx))
                    mask=97;level.RemoveCurses=function() end
                    ops[i+1].a({},ctx); assert(not ops[i+2].b({},ctx),'ignored curse removal accepted')
                    level.RemoveCurses=nil;assert(op.b({},ctx)==nil,'missing capability passed')
                    break
                end
            end
        ''')

    def test_grant_metadata_failure_does_not_abort_valid_cycle_or_pass_phase(self):
        self.load_plans()
        self.lua.execute('''
            local old={anchor='a',ring={1,2,2},price=5,options=7,shop=-1,auto=false}
            local new={anchor='a',ring={1,2,2,3},price=15,options=7,shop=-1,auto=true}
            local pool={entries={},removed={},blacklist={}}
            C.snapshot=function() return {new} end
            C.poolSnapshot=function() return pool end
            Game=function() return {GetFrameCount=function() return 10 end,
                GetSeeds=function() return {GetStartSeed=function() return 123 end} end} end
            local ops=build('compare_copy_oath')
            local ctx={recipe='copy',arm='oath',window={name='grant',before={old},events={},poolBefore=pool,frame=0}}
            for i,op in ipairs(ops) do
                if op.kind=='note' and op.a=='CYCLE_COMPARE' then
                    ops[i-1].a({},ctx)
                    assert(ctx.window.ok and ctx.window.metadataOk==false)
                    assert(op.b({},ctx):find('status=FAIL',1,true))
                    assert(ops[i+1].kind=='require' and ops[i+1].b({},ctx),'metadata aborted copy/rewrite prerequisite')
                    assert(ops[i+2].kind=='check' and ops[i+2].b({},ctx)==false,'metadata failure dropped')
                    new.ring={1,2,3,4};ops[i-1].a({},ctx)
                    assert(ops[i+1].b({},ctx)==false,'lost original duplicate must still abort dependent tests')
                    break
                end
            end
        ''')

    def test_idle_metadata_drift_cannot_conceal_unrewarded_pool_consumption(self):
        self.load_plans()
        self.lua.execute('''
            local old={key='1:7',anchor='a',ring={1,2},price=0,options=0,shop=-1,auto=false}
            local new={key='1:7',anchor='a',ring={2,1},price=0,options=0,shop=-1,auto=true}
            local pool={entries={},removed={},blacklist={}}
            C.snapshot=function() return {new} end;C.poolSnapshot=function() return pool end
            Game=function() return {GetFrameCount=function() return 10 end} end
            local ops=build('compare_capacity0_native')
            local ctx={window={name='idle',before={old},events={},poolBefore=pool,frame=0,callbackKnown=true}}
            for i,op in ipairs(ops) do
                if op.kind=='section' and op.a=='idle' then
                    ops[i+3].a({},ctx)
                    assert(ctx.window.ok and ctx.window.metadataOk==false)
                    ctx.window.events={{decrease=true}};ops[i+3].a({},ctx)
                    assert(ctx.window.ok==false and ctx.window.metadataOk==false,'metadata hid pool consumption')
                    break
                end
            end
        ''')

    def test_stock_observation_includes_no_query_but_excludes_removed_or_empty_entities(self):
        self.lua.execute('''
            EntityType={ENTITY_PICKUP=5}; PickupVariant={PICKUP_COLLECTIBLE=100}
            EntityFlag={FLAG_NO_QUERY=64}
            local function entity(kind,variant,id,exists)
                return {Type=kind,Variant=variant,SubType=id,InitSeed=10,FrameCount=4,
                    Exists=function() return exists end,ToPickup=function(self) return self end,
                    HasEntityFlags=function() return true end}
            end
            local hidden=entity(5,100,1,true)
            Isaac={FindByType=function() error('query cannot see this live pedestal') end,
                GetRoomEntities=function() return {hidden,entity(5,100,2,false),entity(5,100,0,true),
                    entity(5,10,1,true),entity(3,100,1,true)} end}
            local stock=C.stock()
            assert(#stock==1 and stock[1]==hidden)
            assert(C.describeEntity(hidden):find('noQuery=true',1,true))
            assert(C.describeEntity(nil)=='removed')
            assert(C.describeEntity(entity(5,100,2,false))=='removed')
        ''')

    def test_missing_fixture_reports_spawn_and_live_state_without_claiming_cycle_loss(self):
        self.load_plans()
        self.lua.execute('''
            EntityType={ENTITY_PICKUP=5}; PickupVariant={PICKUP_COLLECTIBLE=100}
            EntityFlag={FLAG_NO_QUERY=64}
            local empty={Type=5,Variant=100,SubType=0,InitSeed=71,FrameCount=4,
                Exists=function() return true end,ToPickup=function(self) return self end,
                HasEntityFlags=function() return false end}
            Isaac={GetRoomEntities=function() return {empty} end}
            Game=function() return {
                GetLevel=function() return {GetCurrentRoomIndex=function() return 7 end} end,
                GetRoom=function() return {GetFrameCount=function() return 16 end} end} end
            RoomTransition={GetTransitionMode=function() return 0 end}
            local ops=build('compare_capacity0_native')
            for _,op in ipairs(ops) do
                if op.kind=='require' and op.a=='native cycle inspection and rewrite capability' then
                    local ok,detail=op.b({}, {roomGrid=7,spawnedFixtures={{pointer={Ref=nil},initial='5.100.1'}}})
                    assert(ok==false)
                    assert(detail:find('unexpected fixture count=0 expected=1',1,true))
                    assert(detail:find('5.100.1->removed',1,true))
                    assert(detail:find('livePickups=[5.100.0:seed=71',1,true))
                    assert(detail:find('roomAge=16 mode=0',1,true))
                    break
                end
            end
        ''')

    def test_fixture_trace_is_passive_scoped_and_records_native_removal_state(self):
        self.load_plans()
        self.lua.execute('''
            local vector={};vector.__add=function(a,b) return setmetatable({X=a.X+b.X,Y=a.Y+b.Y},vector) end
            Vector=setmetatable({Zero={X=0,Y=0}},{__call=function(_,x,y) return setmetatable({X=x,Y=y},vector) end})
            EntityFlag={FLAG_NO_QUERY=64}; CollectibleType={COLLECTIBLE_SAD_ONION=1}
            local pickup={Type=5,Variant=100,SubType=1,InitSeed=740011,FrameCount=0,Timeout=-1,State=0,
                Position=Vector(240,210),pointer=19,live=true,
                Exists=function(self) return self.live end,HasEntityFlags=function() return false end,
                ToPickup=function(self) return self end,
                GetSprite=function() return {GetAnimation=function() return 'Appear' end} end}
            EntityPtr=function(p) return {Ref=p} end
            GetPtrHash=function(p) return p.pointer end
            local room={GetCenterPos=function() return Vector(320,280) end,
                FindFreePickupSpawnPosition=function(_,p) return p end,GetFrameCount=function() return 14 end}
            Game=function() return {GetRoom=function() return room end,Spawn=function() return pickup end,
                GetLevel=function() return {GetCurrentRoomIndex=function() return 7 end} end} end
            RoomTransition={GetTransitionMode=function() return 0 end}
            Isaac={GetRoomEntities=function() return {} end};H.suppressRandomGoldenPedestals=function() end
            local player={ControlsEnabled=true,Exists=function() return true end}
            local ops=build('compare_capacity0_native');local ctx={roomGrid=7};ops[1].a(player,ctx)
            local requireOp
            for i,op in ipairs(ops) do
                if op.kind=='require' and op.a=='native cycle inspection and rewrite capability' then
                    requireOp=op;ops[i-2].a(player,ctx);break
                end
            end
            local before=#ctx.fixtureTrace.events
            assert(callbacks[2](nil,{pointer=20,InitSeed=740011})==nil)
            assert(#ctx.fixtureTrace.events==before,'same seed on a different entity was observed')
            assert(callbacks[2](nil,pickup)==nil)
            for _,fn in ipairs(callbackLists[3]) do assert(fn(nil,pickup)==nil) end
            for _=1,20 do callbacks[2](nil,pickup) end
            assert(#ctx.fixtureTrace.events==12,'ordinary trace is unbounded')
            pickup.live=false;pickup.FrameCount=1
            local baseEntity=setmetatable({}, {__index=function(_,key)
                assert(key~='Timeout' and key~='State','pickup fields read from base Entity')
                if key=='ToPickup' then return function() return pickup end end
                return pickup[key]
            end})
            assert(callbacks[4](nil,baseEntity)==nil)
            assert(#ctx.fixtureTrace.events==12,'removal exceeded trace budget')
            local ok,detail=requireOp.b(player,ctx)
            assert(ok==false and detail:find('remove:5.100.1',1,true))
            assert(detail:find('timeout=-1',1,true) and detail:find('exists=false',1,true))
            assert(detail:find('pos=240,210:anim=Appear',1,true))
            assert(detail:find('post-update-early',1,true) and detail:find('post-update-late',1,true))
            assert(pickup.Timeout==-1 and pickup.SubType==1 and pickup.State==0,'observer modified gameplay state')
            before=#ctx.fixtureTrace.events;callbacks[4](nil,pickup)
            assert(#ctx.fixtureTrace.events==before,'observer leaked beyond prerequisite measurement')
            ctx.cleanupFns[1]();assert(player.ControlsEnabled==true)
        ''')

    def test_observer_has_no_effect_outside_window_and_never_returns_replacement(self):
        self.load_plans()
        self.lua.execute("assert(callbacks[1](nil,17,0,true,42)==nil)")

    def test_room_pool_audit_rejects_wrong_source_even_for_shared_pool_members(self):
        self.lua.execute('''
            function auditWindow(before,after,events)
                local function row(ring,i) return {anchor=tostring(i),ring=ring} end
                local w={before={},after={},events=events or {},callbackKnown=true,
                    poolBefore={entries={},removed={},blacklist={}}}
                for i,ring in ipairs(before) do w.before[i]=row(ring,i) end
                for i,ring in ipairs(after) do w.after[i]=row(ring,i) end
                for id=1,9 do w.poolBefore.entries[id]={pool=3,id=id,weight=1,threshold=0.1,unlocked=true} end
                return w
            end
            local w=auditWindow({{1}},{{1,5}},{{id=5,requested=3,actual=3,decrease=true}})
            local a=C.auditGrant(w,3); assert(a.source==true and a.overlap==true)
            w.events[1].requested=1; w.events[1].actual=1
            assert(C.auditGrant(w,3).source==false,'membership alone concealed a stale pool request')
            w.events[1].requested=3
            assert(C.auditGrant(w,3).source==false,'wrong actual pool passed')
            w.events={}; assert(C.auditGrant(w,3).source==nil,'missing final callback evidence became PASS')
            w.events={{id=5,requested=3,actual=3,decrease=false}}
            assert(C.auditGrant(w,3).source==nil,'preview alone became delivery provenance')
            w.events={{id=5,requested=3,actual=3,decrease=true}}
            w.poolBefore.entries[5]=nil
            assert(C.auditGrant(w,3).source==nil,'unregistered final replacement was treated as proven room output')
            w.poolBefore.entries={}
            assert(C.auditGrant(w,3).source==nil,'exhausted fallback treated as ordinary source proof')
        ''')

    def test_existing_duplicates_and_new_same_or_cross_pedestal_collisions_are_separate(self):
        self.lua.execute('''
            local function run(before,after)
                local w={before={},after={},events={},callbackKnown=true,poolBefore={entries={},removed={},blacklist={}}}
                for i,ring in ipairs(before) do w.before[i]={anchor=tostring(i),ring=ring} end
                for i,ring in ipairs(after) do w.after[i]={anchor=tostring(i),ring=ring} end
                for id=1,9 do
                    w.poolBefore.entries[id]={pool=3,id=id,weight=1,threshold=0.1,unlocked=true}
                    w.events[#w.events+1]={id=id,requested=3,actual=3,decrease=true}
                end
                return C.auditGrant(w,3)
            end
            local a=run({{1,1},{1,1}},{{1,1,5},{1,1,6}})
            assert(a.existing==2 and a.same==0 and a.cross==0 and a.overlap==true,'normal duplicates falsely failed')
            a=run({{1}},{{1,1}})
            assert(a.same==1 and a.cross==0 and a.overlap==nil,'new same-pedestal collision hidden')
            a=run({{1},{2}},{{1,5},{2,5}})
            assert(a.same==0 and a.cross==2 and a.overlap==nil,'new cross-pedestal collision hidden')
            a=run({{1},{2}},{{1,2},{2,5}})
            assert(a.cross==1 and a.overlap==nil,'new choice overlapping old sibling hidden')
        ''')

    def test_measurement_window_closes_and_cleanup_stops_aborted_observations(self):
        self.load_plans()
        self.lua.execute('''
            C.snapshot=function() return {} end
            C.poolSnapshot=function() return {entries={},removed={},blacklist={}} end
            H.suppressRandomGoldenPedestals=function() end
            Game=function() return {GetFrameCount=function() return 10 end,
                GetItemPool=function() return {GetLastPool=function() return 3 end} end} end
            local player={ControlsEnabled=true,Exists=function() return true end}
            local ops=build('compare_capacity0_native'); local ctx={}
            ops[1].a(player,ctx); assert(player.ControlsEnabled==false)
            local start
            for i,op in ipairs(ops) do if op.kind=='section' and op.a=='idle' then start=i+1; break end end
            ops[start].a(player,ctx)
            assert(callbacks[1](nil,17,0,true,42)==nil)
            assert(#ctx.window.events==1 and ctx.window.events[1].actual==3)
            ops[start+2].a(player,ctx)
            assert(ctx.window.ok==false,'unrewarded pool consumption passed')
            callbacks[1](nil,18,0,true,43); assert(#ctx.window.events==1)
            ops[start].a(player,ctx); local events=ctx.window.events
            ctx.cleanupFns[1](); assert(player.ControlsEnabled==true)
            callbacks[1](nil,19,0,true,44); assert(#events==0,'aborted observer leaked')
        ''')

    def test_rewrite_oracle_detects_synchronous_sibling_corruption(self):
        self.load_plans()
        self.lua.execute('''
            EntityType={ENTITY_PICKUP=5}; PickupVariant={PICKUP_COLLECTIBLE=100}
            CollectibleType={COLLECTIBLE_SPOON_BENDER=3,COLLECTIBLE_INNER_EYE=2}
            local a={identity=10,InitSeed=71,SubType=1,tail={5,6}}
            local b={identity=11,InitSeed=71,SubType=1,tail={5,6}}
            GetPtrHash=function(p) return p.identity end
            C.stock=function() return {a,b} end
            C.snapshot=function()
                local out={}
                for _,p in ipairs({a,b}) do
                    local ring={p.SubType}; for _,id in ipairs(p.tail) do ring[#ring+1]=id end
                    out[#out+1]={ring=ring,key=p.identity..':'..p.InitSeed,price=0,options=0,shop=-1,auto=false}
                end
                return out
            end
            C.poolSnapshot=function() return {entries={},removed={},blacklist={}} end
            Game=function() return {GetFrameCount=function() return 10 end} end
            function a:Morph(_,_,id) self.SubType=id; b.tail={999,999} end
            function a:RemoveCollectibleCycle() self.tail={} end
            function a:AddCollectibleCycle(id) self.tail[#self.tail+1]=id; return true end
            local ops=build('compare_copy_oath'); local ctx={copyKey='10:71'}; local start
            for i,op in ipairs(ops) do if op.kind=='section' and op.a=='same_seed_rewrite' then start=i+1; break end end
            ops[start].a({},ctx); ops[start+2].a({},ctx)
            assert(ctx.window.ok==false,'post-action snapshot concealed synchronous sibling mutation')
        ''')

    def test_diplopia_preserves_source_and_copies_only_displayed_choice(self):
        self.load_plans()
        self.lua.execute('''
            local original={key='10:71',anchor='a',seed=71,ring={25,1,5,1,25},price=0,options=0,shop=-1,auto=true}
            local duplicate={key='11:71',anchor='b',seed=71,ring={25},price=0,options=0,shop=0,auto=true}
            local before=C.copyRows({original})
            local after={duplicate,original} -- enumeration order is not ownership
            local pool={entries={},removed={},blacklist={}}
            C.snapshot=function() return after end; C.poolSnapshot=function() return pool end
            Game=function() return {GetFrameCount=function() return 10 end} end
            for _,arm in ipairs({'native','oath'}) do
                local ops=build('compare_copy_'..arm)
                local ctx={window={name='diplopia',before=before,events={},poolBefore=pool,frame=0,callbackKnown=true}}
                for i,op in ipairs(ops) do
                    if op.kind=='section' and op.a=='diplopia' then
                        local close=ops[i+3].a
                        close({},ctx); assert(ctx.window.ok and ctx.copyKey=='11:71','native displayed-item copy rejected')
                        duplicate.ring={5};close({},ctx);assert(not ctx.window.ok,'wrong displayed item accepted')
                        duplicate.ring={25};original.ring={25,1,5,1};close({},ctx);assert(not ctx.window.ok,'source queue loss hidden')
                        original.ring={25,1,5,1,25};duplicate.key='10:71';close({},ctx);assert(not ctx.window.ok,'same entity passed as copy')
                        duplicate.key='11:71';ctx.window.events={{decrease=true}};close({},ctx)
                        assert(not ctx.window.ok,'unrewarded copy draw accepted')
                        break
                    end
                end
            end
        ''')

    def test_revisit_separates_price_drift_from_cycle_identity_and_pool_cost(self):
        self.load_plans()
        self.lua.execute('''
            -- A fixed price (AutoUpdatePrice off) is exact; its drift stays a FAIL.
            local old={key='10:71',anchor='a',seed=71,ring={1,2},price=12,options=7,shop=-1,auto=false}
            local new={key='20:71',anchor='a',seed=71,ring={2,1},price=15,options=7,shop=-1,auto=false}
            local pool={entries={},removed={},blacklist={}}
            C.snapshot=function() return {new} end; C.poolSnapshot=function() return pool end
            Game=function() return {GetFrameCount=function() return 10 end} end
            local ops=build('compare_duplicates_metadata_oath')
            local ctx={window={name='revisit',before={old},events={},poolBefore=pool,frame=0,callbackKnown=true}}
            local close
            for i,op in ipairs(ops) do if op.kind=='note' and op.a=='CYCLE_COMPARE' then close=ops[i-1].a end end
            close({},ctx); assert(ctx.window.ok and ctx.window.metadataOk==false)
            new.seed=72;close({},ctx);assert(not ctx.window.ok,'new pedestal seed hidden by price drift')
            new.seed=71;new.ring={1,3};close({},ctx);assert(not ctx.window.ok,'revisit resurrected choice passed')
            new.ring={2,1};ctx.window.events={{decrease=true}};close({},ctx)
            assert(not ctx.window.ok,'metadata failure concealed repeat pool draw')
        ''')

    def test_auto_updated_amount_is_engine_owned_but_every_contract_field_stays_strict(self):
        self.lua.execute('''
            local function row(price,auto,options,shop)
                return {anchor='a',seed=1,key='1:1',ring={1,2},price=price,options=options or 7201,shop=shop or -1,auto=auto}
            end
            -- Logged in game: the auto price followed the displayed choice 15>4>15.
            local ok,detail=C.sameMetadata({row(15,true)},{row(4,true)})
            assert(ok and detail:find('a:15>4',1,true),'engine re-derived auto price failed or was hidden')
            assert(C.addition(row(15,true),{anchor='a',ring={1,2,3},price=4,options=7201,shop=-1,auto=true},1))
            assert(C.signature({row(15,true)},'anchor')==C.signature({row(4,true)},'anchor'))
            assert(C.signature({row(15,true)},'anchor','exact')~=C.signature({row(4,true)},'anchor','exact'),'DIAG lost exact price')
            for _,case in ipairs({
                {row(15,true),row(0,true),'paid pedestal became unpriced'},
                {row(15,true),row(-1,true),'coin price became a heart deal'},
                {row(0,true),row(15,true),'unpriced pedestal became paid'},
                {row(15,true),row(15,false),'automatic price frozen'},
                {row(0,false),row(0,true),'forced fixed flag flip hidden'},
                {row(12,false),row(15,false),'fixed price drift hidden'},
                {row(15,true),row(15,true,0),'option group lost'},
                {row(15,true),row(15,true,7201,-2),'shop/deal id changed'}}) do
                local passed,why=C.sameMetadata({case[1]},{case[2]})
                assert(passed==false and why:find('before=',1,true),case[3])
                assert(C.signature({case[1]},'anchor')~=C.signature({case[2]},'anchor'),case[3]..' (signature)')
                local after=case[2]; after.ring={1,2,3}
                assert(not C.addition(case[1],after,1),case[3]..' (addition)')
            end
        ''')

    def native_turn_fixture(self, recipe):
        self.load_plans()
        self.lua.execute('''
            CollectibleType={COLLECTIBLE_BREAKFAST=25,COLLECTIBLE_SAD_ONION=1,COLLECTIBLE_INNER_EYE=2}
            Isaac={GetItemConfig=function() return {GetCollectible=function(_,id) return id>0 end} end}
            GetPtrHash=function(p) return p.ptr end
            pickups={}
            for i=1,3 do
                local p={ptr=i,InitSeed=740000+i,SubType=1,Position={X=i*80,Y=200},tail={},
                    Price=77,ShopItemId=9,AutoUpdatePrice=false,OptionsPickupIndex=3}
                function p:RemoveCollectibleCycle() self.tail={} end
                function p:AddCollectibleCycle(id) self.tail[#self.tail+1]=id; return true end
                function p:GetCollectibleCycle() return self.tail end
                pickups[i]=p
            end
            C.stock=function() return pickups end
        ''')
        self.lua.execute(f"ops=build('compare_{recipe}')")
        self.lua.execute('''
            for i,op in ipairs(ops) do
                if op.kind=='waitUntil' and op.c=='native turn observed on every rotating fixture' then
                    write,turnWait,settle,contract=ops[i-1],op,ops[i+1],ops[i+2]
                end
            end
            assert(write.kind=='act' and settle.kind=='act' and contract.kind=='require')
            assert(contract.a:find('survives a native turn',1,true))
            ctx={}; write.a({},ctx)
        ''')

    def test_fixture_starts_from_the_state_a_native_turn_keeps(self):
        self.native_turn_fixture("duplicates_metadata_native")
        self.lua.execute('''
            for i,p in ipairs(pickups) do
                -- The logged engine turn resets a forced false to true.
                assert(p.AutoUpdatePrice==true and p.ShopItemId==-1 and p.OptionsPickupIndex==7201)
                assert(p.Price==(i==2 and 0 or 15) and #p.tail==4,'metadata fixture lost its paid/unpriced mix')
            end
            local done,why=turnWait.a({},ctx)
            assert(not done and why:find('head=1',1,true),'baseline taken before any native turn')
            pickups[1].SubType=25; assert(not turnWait.a({},ctx))
            pickups[1].SubType=1; pickups[2].SubType=25; pickups[3].SubType=25
            assert(turnWait.a({},ctx),'a turn back to the head was forgotten')
            pickups[1].Price=4 -- engine re-derives an automatic price after the turn
            settle.a({},ctx); local ok,detail=contract.b({},ctx)
            assert(ok and detail:find('15>4',1,true),'engine-owned amount failed the prerequisite')
            pickups[3].AutoUpdatePrice=false; settle.a({},ctx)
            assert(contract.b({},ctx)==false,'turn that changed the contract passed the prerequisite')
            pickups[3].AutoUpdatePrice=true; pickups[2].Price=15; settle.a({},ctx)
            assert(contract.b({},ctx)==false,'unpriced pedestal became paid before either implementation')
            pickups[2].Price=0; pickups[3]=nil
            local done2,why2=turnWait.a({},{written=ctx.written,turned={}})
            assert(not done2 and why2:find(':missing',1,true),'missing fixture accepted as turned')
        ''')

    def test_single_choice_fixture_needs_no_turn_and_keeps_zero_price(self):
        self.native_turn_fixture("capacity0_oath")
        self.lua.execute('''
            for _,p in ipairs(pickups) do assert(p.Price==0 and p.AutoUpdatePrice==true and p.OptionsPickupIndex==0) end
            assert(turnWait.a({},ctx),'a one-choice pedestal cannot turn')
            settle.a({},ctx); assert(contract.b({},ctx))
        ''')

    def test_each_oath_arm_pins_the_held_golden_state_and_restores_it(self):
        self.load_plans()
        self.lua.execute('''
            ActiveSlot={SLOT_PRIMARY=0}; ConchBlessing.ItemData={SEVERED_OATH={id=1001}}
            -- Golden Items' shared per-ID state, left true by an earlier run.
            local gold={list={['1001']=true},ignore=false}
            function gold:HasGoldenItem(id) return self.list[tostring(id)]==true end
            function gold:SetGoldenItem(id) if not self.ignore then self.list[tostring(id)]=true end end
            function gold:ExaustGoldenItem(id) if not self.ignore then self.list[tostring(id)]=false end end
            GoldenItems=gold
            local function steps(name)
                local ops=build('compare_'..name)
                for i,op in ipairs(ops) do
                    if op.kind=='require' and op.a:find('^held Severed Oath is') then return ops[i-1],op,ops end
                end
                return nil,nil,ops
            end
            local player={AddCollectible=function(_,id) assert(id==1001); added=added+1 end}
            for _,case in ipairs({{'capacity0_oath',true,false,'ordinary'},{'golden0_oath',false,true,'golden'},
                                  {'capacity0_oath',false,false,'ordinary'},{'golden0_oath',true,true,'golden'}}) do
                gold.list['1001']=case[2]; added=0
                local act,check=steps(case[1]); assert(check.a:find(case[4],1,true))
                local ctx={cleanupFns={},gold=case[3] and gold or nil}
                act.a(player,ctx); assert(added==1)
                local ok,detail=check.b(player,ctx)
                assert(ok==true and gold.list['1001']==case[3],case[1]..' did not hold the arm golden state: '..detail)
                assert((case[2]~=case[3])==(detail:find('pinned',1,true)~=nil),'pinning not reported')
                for _,fn in ipairs(ctx.cleanupFns) do fn() end
                assert(gold.list['1001']==case[2],'provider state not restored after '..case[1])
            end
            gold.list['1001']=true; gold.ignore=true
            local act,check=steps('capacity0_oath'); local ctx={cleanupFns={}}
            act.a(player,ctx); assert(check.b(player,ctx)==false,'golden held Oath accepted as the ordinary arm')
            GoldenItems=nil; gold.ignore=false
            act,check=steps('capacity0_oath'); ctx={cleanupFns={}}
            act.a(player,ctx); assert(check.b(player,ctx)==true and #ctx.cleanupFns==0)
            local _,none=steps('capacity0_native'); assert(none==nil,'native arm holds no Severed Oath')
        ''')

    def test_native_full_queue_cost_is_control_evidence_while_oath_stays_strict(self):
        self.load_plans()
        self.lua.execute('''
            local full='no charge when the full queue delivered no additional choice'
            local function window()
                local ring={1,25,1,25,2,25,1,25,2}
                return {before={{anchor='a',ring=ring}},after={{anchor='a',ring=ring}},
                    events={{decrease=true}},callbackKnown=true,
                    poolBefore={entries={},removed={},blacklist={}},poolAfter={entries={},removed={},blacklist={}}}
            end
            for _,name in ipairs({'capacity8','golden8'}) do
                local strict,note
                for _,op in ipairs(build('compare_'..name..'_oath')) do if op.a==full then strict=op end end
                assert(strict and strict.kind=='check','Oath full-queue charge must stay a strict check')
                assert(strict.b({},{window=window()})==false,'Oath charge without a choice passed')
                for _,op in ipairs(build('compare_'..name..'_native')) do
                    assert(op.a~=full,'native card cost reported as an Oath FAIL')
                    if op.kind=='note' and op.a:find('native full-queue charge',1,true) then note=op end
                end
                local detail=note.b({},{window=window()})
                assert(detail:find('^charged: decreasing callbacks=1'),'native cost evidence lost: '..detail)
            end
        ''')


if __name__ == "__main__":
    unittest.main()
