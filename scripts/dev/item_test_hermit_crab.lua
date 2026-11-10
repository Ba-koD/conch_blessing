local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 소라게 (Hermit Crab): the lifecycle contract and its cases. Every trinket the
-- crab takes is really put down through EntityPlayer:DropTrinket (the engine
-- spawns it with the player as its spawner, like the drop key), the crab
-- really walks over to it, and every check reads REPENTOGON's innate and
-- smelted counts, the room's real pickups and the crab's real position.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local TrinketUtils = require("scripts.lib.trinket_utils")
local C = {}

local function crab() return ConchBlessing.hermitcrab end
local function T() return crab()._test end
local function evidence() return T().evidence() end
local function golden(id) return id | TrinketType.TRINKET_GOLDEN_FLAG end

-- Plain trinkets with no pickup effect of their own. Every ID is read when a
-- case runs: the offline harness loads this file without engine enums.
local function penny() return TrinketType.TRINKET_SWALLOWED_PENNY end
local function pin() return TrinketType.TRINKET_PUSH_PIN end
local function goldenPenny() return golden(TrinketType.TRINKET_SWALLOWED_PENNY) end

local function smelted(player, id)
    local normal, gold = TrinketUtils.getSmeltedCounts(player, id & ~TrinketType.TRINKET_GOLDEN_FLAG)
    if normal == nil then return -1 end
    return id & TrinketType.TRINKET_GOLDEN_FLAG ~= 0 and gold or normal
end

-- Innate copies in the crabs' group: what the crab holds.
local function innate(player, id)
    return player:GetInnateTrinketCount(id, T().group)
end

local function floorCount(id)
    local n = 0
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_TRINKET
            and entity.SubType == id and entity:Exists() then n = n + 1 end
    end
    return n
end

