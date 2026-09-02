-- RNG probe: measures the expected value of every random mechanic in the mod by
-- sampling the shipped functions, not copies of them.
--
-- Console:  conch_rng            run every probe with 100000 samples
--           conch_rng 500000     custom sample count
--           conch_rng luck 20    run the luck-dependent probes at Luck 20
--
-- Deterministic probes (proc chances) are evaluated, not sampled, because they are
-- pure functions of Luck and MaxFireDelay. Distribution probes are sampled.
--
-- This file is dev tooling. It registers one console command and touches no game
-- state; leaving it loaded costs a single MC_EXECUTE_CMD handler.

local probe = {}

local DEFAULT_SAMPLES = 100000

local function out(line)
    Isaac.ConsoleOutput(tostring(line) .. "\n")
    ConchBlessing.printDebug("[RNG] " .. tostring(line))
end

local function header(title)
    out("")
    out("== " .. title .. " ==")
end

---Run fn with per-call debug logging suppressed and restore the setting afterwards.
---The shipped roll functions log a line every call; at sampling volume that is
---hundreds of thousands of log lines per run, so sampling must not leave it on.
local function quietly(fn)
    local cfg = ConchBlessing.Config
    local previous = cfg and cfg.debugMode
    if cfg then cfg.debugMode = false end
    local ok, a, b, c = pcall(fn)
    if cfg then cfg.debugMode = previous end
    if not ok then error(a, 0) end
    return a, b, c
end

---Sample a nullary function returning a number.
local function sampleNumbers(fn, samples)
    return quietly(function()
        local sum, min, max = 0, math.huge, -math.huge
        for _ = 1, samples do
            local v = fn()
            sum = sum + v
            if v < min then min = v end
            if v > max then max = v end
        end
        return sum / samples, min, max
    end)
end

---Sample a nullary function returning a key, and tally how often each key comes up.
local function sampleBuckets(fn, samples)
    return quietly(function()
        local counts = {}
        for _ = 1, samples do
            local k = fn()
            counts[k] = (counts[k] or 0) + 1
        end
        return counts
    end)
end

-- ---------------------------------------------------------------- stat rollers
-- Uniform over [min, max) truncated to 2 decimals, so the exact mean is
-- (min + max - 0.01) / 2 rather than the midpoint.
local ROLLERS = {
    { label = "Oral Steroids",       module = "oralsteroids",       cfg = "STATS",
      lo = "MIN_MULTIPLIER", hi = "MAX_MULTIPLIER", factor = "MIN_TOTAL_MULTIPLIER_FACTOR" },
    { label = "Power Training",      module = "powertraining",      cfg = "data",
      lo = "minMultiplier",  hi = "maxMultiplier",  factor = "minTotalMultiplierFactor" },
    { label = "Injectable Steroids", module = "injectablsteroids",  cfg = "data",
      lo = "minMultiplier",  hi = "maxMultiplier",  factor = "minTotalMultiplierFactor" },
}

function probe.statRolls(samples)
    header("Per-roll stat multiplier")
    for _, r in ipairs(ROLLERS) do
        local mod = ConchBlessing[r.module]
        if not (mod and mod.rollStat) then
            out(string.format("%-20s SKIPPED (module not loaded)", r.label))
        else
            local cfg = mod[r.cfg]
            local lo, hi = cfg[r.lo], cfg[r.hi]
            local expected = (lo + hi - 0.01) / 2
            local mean, min, max = sampleNumbers(mod.rollStat, samples)
            out(string.format("%-20s [%.2f, %.2f)  E=%.4f  measured=%.4f  min=%.2f max=%.2f",
                r.label, lo, hi, expected, mean, min, max))
        end
    end
end

