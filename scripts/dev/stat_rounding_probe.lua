-- Stat rounding probe: checks in the live engine that Ceil/Round/Floor round
-- the multiplied stat, and that a multiplier never scales an already rounded
-- value (5.1 x2 = 10.2 -> Ceil 11, never 6 x2 = 12).
--
-- Console:  conch_test rounding          test with a x2 multiplier on player 0
--           conch_test rounding 1.5      custom multiplier
--           conch_test rounding p1       another player index
--           conch_test rounding sweep    stress sweep (see below)
--           conch_test rounding sweep 6  sweep stacking up to 6 sources
--
-- Hold at least one of Ceil/Round/Floor first; the command prints their IDs
-- for `giveitem c<ID>`. A stat whose value is already an integer cannot tell
-- the two orders apart and is reported as n/a.
--
-- The run registers a temporary StatsAPI player multiplier on every rounded
-- stat, re-evaluates the cache, then removes it and evaluates again. Two
-- MC_EVALUATE_CACHE observers sit just before and just after the rounding
-- callback and record only while the command runs. Output goes to the console
-- and to log.txt.
--
-- The sweep shifts every stat onto awkward fractions with an early offset
-- callback, then stacks awkward multipliers one source at a time, both as
-- independent StatsAPI multipliers (m^k) and as steroid-style additive
-- multipliers (1 + k(m - 1)). Each level is compared with two bug models:
-- "rounded value x total" and "each stack scales the previous shown value".
-- The stacks are then removed one at a time and every level must come back
-- exactly.
--
-- This file is dev tooling and changes no gameplay state once it returns.

local probe = {}

local CharacterBaseStats = require("scripts.lib.character_base_stats")

local DEFAULT_MULTIPLIER = 2.0
local DRIFT_PASSES = 3
local SOURCE_KEY = "conch_round_probe"

-- Sweep inputs. Offsets are added to every stat in HUD units before any other
-- mod callback (Isaac's 3.50 damage + 1.60 = 5.10, + 0.495 = 3.995).
local SWEEP_OFFSETS = { 0, 0.01, 0.495, 1.6, -0.37, 1.99, 0.3333 }
local SWEEP_MULTIPLIERS = { 2.0, 1.37, 0.73, 1.013, 2.49, 0.51, 1.999, 3.14159, 0.333 }
local SWEEP_STYLES = { "mult", "add" }
local SWEEP_DEFAULT_STACKS = 4
local SWEEP_MAX_STACKS = 8
local SWEEP_PASSES = 2
-- A steroid-style total at or below this is clamped by StatsAPI; stop there.
local SWEEP_MIN_TOTAL = 0.05
local SWEEP_DETAIL_LINES = 12
-- HUD-unit range a stat may be pushed to. Other mods clamp stats at these
-- floors between StatsAPI and rounding, and some keep the clamp as a lasting
-- offset (Stat Change Commands adds the deficit to its own stat offset for the
-- rest of the run). Once a stat's next stack would leave this range it stops
-- stacking for that combo; the other stats continue.
local SWEEP_SAFE_RANGE = {
    [CacheFlag.CACHE_DAMAGE] = { 0.5, math.huge },
    [CacheFlag.CACHE_FIREDELAY] = { 0.1, 120 },
    [CacheFlag.CACHE_RANGE] = { 1, math.huge },
    [CacheFlag.CACHE_SPEED] = { 0.1, math.huge },
    [CacheFlag.CACHE_SHOTSPEED] = { 0.6, math.huge },
    [CacheFlag.CACHE_LUCK] = { -math.huge, math.huge },
}
-- Before StatsAPI (default priority) and every other mod's EARLY callbacks.
local OFFSET_PRIORITY = -1000

-- Fixed report order; the rounding module keys its stats by CacheFlag.
local STAT_ORDER = {
    CacheFlag.CACHE_DAMAGE,
    CacheFlag.CACHE_FIREDELAY,
    CacheFlag.CACHE_RANGE,
    CacheFlag.CACHE_SPEED,
    CacheFlag.CACHE_SHOTSPEED,
    CacheFlag.CACHE_LUCK,
}

local ALL_FLAGS = 0
for _, flag in ipairs(STAT_ORDER) do
    ALL_FLAGS = ALL_FLAGS | flag
end

local function out(line)
    line = tostring(line)
    Isaac.ConsoleOutput(line .. "\n")
    Isaac.DebugString("[ConchRound] " .. line)
end

-- The engine stores stats as 32-bit floats (about 1e-7 relative error), while
-- the two orders differ by at least a rounding step times the multiplier.
local function approx(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    return math.abs(a - b) <= 2e-5 * math.max(1, math.abs(a), math.abs(b))
end

local function fmt(v)
    if type(v) ~= "number" then return "  -  " end
    return string.format("%.2f", v)
end

-- ------------------------------------------------------------------ capture
local capture = nil

local function makeObserver(slot)
    return function(_, player, cacheFlag)
        if not capture or GetPtrHash(player) ~= capture.hash then return end
        local T = ConchBlessing.statRounding and ConchBlessing.statRounding._test
        local stat = T and T.STATS[cacheFlag]
        if stat then
            capture[slot][cacheFlag] = stat.read(player)
        end
    end
end

-- Shifts the engine-computed stat before anything else sees it, so the offset
-- behaves like part of the character's own stat.
local function offsetInjector(_, player, cacheFlag)
    if not capture or not capture.offset or GetPtrHash(player) ~= capture.hash then return end
    local T = ConchBlessing.statRounding and ConchBlessing.statRounding._test
    local stat = T and T.STATS[cacheFlag]
    if not stat then return end
    local value = stat.read(player) + capture.offset
    if cacheFlag == CacheFlag.CACHE_FIREDELAY and value <= 0 then return end
    stat.write(player, value)
end

local function ensureObservers(T)
    if probe._observerPriority == T.CALLBACK_PRIORITY then return end
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE,
        OFFSET_PRIORITY, offsetInjector)
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE,
        T.CALLBACK_PRIORITY - 1, makeObserver("pre"))
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE,
        T.CALLBACK_PRIORITY + 1, makeObserver("post"))
    probe._observerPriority = T.CALLBACK_PRIORITY
