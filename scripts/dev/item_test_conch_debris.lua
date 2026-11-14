local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 소라 잔해 (Conch Debris): the lifecycle contract and its cases. Answers are
-- real Magic Conch answers (MagicConch.API.TriggerMagicConch with a fixed type)
-- with the provider's Delete Mode switched on or off for the case and put back
-- afterwards; pickups are touched by moving Isaac onto them, and what counts
-- is the engine's own smelted-trinket list (REPENTOGON GetSmeltedTrinkets).
local S = require("scripts.dev.item_scenarios")
local C = {}

local GOLDEN = TrinketType.TRINKET_GOLDEN_FLAG

local function D() return ConchBlessing.conchdebris end
local function T() return D()._test end
local function evidence() return T().evidence() end
local function debrisId() return ConchBlessing.ItemData.CONCH_DEBRIS.id end
local function ticketId()
    local ticket = ConchBlessing.PocketData and ConchBlessing.PocketData.CONCH_TICKET
    return ticket and ticket.id or -1
end
local function smelted(player) return (D().smeltedCount(player)) end

local function floorDebris()
    local list = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET)) do
        if entity:Exists() and D().isDebris(entity.SubType) then list[#list + 1] = entity:ToPickup() end
    end
    return list
end

local function floorTickets()
    local list = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, ticketId())) do
        if entity:Exists() then list[#list + 1] = entity end
    end
    return list
end

local function debrisAt(position)
    for _, pickup in ipairs(floorDebris()) do
        if pickup.Position:Distance(position) < 12 then return pickup end
    end
    return nil
end

local function held(player)
    return string.format("hand=%d,%d smelted=%d", player:GetTrinket(0), player:GetTrinket(1), smelted(player))
end

local function describe(player)
    local e = evidence()
    return string.format("%s floor debris=%d tickets=%d; dropped=%d touched=%d fromHand=%d tickets=%d",
        held(player), #floorDebris(), #floorTickets(), e.dropped, e.touched, e.fromHand, e.tickets)
end

local function requireModule(plan)
    plan.require("Conch Debris module, REPENTOGON's smelt API and the Conch Ticket ready", function()
        local m = D()
        return m and m._test and m.available() and ticketId() > 0 and true or false,
            "module missing, no smelt API or no Conch Ticket card"
    end)
    plan.act(function() T().resetEvidence() end)
end

C.CONCH_DEBRIS = {
    -- Copies never stay in the hand: a copy reaches the hand and is smelted on
    -- the next update; the copies counted are the smelted ones.
    count = function(player) return smelted(player) end,
    change = function(player, item, previous, n)
        if n > previous then
            player:AddTrinket(item.id, false)
        else
            player:TryRemoveSmeltedTrinket(item.id)
        end
    end,
    stage = function(plan, id, n)
        plan.check("nothing stays in the hand", function(player)
            return not D().isDebris(player:GetTrinket(0)) and not D().isDebris(player:GetTrinket(1)), held(player)
        end)
        plan.check("fewer than three copies make no Conch Ticket", function(player)
            return #floorTickets() == 0 and smelted(player) == n, describe(player)
        end)
    end,
}

-- A free debris beside Isaac; nothing may collect it before the case moves Isaac.
local function spawnDebris(x, y, flag)
    local room = Game():GetRoom()
    local position = room:GetCenterPos() + Vector(x, y)
    local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, debrisId() | (flag or 0),
        position, Vector.Zero, nil):ToPickup()
    pickup.Wait = 0
    return pickup
end

-- Offsets are plain numbers: plans are built before the engine's Vector is needed.
local function touch(plan, x, y, label, expected)
    plan.act(function(player, ctx)
        player.Position = Game():GetRoom():GetCenterPos() + Vector(-200, 0)
        ctx.debris = spawnDebris(x, y)
    end)
    plan.wait(3)
    plan.act(function(player, ctx)
        player.Velocity = Vector.Zero
        player.Position = ctx.debris.Position
    end)
    plan.waitUntil(function(player)
        return evidence().touched >= expected, describe(player)
    end, 60, label)
    plan.wait(2)
end

-- Touching a debris smelts it at once, even with a full hand: the held trinket
-- stays and nothing is pushed onto the floor.
S.add("CONCH_DEBRIS", "touch", {}, function(plan)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.penny = TrinketType.TRINKET_SWALLOWED_PENNY
        player:AddTrinket(ctx.penny, false)
    end)
    plan.wait(2)
    plan.require("Isaac's one trinket slot holds Swallowed Penny", function(player, ctx)
        return player:GetTrinket(0) == ctx.penny and player:GetMaxTrinkets() == 1, held(player)
    end)
    touch(plan, 80, 0, "Isaac touches the debris", 1)
    plan.check("the debris is smelted, not held", function(player, ctx)
        return smelted(player) == 1 and player:GetTrinket(0) == ctx.penny and not ctx.debris:Exists(), describe(player)
    end)
    plan.check("Swallowed Penny was not pushed onto the floor", function(player, ctx)
        return #Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, ctx.penny) == 0
            and #floorDebris() == 0, describe(player)
    end)
end)

