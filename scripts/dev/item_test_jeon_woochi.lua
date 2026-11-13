local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 전우치 (Jeon Woo-chi): the lifecycle contract and its cases. Every check
-- reads the real engine: the player's transformation counters, the pedestals
-- really standing in the room, the item pools' removal list and the arrival
-- effects. The user's design (2026-11-13): on pickup, among the unfinished
-- transformations collected the most toward, one at random, as many of its
-- items as it still needs; each copy on its own.
local S = require("scripts.dev.item_scenarios")
local Forms = require("scripts.lib.player_forms")
local C = {}

local function jwc() return ConchBlessing.jeonwoochi end

-- Collectible pedestals standing in the room, by pointer.
local function pedestals()
    local list = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1)) do
        local pickup = entity:ToPickup()
        if pickup and pickup.SubType > 0 then list[GetPtrHash(pickup)] = pickup end
    end
    return list
end

local function arrivals()
    local v = jwc()._test.variant()
    return v > 0 and #Isaac.FindByType(EntityType.ENTITY_EFFECT, v) or 0
end

local function pendingCount()
    local n = 0
    for _ in pairs(jwc().pending()) do n = n + 1 end
    return n
end

-- The pedestals that appeared since `before`.
local function newPedestals(before)
    local list = {}
    for hash, pickup in pairs(pedestals()) do
        if not before[hash] then list[#list + 1] = pickup end
    end
    table.sort(list, function(a, b) return a.SubType < b.SubType end)
    return list
end

-- The transformations an item counts toward, by name.
local function formsOf(id)
    local config, names = Isaac.GetItemConfig():GetCollectible(id), {}
    for _, f in ipairs(Forms.list()) do
        if config and config:HasTags(f.tag) then names[#names + 1] = f.key end
    end
    return names
end

-- Whether a pickup fills a set: a tagged transformation by its tag, a
-- special one by its pieces (a pill by this run's effect for its color).
local function fills(set, pickup, player)
    if set.tag then
        local config = Isaac.GetItemConfig():GetCollectible(pickup.SubType)
        return pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and config ~= nil and config:HasTags(set.tag)
    end
    for _, piece in ipairs(set.supplies) do
        if piece.kind == "pill" and pickup.Variant == PickupVariant.PICKUP_PILL
            and Game():GetItemPool():GetPillEffect(pickup.SubType, player) == piece.id then
            return true
        end
        if piece.kind == "trinket" and pickup.Variant == PickupVariant.PICKUP_TRINKET and pickup.SubType == piece.id then
            return true
        end
        if piece.kind == "collectible" and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and pickup.SubType == piece.id then
            return true
        end
    end
    return false
end

-- Every pickup (collectible, trinket or pill) that appeared since `before`.
local function newPickups(before)
    local list = {}
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, -1, -1)) do
        local p = e:ToPickup()
        if p and not before[GetPtrHash(p)] and (p.Variant == PickupVariant.PICKUP_COLLECTIBLE
            or p.Variant == PickupVariant.PICKUP_TRINKET or p.Variant == PickupVariant.PICKUP_PILL) then
            list[#list + 1] = p
        end
    end
    return list
end

local function describe(list)
    local parts = {}
    for _, p in ipairs(list) do
        parts[#parts + 1] = string.format("%d[%s]", p.SubType, table.concat(formsOf(p.SubType), "/"))
    end
    return table.concat(parts, " ")
end

local function counter(player, name) return player:GetPlayerFormCounter(PlayerForm["PLAYERFORM_" .. name]) end

local function requireModule(plan)
    plan.require("전우치 module, its effect and REPENTOGON's form counter", function(player)
        local m = jwc()
        return m and m._test and m._test.itemId() > 0 and m._test.variant() > 0 and m._test.capable(player) or false,
            "module, effect variant or GetPlayerFormCounter missing"
    end)
end

-- Remembers the pickups standing before a theft.
local function mark(plan)
    plan.act(function(_, ctx)
        ctx.before = {}
        for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, -1, -1)) do ctx.before[GetPtrHash(e)] = true end
    end)
end

-- Waits until every arrival has finished and placed its pedestal.
local function settled(plan, label)
    plan.waitUntil(function()
        return arrivals() == 0 and pendingCount() == 0, string.format("arrivals %d, waiting %d", arrivals(), pendingCount())
    end, 240, label or "every arrival has placed its pedestal")
end

-- Gives items as real first pickups, so they count toward their sets.
local function collect(player, ids)
    for _, id in ipairs(ids) do player:AddCollectible(id, 0, true) end
end

local function stealsFrom(plan, label, sets, count)
    plan.check(label, function(_, ctx)
        local list = newPedestals(ctx.before)
        if #list ~= count then return false, string.format("%d new pedestals, expected %d: %s", #list, count, describe(list)) end
        local wanted = {}
        for _, name in ipairs(sets) do wanted[name] = true end
        local shared
        for _, p in ipairs(list) do
            local ok = false
            for _, name in ipairs(formsOf(p.SubType)) do
                if wanted[name] then ok = true; shared = shared or name end
            end
            if not ok then return false, "not an item of " .. table.concat(sets, "/") .. ": " .. describe(list) end
        end
        return true, describe(list)
    end)
end

local function offPlayerAndApart(plan)
    plan.check("each pedestal stands off the player and apart from the others", function(player, ctx)
        local list = newPedestals(ctx.before)
        for i, a in ipairs(list) do
            if a.Position:Distance(player.Position) < jwc().data.nearest - 1 then
                return false, string.format("%d is %.0f from the player", a.SubType, a.Position:Distance(player.Position))
            end
            for j = i + 1, #list do
                if a.Position:Distance(list[j].Position) < jwc().data.gap - 1 then
                    return false, string.format("%d and %d are %.0f apart", a.SubType, list[j].SubType,
                        a.Position:Distance(list[j].Position))
                end
            end
        end
        return true, #list .. " pedestals"
    end)
end

-- The lifecycle: every copy gained (the first, the stacked one and the
-- reacquired one) steals, for a fresh Isaac whose counters are all 0, as many
-- items of one transformation as its threshold; losing copies steals nothing.
C.JEON_WOOCHI = { prepare = function(plan)
    requireModule(plan)
    mark(plan)
end, beforeChange = function(_, ctx)
    ctx.before = {}
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, -1, -1)) do ctx.before[GetPtrHash(e)] = true end
end, stage = function(plan, _, n, index)
    settled(plan)
    if index == 1 or index == 2 or index == 5 then
        plan.check("a copy picked up steals a whole set's worth of one set", function(player, ctx)
            local list = newPickups(ctx.before)
            local sets = {}
            for _, f in ipairs(Forms.list()) do sets[#sets + 1] = f end
            for _, f in ipairs(Forms.special()) do sets[#sets + 1] = f end
            local parts = {}
            for _, p in ipairs(list) do parts[#parts + 1] = p.Variant .. "." .. p.SubType end
            for _, set in ipairs(sets) do
                local all = #list == Forms.threshold(set)
                for _, p in ipairs(list) do all = all and fills(set, p, player) end
                if all then return true, set.key .. ": " .. table.concat(parts, " ") end
            end
            return false, #list .. " new pickups, no one set at its threshold: " .. table.concat(parts, " ")
        end)
        offPlayerAndApart(plan)
    else
        plan.check("losing a copy steals nothing", function(_, ctx)
            local list = newPedestals(ctx.before)
            return #list == 0 and arrivals() == 0, #list .. " new pedestals, " .. arrivals() .. " arrivals"
        end)
    end
end, permanent = false }

-- Guppy 2 and Bob 1: one Guppy item, which completes Guppy when taken.
S.add("JEON_WOOCHI", "closest", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        collect(player, { CollectibleType.COLLECTIBLE_GUPPYS_PAW, CollectibleType.COLLECTIBLE_GUPPYS_TAIL,
            CollectibleType.COLLECTIBLE_BOBS_CURSE })
    end)
    plan.wait(4)
    plan.require("Guppy 2 and Bob 1 counted by the engine", function(player)
        return counter(player, "GUPPY") == 2 and counter(player, "BOB") == 1,
            string.format("guppy %d bob %d", counter(player, "GUPPY"), counter(player, "BOB"))
    end)
    mark(plan)
    plan.act(function(player) player:AddCollectible(id, 0, true) end)
    settled(plan)
    stealsFrom(plan, "one item, of the set he is closest to (Guppy)", { "GUPPY" }, 1)
    offPlayerAndApart(plan)
    plan.act(function(player, ctx)
        local p = newPedestals(ctx.before)[1]
        ctx.stolen = p and p.SubType
        -- it may be a second copy of an item he holds: count the copies
        ctx.copies = ctx.stolen and player:GetCollectibleNum(ctx.stolen, true) or 0
        if p then player.Position = p.Position end
    end)
    -- a held active of the same kind swaps on the pedestal; that pickup
    -- counts too (measured 2026-11-13, `held_active`), after Isaac holds it up
    plan.waitUntil(function(player, ctx)
        return ctx.stolen ~= nil and player:HasPlayerForm(PlayerForm.PLAYERFORM_GUPPY), "not taken yet"
    end, 150, "Isaac takes the stolen item")
    plan.check("taking it completes the transformation", function(player, ctx)
        return player:HasPlayerForm(PlayerForm.PLAYERFORM_GUPPY), string.format("took %d (%s copy), guppy counter %d",
            ctx.stolen, ctx.copies > 0 and "a second" or "a first", counter(player, "GUPPY"))
    end)
end)

-- Guppy 2 and Bob 2: one item of either.
S.add("JEON_WOOCHI", "tie", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        collect(player, { CollectibleType.COLLECTIBLE_GUPPYS_PAW, CollectibleType.COLLECTIBLE_GUPPYS_TAIL,
            CollectibleType.COLLECTIBLE_BOBS_CURSE, CollectibleType.COLLECTIBLE_IPECAC })
    end)
    plan.wait(4)
    plan.require("Guppy 2 and Bob 2 counted by the engine", function(player)
        return counter(player, "GUPPY") == 2 and counter(player, "BOB") == 2,
            string.format("guppy %d bob %d", counter(player, "GUPPY"), counter(player, "BOB"))
    end)
    mark(plan)
    plan.act(function(player) player:AddCollectible(id, 0, true) end)
    settled(plan)
    stealsFrom(plan, "one item, of either set tied closest", { "GUPPY", "BOB" }, 1)
end)