end

---One full cache evaluation: the value right before rounding (pre), right
---after it (post), and what the player holds once the engine returns (final).
---@param offset number|nil HUD-unit shift applied before every other callback
local function evaluatePass(T, player, offset)
    capture = { hash = GetPtrHash(player), pre = {}, post = {}, offset = offset }
    local ok, err = pcall(function()
        player:AddCacheFlags(ALL_FLAGS)
        player:EvaluateItems()
    end)
    local pass = capture
    capture = nil
    if not ok then error(err, 0) end
    pass.final = {}
    for _, flag in ipairs(STAT_ORDER) do
        pass.final[flag] = T.STATS[flag].read(player)
    end
    return pass
end

-- --------------------------------------------------------- test multiplier
local function setTestMultiplier(um, T, player, multiplier)
    for _, flag in ipairs(STAT_ORDER) do
        um:SetPlayerMultiplier(player, SOURCE_KEY, T.STATS[flag].name, multiplier, "conch_test rounding probe")
    end
end

local function clearTestMultiplier(um, T, player)
    for _, flag in ipairs(STAT_ORDER) do
        um:RemovePlayerMultiplier(player, SOURCE_KEY, T.STATS[flag].name)
    end
    -- Overwrite any snapshot another item saved while the probe entry existed.
    if type(um.SaveToSaveManager) == "function" then
        um:SaveToSaveManager(player)
    end
end

-- ------------------------------------------------------------------ verdict
local function speedClamp(value)
    local shared = ConchBlessing.stats and ConchBlessing.stats.shared
    if shared and type(shared.ClampMoveSpeed) == "function" then
        return shared.ClampMoveSpeed(value)
    end
    return value
end

---True when StatsAPI already clamped this speed, so the unclamped value a
---multiplier would scale is unknown.
local function speedAtCap(value)
    return speedClamp(value + 1) <= value + 1e-6
end

