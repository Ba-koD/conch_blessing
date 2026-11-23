local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- `cb test kronos prism_lasers`: Kronos's hidden Angelic Prism splits lasers
-- in every direction, standing or walking. The user reported (2026-11-23)
-- that with a laser weapon the split to the left failed now and then while
-- moving and shooting. The case absorbs a real Angelic Prism, takes
-- Technology and holds each shooting key in turn, first standing still and
-- then with each movement key held as well, so the engine itself walks Isaac
-- while he shoots. Every laser seen is counted for the window it appeared in,
-- split when REPENTOGON's `IsPrismTouched` reports the prism made it, and
-- given to the attack it followed. The oracle: every attack splits into as
-- many beams as the best attack does, and the best one does split. The walks
-- stay off the walls: pressed against a wall, a shot into it never splits,
-- and against the top wall no shot but a downward one does, at any prism size
-- (measured 2026-11-23 with `prism_walk_probe`; the laser starts at head
-- height, inside the top wall). DIAG lines give every attack: where the prism
-- stood from the player, the player's velocity, the room ahead, the main
-- beam's length and the split.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

local SHOOT = {
    { name = "left", action = "ACTION_SHOOTLEFT" },
    { name = "right", action = "ACTION_SHOOTRIGHT" },
    { name = "up", action = "ACTION_SHOOTUP" },
    { name = "down", action = "ACTION_SHOOTDOWN" },
}
-- Each walk starts on the far side of the room's centre from where it heads,
-- off the centre lines the doors sit on, and stops short of the far wall
-- (Isaac covers about 8.8 units an update at speed 1).
local MOVE = {
    { name = "left", action = "ACTION_LEFT", start = { 200, 60 }, hold = 34 },
    { name = "right", action = "ACTION_RIGHT", start = { -200, 60 }, hold = 34 },
    { name = "up", action = "ACTION_UP", start = { 120, 100 }, hold = 23 },
    { name = "down", action = "ACTION_DOWN", start = { 120, -100 }, hold = 23 },
}
local HOLD = 50     -- updates the keys of a standing window are held
local SETTLE = 20   -- updates after letting go, for the last lasers to show

local WINDOWS = {}
for _, shoot in ipairs(SHOOT) do
    WINDOWS[#WINDOWS + 1] = { name = "shoot " .. shoot.name .. ", stand", shoot = shoot }
end
for _, shoot in ipairs(SHOOT) do
    for _, move in ipairs(MOVE) do
        WINDOWS[#WINDOWS + 1] = { name = "shoot " .. shoot.name .. ", walk " .. move.name, shoot = shoot, move = move }
    end
end

-- { player, window, holding, readable, tally = { [name] = { attacks,
-- lasers = { [number] = touched }, lag, start } } } while the case runs.
local watch = nil

local function tallyFor(name)
    watch.tally[name] = watch.tally[name] or { attacks = 0, lasers = {}, lag = 0, start = {}, born = {}, trace = {},
        length = {} }
    return watch.tally[name]
end

local function prismOf(player)
    return H.familiarAnchors(player, "__kronosAngelicPrism")[1]
end

local AIM = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }

-- How far the player can shoot along the unit vector (ax, ay) before the
-- room's floor ends (a wall, a rock), in steps of 5 units up to 300.
local function room_ahead(player, ax, ay)
    local room = Game():GetRoom()
    for distance = 5, 300, 5 do
        local spot = player.Position + Vector(ax * distance, ay * distance)
        if not room:IsPositionInRoom(spot, 0)
            or room:GetGridCollisionAtPos(spot) ~= GridCollisionClass.COLLISION_NONE then
            return distance - 5
        end
    end
    return 300
end

-- Each laser gets its own number in its data: an address freed by one laser
-- may be reused by the next, so GetPtrHash alone would merge them.
local serial = 0
local function seeLaser(laser)
    if not (watch and watch.window) or not laser then return end
    local data = laser:GetData()
    if not data.__cbPrismProbe then
        serial = serial + 1
        data.__cbPrismProbe = serial
        data.__cbPrismProbeWindow = watch.window.name
        local prism = prismOf(watch.player)
        data.__cbPrismProbeStart = prism and laser.Position:Distance(prism.Position) or -1
        data.__cbPrismProbeBorn = Game():GetFrameCount()
    end
    local tally = tallyFor(data.__cbPrismProbeWindow)
    local id = data.__cbPrismProbe
    local readable = type(laser.IsPrismTouched) == "function"
    watch.readable = watch.readable or readable
    local touched = readable and laser:IsPrismTouched() == true
    tally.lasers[id] = tally.lasers[id] or touched
    tally.start[id] = data.__cbPrismProbeStart
    tally.born[id] = data.__cbPrismProbeBorn
    if type(laser.GetEndPoint) == "function" then
        local ok, finish = pcall(laser.GetEndPoint, laser)
        if ok and finish then
            tally.length[id] = math.max(tally.length[id] or 0, finish:Distance(laser.Position))
        end
    end
end

if ModCallbacks.MC_POST_LASER_INIT then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_LASER_INIT, function(_, laser) seeLaser(laser) end)
end
if ModCallbacks.MC_POST_LASER_UPDATE then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser) seeLaser(laser) end)
end
if ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED, function(_, fireDirection, _, owner)
        if not (watch and watch.window and watch.holding) or not owner then return end
        if GetPtrHash(owner) ~= GetPtrHash(watch.player) then return end
        local tally = tallyFor(watch.window.name)
        tally.attacks = tally.attacks + 1
        local prism = prismOf(watch.player)
        local player = watch.player
        if prism then tally.lag = math.max(tally.lag, prism.Position:Distance(player.Position)) end
        -- The way the attack went: the held shooting key, else the engine's
        -- own fire direction (Marked aims at its target).
        local ax, ay = 1, 0
        local shoot = watch.window.shoot
        if shoot then
            ax, ay = AIM[shoot.name][1], AIM[shoot.name][2]
        elseif fireDirection and fireDirection:Length() > 0.01 then
            local unit = fireDirection:Normalized()
            ax, ay = unit.X, unit.Y
        end
        tally.trace[#tally.trace + 1] = { frame = Game():GetFrameCount(),
            dx = prism and prism.Position.X - player.Position.X or 0, dy = prism and prism.Position.Y - player.Position.Y or 0,
            vx = player.Velocity.X, vy = player.Velocity.Y, pv = prism and prism.Velocity:Length() or -1,
            ahead = room_ahead(player, ax, ay), angle = (math.deg(math.atan(ay, ax)) + 360) % 360,
            knife = (function()
                -- How far the player's own knife stands from the prism as the
                -- attack starts (Mom's Knife is held in front of Isaac).
                local best = nil
                for _, knife in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE)) do
                    local mine = knife.SpawnerEntity and GetPtrHash(knife.SpawnerEntity) == GetPtrHash(player)
                    if mine and prism then
                        local distance = knife.Position:Distance(prism.Position)
                        best = best and math.min(best, distance) or distance
                    end
                end
                return best
            end)() }
    end)