-- Guppy 1: two copies picked up in the same update steal two items each, on
-- their own (each at random, so they may repeat one another).
S.add("JEON_WOOCHI", "same_update", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player) collect(player, { CollectibleType.COLLECTIBLE_GUPPYS_PAW }) end)
    plan.wait(4)
    plan.require("Guppy 1 counted by the engine", function(player)
        return counter(player, "GUPPY") == 1, "guppy " .. counter(player, "GUPPY")
    end)
    mark(plan)
    plan.act(function(player)
        player:AddCollectible(id, 0, true)
        player:AddCollectible(id, 0, true)
    end)
    settled(plan)
    stealsFrom(plan, "two copies steal two Guppy items each", { "GUPPY" }, 4)
    offPlayerAndApart(plan)
end)

-- The show: the pedestal stands only after the smoke has risen.
S.add("JEON_WOOCHI", "presentation", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player) collect(player, { CollectibleType.COLLECTIBLE_GUPPYS_PAW, CollectibleType.COLLECTIBLE_GUPPYS_TAIL }) end)
    plan.wait(4)
    mark(plan)
    plan.act(function(player) player:AddCollectible(id, 0, true) end)
    plan.wait(20)
    plan.check("while he casts, he is there and the pedestal is not", function(_, ctx)
        return arrivals() == 1 and #newPedestals(ctx.before) == 0 and pendingCount() == 1,
            string.format("arrivals %d, new pedestals %d, waiting %d", arrivals(), #newPedestals(ctx.before), pendingCount())
    end)
    settled(plan)
    plan.check("after the smoke the pedestal stands and he is gone", function(_, ctx)
        return #newPedestals(ctx.before) == 1 and arrivals() == 0, describe(newPedestals(ctx.before))
    end)
end)

