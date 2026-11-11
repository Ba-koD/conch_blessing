local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 소라 증명서 (Conch Certificate) benches. Everything goes through the real
-- item use, the real Death Certificate and real room transitions; the checks
-- read the live pedestals, the player's inventory and the floor record.
--   lifecycle      held copies open nothing on their own
--   rooms          every Death Certificate room: the catalog in order from the
--                  first pedestal, nothing else left, and the engine's own item
--                  order measured from what it had put on each pedestal
--   take_reuse     taking the first item goes home with it; a second use
--                  shows the rest again without it
--   inside_blocked using it inside the area is refused
--   dc_order       (measurement, by name only) vanilla Death Certificate alone:
--                  the item IDs the engine puts on every pedestal, room by room
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local DCRooms = require("scripts.rooms.death_certificate_gallery_rooms")
local C = {}
local KEY = "CONCH_CERTIFICATE"
local DC = 2

local uses = 0
if ModCallbacks and type(ModCallbacks.MC_USE_ITEM) == "number" then
    ConchBlessing:AddCallback(ModCallbacks.MC_USE_ITEM, function(_, id)
        local row = ConchBlessing.ItemData[KEY]
        if row and id == row.id then uses = uses + 1 end
    end)
end

local function cert() return assert(ConchBlessing.conchCertificate, "Conch Certificate module not loaded") end
local function ledger() return cert()._test.ledger() end
local function dimension() return Game():GetLevel():GetDimension() end
local function idle() return RoomTransition.GetTransitionMode() == 0 end
local function listIndex() return Game():GetLevel():GetCurrentRoomDesc().ListIndex end

local function inRoom(manifest)
    return dimension() == DC and idle() and listIndex() == manifest.listIndex
end

local function goTo(player, manifest)
    Game():StartRoomTransition(manifest.safeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, DC)
end

-- Pickups of one variant on each grid index of the current room.
local function pickupsByGrid(variant)
    local room, byGrid = Game():GetRoom(), {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, variant, -1, false, false)) do
        local pickup = entity:ToPickup()
        if pickup and pickup:Exists() then
            local index = room:GetGridIndex(pickup.Position)
            byGrid[index] = byGrid[index] or {}
            table.insert(byGrid[index], pickup)
        end
    end
    return byGrid
end

local function slotGrid(manifest, slot)
    local position = manifest.pedestalPositions[slot]
    return position.x + position.y * Game():GetRoom():GetGridWidth()
end

local function capabilities(plan)
    plan.require("REPENTOGON dimensions, room list and transition mode", function()
        local level = Game():GetLevel()
        return (type(level.GetDimension) == "function" and type(level.GetRooms) == "function"
            and type(RoomTransition) == "table" and type(RoomTransition.GetTransitionMode) == "function") or nil,
            "REPENTOGON required"
    end)
end

-- Give the certificate, use it for real and wait in the entrance.
local function enter(plan, id, label)
    plan.require("Conch Certificate resolved", function()
        return type(id) == "number" and id > 0 or nil, "full game restart needed after items.xml changes"
    end)
    plan.act(function(player, ctx)
        ctx.originListIndex, ctx.originDimension = listIndex(), dimension()
        if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) ~= id then
            player:AddCollectible(id, 0, false, ActiveSlot.SLOT_PRIMARY)
        end
        ctx.usesBefore = uses
        H.use(player, id)
    end)
    plan.waitUntil(function(_, ctx)
        local record = ledger()
        return dimension() == DC and idle() and record ~= nil and record.graph ~= nil or false,
            string.format("dimension %d, uses %d", dimension(), uses - (ctx.usesBefore or 0))
    end, 400, label or "arrival in the Death Certificate entrance")
    plan.wait(6)
end

