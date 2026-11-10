local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 묘 (Rabbit): the lifecycle contract and its isolated cases. Every death is a
-- real lethal hit through the engine's damage path, every revive the engine's
-- own (REPENTOGON's MC_PRE_TRIGGER_PLAYER_DEATH), every Raw Liver an engine
-- acquisition, every room reached by a real transition, the rock broken by the
-- engine's own Room:DestroyGrid, the ladder walked onto and the crawlspace's
-- passage walked through into the black market, where the Raw Liver is bought
-- by touch. Real Continue stays a manual check.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local LevelRooms = require("scripts.lib.level_rooms")
local C = {}

local function rabbit() return ConchBlessing.rabbit end
local function T() return rabbit()._test end
local function oneUp() return CollectibleType.COLLECTIBLE_1UP end
local function rawLiver() return CollectibleType.COLLECTIBLE_RAW_LIVER end

local function effectNum(player, id)
    return player:GetEffects():GetCollectibleEffectNum(id)
end

-- Every count of livers the item keeps: at hand, the effect and the HUD's extra lives.
local function counts(player, id)
    return string.format("livers=%d effect=%d extraLives=%s rawLiver=%d", rabbit().livers(player), effectNum(player, id),
        type(player.GetExtraLives) == "function" and tostring(player:GetExtraLives()) or "?",
        player:GetCollectibleNum(rawLiver(), true))
end

C.RABBIT = { stage = function(plan, id, n)
    plan.check("holding it gives no liver by itself", function(player)
        return rabbit().livers(player) == 0 and effectNum(player, id) == 0, counts(player, id)
    end)
end }

local function requireModule(plan)
    plan.require("Rabbit module, REPENTOGON's death callback and the crawlspace RoomConfig", function()
        local module = rabbit()
        return module and module._test and ModCallbacks.MC_PRE_TRIGGER_PLAYER_DEATH
            and type(RoomConfig) == "table" and type(RoomConfig.GetRoomByStageTypeAndVariant) == "function" and true
            or nil, "module, MC_PRE_TRIGGER_PLAYER_DEATH or RoomConfig missing"
    end)
end

-- A fresh, curse-free floor with the holder in its start room: Curse of the
-- Maze would send a room transition elsewhere.
local function setup(plan, id, copies, extra)
    requireModule(plan)
    plan.act(function(player, ctx)
        local level = Game():GetLevel()
        if type(level.RemoveCurses) == "function" then level:RemoveCurses(level:GetCurses()) end
        for _, item in ipairs(extra and extra.before or {}) do player:AddCollectible(item, 0, true) end
        for _ = 1, copies do player:AddCollectible(id, 0, false) end
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() ctx.expectedDeathFrames = nil end)
        T().resetEvidence()
    end)
    plan.wait(4)
    -- Raw Livers taken after Rabbit (one pickup at a time, as in play)
    plan.act(function(player)
        for _, item in ipairs(extra and extra.after or {}) do player:AddCollectible(item, 0, true) end
    end)
    plan.wait(4)
end

-- A real lethal hit from half a red heart. The engine plays the death and
-- revives the holder (by a liver or a vanilla revive).
local function die(plan, label)
    -- a revive leaves a few seconds of invincibility: the next lethal hit
    -- must wait for it to end, or it lands on nothing
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 400, "no invincibility left")
    plan.act(function(player, ctx)
        ctx.expectedDeathFrames = 500
        ctx.deathRoom = Game():GetLevel():GetCurrentRoomIndex()
        player:AddSoulHearts(-player:GetSoulHearts())
        player:AddBoneHearts(-player:GetBoneHearts())
        player:AddHearts(1 - player:GetHearts())
        player:TakeDamage(2, DamageFlag.DAMAGE_INVINCIBLE, EntityRef(player), 0)
    end)
    plan.waitUntil(function(player)
        return not player:IsDead() and player:GetHearts() + player:GetSoulHearts() > 0
    end, 500, label)
    plan.act(function(_, ctx) ctx.expectedDeathFrames = nil end)
    plan.wait(2)
end

-- Where the hidden rock should be: the ordinary rooms exactly four doors from
-- the start room, else the farthest ones, measured independently here.
local function expectedTargets(level)
    local distance = LevelRooms.distances(level, level:GetStartingRoomIndex())
    local exact, farthest, best = {}, {}, -1
    for index, d in pairs(distance) do
        local desc = d > 0 and LevelRooms.roomAt(level, index)
        if desc and desc.SafeGridIndex == index and desc.Data.Type == RoomType.ROOM_DEFAULT then
            if d == 4 then exact[index] = true end
            if d < 4 then
                if d > best then best, farthest = d, { [index] = true } elseif d == best then farthest[index] = true end
            end
        end
    end
    return next(exact) and exact or farthest, distance
end

local function clearEnemies()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc and npc:IsActiveEnemy(false) then npc:Remove() end
    end
end

local function goTo(plan, label, target)
    plan.act(function(player, ctx)
        ctx.goal = target(ctx)
        Game():StartRoomTransition(ctx.goal, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, 0)
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomIndex() == ctx.goal and RoomTransition.GetTransitionMode() == 0
    end, 240, label)
    plan.act(function(player)
        clearEnemies()
        player.Position = Game():GetRoom():GetCenterPos()
    end)
    plan.wait(6)
end

local function market() return rabbit().market() or {} end
local function rockRoom() return market().room end

-- The hidden rock is chosen once the holder is on the floor.
local function rockChosen(plan)
    plan.waitUntil(function() return rockRoom() ~= nil end, 30, "the floor's hidden rock is chosen")
end

-- Breaks the hidden rock with the engine's own DestroyGrid and waits for the ladder.
local function breakRock(plan)
    plan.act(function(_, ctx)
        local m = market()
        ctx.destroyed = Game():GetRoom():DestroyGrid(m.grid, true)
    end)
    plan.waitUntil(function() return market().stairs == true end, 60, "the ladder opens")
    plan.wait(4)
end

