local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 언더독 (Underdog): the lifecycle contract and its cases. Every item enters
-- and leaves through the engine's own inventory (AddCollectible,
-- RemoveCollectible, or a real pedestal touched by Isaac), and every check
-- reads the player's displayed stats. Underdog counts what the player holds
-- now, so its share is measured by taking it away and giving it back. The
-- fixture items are vanilla passives of each quality that give no health or
-- pickups and are no quest items, found in ItemConfig at run time.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function U() return ConchBlessing.underdog end
local function evidence() return U()._test.evidence() end

-- What each quality moves, in displayed units (range in tiles).
local EXPECT = {
    [0] = { stat = "Damage", delta = 1 },
    [1] = { stat = "Tears", delta = 0.3 },
    [2] = { stat = "Range", delta = 0.5 },
    [3] = { stat = "Luck", delta = -0.5 },
    [4] = { stat = "Speed", delta = -0.1 },
}

local fixtures, plain
-- A vanilla passive of each quality 0-4 that gives no health or pickups and
-- is no quest item (ITEM_PASSIVE already leaves familiars out); one that changes no stat at all is preferred
-- (none exists at quality 2 or 4, so their own stat change is allowed: the
-- checks measure Underdog's share by taking it away and giving it back).
local function fixture(quality)
    if not fixtures then
        fixtures, plain = {}, {}
        local config = Isaac.GetItemConfig()
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            local item = config:GetCollectible(id)
            local q = item and item.Quality
            if item and q and q >= 0 and q <= 4 and not item.Hidden
                and item.Type == ItemType.ITEM_PASSIVE
                and (item.AddMaxHearts or 0) == 0 and (item.AddHearts or 0) == 0 and (item.AddSoulHearts or 0) == 0
                and (item.AddBlackHearts or 0) == 0 and (item.AddCoins or 0) == 0 and (item.AddBombs or 0) == 0
                and (item.AddKeys or 0) == 0 and not item:HasTags(ItemConfig.TAG_QUEST) then
                if item.CacheFlags == 0 and not plain[q] then plain[q] = id end
                fixtures[q] = fixtures[q] or id
            end
        end
        for q, id in pairs(plain) do fixtures[q] = id end
    end
    return fixtures[quality]
end

-- Cases that share one run (S.sequenceBundle below); each stays callable alone.
local shared = {}
local case = S.caseIn(shared, "UNDERDOG", { conditions = true })

local function requireModule(plan, qualities)
    plan.require("Underdog module and a fixture item of each quality used", function()
        local missing = {}
        for _, q in ipairs(qualities or { 0, 1, 2, 3, 4 }) do if not fixture(q) then missing[#missing + 1] = q end end
        return U() and U()._test and #missing == 0 and true or nil,
            "missing qualities: " .. table.concat(missing, ",")
    end)
end

local function give(player, id, copies)
    while player:GetCollectibleNum(id) < copies do player:AddCollectible(id, 0, false) end
    while player:GetCollectibleNum(id) > copies do player:RemoveCollectible(id) end
end

-- Underdog's share of each displayed stat right now: the stats while held,
-- less the stats once it is taken away; it is then given back (not a first
-- pickup, so nothing counts).
local function measureShare(plan, id, key)
    plan.act(function(player, ctx)
        ctx.with = H.stats(player)
        player:RemoveCollectible(id)
    end)
    plan.wait(1)
    plan.act(function(player, ctx)
        local without = H.stats(player)
        ctx[key] = {}
        for stat, value in pairs(ctx.with) do ctx[key][stat] = value - without[stat] end
        player:AddCollectible(id, 0, false)
    end)
    plan.wait(1)
end

local function describeShare(share)
    local parts = {}
    for _, stat in ipairs({ "Damage", "Tears", "Range", "Luck", "Speed", "ShotSpeed" }) do
        parts[#parts + 1] = string.format("%s %+.4f", stat, share[stat] or 0)
    end
    return table.concat(parts, " ")
end

-- Pick up one fixture item of `quality` as a first pickup; Underdog's share
-- must grow by exactly that quality's step and nothing else.
local function pickQuality(plan, id, quality)
    local rule = EXPECT[quality]
    measureShare(plan, id, "before")
    plan.act(function(player, ctx)
        ctx.item = fixture(quality)
        player:AddCollectible(ctx.item, 0, true)
    end)
    plan.wait(2)
    measureShare(plan, id, "after")
    plan.check(string.format("quality %d moves only %s by %+.2f", quality, rule.stat, rule.delta), function(_, ctx)
        local ok = true
        for stat, value in pairs(ctx.after) do
            local expected = ctx.before[stat] + (stat == rule.stat and rule.delta or 0)
            if not H.near(value, expected) and math.abs(value - expected) > 1e-4 then ok = false end
        end
        return ok, string.format("item=%d before [%s] after [%s]", ctx.item, describeShare(ctx.before),
            describeShare(ctx.after))
    end)
end

-- The lifecycle's plain quality 0 item: while held damage rises by 1, without it nothing moves.
local function lifecyclePick(plan, counts)
    plan.act(function(player, ctx)
        ctx.before = H.stats(player)
        ctx.item = fixture(0)
        player:AddCollectible(ctx.item, 0, true)
    end)
    plan.wait(2)
    plan.check(string.format("quality 0 %s damage", counts and "raises" or "leaves"), function(player, ctx)
        local now = H.stats(player)
        local expected = ctx.before.Damage + (counts and EXPECT[0].delta or 0)
        local same, detail = true, ""
        for stat, value in pairs(now) do
            if stat ~= "Damage" and not H.near(value, ctx.before[stat]) then same, detail = false, stat .. " moved" end
        end
        return H.near(now.Damage, expected) and same,
            string.format("item=%d damage %.4f -> %.4f expected %.4f %s", ctx.item, ctx.before.Damage, now.Damage,
                expected, detail)
    end)
end

C.UNDERDOG = { stage = function(plan, id, n)
    lifecyclePick(plan, n > 0)
end }

-- One item of each quality: 0 damage +1, 1 tears +0.3, 2 range +0.5,
-- 3 luck -0.5, 4 speed -0.1, each moving only its own stat.
case("qualities", function(plan, id)
    requireModule(plan)
    plan.act(function(player) give(player, id, 1) end)
    for quality = 0, 4 do pickQuality(plan, id, quality) end
end)

-- A real pedestal touched by Isaac counts like any held item.
case("pedestal", function(plan, id)
    requireModule(plan, { 1 })
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() if ctx.pedestal and ctx.pedestal:Exists() then ctx.pedestal:Remove() end end }
        give(player, id, 1)
        ctx.item = fixture(1)
        ctx.before = H.stats(player)
        ctx.pedestal = H.pickup(player, ctx.item)
    end)
    plan.wait(20)
    plan.waitUntil(function(player, ctx)
        player.Position = ctx.pedestal.Position
        player.Velocity = Vector.Zero
        return player:GetCollectibleNum(ctx.item) > 0 and player:IsExtraAnimationFinished(),
            "waiting for Isaac to pick it up"
    end, 120, "Isaac takes the quality 1 item from its pedestal")
    plan.wait(4)
    plan.check("the pedestal pickup raised tears by 0.3", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Tears, ctx.before.Tears + EXPECT[1].delta),
            string.format("tears %.4f -> %.4f", ctx.before.Tears, now.Tears)
    end)
end)

