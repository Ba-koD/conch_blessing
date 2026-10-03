-- Shared runner for in-game test benches (AGENTS.md, Verification).
--
-- Each feature registers one console command, `conch_<feature>`. Typing it with
-- no arguments restarts the run, plays the feature's plan on its own (it gives
-- items, triggers events and waits on game state, never on player input), prints
-- one PASS/FAIL/SKIP line per check and LOOK lines for visual-only checks to the
-- console and log.txt between START and END summaries, then restarts the run
-- again so nothing the test did leaks into play.
--
--   TestBench.register({
--       command  = "conch_feature",          -- console command
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

local benches = {}
local active = nil

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
    function plan.wait(updates) ops[#ops + 1] = { kind = "wait", n = updates } end
    -- Wait until fn returns true, or give up after `timeout` updates.
    function plan.waitUntil(fn, timeout) ops[#ops + 1] = { kind = "until", fn = fn, n = timeout } end
    function plan.section(title, look) ops[#ops + 1] = { kind = "section", title = title, look = look } end
    -- fn returns passed (true/false, or nil for SKIP) and a detail string.
    function plan.check(label, fn) ops[#ops + 1] = { kind = "check", label = label, fn = fn } end
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
    run.def.build(plan)
    run.ops = plan.ops
    announceStart(run)
end

local function finish(run)
    out(run.def, "")
    for _, line in ipairs(summaryLines(run)) do out(run.def, line) end
    if run.restartAtEnd then
        out(run.def, run.def.command .. ": restarting the run to clear the test state...")
        run.ops = nil
        run.endRestartPending = true
    else
        active = nil
    end
end

local function record(run, passed, label, detail)
    local results = run.results
    local full = run.section .. ": " .. label
    if passed == nil then
        results.skip = results.skip + 1
        out(run.def, "   SKIP " .. label .. " (" .. tostring(detail) .. ")")
    elseif passed then
        results.pass = results.pass + 1
        out(run.def, "   PASS " .. label .. " (" .. tostring(detail) .. ")")
    else
        results.fail = results.fail + 1
        results.failures[#results.failures + 1] = full .. " (" .. tostring(detail) .. ")"
        out(run.def, "   FAIL " .. label .. " (" .. tostring(detail) .. ")")
    end
end

local function step(run)
    if not run.ops then return end
    local player = Isaac.GetPlayer(0)
    if not player then return end
    while active == run and run.index <= #run.ops do
        local op = run.ops[run.index]
        if op.kind == "wait" then
            run.left = (run.left or op.n) - 1
            if run.left > 0 then return end
            run.left = nil
            run.index = run.index + 1
            return
        elseif op.kind == "until" then
            local ok, done = pcall(op.fn, player, run.ctx)
            run.left = (run.left or op.n) - 1
            if not (ok and done) and run.left > 0 then return end
            run.left = nil
            run.index = run.index + 1
            return
        elseif op.kind == "section" then
            run.section = op.title
            out(run.def, "-- " .. op.title)
            if op.look then out(run.def, "   LOOK: " .. op.look) end
            if run.def.onSection then pcall(run.def.onSection, run.ctx) end
        elseif op.kind == "act" then
            local ok, err = pcall(op.fn, player, run.ctx)
            if not ok then record(run, false, "step error", tostring(err)) end
        elseif op.kind == "check" then
            local ok, passed, detail = pcall(op.fn, player, run.ctx)
            if ok then
                record(run, passed, op.label, detail)
            else
                record(run, false, op.label, "error " .. tostring(passed))
            end
        end
        run.index = run.index + 1
    end
    if active == run then finish(run) end
end

function TestBench.start(command, restart)
    local def = benches[command]
    if not def then return false end
    if active then
        out(def, command .. ": a test is already running (" .. active.def.command .. ")")
        return false
    end
    active = {
        def = def, index = 1, ctx = { rooms = 0 }, section = "setup", restartAtEnd = restart,
        results = { pass = 0, fail = 0, skip = 0, failures = {} },
    }
    if restart then
        active.restartPending = true
        out(def, command .. ": restarting the run before the test...")
    else
        buildRun(active)
    end
    return true
end

function TestBench.isRunning()
    return active ~= nil
end

function TestBench.register(def)
    assert(type(def.command) == "string" and type(def.build) == "function", "TestBench.register: command and build required")
    def.tag = def.tag or def.command
    benches[string.lower(def.command)] = def
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local run = active
    if not run then return end
    if run.restartPending then
        run.restartPending = false
        run.waitingForStart = true
        Isaac.ExecuteCommand("restart")
        return
    end
    if run.endRestartPending then
        run.endRestartPending = false
        run.waitingForEnd = true
        Isaac.ExecuteCommand("restart")
        return
    end
    step(run)
end)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    local run = active
    if not run or continued then return end
    if run.waitingForStart then
        run.waitingForStart = false
        buildRun(run)
    elseif run.waitingForEnd then
        out(run.def, run.def.command .. ": run restarted, test state cleared.")
        for _, line in ipairs(summaryLines(run)) do out(run.def, line) end
        active = nil
    end
end)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    if active then active.ctx.rooms = (active.ctx.rooms or 0) + 1 end
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