-- Down the ladder as a player goes: a new ladder takes nobody for a moment, and
-- not someone who stayed on it (the engine's own guard against falling in at
-- once), so the player waits two cells off it and then walks onto it.
local function downLadder(plan)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        ctx.ladderAt = room:GetGridPosition(market().grid)
        ctx.from = Game():GetLevel():GetCurrentRoomIndex()
        clearEnemies()
        local off = room:FindFreeTilePosition(ctx.ladderAt + Vector(0, 80), 0)
        if off:Distance(ctx.ladderAt) < 60 then off = room:FindFreeTilePosition(ctx.ladderAt + Vector(80, 0), 0) end
        player.Position, player.Velocity = off, Vector.Zero
    end)
    plan.wait(45)
    plan.waitUntil(function(player, ctx)
        if Game():GetLevel():GetCurrentRoomIndex() ~= ctx.from then return RoomTransition.GetTransitionMode() == 0 end
        local away = ctx.ladderAt - player.Position
        if away:Length() > 2 then player.Velocity = away:Resized(math.min(4, away:Length())) end
        local grid = Game():GetRoom():GetGridEntity(market().grid)
        return false, string.format("still above the ladder: type=%s state=%s distance=%.0f", tostring(grid and grid:GetType()),
            tostring(grid and grid.State), away:Length())
    end, 240, "down the ladder")
    plan.wait(10)
end

-- Along the crawlspace's floor to its right-hand passage, into the black market.
local function throughPassage(plan)
    plan.act(function(_, ctx) ctx.crawl = Game():GetLevel():GetCurrentRoomIndex() end)
    plan.waitUntil(function(player, ctx)
        if Game():GetLevel():GetCurrentRoomIndex() ~= ctx.crawl then return RoomTransition.GetTransitionMode() == 0 end
        player.Velocity = Vector(5, player.Velocity.Y)
        return false, "still in the crawlspace"
    end, 300, "through the passage")
    plan.wait(10)
end

-- A grid type's enum name, for the logs.
local function gridName(kind)
    for name, value in pairs(GridEntityType or {}) do
        if value == kind then return name end
    end
    return tostring(kind)
end

