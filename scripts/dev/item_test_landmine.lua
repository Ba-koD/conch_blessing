local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine): the lifecycle contract and its cases. Every tear is a real
-- tear fired by holding the shoot key, every death the engine's own
-- (REPENTOGON MC_POST_TEAR_DEATH, observed here independently), every mine the
-- module's own effect in the room, and every blast is read from the enemy's
-- actual HP and the player's actual health.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function M() return ConchBlessing.landmine end
local function T() return M()._test end
local function evidence() return T().evidence() end

-- ---------------------------------------------------------------- observers
-- Where each of the watched player's tears died, in order, and every hit the
-- player takes while `playerHits` is a table.
local watched, deaths, playerHits
if ModCallbacks.MC_POST_TEAR_DEATH then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TEAR_DEATH, function(_, tear)
        if not watched or not deaths then return end
        local owner = require("scripts.lib.damage_provenance").getDirectPlayerOwner(tear)
        if owner and GetPtrHash(owner) == GetPtrHash(watched) then
            deaths[#deaths + 1] = { x = tear.Position.X, y = tear.Position.Y, damage = tear.CollisionDamage,
                frame = Game():GetFrameCount() }
        end
    end)
end
if ModCallbacks.MC_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
        if not playerHits or entity.Type ~= EntityType.ENTITY_PLAYER then return end
        local attack = source and source.Entity
        playerHits[#playerHits + 1] = string.format("amt=%.2f flags=%d src=%s", amount, flags,
            attack and string.format("%d.%d", attack.Type, attack.Variant) or "none")
    end)
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
    return string.format("mines=[%s] deaths=%d hits=%d laid=%d skipped=%d trimmed=%d exploded=%d chained=%d",
        table.concat(parts, " "), e.deaths, e.hits, e.laid, e.skipped, e.trimmed, e.exploded, e.chained)
end

-- Cases that share one run per group (S.sequenceBundle below); each stays
-- callable alone.
local sharedConditions, sharedDamage = {}, {}
local conditionsCase = S.caseIn(sharedConditions, "LANDMINE", { conditions = true })
local damageCase = S.caseIn(sharedDamage, "LANDMINE", { damage = true })

local function requireModule(plan)
    plan.require("Landmine module, its mine effect and REPENTOGON's tear callbacks ready", function()
        local m = M()
        return m and m._test and m.available and m.mineVariant() > 0 and ModCallbacks.MC_POST_TEAR_DEATH and true
            or nil, "module missing, effect unregistered or no tear death callback"
    end)
end

local function give(player, id, copies)
    while player:GetCollectibleNum(id) < copies do player:AddCollectible(id, 0, false) end
    while player:GetCollectibleNum(id) > copies do player:RemoveCollectible(id) end
end

local function hold(player, ctx)
    player.Position = ctx.from
    player.Velocity = Vector.Zero
end

