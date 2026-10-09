-- Shared runner for in-game test benches (AGENTS.md, Verification).
--
-- Each feature registers a `conch_test <feature> [case]` plan. item_probe.lua
-- dispatches the single public command. Starting an isolated plan restarts the run, plays the feature's plan on its own (it gives
-- items, triggers events and waits on game state, never on player input), prints
-- one PASS/FAIL/SKIP line per check and LOOK lines for visual-only checks to the
-- console and log.txt between START and END summaries, then restarts the run
-- again so nothing the test did leaks into play.
--
--   TestBench.register({
--       command  = "conch_test feature detail", -- dispatched plan name
--       tag      = "FeatureProbe",           -- log.txt prefix
--       duration = "about 10 seconds",       -- shown in the START line
--       build    = function(plan) ... end,   -- adds the steps (see newPlan)
--       onSection = function(ctx) ... end,   -- optional, runs at every section
--       handle   = function(action, words, player) return handled end, -- optional subcommands
--       help     = function() ... end,       -- optional, for `<command> help`
--   })
--
-- `<command> norestart` runs the plan in place; it exists for the offline harness.
-- This file is dev tooling and only acts while a command it owns is running.

local TestBench = {}
local History = require("scripts.dev.test_history")

local benches = {}
local active = nil
local suite = nil
local cleanLease = nil
local finish, record, completeRun, handleDeadPlayer

local function out(def, line)
    Isaac.ConsoleOutput(tostring(line) .. "\n")
    Isaac.DebugString("[" .. def.tag .. "] " .. tostring(line))
end

