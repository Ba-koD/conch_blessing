local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 축 (Ox): the lifecycle contract and its isolated cases. The oxen walk the
-- engine's own floor: the route is checked against the level's rooms, the
-- broken rock against the room's grid, the reveal against the map's display
-- flags, and growth against the holder's actual damage and tears.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function ox() return ConchBlessing.ox end

-- Live ox effects in the room, NO_QUERY included, by colour (subtype 0 / 1).
local function oxen()
    local found = { yellow = 0, black = 0, total = 0 }
    local variant = ox()._test.variant()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == variant and entity:Exists() then
            local color = entity.SubType == 1 and "black" or "yellow"
            found[color] = found[color] + 1
            found.total = found.total + 1
        end
    end
    return found
end

local function here() return Game():GetLevel():GetCurrentRoomDesc() end
local function state() return ox()._test.state() end

local function field()
    local s = state()
    return s and s.fields["L" .. here().ListIndex]
end

local function size(set)
    local n = 0
    for _ in pairs(set or {}) do n = n + 1 end
    return n
end

local function tears(player) return 30 / (player.MaxFireDelay + 1) end

-- Where each ox stands, what it plans, and why one stopped, for failure details.
local function describe()
    local s, live, e = state(), ox()._test.live(), ox()._test.evidence()
    local parts = {}
    for _, color in ipairs({ "yellow", "black" }) do
        local entry, record = s and s.oxen[color], live[color]
        parts[#parts + 1] = entry and string.format("%s room=%s goal=%s/%s from=%s next=%s done=%s path=%s cells=%.2f exit=%s",
            color, tostring(entry.room), tostring(entry.goals and entry.goals[entry.gi]), tostring(entry.goals and #entry.goals),
            tostring(entry.from), tostring(entry.next), tostring(entry.done),
            tostring(record and record.path and #record.path), entry.cells or -1,
            tostring(record and record.exit)) or (color .. " none")
    end
    parts[#parts + 1] = "here=" .. here().SafeGridIndex
    parts[#parts + 1] = "stuck=[" .. table.concat(e.stuck, "; ") .. "] blows=" .. e.blows .. " opened=" .. e.opened
    return table.concat(parts, " | ")
end

-- The damage and tears multipliers Ox has set on `player` (1 when none).
local function bonus(player)
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    local state = um and ConchBlessing.getUnifiedMultiplierState(player, um)
    local row = state and state.itemMultipliers and state.itemMultipliers[ConchBlessing.ItemData.OX.id] or {}
    return row.Damage and row.Damage.value or 1, row.Tears and row.Tears.value or 1
end

local function requireModule(plan)
    plan.require("Ox module and its effect entity registered", function()
        local module = ox()
        return module ~= nil and module._test ~= nil and module._test.variant() > 0,
            "module missing, or 'Conch Blessing Ox' is not in entities2.xml (fully restart the game)"
    end)
end

local function give(player, id)
    if player:GetCollectibleNum(id) == 0 then player:AddCollectible(id, 0, false) end
end

-- Curse of the Lost, read when a case runs (the offline harnesses load this
-- file without the engine's enums).
local function LOST() return LevelCurse.CURSE_OF_THE_LOST end
local function lost() return Game():GetLevel():GetCurses() & LOST() ~= 0 end

-- Test fixture: while `on`, the floor being made rolls Curse of the Lost, as
-- the engine sometimes does, before the item's own curse callback runs.
local roll = { on = false, rolled = 0 }
if type(ConchBlessing.AddPriorityCallback) == "function" and CallbackPriority and CallbackPriority.EARLY then
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_CURSE_EVAL, CallbackPriority.EARLY, function(_, curses)
        if not roll.on or type(curses) ~= "number" then return end
        roll.rolled = roll.rolled + 1
        return curses | LOST()
    end)
end

local function neighbors(level)
    return function(index) return ox()._test.neighborsOf(level, index) end
end

-- A shortest way to the boss room, by the rooms the yellow ox may pass
-- through (any but a secret room; a boss room only when there is no other).
local function bossRoute(level, start)
    local T = ox()._test
    local boss = T.bossRoom(level)
    return T.route(start, boss, neighbors(level), T.passable(level))
        or T.route(start, boss, neighbors(level), T.passable(level, true))
end

-- Every ox whose floor place is this room walks here; every other one does not.
C.OX = { stage = function(plan, id, n)
    if n > 0 then
        plan.check("each ox whose place is this room walks here, and only those", function()
            local s, live = state(), oxen()
            if not s then return false, "no floor state" end
            local index = here().SafeGridIndex
            local want = { yellow = 0, black = 0 }
            for color, entry in pairs(s.oxen) do
                if entry.room == index then want[color] = 1 end
            end
            return live.yellow == want.yellow and live.black == want.black,
                string.format("live yellow=%d black=%d, expected %d/%d", live.yellow, live.black, want.yellow, want.black)
        end)
        plan.check("the floor knows the yellow ox's goal: the boss room", function()
            local s, level = state(), Game():GetLevel()
            local yellow = s and s.oxen.yellow
            local boss = ox()._test.bossRoom(level)
            return yellow ~= nil and yellow.goals[1] == boss, string.format("goal=%s boss=%s",
                tostring(yellow and yellow.goals[1]), tostring(boss))
        end)
    else
        plan.check("no ox is left once nobody holds the item", function()
            local live = oxen()
            return live.total == 0, "oxen=" .. live.total
        end)
        plan.check("no bonus while not held", function(player)
            local d, t = bonus(player)
            return d == 1 and t == 1, string.format("damage x%s tears x%s", tostring(d), tostring(t))
        end)
    end
end }

-- The yellow ox leaves the start room through the door that leads toward the
-- boss and waits in the next room, which then shows on the map.
S.add("OX", "route", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ox()._test.resetEvidence()
        local level = Game():GetLevel()
        ctx.start = here().SafeGridIndex
        ctx.boss = ox()._test.bossRoom(level)
        ctx.secret = ox()._test.secretRoom(level)
        ctx.path = bossRoute(level, ctx.start)
        ctx.flagsBefore = {}
        for _, index in ipairs(ox()._test.neighborsOf(level, ctx.start)) do
            ctx.flagsBefore[index] = level:GetRoomByIdx(index, 0).DisplayFlags
        end
        give(player, id)
    end)
    plan.wait(3)
    plan.check("two oxen are summoned by the holder (one when the floor has no secret room)", function()
        local live = oxen()
        local want = 1 + (state().oxen.black and 1 or 0)
        return live.yellow == 1 and live.total == want, string.format("yellow=%d black=%d secret=%s",
            live.yellow, live.black, tostring(state().oxen.black and state().oxen.black.goals[1]))
    end)
    plan.check("goals: the boss room; the secret room, then the super secret room for the black ox", function(_, ctx)
        local s, wanted = state(), ox()._test.secretRooms(Game():GetLevel())
        local black = s.oxen.black and table.concat(s.oxen.black.goals, ",") or ""
        return s.oxen.yellow.goals[1] == ctx.boss and #s.oxen.yellow.goals == 1 and black == table.concat(wanted, ","),
            string.format("yellow=%s boss=%s black=[%s] secret rooms=[%s]", tostring(s.oxen.yellow.goals[1]),
            tostring(ctx.boss), black, table.concat(wanted, ","))
    end)
    plan.require("a way leads to the boss room", function(_, ctx)
        return ctx.path ~= nil and #ctx.path >= 2, "route=" .. (ctx.path and table.concat(ctx.path, ">") or "none")
    end)
    plan.waitUntil(function(_, ctx)
        local yellow = state().oxen.yellow
        return yellow.room ~= ctx.start, "yellow ox in " .. tostring(yellow.room)
    end, 900, "the yellow ox walks out through its door")
    plan.check("it went one room nearer the boss room, on a shortest way", function(_, ctx)
        local yellow = state().oxen.yellow
        local rest = bossRoute(Game():GetLevel(), yellow.room)
        return yellow.from == ctx.start and rest ~= nil and #rest == #ctx.path - 1,
            string.format("room=%s from=%s rooms left=%s of %d", tostring(yellow.room), tostring(yellow.from),
                tostring(rest and #rest), #ctx.path)
    end)
    plan.check("that room now shows on the map (shape and icon)", function(_, ctx)
        local index = state().oxen.yellow.room
        local flags = Game():GetLevel():GetRoomByIdx(index, 0).DisplayFlags
        return flags & 5 == 5, string.format("room %d flags %s -> %d", index, tostring(ctx.flagsBefore[index]), flags)
    end)
    plan.check("the yellow ox has left the start room", function()
        return oxen().yellow == 0, "yellow=" .. oxen().yellow
    end)
    plan.section("OX / route", "two oxen appear by Isaac in a puff; the yellow one walks off through the door toward the boss")
end)

-- A rock dropped on the yellow ox's way is broken before it gets there, and
-- the furrow behind it is two tiles wide.
S.add("OX", "furrow", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        ox()._test.resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function()
        local record = ox()._test.live().yellow
        return record ~= nil and record.path ~= nil, describe()
    end, 60, "the yellow ox plans its way to the door")
    plan.act(function(_, ctx)
        local room, path = Game():GetRoom(), ox()._test.live().yellow.path
        ctx.pathCells = {}
        for _, cell in ipairs(path) do ctx.pathCells[cell] = true end
        if #path >= 4 then
            ctx.rockCell = path[math.min(5, #path)]
            Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockCell), true)
        end
        ctx.rockSet = ctx.rockCell ~= nil and room:GetGridCollision(ctx.rockCell) ~= GridCollisionClass.COLLISION_NONE
        -- TNT on another cell of its way, which it crushes without setting off.
        if #path >= 4 then
            local at = math.min(7, #path - 1)
            if path[at] == ctx.rockCell then at = at - 1 end
            if at >= 3 then
                ctx.tntCell = path[at]
                Isaac.GridSpawn(GridEntityType.GRID_TNT, 0, room:GetGridPosition(ctx.tntCell), true)
            end
        end
        local player = Isaac.GetPlayer(0)
        ctx.health = player:GetHearts() + player:GetSoulHearts() + player:GetBlackHearts() + player:GetBoneHearts()
    end)
    plan.require("a rock stands on the yellow ox's path", function(_, ctx)
        return ctx.rockSet == true, "cell=" .. tostring(ctx.rockCell)
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetRoom():GetGridCollision(ctx.rockCell) == GridCollisionClass.COLLISION_NONE, "rock standing"
    end, 400, "the ox reaches the rock")
    plan.check("the rock on its way is broken", function(_, ctx)
        return ox()._test.evidence().broken >= 1, "broken=" .. ox()._test.evidence().broken
    end)
    plan.waitUntil(function(_, ctx)
        if not ctx.tntCell then return true end
        local grid = Game():GetRoom():GetGridEntity(ctx.tntCell)
        return grid == nil or grid:GetType() ~= GridEntityType.GRID_TNT, "TNT standing"
    end, 400, "the ox reaches the TNT")
    plan.check("the TNT on its way is crushed without going off", function(player, ctx)
        if not ctx.tntCell then return nil, "the way is too short to put TNT on" end
        local health = player:GetHearts() + player:GetSoulHearts() + player:GetBlackHearts() + player:GetBoneHearts()
        local blasts = #Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.BOMB_EXPLOSION)
        return ox()._test.evidence().quiet >= 1 and blasts == 0 and health == ctx.health,
            string.format("quiet=%d blasts=%d health %d -> %d", ox()._test.evidence().quiet, blasts, ctx.health, health)
    end)
    -- The share lays the line behind the ox, to the doorway as it leaves;
    -- every way it plans on the way counts as walked.
    plan.waitUntil(function(_, ctx)
        local record = ox()._test.live().yellow
        for _, cell in ipairs(record and record.path or {}) do ctx.pathCells[cell] = true end
        return state().oxen.yellow.room ~= here().SafeGridIndex, describe()
    end, 900, "the yellow ox leaves through its door")
    plan.check("the furrow lies only where the ox walked, to the doorway", function(_, ctx)
        local f, onPath, off = field(), 0, {}
        for key in pairs(f and f.yellow or {}) do
            if ctx.pathCells[tonumber(key)] then onPath = onPath + 1 else off[#off + 1] = key end
        end
        return onPath >= 3 and #off == 0, string.format("on the path=%d off it=[%s]", onPath, table.concat(off, ","))
    end)
    -- A stamp is drawn into the floor and removed by the engine, so the
    -- evidence counts the stamps; a cell stamped twice would only darken.
    plan.check("every quarter of the furrow here was stamped into the floor exactly once", function()
        local f, stamps, wrong, quarters = field(), ox()._test.evidence().stamps, {}, 0
        for _, color in ipairs({ "yellow", "black" }) do
            for key, mask in pairs(f and f[color] or {}) do
                for piece = 0, 23 do
                    if mask & (1 << piece) ~= 0 then
                        quarters = quarters + 1
                        local mark = color .. ":" .. key .. ":" .. piece
                        if (stamps[mark] or 0) ~= 1 then wrong[#wrong + 1] = mark .. "=" .. (stamps[mark] or 0) end
                    end
                end
            end
        end
        return ox()._test.furrowVariant() > 0 and quarters > 0 and #wrong == 0,
            string.format("quarters=%d wrong=[%s]", quarters, table.concat(wrong, ","))
    end)
    plan.section("OX / furrow", "a narrow golden trench behind the yellow ox and a dark one behind the black ox, "
        .. "turning its corners; neither darkens as more is ploughed")
end)

-- The ox walks only where the engine's pathfinder walks a grounded NPC: a
-- pit opened on its way is walked round, never over, and gets no furrow.
S.add("OX", "ground", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ox()._test.resetEvidence()
        ctx.start = here().SafeGridIndex
        give(player, id)
    end)
    plan.waitUntil(function()
        local record = ox()._test.live().yellow
        return record ~= nil and record.path ~= nil, describe()
    end, 60, "the yellow ox plans a way to its door")
    -- Fixture: the ox starts again from the inner corner farthest from its
    -- door, so its way is long enough to open a pit on, whatever the layout.
    plan.act(function(_, ctx)
        local room, record = Game():GetRoom(), ox()._test.live().yellow
        local width, door = room:GetGridWidth(), record.path[#record.path]
        local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
        local best = -1
        for _, corner in ipairs({ tl, Vector(br.X, tl.Y), Vector(tl.X, br.Y), br }) do
            local cell = room:GetGridIndex(corner + (room:GetCenterPos() - corner):Resized(20))
            local d = math.abs(cell % width - door % width) + math.abs(cell // width - door // width)
            if d > best then best, ctx.far = d, cell end
        end
        local yellow, at = state().oxen.yellow, room:GetGridPosition(ctx.far)
        yellow.a, yellow.cells, record.path = { x = at.X, y = at.Y }, 0, nil
    end)
    plan.waitUntil(function(_, ctx)
        local record = ox()._test.live().yellow
        return record ~= nil and record.path ~= nil and record.path[1] == ctx.far, describe()
    end, 30, "the yellow ox plans its way again from the far corner")
    plan.require("the way from the corner is long enough to open a pit on", function()
        local path = ox()._test.live().yellow.path
        return #path >= 8, "cells=" .. #path
    end)
    plan.act(function(player, ctx)
        local room, path = Game():GetRoom(), ox()._test.live().yellow.path
        local width, standing = room:GetGridWidth(), room:GetGridIndex(player.Position)
        for k = 5, #path - 2 do
            local cell = path[k]
            local near = math.abs(cell % width - standing % width) <= 1 and math.abs(cell // width - standing // width) <= 1
            if not near then ctx.pitCell = cell break end
        end
        if ctx.pitCell then
            Isaac.GridSpawn(GridEntityType.GRID_PIT, 0, room:GetGridPosition(ctx.pitCell), true)
            -- A pit spawned in a loaded room blocks nothing until its collision
            -- is updated (measured 2026-10-31: pit, path 0, collision 0).
            local grid = room:GetGridEntity(ctx.pitCell)
            local pit = grid and grid:ToPit()
            if pit then
                pcall(pit.PostInit, pit)
                pit:UpdateCollision()
            end
        end
        ctx.onPit, ctx.seen = 0, 0
    end)
    plan.wait(2)
    plan.require("a pit opens on the yellow ox's way, away from Isaac", function(_, ctx)
        local room = Game():GetRoom()
        local grid = ctx.pitCell and room:GetGridEntity(ctx.pitCell)
        local pit = grid ~= nil and grid:GetType() == GridEntityType.GRID_PIT
        return pit and ox()._test.cellCost(room)(ctx.pitCell) == nil, string.format("cell=%s pit=%s path=%s collision=%s",
            tostring(ctx.pitCell), tostring(pit), tostring(ctx.pitCell and room:GetGridPath(ctx.pitCell)),
            tostring(ctx.pitCell and room:GetGridCollision(ctx.pitCell)))
    end)
    plan.waitUntil(function(_, ctx)
        local record = ox()._test.live().yellow
        local entity = record and record.ref and record.ref.Ref
        if entity and entity:Exists() then
            ctx.seen = ctx.seen + 1
            if Game():GetRoom():GetGridIndex(entity.Position) == ctx.pitCell then ctx.onPit = ctx.onPit + 1 end
        end
        return state().oxen.yellow.room ~= ctx.start, describe()
    end, 900, "the yellow ox walks out through its door")
    plan.check("it found a new way when the pit opened", function()
        return ox()._test.evidence().replans >= 1, "replans=" .. ox()._test.evidence().replans
    end)
    plan.check("it saw the pit coming and turned off before reaching it", function()
        local ahead = ox()._test.evidence().ahead
        return ahead ~= nil and ahead >= 2, "cells ahead when it turned off=" .. tostring(ahead)
    end)
    plan.check("it never stood on the pit", function(_, ctx)
        return ctx.seen > 0 and ctx.onPit == 0, string.format("updates on the pit=%d of %d", ctx.onPit, ctx.seen)
    end)
    plan.check("no furrow on the pit", function(_, ctx)
        local f = field()
        local key = tostring(ctx.pitCell)
        return f ~= nil and f.yellow[key] == nil, "pit cell " .. key .. " furrow=" .. tostring(f and f.yellow[key])
    end)
    plan.section("OX / ground", "the yellow ox steps round the pit that opened in front of it")
end)

-- The ox never waits at its door: in a fight the doors are shut, and it goes
-- through without opening them, so Isaac gets no way out of the fight.
-- Fixture: a harmless target enemy and the room set uncleared, which shuts
-- its doors, once the yellow ox has planned its way.
S.add("OX", "shut", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ox()._test.resetEvidence()
        ctx.start = here().SafeGridIndex
        give(player, id)
    end)
    plan.waitUntil(function()
        local record = ox()._test.live().yellow
        return record ~= nil and record.path ~= nil and record.exit ~= nil, describe()
    end, 60, "the yellow ox plans its way to its door")
    plan.act(function(player, ctx)
        ctx.exit = ox()._test.live().yellow.exit
        ctx.target = H.target(player, true)
        local room = Game():GetRoom()
        room:SetClear(false)
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door then door:Close(true) end
        end
    end)
    plan.waitUntil(function(_, ctx)
        local door = Game():GetRoom():GetDoor(ctx.exit)
        return door ~= nil and not door:IsOpen(), "door " .. tostring(ctx.exit) .. " open"
    end, 30, "a fight shuts the yellow ox's door")
    plan.waitUntil(function(_, ctx)
        return state().oxen.yellow.room ~= ctx.start, describe()
    end, 900, "the yellow ox goes through its shut door")
    plan.check("it went through the shut door without opening it", function(_, ctx)
        local door = Game():GetRoom():GetDoor(ctx.exit)
        return ox()._test.evidence().through >= 1 and door ~= nil and not door:IsOpen(),
            string.format("through=%d door open=%s", ox()._test.evidence().through, tostring(door and door:IsOpen()))
    end)
    plan.act(function(_, ctx)
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
    end)
    plan.section("OX / shut", "in a fight the yellow ox walks out through the shut door, which stays shut")
end)

-- While the holder stays in the start room, the yellow ox walks on unseen,
-- room after room, and each room it walks into shows on the map. Coming into
-- a room it crossed unseen ploughs that room's furrow there and then.
S.add("OX", "ahead", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ox()._test.resetEvidence()
        local level = Game():GetLevel()
        ctx.start = here().SafeGridIndex
        ctx.path = bossRoute(level, ctx.start)
        give(player, id)
    end)
    plan.require("the boss room is at least two rooms away", function(_, ctx)
        return ctx.path ~= nil and #ctx.path >= 3, "route=" .. (ctx.path and table.concat(ctx.path, ">") or "none")
    end)
    plan.waitUntil(function(_, ctx)
        local yellow = state() and state().oxen.yellow
        if not yellow then return false, "the oxen are not summoned yet" end
        return yellow.done or yellow.from ~= nil and yellow.from ~= ctx.start and yellow.room ~= ctx.start, describe()
    end, 1500, "the yellow ox walks two rooms on while the holder stays")
    plan.check("the holder never left the start room", function(_, ctx)
        return here().SafeGridIndex == ctx.start, "here=" .. here().SafeGridIndex
    end)
    plan.check("rooms it walked into unseen, never visited, show on the map", function(_, ctx)
        local level, e = Game():GetLevel(), ox()._test.evidence()
        local shown, unvisited = 0, 0
        for _, index in ipairs(e.revealed) do
            local desc = level:GetRoomByIdx(index, 0)
            if desc.DisplayFlags & 5 == 5 then shown = shown + 1 end
            if desc.VisitedCount == 0 then unvisited = unvisited + 1 end
        end
        return e.offscreen >= 1 and shown >= 2 and unvisited >= 1, string.format(
            "unseen passes=%d revealed=[%s] shown=%d unvisited=%d", e.offscreen, table.concat(e.revealed, ","), shown, unvisited)
    end)
    -- Go into the room it crossed unseen.
    plan.act(function(player, ctx)
        local yellow = state().oxen.yellow
        ctx.crossed = yellow.from
        Game():StartRoomTransition(ctx.crossed, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx)
        return here().SafeGridIndex == ctx.crossed and RoomTransition.GetTransitionMode() == 0
            and Game():GetRoom():GetFrameCount() > 0, "room=" .. tostring(here().SafeGridIndex)
    end, 180, "arrive in the room the ox crossed unseen")
    plan.act(function()
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:IsActiveEnemy(false) then entity:Remove() end
        end
    end)
    plan.wait(3)
    plan.check("its furrow is ploughed there on arrival", function()
        local f = field()
        local s = state()
        local trail = s.trails["L" .. here().ListIndex]
        local pending = 0
        for _, stretch in ipairs(trail and trail.yellow or {}) do
            if not stretch.ploughed then pending = pending + 1 end
        end
        return size(f and f.yellow) >= 4 and trail ~= nil and pending == 0,
            string.format("cells=%d stretches=%d unploughed=%d", size(f and f.yellow), trail and trail.yellow and #trail.yellow or 0, pending)
    end)
    plan.section("OX / ahead", "staying in the start room, the map fills in room by room as the oxen walk on")
end)

-- The farmer's praise said out loud: a positive Magic Conch answer while
-- both oxen are in the same room, wherever the player is, makes the black ox
-- jealous, and it digs red rooms to the ultra secret room. Praise while they
-- are apart and other answers do nothing, praise counts once a floor, and the
-- yellow ox does nothing more. The answers are the real Magic
-- Conch's, forced through its API.
local function conch() return MagicConch and MagicConch.API end

local function ask(plan, kind)
    plan.waitUntil(function()
        return conch().GetState() == "idle", "Conch " .. tostring(conch().GetState())
    end, 240, "the Magic Conch is idle")
    -- The Conch refuses a use within 10 frames of the last one, counted from
    -- the start of the run.
    plan.wait(12)
    plan.act(function(_, ctx)
        ctx.asked = conch().TriggerMagicConch("ConchBlessing Ox test", { type = kind })
    end)
    plan.require("the Magic Conch answers " .. kind, function(_, ctx)
        return ctx.asked ~= nil and ctx.asked.success == true, "reason=" .. tostring(ctx.asked and ctx.asked.reason)
    end)
    plan.waitUntil(function() return conch().GetState() == "idle", "answering" end, 240, "the answer is given")
    plan.wait(3)
end

S.add("OX", "jealous", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ox()._test.resetEvidence()
        ctx.ultra = ox()._test.ultraRoom(Game():GetLevel())
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
    plan.wait(3)
    plan.require("the Magic Conch API, a black ox and an ultra secret room on this floor", function(_, ctx)
        local api = conch()
        local s = state()
        if not (api and type(api.TriggerMagicConch) == "function" and type(api.GetState) == "function") then
            return false, "Magic Conch API missing"
        end
        if not (s and s.oxen.black) or not ctx.ultra then
            return nil, string.format("black ox=%s ultra=%s", tostring(s and s.oxen.black ~= nil), tostring(ctx.ultra))
        end
        return true, "ultra=" .. ctx.ultra
    end)
    -- Fixture: both oxen stand still (held as if done, only so they stay put
    -- for the whole test), first both in this room with the player.
    plan.act(function(_, ctx)
        local s, index = state(), here().SafeGridIndex
        local yellow, black = s.oxen.yellow, s.oxen.black
        ctx.here = index
        ctx.away = ox()._test.neighborsOf(Game():GetLevel(), index)[1]
        yellow.room, yellow.done, yellow.next, yellow.cells, yellow.a = index, true, nil, 0, { center = true }
        black.room, black.gi, black.done, black.next, black.cells = index, #black.goals, true, nil, 0
        black.a, black.from = { center = true }, nil
        local live = ox()._test.live()
        if live.yellow then live.yellow.path = nil end
        if live.black then live.black.path = nil end
        ctx.goals = #black.goals
        ctx.yellowGoals = #yellow.goals
    end)
    plan.require("a room beside this one for an ox to stand in", function(_, ctx)
        return ctx.away ~= nil, "neighbour=" .. tostring(ctx.away)
    end)
    local function calm(label)
        plan.check(label, function(_, ctx)
            local black = state().oxen.black
            return black.done and not black.jealous and #black.goals == ctx.goals and ox()._test.evidence().jealous == 0,
                describe()
        end)
    end
    ask(plan, "positive")
    calm("praise with both oxen in the player's room does nothing (the black ox hears it too)")
    -- The yellow ox goes next door, the black ox stays here with the player.
    plan.act(function(_, ctx)
        local s = state()
        s.oxen.yellow.room, s.oxen.black.room = ctx.away, ctx.here
    end)
    ask(plan, "positive")
    calm("praise away from the yellow ox does nothing")
    -- The yellow ox comes back to the player; the black ox goes next door.
    plan.act(function(_, ctx)
        local s = state()
        s.oxen.yellow.room, s.oxen.black.room = ctx.here, ctx.away
    end)
    ask(plan, "negative")
    calm("a negative answer does nothing")
    ask(plan, "positive")
    plan.check("praise with only the yellow ox in the player's room wakes the black ox", function(_, ctx)
        local black = state().oxen.black
        return black.jealous and not black.done and #black.goals == ctx.goals + 1
            and black.goals[#black.goals] == ctx.ultra and black.gi == #black.goals, describe()
    end)
    plan.check("the yellow ox does nothing more", function(_, ctx)
        return #state().oxen.yellow.goals == ctx.yellowGoals, describe()
    end)
    ask(plan, "positive")
    plan.check("praise counts once a floor", function(_, ctx)
        return #state().oxen.black.goals == ctx.goals + 1 and ox()._test.evidence().jealous == 1, describe()
    end)
    plan.waitUntil(function(_, ctx)
        local black = state().oxen.black
        return black.room == ctx.ultra and black.done, describe()
    end, 5400, "the black ox digs its way to the ultra secret room and sleeps")
    plan.check("it dug red room doors on the way", function()
        return ox()._test.evidence().dug >= 1, "dug=" .. ox()._test.evidence().dug
    end)
    plan.check("the ultra secret room shows on the map", function(_, ctx)
        local flags = Game():GetLevel():GetRoomByIdx(ctx.ultra, 0).DisplayFlags
        return flags & 5 == 5, "flags=" .. flags
    end)
    plan.section("OX / jealous", "a red door opens in the wall where the black ox stood, and red rooms appear on the map toward the ultra secret room")
end)

-- A free floor cell with no furrow, away from both.
local function bareCell(f, room)
    local best
    for cell = 0, room:GetGridSize() - 1 do
        local key, position = tostring(cell), room:GetGridPosition(cell)
        if not f.yellow[key] and not f.black[key] and room:GetGridCollision(cell) == GridCollisionClass.COLLISION_NONE
            and room:IsPositionInRoom(position, 20) then
            local near = false
            for _, color in ipairs({ "yellow", "black" }) do
                for other in pairs(f[color]) do
                    if room:GetGridPosition(tonumber(other)):Distance(position) < 60 then near = true break end
                end
            end
            if not near then best = cell break end
        end
    end
    return best
end

-- A cell of `color`'s furrow, the middle one; with `only`, one the other
-- ox's furrow does not share.
-- Whether `at` is in the rice, where both stats are full at once.
local function nearRice(at)
    for _, spot in pairs(ox()._test.rice()) do
        if (at.X - spot.x) ^ 2 + (at.Y - spot.y) ^ 2 <= 24 ^ 2 then return true end
    end
    return false
end

-- Open cells for a fixture line: ground no ox ploughed (the cell, the row
-- two either side and the rows above and below), away from Isaac and the
-- rice, nearest the room's middle first, `apart` cells from one another.
local function openCells(room, player, count, apart)
    local T, f = ox()._test, field() or { yellow = {}, black = {} }
    local width, centre = room:GetGridWidth(), room:GetGridIndex(room:GetCenterPos())
    local standing, cost = room:GetGridIndex(player.Position), T.groundAt(room)
    local function clear(cell)
        for dy = -1, 1 do
            for dx = -2, 2 do
                local c = cell + dy * width + dx
                if f.yellow[tostring(c)] or f.black[tostring(c)] or c == standing or cost(c) ~= 1 then return false end
            end
        end
        return not nearRice(room:GetGridPosition(cell))
    end
    local found = {}
    for radius = 0, 6 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                local cell = centre + dy * width + dx
                local far = true
                for _, other in ipairs(found) do
                    if math.abs(other % width - cell % width) + math.abs(other // width - cell // width) < apart then
                        far = false
                    end
                end
                if math.max(math.abs(dx), math.abs(dy)) == radius and far and clear(cell) then
                    found[#found + 1] = cell
                    if #found == count then return found end
                end
            end
        end
    end
    return found
end

local function standOn(player, position)
    player.Position = position
    player.Velocity = Vector.Zero
end

-- Standing on 누렁소's furrow grows damage a step every two seconds up to x2;
-- 검은소's grows tears up to +2; off the furrows both wilt at the same pace.
-- The real two-second step is measured on the real clock; the ten-step caps
-- use the module's test clock (60 ticks an update) and are labelled so.
S.add("OX", "growth", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        H.refresh(player)
        ctx.damage, ctx.tears = player.Damage, tears(player)
        ctx.start = here().SafeGridIndex
        give(player, id)
    end)
    plan.waitUntil(function()
        local f = field()
        local black = state() and state().oxen.black
        return f ~= nil and size(f.yellow) >= 4 and (black == nil or size(f.black) >= 4),
            string.format("yellow=%d black=%d", size(f and f.yellow), size(f and f.black))
    end, 300, "the oxen plough a stretch of furrow")
    -- Wait until both have left (or stopped), so the furrows no longer change
    -- under the cells the checks stand on.
    plan.waitUntil(function(_, ctx)
        local s = state()
        local function settled(entry) return entry == nil or entry.room ~= ctx.start or entry.done end
        return settled(s.oxen.yellow) and settled(s.oxen.black), describe()
    end, 900, "both oxen leave the room")
    -- Fixture: once both oxen have left, a furrow and a ditch of their own,
    -- laid by the module's own plough on open ground apart from each other,
    -- so the oxen's own lines (which may run together and grow rice) never
    -- decide what the checks stand on.
    plan.act(function(player, ctx)
        local room, T = Game():GetRoom(), ox()._test
        local cells = openCells(room, player, 2, 4)
        if #cells == 2 then
            local s, desc = state(), here()
            T.plough(s, desc, room, "yellow", { cells[1] - 1, cells[1], cells[1] + 1 }, {}, 0, math.huge)
            T.plough(s, desc, room, "black", { cells[2] - 1, cells[2], cells[2] + 1 }, {}, 0, math.huge)
            ctx.yellowCell, ctx.blackCell = room:GetGridPosition(cells[1]), room:GetGridPosition(cells[2])
        end
        local bare = bareCell(field(), room)
        ctx.bare = bare and room:GetGridPosition(bare)
    end)
    plan.note("furrow cells the checks stand on", function(_, ctx)
        local function at(v) return v and string.format("(%.0f,%.0f)", v.X, v.Y) or "none" end
        return string.format("yellow=%s black=%s bare=%s", at(ctx.yellowCell), at(ctx.blackCell), at(ctx.bare))
    end)
    plan.require("open ground for a furrow and a ditch apart, and a bare cell to stand on", function(_, ctx)
        return ctx.yellowCell ~= nil and ctx.bare ~= nil, string.format("yellow=%s bare=%s", tostring(ctx.yellowCell ~= nil), tostring(ctx.bare ~= nil))
    end)
    -- Each stand is measured two updates later: StatsAPI applies a changed
    -- multiplier on the next cache evaluation.
    local function stand(where, label, damage, tearsBy)
        plan.act(function(player, ctx) standOn(player, ctx[where]) end)
        plan.wait(2)
        plan.check(label, function(player, ctx)
            local d, t = bonus(player)
            return d == damage and t == tearsBy and H.near(player.Damage, ctx.damage * damage)
                and H.near(tears(player), ctx.tears * tearsBy),
                string.format("multipliers damage x%s tears x%s; damage=%.4f (x%.3f) tears=%.4f (x%.3f)", tostring(d), tostring(t),
                    player.Damage, player.Damage / ctx.damage, tears(player), tears(player) / ctx.tears)
        end)
    end
    stand("bare", "off the lines: no bonus", 1, 1)
    stand("yellowCell", "on the yellow furrow: damage x2 at once, tears unchanged", 2, 1)
    stand("bare", "a step off it: damage back at once", 1, 1)
    stand("blackCell", "in the black ditch: tears x2 at once, damage unchanged", 1, 2)
    stand("bare", "a step off it: tears back at once", 1, 1)
    plan.section("OX / growth", "nothing is drawn on Isaac standing on a furrow or a ditch; the numbers come from the HUD")
end)

-- Rice grows where the yellow ox's furrow meets the black ox's ditch, and
-- standing on it doubles both damage and tears, which last two seconds after
-- stepping off (real time).
-- Fixture: a furrow and a ditch crossing in the middle of the start room,
-- laid by the module's own plough as if the oxen had walked them, once both
-- oxen have left.
S.add("OX", "rice", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        H.refresh(player)
        ctx.damage, ctx.tears = player.Damage, tears(player)
        ctx.start = here().SafeGridIndex
        give(player, id)
    end)
    plan.waitUntil(function(_, ctx)
        local s = state()
        local function settled(entry) return entry == nil or entry.room ~= ctx.start or entry.done end
        return s ~= nil and settled(s.oxen.yellow) and settled(s.oxen.black), describe()
    end, 900, "both oxen leave the room")
    plan.act(function(player, ctx)
        local room, T = Game():GetRoom(), ox()._test
        local width = room:GetGridWidth()
        -- A crossing near the middle, on open ground no ox has ploughed.
        ctx.cell = openCells(room, player, 1, 0)[1]
        local s, desc = state(), here()
        if not ctx.cell then return end
        T.plough(s, desc, room, "yellow", { ctx.cell - 1, ctx.cell, ctx.cell + 1 }, {}, 0, math.huge)
        T.plough(s, desc, room, "black", { ctx.cell - width, ctx.cell, ctx.cell + width }, {}, 0, math.huge)
        local bare = bareCell(field(), room)
        ctx.bare = bare and room:GetGridPosition(bare)
        standOn(player, ctx.bare)
    end)
    plan.require("an open cell near the middle that no ox has ploughed", function(_, ctx)
        return ctx.cell ~= nil and ctx.bare ~= nil, string.format("cell=%s bare=%s", tostring(ctx.cell), tostring(ctx.bare ~= nil))
    end)
    plan.wait(2)
    plan.check("rice grows where the furrow crosses the ditch", function(_, ctx)
        local spot = ox()._test.rice()[ctx.cell]
        local plant = spot and spot.ref and spot.ref.Ref
        local centre = Game():GetRoom():GetGridPosition(ctx.cell)
        return plant ~= nil and plant:Exists() and plant.Variant == ox()._test.riceVariant()
            and math.abs(spot.x - centre.X) < 1 and math.abs(spot.y - centre.Y) < 1,
            string.format("cell=%d spot=%s plant=%s", ctx.cell, spot and string.format("(%.0f,%.0f)", spot.x, spot.y) or "none",
                tostring(plant ~= nil and plant:Exists()))
    end)
    plan.check("off the lines: no bonus", function(player)
        local d, t = bonus(player)
        return d == 1 and t == 1, string.format("damage x%s tears x%s", tostring(d), tostring(t))
    end)
    plan.act(function(player, ctx)
        local spot = ox()._test.rice()[ctx.cell]
        standOn(player, Vector(spot.x, spot.y))
    end)
    plan.wait(2)
    plan.check("on the rice both at once: damage x2, tears x2", function(player, ctx)
        local d, t = bonus(player)
        return d == 2 and t == 2 and H.near(player.Damage, ctx.damage * 2) and H.near(tears(player), ctx.tears * 2),
            string.format("damage x%s=%.4f (x%.3f) tears x%s=%.4f (x%.3f)", tostring(d), player.Damage, player.Damage / ctx.damage,
                tostring(t), tears(player), tears(player) / ctx.tears)
    end)
    plan.act(function(player, ctx) standOn(player, ctx.bare) end)
    plan.wait(30)
    plan.check("a second off it: both still x2", function(player, ctx)
        local d, t = bonus(player)
        return d == 2 and t == 2 and H.near(player.Damage, ctx.damage * 2) and H.near(tears(player), ctx.tears * 2),
            string.format("damage x%s tears x%s left=%s", tostring(d), tostring(t),
                tostring(ox()._test.riceLeft()[GetPtrHash(player)]))
    end)
    plan.wait(32)
    plan.check("two seconds off it: both gone", function(player, ctx)
        local d, t = bonus(player)
        return d == 1 and t == 1 and H.near(player.Damage, ctx.damage) and H.near(tears(player), ctx.tears),
            string.format("damage x%s=%.4f tears x%s=%.4f", tostring(d), player.Damage, tostring(t), tears(player))
    end)
    plan.section("OX / rice", "a small clump of rice where the golden furrow crosses the water ditch; it grows up, its ears turn gold and it sways")
end)

-- The black ox rams the secret room's wall open once its room is clear,
-- walks in, and the secret room shows on the map.
S.add("OX", "secret", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        local level = Game():GetLevel()
        ctx.secret = ox()._test.secretRoom(level)
        -- Any room an ox may walk through will do, special rooms too.
        local ok = ox()._test.passable(level, true)
        for _, index in ipairs(ctx.secret and ox()._test.neighborsOf(level, ctx.secret) or {}) do
            if ok(index) then ctx.beside = index break end
        end
        give(player, id)
    end)
    plan.require("this floor has a secret room beside a room an ox walks through", function(_, ctx)
        return ctx.secret ~= nil and ctx.beside ~= nil, string.format("secret=%s beside=%s", tostring(ctx.secret), tostring(ctx.beside))
    end)
    plan.wait(3)
    -- Fixture: the black ox already stands in the room beside the secret room.
    plan.act(function(player, ctx)
        local black = state().oxen.black
        black.room, black.from, black.a, black.next, black.cells = ctx.beside, nil, { center = true }, nil, 0
        black.gi, black.done, black.sensed, black.opened = 1, false, nil, nil
        ctx.flagsBefore = Game():GetLevel():GetRoomByIdx(ctx.secret, 0).DisplayFlags
        Game():StartRoomTransition(ctx.beside, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx)
        return here().SafeGridIndex == ctx.beside and RoomTransition.GetTransitionMode() == 0
            and Game():GetRoom():GetFrameCount() > 0, "room=" .. tostring(here().SafeGridIndex)
    end, 180, "arrive beside the secret room")
    plan.act(function()
        -- Clear the room the way a fight would: every enemy gone.
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:IsActiveEnemy(false) then entity:Remove() end
        end
        ox()._test.resetEvidence()
    end)
    plan.waitUntil(function() return Game():GetRoom():IsClear(), "room not clear" end, 120, "the room is clear")
    plan.note("doors of the room beside the secret room", function()
        local level, room, doors = Game():GetLevel(), Game():GetRoom(), {}
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door then
                local other = level:GetRoomByIdx(door.TargetRoomIndex, 0)
                doors[#doors + 1] = string.format("%d>%d(%s):type%d:%s", slot, door.TargetRoomIndex,
                    tostring(other and other.SafeGridIndex), door.TargetRoomType, door:IsOpen() and "open" or "shut")
            end
        end
        return table.concat(doors, " ")
    end)
    plan.waitUntil(function(_, ctx)
        return state().oxen.black.room == ctx.secret, describe()
    end, 900, "the black ox walks into the secret room")
    plan.note("oxen at the end", function() return describe() end)
    plan.waitUntil(function()
        local black = state().oxen.black
        return #black.goals < 2 or black.gi == 2, describe()
    end, 300, "then it heads for the super secret room (when the floor has one)")
    plan.check("it rammed the hidden wall open", function()
        return ox()._test.evidence().opened >= 1, "opened=" .. ox()._test.evidence().opened
    end)
    plan.check("the secret room shows on the map", function(_, ctx)
        local flags = Game():GetLevel():GetRoomByIdx(ctx.secret, 0).DisplayFlags
        return flags & 5 == 5, string.format("flags %s -> %d", tostring(ctx.flagsBefore), flags)
    end)
    plan.section("OX / secret", "the black ox walks to the wall, a hole opens like a bomb's, and it goes through")
end)

-- Curse of the Lost hides the map the oxen fill in, so a holder never has it
-- (user request 2026-10-31): not when it is already there as the item comes,
-- not from the Amnesia pill, and not on a new floor; without the item it stays.
S.add("OX", "lost", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.require("the level can take and lose curses", function()
        local level = Game():GetLevel()
        return type(level.AddCurse) == "function" and type(level.RemoveCurses) == "function", "AddCurse/RemoveCurses missing"
    end)
    plan.act(function(_, ctx)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            roll.on = false
            local level = Game():GetLevel()
            if level:GetCurses() & LOST() ~= 0 then level:RemoveCurses(LOST()) end
        end)
        ox()._test.resetEvidence()
        Game():GetLevel():AddCurse(LOST(), false)
    end)
    plan.wait(5)
    plan.check("without the item the curse stays", function() return lost(), "curses=" .. Game():GetLevel():GetCurses() end)
    plan.act(function(player) give(player, id) end)
    plan.waitUntil(function() return not lost(), "curses=" .. Game():GetLevel():GetCurses() end, 10,
        "a curse already there lifts as the item comes")
    plan.act(function(player, ctx)
        ctx.lifted = ox()._test.evidence().lifted
        player:UsePill(PillEffect.PILLEFFECT_AMNESIA, PillColor.PILL_BLUE_BLUE)
        ctx.pillCast = lost()
    end)
    plan.note("the Amnesia pill cast the curse at once", function(_, ctx) return tostring(ctx.pillCast) end)
    plan.waitUntil(function(_, ctx)
        return not lost() and ox()._test.evidence().lifted > ctx.lifted,
            string.format("curses=%d lifted=%d", Game():GetLevel():GetCurses(), ox()._test.evidence().lifted)
    end, 30, "the Amnesia pill's curse lifts")
    plan.act(function(_, ctx)
        ctx.spared = ox()._test.evidence().spared
        roll.on, roll.rolled = true, 0
    end)
    S.newFloor(plan, 2)
    plan.act(function() roll.on = false end)
    plan.require("the new floor rolled the curse", function() return roll.rolled > 0, "rolled=" .. roll.rolled end)
    plan.check("a new floor has no Curse of the Lost", function()
        return not lost(), "curses=" .. Game():GetLevel():GetCurses()
    end)
    plan.check("the floor was spared it as it was made", function(_, ctx)
        local spared = ox()._test.evidence().spared - ctx.spared
        return spared > 0, string.format("spared=%d lifted=%d", spared, ox()._test.evidence().lifted)
    end)
    plan.act(function(player)
        player:RemoveCollectible(id)
        Game():GetLevel():AddCurse(LOST(), false)
    end)
    plan.wait(5)
    plan.check("once the item is gone the curse stays again", function()
        return lost(), "curses=" .. Game():GetLevel():GetCurses()
    end)
    plan.section("OX / lost", "the map stays shown with the item, through the Amnesia pill and on the next floor")
end)

-- 축 with 자: one fake rides the walking yellow ox, shoots the nearest enemy
-- by itself, takes no damage up there, and hops back beside Isaac when the ox
-- lies down (user design 2026-10-31).
S.add("OX", "rat", { conditions = true, synergies = true }, function(plan, id)
    requireModule(plan)
    -- Fixture: an ox near its door walks back to where its way began, so it
    -- stays in the room (walking, carrying its rider) while the checks run.
    local function keepWalking()
        local yellow, record = state().oxen.yellow, ox()._test.live().yellow
        if record and record.path and not yellow.done and yellow.cells > #record.path - 4 then yellow.cells = 0 end
    end
    local ratId = ConchBlessing.ItemData.RAT and ConchBlessing.ItemData.RAT.id or -1
    plan.require("자 can make fakes here (REPENTOGON)", function()
        local rat = ConchBlessing.rat
        return ratId > 0 and rat ~= nil and rat.supported(), "Rat module or REPENTOGON's PlayerManager missing"
    end)
    plan.act(function(player)
        ox()._test.resetEvidence()
        give(player, id)
    end)
    plan.waitUntil(function()
        local record = ox()._test.live().yellow
        return record ~= nil and record.path ~= nil, describe()
    end, 60, "the yellow ox plans a way to its door")
    plan.check("without 자 nobody rides the ox", function()
        return ox()._test.ride.rider == nil and ox()._test.evidence().mounts == 0,
            "mounts=" .. ox()._test.evidence().mounts
    end)
    -- Fixture: the ox starts again from the inner corner farthest from its
    -- door, so it stays in the room long enough for the checks.
    plan.act(function(player, ctx)
        local room, record = Game():GetRoom(), ox()._test.live().yellow
        local width, door = room:GetGridWidth(), record.path[#record.path]
        local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
        local best = -1
        for _, corner in ipairs({ tl, Vector(br.X, tl.Y), Vector(tl.X, br.Y), br }) do
            local cell = room:GetGridIndex(corner + (room:GetCenterPos() - corner):Resized(20))
            local d = math.abs(cell % width - door % width) + math.abs(cell // width - door // width)
            if d > best then best, ctx.far = d, cell end
        end
        local yellow, at = state().oxen.yellow, room:GetGridPosition(ctx.far)
        yellow.a, yellow.cells, record.path = { x = at.X, y = at.Y }, 0, nil
        player:AddCollectible(ratId, 0, false)
    end)
    plan.waitUntil(function(player, ctx)
        ctx.fake = ConchBlessing.rat.fakesOf(player)[1]
        return ctx.fake ~= nil, "no fake yet"
    end, 120, "자 makes a fake")
    plan.waitUntil(function(_, ctx)
        keepWalking()
        local rider = ox()._test.ride.rider
        return rider ~= nil and rider.phase == "on" and rider.hash == GetPtrHash(ctx.fake), describe()
    end, 90, "the fake hops onto the yellow ox")
    plan.check("it stands on the ox's back", function(_, ctx)
        local entity = Isaac.FindByType(EntityType.ENTITY_EFFECT, ox()._test.variant(), 0)[1]
        if not entity then return false, "no yellow ox in the room" end
        local d = ctx.fake.Position:Distance(entity.Position)
        return d < 1 and ctx.fake.SpriteOffset.Y <= -15,
            string.format("distance=%.2f spriteOffset=(%.1f,%.1f)", d, ctx.fake.SpriteOffset.X, ctx.fake.SpriteOffset.Y)
    end)
    plan.act(function(player, ctx)
        ctx.target = H.target(player, true)
        ctx.tears = 0
    end)
    plan.waitUntil(function(_, ctx)
        keepWalking()
        return H.targetReady(ctx.target)
    end, 60, "the target enemy is ready")
    plan.waitUntil(function(_, ctx)
        keepWalking()
        for _, tear in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR)) do
            local spawner = tear.SpawnerEntity
            if spawner and GetPtrHash(spawner) == GetPtrHash(ctx.fake) and not tear:GetData().__ConchBlessingOxRideSeen then
                tear:GetData().__ConchBlessingOxRideSeen = true
                ctx.tears = ctx.tears + 1
            end
        end
        local target = ctx.target
        return ctx.tears > 0 and target:Exists() and target.HitPoints < target.MaxHitPoints,
            string.format("rider tears=%d target hp=%.1f/%.1f aimed=%d", ctx.tears, target.HitPoints,
                target.MaxHitPoints, ox()._test.evidence().aimed)
    end, 240, "the rider shoots the enemy by itself and hurts it")
    plan.act(function(_, ctx)
        local fake = ctx.fake
        ctx.health = { fake:GetHearts(), fake:GetSoulHearts(), fake:GetBlackHearts(), fake:GetBoneHearts() }
        ctx.shielded = ox()._test.evidence().shielded
        ctx.taken = fake:TakeDamage(1, 0, EntityRef(ctx.target), 0)
    end)
    plan.wait(2)
    plan.check("on the ox the rider takes no damage", function(_, ctx)
        local fake = ctx.fake
        local now = { fake:GetHearts(), fake:GetSoulHearts(), fake:GetBlackHearts(), fake:GetBoneHearts() }
        local same = true
        for k = 1, 4 do if now[k] ~= ctx.health[k] then same = false end end
        return same and ox()._test.evidence().shielded > ctx.shielded and not fake:IsDead(),
            string.format("taken=%s hearts %s -> %s", tostring(ctx.taken), table.concat(ctx.health, "/"), table.concat(now, "/"))
    end)
    -- The ox lies down where it is: the rider hops back beside Isaac.
    plan.act(function(_, ctx)
        ctx.sprite = ox()._test.ride.rider.sprite
        state().oxen.yellow.done = true
    end)
    plan.waitUntil(function() return ox()._test.ride.rider == nil, describe() end, 60,
        "the rider hops off when the ox sleeps")
    plan.check("off the ox it stands by Isaac with its own drawing back", function(player, ctx)
        local fake, sprite = ctx.fake, ctx.sprite
        local d = fake.Position:Distance(player.Position)
        return d < 80 and math.abs(fake.SpriteOffset.X - sprite.X) < 1e-6 and math.abs(fake.SpriteOffset.Y - sprite.Y) < 1e-6,
            string.format("distance=%.1f spriteOffset=(%.1f,%.1f)", d, fake.SpriteOffset.X, fake.SpriteOffset.Y)
    end)
    plan.wait(20)
    plan.check("a sleeping ox carries nobody", function()
        return ox()._test.ride.rider == nil, describe()
    end)
    plan.section("OX / rat", "Isaac's double hops onto the walking yellow ox, shoots the nearest enemy from its back, "
        .. "and hops back beside Isaac when the ox lies down")
end, { "rat" })

return C