-- Three smelted copies become one Conch Ticket beside Isaac, and are gone.
S.add("CONCH_DEBRIS", "ticket", {}, function(plan)
    requireModule(plan)
    touch(plan, 80, -60, "the first debris is smelted", 1)
    touch(plan, 80, 60, "the second debris is smelted", 2)
    plan.check("two copies are kept, no ticket yet", function(player)
        return smelted(player) == 2 and #floorTickets() == 0, describe(player)
    end)
    touch(plan, 140, 0, "the third debris is smelted", 3)
    plan.check("the three copies are gone and one Conch Ticket lies beside Isaac", function(player)
        local tickets = floorTickets()
        local near = tickets[1] and tickets[1].Position:Distance(player.Position) or -1
        return smelted(player) == 0 and #tickets == 1 and evidence().tickets == 1 and near >= 0 and near < 160,
            describe(player) .. string.format(" ticket %.0f from Isaac", near)
    end)
    plan.section("CONCH_DEBRIS / ticket", "a poof and a thumbs-up as the Conch Ticket appeared beside Isaac")
end)

-- A copy that reaches the hand (bought, given) is smelted on the next update;
-- a golden copy counts as one.
S.add("CONCH_DEBRIS", "hand", {}, function(plan, id)
    requireModule(plan)
    for index, flag in ipairs({ 0, GOLDEN, 0 }) do
        plan.act(function(player) player:AddTrinket(id | flag, false) end)
        plan.waitUntil(function(player)
            return evidence().fromHand >= index, describe(player)
        end, 30, "copy " .. index .. " leaves the hand")
        if index < 3 then
            plan.check("copy " .. index .. " is smelted and counts once", function(player)
                return smelted(player) == index and player:GetTrinket(0) == 0 and #floorTickets() == 0, describe(player)
            end)
        end
    end
    plan.wait(2)
    plan.check("normal, golden and normal make one Conch Ticket", function(player)
        return smelted(player) == 0 and #floorTickets() == 1 and player:GetTrinket(0) == 0, describe(player)
    end)
end)

-- ---- real Magic Conch answers ----

local function conch() return MagicConch and MagicConch.API end