-- Leaving the room during the show: the item stands there on the way back.
S.add("JEON_WOOCHI", "leave", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player) collect(player, { CollectibleType.COLLECTIBLE_GUPPYS_PAW, CollectibleType.COLLECTIBLE_GUPPYS_TAIL }) end)
    plan.wait(4)
    plan.require("a neighbouring room to step into", function(_, ctx)
        local room, level = Game():GetRoom(), Game():GetLevel()
        ctx.home = level:GetCurrentRoomIndex()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomIndex and door.TargetRoomIndex >= 0 then
                ctx.away = door.TargetRoomIndex
                return true, "room " .. ctx.away
            end
        end
        return false, "no door"
    end)
    mark(plan)
    plan.act(function(player) player:AddCollectible(id, 0, true) end)
    plan.wait(5)
    plan.act(function(_, ctx)
        local rec
        for _, r in pairs(jwc().pending()) do rec = r end
        ctx.rec = rec and { id = rec.id, x = rec.x, y = rec.y }
        Game():ChangeRoom(ctx.away)
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomIndex() == ctx.away, "not there yet"
    end, 60, "into the next room")
    plan.wait(4)
    plan.act(function(_, ctx) Game():ChangeRoom(ctx.home) end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomIndex() == ctx.home, "not back yet"
    end, 60, "back into the room")
    plan.wait(6)
    plan.check("the theft was still on its way when Isaac left", function(_, ctx)
        if not ctx.rec then return false, "no record was waiting" end
        return true, string.format("item %d waiting at (%.0f, %.0f)", ctx.rec.id, ctx.rec.x, ctx.rec.y)
    end)
    plan.check("on the way back its pedestal stands where he was to place it", function(_, ctx)
        for _, p in ipairs(newPedestals(ctx.before)) do
            if ctx.rec and p.SubType == ctx.rec.id and p.Position:Distance(Vector(ctx.rec.x, ctx.rec.y)) < 2 then
                return pendingCount() == 0 and arrivals() == 0, "waiting " .. pendingCount()
            end
        end
        return false, "found " .. describe(newPedestals(ctx.before))
    end)
