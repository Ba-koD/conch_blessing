local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 장승 (Jangseung): the lifecycle contract and its isolated cases. Every room
-- is reached by a real room transition, every door read from the engine's own
-- doors, the red route checked against LevelRooms.redStep, each 금줄's icon
-- against the room behind its door, a Red Key's door against the engine's own
-- MakeRedRoomDoor, and the guard watched on real enemies and enemy shots. How
-- the statues, the ropes, their icons and the earth look stays a LOOK check.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local LevelRooms = require("scripts.lib.level_rooms")
local C = {}

local function jangseung() return ConchBlessing.jangseung end
local function T() return jangseung()._test end

-- The live statues in the room (NO_QUERY included).
local function statues()
    local list = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == T().statueVariant() and entity:Exists() then
            list[#list + 1] = entity
        end
    end
    return list
end

-- The doors of this room that should get a pair, read independently.
local function expectedSlots()
    local level, room = Game():GetLevel(), Game():GetRoom()
    local desc = LevelRooms.mainRoom(level)
    local slots = {}
    if not desc then return slots end
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door and door.TargetRoomType ~= RoomType.ROOM_DEFAULT then slots[slot] = "door" end
    end
    local ultra = LevelRooms.ultraRoom(level)
    if ultra and ultra ~= desc.SafeGridIndex then
        local _, slot = LevelRooms.redStep(level, desc.SafeGridIndex, ultra, nil)
        if slot and not room:GetDoor(slot) then slots[slot] = "red" end
    end
    return slots
end

local function markedSlots()
    local slots = {}
    for _, marker in ipairs(jangseung().markers()) do slots[marker.slot] = marker.route and "red" or "door" end
    return slots
end

local function describe(slots)
    local parts = {}
    for slot = 0, 7 do if slots[slot] then parts[#parts + 1] = slot .. ":" .. slots[slot] end end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function same(a, b)
    for slot = 0, 7 do if a[slot] ~= b[slot] then return false end end
    return true
end

local function count(slots)
    local n = 0
    for _ in pairs(slots) do n = n + 1 end
    return n
end

-- The live ropes in the room (NO_QUERY included).
local function ropes()
    local list = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == T().ropeVariant() and entity:Exists() then
            list[#list + 1] = entity
        end
    end
    return list
end

-- What each marked slot's 금줄 should carry, read from the door and the room
-- behind it: "<icon>" or "<icon>/red"; a slot whose room no icon fits has no
-- rope (user request 2026-11-16) and is left out.
local function expectedTags()
    local level, room = Game():GetLevel(), Game():GetRoom()
    local tags = {}
    for slot, kind in pairs(expectedSlots()) do
        if kind == "red" then
            tags[slot] = "IconUltraSecretRoom/red"
        else
            local door = room:GetDoor(slot)
            local target = door and level:GetRoomByIdx(door.TargetRoomIndex)
            local icon, red = T().tagFor(door.TargetRoomType, target and target.Flags,
                target and target.Data and target.Data.Subtype)
            if icon then tags[slot] = icon .. (red and "/red" or "") end
        end
    end
    return tags
end

-- What each slot's live rope carries (its SubType's icon and colour), and the
-- slots whose animation disagrees with that colour or the wall's frame, or
-- whose rope carries no icon (a room without one gets no rope).
local function ropeTags()
    local tags, wrong = {}, {}
    for _, marker in ipairs(jangseung().markers()) do
        local x, y = T().ropePlace(marker.wall, marker.inward.X, marker.inward.Y)
        for _, rope in ipairs(ropes()) do
            if rope.Position:Distance(Vector(x, y)) < 1 then
                local icon, red = T().ropeIcon(rope.SubType)
                tags[marker.slot] = (icon or "-") .. (red and "/red" or "")
                local view = T().frameOf(marker.inward.X, marker.inward.Y)
                local anim = rope:GetSprite():GetAnimation()
                if not icon or anim ~= "Rope" .. view .. (red and "Red" or "") then
                    wrong[#wrong + 1] = marker.slot .. ":" .. anim
                end
            end
        end
    end
    return tags, wrong
end

local function describeTags(tags)
    local parts = {}
    for slot = 0, 7 do if tags[slot] then parts[#parts + 1] = slot .. ":" .. tags[slot] end end
    return "{" .. table.concat(parts, ",") .. "}"
end

C.JANGSEUNG = { stage = function(plan, _, n)
    plan.wait(2)
    plan.check(n > 0 and "a pair at each special door of the room" or "no statue without the item", function()
        local expected = n > 0 and expectedSlots() or {}
        local wanted = count(expected)
        local hung = n > 0 and count(expectedTags()) or 0
        return same(markedSlots(), expected) and #statues() == wanted * 2 and #ropes() == hung,
            string.format("expected %s marked %s statues=%d ropes=%d", describe(expected), describe(markedSlots()),
                #statues(), #ropes())
    end)
end }

-- Cases that share one run (S.sequenceBundle below); each stays callable alone.
local shared = {}
local case = S.caseIn(shared, "JANGSEUNG", { conditions = true })

local function requireModule(plan)
    plan.require("Jangseung module and its effects", function()
        local module = jangseung()
        return module and module._test and T().statueVariant() > 0 and T().groundVariant() > 0
            and T().ropeVariant() > 0 and true or nil,
            "module or effect variants missing (restart after entities2.xml changes)"
    end)
end

local function setup(plan, id, hold)
    requireModule(plan)
    plan.act(function(player)
        local level = Game():GetLevel()
        if type(level.RemoveCurses) == "function" then level:RemoveCurses(level:GetCurses()) end
        if hold then player:AddCollectible(id, 0, false) end
        T().resetEvidence()
    end)
    plan.wait(4)
end

-- An ordinary room next to the room `pick` chooses (by safe grid index), or nil.
local function besideRoom(level, pick)
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc and desc.Data and desc.GridIndex >= 0 and pick(desc) then
            for _, index in ipairs(LevelRooms.neighborsOf(level, desc.SafeGridIndex)) do
                local other = LevelRooms.roomAt(level, index)
                if other and other.Data.Type == RoomType.ROOM_DEFAULT then return other.SafeGridIndex end
            end
        end
    end
    return nil
end

-- The room's own hostile NPCs ("Type.Variant"), appearing ones included.
local function hostiles()
    local list = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc and npc:Exists() and not npc:IsDead() and (npc:IsEnemy() or npc:IsActiveEnemy(true))
            and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            list[#list + 1] = npc.Type .. "." .. npc.Variant
        end
    end
    return list
end

local function clearEnemies()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc and (npc:IsEnemy() or npc:IsActiveEnemy(true)) and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            npc:Remove()
        end
    end
end

local function goTo(plan, label, find)
    plan.require(label .. ": a room to test in", function(_, ctx)
        local why
        ctx.goal, why = find(Game():GetLevel())
        return ctx.goal ~= nil or nil, why or "this floor has no such room"
    end)
    plan.act(function(player, ctx)
        -- count only what the test room raises and stamps: the start room may
        -- have its own pair (a treasure room beside it, say)
        T().resetEvidence()
        Game():StartRoomTransition(ctx.goal, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, 0)
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex == ctx.goal and RoomTransition.GetTransitionMode() == 0
    end, 240, label)
    plan.act(function(player)
        clearEnemies()
        player.Position = Game():GetRoom():GetCenterPos()
    end)
    plan.wait(6)
    -- the room's own enemies go, including ones still appearing (not yet
    -- "active"): a Ragling and a Fat Sack left that way killed Isaac once he
    -- stepped out of the village in shelter (2026-11-16)
    plan.require(label .. ": none of the room's own enemies left", function()
        clearEnemies()
        local left = hostiles()
        return #left == 0 or nil, #left == 0 and "room empty" or ("still here: " .. table.concat(left, ","))
    end)
end

local function besideType(name)
    return function(level)
        return besideRoom(level, function(desc) return desc.Data.Type == RoomType[name] end)
    end
end

-- A pair at the treasure room's door, on the earth.
case("doors", function(plan, id)
    setup(plan, id, true)
    goTo(plan, "the room beside the treasure room", besideType("ROOM_TREASURE"))
    plan.check("a pair stands at every door into a special room", function()
        local expected, marked = expectedSlots(), markedSlots()
        local treasure = false
        local room = Game():GetRoom()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomType == RoomType.ROOM_TREASURE and marked[slot] == "door" then treasure = true end
        end
        return treasure and same(marked, expected) and #statues() == count(expected) * 2,
            string.format("expected %s marked %s statues=%d", describe(expected), describe(marked), #statues())
    end)
    plan.check("a 금줄 hangs at every pair, its icon the room behind the door", function()
        local expected = expectedTags()
        local got, wrong = ropeTags()
        local treasure = false
        for _, tag in pairs(got) do if tag:find("^IconTreasureRoom") then treasure = true end end
        return treasure and same(got, expected) and #wrong == 0 and #ropes() == count(expected),
            string.format("expected %s ropes %s wrong=%s ropes=%d", describeTags(expected), describeTags(got),
                table.concat(wrong, ","), #ropes())
    end)
    plan.check("each pair's earth is stamped once", function()
        local e = T().evidence()
        return e.stamps == #jangseung().markers(), string.format("stamps=%d markers=%d", e.stamps, #jangseung().markers())
    end)
    plan.note("LOOK", function()
        return "the pair (hatted 천하대장군 left/above), the 금줄 between their heads with the treasure room's crown "
            .. "hanging from its middle by a short string (straw rim, no paper behind it, the doorway in sight), and "
            .. "the trodden earth in front of the treasure door"
    end)
end)

-- A hidden secret room's wall gets its pair too.
case("secret", function(plan, id)
    setup(plan, id, true)
    goTo(plan, "the room beside the secret room", besideType("ROOM_SECRET"))
    plan.check("the secret room's hidden wall has a pair", function()
        local room, marked = Game():GetRoom(), markedSlots()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomType == RoomType.ROOM_SECRET then
                return marked[slot] == "door", string.format("slot %d open=%s marked %s", slot, tostring(door:IsOpen()),
                    describe(marked))
            end
        end
        return false, "no door to the secret room"
    end)
end)

-- The wall a Red Key opens toward the ultra secret room gets a pair whose 금줄
-- is red and carries the ultra secret room's icon; digging it follows at once.
case("red", function(plan, id)
    setup(plan, id, true)
    goTo(plan, "a room where the red route starts", function(level)
        local ultra = LevelRooms.ultraRoom(level)
        if not ultra then return nil, "this floor has no ultra secret room" end
        -- the dig may start from any room the route walks to, special ones too
        -- (the pair stands wherever the holder is); an ordinary room first
        local found
        local rooms = level:GetRooms()
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if desc and desc.Data and desc.GridIndex >= 0 and desc.SafeGridIndex ~= ultra
                and desc.Data.Type ~= RoomType.ROOM_BOSS then
                local _, slot = LevelRooms.redStep(level, desc.SafeGridIndex, ultra, nil)
                if slot and desc.Data.Type == RoomType.ROOM_DEFAULT then
                    found = desc.SafeGridIndex
                    break
                elseif slot and found == nil then
                    found = desc.SafeGridIndex
                end
            end
        end
        return found, found == nil and "no room on this floor starts the dig" or nil
    end)
    plan.check("a pair with a red 금줄 and the ultra secret room's icon stands at the wall to dig", function()
        local expected, marked = expectedSlots(), markedSlots()
        local red
        for slot = 0, 7 do if expected[slot] == "red" then red = slot end end
        local tags, wrong = ropeTags()
        return red ~= nil and marked[red] == "red" and tags[red] == "IconUltraSecretRoom/red" and #wrong == 0
                and #statues() == count(expected) * 2,
            string.format("expected %s marked %s ropes %s wrong=%s statues=%d", describe(expected), describe(marked),
                describeTags(tags), table.concat(wrong, ","), #statues())
    end)
    -- A Red Key's door made while the player stands in the room: the pairs
    -- follow at once, without leaving (the engine's own MakeRedRoomDoor, as
    -- the Red Key and 축's black ox use it).
    plan.act(function(_, ctx)
        local level = Game():GetLevel()
        local desc = LevelRooms.mainRoom(level)
        for slot = 0, 7 do if expectedSlots()[slot] == "red" then ctx.dig = slot end end
        T().resetEvidence()
        local ok, made = pcall(level.MakeRedRoomDoor, level, desc.SafeGridIndex, ctx.dig)
        ctx.made = ok and made
    end)
    plan.wait(3)
    plan.check("the dug door's pairs stand at once, each 금줄 the room behind its door", function(_, ctx)
        local expected, marked = expectedSlots(), markedSlots()
        local tags, wrong = ropeTags()
        local wanted = expectedTags()
        local door = ctx.dig and Game():GetRoom():GetDoor(ctx.dig)
        local behind = door and Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex)
        local redFlag = RoomDescriptor.FLAG_RED_ROOM or (1 << 10)
        return ctx.made and door ~= nil and T().evidence().resurveys >= 1 and same(marked, expected)
                and same(tags, wanted) and #wrong == 0 and #statues() == count(expected) * 2
                and #ropes() == count(wanted),
            string.format("made=%s door=%s behind type=%s red=%s resurveys=%d expected %s marked %s ropes %s/%s wrong=%s",
                tostring(ctx.made), tostring(door ~= nil), tostring(door and door.TargetRoomType),
                tostring(behind ~= nil and behind.Flags & redFlag ~= 0), T().evidence().resurveys, describe(expected),
                describe(marked), describeTags(tags), describeTags(wanted), table.concat(wrong, ","))
    end)
    plan.note("LOOK", function()
        return "the red 금줄 with the ultra secret room's icon at the wall to dig; after the dig, the dug door's "
            .. "pair (if it leads to a special room) with its room's icon on a red rope"
    end)
end)

-- Common enemies are pushed out of the earth and feared, enemy shots vanish
-- there, and a boss is not kept out.
case("guard", function(plan, id)
    setup(plan, id, true)
    goTo(plan, "the room beside the treasure room", besideType("ROOM_TREASURE"))
    plan.act(function(player, ctx)
        local marker = jangseung().markers()[1]
        ctx.marker = marker
        player.Position = Game():GetRoom():GetCenterPos()
        local at = marker.center + marker.inward * 30
        local npc = Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, at, Vector.Zero, nil):ToNPC()
        npc.HitPoints, npc.MaxHitPoints = 500, 500
        ctx.npc = npc
        local shot = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, 0, 0, marker.center + marker.inward * 120,
            marker.inward * -6, nil)
        ctx.shot = EntityPtr(shot)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            if ctx.npc and ctx.npc:Exists() then ctx.npc:Remove() end
            if ctx.boss and ctx.boss:Exists() then ctx.boss:Remove() end
        end)
    end)
    plan.wait(40)
    plan.check("the enemy was pushed out of the earth and feared", function(_, ctx)
        local m, npc = ctx.marker, ctx.npc
        local offset = npc.Position - m.center
        local out = not T().inside(offset.X, offset.Y, m.inward.X, m.inward.Y, jangseung().data.radius)
        return out and T().evidence().pushed > 0,
            string.format("distance=%.0f pushed=%d fear=%s", offset:Length(), T().evidence().pushed,
                tostring(npc:HasEntityFlags(EntityFlag.FLAG_FEAR)))
    end)
    plan.check("the enemy shot vanished at the boundary", function(_, ctx)
        local shot = ctx.shot.Ref
        return (not shot or not shot:Exists() or shot:IsDead()) and T().evidence().cleared > 0,
            "cleared=" .. T().evidence().cleared
    end)
    plan.act(function(_, ctx)
        local m = ctx.marker
        -- the common enemy goes first: feared, it may wander back in and be
        -- pushed again, which would count against the boss (2026-11-16)
        if ctx.npc and ctx.npc:Exists() then ctx.npc:Remove() end
        local boss = Isaac.Spawn(EntityType.ENTITY_MONSTRO, 0, 0, m.center + m.inward * 30, Vector.Zero, nil):ToNPC()
        boss:AddEntityFlags(EntityFlag.FLAG_FREEZE)
        ctx.boss = boss
        ctx.pushedBefore = T().evidence().pushed
    end)
    plan.wait(20)
    plan.check("a boss is not kept out", function(_, ctx)
        local boss = ctx.boss
        return not boss:HasEntityFlags(EntityFlag.FLAG_FEAR) and T().evidence().pushed == ctx.pushedBefore,
            string.format("fear=%s pushed %d -> %d", tostring(boss:HasEntityFlags(EntityFlag.FLAG_FEAR)), ctx.pushedBefore,
                T().evidence().pushed)
    end)
end)

-- A player inside the half circle takes no damage but self-damage, and a 금줄
-- lies round their feet while they stand there (user request 2026-11-10).
-- Hits come from a frozen enemy far off (a direct hit with it as source) and
-- from real enemy creep under the player, the engine's own damage; the same
-- creep outside the village is the control that it hurts at all.
local function health(player) return player:GetHearts() + player:GetSoulHearts() end

case("shelter", function(plan, id)
    setup(plan, id, true)
    goTo(plan, "the room beside the treasure room", besideType("ROOM_TREASURE"))
    plan.require("a pair to stand in front of, and a spot outside every village", function(_, ctx)
        local markers, radius = jangseung().markers(), jangseung().data.radius
        local center = Game():GetRoom():GetCenterPos()
        ctx.outside = center
        return #markers > 0 and T().sheltered(markers, center.X, center.Y, radius) == nil or nil,
            string.format("markers=%d centre sheltered=%s", #markers,
                tostring(T().sheltered(markers, center.X, center.Y, radius) ~= nil))
    end)
    plan.act(function(player, ctx)
        local m = jangseung().markers()[1]
        -- only the hits' source: in a corner, away from every village and from
        -- the player, and harmless to touch. Near a door it was pushed out of that
        -- village into the player, and with No Hit Delay its contact killed him
        -- (2026-11-16).
        local corner = Game():GetRoom():GetTopLeftPos() + Vector(20, 20)
        local npc = Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, corner, Vector.Zero, nil):ToNPC()
        npc:AddEntityFlags(EntityFlag.FLAG_FREEZE)
        npc.CollisionDamage = 0
        ctx.npc, ctx.creeps = npc, {}
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            if ctx.npc and ctx.npc:Exists() then ctx.npc:Remove() end
            for _, creep in ipairs(ctx.creeps) do if creep:Exists() then creep:Remove() end end
        end)
        player.Position, player.Velocity = m.center + m.inward * 30, Vector.Zero
        ctx.start = health(player)
    end)
    plan.wait(10) -- longer than the 금줄's fade (wardFade, 8 updates)
    plan.check("standing in front of the pair, the 금줄 lies round the player's feet", function(player)
        local ward = T().ward(player)
        return jangseung().shelters(player) and ward ~= nil and ward.alpha == jangseung().data.wardFade,
            string.format("sheltered=%s alpha=%s", tostring(jangseung().shelters(player)), tostring(ward and ward.alpha))
    end)
    plan.act(function(player, ctx)
        T().resetEvidence()
        ctx.before = health(player)
        player:TakeDamage(1, 0, EntityRef(ctx.npc), 30)
    end)
    plan.wait(3)
    plan.check("an enemy's hit is turned away", function(player, ctx)
        local e = T().evidence()
        return health(player) == ctx.before and e.blocked == 1 and player:GetDamageCooldown() == 0,
            string.format("health %d -> %d blocked=%d cooldown=%d", ctx.before, health(player), e.blocked,
                player:GetDamageCooldown())
    end)
    local function creepUnder(player, ctx)
        local creep = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.CREEP_RED, 0, player.Position, Vector.Zero,
            ctx.npc)
        creep = creep and creep:ToEffect()
        if creep and type(creep.SetTimeout) == "function" then creep:SetTimeout(90) end
        ctx.creeps[#ctx.creeps + 1] = creep
    end
    plan.act(function(player, ctx)
        T().resetEvidence()
        ctx.before = health(player)
        creepUnder(player, ctx)
    end)
    plan.wait(30)
    plan.check("enemy creep under the player hurts nothing", function(player, ctx)
        local e = T().evidence()
        return health(player) == ctx.before and e.blocked > 0,
            string.format("health %d -> %d blocked=%d", ctx.before, health(player), e.blocked)
    end)
    plan.act(function(player, ctx)
        for _, creep in ipairs(ctx.creeps) do if creep:Exists() then creep:Remove() end end
        T().resetEvidence()
        ctx.before = health(player)
        player:TakeDamage(1, DamageFlag.DAMAGE_RED_HEARTS, EntityRef(player), 30)
    end)
    plan.wait(3)
    plan.check("self-damage still costs inside", function(player, ctx)
        return health(player) == ctx.before - 1 and T().evidence().blocked == 0,
            string.format("health %d -> %d blocked=%d", ctx.before, health(player), T().evidence().blocked)
    end)
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 120, "the hit's invincibility to end")
    plan.act(function(player, ctx)
        player.Position, player.Velocity = ctx.outside, Vector.Zero
        T().resetEvidence()
        ctx.before = health(player)
        creepUnder(player, ctx)
    end)
    -- the creep goes as soon as it has hurt once: with No Hit Delay (an
    -- installed mod that removes the invincibility after a hit) it hurts every
    -- update and killed Isaac in five (2026-11-16)
    plan.waitUntil(function(player, ctx) return health(player) < ctx.before end, 30, "the creep's first hit outside")
    plan.act(function(_, ctx)
        for _, creep in ipairs(ctx.creeps) do if creep:Exists() then creep:Remove() end end
    end)
    plan.check("outside the village the same creep hurts", function(player, ctx)
        return not jangseung().shelters(player) and health(player) < ctx.before and T().evidence().blocked == 0,
            string.format("sheltered=%s health %d -> %d blocked=%d", tostring(jangseung().shelters(player)), ctx.before,
                health(player), T().evidence().blocked)
    end)
    plan.wait(10)
    plan.check("the 금줄 is gone once the player has left", function(player)
        return T().ward(player) == nil, "ward alpha=" .. tostring(T().ward(player) and T().ward(player).alpha)
    end)
    plan.act(function(player, ctx)
        for _, creep in ipairs(ctx.creeps) do if creep:Exists() then creep:Remove() end end
        local lost = ctx.start - health(player)
        if lost > 0 then player:AddHearts(lost) end
    end)
    plan.note("LOOK", function()
        return "a 금줄 (straw rope with red peppers, charcoal and paper) round Isaac's feet in front of the pair, "
            .. "flashing and swelling when a hit is turned away, fading as he walks off"
    end)
end)

-- With Door Stop the door the player came in by gets a pair in every room;
-- without it that ordinary door stays bare (user request 2026-11-10).
S.add("JANGSEUNG", "door_stop", { conditions = true, synergies = true }, function(plan, id)
    setup(plan, id, true)
    -- an ordinary room with an open door into another ordinary room (the start
    -- room may have none)
    goTo(plan, "an ordinary room beside another", function(level)
        return besideRoom(level, function(desc) return desc.Data.Type == RoomType.ROOM_DEFAULT end)
    end)
    plan.waitUntil(function() return Game():GetRoom():IsClear() and H.ordinaryDoor() ~= nil end, 120, "its doors open")
    H.walkThroughDoor(plan, "into an ordinary room without Door Stop", H.ordinaryDoor, function() T().resetEvidence() end)
    plan.check("without Door Stop the door come in by has no pair", function(_, ctx)
        local marked = markedSlots()
        return ctx.entry ~= nil and marked[ctx.entry] == nil and same(marked, expectedSlots()),
            string.format("entry=%s EnterDoor=%s marked %s", tostring(ctx.entry), tostring(ctx.enterDoor), describe(marked))
    end)
    plan.act(function(player, ctx)
        player:AddTrinket(TrinketType.TRINKET_DOOR_STOP, false)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            local p = Isaac.GetPlayer(0)
            while p and p:TryRemoveTrinket(TrinketType.TRINKET_DOOR_STOP) do end
        end)
    end)
    plan.wait(2)
    H.walkThroughDoor(plan, "back through the door with Door Stop", function(ctx) return ctx.entry end,
        function() T().resetEvidence() end)
    plan.check("with Door Stop the door come in by has a pair", function(_, ctx)
        local expected, marked = expectedSlots(), markedSlots()
        if ctx.entry ~= nil then expected[ctx.entry] = expected[ctx.entry] or "door" end
        local wanted = count(expected)
        local flagged = false
        for _, marker in ipairs(jangseung().markers()) do
            if marker.slot == ctx.entry and marker.entry then flagged = true end
        end
        return ctx.entry ~= nil and flagged and same(marked, expected) and #statues() == wanted * 2
                and #ropes() == count(expectedTags()), -- the door come in by: a rope only if its room has an icon
            string.format("entry=%s EnterDoor=%s expected %s marked %s statues=%d", tostring(ctx.entry),
                tostring(ctx.enterDoor), describe(expected), describe(marked), #statues())
    end)
    plan.check("its earth is stamped too", function()
        local e = T().evidence()
        return e.stamps == #jangseung().markers(), string.format("stamps=%d markers=%d", e.stamps, #jangseung().markers())
    end)
    plan.note("LOOK", function() return "a pair and its earth at the door Isaac came in by" end)
end, { "trinket_door_stop" })

-- Without the item nothing stands anywhere.
case("not_held", function(plan, id)
    setup(plan, id, false)
    goTo(plan, "the room beside the treasure room", besideType("ROOM_TREASURE"))
    plan.check("no statue, no rope, no earth, no guard without the item", function()
        local e = T().evidence()
        return #statues() == 0 and #ropes() == 0 and #jangseung().markers() == 0 and e.stamps == 0,
            string.format("statues=%d ropes=%d markers=%d stamps=%d", #statues(), #ropes(), #jangseung().markers(),
                e.stamps)
    end)
end)

-- Every shared case walks to the room it needs on its own, so they share one
-- floor: between cases the item goes (and with it every pair, rope and
-- earth) and S.resetPlayer proves the player is where the run started. red
-- goes last: it digs a red room into the floor. door_stop is also a synergy
-- case and keeps its own run, so the synergy suite runs only it.
S.last(shared, "red")
S.sequenceBundle("JANGSEUNG", "shared", { conditions = true }, shared, function(plan)
    S.resetPlayer(plan, nil, function()
        return #statues() == 0 and #ropes() == 0 and #jangseung().markers() == 0,
            string.format("statues=%d ropes=%d markers=%d", #statues(), #ropes(), #jangseung().markers())
    end)
end)

return C
