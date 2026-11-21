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
    plan.check("two quality 0 and one quality 3 item held before, and Underdog itself (quality 2): damage +2, luck -0.5, range +0.5",
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

-- Only the quality counts (user decision 2026-11-20, "예외없이"): a quest item
-- and a second Underdog count like any other item, and nothing counts while
-- it is not held.
case("every_item", function(plan, id)
    requireModule(plan, { 0 })
    plan.act(function(player, ctx)
        give(player, id, 1)
        ctx.before = H.stats(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1, 0, true)
    end)
    plan.wait(2)
    plan.check("a quest item (Key Piece 1, quality 0) raises damage by 1", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Damage, ctx.before.Damage + EXPECT[0].delta),
            string.format("damage %.3f -> %.3f", ctx.before.Damage, now.Damage)
    end)
    plan.act(function(player, ctx)
        ctx.before = H.stats(player)
        player:AddCollectible(id, 0, true)
    end)
    plan.wait(2)
    plan.check("a second Underdog (quality 2) raises range by 0.5", function(player, ctx)
        local now = H.stats(player)
        return H.near(now.Range, ctx.before.Range + EXPECT[2].delta) and H.near(now.Damage, ctx.before.Damage),
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

-- ------------------------------------------------------------------ item pools
-- Quality 0-1 items are lowWeight (3) times as likely in item pool draws while a
-- living player holds Underdog (user decision 2026-11-21). The same seeds are
-- drawn from the real treasure pool without and with Underdog, without taking
-- anything out; the share of quality 0-1 answers must move from p to
-- 3p / (3p + 1 - p). It also records whether the engine runs MC_POST_GET_COLLECTIBLE
-- on the item Underdog's MC_PRE_GET_COLLECTIBLE answers (a measurement: other
-- mods' POST callbacks see Underdog's draws only if it does).
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

-- Draw every seed from the treasure pool without taking anything out. Returns
-- the share of quality 0-1 answers and what the answers were: how many were
-- hidden, already taken out of the pools, locked (REPENTOGON's isUnlocked), or
-- one given item (`watch`).
local function sample(seeds, watch)
    local itemPool, config = Game():GetItemPool(), Isaac.GetItemConfig()
    local removed, locked = removedSet(), {}
    if type(itemPool.GetCollectiblesFromPool) == "function" then
        for _, entry in ipairs(itemPool:GetCollectiblesFromPool(ItemPoolType.POOL_TREASURE)) do
            if entry.isUnlocked == false then locked[entry.itemID] = true end
        end
    end
    local audit = { low = 0, hidden = 0, removed = 0, locked = 0, watched = 0, distinct = 0, removedKnown = removed ~= nil,
        hiddenIds = {}, removedIds = {} }
    local seen = {}
    for _, seed in ipairs(seeds) do
        local got = itemPool:GetCollectible(ItemPoolType.POOL_TREASURE, false, seed)
        local item = got > 0 and config:GetCollectible(got)
        if item and (item.Quality or 0) <= 1 then audit.low = audit.low + 1 end
        if item and item.Hidden then audit.hidden = audit.hidden + 1; audit.hiddenIds[got] = true end
        if removed and removed[got] then audit.removed = audit.removed + 1; audit.removedIds[got] = true end
        if locked[got] then audit.locked = audit.locked + 1 end
        if watch and got == watch then audit.watched = audit.watched + 1 end
        if not seen[got] then seen[got], audit.distinct = 0, audit.distinct + 1 end
        seen[got] = seen[got] + 1
    end
    audit.counts = seen
    return audit.low / #seeds, audit
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
    end)
    plan.check("quality 0-1 items are 3 times as likely in the treasure pool", function(_, ctx)
        local k = U().pool.lowWeight
        local expected = k * ctx.control / (k * ctx.control + 1 - ctx.control)
        local e = ctx.evidence
        return ctx.control > 0 and math.abs(ctx.with - expected) <= 0.05,
            string.format("quality 0-1 share %.3f without, %.3f with (expected %.3f over %d draws); Underdog answered %d, peeks %d, fallbacks %d, left %d",
                ctx.control, ctx.with, expected, POOL_SAMPLES, e.draws, e.peeks, e.fallbacks, e.left)
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

-- Every case only adds and removes items through the engine's own inventory
-- and reads stat changes, so they share one run: S.resetPlayer takes every
-- item away again and proves the stats are back where the run started.
S.sequenceBundle("UNDERDOG", "shared", { conditions = true }, shared, function(plan) S.resetPlayer(plan) end)

return C