local function stockRooms(record)
    local list = {}
    for _, manifest in ipairs(record.graph.rooms) do
        if manifest.kind == "stock" then list[#list + 1] = manifest end
    end
    return list
end

-- Walk into every listed room once, in order, calling visit(manifest, ctx) in
-- each after it has settled.
local function walk(plan, list, visit, label)
    plan.act(function(_, ctx) ctx.walk = { list = list(ctx), index = 0, settled = 0 } end)
    plan.waitUntil(function(player, ctx)
        local walking = ctx.walk
        local target = walking.list[walking.index]
        if target then
            if not inRoom(target) then return false, "walking to room " .. tostring(target.listIndex) end
            walking.settled = walking.settled + 1
            if walking.settled < 6 then return false, "settling" end
            visit(target, ctx)
        end
        walking.index, walking.settled = walking.index + 1, 0
        local nextRoom = walking.list[walking.index]
        if not nextRoom then return true, #walking.list .. " rooms" end
        if not inRoom(nextRoom) then goTo(player, nextRoom) end
        return false, "leaving for room " .. tostring(nextRoom.listIndex)
    end, 120 * 60, label)
end

C[KEY] = { stage = function(plan, id, n)
    if n == 0 then
        plan.check("no certificate remains in either active slot", function(player)
            return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) ~= id
                and player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) ~= id, "removed from active slots"
        end)
        return
    end
    plan.check("holding it opens nothing until it is used", function()
        local record = ledger()
        return dimension() == 0 and (record == nil or record.visiting ~= true),
            "dimension " .. dimension() .. ", visiting " .. tostring(record and record.visiting)
    end)
end }