function probe.stacking(samples)
    header("Stacking (applied path: total = 1 + sum(roll - 1))")
    -- StatsAPI's SetItemAdditiveMultiplier accumulates `value - 1` and applies
    -- `1 + cumulative`, so stacking is additive. The `total = total * roll` product
    -- inside each item file only reaches a debug log and is not modelled here.
    local perDepth = math.max(1000, math.floor(samples / 10))
    for _, r in ipairs(ROLLERS) do
        local mod = ConchBlessing[r.module]
        if mod and mod.rollStat then
            local cfg = mod[r.cfg]
            local perRoll = (cfg[r.lo] + cfg[r.hi] - 0.01) / 2
            local floorValue = (cfg[r.lo] or 0) * (cfg[r.factor] or 0)
            out(string.format("%-20s applied floor = %.2f x %.2f = %.3f",
                r.label, cfg[r.lo], cfg[r.factor] or 0, floorValue))
            for _, n in ipairs({ 1, 2, 3, 5 }) do
                local sum, losses, floored = quietly(function()
                    local s, l, f = 0, 0, 0
                    for _ = 1, perDepth do
                        local total = 1.0
                        for _ = 1, n do total = total + (mod.rollStat() - 1.0) end
                        if total < floorValue then total = floorValue f = f + 1 end
                        s = s + total
                        if total < 1.0 then l = l + 1 end
                    end
                    return s, l, f
                end)
                out(string.format("%-20s x%d  E=%.3f  measured=%.3f  P(<1)=%.1f%%  P(at floor)=%.1f%%",
                    r.label, n, 1 + n * (perRoll - 1), sum / perDepth,
                    losses / perDepth * 100, floored / perDepth * 100))
            end
        end
    end
end

-- --------------------------------------------------------------- proc chances
function probe.voidDagger()
    header("Void Dagger proc chance (deterministic in MaxFireDelay and Luck)")
    local t = ConchBlessing.voiddagger and ConchBlessing.voiddagger._test
    if not t then out("SKIPPED (module not loaded)") return end
    local player = Isaac.GetPlayer(0)
    out(string.format("live player: MaxFireDelay=%.2f Luck=%.2f", player.MaxFireDelay, player.Luck))
    for _, delay in ipairs({ 0, 1, 2, 5, 10, 15 }) do
        local s = t.getShotsPerSecond({ MaxFireDelay = delay })
        local base = t.computeProcChanceFromS(s)
        local line = string.format("  MaxFireDelay %-3d S=%5.2f base=%5.1f%%", delay, s, base * 100)
        for _, luck in ipairs({ 0, 5, 10, 20 }) do
            local final = t.applyLuckBonus(base, luck)
            line = line .. string.format("  L%d=%.1f%%", luck, final * 100)
        end
        out(line)
    end
end

function probe.flatChances(luck)
    header("Flat luck-scaled chances at Luck " .. tostring(luck))
    local fake = { Luck = luck }
    local function hook(moduleName, fnName)
        local mod = ConchBlessing[moduleName]
        local t = mod and mod._test
        return t and t[fnName] or nil
    end
    local rows = {
        { "SOFLAM target",     hook("soflam", "getProcChance") },
        { "Ice Breath freeze", hook("icebreath", "getFreezeChance") },
        { "Fire Breath burn",  hook("firebreath", "getBurnChance") },
    }
    for _, row in ipairs(rows) do
        if row[2] then
            out(string.format("  %-18s %.1f%%", row[1], row[2](fake) * 100))
        else
            out(string.format("  %-18s SKIPPED (module not loaded)", row[1]))
        end
    end
end

-- ------------------------------------------------------------------ time money
local COIN_NAMES = { [1] = "penny", [2] = "nickel", [3] = "dime", [5] = "lucky", [7] = "golden" }
local COIN_VALUE = { [1] = 1, [2] = 5, [3] = 10, [5] = 1, [7] = 1 }

function probe.timeMoney(samples, luck)
    header("Time = Money coin replacement at Luck " .. tostring(luck))
    local t = ConchBlessing.timemoney and ConchBlessing.timemoney._test
    if not t then out("SKIPPED (module not loaded)") return end
    -- The rolls are a sequential if/elseif, so each tier is conditional on the
    -- earlier ones failing; the flat EID percentages are the inputs, not the results.
    local rng = RNG()
    local seed = Random()
    if seed == 0 then seed = 1 end
    rng:SetSeed(seed, 35)
    local fake = { Luck = luck }
    local counts = sampleBuckets(function() return t.chooseCoinSubtype(fake, rng) end, samples)
    local ev = 0
    for sub, n in pairs(counts) do
        local share = n / samples
        ev = ev + share * (COIN_VALUE[sub] or 1)
        out(string.format("  %-8s %6.3f%%", COIN_NAMES[sub] or ("sub" .. sub), share * 100))
    end
    out(string.format("  E[coin value] = %.4f", ev))
