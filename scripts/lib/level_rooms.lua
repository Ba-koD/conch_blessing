-- The floor's rooms as a graph: which room a level cell holds, which rooms a
-- room's doors lead to, the shortest way between rooms and the fewest red
-- room doors (Red Key) to a room. 축 (Ox) walks this graph, 묘 (Rabbit)
-- measures how many rooms from the start its hidden rock lies, and 장승 marks
-- the walls a Red Key would open toward the ultra secret room.
--
-- Rooms connect through REPENTOGON's RoomDescriptor:GetNeighboringRooms when
-- it is there, and otherwise through each room shape's door cells. Every
-- room is named by its safe grid index on the 13x13 level grid.
local R = {}

local function member(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end
R.member = member

-- The main-dimension room on a level cell, or nil.
function R.roomAt(level, index)
    if index == nil or index < 0 then return nil end
    local ok, desc = pcall(level.GetRoomByIdx, level, index, 0)
    if ok and desc and desc.Data and desc.GridIndex >= 0 then return desc end
    return nil
end
local roomAt = R.roomAt

-- The current room when it is a room of the floor's grid in the main
-- dimension, else nil.
function R.mainRoom(level)
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
local L, U, Ri, D = -1, -13, 1, 13
local Shape = rawget(_G, "RoomShape") -- absent only in offline harnesses that never walk a level
R.DOOR_CELLS = Shape == nil and {} or {
    [Shape.ROOMSHAPE_1x1] = { [0] = L, [1] = U, [2] = Ri, [3] = D },
    [Shape.ROOMSHAPE_IH] = { [0] = L, [2] = Ri },
    [Shape.ROOMSHAPE_IV] = { [1] = U, [3] = D },
    [Shape.ROOMSHAPE_1x2] = { [0] = L, [1] = U, [2] = Ri, [3] = D + D, [4] = D + L, [6] = D + Ri },
    [Shape.ROOMSHAPE_IIV] = { [1] = U, [3] = D + D },
    [Shape.ROOMSHAPE_2x1] = { [0] = L, [1] = U, [2] = Ri + Ri, [3] = D, [5] = Ri + U, [7] = Ri + D },
    [Shape.ROOMSHAPE_IIH] = { [0] = L, [2] = Ri + Ri },
    [Shape.ROOMSHAPE_2x2] = { [0] = L, [1] = U, [2] = Ri + Ri, [3] = D + D, [4] = D + L, [5] = Ri + U,
        [6] = Ri + D + Ri, [7] = Ri + D + D },
    [Shape.ROOMSHAPE_LTL] = { [0] = L, [1] = D + L + U, [2] = Ri, [3] = D + L + D, [4] = D + L + L, [5] = U,
        [6] = D + Ri, [7] = D + D },
    [Shape.ROOMSHAPE_LTR] = { [0] = L, [1] = U, [2] = Ri, [3] = D + D, [4] = D + L, [5] = D + Ri + U,
        [6] = D + Ri + Ri, [7] = D + Ri + D },
    [Shape.ROOMSHAPE_LBL] = { [0] = L, [1] = U, [2] = Ri + Ri, [3] = D, [4] = Ri + D + L, [5] = Ri + U,
        [6] = Ri + D + Ri, [7] = Ri + D + D },
    [Shape.ROOMSHAPE_LBR] = { [0] = L, [1] = U, [2] = Ri + Ri, [3] = D + D, [4] = D + L, [5] = Ri + U,
        [6] = D + Ri, [7] = Ri + D },
}
local DOOR_CELLS = R.DOOR_CELLS

-- A red room is 1x1: its door slots and the cells beyond them.
R.RED_CELLS = { [0] = L, [1] = U, [2] = Ri, [3] = D }
local RED_CELLS = R.RED_CELLS

local Types = rawget(_G, "RoomType")
R.SECRET = Types == nil and {} or
    { [Types.ROOM_SECRET] = true, [Types.ROOM_SUPERSECRET] = true, [Types.ROOM_ULTRASECRET] = true }
local SECRET = R.SECRET

-- The level cell beyond a room's door slot, or nil off the map.
function R.cellBeyond(desc, index, slot)
    local cells = DOOR_CELLS[desc.Data.Shape] or {}
    local delta = cells[slot]
    local cell = delta and index + delta
    if cell and cell >= 0 and cell < 169 and math.abs(cell % 13 - index % 13) <= 2 then return cell end
    return nil
end

-- The rooms a room's door cells touch, by safe grid index in door-slot order.
function R.touching(level, desc, index)
    local list = {}
    local doors = tonumber(desc.Data.Doors) or 0
    for slot = 0, 7 do
        if doors & (1 << slot) ~= 0 then
            local cell = R.cellBeyond(desc, index, slot)
            local other = cell and roomAt(level, cell)
            if other and other.SafeGridIndex ~= index then list[#list + 1] = other end
        end
    end
    return list
end

-- The rooms a room's doors lead to, by safe grid index in door-slot order.
-- REPENTOGON names the engine's own doors; the shape's door cells add the
-- secret rooms behind hidden walls and stand in for everything without it.
function R.neighborsOf(level, index)
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
    for _, other in ipairs(R.touching(level, desc, index)) do
        if not found or SECRET[other.Data.Type] then add(other.SafeGridIndex) end
    end
    return list
end
local neighborsOf = R.neighborsOf

-- The safe grid indices of the rooms an engine door of this room leads to,
-- by slot (REPENTOGON), or nil without it.
function R.engineDoors(desc)
    local exact = member(desc, "GetNeighboringRooms")
    if type(exact) ~= "function" then return nil end
    local ok, found = pcall(exact, desc)
    if not ok or type(found) ~= "table" then return nil end
    local doors = {}
    for slot = 0, 7 do
        local other = found[slot]
        if other then doors[slot] = member(other, "SafeGridIndex") end
    end
    return doors
end

-- Breadth-first route over rooms from `from` to `to`, passing only through
-- rooms `through` allows (the goal itself may be any room).
function R.route(from, to, neighbors, through)
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

-- How many doors away each room is from `from`, walking through any room
-- but a secret one (whose walls are hidden): { [safe index] = distance }.
function R.distances(level, from)
    local distance, queue, head = { [from] = 0 }, { from }, 1
    while head <= #queue do
        local node = queue[head]
        head = head + 1
        for _, nextNode in ipairs(neighborsOf(level, node)) do
            local desc = distance[nextNode] == nil and roomAt(level, nextNode)
            if desc and not SECRET[desc.Data.Type] then
                distance[nextNode] = distance[node] + 1
                queue[#queue + 1] = nextNode
            end
        end
    end
    return distance
end

function R.ultraRoom(level)
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc and desc.Data and desc.GridIndex >= 0 and desc.Data.Type == RoomType.ROOM_ULTRASECRET then
            return desc.SafeGridIndex
        end
    end
    return nil
end

local DIG = 1000 -- a red room door outweighs any number of rooms walked

-- The first step from room `index` toward room `goal` (the ultra secret
-- room), like a Red Key: through a door a room already has, or through a red
-- room door dug into an empty cell or an ordinary room. A dig weighs more than
-- any walk, so the way walks the rooms a player can reach as far as they take
-- it and digs as few doors as it can; with as many digs, the fewest rooms; a
-- boss room only when nothing else is near as short. `blocked` holds
-- "r<room>:<slot>" doors refused before. Returns the next room (or the empty
-- cell its red room will fill) and the slot to dig there, nil for an existing
-- door; false when it is there, nil when there is no way. The third value is
-- how many doors the whole way digs.
function R.redStep(level, index, goal, blocked)
    if index == goal then return false end
    blocked = blocked or {}
    local function edges(key)
        local list, base, cells, connected, doors = {}, tonumber(key:sub(2)), RED_CELLS, {}, {}
        if key:sub(1, 1) == "r" then
            local desc = roomAt(level, base)
            if not desc then return list end
            cells = DOOR_CELLS[desc.Data.Shape] or {}
            for _, other in ipairs(neighborsOf(level, base)) do connected[other] = true end
            -- The ultra secret room has a door only where the engine says so;
            -- the room shape's door cells would guess one into every hidden room.
            for _, safe in pairs(R.engineDoors(desc) or {}) do doors[safe] = true end
        end
        for slot = 0, 7 do
            local delta = cells[slot]
            local cell = delta and base + delta
            if cell and cell >= 0 and cell < 169 and math.abs(cell % 13 - base % 13) <= 2
                and not blocked[key .. ":" .. slot] then
                local other = roomAt(level, cell)
                if not other then
                    list[#list + 1] = { "c" .. cell, slot, true, DIG }
                else
                    local safe = other.SafeGridIndex
                    if safe == goal then
                        list[#list + 1] = { "r" .. safe, slot, not doors[safe], doors[safe] and 1 or DIG }
                    elseif connected[safe] and not SECRET[other.Data.Type] then
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
    return tonumber(key:sub(2)), hop[3] and hop[2] or nil, cost[target] // DIG
end

return R