--- The step list a bench's build(plan) fills in. Every step function receives
--- (player, ctx); ctx persists for the whole run, and ctx.rooms counts room loads.
local function newPlan()
    local ops = {}
    local plan = { ops = ops }
    function plan.act(fn) ops[#ops + 1] = { kind = "act", fn = fn } end
    function plan.note(label, fn) ops[#ops + 1] = { kind = "note", label = label, fn = fn } end
    function plan.wait(updates) ops[#ops + 1] = { kind = "wait", n = updates } end
    -- Wait until fn returns true, or give up after `timeout` updates. An optional
    -- second return value explains the last unmet condition in the timeout log.
    function plan.waitUntil(fn, timeout, label)
        ops[#ops + 1] = { kind = "until", fn = fn, n = timeout, label = label or "wait for game state" }
    end
    function plan.section(title, look) ops[#ops + 1] = { kind = "section", title = title, look = look } end
    -- fn returns passed (true/false, or nil for SKIP) and a detail string.
    function plan.check(label, fn) ops[#ops + 1] = { kind = "check", label = label, fn = fn } end
    function plan.require(label, fn) ops[#ops + 1] = { kind = "require", label = label, fn = fn } end
    function plan.eq(label, getActual, expected)
        plan.check(label, function(player, ctx)
            local actual = getActual(player, ctx)
            return actual == expected, string.format("got %s, want %s", tostring(actual), tostring(expected))
        end)
    end
    function plan.atLeast(label, getActual, minimum)
        plan.check(label, function(player, ctx)
            local actual = getActual(player, ctx)
            return actual >= minimum, string.format("got %s, want >= %s", tostring(actual), tostring(minimum))
        end)
    end
    return plan
end

local function summaryLines(run)
    local results = run.results
    local lines = { string.format("== %s END: %d PASS, %d FAIL, %d SKIP ==",
        run.def.command, results.pass, results.fail, results.skip) }
    for _, line in ipairs(results.failures) do lines[#lines + 1] = "  FAIL " .. line end
    return lines
end

local function announceStart(run)
    out(run.def, string.format("== %s START: %d steps, %s. Stand still, press nothing. ==",
        run.def.command, #run.ops, run.def.duration or "a moment"))
end

local function buildRun(run)
    local plan = newPlan()
    local ok, err = pcall(run.def.build, plan)
    run.ops = plan.ops
    announceStart(run)
    if not ok then
        record(run, false, "build plan", err)
        finish(run)
    end
end

finish = function(run)
    if run.finished then return end
    run.finished = true
    run.restartPending = false
    local cleanupOK=true
    if run.def.cleanup then
        local ok, err = pcall(run.def.cleanup, run.ctx)
        cleanupOK=ok
        if not ok then record(run, false, "cleanup", err); run.ctx.reuseReason="cleanup raised an error" end
    end
    local saved,saveError=pcall(History.record,run)
    if not saved then out(run.def,"ERROR saving test retry history: "..tostring(saveError)) end
    local nextDef = suite and not suite.cancelled and benches[suite.commands[suite.index + 1]]
    local proven=cleanupOK and not run.cancelled and run.ctx.canReuse==true and run.def.reuseGroup~=nil
    if proven and run.ctx.verifyReuse then
        local ok, clean, reason=pcall(run.ctx.verifyReuse,Isaac.GetPlayer(0))
        proven=ok and clean==true
        if not proven then run.ctx.reuseReason=ok and reason or tostring(clean) end
    else
        -- Legacy coverage-only plans have no live validator. Their successful
        -- proof can cross an immediate suite boundary, never an idle boundary.
        proven=proven and run.results.fail==0
    end
    cleanLease=nil
    if run.restartAtEnd and proven and (not nextDef or nextDef.reuseGroup==run.def.reuseGroup) then
        if nextDef or run.ctx.verifyReuse then
            run.restartAtEnd=false
            cleanLease={group=run.def.reuseGroup,verify=run.ctx.verifyReuse}
            out(run.def,nextDef and "Baseline verified; continuing the next compatible test without restarting."
                or "Baseline verified; clean test run retained for the next compatible command.")
        end
    end
    if run.restartAtEnd then
        local reason=run.ctx.reuseReason or run.def.resetReason
            or (run.cancelled and "test cancelled before verified cleanup")
            or (not proven and "no completed baseline proof; failed or interrupted cleanup cannot be reused")
            or (nextDef and nextDef.resetReason)
            or (nextDef and "next test requires a different native state baseline")
            or "isolated test has no reusable baseline contract"
        out(run.def,"RESET reason: "..reason)
    end
    out(run.def, "")
    for _, line in ipairs(summaryLines(run)) do out(run.def, line) end
    if run.restartAtEnd then
        out(run.def, run.def.command .. ": restarting the run to clear the test state...")
        run.ops = nil
        run.endRestartPending = true
    else
        completeRun(run)
    end
end

record = function(run, passed, label, detail)
    local results = run.results
    local full = run.section .. ": " .. label
    if run.ctx.retryCommand then
        results.retryOutcomes=results.retryOutcomes or {}
        local child=results.retryOutcomes[run.ctx.retryCommand] or {pass=0,fail=0,skip=0}
        local outcome=passed==nil and "skip" or passed and "pass" or "fail"
        child[outcome]=child[outcome]+1
        results.retryOutcomes[run.ctx.retryCommand]=child
    end
    if passed == nil then
        results.skip = results.skip + 1
        out(run.def, "   SKIP " .. label .. " (" .. tostring(detail) .. ")")
    elseif passed then
        results.pass = results.pass + 1
        out(run.def, "   PASS " .. label .. " (" .. tostring(detail) .. ")")
    else
        results.fail = results.fail + 1
        results.retryFailures=results.retryFailures or {}
        results.retryFailures[run.ctx.retryCommand or run.def.command]=full.." ("..tostring(detail)..")"
        results.failures[#results.failures + 1] = full .. " (" .. tostring(detail) .. ")"
        out(run.def, "   FAIL " .. label .. " (" .. tostring(detail) .. ")")
    end
end

local function step(run)
    if not run.ops then return end
    run.updates = (run.updates or 0) + 1
    if run.updates > (run.def.maxUpdates or 30 * 600) then
        record(run, false, "bench deadline", "exceeded update budget")
        finish(run)
        return
    end
    local player = Isaac.GetPlayer(0)
    if not player then return end
    while active == run and run.index <= #run.ops do
        if handleDeadPlayer(run, false) then return end
        local op = run.ops[run.index]
        if op.kind == "wait" then
            run.left = (run.left or op.n) - 1
            if run.left > 0 then return end
            run.left = nil
            run.index = run.index + 1
            return
        elseif op.kind == "until" then
            local ok, done, detail = pcall(op.fn, player, run.ctx)
            run.left = (run.left or op.n) - 1
            if not ok then
                record(run, false, op.label, done)
                finish(run)
                return
            end
            if not done and run.left > 0 then return end
            if not done then
                record(run, false, op.label, "timed out after " .. op.n .. " updates"
                    .. (detail and "; " .. tostring(detail) or ""))
                finish(run)
                return
            end
            run.left = nil
            run.index = run.index + 1
            return
        elseif op.kind == "section" then
            run.section = op.title
            out(run.def, "-- " .. op.title)
            if op.look then out(run.def, "   LOOK: " .. op.look) end
            if run.def.onSection then
                local ok, err = pcall(run.def.onSection, run.ctx)
                if not ok then record(run, false, "section setup", err); finish(run); return end
            end
        elseif op.kind == "note" then
            local ok,detail=pcall(op.fn,player,run.ctx)
            if not ok then record(run,false,op.label,detail);finish(run);return end
            out(run.def,"   DIAG "..op.label.." ("..tostring(detail)..")")
        elseif op.kind == "act" then
            local ok, err = pcall(op.fn, player, run.ctx)
            if not ok then record(run, false, "step error", tostring(err)); finish(run); return end
        elseif op.kind == "check" or op.kind == "require" then
            local ok, passed, detail = pcall(op.fn, player, run.ctx)
            if ok then
                record(run, passed, op.label, detail)
            else
                record(run, false, op.label, "error " .. tostring(passed))
            end
            if op.kind == "require" and (not ok or passed ~= true) then finish(run); return end
        end
        run.index = run.index + 1
    end
    if active == run then finish(run) end
end

-- Idle reuse is a lease on an observed baseline, not permission to trust an old
-- successful result. Revalidate after any intervening gameplay before skipping.
local function takeCleanLease(def)
    local lease=cleanLease
    cleanLease=nil
    if not lease or lease.group~=def.reuseGroup or not lease.verify then return false end
    local ok,clean,reason=pcall(lease.verify,Isaac.GetPlayer(0))
    if ok and clean==true then
        out(def,"Baseline revalidated; reusing the clean test run without restarting.")
        return true
    end
    out(def,"RESET reason: retained baseline changed: "..tostring(ok and reason or clean))
    return false
end

function TestBench.start(command, restart)
    command = string.lower(command)
    local def = benches[command]
    if not def then return false end
    if active or suite then
        out(def, command .. ": a test is already running")
        return false
    end
    active = {
        def = def, index = 1, ctx = { rooms = 0 }, section = "setup", restartAtEnd = restart,
        results = { pass = 0, fail = 0, skip = 0, failures = {} },
    }
    if restart and not takeCleanLease(def) then
        active.restartPending = true
        out(def, command .. ": restarting the run before the test...")
    else
        buildRun(active)
    end
    return true
end

-- Game-over stops update callbacks on some builds, but render callbacks keep
-- running. Never leave a suite waiting forever on a dead test player.
handleDeadPlayer = function(run, rendered)
    if run.finished or not run.ops then return false end
    local player = Isaac.GetPlayer(0)
    if not player then
        -- A removed player can stop updates without playing a death animation.
        -- Count renders as well so this cannot leave the suite stuck forever.
        run.missingPlayerFrames = (run.missingPlayerFrames or 0) + 1
        if run.missingPlayerFrames < 120 then return false end
    else
        run.missingPlayerFrames = 0
        if type(player.Exists) ~= "function" or player:Exists() then
            if type(player.IsDead) ~= "function" or not player:IsDead() then return false end
        end
    end
    local grace = run.ctx.expectedDeathFrames
    if grace and grace > 0 then
        if rendered then run.ctx.expectedDeathFrames = grace - 1 end
        return true
    end
    local removed = not player or type(player.Exists) == "function" and not player:Exists()
    record(run, false, grace and "revival timeout" or removed and "test player missing/removed" or "test player died",
        "remaining checks not run; restarting before the next isolated bench")
    run.restartAtEnd = true
    finish(run)
    return true
end

-- Only explicitly admitted, successfully verified baselines can cross a member
-- boundary without restarting. A behavior FAIL can retain a independently
-- verified baseline; failed cleanup, cancellation and incompatible cases reset.
local function nextMember()
    local command = not suite.cancelled and suite.commands[suite.index] or nil
    if not command then
        for _, line in ipairs(summaryLines({ def = suite.def, results = suite.results })) do out(suite.def, line) end
        out(suite.def, string.format("Finished %d/%d benches%s", suite.index - 1, #suite.commands,
            suite.cancelled and " (CANCELLED; remaining benches not run)" or ""))
        suite = nil
        return
    end
    local def = benches[command]
    active = { def = def, index = 1, ctx = { rooms = 0 }, section = "setup", restartAtEnd = true,
        results = { pass = 0, fail = 0, skip = 0, failures = {} } }
    out(suite.def, string.format("[%d/%d] %s", suite.index, #suite.commands, command))
    -- A completed member already restarted. The first member needs its own reset.
    if suite.index == 1 and not takeCleanLease(def) then active.restartPending = true
    else cleanLease=nil; buildRun(active) end
end

completeRun = function(run)
    active = nil
    if not suite then return end
    for _, key in ipairs({ "pass", "fail", "skip" }) do
        suite.results[key] = suite.results[key] + run.results[key]
    end
    for _, failure in ipairs(run.results.failures) do
        suite.results.failures[#suite.results.failures + 1] = run.def.command .. ": " .. failure
    end
    suite.index = suite.index + 1
    nextMember()
end

function TestBench.startSuite(command, commands)
    local def = { command = command, tag = "ConchTest" }
    if active or suite then out(def, "A test is already running; use conch_test status or conch_test stop."); return false end
    local seen, copy = {}, {}
    for _, name in ipairs(commands) do
        assert(benches[name], "unregistered suite member: " .. name)
        assert(not seen[name], "duplicate suite member: " .. name)
        seen[name] = true
        copy[#copy + 1] = name
    end
    assert(#copy > 0, "empty suite")
    suite = { def = def, commands = copy, index = 1, results = { pass = 0, fail = 0, skip = 0, failures = {} } }
    out(def, string.format("== %s START: %d benches; compatible verified baselines share a run. ==", command, #copy))
    nextMember()
    return true
end

function TestBench.get(command) return benches[string.lower(command)] end
function TestBench.latestCommands() return History.commands(TestBench.get) end

function TestBench.status()
    if not active then return "idle" end
    return active.def.command .. ": " .. active.section
        .. (suite and string.format(" (%d/%d)", suite.index, #suite.commands) or "")
end

-- Render the runner's actual state, including the gaps between game restarts.
-- These are the same diagnostic labels used in the console/log, independent of
-- the saved debug toggle. No font asset or optional HUD provider is required.
local function progressLines(run)
    local lines = {
        string.format("%d/%d Test - %s", suite and suite.index or 1,
            suite and #suite.commands or 1, run.def.command),
        run.section,
    }
    if run.finished then
        lines[#lines + 1] = (run.cancelled and "Cancelled" or "Finished") .. " - clearing test run..."
    elseif run.restartPending or run.waitingForStart then
        lines[#lines + 1] = "Restarting test run..."
    else
        local op = run.ops and run.ops[run.index]
        local description = "Preparing next step"
        if op then
            if op.kind == "until" then
                description = string.format("Wait: %s (timeout in %d ticks)", op.label, run.left or op.n)
            elseif op.kind == "wait" then
                description = string.format("Wait: %d ticks remaining", run.left or op.n)
            else
                description = op.label or op.title or "Preparing next action"
            end
        end
        lines[#lines + 1] = string.format("Step %d/%d: %s", run.index, run.ops and #run.ops or 0, description)
    end
    local r = run.results
    lines[#lines + 1] = string.format("PASS %d | FAIL %d | SKIP %d | conch_test stop", r.pass, r.fail, r.skip)
    return lines
end

local function renderProgress(run)
    local ok, err = pcall(function()
        assert(type(Isaac.RenderText) == "function", "Isaac.RenderText unavailable")
        local width = type(Isaac.GetScreenWidth) == "function" and Isaac.GetScreenWidth() or 480
        local height = type(Isaac.GetScreenHeight) == "function" and Isaac.GetScreenHeight() or 270
        local maxWidth = math.max(40, width - 34)
        local function textWidth(text)
            return type(Isaac.GetTextWidth) == "function" and Isaac.GetTextWidth(text) or #text * 8
        end
        local rows = {}
        for index, line in ipairs(progressLines(run)) do
            -- Wrap long scenario/check names at spaces; split long command keys
            -- as needed so neither narrow windows nor long waits hide progress.
            line = tostring(line):gsub("[\r\n]", " ")
            repeat
                local cut, lastSpace = #line, nil
                if textWidth(line) > maxWidth then
                    cut = 1
                    while cut < #line and textWidth(line:sub(1, cut + 1)) <= maxWidth do cut = cut + 1 end
                    for pos in line:sub(1, cut):gmatch("() ") do lastSpace = pos end
                    if lastSpace and lastSpace > 1 then cut = lastSpace - 1 end
                end
                local part = line:sub(1, cut)
                rows[#rows + 1] = { text = part, x = math.max(17, (width - textWidth(part)) * 0.5), header = index == 1 }
                line = line:sub(cut + 1):gsub("^ +", "")
            until line == ""
        end
        -- Anchor the entire wrapped block above the bottom edge so room/stage
        -- titles at the top cannot cover progress. Outline against room art.
        local y = math.max(17, height - 28 - #rows * 11)
        for _, row in ipairs(rows) do
            for dx = -1, 1 do
                for dy = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        Isaac.RenderText(row.text, row.x + dx, y + dy, 0, 0, 0, 1)
                    end
                end
            end
            Isaac.RenderText(row.text, row.x, y, 1, row.header and 0.85 or 1, row.header and 0.35 or 1, 1)
            y = y + 11
        end
    end)
    if not ok and not run.hudFailureReported then
        run.hudFailureReported = true
        local message = "[ConchTest] Progress display failed: " .. tostring(err)
        if type(ConchBlessing.printError) == "function" then ConchBlessing.printError(message)
        else out(run.def, message) end
    end
end

function TestBench.stop()
    if not active then return false end
    if suite then suite.cancelled = true end
    active.cancelled = true
    if active.finished then return true end
    record(active, false, "cancelled", "requested with conch_test stop")
    active.restartAtEnd = true
    finish(active)
    return true
end

function TestBench.isRunning()
    return active ~= nil
end

function TestBench.register(def)
    assert(type(def.command) == "string" and type(def.build) == "function", "TestBench.register: command and build required")
    def.tag = def.tag or def.command
    assert(not benches[string.lower(def.command)], "duplicate bench: " .. def.command)
    benches[string.lower(def.command)] = def
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local run = active
    if not run then return end
    if run.restartPending then
        run.restartPending = false
        run.waitingForStart = true
        Isaac.ExecuteCommand(run.def.restartCommand or "restart")
        return
    end
    if run.endRestartPending then
        run.endRestartPending = false
        run.waitingForEnd = true
        Isaac.ExecuteCommand(run.def.restartCommand or "restart")
        return
    end
    if handleDeadPlayer(run, false) then return end
    step(run)
end)

if ModCallbacks.MC_POST_RENDER then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        local run = active
        if not run then return end
        handleDeadPlayer(run, true)
        renderProgress(run)
        if run.endRestartPending then
            run.endRestartPending = false
            run.waitingForEnd = true
            Isaac.ExecuteCommand(run.def.restartCommand or "restart")
        end
    end)
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    local run = active
    cleanLease=nil
    if not run or continued then return end
    if run.waitingForStart then
        run.waitingForStart = false
        if run.finished then completeRun(run) else buildRun(run) end
    elseif run.waitingForEnd then
        out(run.def, run.def.command .. ": run restarted, test state cleared.")
        for _, line in ipairs(summaryLines(run)) do out(run.def, line) end
        completeRun(run)
    else
        record(run, false, "unexpected restart", "test interrupted before completion")
        finish(run)
    end
end)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if active then active.ctx.rooms = (active.ctx.rooms or 0) + 1 else cleanLease=nil end
end)

ConchBlessing:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, cmd, params)
    local def = benches[string.lower(tostring(cmd))]
    if not def then return end
    local words = {}
    for word in string.gmatch(tostring(params or ""), "%S+") do words[#words + 1] = word end
    local action = string.lower(words[1] or "run")
    local player = Isaac.GetPlayer(0)
    if not player then out(def, def.command .. ": start a run first") return end
    if action == "run" or action == "norestart" then
        TestBench.start(string.lower(def.command), action ~= "norestart")
    elseif not (def.handle and def.handle(action, words, player)) then
        out(def, def.command .. "  -> restart, test everything on its own (" .. (def.duration or "a moment")
            .. ", stand still), restart again")
        if def.help then def.help() end
    end
end)

return TestBench
