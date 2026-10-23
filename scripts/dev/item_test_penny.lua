local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Two Faced Penny: which item each coin reserves and what every clean floor pays,
-- across real pedestal pickups, direct grants, removals, extra coins, a grant
-- another mod makes during a pickup, wisps, smelted trinkets, D4, Glowing
-- Hourglass, Kronos and Thurisaz conversions, golden pedestals, shop and devil
-- deals and XL floors. The oracle is the EID: the first non-active item gained
-- after a coin is that coin's item, copied once at once and once more per clean
-- floor. `hit_kinds` and `hit_icons` also check the shared hit rule
-- (scripts/lib/player_hits.lua) with each engine damage source.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local Hits = require("scripts.lib.player_hits")
local TimerClock = require("scripts.lib.timer_clock")

local KEY = "TWO_FACED_PENNY"
local priority = rawget(_G, "CallbackPriority")
-- Engine enums are read when a case is built, not when the module loads.
local C, A, B, X, FAMILIAR, ACTIVE, TRINKET, NAMES, DEVIL_PRICE
local SPOTS = { { -140, -60 }, { 140, -60 }, { -140, 60 }, { 140, 60 } }

local function resolve()
    C = CollectibleType
    A, B, X = C.COLLECTIBLE_SAD_ONION, C.COLLECTIBLE_WOODEN_SPOON, C.COLLECTIBLE_SPOON_BENDER
    FAMILIAR, ACTIVE = C.COLLECTIBLE_BROTHER_BOBBY, C.COLLECTIBLE_D6
    TRINKET = TrinketType.TRINKET_PAPER_CLIP
    DEVIL_PRICE = PickupPrice and PickupPrice.PRICE_ONE_HEART
    NAMES = {}
    for label, id in pairs({ onion = A, spoon = B, bender = X, bobby = FAMILIAR, d6 = ACTIVE }) do
        NAMES[id] = label
    end
end

-- Every add while a case runs, for the DIAG trail (~ repeat pickup, @ the item
-- in the player's pickup queue, w wisp or innate), and a stand-in for another
-- mod that answers one acquisition by granting a second item on the spot.
local events = { on = false, list = {} }
local nested

if ModCallbacks.MC_POST_ADD_COLLECTIBLE and type(ConchBlessing.AddPriorityCallback) == "function" then
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, priority and priority.IMPORTANT or -200,
        function(_, id, _, firstTime, _, _, player)
            if not events.on then return end
            local ok, queued = pcall(function() return player.QueuedItem.Item end)
            events.list[#events.list + 1] = tostring(id) .. (firstTime and "" or "~")
                .. (ok and queued and ("@" .. tostring(queued.ID)) or "")
        end)
    -- One step before default priority: a mod that loaded before this one.
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, -1, function(_, id, _, _, _, _, player)
        local rule = nested
        if not rule or rule.done or id ~= rule.trigger or not player then return end
        rule.done = true
        player:AddCollectible(rule.grant, 0, true)
    end)
end
-- Damage the player takes while a hit case runs (the flags the engine passed,
-- whether it landed), and a stand-in for another mod cancelling the next hit.
local damage = { on = false, list = {}, landed = 0, cancel = 0 }
if ModCallbacks.MC_ENTITY_TAKE_DMG and type(ConchBlessing.AddPriorityCallback) == "function" then
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, priority and priority.IMPORTANT or -200,
        function(_, entity, amount, flags, source)
            if not damage.on or not (entity and entity:ToPlayer()) then return end
            local row = { flags = math.tointeger(tonumber(flags) or 0) or 0, amount = amount,
                source = source and source.Type or -1 }
            damage.list[#damage.list + 1] = row
            if damage.cancel > 0 then
                damage.cancel = damage.cancel - 1
                row.cancelled = true
                return false
            end
        end, EntityType and EntityType.ENTITY_PLAYER)
end
if ModCallbacks.MC_POST_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG, function(_, entity)
        if damage.on and entity and entity:ToPlayer() then damage.landed = damage.landed + 1 end
    end)
end

if ModCallbacks.MC_POST_TRIGGER_COLLECTIBLE_ADDED then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TRIGGER_COLLECTIBLE_ADDED, function(_, _, id, _, wispOrInnate)
        if events.on and wispOrInnate == true then events.list[#events.list + 1] = "w" .. tostring(id) end
    end)
end

local function count(player, id) return player:GetCollectibleNum(id, true) end

local function counts(player, penny)
    local now = { [penny] = count(player, penny) }
    for id in pairs(NAMES) do now[id] = count(player, id) end
    return now
end