-- Whether a player can walk up to `cell` from the room's doors, measured here
-- on the room's own collision (independently of the item's helpers).
local function walkUpTo(cell)
    local room = Game():GetRoom()
    local width = room:GetGridWidth()
    local seen, queue, head = {}, {}, 1
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            local side = slot % 4
            local step = side == 0 and 1 or side == 1 and width or side == 2 and -1 or -width
            local inner = door:GetGridIndex() + step
            if not seen[inner] then seen[inner], queue[#queue + 1] = true, inner end
        end
    end
    while head <= #queue do
        local c = queue[head]
        head = head + 1
        local x = c % width
        for _, n in ipairs({ x > 0 and c - 1 or nil, x < width - 1 and c + 1 or nil, c - width, c + width }) do
            if n and n >= 0 and n < room:GetGridSize() and not seen[n]
                and room:GetGridCollision(n) == GridCollisionClass.COLLISION_NONE then
                seen[n] = true
                queue[#queue + 1] = n
            end
        end
    end
    local x = cell % width
    return (x > 0 and seen[cell - 1]) or (x < width - 1 and seen[cell + 1]) or seen[cell - width]
        or seen[cell + width] or false
end

-- How many rocks of the room a player can walk up to could carry the tracks,
-- counted here (a rock the item laid itself counts too).
local function ownRocks()
    local room = Game():GetRoom()
    local n = 0
    for cell = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(cell)
        if grid and T().kinds()[grid:GetType()] and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE
            and grid:GetSprite():GetAnimation():sub(1, 3) ~= "big" and walkUpTo(cell) then
            n = n + 1
        end
    end
    return n
end

-- One of the room's own rocks was chosen, or the item laid one because the
-- room had none a player could walk up to (then that rock is the only one).
local function ownChosen(m)
    if m.adopted == true then return T().evidence().placed == 0 end
    return m.adopted == false and ownRocks() == 1
end

-- The hidden rock as it stands: one of the room's own rocks (a kind the item
-- allows, intact, a player can walk up to) with its tracks drawn on it.
local function rockStands(m)
    local room = Game():GetRoom()
    local grid = m.grid and room:GetGridEntity(m.grid)
    local mark = T().mark()
    local kind = grid and grid:GetType()
    local ok = grid ~= nil and T().kinds()[kind] == true and kind == m.kind and T().intact(room, m.grid, m.kind)
        and walkUpTo(m.grid) and mark ~= nil and mark:Exists()
    return ok, string.format("cell=%s kind=%s anim=%s adopted=%s layoutRocks=%s reach=%s mark=%s", tostring(m.grid),
        gridName(kind), tostring(grid and grid:GetSprite():GetAnimation()), tostring(m.adopted),
        tostring(m.layoutRocks), tostring(m.grid and walkUpTo(m.grid)), tostring(mark ~= nil and mark:Exists()))
end

local function liverPickup()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and pickup.SubType == rawLiver() then
            return pickup
        end
    end
end

-- Each Raw Liver taken while holding Rabbit is a liver, up to four; one taken
-- before Rabbit is not.
S.add("RABBIT", "liver", { conditions = true, synergies = true }, function(plan, id)
    setup(plan, id, 1, { before = { rawLiver() } })
    plan.check("a Raw Liver taken before Rabbit gives no liver", function(player)
        return rabbit().livers(player) == 0 and effectNum(player, id) == 0, counts(player, id)
    end)
    plan.act(function(player) player:AddCollectible(rawLiver(), 0, true) end)
    plan.wait(4)
    plan.check("a Raw Liver taken with Rabbit is a liver at hand, an extra life", function(player)
        local ok = rabbit().livers(player) == 1 and effectNum(player, id) == 1
        if ok and type(player.GetExtraLives) == "function" then ok = player:GetExtraLives() >= 1 end
        return ok, counts(player, id)
    end)
    plan.act(function(player) for _ = 1, 4 do player:AddCollectible(rawLiver(), 0, true) end end)
    plan.wait(4)
    plan.check("at most four livers", function(player)
        return rabbit().livers(player) == 4 and effectNum(player, id) == 4, counts(player, id)
    end)
    plan.check("without 진 the liver past four is not offered", function(player)
        return T().evidence().offered == 0, "offered=" .. T().evidence().offered
    end)
end, { "raw_liver" })

-- With 진 a Raw Liver past four livers is offered to the Dragon King: each
-- offering adds 0.4 to the damage multiplier for the rest of the floor (user
-- choice and request 2026-11-10: x1.4, then x1.8).
S.add("RABBIT", "dragon", { conditions = true, synergies = true }, function(plan, id)
    local dragonId = ConchBlessing.ItemData.DRAGON and ConchBlessing.ItemData.DRAGON.id or -1
    plan.require("진 is registered", function() return dragonId > 0 or nil, "DRAGON id missing" end)
    setup(plan, id, 1, { before = { dragonId }, after = { rawLiver(), rawLiver(), rawLiver(), rawLiver() } })
    plan.wait(6)
    plan.act(function(player, ctx) ctx.base = player.Damage end)
    plan.check("four livers and no reward yet", function(player)
        return rabbit().livers(player) == 4 and T().evidence().offered == 0, counts(player, id)
    end)
    plan.act(function(player) player:AddCollectible(rawLiver(), 0, true) end)
    plan.wait(8)
    plan.check("a fifth Raw Liver is offered: damage x1.4", function(player, ctx)
        local ratio = player.Damage / ctx.base
        return rabbit().livers(player) == 4 and T().evidence().offered == 1 and math.abs(ratio - 1.4) < 0.01,
            string.format("damage %.3f -> %.3f (x%.3f) offered=%d %s", ctx.base, player.Damage, ratio,
                T().evidence().offered, counts(player, id))
    end)
    plan.act(function(player) player:AddCollectible(rawLiver(), 0, true) end)
    plan.wait(8)
    plan.check("another offering on the same floor adds 0.4: x1.8", function(player, ctx)
        local ratio = player.Damage / ctx.base
        return T().evidence().offered == 2 and math.abs(ratio - 1.8) < 0.01,
            string.format("x%.3f offered=%d", ratio, T().evidence().offered)
    end)
    S.newFloor(plan, 2)
    plan.wait(8)
    plan.check("the next floor takes the reward away", function(player, ctx)
        local ratio = player.Damage / ctx.base
        return math.abs(ratio - 1) < 0.01 and rabbit().livers(player) == 4,
            string.format("damage %.3f (x%.3f) %s", player.Damage, ratio, counts(player, id))
    end)
end, { "dragon" })

-- A lethal hit with a liver and a 1UP: the liver goes first, the holder lives
-- on in the same room with half a heart and four seconds of invincibility, and
-- the 1UP stays for the next death.
S.add("RABBIT", "revive", { conditions = true }, function(plan, id)
    setup(plan, id, 1, { before = { oneUp() }, after = { rawLiver() } })
    die(plan, "the holder revives from a lethal hit")
    plan.check("the liver revived the holder before 1UP", function(player)
        local e = T().evidence()
        return e.revives == 1 and player:GetCollectibleNum(oneUp(), true) == 1 and rabbit().livers(player) == 0
            and effectNum(player, id) == 0,
            string.format("revives=%d 1UP=%d %s", e.revives, player:GetCollectibleNum(oneUp(), true), counts(player, id))
    end)
    plan.check("the holder lives on in the same room with half a heart", function(player, ctx)
        local here = Game():GetLevel():GetCurrentRoomIndex()
        return player:GetHearts() + player:GetSoulHearts() == 1 and here == ctx.deathRoom,
            string.format("hearts=%d soul=%d room %d -> %d", player:GetHearts(), player:GetSoulHearts(), ctx.deathRoom, here)
    end)
    plan.act(function(player, ctx)
        ctx.reviveFrame, ctx.cooldown = Game():GetFrameCount(), player:GetDamageCooldown()
    end)
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 400, "invincibility ends")
    plan.check("invincibility lasts four seconds", function(_, ctx)
        local updates = Game():GetFrameCount() - ctx.reviveFrame
        return math.abs(updates - 120) <= 8, string.format("%d updates (cooldown %d at the revive)", updates, ctx.cooldown)
    end)
    die(plan, "1UP revives the holder")
    plan.check("with no liver left the vanilla revive is used", function(player)
        return T().evidence().revives == 1 and player:GetCollectibleNum(oneUp(), true) == 0,
            string.format("revives=%d 1UP=%d", T().evidence().revives, player:GetCollectibleNum(oneUp(), true))
    end)
end)