end

-- ---------------------------------------------------------------------- A minus
function probe.aMinus(samples)
    header("A- stat split (sum is fixed at totalMultSum, share is random)")
    local t = ConchBlessing.aminus and ConchBlessing.aminus._test
    if not t then out("SKIPPED (module not loaded)") return end
    local cfg = ConchBlessing.aminus.data.config
    local stats = cfg.stats or {}
    local expected = cfg.minPerStat + (cfg.totalMultSum - cfg.minPerStat * #stats) / #stats
    -- computeRandomSplit reseeds from the run seed and the player, so repeated calls
    -- return the same split by design. Report that split and the closed-form mean.
    local split = quietly(function() return t.computeRandomSplit(Isaac.GetPlayer(0)) end)
    local sum = 0
    for _, name in ipairs(stats) do
        sum = sum + (split[name] or 0)
        out(string.format("  %-8s this run = %.4f", name, split[name] or 0))
    end
    out(string.format("  sum = %.4f (config totalMultSum = %.2f)", sum, cfg.totalMultSum))
    out(string.format("  E per stat = %.4f = %.2f + (%.2f - %d*%.2f)/%d",
        expected, cfg.minPerStat, cfg.totalMultSum, #stats, cfg.minPerStat, #stats))
end

-- --------------------------------------------------------------- death spiral
function probe.injectableDeath()
    header("Injectable Steroids instant death (cumulative over one floor)")
    local d = ConchBlessing.injectablsteroids and ConchBlessing.injectablsteroids.data
    if not d then out("SKIPPED (module not loaded)") return end
    out(string.format("  base=%.2f%% increment=%.2f%%/use current=%.2f%%",
        d.baseInstantDeathPercent, d.instantDeathPercentIncrement, d.currentInstantDeathPercent))
    local survive, expectedUses = 1.0, 0.0
    for use = 1, 200 do
        local pct = math.min(100, d.baseInstantDeathPercent + d.instantDeathPercentIncrement * (use - 1))
        -- math.random(1,100) is an integer draw, so a fractional pct truncates: the
        -- room-clear decay does nothing until it crosses a whole percent.
        local effective = math.floor(pct) / 100
        expectedUses = expectedUses + survive
        if use <= 10 then
            out(string.format("  use %-3d raw %5.1f%% -> %3d%%  cumulative dead = %.2f%%",
                use, pct, math.floor(pct), (1 - survive * (1 - effective)) * 100))
        end
        survive = survive * (1 - effective)
        if survive <= 0 then
            out(string.format("  death is certain on use %d", use))
            break
        end
    end
    out(string.format("  E[uses per floor before dying] = %.2f (ignoring room-clear decay)", expectedUses))
end

-- ------------------------------------------------------------------- command
ConchBlessing:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, cmd, params)
    if string.lower(tostring(cmd)) ~= "conch_rng" then return end

    local args = {}
    for word in string.gmatch(tostring(params or ""), "%S+") do
        args[#args + 1] = word
    end

    local samples = DEFAULT_SAMPLES
    local luck = Isaac.GetPlayer(0).Luck
    local i = 1
    while i <= #args do
        if string.lower(args[i]) == "luck" and args[i + 1] then
            luck = tonumber(args[i + 1]) or luck
            i = i + 2
        else
            samples = tonumber(args[i]) or samples
            i = i + 1
        end
    end

    out(string.format("conch_rng: %d samples, Luck %s", samples, tostring(luck)))
    probe.statRolls(samples)
    probe.stacking(samples)
    probe.voidDagger()
    probe.flatChances(luck)
    probe.timeMoney(samples, luck)
    probe.aMinus(samples)
    probe.injectableDeath()
    out("")
    out("conch_rng: done")
end)

ConchBlessing.rngProbe = probe
return probe
