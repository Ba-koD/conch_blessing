local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine): the lifecycle contract and its cases. The player really
-- holds the shoot key (the engine reads it through MC_INPUT_ACTION) and is
-- moved a few units an update along a straight line, as walking moves them.
-- Every attack is the engine's own weapon trigger (REPENTOGON), recorded here
-- with where the player stood, and every mine is the module's own effect in
-- the room (its fall read from its own PositionOffset): a case compares the
-- two, one mine for each attack, at the same spot. Every blast is read from
-- the enemy's actual HP and the player's actual health. A case keeps one
-- harmless enemy pinned in the corner behind the walks (the room stays
-- uncleared and its doors shut), where the tears (fired to the right) never
-- reach it and it never comes near a mine; no_enemies shoots with none.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function M() return ConchBlessing.landmine end
local function T() return M()._test end
local function evidence() return T().evidence() end

local STEP = 4      -- units walked an update (Isaac at speed 1 walks about 4.5)
local WALK = 340    -- a walk long enough for several attacks

-- ---------------------------------------------------------------- observers
-- Every hit the player takes while `playerHits` is a table.
local playerHits
if ModCallbacks.MC_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
        if not playerHits or entity.Type ~= EntityType.ENTITY_PLAYER then return end
        local attack = source and source.Entity
        playerHits[#playerHits + 1] = string.format("amt=%.2f flags=%d src=%s", amount, flags,
            attack and string.format("%d.%d", attack.Type, attack.Variant) or "none")
    end)
end