local function slots(player)
    local M = ConchBlessing.twofacedpenny
    local state = M._test and M._test.state(player) or player:GetData().__twofacedpenny
    local list = {}
    for _, slot in ipairs(state and state.slots or {}) do list[#list + 1] = tostring(slot.itemId or "open") end
    return #list, table.concat(list, ",")
end

-- Copies gained since the case started, per watched item.
-- Arguments after the label are id, copies pairs.
local function expect(plan, penny, label, ...)
    local n, wanted = select("#", ...), { ... }
    plan.check(label, function(player, ctx)
        local now, parts, ok = counts(player, penny), {}, true
        for i = 1, n, 2 do
            local id, delta = wanted[i], wanted[i + 1]
            local actual = now[id] - ctx.start[id]
            parts[#parts + 1] = (NAMES[id] or "coin") .. "=" .. actual .. "/" .. delta
            if actual ~= delta then ok = false end
        end
        table.sort(parts)
        return ok, table.concat(parts, " ") .. " (actual/expected)"
    end)
end

local function give(plan, ...)
    local ids = { ... }
    plan.act(function(player) for _, id in ipairs(ids) do player:AddCollectible(id, 0, true) end end)
    plan.wait(3)
end

local function remove(plan, id, times)
    plan.act(function(player) for _ = 1, times do player:RemoveCollectible(id) end end)
    plan.wait(3)
end

-- arrived(player, ctx) replaces the default "count rose and the queue is empty".
local function pickUp(plan, id, arrived)
    plan.act(function(player, ctx)
        H.suppressRandomGoldenPedestals(ctx)
        ctx.spot = (ctx.spot or 0) % #SPOTS + 1
        local position = Game():GetRoom():GetCenterPos() + Vector(SPOTS[ctx.spot][1], SPOTS[ctx.spot][2])
        ctx.pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, position,
            Vector.Zero, nil):ToPickup()
        ctx.pickup.Wait = 0
        ctx.before = count(player, id)
        player.Position = position
    end)
    plan.waitUntil(function(player, ctx)
        if not player:IsItemQueueEmpty() then return false end
        if arrived then return arrived(player, ctx) end
        return count(player, id) > ctx.before
    end, 180, "real pedestal pickup finishes")
    plan.act(function(player, ctx)
        if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end
        ctx.pickup = nil
        player.Position = Game():GetRoom():GetCenterPos()
    end)
    plan.wait(3)
end

local function trail(plan, label)
    plan.note(label, function(player)
        local text = table.concat(events.list, " ")
        events.list = {}
        local n, list = slots(player)
        return (text ~= "" and text or "none") .. " | slots " .. n .. " [" .. list .. "]"
    end)
end

local function case(name, build)
    S.add(KEY, name, { conditions = true }, function(plan, penny)
        resolve()
        plan.act(function(player, ctx)
            ctx.start = counts(player, penny)
            events.list, events.on, nested = {}, true, nil
            ctx.cleanupFns = ctx.cleanupFns or {}
            ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
                events.on, nested = false, nil
                damage.on, damage.cancel = false, 0
            end
        end)
        build(plan, penny)
        trail(plan, "adds and slots at the end")
    end)
end

-- The order the report describes: the coin, then two items off pedestals.
case("pickup_order", function(plan, penny)
    pickUp(plan, penny)
    pickUp(plan, A)
    expect(plan, penny, "the first item after the coin is copied once", penny, 1, A, 2)
    pickUp(plan, B)
    expect(plan, penny, "the second item is not copied", A, 2, B, 1)
    trail(plan, "adds after the two pickups")
    S.newFloor(plan, 2)
    expect(plan, penny, "a clean floor pays the first item, not the second", A, 3, B, 1)
    pickUp(plan, X)
    expect(plan, penny, "an item picked up after the payout is not copied", A, 3, X, 1)
    S.newFloor(plan, 3)
    expect(plan, penny, "every clean floor pays the same item again", A, 4, B, 1, X, 1)
end)

case("direct_order", function(plan, penny)
    give(plan, penny)
    give(plan, ACTIVE)
    give(plan, A)
    give(plan, B)
    expect(plan, penny, "the active is skipped, the first passive copied, the second not", ACTIVE, 1, A, 2, B, 1)
    S.newFloor(plan, 2)
    expect(plan, penny, "a clean floor pays the first passive only", ACTIVE, 1, A, 3, B, 1)
end)

case("active_pedestal", function(plan, penny)
    pickUp(plan, penny)
    pickUp(plan, ACTIVE)
    pickUp(plan, A)
    expect(plan, penny, "a picked-up active leaves the coin for the next passive", ACTIVE, 1, A, 2)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays the passive", ACTIVE, 1, A, 3)
end)

case("familiar_first", function(plan, penny)
    give(plan, penny)
    pickUp(plan, FAMILIAR)
    give(plan, A)
    expect(plan, penny, "a familiar item is the coin's item", FAMILIAR, 2, A, 1)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays the familiar item", FAMILIAR, 3, A, 1)
end)

case("same_update", function(plan, penny)
    give(plan, penny, A, B)
    expect(plan, penny, "coin and two items in one update copy the first item", A, 2, B, 1)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays the first item", A, 3, B, 1)
end)

case("hit_floor", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    H.hit(plan)
    S.newFloor(plan, 2)
    expect(plan, penny, "a floor with a hit pays nothing", A, 2)
    S.newFloor(plan, 3)
    expect(plan, penny, "the next clean floor pays again", A, 3)
end)

-- A second coin reserving its item after a hit must not clear that hit for
-- the first coin. Whether the late coin's own floor counts is a design choice
-- the EID leaves open, so that part is recorded, not judged.
case("hit_then_new_coin", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    S.newFloor(plan, 2)
    expect(plan, penny, "the first clean floor pays", A, 3)
    H.hit(plan)
    give(plan, penny)
    give(plan, B)
    expect(plan, penny, "the second coin copies its own item", A, 3, B, 2)
    S.newFloor(plan, 3)
    expect(plan, penny, "the hit floor pays nothing for the first coin", A, 3)
    plan.note("second coin, reserved after the hit on that floor", function(player, ctx)
        return "spoon copies " .. (count(player, B) - ctx.start[B]) .. " (2 = not paid, 3 = paid)"
    end)
    S.newFloor(plan, 4)
    expect(plan, penny, "the next clean floor pays the first coin again", A, 4)
end)

case("hit_before_coin", function(plan, penny)
    H.hit(plan)
    give(plan, penny)
    give(plan, A)
    S.newFloor(plan, 2)
    plan.note("hit on the floor before the coin was owned", function(player, ctx)
        return "onion copies " .. (count(player, A) - ctx.start[A]) .. " (2 = not paid, 3 = paid)"
    end)
end)

case("two_coins_first", function(plan, penny)
    give(plan, penny)
    give(plan, penny)
    give(plan, A)
    expect(plan, penny, "both coins copy the same next item", penny, 2, A, 3)
    give(plan, B)
    expect(plan, penny, "a later item is not copied", A, 3, B, 1)
    S.newFloor(plan, 2)
    expect(plan, penny, "each coin pays one copy", A, 5, B, 1)
end)

case("second_coin_later", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    give(plan, penny)
    give(plan, B)
    expect(plan, penny, "each coin copies the item after it", penny, 2, A, 2, B, 2)
    S.newFloor(plan, 2)
    expect(plan, penny, "each coin pays its own item", A, 3, B, 3)
end)

case("reserved_item_removed", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    remove(plan, A, 2)
    give(plan, B)
    expect(plan, penny, "losing the item does not hand the coin to the next one", A, 0, B, 1)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor still pays the coin's item", A, 1, B, 1)
end)

case("coin_lost_and_regained", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    remove(plan, penny, 1)
    S.newFloor(plan, 2)
    expect(plan, penny, "without the coin the floor pays nothing", penny, 0, A, 2)
    give(plan, penny)
    give(plan, B)
    expect(plan, penny, "a coin gained again copies the item after it", A, 2, B, 2)
    S.newFloor(plan, 3)
    expect(plan, penny, "the floor pays the new coin's item", A, 2, B, 3)
end)

case("nested_grant", function(plan, penny)
    give(plan, penny)
    plan.act(function() nested = { trigger = A, grant = X } end)
    pickUp(plan, A)
    plan.act(function() nested = nil end)
    expect(plan, penny, "the picked-up item is copied, not the one granted along with it", A, 2, X, 1)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays the picked-up item", A, 3, X, 1)
end)

case("wisp_and_trinket", function(plan, penny)
    give(plan, penny)
    plan.act(function(player, ctx) ctx.wisp = player:AddItemWisp(A, player.Position) end)
    plan.wait(3)
    plan.act(function(player)
        player:AddTrinket(TRINKET, false)
        player:UseActiveItem(C.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM, -1)
    end)
    plan.wait(3)
    plan.check("the trinket is smelted once and not copied", function(player)
        return player:GetTrinket(0) == 0 and player:GetTrinketMultiplier(TRINKET) == 1,
            "held=" .. player:GetTrinket(0) .. " multiplier=" .. player:GetTrinketMultiplier(TRINKET)
    end)
    give(plan, B)
    expect(plan, penny, "a wisp and a smelted trinket leave the coin for the next item", A, 0, B, 2)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays that item", A, 0, B, 3)
    plan.check("the smelted trinket is still single", function(player)
        return H.expect(player:GetTrinketMultiplier(TRINKET), 1)
    end)
    plan.act(function(_, ctx) if ctx.wisp and ctx.wisp:Exists() then ctx.wisp:Remove() end end)
end)

-- D4 rerolls the coin too, so the floor owes one copy of the reserved item per
-- coin still owned; nothing rerolled in may take a reservation.
case("d4_reroll", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    plan.act(function(player) player:UseActiveItem(C.COLLECTIBLE_D4, UseFlag.USE_NOANIM, -1) end)
    plan.wait(5)
    trail(plan, "adds during the reroll")
    plan.check("a reroll reserves nothing new", function(player)
        local coins, n, list = count(player, penny), slots(player)
        return n == coins and not list:find("open"), "coins=" .. coins .. " slots=" .. n .. " [" .. list .. "]"
    end)
    plan.act(function(player, ctx) ctx.coins, ctx.onion = count(player, penny), count(player, A) end)
    S.newFloor(plan, 2)
    plan.check("the floor pays the reserved item once per coin left", function(player, ctx)
        return H.expect(count(player, A) - ctx.onion, ctx.coins)
    end)
end)

local function visitTreasure(plan)
    plan.act(function(player, ctx)
        local rooms = Game():GetLevel():GetRooms()
        local target
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if desc.Data and desc.Data.Type == RoomType.ROOM_TREASURE then target = desc; break end
        end
        assert(target, "no treasure room on this test floor")
        ctx.targetRoom = target.ListIndex
        Game():StartRoomTransition(target.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex == ctx.targetRoom end,
        180, "treasure room entered")
    plan.wait(10)
end

-- Rewinding to the previous floor restores what the player had there, so the
-- payout for leaving it must not be paid again on the way back or twice after.
case("hourglass_floor", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    plan.act(function(player) player:AddCollectible(C.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, false) end)
    visitTreasure(plan)
    S.newFloor(plan, 2)
    expect(plan, penny, "the clean floor pays once", A, 3)
    plan.act(function(player) H.use(player, C.COLLECTIBLE_GLOWING_HOUR_GLASS) end)
    plan.wait(90)
    plan.require("Glowing Hourglass went back to floor 1", function()
        local stage = Game():GetLevel():GetStage()
        if stage == 1 then return true, "stage 1" end
        return nil, "stage " .. stage .. "; this build did not rewind across the console floor change"
    end)
    expect(plan, penny, "the rewound floor has its earlier copies and pays nothing", A, 2)
    trail(plan, "adds around the rewind")
    S.newFloor(plan, 2)
    expect(plan, penny, "leaving it again pays exactly once", A, 3)
end)

local function flagNames(flags)
    local names = {}
    for name, bit in pairs(DamageFlag) do
        if type(bit) == "number" and bit ~= 0 and flags & bit == bit then
            names[#names + 1] = (name:gsub("^DAMAGE_", ""))
        end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, "|") or "none"
end

local function playerState(namespace, player)
    local module = ConchBlessing[namespace]
    return module and module.getPlayerState and module.getPlayerState(player) or {}
end

local function showsIcon(player, key)
    for _, shown in ipairs(Hits._test.shown(player) or {}) do
        if shown == key then return true end
    end
    return false
end

local function fullHealth(player)
    player:AddMaxHearts(12 - player:GetMaxHearts())
    player:AddHearts(24)
end

local function holdOn(player, ctx)
    if ctx.fixture and ctx.fixture:Exists() then player.Position = ctx.fixture.Position end
end

local function gridOf(room, kind)
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid and grid:GetType() == kind then return index end
    end
end

local function spikesUnder(player, ctx)
    local room = Game():GetRoom()
    local index = gridOf(room, GridEntityType.GRID_SPIKES)
    if not index then
        index = room:GetGridIndex(room:GetCenterPos())
        Isaac.GridSpawn(GridEntityType.GRID_SPIKES, 0, room:GetGridPosition(index), true)
    end
    ctx.spikes = room:GetGridPosition(index)
    player.Position = ctx.spikes
end

local function stayOnSpikes(player, ctx)
    if ctx.spikes then player.Position = ctx.spikes end
end

-- Every fixture is the engine's own source of that damage. hit=true loses the
-- floor's payout, hit=false keeps it; hit=nil is recorded, its rule still open.
local HIT_KINDS = {
    { name = "enemy projectile", hit = true, start = function(player, ctx)
        ctx.fixture = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, ProjectileVariant.PROJECTILE_NORMAL, 0,
            player.Position, Vector.Zero, nil)
    end },
    -- Enemy creep hurts through the effect itself (source type 1000). An
    -- owner-less creep deals no damage, so it belongs to a harmless test enemy.
    { name = "enemy creep", hit = true, start = function(player, ctx)
        ctx.owner = H.target(player)
        ctx.fixture = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.CREEP_RED, 0, player.Position, Vector.Zero,
            ctx.owner)
        if (ctx.fixture.CollisionDamage or 0) <= 0 then ctx.fixture.CollisionDamage = 1 end
    end, step = holdOn },
    { name = "fireplace", hit = true, start = function(player, ctx)
        ctx.fixture = Isaac.Spawn(EntityType.ENTITY_FIREPLACE, 0, 0, player.Position + Vector(30, 0), Vector.Zero, nil)
    end, step = holdOn },
    { name = "spikes", hit = true, start = spikesUnder, step = stayOnSpikes },
    { name = "own bomb", hit = true, start = function(player, ctx)
        ctx.fixture = Isaac.Spawn(EntityType.ENTITY_BOMB, BombVariant.BOMB_NORMAL, 0, player.Position, Vector.Zero, player)
        ctx.fixture:ToBomb():SetExplosionCountdown(0)
    end },
    { name = "Razor Blade", hit = false, start = function(player)
        player:UseActiveItem(C.COLLECTIBLE_RAZOR_BLADE, UseFlag.USE_NOANIM, -1)
    end },
    { name = "IV Bag", hit = false, start = function(player)
        player:UseActiveItem(C.COLLECTIBLE_IV_BAG, UseFlag.USE_NOANIM, -1)
    end },
    { name = "Blood Donation Machine", hit = false, start = function(player, ctx)
        ctx.fixture = Isaac.Spawn(EntityType.ENTITY_SLOT, 2, 0, player.Position + Vector(0, 40), Vector.Zero, nil)
    end, step = holdOn },
    { name = "Sacrifice Room spikes", hit = false, room = "s.sacrifice.0", roomType = "ROOM_SACRIFICE",
        start = spikesUnder, step = stayOnSpikes },
    { name = "hit another mod cancels", hit = false, applied = true, start = function(player, ctx)
        damage.cancel = 1
        ctx.fixture = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, ProjectileVariant.PROJECTILE_NORMAL, 0,
            player.Position, Vector.Zero, nil)
    end },
    { name = "Holy Mantle", start = function(player, ctx)
        player:AddCollectible(C.COLLECTIBLE_HOLY_MANTLE, 0, false)
        ctx.mantle = true
        ctx.fixture = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, ProjectileVariant.PROJECTILE_NORMAL, 0,
            player.Position, Vector.Zero, nil)
    end, done = function(player, ctx)
        return not player:GetEffects():HasCollectibleEffect(C.COLLECTIBLE_HOLY_MANTLE)
            or not (ctx.fixture and ctx.fixture:Exists())
    end },
}