end
if ModCallbacks.MC_INPUT_ACTION then
    ConchBlessing:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
        if not (watch and watch.holding and watch.window) or not entity then return end
        if GetPtrHash(entity) ~= GetPtrHash(watch.player) then return end
        local window = watch.window
        if not (window.shoot and action == ButtonAction[window.shoot.action])
            and not (window.move and action == ButtonAction[window.move.action]) then
            return
        end
        if hook == InputHook.GET_ACTION_VALUE then return 1 end
        return true
    end)
end

-- A window's attacks, lasers, lasers the prism made, the farthest the prism
-- stood from the player at an attack, and the farthest an unsplit laser
-- began from the prism.
local function counts(name)
    local tally = watch and watch.tally[name]
    local lasers, split, farthest = 0, 0, 0
    for id, touched in pairs(tally and tally.lasers or {}) do
        lasers = lasers + 1
        if touched then
            split = split + 1
        else
            farthest = math.max(farthest, tally.start[id] or 0)
        end
    end
    return tally and tally.attacks or 0, lasers, split, tally and tally.lag or 0, farthest
end

-- Each attack of a window with the room ahead of it and the prism's lasers
-- made from then until the next attack.
local function splits(name)
    local tally = watch and watch.tally[name]
    local out = {}
    if not tally then return out end
    local list = tally.trace
    for k, attack in ipairs(list) do
        -- The last attack keeps only what came within 3 updates of it: Marked
        -- goes on firing after the window ends.
        local untilFrame = list[k + 1] and list[k + 1].frame or attack.frame + 3
        local split, length = 0, 0
        for id, touched in pairs(tally.lasers) do
            local born = tally.born[id] or -1
            if born >= attack.frame and born < untilFrame then
                if touched then split = split + 1 else length = math.max(length, tally.length[id] or 0) end
            end
        end
        out[k] = { split = split, ahead = attack.ahead, length = length, angle = attack.angle }
    end
    return out
end

-- Each attack of a window: when it came (updates after the first), where the
-- prism stood from the player, the player's velocity, and the prism's lasers
-- made from then until the next attack.
local function trace(name)
    local tally = watch and watch.tally[name]
    if not tally then return "" end
    local list, parts = tally.trace, {}
    for k, attack in ipairs(list) do
        -- The last attack keeps only what came within 3 updates of it: Marked
        -- goes on firing after the window ends.
        local untilFrame = list[k + 1] and list[k + 1].frame or attack.frame + 3
        local split, length = 0, 0
        for id, touched in pairs(tally.lasers) do
            local born = tally.born[id] or -1
            if born >= attack.frame and born < untilFrame then
                if touched then split = split + 1 else length = math.max(length, tally.length[id] or 0) end
            end
        end
        parts[#parts + 1] = string.format("+%d prism(%.1f,%.1f) v(%.1f,%.1f) wall%d beam%.0f split%d",
            attack.frame - list[1].frame, attack.dx, attack.dy, attack.vx, attack.vy, attack.ahead, length, split)
    end
    return table.concat(parts, " | ")
