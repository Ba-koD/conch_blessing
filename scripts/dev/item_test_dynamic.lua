-- Change real vanilla inventory while the tested item stays owned. Calibrate
-- vanilla-only inputs first; never calculate expected output with an item handler.
local H = require("scripts.dev.item_test_support")
local M = {}
local numeric = {}
for _, key in ipairs({ "MONEY_TEAR", "ORAL_STEROIDS", "POWER_TRAINING", "INJECTABLE_STEROIDS",
    "F_MINUS", "C_MINUS", "B_MINUS", "A_MINUS", "TIME_POWER", "TIME_TEAR", "TIME_LUCK",
    "CEIL", "ROUND", "FLOOR", "SEALED_DEMON_SWORD", "TYRFING", "ETERNAL_FLAME", "KRONOS", "LIVE_EYE" }) do
    numeric[key] = true
end
local attacks = { DRAGON = true, FIRE_BREATH = true, ICE_BREATH = true, VOID_DAGGER = true, SOFLAM = true }
local steroids = { ORAL_STEROIDS = { "oralSteroids", 0.4 }, POWER_TRAINING = { "powerTraining", 0.5 },
    INJECTABLE_STEROIDS = { "injectableSteroids", 0.25 } }
local timers = { TIME_POWER = { "Damage", 0.006 }, TIME_TEAR = { "Tears", 0.0066 }, TIME_LUCK = { "Luck", 0.01 } }

function M.supports(key) return numeric[key] or attacks[key] or key == "TIME_MONEY" end

local function changeBoost(player, ctx, enabled)
    if ctx.dynamicBoost == enabled then return end
    local fixture = {
        { CollectibleType.COLLECTIBLE_SMB_SUPER_FAN, 1 },
        { CollectibleType.COLLECTIBLE_STEVEN, 7 }, -- also crosses Void Dagger's 10-damage duration boundary
        { CollectibleType.COLLECTIBLE_SAD_ONION, 1 },
        { CollectibleType.COLLECTIBLE_SCREW, 1 },
        { CollectibleType.COLLECTIBLE_LUCKY_FOOT, 20 },
    }
    for _, row in ipairs(fixture) do
        for _ = 1, row[2] do
            if enabled then player:AddCollectible(row[1], 0, false) else player:RemoveCollectible(row[1]) end
        end
    end
    ctx.dynamicBoost = enabled
end

function M.prepare(plan, key)
    if not M.supports(key) then return end
    plan.section(key .. " / calibrate vanilla stat inputs")
    plan.act(function(player, ctx) ctx.dynamicRaw = { base = H.stats(player) }; changeBoost(player, ctx, true) end)
    plan.wait(4)
    plan.act(function(player, ctx) ctx.dynamicRaw.boosted = H.stats(player); changeBoost(player, ctx, false) end)
    plan.wait(4)
    plan.require("vanilla stat fixture restores all six input stats", function(player, ctx)
        return H.sameStats(player, ctx.dynamicRaw.base)
    end)
    plan.require("vanilla fixture changes all six input stats", function(_, ctx)
        for stat, value in pairs(ctx.dynamicRaw.base) do
            if H.near(value, ctx.dynamicRaw.boosted[stat]) then return false, stat .. " did not change" end
        end
        return true, "Damage/Tears/Range/Luck/Speed/ShotSpeed inputs changed"
    end)
end

local function factor(player, key, stat)
    if key == "LIVE_EYE" and stat == "Damage" then return ConchBlessing.liveeye.data.damageMultiplier end
    if key == "A_MINUS" and (stat == "Damage" or stat == "Tears" or stat == "Luck") then
        return assert(H.save(player).aMinus.split[stat], "missing A- split")
    end
    local spec = steroids[key]
    if spec and (stat == "Damage" or stat == "Tears" or stat == "Range" or stat == "Luck") then
        local sum = 1
        for _, roll in ipairs(H.save(player)[spec[1]] or {}) do sum = sum + roll[string.lower(stat)] - 1 end
        return math.max(spec[2], sum)
    end
    return 1
end

