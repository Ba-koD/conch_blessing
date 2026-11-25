local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine): the lifecycle contract and its cases, for the tear that
-- sows mines (user design 2026-11-25). The player really holds the shoot key
-- (the engine reads it through MC_INPUT_ACTION); every tear is the engine's
-- own, recorded here as it is fired, and every mine is the module's own
-- effect in the room (its flight read from its own PositionOffset). Every
-- blast is read from the enemy's actual HP and the player's actual health;
-- the expected numbers are the user's: +40 range, x0.33 damage, -0.2 tears,
-- 3 mines a tear (+1 per 5 luck), a blast of twice the holder's damage. A
-- case keeps one harmless enemy pinned in the corner behind the player (the
-- room stays uncleared and its doors shut), where the tears (fired to the
-- right) never reach it. Mines placed for the blast cases are laid with the
-- module's own `lay`, landing at once where the case needs them.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function M() return ConchBlessing.landmine end
local function T() return M()._test end
local function evidence() return T().evidence() end

-- ---------------------------------------------------------------- observers
-- Every hit the player takes while `playerHits` is a table.
local playerHits
-- Every hit `watched` (GetPtrHash) takes while `targetHits` is a table:
-- { amount, kind = "mine" | "tear" | "other" }.
local targetHits, watched
if ModCallbacks.MC_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
        local attack = source and source.Entity
        if playerHits and entity.Type == EntityType.ENTITY_PLAYER then
            playerHits[#playerHits + 1] = string.format("amt=%.2f flags=%d src=%s", amount, flags,
                attack and string.format("%d.%d", attack.Type, attack.Variant) or "none")
        end
        if targetHits and watched and GetPtrHash(entity) == watched then
            local kind = "other"
            if attack and attack.Type == EntityType.ENTITY_EFFECT and attack.Variant == M().mineVariant() then
                kind = "mine"
            elseif attack and attack.Type == EntityType.ENTITY_TEAR then
                kind = "tear"
            end
            targetHits[#targetHits + 1] = { amount = amount, kind = kind }
        end
    end)
end

-- Every tear the player fires while `fired` is a table: where it started.
local fired
if ModCallbacks.MC_POST_FIRE_TEAR then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
        local spawner = fired and tear.SpawnerEntity
        if spawner and spawner:ToPlayer() then fired[#fired + 1] = Vector(tear.Position.X, tear.Position.Y) end
    end)
end

-- Every laser a player's weapon makes while `lasers` is a number.
local lasers
if ModCallbacks.MC_POST_LASER_INIT then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_LASER_INIT, function(_, laser)
        local spawner = lasers and laser.SpawnerEntity
        if spawner and spawner:ToPlayer() then lasers = lasers + 1 end
    end)
end

local function startShooting(player, ctx)
    ctx.fired = ctx.fired or {}
    fired = ctx.fired
    H.shoot(player, "$tears", ctx)
end

local function stopShooting()
    H.stopShooting()
    fired = nil
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

local function noTears()
    return #Isaac.FindByType(EntityType.ENTITY_TEAR) == 0
end

local function clearMines()
    for _, tear in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR)) do tear:Remove() end
    local carriers = T().carriers()
    for k = #carriers, 1, -1 do carriers[k] = nil end
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
    return string.format("mines=[%s] fired=%d laid=%d flung=%d spilled=%d piled=%d lost=%d landed=%d landedOn=%d "
        .. "exploded=%d byPlayer=%d chained=%d", table.concat(parts, " "), e.fired, e.laid, e.flung, e.spilled, e.piled,
        e.lost, e.landed, e.landedOn, e.exploded, e.byPlayer, e.chained)
end

local sharedConditions, sharedDamage = {}, {}
local conditionsCase = S.caseIn(sharedConditions, "LANDMINE", { conditions = true })
local damageCase = S.caseIn(sharedDamage, "LANDMINE", { damage = true })