end

S.add("KRONOS", "prism_lasers", { synergies = true, conditions = true }, function(plan, kronosId)
    plan.require("REPENTOGON laser and weapon-trigger callbacks available", function()
        return ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED and ModCallbacks.MC_POST_LASER_INIT
            and ModCallbacks.MC_POST_LASER_UPDATE and true or nil, "missing laser/weapon callbacks"
    end)
    plan.act(function(player, ctx)
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function() watch = nil end
        player:AddCollectible(kronosId, 0, false)
        player:AddCollectible(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, 0, false)
    end)
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, true) == 0
            and prismOf(player) ~= nil, "prism not absorbed yet"
    end, 120, "Kronos absorbs the Angelic Prism and keeps a hidden prism")
    plan.act(function(player, ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY, 0, false)
        player.Position, player.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
        ctx.roomIndex = Game():GetLevel():GetCurrentRoomIndex()
        watch = { player = player, tally = {} }
    end)
    plan.wait(4)
    plan.note("hidden prism", function(player)
        local prism = prismOf(player)
        return string.format("prism size %.1f (player size %.1f, scale %s), %.1f from the player",
            prism and prism.Size or -1, player.Size, tostring(ConchBlessing.kronos.data.angelicPrismSizeScale),
            prism and prism.Position:Distance(player.Position) or -1)
    end)
    for _, window in ipairs(WINDOWS) do
        plan.act(function(player, ctx)
            local start = window.move and window.move.start or { 0, 0 }
            ctx.spot = Game():GetRoom():GetCenterPos() + Vector(start[1], start[2])
            player.Position, player.Velocity = ctx.spot, Vector.Zero
        end)
        plan.wait(3)
        plan.act(function(_, ctx)
            watch.window, watch.holding = window, true
            ctx.holdUntil = Game():GetFrameCount() + (window.move and window.move.hold or HOLD)
        end)
        plan.waitUntil(function(player, ctx)
            if not window.move then player.Position, player.Velocity = ctx.spot, Vector.Zero end
            return Game():GetFrameCount() >= ctx.holdUntil, window.name
        end, HOLD + 30, "hold: " .. window.name)
        plan.act(function() watch.holding = false end)
        plan.waitUntil(function()
            return #Isaac.FindByType(EntityType.ENTITY_LASER) == 0, "lasers still out"
        end, SETTLE + 30, "the lasers are gone: " .. window.name)
        plan.require("still in the starting room after: " .. window.name, function(_, ctx)
            local index = Game():GetLevel():GetCurrentRoomIndex()
            return index == ctx.roomIndex, "room " .. index .. ", started in " .. ctx.roomIndex
        end)
        plan.note(window.name .. " attacks", function() return trace(window.name) end)
        plan.note(window.name, function()
            local attacks, lasers, split, lag, farthest = counts(window.name)
            return string.format("attacks %d, lasers %d, made by the prism %d; prism up to %.1f from the player"
                .. " at an attack; unsplit lasers began up to %.1f from the prism", attacks, lasers, split, lag, farthest)
        end)
    end
    plan.act(function() watch.window = nil end)
    -- Read on the lasers themselves: the class table is not a global.
    plan.require("the lasers report whether the prism made them (EntityLaser:IsPrismTouched)", function()
        return watch.readable == true, "no laser had IsPrismTouched"
    end)
    plan.check("every window shot several attacks, none against a wall", function()
        local parts, ok = {}, true
        for _, window in ipairs(WINDOWS) do
            local list, near = splits(window.name), 0
            for _, attack in ipairs(list) do
                if attack.ahead <= 25 then near = near + 1 end
            end
            parts[#parts + 1] = string.format("%s=%d", window.name, #list)
            ok = ok and #list >= 2 and near == 0
        end
        return ok, table.concat(parts, "; ")
    end)
    plan.check("every attack splits as much as the best one, standing and walking, every way", function()
        local best, short = 0, {}
        for _, window in ipairs(WINDOWS) do
            for _, attack in ipairs(splits(window.name)) do best = math.max(best, attack.split) end
        end
        for _, window in ipairs(WINDOWS) do
            for k, attack in ipairs(splits(window.name)) do
                if attack.split < best then
                    short[#short + 1] = string.format("%s #%d split %d (room ahead %d, beam %.0f)", window.name, k,
                        attack.split, attack.ahead, attack.length)
                end
            end
        end
        return best > 0 and #short == 0, string.format("best %d beams; short: [%s]", best, table.concat(short, "; "))
    end)
end)

