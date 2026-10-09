"""Independent oracle regressions; recorded engine samples are not new game runs."""
import unittest
import test_item_bench as shared
import test_weapon_observer as weapon


class DamageOracles(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua

    def setUp(self):
        shared.BenchTests.setUp(self)
        self.run_lua("O=require('scripts.dev.damage_oracle')")

    def test_recorded_15_hits_follow_lifetime_curve_without_using_measured_damage_as_expected(self):
        self.run_lua('''
            -- 2026-10-09 22:32 latest log: base, remaining life, applied damage, HP loss.
            local rows={
                {0.7,31,0.60277777910233,0.6015625},
                {2.1868700027466,35,1.9135112762451,1.9140625},
                {0.7,30,0.60000002384186,0.6015625},
                {0.7,26,0.58709675073624,0.5859375},
                {0.7,27,0.59062498807907,0.59375},
                {0.7,33,0.607894718647,0.609375},
                {0.7,33,0.607894718647,0.609375},
                {0.7,32,0.6054053902626,0.6015625},
                {0.7,29,0.59705877304077,0.59375},
                {0.7,31,0.60277777910233,0.6015625},
                {0.7,30,0.60000002384186,0.6015625},
                {0.7,32,0.6054053902626,0.6015625},
                {1.4,29,1.1941175460815,1.1953125},
                {0.7,26,0.58709675073624,0.5859375},
                {0.7,28,0.5939394235611,0.59375},
            }
            for _,r in ipairs(rows) do
                local hit={age=6,timeout=r[2],amount=r[3],damage=999}
                local capture={hits={hit}}
                assert(O.evaluate(r[1],capture,r[4],100000,'blue_flame'))
                assert(not O.evaluate(r[1],capture,r[4],100000),'constant oracle hid the regression')
                assert(not O.evaluate(r[1]*2,capture,r[4],100000,'blue_flame'),'wrong coefficient passed')
            end
        ''')

    def test_lifetime_boundaries_and_missing_evidence(self):
        self.run_lua('''
            assert(O.blueFlameFactor({age=1,timeout=40})==1)
            assert(O.blueFlameFactor({age=21,timeout=20})==0.5)
            assert(O.blueFlameFactor({age=40,timeout=1})==0.025)
            for _,hit in ipairs({{}, {age=0,timeout=40},{age=1,timeout=0},{age=2}}) do
                assert(O.blueFlameFactor(hit)==nil)
            end
        ''')

    def test_no_hit_multiple_hits_and_foreign_damage_never_pass(self):
        self.run_lua('''
            local hit={amount=0.7,age=1,timeout=40}
            assert(not O.evaluate(0.7,{hits={}},0.7,1000,'blue_flame'))
            assert(not O.evaluate(0.7,{hits={hit,hit}},1.4,1000,'blue_flame'))
            assert(not O.evaluate(0.7,{hits={hit},foreignHits=1},0.7,1000,'blue_flame'))
            assert(not O.evaluate(0.7,{hits={hit}},0,1000,'blue_flame'),'callback without HP loss passed')
        ''')

    def test_float_hp_tolerance_does_not_hide_damage_or_lifetime_regressions(self):
        self.run_lua('''
            local capture={hits={{amount=0.7,age=1,timeout=40}}}
            assert(O.evaluate(0.7,capture,0.70001220703125,1000,'blue_flame'))
            assert(not O.evaluate(0.7,capture,0.71,1000,'blue_flame'))
            capture.hits[1].amount=0.71
            assert(not O.evaluate(0.7,capture,0.71,1000,'blue_flame'))
            capture.hits[1].amount=0.7;capture.hits[1].age=21;capture.hits[1].timeout=20
            assert(not O.evaluate(0.7,capture,0.7,1000,'blue_flame'),'missing decay passed')
        ''')


class ObserverIsolation(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua

    def setUp(self):
        weapon.WeaponObserverTests.setUp(self)

    def test_first_applied_hit_stops_attack_before_hp_commit_and_records_foreign_damage(self):
        self.run_lua('''
            local attack=entity(2,1000,player)
            attack.Variant=10;attack.SubType=0;attack.FrameCount=6;attack.Timeout=31
            attack.ToEffect=function(self) return self end
            local target=entity(3,21);local ctx={attack=attack,target=target}
            H.captureDamage(ctx,true)
            dispatch(41,target,0,0,{Entity=attack},0,nil);assert(attack.alive)
            dispatch(41,target,0.6,0,{Entity=attack},0,nil)
            assert(not attack.alive and #ctx.hitCapture.hits==1)
            dispatch(41,target,1,0,{Entity=entity(4,2,player)},0,nil)
            assert(ctx.hitCapture.foreignHits==1)
            H.stopDamageCapture(ctx)
            dispatch(41,target,1,0,{Entity=entity(5,2,player)},0,nil)
            assert(ctx.hitCapture.foreignHits==1,'capture leaked after stop')
        ''')

    def test_room_scan_includes_no_query_anchors_and_rejects_stale_or_wrong_owner(self):
        self.run_lua('''
            EntityType.ENTITY_FAMILIAR=3
            Isaac.FindByType=function() return {} end -- native NO_QUERY exclusion
            local own=entity(2,3,player);own.Player=player;own.data.anchor=true;own.noQuery=true
            local stale=entity(3,3,player);stale.Player=player;stale.data.anchor=true;stale.alive=false
            local foreign=entity(4,3);foreign.Player={hash=9};foreign.data.anchor=true
            local unmarked=entity(5,3);unmarked.Player=player
            local tear=entity(6,2,player);tear.Player=player;tear.data.anchor=true
            for _,e in ipairs({own,stale,foreign,unmarked,tear}) do e.ToFamiliar=function(self) return self end end
            entities={own,stale,foreign,unmarked,tear}
            local found=H.familiarAnchors(player,'anchor')
            assert(#found==1 and found[1]==own)
            player.data={tracked={own}};entities={}
            assert(#H.familiarAnchors(player,'anchor')==0,'internal tracking substituted for room evidence')
        ''')

    def run_hp_scenario(self, control, amount):
        self.lua.globals().isControl = control
        self.lua.globals().appliedAmount = amount
        self.run_lua('''
            EntityType.ENTITY_EFFECT=1000;EffectVariant={BLUE_FLAME=10}
            EntityFlag={FLAG_NO_TARGET=1};EntityCollisionClass={ENTCOLL_ALL=4}
            Vector=setmetatable({}, {__call=function() return setmetatable({},
                {__add=function(a,b) return a end}) end})
            player.Position=Vector()
            local attack=entity(2,1000,player)
            attack.Variant=10;attack.SubType=0;attack.FrameCount=6;attack.Timeout=31
            attack.Position=Vector();attack.Velocity=Vector()
            attack.ToEffect=function(self) return self end
            attack.ToLaser=function() end
            local target,captured,commitAt
            H.target=function()
                target=entity(3,21);target.FrameCount=1;target.HitPoints=100000
                target.IsDead=function() return false end
                target.IsActiveEnemy=function() return true end
                target.IsVulnerableEnemy=function() return true end
                target.ClearEntityFlags=function() end
                return target
            end
            local capture=H.captureDamage
            H.captureDamage=function(ctx,stop) captured=ctx;capture(ctx,stop) end
            local removedBeforeCommit=false
            ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE,function()
                frame=frame+1
                if commitAt and frame>=commitAt then
                    removedBeforeCommit=not attack.alive
                    target.HitPoints=target.HitPoints-appliedAmount
                    commitAt=nil
                end
                if captured and attack.alive then
                    dispatch(41,target,appliedAmount,0,{Entity=attack},0,nil)
                    commitAt=frame+1
                end
            end)
            bench.register({command='hp',cleanup=H.cleanup,build=function(p)
                H.sampleAttackDamage(p,function() return 0.7 end,function() return attack end,
                    {blueFlame=true,control=isControl})
                p.check('following item stage',function() return true end)
            end})
            bench.start('hp',false);drain()
            assert(removedBeforeCommit,'second collision was possible while HP was buffered')
            assert(not target.alive and not attack.alive,'fixture entities leaked')
        ''')

    def test_full_hp_measurement_waits_for_buffer_and_accepts_independent_expectation(self):
        self.run_hp_scenario(False, 0.60277777910233)
        self.run_lua("assert(output():find('hp END: 3 PASS, 0 FAIL, 0 SKIP',1,true),output())")

    def test_vanilla_control_disagreement_aborts_dependent_item_checks(self):
        self.run_hp_scenario(True, 0.7)
        self.run_lua('''
            assert(output():find('vanilla damage control disagrees with oracle',1,true),output())
            assert(not output():find('PASS following item stage',1,true),output())
        ''')

    def test_vanilla_control_does_not_add_gameplay_passes(self):
        self.run_hp_scenario(True, 0.60277777910233)
        self.run_lua('''
            assert(output():find('DIAG vanilla blue-flame HP control',1,true),output())
            assert(output():find('hp END: 1 PASS, 0 FAIL, 0 SKIP',1,true),output())
        ''')


if __name__ == '__main__':
    unittest.main()