local function requireModule(plan)
    plan.require("Landmine module and its mine effect ready", function()
        local m = M()
        return m and m._test and m.available and m.mineVariant() > 0 and ModCallbacks.MC_POST_FIRE_TEAR
            and true or nil, "module missing, effect unregistered or no fire-tear callback"
    end)
end

local function give(player, id, copies)
    while player:GetCollectibleNum(id) < copies do player:AddCollectible(id, 0, false) end
    while player:GetCollectibleNum(id) > copies do player:RemoveCollectible(id) end
end

local function leftSide(room)
    return Vector(room:GetTopLeftPos().X + 60, room:GetCenterPos().Y)
end

-- The bottom-left corner: behind the player, since the tears fly right.
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
            playerHits, targetHits, watched, lasers = nil, nil, nil, nil
            if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        end }
        give(player, id, 1)
        clearMines()
        T().resetEvidence()
        ctx.fired = {}
    end)
end

-- A harmless enemy waits at `place(room, player)` (else in the corner behind
-- the player), so the room has one.
local function withEnemy(plan, place)
    plan.act(function(player, ctx)
        ctx.targetSpot = (place or behind)(Game():GetRoom(), player)
        ctx.target = H.target(player, true)
        pin(ctx)
    end)
    plan.waitUntil(function(_, ctx)
        pin(ctx)
        local ready, why = H.targetReady(ctx.target)
        if not ready then return false, why end
        local alive = Game():GetRoom():GetAliveEnemiesCount()
        return alive > 0, "alive enemies " .. alive
    end, 30, "an enemy waits")
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

-- Waits, the player held where they stand, until every tear is gone, no tear
-- carries a mine any more and every mine has landed.
local function settle(plan)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        track(ctx)
        if ctx.spot then player.Position, player.Velocity = ctx.spot, Vector.Zero end
        if not noTears() then return false, "tears still flying" end
        if #T().carriers() > 0 then return false, #T().carriers() .. " tears still carry mines" end
        local e = evidence()
        return e.landed == e.laid, string.format("%d of %d landed", e.landed, e.laid)
    end, 150, "the tears are gone and every mine has landed")
end

-- The mines laid for each tear fired: `per` each.
local function everyTearCarried(plan, label, per)
    plan.check(label, function(_, ctx)
        local e, shots = evidence(), #ctx.fired
        return shots >= 1 and e.fired == shots and e.laid == per * shots and e.lost == 0 and #roomMines() == e.laid,
            string.format("observed tears=%d per=%d %s", shots, per, describeMines())
    end)
end

-- Waits until every mine laid for a blast case has armed, the player held at
-- `ctx.spot`.
local function armed(plan, label)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        for _, record in ipairs(M().mines()) do
            if not record.armed then return false, "a mine is not armed" end
        end
        return true
    end, 30, label)
end

local function lay(player, spot)
    local _, record = T().lay(player, spot, player.Damage)
    return record
end

-- ---------------------------------------------------------------- lifecycle
local STATS = { "Damage", "Tears", "Range" }

-- The item's share of the displayed stats: the stats while held, less the
-- stats with every copy taken away (the damage as a ratio), then the copies
-- are given back. StatsAPI's damage multiplier follows on the next update.
local function measureShare(plan, id)
    plan.act(function(player, ctx)
        ctx.with = H.stats(player)
        ctx.held = player:GetCollectibleNum(id)
        give(player, id, 0)
    end)
    plan.wait(3)
    plan.act(function(player, ctx)
        local without = H.stats(player)
        ctx.share = { Damage = ctx.with.Damage / without.Damage, Tears = ctx.with.Tears - without.Tears,
            Range = ctx.with.Range - without.Range }
        give(player, id, ctx.held)
    end)
    plan.wait(3)
end