-- The whole way: the hidden rock four doors from the start room, its tracks,
-- the ladder when it breaks, the crawlspace's passage and the black market's
-- Raw Liver, bought by touch for a liver.
S.add("RABBIT", "rock", { conditions = true }, function(plan, id)
    setup(plan, id, 1)
    rockChosen(plan)
    plan.check("the hidden rock is four doors from the start room (else the farthest)", function()
        local allowed, distance = expectedTargets(Game():GetLevel())
        local m = market()
        return allowed[m.room] == true, string.format("room=%s distance=%s", tostring(m.room), tostring(distance[m.room]))
    end)
    goTo(plan, "walk to the hidden rock's room", function() return rockRoom() end)
    plan.check("one of the room's own rocks carries the tracks", function()
        local m = market()
        local ok, detail = rockStands(m)
        return ok and ownChosen(m), detail .. string.format(" placed=%d ownRocks=%d", T().evidence().placed, ownRocks())
    end)
    plan.check("its rabbit tracks are drawn on the rock", function()
        local mark, m = T().mark(), market()
        local at = mark and Game():GetRoom():GetGridPosition(m.grid)
        return T().tracksVariant() > 0 and mark ~= nil and mark:Exists() and mark.Position:Distance(at) < 1
            and T().evidence().marks == 1,
            string.format("variant=%d mark=%s marks=%d (restart after entities2.xml changes)", T().tracksVariant(),
                tostring(mark ~= nil), T().evidence().marks)
    end)
    plan.note("LOOK", function() return "faint muddy rabbit tracks across one of the room's own rocks" end)
    plan.wait(30)
    plan.check("no ladder while the rock stands", function()
        return not market().stairs and not T().stairsAt(Game():GetRoom(), market().grid), "stairs=" .. tostring(market().stairs)
    end)
    breakRock(plan)
    plan.check("the tracks go with the rock", function()
        local mark = T().mark()
        return mark == nil or not mark:Exists(), "mark=" .. tostring(mark ~= nil)
    end)
    plan.check("breaking it opens a ladder and makes the crawlspace the black market's passage", function(_, ctx)
        local desc = Game():GetLevel():GetRoomByIdx(GridRooms.ROOM_DUNGEON_IDX)
        local data = desc and desc.Data
        return T().stairsAt(Game():GetRoom(), market().grid) and data ~= nil and data.Type == RoomType.ROOM_DUNGEON
            and data.Variant == 1 and market().written == true,
            string.format("destroyed=%s crawlspace var=%s written=%s", tostring(ctx.destroyed),
                tostring(data and data.Variant), tostring(market().written))
    end)
    downLadder(plan)
    plan.check("the ladder leads into the passage crawlspace", function()
        local desc = Game():GetLevel():GetCurrentRoomDesc()
        return Game():GetLevel():GetCurrentRoomIndex() == GridRooms.ROOM_DUNGEON_IDX and desc.Data.Variant == 1,
            string.format("room=%d var=%d", Game():GetLevel():GetCurrentRoomIndex(), desc.Data.Variant)
    end)
    throughPassage(plan)
    plan.check("the passage leads into the black market, which sells one Raw Liver", function()
        local pickup = liverPickup()
        return Game():GetLevel():GetCurrentRoomIndex() == GridRooms.ROOM_BLACK_MARKET_IDX and pickup ~= nil
            and pickup:IsShopItem() and pickup.Price < 0,
            string.format("room=%d liver=%s price=%s shop=%s stocked=%d", Game():GetLevel():GetCurrentRoomIndex(),
                tostring(pickup ~= nil), tostring(pickup and pickup.Price), tostring(pickup and pickup.ShopItemId),
                T().evidence().stocked)
    end)
    plan.act(function(player, ctx)
        ctx.containers = player:GetMaxHearts()
        ctx.liverAt = liverPickup().Position
    end)
    plan.waitUntil(function(player, ctx)
        if rabbit().livers(player) >= 1 then return true end
        player.Position, player.Velocity = ctx.liverAt, Vector.Zero
        return false, counts(player, id)
    end, 240, "buy the Raw Liver")
    plan.wait(10)
    plan.check("the Raw Liver, bought with hearts, is a liver at hand", function(player, ctx)
        return rabbit().livers(player) == 1 and effectNum(player, id) == 1 and player:GetCollectibleNum(rawLiver(), true) == 1,
            string.format("%s containers %d -> %d", counts(player, id), ctx.containers, player:GetMaxHearts())
    end)
    plan.wait(30)
    plan.check("the black market holds no second Raw Liver", function()
        return liverPickup() == nil and T().evidence().stocked == 1, "stocked=" .. T().evidence().stocked
    end)
end)

-- A crawlspace already visited keeps its own layout: the ladder still leads to
-- the black market, sent on from the crawlspace.
S.add("RABBIT", "visited", { conditions = true }, function(plan, id)
    setup(plan, id, 1)
    rockChosen(plan)
    plan.act(function(_, ctx) ctx.start = Game():GetLevel():GetCurrentRoomIndex() end)
    goTo(plan, "visit the floor's crawlspace first", function() return GridRooms.ROOM_DUNGEON_IDX end)
    plan.act(function(_, ctx)
        local data = Game():GetLevel():GetCurrentRoomDesc().Data
        ctx.ownVariant = data and data.Variant
    end)
    goTo(plan, "back to the start room", function(ctx) return ctx.start end)
    goTo(plan, "walk to the hidden rock's room", function() return rockRoom() end)
    breakRock(plan)
    plan.check("the visited crawlspace keeps its layout", function(_, ctx)
        local data = Game():GetLevel():GetRoomByIdx(GridRooms.ROOM_DUNGEON_IDX).Data
        return market().direct == true and data.Variant == ctx.ownVariant,
            string.format("direct=%s var %s -> %s", tostring(market().direct), tostring(ctx.ownVariant), tostring(data.Variant))
    end)
    downLadder(plan)
    plan.waitUntil(function()
        return Game():GetLevel():GetCurrentRoomIndex() == GridRooms.ROOM_BLACK_MARKET_IDX
            and RoomTransition.GetTransitionMode() == 0
    end, 240, "sent on to the black market")
    plan.wait(10)
    plan.check("the ladder still reaches the black market and its Raw Liver", function()
        return T().evidence().redirected == 1 and liverPickup() ~= nil,
            string.format("redirected=%d liver=%s", T().evidence().redirected, tostring(liverPickup() ~= nil))
    end)
end)

-- A new floor has its own hidden rock; livers at hand come along.
S.add("RABBIT", "floor", { conditions = true }, function(plan, id)
    setup(plan, id, 1, { after = { rawLiver() } })
    rockChosen(plan)
    S.newFloor(plan, 2)
    plan.act(function()
        local level = Game():GetLevel()
        if type(level.RemoveCurses) == "function" then level:RemoveCurses(level:GetCurses()) end
    end)
    rockChosen(plan)
    plan.check("the new floor's rock is four doors from its start, with nothing broken yet", function()
        local allowed, distance = expectedTargets(Game():GetLevel())
        local m = market()
        return allowed[m.room] == true and not m.stairs and m.grid == nil,
            string.format("room=%s distance=%s stairs=%s", tostring(m.room), tostring(distance[m.room]), tostring(m.stairs))
    end)
    plan.check("the liver at hand came along", function(player) return rabbit().livers(player) == 1, counts(player, id) end)
end)