end)

-- A copy that comes back to the inventory (AddCollectible without a first
-- pickup, as Kronos hands items back) steals nothing.
S.add("JEON_WOOCHI", "returned_copy", {}, function(plan, id)
    requireModule(plan)
    mark(plan)
    plan.act(function(player) player:AddCollectible(id, 0, false) end)
    plan.wait(60)
    plan.check("nothing is stolen", function(_, ctx)
        return arrivals() == 0 and #newPedestals(ctx.before) == 0, describe(newPedestals(ctx.before))
    end)
end)

-- Every set already complete, the special ones too: nothing is stolen.
S.add("JEON_WOOCHI", "complete", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        for _, f in ipairs(Forms.list()) do
            local missing = Forms.threshold(f) - player:GetPlayerFormCounter(f.form)
            if missing > 0 then player:IncrementPlayerFormCounter(f.form, missing) end
        end
        for _, set in ipairs(Forms.special()) do
            if set.held then
                for _, piece in ipairs(set.supplies) do player:AddCollectible(piece.id, 0, true) end
            else
                local missing = Forms.threshold(set) - player:GetPlayerFormCounter(set.form)
                if missing > 0 then player:IncrementPlayerFormCounter(set.form, missing) end
            end
        end
    end)
    plan.wait(10)
    plan.require("every set complete", function(player)
        for _, f in ipairs(Forms.list()) do
            if not player:HasPlayerForm(f.form) then return false, f.key .. " not complete" end
        end
        for _, set in ipairs(Forms.special()) do
            if set.form and not player:HasPlayerForm(set.form) then return false, set.key .. " not complete" end
        end
        return true, (#Forms.list() + #Forms.special()) .. " complete"
    end)
    mark(plan)
    plan.act(function(player) player:AddCollectible(id, 0, true) end)
    plan.wait(60)
    plan.check("nothing is stolen", function(_, ctx)
        return arrivals() == 0 and #newPickups(ctx.before) == 0, #newPickups(ctx.before) .. " new pickups"
    end)
end)