local function judgeStat(T, flag, ctx)
    local stat = T.STATS[flag]
    local transform = function(v)
        return ConchBlessing.statRounding.applyModes(v, stat.allowsNonPositive,
            ctx.hasCeil, ctx.hasRound, ctx.hasFloor, ctx.base[stat.name])
    end
    local scale = function(v)
        v = v * ctx.multiplier
        if flag == CacheFlag.CACHE_SPEED then v = speedClamp(v) end
        return v
    end

    local before, test, after = ctx.before, ctx.tests, ctx.after
    local problems = {}

    if type(before.pre[flag]) ~= "number" or type(test[1].pre[flag]) ~= "number" then
        return "NO DATA", { "observers did not fire" }, nil
    end

    -- Every pass must round the value it saw in that same pass.
    for _, pass in ipairs({ before, after, table.unpack(test) }) do
        if not approx(pass.post[flag], transform(pass.pre[flag])) then
            problems[#problems + 1] = "rounding"
            break
        end
    end
    for _, pass in ipairs({ before, after, table.unpack(test) }) do
        if not approx(pass.final[flag], pass.post[flag]) then
            problems[#problems + 1] = "changed-after-rounding"
            break
        end
    end
    -- Re-evaluating must not feed the previous result back in.
    for i = 2, #test do
        if not approx(test[i].pre[flag], test[1].pre[flag]) then
            problems[#problems + 1] = "drift"
            break
        end
    end
    if not (approx(after.pre[flag], before.pre[flag]) and approx(after.post[flag], before.post[flag])) then
        problems[#problems + 1] = "not-restored"
    end

    local expectedPre = scale(before.pre[flag])
    local bugPre = scale(before.post[flag])
    local detail = {
        expected = transform(expectedPre),
        bug = transform(bugPre),
    }

    -- The order verdict only asks which value the multiplier scaled; the
    -- problems list carries the per-pass checks separately.
    local verdict
    if approx(transform(expectedPre), transform(bugPre)) then
        verdict = "n/a"
    elseif approx(test[1].pre[flag], expectedPre) then
        verdict = "PASS"
    elseif approx(test[1].pre[flag], bugPre) then
        verdict = "FAIL"
    else
        verdict = "INCONCLUSIVE"
    end
    return verdict, problems, detail
end

-- -------------------------------------------------------------------- setup
---Resolves the modules and player, prints the header, and arms the observers.
---@return table|nil T, table um, EntityPlayer player, table ctx
local function setup(playerIndex, header)
    local T = ConchBlessing.statRounding and ConchBlessing.statRounding._test
    if not T then
        out("conch_test rounding: SKIPPED (stat_rounding module not loaded)")
        return nil
    end
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not (um and type(um.SetPlayerMultiplier) == "function"
        and type(um.RemovePlayerMultiplier) == "function"
        and type(um.SetPlayerAdditiveMultiplier) == "function") then
        out("conch_test rounding: SKIPPED (StatsAPI player multipliers unavailable)")
        return nil
    end
    if playerIndex >= Game():GetNumPlayers() then
        out(string.format("conch_test rounding: no player %d", playerIndex))
        return nil
    end
    local player = Isaac.GetPlayer(playerIndex)

    local ctx = {
        T = T,
        hasCeil = T.playerHasMode(player, T.MODE_CEIL),
        hasRound = T.playerHasMode(player, T.MODE_ROUND),
        hasFloor = T.playerHasMode(player, T.MODE_FLOOR),
        base = CharacterBaseStats.get(player),
    }

    local function yn(held, id) return (held and "yes" or "no") .. " (c" .. tostring(id) .. ")" end
    out("")
    out(string.format("conch_test rounding: player %d %s, %s", playerIndex, player:GetName(), header))
    out(string.format("held: Ceil %s  Round %s  Floor %s",
        yn(ctx.hasCeil, T.ITEM_IDS[T.MODE_CEIL]),
        yn(ctx.hasRound, T.ITEM_IDS[T.MODE_ROUND]),
        yn(ctx.hasFloor, T.ITEM_IDS[T.MODE_FLOOR])))
    if not (ctx.hasCeil or ctx.hasRound or ctx.hasFloor) then
        out("hold Ceil, Round or Floor first (giveitem c<ID>); every stat will read n/a")
    end

    ensureObservers(T)
    return T, um, player, ctx
end

-- ------------------------------------------------------------------ command
function probe.run(multiplier, playerIndex)
    local T, um, player, ctx = setup(playerIndex,
        string.format("test multiplier x%.2f", multiplier))
    if not T then return end
    ctx.multiplier = multiplier

    local ok, err = pcall(function()
        ctx.before = evaluatePass(T, player)
        setTestMultiplier(um, T, player, multiplier)
        ctx.tests = {}
        for i = 1, DRIFT_PASSES do
            ctx.tests[i] = evaluatePass(T, player)
        end
    end)
    -- Always remove the probe multiplier, even when a pass failed.
    local cleanOk, cleanErr = pcall(function()
        clearTestMultiplier(um, T, player)
        ctx.after = evaluatePass(T, player)
    end)
    if not ok then
        out("conch_test rounding: ERROR " .. tostring(err))
        if not cleanOk then out("conch_test rounding: CLEANUP ERROR " .. tostring(cleanErr)) end
        return
    end
    if not cleanOk then
        out("conch_test rounding: CLEANUP ERROR " .. tostring(cleanErr))
        return
    end

    out("stat       before->shown   x" .. string.format("%.2f", multiplier)
        .. " raw  shown | correct  bug-order | verdict")
    local counts = { issues = 0 }
    for _, flag in ipairs(STAT_ORDER) do
        local stat = T.STATS[flag]
        local verdict, problems, detail = judgeStat(T, flag, ctx)
        counts[verdict] = (counts[verdict] or 0) + 1
        if #problems > 0 then counts.issues = counts.issues + 1 end
        local test = ctx.tests[1]
        out(string.format("%-10s %6s->%-6s %8s %6s | %7s  %9s | %s%s",
            stat.name,
            fmt(ctx.before.pre[flag]), fmt(ctx.before.post[flag]),
            fmt(test.pre[flag]), fmt(test.final[flag]),
            fmt(detail and detail.expected), fmt(detail and detail.bug),
            verdict,
            #problems > 0 and ("  [" .. table.concat(problems, ", ") .. "]") or ""))
    end
    out(string.format("conch_test rounding: PASS %d  FAIL %d  INCONCLUSIVE %d  n/a %d  NO DATA %d  | other issues %d",
        counts.PASS or 0, counts.FAIL or 0, counts.INCONCLUSIVE or 0,
        counts["n/a"] or 0, counts["NO DATA"] or 0, counts.issues))
    if (counts.INCONCLUSIVE or 0) > 0 then
        out("INCONCLUSIVE: another callback changed that stat between StatsAPI and rounding")
    end
end

-- -------------------------------------------------------------------- sweep
---Runs fn with Conch Blessing and StatsAPI debug logging off; a sweep does
---thousands of cache evaluations and each one logs dozens of lines otherwise.
local function quietly(fn)
    local cfg = ConchBlessing.Config
    local statsApi = rawget(_G, "StatsAPI")
    if type(statsApi) ~= "table" then statsApi = nil end
    local previousConch = cfg and cfg.debugMode
    local previousStats = statsApi and statsApi.DEBUG
    if cfg then cfg.debugMode = false end
    if statsApi then statsApi.DEBUG = false end
    local ok, err = pcall(fn)
    if cfg then cfg.debugMode = previousConch end
    if statsApi then statsApi.DEBUG = previousStats end
    if not ok then error(err, 0) end
end

local function sweepKey(k)
    return SOURCE_KEY .. "_" .. tostring(k)
end

---Total multiplier after k stacks: independent sources multiply, steroid-style
---additive multipliers add their deltas.
local function stackTotal(style, m, k)
    if style == "mult" then return m ^ k end
    return 1 + k * (m - 1)
end

local function pushStack(um, T, player, style, m, k, flag)
    local name = T.STATS[flag].name
    if style == "mult" then
        um:SetPlayerMultiplier(player, sweepKey(k), name, m, "conch_test rounding sweep")
    else
        um:SetPlayerAdditiveMultiplier(player, SOURCE_KEY, name, m, "conch_test rounding sweep")
    end
end

local function popStack(um, T, player, style, m, k, flag)
    local name = T.STATS[flag].name
    if style == "mult" then
        um:RemovePlayerMultiplier(player, sweepKey(k), name)
    else
        -- One additive stack adds m - 1; adding 2 - m takes exactly one back off.
        um:SetPlayerAdditiveMultiplier(player, SOURCE_KEY, name, 2 - m, "conch_test rounding sweep")
    end
end

local function inSafeRange(flag, value)
    local range = SWEEP_SAFE_RANGE[flag]
    return value >= range[1] and value <= range[2]
end

local function clearSweep(um, T, player, stacks)
    for _, flag in ipairs(STAT_ORDER) do
        local name = T.STATS[flag].name
        um:RemovePlayerMultiplier(player, SOURCE_KEY, name)
        for k = 1, stacks do
            um:RemovePlayerMultiplier(player, sweepKey(k), name)
        end
    end
end

local function fmt3(v)
    if type(v) ~= "number" then return "-" end
    return string.format("%.3f", v)
end

---Judges one stat at one stack level.
---@return string verdict, table problems, table|nil info, number|nil chainNext
local function judgeSweepCase(ctx, flag, base, passes, total, prevTotal, chainPrev)
    local stat = ctx.T.STATS[flag]
    local transform = function(v)
        return ConchBlessing.statRounding.applyModes(v, stat.allowsNonPositive,
            ctx.hasCeil, ctx.hasRound, ctx.hasFloor, ctx.base[stat.name])
    end
    local scale = function(v, f)
        v = v * f
        if flag == CacheFlag.CACHE_SPEED then v = speedClamp(v) end
        return v
    end

    local problems = {}
    local function problem(name)
        for _, p in ipairs(problems) do if p == name then return end end
        problems[#problems + 1] = name
    end
    for i, pass in ipairs(passes) do
        if type(pass.pre[flag]) ~= "number" or type(base.pre[flag]) ~= "number" then
            return "NO DATA", { "observers did not fire" }, nil, nil
        end
        if not approx(pass.post[flag], transform(pass.pre[flag])) then problem("rounding") end
        if not approx(pass.final[flag], pass.post[flag]) then problem("changed-after-rounding") end
        if i > 1 and not approx(pass.pre[flag], passes[1].pre[flag]) then problem("drift") end
    end

    if flag == CacheFlag.CACHE_SPEED and speedAtCap(base.pre[flag]) then
        return "skip", problems, nil, nil
    end
    if type(chainPrev) ~= "number" then
        return "skip", problems, nil, nil
    end

    local info = {
        live = passes[1].pre[flag],
        shown = passes[1].post[flag],
        expected = scale(base.pre[flag], total),
        bug = scale(base.post[flag], total),
        chain = scale(chainPrev, total / prevTotal),
    }
    info.expectedOut = transform(info.expected)
    info.bugOut = transform(info.bug)
    info.chainOut = transform(info.chain)

    local distinguishable = not approx(info.expectedOut, info.bugOut)
        or not approx(info.expectedOut, info.chainOut)
    local verdict
    if approx(info.live, info.expected) then
        verdict = distinguishable and "PASS" or "same"
    elseif approx(info.live, info.bug) or approx(info.live, info.chain) then
        verdict = "FAIL"
    else
        verdict = "INCONCLUSIVE"
    end
    return verdict, problems, info, info.chainOut
end

local VERDICTS = { "PASS", "same", "FAIL", "INCONCLUSIVE", "skip", "NO DATA" }

function probe.sweep(stacks, playerIndex)
    local T, um, player, ctx = setup(playerIndex, string.format(
        "sweep: %d offsets x %d multipliers x %d styles, up to %d stacks",
        #SWEEP_OFFSETS, #SWEEP_MULTIPLIERS, #SWEEP_STYLES, stacks))
    if not T then return end

    local counts = {}
    for _, flag in ipairs(STAT_ORDER) do
        counts[flag] = { cases = 0, issues = 0, range = 0 }
        for _, v in ipairs(VERDICTS) do counts[flag][v] = 0 end
    end
    local details, traces = {}, {}
    local evaluations = 0
    local startTime = type(Isaac.GetTime) == "function" and Isaac.GetTime() or nil

    local function evaluate(offset)
        evaluations = evaluations + 1
        return evaluatePass(T, player, offset)
    end
    local function describe(flag, offset, m, style, k)
        return string.format("%s off%+.3f x%s %s k=%d",
            T.STATS[flag].name, offset, tostring(m), style, k)
    end

    local function runCombo(offset, m, style)
        local base = evaluate(offset)
        local levels = { [0] = base }
        -- depth: stacks this stat actually received; a stat stops at its safe range.
        local chain, depth, active = {}, {}, {}
        for _, flag in ipairs(STAT_ORDER) do
            chain[flag] = base.post[flag]
            depth[flag] = 0
            active[flag] = type(base.pre[flag]) == "number" and inSafeRange(flag, base.pre[flag])
            if not active[flag] then
                counts[flag].range = counts[flag].range + 1
            end
        end
        -- Damage at the 1.60 offset is the 5.10 case; trace it level by level.
        local traceKey = offset == 1.6 and (m == 2.0 or m == 1.37) and (style .. " x" .. tostring(m)) or nil
        if traceKey then
            traces[#traces + 1] = string.format("Damage %s: start %s -> shown %s",
                traceKey, fmt3(base.pre[CacheFlag.CACHE_DAMAGE]), fmt(base.post[CacheFlag.CACHE_DAMAGE]))
        end

        local function recordCase(flag, k, passes, total, prevTotal)
            local verdict, problems, info, chainNext =
                judgeSweepCase(ctx, flag, base, passes, total, prevTotal, chain[flag])
            chain[flag] = chainNext
            local c = counts[flag]
            c.cases = c.cases + 1
            c[verdict] = c[verdict] + 1
            if #problems > 0 then c.issues = c.issues + 1 end
            if (verdict == "FAIL" or verdict == "INCONCLUSIVE" or #problems > 0)
                and #details < SWEEP_DETAIL_LINES then
                details[#details + 1] = string.format(
                    "%s: live %s->%s | correct %s->%s | bug %s->%s | chain %s->%s | %s%s",
                    describe(flag, offset, m, style, k),
                    fmt3(info and info.live), fmt(info and info.shown),
                    fmt3(info and info.expected), fmt(info and info.expectedOut),
                    fmt3(info and info.bug), fmt(info and info.bugOut),
                    fmt3(info and info.chain), fmt(info and info.chainOut),
                    verdict,
                    #problems > 0 and (" [" .. table.concat(problems, ", ") .. "]") or "")
            end
            if traceKey and flag == CacheFlag.CACHE_DAMAGE and info then
                traces[#traces + 1] = string.format(
                    "  k=%d total x%.4f: live %s -> shown %s | bug-order %s | chained %s | %s",
                    k, total, fmt3(info.live), fmt(info.shown),
                    fmt(info.bugOut), fmt(info.chainOut), verdict)
            end
        end

        local reached = 0
        for k = 1, stacks do
            local total = stackTotal(style, m, k)
            if total <= SWEEP_MIN_TOTAL then break end
            local anyActive = false
            for _, flag in ipairs(STAT_ORDER) do
                if active[flag] and inSafeRange(flag, base.pre[flag] * total) then
                    pushStack(um, T, player, style, m, k, flag)
                    depth[flag] = k
                    anyActive = true
                elseif active[flag] then
                    active[flag] = false
                    counts[flag].range = counts[flag].range + 1
                end
            end
            if not anyActive then break end
            reached = k
            local passes = {}
            for i = 1, SWEEP_PASSES do passes[i] = evaluate(offset) end
            levels[k] = passes[1]
            local prevTotal = stackTotal(style, m, k - 1)
            for _, flag in ipairs(STAT_ORDER) do
                if depth[flag] == k then
                    recordCase(flag, k, passes, total, prevTotal)
                end
            end
        end

        -- Unwind one stack at a time; each stat must come back exactly to the
        -- value it had at its own depth.
        for k = reached, 1, -1 do
            for _, flag in ipairs(STAT_ORDER) do
                if depth[flag] >= k then
                    popStack(um, T, player, style, m, k, flag)
                end
            end
            local pass = evaluate(offset)
            for _, flag in ipairs(STAT_ORDER) do
                local want = levels[math.min(depth[flag], k - 1)]
                if not (approx(pass.pre[flag], want.pre[flag]) and approx(pass.post[flag], want.post[flag])) then
                    counts[flag].issues = counts[flag].issues + 1
                    if #details < SWEEP_DETAIL_LINES then
                        details[#details + 1] = string.format(
                            "%s: unwind to k=%d gave %s->%s, expected %s->%s [not-restored]",
                            describe(flag, offset, m, style, k), k - 1,
                            fmt3(pass.pre[flag]), fmt(pass.post[flag]),
                            fmt3(want.pre[flag]), fmt(want.post[flag]))
                    end
                end
            end
        end
    end

    local initial, final = nil, nil
    local ok, err = pcall(quietly, function()
        initial = evaluate(nil)
        for _, offset in ipairs(SWEEP_OFFSETS) do
            for _, m in ipairs(SWEEP_MULTIPLIERS) do
                for _, style in ipairs(SWEEP_STYLES) do
                    local comboOk, comboErr = pcall(runCombo, offset, m, style)
                    -- Never let one combo's leftovers leak into the next.
                    clearSweep(um, T, player, stacks)
                    if not comboOk then error(comboErr, 0) end
                end
            end
        end
    end)
    local cleanOk, cleanErr = pcall(function()
        clearSweep(um, T, player, stacks)
        if type(um.SaveToSaveManager) == "function" then
            um:SaveToSaveManager(player)
        end
        final = evaluatePass(T, player)
    end)
    if not ok then out("conch_test rounding sweep: ERROR " .. tostring(err)) end
    if not cleanOk then out("conch_test rounding sweep: CLEANUP ERROR " .. tostring(cleanErr)) end
    if not (ok and cleanOk) then return end

    if #traces > 0 then
        out("-- Damage traces (offset +1.60) --")
        for _, line in ipairs(traces) do out(line) end
    end
    if #details > 0 then
        out(string.format("-- first %d problem cases --", #details))
        for _, line in ipairs(details) do out(line) end
    end

    out("stat        cases  PASS  same  FAIL  INCONC  skip  range  issues")
    local totals = { cases = 0, issues = 0, range = 0 }
    for _, v in ipairs(VERDICTS) do totals[v] = 0 end
    for _, flag in ipairs(STAT_ORDER) do
        local c = counts[flag]
        out(string.format("%-10s %6d %5d %5d %5d %7d %5d %6d %7d",
            T.STATS[flag].name, c.cases, c.PASS, c.same, c.FAIL, c.INCONCLUSIVE, c.skip, c.range, c.issues))
        totals.cases = totals.cases + c.cases
        totals.issues = totals.issues + c.issues
        totals.range = totals.range + c.range
        for _, v in ipairs(VERDICTS) do totals[v] = totals[v] + c[v] end
    end
    local elapsed = startTime and (Isaac.GetTime() - startTime) or nil
    out(string.format(
        "conch_test rounding sweep: %d cases | PASS %d  same %d  FAIL %d  INCONCLUSIVE %d  skip %d  NO DATA %d | issues %d | %d evaluations%s",
        totals.cases, totals.PASS, totals.same, totals.FAIL, totals.INCONCLUSIVE, totals.skip,
        totals["NO DATA"], totals.issues, evaluations,
        elapsed and string.format(" in %d ms", elapsed) or ""))
    out("same = correct and bug orders show the same value; skip = speed already at the StatsAPI cap;"
        .. " range = stat stopped stacking at its safe range")

    -- Every probe change is removed by now, so anything left is a correction
    -- another mod stored while the sweep ran.
    local leftovers = {}
    for _, flag in ipairs(STAT_ORDER) do
        if not approx(final.pre[flag], initial.pre[flag]) then
            leftovers[#leftovers + 1] = string.format("%s %s->%s",
                T.STATS[flag].name, fmt3(initial.pre[flag]), fmt3(final.pre[flag]))
        end
    end
    if #leftovers > 0 then
        out("WARNING: stats did not return to their pre-sweep values: " .. table.concat(leftovers, ", "))
        out("another mod stored a correction during the sweep; the probe's own multipliers are all removed")
    else
        out("baseline restored: every stat is back to its pre-sweep value")
    end
end

function probe.execute(params)

    local number = nil
    local playerIndex = 0
    local sweep = false
    local playerSeen = false
    for word in string.gmatch(tostring(params or ""), "%S+") do
        local lower = string.lower(word)
        local index = string.match(lower, "^p(%d+)$")
        if index and not playerSeen then
            playerIndex = tonumber(index)
            playerSeen = true
        elseif lower == "sweep" and not sweep then
            sweep = true
        elseif tonumber(word) and not number then
            number = tonumber(word)
        else
            out("Usage: conch_test rounding [multiplier | sweep [stacks]] [pN]")
            return
        end
    end

    if sweep then
        -- In sweep mode the number is the stack depth.
        local stacks = number and math.floor(number) or SWEEP_DEFAULT_STACKS
        if stacks < 1 or stacks > SWEEP_MAX_STACKS then
            out(string.format("conch_test rounding sweep: stacks must be 1-%d", SWEEP_MAX_STACKS))
            return
        end
        probe.sweep(stacks, playerIndex)
        return
    end

    local multiplier = number or DEFAULT_MULTIPLIER
    if not (multiplier > 0 and multiplier < math.huge) then
        out("conch_test rounding: multiplier must be a positive number")
        return
    end
    probe.run(multiplier, playerIndex)
end

ConchBlessing.statRoundingProbe = probe
return probe