-- Items held before Underdog count the moment it is picked up.
case("held_before", function(plan, id)
    requireModule(plan, { 0, 3 })
    plan.act(function(player)
        player:AddCollectible(fixture(0), 0, true)
        player:AddCollectible(fixture(0), 0, true)
        player:AddCollectible(fixture(3), 0, true)
    end)
    plan.wait(2)
    plan.act(function(player, ctx)
        ctx.before = H.stats(player)
        player:AddCollectible(id, 0, true)
    end)
    plan.wait(2)
    plan.check("two quality 0 and one quality 3 item held before: damage +2, luck -0.5", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Damage, ctx.before.Damage + 2 * EXPECT[0].delta)
            and H.near(now.Luck, ctx.before.Luck + EXPECT[3].delta),
            string.format("damage %.3f -> %.3f luck %.3f -> %.3f", ctx.before.Damage, now.Damage, ctx.before.Luck, now.Luck)
    end)
end)

-- An item leaving takes its share: at once when the item total changes, and
-- within the sweep when one item is swapped for another.
case("leave", function(plan, id)
    requireModule(plan, { 0, 1, 4 })
    plan.act(function(player)
        give(player, id, 1)
        player:AddCollectible(fixture(0), 0, true)
        player:AddCollectible(fixture(1), 0, true)
    end)
    plan.wait(2)
    measureShare(plan, id, "before")
    plan.act(function(player) player:RemoveCollectible(fixture(1)) end)
    plan.wait(2)
    measureShare(plan, id, "after")
    plan.check("removing the quality 1 item takes its +0.3 tears", function(_, ctx)
        return H.near(ctx.after.Tears, ctx.before.Tears - EXPECT[1].delta) and H.near(ctx.after.Damage, ctx.before.Damage),
            string.format("before [%s] after [%s]", describeShare(ctx.before), describeShare(ctx.after))
    end)
    plan.act(function(player, ctx)
        ctx.total = player:GetCollectibleCount()
        player:RemoveCollectible(fixture(0))
        player:AddCollectible(fixture(4), 0, true)
    end)
    plan.wait((U() and U().sweep or 30) + 5)
    measureShare(plan, id, "swapped")
    plan.check("a swap that keeps the item total is caught: damage -1, speed -0.1", function(player, ctx)
        local s = ctx.swapped
        return player:GetCollectibleCount() == ctx.total
            and H.near(s.Damage, ctx.after.Damage - EXPECT[0].delta)
            and H.near(s.Speed, ctx.after.Speed + EXPECT[4].delta),
            string.format("total %d -> %d; after [%s] swapped [%s]", ctx.total, player:GetCollectibleCount(),
                describeShare(ctx.after), describeShare(s))
    end)
end)