-- Fire `count` real tears to the right from `place(room)` and wait until every
-- one of them is gone; `each(player, ctx)` runs on every update meanwhile.
local function fire(plan, label, place, count, each)
    count = count or 1
    local function tend(player, ctx)
        hold(player, ctx)
        if each then each(player, ctx) end
    end
    plan.act(function(player, ctx)
        ctx.from = place(Game():GetRoom())
        tend(player, ctx)
        watched, deaths = player, {}
        ctx.deaths = deaths
    end)
    plan.wait(2)
    plan.act(function(player, ctx)
        H.shoot(player, "$tears", ctx, count)
        ctx.shots.directOnly = true
    end)
    plan.waitUntil(function(player, ctx)
        tend(player, ctx)
        return ctx.shots.count >= count, string.format("%d of %d tears fired", ctx.shots.count, count)
    end, 60 + 40 * count, label .. ": " .. count .. " real tear(s) fired")
    plan.act(function() H.stopShooting() end)
    plan.waitUntil(function(player, ctx)
        tend(player, ctx)
        for _, tear in ipairs(ctx.shots.entities) do
            if tear:Exists() then return false, "a tear is still flying" end
        end
        return true
    end, 180, label .. ": every tear is gone")
    plan.wait(2)
    plan.note(label .. ": tear deaths the engine reported", function(_, ctx)
        local parts = {}
        for _, death in ipairs(ctx.deaths) do
            parts[#parts + 1] = string.format("f%d %.0f,%.0f dmg=%.2f", death.frame, death.x, death.y, death.damage)
        end
        return string.format("%d of %d: %s", #ctx.deaths, count, table.concat(parts, "; "))
    end)
end

local function reportedDeaths(plan, count)
    plan.require("the engine reported every tear's death", function(_, ctx)
        return #ctx.deaths >= count, string.format("%d of %d", #ctx.deaths, count)
    end)
end

local function leftSide(room)
    local centre = room:GetCenterPos()
    return Vector(room:GetTopLeftPos().X + 60, centre.Y)
end

-- The armed mine's record and entity, the only one in the room.
local function onlyMine(ctx)
    local list = roomMines()
    ctx.mine = list[1]
    for _, record in ipairs(M().mines()) do
        if record.ref.Ref and ctx.mine and GetPtrHash(record.ref.Ref) == GetPtrHash(ctx.mine) then ctx.record = record end
    end
    return #list == 1 and ctx.record ~= nil
end

C.LANDMINE = { stage = function(plan, id, n)
    plan.act(function() clearMines(); T().resetEvidence() end)
    fire(plan, "lifecycle with " .. n .. " cop" .. (n == 1 and "y" or "ies"), leftSide, 1)
    plan.check(n > 0 and "a missed tear lays one mine" or "without Landmine a missed tear lays nothing", function()
        local count = #roomMines()
        return count == (n > 0 and 1 or 0), describeMines()
    end)
    plan.act(function()
        clearMines()
        watched, deaths = nil, nil
    end)
end }

-- A tear that flies its full range and falls lays one mine where it died,
-- owned by the shooter and holding that tear's damage.
conditionsCase("miss", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines(); watched, deaths = nil, nil end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a missed tear", leftSide, 1)
    reportedDeaths(plan, 1)
    plan.check("one mine lies where the tear died, from that tear", function(player, ctx)
        local death = ctx.deaths[1]
        local ok = onlyMine(ctx)
        local distance = ok and ctx.mine.Position:Distance(Vector(death.x, death.y)) or -1
        local owner = ok and ctx.mine.SpawnerEntity
        return ok and distance <= 2 and owner and GetPtrHash(owner) == GetPtrHash(player)
            and H.near(ctx.record.damage, death.damage),
            string.format("distance=%.1f damage=%.2f tear=%.2f %s", distance, ok and ctx.record.damage or -1,
                death and death.damage or -1, describeMines())
    end)
    plan.waitUntil(function(_, ctx)
        local sprite = ctx.mine:GetSprite()
        return sprite:IsPlaying("Idle"), "animation " .. tostring(sprite:GetAnimation())
    end, 30, "the mine finishes appearing and idles")
    plan.wait(30)
    plan.check("an armed mine with nobody on it stays", function(_, ctx)
        return ctx.mine:Exists() and evidence().exploded == 0, describeMines()
    end)
    plan.section("LANDMINE / miss", "a green splash where the tear fell turns into a small olive mine whose red button blinks")
end)

-- A tear that hits an enemy lays nothing.
conditionsCase("hit", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function()
            clearMines(); watched, deaths = nil, nil
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        T().resetEvidence()
        ctx.target = H.target(player, true)
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 30, "target ready")
    plan.act(function(_, ctx)
        ctx.spot = leftSide(Game():GetRoom()) + Vector(100, 0)
        ctx.before = ctx.target.HitPoints
    end)
    fire(plan, "a tear at an enemy", leftSide, 1, function(_, ctx)
        if ctx.target:Exists() then
            ctx.target.Position = ctx.spot
            ctx.target.Velocity = Vector.Zero
        end
    end)
    plan.check("the tear hit the enemy and laid no mine", function(_, ctx)
        local loss = ctx.before - ctx.target.HitPoints
        return loss > 0 and #roomMines() == 0 and evidence().hits >= 1,
            string.format("hpLoss=%.2f %s", loss, describeMines())
    end)
end)
-- A tear that strikes the wall lays its mine inside the room, on floor.
conditionsCase("wall", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines(); watched, deaths = nil, nil end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a tear into the right wall", function(room)
        return Vector(room:GetBottomRightPos().X - 50, room:GetCenterPos().Y)
    end, 1)
    plan.check("the mine lies inside the room, on floor, by the wall", function(_, ctx)
        local room = Game():GetRoom()
        local ok = onlyMine(ctx)
        local position = ok and ctx.mine.Position
        local inside = ok and room:IsPositionInRoom(position, 0)
            and room:GetGridCollisionAtPos(position) == GridCollisionClass.COLLISION_NONE
        local gap = ok and room:GetBottomRightPos().X - position.X or -1
        return ok and inside and gap >= 0 and gap <= 60,
            string.format("inside=%s gapToWall=%.1f %s", tostring(inside), gap, describeMines())
    end)
end)