local function crabs(player)
    local list, v = {}, T().variant()
    if not v then return list end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local fam = entity.Type == EntityType.ENTITY_FAMILIAR and entity.Variant == v and entity:ToFamiliar()
        if fam and fam:Exists() and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player) then
            list[#list + 1] = fam
        end
    end
    return list
end

local function held(player)
    local data = T().ledger(player)
    return data and data.held or {}
end

local function describe(player, ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = string.format("%d: innate=%d smelted=%d floor=%d", id, innate(player, id),
            smelted(player, id), floorCount(id))
    end
    return "held={" .. table.concat(held(player), ",") .. "} " .. table.concat(parts, "; ")
end

local function requireModule(plan)
    plan.require("Hermit Crab module, its familiar and REPENTOGON's innate and smelt APIs ready", function(player)
        local m = crab()
        return m and m._test and m._test.itemId() > 0 and m._test.variant() ~= nil
            and type(player.AddInnateTrinket) == "function" and type(player.RemoveInnateTrinket) == "function"
            and type(player.GetInnateTrinketCount) == "function"
            and type(player.AddSmeltedTrinket) == "function" and type(player.TryRemoveSmeltedTrinket) == "function"
            and type(player.GetSmeltedTrinkets) == "function" and true or false, "module, variant or API missing"
    end)
end

local function give(player, id, n)
    while player:GetCollectibleNum(id) < (n or 1) do player:AddCollectible(id, 0, false) end
end

-- The room corner farthest from where the owner drops trinkets, a tile in.
local function farCorner(player)
    local room = Game():GetRoom()
    local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
    local spot = player.Position + Vector(0, 40)
    local best, bestDist
    for _, corner in ipairs({ Vector(tl.X + 40, tl.Y + 40), Vector(br.X - 40, tl.Y + 40),
        Vector(tl.X + 40, br.Y - 40), Vector(br.X - 40, br.Y - 40) }) do
        local d = corner:Distance(spot)
        if not bestDist or d > bestDist then best, bestDist = corner, d end
    end
    return best
end

-- Send the owner's crab to the far corner so the fetch is a real walk.
local function crabToCorner(plan)
    plan.act(function(player, ctx)
        local fam = crabs(player)[1]
        if fam then
            fam.Position = farCorner(player)
            fam.Velocity = Vector.Zero
        end
        ctx.corner = fam and fam.Position
    end)
end

local function droppedPickup(id)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_TRINKET
            and entity.SubType == id and entity:Exists() then return entity end
    end
end

-- Put a trinket in hand, then drop it the way the drop key does.
local function putInHandAndDrop(plan, trinket)
    plan.act(function(player, ctx)
        ctx.takenBefore = evidence().taken
        player:AddTrinket(trinket())
        ctx.dropped = trinket()
    end)
    plan.wait(2)
    plan.act(function(player) player:DropTrinket(player.Position + Vector(0, 40), false) end)
end

-- The owner walks off to the room corner farthest from the trinket that is
-- not where the crab stands (a fixture move: no input is pressed).
local function walkAway(plan)
    plan.act(function(player, ctx)
        local pickup = droppedPickup(ctx.dropped)
        local from = pickup and pickup.Position or player.Position
        local fam = crabs(player)[1]
        local room = Game():GetRoom()
        local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
        local best, bestDist
        for _, corner in ipairs({ Vector(tl.X + 60, tl.Y + 60), Vector(br.X - 60, tl.Y + 60),
            Vector(tl.X + 60, br.Y - 60), Vector(br.X - 60, br.Y - 60) }) do
            local d = corner:Distance(from)
            if (not fam or corner:Distance(fam.Position) > 80) and (not bestDist or d > bestDist) then
                best, bestDist = corner, d
            end
        end
        if best then
            player.Position = best
            player.Velocity = Vector.Zero
        end
    end)
end

-- The crab walks over (up to a whole room at its hurry), so allow ten seconds.
local function drop(plan, trinket, label)
    putInHandAndDrop(plan, trinket)
    plan.wait(2)
    walkAway(plan)
    plan.waitUntil(function() return evidence().taken > 0 and true or false, "taken=" .. evidence().taken end,
        300, label or "the crab walks over and takes the dropped trinket")
    plan.wait(2)
end

C.HERMIT_CRAB = { stage = function(plan, id, n)
    plan.check("one crab familiar per copy", function(player)
        return #crabs(player) == n, string.format("crabs=%d copies=%d", #crabs(player), n)
    end)
    plan.check("each crab can hold one trinket", function(player)
        return crab().capacity(player) == n, "capacity " .. crab().capacity(player)
    end)
    plan.check("nothing held", function(player) return #held(player) == 0, "held " .. #held(player) end)
end }

-- The owner's dropped trinket is taken: gone from the floor, smelted once.
S.add("HERMIT_CRAB", "take", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1, "crabs=" .. #crabs(player) end, 30, "the crab appears")
    plan.act(function(_, ctx) ctx.penny = penny() end)
    crabToCorner(plan)
    plan.require("the crab stands in the far corner", function(player, ctx)
        local fam = crabs(player)[1]
        return fam and ctx.corner and fam.Position:Distance(ctx.corner) < 1 and true or false,
            fam and string.format("crab at (%.0f, %.0f)", fam.Position.X, fam.Position.Y) or "no crab"
    end)
    putInHandAndDrop(plan, penny)
    plan.wait(60)
    plan.check("while Isaac stands within two tiles of it, the crab leaves it alone", function(player, ctx)
        local pickup = droppedPickup(ctx.penny)
        local near = pickup and player.Position:Distance(pickup.Position) or -1
        return floorCount(ctx.penny) == 1 and evidence().taken == 0 and evidence().waitedNear > 0
            and near >= 0 and near <= crab().data.ownerNear,
            string.format("%s; Isaac %.0f from it, waited %d", describe(player, { ctx.penny }), near, evidence().waitedNear)
    end)
    walkAway(plan)
    plan.wait(2)
    plan.check("the crab does not take it from across the room", function(player, ctx)
        return floorCount(ctx.penny) == 1 and evidence().taken == 0, describe(player, { ctx.penny })
    end)
    plan.waitUntil(function() return evidence().taken > 0 and true or false, "taken=" .. evidence().taken end,
        300, "the crab walks over and takes the dropped trinket")
    plan.wait(2)
    plan.check("it walked to the trinket and took it within reach", function()
        local e, reach = evidence(), crab().data.reach
        return e.fetchFrom > 3 * reach and e.fetchAt >= 0 and e.fetchAt <= reach,
            string.format("set out %.0f away, took it at %.1f (reach %d)", e.fetchFrom, e.fetchAt, reach)
    end)
    plan.check("the dropped trinket left the floor and is held once as an innate trinket, not smelted", function(player, ctx)
        local p = ctx.penny
        return floorCount(p) == 0 and innate(player, p) == 1 and smelted(player, p) == 0 and #held(player) == 1
            and held(player)[1] == p
            and player:GetTrinket(0) == 0, describe(player, { p })
    end)
    plan.check("the held trinket counts as the owner's", function(player, ctx)
        return player:HasTrinket(ctx.penny), "HasTrinket false"
    end)
    plan.section("HERMIT_CRAB / take", "the crab holds the penny low in front, both claws gathered")
end, { "bffs" })

-- A trinket the room spawns (no player spawner) is never taken.
S.add("HERMIT_CRAB", "floor_ignored", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    plan.act(function(player, ctx)
        ctx.trinket = TrinketType.TRINKET_PETRIFIED_POOP
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, ctx.trinket,
            Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(60, 0), 0, true), Vector.Zero, nil)
    end)
    plan.wait(30)
    plan.check("a trinket the room spawned stays on the floor", function(player, ctx)
        return floorCount(ctx.trinket) == 1 and evidence().taken == 0 and #held(player) == 0,
            describe(player, { ctx.trinket })
    end)
end)

-- It strolls the room on its own while its owner stands still.
S.add("HERMIT_CRAB", "wander", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    plan.act(function(player, ctx)
        ctx.home = player.Position
        ctx.samples, ctx.far, ctx.outside, ctx.rested, ctx.walked, ctx.follower, ctx.fastest = 0, 0, 0, 0, 0, false, 0
    end)
    plan.waitUntil(function(player, ctx)
        local fam = crabs(player)[1]
        if fam then
            ctx.samples = ctx.samples + 1
            ctx.far = math.max(ctx.far, fam.Position:Distance(ctx.home))
            if not Game():GetRoom():IsPositionInRoom(fam.Position, 0) then ctx.outside = ctx.outside + 1 end
            local speed = fam.Velocity:Length()
            ctx.fastest = math.max(ctx.fastest, speed)
            if speed < 0.1 then ctx.rested = ctx.rested + 1 else ctx.walked = ctx.walked + 1 end
            if fam.IsFollower then ctx.follower = true end
        end
        return ctx.samples >= 450, "samples=" .. ctx.samples
    end, 480, "the crab strolls for fifteen seconds")
    plan.check("it is not one of the owner's followers", function(_, ctx)
        return not ctx.follower, "IsFollower was true"
    end)
    plan.check("it strolls away from where its owner stands, inside the walls", function(player, ctx)
        return ctx.far >= 80 and ctx.outside == 0 and player.Position:Distance(ctx.home) < 1,
            string.format("farthest %.0f from the owner, %d samples outside", ctx.far, ctx.outside)
    end)
    plan.check("it rests between strolls and only ambles", function(_, ctx)
        return ctx.rested > 0 and ctx.walked > 0 and ctx.fastest <= crab().data.wanderSpeed + 0.5,
            string.format("rested %d, walked %d, fastest %.2f", ctx.rested, ctx.walked, ctx.fastest)
    end)
    plan.section("HERMIT_CRAB / wander", "the crab ambles about the room, rests and ambles on; it never trails Isaac")
end)

-- A trinket picked back up before the crab gets there is left alone.
S.add("HERMIT_CRAB", "gone", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    plan.act(function(_, ctx) ctx.penny = penny() end)
    crabToCorner(plan)
    putInHandAndDrop(plan, penny)
    plan.wait(2)
    walkAway(plan)
    plan.wait(3)
    plan.require("the crab set out for it", function(player)
        local fam = crabs(player)[1]
        return fam and T().walkState(fam).claim and true or false, "no crab is fetching"
    end)
    plan.act(function(_, ctx)
        local pickup = droppedPickup(ctx.penny)
        if pickup then pickup:Remove() end
    end)
    plan.wait(30)
    plan.check("nothing was taken and the crab went back to strolling", function(player, ctx)
        local fam = crabs(player)[1]
        return evidence().taken == 0 and innate(player, ctx.penny) == 0 and #held(player) == 0
            and #T().claims() == 0 and fam and not T().walkState(fam).claim and true or false,
            describe(player, { ctx.penny })
    end)
end)

-- Drop Curved Horn by the crab, let the real Magic Conch answer positive (it
-- becomes Time = Power), walk off while the upgrade still plays: the crab
-- waits it out, then carries Time = Power.
local function conch() return MagicConch and MagicConch.API end

S.add("HERMIT_CRAB", "upgrade", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        T().resetEvidence()
        local config = MagicConch and MagicConch.Config
        ctx.cleanupFns = ctx.cleanupFns or {}
        if config then
            local enabled, timing, attempts = config.enabled, config.timing, config.attemptsPerRoom
            table.insert(ctx.cleanupFns, function()
                config.enabled, config.timing, config.attemptsPerRoom = enabled, timing, attempts
            end)
            config.enabled, config.attemptsPerRoom = true, 0
            config.timing = { shake = 1, wait = 1, display = 1, cooldown = 0 }
        end
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    plan.require("the Magic Conch API and Time = Power", function()
        local api = conch()
        local upgraded = ConchBlessing.ItemData.TIME_POWER and ConchBlessing.ItemData.TIME_POWER.id or -1
        return api and type(api.TriggerMagicConch) == "function" and type(api.GetState) == "function"
            and upgraded > 0 and true or false, "Magic Conch API or Time = Power missing"
    end)
    plan.act(function(_, ctx)
        ctx.horn = TrinketType.TRINKET_CURVED_HORN
        ctx.power = ConchBlessing.ItemData.TIME_POWER.id
    end)
    putInHandAndDrop(plan, function() return TrinketType.TRINKET_CURVED_HORN end)
    plan.waitUntil(function() return conch().GetState() == "idle", "Conch " .. tostring(conch().GetState()) end,
        240, "the Magic Conch is idle")
    plan.wait(12) -- the Conch refuses a use within 10 frames of the last one
    plan.act(function(_, ctx)
        ctx.asked = conch().TriggerMagicConch("ConchBlessing Hermit Crab test", { type = "positive" })
    end)
    plan.require("the Magic Conch answers positive", function(_, ctx)
        return ctx.asked ~= nil and ctx.asked.success == true, "reason=" .. tostring(ctx.asked and ctx.asked.reason)
    end)
    plan.waitUntil(function(_, ctx)
        local pickup = droppedPickup(ctx.horn) or droppedPickup(ctx.power)
        return pickup and ConchBlessing.upgrade.isAnimatingPickup(pickup) and true or false, "no upgrade playing"
    end, 240, "the upgrade starts on the dropped trinket")
    plan.act(function(_, ctx) ctx.dropped = ctx.horn end)
    walkAway(plan)
    plan.wait(10)
    plan.check("Isaac walked off, and the crab still leaves it alone while the upgrade plays", function(player, ctx)
        local pickup = droppedPickup(ctx.horn) or droppedPickup(ctx.power)
        local away = pickup and player.Position:Distance(pickup.Position) or -1
        return pickup and away > crab().data.ownerNear and evidence().taken == 0 and evidence().waitedUpgrade > 0
            and true or false,
            string.format("Isaac %.0f from it, waited for the upgrade %d, taken %d", away,
                evidence().waitedUpgrade, evidence().taken)
    end)
    plan.waitUntil(function() return evidence().taken > 0 and true or false, "taken=" .. evidence().taken end,
        900, "the crab carries the upgraded trinket once the upgrade is over")
    plan.wait(2)
    plan.check("it holds Time = Power, and Curved Horn is gone", function(player, ctx)
        local h = held(player)
        return #h == 1 and h[1] == ctx.power and innate(player, ctx.power) == 1 and floorCount(ctx.power) == 0
            and floorCount(ctx.horn) == 0 and innate(player, ctx.horn) == 0, describe(player, { ctx.horn, ctx.power })
    end)
end)

-- The crab protects what it holds: a hit breaks a carried Perfection, but the
-- engine never takes an innate trinket away (user decision 2026-11-09).
S.add("HERMIT_CRAB", "protected", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    plan.act(function(_, ctx) ctx.perfection = TrinketType.TRINKET_PERFECTION end)
    drop(plan, function() return TrinketType.TRINKET_PERFECTION end, "the crab takes Perfection")
    plan.require("the crab holds Perfection and Isaac has its +10 luck", function(player, ctx)
        return innate(player, ctx.perfection) == 1 and held(player)[1] == ctx.perfection
            and player:HasTrinket(ctx.perfection) and player.Luck >= 10 - 1e-3,
            describe(player, { ctx.perfection }) .. string.format(" luck=%.2f", player.Luck)
    end)
    H.hit(plan)
    plan.wait(10)
    plan.check("the hit leaves the crab's Perfection, and its luck, alone", function(player, ctx)
        local fam = crabs(player)[1]
        local drawn = fam and T().layout()[GetPtrHash(fam)] or {}
        return innate(player, ctx.perfection) == 1 and #held(player) == 1 and #drawn == 1
            and player.Luck >= 10 - 1e-3 and evidence().vanished == 0,
            describe(player, { ctx.perfection }) .. string.format(" luck=%.2f drawn=%d vanished=%d",
                player.Luck, #drawn, evidence().vanished)
    end)
    plan.check("nothing went on the floor", function(_, ctx)
        return evidence().released == 0 and floorCount(ctx.perfection) == 0,
            string.format("released=%d floor=%d", evidence().released, floorCount(ctx.perfection))
    end)
end)

-- With its claws full the crab puts the oldest down and takes the new one.
S.add("HERMIT_CRAB", "swap", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    drop(plan, penny, "first trinket taken")
    plan.act(function() T().resetEvidence() end)
    drop(plan, pin, "second trinket taken")
    plan.check("the new one is held, the old one is back on the floor and no longer smelted", function(player)
        local a, b = TrinketType.TRINKET_SWALLOWED_PENNY, TrinketType.TRINKET_PUSH_PIN
        local h = held(player)
        return #h == 1 and h[1] == b and innate(player, b) == 1 and innate(player, a) == 0 and floorCount(a) == 1
            and evidence().putDown == 1, describe(player, { a, b })
    end)
    plan.wait(30)
    plan.check("the crab never takes back what it put down", function(player)
        local a = TrinketType.TRINKET_SWALLOWED_PENNY
        return floorCount(a) == 1 and evidence().taken == 1, describe(player, { a })
    end)
end)

-- Three crabs: each trinket stays in the claws of the crab that took it (user
-- report 2026-11-10: the third crab's catch was drawn on the second), a crab
-- with a free claw goes before a nearer full one, and a full crab swaps only
-- its own trinket.
-- The owner's crabs by their number (the engine gives them all one InitSeed).
local function crabsByNumber(player)
    local list = crabs(player)
    table.sort(list, function(a, b) return (T().slot(a) or 0) < (T().slot(b) or 0) end)
    return list
end

local function drawn(fam)
    return fam and table.concat(T().layout()[GetPtrHash(fam)] or {}, ",") or "missing"
end

local function drawings(player)
    local parts = {}
    for i, fam in ipairs(crabsByNumber(player)) do parts[#parts + 1] = string.format("crab%d={%s}", i, drawn(fam)) end
    return table.concat(parts, " ")
end

-- Drop a trinket and walk off; then crab number `near` stands by
-- it and the others stand by Isaac, so `near` is the nearest (a fixture move).
local function fetchWith(plan, near, trinket, label)
    putInHandAndDrop(plan, trinket)
    plan.wait(2)
    walkAway(plan)
    plan.act(function(player, ctx)
        local pickup = droppedPickup(ctx.dropped)
        local room = Game():GetRoom()
        local list = crabsByNumber(player)
        for i, fam in ipairs(list) do
            local beside = pickup and room:GetClampedPosition(pickup.Position + Vector(50, 0), 10)
            local at = i == near and beside or player.Position
            fam.Position = at
            fam.Velocity = Vector.Zero
        end
        ctx.nearCrab = list[near] and GetPtrHash(list[near]) or -1
    end)
    plan.waitUntil(function(_, ctx) return evidence().taken > ctx.takenBefore and true or false,
        "taken=" .. evidence().taken end, 300, label)
    plan.wait(2)
end

S.add("HERMIT_CRAB", "many", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id, 3)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 3, "crabs=" .. #crabs(player) end, 30, "three crabs appear")
    -- they share one InitSeed (measured 2026-11-10); each strolls its own way
    plan.act(function(player, ctx)
        ctx.start = {}
        for i, fam in ipairs(crabsByNumber(player)) do ctx.start[i] = fam.Position end
        ctx.spread = 0
    end)
    plan.waitUntil(function(player, ctx)
        local list = crabsByNumber(player)
        for i = 1, #list do
            for j = i + 1, #list do
                local now = list[i].Position:Distance(list[j].Position)
                local before = ctx.start[i] and ctx.start[j] and ctx.start[i]:Distance(ctx.start[j]) or now
                ctx.spread = math.max(ctx.spread, now - before)
            end
        end
        return ctx.spread >= 48, string.format("spread %.0f", ctx.spread)
    end, 450, "two crabs born together drift apart")
    plan.check("the three crabs are numbered 1, 2 and 3", function(player)
        local list, numbers = crabsByNumber(player), {}
        for i, fam in ipairs(list) do numbers[i] = tostring(T().slot(fam)) end
        return table.concat(numbers, ",") == "1,2,3", "numbers " .. table.concat(numbers, ",")
    end)
    plan.act(function(_, ctx)
        ctx.penny, ctx.pin = penny(), pin()
        ctx.poop, ctx.clip = TrinketType.TRINKET_PETRIFIED_POOP, TrinketType.TRINKET_PAPER_CLIP
    end)
    fetchWith(plan, 1, penny, "the first crab takes the penny")
    fetchWith(plan, 3, pin, "the third crab takes the pin")
    plan.check("the third crab's catch is in its own claws, not the second's", function(player, ctx)
        local list = crabsByNumber(player)
        return evidence().fetchCrab == ctx.nearCrab and drawn(list[1]) == tostring(ctx.penny)
            and drawn(list[2]) == "" and drawn(list[3]) == tostring(ctx.pin),
            drawings(player) .. string.format(" fetched by the third crab: %s", tostring(evidence().fetchCrab == ctx.nearCrab))
    end)
    plan.wait(60)
    plan.check("strolling about keeps each trinket with its crab", function(player, ctx)
        local list = crabsByNumber(player)
        return drawn(list[1]) == tostring(ctx.penny) and drawn(list[2]) == "" and drawn(list[3]) == tostring(ctx.pin),
            drawings(player)
    end)
    -- the first crab (full) stands by the drop, the second (free) by Isaac:
    -- the free one sets out
    fetchWith(plan, 1, function() return TrinketType.TRINKET_PETRIFIED_POOP end, "a crab takes the poop")
    plan.check("a crab with a free claw went, not the nearer full one", function(player, ctx)
        local list = crabsByNumber(player)
        return evidence().fetchCrab == GetPtrHash(list[2]) and drawn(list[1]) == tostring(ctx.penny)
            and drawn(list[2]) == tostring(ctx.poop) and drawn(list[3]) == tostring(ctx.pin)
            and floorCount(ctx.penny) == 0, drawings(player)
    end)
    plan.act(function() T().resetEvidence() end)
    fetchWith(plan, 1, function() return TrinketType.TRINKET_PAPER_CLIP end, "the first crab takes the paper clip")
    plan.check("every claw was full: the first crab put its own penny down and the others kept theirs", function(player, ctx)
        local list = crabsByNumber(player)
        return evidence().fetchCrab == GetPtrHash(list[1]) and evidence().putDown == 1
            and drawn(list[1]) == tostring(ctx.clip) and drawn(list[2]) == tostring(ctx.poop)
            and drawn(list[3]) == tostring(ctx.pin) and floorCount(ctx.penny) == 1 and innate(player, ctx.penny) == 0
            and innate(player, ctx.clip) == 1,
            drawings(player) .. " " .. describe(player, { ctx.penny, ctx.clip })
    end)
    plan.section("HERMIT_CRAB / many", "each of the three crabs draws the trinket it walked over to")
end)

-- A golden trinket stays golden while held.
S.add("HERMIT_CRAB", "golden", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    drop(plan, goldenPenny, "the golden trinket is taken")
    plan.check("held as a golden copy", function(player)
        local g = golden(TrinketType.TRINKET_SWALLOWED_PENNY)
        return innate(player, g) == 1 and innate(player, TrinketType.TRINKET_SWALLOWED_PENNY) == 0
            and held(player)[1] == g, describe(player, { g, TrinketType.TRINKET_SWALLOWED_PENNY })
    end)
end)

-- BFFS: one crab holds two.
S.add("HERMIT_CRAB", "bffs", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
        give(player, CollectibleType.COLLECTIBLE_BFFS)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    drop(plan, penny, "first trinket taken")
    plan.act(function() T().resetEvidence() end)
    drop(plan, pin, "second trinket taken")
    plan.check("both are held and smelted; nothing was put down", function(player)
        local a, b = TrinketType.TRINKET_SWALLOWED_PENNY, TrinketType.TRINKET_PUSH_PIN
        local h = held(player)
        return #h == 2 and innate(player, a) == 1 and innate(player, b) == 1 and floorCount(a) == 0
            and floorCount(b) == 0, describe(player, { a, b })
    end)
    plan.check("the crab is drawn larger and its layout holds two", function(player)
        local list = crabs(player)
        local fam = list[1]
        local layout = fam and T().layout()[GetPtrHash(fam)] or {}
        local animation = fam and fam:GetSprite():GetAnimation() or "missing"
        -- the scale it was last drawn at: the engine re-applies BFFS's 1.25
        -- after each update, and the crab undoes it before the draw
        local drawn = fam and T().drawnScale(fam)
        return fam and drawn and math.abs(drawn - 1) < 1e-3 and animation:find("^BffsTwo") and #layout == 2
            and true or false,
            string.format("native BFFS pose=%s drawn scale=%s (update scale %s) held=%d", animation,
                tostring(drawn), tostring(fam and fam.SpriteScale.X), #layout)
    end)
    plan.act(function(player) player:RemoveCollectible(CollectibleType.COLLECTIBLE_BFFS) end)
    plan.wait(4)
    plan.check("losing BFFS lets go of the newest one", function(player)
        local a, b = TrinketType.TRINKET_SWALLOWED_PENNY, TrinketType.TRINKET_PUSH_PIN
        local h = held(player)
        return #h == 1 and h[1] == a and innate(player, b) == 0 and floorCount(b) == 1, describe(player, { a, b })
    end)
    plan.section("HERMIT_CRAB / bffs", "a bigger crab holds one trinket in each claw")
end, { "bffs" })

-- Losing the crab gives the trinket back on the floor.
S.add("HERMIT_CRAB", "loss", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    drop(plan, penny)
    plan.act(function(player) player:RemoveCollectible(id) end)
    plan.wait(4)
    plan.check("the trinket is back on the floor, no longer smelted, and the crab is gone", function(player)
        local a = TrinketType.TRINKET_SWALLOWED_PENNY
        return #held(player) == 0 and innate(player, a) == 0 and floorCount(a) == 1 and #crabs(player) == 0,
            describe(player, { a })
    end)
end)

-- Kronos absorbs the crab: what it held stays smelted; an empty absorbed crab
-- smelts the next trinket in hand at once, and then no more.
S.add("HERMIT_CRAB", "kronos", {}, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    drop(plan, penny)
    plan.act(function(player)
        T().resetEvidence()
        player:AddCollectible(ConchBlessing.ItemData.KRONOS.id, 0, false)
    end)
    plan.waitUntil(function(player)
        return ConchBlessing.kronos._getEffectCount(player, id) >= 1 and player:GetCollectibleNum(id) == 0,
            "absorbed=" .. ConchBlessing.kronos._getEffectCount(player, id)
    end, 120, "Kronos absorbs the crab")
    plan.wait(4)
    plan.check("what the crab held stays smelted for good", function(player)
        local a = TrinketType.TRINKET_SWALLOWED_PENNY
        local data = T().ledger(player)
        return smelted(player, a) == 1 and innate(player, a) == 0 and floorCount(a) == 0 and #data.held == 0
            and data.kept == 1,
            describe(player, { a }) .. " kept=" .. data.kept
    end)
    -- a second crab, absorbed at once, smelts the next trinket in hand
    plan.act(function(player) player:AddCollectible(id, 0, false) end)
    plan.waitUntil(function(player)
        return ConchBlessing.kronos._getEffectCount(player, id) >= 2, "absorbed=" .. ConchBlessing.kronos._getEffectCount(player, id)
    end, 120, "Kronos absorbs the second crab")
    plan.act(function(player) player:AddTrinket(TrinketType.TRINKET_PUSH_PIN) end)
    plan.wait(4)
    plan.check("the trinket in hand is smelted at once", function(player)
        local b = TrinketType.TRINKET_PUSH_PIN
        return player:GetTrinket(0) == 0 and smelted(player, b) == 1 and evidence().smeltedAtOnce == 1,
            describe(player, { b })
    end)
    plan.act(function(player) player:AddTrinket(TrinketType.TRINKET_PETRIFIED_POOP) end)
    plan.wait(4)
    plan.check("with the room used up, the next trinket stays in hand", function(player)
        local c = TrinketType.TRINKET_PETRIFIED_POOP
        return player:GetTrinket(0) == c and smelted(player, c) == 0, describe(player, { c })
    end)
end, { "kronos" })

-- Every trinket a synergy names works from the crab's claws as from a hand
-- (user goal 2026-11-10): each synergy check reads HasTrinket, which counts the
-- crab's innate copy. Each such trinket is checked in the crab in turn; Door
-- Stop really raises 장승 at the door come in by, and Atropos really unlinks a
-- choice.
local function synergyTrinkets()
    local list, seen = {}, {}
    local function add(id)
        if type(id) == "number" and id > 0 and not seen[id] then seen[id], list[#list + 1] = true, id end
    end
    for _, item in pairs(ConchBlessing.ItemData) do
        if item.type == "trinket" and next(item.synergies or {}) ~= nil then add(item.id) end
        for target in pairs(item.synergies or {}) do
            if type(target) == "table" and target.type == "trinket" then
                add(target.id or (target.name and Isaac.GetTrinketIdByName(target.name)))
            end
        end
    end
    table.sort(list)
    return list
end

local function inSlots(player, id)
    for slot = 0, 1 do
        if (player:GetTrinket(slot) & ~TrinketType.TRINKET_GOLDEN_FLAG) == id then return true end
    end
    return false
end

-- Takes a trinket the crab put down off the floor so nobody picks it up by walking.
local function clearFloor(id)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_TRINKET
            and (entity.SubType & ~TrinketType.TRINKET_GOLDEN_FLAG) == id then entity:Remove() end
    end
end

S.add("HERMIT_CRAB", "partner_trinkets", {}, function(plan, id)
    requireModule(plan)
    local items = ConchBlessing.ItemData
    local jangseungId = items.JANGSEUNG and items.JANGSEUNG.id or -1
    local atroposId = items.ATROPOS and items.ATROPOS.id or -1
    local trinkets = synergyTrinkets()
    plan.require("the trinkets synergies name, 장승 and Atropos", function()
        return #trinkets >= 3 and jangseungId > 0 and atroposId > 0 and ConchBlessing.jangseung ~= nil or nil,
            "trinkets={" .. table.concat(trinkets, ",") .. "}"
    end)
    plan.act(function(player)
        T().resetEvidence()
        give(player, id)
        player:AddCollectible(jangseungId, 0, false)
    end)
    plan.waitUntil(function(player) return #crabs(player) == 1 end, 30, "the crab appears")
    for index, trinket in ipairs(trinkets) do
        local previous = trinkets[index - 1]
        plan.act(function() T().resetEvidence() end)
        drop(plan, function() return trinket end, "the crab takes " .. trinket)
        plan.act(function() if previous then clearFloor(previous) end end)
        plan.check(trinket .. ": Isaac has it only through the crab, and HasTrinket sees it", function(player)
            return held(player)[1] == trinket and innate(player, trinket) == 1 and not inSlots(player, trinket)
                and player:HasTrinket(trinket), describe(player, { trinket })
        end)
        if trinket == TrinketType.TRINKET_DOOR_STOP then
            plan.check("장승 sees the crab's Door Stop", function()
                local seen = ConchBlessing.jangseung._test.doorStop()
                return seen, "doorStop()=" .. tostring(seen)
            end)
            H.walkThroughDoor(plan, "through a door with the crab's Door Stop", H.ordinaryDoor,
                function() ConchBlessing.jangseung._test.resetEvidence() end)
            plan.check("a pair stands at the door come in by", function(_, ctx)
                local found = false
                for _, marker in ipairs(ConchBlessing.jangseung.markers()) do
                    if marker.slot == ctx.entry and marker.entry then found = true end
                end
                return ctx.entry ~= nil and found,
                    string.format("entry=%s EnterDoor=%s", tostring(ctx.entry), tostring(ctx.enterDoor))
            end)
        elseif trinket == atroposId then
            plan.act(function(player, ctx)
                local room = Game():GetRoom()
                local center = room:GetCenterPos()
                ctx.choices = {}
                for i, dx in ipairs({ -60, 60 }) do
                    local at = room:FindFreePickupSpawnPosition(center + Vector(dx, -60), 0, true)
                    local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
                        CollectibleType.COLLECTIBLE_BREAKFAST, at, Vector.Zero, nil):ToPickup()
                    pickup.OptionsPickupIndex = 77
                    ctx.choices[i] = EntityPtr(pickup)
                end
                ctx.cleanupFns = ctx.cleanupFns or {}
                table.insert(ctx.cleanupFns, function()
                    for _, ref in ipairs(ctx.choices or {}) do
                        if ref.Ref and ref.Ref:Exists() then ref.Ref:Remove() end
                    end
                end)
            end)
            plan.wait(4)
            plan.check("Atropos, held by the crab, unlinks the choice", function(_, ctx)
                local indexes = {}
                local unlinked = true
                for i, ref in ipairs(ctx.choices) do
                    local pickup = ref.Ref and ref.Ref:ToPickup()
                    indexes[i] = pickup and tostring(pickup.OptionsPickupIndex) or "gone"
                    if not pickup or pickup.OptionsPickupIndex ~= 0 then unlinked = false end
                end
                return unlinked, "OptionsPickupIndex=" .. table.concat(indexes, ",")
            end)
            plan.act(function(_, ctx)
                for _, ref in ipairs(ctx.choices) do if ref.Ref and ref.Ref:Exists() then ref.Ref:Remove() end end
                ctx.choices = {}
            end)
        end
    end
end)

return C
