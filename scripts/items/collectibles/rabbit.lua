local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 묘 (Rabbit), 간을 숨겨 둔 토끼 (user design 2026-11-10, replacing the liver
-- that lay on a tinted rock).
--
-- In 「토끼전」 the rabbit dragged down to the Dragon King's palace for its
-- liver talks its way out: "I left my liver hidden on land." Here the black
-- market, down under the floor, is where the liver is kept. While a living
-- player holds it, every floor has one hidden rock in an ordinary room four
-- doors from the start room: one of that room's own rocks (user request
-- 2026-11-10: the room's obstacles carry the mark), whatever its look, with
-- faint muddy rabbit tracks (four prints to a hop) across its top, harder to
-- see than a tinted rock's mark. Rooms whose layout has rocks come first; a room
-- that turns out to have none gets a rock of its own, and a room with no room
-- for one hands the rock to another. Breaking it opens a ladder into the
-- floor's crawlspace, written beforehand as the crawlspace with the black
-- market's side passage, and the black market always has one Raw Liver for sale.
--
-- Every Raw Liver the holder takes while holding Rabbit is one liver, up to
-- four. A lethal hit with a liver at hand revives the holder on the spot, before
-- any other revive (1UP, Lazarus...), with half a heart and four seconds of
-- invincibility. 묘 is fourth of the twelve, so its numbers are fours (four is
-- also 死).
--
-- With 진 (the Dragon; user choice 2026-11-10, the Dragon King's reward): a Raw
-- Liver taken with four livers already at hand is offered to the Dragon King,
-- and every offering adds 0.4 to the holder's damage multiplier for the rest of
-- that floor (user request 2026-11-10: kept through the floor and added up,
-- x1.4, x1.8, x2.2...).
--
-- A liver at hand is one TemporaryEffect of this collectible, which items.xml
-- tags "reviveeffect" (REPENTOGON): the HUD counts it as an extra life and the
-- engine keeps the run save through the death, so reviving in
-- MC_PRE_TRIGGER_PLAYER_DEATH (before the vanilla revives) is safe. Without
-- REPENTOGON there is no safe revive and no crawlspace RoomConfig, and the item
-- does nothing.
--
-- Saved state: each player's run save `rabbit` = { livers, counted } (livers at
-- hand, and the Raw Liver copies already counted), their floor save
-- `rabbitOffering` (livers offered this floor), and the floor save
-- `rabbitMarket` = { room, list, grid, kind, adopted, flip, skip, stairs,
-- written, direct, stocked }: the hidden rock's room (safe grid index and
-- ListIndex), its cell and grid type once chosen, whether it is the room's own
-- obstacle, whether its tracks are drawn mirrored, the rooms that could hold no
-- rock, and how far the way to the market has opened.
local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local LevelRooms = require("scripts.lib.level_rooms")
local definitions = require("scripts.entities.definitions")
local Sound = require("scripts.lib.sound_volume")

local M = {}
ConchBlessing.rabbit = M

local RABBIT_ID = Isaac.GetItemIdByName("Rabbit")
local DRAGON_ID = Isaac.GetItemIdByName("Dragon")
local RAW_LIVER = CollectibleType.COLLECTIBLE_RAW_LIVER
local SAVE_KEY = "rabbit"
local OFFERING_KEY = "rabbitOffering"
local FLOOR_KEY = "rabbitMarket"
local DUNGEON = GridRooms.ROOM_DUNGEON_IDX
local MARKET = GridRooms.ROOM_BLACK_MARKET_IDX
local PASSAGE_VARIANT = 1 -- the special rooms' "ItemDungeon with Black Market Entrance"

-- The obstacles the hidden rock can be: a room's own breakable rocks of every
-- look (rock, alt rock and its marked look, bomb rock, spiked rock, fool's
-- gold). Tinted rocks keep their own mark; metal blocks, pillars, poop and TNT
-- are not rocks.
local KINDS = {}
for _, name in ipairs({ "GRID_ROCK", "GRID_ROCK_ALT", "GRID_ROCK_ALT2", "GRID_ROCK_BOMB", "GRID_ROCK_SPIKED",
    "GRID_ROCK_GOLD" }) do
    local value = GridEntityType[name]
    if value then KINDS[value] = true end
end
-- The same rocks as room layouts write them (STB entity types).
local LAYOUT_ROCKS = { [1000] = true, [1001] = true, [1002] = true, [1008] = true, [1009] = true, [1010] = true,
    [1011] = true }

M.data = {
    rooms = 4,          -- the hidden rock is four doors from the start room...
    livers = 4,         -- ...at most four livers at hand...
    halves = 1,         -- ...the holder lives on with half a heart...
    invincible = 240,   -- ...and four seconds of damage cooldown (player frames, 60 a second; the bench checks 120 updates)
    keepOut = 2,        -- the rock stays two cells off every door
    offering = 0.4,     -- 진: added to the damage multiplier for each liver offered this floor
}