S.add(KEY, "rooms", {}, function(plan, id)
    capabilities(plan)
    enter(plan, id)
    plan.check("catalog: our collectibles by ID (console items and WIP previews in, the certificate out), then our trinkets", function()
        local record, items = ledger(), ConchBlessing.ItemData
        local collectibles, trinkets = {}, {}
        for key, row in pairs(items) do
            if type(row) == "table" and row.type and key ~= KEY and type(row.id) == "number" and row.id > 0 then
                local list = row.type == "trinket" and trinkets or collectibles
                list[#list + 1] = row.id
            end
        end
        table.sort(collectibles); table.sort(trinkets)
        local want = {}
        for _, value in ipairs(collectibles) do want[#want + 1] = "c" .. value end
        for _, value in ipairs(trinkets) do want[#want + 1] = "t" .. value end
        local got = {}
        for _, entry in ipairs(record.catalog) do got[#got + 1] = (entry.kind == "trinket" and "t" or "c") .. entry.id end
        return table.concat(got, ",") == table.concat(want, ","),
            string.format("%d collectibles + %d trinkets; got %s", #collectibles, #trinkets, table.concat(got, ","))
    end)
    plan.check("the entrance stays the engine's: no pedestal added", function()
        local count = 0
        for _ in pairs(pickupsByGrid(PickupVariant.PICKUP_COLLECTIBLE)) do count = count + 1 end
        return count == 0, count .. " collectible spots in the entrance"
    end)
    walk(plan, function() return stockRooms(ledger()) end, function(manifest, ctx)
        local record = ledger()
        local collectibles = pickupsByGrid(PickupVariant.PICKUP_COLLECTIBLE)
        local trinkets = pickupsByGrid(PickupVariant.PICKUP_TRINKET)
        local problems, expectedSpots = {}, {}
        for slot = 1, manifest.capacity do
            local grid = slotGrid(manifest, slot)
            local entry = cert().entryFor(record.catalog, manifest, slot)
            local here = collectibles[grid] or {}
            if entry and entry.kind == "collectible" then
                expectedSpots[grid] = true
                if #here ~= 1 or here[1].SubType ~= entry.id then
                    problems[#problems + 1] = string.format("slot %d wants c%d, has %s", slot, entry.id,
                        here[1] and ("c" .. here[1].SubType) or "nothing")
                end
            elseif entry then
                local trinket = (trinkets[grid] or {})[1]
                if #here > 0 or not trinket or trinket.SubType ~= entry.id then
                    problems[#problems + 1] = string.format("slot %d wants t%d, has %s", slot, entry.id,
                        trinket and ("t" .. trinket.SubType) or (#here > 0 and "a pedestal" or "nothing"))
                end
            elseif #here > 0 then
                problems[#problems + 1] = string.format("slot %d past the catalog still has c%d", slot, here[1].SubType)
            end
        end
        for grid, list in pairs(collectibles) do
            if not expectedSpots[grid] then
                problems[#problems + 1] = "stray collectible c" .. list[1].SubType .. " at grid " .. grid
            end
        end
        ctx.roomProblems = ctx.roomProblems or {}
        ctx.roomCount = (ctx.roomCount or 0) + 1
        for _, line in ipairs(problems) do
            ctx.roomProblems[#ctx.roomProblems + 1] = "room " .. manifest.listIndex .. ": " .. line
        end
    end, "every Death Certificate room")
    plan.check("every room: catalog items on their slots in order, nothing past the catalog, no stray pedestal", function(_, ctx)
        local problems = ctx.roomProblems or {}
        return #problems == 0 and (ctx.roomCount or 0) > 0,
            (ctx.roomCount or 0) .. " rooms; " .. (#problems == 0 and "clean" or table.concat(problems, "; ", 1, math.min(#problems, 6)))
    end)
    -- The order oracle: what the engine had put on each pedestal, in the layout
    -- order the certificate fills (rooms by ListIndex, slots by spawn order).
    plan.act(function(_, ctx)
        local record = ledger()
        local catalogIds, restIds, sequence, missing = {}, {}, {}, 0
        for _, manifest in ipairs(stockRooms(record)) do
            local state = record.rooms[manifest.key]
            for slot = 1, manifest.capacity do
                local original = state and state.original and state.original[slot] or 0
                if original == 0 then missing = missing + 1 else sequence[#sequence + 1] = original end
                local list = slot <= manifest.slotCount and catalogIds or restIds
                if original ~= 0 then list[#list + 1] = original end
            end
        end
        ctx.order = { catalog = catalogIds, rest = restIds, sequence = sequence, missing = missing }
    end)
    plan.note("engine items per room (ListIndex: first..last)", function()
        local record, parts = ledger(), {}
        for _, manifest in ipairs(stockRooms(record)) do
            local state = record.rooms[manifest.key]
            local low, high
            for slot = 1, manifest.capacity do
                local value = state and state.original[slot] or 0
                if value > 0 then
                    low = low and math.min(low, value) or value
                    high = high and math.max(high, value) or value
                end
            end
            parts[#parts + 1] = string.format("%d:%s..%s", manifest.listIndex, tostring(low), tostring(high))
        end
        return table.concat(parts, " ")
    end)
    plan.check("the engine had an item on every catalog pedestal", function(_, ctx)
        local record, empty = ledger(), 0
        for _, manifest in ipairs(stockRooms(record)) do
            for slot = 1, manifest.slotCount do
                if (record.rooms[manifest.key].original[slot] or 0) == 0 then empty = empty + 1 end
            end
        end
        return empty == 0, empty .. " empty catalog pedestals"
    end)
    plan.check("engine item IDs rise along the layout order the certificate fills", function(_, ctx)
        local sequence = ctx.order.sequence
        for index = 2, #sequence do
            if sequence[index] <= sequence[index - 1] then
                return false, string.format("pedestal %d holds %d after %d", index, sequence[index], sequence[index - 1])
            end
        end
        return #sequence > 0, #sequence .. " engine pedestals in order"
    end)
    plan.check("our items took the pedestals of the engine's lowest IDs", function(_, ctx)
        local highest, lowestRest = 0, math.huge
        for _, value in ipairs(ctx.order.catalog) do highest = math.max(highest, value) end
        for _, value in ipairs(ctx.order.rest) do lowestRest = math.min(lowestRest, value) end
        return #ctx.order.catalog > 0 and highest < lowestRest,
            string.format("catalog pedestals had up to %d, the rest from %s", highest, tostring(lowestRest))
    end)
end)

S.add(KEY, "take_reuse", {}, function(plan, id)
    capabilities(plan)
    enter(plan, id)
    plan.act(function(player, ctx)
        local record = ledger()
        ctx.first, ctx.second = record.catalog[1], record.catalog[2]
        for _, manifest in ipairs(stockRooms(record)) do
            if manifest.catalogStart == 1 and manifest.slotCount >= 2 then ctx.firstRoom = manifest end
        end
        assert(ctx.first and ctx.first.kind == "collectible" and ctx.firstRoom, "no first catalog room")
        goTo(player, ctx.firstRoom)
    end)
    plan.waitUntil(function(_, ctx) return inRoom(ctx.firstRoom) end, 300, "the first catalog room")
    plan.wait(10)
    plan.act(function(player, ctx)
        local here = pickupsByGrid(PickupVariant.PICKUP_COLLECTIBLE)[slotGrid(ctx.firstRoom, 1)]
        local pickup = assert(here and here[1], "first catalog pedestal missing")
        assert(pickup.SubType == ctx.first.id, "first pedestal holds " .. pickup.SubType)
        ctx.heldBefore = player:GetCollectibleNum(ctx.first.id, true)
        pickup.Wait = 0
        player.Position = pickup.Position
        player.Velocity = Vector.Zero
    end)
    plan.waitUntil(function(_, ctx)
        ctx.quiet = (dimension() ~= DC and idle()) and (ctx.quiet or 0) + 1 or 0
        return ctx.quiet >= 20, "dimension " .. dimension()
    end, 900, "Death Certificate takes Isaac home")
    plan.check("Isaac came home with the first catalog item", function(player, ctx)
        local count = player:GetCollectibleNum(ctx.first.id, true)
        return count == ctx.heldBefore + 1 and dimension() == ctx.originDimension and listIndex() == ctx.originListIndex,
            string.format("c%d x%d, room %d (used in %d)", ctx.first.id, count, listIndex(), ctx.originListIndex)
    end)
    plan.check("the floor record ended the visit and noted the item as taken", function(_, ctx)
        local record = ledger()
        return record.visiting == false and record.taken["c" .. ctx.first.id] == true,
            "visiting " .. tostring(record.visiting)
    end)
    enter(plan, id, "second use: back in the entrance")
    plan.act(function(player, ctx) goTo(player, ctx.firstRoom) end)
    plan.waitUntil(function(_, ctx) return inRoom(ctx.firstRoom) end, 300, "the first catalog room again")
    plan.wait(10)
    plan.check("the taken item stays gone and the next one is still on its pedestal", function(_, ctx)
        local collectibles = pickupsByGrid(PickupVariant.PICKUP_COLLECTIBLE)
        local first = collectibles[slotGrid(ctx.firstRoom, 1)]
        local second = collectibles[slotGrid(ctx.firstRoom, 2)]
        local wantSecond = ctx.second.kind == "collectible" and ctx.second.id or nil
        return first == nil and second ~= nil and second[1].SubType == wantSecond,
            string.format("slot 1 %s, slot 2 %s (want c%s)", first and ("c" .. first[1].SubType) or "empty",
                second and ("c" .. second[1].SubType) or "empty", tostring(wantSecond))
    end)
end)

S.add(KEY, "inside_blocked", {}, function(plan, id)
    capabilities(plan)
    enter(plan, id)
    plan.act(function(player, ctx)
        ctx.room, ctx.usesInside = listIndex(), uses
        H.use(player, id)
    end)
    plan.wait(15)
    plan.check("a use inside the area is refused before it is accepted", function(_, ctx)
        return uses == ctx.usesInside and dimension() == DC and idle() and listIndex() == ctx.room,
            string.format("accepted uses %d, room %d", uses - ctx.usesInside, listIndex())
    end)
    plan.check("the visit stays open", function() return ledger().visiting == true, "visiting" end)
end)

-- Vanilla Death Certificate alone: which item the engine puts on every
-- pedestal, in descriptor ListIndex and layout spawn order (DIAG), and whether
-- that order rises with the item ID.
S.add(KEY, "dc_order", {}, function(plan)
    capabilities(plan)
    plan.act(function(player)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, -1)
    end)
    plan.waitUntil(function() return dimension() == DC and idle() end, 400, "Death Certificate entry")
    plan.wait(6)
    plan.act(function(_, ctx)
        local ok, graph, reason = pcall(DCRooms.capture, {}, 1)
        assert(ok and graph, "capture failed: " .. tostring(reason or graph))
        ctx.graph, ctx.rows = graph, {}
    end)
    walk(plan, function(ctx) return stockRooms(ctx) end, function(manifest, ctx)
        local collectibles, ids = pickupsByGrid(PickupVariant.PICKUP_COLLECTIBLE), {}
        for slot = 1, manifest.capacity do
            local here = collectibles[slotGrid(manifest, slot)]
            ids[slot] = here and here[1].SubType or 0
        end
        ctx.rows[#ctx.rows + 1] = { listIndex = manifest.listIndex, grid = manifest.gridIndex, ids = ids }
    end, "every Death Certificate room")
    for index = 1, 40 do
        plan.note("room #" .. index, function(_, ctx)
            local row = ctx.rows[index]
            return row and string.format("ListIndex %d grid %d: %s", row.listIndex, row.grid, table.concat(row.ids, ",")) or "-"
        end)
    end
    plan.check("engine item IDs rise along ListIndex and spawn order", function(_, ctx)
        local previous, count = 0, 0
        for _, row in ipairs(ctx.rows) do
            for slot, value in ipairs(row.ids) do
                if value > 0 then
                    if value <= previous then
                        return false, string.format("ListIndex %d slot %d holds %d after %d", row.listIndex, slot, value, previous)
                    end
                    previous, count = value, count + 1
                end
            end
        end
        return count > 0, count .. " pedestals in order"
    end)
end)
S.rows[#S.rows].manual = true

return C