local function hitKind(plan, kind, stage)
    plan.section(KEY .. " / hit_kinds / " .. kind.name)
    if kind.room then
        plan.act(function() Isaac.ExecuteCommand("goto " .. kind.room) end)
        plan.waitUntil(function()
            return Game():GetRoom():GetType() == RoomType[kind.roomType]
        end, 180, kind.name .. " room loaded")
        plan.wait(10)
    end
    if kind.applied then
        plan.require("REPENTOGON's applied-damage callback", function()
            return Hits.appliedDamage or nil, "without it a hit is counted before another mod can cancel it"
        end)
    end
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 180, "damage cooldown expires")
    plan.act(function(player, ctx)
        fullHealth(player)
        ctx.onion = count(player, A)
        damage.list, damage.landed, damage.on = {}, 0, true
        kind.start(player, ctx)
    end)
    plan.waitUntil(function(player, ctx)
        if kind.step then kind.step(player, ctx) end
        if kind.done then return kind.done(player, ctx) end
        return #damage.list > 0
    end, 150, kind.name .. " reaches the player")
    plan.wait(3)
    plan.note(kind.name .. " damage", function(player)
        local first = damage.list[1]
        damage.on = false
        if not first then return "no damage callback; landed=" .. damage.landed end
        return string.format("flags=%s amount=%s source=%d landed=%d%s counts=%s", flagNames(first.flags),
            tostring(first.amount), first.source, damage.landed, first.cancelled and " cancelled" or "",
            tostring(Hits.counts(first.flags)))
    end)
    if kind.hit ~= nil then
        plan.check(kind.name .. (kind.hit and " shows the coin's hit icon" or " shows no hit icon"), function(player)
            local shown = showsIcon(player, KEY)
            return shown == kind.hit, "icon shown=" .. tostring(shown)
        end)
    end
    plan.act(function(player, ctx)
        if ctx.fixture and ctx.fixture:Exists() then ctx.fixture:Remove() end
        if ctx.owner and ctx.owner:Exists() then ctx.owner:Remove() end
        ctx.fixture, ctx.spikes, ctx.owner = nil, nil, nil
        if ctx.mantle then player:RemoveCollectible(C.COLLECTIBLE_HOLY_MANTLE); ctx.mantle = nil end
    end)
    S.newFloor(plan, stage)
    if kind.hit == nil then
        plan.note(kind.name .. " floor payout", function(player, ctx)
            return "onion +" .. (count(player, A) - ctx.onion) .. " (0 = counted as a hit, 1 = not a hit)"
        end)
    else
        plan.check(kind.name .. (kind.hit and " is a hit: the floor pays nothing" or " is not a hit: the floor pays"),
            function(player, ctx) return H.expect(count(player, A) - ctx.onion, kind.hit and 0 or 1) end)
    end
