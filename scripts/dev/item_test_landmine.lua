local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine): the lifecycle contract and its cases. Every tear is a real
-- tear fired by holding the shoot key and followed every update on its way,
-- every mine the module's own effect in the room (its fall read from its own
-- PositionOffset), and every blast is read from the enemy's actual HP and the
-- player's actual health.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function M() return ConchBlessing.landmine end
local function T() return M()._test end
local function evidence() return T().evidence() end

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

-- Removes every mine but the first `keep` laid, through the module's own list.
local function keepFirst(keep)
    for index, record in ipairs(M().mines()) do
        if index > keep and record.ref.Ref then record.ref.Ref:Remove() end
    end
    return #M().mines()
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
    return string.format("mines=[%s] trails=%d laid=%d landed=%d blocked=%d crowded=%d exploded=%d chained=%d",
        table.concat(parts, " "), e.trails, e.laid, e.landed, e.blocked, e.crowded, e.exploded, e.chained)
end

-- Cases that share one run per group (S.sequenceBundle below); each stays
-- callable alone.
local sharedConditions, sharedDamage = {}, {}
local conditionsCase = S.caseIn(sharedConditions, "LANDMINE", { conditions = true })
local damageCase = S.caseIn(sharedDamage, "LANDMINE", { damage = true })

