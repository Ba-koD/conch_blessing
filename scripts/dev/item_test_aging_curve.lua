local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 에이징 커브 (Aging Curve): the lifecycle contract and its cases. Every copy
-- enters and leaves through the engine's own inventory, and every check reads
-- the player's displayed stats. The item's share is measured by taking every
-- copy away and giving them back (not first pickups). The expected numbers
-- are the user's design (2026-11-24), written out per floor here rather than
-- read from the module: damage 9 - 1.5 x stage, tears 3 - 0.5 x stage, range
-- 6 - stage tiles, shot speed and speed 0.6 - 0.1 x stage per copy, nothing on
-- stage 6, luck +1 a stage from stage 4. The item sets no floor of its own;
-- the engine keeps damage at 0.5, shot speed at 0.6 and range at one tile
-- (measured 2026-11-24 with `cb test aging_curve engine`).
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function A() return ConchBlessing.agingCurve end

local STATS = { "Damage", "Tears", "Range", "Luck", "Speed", "ShotSpeed" }
-- Per copy, in displayed units (range in tiles).
local EXPECT = {
    [1] = { Damage = 7.5, Tears = 2.5, Speed = 0.5, Range = 5, ShotSpeed = 0.5, Luck = 0 },
    [4] = { Damage = 3, Tears = 1, Speed = 0.2, Range = 2, ShotSpeed = 0.2, Luck = 1 },
    [6] = { Damage = 0, Tears = 0, Speed = 0, Range = 0, ShotSpeed = 0, Luck = 3 },
    [7] = { Damage = -1.5, Tears = -0.5, Speed = -0.1, Range = -1, ShotSpeed = -0.1, Luck = 4 },
}
-- Isaac on stage 13 with one copy: the engine stops damage, range and shot
-- speed at its own floors; speed 1 - 0.7. Tears are recorded, not checked:
-- nothing in the engine stops them (StatsAPI leaves 0.01 shots a second).
local FLOORED = { Damage = 0.5, Range = 1, ShotSpeed = 0.6, Speed = 0.3, Luck = 10 }

local function give(player, id, copies)
    while player:GetCollectibleNum(id) < copies do player:AddCollectible(id, 0, false) end
    while player:GetCollectibleNum(id) > copies do player:RemoveCollectible(id) end
end

-- The item's share of each displayed stat right now: the stats while held,
-- less the stats with every copy taken away; the copies are then given back.
local function measureShare(plan, id, key)
    plan.act(function(player, ctx)
        ctx.with = H.stats(player)
        ctx[key .. "With"] = ctx.with
        ctx.held = player:GetCollectibleNum(id)
        give(player, id, 0)
    end)
    plan.wait(1)
    plan.act(function(player, ctx)
        local without = H.stats(player)
        ctx[key] = {}
        for _, stat in ipairs(STATS) do ctx[key][stat] = ctx.with[stat] - without[stat] end
        give(player, id, ctx.held)
    end)
    plan.wait(1)
end

local function describe(share, expected)
    local parts = {}
    for _, stat in ipairs(STATS) do
        parts[#parts + 1] = string.format("%s %+.4f (want %+.4f)", stat, share[stat] or 0, expected[stat] or 0)
    end
    return table.concat(parts, " ")
end

-- Whether the measured share matches `copies` times the stage's numbers.
local function expectShare(plan, label, key, stage, copies)
    plan.check(label, function(_, ctx)
        local share, expected, ok = ctx[key], {}, true
        for _, stat in ipairs(STATS) do
            expected[stat] = EXPECT[stage][stat] * copies
            if math.abs(share[stat] - expected[stat]) > 0.002 then ok = false end
        end
        return ok, string.format("stage %d, %d cop%s: %s", Game():GetLevel():GetStage(), copies,
            copies == 1 and "y" or "ies", describe(share, expected))
    end)
end

local function requireModule(plan)
    plan.require("Aging Curve module ready", function()
        return A() and A()._test and true or nil, "module missing"
    end)
end

-- The lifecycle runs on the first floor: n copies give n times the prime.
C.AGING_CURVE = { stage = function(plan, id, n)
    requireModule(plan)
    measureShare(plan, id, "share")
    expectShare(plan, n > 0 and "the first floor's prime, once per copy" or "without it no stat moves", "share", 1, n)
end }

-- Floor by floor with one copy: the prime on stage 1, less on stage 4,
-- nothing but luck +3 on stage 6, below nothing on stage 7, and on stage 13
-- Isaac's damage, range and shot speed resting on the engine's floors with
-- luck +10.
-- Each new floor is a real one (the `stage` command), so the case runs alone.
S.add("AGING_CURVE", "floors", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player) give(player, id, 1) end)
    plan.wait(2)
    for _, stage in ipairs({ 1, 4, 6, 7 }) do
        if stage > 1 then S.newFloor(plan, stage) end
        measureShare(plan, id, "share" .. stage)
        expectShare(plan, "stage " .. stage .. " follows the curve", "share" .. stage, stage, 1)
    end
    S.newFloor(plan, 13)
    measureShare(plan, id, "share13")
    plan.check("stage 13: the engine stops damage, range and shot speed at its floors", function(_, ctx)
        local with, ok, parts = ctx.share13With, true, {}
        for _, stat in ipairs(STATS) do
            local want = FLOORED[stat]
            if want then
                local got = stat == "Luck" and ctx.share13.Luck or with[stat]
                if math.abs(got - want) > 0.002 then ok = false end
                parts[#parts + 1] = string.format("%s %.4f (want %.4f)", stat, got, want)
            end
        end
        return ok, string.format("stage %d, Isaac with 1 copy (luck as the item's share): %s",
            Game():GetLevel():GetStage(), table.concat(parts, " "))
    end)
    plan.note("stage 13 tears", function(_, ctx) return string.format("%.4f shots a second", ctx.share13With.Tears) end)
end)