-- The thresholds he counts by: for every transformation he knows, the
-- engine's counter is raised one at a time, and the value at which the
-- engine completes it must be Forms.threshold. playerforms.xml names no such
-- number and REPENTOGON exposes none, so this is where it is measured.
S.add("JEON_WOOCHI", "thresholds", {}, function(plan)
    requireModule(plan)
    plan.note("transformations he knows (playerforms data)", function()
        local parts = {}
        for _, f in ipairs(Forms.list()) do parts[#parts + 1] = f.form .. ":" .. f.key end
        return #parts .. " [" .. table.concat(parts, " ") .. "] from " .. (XMLData and "XMLData" or "the vanilla table")
    end)
    for _, f in ipairs(Forms.list()) do
        plan.act(function(player, ctx)
            ctx.flip = nil
            ctx.start = player:GetPlayerFormCounter(f.form)
        end)
        for _ = 1, Forms.threshold(f) + 2 do
            plan.act(function(player, ctx)
                if not ctx.flip and not player:HasPlayerForm(f.form) then player:IncrementPlayerFormCounter(f.form, 1) end
            end)
            plan.wait(2)
            plan.act(function(player, ctx)
                if not ctx.flip and player:HasPlayerForm(f.form) then ctx.flip = player:GetPlayerFormCounter(f.form) end
            end)
        end
        plan.check(f.key .. " completes at its threshold", function(_, ctx)
            return ctx.flip == Forms.threshold(f), string.format("completed at %s (started at %d), threshold %d",
                tostring(ctx.flip), ctx.start, Forms.threshold(f))
        end)
    end
end)

-- Three 전우치 for a fresh Isaac's three missing items: they arrive in turn
-- and vanish together, so every pedestal stands on the same update.
S.add("JEON_WOOCHI", "together", {}, function(plan, id)
    requireModule(plan)
    mark(plan)
    plan.act(function(player, ctx)
        ctx.appeared = {}
        ctx.tick = 0
        player:AddCollectible(id, 0, true)
    end)
    plan.wait(5)
    plan.check("they arrive in turn: one casting, the others still to come", function()
        local v, steal, waiting = jwc()._test.variant(), 0, 0
        for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, v)) do
            local anim = e:GetSprite():GetAnimation()
            if anim == "Steal" then steal = steal + 1 elseif anim == "Wait" then waiting = waiting + 1 end
        end
        return steal == 1 and waiting == 2, string.format("casting %d, to come %d", steal, waiting)
    end)
    plan.waitUntil(function(_, ctx)
        ctx.tick = ctx.tick + 1
        for _, p in ipairs(newPickups(ctx.before)) do
            local hash = GetPtrHash(p)
            if not ctx.appeared[hash] then ctx.appeared[hash] = ctx.tick end
        end
        return arrivals() == 0 and pendingCount() == 0, string.format("arrivals %d", arrivals())
    end, 300, "every arrival has placed its pedestal")
    plan.check("the three vanish together: every pedestal stands on the same update", function(_, ctx)
        local ticks = {}
        for _, t in pairs(ctx.appeared) do ticks[#ticks + 1] = t end
        table.sort(ticks)
        return #ticks == 3 and ticks[1] == ticks[3], "appeared on updates " .. table.concat(ticks, ",")
    end)
end)

-- ------------------------------------------------------- the special sets
-- Forms.SPECIAL is written from the wiki, because neither the engine nor
-- playerforms.xml describes these sets; these cases measure each rule in the
-- engine and then let 전우치 fill a set one piece short.

local function special(key)
    for _, set in ipairs(Forms.special()) do
        if set.key == key then return set end
    end
    return nil
end

-- The color this run gives a pill effect; a fixture may add it to the run's
-- pills with REPENTOGON's ForceAddPillEffect.
local function pillColor(player, effect, force)
    local pool = Game():GetItemPool()
    for color = 1, 13 do
        if pool:GetPillEffect(color, player) == effect then return color end
    end
    if force and type(pool.ForceAddPillEffect) == "function" then return pool:ForceAddPillEffect(effect) end
    return nil
end

local function usePill(player, effect)
    player:UsePill(effect, pillColor(player, effect, true) or PillColor.PILL_BLUE_BLUE, 0)
end

local function superBums()
    local v = FamiliarVariant and FamiliarVariant.SUPER_BUM
    return v and #Isaac.FindByType(EntityType.ENTITY_FAMILIAR, v) or 0
end

