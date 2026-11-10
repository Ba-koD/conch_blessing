local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 장승 (Jangseung), the Guardian Angel's Magic Conch positive upgrade (user
-- design 2026-11-10).
--
-- A 장승 stood at the mouth of a village: it marked where the village began
-- (경계표) and kept out the evil spirits and plagues of the world outside
-- (수호). Here every special room is a village. While a living player holds
-- it, a pair of 장승 (천하대장군 and 지하여장군) stands on either side of each
-- door that leads into a special room (any room but an ordinary one), a hidden
-- secret room's wall included, so they give a secret room away (it still takes
-- a bomb to open). A pair also stands at the wall where a Red Key opens the way
-- toward the ultra secret room with the fewest red rooms (user request
-- 2026-11-10, the red room route 축's jealous black ox digs).
--
-- In front of each pair a half circle two tiles wide is the village's inside,
-- marked on the floor as trodden earth (user request 2026-11-10). An enemy that
-- is not a boss is pushed back out of it and feared, and an enemy shot that
-- crosses into it is gone. Bosses and their shots are not kept out, and the
-- player gets no invincibility (user decisions 2026-11-10).
--
-- With Door Stop (user request 2026-11-10), whose own effect keeps the door the
-- player last came in through open, the door the player came in by gets a pair
-- in every room too, so the way back is always a village.
--
-- The statues are effect entities that only stand and draw (Kronos never sees
-- them); the earth is a FLAG_RENDER_FLOOR stamp, drawn into the floor once a
-- visit, as 축's furrows are. Nothing is saved: every room works it out again.
local LevelRooms = require("scripts.lib.level_rooms")
local definitions = require("scripts.entities.definitions")

local M = {}
ConchBlessing.jangseung = M

local ID = Isaac.GetItemIdByName("Jangseung")
local DOOR_STOP = TrinketType.TRINKET_DOOR_STOP or 124

M.data = {
    radius = 80,  -- the village's inside: two tiles from the door
    inset = 20,   -- the guarded half circle's middle sits this far inside the wall...
    groundInset = 0, -- ...and the earth starts at the threshold, where the floor shows
    -- Each pair stands right against its wall beside the door frame (user
    -- requests 2026-11-10), every wall alike.
    spread = 46,  -- this far to each side of the door, just outside the frame...
    stand = 22,   -- ...its foot this far into the room from the wall's middle: against the
                  -- wall's face, leaning back 3 degrees to rest its head on it (model3d.py)
    fear = 60,    -- updates an enemy stays feared once pushed out
    push = 7,     -- speed it is pushed out at
}

local function effectVariant(entry)
    local found = -1
    if entry and type(Isaac.GetEntityTypeByName) == "function" and type(Isaac.GetEntityVariantByName) == "function" then
        local ok, entityType, value = pcall(function()
            return Isaac.GetEntityTypeByName(entry.name), Isaac.GetEntityVariantByName(entry.name)
        end)
        if ok and entityType == entry.id and type(value) == "number" and value > 0 then found = value end
    end
    if found <= 0 and ID > 0 then
        ConchBlessing.printError("Jangseung: the effect '" .. tostring(entry and entry.name)
            .. "' is not registered; restart the game after entities2.xml changes")
    end
    return found
end
local statueVariant = effectVariant(definitions.JANGSEUNG)
local groundVariant = effectVariant(definitions.JANGSEUNG_GROUND)

local started = false
local marked = nil   -- ListIndex of the room the markers belong to, or false outside the grid
local markers = {}   -- { slot, red, center = Vector, inward = Vector }
local statues = {}   -- EntityPtr of this room's statues
local stamped = {}   -- [slot] = true once its earth is on this room's floor

local evidence
local function resetEvidence()
    evidence = { markers = 0, red = 0, statues = 0, stamps = 0, pushed = 0, cleared = 0, slots = {}, entry = nil }
end
resetEvidence()

local function acting(player)
    if not player or not player:Exists() or player:IsDead() then return false end
    return not (type(player.IsCoopGhost) == "function" and player:IsCoopGhost())
end

local function holder()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and acting(player) and player:HasCollectible(ID) then return player end
    end
    return nil
end

-- Whether a living holder also holds Door Stop (carried, smelted or innate).
local function doorStop()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and acting(player) and player:HasCollectible(ID) and player:HasTrinket(DOOR_STOP) then return true end
    end
    return false
end

-- ------------------------------------------------------------------ pure rules

-- The way into the room from a door slot's wall: left walls face right, top
-- walls down, right walls left and bottom walls up.
local function inwardOf(slot)
    local side = slot % 4
    if side == 0 then return 1, 0 elseif side == 1 then return 0, 1 elseif side == 2 then return -1, 0 end
    return 0, -1
end

-- Whether (x, y), relative to the half circle's middle, is inside the village:
-- within `radius` and not behind the wall (`ix`, `iy` point into the room).
local function inside(x, y, ix, iy, radius)
    return x * x + y * y < radius * radius and x * ix + y * iy > -radius * 0.25
end

-- The doors that get a pair: `doors[slot]` = the room type behind it (0..7),
-- a pair for every one leading into a room that is not ordinary, `red`, the
-- slot to dig toward the ultra secret room, when no door stands there, and
-- `entry`, the door the player came in by (Door Stop), when it has no pair yet.
local function chooseMarkers(doors, ordinary, red, entry)
    local list = {}
    for slot = 0, 7 do
        local kind = doors[slot]
        if kind ~= nil and kind ~= ordinary then list[#list + 1] = { slot = slot, red = false } end
    end
    if red ~= nil and doors[red] == nil then list[#list + 1] = { slot = red, red = true } end
    if entry ~= nil and doors[entry] == ordinary then list[#list + 1] = { slot = entry, red = false, entry = true } end
    return list
end

-- ------------------------------------------------------------------ the room

local function clearStatues()
    for _, ref in ipairs(statues) do
        local statue = ref.Ref
        if statue and statue:Exists() then statue:Remove() end
    end
    statues = {}
end

local function forget()
    clearStatues()
    marked, markers, stamped = nil, {}, {}
end

local function slotPosition(room, slot)
    local ok, position = pcall(room.GetDoorSlotPosition, room, slot)
    if ok and position then return position end
    return nil
end

-- The markers of the room the holder is in.
local function survey(level, room, desc)
    local doors = {}
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then doors[slot] = door.TargetRoomType end
    end
    local red
    local ultra = LevelRooms.ultraRoom(level)
    if ultra and ultra ~= desc.SafeGridIndex then
        local nextRoom, slot = LevelRooms.redStep(level, desc.SafeGridIndex, ultra, nil)
        if nextRoom and slot then red = slot end
    end
    local entry
    if doorStop() then
        local slot = level.EnterDoor
        if type(slot) == "number" and slot >= 0 and slot <= 7 and doors[slot] ~= nil then entry = slot end
        evidence.entry = entry or -1
    end
    local list = chooseMarkers(doors, RoomType.ROOM_DEFAULT, red, entry)
    local found = {}
    for _, marker in ipairs(list) do
        local wall = slotPosition(room, marker.slot)
        if wall then
            local ix, iy = inwardOf(marker.slot)
            marker.inward = Vector(ix, iy)
            marker.wall = wall
            marker.center = wall + marker.inward * M.data.inset
            found[#found + 1] = marker
            evidence.slots[#evidence.slots + 1] = (marker.red and "r" or marker.entry and "e" or "") .. marker.slot
            if marker.red then evidence.red = evidence.red + 1 end
        end
    end
    evidence.markers = evidence.markers + #found
    return found
end

-- The pair's places beside a wall point (wx, wy) facing (ix, iy): 천하대장군
-- first (the left one, or the upper one on a side wall), then 지하여장군.
local function pairPlaces(wx, wy, ix, iy)
    local spread, stand = M.data.spread, M.data.stand
    local sx, sy = -iy, ix
    local ax, ay = wx + ix * stand + sx * spread, wy + iy * stand + sy * spread
    local bx, by = wx + ix * stand - sx * spread, wy + iy * stand - sy * spread
    local aFirst
    if iy ~= 0 then aFirst = ax < bx else aFirst = ay < by end
    if aFirst then return ax, ay, bx, by end
    return bx, by, ax, ay
end

-- How the pair against a wall is drawn (user decisions 2026-11-10, after a
-- 3D model of the room: docs/previews/jangseung/model3d.py). The room is a box
-- seen from above its middle, so a post standing against a wall is seen from
-- above, its cap toward the wall: the top wall's frame shows it so, the bottom
-- wall uses it upside down, the right wall's frame lies on its side with the
-- cap to the right (drawn longer: a post on a side wall is seen along its
-- height), and the left wall uses that mirrored. Returns the frame and the flips.
local function frameOf(ix, iy)
    if ix > 0 then return "Side", true, false elseif ix < 0 then return "Side", false, false end
    if iy < 0 then return "Top", false, true end
    return "Top", false, false
end

local function raise(marker)
    if statueVariant <= 0 then return end
    local ax, ay, bx, by = pairPlaces(marker.wall.X, marker.wall.Y, marker.inward.X, marker.inward.Y)
    local view, flipX, flipY = frameOf(marker.inward.X, marker.inward.Y)
    for i, at in ipairs({ Vector(ax, ay), Vector(bx, by) }) do
        local statue = Isaac.Spawn(EntityType.ENTITY_EFFECT, statueVariant, marker.red and 1 or 0, at, Vector.Zero, nil)
        statue = statue and statue:ToEffect()
        if statue then
            local sprite = statue:GetSprite()
            sprite:Play((i == 1 and "Cheonha" or "Jiha") .. view .. (marker.red and "Red" or ""), true)
            sprite.FlipX, sprite.FlipY = flipX, flipY
            statues[#statues + 1] = EntityPtr(statue)
            evidence.statues = evidence.statues + 1
        end
    end
end

-- Stamps a marker's trodden earth into this room's floor, once a visit.
local function stamp(marker)
    if groundVariant <= 0 or stamped[marker.slot] then return end
    stamped[marker.slot] = true
    local at = marker.wall + marker.inward * M.data.groundInset
    local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, groundVariant, 0, at, Vector.Zero, nil)
    effect = effect and effect:ToEffect()
    if not effect then return end
    local sprite = effect:GetSprite()
    sprite:Play("Ground", true)
    sprite.Rotation = math.deg(math.atan(marker.inward.Y, marker.inward.X)) - 90
    effect:AddEntityFlags(EntityFlag.FLAG_RENDER_FLOOR)
    evidence.stamps = evidence.stamps + 1
end

-- ------------------------------------------------------------------ the guard

local function bossShot(projectile)
    local spawner = projectile.SpawnerEntity
    return spawner ~= nil and spawner:IsBoss()
end

local function guard(player)
    if #markers == 0 then return end
    local radius = M.data.radius
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local projectile = entity.Type == EntityType.ENTITY_PROJECTILE and entity:ToProjectile()
        local npc = not projectile and entity:ToNPC()
        if (projectile and not bossShot(projectile))
            or (npc and npc:IsActiveEnemy(false) and not npc:IsBoss() and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)) then
            for _, marker in ipairs(markers) do
                local offset = entity.Position - marker.center
                if inside(offset.X, offset.Y, marker.inward.X, marker.inward.Y, radius) then
                    if projectile then
                        projectile:Die()
                        evidence.cleared = evidence.cleared + 1
                    else
                        local away = offset:Length() > 1 and offset:Normalized() or marker.inward
                        npc.Velocity = away * M.data.push
                        npc:AddFear(EntityRef(player), M.data.fear)
                        evidence.pushed = evidence.pushed + 1
                    end
                    break
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ callbacks

-- Raises this room's pairs and stamps their earth once.
local function settle()
    local level, room = Game():GetLevel(), Game():GetRoom()
    local desc = LevelRooms.mainRoom(level)
    local key = desc and desc.ListIndex or false
    if marked ~= key then
        forget()
        marked = key
        if desc then
            markers = survey(level, room, desc)
            for _, marker in ipairs(markers) do raise(marker) end
        end
    end
    for _, marker in ipairs(markers) do stamp(marker) end
end

function M.onUpdate()
    if not started then return end
    local player = holder()
    if not player then
        if marked ~= nil then forget() end
        return
    end
    settle()
    guard(player)
end

-- A new room's floor has no earth yet, and its statues are gone with the old
-- room. The new pairs stand at once, so they show from the first frame of the
-- room transition (updates pause while it plays; 묘's rock popped in after it,
-- measured 2026-11-10).
function M.onNewRoom()
    statues, marked, markers, stamped = {}, nil, {}, {}
    if started and holder() then settle() end
end

function M.onGameStarted()
    started = true
    statues, marked, markers, stamped = {}, nil, {}, {}
end

function M.onGameExit()
    started = false
    statues, marked, markers, stamped = {}, nil, {}, {}
end

function M.onModUnload()
    clearStatues()
end

function M.markers() return markers end

M._test = {
    inwardOf = inwardOf,
    inside = inside,
    chooseMarkers = chooseMarkers,
    pairPlaces = pairPlaces,
    frameOf = frameOf,
    doorStop = doorStop,
    statues = function() return statues end,
    statueVariant = function() return statueVariant end,
    groundVariant = function() return groundVariant end,
    started = function() return started end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
}

return M
