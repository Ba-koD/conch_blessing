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
-- A 금줄 is strung between each pair's heads across the door (user request
-- 2026-11-15, replacing the red-route pair's red cloth), and the minimap icon
-- of the room behind the door hangs from its middle on a short string, turned
-- with its wall so its top faces the rope, with no tag behind it, so every
-- kind of room reads differently and the door stays in sight; a room no icon
-- fits gets no rope (user requests 2026-11-16). The rope is red where a Red Key
-- opened or opens the way: a red room (one the Red Key made, a special one
-- included), the ultra secret
-- room and the wall to dig toward it. A door that appears or changes while the
-- player is in the room (a Red Key, a devil deal door after the boss) gets its
-- pair at once.
--
-- In front of each pair a half circle two tiles wide is the village's inside,
-- marked on the floor as trodden earth (user request 2026-11-10). An enemy that
-- is not a boss is pushed back out of it and feared, and an enemy shot that
-- crosses into it is gone; bosses and their shots are not kept out. A player
-- standing inside takes no damage at all, a boss's included (user request
-- 2026-11-10, replacing the earlier "no invincibility"): every hit but
-- self-damage (player_hits' rule: devil deals, IV Bag, curse room doors,
-- Sacrifice Room spikes...) is cancelled before it lands. A 금줄 laid round
-- the player's feet shows they are inside (user: not overdone, and Korean); it
-- flashes and rustles when it turns a hit away. It is drawn only, from this
-- process's state, and never spawned.
--
-- With Door Stop (user request 2026-11-10), whose own effect keeps the door the
-- player last came in through open, the door the player came in by gets a pair
-- in every room too, so the way back is always a village.
--
-- The statues and the ropes are effect entities that only stand and draw
-- (Kronos never sees them; the rope's SubType names its icon and colour, and
-- the icon is the vanilla minimap art drawn hanging from it); the earth is a
-- FLAG_RENDER_FLOOR stamp, drawn into the floor once a visit, as 축's furrows
-- are. Nothing is saved: every room works it out again.
local LevelRooms = require("scripts.lib.level_rooms")
local definitions = require("scripts.entities.definitions")
local Hits = require("scripts.lib.player_hits")
local Sound = require("scripts.lib.sound_volume")

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
    stand = 22,   -- ...its foot this far into the room from the wall's middle: on the
                  -- wall-floor seam (world 140 on the top wall), where a door's threshold is
    -- The 금줄's hook, where its icon hangs at the string's end (its frame's
    -- pivot, docs/previews/jangseung/author.py), stands half way between the
    -- pair this far in from a top or bottom wall's middle...
    hangTop = -4.15,
    hangSide = -33.38, -- ...and from a side wall's: beyond it, as the posts there are seen along their height
    ropeDepth = 1000, -- the rope hangs high on the wall: it draws over whatever passes under it
    -- a one-pixel rim of the rope's straw round the hanging icon, so a dark icon
    -- still reads over a dark doorway (no paper behind it: user 2026-11-16)
    rimR = 220,
    rimG = 186,
    rimB = 112,
    fear = 60,    -- updates an enemy stays feared once pushed out
    push = 7,     -- speed it is pushed out at
    -- the 금줄 round a sheltered player's feet
    wardFade = 8,      -- updates it takes to fade in or out
    wardAlpha = 0.85,  -- its opacity once shown
    wardFlash = 12,    -- updates a turned-away hit's flash lasts
    wardSoundGap = 8,  -- updates between two of one player's rustles
}

local WARD_ANM2 = "gfx/effects/conch_jangseung_ward.anm2"
-- The room icons, drawn in place. MiniMAPI (a hard dependency) hides the
-- vanilla minimap by shipping a gfx/ui/minimap_icons.anm2 whose animations
-- have no frames, so that file draws nothing while MiniMAPI is installed
-- (measured 2026-11-16); MiniMAPI's own icon file holds the same animations
-- with the vanilla pixels at the same places, so it is used first.
local ICON_ANM2 = "gfx/ui/minimap_icons.anm2"
local MINIMAPI_ICON_ANM2 = "gfx/ui/minimapapi_icons.anm2"