-- The engine's own counting of every special set, the rules the table states.
S.add("JEON_WOOCHI", "special_counters", {}, function(plan)
    requireModule(plan)
    -- Adult: three Puberty pills
    for k = 1, 3 do
        plan.act(function(player) usePill(player, PillEffect.PILLEFFECT_PUBERTY) end)
        plan.wait(4)
        plan.check("Adult: Puberty pill " .. k .. " counts", function(player)
            local c = player:GetPlayerFormCounter(PlayerForm.PLAYERFORM_ADULTHOOD)
            return c == k and player:HasPlayerForm(PlayerForm.PLAYERFORM_ADULTHOOD) == (k >= 3),
                string.format("counter %d, adult %s", c, tostring(player:HasPlayerForm(PlayerForm.PLAYERFORM_ADULTHOOD)))
        end)
    end
    -- Stompy: Leo, the One Makes You Larger pill and Magic Mushroom, one each
    local stompy = {
        { "Leo", function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_LEO, 0, true) end },
        { "One Makes You Larger", function(player) usePill(player, PillEffect.PILLEFFECT_LARGER) end },
        { "Magic Mushroom", function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM, 0, true) end },
    }
    for k, step in ipairs(stompy) do
        plan.act(function(player) step[2](player) end)
        plan.wait(4)
        plan.check("Stompy: " .. step[1] .. " counts", function(player)
            local c = player:GetPlayerFormCounter(PlayerForm.PLAYERFORM_STOMPY)
            return c == k and player:HasPlayerForm(PlayerForm.PLAYERFORM_STOMPY) == (k >= 3),
                string.format("counter %d, stompy %s", c, tostring(player:HasPlayerForm(PlayerForm.PLAYERFORM_STOMPY)))
        end)
    end
    -- Super Bum: the three bums held at once
    plan.act(function(player)
        for _, id in ipairs({ CollectibleType.COLLECTIBLE_BUM_FRIEND, CollectibleType.COLLECTIBLE_DARK_BUM,
            CollectibleType.COLLECTIBLE_KEY_BUM }) do
            player:AddCollectible(id, 0, true)
        end
    end)
    plan.wait(10)
    plan.check("Super Bum: the three bums held fuse", function() return superBums() == 1, "super bums " .. superBums() end)
    -- Necromancer (Repentance+): one of each piece, a second copy not counted
    plan.note("playerforms data", function()
        local xml, node = XMLData, XMLNode and XMLNode.PLAYERFORM
        if not (xml and node) then return "no XMLData" end
        local parts = {}
        for order = 1, xml.GetNumEntries(node) do
            local e = xml.GetEntryByOrder(node, order)
            parts[#parts + 1] = tostring(e and e.id) .. ":" .. tostring(e and e.name)
        end
        return table.concat(parts, " ")
    end)
    if not special("NECROMANCER") then
        plan.check("Necromancer (Repentance+)", function()
            return nil, "this game's playerforms data has no Necromancer: left out"
        end)
        return
    end
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_NECRONOMICON, 0, true) end)
    plan.wait(4)
    plan.act(function(player, ctx)
        ctx.necro = player:GetPlayerFormCounter(special("NECROMANCER").form)
        player:AddCollectible(CollectibleType.COLLECTIBLE_NECRONOMICON, 0, true, ActiveSlot.SLOT_SECONDARY)
    end)
    plan.wait(4)
    plan.check("Necromancer: a second Necronomicon does not count", function(player, ctx)
        local c = player:GetPlayerFormCounter(special("NECROMANCER").form)
        return ctx.necro == 1 and c == 1, string.format("after the first %d, after the second %d", ctx.necro, c)
    end)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_MISSING_PAGE_2, 0, true) end)
    plan.wait(4)
    plan.act(function(player)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, TrinketType.TRINKET_MISSING_PAGE,
            player.Position, Vector.Zero, nil)
    end)
    plan.waitUntil(function(player) return player:HasTrinket(TrinketType.TRINKET_MISSING_PAGE), "not picked up" end,
        90, "Isaac picks up A Missing Page")
    plan.wait(4)
    plan.check("Necromancer: A Missing Page completes it", function(player)
        local form = special("NECROMANCER").form
        return player:HasPlayerForm(form), "counter " .. player:GetPlayerFormCounter(form)
    end)
end)

