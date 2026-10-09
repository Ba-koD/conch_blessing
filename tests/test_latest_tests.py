"""Retry selection, durable test history and diagnostics; not engine validation."""
import unittest
import test_item_bench as shared
import test_weapon_observer as weapon


class LatestTests(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua
    load_item_probe = shared.BenchTests.load_item_probe

    def setUp(self):
        shared.BenchTests.setUp(self)

    def test_seed_targets_only_failed_scenarios_and_list_does_not_restart(self):
        self.load_item_probe()
        self.run_lua('''
            local names=bench.latestCommands();assert(#names==13)
            local seen={};for _,name in ipairs(names) do seen[name]=true;assert(bench.get(name)) end
            assert(seen['conch_test kronos guardian_angel'] and seen['conch_test kronos twisted_pair'])
            assert(not seen['conch_test kronos abilities'] and not seen['conch_test kronos auras'])
            assert(not seen['conch_test kronos incubus'] and not seen['conch_test fire_breath lifecycle'])
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','latest list')
            assert(#restarts==0 and not bench.isRunning())
            local selected
            bench.startSuite=function(label,commands) assert(label=='conch_test latest');selected=commands end
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','latest')
            assert(#selected==13)
            for _,params in ipairs({'latest nonsense','latest list extra'}) do
                selected=nil;dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',params);assert(not selected)
            end
        ''')

    def init_persistence(self):
        self.run_lua('''
            saved={conchTestFailuresV1={version=1,pending={},source='test'}}
            saves=0
            ConchBlessing.originalMod=ConchBlessing
            ConchBlessing.SaveManager={GetPersistentSave=function() return saved end,
                SaveCallbacks={POST_DATA_SAVE=60},Save=function()
                    saves=saves+1
                    disk={conchTestFailuresV1={version=1,pending={},source=saved.conchTestFailuresV1.source,
                        revision=saved.conchTestFailuresV1.revision}}
                    for k,v in pairs(saved.conchTestFailuresV1.pending) do disk.conchTestFailuresV1.pending[k]=v end
                    dispatch(60,{file={other=disk}})
                end}
            history=require('scripts.dev.test_history')
        ''')

    def test_failures_survive_new_run_and_reload_until_full_pass(self):
        self.init_persistence()
        self.run_lua('''
            local mode='fail'
            bench.register({command='case',build=function(p)
                p.check('result',function() if mode=='skip' then return nil end;return mode=='pass','evidence' end)
            end})
            bench.start('case',true);drain();assert(#bench.latestCommands()==1 and saves==1)
            saved=disk -- replace the run cache with the disk snapshot
            package.loaded['scripts.dev.test_history']=nil
            local restored=require('scripts.dev.test_history')
            assert(#restored.commands(bench.get)==1)
            mode='skip';bench.start('case',true);drain();assert(#bench.latestCommands()==1)
            mode='pass';bench.start('case',true);drain();assert(#bench.latestCommands()==0)
            assert(next(disk.conchTestFailuresV1.pending)==nil)
        ''')

    def test_stop_preserves_current_and_not_yet_run_failures(self):
        self.init_persistence()
        self.run_lua('''
            for _,name in ipairs({'first','second'}) do
                saved.conchTestFailuresV1.pending[name]='old failure'
                bench.register({command=name,build=function(p) p.wait(200) end})
            end
            bench.startSuite('latest',{'first','second'});tick();tick();bench.stop();drain()
            assert(#bench.latestCommands()==2)
            assert(saved.conchTestFailuresV1.pending.second=='old failure')
        ''')

    def test_bundle_failure_retries_child_and_success_clears_covered_children(self):
        self.init_persistence()
        self.run_lua('''
            bench.register({command='child',build=function() end})
            local pass=false
            bench.register({command='bundle',retryMembers={'child'},build=function(p)
                p.act(function(_,ctx) ctx.retryCommand='child' end)
                p.check('native effect',function() return pass,'child evidence' end)
            end})
            bench.start('bundle',false);drain()
            local names=bench.latestCommands();assert(#names==1 and names[1]=='child')
            pass=true;bench.start('bundle',false);drain();assert(#bench.latestCommands()==0)
        ''')

    def test_failed_cleanup_is_not_retired_and_unregistered_command_is_not_dropped(self):
        self.init_persistence()
        self.run_lua('''
            bench.register({command='cleanup',cleanup=function() error('leak') end,
                build=function(p) p.check('effect',function() return true end) end})
            bench.start('cleanup',false);drain();assert(#bench.latestCommands()==1)
            saved.conchTestFailuresV1.pending['missing']='old failure'
            assert(not pcall(bench.latestCommands));assert(saved.conchTestFailuresV1.pending.missing)
        ''')

    def test_completed_child_is_retired_when_a_later_child_fails(self):
        self.init_persistence()
        self.run_lua('''
            for _,name in ipairs({'first','second'}) do
                saved.conchTestFailuresV1.pending[name]='old failure'
                bench.register({command=name,build=function() end})
            end
            bench.register({command='bundle',retryMembers={'first','second'},build=function(p)
                p.act(function(_,ctx) ctx.retryCommand='first' end)
                p.check('first effect',function() return true end)
                p.act(function(_,ctx) ctx.completedRetryCommands={first=true};ctx.retryCommand='second' end)
                p.require('second prerequisite',function() return false end)
            end})
            bench.start('bundle',false);drain()
            local names=bench.latestCommands();assert(#names==1 and names[1]=='second')
        ''')

    def test_silent_save_failure_is_reported_and_memory_still_has_failure(self):
        self.init_persistence()
        self.run_lua('''
            ConchBlessing.SaveManager.Save=function() end
            bench.register({command='case',build=function(p) p.check('effect',function() return false end) end})
            bench.start('case',false);drain()
            assert(output():find('disk write not confirmed',1,true),output())
            assert(#bench.latestCommands()==1)
        ''')

    def test_empty_latest_has_no_reset_and_diagnostic_is_not_a_pass(self):
        self.load_item_probe()
        self.init_persistence()
        self.run_lua('''
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','latest')
            assert(#restarts==0 and not bench.isRunning())
            bench.register({command='diagnostic',build=function(p)
                p.note('native control',function() return 'age=5 damage=0.6' end)
            end})
            bench.start('diagnostic',false);drain()
            assert(output():find('DIAG native control (age=5 damage=0.6)',1,true),output())
            assert(output():find('diagnostic END: 0 PASS, 0 FAIL, 0 SKIP',1,true))
        ''')

    def test_freeze_control_reports_engine_values_without_changing_the_oracle(self):
        self.load_item_probe()
        self.run_lua('''
            EntityFlag={FLAG_ICE=4};EntityRef=function(e) return {Entity=e} end
            local notes={}
            local plan=setmetatable({note=function(label,fn) notes[#notes+1]=fn end},
                {__index=function() return function() end end})
            bench.get('conch_test ice_breath status_conditions').build(plan)
            assert(#notes==1)
            local npc={count=0,alive=true}
            function npc:GetFreezeCountdown() return self.count end
            function npc:AddFreeze(ref,duration) assert(duration==60);self.count=self.count+120 end
            function npc:AddEntityFlags(flag) assert(flag==4) end
            function npc:Remove() self.alive=false end
            local ctx={target=npc};local detail=notes[1](player,ctx)
            assert(detail:find('AddFreeze(60)=120',1,true),detail)
            assert(detail:find('repeated AddFreeze(60)=240',1,true),detail)
            assert(not npc.alive and ctx.target==nil)
        ''')

    def test_native_flame_control_observes_age_without_restoring_damage(self):
        self.run_lua('''
            H=require('scripts.dev.item_test_support')
            EntityType={ENTITY_EFFECT=1000};EffectVariant={BLUE_FLAME=10}
            Vector=setmetatable({Zero={}}, {__call=function() return setmetatable({},
                {__add=function(a,b) return a end}) end})
            player.Position=Vector();player.Damage=3.5
            Isaac.Spawn=function(kind,variant)
                assert(kind==1000 and variant==10)
                flame={FrameCount=0,alive=true}
                function flame:ToEffect() return self end
                function flame:SetTimeout(n) self.Timeout=n end
                function flame:Exists() return self.alive end
                function flame:Remove() self.alive=false end
                return flame
            end
            ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE,function()
                if flame and flame.alive then
                    flame.FrameCount=flame.FrameCount+1;flame.Timeout=flame.Timeout-1
                    flame.CollisionDamage=flame.CollisionDamage*0.9
                end
            end)
            bench.register({command='control',cleanup=H.cleanup,build=function(p) H.flameDecayControl(p) end})
            bench.start('control',false);drain()
            assert(output():find('age=0 timeout=40 collisionDamage=0.7',1,true),output())
            assert(output():find('age=5',1,true) and output():find('age=10',1,true),output())
            assert(not flame.alive and flame.CollisionDamage<0.3,'control damaged/restored the age curve')
            assert(output():find('control END: 0 PASS, 0 FAIL, 0 SKIP',1,true))
            bench.start('control',false);tick();bench.stop();drain()
            assert(not flame.alive,'cancel leaked the control flame')
        ''')


class HitDiagnostics(unittest.TestCase):
    run_lua = shared.BenchTests.run_lua

    def setUp(self):
        weapon.WeaponObserverTests.setUp(self)

    def test_exact_attack_and_target_count_each_applied_hit_and_keep_age(self):
        self.run_lua('''
            local attack=entity(2,1000,player)
            attack.Variant=10;attack.SubType=0;attack.FrameCount=3;attack.Timeout=30
            attack.ToEffect=function(self) return self end
            local target=entity(3,21)
            target.GetFreezeCountdown=function() return 120 end
            local ctx={attack=attack,target=target};H.captureDamage(ctx)
            dispatch(41,target,0.64,0,{Entity=player},0,{Entity=attack})
            attack.FrameCount=4;attack.Timeout=29
            dispatch(41,target,0.63,0,{Entity=attack},0,nil)
            dispatch(41,target,0,0,{Entity=attack},0,nil)
            dispatch(41,{hash=4},1,0,{Entity=attack},0,nil)
            dispatch(41,target,1,0,{Entity=entity(5,2,player)},0,nil)
            local evidence=H.damageEvidence(ctx)
            assert(#ctx.hitCapture.hits==2 and ctx.hitCapture.hits[1].age==3)
            assert(evidence:find('appliedHits=2',1,true) and evidence:find('freeze=120',1,true),evidence)
            H.stopDamageCapture(ctx);dispatch(41,target,1,0,{Entity=attack},0,nil)
            assert(#ctx.hitCapture.hits==2)
            H.captureDamage(ctx);H.cleanup({});dispatch(41,target,1,0,{Entity=attack},0,nil)
            assert(#ctx.hitCapture.hits==0,'capture leaked beyond cleanup')
        ''')


if __name__ == '__main__':
    unittest.main()