-- `cb test kronos prism_walk_probe` (a measurement, run by name only): many
-- attacks while walking across the middle of the room, away from the walls,
-- in each direction, shooting the way Isaac walks and the opposite way. DIAG
-- lines give every attack; nothing here is a PASS.
local PROBE = {}
for _, pair in ipairs({
    { "left", "left", { 220, 60 }, 85 }, { "right", "left", { 220, 60 }, 85 },
    { "right", "right", { -220, 60 }, 85 }, { "left", "right", { -220, 60 }, 85 },
    { "up", "up", { 120, 110 }, 45 }, { "down", "up", { 120, 110 }, 45 },
    { "down", "down", { 120, -110 }, 45 }, { "up", "down", { 120, -110 }, 45 },
}) do
    local shoot, move
    for _, entry in ipairs(SHOOT) do if entry.name == pair[1] then shoot = entry end end
    for _, entry in ipairs(MOVE) do if entry.name == pair[2] then move = entry end end
    for pass = 1, 3 do
        PROBE[#PROBE + 1] = { name = string.format("shoot %s, walk %s #%d", pair[1], pair[2], pass), shoot = shoot,
            move = { name = move.name, action = move.action, start = pair[3] }, hold = pair[4] }
    end
end

S.add("KRONOS", "prism_walk_probe", {}, function(plan, kronosId)
    plan.act(function(player, ctx)
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function() watch = nil end
        player:AddCollectible(kronosId, 0, false)
        player:AddCollectible(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, 0, false)
    end)
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, true) == 0
            and prismOf(player) ~= nil, "prism not absorbed yet"
    end, 120, "Kronos absorbs the Angelic Prism and keeps a hidden prism")
    plan.act(function(player, ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY, 0, false)
        ctx.roomIndex = Game():GetLevel():GetCurrentRoomIndex()
        watch = { player = player, tally = {} }
    end)
    plan.note("settings", function(player)
        return string.format("scale %s, player speed %.2f", tostring(ConchBlessing.kronos.data.angelicPrismSizeScale),
            player.MoveSpeed)
    end)
    for _, window in ipairs(PROBE) do
        plan.act(function(player, ctx)
            ctx.spot = Game():GetRoom():GetCenterPos() + Vector(window.move.start[1], window.move.start[2])
            player.Position, player.Velocity = ctx.spot, Vector.Zero
        end)
        plan.wait(3)
        plan.act(function(_, ctx)
            watch.window, watch.holding = window, true
            ctx.holdUntil = Game():GetFrameCount() + window.hold
        end)
        plan.waitUntil(function(_, ctx)
            return Game():GetFrameCount() >= ctx.holdUntil, window.name
        end, window.hold + 30, "hold: " .. window.name)
        plan.act(function() watch.holding = false end)
        plan.waitUntil(function()
            return #Isaac.FindByType(EntityType.ENTITY_LASER) == 0, "lasers still out"
        end, SETTLE + 30, "the lasers are gone: " .. window.name)
        plan.require("still in the starting room after: " .. window.name, function(_, ctx)
            return Game():GetLevel():GetCurrentRoomIndex() == ctx.roomIndex, "left the room"
        end)
    end
    plan.note("totals", function()
        local attacks, split, missed = 0, 0, {}
        for _, window in ipairs(PROBE) do
            local a, _, s = counts(window.name)
            attacks, split = attacks + a, split + s
            if s < 4 * a then missed[#missed + 1] = string.format("%s %d/%d", window.name, s, 4 * a) end
        end
        return string.format("attacks %d, split beams %d of %d; short: [%s]", attacks, split, 4 * attacks,
            table.concat(missed, "; "))
    end)
    for _, window in ipairs(PROBE) do
        plan.note(window.name, function() return trace(window.name) end)
    end
end)
S.rows[#S.rows].manual = true

-- `cb test kronos prism_marked`: every angle, not only the four shooting keys
-- (user request 2026-11-24). Isaac holds Marked, which fires on its own at a
-- target, with a fire rate this case raises (MaxFireDelay 2, an attack every
-- third update); the case sweeps the target round him, a full turn standing in
-- the room's centre and a full turn during each short walk (off the walls, as
-- in prism_lasers). Every attack must split as much as the best one; DIAG
-- lines give each 45-degree sector and every miss with its angle.
local MARKED_RADIUS = 100
local MARKED = {
    { name = "Marked, stand", hold = 360 },
}
for _, move in ipairs(MOVE) do
    MARKED[#MARKED + 1] = { name = "Marked, walk " .. move.name, move = move, hold = move.hold }
end

local fast = nil -- GetPtrHash of the player whose fire rate the case raises
local fastDelay = 2 -- the MaxFireDelay it gets (2: an attack every third update)
if ModCallbacks.MC_EVALUATE_CACHE and ConchBlessing.AddPriorityCallback then
    local late = (CallbackPriority and CallbackPriority.LATE) or 100
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, late, function(_, player, flag)
        if fast and flag == CacheFlag.CACHE_FIREDELAY and GetPtrHash(player) == fast then
            player.MaxFireDelay = fastDelay
        end
    end)
end

-- Marked's target on the floor: the engine's own answer, else the target
-- effect this player put down, else the only one.
local function markedTarget(player)
    if type(player.GetMarkedTarget) == "function" then
        local ok, target = pcall(player.GetMarkedTarget, player)
        if ok and target and target:Exists() then return target end
    end
    local found = nil
    local list = Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.TARGET)
    for _, effect in ipairs(list) do
        local spawner = effect.SpawnerEntity
        if spawner and GetPtrHash(spawner) == GetPtrHash(player) then found = effect end
    end
    if not found and #list == 1 then found = list[1] end
    return found