-- A measurement (run by name): what the engine does with the stats stage 13
-- asks of Isaac (damage -7, tears below nothing, range -0.5 tiles, shot speed
-- and speed 0.3). Records the stats as stored, then one real tear fired at a
-- target with and without the item: its damage, speed, lifetime and the HP it
-- took.
local function shoot(plan, tag)
    plan.act(function(player, ctx)
        ctx.target = H.target(player, true)
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 60, "target ready")
    plan.act(function(player, ctx)
        local s = H.stats(player)
        ctx[tag] = { stats = string.format("Damage %.4f MaxFireDelay %.2f (tears %.4f) TearRange %.2f ShotSpeed %.4f "
            .. "MoveSpeed %.4f Luck %.2f", player.Damage, player.MaxFireDelay, s.Tears, player.TearRange,
            player.ShotSpeed, player.MoveSpeed, player.Luck) }
        ctx.hp0 = ctx.target.HitPoints
        local dir = (ctx.target.Position - player.Position):Normalized()
        local tear = player:FireTear(player.Position, dir * 10 * player.ShotSpeed, false, true, false)
        ctx.tearPtr, ctx.born = tear and EntityPtr(tear), Game():GetFrameCount()
        ctx[tag].tear = tear and string.format("CollisionDamage %.4f speed %.4f height %.2f falling %.4f",
            tear.CollisionDamage, tear.Velocity:Length(), tear.Height, tear.FallingSpeed) or "no tear"
    end)
    plan.waitUntil(function(_, ctx) return not (ctx.tearPtr and ctx.tearPtr.Ref and ctx.tearPtr.Ref:Exists()) end, 300,
        "tear gone")
    plan.act(function(_, ctx) ctx[tag].life = Game():GetFrameCount() - ctx.born end)
    plan.wait(8)
    plan.act(function(_, ctx)
        ctx[tag].hp = ctx.hp0 - ctx.target.HitPoints
        ctx.target:Remove()
    end)
    plan.wait(2)
    plan.note(tag .. " stats", function(_, ctx) return ctx[tag].stats end)
    plan.note(tag .. " tear", function(_, ctx)
        return string.format("%s life %d frames, target HP lost %.4f", ctx[tag].tear, ctx[tag].life, ctx[tag].hp)
    end)
end

S.add("AGING_CURVE", "engine", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.note("MC_EVALUATE_CACHE order", function()
        local out = {}
        for i, cb in ipairs(Isaac.GetCallbacks(ModCallbacks.MC_EVALUATE_CACHE) or {}) do
            out[#out + 1] = string.format("%d:%s(%s)", i, tostring(cb.Mod and cb.Mod.Name), tostring(cb.Priority))
        end
        return table.concat(out, " ")
    end)
    S.newFloor(plan, 13)
    plan.act(function(player) give(player, id, 1) end)
    plan.wait(4)
    shoot(plan, "with")
    plan.act(function(player) give(player, id, 0) end)
    plan.wait(4)
    shoot(plan, "without")
end)
S.rows[#S.rows].manual = true

-- Two copies add up, on the first floor and past stage 6.
S.add("AGING_CURVE", "copies", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player) give(player, id, 2) end)
    plan.wait(2)
    measureShare(plan, id, "early")
    expectShare(plan, "two copies on the first floor give twice the prime", "early", 1, 2)
    S.newFloor(plan, 7)
    measureShare(plan, id, "late")
    expectShare(plan, "two copies late fall twice as far and give twice the luck", "late", 7, 2)
end)

return C
