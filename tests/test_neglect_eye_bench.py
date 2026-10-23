"""Offline oracle for conch_test hemispatial_neglect right_eye. Requires lupa.

The first class tests the pure burst bookkeeping. The second drives the shipped
bench plan through the real runner against a scripted engine double: strictly
alternating eyes, both-eye shots (The Wiz), quad shots, and an Eye Drops-like
schedule whose left eye fires more often and whose phase carries over between
bursts. It validates the bench's measurement and its oracle against correct and
deliberately wrong items; it does not prove Isaac's native eye schedule, which
needs the in-game rerun.
"""
from pathlib import Path
import unittest

from lupa.lua53 import LuaRuntime

import test_item_bench as runner_tests

ROOT = Path(__file__).resolve().parents[1]


class EyeSampleOracleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            E=require('scripts.dev.eye_sample')
            -- spec: one letter per tear in firing order, L/R = eye, ? = no
            -- record; lower case = suppressed by the item.
            function burst(spec,offsets,gaps,survivors)
                local s=E.new(1)
                for i=1,#spec do
                    local c=spec:sub(i,i)
                    local eye=(c=='L' or c=='l') and E.LEFT or (c=='R' or c=='r') and E.RIGHT or nil
                    E.addTear(s,i,c~='?' and c:lower()==c,eye)
                end
                for _,o in ipairs(offsets or {0,7,14,28,35,42}) do E.addTrigger(s,100+o) end
                s.inputGaps=gaps or 0
                return E.summarize(s,survivors)
            end
        ''')

    def test_expected_split_comes_from_each_bursts_own_eye_record(self):
        self.lua.execute(r'''
            -- A six-trigger Eye Drops burst can hold four left-eye tears.
            local control=burst('LRLLRL')
            assert(E.controlContract(control,1))
            local kept,blocked=E.expected(control,true,1)
            assert(kept==4 and blocked==2,'expected counts must follow the control eyes, not total/2')
            local owned=burst('LrLLrL')
            local ok,detail=E.eyeContract(owned,true,1); assert(ok,detail)
            assert(owned.kept==4 and owned.blocked==2 and owned.marks=='LrLLrL')
            ok,detail=E.matchesControl(owned,control,true,1,2); assert(ok,detail)
            -- The next phase of the same weapon is 3/3; it is judged by its own eyes.
            local other=burst('RLLRLR',{0,8,18,26,36,44})
            assert(E.controlContract(other,1)); kept,blocked=E.expected(other,true,1)
            assert(kept==3 and blocked==3)
            -- After removal nothing may be suppressed.
            assert(E.eyeContract(burst('LRLLRL'),false,1))
            assert(not E.eyeContract(burst('LrLLRL'),false,1))
        ''')

    def test_wrong_items_fail_the_eye_contract(self):
        self.lua.execute(r'''
            local function fails(spec,eyes,gaps,survivors)
                local ok,detail=E.eyeContract(burst(spec,nil,gaps,survivors),true,eyes or 1)
                assert(ok==false,spec..' wrongly passed: '..tostring(detail)); return detail
            end
            fails('lRLLRL')                       -- a left-eye tear suppressed
            fails('LRLLrL')                       -- a right-eye tear kept
            fails('LrLlRl')                       -- every other tear, not the right eye
            assert(fails('L?LLrL'):find('engine eye record',1,true))
            assert(fails('LLLL'):find('each eye',1,true))  -- cannot prove both halves
            assert(fails('LrLLrL',1,0,1):find('still exist',1,true))
            assert(fails('',1):find('no tear',1,true))
            assert(not E.controlContract(burst('LrLRLR'),1),'a control may not suppress anything')
            assert(not E.controlContract(burst('LLLLLL'),1),'a control must fire both eyes')
            -- Both-eye shots: one tear of every pair.
            assert(E.eyeContract(burst('LlRrLl'),true,2))
            assert(not E.eyeContract(burst('llRRLL'),true,2))
            assert(E.eyeContract(burst('LlRr'),true,3)==nil,'an unsupported eye count is a SKIP')
        ''')

    def test_reference_needs_two_agreeing_control_bursts(self):
        self.lua.execute(r'''
            local normal={0,11,22,33,44,55}
            local stalled=burst('LRLRLR',{0,11,22,96,107,118},40)
            local a,b=burst('LRLRLR',normal),burst('LRLRLR',normal)
            assert(E.reference({stalled,a,b},2)==a,'an interrupted control burst is never the oracle')
            assert(E.reference({stalled,a},2)==nil)
            -- Phases that alternate between bursts settle on a reproduced one.
            local p1,p2=burst('LRLLRL'),burst('RLLRLL',{0,7,21,28,35,49})
            assert(E.reference({p1,p2,burst('LRLLRL')},2)==p1)
            assert(E.reference({p1,p2},2)==nil)
            -- The tolerance is the original two frames.
            assert(E.reference({a,burst('LRLRLR',{0,11,22,33,44,57})},2)==a)
            assert(E.reference({a,burst('LRLRLR',{0,11,22,33,44,58})},2)==nil)
            assert(E.reference({a,burst('LRLRL',{0,11,22,33,44})},2)==nil)
        ''')

    def test_comparable_burst_is_chosen_by_phase_and_input_never_by_timing(self):
        self.lua.execute(r'''
            local ref=burst('LRLLRL')
            local otherPhase=burst('RLLRLL',{0,7,21,28,35,49})
            local slow=burst('LrLLrL',{0,9,18,32,41,50})
            assert(E.comparable({otherPhase,slow},ref,false)==slow)
            local ok,detail=E.matchesControl(slow,ref,true,1,2)
            assert(not ok and detail:find('largest difference 8',1,true),detail)
            local gapped=burst('LrLLrL',nil,3)
            assert(E.comparable({gapped},ref,false)==nil,'resample while attempts remain')
            assert(E.comparable({gapped},ref,true)==gapped,'a gap report alone never fails the bench')
            local clean=burst('LrLLrL')
            assert(E.comparable({gapped,clean},ref,false)==clean)
            assert(E.comparable({otherPhase},ref,true)==nil)
        ''')

    def test_control_comparison_checks_counts_and_every_trigger(self):
        self.lua.execute(r'''
            local ref=burst('LRLLRL')
            assert(E.matchesControl(burst('LrLLrL'),ref,true,1,2))
            assert(E.matchesControl(burst('LrLLrL',{0,9,16,30,37,44}),ref,true,1,2))
            assert(not E.matchesControl(burst('LrLLrL',{0,10,17,31,38,45}),ref,true,1,2))
            assert(not E.matchesControl(burst('LrLLr',{0,7,14,28,35}),ref,true,1,2))
            assert(not E.matchesControl(burst('LrLLrLL'),ref,true,1,2),'an extra tear is not native output')
            assert(E.matchesControl(burst('LRLLRL'),ref,false,1,2))
            assert(not E.matchesControl(burst('LrLLrL'),ref,false,1,2))
            local pairs=burst('LLRRLL',{0,11,22}); local wiz=burst('LlRrLl',{0,11,22})
            assert(E.matchesControl(wiz,pairs,true,2,2))
        ''')


class RightEyeBenchSimulationTests(unittest.TestCase):
    COMMAND = 'conch_test hemispatial_neglect right_eye'

    def setUp(self):
        runner_tests.BenchTests.setUp(self)
        self.lua.execute(r'''
            ModCallbacks.MC_EVALUATE_TEAR_HIT_PARAMS=1490; ModCallbacks.MC_PRE_TEAR_UPDATE=1161
            REPENTOGON={Real=true}
            ButtonAction={ACTION_SHOOTRIGHT=2}; InputHook={IS_ACTION_PRESSED=0,IS_ACTION_TRIGGERED=1,GET_ACTION_VALUE=2}
            WeaponType={WEAPON_TEARS=1}; TearFlags={TEAR_NORMAL=0}; SoundEffect={SOUND_NULL=0}
            EntityCollisionClass={ENTCOLL_NONE=0,ENTCOLL_ALL=4}; EntityGridCollisionClass={GRIDCOLL_NONE=0}
            EntityType.ENTITY_TEAR=2; EntityType.ENTITY_LASER=7; EntityType.ENTITY_BOMB=4
            EntityType.ENTITY_EFFECT=1000; EntityType.ENTITY_PLAYER=1
            SPIDER,WIZ,DROPS,SOY,NEGLECT=153,358,600,330,1007
            CollectibleType={COLLECTIBLE_MUTANT_SPIDER=SPIDER,COLLECTIBLE_THE_WIZ=WIZ,
                COLLECTIBLE_EYE_DROPS=DROPS,COLLECTIBLE_SOY_MILK=SOY}
            Color=function(...) return {...} end
            frame=0
            Game=function() return {GetFrameCount=function() return frame end,GetNumPlayers=function() return 1 end} end
            GetPtrHash=function(e) return e.hash end
            Isaac.GetItemIdByName=function() return NEGLECT end
            Isaac.GetEntityTypeByName=function() return 2 end
            Isaac.GetEntityVariantByName=function() return 9001 end
            priorityCallbacks={}
            function ConchBlessing:AddPriorityCallback(id,priority,fn)
                priorityCallbacks[#priorityCallbacks+1]={id=id,priority=priority,fn=fn}
            end
            ConchBlessing.printError=function(message) error(message) end
            package.loaded['scripts.items.collectibles.hemispatial_neglect_visual']={reset=function() end,
                onUnload=function() end,onPlayerUpdate=function() end,onPrePlayerRender=function() end}
            package.loaded['scripts.lib.damage_provenance']={getDirectPlayerOwner=function(e) return e.owner end,
                getPlayerOwner=function(e) return e.owner end,getSourceEntity=function() end}
            NEG=require('scripts.items.collectibles.hemispatial_neglect')
            H=require('scripts.dev.item_test_support')
            -- The bench's damage section is covered elsewhere; keep it inert here.
            H.fireWeaponAtTarget=function() end
            H.target=function() return {Remove=function() end} end
            H.expect=function() return true,'damage section not simulated' end
            builders={}
            package.loaded['scripts.dev.item_scenarios']={
                add=function(key,name,_,build) builders[key..' '..name]=build end,
                collectible=function(p,id,wanted) p.inv[id]=wanted end}
            require('scripts.dev.item_test_eye_upgrades')
            bench.register({command='conch_test hemispatial_neglect right_eye',build=function(plan)
                plan.act(function(_,ctx) ctx.base={Damage=3.5} end)
                builders['HEMISPATIAL_NEGLECT right_eye'](plan,NEGLECT)
            end})

            player.hash=1; player.Type=1; player.inv={}; player.displacement=1
            player.FireDelay=-1; player.MaxFireDelay=10
            function player:Exists() return true end
            function player:IsDead() return false end
            function player:ToPlayer() return self end
            function player:HasCollectible(id) return (self.inv[id] or 0)>0 end
            function player:GetCollectibleNum(id) return self.inv[id] or 0 end
            function player:GetTearDisplacement() return self.displacement end
            function player:SetTearDisplacement(eye) self.displacement=eye end
            function player:GetMultiShotParams()
                local eyes=self:HasCollectible(WIZ) and 2 or 1
                return {GetNumEyesActive=function() return eyes end}
            end

            -- The item as the game registers it; tests swap in wrong items.
            item={params=function(...) NEG.onTearParams(nil,...) end,
                init=function(t) NEG.onTearInit(nil,t) end,fire=function(t) NEG.onFireTear(nil,t) end}
            model={}
            shots,serial,blackoutUntil=0,100,-1
            eyeTimer={[-1]=-1,[1]=-1}

            local function queryShoot()
                local list={}
                for _,c in ipairs(priorityCallbacks) do
                    if c.id==ModCallbacks.MC_INPUT_ACTION then list[#list+1]=c end
                end
                table.sort(list,function(a,b) return a.priority<b.priority end)
                for _,c in ipairs(callbacks[ModCallbacks.MC_INPUT_ACTION] or {}) do list[#list+1]={fn=c} end
                for _,c in ipairs(list) do
                    -- The engine stops at the first callback that returns a value.
                    local value=c.fn(nil,player,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_SHOOTRIGHT)
                    if value~=nil then return value end
                end
                return 0
            end

            local function fireTear(eye)
                serial=serial+1
                local params={TearVariant=0,TearDamage=3.5,TearFlags=0,TearColor={}}
                item.params(player,params,WeaponType.WEAPON_TEARS,1,eye,nil)
                local t={hash=serial,Type=2,Variant=params.TearVariant,SpawnerEntity=player,data={},
                    alive=true,Visible=true,CollisionDamage=params.TearDamage,TearFlags=params.TearFlags}
                function t:GetData() return self.data end
                function t:Exists() return self.alive end
                function t:Remove() self.alive=false end
                function t:SetInitSound() end
                item.init(t); item.fire(t)
                dispatch(ModCallbacks.MC_POST_FIRE_TEAR,t)
            end

            local function shoot(eye)
                player.displacement=eye
                if player:HasCollectible(WIZ) then fireTear(-1); fireTear(1)
                else for _=1,player:HasCollectible(SPIDER) and 4 or 1 do fireTear(eye) end end
                dispatch(ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED,{X=1,Y=0},1,player,{})
                shots=shots+1
                if model.blackoutAfterShot==shots then blackoutUntil=frame+model.blackoutFrames end
            end

            -- One engine update: input, native fire, then MC_POST_UPDATE. Without Eye
            -- Drops each shot flips the eye after MaxFireDelay+1 frames. Eye Drops
            -- is a scripted stand-in for an uneven schedule: per-eye cooldowns (left
            -- 14, right 22 frames) under a shared 7-frame gap, so the left eye can
            -- fire twice in a row and the phase carries over into the next burst.
            function engineUpdate()
                frame=frame+1
                local p=player
                p.MaxFireDelay=p:HasCollectible(SPIDER) and 25 or p:HasCollectible(SOY) and 1 or 10
                local held=frame>blackoutUntil and (queryShoot() or 0)~=0
                p.FireDelay=math.max(p.FireDelay-1,-1)
                eyeTimer[-1]=math.max(eyeTimer[-1]-1,-1); eyeTimer[1]=math.max(eyeTimer[1]-1,-1)
                if held and p.FireDelay<0 then
                    local eye=-p.displacement
                    if p:HasCollectible(DROPS) then
                        if eyeTimer[eye]>=0 then eye=eyeTimer[-eye]<0 and -eye or nil end
                    end
                    if eye then
                        shoot(eye)
                        if p:HasCollectible(DROPS) then
                            eyeTimer[eye]=eye==-1 and 13 or 21; p.FireDelay=6
                        else p.FireDelay=p.MaxFireDelay end
                        p.FireDelay=p.FireDelay+(model.extraDelay and model.extraDelay(p,eye) or 0)
                    end
                end
                dispatch(ModCallbacks.MC_POST_UPDATE)
            end

            function runBench()
                assert(bench.start('conch_test hemispatial_neglect right_eye',false))
                for _=1,30000 do
                    if not bench.isRunning() then return output() end
                    engineUpdate()
                end
                error('bench did not finish')
            end
        ''')

    def run_bench(self):
        log = self.lua.execute('return runBench()')
        summary = [line for line in log.splitlines() if 'right_eye END:' in line]
        self.assertEqual(len(summary), 1, log[-3000:])
        return log, summary[0]

    @staticmethod
    def lines(log, marker):
        return [line for line in log.splitlines() if marker in line]

    def assert_clean(self, log, summary):
        self.assertIn(' 0 FAIL, 0 SKIP', summary, '\n'.join(self.lines(log, 'FAIL'))[:3000])
        self.assertEqual(len(self.lines(log, 'PASS vanilla control suppresses nothing')), 5)
        self.assertEqual(len(self.lines(log, 'PASS right-eye output omitted and left-eye output kept')), 10)
        self.assertEqual(len(self.lines(log, 'PASS nothing suppressed after the item is removed')), 5)
        self.assertEqual(len(self.lines(log, 'PASS output and native cadence match the vanilla control')), 15)

    def test_correct_item_passes_every_fixture_including_an_uneven_eye_schedule(self):
        log, summary = self.run_bench()
        self.assert_clean(log, summary)
        drops = [l for l in self.lines(log, 'PASS output and native cadence') if 'kept expected=4 ' in l]
        self.assertEqual(len(drops), 2, 'Eye Drops bursts keep their four left-eye tears')
        self.assertTrue(any('marks=LrLLrL' in l for l in self.lines(log, 'DIAG bursts')), log[-3000:])
        self.assertTrue(any('both-eye shots: blocked=6 kept=6 of 12' in l for l in log.splitlines()))
        self.assertTrue(any('engine eye record=true; starting-eye alignment=true; input-delivery observer=true'
                            in l for l in log.splitlines()))

    def test_without_start_alignment_bursts_are_resampled_into_the_controls_phase(self):
        self.lua.execute('player.SetTearDisplacement=nil')
        log, summary = self.run_bench()
        self.assert_clean(log, summary)
        self.assertTrue(any('starting-eye alignment=false' in l for l in log.splitlines()))
        self.assertTrue(any('from 3 bursts' in l for l in self.lines(log, 'PASS vanilla control')),
                        'Eye Drops phases differ until a control burst is reproduced')

    def test_engine_and_fixture_eye_counts_disagreeing_use_the_pair_contract(self):
        self.lua.execute('function player:GetMultiShotParams() return {GetNumEyesActive=function() return 1 end} end')
        log, summary = self.run_bench()
        self.assert_clean(log, summary)
        self.assertTrue(any('eyes per shot=2 (engine 1 vs fixture 2; the larger applies)' in l
                            for l in self.lines(log, 'DIAG bursts')))
        self.lua.execute('player.GetMultiShotParams=nil; for k in pairs(logs) do logs[k]=nil end')
        log, summary = self.run_bench()
        self.assert_clean(log, summary)
        self.assertTrue(any('eyes per shot=2 (fixture declaration; MultiShotParams unavailable)' in l
                            for l in self.lines(log, 'DIAG bursts')))

    def test_interrupted_control_burst_is_never_the_oracle(self):
        self.lua.execute('model.blackoutAfterShot=3; model.blackoutFrames=40')
        log, summary = self.run_bench()
        self.assert_clean(log, summary)
        diag = next(l for l in self.lines(log, 'DIAG bursts') if 'burst 3:' in l)
        self.assertIn('inputGaps=40', diag)
        self.assertTrue(any('from 3 bursts' in l for l in self.lines(log, 'PASS vanilla control')))

    def test_interrupted_item_burst_is_repeated_instead_of_failing_cadence(self):
        # The ordinary control fires twelve shots; shot 15 is inside its owned burst.
        self.lua.execute('model.blackoutAfterShot=15; model.blackoutFrames=30')
        log, summary = self.run_bench()
        self.assert_clean(log, summary)
        self.assertTrue(any('inputGaps=30' in l and 'burst 2:' in l for l in self.lines(log, 'DIAG bursts')))

    def failures(self, log):
        return [l for l in log.splitlines() if l.startswith('  FAIL ')]

    def test_item_that_suppresses_every_other_tear_fails_where_eyes_do_not_alternate(self):
        self.lua.execute(r'''
            local calls=0
            item.params=function(p,params,weapon,_,eye)
                if not p:HasCollectible(NEGLECT) then return end
                calls=calls+1
                if calls%2==0 then params.TearVariant=9001; params.TearDamage=0 end
            end
        ''')
        log, _ = self.run_bench()
        failed = self.failures(log)
        for fixture in ('eye_drops', 'multishot'):
            self.assertTrue(any(f'/ {fixture} / owned: right-eye output omitted' in l for l in failed),
                            '\n'.join(failed))

    def test_item_that_suppresses_the_left_eye_fails(self):
        self.lua.execute(r'''
            item.params=function(p,params,weapon,_,eye)
                if p:HasCollectible(NEGLECT) and eye==-1 then params.TearVariant=9001; params.TearDamage=0 end
            end
        ''')
        failed = self.failures(self.run_bench()[0])
        for fixture in ('ordinary', 'multishot', 'eye_drops', 'high_tears'):
            for state in ('owned', 'stacked'):
                self.assertTrue(any(f'/ {fixture} / {state}: right-eye output omitted' in l for l in failed),
                                (fixture, state, failed))

    def test_item_that_changes_cadence_fails(self):
        self.lua.execute('model.extraDelay=function(p,eye) return p:HasCollectible(NEGLECT) and eye==1 and 3 or 0 end')
        failed = self.failures(self.run_bench()[0])
        for fixture in ('ordinary', 'eye_drops'):
            self.assertTrue(any(f'/ {fixture} / owned: output and native cadence' in l for l in failed), failed)
        self.assertFalse(any('/ removed:' in l for l in failed), failed)

    def test_suppressed_tear_left_alive_fails(self):
        self.lua.execute('item.fire=function() end')
        failed = self.failures(self.run_bench()[0])
        self.assertTrue(any('/ ordinary / owned: right-eye output omitted' in l and 'still exist' in l
                            for l in failed), failed)

    def test_missing_engine_eye_record_skips_instead_of_guessing(self):
        self.lua.execute('player.GetTearDisplacement=nil')
        log, summary = self.run_bench()
        # Per fixture: one control check and two checks for each of three states.
        self.assertIn(' 0 FAIL, 35 SKIP', summary)
        skips = self.lines(log, '   SKIP ')
        self.assertEqual(len(skips), 35)
        self.assertTrue(all('GetTearDisplacement unavailable' in l for l in skips), skips[:3])


if __name__ == '__main__':
    unittest.main()