local function tracksVariant()
    local entry, found = definitions.RABBIT_TRACKS, -1
    if entry and type(Isaac.GetEntityTypeByName) == "function" and type(Isaac.GetEntityVariantByName) == "function" then
        local ok, entityType, value = pcall(function()
            return Isaac.GetEntityTypeByName(entry.name), Isaac.GetEntityVariantByName(entry.name)
        end)
        if ok and entityType == entry.id and type(value) == "number" and value > 0 then found = value end
    end
    if found <= 0 and RABBIT_ID > 0 then
        ConchBlessing.printError("Rabbit: the effect '" .. tostring(entry and entry.name)
            .. "' is not registered; restart the game after entities2.xml changes")
    end
    return found
end
local TRACKS = tracksVariant()

local started = false
local pending = {}    -- [GetPtrHash(player)] = EntityPtr: revived by a liver, health not yet set
local cache = {}      -- [GetPtrHash(player)] = { raw, holding, livers }: skips the save while nothing changed
local visit = nil     -- this room visit: { list, mark, stocked, redirect, ... }
local lastList = nil  -- ListIndex of the last room of the floor's grid a player was in
local offered = {}    -- [GetPtrHash(player)] = livers offered this floor as last applied (nil: not checked yet)

local evidence
local function resetEvidence()
    evidence = { revives = 0, healed = 0, gained = 0, offered = 0, placed = 0, adopted = 0, moved = 0, marks = 0,
        stairs = 0, written = 0, direct = 0,
        redirected = 0, stocked = 0, lastCell = nil }
end
resetEvidence()

local function capable()
    return ModCallbacks.MC_PRE_TRIGGER_PLAYER_DEATH ~= nil
end