-- Losing Rabbit keeps the livers saved but out of reach; it brings them back.
S.add("RABBIT", "loss", { conditions = true }, function(plan, id)
    setup(plan, id, 1, { after = { rawLiver(), rawLiver() } })
    plan.check("two livers", function(player)
        return rabbit().livers(player) == 2 and effectNum(player, id) == 2, counts(player, id)
    end)
    plan.act(function(player) player:RemoveCollectible(id) end)
    plan.wait(4)
    plan.check("without Rabbit no liver is at hand, but they are kept", function(player)
        return rabbit().livers(player) == 2 and effectNum(player, id) == 0, counts(player, id)
    end)
    plan.act(function(player) player:AddCollectible(rawLiver(), 0, true) end)
    plan.wait(4)
    plan.act(function(player) player:AddCollectible(id, 0, false) end)
    plan.wait(4)
    plan.check("back with Rabbit the kept livers return; the Raw Liver taken without it gave none", function(player)
        return rabbit().livers(player) == 2 and effectNum(player, id) == 2, counts(player, id)
    end)
end)

-- Without Rabbit a lethal hit uses 1UP as usual and the floor has no hidden rock.
S.add("RABBIT", "control", { conditions = true }, function(plan, id)
    setup(plan, id, 0, { before = { oneUp(), rawLiver() } })
    die(plan, "1UP revives the player")
    plan.check("no liver and no hidden rock without Rabbit", function(player)
        return T().evidence().revives == 0 and player:GetCollectibleNum(oneUp(), true) == 0 and rabbit().market() == nil,
            string.format("revives=%d 1UP=%d market=%s", T().evidence().revives,
                player:GetCollectibleNum(oneUp(), true), tostring(rabbit().market() ~= nil))
    end)
end)

-- A measurement for the 묘 redesign (user idea 2026-11-10: a hidden rock on
-- every floor opens a crawlspace whose side passage leads to the black market,
-- where the liver is kept). Records, with no checks: whether each floor has the
-- black market (-6) and crawlspace (-4) rooms, and whether stairs spawned by
-- Lua and a crawlspace RoomConfig written into the -4 descriptor beforehand
-- lead through the black-market-entrance crawlspace into the black market.
local function offGrid(index)
    local desc = Game():GetLevel():GetRoomByIdx(index)
    if not desc then return "none" end
    local data = desc.Data
    if not data then return "noData" end
    return string.format("type=%s var=%s sub=%s shape=%s name=%s", tostring(data.Type), tostring(data.Variant),
        tostring(data.Subtype), tostring(data.Shape), tostring(data.Name))
end

local function doorsHere()
    local room, parts = Game():GetRoom(), {}
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            local at = room:GetDoorSlotPosition(slot)
            parts[#parts + 1] = string.format("%d->%d type=%d open=%s at=(%.0f,%.0f)", slot, door.TargetRoomIndex,
                door.TargetRoomType, tostring(door:IsOpen()), at.X, at.Y)
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or "no doors"
end

local function hereDescribed()
    local level, room = Game():GetLevel(), Game():GetRoom()
    local desc = level:GetCurrentRoomDesc()
    return string.format("idx=%d stage=%d/%d roomType=%d %s", level:GetCurrentRoomIndex(), level:GetStage(),
        level:GetStageType(), room:GetType(), desc and desc.Data and string.format("var=%d name=%s",
            desc.Data.Variant, tostring(desc.Data.Name)) or "noData")
end

local function pickupsHere()
    local parts = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup then
            parts[#parts + 1] = string.format("%d.%d.%d price=%d shop=%d", pickup.Type, pickup.Variant, pickup.SubType,
                pickup.Price, pickup.ShopItemId)
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or "no pickups"
end

local function survey(plan, label)
    plan.note(label, function()
        return string.format("%s | blackMarket(-6) %s | crawlspace(-4) %s", hereDescribed(),
            offGrid(GridRooms.ROOM_BLACK_MARKET_IDX), offGrid(GridRooms.ROOM_DUNGEON_IDX))
    end)
end

local function altFloor(plan, command, stage)
    plan.act(function() Isaac.ExecuteCommand("stage " .. command) end)
    plan.waitUntil(function()
        local level = Game():GetLevel()
        return level:GetStage() == stage and level:GetStageType() >= StageType.STAGETYPE_REPENTANCE
    end, 180, "floor " .. command)
    plan.wait(4)
end