-- An enemy walking onto an armed mine sets it off: it loses exactly twice the
-- tear's damage; the player standing on the same mine is never hurt, does not
-- set it off, and a rock beside it stays whole.
damageCase("trigger", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function()
            clearMines(); watched, deaths, playerHits = nil, nil, nil
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a missed tear", leftSide, 1)
    plan.require("one mine laid", function(_, ctx) return onlyMine(ctx), describeMines() end)
    plan.act(function(player, ctx)
        ctx.from = ctx.mine.Position
        ctx.health = health(player)
        playerHits = {}
        local room = Game():GetRoom()
        ctx.rockIndex = room:GetGridIndex(ctx.mine.Position + Vector(0, 40))
        ctx.rockPlaced = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
    end)
    plan.wait(20)
    plan.check("the player standing on the armed mine does not set it off", function(player, ctx)
        hold(player, ctx)
        return ctx.mine:Exists() and evidence().exploded == 0, describeMines()
    end)
    plan.act(function(player, ctx)
        ctx.target = H.target(player, true)
        ctx.target.Position = ctx.mine.Position + Vector(120, 0)
    end)
    plan.waitUntil(function(player, ctx)
        hold(player, ctx)
        ctx.target.Position = ctx.mine.Position + Vector(120, 0)
        return H.targetReady(ctx.target)
    end, 30, "target ready away from the mine")
    plan.act(function(player, ctx)
        ctx.damage = ctx.record.damage
        ctx.before = ctx.target.HitPoints
    end)
    plan.waitUntil(function(player, ctx)
        hold(player, ctx)
        if evidence().exploded > 0 then return true end
        ctx.target.Position = ctx.mine.Position
        ctx.target.Velocity = Vector.Zero
        return false, "waiting for the enemy to set it off"
    end, 30, "the enemy steps on the mine")
    plan.wait(3)
    plan.check("the enemy lost exactly twice the tear's damage", function(_, ctx)
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

-- Two tears fired the same way fall together: an enemy on one mine sets off
-- the other a moment later, and both blasts reach it.
damageCase("chain", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function()
            clearMines(); watched, deaths = nil, nil
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "two missed tears", leftSide, 2)
    plan.require("two mines laid close together", function(_, ctx)
        local list = roomMines()
        ctx.mines = list
        local gap = #list == 2 and list[1].Position:Distance(list[2].Position) or -1
        return #list == 2 and gap <= M().data.blastRadius, string.format("gap=%.1f %s", gap, describeMines())
    end)
    plan.act(function(player, ctx)
        ctx.damage = M().mines()[1].damage
        ctx.target = H.target(player, true)
        ctx.spot = ctx.mines[1].Position
        ctx.target.Position = ctx.spot + Vector(120, 0)
    end)
    plan.waitUntil(function(_, ctx)
        ctx.target.Position = ctx.spot + Vector(120, 0)
        return H.targetReady(ctx.target)
    end, 30, "target ready away from the mines")
    plan.act(function(_, ctx) ctx.before = ctx.target.HitPoints end)
    plan.waitUntil(function(_, ctx)
        if evidence().exploded >= 2 then return true end
        if evidence().exploded == 0 then ctx.target.Position = ctx.spot end
        ctx.target.Velocity = Vector.Zero
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

-- Twelve missed tears leave ten mines: the two oldest go.
conditionsCase("cap", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines(); watched, deaths = nil, nil end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "twelve missed tears", leftSide, 12)
    reportedDeaths(plan, 12)
    plan.check("ten mines remain and the two oldest were removed", function()
        local e = evidence()
        return #roomMines() == 10 and e.laid == 12 and e.trimmed == 2, describeMines()
    end)
end)

-- Leaving the room leaves its mines behind, and tears dying as the room is
-- left lay nothing in the next one.
conditionsCase("room_change", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines(); watched, deaths = nil, nil end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a missed tear", leftSide, 1)
    plan.require("one mine laid", function(_, ctx) return onlyMine(ctx), describeMines() end)
    plan.act(function(player, ctx)
        H.shoot(player, "$tears", ctx, 3)
    end)
    plan.wait(6)
    -- Any open door will do: the case needs another room, not an ordinary one.
    H.walkThroughDoor(plan, "leave with tears in flight", function()
        local room = Game():GetRoom()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door:IsOpen() then return slot end
        end
        return nil
    end, function() H.stopShooting() end)
    plan.wait(30)
    plan.check("no mine in the new room and none remembered", function()
        return #roomMines() == 0 and #M().mines() == 0, describeMines()
    end)
end)

-- One run per group: between cases the mines go and S.resetPlayer proves the
-- player is where a fresh run left it. room_change walks into the next room
-- and trigger leaves a rock, so each closes its run; chain runs before trigger.
local function fresh(plan)
    S.resetPlayer(plan, function()
        clearMines()
        watched, deaths, playerHits = nil, nil, nil
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