end

-- One floor per damage source, so each payout shows on its own whether that
-- source counted as a hit.
case("hit_kinds", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    for index, kind in ipairs(HIT_KINDS) do
        hitKind(plan, kind, index % 2 == 1 and 2 or 1)
    end
end)

-- The other items that react to hits share the rule and show their own icons.
case("hit_icons", function(plan, penny)
    local keys = { KEY, "F_MINUS", "TIME_POWER", "TYRFING", "TIME_MONEY" }
    plan.act(function(player)
        player:AddCollectible(C.COLLECTIBLE_MOMS_PURSE, 0, false)
        player:AddTrinket(ConchBlessing.ItemData.F_MINUS.id, false)
        player:AddTrinket(ConchBlessing.ItemData.TIME_POWER.id, false)
        for _, key in ipairs({ "TYRFING", "TIME_MONEY" }) do
            player:AddCollectible(ConchBlessing.ItemData[key].id, 0, false)
        end
        player:AddCollectible(penny, 0, true)
    end)
    plan.wait(5)
    for _, phase in ipairs({ HIT_KINDS[1], HIT_KINDS[6] }) do
        plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 180, "damage cooldown expires")
        plan.wait(31)
        plan.act(function(player, ctx)
            fullHealth(player)
            ctx.money = playerState("timemoney", player).pendingPenalty or 0
            damage.list, damage.on = {}, true
            phase.start(player, ctx)
        end)
        plan.waitUntil(function() return #damage.list > 0 end, 150, phase.name .. " reaches the player")
        plan.wait(3)
        plan.check(phase.name .. (phase.hit and " shows every holder's icon" or " shows no icon"), function(player)
            local missing = {}
            for _, key in ipairs(keys) do
                if showsIcon(player, key) ~= phase.hit then missing[#missing + 1] = key end
            end
            return #missing == 0, "wrong: " .. (#missing > 0 and table.concat(missing, ",") or "none")
                .. "; shown=" .. table.concat(Hits._test.shown(player) or {}, ",")
        end)
        plan.check(phase.name .. (phase.hit and " reaches every holder" or " reaches none"), function(player, ctx)
            local power = playerState("timepowertrinket", player)
            local money = playerState("timemoney", player)
            local minus = not ConchBlessing.minuschain.noHit(player)
            local paused = (power.pausedUntilFrame or 0) > TimerClock.now()
            local fined = (money.pendingPenalty or 0) > ctx.money
            local ok = minus == phase.hit and fined == phase.hit and (paused == phase.hit or not phase.hit)
            return ok, string.format("minus marked=%s time paused=%s money penalty=%s",
                tostring(minus), tostring(paused), tostring(fined))
        end)
        plan.act(function(player, ctx)
            damage.on = false
            if ctx.fixture and ctx.fixture:Exists() then ctx.fixture:Remove() end
            ctx.fixture = nil
            ConchBlessing.minuschain.setNoHit(player, true)
        end)
    end
    plan.section(KEY .. " / hit_icons / A- demotion")
    plan.act(function(player)
        player:TryRemoveTrinket(ConchBlessing.ItemData.F_MINUS.id)
        player:AddTrinket(ConchBlessing.ItemData.A_MINUS.id, false)
    end)
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 180, "damage cooldown expires")
    plan.wait(31)
    plan.act(function(player, ctx)
        fullHealth(player)
        damage.list, damage.on = {}, true
        HIT_KINDS[1].start(player, ctx)
    end)
    plan.waitUntil(function() return #damage.list > 0 end, 150, "enemy projectile reaches the player")
    plan.wait(3)
    plan.check("a hit demotes A- and shows its icon", function(player)
        return showsIcon(player, "A_MINUS") and not player:HasTrinket(ConchBlessing.ItemData.A_MINUS.id),
            "icon=" .. tostring(showsIcon(player, "A_MINUS")) .. " still held=" .. tostring(player:HasTrinket(ConchBlessing.ItemData.A_MINUS.id))
    end)
    plan.act(function(_, ctx) damage.on = false; if ctx.fixture and ctx.fixture:Exists() then ctx.fixture:Remove() end end)
end)

local function waitAbsorbed(plan, familiar, absorbed, technology)
    plan.waitUntil(function(player, ctx)
        local held = count(player, familiar)
        local done = ConchBlessing.kronos._getAbsorbedCount(player, familiar)
        local tech = count(player, C.COLLECTIBLE_TECHNOLOGY) - ctx.tech
        return held == 0 and done == absorbed and tech == technology,
            "held=" .. held .. " absorbed=" .. done .. " technology=" .. tech
    end, 150, "Kronos absorbs " .. absorbed .. " and converts them")
end

-- Kronos absorbs the picked-up familiar and its coin copy; its conversion items
-- come after the coin chose, so the coin keeps the familiar.
case("kronos_conversion", function(plan, penny)
    plan.act(function(player, ctx)
        ctx.tech = count(player, C.COLLECTIBLE_TECHNOLOGY)
        player:AddCollectible(ConchBlessing.ItemData.KRONOS.id, 0, false)
    end)
    plan.wait(5)
    give(plan, penny)
    pickUp(plan, C.COLLECTIBLE_ROBO_BABY, function(player)
        return count(player, C.COLLECTIBLE_ROBO_BABY) + ConchBlessing.kronos._getAbsorbedCount(player, C.COLLECTIBLE_ROBO_BABY) >= 2
    end)
    waitAbsorbed(plan, C.COLLECTIBLE_ROBO_BABY, 2, 2)
    plan.check("the coin keeps the picked-up familiar, not its conversion", function(player)
        local _, list = slots(player)
        return list == tostring(C.COLLECTIBLE_ROBO_BABY), "slots [" .. list .. "]"
    end)
    S.newFloor(plan, 2)
    waitAbsorbed(plan, C.COLLECTIBLE_ROBO_BABY, 3, 3)
    plan.act(function(player) player:RemoveCollectible(ConchBlessing.ItemData.KRONOS.id) end)
    plan.waitUntil(function(player) return count(player, C.COLLECTIBLE_ROBO_BABY) == 3 end, 150,
        "losing Kronos returns all three familiars")
    plan.wait(3)
    plan.check("Kronos takes back only its conversions; the coin's copies stay", function(player, ctx)
        local tech = count(player, C.COLLECTIBLE_TECHNOLOGY) - ctx.tech
        local _, list = slots(player)
        return tech == 0 and list == tostring(C.COLLECTIBLE_ROBO_BABY),
            "technology=" .. tech .. " slots [" .. list .. "]"
    end)
end)

-- Thurisaz devours a familiar the player already had and hands over its
-- conversion item. Whether that item should take an open coin is not decided.
case("thurisaz_conversion", function(plan, penny)
    plan.act(function(player, ctx)
        ctx.tech = count(player, C.COLLECTIBLE_TECHNOLOGY)
        player:AddCollectible(C.COLLECTIBLE_ROBO_BABY, 0, false)
    end)
    plan.wait(10)
    give(plan, penny)
    plan.act(function(player)
        player:UseCard(ConchBlessing.PocketData.THURISAZ.id, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER)
    end)
    plan.waitUntil(function(player) return count(player, C.COLLECTIBLE_ROBO_BABY) == 0 end, 150, "the rune devours Robo-Baby")
    plan.wait(5)
    plan.note("open coin when the rune converts", function(player, ctx)
        local _, list = slots(player)
        return "technology +" .. (count(player, C.COLLECTIBLE_TECHNOLOGY) - ctx.tech) .. " slots [" .. list
            .. "] (technology=" .. C.COLLECTIBLE_TECHNOLOGY .. ")"
    end)
    plan.check("the rune's conversion is granted once", function(player)
        local save = ConchBlessing.SaveManager.GetRunSave(player)
        local grants = save and save.thurisaz and save.thurisaz.grants or {}
        return H.expect(grants["fam_" .. C.COLLECTIBLE_ROBO_BABY] or 0, 1)
    end)
    plan.act(function(player, ctx) ctx.techBefore = count(player, C.COLLECTIBLE_TECHNOLOGY) end)
    S.newFloor(plan, 2)
    plan.note("floor payout after the rune", function(player, ctx)
        return "technology +" .. (count(player, C.COLLECTIBLE_TECHNOLOGY) - ctx.techBefore)
    end)
end)

-- Golden Items (optional mod): a golden passive gives a second copy after the
-- pickup, and a golden coin counts as two coins.
case("golden_pedestal", function(plan, penny)
    local function provider()
        local golden = rawget(_G, "GoldenItems")
        local item = golden and golden.Pickup and golden.Pickup.GOLDEN_ITEM
        return item and type(item.TurnItemGold) == "function" and item or nil
    end
    plan.require("Golden Items installed", function()
        if provider() then return true, "GoldenItems.Pickup.GOLDEN_ITEM:TurnItemGold" end
        return nil, "Golden Items not loaded"
    end)
    local function goldenPickUp(id, wanted)
        plan.act(function(player, ctx)
            local position = Game():GetRoom():GetCenterPos() + Vector(140, 0)
            ctx.pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, position,
                Vector.Zero, nil):ToPickup()
            provider():TurnItemGold(ctx.pickup, false)
            ctx.pickup.Wait = 0
            ctx.before = count(player, id)
            player.Position = position
        end)
        plan.waitUntil(function(player, ctx)
            return count(player, id) - ctx.before >= wanted and player:IsItemQueueEmpty()
        end, 180, "golden pickup and its second copy arrive")
        plan.act(function(player, ctx)
            if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end
            ctx.pickup = nil
            player.Position = Game():GetRoom():GetCenterPos()
        end)
        plan.wait(5)
    end
    goldenPickUp(penny, 2)
    expect(plan, penny, "a golden coin gives two coins", penny, 2)
    goldenPickUp(A, 4)
    expect(plan, penny, "a golden item: the item, its golden copy and one copy per coin", A, 4)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays one copy per coin", A, 6)
end)