-- n copies: +40 range, x0.33 damage and -0.2 tears once however many, and
-- every tear carries 3 mines; nothing without the item.
C.LANDMINE = { stage = function(plan, id, n)
    requireModule(plan)
    plan.act(function(_, ctx)
        clearMines()
        T().resetEvidence()
        ctx.fired = {}
    end)
    withEnemy(plan)
    measureShare(plan, id)
    plan.check(n > 0 and "+40 range, x0.33 damage and -0.2 tears, once whatever the copies"
        or "without Landmine no stat moves", function(_, ctx)
        local want = n > 0 and { Damage = 0.33, Tears = -0.2, Range = 40 } or { Damage = 1, Tears = 0, Range = 0 }
        local ok, parts = true, {}
        for _, stat in ipairs(STATS) do
            if math.abs(ctx.share[stat] - want[stat]) > 0.005 then ok = false end
            parts[#parts + 1] = string.format("%s %.4f (want %.4f)", stat, ctx.share[stat], want[stat])
        end
        return ok, string.format("%d cop%s: %s", n, n == 1 and "y" or "ies", table.concat(parts, " "))
    end)
    stand(plan, function(room) return leftSide(room) end, 20, true)
    settle(plan)
    if n > 0 then
        everyTearCarried(plan, "every tear the holder fires carries 3 mines", 3)
    else
        plan.check("without Landmine the tears carry nothing", function(_, ctx)
            return #ctx.fired >= 1 and evidence().laid == 0 and #roomMines() == 0,
                string.format("tears=%d %s", #ctx.fired, describeMines())
        end)
    end
    plan.act(function(_, ctx)
        clearMines()
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        ctx.target = nil
    end)
end }

-- ---------------------------------------------------------------- conditions
-- Shooting right in place: each tear flings its 3 mines to both sides of its
-- line as it flies, each seen in the air and landed, a gap apart, holding the
-- player's damage; nobody on them, they stay.
conditionsCase("scatter", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    stand(plan, function(room) return leftSide(room) end, 25, true)
    settle(plan)
    everyTearCarried(plan, "every tear carried 3 mines and all were laid", 3)
    plan.check("flung to both sides of the tears' line, within a tile of it", function(_, ctx)
        local line, above, below, worst = ctx.fired[1] and ctx.fired[1].Y or 0, 0, 0, 0
        for _, mine in ipairs(roomMines()) do
            local off = mine.Position.Y - line
            if off < -2 then above = above + 1 elseif off > 2 then below = below + 1 end
            worst = math.max(worst, math.abs(off))
        end
        return above >= 1 and below >= 1 and worst <= M().data.scatter + 12,
            string.format("above=%d below=%d widest=%.1f line=%.1f", above, below, worst, line)
    end)
    plan.check("no two mines closer than the gap, none piled", function()
        local list, closest = roomMines(), math.huge
        for a = 1, #list do
            for b = a + 1, #list do closest = math.min(closest, list[a].Position:Distance(list[b].Position)) end
        end
        return #list >= 2 and closest >= M().data.gap - 0.5 and evidence().piled == 0,
            string.format("closest=%.1f gap=%d piled=%d", closest, M().data.gap, evidence().piled)
    end)
    plan.check("each mine flew from the tear and landed", function(_, ctx)
        local parts, ok = {}, true
        for _, mine in ipairs(roomMines()) do
            local lift = ctx.lifts[GetPtrHash(mine)] or 0
            parts[#parts + 1] = string.format("%.1f->%.1f", lift, mine.PositionOffset.Y)
            ok = ok and lift <= -5 and mine.PositionOffset.Y == 0
        end
        return #parts >= 1 and ok, "highest->now=[" .. table.concat(parts, " ") .. "]"
    end)
    plan.check("every mine is the player's and holds the player's damage", function(player)
        local bad = 0
        for _, record in ipairs(M().mines()) do
            local owner = record.ref.Ref and record.ref.Ref.SpawnerEntity
            if not owner or GetPtrHash(owner) ~= GetPtrHash(player) or not H.near(record.damage, player.Damage) then
                bad = bad + 1
            end
        end
        return #M().mines() >= 1 and bad == 0, string.format("bad=%d damage=%.3f", bad, player.Damage)
    end)
    plan.wait(20)
    plan.check("armed mines with nobody on them stay", function()
        return evidence().exploded == 0 and #roomMines() == evidence().laid, describeMines()
    end)
    plan.section("LANDMINE / scatter", "each tear flies to the far wall flinging olive mines to both sides; they arc down, land in a green splash and blink")
end)

-- Luck 10: every tear carries 5 mines.
local luckPlayer = nil -- GetPtrHash of the player whose luck the case sets
if ModCallbacks.MC_EVALUATE_CACHE and ConchBlessing.AddPriorityCallback then
    local late = (CallbackPriority and CallbackPriority.LATE) or 100
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, late, function(_, player, flag)
        if luckPlayer and flag == CacheFlag.CACHE_LUCK and GetPtrHash(player) == luckPlayer then player.Luck = 10 end
    end)
end
local function setLuck(player, on)
    luckPlayer = on and GetPtrHash(player) or nil
    player:AddCacheFlags(CacheFlag.CACHE_LUCK)
    player:EvaluateItems()
end

conditionsCase("luck", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    plan.act(function(player, ctx)
        setLuck(player, true)
        table.insert(ctx.cleanupFns, 1, function() setLuck(player, false) end)
    end)
    plan.wait(2)
    plan.require("luck 10", function(player)
        return player.Luck == 10, string.format("luck %.2f", player.Luck)
    end)
    stand(plan, function(room) return leftSide(room) end, 20, true)
    plan.act(function(player) setLuck(player, false) end)
    settle(plan)
    everyTearCarried(plan, "at luck 10 every tear carries 5 mines", 5)
end)

-- Shooting into the right wall from close by: the tear stops at the wall and
-- spills everything it still carries there.
conditionsCase("wall_spill", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    stand(plan, function(room, ctx)
        ctx.wall = room:GetBottomRightPos().X
        return Vector(ctx.wall - 50, room:GetCenterPos().Y)
    end, 15, true)
    settle(plan)
    everyTearCarried(plan, "every mine of every tear was laid", 3)
    plan.check("what the tears still carried spilled by the wall", function(_, ctx)
        local far = 0
        for _, mine in ipairs(roomMines()) do
            if mine.Position.X < ctx.wall - 100 then far = far + 1 end
        end
        local e = evidence()
        return e.spilled >= 1 and far == 0, string.format("wall=%.0f far=%d %s", ctx.wall, far, describeMines())
    end)
end)

-- REPENTOGON: with Brimstone held the holder's attacks are tears; once the
-- item is gone Brimstone's beam comes back.
conditionsCase("tears_only", function(plan, id)
    setup(plan, id)
    plan.require("REPENTOGON weapon types and the laser callback", function(player)
        local repentogon = rawget(_G, "REPENTOGON")
        return type(repentogon) == "table" and repentogon.Real == true and type(player.EnableWeaponType) == "function"
            and ModCallbacks.MC_POST_LASER_INIT and true or nil, "REPENTOGON missing"
    end)
    withEnemy(plan)
    plan.act(function(player, ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE, 0, false)
        lasers = 0
        table.insert(ctx.cleanupFns, 1, function() lasers = nil end)
    end)
    plan.wait(3)
    stand(plan, function(room) return leftSide(room) end, 45, true)
    plan.wait(10)
    plan.check("with Brimstone and Landmine the attacks are tears that carry mines", function(_, ctx)
        return #ctx.fired >= 2 and lasers == 0 and evidence().fired == #ctx.fired,
            string.format("tears=%d lasers=%d %s", #ctx.fired, lasers, describeMines())
    end)
    plan.act(function(player, ctx)
        give(player, id, 0)
        ctx.fired, lasers = {}, 0
        T().resetEvidence()
    end)
    plan.wait(3)
    stand(plan, function(room) return leftSide(room) end, 60, true)
    plan.wait(15)
    plan.check("without Landmine Brimstone's beam is back and nothing carries mines", function(_, ctx)
        return lasers >= 1 and #ctx.fired == 0 and evidence().fired == 0,
            string.format("tears=%d lasers=%d fired=%d", #ctx.fired, lasers, evidence().fired)
    end)
end)

-- WeaponType numbers by name, for the logs.
local WEAPON_NAMES = {}
for name, value in pairs(WeaponType or {}) do WEAPON_NAMES[value] = name:gsub("^WEAPON_", "") end

-- The weapons other than tears `player` has now.
local function otherWeaponsHeld(player)
    local held = {}
    for _, weapon in ipairs(T().otherWeapons()) do
        if player:HasWeaponType(weapon) then held[#held + 1] = WEAPON_NAMES[weapon] or tostring(weapon) end
    end
    return held
end

-- Knives, bombs and Epic Fetus targets in the room: attacks that are no tear.
local function otherAttacks()
    local count = 0
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_KNIFE or entity.Type == EntityType.ENTITY_BOMB
            or (entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == EffectVariant.TARGET) then
            count = count + 1
        end
    end
    return count
end

local function requireWeapons(plan)
    plan.require("REPENTOGON weapon types and the laser callback", function(player)
        local repentogon = rawget(_G, "REPENTOGON")
        return type(repentogon) == "table" and repentogon.Real == true and type(player.EnableWeaponType) == "function"
            and type(player.HasWeaponType) == "function" and ModCallbacks.MC_POST_LASER_INIT and true or nil,
            "REPENTOGON missing"
    end)
end

-- Holds `itemId` with Landmine, shoots for `updates` and checks or (`probe`)
-- only reports what came out, then reads its weapons without Landmine.
local function weaponRound(plan, id, name, itemId, updates, probe)
    plan.act(function(player, ctx)
        player:AddCollectible(itemId, 0, false)
        ctx.fired, lasers = {}, 0
        T().resetEvidence()
    end)
    plan.wait(3)
    local function report(label, fn)
        if probe then plan.note(label, function(player, ctx) return select(2, fn(player, ctx)) end)
        else plan.check(label, fn) end
    end
    report(name .. ": with Landmine its only weapon is tears", function(player)
        local held = otherWeaponsHeld(player)
        return #held == 0 and player:HasWeaponType(WeaponType.WEAPON_TEARS),
            "other weapons=[" .. table.concat(held, " ") .. "] tears=" .. tostring(player:HasWeaponType(WeaponType.WEAPON_TEARS))
    end)
    stand(plan, function(room) return leftSide(room) end, updates, true)
    plan.wait(15)
    report(name .. ": with Landmine its attacks are tears that carry mines", function(_, ctx)
        local others = otherAttacks()
        return #ctx.fired >= 1 and lasers == 0 and others == 0 and evidence().fired == #ctx.fired,
            string.format("tears=%d lasers=%d knives/bombs/targets=%d carried=%d", #ctx.fired, lasers, others,
                evidence().fired)
    end)
    plan.act(function(player, ctx)
        give(player, id, 0)
        clearMines()
        ctx.fired, lasers = {}, 0
    end)
    plan.wait(3)
    if probe then
        stand(plan, function(room) return leftSide(room) end, updates, true)
        plan.wait(15)
        plan.note(name .. ": without Landmine", function(player, ctx)
            return string.format("other weapons=[%s] tears=%d lasers=%d knives/bombs/targets=%d",
                table.concat(otherWeaponsHeld(player), " "), #ctx.fired, lasers, otherAttacks())
        end)
    else
        plan.check(name .. ": without Landmine it has a weapon of its own", function(player)
            local held = otherWeaponsHeld(player)
            return #held >= 1, "other weapons=[" .. table.concat(held, " ") .. "]"
        end)
    end
    plan.act(function(player)
        player:RemoveCollectible(itemId)
        clearMines()
        give(player, id, 1)
    end)
    plan.wait(3)
end

-- REPENTOGON: every item Landmine's EID says it overrides (its row's
-- `eidOverrides`) has a weapon of its own, and with Landmine held its attacks
-- are tears that carry mines, with no beam, knife, bomb or target.
conditionsCase("weapon_items", function(plan, id)
    setup(plan, id)
    requireWeapons(plan)
    withEnemy(plan)
    plan.act(function(_, ctx)
        lasers = 0
        table.insert(ctx.cleanupFns, 1, function() lasers = nil end)
    end)
    local row = ConchBlessing.ItemData.LANDMINE
    local names = row and row.eidOverrides or {}
    plan.require("Landmine's row names the items it overrides", function()
        return #names > 0 or nil, #names .. " names"
    end)
    for _, name in ipairs(names) do
        local itemId = CollectibleType["COLLECTIBLE_" .. name]
        plan.require(name .. " is a collectible", function()
            return type(itemId) == "number" and itemId > 0 or nil, tostring(itemId)
        end)
        weaponRound(plan, id, name, itemId, 30)
    end
end)

-- A measurement, run by name: attacks that may or may not be weapons of their
-- own (lasers that come with tears, charged beams), with and without Landmine.
S.add("LANDMINE", "weapon_probe", { conditions = true }, function(plan, id)
    setup(plan, id)
    requireWeapons(plan)
    withEnemy(plan)
    plan.act(function(_, ctx)
        lasers = 0
        table.insert(ctx.cleanupFns, 1, function() lasers = nil end)
    end)
    for _, name in ipairs({ "TECHNOLOGY_2", "TECH_5", "TECHNOLOGY_ZERO", "MAW_OF_THE_VOID", "REVELATION",
        "C_SECTION" }) do
        local itemId = CollectibleType["COLLECTIBLE_" .. name]
        if type(itemId) == "number" and itemId > 0 then weaponRound(plan, id, name, itemId, 60, true) end
    end
end)
S.rows[#S.rows].manual = true

-- Leaving the room leaves its mines behind; none follows into the next room.
conditionsCase("room_change", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    stand(plan, function(room) return leftSide(room) end, 15, true)
    settle(plan)
    plan.require("mines laid", function() return #roomMines() >= 1, describeMines() end)
    plan.act(function(_, ctx)
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        ctx.target, ctx.spot = nil, nil
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
        return #roomMines() == 0 and #M().mines() == 0 and #T().carriers() == 0, describeMines()
    end)
end)

-- ---------------------------------------------------------------- blasts
-- A blast case watches the enemy's hits from here on. Its HP starts at 1000:
-- at H.target's 100000 the engine's float HP rounds each hit to 1/128.
local function watch(ctx)
    ctx.target.MaxHitPoints, ctx.target.HitPoints = 1000, 1000
    ctx.before = ctx.target.HitPoints
    targetHits, watched = {}, GetPtrHash(ctx.target)
    ctx.hits = targetHits
end

-- Whether the enemy lost exactly what was recorded, every blast twice the
-- holder's damage and every tear hit the holder's damage.
local function exactLoss(ctx, damage)
    local sum, bad, mines = 0, 0, 0
    for _, hit in ipairs(ctx.hits or {}) do
        sum = sum + hit.amount
        if hit.kind == "mine" then
            mines = mines + 1
            if not H.near(hit.amount, 2 * damage) then bad = bad + 1 end
        elseif hit.kind == "tear" then
            if not H.near(hit.amount, damage) then bad = bad + 1 end
        else
            bad = bad + 1
        end
    end
    local loss = ctx.before - ctx.target.HitPoints
    return H.near(loss, sum) and bad == 0, mines,
        string.format("loss=%.4f recorded=%.4f blasts=%d bad=%d damage=%.4f", loss, sum, mines, bad, damage)
end

-- Shooting at an enemy two and a half tiles away: what a tear still carries
-- spills around it, and a mine landing on it goes off at once. The tears
-- keep coming until one has.
damageCase("on_enemy", function(plan, id)
    setup(plan, id)
    withEnemy(plan, function(room) return leftSide(room) + Vector(100, 0) end)
    plan.act(function(player, ctx)
        ctx.spot = leftSide(Game():GetRoom())
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        ctx.damage = player.Damage
        watch(ctx)
        startShooting(player, ctx)
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        return evidence().landedOn >= 1, describeMines()
    end, 300, "a mine lands on the enemy")
    plan.act(function() stopShooting() end)
    settle(plan)
    plan.wait(12)
    plan.check("a mine that landed on the enemy went off at once", function()
        local e = evidence()
        return e.landedOn >= 1 and e.spilled >= 1, describeMines()
    end)
    plan.check("the enemy lost exactly its tear hits and twice the damage for every blast", function(_, ctx)
        local ok, blasts, detail = exactLoss(ctx, ctx.damage)
        return ok and blasts >= 1, detail
    end)
    plan.section("LANDMINE / on_enemy", "tears hit the maggot and burst into mines around it; those landing on it blow up in green at once")
end)

-- A player walking onto an armed mine sets it off and takes no damage; the
-- enemy beside it loses twice the holder's damage.
damageCase("player_steps", function(plan, id)
    setup(plan, id)
    withEnemy(plan, function(room) return leftSide(room) + Vector(154, 0) end)
    plan.act(function(player, ctx)
        ctx.spot = leftSide(Game():GetRoom())
        ctx.mineSpot = ctx.spot + Vector(120, 0)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        ctx.damage = player.Damage
        lay(player, ctx.mineSpot)
    end)
    armed(plan, "the mine is armed with nobody on it")
    plan.require("one armed mine, the enemy within its blast but not on it", function(_, ctx)
        local reach = M().data.triggerRadius + ctx.target.Size
        local gap = ctx.target.Position:Distance(ctx.mineSpot)
        return #roomMines() == 1 and evidence().exploded == 0 and gap > reach and gap <= M().data.blastRadius + ctx.target.Size,
            string.format("enemy %.1f from the mine, reach %.1f %s", gap, reach, describeMines())
    end)
    plan.act(function(player, ctx)
        ctx.health = health(player)
        playerHits = {}
        watch(ctx)
        ctx.spot = ctx.mineSpot
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        return evidence().exploded >= 1, "waiting for the player to set it off"
    end, 10, "the player steps on the mine")
    plan.wait(3)
    plan.check("the player set it off", function()
        local e = evidence()
        return e.byPlayer == 1 and e.exploded == 1 and #roomMines() == 0, describeMines()
    end)
    plan.check("the enemy beside it lost exactly twice the holder's damage", function(_, ctx)
        local ok, blasts, detail = exactLoss(ctx, ctx.damage)
        return ok and blasts == 1, detail
    end)
    plan.check("the player was not hurt", function(player, ctx)
        local hits = playerHits or {}
        return #hits == 0 and health(player) == ctx.health,
            string.format("playerHits=[%s] health %d -> %d", table.concat(hits, "; "), ctx.health, health(player))
    end)
end)

-- Two mines 30 apart: an enemy on one sets off the other a moment later, and
-- both blasts reach it.
damageCase("chain", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    plan.act(function(player, ctx)
        ctx.spot = leftSide(Game():GetRoom())
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        ctx.damage = player.Damage
        ctx.mineSpot = ctx.spot + Vector(200, 0)
        lay(player, ctx.mineSpot)
        lay(player, ctx.mineSpot + Vector(0, 30))
    end)
    armed(plan, "both mines are armed")
    plan.act(function(_, ctx)
        watch(ctx)
        ctx.targetSpot = ctx.mineSpot
    end)
    plan.waitUntil(function(player, ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        if evidence().exploded == 0 then pin(ctx) end
        if ctx.target:Exists() then ctx.target.Velocity = Vector.Zero end
        return evidence().exploded >= 2, "exploded " .. evidence().exploded
    end, 30, "both mines go off")
    plan.wait(3)
    plan.check("the second mine went off from the first one's blast", function()
        local e = evidence()
        return e.chained == 1 and e.exploded == 2 and #roomMines() == 0, describeMines()
    end)
    plan.check("both blasts reached the enemy, twice the holder's damage each", function(_, ctx)
        local ok, blasts, detail = exactLoss(ctx, ctx.damage)
        return ok and blasts == 2, detail
    end)
end)

-- An enemy walking onto an armed mine sets it off: it loses exactly twice the
-- holder's damage, the player far off is not hurt and a rock beside it stays
-- whole.
damageCase("trigger", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    plan.act(function(player, ctx)
        ctx.spot = leftSide(Game():GetRoom())
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        ctx.damage = player.Damage
        ctx.mineSpot = ctx.spot + Vector(200, 0)
        lay(player, ctx.mineSpot)
        local room = Game():GetRoom()
        ctx.rockIndex = room:GetGridIndex(ctx.mineSpot + Vector(0, 40))
        ctx.rockPlaced = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
    end)
    armed(plan, "the mine is armed")
    plan.act(function(player, ctx)
        ctx.health = health(player)
        playerHits = {}
        watch(ctx)
        ctx.targetSpot = ctx.mineSpot
    end)
    plan.waitUntil(function(player, ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        if evidence().exploded > 0 then return true end
        pin(ctx)
        return false, "waiting for the enemy to set it off"
    end, 30, "the enemy steps on the mine")
    plan.wait(3)
    plan.check("the enemy lost exactly twice the holder's damage", function(_, ctx)
        local ok, blasts, detail = exactLoss(ctx, ctx.damage)
        return ok and blasts == 1 and evidence().byPlayer == 0, detail
    end)
    plan.check("the player was not hurt", function(player, ctx)
        local hits = playerHits or {}
        return #hits == 0 and health(player) == ctx.health,
            string.format("playerHits=[%s] health %d -> %d", table.concat(hits, "; "), ctx.health, health(player))
    end)
    plan.check("a rock beside the mine is still whole", function(_, ctx)
        local room = Game():GetRoom()
        local grid = room:GetGridEntity(ctx.rockIndex)
        local solid = room:GetGridCollision(ctx.rockIndex) ~= GridCollisionClass.COLLISION_NONE
        return ctx.rockPlaced and grid and grid:GetType() == GridEntityType.GRID_ROCK and solid,
            string.format("placed=%s type=%s solid=%s", tostring(ctx.rockPlaced), tostring(grid and grid:GetType()),
                tostring(solid))
    end)
    plan.section("LANDMINE / trigger", "a small green explosion where the maggot stepped on the mine")
end)

-- One run per group: between cases the mines go and S.resetPlayer proves the
-- player is where a fresh run left it. room_change walks into the next room
-- and trigger leaves a rock, so each closes its run.
local function fresh(plan)
    S.resetPlayer(plan, function()
        stopShooting()
        clearMines()
        playerHits, targetHits, watched, lasers = nil, nil, nil, nil
    end, function()
        return #M().mines() == 0 and #roomMines() == 0 and #T().carriers() == 0, describeMines()
    end)
    plan.act(function() T().resetEvidence() end)
end
S.last(sharedConditions, "room_change")
S.last(sharedDamage, "trigger")
S.sequenceBundle("LANDMINE", "shared_conditions", { conditions = true }, sharedConditions, function(plan) fresh(plan) end)
S.sequenceBundle("LANDMINE", "shared_damage", { damage = true }, sharedDamage, function(plan) fresh(plan) end)

return C
