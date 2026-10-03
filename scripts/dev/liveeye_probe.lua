-- Live Eye test bench: `conch_liveeye` restarts the run, checks that a missed
-- tear can be forgiven (50% + 5% per luck), that only unforgiven misses lower
-- the damage multiplier, that a non-tear attack fixes it at x1.5 and Rock Bottom
-- at x3.0, then restarts the run again (scripts/dev/test_bench.lua).
-- This file is dev tooling and only acts while its command runs.

local TestBench = require("scripts.dev.test_bench")

local LIVE_EYE_ID = Isaac.GetItemIdByName("Live Eye")
local MISSES_PER_LUCK = 200
local BATCH = 20

local function counters()
    return ConchBlessing.liveeye._counters
end

local function multiplier()
    return ConchBlessing.liveeye.data.damageMultiplier
end

-- The multiplier the last damage evaluation actually applied.
local function applied(player)
    return player:GetData().__conchLiveEyeApplied
end

local function appliedIs(label, value)
    return function(player)
        local now = applied(player)
        return now == value, string.format("%s: applied x%s", label, tostring(now))
    end
end

-- Odds checked over MISSES_PER_LUCK misses. 0% and 100% must be exact; the
-- others allow about four standard deviations of a binomial draw.
local CASES = {
    { luck = -10, expected = 0.0, tolerance = 0 },
    { luck = 0, expected = 0.5, tolerance = 30 },
    { luck = 5, expected = 0.75, tolerance = 26 },
    { luck = 10, expected = 1.0, tolerance = 0 },
}

local function build(plan)
    plan.section("setup", nil)
    plan.act(function(player)
        player:AddCollectible(LIVE_EYE_ID, 0, false)
    end)
    plan.wait(10)

    plan.section("tear miss path", nil)
    plan.act(function(player, ctx)
        ctx.fixedAtStart = ConchBlessing.liveeye._test.getFixedMultiplier(player)
        ctx.misses = counters().misses
        local tear = player:FireTear(player.Position, Vector(0, -14), false, true, false)
        -- FireTear may skip MC_POST_FIRE_TEAR; start Live Eye's tracking the same way.
        if tear and not tear:GetData().conch_liveeye then
            ConchBlessing.liveeye.onFireTear(nil, tear)
        end
        ctx.tracked = tear ~= nil and tear:GetData().conch_liveeye ~= nil
    end)
    plan.waitUntil(function(_, ctx) return counters().misses > ctx.misses end, 120)
    plan.check("a tear that hits nothing counts as one miss", function(_, ctx)
        if ctx.fixedAtStart then return nil, "this character has no tear attack" end
        local n = counters().misses - ctx.misses
        return n == 1, string.format("misses +%d (tear tracked: %s)", n, tostring(ctx.tracked))
    end)

    for _, case in ipairs(CASES) do
        plan.section(string.format("luck %d", case.luck), nil)
        plan.act(function(player, ctx)
            ctx.luckBefore = player.Luck
            ctx.misses, ctx.forgiven = counters().misses, counters().forgiven
        end)
        for _ = 1, MISSES_PER_LUCK // BATCH do
            plan.act(function(player)
                -- Set right before the batch: a luck cache re-evaluation elsewhere
                -- would restore the real value between updates.
                player.Luck = case.luck
                ConchBlessing.liveeye.data.damageMultiplier = 2.0
                for _ = 1, BATCH do ConchBlessing.liveeye.handleMiss(player) end
            end)
            plan.wait(1)
        end
        plan.check(string.format("misses kept at luck %d (want %.0f%%)", case.luck, case.expected * 100),
            function(player, ctx)
                local misses = counters().misses - ctx.misses
                local kept = counters().forgiven - ctx.forgiven
                player.Luck = ctx.luckBefore
                local ok = math.abs(kept - case.expected * misses) <= case.tolerance
                return ok, string.format("%d of %d kept (%.1f%%)", kept, misses, kept / math.max(1, misses) * 100)
            end)
    end

    plan.section("multiplier", nil)
    plan.act(function(player)
        player.Luck = 10
        ConchBlessing.liveeye.data.damageMultiplier = 2.0
        for _ = 1, 5 do ConchBlessing.liveeye.handleMiss(player) end
    end)
    plan.check("Luck 10: 5 misses leave the multiplier at x2.00", function()
        return math.abs(multiplier() - 2.0) < 1e-9, string.format("x%.2f", multiplier())
    end)
    plan.act(function(player)
        player.Luck = -10
        ConchBlessing.liveeye.data.damageMultiplier = 2.0
        for _ = 1, 2 do ConchBlessing.liveeye.handleMiss(player) end
    end)
    plan.check("Luck -10: 2 misses lower it by 0.15 each", function()
        return math.abs(multiplier() - 1.7) < 1e-9, string.format("x%.2f", multiplier())
    end)

    plan.section("non-tear attack", nil)
    plan.act(function(player, ctx)
        ConchBlessing.liveeye.data.damageMultiplier = 2.0
        ctx.misses = counters().misses
        player:AddCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE, 0, false)
    end)
    plan.wait(20)
    plan.check("Brimstone fixes the multiplier at x1.5", appliedIs("Brimstone", 1.5))
    plan.act(function(player, ctx)
        local tear = player:FireTear(player.Position, Vector(0, -14), false, true, false)
        if tear and not tear:GetData().conch_liveeye then ConchBlessing.liveeye.onFireTear(nil, tear) end
        ctx.tracked = tear ~= nil and tear:GetData().conch_liveeye ~= nil
    end)
    plan.wait(60)
    plan.check("a stray tear is not scored while fixed", function(_, ctx)
        local n = counters().misses - ctx.misses
        return not ctx.tracked and n == 0, string.format("tracked %s, misses +%d", tostring(ctx.tracked), n)
    end)
    plan.act(function(player)
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
    end)
    plan.wait(20)
    plan.check("back to tears: hits and misses drive it again", appliedIs("tears", 2.0))

    plan.section("Rock Bottom", nil)
    plan.act(function(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_ROCK_BOTTOM, 0, false)
    end)
    plan.wait(20)
    plan.check("Rock Bottom fixes it at x3.0", appliedIs("Rock Bottom", 3.0))
    plan.act(function(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE, 0, false)
    end)
    plan.wait(20)
    plan.check("Rock Bottom + Brimstone stays x3.0", appliedIs("Rock Bottom + Brimstone", 3.0))
end

TestBench.register({
    command = "conch_liveeye",
    tag = "LiveEyeProbe",
    duration = "about 15 seconds",
    build = build,
})

return {}