-- Each special set one piece short: he places the piece that completes it.
local function shortCase(name, label, setKey, setup, check, take, done)
    S.add("JEON_WOOCHI", name, {}, function(plan, id)
        requireModule(plan)
        if not special(setKey) then
            plan.check(setKey, function() return nil, "this game has no " .. setKey .. ": left out" end)
            return
        end
        plan.act(function(player, ctx) setup(player, ctx) end)
        plan.wait(6)
        mark(plan)
        plan.act(function(player) player:AddCollectible(id, 0, true) end)
        settled(plan)
        plan.check(label, function(player, ctx)
            local list = newPickups(ctx.before)
            if #list ~= 1 then return false, #list .. " new pickups" end
            ctx.stolen = list[1]
            return check(player, list[1])
        end)
        plan.act(function(player, ctx) if ctx.stolen then take(player, ctx.stolen, ctx) end end)
        -- a collectible joins the inventory after Isaac holds it up
        plan.waitUntil(function(player) return done(player) end, 150, "the set completes")
        plan.check("taking it completes " .. setKey, function(player) return done(player) end)
    end)
end

local function walkOnto(player, pickup) player.Position = pickup.Position end

shortCase("special_super_bum", "the missing bum: Key Bum", "SUPER_BUM", function(player)
    player:AddCollectible(CollectibleType.COLLECTIBLE_BUM_FRIEND, 0, true)
    player:AddCollectible(CollectibleType.COLLECTIBLE_DARK_BUM, 0, true)
end, function(_, p)
    return p.Variant == PickupVariant.PICKUP_COLLECTIBLE and p.SubType == CollectibleType.COLLECTIBLE_KEY_BUM,
        p.Variant .. "." .. p.SubType
end, walkOnto, function() return superBums() == 1, "super bums " .. superBums() end)

shortCase("special_necromancer", "the missing piece: A Missing Page", "NECROMANCER", function(player)
    player:AddCollectible(CollectibleType.COLLECTIBLE_NECRONOMICON, 0, true)
    player:AddCollectible(CollectibleType.COLLECTIBLE_MISSING_PAGE_2, 0, true)
end, function(_, p)
    return p.Variant == PickupVariant.PICKUP_TRINKET and p.SubType == TrinketType.TRINKET_MISSING_PAGE,
        p.Variant .. "." .. p.SubType
end, walkOnto, function(player)
    local form = special("NECROMANCER").form
    return player:HasPlayerForm(form), "counter " .. player:GetPlayerFormCounter(form)
end)

shortCase("special_adult", "a pill of this run's Puberty color", "ADULTHOOD", function(player)
    usePill(player, PillEffect.PILLEFFECT_PUBERTY)
    usePill(player, PillEffect.PILLEFFECT_PUBERTY)
end, function(player, p)
    local effect = Game():GetItemPool():GetPillEffect(p.SubType, player)
    return p.Variant == PickupVariant.PICKUP_PILL and effect == PillEffect.PILLEFFECT_PUBERTY,
        string.format("%d.%d, effect %d", p.Variant, p.SubType, effect)
end, function(player, p)
    -- the pill's own effect, as if he swallowed it
    player:UsePill(Game():GetItemPool():GetPillEffect(p.SubType, player), p.SubType, 0)
    p:Remove()
end, function(player)
    return player:HasPlayerForm(PlayerForm.PLAYERFORM_ADULTHOOD),
        "counter " .. player:GetPlayerFormCounter(PlayerForm.PLAYERFORM_ADULTHOOD)
end)

shortCase("special_stompy", "Leo, Magic Mushroom or the One Makes You Larger pill", "STOMPY", function(player)
    player:AddCollectible(CollectibleType.COLLECTIBLE_LEO, 0, true)
    usePill(player, PillEffect.PILLEFFECT_LARGER)
end, function(player, p)
    if p.Variant == PickupVariant.PICKUP_PILL then
        local effect = Game():GetItemPool():GetPillEffect(p.SubType, player)
        return effect == PillEffect.PILLEFFECT_LARGER, "pill effect " .. effect
    end
    return p.Variant == PickupVariant.PICKUP_COLLECTIBLE and (p.SubType == CollectibleType.COLLECTIBLE_LEO
        or p.SubType == CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM), p.Variant .. "." .. p.SubType
end, function(player, p)
    if p.Variant == PickupVariant.PICKUP_PILL then
        player:UsePill(Game():GetItemPool():GetPillEffect(p.SubType, player), p.SubType, 0)
        p:Remove()
    else
        walkOnto(player, p)
    end
end, function(player)
    return player:HasPlayerForm(PlayerForm.PLAYERFORM_STOMPY),
        "counter " .. player:GetPlayerFormCounter(PlayerForm.PLAYERFORM_STOMPY)
end)