end

local function setFast(player, on, delay)
    fast = on and GetPtrHash(player) or nil
    fastDelay = delay or 2
    player:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
    player:EvaluateItems()
end

S.add("KRONOS", "prism_marked", { synergies = true, conditions = true }, function(plan, kronosId)
    plan.require("REPENTOGON laser and weapon-trigger callbacks available", function()
        return ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED and ModCallbacks.MC_POST_LASER_INIT
            and ModCallbacks.MC_POST_LASER_UPDATE and true or nil, "missing laser/weapon callbacks"
    end)
    plan.act(function(player, ctx)
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            watch = nil
            if fast then setFast(player, false) end
        end
        player:AddCollectible(kronosId, 0, false)
        player:AddCollectible(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, 0, false)
    end)
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, true) == 0
            and prismOf(player) ~= nil, "prism not absorbed yet"
    end, 120, "Kronos absorbs the Angelic Prism and keeps a hidden prism")
    plan.act(function(player, ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY, 0, false)
        player:AddCollectible(CollectibleType.COLLECTIBLE_MARKED, 0, false)
        setFast(player, true)
        player.Position, player.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
        ctx.roomIndex = Game():GetLevel():GetCurrentRoomIndex()
        -- Marked puts its target down once a shooting key is pressed.
        watch = { player = player, tally = {}, holding = true,
            window = { name = "Marked, first press", shoot = SHOOT[2] } }
    end)
    plan.waitUntil(function(player)
        return markedTarget(player) ~= nil, "no Marked target yet"
    end, 60, "Marked puts its target down")
    plan.act(function() watch = nil end)
    plan.wait(10)
    plan.check("the fire rate is raised (MaxFireDelay 2)", function(player)
        return math.abs(player.MaxFireDelay - 2) < 0.01, string.format("MaxFireDelay %.2f", player.MaxFireDelay)
    end)
    plan.act(function(player) watch = { player = player, tally = {} } end)
    for _, window in ipairs(MARKED) do
        plan.act(function(player, ctx)
            local start = window.move and window.move.start or { 0, 0 }
            ctx.spot = Game():GetRoom():GetCenterPos() + Vector(start[1], start[2])
            player.Position, player.Velocity = ctx.spot, Vector.Zero
        end)
        plan.wait(3)
        plan.act(function(_, ctx)
            watch.window, watch.holding = window, true
            ctx.from = Game():GetFrameCount()
            ctx.holdUntil = ctx.from + window.hold
        end)
        plan.waitUntil(function(player, ctx)
            if not window.move then player.Position, player.Velocity = ctx.spot, Vector.Zero end
            local turn = (Game():GetFrameCount() - ctx.from) / window.hold * 2 * math.pi
            local target = markedTarget(player)
            if target then
                target.Position = player.Position + Vector(math.cos(turn), math.sin(turn)) * MARKED_RADIUS
                target.Velocity = Vector.Zero
            end
            return Game():GetFrameCount() >= ctx.holdUntil, window.name
        end, window.hold + 30, "sweep: " .. window.name)
        -- Marked never stops firing: stop counting attacks, give the last
        -- one's beams 3 updates, then stop watching lasers.
        plan.act(function() watch.holding = false end)
        plan.wait(3)
        plan.act(function() watch.window = nil end)
        plan.require("still in the starting room after: " .. window.name, function(_, ctx)
            return Game():GetLevel():GetCurrentRoomIndex() == ctx.roomIndex, "left the room"
        end)
        plan.note(window.name, function()
            local list, sectors = splits(window.name), {}
            for _, attack in ipairs(list) do
                local sector = math.floor(attack.angle / 45) % 8
                sectors[sector] = sectors[sector] or { 0, 0 }
                sectors[sector][1] = sectors[sector][1] + 1
                if attack.split >= 4 then sectors[sector][2] = sectors[sector][2] + 1 end
            end
            local parts = {}
            for sector = 0, 7 do
                local entry = sectors[sector] or { 0, 0 }
                parts[#parts + 1] = string.format("%d-%d: %d/%d", sector * 45, sector * 45 + 45, entry[2], entry[1])
            end
            return string.format("attacks %d; split in four per sector (degrees, 0 = right, 90 = down): %s", #list,
                table.concat(parts, ", "))
        end)
    end
    plan.act(function() watch.window = nil end)
    plan.require("the lasers report whether the prism made them (EntityLaser:IsPrismTouched)", function()
        return watch.readable == true, "no laser had IsPrismTouched"
    end)
    plan.check("the attacks cover every angle", function()
        local covered = {}
        for _, window in ipairs(MARKED) do
            for _, attack in ipairs(splits(window.name)) do covered[math.floor(attack.angle / 10) % 36] = true end
        end
        local missing = {}
        for slice = 0, 35 do
            if not covered[slice] then missing[#missing + 1] = tostring(slice * 10) end
        end
        return #missing == 0, "10-degree slices with no attack: [" .. table.concat(missing, " ") .. "]"
    end)
    plan.check("every attack splits as much as most do, at every angle, standing and walking", function()
        -- The usual number of beams per attack: with an attack every third
        -- update, a neighbour's beams may land in one attack's count, so the
        -- largest count is not the reference.
        local seen, best, short, total = {}, 0, {}, 0
        for _, window in ipairs(MARKED) do
            for _, attack in ipairs(splits(window.name)) do seen[attack.split] = (seen[attack.split] or 0) + 1 end
        end
        for count, n in pairs(seen) do
            if n > (seen[best] or 0) then best = count end
        end
        for _, window in ipairs(MARKED) do
            for _, attack in ipairs(splits(window.name)) do
                total = total + 1
                if attack.split < best then
                    short[#short + 1] = string.format("%s %.0f deg split %d (room ahead %d)", window.name, attack.angle,
                        attack.split, attack.ahead)
                end
            end
        end
        return best > 0 and #short == 0, string.format("usual %d beams over %d attacks; short: [%s]", best, total,
            table.concat(short, "; "))
    end)
    plan.act(function(player)
        watch = nil
        setFast(player, false)
    end)
    plan.wait(1)
end)