S.add("RABBIT", "market_probe", {}, function(plan)
    for stage = 1, 11 do
        S.newFloor(plan, stage)
        survey(plan, "floor " .. stage)
    end
    for _, alt in ipairs({ { "1c", 1 }, { "2c", 2 }, { "3c", 3 }, { "4c", 4 }, { "5c", 5 }, { "6c", 6 } }) do
        altFloor(plan, alt[1], alt[2])
        survey(plan, "floor " .. alt[1])
    end
    -- the crawlspace with the black market's side passage (special rooms STB, variant 1)
    S.newFloor(plan, 2)
    S.newFloor(plan, 1)
    survey(plan, "back on floor 1")
    plan.act(function(player, ctx)
        local room, level = Game():GetRoom(), Game():GetLevel()
        local ok, config = pcall(function()
            return RoomConfig.GetRoomByStageTypeAndVariant(StbType.SPECIAL_ROOMS or 0, RoomType.ROOM_DUNGEON, 1, 0)
        end)
        ctx.config = ok and config or nil
        ctx.configNote = ok and (config and string.format("var=%d name=%s type=%d", config.Variant,
            tostring(config.Name), config.Type) or "nil") or ("error " .. tostring(config))
        local desc = level:GetRoomByIdx(GridRooms.ROOM_DUNGEON_IDX)
        local wrote, err = pcall(function() desc.Data = ctx.config end)
        ctx.writeNote = wrote and "written" or ("write error " .. tostring(err))
        ctx.afterWrite = offGrid(GridRooms.ROOM_DUNGEON_IDX)
        ctx.stairsAt = room:FindFreeTilePosition(room:GetCenterPos() + Vector(80, 0), 0)
        local grid = Isaac.GridSpawn(GridEntityType.GRID_STAIRS, 0, ctx.stairsAt, true)
        ctx.gridNote = grid and string.format("type=%d variant=%d index=%d state=%s coll=%s varData=%s", grid:GetType(),
            grid:GetVariant(), grid:GetGridIndex(), tostring(grid.State), tostring(grid.CollisionClass),
            tostring(grid.VarData)) or "GridSpawn returned nil"
        ctx.start = level:GetCurrentRoomIndex()
    end)
    plan.note("config, write and stairs", function(_, ctx)
        return string.format("config %s | %s | -4 now %s | stairs %s", ctx.configNote, ctx.writeNote, ctx.afterWrite,
            ctx.gridNote)
    end)
    plan.wait(10)
    plan.act(function(player, ctx)
        player.Position = ctx.stairsAt
        player.Velocity = Vector.Zero
    end)
    plan.waitUntil(function(player, ctx)
        if Game():GetLevel():GetCurrentRoomIndex() ~= ctx.start then return RoomTransition.GetTransitionMode() == 0 end
        player.Position = ctx.stairsAt
        return false, "still above the stairs"
    end, 240, "down the stairs")
    plan.wait(10)
    plan.note("in the crawlspace", function()
        return hereDescribed() .. " | " .. doorsHere() .. " | -6 " .. offGrid(GridRooms.ROOM_BLACK_MARKET_IDX)
    end)
    -- walk along the floor toward a door into the black market, when there is one
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        ctx.marketDoor = nil
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomIndex == GridRooms.ROOM_BLACK_MARKET_IDX then ctx.marketDoor = slot end
        end
        ctx.crawl = Game():GetLevel():GetCurrentRoomIndex()
        if ctx.marketDoor then
            local at = room:GetDoorSlotPosition(ctx.marketDoor)
            player.Position = Vector(at.X - 60, player.Position.Y)
        end
    end)
    plan.waitUntil(function(player, ctx)
        if not ctx.marketDoor then return true end
        if Game():GetLevel():GetCurrentRoomIndex() ~= ctx.crawl then return RoomTransition.GetTransitionMode() == 0 end
        local at = Game():GetRoom():GetDoorSlotPosition(ctx.marketDoor)
        player.Velocity = Vector(at.X > player.Position.X and 5 or -5, player.Velocity.Y)
        return false, string.format("at (%.0f,%.0f), door at (%.0f,%.0f)", player.Position.X, player.Position.Y, at.X, at.Y)
    end, 300, "into the black market")
    plan.wait(10)
    plan.note("after the walk", function(_, ctx)
        return "marketDoor=" .. tostring(ctx.marketDoor) .. " | " .. hereDescribed() .. " | " .. doorsHere()
            .. " | " .. pickupsHere()
    end)