local function backToStart(plan)
    plan.act(function(player, ctx)
        ctx.startIndex = Game():GetLevel():GetStartingRoomIndex()
        Game():StartRoomTransition(ctx.startIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx) return Game():GetLevel():GetCurrentRoomIndex() == ctx.startIndex end,
        180, "back in the starting room")
    plan.wait(10)
end

local function clearPedestals()
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
        entity:Remove()
    end
end

-- Rewinding the room where the coin chose its item reopens the coin with the
-- inventory, and the next pickup is copied once.
case("hourglass_room", function(plan, penny)
    plan.act(function(player) player:AddCollectible(C.COLLECTIBLE_GLOWING_HOUR_GLASS, 0, false) end)
    give(plan, penny)
    visitTreasure(plan)
    plan.act(function(_, ctx) ctx.treasure = ctx.targetRoom; clearPedestals() end)
    backToStart(plan)
    pickUp(plan, A)
    expect(plan, penny, "the coin copies the item", A, 2)
    plan.act(function(player) H.use(player, C.COLLECTIBLE_GLOWING_HOUR_GLASS) end)
    plan.waitUntil(function(_, ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex == ctx.treasure end,
        240, "Glowing Hourglass goes back one room")
    plan.wait(20)
    plan.act(clearPedestals)
    expect(plan, penny, "the rewind takes the item and its copy back", A, 0)
    plan.check("the rewind reopens the coin", function(player)
        local n, list = slots(player)
        return n == 1 and list == "open", "slots " .. n .. " [" .. list .. "]"
    end)
    pickUp(plan, A)
    expect(plan, penny, "picking it up again copies it once", A, 2)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays once", A, 3)
end)

local function buy(plan, id, price, setup, label)
    plan.act(function(player, ctx)
        H.suppressRandomGoldenPedestals(ctx)
        local position = Game():GetRoom():GetCenterPos() + Vector(140, 0)
        ctx.pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, position,
            Vector.Zero, nil):ToPickup()
        ctx.pickup.Price, ctx.pickup.ShopItemId, ctx.pickup.AutoUpdatePrice = price, -1, false
        ctx.pickup.Wait = 0
        setup(player, ctx)
        ctx.before = count(player, id)
        player.Position = position
    end)
    plan.waitUntil(function(player, ctx)
        return count(player, id) > ctx.before and player:IsItemQueueEmpty()
    end, 180, label)
    plan.act(function(player, ctx)
        if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end
        ctx.pickup = nil
        player.Position = Game():GetRoom():GetCenterPos()
    end)
    plan.wait(3)