local function conchSetup(plan, deleteMode)
    plan.require("the Magic Conch API and the conversion map", function()
        local api = conch()
        return api and type(api.TriggerMagicConch) == "function" and type(api.GetState) == "function"
            and type(api.GetLastResult) == "function" and MagicConch.Config ~= nil
            and ConchBlessing._itemMapsReady == true and true or false, "Magic Conch API or conversion map missing"
    end)
    plan.act(function(_, ctx)
        local configs = { MagicConch.Config }
        if conch().Config and conch().Config ~= MagicConch.Config then configs[#configs + 1] = conch().Config end
        ctx.cleanupFns = ctx.cleanupFns or {}
        for _, config in ipairs(configs) do
            local saved = { config.enabled, config.timing, config.attemptsPerRoom, config.deleteMode }
            table.insert(ctx.cleanupFns, function()
                config.enabled, config.timing, config.attemptsPerRoom, config.deleteMode = saved[1], saved[2], saved[3], saved[4]
            end)
            config.enabled, config.attemptsPerRoom, config.deleteMode = true, 0, deleteMode
            config.timing = { shake = 1, wait = 1, display = 1, cooldown = 0 }
        end
    end)
end

local function answer(plan, kind)
    plan.waitUntil(function() return conch().GetState() == "idle", "Conch " .. tostring(conch().GetState()) end,
        240, "the Magic Conch is idle")
    plan.wait(12) -- the Conch refuses a use within 10 frames of the last one
    plan.act(function(_, ctx)
        ctx.askFrame = Game():GetFrameCount()
        ctx.asked = conch().TriggerMagicConch("ConchBlessing Conch Debris test", { type = kind })
    end)
    plan.require("the Magic Conch takes the question", function(_, ctx)
        return ctx.asked ~= nil and ctx.asked.success == true, "reason=" .. tostring(ctx.asked and ctx.asked.reason)
    end)
    plan.waitUntil(function(_, ctx)
        local last = conch().GetLastResult()
        return last ~= nil and last.type == kind and (last.timestamp or -1) >= ctx.askFrame,
            "last=" .. tostring(last and last.type)
    end, 240, "the Magic Conch answers " .. kind)
    plan.wait(3)
end

-- Vanilla origins with (has = true) or without (has = false) a result for `flag`.
local function origins(kind, flag, has)
    local own = {}
    for _, item in pairs(ConchBlessing.ItemData) do
        if type(item) == "table" and type(item.id) == "number" then
            own[(item.type == "trinket" and "T:" or "C:") .. item.id] = true
        end
    end
    local list = {}
    for key, maps in pairs(ConchBlessing.ItemMaps or {}) do
        local k, id = key:match("^(%a):(%d+)$")
        if k == kind and not own[key] and ((maps[flag] ~= nil) == has) then list[#list + 1] = tonumber(id) end
    end
    table.sort(list)
    return list[1]
end

local function spot(x, y) return Game():GetRoom():GetCenterPos() + Vector(x, y) end

local function spawn(variant, subtype, x, y)
    local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, spot(x, y), Vector.Zero, nil):ToPickup()
    pickup.Wait = 0
    return pickup
end

local function park(plan)
    plan.act(function(player)
        player.Velocity = Vector.Zero
        player.Position = spot(-220, 0)
    end)
end

-- Delete Mode, a neutral answer: every evolvable item without a neutral result
-- is deleted and leaves one free, normal debris on its spot (a shop item, a
-- choice and a golden trinket alike); an item with a neutral result evolves,
-- and an item that cannot evolve stays (Delete Mode deletes those only on a
-- negative answer).
S.add("CONCH_DEBRIS", "drop", {}, function(plan)
    requireModule(plan)
    conchSetup(plan, true)
    plan.require("vanilla items that fail, pass and cannot evolve on a neutral answer", function(_, ctx)
        ctx.failC = origins("C", "neutral", false)
        ctx.failT = origins("T", "neutral", false)
        ctx.passT = origins("T", "neutral", true)
        ctx.plain = CollectibleType.COLLECTIBLE_BREAKFAST
        return ctx.failC and ctx.failT and ctx.passT and ConchBlessing.ItemMaps["C:" .. ctx.plain] == nil and true or false,
            string.format("failC=%s failT=%s passT=%s", tostring(ctx.failC), tostring(ctx.failT), tostring(ctx.passT))
    end)
    park(plan)
    plan.act(function(_, ctx)
        ctx.a = spawn(PickupVariant.PICKUP_COLLECTIBLE, ctx.failC, 40, -80)
        ctx.a.AutoUpdatePrice = false
        ctx.a.Price = 15
        ctx.a.OptionsPickupIndex = 7
        ctx.b = spawn(PickupVariant.PICKUP_TRINKET, ctx.failT | GOLDEN, 140, -80)
        ctx.c = spawn(PickupVariant.PICKUP_TRINKET, ctx.passT, 40, 80)
        ctx.d = spawn(PickupVariant.PICKUP_COLLECTIBLE, ctx.plain, 140, 80)
    end)
    plan.wait(5)
    plan.act(function(_, ctx)
        local function at(e) return Vector(e.Position.X, e.Position.Y) end
        ctx.aPos, ctx.bPos, ctx.cPos = at(ctx.a), at(ctx.b), at(ctx.c)
    end)
    plan.require("the four items stand, the failing collectible for sale in choice group 7", function(_, ctx)
        return ctx.a:Exists() and ctx.b:Exists() and ctx.c:Exists() and ctx.d:Exists() and ctx.a:IsShopItem()
            and ctx.a.OptionsPickupIndex == 7, string.format("shop=%s price=%d", tostring(ctx.a:IsShopItem()), ctx.a.Price)
    end)
    answer(plan, "neutral")
    plan.check("both failed items are gone, each leaving one debris on its spot", function(player, ctx)
        local a, b = debrisAt(ctx.aPos), debrisAt(ctx.bPos)
        return not ctx.a:Exists() and not ctx.b:Exists() and a ~= nil and b ~= nil and #floorDebris() == 2
            and evidence().dropped == 2, describe(player)
    end)
    plan.check("each debris is a normal copy, free and in no choice group", function(player, ctx)
        for _, position in ipairs({ ctx.aPos, ctx.bPos }) do
            local d = debrisAt(position)
            if not d or d.SubType ~= debrisId() or d.Price ~= 0 or d:IsShopItem() or d.OptionsPickupIndex ~= 0 then
                return false, d and string.format("subtype=%d price=%d options=%d", d.SubType, d.Price,
                    d.OptionsPickupIndex) or "missing"
            end
        end
        return true
    end)
    plan.check("the item with a neutral result evolves and leaves no debris", function(player, ctx)
        return ctx.c:Exists() and ConchBlessing.upgrade.isAnimatingPickup(ctx.c) and debrisAt(ctx.cPos) == nil,
            describe(player)
    end)
    plan.check("the item that cannot evolve stays", function(_, ctx)
        return ctx.d:Exists() and ctx.d.SubType == ctx.plain, "Breakfast exists=" .. tostring(ctx.d:Exists())
    end)
    plan.section("CONCH_DEBRIS / drop", "the two failed items vanished with a poof and a broken-shell trinket lay on each spot")
end)

-- Delete Mode, a negative answer: an item that cannot evolve is deleted with no
-- debris, a debris already on the floor stays, and an evolvable item without a
-- negative result leaves a debris.
S.add("CONCH_DEBRIS", "negative", {}, function(plan)
    requireModule(plan)
    conchSetup(plan, true)
    plan.require("a vanilla collectible with no negative result", function(_, ctx)
        ctx.fail = origins("C", "negative", false)
        return ctx.fail ~= nil, "none found"
    end)
    park(plan)
    plan.act(function(player, ctx)
        ctx.old = spawnDebris(40, 80)
        ctx.plain = spawn(PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_BREAKFAST, 140, 80)
        ctx.failed = spawn(PickupVariant.PICKUP_COLLECTIBLE, ctx.fail, 40, -80)
    end)
    plan.wait(5)
    plan.act(function(_, ctx)
        T().resetEvidence()
        ctx.failPos = Vector(ctx.failed.Position.X, ctx.failed.Position.Y)
        ctx.oldPos = Vector(ctx.old.Position.X, ctx.old.Position.Y)
        ctx.plainPos = Vector(ctx.plain.Position.X, ctx.plain.Position.Y)
    end)
    answer(plan, "negative")
    plan.check("the item that cannot evolve is deleted, leaving nothing", function(player, ctx)
        return not ctx.plain:Exists() and debrisAt(ctx.plainPos) == nil, describe(player)
    end)
    plan.check("the debris already on the floor stays", function(player, ctx)
        return ctx.old:Exists() and debrisAt(ctx.oldPos) ~= nil, describe(player)
    end)
    plan.check("the failed evolution leaves one debris", function(player, ctx)
        return not ctx.failed:Exists() and debrisAt(ctx.failPos) ~= nil and evidence().dropped == 1
            and #floorDebris() == 2, describe(player)
    end)
end)

-- Delete Mode off: a failed evolution deletes nothing and drops nothing.
S.add("CONCH_DEBRIS", "delete_off", {}, function(plan)
    requireModule(plan)
    conchSetup(plan, false)
    plan.require("a vanilla collectible with no neutral result", function(_, ctx)
        ctx.fail = origins("C", "neutral", false)
        return ctx.fail ~= nil, "none found"
    end)
    park(plan)
    plan.act(function(_, ctx) ctx.item = spawn(PickupVariant.PICKUP_COLLECTIBLE, ctx.fail, 40, -80) end)
    plan.wait(5)
    answer(plan, "neutral")
    plan.check("the item stays as it was and no debris drops", function(player, ctx)
        return ctx.item:Exists() and ctx.item.SubType == ctx.fail and #floorDebris() == 0 and evidence().dropped == 0,
            describe(player)
    end)
end)

return C
