local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 축 (Ox): 누렁소 and 검은소, the two oxen of the 황희 tale (user design
-- 2026-10-31). While someone holds it, every floor has a yellow ox walking
-- slowly to the boss room and a black ox walking to the secret room. They
-- break every breakable obstacle in their way and plough a furrow one tile
-- wide behind them, and a room on the map shows up as soon as an ox walks
-- into it. Standing on 누렁소's furrow doubles the holder's damage, standing
-- in 검은소's ditch doubles their tears, only while they stand there (user
-- request 2026-10-31: nothing grows or wilts); in the rice where the two
-- lines meet they have both, and keep both for two seconds after stepping off.
--
-- The oxen walk on whether or not anyone is in their room. In a player's room
-- an ox heads for the door that leads one room closer to its goal and waits
-- there until the door is open; a room nobody is in it crosses unseen, and
-- that stretch is ploughed when a player first comes in. The black ox rams
-- the secret room's wall open once its room is clear. In its goal room an ox
-- walks to the middle; with nowhere left to go it lies down and sleeps.
-- The oxen are effect entities, so Kronos never sees them; their place, goal
-- and furrows are floor state. Since
-- they fill the map in, a holder is never under Curse of the Lost, which
-- hides the map (the Amnesia pill casts it too).
--
-- Rooms connect through REPENTOGON's RoomDescriptor:GetNeighboringRooms when
-- it is there, and otherwise through each room shape's door cells. Inside a
-- room an ox walks only where the engine's own pathfinder lets a ground NPC
-- walk (the room's grid path costs), crushing rocks on the way like an NPC
-- that can crush rocks; it never crosses a pit (user request 2026-10-31).
--
-- The furrow is the line the plough's share cuts behind the ox, round its
-- turns, stamped into the room's floor a quarter of a cell at a time as the
-- share passes: an effect with FLAG_RENDER_FLOOR is drawn into the floor and
-- then removed by the engine (measured 2026-10-31), so each quarter is
-- stamped once a visit; stamped again it would only darken.
local SaveManager = require("scripts.lib.save_manager")
local definitions = require("scripts.entities.definitions")
local definition, furrowDefinition, riceDefinition = definitions.OX, definitions.OX_FURROW, definitions.OX_RICE

local M = {}
ConchBlessing.ox = M

local OX_ID = Isaac.GetItemIdByName("Ox")
local ANM2 = "gfx/effects/conch_ox.anm2"
local MARK = "__ConchBlessingOx"

M.data = {
    -- 축 is second of the twelve, so its numbers are twos.
    damage = 2,        -- 누렁소's furrow doubles damage while it is stood on...
    tears = 2,         -- ...and 검은소's ditch tears (user requests 2026-10-31: x2, only while stood on)
    riceHold = 60,     -- the rice gives both, and keeps them two seconds after stepping off (user request 2026-10-31)
    speed = 80 / 30,   -- two tiles a second
    width = 1,         -- a furrow is one tile wide, only where the ox walked (user request 2026-10-31)
    rideHop = 12,      -- updates 자's fake takes to hop on or off 누렁소...
    rideArc = 10,      -- ...rising this many pixels on the way
}

local COLORS = { "yellow", "black" }
local SUBTYPE = { yellow = 0, black = 1 }
local ANIM = { yellow = "Yellow", black = "Black" }
-- Furrow pieces: 24 a row (quarters of the plough's line, see LINE), two
-- variant rows a colour (see docs/previews/ox-revision/furrow.py).
local N, E, S, W = 1, 2, 4, 8
local PIECES, VARIANTS = 24, 2
local ROW = { yellow = 0, black = 2 }
local SLOT_BIT = { [0] = W, [4] = W, [1] = N, [5] = N, [2] = E, [6] = E, [3] = S, [7] = S }
local LOST = LevelCurse.CURSE_OF_THE_LOST

local function effectVariant(entry)
    local found = -1
    if entry and type(Isaac.GetEntityTypeByName) == "function" and type(Isaac.GetEntityVariantByName) == "function" then
        local ok, entityType, value = pcall(function()
            return Isaac.GetEntityTypeByName(entry.name), Isaac.GetEntityVariantByName(entry.name)
        end)
        if ok and entityType == entry.id and type(value) == "number" and value > 0 then found = value end
    end
    if found <= 0 and OX_ID > 0 then
        ConchBlessing.printError("Ox: the effect '" .. tostring(entry and entry.name)
            .. "' is not registered; restart the game after entities2.xml changes")
    end
    return found
end
local variant = effectVariant(definition)
local furrowVariant = effectVariant(furrowDefinition)
local riceVariant = effectVariant(riceDefinition)

-- Closed until game start has read the run's saves; a reload inside a run
-- (REPENTOGON can tell) is already in one.
local started = type(Isaac.IsInGame) == "function" and Isaac.IsInGame() == true
local live = {}           -- [color] = { ref, path, exit, ploughed } for the ox in this room
local materialized        -- ListIndex of the room whose unseen furrows were ploughed on entry
local boosted = {}        -- [GetPtrHash(player)] = whether Ox's multipliers are on; nil = not looked at yet
local riceLeft = {}       -- [GetPtrHash(player)] = updates the rice's bonus still lasts
local stamped = {}        -- ["color:cell"] = directions already stamped into this room's floor
local furrowVersion, furrowSynced = 0, -1 -- a furrow cell gaining a direction anywhere bumps the version
local rice = {}          -- [cell] = { x, y, ref } of this room's rice, where the two lines meet
-- Runtime evidence for conch_test ox; never saved.
local evidence
local function resetEvidence()
    evidence = { broken = 0, ploughed = 0, passed = 0, revealed = {}, opened = 0, steps = 0, spawned = 0, stuck = {},
        blows = 0, offscreen = 0, dug = 0, jealous = 0, stamps = {}, replans = 0, waits = 0, through = 0, rice = 0, quiet = 0,
        spared = 0, lifted = 0, mounts = 0, dismounts = 0, aimed = 0, releases = 0, shielded = 0 }
end
resetEvidence()

local function member(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function isActingPlayer(player)
    if not player then return false end
    if type(player.IsDead) == "function" and player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

-- Whether a living player holds the item.
local function anyHolder()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player and player:HasCollectible(OX_ID) and isActingPlayer(player) then return true end
    end
    return false
end

-- ------------------------------------------------------------------ pure rules

-- Breadth-first route over rooms from `from` to `to`, passing only through
-- rooms `through` allows (the goal itself may be any room).
local function route(from, to, neighbors, through)
    if from == to then return { from } end
    local previous, queue, head = { [from] = from }, { from }, 1
    while head <= #queue do
        local node = queue[head]
        head = head + 1
        for _, nextNode in ipairs(neighbors(node)) do
            if previous[nextNode] == nil and (nextNode == to or through(nextNode)) then
                previous[nextNode] = node
                if nextNode == to then
                    local path = { to }
                    while path[1] ~= from do table.insert(path, 1, previous[path[1]]) end
                    return path
                end
                queue[#queue + 1] = nextNode
            end
        end
    end
    return nil
end

-- The cheapest four-way path over a room grid `width` cells wide and `size`
-- cells long from `start` to `goal`. `cost(cell)` is the cost of stepping on
-- a cell, or nil where the ox cannot go. Turning costs half a step, so the ox
-- ploughs straight lines rather than a staircase. Returns the path and true;
-- when the goal cannot be reached, the path to the reachable cell nearest it
-- and false (`partial`), or nil.
local function findPath(width, size, start, goal, cost, partial)
    if start == goal then return { start }, true end
    local deltas = { -width, width, -1, 1 }
    local goalColumn, goalRow = goal % width, math.floor(goal / width)
    local function guess(cell)
        return math.abs(cell % width - goalColumn) + math.abs(math.floor(cell / width) - goalRow)
    end
    local heap, spent, came, closed = {}, {}, {}, {}
    local function push(key, score)
        heap[#heap + 1] = { key, score }
        local i = #heap
        while i > 1 do
            local parent = math.floor(i / 2)
            if heap[parent][2] <= heap[i][2] then break end
            heap[parent], heap[i] = heap[i], heap[parent]
            i = parent
        end
    end
    local function pop()
        local top, last = heap[1], table.remove(heap)
        if #heap > 0 then
            heap[1] = last
            local i = 1
            while true do
                local left, right, least = i * 2, i * 2 + 1, i
                if left <= #heap and heap[left][2] < heap[least][2] then least = left end
                if right <= #heap and heap[right][2] < heap[least][2] then least = right end
                if least == i then break end
                heap[least], heap[i] = heap[i], heap[least]
                i = least
            end
        end
        return top[1]
    end
    -- A key is cell * 5 + the direction it was entered by (0 for the start).
    local first = start * 5
    spent[first] = 0
    push(first, guess(start))
    local nearest = first
    local function walkBack(key)
        local path = { math.floor(key / 5) }
        while came[key] do
            key = came[key]
            table.insert(path, 1, math.floor(key / 5))
        end
        return path
    end
    while #heap > 0 do
        local key = pop()
        if not closed[key] then
            closed[key] = true
            local cell, came_by = math.floor(key / 5), key % 5
            if cell == goal then return walkBack(key), true end
            local best = guess(math.floor(nearest / 5))
            if guess(cell) < best or guess(cell) == best and spent[key] < spent[nearest] then nearest = key end
            local column = cell % width
            for direction = 1, 4 do
                local nextCell = cell + deltas[direction]
                local inRow = (direction ~= 3 or column > 0) and (direction ~= 4 or column < width - 1)
                if inRow and nextCell >= 0 and nextCell < size then
                    local step = cost(nextCell)
                    if step then
                        local nextKey = nextCell * 5 + direction
                        local total = spent[key] + step + ((came_by ~= 0 and came_by ~= direction) and 0.5 or 0)
                        if not closed[nextKey] and (spent[nextKey] == nil or total < spent[nextKey]) then
                            spent[nextKey], came[nextKey] = total, key
                            push(nextKey, total + guess(nextCell))
                        end
                    end
                end
            end
        end
    end
    if partial then return walkBack(nearest), false end
    return nil
end

-- The line the plough cuts (user request 2026-10-31: a line, not tiles). The
-- ox walks along rows and columns and turns in a quarter circle of half a
-- cell, so in a cell the line is a straight half (an edge to the middle) or an
-- arc (one edge round the corner to the next), each cut into quarters, the
-- pieces the plough stamps (docs/previews/ox-revision/furrow.py draws them).
-- A straight quarter is side * 2 + (0 at the edge, 1 at the middle), sides
-- N, E, S, W being 0-3; an arc quarter is 8 + corner * 4 + k, corners N-E,
-- E-S, S-W, W-N being 0-3 and k counted from the first side to the second.
-- Progress `p` along a way of cells runs 0 at the first cell's middle to
-- #path - 1 at the last's; cell j spans j - 1.5 (its entry edge) to j - 0.5.
local LINE = {
    index = { [N] = 0, [E] = 1, [S] = 2, [W] = 3 },
    side = { [0] = N, [1] = E, [2] = S, [3] = W },
    opposite = { [N] = S, [S] = N, [E] = W, [W] = E },
    corner = { [N] = { [E] = 0 }, [E] = { [S] = 1 }, [S] = { [W] = 2 }, [W] = { [N] = 3 } },
    corners = { [0] = { N, E }, [1] = { E, S }, [2] = { S, W }, [3] = { W, N } },
    edge = { [N] = { 0, -1 }, [E] = { 1, 0 }, [S] = { 0, 1 }, [W] = { -1, 0 } },
    half = 20,  -- half a cell in world units: the middle, and a turn's radius
    near = 12,  -- how close to the line a holder stands on the furrow
    meet = 8,   -- how close the two lines come where rice grows
    rice = 16,  -- how close to the rice a holder stands in it
}

-- The piece for quarter q (0-3) of a cell the line enters by side `a` and
-- leaves by side `b` (nil where a way starts or ends in the middle).
local function quarterPiece(a, b, q)
    -- In and straight out (or in and back out the same side): two straight halves.
    if a and b and (LINE.opposite[a] == b or a == b) then
        if q < 2 then return LINE.index[a] * 2 + q end
        return LINE.index[b] * 2 + (3 - q)
    elseif a and b then
        local c = LINE.corner[a][b]
        if c then return 8 + c * 4 + q end
        return 8 + LINE.corner[b][a] * 4 + (3 - q)
    elseif a then
        if q < 2 then return LINE.index[a] * 2 + q end
    elseif b then
        if q >= 2 then return LINE.index[b] * 2 + (3 - q) end
    end
    return nil
end

-- The sides cell `path[j]` is entered and left by; at the ends, the door
-- sides `first` and `last` (nil for a way that starts or ends in the middle).
local function cellSides(path, j, width, first, last)
    local function toward(other)
        local d = other - path[j]
        return d == -width and N or d == 1 and E or d == width and S or d == -1 and W or nil
    end
    local a = j > 1 and toward(path[j - 1]) or (j == 1 and first or nil)
    local b = j < #path and toward(path[j + 1]) or (j == #path and last or nil)
    return a, b
end

-- Where the ox (or its share) is at progress `p`: the cell index, the offset
-- from that cell's middle and the direction it heads, in world units.
local function curveAt(path, width, p, first, last)
    local j = math.max(1, math.min(#path, math.floor(p + 1.5)))
    local a, b = cellSides(path, j, width, first, last)
    local t = math.max(a and 0 or 0.5, math.min(b and 1 or 0.5, p - (j - 1.5)))
    local h = LINE.half
    if a and b and a ~= b and LINE.opposite[a] ~= b then
        local ea, eb = LINE.edge[a], LINE.edge[b]
        local cx, cy = (ea[1] + eb[1]) * h, (ea[2] + eb[2]) * h
        local sx, sy, fx, fy = ea[1] * h - cx, ea[2] * h - cy, eb[1] * h - cx, eb[2] * h - cy
        local angle = t * math.pi / 2
        local c, s = math.cos(angle), math.sin(angle)
        return j, cx + sx * c + fx * s, cy + sy * c + fy * s, fx * c - sx * s, fy * c - sy * s
    end
    if t < 0.5 then
        local e = LINE.edge[a]
        return j, e[1] * h * (1 - 2 * t), e[2] * h * (1 - 2 * t), -e[1], -e[2]
    end
    local e = b and LINE.edge[b] or { 0, 0 }
    return j, e[1] * h * (2 * t - 1), e[2] * h * (2 * t - 1), e[1], e[2]
end

-- How far the point (x, y), measured from a cell's middle in world units,
-- lies from that cell's drawn pieces (`mask`, a bit a piece).
local function furrowDistance(mask, x, y)
    local best, h = math.huge, LINE.half
    for piece = 0, 23 do
        if mask & (1 << piece) ~= 0 then
            local d
            if piece < 8 then
                local e, part = LINE.edge[LINE.side[piece // 2]], piece % 2
                local from, to = h * (1 - part * 0.5), h * (0.5 - part * 0.5)
                -- Along the half from the edge to the middle: clamp, then measure.
                local along = math.max(to, math.min(from, x * e[1] + y * e[2]))
                d = math.sqrt((x - e[1] * along) ^ 2 + (y - e[2] * along) ^ 2)
            else
                local sides, k = LINE.corners[(piece - 8) // 4], (piece - 8) % 4
                local ea, eb = LINE.edge[sides[1]], LINE.edge[sides[2]]
                local cx, cy = (ea[1] + eb[1]) * h, (ea[2] + eb[2]) * h
                local vx, vy = x - cx, y - cy
                local angle = math.atan(vx * (eb[1] * h - cx) + vy * (eb[2] * h - cy),
                    vx * (ea[1] * h - cx) + vy * (ea[2] * h - cy))
                angle = math.max(k * math.pi / 8, math.min((k + 1) * math.pi / 8, angle))
                local px = cx + (ea[1] * h - cx) * math.cos(angle) + (eb[1] * h - cx) * math.sin(angle)
                local py = cy + (ea[2] * h - cy) * math.cos(angle) + (eb[2] * h - cy) * math.sin(angle)
                d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
            end
            if d < best then best = d end
        end
    end
    return best
end

-- A point a fraction `f` along a piece's line, from a cell's middle in world units.
local function piecePoint(piece, f)
    local h = LINE.half
    if piece < 8 then
        local e, part = LINE.edge[LINE.side[piece // 2]], piece % 2
        local along = h * (1 - part * 0.5) - h * 0.5 * f
        return e[1] * along, e[2] * along
    end
    local sides, k = LINE.corners[(piece - 8) // 4], (piece - 8) % 4
    local ea, eb = LINE.edge[sides[1]], LINE.edge[sides[2]]
    local cx, cy = (ea[1] + eb[1]) * h, (ea[2] + eb[2]) * h
    local angle = (k + f) * math.pi / 8
    local c, s = math.cos(angle), math.sin(angle)
    return cx + (ea[1] * h - cx) * c + (eb[1] * h - cx) * s, cy + (ea[2] * h - cy) * c + (eb[2] * h - cy) * s
end

-- Where in a cell the yellow ox's furrow (`yellow`, a mask of pieces) meets
-- the black ox's ditch (`black`): of the furrow's points within LINE.meet of
-- the ditch, the one nearest the cell's middle, so the rice stands where the
-- lines cross or in the middle of where they run together; nil if they never
-- come that close.
local function meetPoint(yellow, black)
    local best, bx, by
    for piece = 0, 23 do
        if yellow & (1 << piece) ~= 0 then
            for step = 0, 4 do
                local x, y = piecePoint(piece, step / 4)
                local d = furrowDistance(black, x, y)
                local score = x * x + y * y + d
                if d <= LINE.meet and (not best or score < best) then best, bx, by = score, x, y end
            end
        end
    end
    return bx, by
end

-- The frame of a piece of `color`'s furrow on `cell`; the variant follows the
-- cell, so a cell looks the same each visit.
local function pieceFrame(color, piece, cell)
    return (ROW[color] + (cell * 7 + cell // 13) % VARIANTS) * PIECES + piece
end

-- ------------------------------------------------------------------ the level
local function roomAt(level, index)
    if index == nil or index < 0 then return nil end
    local ok, desc = pcall(level.GetRoomByIdx, level, index, 0)
    if ok and desc and desc.Data and desc.GridIndex >= 0 then return desc end
    return nil
end

local function mainRoom(level)
    local desc = level:GetCurrentRoomDesc()
    if not desc or not desc.Data or desc.GridIndex < 0 then return nil end
    if type(level.GetDimension) == "function" then
        local ok, dimension = pcall(level.GetDimension, level)
        if ok and dimension ~= 0 then return nil end
    end
    local main = roomAt(level, desc.SafeGridIndex)
    if not main or main.ListIndex ~= desc.ListIndex then return nil end
    return desc
end

-- Each room shape's door slots and the level cell beyond each, from the
-- room's safe grid index (the engine's own layout, 13 cells to a row).
local L, U, R, D = -1, -13, 1, 13
local DOOR_CELLS = {
    [RoomShape.ROOMSHAPE_1x1] = { [0] = L, [1] = U, [2] = R, [3] = D },
    [RoomShape.ROOMSHAPE_IH] = { [0] = L, [2] = R },
    [RoomShape.ROOMSHAPE_IV] = { [1] = U, [3] = D },
    [RoomShape.ROOMSHAPE_1x2] = { [0] = L, [1] = U, [2] = R, [3] = D + D, [4] = D + L, [6] = D + R },
    [RoomShape.ROOMSHAPE_IIV] = { [1] = U, [3] = D + D },
    [RoomShape.ROOMSHAPE_2x1] = { [0] = L, [1] = U, [2] = R + R, [3] = D, [5] = R + U, [7] = R + D },
    [RoomShape.ROOMSHAPE_IIH] = { [0] = L, [2] = R + R },
    [RoomShape.ROOMSHAPE_2x2] = { [0] = L, [1] = U, [2] = R + R, [3] = D + D, [4] = D + L, [5] = R + U,
        [6] = R + D + R, [7] = R + D + D },
    [RoomShape.ROOMSHAPE_LTL] = { [0] = L, [1] = D + L + U, [2] = R, [3] = D + L + D, [4] = D + L + L, [5] = U,
        [6] = D + R, [7] = D + D },
    [RoomShape.ROOMSHAPE_LTR] = { [0] = L, [1] = U, [2] = R, [3] = D + D, [4] = D + L, [5] = D + R + U,
        [6] = D + R + R, [7] = D + R + D },
    [RoomShape.ROOMSHAPE_LBL] = { [0] = L, [1] = U, [2] = R + R, [3] = D, [4] = R + D + L, [5] = R + U,
        [6] = R + D + R, [7] = R + D + D },
    [RoomShape.ROOMSHAPE_LBR] = { [0] = L, [1] = U, [2] = R + R, [3] = D + D, [4] = D + L, [5] = R + U,
        [6] = D + R, [7] = R + D },
}

local SECRET = { [RoomType.ROOM_SECRET] = true, [RoomType.ROOM_SUPERSECRET] = true, [RoomType.ROOM_ULTRASECRET] = true }

-- The rooms a room's door cells touch, by safe grid index in door-slot order.
local function touching(level, desc, index)
    local list = {}
    local cells = DOOR_CELLS[desc.Data.Shape] or {}
    local doors = tonumber(desc.Data.Doors) or 0
    local column = index % 13
    for slot = 0, 7 do
        local delta = cells[slot]
        if delta and doors & (1 << slot) ~= 0 then
            local cell = index + delta
            if cell >= 0 and cell < 169 and math.abs(cell % 13 - column) <= 2 then
                local other = roomAt(level, cell)
                if other and other.SafeGridIndex ~= index then list[#list + 1] = other end
            end
        end
    end
    return list
end

-- The rooms a room's doors lead to, by safe grid index in door-slot order.
-- REPENTOGON names the engine's own doors; the shape's door cells add the
-- secret rooms behind hidden walls and stand in for everything without it.
local function neighborsOf(level, index)
    local desc = roomAt(level, index)
    local list, seen = {}, {}
    if not desc then return list end
    local function add(safe)
        if safe and safe >= 0 and safe ~= index and not seen[safe] then
            seen[safe] = true
            list[#list + 1] = safe
        end
    end
    local exact = member(desc, "GetNeighboringRooms")
    local found
    if type(exact) == "function" then
        local ok, result = pcall(exact, desc)
        if ok and type(result) == "table" then found = result end
    end
    if found then
        for slot = 0, 7 do
            local other = found[slot]
            if other then add(member(other, "SafeGridIndex")) end
        end
    end
    for _, other in ipairs(touching(level, desc, index)) do
        if not found or SECRET[other.Data.Type] then add(other.SafeGridIndex) end
    end
    return list
end

-- Oxen walk through ordinary rooms; special rooms are normally dead ends,
-- and only a route that needs one (another mod's layout) passes through it.
-- Hidden secret rooms are never on the way.
-- The rooms an ox may walk through on the shortest way (user request
-- 2026-10-31): any room but a secret one, whose walls are hidden; a boss room
-- only with `bosses` (on an XL floor the last boss room lies behind the
-- first); the goal always. Locked doors do not matter: it goes through them.
local function passable(level, bosses)
    return function(index)
        local desc = roomAt(level, index)
        return desc ~= nil and not SECRET[desc.Data.Type] and (bosses or desc.Data.Type ~= RoomType.ROOM_BOSS)
    end
end

local function bossRoom(level)
    local ok, list = pcall(level.GetLastBossRoomListIndex, level)
    local rooms = level:GetRooms()
    if ok and type(list) == "number" and list >= 0 and list < rooms.Size then
        local desc = rooms:Get(list)
        if desc and desc.Data and desc.GridIndex >= 0 then return desc.SafeGridIndex end
    end
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc and desc.Data and desc.Data.Type == RoomType.ROOM_BOSS and desc.GridIndex >= 0 then return desc.SafeGridIndex end
    end
    return nil
end

local function secretRoom(level)
    local rooms, super = level:GetRooms(), nil
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc and desc.Data and desc.GridIndex >= 0 then
            if desc.Data.Type == RoomType.ROOM_SECRET then return desc.SafeGridIndex end
            if desc.Data.Type == RoomType.ROOM_SUPERSECRET then super = super or desc.SafeGridIndex end
        end
    end
    return super
end

-- Shows a room on the map, shape and icon, the way the maps do.
local function reveal(level, index)
    local desc = roomAt(level, index)
    if not desc then return end
    desc.DisplayFlags = desc.DisplayFlags | 5
    if type(level.UpdateVisibility) == "function" then level:UpdateVisibility() end
    evidence.revealed[#evidence.revealed + 1] = index
end

-- ------------------------------------------------------------------ floor state
-- Each ox walks one stretch at a time inside a room: from where it came in
-- (`a`: { from = room } for the door from that room, { x, y } where it was
-- summoned, or { center = true }) to the door toward its next room (`next`)
-- or, in a goal room, to the middle (`next == false`). `cells` is how far
-- along the stretch it has walked. The black ox has two goals in turn: the
-- secret room, then the super secret room.
local function secretRooms(level)
    local rooms, secret, super = level:GetRooms(), nil, nil
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc and desc.Data and desc.GridIndex >= 0 then
            if desc.Data.Type == RoomType.ROOM_SECRET then secret = secret or desc.SafeGridIndex end
            if desc.Data.Type == RoomType.ROOM_SUPERSECRET then super = super or desc.SafeGridIndex end
        end
    end
    local list = {}
    if secret then list[#list + 1] = secret end
    if super then list[#list + 1] = super end
    return list
end

-- An ox saved before the stretch model (one goal, a position) carries on.
local function normalize(ox)
    if ox.goals then return ox end
    ox.goals, ox.gi = { ox.goal }, 1
    ox.a = ox.x and { x = ox.x, y = ox.y } or (ox.from and { from = ox.from }) or { center = true }
    ox.cells, ox.goal, ox.x, ox.y = 0, nil, nil, nil
    return ox
end

local function floorState(create, level, desc, player)
    local save = SaveManager.GetFloorSave and SaveManager.GetFloorSave(nil)
    if not save then return nil end
    if save.ox or not create then
        if save.ox then
            save.ox.trails = save.ox.trails or {}
            save.ox.walls = save.ox.walls or {}
            for _, ox in pairs(save.ox.oxen) do normalize(ox) end
            if not save.ox.pieces then
                -- A floor saved before the plough's line kept the directions through
                -- a cell (`bits`), or before that 0 (along a row) or 1 (along a
                -- column); each direction becomes the straight half toward it.
                for _, field in pairs(save.ox.fields) do
                    for _, cells in pairs(field) do
                        for key, value in pairs(cells) do
                            local dirs = save.ox.bits and value or (value == 1 and (N | S) or (E | W))
                            local mask = 0
                            for side, index in pairs(LINE.index) do
                                if dirs & side ~= 0 then mask = mask | (3 << (index * 2)) end
                            end
                            cells[key] = mask
                        end
                    end
                end
                save.ox.pieces, save.ox.bits = true, nil
            end
        end
        return save.ox
    end
    local state = { oxen = {}, fields = {}, trails = {}, walls = {}, pieces = true }
    local boss = bossRoom(level)
    local goals = { yellow = boss and { boss } or {}, black = secretRooms(level) }
    for _, color in ipairs(COLORS) do
        if #goals[color] > 0 then
            local offset = color == "yellow" and -24 or 24
            state.oxen[color] = { goals = goals[color], gi = 1, room = desc.SafeGridIndex, cells = 0,
                a = { x = player.Position.X + offset, y = player.Position.Y + 8 }, done = false, fresh = true }
        end
    end
    save.ox = state
    return state
end

local function fieldOf(state, desc, create)
    local key = "L" .. desc.ListIndex
    local field = state.fields[key]
    if not field and create then
        field = { yellow = {}, black = {} }
        state.fields[key] = field
    end
    return field
end

-- The stretches an ox has walked in a room, so a room it crossed while
-- nobody watched gets its furrow when someone first comes in.
local function trailOf(state, desc, color)
    local key = "L" .. desc.ListIndex
    local trail = state.trails[key] or {}
    state.trails[key] = trail
    trail[color] = trail[color] or {}
    return trail[color]
end

-- How many grid cells an ox walks across a room nobody is in: about ten a
-- room cell, half that to the middle.
local SHAPE_CELLS = {
    [RoomShape.ROOMSHAPE_1x2] = 2, [RoomShape.ROOMSHAPE_IIV] = 2, [RoomShape.ROOMSHAPE_2x1] = 2,
    [RoomShape.ROOMSHAPE_IIH] = 2, [RoomShape.ROOMSHAPE_2x2] = 3, [RoomShape.ROOMSHAPE_LTL] = 3,
    [RoomShape.ROOMSHAPE_LTR] = 3, [RoomShape.ROOMSHAPE_LBL] = 3, [RoomShape.ROOMSHAPE_LBR] = 3,
}
local function crossing(desc, toMiddle)
    return (SHAPE_CELLS[desc.Data.Shape] or 1) * (toMiddle and 5 or 10)
end

local function step() return M.data.speed / 40 end -- grid cells an update

-- ------------------------------------------------------------------ the oxen
-- What an ox crushes as it walks, like an NPC that can crush rocks: every
-- block a bomb could break (user request 2026-10-31: only pits stop it). TNT
-- and bomb rocks it crushes without setting them off (`QUIET`), so nothing
-- blows up in the holder's face. Metal blocks, pillars, key blocks and
-- statues, which no bomb breaks, it walks round.
local BREAKABLE, QUIET = {}, {}
for _, name in ipairs({ "GRID_ROCK", "GRID_ROCKT", "GRID_ROCK_ALT", "GRID_ROCK_ALT2", "GRID_ROCK_SS",
    "GRID_ROCK_SPIKED", "GRID_ROCK_GOLD", "GRID_POOP", "GRID_SPIDERWEB", "GRID_TNT", "GRID_ROCK_BOMB" }) do
    if GridEntityType[name] then BREAKABLE[GridEntityType[name]] = true end
end
for _, name in ipairs({ "GRID_TNT", "GRID_ROCK_BOMB" }) do
    if GridEntityType[name] then QUIET[GridEntityType[name]] = true end
end

-- The cost of a step on `cell` for an ox: the ground the engine's pathfinder
-- walks a grounded NPC over, read from the room's grid path costs. Below 900
-- is open ground, 900-999 is ground it takes only to save a step (a monster's
-- trail, a fire place), and 1000 and up is no ground at all (grid entities 1000, pits
-- 3000, grimaces 3999). A cell whose grid collides (`solid`) is no ground
-- either: a pit that just opened has no path cost until its next update
-- (measured 2026-10-31). A standing rock, poop or web is crushed on the way.
local function groundCost(gridPath, breakable, solid)
    if breakable then return 2 end
    if solid or gridPath >= 1000 then return nil end
    if gridPath >= 900 then return 2 end
    return 1
end

local function groundAt(room)
    return function(cell)
        if not room:IsPositionInRoom(room:GetGridPosition(cell), 0) then return nil end
        local grid = room:GetGridEntity(cell)
        local breakable = grid ~= nil and BREAKABLE[grid:GetType()] == true
            and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE
        return groundCost(room:GetGridPath(cell), breakable,
            room:GetGridCollision(cell) ~= GridCollisionClass.COLLISION_NONE)
    end
end

-- The room's cross (user request 2026-10-31): the rows of the places a door
-- can go on its left and right walls and the columns of those on its top and
-- bottom walls, drawn right across the room, whether a door is there or not.
-- A 1x1 room has one row and one column through its middle; a 2x2 room two of
-- each. Returns the rows and columns as sets.
local function doorLines(room)
    local rows, columns, width = {}, {}, room:GetGridWidth()
    local allowed, place = member(room, "IsDoorSlotAllowed"), member(room, "GetDoorSlotPosition")
    if type(place) ~= "function" then return rows, columns end
    for slot = 0, 7 do
        if type(allowed) ~= "function" or allowed(room, slot) then
            local ok, position = pcall(place, room, slot)
            if ok and position then
                local cell = room:GetGridIndex(position)
                -- Left and right doors (even slots) mark a row, top and bottom ones a column.
                if slot % 2 == 0 then rows[cell // width] = true else columns[cell % width] = true end
            end
        end
    end
    return rows, columns
end

-- The cost of a step for the ox's way: the ground's cost, one more off the
-- room's cross, so it makes for the cross and follows it to its door rather
-- than hugging a wall.
local function cellCost(room)
    local ground, rows, columns = groundAt(room), doorLines(room)
    local width = room:GetGridWidth()
    return function(cell)
        local cost = ground(cell)
        if cost and not (rows[cell // width] or columns[cell % width]) then cost = cost + 1 end
        return cost
    end
end

-- The ox's way over the ground from cell `from` to `to`, and whether it gets
-- there; when it cannot, the way to the nearest cell it can reach.
local function pathIn(room, from, to)
    return findPath(room:GetGridWidth(), room:GetGridSize(), from, to, cellCost(room), true)
end

-- The way an ox takes across a room: to its door (`toDoor`), or to the
-- middle; a middle it cannot walk to it gives up and stays at the entrance it
-- came in by (user request 2026-10-31).
local function wayIn(room, from, to, toDoor)
    local path, reached = pathIn(room, from, to)
    if not toDoor and not reached then return { from }, true end
    return path, reached
end

local INWARD = { [0] = 1, [4] = 1, [2] = -1, [6] = -1, [1] = "down", [5] = "down", [3] = "up", [7] = "up" }

-- The floor cell just inside a door, where an ox waits or comes in.
local function insideDoor(room, slot)
    local cell = room:GetGridIndex(room:GetDoorSlotPosition(slot))
    local step = INWARD[slot]
    if step == "down" then return cell + room:GetGridWidth() end
    if step == "up" then return cell - room:GetGridWidth() end
    return cell + step
end

-- The rooms this room's real doors lead to, hidden secret walls included,
-- and the door slot for each. A door counts for the room the level's layout
-- puts behind it and for the room it names, since a mod may point a door
-- somewhere else (Adjacent Starting Treasure sends a start-room door to the
-- treasure room for the first visit).
local function exits(level, room, desc)
    local list, slots = {}, {}
    local cells = DOOR_CELLS[desc.Data.Shape] or {}
    local function add(other, slot)
        if other and other.SafeGridIndex ~= desc.SafeGridIndex and slots[other.SafeGridIndex] == nil then
            slots[other.SafeGridIndex] = slot
            list[#list + 1] = other.SafeGridIndex
        end
    end
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            local delta = cells[slot]
            local cell = delta and desc.SafeGridIndex + delta
            if cell and cell >= 0 and cell < 169 and math.abs(cell % 13 - desc.SafeGridIndex % 13) <= 2 then
                add(roomAt(level, cell), slot)
            end
            add(roomAt(level, door.TargetRoomIndex), slot)
        end
    end
    return list, slots
end

-- The door of this room that leads into room `index`.
local function doorTo(level, room, desc, index)
    local _, slots = exits(level, room, desc)
    local slot = slots[index]
    return slot, slot and room:GetDoor(slot)
end

-- An ox that cannot go on stays where it is; the reason goes to the debug log
-- and to conch_test's evidence.
local function stuck(color, reason, room)
    local doors = {}
    for slot = 0, 7 do
        local door = room and room:GetDoor(slot)
        if door then
            doors[#doors + 1] = string.format("%d>%d:%d%s", slot, door.TargetRoomIndex, door.TargetRoomType,
                door:IsOpen() and "o" or "c")
        end
    end
    local line = color .. " ox stops: " .. reason .. " [doors " .. table.concat(doors, " ") .. "]"
    evidence.stuck[#evidence.stuck + 1] = line
    ConchBlessing.printDebug("Ox: " .. line)
end

-- The next room on the shortest way to the ox's goal from room `index`;
-- false when it is in the goal room, nil when there is no way. `firstHop`
-- lists the rooms this room's real doors lead to, when someone is there to
-- see them. Out of a secret room it goes by whichever hidden wall is nearest
-- the goal, ramming it open.
local function plan(ox, level, index, firstHop)
    local goal = ox.goals[ox.gi]
    if index == goal then return false end
    local function from(i)
        if i == index and firstHop then return firstHop end
        return neighborsOf(level, i)
    end
    local rooms = route(index, goal, from, passable(level)) or route(index, goal, from, passable(level, true))
    return rooms and rooms[2]
end

-- The end of a stretch: the middle of a goal room (the next goal, or done),
-- or through the door into the next room, which shows on the map. `seen`
-- says whether the stretch was walked in front of a player (and ploughed).
local function arrive(ox, state, level, desc, color, seen)
    local trail = trailOf(state, desc, color)
    if ox.next == false then
        trail[#trail + 1] = { a = ox.a, b = { center = true }, ploughed = seen }
        if ox.gi < #ox.goals then
            ox.gi, ox.a, ox.next, ox.cells = ox.gi + 1, { center = true }, nil, 0
        else
            ox.done = true
        end
        return
    end
    trail[#trail + 1] = { a = ox.a, b = { to = ox.next }, ploughed = seen }
    local other = roomAt(level, ox.next)
    if not seen and other and (SECRET[other.Data.Type] or SECRET[desc.Data.Type]) then
        -- It went through a hidden wall nobody saw, into a secret room or out
        -- of one: the hole is made when a player comes into either room.
        local known = false
        for _, wall in ipairs(state.walls) do
            local a, b = wall[1], wall[2]
            if (a == desc.SafeGridIndex and b == ox.next) or (a == ox.next and b == desc.SafeGridIndex) then known = true end
        end
        if not known then state.walls[#state.walls + 1] = { desc.SafeGridIndex, ox.next } end
    end
    ox.from, ox.room, ox.a, ox.next, ox.cells = desc.SafeGridIndex, ox.next, { from = desc.SafeGridIndex }, nil, 0
    evidence.passed = evidence.passed + 1
    reveal(level, ox.room)
end

-- ------------------------------------------------------------------ red rooms
-- The ultra secret room, which only red rooms reach.
local function ultraRoom(level)
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc and desc.Data and desc.GridIndex >= 0 and desc.Data.Type == RoomType.ROOM_ULTRASECRET then
            return desc.SafeGridIndex
        end
    end
    return nil
end

local RED_CELLS = { [0] = L, [1] = U, [2] = R, [3] = D } -- a red room is 1x1
local DIG = 1000 -- a red room door outweighs any number of rooms walked

-- The first step toward the jealous black ox's goal (the ultra secret room),
-- like a Red Key: through a door a room already has, or through a red room
-- door it digs into an empty cell or an ordinary room. Returns the room (or
-- the empty cell its red room will fill) and the slot to dig, nil for an
-- existing door; false when it is there, nil when there is no way.
local function planRed(ox, level, index)
    local goal = ox.goals[ox.gi]
    if index == goal then return false end
    local blocked = ox.blocked or {}
    local function edges(key)
        local list, base, cells, connected, doors = {}, tonumber(key:sub(2)), RED_CELLS, {}, {}
        if key:sub(1, 1) == "r" then
            local desc = roomAt(level, base)
            if not desc then return list end
            cells = DOOR_CELLS[desc.Data.Shape] or {}
            for _, other in ipairs(neighborsOf(level, base)) do connected[other] = true end
            -- The ultra secret room has a door only where the engine says so;
            -- the room shape's door cells would guess one into every hidden room.
            local exact = member(desc, "GetNeighboringRooms")
            local ok, found = false, nil
            if type(exact) == "function" then ok, found = pcall(exact, desc) end
            for slot = 0, 7 do
                local other = ok and type(found) == "table" and found[slot]
                if other then doors[member(other, "SafeGridIndex") or -1] = true end
            end
        end
        for slot = 0, 7 do
            local delta = cells[slot]
            local cell = delta and base + delta
            if cell and cell >= 0 and cell < 169 and math.abs(cell % 13 - base % 13) <= 2
                and not blocked[key .. ":" .. slot] then
                local other = roomAt(level, cell)
                -- A red room door is a Red Key used, which the floor is laid out to
                -- need only once (user decision 2026-10-31): a dig weighs more than
                -- any walk, so the ox walks the rooms a player can reach as far as
                -- they take it and digs as few doors as it can; with as many digs,
                -- the fewest rooms.
                if not other then
                    list[#list + 1] = { "c" .. cell, slot, true, DIG }
                else
                    local safe = other.SafeGridIndex
                    if safe == goal then
                        list[#list + 1] = { "r" .. safe, slot, not doors[safe], doors[safe] and 1 or DIG }
                    elseif connected[safe] and passable(level, true)(safe) then
                        -- Through a boss room only when nothing else is near as short.
                        local boss = other.Data.Type == RoomType.ROOM_BOSS
                        list[#list + 1] = { "r" .. safe, slot, false, boss and 6 or 1 }
                    elseif other.Data.Type == RoomType.ROOM_DEFAULT then
                        list[#list + 1] = { "r" .. safe, slot, true, DIG }
                    end
                end
            end
        end
        return list
    end
    local start, target = "r" .. index, "r" .. goal
    local cost, came, open, closed = { [start] = 0 }, {}, { start }, {}
    while #open > 0 do
        local best, at = nil, 1
        for i, key in ipairs(open) do
            if not best or cost[key] < cost[best] then best, at = key, i end
        end
        table.remove(open, at)
        if best == target then break end
        closed[best] = true
        for _, edge in ipairs(edges(best)) do
            local key, total = edge[1], cost[best] + edge[4]
            if not closed[key] and (cost[key] == nil or total < cost[key]) then
                if cost[key] == nil then open[#open + 1] = key end
                cost[key], came[key] = total, { best, edge[2], edge[3] }
            end
        end
    end
    if not came[target] then return nil end
    local key = target
    while came[key][1] ~= start do key = came[key][1] end
    local hop = came[key]
    return tonumber(key:sub(2)), hop[3] and hop[2] or nil
end

-- Digs the red room door the ox planned from room `index`; the room behind
-- it is then a room. A refused door is never tried again.
local function dig(ox, level, index)
    local ok, made = pcall(level.MakeRedRoomDoor, level, index, ox.dig)
    local behind = roomAt(level, ox.next)
    if ok and made and behind then
        evidence.dug = evidence.dug + 1
        ox.next, ox.dig = behind.SafeGridIndex, nil
        return true
    end
    ox.blocked = ox.blocked or {}
    ox.blocked["r" .. index .. ":" .. ox.dig] = true
    ox.next, ox.dig = nil, nil
    return false
end

-- The next room toward the current goal, by doors or, for the jealous black
-- ox's ultra secret room, by red rooms. See plan and planRed.
local function nextStep(ox, level, index, firstHop)
    if ox.red and ox.gi == #ox.goals then return planRed(ox, level, index) end
    return plan(ox, level, index, firstHop)
end

-- One update of an ox whose room nobody is in: it walks on across the room
-- and through it, room after room, hidden walls included, to its last goal.
local function travel(color, ox, state, level)
    if ox.done then return end
    local desc = roomAt(level, ox.room)
    if not desc then
        ox.done = true
        return
    end
    if ox.next == nil then
        local nextRoom, slot = nextStep(ox, level, ox.room)
        if nextRoom == nil then
            ox.done = true
            stuck(color, "no route from " .. ox.room .. " to " .. tostring(ox.goals[ox.gi]))
            return
        end
        ox.next, ox.dig = nextRoom, slot
    end
    if ox.cells < crossing(desc, ox.next == false) then
        ox.cells = ox.cells + step()
        return
    end
    if ox.dig and not dig(ox, level, ox.room) then return end
    evidence.offscreen = evidence.offscreen + 1
    arrive(ox, state, level, desc, color, false)
end

local function liveOx(color)
    local record = live[color]
    local entity = record and record.ref and record.ref.Ref
    if entity and entity:Exists() then return entity:ToEffect(), record end
    return nil, record
end

local function removeOx(color)
    local entity = liveOx(color)
    if entity then entity:Remove() end
    live[color] = nil
end

local function removeAll()
    for _, color in ipairs(COLORS) do removeOx(color) end
    if variant > 0 then
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, variant)) do entity:Remove() end
    end
end

-- The ox of `color` in this room at `position`: the one already here, or a new one.
local function spawnOx(color, ox, position)
    local entity = liveOx(color)
    if entity then return entity end
    -- A reload forgets its references; the oxen it left in the room go.
    for _, other in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, variant, SUBTYPE[color])) do
        if other:GetData()[MARK] then other:Remove() end
    end
    entity = Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, SUBTYPE[color], position, Vector.Zero, nil):ToEffect()
    entity:GetData()[MARK] = color
    entity:GetSprite():Play(ANIM[color] .. "Idle", true)
    live[color] = live[color] or {}
    live[color].ref = EntityPtr(entity)
    if ox.fresh then
        -- Summoned: the oxen appear by the holder in a puff.
        ox.fresh = nil
        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, position, Vector.Zero, nil)
    end
    evidence.spawned = evidence.spawned + 1
    return entity
end

-- Breaks the rock, poop or web standing on `cell`, the ox about to step there.
local function crush(room, cell)
    if not cell then return end
    local grid = room:GetGridEntity(cell)
    local kind = grid and grid:GetType()
    if not (kind and BREAKABLE[kind] and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE) then return end
    if QUIET[kind] then
        -- Removed, not destroyed, so it never goes off; a little rubble flies.
        if pcall(room.RemoveGridEntity, room, cell, 0, false) then
            evidence.broken, evidence.quiet = evidence.broken + 1, evidence.quiet + 1
            local game = Game()
            if type(game.SpawnParticles) == "function" and EffectVariant.ROCK_PARTICLE then
                pcall(game.SpawnParticles, game, room:GetGridPosition(cell), EffectVariant.ROCK_PARTICLE, 6, 3)
            end
        end
    elseif room:DestroyGrid(cell, true) then
        evidence.broken = evidence.broken + 1
    end
end

-- Where a way's line starts and ends (progress, see LINE): at the door edge
-- it came in or goes out by (`ends.first`, `ends.last`), else in the middle.
local function lineSpan(path, ends)
    return ends.first and -0.5 or 0, ends.last and #path - 0.5 or #path - 1
end

-- Ploughs the way's line from progress `from` up to the share at `upto`, a
-- quarter of a cell at a time, each quarter once; returns where it stopped.
local function plough(state, desc, room, color, path, ends, from, upto)
    local width, field = room:GetGridWidth(), fieldOf(state, desc, true)[color]
    local _, finish = lineSpan(path, ends)
    local at = from
    while at < finish - 1e-6 and at + 0.125 <= upto + 1e-6 do
        local j = math.floor(at + 1.5 + 1e-6)
        local cell = path[j]
        local a, b = cellSides(path, j, width, ends.first, ends.last)
        local piece = quarterPiece(a, b, math.floor((at - (j - 1.5)) / 0.25 + 0.5))
        if piece and cell and room:IsPositionInRoom(room:GetGridPosition(cell), 0)
            and room:GetGridCollision(cell) == GridCollisionClass.COLLISION_NONE then
            local key = tostring(cell)
            local before = field[key]
            local mask = (before or 0) | (1 << piece)
            if before == nil then evidence.ploughed = evidence.ploughed + 1 end
            if mask ~= before then field[key], furrowVersion = mask, furrowVersion + 1 end
        end
        at = at + 0.25
    end
    return at
end

-- The grid cell an end of a stretch stands on in this room.
local function endCell(level, room, desc, e)
    if e.dig then return insideDoor(room, e.dig), e.dig end
    if e.from or e.to then
        local slot = doorTo(level, room, desc, e.from or e.to)
        return slot and insideDoor(room, slot), slot
    end
    if e.x then return room:GetGridIndex(Vector(e.x, e.y)) end
    return room:GetGridIndex(room:GetCenterPos())
end

-- The furrows of the stretches oxen walked here while nobody watched, and
-- the hidden walls they went through, opened as a bomb would.
local function materialize(state, level, desc, room, holder)
    for i = #state.walls, 1, -1 do
        local wall = state.walls[i]
        local other = wall[1] == desc.SafeGridIndex and wall[2] or wall[2] == desc.SafeGridIndex and wall[1]
        if other then
            local _, door = doorTo(level, room, desc, other)
            if door and not door:IsOpen() and door:TryBlowOpen(true, holder) then
                evidence.opened = evidence.opened + 1
            end
            if not door or door:IsOpen() then table.remove(state.walls, i) end
        end
    end
    local trails = state.trails["L" .. desc.ListIndex]
    if not trails then return end
    for _, color in ipairs(COLORS) do
        for _, stretch in ipairs(trails[color] or {}) do
            if not stretch.ploughed then
                stretch.ploughed = true
                local a, slotA = endCell(level, room, desc, stretch.a)
                local b, slotB = endCell(level, room, desc, stretch.b)
                local path, reached = nil, false
                if a and b then path, reached = wayIn(room, a, b, not stretch.b.center) end
                local ends = { first = slotA and SLOT_BIT[slotA], last = reached and slotB and SLOT_BIT[slotB] or nil }
                if path then
                    for _, cell in ipairs(path) do crush(room, cell) end
                    local from, to = lineSpan(path, ends)
                    plough(state, desc, room, color, path, ends, from, to)
                end
            end
        end
    end
end

local TURN_HOLD = 8 -- walking updates a new facing holds before the ox may turn again
local RETRY = 30    -- updates an ox with no ground way on waits before looking again
-- How far behind the ox's feet the plough's share cuts the ground, in cells,
-- by its facing, measured from the direction art (side 30 px, facing down
-- 27 px; facing up the body hides most of the plough and the share shows 9 px
-- below the feet).
LINE.share = { [""] = 30 / 26, Down = 27 / 26, Up = 9 / 26 }

-- Walk or stand facing the way it goes: up or down when it moves more along
-- a column (no flip), sideways otherwise (art faces right, flipped for left).
-- A turn holds a few steps, so a zigzag never makes it flicker; standing
-- keeps the last facing; sleeping has one pose.
local function setPose(entity, color, pose, step)
    local sprite = entity:GetSprite()
    local record = live[color]
    if step and (math.abs(step.X) > 0.01 or math.abs(step.Y) > 0.01) and record then
        record.hold = math.max(0, (record.hold or 0) - 1)
        local facing, flip
        if math.abs(step.Y) > math.abs(step.X) then
            facing, flip = step.Y > 0 and "Down" or "Up", false
        else
            facing, flip = "", step.X < 0
        end
        if record.hold == 0 and (facing ~= record.facing or flip ~= record.flip) then
            if record.facing ~= nil then record.hold = TURN_HOLD end
            record.facing, record.flip = facing, flip
        end
    end
    local facing = pose ~= "Sleep" and record and record.facing or ""
    local name = ANIM[color] .. pose .. facing
    if not sprite:IsPlaying(name) then sprite:Play(name, true) end
    sprite.FlipX = pose ~= "Sleep" and facing == "" and record ~= nil and record.flip == true
end

-- One update of the ox of `color` in the room a player is in.
local function walk(color, ox, state, level, desc, room, holder)
    local record = live[color] or {}
    live[color] = record
    if not record.path then
        if not ox.done and ox.next == nil then
            -- From this room the ox goes only through a door the room really has.
            local nextRoom, slot = nextStep(ox, level, desc.SafeGridIndex, (exits(level, room, desc)))
            if nextRoom == nil then
                ox.done = true
                stuck(color, "no route from " .. desc.SafeGridIndex .. " to " .. tostring(ox.goals[ox.gi]), room)
            else
                ox.next, ox.dig = nextRoom, slot
            end
        end
        local a, slotA = endCell(level, room, desc, ox.a)
        a = a or room:GetGridIndex(room:GetCenterPos())
        local toDoor = not (ox.done or ox.next == false)
        local b, slot = endCell(level, room, desc, toDoor and (ox.dig and { dig = ox.dig } or { to = ox.next })
            or { center = true })
        if not b then
            ox.done, toDoor = true, false
            stuck(color, "no door to " .. tostring(ox.next), room)
            b = a
        end
        local path, reached = wayIn(room, a, b, toDoor)
        record.path, record.reached = path, reached
        record.exit = toDoor and slot or nil
        record.ends = { first = slotA and SLOT_BIT[slotA], last = reached and toDoor and slot and SLOT_BIT[slot] or nil }
        record.laid = (lineSpan(path, record.ends))
        record.crushed, record.checked, record.wait = 0, nil, 0
        if toDoor and not reached and not record.reported then
            record.reported = true
            stuck(color, "no ground way to the door toward " .. tostring(ox.next) .. "; it waits nearby", room)
        end
    end
    local path, ends = record.path, record.ends
    local last = #path
    local moving = not ox.done and ox.cells < last - 1
    if moving then ox.cells = math.min(ox.cells + step(), last - 1) end
    local progress = ox.done and last - 1 or math.min(ox.cells, last - 1)
    -- On its way: straight along rows and columns, round each turn.
    local j, dx, dy, tx, ty = curveAt(path, room:GetGridWidth(), progress, ends.first, ends.last)
    -- What stands in front of it is broken before it gets there.
    local reach = math.min(last, j + 1)
    for k = record.crushed + 1, reach do crush(room, path[k]) end
    record.crushed = math.max(record.crushed, reach)
    local position = room:GetGridPosition(path[j]) + Vector(dx, dy)
    if moving and record.checked ~= j and j < last then
        record.checked = j
        -- The ground on its way changed (a pit opened, a block was placed): it
        -- looks over all the way left, not just the next step, so it turns off
        -- as soon as it can rather than walking up to the pit and back (user
        -- report 2026-10-31). The furrow is finished to the middle of its cell
        -- and it finds a new way from there.
        local ground, blocked = groundAt(room), nil
        for k = j + 1, last do
            if ground(path[k]) == nil then blocked = k break end
        end
        if blocked then
            plough(state, desc, room, color, path, ends, record.laid, j - 1)
            evidence.replans, evidence.ahead = evidence.replans + 1, blocked - j
            position = room:GetGridPosition(path[j])
            ox.a, ox.cells, record.path = { x = position.X, y = position.Y }, 0, nil
        end
    end
    local entity = spawnOx(color, ox, position)
    entity.Velocity = Vector.Zero
    entity.Position = position
    if not record.path then
        setPose(entity, color, "Idle")
        return
    end
    -- With nowhere left to go it lies down and sleeps where it is.
    setPose(entity, color, ox.done and "Sleep" or moving and "Walk" or "Idle", moving and Vector(tx, ty) or nil)
    -- The share, behind it on its way, cuts the furrow as it passes.
    local share = progress - (LINE.share[record.facing or ""] or LINE.share[""])
    record.laid = plough(state, desc, room, color, path, ends, record.laid, share)
    if ox.done or ox.cells < last - 1 then return end
    if ox.next ~= false and not record.reached then
        -- No ground way to its door: it waits as near as it can get and looks again in a while.
        evidence.waits = evidence.waits + 1
        record.wait = record.wait + 1
        if record.wait >= RETRY then
            plough(state, desc, room, color, path, ends, record.laid, last - 1)
            ox.a, ox.cells, record.path = { x = position.X, y = position.Y }, 0, nil
        end
        return
    end
    if ox.next == false then
        -- In the middle of its goal room the share catches up as it stops.
        plough(state, desc, room, color, path, ends, record.laid, last - 1)
        arrive(ox, state, level, desc, color, true)
        live[color].path = nil
        return
    end
    if ox.dig then
        -- A red room door, dug where the ox stands, like a Red Key.
        if not dig(ox, level, desc.SafeGridIndex) then
            live[color].path = nil
            return
        end
    end
    local door = room:GetDoor(record.exit)
    if door and not door:IsOpen() and (SECRET[desc.Data.Type] or SECRET[door.TargetRoomType]) then
        -- A hidden wall into or out of a secret room: rammed open as a bomb
        -- would, fight or no fight; the API takes the entity itself.
        evidence.blows = evidence.blows + 1
        if door:TryBlowOpen(true, holder) then evidence.opened = evidence.opened + 1 end
    end
    -- It never waits at its door (user request 2026-10-31): a door shut for a
    -- fight or locked, or a wall that will not break (the Void's), it goes
    -- through without opening, so Isaac gets no way out of a fight or past a
    -- lock from it. The share follows it out, cutting the furrow to the
    -- doorway, and it walks on in the next room, which shows on the map.
    if door and not door:IsOpen() then evidence.through = evidence.through + 1 end
    plough(state, desc, room, color, path, ends, record.laid, math.huge)
    removeOx(color)
    arrive(ox, state, level, desc, color, true)
end

-- The Magic Conch says yes while the yellow ox is in the player's room and
-- the black ox is not: the farmer's praise of the yellow ox alone (user
-- decision 2026-10-31; it once needed both oxen in one room). The black ox,
-- left out, grows jealous and, once it has seen its own rooms, digs red rooms
-- to the ultra secret room; the yellow ox does nothing more. Once a floor.
function M.onConchResult(result)
    if not started or type(result) ~= "table" or result.type ~= "positive" or OX_ID <= 0 then return end
    local game = Game()
    local level = game:GetLevel()
    local state = floorState(false)
    local yellow, black = state and state.oxen.yellow, state and state.oxen.black
    local desc = mainRoom(level)
    local here = desc and desc.SafeGridIndex
    if not yellow or not black or black.jealous or here == nil or yellow.room ~= here or black.room == here then
        return
    end
    local ultra = anyHolder() and ultraRoom(level)
    if not ultra then return end
    black.jealous, black.red = true, true
    black.goals[#black.goals + 1] = ultra
    evidence.jealous = evidence.jealous + 1
    if black.done then
        -- It wakes where it slept and sets off.
        black.done, black.gi, black.next, black.dig, black.cells = false, #black.goals, nil, nil, 0
        black.a = { center = true }
        if live.black then live.black.path = nil end
    end
end

-- ------------------------------------------------------------------ the map
-- The oxen fill the map in, so while a living player holds the item nobody is
-- under Curse of the Lost, which hides it (user request 2026-10-31; the
-- Amnesia pill casts the same curse). A new floor never rolls it, and one
-- cast during the floor (the pill, another mod) or already there when the
-- item comes is lifted on the next update.
function M.onCurseEval(_, curses)
    if not started or OX_ID <= 0 or type(curses) ~= "number" or curses & LOST == 0 or not anyHolder() then return end
    evidence.spared = evidence.spared + 1
    return curses & ~LOST
end

local function liftLost(level)
    if level:GetCurses() & LOST == 0 or type(level.RemoveCurses) ~= "function" then return end
    level:RemoveCurses(LOST)
    if type(level.UpdateVisibility) == "function" then level:UpdateVisibility() end
    evidence.lifted = evidence.lifted + 1
end

-- ------------------------------------------------------------------ the bonus

-- Sets `player`'s two multipliers: damage while on 누렁소's furrow
-- (`yellow`), tears while in 검은소's ditch (`black`).
local function applyStats(player, yellow, black)
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not um or OX_ID <= 0 then return end
    local state = ConchBlessing.getUnifiedMultiplierState(player, um)
    local row = state and state.itemMultipliers and state.itemMultipliers[OX_ID]
    local changed = false
    for stat, target in pairs({ Damage = yellow and M.data.damage or false, Tears = black and M.data.tears or false }) do
        local entry, moved = row and row[stat], false
        if target and (not entry or math.abs(entry.value - target) > 1e-9) then
            um:SetItemMultiplier(player, OX_ID, stat, target, "Ox")
            moved = true
        elseif not target and entry then
            um:RemoveItemMultiplier(player, OX_ID, stat)
            moved = true
        end
        if moved then
            changed = true
            if um.QueueCacheUpdate then um:QueueCacheUpdate(player, stat) end
        end
    end
    if changed and um.SaveToSaveManager then um:SaveToSaveManager(player) end
    boosted[GetPtrHash(player)] = yellow or black
end

-- Whether `position` stands on `color`'s furrow: within LINE.near of the
-- line drawn in its cell or the four next to it.
local function onFurrow(field, color, room, position)
    local cells = field and field[color]
    if not cells then return false end
    local cell, width = room:GetGridIndex(position), room:GetGridWidth()
    for _, other in ipairs({ cell, cell - width, cell + width, cell - 1, cell + 1 }) do
        local mask = cells[tostring(other)]
        if mask then
            local centre = room:GetGridPosition(other)
            if furrowDistance(mask, position.X - centre.X, position.Y - centre.Y) <= LINE.near then return true end
        end
    end
    return false
end

-- Whether `position` stands in this room's rice.
local function inRice(position)
    for _, spot in pairs(rice) do
        if (position.X - spot.x) ^ 2 + (position.Y - spot.y) ^ 2 <= LINE.rice ^ 2 then return true end
    end
    return false
end

-- The bonus under `player` this update: damage on 누렁소's furrow, tears in
-- 검은소's ditch, both in the rice and for two seconds after it, nothing
-- anywhere else.
local function grow(player, field, room)
    local hash = GetPtrHash(player)
    if next(rice) ~= nil and inRice(player.Position) then
        riceLeft[hash] = M.data.riceHold
    elseif riceLeft[hash] then
        riceLeft[hash] = riceLeft[hash] > 1 and riceLeft[hash] - 1 or nil
    end
    local ripe = riceLeft[hash] ~= nil
    applyStats(player, ripe or onFurrow(field, "yellow", room, player.Position),
        ripe or onFurrow(field, "black", room, player.Position))
end

-- A player who no longer holds the item has no bonus (looked at once after a
-- start or reload, since StatsAPI keeps its multipliers in the save).
local function wither(player)
    riceLeft[GetPtrHash(player)] = nil
    if boosted[GetPtrHash(player)] == false then return end
    applyStats(player, false, false)
end

-- ------------------------------------------------------------------ furrow marks
-- Stamps one furrow piece into this room's floor. The engine draws a
-- FLAG_RENDER_FLOOR effect into the floor and removes it on its next update,
-- so the stamp stays until the room is left and a quarter is never stamped twice
-- (each stamp would darken it again).
local function stamp(room, color, cell, frame)
    local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, furrowVariant, SUBTYPE[color],
        room:GetGridPosition(cell), Vector.Zero, nil):ToEffect()
    effect:GetSprite():SetFrame("Furrow", frame)
    effect:AddEntityFlags(EntityFlag.FLAG_RENDER_FLOOR)
end

-- Rice where the two lines meet in a cell: grown already on coming in, and
-- growing before the player's eyes where the oxen first make them meet.
local function sowRice(field, room, growing)
    if riceVariant <= 0 or not field then return end
    for key, yellow in pairs(field.yellow) do
        local cell, black = tonumber(key), field.black[key]
        if cell and black and not rice[cell] then
            local x, y = meetPoint(yellow, black)
            if x then
                local at = room:GetGridPosition(cell) + Vector(x, y)
                local plant = Isaac.Spawn(EntityType.ENTITY_EFFECT, riceVariant, 0, at, Vector.Zero, nil):ToEffect()
                plant.DepthOffset = -10
                plant:GetSprite():Play(growing and "Grow" or "Idle", true)
                rice[cell] = { x = at.X, y = at.Y, ref = EntityPtr(plant) }
                evidence.rice = evidence.rice + 1
            end
        end
    end
end

-- Stamps every quarter of this room's furrows not on the floor yet.
local function stampFurrows(state, desc, room)
    if furrowVariant <= 0 or furrowSynced == furrowVersion then return end
    local entering = furrowSynced == -1
    furrowSynced = furrowVersion
    local field = fieldOf(state, desc, false)
    if not field then return end
    for _, color in ipairs(COLORS) do
        for key, mask in pairs(field[color]) do
            local cell, mark = tonumber(key), color .. ":" .. key
            local fresh = mask & ~(stamped[mark] or 0)
            if cell and fresh ~= 0 then
                for piece = 0, PIECES - 1 do
                    if fresh & (1 << piece) ~= 0 then
                        stamp(room, color, cell, pieceFrame(color, piece, cell))
                        local one = mark .. ":" .. piece
                        evidence.stamps[one] = (evidence.stamps[one] or 0) + 1
                    end
                end
                stamped[mark] = mask | (stamped[mark] or 0)
            end
        end
    end
    sowRice(field, room, not entering)
end

-- A new room's floor has none of them, nor its rice.
local function forgetStamps()
    stamped, furrowSynced, rice = {}, -1, {}
    evidence.stamps = {}
end

-- Grown rice sways; the engine leaves a finished animation on its last frame.
local function tendRice()
    for _, spot in pairs(rice) do
        local plant = spot.ref and spot.ref.Ref
        if plant and plant:Exists() and plant:GetSprite():IsFinished("Grow") then plant:GetSprite():Play("Idle", true) end
    end
end

-- ------------------------------------------------------------------ 자's rider
-- With 자 (Rat) in the run, one of its fakes rides 누렁소 and shoots the
-- nearest enemy by itself (user design 2026-10-31; in the zodiac race the rat
-- rode the ox's back). Only the yellow ox carries one, the first live fake in
-- player order however many Rats there are, and only while the ox walks in
-- the players' room: a fake is a player, so it is only ever where the players
-- are, and a room nobody is in is never cleared by it. The ox keeps its own
-- way; when it leaves the room, or lies down to sleep (user request
-- 2026-10-31), the fake hops off back beside its owner. On the ox it takes no
-- damage, its movement and its bomb, item, card and drop keys are not its
-- own, and its shooting keys point at the nearest enemy through
-- MC_INPUT_ACTION, so the engine fires the fake's own weapon; a charge weapon
-- is let go once fully charged (REPENTOGON's Weapon:GetCharge). It is drawn on
-- the ox's back through SpriteOffset while its Position stays on the ox's
-- feet, ground the ox walks, so it never stands over a pit or in a wall.
local Ride = {
    rider = nil, -- { ref, hash, phase = "up" | "on" | "down", t, from, to, offset, sprite, depth, fire, press }
    -- Where the rider's feet sit on the ox's back, in sprite pixels from the
    -- ox's feet (measured from conch_ox.anm2's frames); while the ox faces the
    -- camera the rider sits behind its head.
    SADDLE = { side = { -8, -21 }, Down = { 0, -27, behind = true }, Up = { 0, -22 }, Sleep = { -6, -16 } },
    KEYS = {},   -- [ButtonAction] = true (not the rider's while it rides) or the shooting direction
}
if ButtonAction then
    Ride.KEYS = {
        [ButtonAction.ACTION_LEFT] = true, [ButtonAction.ACTION_RIGHT] = true,
        [ButtonAction.ACTION_UP] = true, [ButtonAction.ACTION_DOWN] = true,
        [ButtonAction.ACTION_BOMB] = true, [ButtonAction.ACTION_ITEM] = true,
        [ButtonAction.ACTION_PILLCARD] = true, [ButtonAction.ACTION_DROP] = true,
        [ButtonAction.ACTION_SHOOTLEFT] = "left", [ButtonAction.ACTION_SHOOTRIGHT] = "right",
        [ButtonAction.ACTION_SHOOTUP] = "up", [ButtonAction.ACTION_SHOOTDOWN] = "down",
    }
end

-- The seat for the ox's current animation: x, y and whether it is behind the ox.
function Ride.saddle(anim, flipX)
    anim = tostring(anim or "")
    local seat = (anim:find("Sleep", 1, true) and Ride.SADDLE.Sleep)
        or (anim:find("Down$") and Ride.SADDLE.Down)
        or (anim:find("Up$") and Ride.SADDLE.Up) or Ride.SADDLE.side
    local x = seat[1]
    if seat == Ride.SADDLE.side and flipX then x = -x end
    return x, seat[2], seat.behind == true
end

-- Shooting toward (dx, dy): each direction's value, and the one held down.
function Ride.aim(dx, dy)
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1e-6 then return nil, nil end
    local fire = { left = math.max(0, -dx / length), right = math.max(0, dx / length),
        up = math.max(0, -dy / length), down = math.max(0, dy / length) }
    local press = math.abs(dx) >= math.abs(dy) and (dx < 0 and "left" or "right") or (dy < 0 and "up" or "down")
    return fire, press
end

-- A charge weapon fires when let go: it is let go once full.
function Ride.charged(charge, max)
    return type(charge) == "number" and type(max) == "number" and max > 0 and charge >= max
end

-- The hop's height at progress p (0..1), in sprite pixels (up is negative).
function Ride.arc(p) return -M.data.rideArc * math.sin(math.pi * p) end

function Ride.player()
    local entry = Ride.rider
    local entity = entry and entry.ref and entry.ref.Ref
    local player = entity and entity:ToPlayer()
    if player and player:Exists() then return player end
end

-- The fake that rides: the one riding while it can, else the first live fake.
function Ride.candidate()
    local rat = ConchBlessing.rat
    if not rat or type(rat.isFake) ~= "function" then return nil end
    local current = Ride.player()
    if current and rat.isFake(current) and isActingPlayer(current) then return current end
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player and player:Exists() and rat.isFake(player) and isActingPlayer(player) then return player end
    end
end

-- Gives back everything the ride borrowed, at once (a new room, the game's end).
function Ride.restore(player, entry)
    if player and entry then
        player.SpriteOffset = entry.sprite
        player.DepthOffset = entry.depth
    end
    Ride.rider = nil
end

function Ride.mount(player)
    local s = player.SpriteOffset
    Ride.rider = { ref = EntityPtr(player), hash = GetPtrHash(player), phase = "up", t = 0,
        from = Vector(player.Position.X, player.Position.Y), sprite = Vector(s.X, s.Y), depth = player.DepthOffset }
    evidence.mounts = evidence.mounts + 1
end

-- Off the ox: a hop back beside its owner.
function Ride.dismount(player)
    local entry = Ride.rider
    if not entry or entry.phase == "down" then return end
    local owner = player.Parent
    local to = player.Position
    if owner and owner:Exists() then to = Isaac.GetFreeNearPosition(owner.Position, 20) end
    entry.phase, entry.t, entry.fire, entry.press = "down", 0, nil, nil
    entry.from, entry.to = Vector(player.Position.X, player.Position.Y), to
    entry.fromOffset = entry.offset or Vector.Zero
    evidence.dismounts = evidence.dismounts + 1
end

-- Points the rider's shooting at the nearest enemy, or at nothing.
function Ride.target(player, entry)
    entry.fire, entry.press = nil, nil
    local best, bestDistance
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) and entity:IsVulnerableEnemy()
            and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            local distance = entity.Position:DistanceSquared(player.Position)
            if not bestDistance or distance < bestDistance then best, bestDistance = entity, distance end
        end
    end
    if not best then return end
    local weapon = type(player.GetWeapon) == "function" and player:GetWeapon(1) or nil
    if weapon and type(weapon.GetCharge) == "function" and type(weapon.GetMaxCharge) == "function"
        and Ride.charged(weapon:GetCharge(), weapon:GetMaxCharge()) then
        evidence.releases = evidence.releases + 1
        return
    end
    local d = best.Position - player.Position
    entry.fire, entry.press = Ride.aim(d.X, d.Y)
    evidence.aimed = evidence.aimed + 1
end

-- One update of the ride: `ox` is the yellow ox's entity in this room or nil,
-- `walking` false once it sleeps.
function Ride.update(ox, walking)
    local player = Ride.player()
    if Ride.rider and not player then Ride.rider = nil end
    local want = ox and walking and Ride.candidate() or nil
    if Ride.rider and (not want or GetPtrHash(want) ~= Ride.rider.hash) then Ride.dismount(player) end
    if not Ride.rider and want then
        Ride.mount(want)
        player = want
    end
    local entry = Ride.rider
    if not entry then return end
    entry.t = entry.t + 1
    local p = math.min(1, entry.t / M.data.rideHop)
    player.Velocity = Vector.Zero
    if entry.phase == "down" then
        player.Position = entry.from + (entry.to - entry.from) * p
        player.SpriteOffset = entry.sprite + entry.fromOffset * (1 - p) + Vector(0, Ride.arc(p))
        if p >= 1 then Ride.restore(player, entry) end
        return
    end
    local sprite = ox:GetSprite()
    local x, y, behind = Ride.saddle(sprite:GetAnimation(), sprite.FlipX)
    local seat = Vector(x, y)
    if entry.phase == "up" then
        player.Position = entry.from + (ox.Position - entry.from) * p
        entry.offset = seat * p + Vector(0, Ride.arc(p))
        if p >= 1 then entry.phase = "on" end
    else
        player.Position = ox.Position
        entry.offset = seat
    end
    player.SpriteOffset = entry.sprite + entry.offset
    player.DepthOffset = entry.depth + (behind and -1 or 1)
    Ride.target(player, entry)
end

function M.onInputAction(_, entity, hook, action)
    local entry = Ride.rider
    if entry == nil or entity == nil then return end
    local kind = Ride.KEYS[action]
    if kind == nil or GetPtrHash(entity) ~= entry.hash then return end
    local value = kind ~= true and entry.fire and entry.fire[kind] or 0
    if hook == InputHook.GET_ACTION_VALUE then return value end
    if hook == InputHook.IS_ACTION_TRIGGERED then return false end
    return value > 0 and entry.press == kind
end

-- On the ox the rider takes no damage.
function M.onRiderDamage(_, entity)
    local entry = Ride.rider
    if entry == nil or entity == nil or GetPtrHash(entity) ~= entry.hash then return end
    evidence.shielded = evidence.shielded + 1
    return false
end

-- ------------------------------------------------------------------ callbacks
function M.onUpdate()
    if not started or OX_ID <= 0 then return end
    -- After a reload the saves come back a moment later.
    if type(SaveManager.IsLoaded) == "function" and not SaveManager.IsLoaded() then return end
    local game = Game()
    local level, room = game:GetLevel(), game:GetRoom()
    local holders = {}
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player and player:HasCollectible(OX_ID) then
            if isActingPlayer(player) then holders[#holders + 1] = player end
        elseif player then
            wither(player)
        end
    end
    if #holders == 0 then
        if next(live) then removeAll() end
        live = {}
        Ride.update(nil, false)
        return
    end
    liftLost(level)
    local desc = mainRoom(level)
    local state = desc and variant > 0 and floorState(true, level, desc, holders[1]) or floorState(false)
    if state and variant > 0 then
        if desc and materialized ~= desc.ListIndex then
            materialized = desc.ListIndex
            materialize(state, level, desc, room, holders[1])
        end
        -- An ox in the holder's room walks in sight; the other walks on unseen.
        for _, color in ipairs(COLORS) do
            local ox = state.oxen[color]
            if ox and desc and ox.room == desc.SafeGridIndex then
                walk(color, ox, state, level, desc, room, holders[1])
            else
                if live[color] then removeOx(color) end
                if ox then travel(color, ox, state, level) end
            end
        end
    end
    local yellow = state and variant > 0 and state.oxen.yellow
    Ride.update(yellow and liveOx("yellow") or nil, yellow and not yellow.done)
    if state and desc then stampFurrows(state, desc, room) end
    if next(rice) then tendRice() end
    local field = state and desc and fieldOf(state, desc, false)
    for _, player in ipairs(holders) do grow(player, field, room) end
end

function M.onNewRoom()
    Ride.restore(Ride.player(), Ride.rider)
    live, materialized = {}, nil
    forgetStamps()
end

function M.onGameStarted()
    Ride.rider = nil
    live, boosted, riceLeft, materialized = {}, {}, {}, nil
    forgetStamps()
    started = true
end

function M.onPreGameExit()
    Ride.restore(Ride.player(), Ride.rider)
    started = false
    live, boosted, riceLeft = {}, {}, {}
end

function M.onModUnload()
    Ride.restore(Ride.player(), Ride.rider)
    removeAll()
    for _, spot in pairs(rice) do
        local plant = spot.ref and spot.ref.Ref
        if plant and plant:Exists() then plant:Remove() end
    end
    rice = {}
    started = false
end

M._test = {
    liftLost = liftLost,
    ride = Ride,
    route = route,
    findPath = findPath,
    quarterPiece = quarterPiece,
    curveAt = curveAt,
    furrowDistance = furrowDistance,
    lineSpan = lineSpan,
    onFurrow = onFurrow,
    pieceFrame = pieceFrame,
    piecePoint = piecePoint,
    meetPoint = meetPoint,
    wayIn = wayIn,
    crush = crush,
    sowRice = sowRice,
    rice = function() return rice end,
    riceVariant = function() return riceVariant end,
    groundCost = groundCost,
    groundAt = groundAt,
    doorLines = doorLines,
    cellCost = cellCost,
    plough = plough,
    stampFurrows = stampFurrows,
    neighborsOf = neighborsOf,
    exits = exits,
    ultraRoom = ultraRoom,
    planRed = planRed,
    passable = passable,
    bossRoom = bossRoom,
    secretRoom = secretRoom,
    secretRooms = secretRooms,
    normalize = normalize,
    crossing = crossing,
    plan = plan,
    travel = travel,
    variant = function() return variant end,
    furrowVariant = function() return furrowVariant end,
    state = function() return floorState(false) end,
    live = function() return live end,
    boosted = function() return boosted end,
    riceLeft = function() return riceLeft end,
    grow = grow,
    wither = wither,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    started = function() return started end,
}

ConchBlessing.conchResultListeners = ConchBlessing.conchResultListeners or {}
ConchBlessing.conchResultListeners.ox = M.onConchResult

return M