-- Tears, knives and bombs are counted the same way as lasers: a prism split
-- marks what it makes as prism-touched on each of them (REPENTOGON).
for _, name in ipairs({ "MC_POST_TEAR_INIT", "MC_POST_TEAR_UPDATE", "MC_POST_KNIFE_INIT", "MC_POST_KNIFE_UPDATE",
    "MC_POST_BOMB_INIT", "MC_POST_BOMB_UPDATE" }) do
    if ModCallbacks[name] then
        ConchBlessing:AddCallback(ModCallbacks[name], function(_, entity) seeLaser(entity) end)
    end
end

-- `cb test kronos prism_weapons` (a measurement, run by name only; user
-- request 2026-11-24): the Marked sweep of prism_marked for each kind of
-- attack the prism splits, one after another in one run: plain tears,
-- Technology, Technology 2, Brimstone, Tech X, Mom's Knife and Dr. Fetus.
-- Each gets a full turn standing in the centre and a full turn while walking
-- left and while walking right. DIAG lines give, per weapon, the attacks, how
-- many beams or tears the prism made per attack and every attack that got
-- fewer than most did, with its angle. Nothing here is a PASS.
-- `cb test kronos prism_fast` does the same at tears 120 (MaxFireDelay -0.75;
-- user request 2026-11-24): plain tears, Soy Milk and Technology.
local WEAPONS = {
    { name = "tears" },
    { name = "Technology", items = { "COLLECTIBLE_TECHNOLOGY" } },
    { name = "Technology 2", items = { "COLLECTIBLE_TECHNOLOGY_2" } },
    { name = "Brimstone", items = { "COLLECTIBLE_BRIMSTONE" } },
    { name = "Tech X", items = { "COLLECTIBLE_TECH_X" } },
    { name = "Mom's Knife", items = { "COLLECTIBLE_MOMS_KNIFE" } },
    { name = "Dr. Fetus", items = { "COLLECTIBLE_DR_FETUS" } },
}
-- Tears 120: 30 / (MaxFireDelay + 1) = 120.
local FAST_DELAY = 30 / 120 - 1
local FAST_WEAPONS = {
    { name = "tears at 120", delay = FAST_DELAY },
    { name = "Soy Milk at 120", items = { "COLLECTIBLE_SOY_MILK" }, delay = FAST_DELAY },
    { name = "Technology at 120", items = { "COLLECTIBLE_TECHNOLOGY" }, delay = FAST_DELAY },
}