-- The minimap icon hung on the 금줄 for each kind of room behind a door. A
-- room with no icon of its own borrows the nearest: the crawlspace and the
-- secret exit (a way down) the ladder, Boss Rush the boss challenge's swords.
-- Rooms not listed (I AM ERROR, Greed's exit, the black market, which only a
-- crawlspace leads to) get no rope, only the pair (user request 2026-11-16).
local ICONS = {
    ROOM_SHOP = "IconShop",
    ROOM_TREASURE = "IconTreasureRoom",
    ROOM_BOSS = "IconBoss",
    ROOM_MINIBOSS = "IconMiniboss",
    ROOM_SECRET = "IconSecretRoom",
    ROOM_SUPERSECRET = "IconSuperSecretRoom",
    ROOM_ARCADE = "IconArcade",
    ROOM_CURSE = "IconCurseRoom",
    ROOM_CHALLENGE = "IconAmbushRoom",
    ROOM_LIBRARY = "IconLibrary",
    ROOM_SACRIFICE = "IconSacrificeRoom",
    ROOM_DEVIL = "IconDevilRoom",
    ROOM_ANGEL = "IconAngelRoom",
    ROOM_DUNGEON = "IconLadder",
    ROOM_BOSSRUSH = "IconBossAmbushRoom",
    ROOM_ISAACS = "IconIsaacsRoom",
    ROOM_BARREN = "IconBarrenRoom",
    ROOM_CHEST = "IconChestRoom",
    ROOM_DICE = "IconDiceRoom",
    ROOM_PLANETARIUM = "IconPlanetarium",
    ROOM_TELEPORTER = "IconTeleporterRoom",
    ROOM_TELEPORTER_EXIT = "IconTeleporterRoom",
    ROOM_SECRET_EXIT = "IconLadder",
    ROOM_ULTRASECRET = "IconUltraSecretRoom",
}
local DEVIL_TREASURE_ICON = "IconTreasureRoomRed" -- Devil's Crown's treasure room, as the minimap shows it
local BOSS_CHALLENGE_ICON = "IconBossAmbushRoom"  -- a challenge room of subtype 1
local ROUTE_ICON = "IconUltraSecretRoom"          -- the wall to dig toward the ultra secret room