local function requireModule(plan)
    plan.require("Landmine module and its mine effect ready", function()
        local m = M()
        return m and m._test and m.available and m.mineVariant() > 0 and true or nil,
            "module missing or effect unregistered"
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
-- one of them is gone, recording where each was on every update in
-- `ctx.path` (one straight line, so a list of x by y); `each(player, ctx)`
-- runs on every update meanwhile.
local function fire(plan, label, place, count, each)
    count = count or 1
    local function tend(player, ctx)
        hold(player, ctx)
        if each then each(player, ctx) end
        for _, tear in ipairs(ctx.shots and ctx.shots.entities or {}) do
            if tear:Exists() then
                local position = tear.Position
                ctx.path[#ctx.path + 1] = { x = position.X, y = position.Y }
                ctx.tearDamage, ctx.tearHeight = tear.CollisionDamage, tear.Height
            end
        end
        -- The highest each mine was seen above the floor (PositionOffset is
        -- negative upward).
        for _, mine in ipairs(roomMines()) do
            local hash = GetPtrHash(mine)
            ctx.lifts[hash] = math.min(ctx.lifts[hash] or 0, mine.PositionOffset.Y)
        end
    end
    plan.act(function(player, ctx)
        ctx.from = place(Game():GetRoom())
        ctx.path, ctx.shots, ctx.lifts = {}, nil, ctx.lifts or {}
        tend(player, ctx)
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
    plan.note(label .. ": the tears' path", function(_, ctx)
        local first, last = ctx.path[1], ctx.path[#ctx.path]
        return string.format("%d positions from %.0f,%.0f to %.0f,%.0f dmg=%.2f height=%.2f; %s", #ctx.path,
            first and first.x or -1, first and first.y or -1, last and last.x or -1, last and last.y or -1,
            ctx.tearDamage or -1, ctx.tearHeight or 0, describeMines())
    end)
end

local function leftSide(room)
    local centre = room:GetCenterPos()
    return Vector(room:GetTopLeftPos().X + 60, centre.Y)
end

-- The mines in the room sorted from left to right.
local function minesByX()
    local list = roomMines()
    table.sort(list, function(a, b) return a.Position.X < b.Position.X end)
    return list
end

-- Whether every mine lies on the path one tear flew to the right: on its line,
-- between where it was first seen and one step past where it was last seen.
local function onPath(ctx, list)
    local first, last = ctx.path[1], ctx.path[#ctx.path]
    if not first then return false, "no path recorded" end
    for _, mine in ipairs(list) do
        local p = mine.Position
        if math.abs(p.Y - first.y) > 2 or p.X < first.x - 1 or p.X > last.x + 16 then
            return false, string.format("mine %.1f,%.1f off the path %.1f..%.1f at y=%.1f", p.X, p.Y, first.x,
                last.x, first.y)
        end
    end
    return true
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
    plan.check(n > 0 and "a tear leaves a trail of mines" or "without Landmine a tear leaves nothing", function()
        local count = #roomMines()
        return n > 0 and count >= 2 or n == 0 and count == 0, describeMines()
    end)
    plan.act(function() clearMines() end)
end }

-- One tear leaves mines along its flight, a spacing apart, from that tear.
conditionsCase("trail", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines() end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "one tear", leftSide, 1)
    plan.check("the tear dropped two mines, both on its path", function(_, ctx)
        local list = minesByX()
        local ok, why = onPath(ctx, list)
        return #list == 2 and ok, string.format("%s %s", why or "", describeMines())
    end)
    plan.check("each mine fell from the tear's height and landed", function(_, ctx)
        local parts, ok = {}, true
        for _, mine in ipairs(roomMines()) do
            local lift = ctx.lifts[GetPtrHash(mine)] or 0
            parts[#parts + 1] = string.format("%.1f->%.1f", lift, mine.PositionOffset.Y)
            ok = ok and lift <= -5 and mine.PositionOffset.Y == 0
        end
        local e = evidence()
        return #parts >= 1 and ok and e.landed == e.laid,
            string.format("highest->now=[%s] tearHeight=%.2f firstLift=%.2f landed=%d laid=%d",
                table.concat(parts, " "), ctx.tearHeight or 0, e.last and e.last.lift or 0, e.landed, e.laid)
    end)
    plan.check("the mines lie a spacing apart", function()
        local list, spacing, gaps, ok = minesByX(), M().data.spacing, {}, true
        for k = 2, #list do
            local gap = list[k].Position.X - list[k - 1].Position.X
            gaps[#gaps + 1] = string.format("%.1f", gap)
            ok = ok and gap >= spacing - 1 and gap <= spacing + 16
        end
        return #list >= 2 and ok, "gaps=[" .. table.concat(gaps, " ") .. "] spacing=" .. spacing
    end)
    plan.check("every mine is the player's and holds the tear's damage", function(player, ctx)
        local bad = 0
        for _, record in ipairs(M().mines()) do
            local owner = record.ref.Ref and record.ref.Ref.SpawnerEntity
            if not owner or GetPtrHash(owner) ~= GetPtrHash(player) or not H.near(record.damage, ctx.tearDamage) then
                bad = bad + 1
            end
        end
        return #M().mines() >= 1 and bad == 0, string.format("bad=%d tear=%.2f", bad, ctx.tearDamage or -1)
    end)
    plan.act(function(_, ctx) ctx.mine = minesByX()[1] end)
    plan.waitUntil(function(_, ctx)
        local sprite = ctx.mine:GetSprite()
        return sprite:IsPlaying("Idle"), "animation " .. tostring(sprite:GetAnimation())
    end, 30, "the mine finishes appearing and idles")
    plan.wait(30)
    plan.check("armed mines with nobody on them stay", function(_, ctx)
        return ctx.mine:Exists() and evidence().exploded == 0, describeMines()
    end)
    plan.section("LANDMINE / trail", "two olive mines drop out of the flying tear, fall to the floor beneath it, sink into a green splash and settle; their red buttons blink")
end)

-- A tear that hits an enemy keeps the mines it laid before, and none lies past
-- the enemy.
conditionsCase("hit", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function()
            clearMines()
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        T().resetEvidence()
        ctx.target = H.target(player, true)
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 30, "target ready")
    plan.act(function(_, ctx)
        ctx.spot = leftSide(Game():GetRoom()) + Vector(190, 0)
        ctx.before = ctx.target.HitPoints
    end)
    fire(plan, "a tear at an enemy", leftSide, 1, function(_, ctx)
        if ctx.target:Exists() then
            ctx.target.Position = ctx.spot
            ctx.target.Velocity = Vector.Zero
        end
    end)
    plan.check("the tear hit the enemy and left its mines short of it", function(_, ctx)
        local loss, list, beyond = ctx.before - ctx.target.HitPoints, minesByX(), 0
        for _, mine in ipairs(list) do
            if mine.Position.X >= ctx.spot.X then beyond = beyond + 1 end
        end
        return loss > 0 and #list >= 1 and beyond == 0,
            string.format("hpLoss=%.2f beyond=%d %s", loss, beyond, describeMines())
    end)
end)

-- Shots along one line never add mines to it: a drop point with a mine within
-- a tile counts as dropped, so two more tears the same way add none.
conditionsCase("gap", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines() end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "one tear", leftSide, 1)
    plan.act(function(_, ctx) ctx.first = #roomMines() end)
    plan.require("the first tear laid mines", function(_, ctx) return ctx.first >= 2, describeMines() end)
    fire(plan, "two more tears the same way", leftSide, 2)
    plan.check("no new mine on the same line", function(_, ctx)
        return #roomMines() == ctx.first and evidence().crowded > 0,
            string.format("first=%d now=%d %s", ctx.first, #roomMines(), describeMines())
    end)
    plan.check("no two mines within a tile", function()
        local list, gap, closest = roomMines(), M().data.gap, math.huge
        for i = 1, #list do
            for j = i + 1, #list do closest = math.min(closest, list[i].Position:Distance(list[j].Position)) end
        end
        return closest >= gap, string.format("closest=%.1f gap=%d", closest, gap)
    end)
end)

-- Three rows of tears from two starts each leave more than the old ten mines,
-- and none goes.
conditionsCase("no_cap", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines() end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    for row = -1, 1 do
        for _, start in ipairs({ 0, 50 }) do
            fire(plan, "a tear on row " .. row .. " from +" .. start, function(room)
                return leftSide(room) + Vector(start, row * 45)
            end, 1)
        end
    end
    plan.check("every mine laid is still there, more than ten", function()
        local e = evidence()
        return #roomMines() > 10 and #roomMines() == e.laid and #M().mines() == e.laid, describeMines()
    end)
end)

-- The spacing is by distance: a faster tear drops its mines just as far apart.
-- How far the tear flies (and so how many it drops) is the engine's, read
-- here at both shot speeds.
conditionsCase("shot_speed", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines() end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a tear at the starting shot speed", leftSide, 1)
    plan.act(function(player, ctx)
        local first, last = ctx.path[1], ctx.path[#ctx.path]
        ctx.slow = { speed = player.ShotSpeed, mines = #roomMines(), flight = last and first and last.x - first.x or -1 }
        clearMines()
        for _ = 1, 3 do player:AddCollectible(CollectibleType.COLLECTIBLE_SPEED_BALL, 0, false) end
    end)
    plan.wait(2)
    plan.require("three Speed Balls raised the shot speed", function(player, ctx)
        return player.ShotSpeed >= ctx.slow.speed + 0.5,
            string.format("shot speed %.2f -> %.2f", ctx.slow.speed, player.ShotSpeed)
    end)
    fire(plan, "a faster tear", leftSide, 1)
    plan.note("flight and mines at both shot speeds", function(player, ctx)
        local first, last = ctx.path[1], ctx.path[#ctx.path]
        return string.format("shot speed %.2f: flew %.0f, %d mines; shot speed %.2f: flew %.0f, %d mines",
            ctx.slow.speed, ctx.slow.flight, ctx.slow.mines, player.ShotSpeed,
            last and first and last.x - first.x or -1, #roomMines())
    end)
    plan.check("the faster tear's mines lie a spacing apart, on its path", function(_, ctx)
        local list, spacing, gaps, step, ok = minesByX(), M().data.spacing, {}, 0, true
        for k = 2, #ctx.path do step = math.max(step, math.abs(ctx.path[k].x - ctx.path[k - 1].x)) end
        for k = 2, #list do
            local gap = list[k].Position.X - list[k - 1].Position.X
            gaps[#gaps + 1] = string.format("%.1f", gap)
            ok = ok and gap >= spacing - 1 and gap <= spacing + step + 1
        end
        local onLine, why = onPath(ctx, list)
        return #list >= 1 and ok and onLine,
            string.format("gaps=[%s] step=%.1f %s %s", table.concat(gaps, " "), step, why or "", describeMines())
    end)
end)

-- Leaving the room leaves its mines behind, and tears in flight as the room is
-- left lay nothing in the next one.
conditionsCase("room_change", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines() end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a tear", leftSide, 1)
    plan.require("mines laid", function() return #roomMines() >= 1, describeMines() end)
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

-- Pits on the tear's first drop point: no mine on them, and that mine drops
-- at the first floor past them instead. Pits stay, so the case runs alone.
S.add("LANDMINE", "pit", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function() clearMines() end }
        give(player, id, 1)
        T().resetEvidence()
        local room = Game():GetRoom()
        ctx.pits = {}
        -- The tear is first seen 20 past the start, so its first drop is due
    -- 120 past it: the pits cover 100..180.
    for _, offset in ipairs({ 120, 160 }) do
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
    plan.require("two pits across the tear's row", function(_, ctx)
        local room = Game():GetRoom()
        for _, index in ipairs(ctx.pits) do
            if room:GetGridCollision(index) ~= GridCollisionClass.COLLISION_PIT then
                return false, "grid " .. index .. " collision " .. tostring(room:GetGridCollision(index))
            end
        end
        ctx.pitLeft = room:GetGridPosition(ctx.pits[1]).X - 20
        ctx.pitRight = room:GetGridPosition(ctx.pits[#ctx.pits]).X + 20
        return true
    end)
    fire(plan, "a tear over the pits", leftSide, 1)
    plan.check("no mine on a pit; the due mine drops at the first floor past them", function(_, ctx)
        local room, onPit, first = Game():GetRoom(), 0, nil
        for _, mine in ipairs(minesByX()) do
            if room:GetGridCollisionAtPos(mine.Position) ~= GridCollisionClass.COLLISION_NONE then onPit = onPit + 1 end
            first = first or mine.Position.X
        end
        local dueOnPit = ctx.path[1] and ctx.path[1].x + M().data.spacing
        return onPit == 0 and first and first >= ctx.pitRight - 1 and first <= ctx.pitRight + 16
            and dueOnPit >= ctx.pitLeft and dueOnPit <= ctx.pitRight and evidence().blocked > 0,
            string.format("onPit=%d first=%s due=%s pits %.0f..%.0f %s", onPit, tostring(first), tostring(dueOnPit),
                ctx.pitLeft, ctx.pitRight, describeMines())
    end)
end)

-- An enemy walking onto an armed mine sets it off: it loses exactly twice the
-- tear's damage; the player standing on the same mine is never hurt, does not
-- set it off, and a rock beside it stays whole.
damageCase("trigger", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function()
            clearMines(); playerHits = nil
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a tear", leftSide, 1)
    plan.act(function() keepFirst(1) end)
    plan.require("one mine kept", function(_, ctx) return onlyMine(ctx), describeMines() end)
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

-- Two mines 50 apart, from tears fired from starts 50 apart: an enemy on one
-- sets off the other a moment later, and both blasts reach it.
damageCase("chain", function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        ctx.cleanupFns = { function()
            clearMines()
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        T().resetEvidence()
    end)
    fire(plan, "a tear", leftSide, 1)
    fire(plan, "a tear 50 further on", function(room) return leftSide(room) + Vector(50, 0) end, 1)
    plan.act(function()
        local list = minesByX()
        for k = 3, #list do list[k]:Remove() end
        M().mines()
    end)
    plan.require("two mines kept close together", function(_, ctx)
        local list = minesByX()
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

-- One run per group: between cases the mines go and S.resetPlayer proves the
-- player is where a fresh run left it. room_change walks into the next room
-- and trigger leaves a rock, so each closes its run; chain runs before trigger.
local function fresh(plan)
    S.resetPlayer(plan, function()
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