end)
S.rows[#S.rows].manual = true

-- The second half of the measurement: down Lua stairs into the forced
-- black-market-entrance crawlspace, then walk right along its floor.
local function gridRow(y)
    local room, parts = Game():GetRoom(), {}
    local width = room:GetGridWidth()
    for x = 0, width - 1 do
        local grid = room:GetGridEntity(y * width + x)
        parts[#parts + 1] = grid and tostring(grid:GetType()) or "."
    end
    return table.concat(parts, " ")
end

S.add("RABBIT", "market_walk", {}, function(plan)
    plan.act(function(player, ctx)
        local room, level = Game():GetRoom(), Game():GetLevel()
        local config = RoomConfig.GetRoomByStageTypeAndVariant(StbType.SPECIAL_ROOMS or 0, RoomType.ROOM_DUNGEON, 1, 0)
        level:GetRoomByIdx(GridRooms.ROOM_DUNGEON_IDX).Data = config
        ctx.stairsAt = room:FindFreeTilePosition(room:GetCenterPos() + Vector(80, 0), 0)
        Isaac.GridSpawn(GridEntityType.GRID_STAIRS, 0, ctx.stairsAt, true)
        ctx.start = level:GetCurrentRoomIndex()
    end)
    plan.wait(10)
    plan.act(function(player, ctx) player.Position = ctx.stairsAt; player.Velocity = Vector.Zero end)
    plan.waitUntil(function(player, ctx)
        if Game():GetLevel():GetCurrentRoomIndex() ~= ctx.start then return RoomTransition.GetTransitionMode() == 0 end
        player.Position = ctx.stairsAt
        return false, "still above the stairs"
    end, 240, "down the stairs")
    plan.wait(20)
    plan.note("arrived", function(player)
        local room = Game():GetRoom()
        return string.format("%s | player (%.0f,%.0f) | grid %dx%d | pickups %s", hereDescribed(), player.Position.X,
            player.Position.Y, room:GetGridWidth(), room:GetGridHeight(), pickupsHere())
    end)
    for y = 0, 8 do
        plan.note("row " .. y, function() return gridRow(y) end)
    end
    plan.act(function(_, ctx) ctx.crawl = Game():GetLevel():GetCurrentRoomIndex(); ctx.trail = {} end)
    plan.waitUntil(function(player, ctx)
        if Game():GetLevel():GetCurrentRoomIndex() ~= ctx.crawl then return RoomTransition.GetTransitionMode() == 0 end
        player.Velocity = Vector(5, player.Velocity.Y)
        if Game():GetFrameCount() % 15 == 0 then
            ctx.trail[#ctx.trail + 1] = string.format("(%.0f,%.0f)", player.Position.X, player.Position.Y)
        end
        return false, "still in the crawlspace"
    end, 300, "walk right")
    plan.wait(10)
    plan.note("trail", function(_, ctx) return table.concat(ctx.trail, " ") end)
    plan.note("after the walk", function(player)
        return string.format("%s | player (%.0f,%.0f) | %s | %s", hereDescribed(), player.Position.X, player.Position.Y,
            doorsHere(), pickupsHere())
    end)
end)
S.rows[#S.rows].manual = true

-- How the hidden rock looks, render frame by render frame, as a player walks
-- through a real door into its room (user report 2026-11-10: it flickers
-- before the room is entered). A measurement: every change of the rock's grid,
-- sprite and tracks is logged with the render and update it was seen in.
local rockWatch = nil -- { log = {}, last = nil, render = 0 }

local function rockState(tag)
    if not rockWatch then return end
    local m = rabbit().market() or {}
    local room, level = Game():GetRoom(), Game():GetLevel()
    local grid = m.grid and room:GetGridEntity(m.grid)
    local sprite = grid and grid:GetSprite()
    local mark = T().mark()
    local state = string.format("idx=%d mode=%d grid=%s coll=%s anim=%s/%s mark=%s placed=%d marks=%d",
        level:GetCurrentRoomIndex(), RoomTransition.GetTransitionMode(), tostring(grid and grid:GetType()),
        tostring(grid and grid.CollisionClass), tostring(sprite and sprite:GetAnimation()),
        tostring(sprite and sprite:GetFrame()), tostring(mark ~= nil and mark:Exists()),
        T().evidence().placed, T().evidence().marks)
    if state ~= rockWatch.last then
        rockWatch.last = state
        rockWatch.log[#rockWatch.log + 1] = string.format("%s r%d u%d %s", tag, rockWatch.render,
            Game():GetFrameCount(), state)
    end
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not rockWatch then return end
    rockWatch.render = rockWatch.render + 1
    rockState("R")
end)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function() rockState("U") end)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() rockState("N") end)

-- The door of this room into the hidden rock's room, or nil.
local function doorToRock()
    local room, level = Game():GetRoom(), Game():GetLevel()
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        local target = door and level:GetRoomByIdx(door.TargetRoomIndex)
        if target and target.ListIndex == (rabbit().market() or {}).list then return slot end
    end
    return nil
end

-- A room beside the hidden rock's room, entered through a door into it.
local function besideRock(level)
    local m = rabbit().market() or {}
    for _, index in ipairs(LevelRooms.neighborsOf(level, m.room)) do
        local desc = LevelRooms.roomAt(level, index)
        if desc and desc.Data and desc.Data.Type == RoomType.ROOM_DEFAULT and desc.ListIndex ~= m.list then
            return desc.SafeGridIndex
        end
    end
    return nil
end

local function watchedWalk(plan, label)
    plan.waitUntil(function() return Game():GetRoom():IsClear() and doorToRock() ~= nil end, 120, label .. ": doors open")
    H.walkThroughDoor(plan, label, function() return doorToRock() end, function()
        rockWatch = { log = {}, render = 0 }
    end)
    plan.wait(20)
    for i = 1, 24 do
        plan.note(label .. " " .. i, function() return rockWatch and rockWatch.log[i] or "-" end)
    end
    plan.act(function() rockWatch = nil end)
end

S.add("RABBIT", "rock_watch", {}, function(plan, id)
    setup(plan, id, 1)
    rockChosen(plan)
    plan.act(function(_, ctx)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function() rockWatch = nil end)
    end)
    goTo(plan, "the room beside the hidden rock", function() return besideRock(Game():GetLevel()) end)
    watchedWalk(plan, "first visit")
    plan.act(function(_, ctx) ctx.back = ctx.from end)
    goTo(plan, "back beside it", function(ctx) return ctx.back end)
    watchedWalk(plan, "second visit")
end)
S.rows[#S.rows].manual = true


local function layoutRocks(desc)
    local types = T().layoutTypes(desc.Data)
    return types and T().countLayoutRocks(types) or nil
end

-- A room the hidden rock is handed to by hand (a fixture: the floor's own
-- choice is overwritten before anyone has been there).
local function handTo(plan, label, find)
    plan.require(label, function(_, ctx)
        local level = Game():GetLevel()
        local rooms = level:GetRooms()
        local start = level:GetStartingRoomIndex()
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if desc and desc.Data and desc.GridIndex >= 0 and desc.SafeGridIndex ~= start
                and desc.Data.Type == RoomType.ROOM_DEFAULT and find(desc) then
                ctx.handed = desc
                return true, string.format("room %d shape %d", desc.SafeGridIndex, desc.Data.Shape)
            end
        end
        return nil, "this floor has no such room"
    end)
    plan.act(function(_, ctx)
        local m = market()
        m.room, m.list, m.grid, m.kind, m.adopted = ctx.handed.SafeGridIndex, ctx.handed.ListIndex, nil, nil, nil
        m.layoutRocks = layoutRocks(ctx.handed)
        T().resetEvidence()
    end)
end

-- Remakes the floor with a new seed (the reseed command) until it has a room
-- `find` accepts, at most `tries` times.
local function floorWith(plan, label, find, tries)
    plan.waitUntil(function(_, ctx)
        local level = Game():GetLevel()
        if RoomTransition.GetTransitionMode() ~= 0 then return false, "floor changing" end
        local rooms = level:GetRooms()
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if desc and desc.Data and desc.GridIndex >= 0 and desc.SafeGridIndex ~= level:GetStartingRoomIndex()
                and desc.Data.Type == RoomType.ROOM_DEFAULT and find(desc) then
                return true
            end
        end
        ctx.reseeds = ctx.reseeds or 0
        ctx.reseedWait = (ctx.reseedWait or 0) - 1
        if ctx.reseeds >= tries then return true end
        if ctx.reseedWait <= 0 then
            ctx.reseeds, ctx.reseedWait = ctx.reseeds + 1, 20
            Isaac.ExecuteCommand("reseed")
        end
        return false, "reseeding (" .. ctx.reseeds .. ")"
    end, 60 * tries + 120, label)
    plan.act(function()
        local level = Game():GetLevel()
        if type(level.RemoveCurses) == "function" then level:RemoveCurses(level:GetCurses()) end
    end)
    plan.wait(4)
end

local function roomWithoutRocks(desc)
    local shape = desc.Data.Shape
    return layoutRocks(desc) == 0 and shape ~= RoomShape.ROOMSHAPE_IH and shape ~= RoomShape.ROOMSHAPE_IV
        and shape ~= RoomShape.ROOMSHAPE_IIH and shape ~= RoomShape.ROOMSHAPE_IIV
end

-- A room whose layout has no rock gets a rock of its own: an ordinary rock two
-- cells clear of every door, never cutting one door off from another.
S.add("RABBIT", "fallback", { conditions = true }, function(plan, id)
    setup(plan, id, 1)
    floorWith(plan, "a floor with an ordinary room without rocks", roomWithoutRocks, 25)
    rockChosen(plan)
    handTo(plan, "an ordinary room with no rock in its layout", roomWithoutRocks)
    goTo(plan, "walk into it", function(ctx) return ctx.handed.SafeGridIndex end)
    plan.check("a rock of its own stands there, two cells clear of every door, with its tracks", function()
        local m, room = market(), Game():GetRoom()
        local ok, detail = rockStands(m)
        if not ok then return false, detail end
        local width = room:GetGridWidth()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door then
                local cell = door:GetGridIndex()
                if math.max(math.abs(cell % width - m.grid % width), math.abs(cell // width - m.grid // width)) <= 2 then
                    return false, "too near door slot " .. slot
                end
            end
        end
        return m.adopted == false and m.kind == GridEntityType.GRID_ROCK and T().evidence().placed == 1
            and T().evidence().adopted == 0, detail
    end)
    breakRock(plan)
    plan.check("breaking it opens the ladder", function()
        return T().stairsAt(Game():GetRoom(), market().grid), "stairs=" .. tostring(market().stairs)
    end)
end)

-- A room with no rock and no room for one hands the hidden rock to another
-- room. Fixture: the start room is handed the rock after every floor cell but
-- those next to the doors and the player is made a pit (no rock of its own,
-- nowhere to lay one); the narrow corridor rooms of real floors had room for a
-- rock when measured (2026-11-10).
S.add("RABBIT", "no_room", { conditions = true }, function(plan, id)
    setup(plan, id, 1)
    rockChosen(plan)
    plan.act(function(player, ctx)
        local level, room = Game():GetLevel(), Game():GetRoom()
        local width = room:GetGridWidth()
        local doors = {}
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door then
                local side = slot % 4
                doors[#doors + 1] = door:GetGridIndex()
                    + (side == 0 and 1 or side == 1 and width or side == 2 and -1 or -width)
            end
        end
        player.Position = room:GetGridPosition(doors[1])
        local me = room:GetGridIndex(player.Position)
        local function near(cell, list, d)
            for _, other in ipairs(list) do
                if math.max(math.abs(other % width - cell % width), math.abs(other // width - cell // width)) <= d then
                    return true
                end
            end
            return false
        end
        ctx.pits = 0
        for cell = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(cell)
            if grid and T().kinds()[grid:GetType()] then room:DestroyGrid(cell, true) end
            if room:IsPositionInRoom(room:GetGridPosition(cell), 0) and not room:GetGridEntity(cell)
                and room:GetGridCollision(cell) == GridCollisionClass.COLLISION_NONE
                and not near(cell, doors, 2) and not near(cell, { me }, 1) then
                if room:SpawnGridEntity(cell, GridEntityType.GRID_PIT, 0, 1, 0) then ctx.pits = ctx.pits + 1 end
            end
        end
        local desc = level:GetCurrentRoomDesc()
        ctx.startList = desc.ListIndex
        local m = market()
        ctx.before = m.list
        m.room, m.list, m.grid, m.kind, m.adopted = desc.SafeGridIndex, desc.ListIndex, nil, nil, nil
        T().resetEvidence()
    end)
    plan.wait(6)
    plan.check("with no rock and nowhere to lay one, the hidden rock moved to another room", function(_, ctx)
        local m, e = market(), T().evidence()
        return e.moved == 1 and e.placed == 0 and e.adopted == 0 and m.list ~= nil and m.list ~= ctx.startList
            and m.grid == nil and type(m.skip) == "table" and m.skip[tostring(ctx.startList)] == true,
            string.format("pits=%d moved=%d placed=%d adopted=%d room %s -> %s", ctx.pits, e.moved, e.placed, e.adopted,
                tostring(ctx.startList), tostring(m.list))
    end)
    goTo(plan, "walk to the room it moved to", function() return market().room end)
    plan.check("there it stands on that room's rock with its tracks", function()
        local ok, detail = rockStands(market())
        return ok, detail
    end)
end)

-- Every floor (1-11 and the alternate 1c-6c): the hidden rock stands on one of
-- the chosen room's own rocks of that stage's look, a player can walk up to it,
-- its tracks are drawn, and breaking it opens the ladder (thorough check the
-- user asked for, 2026-11-10).
S.add("RABBIT", "floors", { conditions = true }, function(plan, id)
    setup(plan, id, 1)
    local floors = {}
    for stage = 1, 11 do floors[#floors + 1] = { tostring(stage), stage, false } end
    for stage = 1, 6 do floors[#floors + 1] = { stage .. "c", stage, true } end
    for _, f in ipairs(floors) do
        local command, stage, alt = f[1], f[2], f[3]
        plan.act(function() Isaac.ExecuteCommand("stage " .. command) end)
        plan.waitUntil(function()
            local level = Game():GetLevel()
            local repentance = level:GetStageType() >= StageType.STAGETYPE_REPENTANCE
            return level:GetStage() == stage and repentance == alt and RoomTransition.GetTransitionMode() == 0
        end, 240, "floor " .. command)
        plan.act(function(player)
            local level = Game():GetLevel()
            if type(level.RemoveCurses) == "function" then level:RemoveCurses(level:GetCurses()) end
            T().resetEvidence()
        end)
        plan.wait(4)
        rockChosen(plan)
        goTo(plan, "floor " .. command .. ": the hidden rock's room", function() return rockRoom() end)
        plan.check("floor " .. command .. ": the hidden rock stands on the room's own rock with its tracks", function()
            local m = market()
            local ok, detail = rockStands(m)
            return ok and ownChosen(m), detail .. string.format(" ownRocks=%d", ownRocks())
        end)
        plan.act(function(player)
            -- stand away from the rock (a bomb rock blows up) and out of harm's way
            local room = Game():GetRoom()
            local at = room:GetGridPosition(market().grid)
            local best, bestDistance = room:GetCenterPos(), -1
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    local p = room:FindFreeTilePosition(room:GetDoorSlotPosition(slot), 40)
                    if p:Distance(at) > bestDistance then best, bestDistance = p, p:Distance(at) end
                end
            end
            player.Position = best
            player:SetMinDamageCooldown(90)
        end)
        breakRock(plan)
        plan.check("floor " .. command .. ": breaking it opens the ladder", function()
            return T().stairsAt(Game():GetRoom(), market().grid) and T().mark() == nil,
                string.format("stairs=%s mark=%s", tostring(market().stairs), tostring(T().mark() ~= nil))
        end)
    end
end)

return C