local function rounded(key, value, stat, player)
    local displayed = math.floor(value * 100 + 0.5) / 100
    if key == "CEIL" then return math.ceil(displayed) end
    if key == "FLOOR" then return math.max(math.floor(displayed), require("scripts.lib.character_base_stats").get(player)[stat]) end
    local out = math.floor(displayed + 0.5)
    return stat ~= "Luck" and displayed > 0 and math.max(1, out) or out
end

local function chanceCheck(player, key)
    local luck = player.Luck
    local actual, expected
    if key == "FIRE_BREATH" then
        actual = ConchBlessing.firebreath._test.getBurnChance(player); expected = math.min(1, math.max(0, luck * 0.05))
    elseif key == "ICE_BREATH" then
        actual = ConchBlessing.icebreath._test.getFreezeChance(player); expected = math.min(1, math.max(0, luck * 0.01))
    elseif key == "SOFLAM" then
        actual = ConchBlessing.soflam._test.getProcChance(player); expected = math.min(1, math.max(0, 0.1 + luck * 0.05))
    elseif key == "LIVE_EYE" then
        actual = ConchBlessing.liveeye._test.getMissForgiveChance(player); expected = math.min(1, math.max(0, 0.5 + luck * 0.05))
    elseif key == "VOID_DAGGER" then
        local sps = math.max(1, H.stats(player).Tears)
        local hooks = ConchBlessing.voiddagger._test
        actual = hooks.applyLuckBonus(hooks.computeProcChanceFromS(sps), luck)
        expected = math.min(1, math.max(0.05, (30 - sps) / 100) * (1 + 0.1 * math.max(0, luck)))
    else return true, "no luck formula" end
    local ok, detail = H.expect(actual, expected)
    return ok, "formula only; live Luck=" .. luck .. " " .. detail
end

local function coinChanceCheck(player)
    local mult = math.max(1, math.min(4, 1 + 0.1 * player.Luck))
    for index, spec in ipairs({ {0.01, 3}, {0.02, 7}, {0.05, 2}, {0.02, 5} }) do
        local calls = 0
        local roll = spec[1] * 1.5
        local rng = { RandomFloat = function() calls = calls + 1; return calls == index and roll or 0.999999 end }
        local actual = ConchBlessing.timemoney._test.chooseCoinSubtype(player, rng)
        local expected = roll < spec[1] * mult and spec[2] or 1
        if actual ~= expected then return false, "coin branch " .. index .. " got " .. actual .. " expected " .. expected end
    end
    return true, "formula only; coin thresholds follow live Luck=" .. player.Luck
end

local function breathBoundaries(plan, key, id, n, contract)
    local S = require("scripts.dev.item_scenarios")
    plan.act(function(player, ctx)
        ctx.breathLuckCopies = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_LUCKY_FOOT, true)
        ctx.breathBase = H.stats(player)
    end)
    -- Change only luck: verify the real trigger boundary and the emitted count,
    -- damage and chance while tears stay constant. Above 14 must clamp to 1.
    for _, luck in ipairs({ 0, 5, 13, 14, 15, 20 }) do
        plan.section(key .. " / luck only = " .. luck)
        plan.act(function(player) S.collectible(player, CollectibleType.COLLECTIBLE_LUCKY_FOOT, luck) end)
        plan.wait(2)
        plan.require("luck fixture changes luck only", function(player, ctx)
            return H.near(player.Luck, luck) and H.near(H.stats(player).Tears, ctx.breathBase.Tears),
                "Luck=" .. player.Luck .. " expected=" .. luck .. "; Tears=" .. H.stats(player).Tears
        end)
        contract.stage(plan, id, n)
    end
    plan.act(function(player) S.collectible(player, CollectibleType.COLLECTIBLE_LUCKY_FOOT, 14) end)
    for _, count in ipairs({ 0, 1, 0 }) do
        plan.section(key .. " / tears only / Sad Onion copies=" .. count)
        plan.act(function(player) S.collectible(player, CollectibleType.COLLECTIBLE_SAD_ONION, count) end)
        plan.wait(2)
        plan.require("tears fixture crosses projectile-count boundary with fixed luck", function(player, ctx)
            local tears, base = H.stats(player).Tears, ctx.breathBase.Tears
            return H.near(player.Luck, 14) and (count == 0 and H.near(tears, base)
                or count > 0 and math.floor(tears) > math.floor(base)),
                "Luck=" .. player.Luck .. " Tears=" .. tears .. " base=" .. base
        end)
        contract.stage(plan, id, n)
    end
    plan.act(function(player, ctx) S.collectible(player, CollectibleType.COLLECTIBLE_LUCKY_FOOT, ctx.breathLuckCopies) end)
    plan.wait(2)
    plan.require("breath boundary fixtures restore all input stats", function(player, ctx) return H.sameStats(player, ctx.breathBase) end)