local function weaponWindows(weapon)
    local list = { { name = weapon.name .. ", stand", hold = 360 } }
    for _, move in ipairs(MOVE) do
        if move.name == "left" or move.name == "right" then
            list[#list + 1] = { name = weapon.name .. ", walk " .. move.name, move = move, hold = move.hold }
        end
    end
    return list
end

-- One weapon's line: its attacks, what the prism made for most of them, how
-- many got fewer (with their angles) and the average made per attack.
local function weaponNote(weapon)
    local seen, total, attacks, made = {}, 0, {}, 0
    for _, window in ipairs(weaponWindows(weapon)) do
        for _, attack in ipairs(splits(window.name)) do
            seen[attack.split] = (seen[attack.split] or 0) + 1
            total = total + 1
            made = made + attack.split
            attacks[#attacks + 1] = { window = window.name, attack = attack }
        end
    end
    local usual = 0
    for count, n in pairs(seen) do
        if n > (seen[usual] or 0) then usual = count end
    end
    local counts, short, missed = {}, {}, 0
    for count, n in pairs(seen) do counts[#counts + 1] = string.format("%dx%d", count, n) end
    table.sort(counts)
    for _, entry in ipairs(attacks) do
        if entry.attack.split < usual then
            missed = missed + 1
            if #short < 24 then
                short[#short + 1] = string.format("%s %.0f deg split %d", entry.window, entry.attack.angle,
                    entry.attack.split)
            end
        end
    end
    -- Whole entities too, for weapons whose trigger fires every update while
    -- charging (Brimstone): what the weapon made itself and what the prism made.
    local main, byPrism, born, held = 0, 0, {}, {}
    for _, window in ipairs(weaponWindows(weapon)) do
        local tally = watch and watch.tally[window.name]
        for id, touched in pairs(tally and tally.lasers or {}) do
            if touched then
                byPrism = byPrism + 1
                if (tally.start[id] or -1) >= 0 then born[#born + 1] = tally.start[id] end
            else
                main = main + 1
            end
        end
        for _, attack in ipairs(tally and tally.trace or {}) do
            if attack.knife then held[#held + 1] = attack.knife end
        end
    end
    -- Where the prism's own pieces first appeared, and where a held knife
    -- stood, measured from the prism: min / median / max.
    local function spread(list)
        if #list == 0 then return "none" end
        table.sort(list)
        return string.format("%.0f / %.0f / %.0f", list[1], list[math.floor((#list + 1) / 2)], list[#list])
    end
    return string.format("attacks %d, usual %d made per attack, fewer %d, average %.2f; made per attack [%s];"
        .. " entities: own %d, by the prism %d; prism pieces appeared %s from the prism; knife at an attack %s"
        .. " from the prism; fewer: [%s]", total, usual, missed, total > 0 and made / total or 0,
        table.concat(counts, " "), main, byPrism, spread(born), spread(held), table.concat(short, "; "))
end

-- Every attack of `weapon` got at least as much from the prism as most did,
-- and most got 4: what a check case requires.
local function weaponSplitsFully(weapon)
    local seen, short = {}, 0
    local list = {}
    for _, window in ipairs(weaponWindows(weapon)) do
        for _, attack in ipairs(splits(window.name)) do
            seen[attack.split] = (seen[attack.split] or 0) + 1
            list[#list + 1] = attack
        end
    end
    local usual = 0
    for count, n in pairs(seen) do
        if n > (seen[usual] or 0) then usual = count end
    end
    for _, attack in ipairs(list) do
        if attack.split < usual then short = short + 1 end
    end
    return #list >= 6 and usual >= 4 and short == 0
end

local function addWeaponProbe(name, weapons, opts)
    opts = opts or {}
    S.add("KRONOS", name, opts.groups or {}, function(plan, kronosId)
        plan.act(function(player, ctx)
            ctx.cleanupFns = ctx.cleanupFns or {}
            ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
                watch = nil
                if fast then setFast(player, false) end
            end
            player:AddCollectible(kronosId, 0, false)
            player:AddCollectible(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, 0, false)
        end)
        plan.waitUntil(function(player)
            return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, true) == 0
                and prismOf(player) ~= nil, "prism not absorbed yet"
        end, 120, "Kronos absorbs the Angelic Prism and keeps a hidden prism")
        plan.act(function(player, ctx)
            player:AddCollectible(CollectibleType.COLLECTIBLE_MARKED, 0, false)
            setFast(player, true)
            player.Position, player.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
            ctx.roomIndex = Game():GetLevel():GetCurrentRoomIndex()
            watch = { player = player, tally = {}, holding = true,
                window = { name = "Marked, first press", shoot = SHOOT[2] } }
        end)
        plan.waitUntil(function(player)
            return markedTarget(player) ~= nil, "no Marked target yet"
        end, 60, "Marked puts its target down")
        plan.act(function(player) watch = { player = player, tally = {} } end)
        local previous = {}
        for _, weapon in ipairs(weapons) do
            local before = previous
            plan.act(function(player)
                for _, item in ipairs(before) do player:RemoveCollectible(CollectibleType[item]) end
                for _, item in ipairs(weapon.items or {}) do player:AddCollectible(CollectibleType[item], 0, false) end
                setFast(player, true, weapon.delay)
            end)
            previous = weapon.items or {}
            plan.wait(15)
            plan.note(weapon.name .. " fire rate", function(player)
                return string.format("MaxFireDelay %.2f, tears %.1f", player.MaxFireDelay, 30 / (player.MaxFireDelay + 1))
            end)
            for _, window in ipairs(weaponWindows(weapon)) do
                plan.act(function(player, ctx)
                    local start = window.move and window.move.start or { 0, 0 }
                    ctx.spot = Game():GetRoom():GetCenterPos() + Vector(start[1], start[2])
                    player.Position, player.Velocity = ctx.spot, Vector.Zero
                end)
                plan.wait(3)
                plan.act(function(_, ctx)
                    watch.window, watch.holding = window, true
                    ctx.from = Game():GetFrameCount()
                    ctx.holdUntil = ctx.from + window.hold
                end)
                plan.waitUntil(function(player, ctx)
                    if not window.move then player.Position, player.Velocity = ctx.spot, Vector.Zero end
                    local turn = (Game():GetFrameCount() - ctx.from) / window.hold * 2 * math.pi
                    local target = markedTarget(player)
                    if target then
                        target.Position = player.Position + Vector(math.cos(turn), math.sin(turn)) * MARKED_RADIUS
                        target.Velocity = Vector.Zero
                    end
                    return Game():GetFrameCount() >= ctx.holdUntil, window.name
                end, window.hold + 30, "sweep: " .. window.name)
                plan.act(function() watch.holding = false end)
                plan.wait(3)
                plan.act(function() watch.window = nil end)
                plan.require("still in the starting room after: " .. window.name, function(_, ctx)
                    return Game():GetLevel():GetCurrentRoomIndex() == ctx.roomIndex, "left the room"
                end)
            end
            plan.note(weapon.name, function() return weaponNote(weapon) end)
            if opts.check then
                plan.check(weapon.name .. ": every attack splits into 4 at every angle, standing and walking",
                    function() return weaponSplitsFully(weapon), weaponNote(weapon) end)
            end
        end
        plan.act(function(player)
            watch = nil
            setFast(player, false)
        end)
        plan.wait(1)
    end)
    if not opts.check then S.rows[#S.rows].manual = true end
end

addWeaponProbe("prism_weapons", WEAPONS)
addWeaponProbe("prism_fast", FAST_WEAPONS)
addWeaponProbe("prism_brimstone", { { name = "Brimstone", items = { "COLLECTIBLE_BRIMSTONE" } } })
-- `cb test kronos prism_knife` (in the suite): thrown knives split on the
-- knife prism Kronos keeps ahead of the knife (user request 2026-11-24).
addWeaponProbe("prism_knife", { { name = "Mom's Knife", items = { "COLLECTIBLE_MOMS_KNIFE" } } },
    { groups = { synergies = true, conditions = true }, check = true })

-- `cb test kronos prism_vanilla_knife` (a measurement, run by name only): the
-- vanilla control for Mom's Knife. No Kronos: the real Angelic Prism orbits
-- Isaac as the item does, Marked throws the knife at a target swept round him
-- for three full turns, and a Technology run follows as the control that the
-- real prism splits what it touches. DIAG lines give what the prism made.
local VANILLA = {
    { name = "vanilla Mom's Knife", items = { "COLLECTIBLE_MOMS_KNIFE" } },
    { name = "vanilla Technology", items = { "COLLECTIBLE_TECHNOLOGY" } },
}
S.add("KRONOS", "prism_vanilla_knife", {}, function(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            watch = nil
            if fast then setFast(player, false) end
        end
        player:AddCollectible(CollectibleType.COLLECTIBLE_ANGELIC_PRISM, 0, false)
        player:AddCollectible(CollectibleType.COLLECTIBLE_MARKED, 0, false)
        setFast(player, true)
        player.Position, player.Velocity = Game():GetRoom():GetCenterPos(), Vector.Zero
        watch = { player = player, tally = {}, holding = true,
            window = { name = "Marked, first press", shoot = SHOOT[2] } }
    end)
    plan.waitUntil(function(player)
        return markedTarget(player) ~= nil, "no Marked target yet"
    end, 60, "Marked puts its target down")
    plan.act(function(player) watch = { player = player, tally = {} } end)
    local previous = {}
    for _, weapon in ipairs(VANILLA) do
        local before = previous
        plan.act(function(player)
            for _, item in ipairs(before) do player:RemoveCollectible(CollectibleType[item]) end
            for _, item in ipairs(weapon.items) do player:AddCollectible(CollectibleType[item], 0, false) end
            setFast(player, true)
        end)
        previous = weapon.items
        plan.wait(15)
        local window = { name = weapon.name, hold = 540 }
        plan.act(function(player, ctx)
            ctx.spot = Game():GetRoom():GetCenterPos()
            player.Position, player.Velocity = ctx.spot, Vector.Zero
            watch.window, watch.holding = window, true
            ctx.from = Game():GetFrameCount()
            ctx.holdUntil = ctx.from + window.hold
        end)
        plan.waitUntil(function(player, ctx)
            player.Position, player.Velocity = ctx.spot, Vector.Zero
            local turn = (Game():GetFrameCount() - ctx.from) / 180 * 2 * math.pi
            local target = markedTarget(player)
            if target then
                target.Position = player.Position + Vector(math.cos(turn), math.sin(turn)) * MARKED_RADIUS
                target.Velocity = Vector.Zero
            end
            return Game():GetFrameCount() >= ctx.holdUntil, window.name
        end, window.hold + 30, "sweep: " .. window.name)
        plan.act(function() watch.holding = false end)
        plan.wait(3)
        plan.act(function() watch.window = nil end)
        plan.note(weapon.name, function()
            local tally = watch.tally[window.name]
            local own, made = 0, 0
            for _, touched in pairs(tally and tally.lasers or {}) do
                if touched then made = made + 1 else own = own + 1 end
            end
            return string.format("attacks %d; own pieces %d, made by the prism %d", tally and tally.attacks or 0, own, made)
        end)
    end
    plan.act(function(player)
        watch = nil
        setFast(player, false)
    end)
    plan.wait(1)
end)
S.rows[#S.rows].manual = true
