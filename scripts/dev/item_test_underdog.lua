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
    [0] = { stat = "Damage", delta = 1.5 },
    [1] = { stat = "Tears", delta = 0.4 },
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

-- The lifecycle's plain quality 0 item: with n copies held damage rises by n
-- (copies stack, user decision 2026-11-21), without it nothing moves.
local function lifecyclePick(plan, copies)
    plan.act(function(player, ctx)
        ctx.before = H.stats(player)
        ctx.item = fixture(0)
        player:AddCollectible(ctx.item, 0, true)
    end)
    plan.wait(2)
    plan.check(copies > 0 and string.format("quality 0 raises damage by %g with %d cop%s", copies * EXPECT[0].delta,
        copies, copies == 1 and "y" or "ies") or "quality 0 leaves damage", function(player, ctx)
        local now = H.stats(player)
        local expected = ctx.before.Damage + copies * EXPECT[0].delta
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
    lifecyclePick(plan, n)
end }

-- One item of each quality: 0 damage +1.5, 1 tears +0.4, 2 range +0.5,
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
    plan.check("the pedestal pickup raised tears by 0.4", function(player, ctx)
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
    plan.check("two quality 0 and one quality 3 item held before, and Underdog itself (quality 2): damage +3, luck -0.5, range +0.5",
        function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Damage, ctx.before.Damage + 2 * EXPECT[0].delta)
            and H.near(now.Luck, ctx.before.Luck + EXPECT[3].delta)
            and H.near(now.Range, ctx.before.Range + EXPECT[2].delta),
            string.format("damage %.3f -> %.3f luck %.3f -> %.3f range %.3f -> %.3f", ctx.before.Damage, now.Damage,
                ctx.before.Luck, now.Luck, ctx.before.Range, now.Range)
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
    plan.check("removing the quality 1 item takes its +0.4 tears", function(_, ctx)
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
    plan.check("a swap that keeps the item total is caught: damage -1.5, speed -0.1", function(player, ctx)
        local s = ctx.swapped
        return player:GetCollectibleCount() == ctx.total
            and H.near(s.Damage, ctx.after.Damage - EXPECT[0].delta)
            and H.near(s.Speed, ctx.after.Speed + EXPECT[4].delta),
            string.format("total %d -> %d; after [%s] swapped [%s]", ctx.total, player:GetCollectibleCount(),
                describeShare(ctx.after), describeShare(s))
    end)
end)

-- Only the quality counts (user decision 2026-11-20, "예외없이"): a quest item
-- and a second Underdog count like any other item (the second copy also doubles
-- every stat), and nothing counts while it is not held.
case("every_item", function(plan, id)
    requireModule(plan, { 0 })
    plan.act(function(player, ctx)
        give(player, id, 1)
        ctx.before = H.stats(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1, 0, true)
    end)
    plan.wait(2)
    plan.check("a quest item (Key Piece 1, quality 0) raises damage by 1.5", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Damage, ctx.before.Damage + EXPECT[0].delta),
            string.format("damage %.3f -> %.3f", ctx.before.Damage, now.Damage)
    end)
    plan.act(function(player, ctx)
        ctx.before = H.stats(player)
        player:AddCollectible(id, 0, true)
    end)
    plan.wait(2)
    -- one copy: Key Piece damage +1.5, Underdog range +0.5; two copies: each
    -- quality 0 item damage +3 and two quality 2 items (the copies) range +1 each
    plan.check("a second Underdog doubles damage (+1.5 -> +3) and range (+0.5 -> +2)", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Range, ctx.before.Range + 1.5) and H.near(now.Damage, ctx.before.Damage + EXPECT[0].delta),
            string.format("range %.3f -> %.3f damage %.3f -> %.3f", ctx.before.Range, now.Range,
                ctx.before.Damage, now.Damage)
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

-- Copies stack (user decision 2026-11-21): with n copies every stat is n
-- times one copy's. One item of quality 0, 1, 3 and 4 is held; the copies are
-- the quality 2 items, so range is 0.5 x n x n.
case("copies", function(plan, id)
    requireModule(plan, { 0, 1, 3, 4 })
    plan.act(function(player, ctx)
        give(player, id, 0)
        for _, q in ipairs({ 0, 1, 3, 4 }) do player:AddCollectible(fixture(q), 0, true) end
    end)
    plan.wait(2)
    plan.act(function(_, ctx) ctx.base = H.stats(_) end)
    local function expectCopies(n)
        plan.act(function(player) give(player, id, n) end)
        plan.wait(3)
        plan.check(string.format("%d cop%s: damage %+g, tears %+g, range %+g, luck %+g, speed %+g", n,
            n == 1 and "y" or "ies", n * EXPECT[0].delta, n * EXPECT[1].delta, n * n * EXPECT[2].delta,
            n * EXPECT[3].delta, n * EXPECT[4].delta), function(player, ctx)
            local now, b = H.stats(player), ctx.base
            return H.near(now.Damage, b.Damage + n * EXPECT[0].delta) and H.near(now.Tears, b.Tears + n * EXPECT[1].delta)
                and H.near(now.Range, b.Range + n * n * EXPECT[2].delta) and H.near(now.Luck, b.Luck + n * EXPECT[3].delta)
                and H.near(now.Speed, b.Speed + n * EXPECT[4].delta),
                string.format("damage %+.3f tears %+.3f range %+.3f luck %+.3f speed %+.3f", now.Damage - b.Damage,
                    now.Tears - b.Tears, now.Range - b.Range, now.Luck - b.Luck, now.Speed - b.Speed)
        end)
    end
    expectCopies(1)
    expectCopies(2)
    expectCopies(3)
    expectCopies(1)
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
    plan.check("damage +1.5 and luck -0.5 while held", function(player, ctx)
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

-- ------------------------------------------------------------------ item pools
-- Item pool draws weigh quality 0-4 by 5, 4, 3, 2, 1, raised to the power of
-- the copies held, while a living player holds Underdog (user decision
-- 2026-11-21). The same seeds are drawn from the real treasure pool without and
-- with Underdog, without taking anything out; each quality's share must move
-- from c_q to what those weights give (expectedShares). It also records whether
-- the engine runs MC_POST_GET_COLLECTIBLE on the item Underdog's
-- MC_PRE_GET_COLLECTIBLE answers (a measurement: other mods' POST callbacks see
-- Underdog's draws only if it does).
local POOL_SAMPLES = 1500
local postWatch = nil -- { counts = { [id] = n } } while a draw is watched
if ModCallbacks and ModCallbacks.MC_POST_GET_COLLECTIBLE then
    local priority = rawget(_G, "CallbackPriority")
    local first = type(priority) == "table" and tonumber(priority.IMPORTANT) or -200
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, first, function(_, selected)
        if postWatch then
            postWatch.counts[selected] = (postWatch.counts[selected] or 0) + 1
            postWatch.total = (postWatch.total or 0) + 1
        end
    end)
end

-- The treasure pool's weights by item (REPENTOGON), or nil without that API.
local function poolWeights()
    local itemPool = Game():GetItemPool()
    if type(itemPool.GetCollectiblesFromPool) ~= "function" then return nil end
    local weights, total = {}, 0
    for _, entry in ipairs(itemPool:GetCollectiblesFromPool(ItemPoolType.POOL_TREASURE)) do
        weights[entry.itemID] = (weights[entry.itemID] or 0) + (tonumber(entry.weight) or 0)
        total = total + (tonumber(entry.weight) or 0)
    end
    return weights, total
end

-- The items taken out of every pool (REPENTOGON), or nil without that API.
local function removedSet()
    local itemPool = Game():GetItemPool()
    if type(itemPool.GetRemovedCollectibles) ~= "function" then return nil end
    local ok, values = pcall(itemPool.GetRemovedCollectibles, itemPool)
    if not ok or type(values) ~= "table" then return nil end
    local set = {}
    for key, value in pairs(values) do
        local id = type(value) == "boolean" and tonumber(key) or type(value) == "number" and value or nil
        if id and value ~= false then set[id] = true end
    end
    return set
end

-- Draw every seed from a pool (the treasure pool unless named) without taking
-- anything out. Returns the share of quality 0-1 answers and what the answers
-- were: how many were hidden, already taken out of the pools, locked
-- (REPENTOGON's isUnlocked), or one given item (`watch`).
local function sample(seeds, watch, pool)
    pool = pool or ItemPoolType.POOL_TREASURE
    local itemPool, config = Game():GetItemPool(), Isaac.GetItemConfig()
    local removed, locked = removedSet(), {}
    if type(itemPool.GetCollectiblesFromPool) == "function" then
        for _, entry in ipairs(itemPool:GetCollectiblesFromPool(pool)) do
            if entry.isUnlocked == false then locked[entry.itemID] = true end
        end
    end
    local audit = { low = 0, hidden = 0, removed = 0, locked = 0, watched = 0, distinct = 0, removedKnown = removed ~= nil,
        hiddenIds = {}, removedIds = {}, quality = { 0, 0, 0, 0, 0 } }
    local seen = {}
    for _, seed in ipairs(seeds) do
        local got = itemPool:GetCollectible(pool, false, seed)
        local item = got > 0 and config:GetCollectible(got)
        if item and (item.Quality or 0) <= 1 then audit.low = audit.low + 1 end
        if item then
            local q = math.max(0, math.min(4, math.floor(item.Quality or 0))) + 1
            audit.quality[q] = audit.quality[q] + 1
        end
        if item and item.Hidden then audit.hidden = audit.hidden + 1; audit.hiddenIds[got] = true end
        if removed and removed[got] then audit.removed = audit.removed + 1; audit.removedIds[got] = true end
        if locked[got] then audit.locked = audit.locked + 1 end
        if watch and got == watch then audit.watched = audit.watched + 1 end
        if not seen[got] then seen[got], audit.distinct = 0, audit.distinct + 1 end
        seen[got] = seen[got] + 1
    end
    audit.counts = seen
    for q = 1, 5 do audit.quality[q] = audit.quality[q] / #seeds end
    return audit.low / #seeds, audit
end

-- Each quality's share with `copies` held, from the shares `c` without it
-- (other mods change draws in both arms, so the control stands for the pool):
-- k_q = (w_q / w_0)^n, a = sum c_q k_q, N the peek limit,
-- P_q = (c_q k_q / a)(1 - (1 - a)^N) + (1 - a)^(N - 1) c_q (1 - k_q).
local function expectedShares(c, copies)
    local pool = U().pool
    local limit, keep, a = pool.peeksPerCopy * copies, {}, 0
    for q = 1, 5 do keep[q] = (pool.weights[q] / pool.weights[1]) ^ copies; a = a + c[q] * keep[q] end
    local out = {}
    for q = 1, 5 do
        out[q] = a > 0 and ((c[q] * keep[q] / a) * (1 - (1 - a) ^ limit) + (1 - a) ^ (limit - 1) * c[q] * (1 - keep[q]))
            or c[q]
    end
    return out
end

-- Whether every quality's share is within its tolerance of the expected one.
local function sharesMatch(got, want, samples)
    local ok, parts = true, {}
    for q = 1, 5 do
        local tolerance = 0.02 + 4 * math.sqrt(want[q] * (1 - want[q]) / samples)
        if math.abs(got[q] - want[q]) > tolerance then ok = false end
        parts[q] = string.format("Q%d %.3f/%.3f", q - 1, got[q], want[q])
    end
    return ok, table.concat(parts, " ")
end

local function fmtShares(c)
    local parts = {}
    for q = 1, 5 do parts[q] = string.format("%.3f", c[q]) end
    return table.concat(parts, "/")
end

local function itemList(set)
    local config, names = Isaac.GetItemConfig(), {}
    for item in pairs(set) do
        local c = config:GetCollectible(item)
        names[#names + 1] = string.format("%d %s", item, c and tostring(c.Name) or "?")
    end
    table.sort(names)
    return table.concat(names, ", ")
end

local function describeAudit(audit)
    return string.format("%d distinct items; hidden %d [%s], already taken out %s [%s], locked %d", audit.distinct,
        audit.hidden, itemList(audit.hiddenIds), audit.removedKnown and tostring(audit.removed) or "unknown",
        itemList(audit.removedIds), audit.locked)
end

S.add("UNDERDOG", "pool_weight", { conditions = true }, function(plan, id)
    plan.require("Underdog's pool hook loaded", function()
        return (U() and U().pool and type(U().onPreGetCollectible) == "function") or nil, "module or pool hook missing"
    end)
    plan.act(function(player, ctx)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            local itemPool = Game():GetItemPool()
            local items = { ctx.taken or 0, ctx.frequent or 0 }
            for _, item in ipairs(ctx.nativeTaken or {}) do items[#items + 1] = item end
            for _, item in ipairs(items) do
                if item > 0 and type(itemPool.ResetCollectible) == "function" then
                    pcall(itemPool.ResetCollectible, itemPool, item)
                end
            end
        end)
        ctx.seeds = {}
        for i = 1, POOL_SAMPLES do ctx.seeds[i] = i * 7919 + 13 end
        give(player, id, 0)
        ctx.weights, ctx.total = poolWeights()
        postWatch = { counts = {} }
        ctx.control, ctx.controlAudit = sample(ctx.seeds)
        ctx.controlPosts = postWatch.total or 0
        give(player, id, 1)
        U()._test.resetEvidence()
        postWatch = { counts = {} }
        ctx.with, ctx.withAudit = sample(ctx.seeds)
        ctx.withPosts = postWatch.total or 0
        postWatch = nil
        ctx.evidence = U()._test.evidence()
        local _, total = poolWeights()
        ctx.totalAfterPeeks = total
        give(player, id, 2)
        U()._test.resetEvidence()
        local _, twoAudit = sample(ctx.seeds)
        ctx.twoAudit, ctx.twoEvidence = twoAudit, U()._test.evidence()
        give(player, id, 1)
    end)
    plan.check("the treasure pool weighs quality 0-4 by 5, 4, 3, 2, 1", function(_, ctx)
        local ok, detail = sharesMatch(ctx.withAudit.quality, expectedShares(ctx.controlAudit.quality, 1), POOL_SAMPLES)
        local e = ctx.evidence
        return ok, string.format("without %s; with/expected %s over %d draws; Underdog answered %d, peeks %d, fallbacks %d, left %d",
            fmtShares(ctx.controlAudit.quality), detail, POOL_SAMPLES, e.draws, e.peeks, e.fallbacks, e.left)
    end)
    plan.check("two copies weigh it by 25, 16, 9, 4, 1", function(_, ctx)
        local ok, detail = sharesMatch(ctx.twoAudit.quality, expectedShares(ctx.controlAudit.quality, 2), POOL_SAMPLES)
        local e = ctx.twoEvidence
        return ok, string.format("with/expected %s; Underdog answered %d, peeks %d, fallbacks %d, left %d", detail,
            e.draws, e.peeks, e.fallbacks, e.left)
    end)
    plan.check("draws that take nothing out leave the pool whole", function(_, ctx)
        if not ctx.total then return nil, "no REPENTOGON pool weights to read" end
        return ctx.total == ctx.totalAfterPeeks,
            string.format("treasure pool weight %s -> %s", tostring(ctx.total), tostring(ctx.totalAfterPeeks))
    end)
    -- Underdog only peeks through the engine's own draw, so it answers with what
    -- that draw allows. Other mods' callbacks still change draws in both arms:
    -- measured 2026-11-21, Astro Items lists hidden items in pools (Black Cube)
    -- and its MC_POST_GET_COLLECTIBLE upgrades hand out hidden items even after
    -- they were taken out (Marigold for Midas Touch), with and without Underdog.
    plan.note("MC_POST_GET_COLLECTIBLE calls over the same draws", function(_, ctx)
        local e = ctx.evidence
        return string.format("without Underdog %d for %d draws; with Underdog %d for %d draws, %d peeks", ctx.controlPosts,
            POOL_SAMPLES, ctx.withPosts, POOL_SAMPLES, e.peeks)
    end)
    plan.note("hidden, taken-out and locked answers in both arms", function(_, ctx)
        return "with Underdog: " .. describeAudit(ctx.withAudit) .. "; without: " .. describeAudit(ctx.controlAudit)
    end)
    plan.act(function(_, ctx)
        ctx.removedBefore = removedSet()
        ctx.weightsBefore = poolWeights()
        local drawsBefore = U()._test.evidence().draws
        postWatch = { counts = {} }
        ctx.taken = Game():GetItemPool():GetCollectible(ItemPoolType.POOL_TREASURE, true, 424242)
        ctx.posts = postWatch.counts[ctx.taken] or 0
        postWatch = nil
        ctx.answered = U()._test.evidence().draws - drawsBefore
        ctx.removedAfter = removedSet()
        ctx.weightsAfter = poolWeights()
    end)
    plan.note("MC_POST_GET_COLLECTIBLE after Underdog's MC_PRE_GET_COLLECTIBLE answer", function(_, ctx)
        local before = ctx.weightsBefore and ctx.weightsBefore[ctx.taken]
        local after = ctx.weightsAfter and ctx.weightsAfter[ctx.taken]
        return string.format("item %d (answered by Underdog: %s) seen %d time(s) by a POST observer; its pool weight %s -> %s",
            ctx.taken, tostring(ctx.answered == 1), ctx.posts, tostring(before), tostring(after))
    end)
    plan.check("a draw that takes its item out takes only that item", function(_, ctx)
        if not (ctx.removedBefore and ctx.removedAfter and ctx.weightsBefore and ctx.weightsAfter) then
            return nil, "no REPENTOGON pool state to read"
        end
        local others = {}
        for item in pairs(ctx.removedAfter) do
            if item ~= ctx.taken and not ctx.removedBefore[item] then others[#others + 1] = "removed " .. item end
        end
        for item, weight in pairs(ctx.weightsBefore) do
            if item ~= ctx.taken and ctx.weightsAfter[item] ~= weight then others[#others + 1] = "weight " .. item end
        end
        return ctx.answered == 1 and ctx.removedAfter[ctx.taken] == true and #others == 0,
            string.format("item %d answered by Underdog %d time(s), removed %s; other changes [%s]", ctx.taken,
                ctx.answered, tostring(ctx.removedAfter[ctx.taken] == true), table.concat(others, ","))
    end)
    -- An item that already appeared is out of the pools however it was taken
    -- out: the one Underdog answered above, whatever a native draw takes out here
    -- (another mod may swap what that draw returns, so the pool's own removed
    -- list says what it took), and the item Underdog answered most often,
    -- taken out with the engine's RemoveCollectible.
    plan.act(function(player, ctx)
        local itemPool = Game():GetItemPool()
        give(player, id, 0)
        local removedBefore = removedSet() or {}
        ctx.nativeReturned = itemPool:GetCollectible(ItemPoolType.POOL_TREASURE, true, 515151)
        ctx.nativeTaken = {}
        for item in pairs(removedSet() or {}) do
            if not removedBefore[item] then ctx.nativeTaken[#ctx.nativeTaken + 1] = item end
        end
        local best, bestCount = nil, 0
        for item, count in pairs(ctx.withAudit.counts) do
            local config = Isaac.GetItemConfig():GetCollectible(item)
            if count > bestCount and item ~= ctx.taken and config and not config.Hidden then best, bestCount = item, count end
        end
        ctx.frequent = best
        if best then itemPool:RemoveCollectible(best) end
        give(player, id, 1)
        local _, audit = sample(ctx.seeds)
        ctx.afterAudit = audit
    end)
    plan.check("items that already appeared never come up again", function(_, ctx)
        if not removedSet() then return nil, "no REPENTOGON removed-item list to read" end
        local before, after = ctx.withAudit.counts, ctx.afterAudit.counts
        local ok, parts = ctx.frequent ~= nil and #ctx.nativeTaken > 0, {}
        local function report(label, item)
            parts[#parts + 1] = string.format("%s %d: %d -> %d", label, item, before[item] or 0, after[item] or 0)
            if (after[item] or 0) > 0 then ok = false end
        end
        report("Underdog's answer", ctx.taken)
        for _, item in ipairs(ctx.nativeTaken) do report("taken out by a native draw (returned " .. ctx.nativeReturned .. ")", item) end
        if ctx.frequent then report("most frequent answer, taken out", ctx.frequent) end
        return ok, string.format("%s of %d draws; %s", table.concat(parts, "; "), POOL_SAMPLES, describeAudit(ctx.afterAudit))
    end)
    plan.act(function(player, ctx)
        local pearl = ConchBlessing.ItemData.CONCH_PEARL and ConchBlessing.ItemData.CONCH_PEARL.id
        ctx.pearl = pearl
        if not (pearl and pearl > 0) then return end
        player:AddCollectible(pearl, 0, false)
        local before = U()._test.evidence().draws
        for i = 1, 20 do Game():GetItemPool():GetCollectible(ItemPoolType.POOL_TREASURE, false, 7770 + i) end
        ctx.pearlDraws = U()._test.evidence().draws - before
        player:RemoveCollectible(pearl)
        give(player, id, 0)
    end)
    plan.check("with Conch Pearl held, Underdog leaves the draw alone", function(_, ctx)
        if not (ctx.pearl and ctx.pearl > 0) then return nil, "Conch Pearl not registered" end
        return ctx.pearlDraws == 0, string.format("Underdog answered %d of 20 draws", ctx.pearlDraws)
    end)
end)

-- Every item pool, not only the treasure pool (by name only: about 30 pools).
-- The same seeds are drawn from each pool without Underdog, with one copy and
-- with two, without taking anything out; each quality's share must be what the
-- weights give within the peek limit (expectedShares), taking the shares
-- without it as the pool's because other mods change draws in every arm.
local ALL_POOL_SAMPLES = 2000

local function poolName(pool)
    for name, value in pairs(type(ItemPoolType) == "table" and ItemPoolType or {}) do
        if value == pool and name ~= "NUM_ITEMPOOLS" then return name end
    end
    return "pool " .. pool
end

S.add("UNDERDOG", "all_pools", { conditions = true }, function(plan, id)
    plan.require("Underdog's pool hook loaded", function()
        return (U() and U().pool and type(U().onPreGetCollectible) == "function") or nil, "module or pool hook missing"
    end)
    plan.act(function(_, ctx)
        ctx.seeds = {}
        for i = 1, ALL_POOL_SAMPLES do ctx.seeds[i] = i * 7919 + 13 end
        ctx.rows = {}
    end)
    local count = type(ItemPoolType) == "table" and tonumber(ItemPoolType.NUM_ITEMPOOLS) or 31
    for pool = 0, count - 1 do
        plan.act(function(player, ctx)
            give(player, id, 0)
            local _, controlAudit = sample(ctx.seeds, nil, pool)
            local row = { control = controlAudit.quality, distinct = controlAudit.distinct, arms = {} }
            for copies = 1, 2 do
                give(player, id, copies)
                U()._test.resetEvidence()
                local _, audit = sample(ctx.seeds, nil, pool)
                local e = U()._test.evidence()
                row.arms[copies] = { shares = audit.quality, distinct = audit.distinct, draws = e.draws,
                    peeks = e.peeks, fallbacks = e.fallbacks, left = e.left }
            end
            give(player, id, 0)
            ctx.rows[pool] = row
        end)
        plan.check(poolName(pool) .. ": quality 0-4 weighed by 5-1, and by their squares with two copies", function(_, ctx)
            local row, ok, parts = ctx.rows[pool], true, {}
            for copies = 1, 2 do
                local arm = row.arms[copies]
                local match, detail = sharesMatch(arm.shares, expectedShares(row.control, copies), ALL_POOL_SAMPLES)
                ok = ok and match
                parts[#parts + 1] = string.format("x%d: %s; %d distinct, answered %d, peeks %.2f a draw, fallbacks %d, left %d",
                    copies, detail, arm.distinct, arm.draws, arm.draws > 0 and arm.peeks / arm.draws or 0,
                    arm.fallbacks, arm.left)
            end
            return ok, string.format("without %s (%d distinct) | %s", fmtShares(row.control), row.distinct,
                table.concat(parts, " | "))
        end)
        plan.wait(1)
    end
end)
S.rows[#S.rows].manual = true

-- Binge Eater with and without Underdog (a measurement, by name only): the
-- same seeded pedestals are made while holding Binge Eater, first without
-- Underdog and then with it, and the food choice Binge Eater adds to each is
-- compared seed by seed. It also counts the item pool draws the engine makes
-- through MC_PRE_GET_COLLECTIBLE outside Underdog's own peeks, which shows
-- whether Binge Eater's food is drawn from a pool at all.
local BINGE_PEDESTALS = 24
local bingeWatch = nil -- { calls, decreasing, pools } while one arm's pedestals are made
if ModCallbacks and ModCallbacks.MC_PRE_GET_COLLECTIBLE then
    local priority = rawget(_G, "CallbackPriority")
    local first = type(priority) == "table" and tonumber(priority.IMPORTANT) or -200
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, first, function(_, pool, decrease)
        if not bingeWatch or (U() and U()._test and U()._test.peeking()) then return end
        bingeWatch.calls = bingeWatch.calls + 1
        if decrease then bingeWatch.decreasing = bingeWatch.decreasing + 1 end
        bingeWatch.pools[pool] = (bingeWatch.pools[pool] or 0) + 1
    end)
end

local function describeItem(item)
    local config = Isaac.GetItemConfig():GetCollectible(item)
    local food = config and ItemConfig.TAG_FOOD and config:HasTags(ItemConfig.TAG_FOOD)
    return string.format("%d(Q%s%s)", item, config and tostring(config.Quality) or "?", food and ",food" or "")
end

local function listItems(list)
    local out = {}
    for _, item in ipairs(list) do out[#out + 1] = describeItem(item) end
    return #out > 0 and table.concat(out, " ") or "-"
end

local function poolCounts(pools)
    local out = {}
    for pool, n in pairs(pools) do out[#out + 1] = string.format("pool %d x%d", pool, n) end
    table.sort(out)
    return #out > 0 and table.concat(out, ", ") or "none"
end

S.add("UNDERDOG", "binge_eater", { conditions = true }, function(plan, id)
    local BINGE = CollectibleType.COLLECTIBLE_BINGE_EATER
    plan.require("Underdog's pool hook and REPENTOGON's pedestal cycle", function()
        local probe = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
            CollectibleType.COLLECTIBLE_SAD_ONION, Vector(-1000, -1000), Vector.Zero, nil):ToPickup()
        local cycle = type(probe.GetCollectibleCycle) == "function"
        probe:Remove()
        return (U() and U()._test and type(U()._test.peeking) == "function" and cycle) or nil,
            "module or GetCollectibleCycle missing"
    end)
    local function arm(label, copies)
        plan.act(function(player, ctx)
            ctx.cleanupFns = ctx.cleanupFns or {}
            if not ctx.bingeCleanup then
                ctx.bingeCleanup = true
                table.insert(ctx.cleanupFns, function()
                    bingeWatch = nil
                    for _, key in ipairs({ "without", "with" }) do
                        for _, pedestal in ipairs(ctx[key] and ctx[key].pedestals or {}) do
                            if pedestal:Exists() then pedestal:Remove() end
                        end
                    end
                end)
            end
            give(player, id, copies)
            if player:GetCollectibleNum(BINGE) == 0 then player:AddCollectible(BINGE, 0, false) end
            local room = Game():GetRoom()
            local data = { pedestals = {}, removedBefore = removedSet() or {} }
            ctx[label] = data
            U()._test.resetEvidence()
            bingeWatch = { calls = 0, decreasing = 0, pools = {} }
            for i = 1, BINGE_PEDESTALS do
                local spot = room:GetCenterPos() + Vector(((i - 1) % 6 - 2.5) * 60, (math.floor((i - 1) / 6) - 1.5) * 60 + 30)
                local seed = 100003 * i + 7
                local entity = Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, spot, Vector.Zero,
                    nil, 0, seed)
                local pedestal = entity:ToPickup()
                data.pedestals[i] = pedestal
                local queued = {}
                for _, item in ipairs(pedestal:GetCollectibleCycle() or {}) do queued[#queued + 1] = item end
                data.atSpawn = data.atSpawn or {}
                data.atSpawn[i] = { main = pedestal.SubType, cycle = queued }
            end
            data.spawnCalls = bingeWatch.calls
        end)
        plan.wait(15)
        plan.act(function(_, ctx)
            local data = ctx[label]
            data.calls, data.decreasing, data.pools = bingeWatch.calls, bingeWatch.decreasing, bingeWatch.pools
            bingeWatch = nil
            local e = U()._test.evidence()
            data.evidence = { draws = e.draws, peeks = e.peeks }
            data.rows = {}
            for i, pedestal in ipairs(data.pedestals) do
                local cycle = {}
                if pedestal:Exists() then
                    for _, item in ipairs(pedestal:GetCollectibleCycle() or {}) do cycle[#cycle + 1] = item end
                end
                data.rows[i] = { main = pedestal:Exists() and pedestal.SubType or 0, cycle = cycle }
            end
            local itemPool = Game():GetItemPool()
            data.taken = {}
            for item in pairs(removedSet() or {}) do
                if not data.removedBefore[item] then data.taken[#data.taken + 1] = item end
            end
            for _, pedestal in ipairs(data.pedestals) do if pedestal:Exists() then pedestal:Remove() end end
            for _, item in ipairs(data.taken) do pcall(itemPool.ResetCollectible, itemPool, item) end
        end)
        plan.wait(2)
    end
    arm("without", 0)
    arm("with", 1)
    -- Which items Binge Eater leaves without food, without Underdog: each item a
    -- pedestal of the "with" arm showed, put on a fixed pedestal (subtype set,
    -- no pool draw) at that pedestal's own seed and at another seed.
    plan.act(function(player, ctx)
        give(player, id, 0)
        local room = Game():GetRoom()
        ctx.fixed = {}
        -- Mystery Egg got no food on one Underdog run (2026-11-22): checked on its own.
        local items = {}
        for i = 1, #ctx.with.rows do items[i] = ctx.with.atSpawn[i].main end
        items[#items + 1] = CollectibleType.COLLECTIBLE_MYSTERY_EGG
        for i, item in ipairs(items) do
            local seeds = { 100003 * i + 7, 7777 * i + 3 }
            if i == #items then seeds = { 600025, 100003 * i + 7, 7777 * i + 3 } end -- 600025: that run's pedestal 6
            for k, seed in ipairs(seeds) do
                local spot = room:GetCenterPos() + Vector(((i - 1) % 6 - 2.5) * 60, (k - 1.5) * 90 + 40)
                local pedestal = Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, spot, Vector.Zero,
                    nil, item, seed):ToPickup()
                local queued = {}
                for _, choice in ipairs(pedestal:GetCollectibleCycle() or {}) do queued[#queued + 1] = choice end
                ctx.fixed[#ctx.fixed + 1] = { item = item, seed = seed, food = #queued > 0 and table.concat(queued, ",") or "none" }
                pedestal:Remove()
            end
        end
    end)
    plan.note("Binge Eater's food on fixed pedestals without Underdog", function(_, ctx)
        local out = {}
        for _, row in ipairs(ctx.fixed) do out[#out + 1] = string.format("%s@%d->%s", describeItem(row.item), row.seed, row.food) end
        return table.concat(out, " ")
    end)
    plan.note("item pool draws outside Underdog's peeks", function(_, ctx)
        local a, b = ctx.without, ctx.with
        return string.format("without Underdog %d (%d while spawning, %d decreasing; %s); with Underdog %d (%d while spawning, %d decreasing; %s), Underdog answered %d with %d peeks; %d pedestals each",
            a.calls, a.spawnCalls, a.decreasing, poolCounts(a.pools), b.calls, b.spawnCalls, b.decreasing, poolCounts(b.pools),
            b.evidence.draws, b.evidence.peeks, BINGE_PEDESTALS)
    end)
    plan.note("items taken out of the pools", function(_, ctx)
        return "without: " .. listItems(ctx.without.taken) .. " | with: " .. listItems(ctx.with.taken)
    end)
    for i = 1, BINGE_PEDESTALS do
        plan.note(string.format("pedestal %d", i), function(_, ctx)
            local a, b = ctx.without.rows[i], ctx.with.rows[i]
            return string.format("without: %s + choices %s | with: %s + choices %s", describeItem(a.main), listItems(a.cycle),
                describeItem(b.main), listItems(b.cycle))
        end)
    end
    -- Binge Eater's choice is the one not drawn from the pool (a pool draw takes
    -- its item out; the food is never taken out, see the DIAG above).
    local function foodOf(data, row)
        local taken = {}
        for _, item in ipairs(data.taken) do taken[item] = true end
        local foods = {}
        for _, item in ipairs({ row.main, table.unpack(row.cycle) }) do
            if not taken[item] then foods[#foods + 1] = item end
        end
        return table.concat(foods, ",")
    end
    plan.note("first choice shown right after spawning", function(_, ctx)
        local out = {}
        for i = 1, BINGE_PEDESTALS do
            local a, b = ctx.without.atSpawn[i], ctx.with.atSpawn[i]
            out[#out + 1] = string.format("%d: %d+[%s] / %d+[%s]", i, a.main, table.concat(a.cycle, ","), b.main,
                table.concat(b.cycle, ","))
        end
        return "without / with: " .. table.concat(out, "; ")
    end)
    plan.check("Binge Eater adds the same food to each seeded pedestal with and without Underdog", function(_, ctx)
        local same, differ, missing = 0, {}, 0
        for i = 1, BINGE_PEDESTALS do
            local a, b = foodOf(ctx.without, ctx.without.rows[i]), foodOf(ctx.with, ctx.with.rows[i])
            if a == "" or b == "" then missing = missing + 1
            elseif a == b then same = same + 1
            else differ[#differ + 1] = string.format("%d:%s/%s", i, a, b) end
        end
        return missing == 0 and #differ == 0, string.format("%d same, %d differ [%s], %d without a food choice", same,
            #differ, table.concat(differ, " "), missing)
    end)
end)
S.rows[#S.rows].manual = true

-- Every case only adds and removes items through the engine's own inventory
-- and reads stat changes, so they share one run: S.resetPlayer takes every
-- item away again and proves the stats are back where the run started.
S.sequenceBundle("UNDERDOG", "shared", { conditions = true }, shared, function(plan) S.resetPlayer(plan) end)

return C