-- Each icon's number in the rope's SubType (`number * 2 + red`), 0 none.
local ICON_LIST, ICON_NUMBER = {}, {}
for _, name in ipairs({ "IconShop", "IconTreasureRoom", DEVIL_TREASURE_ICON, "IconBoss", "IconMiniboss",
    "IconSecretRoom", "IconSuperSecretRoom", "IconArcade", "IconCurseRoom", "IconAmbushRoom", BOSS_CHALLENGE_ICON,
    "IconLibrary", "IconSacrificeRoom", "IconDevilRoom", "IconAngelRoom", "IconLadder", "IconIsaacsRoom",
    "IconBarrenRoom", "IconChestRoom", "IconDiceRoom", "IconPlanetarium", "IconTeleporterRoom",
    "IconUltraSecretRoom" }) do
    ICON_LIST[#ICON_LIST + 1] = name
    ICON_NUMBER[name] = #ICON_LIST
end
-- Each icon's opaque box { x0, y0, x1, y1 } (x1 and y1 past its last pixel) in
-- its 16x16 vanilla frame, measured offline from the extracted
-- minimap_icons.png (tests/test_jangseung.py checks it), since a running game
-- cannot read a sprite's pixels. The icon hangs by the middle of its top edge,
-- toward the rope (`iconPose`); a resource pack's own icons may hang a pixel
-- off.
local ICON_BOX = {
    IconShop = { 3, 2, 10, 10 },
    IconTreasureRoom = { 3, 3, 10, 9 },
    IconTreasureRoomRed = { 3, 3, 10, 9 },
    IconBoss = { 2, 2, 11, 10 },
    IconMiniboss = { 3, 3, 10, 10 },
    IconSecretRoom = { 3, 2, 10, 10 },
    IconSuperSecretRoom = { 3, 2, 10, 10 },
    IconArcade = { 3, 2, 10, 9 },
    IconCurseRoom = { 3, 2, 10, 9 },
    IconAmbushRoom = { 3, 4, 10, 9 },
    IconBossAmbushRoom = { 2, 3, 10, 9 },
    IconLibrary = { 3, 2, 11, 10 },
    IconSacrificeRoom = { 3, 2, 10, 9 },
    IconDevilRoom = { 3, 2, 10, 10 },
    IconAngelRoom = { 3, 2, 10, 10 },
    IconLadder = { 4, 3, 9, 10 },
    IconIsaacsRoom = { 3, 2, 11, 10 },
    IconBarrenRoom = { 3, 2, 11, 10 },
    IconChestRoom = { 3, 3, 11, 10 },
    IconDiceRoom = { 3, 2, 11, 10 },
    IconPlanetarium = { 3, 2, 10, 10 },
    IconTeleporterRoom = { 3, 2, 11, 9 },
    IconUltraSecretRoom = { 3, 2, 10, 10 },
}
local ICON_BOX_DEFAULT = { 3, 2, 10, 10 }
-- ICONS keyed by the RoomType numbers this runtime has.
local ICON_OF = {}
for name, icon in pairs(ICONS) do
    local kind = RoomType and RoomType[name]
    if type(kind) == "number" then ICON_OF[kind] = icon end
end

local function flag(name, bit)
    local value = RoomDescriptor and RoomDescriptor[name]
    return type(value) == "number" and value or bit
end
local FLAG_RED_ROOM = flag("FLAG_RED_ROOM", 1 << 10)
local FLAG_DEVIL_TREASURE = flag("FLAG_DEVIL_TREASURE", 1 << 11)

local callbackPriority = rawget(_G, "CallbackPriority")
local EARLY = type(callbackPriority) == "table" and tonumber(callbackPriority.EARLY) or -100

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
local ropeVariant = effectVariant(definitions.JANGSEUNG_ROPE)

local started = false
local marked = nil   -- ListIndex of the room the markers belong to, or false outside the grid
local doorsSeen = nil -- the room's doors when its markers were last worked out (doorSignature)
local markers = {}   -- { slot, route, entry, icon, red, wall, center, inward, entities = { EntityPtr } }
local stamped = {}   -- [slot] = true once its earth is on this room's floor
local wards = {}     -- [GetPtrHash(player)] = { alpha, flash, sound }: the 금줄 being shown

local evidence
local function resetEvidence()
    evidence = { markers = 0, red = 0, statues = 0, ropes = 0, stamps = 0, pushed = 0, cleared = 0, blocked = 0,
        resurveys = 0, slots = {}, entry = nil }
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

-- The marker whose village holds the point (x, y), or nil.
local function sheltered(list, x, y, radius)
    for _, marker in ipairs(list) do
        local center, inward = marker.center, marker.inward
        if center and inward and inside(x - center.X, y - center.Y, inward.X, inward.Y, radius) then return marker end
    end
    return nil
end

-- Whether a hit on a sheltered player is turned away: everything but
-- self-damage (player_hits' rule, the same one every hit reaction uses).
local function turnsAway(flags)
    return not Hits.isSelfDamage(flags)
end

-- The doors that get a pair: `doors[slot]` = the room type behind it (0..7),
-- a pair for every one leading into a room that is not ordinary, `route`, the
-- slot to dig toward the ultra secret room, when no door stands there, and
-- `entry`, the door the player came in by (Door Stop), when it has no pair yet.
local function chooseMarkers(doors, ordinary, route, entry)
    local list = {}
    for slot = 0, 7 do
        local kind = doors[slot]
        if kind ~= nil and kind ~= ordinary then list[#list + 1] = { slot = slot, route = false } end
    end
    if route ~= nil and doors[route] == nil then list[#list + 1] = { slot = route, route = true } end
    if entry ~= nil and doors[entry] == ordinary then list[#list + 1] = { slot = entry, route = false, entry = true } end
    return list
end

-- The 금줄's icon and colour for a door into a room of type `kind` whose
-- descriptor carries `flags` and whose layout has `subtype`: the room's
-- minimap icon (nil: no rope), and whether the rope is red, which it is
-- for a red room (a Red Key's) and the ultra secret room.
local function tagFor(kind, flags, subtype)
    flags = flags or 0
    local icon = ICON_OF[kind]
    if kind == RoomType.ROOM_TREASURE and flags & FLAG_DEVIL_TREASURE ~= 0 then
        icon = DEVIL_TREASURE_ICON
    elseif kind == RoomType.ROOM_CHALLENGE and subtype == 1 then
        icon = BOSS_CHALLENGE_ICON
    end
    return icon, flags & FLAG_RED_ROOM ~= 0 or kind == RoomType.ROOM_ULTRASECRET
end

-- The rope's SubType: its icon's number twice over, plus one when it is red.
local function ropeSubtype(icon, red)
    return (ICON_NUMBER[icon] or 0) * 2 + (red and 1 or 0)
end

local function ropeIcon(subtype)
    return ICON_LIST[subtype >> 1], subtype & 1 == 1
end

-- How the icon hangs from the rope's hook (its frame's pivot): turned with
-- its wall so its top always faces the rope (user request 2026-11-16), upright
-- on the top wall, upside down on the bottom wall, a quarter turn clockwise on
-- the right wall (the rope beside it to the right) and anticlockwise on the
-- left, hanging by the middle pixel of its top edge, which lands on the hook's
-- pixel. Returns the sprite's Rotation and where to render it from the hook
-- (the icon frames' pivot is their top-left corner). Matches author.py's
-- icon_pose.
local function iconPose(icon, side, flip)
    local box = ICON_BOX[icon] or ICON_BOX_DEFAULT
    local ax, ay = box[1] + (box[3] - box[1] - 1) // 2, box[2]
    if not side then
        if flip then return 180, ax + 1, ay end
        return 0, -ax, -ay
    end
    if flip then return -90, -ay, ax + 1 end
    return 90, ay, -ax
end

-- The room's doors as one number (the room type behind each slot): when it
-- changes while the player is in the room, the pairs are worked out again.
local function doorSignature(room)
    local signature = 0
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        signature = signature * 64 + (door and (door.TargetRoomType % 63) + 1 or 0)
    end
    return signature
end

-- ------------------------------------------------------------------ the room

local function clearMarker(marker)
    for _, ref in ipairs(marker.entities or {}) do
        local entity = ref.Ref
        if entity and entity:Exists() then entity:Remove() end
    end
    marker.entities, marker.rope = nil, nil
end

local function forget()
    for _, marker in ipairs(markers) do clearMarker(marker) end
    marked, doorsSeen, markers, stamped = nil, nil, {}, {}
end

local function slotPosition(room, slot)
    local ok, position = pcall(room.GetDoorSlotPosition, room, slot)
    if ok and position then return position end
    return nil
end

-- The descriptor of the room behind a door, or nil.
local function targetOf(level, door)
    local index = door.TargetRoomIndex
    if type(index) ~= "number" then return nil end
    local ok, desc = pcall(level.GetRoomByIdx, level, index)
    return ok and desc or nil
end

-- The markers of the room the holder is in.
local function survey(level, room, desc)
    local doors, tags = {}, {}
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            doors[slot] = door.TargetRoomType
            local target = targetOf(level, door)
            local icon, red = tagFor(door.TargetRoomType, target and target.Flags,
                target and target.Data and target.Data.Subtype)
            tags[slot] = { icon = icon, red = red }
        end
    end
    local route
    local ultra = LevelRooms.ultraRoom(level)
    if ultra and ultra ~= desc.SafeGridIndex then
        local nextRoom, slot = LevelRooms.redStep(level, desc.SafeGridIndex, ultra, nil)
        if nextRoom and slot then route = slot end
    end
    local entry
    if doorStop() then
        local slot = level.EnterDoor
        if type(slot) == "number" and slot >= 0 and slot <= 7 and doors[slot] ~= nil then entry = slot end
        evidence.entry = entry or -1
    end
    local list = chooseMarkers(doors, RoomType.ROOM_DEFAULT, route, entry)
    local found = {}
    for _, marker in ipairs(list) do
        local wall = slotPosition(room, marker.slot)
        if wall then
            local ix, iy = inwardOf(marker.slot)
            marker.inward = Vector(ix, iy)
            marker.wall = wall
            marker.center = wall + marker.inward * M.data.inset
            local tag = tags[marker.slot]
            if marker.route then
                marker.icon, marker.red = ROUTE_ICON, true
            elseif tag then
                marker.icon, marker.red = tag.icon, tag.red
            end
            found[#found + 1] = marker
            evidence.slots[#evidence.slots + 1] = (marker.route and "r" or marker.entry and "e" or "") .. marker.slot
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

-- Where the 금줄's hook (its frame's pivot) stands: half way between the pair,
-- `hangTop` or `hangSide` in from the wall's middle.
local function ropePlace(wall, ix, iy)
    local hang = iy ~= 0 and M.data.hangTop or M.data.hangSide
    return wall.X + ix * hang, wall.Y + iy * hang
end

local function raise(marker)
    marker.entities = {}
    local view, flipX, flipY = frameOf(marker.inward.X, marker.inward.Y)
    if statueVariant > 0 then
        local ax, ay, bx, by = pairPlaces(marker.wall.X, marker.wall.Y, marker.inward.X, marker.inward.Y)
        for i, at in ipairs({ Vector(ax, ay), Vector(bx, by) }) do
            local statue = Isaac.Spawn(EntityType.ENTITY_EFFECT, statueVariant, 0, at, Vector.Zero, nil)
            statue = statue and statue:ToEffect()
            if statue then
                local sprite = statue:GetSprite()
                sprite:Play((i == 1 and "Cheonha" or "Jiha") .. view, true)
                sprite.FlipX, sprite.FlipY = flipX, flipY
                marker.entities[#marker.entities + 1] = EntityPtr(statue)
                evidence.statues = evidence.statues + 1
            end
        end
    end
    if ropeVariant > 0 and marker.icon then -- a room no icon fits gets only the pair
        local x, y = ropePlace(marker.wall, marker.inward.X, marker.inward.Y)
        local rope = Isaac.Spawn(EntityType.ENTITY_EFFECT, ropeVariant, ropeSubtype(marker.icon, marker.red),
            Vector(x, y), Vector.Zero, nil)
        rope = rope and rope:ToEffect()
        if rope then
            local sprite = rope:GetSprite()
            sprite:Play("Rope" .. view .. (marker.red and "Red" or ""), true)
            sprite.FlipX, sprite.FlipY = flipX, flipY
            rope.DepthOffset = M.data.ropeDepth
            marker.entities[#marker.entities + 1] = EntityPtr(rope)
            marker.rope = EntityPtr(rope) -- its icon is drawn after the room's entities (M.onRoomRender)
            evidence.ropes = evidence.ropes + 1
        end
    end
end

-- Whether a marker worked out again still stands as it did (its pair and rope
-- are kept rather than raised anew).
local function sameMarker(a, b)
    return a.slot == b.slot and a.route == b.route and a.entry == b.entry and a.icon == b.icon and a.red == b.red
end

-- Works this room's markers out again after its doors changed: unchanged ones
-- keep their pair, gone ones are taken down, new ones raised.
local function resurvey(level, room, desc)
    local old = {}
    for _, marker in ipairs(markers) do old[marker.slot] = marker end
    local fresh = survey(level, room, desc)
    for i, marker in ipairs(fresh) do
        local before = old[marker.slot]
        if before and sameMarker(before, marker) then
            fresh[i], old[marker.slot] = before, nil
        end
    end
    for _, marker in pairs(old) do clearMarker(marker) end
    for _, marker in ipairs(fresh) do
        if not marker.entities then raise(marker) end
    end
    markers = fresh
    evidence.resurveys = evidence.resurveys + 1
end

-- The live rope effects of this room's markers.
local function ropes()
    local list = {}
    for _, marker in ipairs(markers) do
        for _, ref in ipairs(marker.entities or {}) do
            local entity = ref.Ref
            if entity and entity:Exists() and entity.Variant == ropeVariant then list[#list + 1] = entity end
        end
    end
    return list
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

-- ------------------------------------------------------------------ the shelter

-- Whether this player stands inside one of this room's villages while a living
-- holder keeps the pairs standing.
local function shelters(player)
    if not started or #markers == 0 or not player then return false end
    local position = player.Position
    return sheltered(markers, position.X, position.Y, M.data.radius) ~= nil and holder() ~= nil
end

local function wardOf(player, create)
    local hash = GetPtrHash(player)
    local ward = wards[hash]
    if not ward and create then
        ward = { alpha = 0, flash = 0, sound = -1000 }
        wards[hash] = ward
    end
    return ward
end

-- Fades each player's 금줄 in while they stand inside and out once they leave.
local function tendWards(active)
    local game = Game()
    local seen = {}
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local hash = GetPtrHash(player)
            seen[hash] = true
            local inside = active and not player:IsDead() and shelters(player)
            local ward = wardOf(player, inside)
            if ward then
                ward.alpha = inside and math.min(M.data.wardFade, ward.alpha + 1) or math.max(0, ward.alpha - 1)
                if ward.flash > 0 then ward.flash = ward.flash - 1 end
                if not inside and ward.alpha == 0 and ward.flash == 0 then wards[hash] = nil end
            end
        end
    end
    for hash in pairs(wards) do
        if not seen[hash] then wards[hash] = nil end
    end
end

-- A hit turned away: the 금줄 shows at once, flashes and rustles (at most once
-- every few updates, so a creep pool does not rustle every frame).
local function turnedAway(player)
    local ward = wardOf(player, true)
    ward.alpha = M.data.wardFade
    ward.flash = M.data.wardFlash
    local frame = Game():GetFrameCount()
    if frame - ward.sound >= M.data.wardSoundGap then
        ward.sound = frame
        SFXManager():Play(SoundEffect.SOUND_PAPER_OUT, Sound.volume(0.7), 0, false, 0.8)
    end
end

-- Pre-damage, EARLY: a sheltered player takes no damage but self-damage.
function M.onPlayerDamage(_, entity, amount, flags)
    local player = entity and entity:ToPlayer()
    if not player or not turnsAway(flags) or not shelters(player) then return end
    evidence.blocked = evidence.blocked + 1
    turnedAway(player)
    return false
end

local wardSprite = nil -- nil: not loaded yet; false: failed (reported once)
local function wardArt()
    if wardSprite == nil then
        local ok, sprite = pcall(function()
            local s = Sprite()
            s:Load(WARD_ANM2, true)
            assert(type(s.IsLoaded) ~= "function" or s:IsLoaded(), "it did not load")
            s:Play("Idle", true)
            return s
        end)
        wardSprite = ok and sprite or false
        if not ok then
            ConchBlessing.printError("Jangseung: the 금줄 art " .. WARD_ANM2 .. " is unavailable (" .. tostring(sprite)
                .. "); restart the game after resource changes")
        end
    end
    return wardSprite or nil
end

local function reflecting()
    local room = Game():GetRoom()
    return RenderMode ~= nil and type(room.GetRenderMode) == "function"
        and room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
end

local iconSprite = nil -- nil: not loaded yet; false: failed (reported once)
local rimSteps, rimColor, plainColor -- built on the first draw
-- The file the icons are drawn from: MiniMAPI's while it is loaded, else the
-- vanilla one.
local function iconFile()
    return rawget(_G, "MinimapAPI") ~= nil and MINIMAPI_ICON_ANM2 or ICON_ANM2
end

local function iconArt()
    if iconSprite == nil then
        local path = iconFile()
        local ok, sprite = pcall(function()
            local s = Sprite()
            s:Load(path, true)
            assert(type(s.IsLoaded) ~= "function" or s:IsLoaded(), "it did not load")
            return s
        end)
        iconSprite = ok and sprite or false
        if not ok then
            ConchBlessing.printError("Jangseung: the minimap icons " .. path .. " are unavailable (" .. tostring(sprite)
                .. ")")
        end
    end
    return iconSprite or nil
end

-- Draws one rope's minimap icon hanging from its string, turned with its wall
-- (`iconPose`; the rope itself is mirrored for the bottom and left walls, as
-- the statues are, and its animation and flips say which wall it is on).
local function drawHung(rope)
    local icon = ropeIcon(rope.SubType)
    if not icon then return end
    local sprite = iconArt()
    if not sprite then return end
    local ropeSprite = rope:GetSprite()
    local side = ropeSprite:GetAnimation():find("Side", 1, true) ~= nil
    local flip = ropeSprite.FlipY
    if side then flip = ropeSprite.FlipX end
    local rotation, dx, dy = iconPose(icon, side, flip)
    sprite:SetFrame(icon, 0)
    sprite.Rotation = rotation
    local base = Isaac.WorldToScreen(rope.Position) + Vector(dx, dy)
    if not rimSteps then
        rimSteps = { Vector(1, 0), Vector(-1, 0), Vector(0, 1), Vector(0, -1) }
        rimColor = Color(0, 0, 0, 1, M.data.rimR / 255, M.data.rimG / 255, M.data.rimB / 255)
        plainColor = Color(1, 1, 1, 1, 0, 0, 0)
    end
    sprite.Color = rimColor -- the icon's own shape in solid straw, one pixel out each way
    for _, step in ipairs(rimSteps) do sprite:Render(base + step) end
    sprite.Color = plainColor
    sprite:Render(base)
end

-- The icons are drawn after the room's entities (REPENTOGON's
-- MC_POST_ROOM_RENDER_ENTITIES, else MC_POST_RENDER), as the rope hangs over
-- everything anyway (`ropeDepth`). Drawn from the rope's own
-- MC_POST_EFFECT_RENDER they never showed in game, though every call ran with
-- the right frame, colour and place (measured 2026-11-16).
function M.onRoomRender()
    if #markers == 0 or reflecting() then return end
    for _, marker in ipairs(markers) do
        local rope = marker.rope and marker.rope.Ref
        if rope and rope:Exists() then drawHung(rope) end
    end
end

-- Draws the 금줄 on the floor round the player's feet: before the player with
-- REPENTOGON's pre-render hook, else right after (it is half see-through).
function M.onPlayerRender(_, player)
    if not next(wards) or not player then return end
    local ward = wards[GetPtrHash(player)]
    if not ward or ward.alpha <= 0 or reflecting() then return end
    -- Hemispatial Neglect drawing the player again into its capture
    local neglect = ConchBlessing.hemispatialneglect
    if neglect and neglect.isCapturing and neglect.isCapturing() then return end
    local sprite = wardArt()
    if not sprite then return end
    local shown = ward.alpha / M.data.wardFade
    local flash = ward.flash / M.data.wardFlash
    local glow = 0.45 * flash
    sprite.Color = Color(1, 1, 1, M.data.wardAlpha * shown, glow, glow * 0.85, glow * 0.5)
    local swell = 1 + 0.12 * math.sin(math.pi * flash) -- swells once and settles
    sprite.Scale = Vector(swell * player.SpriteScale.X, swell * player.SpriteScale.Y)
    if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(sprite) end
    sprite:Render(Isaac.WorldToScreen(player.Position))
end

-- ------------------------------------------------------------------ callbacks

-- Raises this room's pairs and stamps their earth once, and raises them again
-- when a door appears or changes while the player is here.
local function settle()
    local level, room = Game():GetLevel(), Game():GetRoom()
    local desc = LevelRooms.mainRoom(level)
    local key = desc and desc.ListIndex or false
    if marked ~= key then
        forget()
        marked = key
        if desc then
            doorsSeen = doorSignature(room)
            markers = survey(level, room, desc)
            for _, marker in ipairs(markers) do raise(marker) end
        end
    elseif desc then
        local doors = doorSignature(room)
        if doors ~= doorsSeen then
            doorsSeen = doors
            resurvey(level, room, desc)
        end
    end
    for _, marker in ipairs(markers) do stamp(marker) end
end

function M.onUpdate()
    if not started then return end
    local player = holder()
    if not player then
        if marked ~= nil then forget() end
        if next(wards) then tendWards(false) end
        return
    end
    settle()
    guard(player)
    tendWards(true)
end

-- A new room's floor has no earth yet, and its statues are gone with the old
-- room. The new pairs stand at once, so they show from the first frame of the
-- room transition (updates pause while it plays; 묘's rock popped in after it,
-- measured 2026-11-10).
function M.onNewRoom()
    marked, doorsSeen, markers, stamped, wards = nil, nil, {}, {}, {}
    if started and holder() then settle() end
end

function M.onGameStarted()
    started = true
    marked, doorsSeen, markers, stamped, wards = nil, nil, {}, {}, {}
end

function M.onGameExit()
    started = false
    marked, doorsSeen, markers, stamped, wards = nil, nil, {}, {}, {}
end

function M.onModUnload()
    for _, marker in ipairs(markers) do clearMarker(marker) end
    markers, wards = {}, {}
end

function M.markers() return markers end
function M.shelters(player) return shelters(player) end

-- Priorities and hooks the ItemData registrar cannot express: the shelter must
-- cancel a hit before anything at default priority reacts to it (player_hits'
-- base-game fallback counts hits there), and the 금줄 lies under the player
-- where REPENTOGON can draw before them.
if type(ConchBlessing.AddCallback) == "function" then
    local damage = ModCallbacks.MC_ENTITY_TAKE_DMG
    if type(ConchBlessing.AddPriorityCallback) == "function" then
        ConchBlessing:AddPriorityCallback(damage, EARLY, M.onPlayerDamage, EntityType.ENTITY_PLAYER)
    else
        ConchBlessing:AddCallback(damage, M.onPlayerDamage, EntityType.ENTITY_PLAYER)
    end
    local before = ModCallbacks.MC_PRE_PLAYER_RENDER
    ConchBlessing:AddCallback(type(before) == "number" and before or ModCallbacks.MC_POST_PLAYER_RENDER,
        M.onPlayerRender)
    if ropeVariant > 0 then
        local after = ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES
        ConchBlessing:AddCallback(type(after) == "number" and after or ModCallbacks.MC_POST_RENDER, M.onRoomRender)
    end
end

M._test = {
    inwardOf = inwardOf,
    inside = inside,
    sheltered = sheltered,
    turnsAway = turnsAway,
    tendWards = tendWards,
    wards = function() return wards end,
    ward = function(player) return player and wards[GetPtrHash(player)] or nil end,
    chooseMarkers = chooseMarkers,
    tagFor = tagFor,
    ropeSubtype = ropeSubtype,
    ropeIcon = ropeIcon,
    iconPose = iconPose,
    drawHung = drawHung,
    iconFile = iconFile,
    iconBox = ICON_BOX,
    ropePlace = ropePlace,
    doorSignature = doorSignature,
    sameMarker = sameMarker,
    iconList = function() return ICON_LIST end,
    pairPlaces = pairPlaces,
    frameOf = frameOf,
    doorStop = doorStop,
    ropes = ropes,
    statueVariant = function() return statueVariant end,
    groundVariant = function() return groundVariant end,
    ropeVariant = function() return ropeVariant end,
    started = function() return started end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
}

return M