-- A quest item and a second Underdog count nothing, and nothing counts while
-- it is not held.
case("not_counted", function(plan, id)
    requireModule(plan, { 0 })
    plan.act(function(player, ctx)
        give(player, id, 1)
        ctx.before = H.stats(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1, 0, true)
        player:AddCollectible(id, 0, true)
    end)
    plan.wait((U() and U().sweep or 30) + 5)
    plan.check("a quest item and a second Underdog change nothing", function(player, ctx)
        return H.sameStats(player, ctx.before)
    end)
    plan.act(function(player, ctx)
        give(player, id, 0)
        ctx.before = H.stats(player)
        player:AddCollectible(fixture(0), 0, true)
    end)
    plan.wait((U() and U().sweep or 30) + 5)
    plan.check("without Underdog a held item gives nothing", function(player, ctx)
        return H.sameStats(player, ctx.before)
    end)
end)

-- The changes leave with Underdog and come back with it.
case("loss", function(plan, id)
    requireModule(plan, { 0, 3 })
    plan.act(function(player, ctx)
        ctx.base = H.stats(player)
        give(player, id, 1)
        player:AddCollectible(fixture(0), 0, true)
        player:AddCollectible(fixture(3), 0, true)
    end)
    plan.wait(2)
    plan.check("damage +1 and luck -0.5 while held", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Damage, ctx.base.Damage + EXPECT[0].delta) and H.near(now.Luck, ctx.base.Luck + EXPECT[3].delta),
            string.format("damage %.3f luck %.3f", now.Damage, now.Luck)
    end)
    plan.act(function(player) give(player, id, 0) end)
    plan.wait(2)
    plan.check("losing Underdog takes both away", function(player, ctx) return H.sameStats(player, ctx.base) end)
    plan.act(function(player) player:AddCollectible(id, 0, false) end)
    plan.wait(2)
    plan.check("holding it again brings them back", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Damage, ctx.base.Damage + EXPECT[0].delta) and H.near(now.Luck, ctx.base.Luck + EXPECT[3].delta),
            string.format("damage %.3f luck %.3f", now.Damage, now.Luck)
    end)
end)

-- Every case only adds and removes items through the engine's own inventory
-- and reads stat changes, so they share one run: S.resetPlayer takes every
-- item away again and proves the stats are back where the run started.
S.sequenceBundle("UNDERDOG", "shared", { conditions = true }, shared, function(plan) S.resetPlayer(plan) end)

return C