-- Where the player stood at each of their own attacks while `attacks` is a
-- table (a familiar's weapon is its own owner and is not recorded).
local attacks
if ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED, function(_, _, _, owner)
        local player = attacks and owner and owner:ToPlayer()
        if player then attacks[#attacks + 1] = Vector(player.Position.X, player.Position.Y) end
    end)
end

local function startShooting(player, ctx)
    ctx.attacks = ctx.attacks or {}
    attacks = ctx.attacks
    H.shoot(player, "$tears", ctx)
end

local function stopShooting()
    H.stopShooting()
    attacks = nil
end

-- The mines in the room, NO_QUERY included.
local function roomMines()
    local list, variant = {}, M().mineVariant()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == variant and entity:Exists() then
            list[#list + 1] = entity
        end
    end
    return list
end

local function clearMines()
    for _, mine in ipairs(roomMines()) do mine:Remove() end
    M().mines()
end

local function health(player)
    return player:GetHearts() + player:GetSoulHearts() + player:GetBlackHearts() + player:GetBoneHearts()
end

local function describeMines()
    local parts = {}
    for _, mine in ipairs(roomMines()) do
        parts[#parts + 1] = string.format("%.0f,%.0f", mine.Position.X, mine.Position.Y)
    end
    local e = evidence()
    return string.format("mines=[%s] laid=%d landed=%d blocked=%d exploded=%d chained=%d pictures=%d",
        table.concat(parts, " "), e.laid, e.landed, e.blocked, e.exploded, e.chained, e.pictures)
end

local function byPlace(a, b)
    if a.X ~= b.X then return a.X < b.X end
    return a.Y < b.Y
end

-- Whether the room holds exactly one mine for each attack recorded (`spots`,
-- else every attack of the case), each where the player stood for it.
local function matchesAttacks(ctx, spots)
    local places, wanted = {}, {}
    for k, mine in ipairs(roomMines()) do places[k] = mine.Position end
    for k, spot in ipairs(spots or ctx.attacks or {}) do wanted[k] = spot end
    table.sort(places, byPlace)
    table.sort(wanted, byPlace)
    local ok, worst = #places == #wanted and #wanted > 0, 0
    for k = 1, math.min(#places, #wanted) do
        worst = math.max(worst, places[k]:Distance(wanted[k]))
    end
    return ok and worst <= 1, string.format("attacks=%d worst=%.2f %s", #wanted, worst, describeMines())
end

-- Cases that share one run per group (S.sequenceBundle below); each stays
-- callable alone. Mines drop with or without enemies; the cases keep one so
-- the room stays uncleared and its doors shut.
local sharedConditions, sharedDamage = {}, {}
local conditionsCase = S.caseIn(sharedConditions, "LANDMINE", { conditions = true })
local damageCase = S.caseIn(sharedDamage, "LANDMINE", { damage = true })

local function requireModule(plan)
    plan.require("Landmine module, its mine effect and REPENTOGON's attack event ready", function()
        local m = M()
        return m and m._test and m.available and m.mineVariant() > 0 and m._test.weaponEvent()
            and ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED and true or nil,
            "module missing, effect unregistered or no weapon-trigger callback"
    end)
end

local function give(player, id, copies)
    while player:GetCollectibleNum(id) < copies do player:AddCollectible(id, 0, false) end
    while player:GetCollectibleNum(id) > copies do player:RemoveCollectible(id) end
end

local function leftSide(room)
    local centre = room:GetCenterPos()
    return Vector(room:GetTopLeftPos().X + 60, centre.Y)
end

-- The bottom-left corner: behind every walk, since the tears fly right.
local function behind(room)
    return Vector(room:GetTopLeftPos().X + 20, room:GetBottomRightPos().Y - 20)
end

local function pin(ctx)
    local target = ctx.target
    if target and target:Exists() and ctx.targetSpot then
        target.Position = ctx.targetSpot
        target.Velocity = Vector.Zero
    end
end

-- The highest each mine was seen above the floor (PositionOffset is negative
-- upward).
local function track(ctx)
    ctx.lifts = ctx.lifts or {}
    for _, mine in ipairs(roomMines()) do
        local hash = GetPtrHash(mine)
        ctx.lifts[hash] = math.min(ctx.lifts[hash] or 0, mine.PositionOffset.Y)
    end
end

local function setup(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function()
            stopShooting()
            clearMines()
            playerHits = nil
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        clearMines()
        T().resetEvidence()
        ctx.attacks = {}
    end)
end

-- A harmless enemy waits in the corner behind the walks, so the room has one.
local function withEnemy(plan)
    plan.act(function(player, ctx)
        ctx.targetSpot = behind(Game():GetRoom())
        ctx.target = H.target(player, true)
        pin(ctx)
    end)
    plan.waitUntil(function(_, ctx)
        pin(ctx)
        local ready, why = H.targetReady(ctx.target)
        if not ready then return false, why end
        local alive = Game():GetRoom():GetAliveEnemiesCount()
        return alive > 0, "alive enemies " .. alive
    end, 30, "an enemy waits behind the walks")
end

-- Stands the player at `place(room, ctx)` for `updates` updates, holding the
-- shoot key when `shoot`.
local function stand(plan, place, updates, shoot)
    plan.act(function(player, ctx)
        ctx.spot = place(Game():GetRoom(), ctx)
        ctx.standUntil = Game():GetFrameCount() + updates
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        if shoot then startShooting(player, ctx) end
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        track(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        return Game():GetFrameCount() >= ctx.standUntil, "standing"
    end, updates + 30, string.format("stand still %d updates%s", updates, shoot and ", shooting" or ""))
    plan.act(function() stopShooting() end)
end

-- Walks the player from `from(room)` by (dx, dy), STEP units an update,
-- holding the shoot key when `shoot`: two updates standing at the start,
-- the walk, two updates standing at the end, then the key is let go.
local function walk(plan, label, from, dx, dy, shoot)
    local length = math.sqrt(dx * dx + dy * dy)
    local delta
    plan.act(function(player, ctx)
        delta = Vector(dx, dy)
        ctx.from = from(Game():GetRoom())
        ctx.walked, ctx.held = 0, 0
        player.Position, player.Velocity = ctx.from, Vector.Zero
        if shoot then startShooting(player, ctx) end
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        track(ctx)
        ctx.held = ctx.held + 1
        if ctx.held > 2 and ctx.walked < length then ctx.walked = math.min(length, ctx.walked + STEP) end
        player.Position = ctx.from + delta * (ctx.walked / length)
        player.Velocity = Vector.Zero
        return ctx.walked >= length and ctx.held >= math.ceil(length / STEP) + 4,
            string.format("%.0f of %.0f walked", ctx.walked, length)
    end, math.ceil(length / STEP) + 40, label)
    plan.act(function() stopShooting() end)
end

-- Waits until every mine laid has landed.
local function settle(plan)
    plan.waitUntil(function(_, ctx)
        pin(ctx)
        track(ctx)
        local e = evidence()
        return e.landed == e.laid, string.format("%d of %d landed", e.landed, e.laid)
    end, 40, "every mine has landed")
end

-- The armed mine's record and entity, the only one in the room.
local function onlyMine(ctx)
    local list = roomMines()
    ctx.mine = list[1]
    ctx.record = nil
    for _, record in ipairs(M().mines()) do
        if record.ref.Ref and ctx.mine and GetPtrHash(record.ref.Ref) == GetPtrHash(ctx.mine) then ctx.record = record end
    end
    return #list == 1 and ctx.record ~= nil
end

local function noTears()
    return #Isaac.FindByType(EntityType.ENTITY_TEAR) == 0
end

-- Waits, the player held at `spot`, until the tears are gone and every mine
-- is armed.
local function armed(plan, spot, label)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = spot(ctx), Vector.Zero
        if not noTears() then return false, "tears still flying" end
        for _, record in ipairs(M().mines()) do
            if not record.armed then return false, "a mine is not armed" end
        end
        return true
    end, 90, label)
end

-- Shooting in place in a room with an enemy: one mine for every attack, all
-- piled at the feet, whatever the number of copies; none without the item.
C.LANDMINE = { stage = function(plan, id, n)
    requireModule(plan)
    plan.act(function(_, ctx)
        clearMines()
        T().resetEvidence()
        ctx.attacks = {}
    end)
    withEnemy(plan)
    stand(plan, function(room, ctx)
        ctx.from = leftSide(room)
        return ctx.from
    end, 30, true)
    settle(plan)
    plan.check(n > 0 and "every attack in place drops a mine at the feet, piled up"
        or "without Landmine attacking drops nothing", function(_, ctx)
        local list, shots = roomMines(), #ctx.attacks
        if n == 0 then
            return #list == 0 and shots >= 1, string.format("attacks=%d %s", shots, describeMines())
        end
        local ok, detail = matchesAttacks(ctx)
        for _, mine in ipairs(list) do ok = ok and mine.Position:Distance(ctx.from) <= 1 end
        return ok and shots >= 2, detail
    end)
    plan.act(function(_, ctx)
        clearMines()
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        ctx.target = nil
    end)
end }

-- Walking while shooting: a mine for every attack, where the player stood
-- for it, each falling from the holder and landing.
conditionsCase("every_attack", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    walk(plan, "walk and shoot", leftSide, WALK, 0, true)
    settle(plan)
    plan.check("a mine for every attack, where the player stood for it", function(_, ctx)
        local ok, detail = matchesAttacks(ctx)
        return ok and #ctx.attacks >= 4, detail
    end)
    plan.check("each mine fell from the holder's hands and landed", function(_, ctx)
        local parts, ok = {}, true
        for _, mine in ipairs(roomMines()) do
            local lift = ctx.lifts[GetPtrHash(mine)] or 0
            parts[#parts + 1] = string.format("%.1f->%.1f", lift, mine.PositionOffset.Y)
            ok = ok and lift <= -5 and mine.PositionOffset.Y == 0
        end
        local e = evidence()
        return #parts >= 1 and ok and e.landed == e.laid,
            string.format("highest->now=[%s] landed=%d laid=%d", table.concat(parts, " "), e.landed, e.laid)
    end)
    plan.check("every mine is the player's and holds the player's damage", function(player)
        local bad = 0
        for _, record in ipairs(M().mines()) do
            local owner = record.ref.Ref and record.ref.Ref.SpawnerEntity
            if not owner or GetPtrHash(owner) ~= GetPtrHash(player) or not H.near(record.damage, player.Damage) then
                bad = bad + 1
            end
        end
        return #M().mines() >= 1 and bad == 0, string.format("bad=%d damage=%.2f", bad, player.Damage)
    end)
    plan.act(function(_, ctx) ctx.mine = roomMines()[1] end)
    plan.waitUntil(function(_, ctx)
        pin(ctx)
        local sprite = ctx.mine:GetSprite()
        return sprite:IsPlaying("Idle"), "animation " .. tostring(sprite:GetAnimation())
    end, 30, "the mine finishes landing and idles")
    plan.waitUntil(function(_, ctx)
        pin(ctx)
        return noTears(), "tears still flying"
    end, 60, "the tears are gone")
    plan.check("armed mines with nobody on them stay", function(_, ctx)
        return ctx.mine:Exists() and evidence().exploded == 0, describeMines()
    end)
    plan.section("LANDMINE / every_attack", "an olive mine drops from Isaac's hands at his feet with every shot as he walks, sinks into a green splash and settles; their red buttons blink")
end)

-- Walking without shooting drops nothing; the first shot then drops one at
-- once, at the feet.
conditionsCase("not_shooting", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    walk(plan, "walk without shooting", leftSide, WALK, 0, false)
    plan.check("walking without shooting drops nothing", function()
        return #roomMines() == 0 and evidence().laid == 0, describeMines()
    end)
    plan.act(function(player, ctx)
        ctx.spot = Vector(player.Position.X, player.Position.Y)
        ctx.shotAt = Game():GetFrameCount()
        startShooting(player, ctx)
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        return evidence().laid > 0, "no mine yet"
    end, 10, "a mine drops as soon as the shooting starts")
    plan.act(function(_, ctx)
        ctx.after = Game():GetFrameCount() - ctx.shotAt
        stopShooting()
    end)
    plan.check("it came with the first attack, at the feet", function(_, ctx)
        local ok, detail = matchesAttacks(ctx)
        local list = roomMines()
        return ok and #list == 1 and list[1].Position:Distance(ctx.spot) <= 1 and ctx.after <= 3,
            string.format("after %d updates %s", ctx.after, detail)
    end)
end)

-- With no enemy in the room every attack still drops its mine (user decision
-- 2026-11-24), and an enemy coming in later sets one off.
conditionsCase("no_enemies", function(plan, id)
    setup(plan, id)
    plan.require("no enemy in the room", function()
        local alive = Game():GetRoom():GetAliveEnemiesCount()
        return alive == 0, "alive enemies " .. alive
    end)
    walk(plan, "walk and shoot with no enemy about", leftSide, WALK, 0, true)
    settle(plan)
    plan.check("no enemy, still a mine for every attack where the player stood", function(_, ctx)
        local ok, detail = matchesAttacks(ctx)
        return ok and #ctx.attacks >= 4, detail
    end)
end)

-- At tears 120 (MaxFireDelay -0.75: four tears an update) a holder still
-- drops one mine every 3 updates, 0.1 s (user decision 2026-11-24); every
-- mine lies where the player stood.
local fastPlayer = nil -- GetPtrHash of the player whose fire rate the case raises
if ModCallbacks.MC_EVALUATE_CACHE and ConchBlessing.AddPriorityCallback then
    local late = (CallbackPriority and CallbackPriority.LATE) or 100
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, late, function(_, player, flag)
        if fastPlayer and flag == CacheFlag.CACHE_FIREDELAY and GetPtrHash(player) == fastPlayer then
            player.MaxFireDelay = 30 / 120 - 1
        end
    end)
end
local function setFast(player, on)
    fastPlayer = on and GetPtrHash(player) or nil
    player:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
    player:EvaluateItems()
end

conditionsCase("interval", function(plan, id)
    local UPDATES = 60
    setup(plan, id)
    withEnemy(plan)
    plan.act(function(player, ctx)
        setFast(player, true)
        table.insert(ctx.cleanupFns, 1, function() setFast(player, false) end)
    end)
    plan.wait(2)
    plan.require("tears 120", function(player)
        local tears = 30 / (player.MaxFireDelay + 1)
        return math.abs(tears - 120) < 0.5, string.format("tears %.1f", tears)
    end)
    stand(plan, function(room, ctx)
        ctx.from = leftSide(room)
        return ctx.from
    end, UPDATES, true)
    plan.act(function(player) setFast(player, false) end)
    settle(plan)
    plan.check("one mine every 3 updates however fast the attacks come", function(_, ctx)
        local frames = {}
        for _, record in ipairs(M().mines()) do frames[#frames + 1] = record.frame end
        table.sort(frames)
        local closest = math.huge
        for k = 2, #frames do closest = math.min(closest, frames[k] - frames[k - 1]) end
        local expected = UPDATES / M().data.interval
        return #ctx.attacks >= 2 * #frames and #frames >= expected - 2 and #frames <= expected + 1
            and closest >= M().data.interval,
            string.format("attacks=%d mines=%d expected about %d closest %s updates apart waited=%d", #ctx.attacks,
                #frames, expected, tostring(closest), evidence().waited)
    end)
    plan.check("every mine lies at the feet", function(_, ctx)
        local list = roomMines()
        for _, mine in ipairs(list) do
            if mine.Position:Distance(ctx.from) > 1 then return false, describeMines() end
        end
        return #list >= 1, describeMines()
    end)
end)

-- Three walks leave every mine laid, far more than the old ten.
conditionsCase("no_cap", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    for _, row in ipairs({ -80, 0, 80 }) do
        walk(plan, "a walk on row " .. row, function(room) return leftSide(room) + Vector(0, row) end,
            WALK, 0, true)
    end
    settle(plan)
    plan.check("every mine laid is still there, one for every attack", function(_, ctx)
        local e = evidence()
        local ok, detail = matchesAttacks(ctx)
        return ok and #ctx.attacks > 10 and #roomMines() == e.laid and #M().mines() == e.laid, detail
    end)
end)

-- Leaving the room leaves its mines behind; none follows into the next room.
conditionsCase("room_change", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    walk(plan, "a walk shooting", leftSide, WALK, 0, true)
    plan.require("mines dropped", function() return #roomMines() >= 1, describeMines() end)
    plan.act(function(_, ctx)
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        ctx.target = nil
    end)
    -- Any open door will do: the case needs another room, not an ordinary one.
    local function openDoor()
        local room = Game():GetRoom()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door:IsOpen() then return slot end
        end
        return nil
    end
    plan.waitUntil(function() return openDoor() ~= nil, "every door shut" end, 90, "a door is open")
    H.walkThroughDoor(plan, "leave the room", openDoor)
    plan.wait(10)
    plan.check("no mine in the new room and none remembered", function()
        return #roomMines() == 0 and #M().mines() == 0, describeMines()
    end)
end)

-- Flying over pits: an attack over a pit drops nothing, every other attack
-- drops its mine where the player stood. Pits stay, so the case runs alone.
S.add("LANDMINE", "pit", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.act(function(player, ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_TRANSCENDENCE, 0, false)
        player:AddCacheFlags(CacheFlag.CACHE_FLYING)
        player:EvaluateItems()
        local room = Game():GetRoom()
        ctx.pits = {}
        -- Three tiles of pit across the walk, wide enough for attacks over them.
        for _, offset in ipairs({ 80, 120, 160 }) do
            local index = room:GetGridIndex(leftSide(room) + Vector(offset, 0))
            Isaac.GridSpawn(GridEntityType.GRID_PIT, 0, room:GetGridPosition(index), true)
            -- A pit spawned in a loaded room blocks nothing until its
            -- collision is updated (measured for 축 on 2026-10-31).
            local grid = room:GetGridEntity(index)
            local pit = grid and grid:ToPit()
            if pit then
                pcall(pit.PostInit, pit)
                pit:UpdateCollision()
            end
            ctx.pits[#ctx.pits + 1] = index
        end
    end)
    plan.wait(2)
    plan.require("the player flies and three pits lie across the walk", function(player, ctx)
        local room = Game():GetRoom()
        for _, index in ipairs(ctx.pits) do
            if room:GetGridCollision(index) ~= GridCollisionClass.COLLISION_PIT then
                return false, "grid " .. index .. " collision " .. tostring(room:GetGridCollision(index))
            end
        end
        return player.CanFly, "can fly " .. tostring(player.CanFly)
    end)
    withEnemy(plan)
    walk(plan, "a walk shooting over the pits", leftSide, WALK, 0, true)
    settle(plan)
    plan.check("no mine on a pit; every attack over the floor dropped one where the player stood",
        function(_, ctx)
            local room, onPit, overPit, overFloor = Game():GetRoom(), 0, 0, {}
            for _, mine in ipairs(roomMines()) do
                if room:GetGridCollisionAtPos(mine.Position) ~= GridCollisionClass.COLLISION_NONE then
                    onPit = onPit + 1
                end
            end
            for _, spot in ipairs(ctx.attacks) do
                if room:GetGridCollisionAtPos(spot) ~= GridCollisionClass.COLLISION_NONE then
                    overPit = overPit + 1
                else
                    overFloor[#overFloor + 1] = spot
                end
            end
            local ok, detail = matchesAttacks(ctx, overFloor)
            return ok and onPit == 0 and overPit > 0 and evidence().blocked == overPit,
                string.format("onPit=%d overPit=%d blocked=%d %s", onPit, overPit, evidence().blocked, detail)
        end)
end)

-- Shooting in place piles mines up; an enemy stepping on the pile sets off
-- every mine in it at once (one explosion), losing twice the holder's damage
-- for each, and the player standing on it is never hurt.
damageCase("pile", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    stand(plan, function(room, ctx)
        ctx.from = leftSide(room)
        return ctx.from
    end, 60, true)
    settle(plan)
    plan.require("a pile at the feet, one mine for every attack", function(_, ctx)
        local ok, detail = matchesAttacks(ctx)
        local list = roomMines()
        for _, mine in ipairs(list) do ok = ok and mine.Position:Distance(ctx.from) <= 1 end
        ctx.pile = #list
        return ok and #list >= 3, detail
    end)
    plan.act(function(player, ctx)
        ctx.damage = player.Damage
        ctx.health = health(player)
        playerHits = {}
    end)
    armed(plan, function(ctx) return ctx.from end, "the tears are gone and the pile is armed")
    plan.act(function(_, ctx)
        ctx.before = ctx.target.HitPoints
        ctx.targetSpot = ctx.from
    end)
    plan.waitUntil(function(player, ctx)
        player.Position, player.Velocity = ctx.from, Vector.Zero
        if evidence().exploded > 0 then return true end
        pin(ctx)
        return false, "waiting for the enemy to step on the pile"
    end, 30, "the enemy steps on the pile")
    plan.wait(3)
    plan.check("the whole pile went off at once, with one explosion", function(_, ctx)
        local e = evidence()
        return e.exploded == ctx.pile and e.chained == 0 and e.pictures == 1 and #roomMines() == 0,
            string.format("pile=%d %s", ctx.pile, describeMines())
    end)
    plan.check("the enemy lost twice the holder's damage for every mine in the pile", function(_, ctx)
        local loss, expected = ctx.before - ctx.target.HitPoints, 2 * ctx.damage * ctx.pile
        return H.near(loss, expected) and evidence().struck == ctx.pile,
            string.format("loss=%.4f expected=%.4f struck=%d pile=%d", loss, expected, evidence().struck, ctx.pile)
    end)
    plan.check("the player standing on the pile was not hurt", function(player, ctx)
        local hits = playerHits or {}
        return #hits == 0 and health(player) == ctx.health,
            string.format("playerHits=[%s] health %d -> %d", table.concat(hits, "; "), ctx.health, health(player))
    end)
    plan.section("LANDMINE / pile", "one green explosion where the enemy stepped on the pile of mines")
end)

-- An enemy walking onto an armed mine sets it off: it loses exactly twice the
-- holder's damage; the player standing on the same mine is never hurt, does
-- not set it off, and a rock beside it stays whole.
damageCase("trigger", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    stand(plan, function(room, ctx)
        ctx.from = leftSide(room)
        return ctx.from
    end, 6, true)
    settle(plan)
    plan.require("one mine at the feet", function(_, ctx)
        return onlyMine(ctx) and ctx.mine.Position:Distance(ctx.from) <= 1, describeMines()
    end)
    plan.act(function(player, ctx)
        ctx.damage = player.Damage
        ctx.health = health(player)
        playerHits = {}
        local room = Game():GetRoom()
        ctx.rockIndex = room:GetGridIndex(ctx.mine.Position + Vector(0, 40))
        ctx.rockPlaced = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
    end)
    armed(plan, function(ctx) return ctx.from end, "the tears are gone and the mine is armed")
    plan.wait(20)
    plan.check("the player standing on the armed mine does not set it off", function(player, ctx)
        player.Position, player.Velocity = ctx.from, Vector.Zero
        return ctx.mine:Exists() and evidence().exploded == 0, describeMines()
    end)
    plan.check("the mine holds the player's damage", function(_, ctx)
        return H.near(ctx.record.damage, ctx.damage), string.format("mine=%.4f player=%.4f", ctx.record.damage, ctx.damage)
    end)
    plan.act(function(_, ctx)
        ctx.before = ctx.target.HitPoints
        ctx.targetSpot = ctx.mine.Position
    end)
    plan.waitUntil(function(player, ctx)
        player.Position, player.Velocity = ctx.from, Vector.Zero
        if evidence().exploded > 0 then return true end
        pin(ctx)
        return false, "waiting for the enemy to set it off"
    end, 30, "the enemy steps on the mine")
    plan.wait(3)
    plan.check("the enemy lost exactly twice the holder's damage", function(_, ctx)
        local loss, expected = ctx.before - ctx.target.HitPoints, 2 * ctx.damage
        return H.near(loss, expected) and evidence().struck == 1,
            string.format("loss=%.4f expected=%.4f struck=%d", loss, expected, evidence().struck)
    end)
    plan.check("the mine is gone and the player was not hurt", function(player, ctx)
        local hits = playerHits or {}
        return not ctx.mine:Exists() and #hits == 0 and health(player) == ctx.health,
            string.format("mine=%s playerHits=[%s] health %d -> %d", tostring(ctx.mine:Exists()),
                table.concat(hits, "; "), ctx.health, health(player))
    end)
    plan.check("a rock beside the mine is still whole", function(_, ctx)
        local room = Game():GetRoom()
        local grid = room:GetGridEntity(ctx.rockIndex)
        local solid = room:GetGridCollision(ctx.rockIndex) ~= GridCollisionClass.COLLISION_NONE
        return ctx.rockPlaced and grid and grid:GetType() == GridEntityType.GRID_ROCK and solid,
            string.format("placed=%s type=%s solid=%s", tostring(ctx.rockPlaced), tostring(grid and grid:GetType()),
                tostring(solid))
    end)
    plan.section("LANDMINE / trigger", "a small green explosion where the enemy stepped on the mine")
end)

-- Two mines 50 apart (one shot in place, then another after walking away and
-- back below it): an enemy on one sets off the other a moment later, and both
-- blasts reach it.
damageCase("chain", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    stand(plan, function(room, ctx)
        ctx.from = leftSide(room)
        return ctx.from
    end, 6, true)
    stand(plan, function(_, ctx) return ctx.from + Vector(200, 0) end, 2, false)
    -- Long enough for the next attack once the fire delay is over, not for two.
    stand(plan, function(_, ctx) return ctx.from + Vector(0, 50) end, 8, true)
    settle(plan)
    plan.require("two mines 50 apart", function(_, ctx)
        local list = roomMines()
        local gap = #list == 2 and list[1].Position:Distance(list[2].Position) or -1
        return #list == 2 and math.abs(gap - 50) <= 1, string.format("gap=%.1f %s", gap, describeMines())
    end)
    plan.act(function(player, ctx)
        ctx.damage = player.Damage
        ctx.spot = ctx.from + Vector(0, 50)
    end)
    armed(plan, function(ctx) return ctx.spot end, "the tears are gone and both mines are armed")
    plan.act(function(_, ctx)
        ctx.before = ctx.target.HitPoints
        ctx.targetSpot = ctx.from
    end)
    plan.waitUntil(function(player, ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        if evidence().exploded >= 2 then return true end
        if evidence().exploded == 0 then pin(ctx) end
        if ctx.target:Exists() then ctx.target.Velocity = Vector.Zero end
        return false, "exploded " .. evidence().exploded
    end, 30, "both mines go off")
    plan.wait(3)
    plan.check("the second mine went off from the first one's blast", function()
        local e = evidence()
        return e.chained == 1 and e.exploded == 2 and #roomMines() == 0, describeMines()
    end)
    plan.check("both blasts reached the enemy", function(_, ctx)
        local loss, expected = ctx.before - ctx.target.HitPoints, 4 * ctx.damage
        return H.near(loss, expected), string.format("loss=%.4f expected=%.4f", loss, expected)
    end)
end)

-- One run per group: between cases the mines go and S.resetPlayer proves the
-- player is where a fresh run left it. room_change walks into the next room
-- and trigger leaves a rock, so each closes its run; pile and chain run
-- before trigger.
local function fresh(plan)
    S.resetPlayer(plan, function()
        stopShooting()
        clearMines()
        playerHits = nil
    end, function()
        return #M().mines() == 0 and #roomMines() == 0, describeMines()
    end)
    plan.act(function() T().resetEvidence() end)
end
S.last(sharedConditions, "room_change")
S.last(sharedDamage, "trigger")
S.sequenceBundle("LANDMINE", "shared_conditions", { conditions = true }, sharedConditions, function(plan) fresh(plan) end)
S.sequenceBundle("LANDMINE", "shared_damage", { damage = true }, sharedDamage, function(plan) fresh(plan) end)

return C