local function acting(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

local function saveReady()
    return started and SaveManager and (type(SaveManager.IsLoaded) ~= "function" or SaveManager.IsLoaded())
end

local function players()
    local list, game = {}, Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then list[#list + 1] = player end
    end
    return list
end

local function holding(player)
    return player:GetCollectibleNum(RABBIT_ID, true) > 0
end

local function anyHolder()
    for _, player in ipairs(players()) do
        if acting(player) and holding(player) then return player end
    end
    return nil
end

-- ------------------------------------------------------------------ pure rules

-- The room the hidden rock goes to: among `candidates` ({ index, distance }),
-- the ones exactly `rooms` doors away, else the farthest nearer ones, else
-- (with `farther`) the nearest farther ones; `pick(n)` chooses one of n
-- (0-based). Returns the chosen candidate, or nil when there is none.
local function chooseTarget(candidates, rooms, pick, farther)
    local exact, farthest, best, beyond, near = {}, {}, -1, {}, math.huge
    for _, c in ipairs(candidates) do
        if c.distance == rooms then exact[#exact + 1] = c end
        if c.distance < rooms then
            if c.distance > best then best, farthest = c.distance, { c }
            elseif c.distance == best then farthest[#farthest + 1] = c end
        elseif c.distance > rooms then
            if c.distance < near then near, beyond = c.distance, { c }
            elseif c.distance == near then beyond[#beyond + 1] = c end
        end
    end
    local list = #exact > 0 and exact or #farthest > 0 and farthest or farther and beyond or {}
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.index < b.index end)
    return list[pick(#list) + 1]
end

-- How many halves of red and soul hearts to add so the revived holder has
-- `halves` in all: red up to the containers' room, the rest as soul hearts.
local function topUp(red, soul, redRoom, halves)
    local need = math.max(0, halves - red - soul)
    local addRed = math.min(need, math.max(0, redRoom))
    return addRed, need - addRed
end

-- Livers at hand after the holder's Raw Liver count went from `counted` to
-- `raw`: each copy gained while holding Rabbit is a liver, up to `cap`. Copies
-- gained without Rabbit, or lost, only move the count. Returns livers, counted
-- and how many livers overflowed the cap.
local function credit(livers, counted, raw, held, cap)
    local overflow = 0
    if held and raw > counted then
        local total = livers + raw - counted
        overflow = math.max(0, total - cap)
        livers = math.min(cap, total)
    end
    return livers, raw, overflow
end

-- What the hidden rock's ladder does with the floor's one crawlspace (-4):
-- "ready" when it already is the black market's passage, "write" when it was
-- never visited (its RoomConfig can still be chosen), else "direct" (a visited
-- crawlspace keeps its layout, so the ladder sends the player on to the market).
local function crawlspacePlan(visited, roomType, variant)
    if roomType == RoomType.ROOM_DUNGEON and variant == PASSAGE_VARIANT then return "ready" end
    if (visited or 0) == 0 then return "write" end
    return "direct"
end

-- Inward step from a door slot's wall cell, on a grid `width` cells wide.
local function inward(slot, width)
    local side = slot % 4
    if side == 0 then return 1 elseif side == 1 then return width elseif side == 2 then return -1 end
    return -width
end

-- A cell for the rock: free (`free[cell]`), at least `keepOut` cells (in rows
-- and columns) from every door cell and every cell in `avoid`, and leaving
-- every door's inner cell reachable from the others as before. `order` lists
-- the cells to try. Returns the cell or nil.
local function chooseCell(width, free, doors, avoid, keepOut, order)
    local function far(cell, list, distance)
        local x, y = cell % width, cell // width
        for _, other in ipairs(list) do
            if math.max(math.abs(other % width - x), math.abs(other // width - y)) <= distance then return false end
        end
        return true
    end
    local function reach(blocked)
        if #doors == 0 then return 0 end
        local seen, queue, head, count = { [doors[1]] = true }, { doors[1] }, 1, 0
        local isDoor = {}
        for _, d in ipairs(doors) do isDoor[d] = true end
        while head <= #queue do
            local cell = queue[head]
            head = head + 1
            if isDoor[cell] then count = count + 1 end
            local x = cell % width
            for _, n in ipairs({ x > 0 and cell - 1 or nil, x < width - 1 and cell + 1 or nil, cell - width, cell + width }) do
                if n and not seen[n] and n ~= blocked and (free[n] or isDoor[n]) then
                    seen[n] = true
                    queue[#queue + 1] = n
                end
            end
        end
        return count
    end
    local baseline = reach(nil)
    for _, cell in ipairs(order) do
        if free[cell] and far(cell, doors, keepOut) and far(cell, avoid, 1) and reach(cell) == baseline then
            return cell
        end
    end
    return nil
end

-- The cells a player can walk to from the doors: `walkable[cell]` cells joined
-- in rows and columns to a door's inner cell (`starts`) on a grid `width` wide.
local function reachable(width, walkable, starts)
    local seen, queue, head = {}, {}, 1
    for _, cell in ipairs(starts) do
        if not seen[cell] then seen[cell], queue[#queue + 1] = true, cell end
    end
    while head <= #queue do
        local cell = queue[head]
        head = head + 1
        local x = cell % width
        for _, n in ipairs({ x > 0 and cell - 1 or nil, x < width - 1 and cell + 1 or nil, cell - width, cell + width }) do
            if n and not seen[n] and walkable[n] then
                seen[n] = true
                queue[#queue + 1] = n
            end
        end
    end
    return seen
end

-- The room's obstacles that can be the hidden rock: of `cells` (rock cells),
-- the ones with a reachable cell beside them in a row or column, so the ladder
-- under them can be walked onto. Keeps `cells`' order.
local function eligibleRocks(width, cells, reached)
    local list = {}
    for _, cell in ipairs(cells) do
        local x = cell % width
        if (x > 0 and reached[cell - 1]) or (x < width - 1 and reached[cell + 1]) or reached[cell - width]
            or reached[cell + width] then
            list[#list + 1] = cell
        end
    end
    return list
end

-- How many of a room layout's spawn spots can be a rock (`types[i]` lists the
-- STB entity types spot i may hold).
local function countLayoutRocks(types)
    local count = 0
    for _, spot in ipairs(types) do
        for _, t in ipairs(spot) do
            if LAYOUT_ROCKS[t] then count = count + 1 break end
        end
    end
    return count
end

-- ------------------------------------------------------------------ the floor

-- The STB entity types each spawn spot of a room's layout may hold, or nil
-- when the layout cannot be read.
local function layoutTypes(data)
    local ok, result = pcall(function()
        local spawns = data and data.Spawns
        if not spawns or type(spawns.Get) ~= "function" or not tonumber(spawns.Size) then return nil end
        local list = {}
        for i = 0, spawns.Size - 1 do
            local spawn = spawns:Get(i)
            local entries = spawn and tonumber(spawn.EntryCount) or 0
            local spot = {}
            if spawn and type(spawn.PickEntry) == "function" then
                for k = 0, entries - 1 do
                    local entry = spawn:PickEntry((k + 0.5) / entries)
                    if entry then spot[#spot + 1] = entry.Type end
                end
            end
            list[#list + 1] = spot
        end
        return list
    end)
    return ok and result or nil
end

local function floorRecord(create)
    if not saveReady() then return nil end
    local save = SaveManager.GetFloorSave()
    if type(save) ~= "table" then return nil end
    local record = save[FLOOR_KEY]
    if type(record) ~= "table" then
        if not create then return nil end
        record = {}
        save[FLOOR_KEY] = record
    end
    return record
end

-- A random source for this floor's rock that spends no gameplay RNG.
local function floorRng(salt)
    local game = Game()
    local stage = game:GetLevel():GetStage()
    local rng = RNG()
    rng:SetSeed(math.max(1, (game:GetSeeds():GetStageSeed(stage) + salt) % 4294967296), 35)
    return rng
end

-- Chooses the floor's hidden rock room once: an ordinary room whose layout
-- has rocks, four doors from the start room, else the farthest nearer one,
-- else the nearest farther one; with no such room, any ordinary room by the
-- same distances (it will get a rock of its own), else the start room (a floor
-- with no other ordinary room, measured on the Blue Womb). Rooms in
-- `record.skip` could hold no rock.
local function chooseRoom(record)
    if record.room ~= nil or Game():IsGreedMode() then return end
    local level = Game():GetLevel()
    local start = level:GetStartingRoomIndex()
    local skip = type(record.skip) == "table" and record.skip or {}
    local candidates, rocky = {}, {}
    for index, d in pairs(LevelRooms.distances(level, start)) do
        local desc = d > 0 and LevelRooms.roomAt(level, index)
        if desc and desc.SafeGridIndex == index and desc.Data and desc.Data.Type == RoomType.ROOM_DEFAULT
            and not skip[tostring(desc.ListIndex)] then
            local types = layoutTypes(desc.Data)
            local c = { index = index, distance = d, desc = desc, rocks = types and countLayoutRocks(types) or 0 }
            candidates[#candidates + 1] = c
            if c.rocks > 0 then rocky[#rocky + 1] = c end
        end
    end
    local rng = floorRng(4)
    local pick = function(n) return rng:RandomInt(n) end
    local chosen = chooseTarget(rocky, M.data.rooms, pick, true) or chooseTarget(candidates, M.data.rooms, pick, true)
    if not chosen and not skip[tostring((LevelRooms.roomAt(level, start) or {}).ListIndex)] then
        -- a floor with no other ordinary room (the Blue Womb): the start room
        local desc = LevelRooms.roomAt(level, start)
        local types = desc and desc.Data and layoutTypes(desc.Data)
        if desc then chosen = { index = start, distance = 0, desc = desc, rocks = types and countLayoutRocks(types) or 0 } end
    end
    if chosen then
        record.room, record.list, record.distance = chosen.index, chosen.desc.ListIndex, chosen.distance
        record.layoutRocks = chosen.rocks
    else
        record.room = false -- no ordinary room on this floor
    end
end

-- ------------------------------------------------------------------ the rock

local function freeCells(room)
    local free, width = {}, room:GetGridWidth()
    for cell = 0, room:GetGridSize() - 1 do
        local position = room:GetGridPosition(cell)
        if room:IsPositionInRoom(position, 0) and not room:GetGridEntity(cell)
            and room:GetGridCollision(cell) == GridCollisionClass.COLLISION_NONE then
            local busy = false
            for _, entity in ipairs(Isaac.FindInRadius(position, 20, EntityPartition.PICKUP)) do
                if entity:Exists() then busy = true break end
            end
            if not busy then free[cell] = true end
        end
    end
    return free, width
end

local function doorCells(room, width)
    local list = {}
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then list[#list + 1] = door:GetGridIndex() + inward(slot, width) end
    end
    return list
end

local function intact(room, cell, kind)
    local grid = cell and room:GetGridEntity(cell)
    return grid ~= nil and grid:GetType() == (kind or GridEntityType.GRID_ROCK)
        and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE
end

-- A two-by-two rock is four cells of one sprite: never the hidden rock.
local function bigRock(grid)
    local ok, animation = pcall(function() return grid:GetSprite():GetAnimation() end)
    return ok and type(animation) == "string" and animation:sub(1, 3) == "big"
end

-- Makes one of the room's own rocks the hidden rock: an intact rock of KINDS
-- a player can walk up to, picked with the floor's RNG. Returns whether one was.
local function adopt(record)
    local room = Game():GetRoom()
    local width, size = room:GetGridWidth(), room:GetGridSize()
    local walkable, cells = {}, {}
    for cell = 0, size - 1 do
        if room:GetGridCollision(cell) == GridCollisionClass.COLLISION_NONE
            and room:IsPositionInRoom(room:GetGridPosition(cell), 0) then
            walkable[cell] = true
        end
        local grid = room:GetGridEntity(cell)
        if grid and KINDS[grid:GetType()] and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE
            and not bigRock(grid) then
            cells[#cells + 1] = cell
        end
    end
    local list = eligibleRocks(width, cells, reachable(width, walkable, doorCells(room, width)))
    if #list == 0 then return false end
    local rng = floorRng(44)
    local cell = list[rng:RandomInt(#list) + 1]
    record.grid, record.kind, record.adopted = cell, room:GetGridEntity(cell):GetType(), true
    record.flip = rng:RandomInt(2) == 1
    evidence.adopted, evidence.lastCell = evidence.adopted + 1, cell
    return true
end

local function stairsAt(room, cell)
    local grid = cell and room:GetGridEntity(cell)
    return grid ~= nil and grid:GetType() == GridEntityType.GRID_STAIRS
end

-- Lays a rock of its own in a room that has none to mark. Returns whether it stands.
local function place(record)
    local room = Game():GetRoom()
    local free, width = freeCells(room)
    local avoid = {}
    for _, player in ipairs(players()) do avoid[#avoid + 1] = room:GetGridIndex(player.Position) end
    local rng = floorRng(44)
    local order = {}
    for cell in pairs(free) do order[#order + 1] = cell end
    table.sort(order)
    for i = #order, 2, -1 do
        local j = rng:RandomInt(i) + 1
        order[i], order[j] = order[j], order[i]
    end
    local cell = chooseCell(width, free, doorCells(room, width), avoid, M.data.keepOut, order)
    if not cell then
        ConchBlessing.printDebug("[Rabbit] no free cell for the hidden rock in this room")
        return false
    end
    if not room:SpawnGridEntity(cell, GridEntityType.GRID_ROCK, 0, math.max(1, rng:Next()), 0) then
        ConchBlessing.printError("[Rabbit] could not spawn the hidden rock at " .. cell)
        return false
    end
    record.grid, record.kind, record.adopted = cell, GridEntityType.GRID_ROCK, false
    record.flip = rng:RandomInt(2) == 1
    evidence.placed, evidence.lastCell = evidence.placed + 1, cell
    return true
end

-- Draws the rabbit tracks on the standing rock (one effect a visit, just above
-- the rock in the draw order), and takes them away once the rock is broken.
local function markRock(record)
    if TRACKS <= 0 or not visit then return end
    local mark = visit.mark and visit.mark.Ref
    if mark and mark:Exists() then return end
    if visit.marked then return end -- spawned once a visit; the engine removed it with the room
    visit.marked = true
    local at = Game():GetRoom():GetGridPosition(record.grid)
    local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, TRACKS, 0, at, Vector.Zero, nil)
    effect = effect and effect:ToEffect()
    if not effect then return end
    effect:GetSprite():Play("Tracks", true)
    effect:GetSprite().FlipX = record.flip == true
    effect.DepthOffset = 8
    visit.mark = EntityPtr(effect)
    evidence.marks = evidence.marks + 1
end

local function unmarkRock()
    local mark = visit and visit.mark and visit.mark.Ref
    if mark and mark:Exists() then mark:Remove() end
    if visit then visit.mark = nil end
end

local function passageConfig()
    if type(RoomConfig) ~= "table" or type(RoomConfig.GetRoomByStageTypeAndVariant) ~= "function" then return nil end
    local mode = Game():IsGreedMode() and 1 or 0
    local ok, config = pcall(RoomConfig.GetRoomByStageTypeAndVariant, StbType and StbType.SPECIAL_ROOMS or 0,
        RoomType.ROOM_DUNGEON, PASSAGE_VARIANT, mode)
    return ok and config or nil
end

-- Makes the floor's crawlspace the black market's passage when it still can
-- be; a visited crawlspace keeps its layout and the ladder leads on directly.
local function ensureCrawlspace(record)
    local desc = Game():GetLevel():GetRoomByIdx(DUNGEON)
    if not desc then return end
    local data = desc.Data
    local plan = crawlspacePlan(desc.VisitedCount, data and data.Type, data and data.Variant)
    if plan == "write" then
        local config = passageConfig()
        local wrote = config ~= nil and pcall(function() desc.Data = config end)
        if wrote then
            record.written, record.direct = true, nil
            evidence.written = evidence.written + 1
        else
            ConchBlessing.printError("[Rabbit] could not make the crawlspace the black market's passage")
            record.direct = true
        end
    elseif plan == "direct" then
        if not record.direct then evidence.direct = evidence.direct + 1 end
        record.direct = true
    else
        record.written = true
    end
end

-- The rock is gone: a ladder down where it stood.
local function openLadder(record)
    local room = Game():GetRoom()
    ensureCrawlspace(record)
    if not stairsAt(room, record.grid) then
        local grid = Isaac.GridSpawn(GridEntityType.GRID_STAIRS, 0, room:GetGridPosition(record.grid), true)
        if not grid or grid:GetType() ~= GridEntityType.GRID_STAIRS then
            ConchBlessing.printError("[Rabbit] could not open the ladder at " .. tostring(record.grid))
            return
        end
        if not record.stairs then evidence.stairs = evidence.stairs + 1 end
    end
    record.stairs = true
end

-- The hidden rock's room: choose the rock on the first visit (one of the
-- room's own, else one laid there, else the rock goes to another room), draw
-- its tracks, and open the ladder once it is broken (rubble, gone, or turned
-- into something else).
local function tendRock(record, desc)
    if not record.room or desc.ListIndex ~= record.list then return end
    local room = Game():GetRoom()
    if record.grid == nil then
        if visit.tried then return end
        visit.tried = true
        if not adopt(record) and not place(record) then
            record.skip = type(record.skip) == "table" and record.skip or {}
            record.skip[tostring(record.list)] = true
            record.room, record.list = nil, nil
            evidence.moved = evidence.moved + 1
            chooseRoom(record)
            return
        end
    end
    if record.stairs then
        if not visit.ladder then
            visit.ladder = true
            openLadder(record)
        end
        return
    end
    if intact(room, record.grid, record.kind) then
        visit.sawRock = true
        markRock(record)
    else
        unmarkRock()
        openLadder(record)
        visit.ladder = true
    end
end

-- ------------------------------------------------------------------ the market

local function shopFields(pickup)
    return { price = pickup.Price, id = pickup.ShopItemId, auto = pickup.AutoUpdatePrice }
end

-- The black market always has one Raw Liver for sale (once a floor): the first
-- shop item becomes it, keeping its deal, else one is put out.
local function stock(record)
    local list = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and pickup.SubType > 0 then
            if pickup.SubType == RAW_LIVER then
                record.stocked = true
                return
            end
            if pickup:IsShopItem() then list[#list + 1] = pickup end
        end
    end
    table.sort(list, function(a, b) return a.ShopItemId < b.ShopItemId end)
    local pickup = list[1]
    if pickup then
        local fields = shopFields(pickup)
        pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, RAW_LIVER, true, true, true)
        pickup.ShopItemId, pickup.Price, pickup.AutoUpdatePrice = fields.id, fields.price, fields.auto
    else
        local room = Game():GetRoom()
        local at = room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true)
        local spawned = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, RAW_LIVER, at,
            Vector.Zero, nil):ToPickup()
        if not spawned then return end
        spawned.ShopItemId, spawned.Price, spawned.AutoUpdatePrice = -2, PickupPrice.PRICE_ONE_HEART, true
    end
    record.stocked = true
    evidence.stocked = evidence.stocked + 1
end

-- ------------------------------------------------------------------ the livers

local function ledger(player, raw)
    if not saveReady() then return nil end
    local save = SaveManager.GetRunSave(player)
    if type(save) ~= "table" then return nil end
    local data = save[SAVE_KEY]
    if type(data) ~= "table" then
        data = {}
        save[SAVE_KEY] = data
    end
    if type(data.livers) ~= "number" then
        -- the earlier Rabbit kept a liver per copy, some on rocks: those at hand stay
        local old = type(data.out) == "table" and math.max(0, (tonumber(data.held) or 0) - #data.out) or 0
        data.livers = math.min(M.data.livers, old)
        data.counted = raw
        data.out, data.held = nil, nil
    end
    if type(data.counted) ~= "number" then data.counted = raw end
    return data
end

-- The player's record without creating it (nil before their first).
local function peek(player)
    if not saveReady() then return nil end
    local save = SaveManager.GetRunSave(player)
    local data = type(save) == "table" and save[SAVE_KEY]
    return type(data) == "table" and data or nil
end

-- The livers a player offered this floor (an older save's `true` is one).
local function offerings(save)
    local value = type(save) == "table" and save[OFFERING_KEY]
    if value == true then return 1 end
    return math.max(0, math.floor(tonumber(value) or 0))
end

-- The damage multiplier after `count` offerings this floor: 0.4 added for each.
local function offeringMultiplier(count)
    return 1 + M.data.offering * count
end

-- 진's offering: the floor's damage multiplier, set from the player's floor
-- save and taken away on the next floor (its save is new).
local function syncOffering(player)
    local key = GetPtrHash(player)
    local want = offerings(SaveManager.GetFloorSave(player))
    if offered[key] == want then return end
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not um or RABBIT_ID <= 0 then return end
    if want > 0 then
        um:SetItemMultiplier(player, RABBIT_ID, "Damage", offeringMultiplier(want), "Rabbit")
    else
        local state = ConchBlessing.getUnifiedMultiplierState and ConchBlessing.getUnifiedMultiplierState(player, um)
        local row = state and state.itemMultipliers and state.itemMultipliers[RABBIT_ID]
        if row and row.Damage then um:RemoveItemMultiplier(player, RABBIT_ID, "Damage") end
    end
    if um.QueueCacheUpdate then um:QueueCacheUpdate(player, "Damage") end
    if um.SaveToSaveManager then um:SaveToSaveManager(player) end
    offered[key] = want
end

-- Offers `count` overflowing livers: each adds 0.4 to this floor's multiplier.
local function offer(player, count)
    local save = SaveManager.GetFloorSave(player)
    if type(save) ~= "table" or count <= 0 then return end
    local total = offerings(save) + count
    save[OFFERING_KEY] = total
    evidence.offered = evidence.offered + count
    local hud = Game():GetHUD()
    if hud and type(hud.ShowItemText) == "function" then
        pcall(hud.ShowItemText, hud, ConchBlessing.Locale.text("ui.rabbit.offering",
            string.format("%.1f", offeringMultiplier(total))), "")
    end
    SFXManager():Play(SoundEffect.SOUND_THUNDER, Sound.volume(0.6), 0, false, 0.8)
    syncOffering(player)
end

-- Counts Raw Livers gained and keeps the livers at hand as this collectible's
-- TemporaryEffect while the player holds Rabbit.
local function reconcile(player)
    local raw, held = player:GetCollectibleNum(RAW_LIVER, true), holding(player)
    local data = held and ledger(player, raw) or peek(player)
    if not data then
        cache[GetPtrHash(player)] = { raw = raw, held = held, livers = 0 }
        return
    end
    if type(data.livers) ~= "number" then data = ledger(player, raw) end
    local before, overflow = data.livers, 0
    data.livers, data.counted, overflow = credit(data.livers, data.counted, raw, held, M.data.livers)
    if data.livers > before then evidence.gained = evidence.gained + data.livers - before end
    if overflow > 0 and DRAGON_ID > 0 and player:HasCollectible(DRAGON_ID) then offer(player, overflow) end
    local want = held and data.livers or 0
    local effects = player:GetEffects()
    local have = effects:GetCollectibleEffectNum(RABBIT_ID)
    if have < want then
        effects:AddCollectibleEffect(RABBIT_ID, false, want - have)
    elseif have > want then
        effects:RemoveCollectibleEffect(RABBIT_ID, have - want)
    end
    cache[GetPtrHash(player)] = { raw = raw, held = held, livers = want }
end

function M.livers(player)
    local data = player and peek(player)
    return data and tonumber(data.livers) or 0
end

function M.market() return floorRecord(false) end

local function heal(player)
    pending[GetPtrHash(player)] = nil
    local healthType = type(player.GetHealthType) == "function" and player:GetHealthType() or nil
    if not (HealthType and healthType == HealthType.LOST) then
        local red, soul = player:GetHearts(), player:GetSoulHearts()
        local addRed, addSoul = topUp(red, soul, player:GetEffectiveMaxHearts() - red, M.data.halves)
        if addRed > 0 then player:AddHearts(addRed) end
        if addSoul > 0 then player:AddSoulHearts(addSoul) end
    end
    player:SetMinDamageCooldown(M.data.invincible)
    evidence.healed = evidence.healed + 1
    local hud = Game():GetHUD()
    if hud and type(hud.ShowItemText) == "function" then
        pcall(hud.ShowItemText, hud, ConchBlessing.Locale.text("ui.rabbit.revive"), "")
    end
end

-- A lethal hit with a liver at hand: the holder lives on in this room. Runs
-- before the vanilla revives, so 1UP and the like are kept.
function M.onPreTriggerDeath(_, player)
    if not player or not saveReady() then return nil end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return nil end
    if not holding(player) then return nil end
    local data = peek(player)
    if not data or (tonumber(data.livers) or 0) <= 0 then return nil end
    local effects = player:GetEffects()
    if effects:GetCollectibleEffectNum(RABBIT_ID) <= 0 then return nil end
    data.livers = data.livers - 1
    effects:RemoveCollectibleEffect(RABBIT_ID, 1)
    cache[GetPtrHash(player)] = nil
    pending[GetPtrHash(player)] = EntityPtr(player)
    evidence.revives = evidence.revives + 1
    return false
end

function M.onPostRevive(_, player)
    if player and pending[GetPtrHash(player)] then heal(player) end
end

-- ------------------------------------------------------------------ callbacks

local function enterRoom()
    local level = Game():GetLevel()
    local index = level:GetCurrentRoomIndex()
    local desc = LevelRooms.mainRoom(level)
    visit = { list = desc and desc.ListIndex or index }
    local record = floorRecord(false)
    -- a ladder into a crawlspace that kept its own layout leads on to the market
    if index == DUNGEON and record and record.direct and record.list ~= nil and lastList == record.list then
        visit.redirect = true
    end
    if desc then lastList = desc.ListIndex end
end

-- The floor's rock and market in the current room, while a holder lives.
local function tendHere()
    local record = floorRecord(true)
    if not record then return end
    chooseRoom(record)
    local level = Game():GetLevel()
    if level:GetCurrentRoomIndex() == MARKET then
        if not visit.stocked and not record.stocked then stock(record) end
        visit.stocked = true
        return
    end
    local desc = LevelRooms.mainRoom(level)
    if desc then tendRock(record, desc) end
end

function M.onUpdate()
    if not started then return end
    for key, ref in pairs(pending) do
        local player = ref.Ref and ref.Ref:ToPlayer()
        if not player then
            pending[key] = nil
        elseif acting(player) then
            heal(player)
        end
    end
    if not saveReady() then return end
    local holder = nil
    for _, player in ipairs(players()) do
        local key = GetPtrHash(player)
        if acting(player) and not pending[key] then
            local known = cache[key]
            local raw, held = player:GetCollectibleNum(RAW_LIVER, true), holding(player)
            if not known or known.raw ~= raw or known.held ~= held
                or (held and player:GetEffects():GetCollectibleEffectNum(RABBIT_ID) ~= known.livers) then
                reconcile(player)
            end
            if offered[key] == nil then syncOffering(player) end
            if held and not holder then holder = player end
        end
    end
    if not holder then return end
    if not visit then enterRoom() end
    if visit.redirect then
        visit.redirect = nil
        evidence.redirected = evidence.redirected + 1
        Game():StartRoomTransition(MARKET, Direction.NO_DIRECTION, RoomTransitionAnim.WALK, holder, -1)
        return
    end
    tendHere()
end

-- The room just loaded: its rock, tracks and market liver are set at once, so
-- they show from the first frame of the room transition (updates pause while
-- it plays; measured 2026-11-10, the rock and its tracks popped in after it).
function M.onNewRoom()
    if not started then return end
    enterRoom()
    if saveReady() and anyHolder() then tendHere() end
end

-- A new floor: its own rock, and 진's offering ends (the floor save is new).
function M.onNewLevel()
    if not started then return end
    visit, lastList, offered = nil, nil, {}
end

function M.onGameStarted()
    started = true
    pending, cache, visit, lastList, offered = {}, {}, nil, nil, {}
    if not capable() then
        ConchBlessing.printDebug("[Rabbit] REPENTOGON's death callbacks are missing; the item does nothing")
        return
    end
    for _, player in ipairs(players()) do
        if holding(player) or peek(player) then reconcile(player) end
    end
    -- a Continue may have put the crawlspace's own layout back
    local record = floorRecord(false)
    if record and record.stairs and not record.direct then ensureCrawlspace(record) end
end

function M.onGameExit()
    started = false
    pending, cache, visit, lastList, offered = {}, {}, nil, nil, {}
end

M._test = {
    chooseTarget = chooseTarget,
    reachable = reachable,
    eligibleRocks = eligibleRocks,
    countLayoutRocks = countLayoutRocks,
    layoutTypes = layoutTypes,
    kinds = function() return KINDS end,
    topUp = topUp,
    credit = credit,
    crawlspacePlan = crawlspacePlan,
    inward = inward,
    chooseCell = chooseCell,
    reconcile = reconcile,
    intact = intact,
    stairsAt = stairsAt,
    tracksVariant = function() return TRACKS end,
    mark = function() return visit and visit.mark and visit.mark.Ref end,
    offered = function(player) return offered[GetPtrHash(player)] end,
    syncOffering = syncOffering,
    offeringMultiplier = offeringMultiplier,
    offerings = offerings,
    pending = function() return pending end,
    started = function() return started end,
    setStarted = function(value) started = value end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
}

if capable() then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_TRIGGER_PLAYER_DEATH, M.onPreTriggerDeath)
    if ModCallbacks.MC_POST_PLAYER_REVIVE then
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_PLAYER_REVIVE, M.onPostRevive)
    end
end
do
    local sm, mod = SaveManager, ConchBlessing.originalMod
    if sm and mod and mod.__SAVEMANAGER_UNIQUE_KEY and sm.SaveCallbacks then
        -- a luamod reload in the middle of a run never sees game start
        if sm.SaveCallbacks.POST_DATA_LOAD then
            mod:AddCallback(sm.SaveCallbacks.POST_DATA_LOAD, function(_, _, isLuamod)
                if isLuamod then M.onGameStarted() end
            end)
        end
        -- Glowing Hourglass puts the run and floor saves back: recount from them.
        if sm.SaveCallbacks.POST_GLOWING_HOURGLASS_RESET then
            mod:AddCallback(sm.SaveCallbacks.POST_GLOWING_HOURGLASS_RESET, function()
                cache, visit, offered = {}, nil, {}
            end)
        end
    end
end

return M