end

case("shop_purchase", function(plan, penny)
    give(plan, penny)
    buy(plan, A, 15, function(player) player:AddCoins(15 - player:GetNumCoins()) end, "15-coin shop item bought")
    expect(plan, penny, "a bought item is the coin's item", A, 2)
    plan.check("paid once", function(player) return H.expect(player:GetNumCoins(), 0) end)
    S.newFloor(plan, 2)
    expect(plan, penny, "the floor pays it", A, 3)
end)

case("devil_deal", function(plan, penny)
    give(plan, penny)
    buy(plan, A, DEVIL_PRICE, function(player, ctx)
        player:AddMaxHearts(6 - player:GetMaxHearts())
        player:AddHearts(12)
        ctx.maxHearts = player:GetMaxHearts()
    end, "one-heart devil deal taken")
    expect(plan, penny, "a devil deal is the coin's item", A, 2)
    plan.check("paid one heart container", function(player, ctx)
        return H.expect(player:GetMaxHearts(), ctx.maxHearts - 2)
    end)
    S.newFloor(plan, 2)
    expect(plan, penny, "paying the deal is not a hit: the floor pays", A, 3)
end)

-- Curse of the Labyrinth joins two floors into one: one payout for it.
case("xl_floor", function(plan, penny)
    give(plan, penny)
    give(plan, A)
    plan.require("a permanent Labyrinth seed effect", function()
        if SeedEffect and SeedEffect.SEED_PERMANENT_CURSE_LABYRINTH then return true, "SEED_PERMANENT_CURSE_LABYRINTH" end
        return nil, "SeedEffect missing"
    end)
    plan.act(function(_, ctx)
        local seeds = Game():GetSeeds()
        seeds:AddSeedEffect(SeedEffect.SEED_PERMANENT_CURSE_LABYRINTH)
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            Game():GetSeeds():RemoveSeedEffect(SeedEffect.SEED_PERMANENT_CURSE_LABYRINTH)
        end
    end)
    S.newFloor(plan, 3)
    plan.require("the new floor is XL", function()
        if Game():GetLevel():GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0 then return true, "Curse of the Labyrinth" end
        return nil, "Curse of the Labyrinth did not apply"
    end)
    expect(plan, penny, "leaving floor 1 pays once", A, 3)
    S.newFloor(plan, 5)
    expect(plan, penny, "leaving the XL floor pays once", A, 4)
end)

return S