-- Measurement by name only: the sounds the game plays when Isaac himself
-- teleports (Teleport!, Teleport 2.0 and the Telepills pill), for 전우치's
-- landing cue (user request 2026-11-13: a teleport sound, not Holy Card).
local heard = nil

if type(ModCallbacks.MC_PRE_SFX_PLAY) == "number" then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_SFX_PLAY, function(_, id, volume, _, _, pitch)
        if heard then heard[#heard + 1] = { id = id, volume = volume, pitch = pitch, tick = heard.tick } end
    end)
end

local function soundName(id)
    for name, value in pairs(SoundEffect) do
        if value == id then return name end
    end
    return "?"
end

S.add("JEON_WOOCHI", "teleport_sound", {}, function(plan)
    plan.require("the sound hook (REPENTOGON MC_PRE_SFX_PLAY)", function()
        return type(ModCallbacks.MC_PRE_SFX_PLAY) == "number", "missing"
    end)
    local ways = {
        { "Teleport!", function(player)
            player:UseActiveItem(CollectibleType.COLLECTIBLE_TELEPORT, UseFlag.USE_OWNED, ActiveSlot.SLOT_PRIMARY)
        end },
        { "Teleport 2.0", function(player)
            player:UseActiveItem(CollectibleType.COLLECTIBLE_TELEPORT_2, UseFlag.USE_OWNED, ActiveSlot.SLOT_PRIMARY)
        end },
        { "Telepills", function(player) player:UsePill(PillEffect.PILLEFFECT_TELEPILLS, PillColor.PILL_BLUE_BLUE, 0) end },
    }
    for _, way in ipairs(ways) do
        plan.act(function(player, ctx)
            heard = { tick = 0 }
            ctx.cleanupFns = ctx.cleanupFns or {}
            table.insert(ctx.cleanupFns, function() heard = nil end)
            way[2](player)
        end)
        for _ = 1, 45 do
            plan.act(function() if heard then heard.tick = heard.tick + 1 end end)
            plan.wait(1)
        end
        plan.note(way[1] .. ": sounds played", function()
            local parts = {}
            for _, s in ipairs(heard or {}) do
                parts[#parts + 1] = string.format("+%d %d %s vol=%.2f pitch=%.2f", s.tick, s.id, soundName(s.id),
                    s.volume or -1, s.pitch or -1)
            end
            heard = nil
            return #parts > 0 and table.concat(parts, "; ") or "none"
        end)
    end
end)
S.rows[#S.rows].manual = true

-- Measurement by name only: Guppy 2 from Guppy's Paw (an active, held) and
-- Guppy's Tail; a second Guppy's Paw on a pedestal is walked onto, which swaps
-- the actives. Does that pickup count toward Guppy?
S.add("JEON_WOOCHI", "held_active", {}, function(plan)
    plan.act(function(player)
        player:AddCollectible(CollectibleType.COLLECTIBLE_GUPPYS_PAW, 0, true)
        player:AddCollectible(CollectibleType.COLLECTIBLE_GUPPYS_TAIL, 0, true)
    end)
    plan.wait(6)
    plan.note("before the swap", function(player)
        return "guppy counter " .. player:GetPlayerFormCounter(PlayerForm.PLAYERFORM_GUPPY)
    end)
    plan.act(function(player, ctx)
        ctx.pedestal = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
            CollectibleType.COLLECTIBLE_GUPPYS_PAW, Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(80, 0)),
            Vector.Zero, nil)
    end)
    plan.wait(10)
    plan.act(function(player, ctx) player.Position = ctx.pedestal.Position end)
    for k = 1, 4 do
        plan.wait(15)
        plan.note("after the swap +" .. (15 * k), function(player)
            return string.format("guppy counter %d, guppy %s, paws held %d",
                player:GetPlayerFormCounter(PlayerForm.PLAYERFORM_GUPPY),
                tostring(player:HasPlayerForm(PlayerForm.PLAYERFORM_GUPPY)),
                player:GetCollectibleNum(CollectibleType.COLLECTIBLE_GUPPYS_PAW, true))
        end)
    end
    plan.act(function(player) player.Position = Game():GetRoom():GetCenterPos() end)
end)
S.rows[#S.rows].manual = true

return C
