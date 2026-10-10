"""Offline runner/coverage regressions. Requires lupa (Lua 5.3).

These tests validate orchestration and the test oracles, not Isaac's engine.
Run from any directory: python -m unittest discover -s tests -v
"""
from pathlib import Path
import re
import unittest

from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class BenchTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r"""
            package.path = root .. '/?.lua;' .. package.path
            callbacks, logs, restarts = {}, {}, {}
            ModCallbacks = { MC_POST_UPDATE=1, MC_POST_GAME_STARTED=2, MC_POST_NEW_ROOM=3,
                MC_EXECUTE_CMD=4, MC_INPUT_ACTION=5, MC_POST_TRIGGER_WEAPON_FIRED=6, MC_USE_ITEM=7,
                MC_POST_RENDER=8, MC_POST_NPC_DEATH=9, MC_PRE_SPAWN_CLEAN_AWARD=10,
                MC_POST_PICKUP_INIT=11, MC_POST_FIRE_TEAR=61 }
            ConchBlessing = { ItemData = {} }
            function ConchBlessing:AddCallback(id, fn)
                callbacks[id] = callbacks[id] or {}
                table.insert(callbacks[id], fn)
            end
            function dispatch(id, ...)
                for _, fn in ipairs(callbacks[id] or {}) do fn(nil, ...) end
            end
            player = {}
            Isaac = {
                GetPlayer = function() return player end,
                ConsoleOutput = function(s) logs[#logs+1] = s end,
                DebugString = function() end,
                ExecuteCommand = function(cmd) restarts[#restarts+1] = cmd; pendingRestart=true end,
                GetRoomEntities = function() return {} end,
            }
            function tick()
                dispatch(ModCallbacks.MC_POST_UPDATE)
                if pendingRestart then pendingRestart=false; dispatch(ModCallbacks.MC_POST_GAME_STARTED, false) end
            end
            function drain()
                for _=1,1000 do if not bench.isRunning() then return end; tick() end
                error('runner did not terminate')
            end
            function output() return table.concat(logs) end
            bench = require('scripts.dev.test_bench')
        """)

    def run_lua(self, script):
        self.lua.execute(script)

    def test_restart_isolation_and_summary(self):
        self.run_lua("""
            order={}
            for _, name in ipairs({'first','second'}) do
                bench.register({command=name, restartCommand='restart 0', build=function(p)
                    p.act(function() order[#order+1]=name; assert(#restarts == #order) end)
                    p.check('pass', function() return true, 'ok' end)
                    p.check('skip', function() return nil, 'optional API absent' end)
                end})
            end
            assert(bench.startSuite('suite', {'first','second'}))
            assert(not bench.start('first', true))
            drain()
            assert(#restarts == 3 and #order == 2)
            assert(output():find('suite END: 2 PASS, 0 FAIL, 2 SKIP',1,true))
        """)

    def test_progress_renders_real_suite_index_wait_and_cancellation(self):
        self.run_lua("""
            local drawn={}
            Isaac.GetScreenWidth=function() return 800 end
            Isaac.GetTextWidth=function(text) return #text*5 end
            Isaac.RenderText=function(text,x,y,r,g,b,a)
                if r~=0 then drawn[#drawn+1]=text end
            end
            local function screen()
                drawn={}; dispatch(ModCallbacks.MC_POST_RENDER); return table.concat(drawn,' | ')
            end
            assert(screen()=='','idle HUD must be empty')
            local commands={}
            for i=1,209 do
                commands[i]='conch_test item'..i..' lifecycle'
                bench.register({command=commands[i],build=function(p)
                    p.section('acquisition and removal'); p.wait(3)
                end})
            end
            bench.startSuite('conch_test',commands)
            local s=screen()
            assert(s:find('1/209 Test - '..commands[1],1,true),s)
            assert(s:find('Restarting test run',1,true),s)
            tick(); tick()
            s=screen()
            assert(s:find('acquisition and removal',1,true),s)
            assert(s:find('Step 2/2: Wait: 2 ticks remaining',1,true),s)
            tick(); assert(screen():find('1 ticks remaining',1,true))
            tick(); tick()
            s=screen(); assert(s:find('1/209',1,true) and s:find('clearing test run',1,true),s)
            tick()
            s=screen(); assert(s:find('2/209 Test - '..commands[2],1,true),s)
            bench.stop()
            s=screen(); assert(s:find('Cancelled - clearing test run',1,true),s)
            drain(); assert(screen()=='','cancelled suite HUD must disappear')
        """)

    def test_progress_wait_deadline_wraps_inside_screen_and_single_run_finishes(self):
        self.run_lua("""
            local drawn={}
            Isaac.GetScreenWidth=function() return 240 end
            Isaac.GetTextWidth=function(text) return #text*6 end
            Isaac.RenderText=function(text,x,y,r,g,b,a)
                assert(x>=16 and x+#text*6<=225,'progress overflows narrow screen')
                if r~=0 then drawn[#drawn+1]=text end
            end
            local ready=false
            bench.register({command='conch_test kronos box_of_friends',build=function(p)
                p.section('KRONOS / temporary room effect')
                p.waitUntil(function() return ready end,30,'observe actual familiar absorption')
                p.check('completed',function() return true,'ok' end)
            end})
            bench.start('conch_test kronos box_of_friends',false); tick()
            dispatch(ModCallbacks.MC_POST_RENDER)
            local s=table.concat(drawn,' ')
            assert(s:find('1/1 Test',1,true),s)
            assert(s:find('observe actual familiar absorption',1,true),s)
            assert(s:find('timeout in 29 ticks',1,true),s)
            ready=true; drain(); drawn={}; dispatch(ModCallbacks.MC_POST_RENDER)
            assert(#drawn==0,'completed single test HUD must disappear')
        """)

    def test_progress_render_failure_reports_once_without_stalling_bench(self):
        self.run_lua("""
            Isaac.RenderText=function() error('render unavailable') end
            bench.register({command='short',build=function(p) p.wait(4) end})
            bench.start('short',false)
            dispatch(ModCallbacks.MC_POST_RENDER); dispatch(ModCallbacks.MC_POST_RENDER)
            local _,count=output():gsub('Progress display failed:','')
            assert(count==1,'render failure must not flood the log')
            drain(); assert(bench.status()=='idle')
            assert(output():find('short END: 0 PASS, 0 FAIL',1,true))
        """)

    def test_timeout_aborts_dependent_actions_and_runs_next_member(self):
        self.run_lua("""
            bench.register({command='timeout', build=function(p)
                p.waitUntil(function() return false end, 2, 'expected transition')
                p.act(function() error('must not run after timeout') end)
            end})
            bench.register({command='next', build=function(p) p.check('next runs',function() return true end) end})
            bench.startSuite('suite', {'timeout','next'}); drain()
            assert(output():find('timed out after 2 updates',1,true))
            assert(not output():find('must not run after timeout',1,true))
            assert(output():find('suite END: 1 PASS, 1 FAIL, 0 SKIP',1,true))
        """)

    def test_build_action_wait_and_cleanup_errors(self):
        self.run_lua("""
            for _, kind in ipairs({'build','action','wait','cleanup','section'}) do
                bench.register({command=kind, cleanup=function() if kind=='cleanup' then error('cleanup failure') end end,
                    onSection=function() if kind=='section' then error('section failure') end end,
                    build=function(p)
                        if kind=='build' then error('build failure') end
                        p.section('start')
                        if kind=='action' then p.act(function() error('action failure') end) end
                        if kind=='wait' then p.waitUntil(function() error('wait failure') end,2) end
                    end})
            end
            bench.startSuite('suite', {'build','action','wait','cleanup','section'}); drain()
            assert(#restarts==6)
            assert(output():find('suite END: 0 PASS, 5 FAIL, 0 SKIP',1,true))
        """)

    def test_failed_prerequisite_aborts_only_its_bench(self):
        self.run_lua("""
            for _, mode in ipairs({'false','error','skip'}) do
                bench.register({command=mode,build=function(p)
                    p.require('fixture ready',function()
                        if mode=='error' then error('fixture broken') end
                        if mode=='skip' then return nil,'optional provider absent' end
                        return false,'unexpected fixture state'
                    end)
                    p.act(function() error('dependent action executed') end)
                end})
            end
            bench.register({command='next',build=function(p) p.check('next runs',function() return true end) end})
            bench.startSuite('suite',{'false','error','skip','next'}); drain()
            assert(not output():find('dependent action executed',1,true))
            assert(output():find('suite END: 1 PASS, 2 FAIL, 1 SKIP',1,true))
        """)

    def test_game_over_recovers_without_update_callbacks(self):
        self.run_lua("""
            local dead=false
            player.IsDead=function() return dead end
            local execute=Isaac.ExecuteCommand
            Isaac.ExecuteCommand=function(cmd) dead=false; execute(cmd) end
            bench.register({command='dies',build=function(p)
                p.wait(100)
                p.act(function() error('dead-player dependent action') end)
            end})
            bench.register({command='next',build=function(p) p.check('next runs',function() return true end) end})
            bench.startSuite('suite',{'dies','next'}); tick(); tick()
            dead=true
            dispatch(ModCallbacks.MC_POST_RENDER) -- no POST_UPDATE during game over
            assert(pendingRestart)
            pendingRestart=false; dispatch(ModCallbacks.MC_POST_GAME_STARTED,false)
            drain()
            assert(output():find('test player died',1,true))
            assert(not output():find('dead-player dependent action',1,true))
            assert(output():find('suite END: 1 PASS, 1 FAIL, 0 SKIP',1,true))
        """)

    def test_expected_revival_pauses_steps_but_has_a_render_deadline(self):
        self.run_lua("""
            local dead=false
            player.IsDead=function() return dead end
            bench.register({command='revival',build=function(p)
                p.act(function(_,ctx) ctx.expectedDeathFrames=2; dead=true end)
                p.check('alive after revival',function(_,ctx) ctx.expectedDeathFrames=nil; return not dead end)
            end})
            bench.start('revival',false); tick()
            assert(not output():find('alive after revival',1,true))
            dispatch(ModCallbacks.MC_POST_RENDER)
            dead=false; drain()
            assert(output():find('revival END: 1 PASS, 0 FAIL, 0 SKIP',1,true))
            logs={}
            bench.start('revival',false); tick()
            for _=1,3 do dispatch(ModCallbacks.MC_POST_RENDER) end
            assert(output():find('revival timeout',1,true))
            assert(not output():find('PASS alive after revival',1,true))
            assert(pendingRestart)
        """)

    def test_unregistered_target_markers_are_not_counted_as_a_death(self):
        self.run_lua("""
            H=require('scripts.dev.item_test_support')
            local npc={GetData=function() return {__ConchBlessingTestTarget=12} end}
            assert(not H.deathObserved(player,{deathToken=12}))
            dispatch(ModCallbacks.MC_POST_NPC_DEATH,npc)
            assert(not H.deathObserved(player,{deathToken=12}),'a marker without tracked entity identity passed')
            assert(not H.deathObserved(player,{deathToken=13}))
            H.cleanup({})
            assert(not H.deathObserved(player,{deathToken=12}))
        """)

    def test_cancellation_restores_run_and_keeps_total(self):
        self.run_lua("""
            cleaned=0
            bench.register({command='slow',cleanup=function() cleaned=cleaned+1 end,build=function(p) p.wait(500) end})
            bench.register({command='never',build=function() error('should not start') end})
            bench.startSuite('suite', {'slow','never'}); tick(); tick()
            assert(bench.stop()); assert(bench.stop()); drain()
            assert(cleaned==1 and #restarts==2)
            assert(output():find('Finished 1/2 benches (CANCELLED',1,true))
            assert(not output():find('never START',1,true))
            assert(bench.status()=='idle')
        """)

    def test_invalid_suites_do_not_partially_start(self):
        self.run_lua("""
            bench.register({command='ok',build=function() end})
            assert(not pcall(bench.startSuite,'bad',{'ok','missing'}))
            assert(not pcall(bench.startSuite,'bad',{'ok','ok'}))
            assert(not pcall(bench.startSuite,'bad',{}))
            assert(not bench.isRunning() and #restarts==0)
            assert(not pcall(bench.register,{command='ok',build=function() end}))
        """)

    def test_stop_before_initial_restart_never_builds_plan(self):
        self.run_lua("""
            bench.register({command='cancel_early',build=function() error('cancelled plan ran') end})
            bench.start('cancel_early',true); bench.stop(); drain()
            assert(#restarts==1)
            assert(not output():find('cancelled plan ran',1,true))
        """)

    def test_no_player_deadline_and_unexpected_restart(self):
        self.run_lua("""
            bench.register({command='lost',maxUpdates=2,build=function(p) p.wait(100) end})
            bench.start('lost',false); player=nil; drain()
            assert(output():find('bench deadline',1,true))
            player={}; bench.start('lost',false)
            dispatch(ModCallbacks.MC_POST_GAME_STARTED,false)
            assert(not bench.isRunning())
            assert(output():find('unexpected restart',1,true))
        """)

    def load_item_probe(self):
        source = (ROOT / 'scripts/conch_blessing_items.lua').read_text(encoding='utf-8-sig')
        starts = list(re.finditer(r'^    ([A-Z_0-9]+) = \{', source, re.M))
        rows = []
        for i, match in enumerate(starts):
            block = source[match.end():starts[i+1].start() if i+1 < len(starts) else len(source)]
            item_type = re.search(r'type\s*=\s*"(passive|active|trinket|familiar)"', block).group(1)
            pending = bool(re.search(r'WorkingNow\s*=\s*true', block))
            rows.append((match.group(1), item_type, pending))
        self.assertTrue(rows, 'no ItemData rows parsed')
        self.lua.globals().expected_rows = len(rows)
        self.run_lua("""
            TrinketType={TRINKET_GOLDEN_FLAG=32768}
            Game=function() return {GetNumPlayers=function() return 1 end} end
        """)
        for i, (key, item_type, pending) in enumerate(rows):
            self.lua.globals().ConchBlessing.ItemData[key] = self.lua.table_from(
                {'type': item_type, 'id': i+1000, 'WorkingNow': pending})
        self.run_lua("""
            probe=require('scripts.dev.item_probe')
            assert(#probe.keys == expected_rows)
            for _, key in ipairs(probe.keys) do
                local item=ConchBlessing.ItemData[key]
                assert(bench.get(probe.commands[key]), key..' missing command')
                if not item.WorkingNow then assert(probe.contracts[key],key..' missing behavior contract') end
            end
        """)
    def test_every_registry_row_has_command_and_released_contract(self):
        self.load_item_probe()
        # Build every plan with real builders (no gameplay actions); catches absent
        # functions/enum use at construction time and unintended closure capture.
        self.run_lua("""
            CacheFlag={}; CollectibleType={}; PlayerType={}; ActiveSlot={}; EntityType={};
            for _, key in ipairs(probe.keys) do
                local n=0
                local p=setmetatable({}, {__index=function() return function() n=n+1 end end})
                bench.get(probe.commands[key]).build(p)
                assert(n>0, key..' empty plan')
            end
            for _,row in ipairs(probe.scenarios.rows) do
                if not row.external then
                    local n=0
                    local p=setmetatable({}, {__index=function() return function() n=n+1 end end})
                    bench.get(row.command).build(p)
                    assert(n>0,row.command..' empty scenario')
                end
            end
            local total=0
            for key,item in pairs(require('scripts.locale.en').items) do
                for name in pairs(item.synergies or {}) do
                    local command=assert((probe.scenarios.coverage[key] or {})[name],key..':'..name..' missing synergy case')
                    assert(bench.get(command) or command=='conch_test appraisal detail',command..' missing command')
                    total=total+1
                end
            end
            assert(total==144,'update the documented synergy inventory when it changes')
            for _,name in ipairs({'conch_test kronos detail','conch_test live_eye detail','conch_test appraisal detail'}) do
                bench.register({command=name,build=function() end})
            end
            local suite=probe.suiteCommands(probe.keys)
            local seen={}
            for _,command in ipairs(suite) do
                assert(not seen[command],'duplicate suite entry '..command)
                seen[command]=true
            end
            scenario_count=#probe.scenarios.rows
            suite_count=#suite
            local selected
            bench.startSuite=function(_,commands) selected=commands end
            for _,group in ipairs({'damage','conditions','synergies'}) do
                dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',group)
                assert(selected and #selected>0,group..' group is empty')
                for _,command in ipairs(selected) do assert(bench.get(command),command..' not registered') end
            end
            bench.start('conch_test rat lifecycle',false); drain()
            assert(output():find('0 PASS, 0 FAIL, 1 SKIP',1,true))
        """)

    def test_parameter_commands_route_all_items_and_cases(self):
        self.load_item_probe()
        self.run_lua("""
            local started, selected, label, restart
            bench.start=function(name,withRestart) started=name; restart=withRestart end
            bench.startSuite=function(name,commands) label=name; selected=commands end
            for _,name in ipairs({'conch_test kronos detail','conch_test live_eye detail','conch_test appraisal detail'}) do
                bench.register({command=name,build=function() end})
            end
            for _,key in ipairs(probe.keys) do
                dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',string.lower(key))
                assert(label=='conch_test '..string.lower(key))
                local expected=probe.suiteCommands({key})
                assert(table.concat(selected,'|')==table.concat(expected,'|'),key..' wrong item suite')
                dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',key..' lifecycle')
                assert(started==probe.commands[key] and restart==true,key..' wrong lifecycle')
                assert(started=='conch_test '..string.lower(key)..' lifecycle')
            end
            for _,row in ipairs(probe.scenarios.rows) do
                dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',row.key..' '..row.name)
                assert(started==row.command and restart==true,row.command..' unreachable case')
                assert(not row.command:match('^conch_test_'),'legacy command exposed')
            end
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'CONCH_TEST','  KrOnOs   BoX_Of_FrIeNdS  ')
            assert(started=='conch_test kronos box_of_friends')
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','kronos detail')
            assert(started=='conch_test kronos detail')
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','all')
            assert(label=='conch_test' and #selected==111,'update the documented suite count when it changes')
        """)

    def test_aliases_detailed_helpers_and_shared_probes_use_the_single_command(self):
        self.load_item_probe()
        self.run_lua('''
            local started,selected,helper,helped,rng,rounding
            bench.start=function(name) started=name end
            bench.startSuite=function(_,commands) selected=commands end
            for _,name in ipairs({'conch_test kronos detail','conch_test live_eye detail','conch_test appraisal detail'}) do
                bench.register({command=name,build=function() end,help=function() helped=true end,
                    handle=function(action,words,p) helper=table.concat(words,' '); return p==player end})
            end
            bench.register({command='conch_test locale',build=function() end})
            for alias,key in pairs({appraisal='APPRAISAL_CERTIFICATE',belt='UTILITY_BELT',liveeye='LIVE_EYE'}) do
                dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',alias)
                assert(table.concat(selected,'|')==table.concat(probe.suiteCommands({key}),'|'))
            end
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','kronos detail caption 8'); assert(helper=='caption 8')
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','kronos detail help'); assert(helped)
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','locale'); assert(started=='conch_test locale')
            package.loaded['scripts.dev.rng_probe']={run=function(params) rng=params end}
            package.loaded['scripts.dev.stat_rounding_probe']={execute=function(params) rounding=params end}
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','rng 2000 luck 5'); assert(rng=='2000 luck 5')
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','rounding sweep 6'); assert(rounding=='sweep 6')
            bench.isRunning=function() return true end
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','rng 9'); assert(rng=='2000 luck 5')
            dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test','kronos detail caption 9'); assert(helper=='caption 8')
        ''')

    def test_sequential_bundle_uses_one_run_and_aborts_on_failed_boundary(self):
        self.run_lua('''
            local S=require('scripts.dev.item_scenarios'); local H=require('scripts.dev.item_test_support')
            Game=function() return {GetFrameCount=function() return 10 end} end
            local seen,cleaned={},{}
            for _,name in ipairs({'a','b','c'}) do
                S.add('FIXTURE',name,{},function(p)
                    p.act(function(_,ctx)
                        assert(ctx.marker==nil,'case context leaked')
                        ctx.marker=name; seen[#seen+1]=name
                        ctx.cleanupFns={function() cleaned[#cleaned+1]=name end}
                    end)
                    p.waitUntil(function(_,ctx) return ctx.marker==name end,2,'case context')
                    p.eq('scoped equation',function(_,ctx) return ctx.marker end,name)
                end)
            end
            local fail
            S.sequenceBundle('FIXTURE','batch',{}, {'a','b','c'},nil,function(p)
                p.require('clean boundary',function(_,ctx) return ctx.marker~=fail end)
            end)
            local build=S.rows[#S.rows].build
            bench.register({command='wrapped',build=function(p) build(p,1) end,cleanup=H.cleanup})
            bench.start('wrapped',true); drain()
            assert(table.concat(seen)=='abc' and table.concat(cleaned)=='abc')
            assert(#restarts==2,'bundle restarted between cases')
            seen={}; cleaned={}; restarts={}; fail='b'
            bench.start('wrapped',true); drain()
            assert(table.concat(seen)=='ab' and table.concat(cleaned)=='ab','failed case cleanup or abort was lost')
            assert(#restarts==2 and output():find('FAIL clean boundary',1,true))
            assert(output():find('NOT RUN FIXTURE / c',1,true),'unexecuted case hidden by bundle summary')
        ''')

    def test_command_help_and_invalid_parameters_never_start_a_run(self):
        self.load_item_probe()
        self.run_lua("""
            bench.start=function() error('must not start a bench') end
            bench.startSuite=function() error('must not start a suite') end
            for _,params in ipairs({'kronos typo','kronos box_of_friends extra','all extra',
                'status extra','damage extra','does_not_exist','list does_not_exist'}) do
                dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',params)
            end
            for _,params in ipairs({'list','kronos list','list kronos','kronos help'}) do
                dispatch(ModCallbacks.MC_EXECUTE_CMD,'conch_test',params)
            end
            local log=output()
            assert(not log:find('FAIL',1,true),log)
            assert(log:find('Unknown case: typo',1,true))
            assert(log:find('Unexpected parameter: extra',1,true))
            assert(log:find('conch_test kronos box_of_friends',1,true))
            assert(log:find('conch_test kronos lifecycle',1,true))
            assert(log:find('conch_test kronos detail',1,true))
            assert(not log:find('conch_test_',1,true),log)
        """)

    def test_atropos_choice_oracles_reject_return_and_cross_room_deletion(self):
        self.load_item_probe()
        self.run_lua("""
            local checks={}
            local capture=function(label,fn) checks[label]=fn end
            local plan=setmetatable({check=capture,require=capture},
                {__index=function() return function() end end})
            bench.get('conch_test atropos death_certificate').build(plan)
            local dimension,roomIndex,mode=2,81,0
            Game=function() return {GetLevel=function() return {
                GetDimension=function() return dimension end,
                GetCurrentRoomDesc=function() return {ListIndex=roomIndex} end,
            } end} end
            RoomTransition={GetTransitionMode=function() return mode end}
            local stayed=checks['choice stays in the selected room after pickup completion']
            local ctx={stockIndex=81,beforeReward=0,rewardId=1,
                otherStock='1@100.00,100.00;2@200.00,100.00',otherStockCount=2}
            assert(stayed(player,ctx))
            dimension=0; assert(not stayed(player,ctx)); dimension=2
            roomIndex=80; assert(not stayed(player,ctx)); roomIndex=81
            mode=1; assert(not stayed(player,ctx)); mode=0 -- return started but not arrived
            EntityType={ENTITY_PICKUP=5}; PickupVariant={PICKUP_COLLECTIBLE=100}
            local rows={}
            Isaac.FindByType=function() return rows end
            local function pedestal(id,x)
                return {ToPickup=function() return {SubType=id,Position={X=x,Y=100},
                    Exists=function() return true end} end}
            end
            local cleared=checks['choice removes remaining collectible pedestals']
            local revisited=checks['closed room stays empty on revisit']
            local preserved=checks['choice preserves other room stock']
            assert(cleared(player,ctx) and revisited(player,ctx))
            assert(not preserved(player,ctx)) -- a sweep of every DC room must fail
            rows={pedestal(1,100),pedestal(2,200)}
            assert(preserved(player,ctx))
            assert(not cleared(player,ctx) and not revisited(player,ctx))
            rows={pedestal(3,100),pedestal(2,200)}
            assert(not preserved(player,ctx)) -- equal count with replaced stock must fail
            rows={pedestal(2,200),pedestal(1,100)}
            assert(preserved(player,ctx)) -- enumeration order is not room identity
            local received=checks['selected collectible is retained exactly once']
            local count=1; player.GetCollectibleNum=function() return count end
            assert(received(player,ctx))
            count=0; assert(not received(player,ctx))
            count=2; assert(not received(player,ctx))
        """)

    def test_hp_oracle_rejects_a_spawn_without_damage_and_wrong_damage(self):
        self.run_lua("""
            H=require('scripts.dev.item_test_support')
            local p={act=function() end,require=function() end}
            function p.waitUntil(fn) observed=fn end
            function p.check(_,fn) compare=fn end
            H.sampleAttackDamage(p,function() return 12 end,function() end)
            local ctx={damageBefore=100,damageExpected=12,hitCapture={hits={},variant='2:0:0'}}
            ctx.target={HitPoints=100,Remove=function() end}
            ctx.attack={Exists=function() return true end,Remove=function() end}
            assert(observed(nil,ctx)==false,'a spawned attack without HP loss must not pass')
            ctx.hitCapture.hits={{amount=5}}
            ctx.target.HitPoints=95
            assert(observed(nil,ctx)==false,'wait for HP commit after the isolated hit')
            assert(observed(nil,ctx)==true)
            assert(compare(nil,ctx)==false,'wrong actual HP loss must fail')
            ctx.target={HitPoints=88,Remove=function() end}
            ctx.attack={Exists=function() return true end,Remove=function() end}
            ctx.hitCapture.hits={{amount=12}}
            assert(observed(nil,ctx)==true)
            assert(compare(nil,ctx)==true)
        """)

    def test_award_pickup_evidence_excludes_later_vanilla_reward(self):
        self.run_lua("""
            Game=function() return {GetFrameCount=function() return 7 end} end
            EntityCollisionClass={ENTCOLL_NONE=0}
            -- Production callback registration precedes loading the observer.
            ConchBlessing:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD,function()
                dispatch(ModCallbacks.MC_POST_PICKUP_INIT,{Variant=10,SubType=3})
            end)
            H=require('scripts.dev.item_test_support')
            bench.isRunning=function() return true end
            local capture=H.capturePickups(nil,true)
            dispatch(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD)
            dispatch(ModCallbacks.MC_POST_PICKUP_INIT,{Variant=20,SubType=1})
            assert(capture.count==2)
            assert(#H.awardPickups()==1)
            assert(H.awardPickups()[1].variant==10 and H.awardPickups()[1].subtype==3)
            H.cleanup({})
            assert(#H.awardPickups()==0)
        """)

    def test_kronos_grant_oracles_match_the_authoritative_description(self):
        self.run_lua("""
            local descriptions=require('scripts.locale.en').items.KRONOS.synergies
            local cases=require('scripts.dev.kronos_synergy_cases')
            for name,description in pairs(descriptions) do
                local spec=assert(cases[name],'missing independent Kronos case '..name)
                local text=type(description)=='table' and table.concat(description,' ') or description
                local grant=text:match('Gains {c:([%w_]+)}') or text:match('Gains a {c:([%w_]+)}')
                assert(grant==spec.grant,'grant contract drift: '..name)
                if grant then
                    assert(spec.cap==(text:find('first time only',1,true) and 1 or 0),'grant cap drift: '..name)
                end
                local percent=text:match('(%d+)%% chance to ignore damage')
                assert(spec.block==(percent and tonumber(percent)/100 or nil),'barrier contract drift: '..name)
                assert(not not spec.excluded==not not text:find('Cannot be absorbed',1,true),'exclusion contract drift: '..name)
            end
            for name in pairs(cases) do assert(descriptions[name],'orphaned Kronos case '..name) end
        """)

    def test_money_tear_oracle_rejects_stale_contribution(self):
        self.run_lua("""
            H=require('scripts.dev.item_test_support')
            C=require('scripts.dev.item_test_stats')
            contribution=0
            ConchBlessing.getUnifiedMultiplierState=function() return {itemAdditions={[7]={Tears={cumulative=contribution}}}} end
            player.GetNumCoins=function() return 10 end
            player.MaxFireDelay=9
            function evaluate(n)
                local checks={}
                C.MONEY_TEAR.stage({check=function(label,fn) checks[#checks+1]=fn end},7,n)
                local ok=checks[1](player,{base={Tears=3}})
                return ok
            end
            contribution=1.32; assert(evaluate(2))
            assert(not evaluate(1)) -- stale double stack
            contribution=0.66; assert(evaluate(1)); assert(not evaluate(0)) -- orphan final copy
            contribution=0; assert(evaluate(0))
        """)

    def test_dynamic_stats_oracle_rejects_stale_output_in_each_stat(self):
        self.run_lua("""
            D=require('scripts.dev.item_test_dynamic')
            local checks={}
            local plan=setmetatable({check=function(label,fn)
                if label=='owned effect follows new stats without reacquisition' then checks[#checks+1]=fn end
            end}, {__index=function() return function() end end})
            D.build(plan,'F_MINUS',7,1,{})
            assert(#checks==2)
            local base={Damage=3.5,Tears=3,Range=6.5,Luck=0,Speed=1,ShotSpeed=1}
            local boosted={Damage=11.5,Tears=5,Range=8,Luck=20,Speed=1.2,ShotSpeed=1.5}
            local owned={Damage=3.5,Tears=3,Range=6.5,Luck=5,Speed=1,ShotSpeed=1}
            local ctx={dynamicRaw={base=base,boosted=boosted},dynamicOwnedBase=owned}
            local function set(stat,value)
                if stat=='Tears' then player.MaxFireDelay=30/value-1
                elseif stat=='Range' then player.TearRange=value*40
                elseif stat=='Speed' then player.MoveSpeed=value
                else player[stat]=value end
            end
            for index, profile in ipairs({boosted,base}) do
                for stat,value in pairs(profile) do set(stat,value+(stat=='Luck' and 5 or 0)) end
                assert(checks[index](player,ctx))
                for stat,value in pairs(profile) do
                    local correct=value+(stat=='Luck' and 5 or 0)
                    set(stat,correct+0.3)
                    assert(not checks[index](player,ctx),'stale '..stat..' accepted')
                    set(stat,correct)
                end
            end
        """)

    def test_breath_oracles_detect_stale_attack_count_and_projectile_stats(self):
        self.run_lua("""
            C=require('scripts.dev.item_test_combat')
            local checks={}
            local plan=setmetatable({check=function(label,fn) checks[label]=fn end},
                {__index=function() return function() end end})
            C.FIRE_BREATH.stage(plan,7,1)
            player.Damage=10; player.MaxFireDelay=9; player.TearRange=240; player.ShotSpeed=1.4; player.Luck=5
            local ctx={requiredTriggers=10,shots={triggers=10,count=3,damages={3},
                samples={{range=240,speed=14,chance=0.25}}}}
            local count=checks['burst projectile count follows current tears']
            local interval=checks['burst occurs at the required real attack count']
            local damage=checks['projectile damage scales with remaining copies']
            local motion=checks['emitted flame status chance follows live luck']
            assert(count(player,ctx) and interval(player,ctx) and damage(player,ctx) and motion(player,ctx))
            ctx.shots.count=2; assert(not count(player,ctx)); ctx.shots.count=3
            ctx.shots.triggers=15; assert(not interval(player,ctx)); ctx.shots.triggers=10
            ctx.shots.damages={1.05}; assert(not damage(player,ctx))
            -- Default vanilla flame mode carries no custom motion state.
            ctx.shots.samples[1].range=nil; ctx.shots.samples[1].speed=nil
            assert(motion(player,ctx),'default projectile incorrectly requires custom motion fields')
            for _, change in ipairs({{'chance',0}}) do
                local sample=ctx.shots.samples[1]; local saved=sample[change[1]]
                sample[change[1]]=change[2]; assert(not motion(player,ctx)); sample[change[1]]=saved
            end
        """)

    def test_soflam_oracle_checks_actual_hp_loss_not_only_spawn(self):
        self.run_lua("""
            package.loaded['scripts.lib.damage_provenance']={hasAppliedDamageCallback=function() return true end}
            C=require('scripts.dev.item_test_combat')
            local check
            local plan=setmetatable({check=function(label,fn)
                if label=='actual missile HP loss is three times current damage' then check=fn end
            end}, {__index=function() return function() end end})
            C.SOFLAM.stage(plan,7,1)
            assert(check)
            local ctx={hpBeforeStrike=100000,procDamage=9,target={HitPoints=99973}}
            assert(check(player,ctx))
            ctx.target.HitPoints=100000; assert(not check(player,ctx)) -- a spawned but harmless missile
            ctx.target.HitPoints=99989.5; assert(not check(player,ctx)) -- stale 3.5 damage
        """)

    def test_lua_syntax(self):
        check = self.lua.eval('function(s,n) local f,e=load(s,n); return f~=nil,e end')
        for path in (ROOT / 'scripts/dev').glob('*.lua'):
            good, error = check(path.read_text(encoding='utf-8-sig'), str(path))
            self.assertTrue(good, error)

    def test_eternal_flame_oracle_preserves_earned_reward(self):
        self.run_lua("""
            H=require('scripts.dev.item_test_support')
            C=require('scripts.dev.item_test_stats')
            assert(C.ETERNAL_FLAME.permanent)
            for _, n in ipairs({1,2,1,0,1,0}) do
                local checks={}
                C.ETERNAL_FLAME.stage(setmetatable({
                    check=function(label,fn)
                        if label:find('earned curse',1,true) then checks[#checks+1]=fn end
                    end,
                },{__index=function() return function() end end}),7,n)
                local ctx={base={Damage=3.5,Tears=3},flameDamage=3,flameTears=1}
                player.Damage=6.5; player.MaxFireDelay=6.5 -- 4 SPS
                for _, check in ipairs(checks) do assert(check(player,ctx)) end
                player.Damage=3.5 -- stale held-only implementation after loss
                assert(not checks[1](player,ctx))
                player.Damage=9.5 -- inventory alone re-awarded the old curse
                assert(not checks[1](player,ctx))
                player.MaxFireDelay=9 -- permanent tear reward lost
                assert(not checks[2](player,ctx))
            end
        """)

    def test_eternal_flame_fixture_removes_generated_floor_curse_before_acquisition(self):
        self.run_lua("""
            local curse=5; local ctx={}; local checked=false
            Game=function() return {GetLevel=function() return {
                GetCurses=function() return curse end,
                RemoveCurses=function(_,mask) curse=curse & (~mask) end} end} end
            player.GetEternalHearts=function() return 0 end
            local C=require('scripts.dev.item_test_stats')
            C.ETERNAL_FLAME.prepare({act=function(fn) fn(player,ctx) end,
                require=function(_,fn) assert(fn());checked=true end})
            assert(curse==0 and checked and ctx.flameDamage==0 and ctx.flameTears==0)
        """)

    def test_dragon_oracle_distinguishes_lightning_and_typhoon(self):
        self.run_lua("""
            C=require('scripts.dev.item_test_combat')
            for _, n in ipairs({0,1,2,3}) do
                local check
                local plan=setmetatable({check=function(label,fn)
                    if label:find('one copy fires lightning',1,true) then check=fn end
                end}, {__index=function() return function() end end})
                C.DRAGON.stage(plan,7,n)
                assert(check, 'missing projectile-kind assertion')
                local function result(lightning,typhoons)
                    return check(player,{shots={countsByKey={
                        __ConchDragonTechX=lightning,__ConchDragonVortex=typhoons}}})
                end
                if n==0 then
                    assert(result(0,0)); assert(not result(5,0)); assert(not result(0,5))
                elseif n==1 then
                    assert(result(5,0)); assert(not result(0,5)); assert(not result(5,5))
                else
                    assert(result(0,5)); assert(not result(5,0)); assert(not result(5,5))
                end
            end
        """)

    def test_sword_oracle_rejects_single_copy_evolution(self):
        self.run_lua("""
            C=require('scripts.dev.item_test_stats')
            ConchBlessing.ItemData.TYRFING={id=8}
            local check
            local plan=setmetatable({check=function(label,fn)
                if label:find('300th kill converts every sword',1,true) then check=fn end
            end}, {__index=function() return function() end end})
            C.SEALED_DEMON_SWORD.finish(plan,7)
            assert(check, 'missing all-copy evolution assertion')
            local swords,tyrfings=0,3
            player.GetCollectibleNum=function(_,id) return id==7 and swords or tyrfings end
            assert(check(player))
            swords,tyrfings=2,1
            assert(not check(player))
            swords,tyrfings=0,1
            assert(not check(player))
        """)

    def test_tyrfing_kill_stacking_and_fixed_hit_loss(self):
        # Exercise shipped arithmetic and save handling with engine doubles.
        # Actual damage/death callback delivery still needs the in-game bench.
        self.run_lua("""
            local saved={tyrfing={accumulatedDamage=0}}
            local copies,applied=1,nil
            local sm={GetRunSave=function() return saved end,Save=function() end}
            package.loaded['scripts.lib.save_manager']=sm
            package.loaded['scripts.lib.enemy_utils']={isMonsterKind=function(npc) return npc.monster end}
            ConchBlessing.DamageUtils={isSelfInflictedDamage=function(flags) return flags==1 end}
            ConchBlessing.printDebug=function() end
            ConchBlessing.stats={damage={applyAddition=function(_,value) applied=value end}}
            CacheFlag={CACHE_DAMAGE=1}
            Isaac.GetItemIdByName=function() return 77 end
            Game=function() return {GetNumPlayers=function() return 1 end,GetPlayer=function() return player end} end
            player.HasCollectible=function() return copies>0 end
            player.GetCollectibleNum=function() return copies end
            player.ToPlayer=function() return player end
            player.AddCacheFlags=function() end
            player.EvaluateItems=function() end
            require('scripts.items.collectibles.tyrfing')
            local item=ConchBlessing.tyrfing
            local function equal(actual,expected) assert(math.abs(actual-expected)<1e-9,tostring(actual)..' ~= '..expected) end
            for _, n in ipairs({1,2,3}) do
                copies=n; saved.tyrfing.accumulatedDamage=4
                item.onNPCDeath(nil,{monster=true})
                local earned=4+0.05*n
                equal(saved.tyrfing.accumulatedDamage,earned)
                item.onEntityTakeDamage(nil,player,1,0,nil,0)
                equal(saved.tyrfing.accumulatedDamage,earned*0.5)
                item.onEntityTakeDamage(nil,player,1,1,nil,0) -- self-inflicted: ignored
                item.onNPCDeath(nil,{monster=false}) -- furniture: ignored
                equal(saved.tyrfing.accumulatedDamage,earned*0.5)
                item.onEntityTakeDamage(nil,player,1,0,nil,0)
                equal(saved.tyrfing.accumulatedDamage,earned*0.25)
            end
            copies=2; saved.tyrfing.accumulatedDamage=0
            item.onNPCDeath(nil,{monster=true})
            copies=1; item.onEvaluateCache(nil,player,CacheFlag.CACHE_DAMAGE)
            equal(applied,0.1) -- partial loss does not rescale past earnings
            item.onNPCDeath(nil,{monster=true}); equal(saved.tyrfing.accumulatedDamage,0.15)
            copies=0; applied=nil
            item.onNPCDeath(nil,{monster=true})
            item.onEntityTakeDamage(nil,player,1,0,nil,0)
            item.onEvaluateCache(nil,player,CacheFlag.CACHE_DAMAGE)
            assert(applied==nil); equal(saved.tyrfing.accumulatedDamage,0.15)
            copies=3; item.onEvaluateCache(nil,player,CacheFlag.CACHE_DAMAGE)
            equal(applied,0.15) -- reacquisition restores the stored total once
            item.onNPCDeath(nil,{monster=true}); equal(saved.tyrfing.accumulatedDamage,0.3)
        """)


if __name__ == '__main__':
    unittest.main()