end

function M.build(plan, key, id, n, contract)
    if not M.supports(key) then return end
    plan.act(function(player, ctx)
        ctx.dynamicOwnedBase = H.stats(player)
        ctx.dynamicStartFrame = Game():GetFrameCount()
    end)
    for _, boosted in ipairs({ true, false }) do
        plan.section(key .. (boosted and " / stats increase while owned" or " / stats decrease while owned"))
        plan.act(function(player, ctx) changeBoost(player, ctx, boosted) end)
        plan.wait(4)
        plan.check("log live input stats", function(player)
            local p = H.stats(player)
            return true, string.format("Damage=%.4f Tears=%.4f Range=%.4f Luck=%.4f Speed=%.4f ShotSpeed=%.4f",
                p.Damage, p.Tears, p.Range, p.Luck, p.Speed, p.ShotSpeed)
        end)
        if numeric[key] then
            plan.check("owned effect follows new stats without reacquisition", function(player, ctx)
                local raw = boosted and ctx.dynamicRaw.boosted or ctx.dynamicRaw.base
                for stat, actual in pairs(H.stats(player)) do
                    local expected
                    if key == "CEIL" or key == "ROUND" or key == "FLOOR" then
                        expected = rounded(key, raw[stat], stat, player)
                    else
                        expected = ctx.dynamicOwnedBase[stat] + (raw[stat] - ctx.dynamicRaw.base[stat]) * factor(player, key, stat)
                        local timer = timers[key]
                        if timer and timer[1] == stat then
                            expected = expected + (Game():GetFrameCount() - ctx.dynamicStartFrame) * timer[2] / 30 * player:GetTrinketMultiplier(id)
                        end
                    end
                    if not H.near(actual, expected) then return false, stat .. " actual=" .. actual .. " expected=" .. expected end
                end
                return true, "all six actual stats follow the input change"
            end)
        end
        if attacks[key] then
            -- Exercise the real firing/applied-damage path again with new stats.
            contract.stage(plan, id, n)
        end
        if key == "FIRE_BREATH" or key == "ICE_BREATH" or key == "SOFLAM" or key == "VOID_DAGGER" or key == "LIVE_EYE" then
            if key == "SOFLAM" or key == "VOID_DAGGER" then
                -- The combat fixture grants 200 Luck for guaranteed procs. Take
                -- that fixture away while checking the ordinary probability.
                plan.act(function(player)
                    for _ = 1, 200 do player:RemoveCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT) end
                end)
                plan.wait(4)
            end
            plan.check("probability formula uses current stats", function(player) return chanceCheck(player, key) end)
            if key == "SOFLAM" or key == "VOID_DAGGER" then
                plan.act(function(player)
                    for _ = 1, 200 do player:AddCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT, 0, false) end
                end)
                plan.wait(4)
            end
        elseif key == "TIME_MONEY" then
            plan.check("coin probability thresholds use current luck", coinChanceCheck)
        end
    end
    if key == "FIRE_BREATH" or key == "ICE_BREATH" then breathBoundaries(plan, key, id, n, contract) end
    if key == "MONEY_TEAR" then
        for _, coins in ipairs({ 0, 99, 10 }) do
            plan.section("MONEY_TEAR / live coin change to " .. coins)
            plan.act(function(player) player:AddCoins(coins - player:GetNumCoins()) end)
            plan.wait(4)
            contract.stage(plan, id, n)
        end
    end
end

return M
