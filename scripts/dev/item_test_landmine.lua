local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine): the lifecycle contract and its cases, for the tear that
-- sows mines (user designs 2026-11-25 and 2026-11-27). The player really holds the shoot key
-- (the engine reads it through MC_INPUT_ACTION); every tear is the engine's
-- own, recorded here as it is fired, and every mine is the module's own
-- record (its flight read from its own height; one field effect draws them
-- all). Every
-- blast is read from the enemy's actual HP and the player's actual health;
-- the expected numbers are the user's: +40 range, x0.33 damage, x0.8 tears, -0.2 shot speed,
-- mines laid 2 times a tear (+1 per 5 luck), every 0.2 s, one mine at a time
-- per copy, all of them again 5 fire intervals after a tear runs out, a blast
-- of the holder's damage carrying the holder's bomb flags on one mine in ten,
-- and one mine in ten a rusted dud that goes off as a real bomb. Every
-- case lays no dud of its own accord (its chance is held at 0 while it runs)
-- and `bomb_synergies` sets each mine's roll on its item's tenth, so each
-- case sees the mines it lays; `dud` lays its dud itself. A
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
            if T().blasting() then
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

-- The mines in the room: the module's live records.
local function roomMines()
    return M().mines()
end

-- The field effects in the room (NO_QUERY included): one while mines lie there.
local function fields()
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
    T().clear()
end

local function health(player)
    return player:GetHearts() + player:GetSoulHearts() + player:GetBlackHearts() + player:GetBoneHearts()
end

local function describeMines()
    local parts = {}
    for _, mine in ipairs(roomMines()) do
        parts[#parts + 1] = string.format("%.0f,%.0f", mine.x, mine.y)
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

-- The highest each mine was seen above the floor (its height is negative
-- upward, as PositionOffset).
local function track(ctx)
    ctx.lifts = ctx.lifts or {}
    for _, mine in ipairs(roomMines()) do
        ctx.lifts[mine] = math.min(ctx.lifts[mine] or 0, mine.z or 0)
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
        -- No dud of its own accord: a case lays the duds it wants.
        local d = M().data
        local dudChance = d.dudChance
        d.dudChance = 0
        table.insert(ctx.cleanupFns, function() d.dudChance = dudChance end)
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
-- (a tear still flying 5 fire intervals after its first mine holds `per`
-- again: -0.2 shot speed keeps tears up long enough, user decision 2026-11-28)
local function everyTearCarried(plan, label, per)
    plan.check(label, function(_, ctx)
        local e, shots = evidence(), #ctx.fired
        return shots >= 1 and e.fired == shots and e.laid == per * (shots + e.reloads) and e.lost == 0
            and #roomMines() == e.laid,
            string.format("observed tears=%d per=%d reloads=%d %s", shots, per, e.reloads, describeMines())
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
    return T().lay(player, spot, player.Damage)
end

-- ---------------------------------------------------------------- lifecycle
local STATS = { "Damage", "Tears", "Range", "ShotSpeed" }

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
        ctx.share = { Damage = ctx.with.Damage / without.Damage, Tears = ctx.with.Tears / without.Tears,
            Range = ctx.with.Range - without.Range, ShotSpeed = ctx.with.ShotSpeed - without.ShotSpeed }
        give(player, id, ctx.held)
    end)
    plan.wait(3)
end

-- n copies: +40 range, x0.33 damage, x0.8 tears and -0.2 shot speed once however many, and
-- every tear lays n mines 2 times; nothing without the item.
C.LANDMINE = { stage = function(plan, id, n)
    requireModule(plan)
    plan.act(function(_, ctx)
        clearMines()
        T().resetEvidence()
        ctx.fired = {}
    end)
    withEnemy(plan)
    measureShare(plan, id)
    plan.check(n > 0 and "+40 range, x0.33 damage, x0.8 tears and -0.2 shot speed, once whatever the copies"
        or "without Landmine no stat moves", function(_, ctx)
        local want = n > 0 and { Damage = 0.33, Tears = 0.8, Range = 40, ShotSpeed = -0.2 }
            or { Damage = 1, Tears = 1, Range = 0, ShotSpeed = 0 }
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
        everyTearCarried(plan, string.format("every tear the holder fires lays %d mines 2 times", n), 2 * n)
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
-- Shooting right in place: each tear lays its 2 mines, one at a time to
-- alternating sides of its line, as it flies, each seen in the air and
-- landed, a gap apart, holding the player's damage; nobody on them, they stay.
conditionsCase("scatter", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    -- 330 from the right wall, which a tear reaches before it refills (-0.2
    -- shot speed, 2026-11-28), so nothing spills there
    stand(plan, function(room) return Vector(room:GetBottomRightPos().X - 330, room:GetCenterPos().Y) end, 25, true)
    settle(plan)
    everyTearCarried(plan, "every tear held 2 mines and all were laid", 2)
    plan.check("one mine went down at a time with one copy", function()
        local e = evidence()
        return e.placed >= 1 and e.flung == e.placed, string.format("drops=%d flung=%d", e.placed, e.flung)
    end)
    plan.check("flung to both sides of the tears' line, within a tile of it", function(_, ctx)
        local line, above, below, worst = ctx.fired[1] and ctx.fired[1].Y or 0, 0, 0, 0
        for _, mine in ipairs(roomMines()) do
            local off = mine.y - line
            if off < -2 then above = above + 1 elseif off > 2 then below = below + 1 end
            worst = math.max(worst, math.abs(off))
        end
        return above >= 1 and below >= 1 and worst <= M().data.scatter + 12,
            string.format("above=%d below=%d widest=%.1f line=%.1f", above, below, worst, line)
    end)
    plan.check("no two mines closer than the gap, none piled", function()
        local list, closest = roomMines(), math.huge
        for a = 1, #list do
            for b = a + 1, #list do closest = math.min(closest, list[a].spot:Distance(list[b].spot)) end
        end
        return #list >= 2 and closest >= M().data.gap - 0.5 and evidence().piled == 0,
            string.format("closest=%.1f gap=%d piled=%d", closest, M().data.gap, evidence().piled)
    end)
    plan.check("each mine flew from the tear and landed", function(_, ctx)
        local parts, ok = {}, true
        for _, mine in ipairs(roomMines()) do
            local lift = ctx.lifts[mine] or 0
            parts[#parts + 1] = string.format("%.1f->%.1f", lift, mine.z)
            ok = ok and lift <= -5 and mine.z == 0
        end
        return #parts >= 1 and ok, "highest->now=[" .. table.concat(parts, " ") .. "]"
    end)
    plan.check("one field effect draws every mine, and nothing else of the mine's variant lies there", function()
        local list, own, e = fields(), T().field(), evidence()
        return #list == 1 and own ~= nil and GetPtrHash(list[1]) == GetPtrHash(own) and e.drawn >= 1
            and e.drawnMines == #roomMines(), string.format("fields=%d draws=%d last drew %d of %d mines", #list,
                e.drawn, e.drawnMines, #roomMines())
    end)
    plan.check("every mine is the player's and holds the player's damage", function(player)
        local bad = 0
        for _, record in ipairs(M().mines()) do
            local owner = record.owner and record.owner.Ref
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

-- Luck 10: every tear lays 4 times.
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
    -- luck stays 10 until every mine is down: a tear that refills holds what
    -- its holder's luck gives then
    stand(plan, function(room) return leftSide(room) end, 20, true)
    settle(plan)
    everyTearCarried(plan, "at luck 10 every tear lays 4 mines", 4)
    plan.act(function(player) setLuck(player, false) end)
end)

-- Shooting into the right wall from close by: the tear stops at the wall and
-- spills everything it still carries there. The player stands 80 away, out of
-- reach of the spill (40 around the stop), so nobody steps on it.
conditionsCase("wall_spill", function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    stand(plan, function(room, ctx)
        ctx.wall = room:GetBottomRightPos().X
        -- close enough that a tear (2 mines, the second 9 updates out) reaches
        -- the wall still holding one
        return Vector(ctx.wall - 45, room:GetCenterPos().Y)
    end, 15, true)
    settle(plan)
    everyTearCarried(plan, "every mine of every tear was laid", 2)
    plan.check("what the tears still carried spilled by the wall", function(_, ctx)
        local far = 0
        for _, mine in ipairs(roomMines()) do
            if mine.x < ctx.wall - 100 then far = far + 1 end
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

-- REPENTOGON: the weapons that shoot tears stay with Landmine held (user
-- decision 2026-11-27), and their tears lay mines like any other: Ludovico's
-- one tear lays its 3 mines, waits 5 fire intervals and lays them again.
local TEAR_WEAPONS = {
    { "LUDOVICO_TECHNIQUE", "WEAPON_LUDOVICO_TECHNIQUE", 120 },
    -- The Lung charges longer at Landmine's lower tears: at -0.2 tears 60
    -- updates were not enough to fire and 150 were (`lung_probe`, 2026-11-27);
    -- x0.8 tears (2026-11-28) is slower again.
    { "MONSTROS_LUNG", "WEAPON_MONSTROS_LUNGS", 200 },
    { "C_SECTION", "WEAPON_FETUS", 60 },
}
conditionsCase("tear_weapons", function(plan, id)
    setup(plan, id)
    requireWeapons(plan)
    withEnemy(plan)
    plan.act(function(_, ctx)
        lasers = 0
        table.insert(ctx.cleanupFns, 1, function() lasers = nil end)
    end)
    for _, entry in ipairs(TEAR_WEAPONS) do
        local name, weaponName, updates = entry[1], entry[2], entry[3]
        local itemId, weapon = CollectibleType["COLLECTIBLE_" .. name], WeaponType and WeaponType[weaponName]
        plan.require(name .. " is a collectible with its weapon type", function()
            return type(itemId) == "number" and itemId > 0 and type(weapon) == "number" or nil,
                tostring(itemId) .. " " .. tostring(weapon)
        end)
        plan.act(function(player, ctx)
            player:AddCollectible(itemId, 0, false)
            ctx.fired, lasers = {}, 0
            clearMines()
            T().resetEvidence()
        end)
        plan.wait(3)
        plan.check(name .. ": with Landmine its weapon stays, with no plain tears beside it", function(player)
            local held = otherWeaponsHeld(player)
            local plain = player:HasWeaponType(WeaponType.WEAPON_TEARS)
            return player:HasWeaponType(weapon) and not plain, string.format("%s=%s tears=%s other weapons=[%s]",
                weaponName, tostring(player:HasWeaponType(weapon)), tostring(plain), table.concat(held, " "))
        end)
        stand(plan, function(room) return leftSide(room) end, updates, true)
        plan.wait(20) -- Monstro's Lung fires its burst as the key is let go
        plan.check(name .. ": its tears lay mines, and no beam", function()
            local e = evidence()
            return e.fired >= 1 and e.placed >= 1 and e.laid >= 1 and lasers == 0,
                string.format("tears=%d pairs=%d reloads=%d lasers=%d %s", e.fired, e.placed, e.reloads, lasers,
                    describeMines())
        end)
        if name == "LUDOVICO_TECHNIQUE" then
            plan.check("Ludovico's tear refilled after it ran out and laid again", function(player)
                local e = evidence()
                return e.reloads >= 1 and e.laid >= 4, string.format("reloads=%d laid=%d wait=%.0f updates",
                    e.reloads, e.laid, T().reloadDelay(player.MaxFireDelay))
            end)
        end
        plan.act(function(player)
            player:RemoveCollectible(itemId)
            clearMines()
        end)
        plan.wait(3)
    end
end)

-- The bomb synergies (user design 2026-11-27): a mine's fake explosion carries
-- the holder's bomb flags. For each bomb item: a mine laid on a pinned enemy
-- goes off, and the item's own mark shows (a cross of blasts, a status on the
-- enemy, Sad Bombs' tears that lay no mines, four short Brimstone beams that
-- miss an enemy three tiles away, a Purgatory soul that bursts on the enemy,
-- small scatter blasts, a random flag, or, with Bobby-Bomb, a mine creeping to
-- the enemy); every time the player is unhurt and a rock beside the mine stays.
local BOMB_SYNERGIES = {
    { "BOMBER_BOY", "bomber_boy" }, { "HOT_BOMBS", "hot_bombs" }, { "BOBS_CURSE", "bobs_curse" },
    { "SAD_BOMBS", "sad_bombs" }, { "SCATTER_BOMBS", "scatter_bombs" }, { "BRIMSTONE_BOMBS", "brimstone_bombs" },
    { "GHOST_BOMBS", "ghost_bombs" }, { "STICKY_BOMBS", "sticky_bombs" }, { "BUTT_BOMBS", "butt_bombs" },
    { "NANCY_BOMBS", "nancy_bombs" }, { "BOBBY_BOMB", "bobby_bomb" },
}
local SYNERGY_NAMES = {}
for _, entry in ipairs(BOMB_SYNERGIES) do SYNERGY_NAMES[#SYNERGY_NAMES + 1] = entry[2] end

local function bombRound(plan, itemName, key)
    local label = key
    local crawls = key == "bobby_bomb"
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        ctx.itemId = CollectibleType["COLLECTIBLE_" .. itemName]
        player:AddCollectible(ctx.itemId, 0, false)
        clearMines()
        T().resetEvidence()
        ctx.spot = Vector(room:GetCenterPos().X + 60, room:GetCenterPos().Y)
        player.Position, player.Velocity = ctx.spot + Vector(-160, 80), Vector.Zero
        ctx.health = health(player)
        ctx.rockIndex = room:GetGridIndex(ctx.spot + Vector(0, -80))
        room:RemoveGridEntity(ctx.rockIndex, 0, false)
        ctx.rockMade = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
        ctx.target = H.target(player, true)
        ctx.targetSpot = crawls and ctx.spot + Vector(110, 0) or ctx.spot
        pin(ctx)
        ctx.seen, ctx.statuses, ctx.tears, ctx.lasers, ctx.souls = {}, {}, 0, 0, 0
        ctx.reach, ctx.bursts, ctx.longSouls = {}, 0, 0
        -- Brimstone Bombs: an enemy 120 along the beam to the right, past its reach
        if key == "brimstone_bombs" then
            ctx.far = H.target(player, true)
            ctx.farSpot = ctx.spot + Vector(120, 0)
        end
        for _, entity in ipairs(Isaac.GetRoomEntities()) do ctx.seen[GetPtrHash(entity)] = true end
        playerHits = {}
    end)
    local function pinFar(ctx)
        if ctx.far and ctx.far:Exists() then ctx.far.Position, ctx.far.Velocity = ctx.farSpot, Vector.Zero end
    end
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        pinFar(ctx)
        if ctx.far and not H.targetReady(ctx.far) then return false, "far enemy" end
        return H.targetReady(ctx.target)
    end, 30, label .. ": an enemy waits")
    plan.act(function(player, ctx)
        ctx.mine = lay(player, ctx.spot)
        -- The mine's roll falls on this item's tenth (Bobby-Bomb needs none).
        if ctx.mine and T().slotRoll(key) then ctx.mine.bombRoll = T().slotRoll(key) end
        -- Bomber Boy: a second mine 75 away, past the mine's own blast but inside its arm's.
        if key == "bomber_boy" then ctx.extra = lay(player, ctx.spot + Vector(75, 0)) end
        ctx.firedBefore = evidence().fired
        ctx.hpBefore = ctx.target and ctx.target.HitPoints
        ctx.farBefore = ctx.far and ctx.far.HitPoints
        ctx.until_ = Game():GetFrameCount() + ((crawls or key == "ghost_bombs") and 240 or 90)
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        pinFar(ctx)
        player.Position, player.Velocity = ctx.spot + Vector(-160, 80), Vector.Zero
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local hash = GetPtrHash(entity)
            if not ctx.seen[hash] then
                ctx.seen[hash] = true
                if entity.Type == EntityType.ENTITY_TEAR then ctx.tears = ctx.tears + 1 end
                if entity.Type == EntityType.ENTITY_LASER then ctx.lasers = ctx.lasers + 1 end
                if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == (EffectVariant.PURGATORY or 189)
                    and entity.SubType == 1 then ctx.souls = ctx.souls + 1 end
                if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == (EffectVariant.HUNGRY_SOUL or 186) then
                    ctx.longSouls = ctx.longSouls + 1
                end
                if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == (EffectVariant.ENEMY_GHOST or 144)
                    and entity.SubType == 1 then ctx.bursts = ctx.bursts + 1 end
            end
            -- how far each beam reaches, the most seen once it has been
            -- updated (its end point reads (0, 0) before its first update)
            local laser = entity.Type == EntityType.ENTITY_LASER and entity:ToLaser()
            if laser and laser.FrameCount >= 1 and type(laser.GetEndPoint) == "function" then
                local finish = laser:GetEndPoint()
                if finish.X ~= 0 or finish.Y ~= 0 then
                    ctx.reach[hash] = math.max(ctx.reach[hash] or 0, laser.Position:Distance(finish))
                end
            end
        end
        local target = ctx.target
        if target and target:Exists() then
            for _, name in ipairs({ "FLAG_BURN", "FLAG_POISON", "FLAG_SLOW", "FLAG_CONFUSION" }) do
                if EntityFlag[name] and target:HasEntityFlags(EntityFlag[name]) then ctx.statuses[name] = true end
            end
        end
        if crawls and ctx.mine and not ctx.mine.dead then
            ctx.closest = math.min(ctx.closest or math.huge, ctx.mine.spot:Distance(ctx.targetSpot))
        end
        return Game():GetFrameCount() >= ctx.until_, "watching"
    end, 280, label .. ": the mine went off and its effects played")
    -- Which tear flags the item puts on the player's bombs (a record for the
    -- slot table in landmine.lua).
    plan.note(label .. ": the bomb flags held", function(player)
        local flags, names = player:GetBombFlags(), {}
        for name, value in pairs(TearFlags) do
            if name ~= "TEAR_NORMAL" then
                local ok, set = pcall(function() return (flags & value) == value end)
                if ok and set then names[#names + 1] = name end
            end
        end
        table.sort(names)
        return table.concat(names, " ")
    end)
    plan.check(label .. ": the mine went off on the enemy", function(_, ctx)
        local e = evidence()
        return e.exploded >= 1 and e.struck >= 1, describeMines()
    end)
    local checks = {
        bomber_boy = { "two more blasts along each arm of a cross, setting off the mine 75 away", function(_, ctx)
            return evidence().crossed >= 4 and ctx.extra ~= nil and ctx.extra.dead == true,
                string.format("crossed=%d pictures=%d chained=%d extra gone=%s", evidence().crossed,
                    evidence().pictures, evidence().chained, tostring(ctx.extra and ctx.extra.dead))
        end },
        hot_bombs = { "the enemy burned", function(_, ctx) return ctx.statuses.FLAG_BURN == true, "burn" end },
        bobs_curse = { "the enemy was poisoned", function(_, ctx) return ctx.statuses.FLAG_POISON == true, "poison" end },
        sad_bombs = { "tears burst out and laid no mines", function(_, ctx)
            local e = evidence()
            return ctx.tears >= 8 and e.fired == ctx.firedBefore and #roomMines() == 0,
                string.format("tears=%d tracked=%d mines=%d", ctx.tears, e.fired - ctx.firedBefore, #roomMines())
        end },
        scatter_bombs = { "small blasts went off around it", function()
            return evidence().scattered >= 2, string.format("scattered=%d", evidence().scattered)
        end },
        brimstone_bombs = { "four short beams, none reaching the enemy 120 away", function(_, ctx)
            local reaches, longest = {}, 0
            for _, reach in pairs(ctx.reach) do
                reaches[#reaches + 1] = string.format("%.0f", reach)
                longest = math.max(longest, reach)
            end
            local farLost = (ctx.farBefore or 0) - (ctx.far and ctx.far:Exists() and ctx.far.HitPoints or 0)
            local nearLost = (ctx.hpBefore or 0) - (ctx.target and ctx.target:Exists() and ctx.target.HitPoints or 0)
            return ctx.lasers == 4 and evidence().beams == 4 and #reaches == 4 and longest <= 60 and farLost == 0
                and nearLost > 0,
                string.format("lasers=%d reaches=[%s] nearLost=%.2f farLost=%.2f", ctx.lasers,
                    table.concat(reaches, " "), nearLost, farLost)
        end },
        ghost_bombs = { "a Purgatory soul burst on the enemy for half the mine's damage", function(_, ctx)
            local lost = (ctx.hpBefore or 0) - (ctx.target and ctx.target:Exists() and ctx.target.HitPoints or 0)
            -- the blast, then the ghost's one hit of half of it
            local blast = T().mineDamage(ctx.mine and ctx.mine.damage or 0)
            local expected = blast * (1 + M().data.ghostDamage)
            return ctx.souls >= 1 and evidence().ghosts >= 1 and ctx.bursts >= 1 and ctx.longSouls == 0
                and math.abs(lost - expected) <= 0.01 * expected,
                string.format("souls=%d bursts=%d hungrySouls=%d enemyLost=%.3f expected=%.3f (blast %.3f)",
                    ctx.souls, ctx.bursts, ctx.longSouls, lost, expected, blast)
        end },
        sticky_bombs = { "the enemy was slowed", function(_, ctx) return ctx.statuses.FLAG_SLOW == true, "slow" end },
        butt_bombs = { "the enemy was confused", function(_, ctx) return ctx.statuses.FLAG_CONFUSION == true, "confusion" end },
        nancy_bombs = { "the mine carried a bomb flag", function()
            local flags = evidence().flags
            local some = flags ~= nil and TearFlags and flags ~= TearFlags.TEAR_NORMAL
            return some == true and evidence().flagEffects >= 1, "flagEffects=" .. evidence().flagEffects
        end },
        bobby_bomb = { "the mine stood up and crept to the enemy", function(_, ctx)
            local e = evidence()
            return e.crawled >= 20 and (ctx.closest or math.huge) < 100 and ctx.mine.legs == true,
                string.format("crawled=%d closest=%.1f legs=%s", e.crawled, ctx.closest or -1, tostring(ctx.mine.legs))
        end },
    }
    local check = checks[key]
    plan.check(label .. ": " .. check[1], check[2])
    plan.check(label .. ": the player was not hurt", function(player, ctx)
        return #playerHits == 0 and health(player) == ctx.health,
            string.format("hits=[%s] health %d -> %d", table.concat(playerHits, " "), ctx.health, health(player))
    end)
    plan.check(label .. ": a rock beside the mine is still whole", function(_, ctx)
        local grid = Game():GetRoom():GetGridEntity(ctx.rockIndex)
        return ctx.rockMade and grid ~= nil and grid.State ~= 2,
            grid and string.format("state=%d", grid.State) or "gone"
    end)
    plan.act(function(player, ctx)
        playerHits = nil
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        if ctx.far and ctx.far:Exists() then ctx.far:Remove() end
        ctx.target, ctx.far = nil, nil
        clearMines()
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local t = entity.Type
            if t == EntityType.ENTITY_LASER or t == EntityType.ENTITY_PICKUP or t == EntityType.ENTITY_BOMB
                or (t == EntityType.ENTITY_EFFECT and entity.Variant ~= M().mineVariant())
                or (t == EntityType.ENTITY_FAMILIAR and entity.Variant == FamiliarVariant.BLUE_SPIDER) then
                entity:Remove()
            end
        end
        Game():GetRoom():RemoveGridEntity(ctx.rockIndex, 0, false)
        player:RemoveCollectible(ctx.itemId)
    end)
    plan.wait(5)
end

S.add("LANDMINE", "bomb_synergies", { synergies = true, conditions = true }, function(plan, id)
    setup(plan, id)
    plan.require("REPENTOGON's bomb parts", function()
        local game = Game()
        return type(game.BombDamage) == "function" and type(game.BombTearflagEffects) == "function" or nil,
            "Game():BombDamage or BombTearflagEffects missing"
    end)
    plan.act(function(_, ctx)
        table.insert(ctx.cleanupFns, 1, function() playerHits = nil end)
    end)
    for _, entry in ipairs(BOMB_SYNERGIES) do
        local itemName, key = entry[1], entry[2]
        plan.require(key .. ": " .. itemName .. " is a collectible", function()
            return type(CollectibleType["COLLECTIBLE_" .. itemName]) == "number" or nil, itemName
        end)
        bombRound(plan, itemName, key)
    end
end, SYNERGY_NAMES)

-- A measurement, run by name: what a mine's blast would do as the engine's own
-- explosion carrying the player's bomb flags, for each vanilla bomb item (and
-- none). Each route goes off at one spot with a pinned target 30 units away, a
-- rock 50 units away and the player 45 units away (their damage is cancelled
-- and counted): "effects" is Game():BombExplosionEffects with the flags,
-- "bomb" a bomb of the player's that explodes at once. Logs the target's HP
-- lost, the status flags it showed, what appeared in the room, whether the
-- rock broke and the hits the player would have taken.
local probeShield -- hits on the player cancelled while the probe runs
if ModCallbacks.MC_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, _, _, source)
        if probeShield and entity.Type == EntityType.ENTITY_PLAYER then
            local attack = source and source.Entity
            probeShield[#probeShield + 1] = attack and string.format("%d.%d", attack.Type, attack.Variant) or "none"
            return false
        end
    end)
end

local BOMB_ITEMS = { "NONE", "BOMBER_BOY", "MR_MEGA", "HOT_BOMBS", "BOBS_CURSE", "SAD_BOMBS", "SCATTER_BOMBS",
    "BRIMSTONE_BOMBS", "GHOST_BOMBS", "STICKY_BOMBS", "BUTT_BOMBS", "GLITTER_BOMBS", "NANCY_BOMBS", "BOBBY_BOMB" }
local STATUS = { "FLAG_BURN", "FLAG_POISON", "FLAG_SLOW", "FLAG_CONFUSION", "FLAG_CHARM", "FLAG_FEAR", "FLAG_MIDAS_FREEZE",
    "FLAG_FREEZE", "FLAG_SHRINK", "FLAG_BLEED_OUT", "FLAG_ICE" }

local function flagsText(flags)
    local ok, text = pcall(function()
        if type(flags) == "number" then return string.format("%d", flags) end
        return string.format("l=%s h=%s", tostring(flags.l), tostring(flags.h))
    end)
    return ok and text or tostring(flags)
end

local function probeRound(plan, itemName, route)
    local label = itemName .. " / " .. route
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        ctx.spot = Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y)
        ctx.itemId = itemName ~= "NONE" and CollectibleType["COLLECTIBLE_" .. itemName] or nil
        if ctx.itemId then player:AddCollectible(ctx.itemId, 0, false) end
        player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
        ctx.target = H.target(player, true)
        ctx.targetSpot = ctx.spot + Vector(30, 0)
        pin(ctx)
        local rockAt = ctx.spot + Vector(0, -50)
        ctx.rockIndex = room:GetGridIndex(rockAt)
        room:RemoveGridEntity(ctx.rockIndex, 0, false)
        ctx.rockMade = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
        return H.targetReady(ctx.target)
    end, 30, label .. ": target ready")
    plan.act(function(player, ctx)
        ctx.seen, ctx.appeared, ctx.statuses = {}, {}, {}
        for _, entity in ipairs(Isaac.GetRoomEntities()) do ctx.seen[GetPtrHash(entity)] = true end
        ctx.hp = ctx.target.HitPoints
        ctx.flags = player:GetBombFlags()
        probeShield = {}
        local damage = player.Damage * M().data.damageMultiplier
        if route == "effects" then
            Game():BombExplosionEffects(ctx.spot, damage, ctx.flags, Color.Default, player, 1, true, false,
                DamageFlag.DAMAGE_EXPLOSION)
        else
            local bomb = Isaac.Spawn(EntityType.ENTITY_BOMB, BombVariant.BOMB_NORMAL, 0, ctx.spot, Vector.Zero, player)
            bomb = bomb and bomb:ToBomb()
            if bomb then
                bomb.Flags = ctx.flags
                bomb.ExplosionDamage = damage
                bomb:SetExplosionCountdown(0)
            end
            ctx.bombMade = bomb ~= nil
        end
        ctx.until_ = Game():GetFrameCount() + 75
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local hash = GetPtrHash(entity)
            if not ctx.seen[hash] then
                ctx.seen[hash] = true
                local key = string.format("%d.%d", entity.Type, entity.Variant)
                ctx.appeared[key] = (ctx.appeared[key] or 0) + 1
            end
        end
        local target = ctx.target
        if target and target:Exists() then
            for _, name in ipairs(STATUS) do
                local flag = EntityFlag[name]
                if flag and target:HasEntityFlags(flag) then ctx.statuses[name] = true end
            end
        end
        return Game():GetFrameCount() >= ctx.until_, "watching"
    end, 120, label .. ": 75 updates after the blast")
    plan.note(label, function(player, ctx)
        local room = Game():GetRoom()
        local grid = room:GetGridEntity(ctx.rockIndex)
        local rock = not ctx.rockMade and "no rock"
            or (grid and string.format("type=%d state=%d coll=%d", grid:GetType(), grid.State, grid.CollisionClass) or "gone")
        local appeared, statuses = {}, {}
        for key, count in pairs(ctx.appeared) do appeared[#appeared + 1] = key .. "x" .. count end
        table.sort(appeared)
        for name in pairs(ctx.statuses) do statuses[#statuses + 1] = name:gsub("^FLAG_", "") end
        table.sort(statuses)
        local hp = ctx.target and ctx.target:Exists() and ctx.hp - ctx.target.HitPoints or -1
        return string.format("flags=%s hpLost=%.2f status=[%s] rock=%s playerHits=[%s] appeared=[%s]",
            flagsText(ctx.flags), hp, table.concat(statuses, " "), rock, table.concat(probeShield or {}, " "),
            table.concat(appeared, " "))
    end)
    plan.act(function(player, ctx)
        probeShield = nil
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        ctx.target = nil
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local t = entity.Type
            if t == EntityType.ENTITY_BOMB or t == EntityType.ENTITY_TEAR or t == EntityType.ENTITY_LASER
                or t == EntityType.ENTITY_PICKUP or (t == EntityType.ENTITY_EFFECT and entity.Variant ~= M().mineVariant())
                or (t == EntityType.ENTITY_FAMILIAR and entity.Variant == FamiliarVariant.BLUE_SPIDER) then
                entity:Remove()
            end
        end
        Game():GetRoom():RemoveGridEntity(ctx.rockIndex, 0, false)
        if ctx.itemId then player:RemoveCollectible(ctx.itemId) end
    end)
    plan.wait(5)
end

S.add("LANDMINE", "bomb_probe", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.act(function(player, ctx)
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
        table.insert(ctx.cleanupFns, 1, function() probeShield = nil end)
    end)
    for _, itemName in ipairs(BOMB_ITEMS) do
        local known = itemName == "NONE" or type(CollectibleType["COLLECTIBLE_" .. itemName]) == "number"
        if known then
            probeRound(plan, itemName, "effects")
            probeRound(plan, itemName, "bomb")
        else
            plan.note(itemName, function() return "no such collectible" end)
        end
    end
end)
S.rows[#S.rows].manual = true

-- A second measurement, run by name: a real bomb of the player's, set off at
-- once, as a mine's blast. Rounds compare the plain bomb with one marked as a
-- fetus bomb and given the player's own bomb variant, and log the arguments of
-- REPENTOGON's MC_PRE_GRID_HURT while the blast runs (cancelled in the second
-- round, to see whether that keeps the rock), the update the explosion came
-- on and the player's hits (cancelled).
local gridProbe -- { calls, cancel } while a round watches the grid
if ModCallbacks.MC_PRE_GRID_HURT then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GRID_HURT, function(_, ...)
        if not gridProbe then return nil end
        local n, parts = select("#", ...), {}
        for i = 1, n do
            local value = select(i, ...)
            local text = type(value)
            if type(value) == "number" or type(value) == "boolean" then
                text = tostring(value)
            elseif type(value) == "userdata" then
                local ok, kind = pcall(function()
                    if value.GetType and value.GetGridIndex then
                        return string.format("grid%d@%d", value:GetType(), value:GetGridIndex())
                    end
                    if value.Type then return string.format("ent%d.%d", value.Type, value.Variant) end
                    if value.Entity then
                        return value.Entity and string.format("ref%d.%d", value.Entity.Type, value.Entity.Variant) or "ref-nil"
                    end
                    return "userdata"
                end)
                text = ok and kind or "userdata?"
            end
            parts[#parts + 1] = text
        end
        if #gridProbe.calls < 4 then gridProbe.calls[#gridProbe.calls + 1] = table.concat(parts, ",") end
        gridProbe.count = gridProbe.count + 1
        if gridProbe.cancel then return false end
    end)
end

local PROBE2_ITEMS = { "NONE", "MR_MEGA", "SCATTER_BOMBS", "GHOST_BOMBS", "BOBS_CURSE", "BOMBER_BOY" }

local function probe2Round(plan, itemName, variantMode, cancel)
    local label = string.format("%s / %s%s", itemName, variantMode, cancel and " / grid cancelled" or "")
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        ctx.spot = Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y)
        ctx.itemId = itemName ~= "NONE" and CollectibleType["COLLECTIBLE_" .. itemName] or nil
        if ctx.itemId then player:AddCollectible(ctx.itemId, 0, false) end
        player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
        ctx.target = H.target(player, true)
        ctx.targetSpot = ctx.spot + Vector(30, 0)
        pin(ctx)
        ctx.rockIndex = room:GetGridIndex(ctx.spot + Vector(0, -50))
        room:RemoveGridEntity(ctx.rockIndex, 0, false)
        ctx.rockMade = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
        return H.targetReady(ctx.target)
    end, 30, label .. ": target ready")
    plan.act(function(player, ctx)
        ctx.seen, ctx.appeared, ctx.statuses = {}, {}, {}
        for _, entity in ipairs(Isaac.GetRoomEntities()) do ctx.seen[GetPtrHash(entity)] = true end
        ctx.hp = ctx.target.HitPoints
        ctx.flags = player:GetBombFlags()
        probeShield = {}
        gridProbe = { calls = {}, count = 0, cancel = cancel }
        ctx.start = Game():GetFrameCount()
        ctx.boomAt = nil
        local damage = player.Damage * M().data.damageMultiplier
        local variant = BombVariant.BOMB_NORMAL
        if variantMode == "fetus+variant" and type(player.GetBombVariant) == "function" then
            variant = player:GetBombVariant(ctx.flags, false)
        end
        ctx.variant = variant
        local bomb = Isaac.Spawn(EntityType.ENTITY_BOMB, variant, 0, ctx.spot, Vector.Zero, player)
        bomb = bomb and bomb:ToBomb()
        if bomb then
            bomb.Flags = ctx.flags
            bomb.ExplosionDamage = damage
            if variantMode == "fetus+variant" then bomb.IsFetus = true end
            bomb:SetExplosionCountdown(0)
            ctx.radius = bomb.RadiusMultiplier
        end
        ctx.until_ = Game():GetFrameCount() + 75
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local hash = GetPtrHash(entity)
            if not ctx.seen[hash] then
                ctx.seen[hash] = true
                local key = string.format("%d.%d", entity.Type, entity.Variant)
                ctx.appeared[key] = (ctx.appeared[key] or 0) + 1
                if not ctx.boomAt and entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == EffectVariant.BOMB_EXPLOSION then
                    ctx.boomAt = Game():GetFrameCount() - ctx.start
                end
            end
        end
        local target = ctx.target
        if target and target:Exists() then
            for _, name in ipairs(STATUS) do
                local flag = EntityFlag[name]
                if flag and target:HasEntityFlags(flag) then ctx.statuses[name] = true end
            end
        end
        return Game():GetFrameCount() >= ctx.until_, "watching"
    end, 120, label .. ": 75 updates after the blast")
    plan.note(label, function(_, ctx)
        local room = Game():GetRoom()
        local grid = room:GetGridEntity(ctx.rockIndex)
        local rock = not ctx.rockMade and "no rock"
            or (grid and string.format("state=%d coll=%d", grid.State, grid.CollisionClass) or "gone")
        local appeared, statuses = {}, {}
        for key, count in pairs(ctx.appeared) do appeared[#appeared + 1] = key .. "x" .. count end
        table.sort(appeared)
        for name in pairs(ctx.statuses) do statuses[#statuses + 1] = name:gsub("^FLAG_", "") end
        table.sort(statuses)
        local hp = ctx.target and ctx.target:Exists() and ctx.hp - ctx.target.HitPoints or -1
        return string.format("variant=%s radiusMult=%s boomAfter=%s hpLost=%.2f status=[%s] rock=%s playerHits=[%s] "
            .. "gridHurts=%d first=[%s] appeared=[%s]", tostring(ctx.variant), tostring(ctx.radius), tostring(ctx.boomAt),
            hp, table.concat(statuses, " "), rock, table.concat(probeShield or {}, " "), gridProbe and gridProbe.count or -1,
            gridProbe and table.concat(gridProbe.calls, " | ") or "", table.concat(appeared, " "))
    end)
    plan.act(function(player, ctx)
        probeShield, gridProbe = nil, nil
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        ctx.target = nil
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local t = entity.Type
            if t == EntityType.ENTITY_BOMB or t == EntityType.ENTITY_TEAR or t == EntityType.ENTITY_LASER
                or t == EntityType.ENTITY_PICKUP or (t == EntityType.ENTITY_EFFECT and entity.Variant ~= M().mineVariant())
                or (t == EntityType.ENTITY_FAMILIAR and entity.Variant == FamiliarVariant.BLUE_SPIDER) then
                entity:Remove()
            end
        end
        Game():GetRoom():RemoveGridEntity(ctx.rockIndex, 0, false)
        if ctx.itemId then player:RemoveCollectible(ctx.itemId) end
    end)
    plan.wait(5)
end

S.add("LANDMINE", "bomb_probe2", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.act(function(_, ctx)
        table.insert(ctx.cleanupFns, 1, function() probeShield, gridProbe = nil, nil end)
    end)
    for _, itemName in ipairs(PROBE2_ITEMS) do
        if itemName == "NONE" or type(CollectibleType["COLLECTIBLE_" .. itemName]) == "number" then
            probe2Round(plan, itemName, "plain", false)
            probe2Round(plan, itemName, "fetus+variant", true)
        end
    end
end)
S.rows[#S.rows].manual = true

-- A third measurement, run by name: which REPENTOGON grid callbacks a mine's
-- real bomb goes through as it breaks a rock (MC_GRID_HURT_DAMAGE, its POST,
-- MC_POST_GRID_ROCK_DESTROY), and whether cancelling MC_GRID_HURT_DAMAGE keeps
-- the rock.
local gridHurt -- { counts, cancel } while a round watches
for _, name in ipairs({ "MC_GRID_HURT_DAMAGE", "MC_POST_GRID_HURT_DAMAGE", "MC_POST_GRID_ROCK_DESTROY" }) do
    local id = ModCallbacks[name]
    if id then
        ConchBlessing:AddCallback(id, function(_, ...)
            if not gridHurt then return nil end
            gridHurt.counts[name] = (gridHurt.counts[name] or 0) + 1
            if not gridHurt.args[name] then
                local parts = {}
                for i = 1, select("#", ...) do
                    local v = select(i, ...)
                    parts[#parts + 1] = (type(v) == "number" or type(v) == "boolean") and tostring(v) or type(v)
                end
                gridHurt.args[name] = table.concat(parts, ",")
            end
            if gridHurt.cancel and name == "MC_GRID_HURT_DAMAGE" then return false end
        end)
    end
end

S.add("LANDMINE", "bomb_probe3", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.act(function(_, ctx)
        table.insert(ctx.cleanupFns, 1, function() gridHurt, probeShield = nil, nil end)
    end)
    for _, cancel in ipairs({ false, true }) do
        for _, route in ipairs({ "effects", "bomb" }) do
            local label = route .. (cancel and " / grid hurt cancelled" or "")
            plan.act(function(player, ctx)
                local room = Game():GetRoom()
                ctx.spot = Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y)
                player.Position, player.Velocity = ctx.spot + Vector(-80, 0), Vector.Zero
                ctx.rockIndex = room:GetGridIndex(ctx.spot + Vector(0, -50))
                room:RemoveGridEntity(ctx.rockIndex, 0, false)
                ctx.rockMade = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
            end)
            plan.wait(3)
            plan.act(function(player, ctx)
                gridHurt, probeShield = { counts = {}, args = {}, cancel = cancel }, {}
                local damage = player.Damage * M().data.damageMultiplier
                if route == "effects" then
                    Game():BombExplosionEffects(ctx.spot, damage, player:GetBombFlags(), Color.Default, player, 1, true,
                        false, DamageFlag.DAMAGE_EXPLOSION)
                else
                    local bomb = Isaac.Spawn(EntityType.ENTITY_BOMB, BombVariant.BOMB_NORMAL, 0, ctx.spot, Vector.Zero,
                        player):ToBomb()
                    bomb.ExplosionDamage = damage
                    bomb:SetExplosionCountdown(0)
                end
            end)
            plan.wait(20)
            plan.note(label, function(_, ctx)
                local grid = Game():GetRoom():GetGridEntity(ctx.rockIndex)
                local counts, args = {}, {}
                for k, v in pairs(gridHurt.counts) do counts[#counts + 1] = k .. "=" .. v end
                for k, v in pairs(gridHurt.args) do args[#args + 1] = k .. "(" .. v .. ")" end
                return string.format("rock=%s calls=[%s] args=[%s] playerHits=%d",
                    grid and string.format("state=%d coll=%d", grid.State, grid.CollisionClass) or "gone",
                    table.concat(counts, " "), table.concat(args, " "), #probeShield)
            end)
            plan.act(function(_, ctx)
                gridHurt, probeShield = nil, nil
                Game():GetRoom():RemoveGridEntity(ctx.rockIndex, 0, false)
            end)
            plan.wait(3)
        end
    end
end)
S.rows[#S.rows].manual = true

-- A fourth measurement, run by name: a "fake" explosion that keeps grids whole
-- (user question 2026-11-27): the vanilla explosion only as a picture, then
-- Game():BombDamage with the player's bomb flags (damage and statuses to
-- entities) and Game():BombTearflagEffects (the flags' extra effects), for each
-- bomb item.
S.add("LANDMINE", "bomb_probe4", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.act(function(_, ctx)
        table.insert(ctx.cleanupFns, 1, function() probeShield = nil end)
    end)
    for _, itemName in ipairs(BOMB_ITEMS) do
        if itemName == "NONE" or type(CollectibleType["COLLECTIBLE_" .. itemName]) == "number" then
            local label = itemName .. " / fake"
            plan.act(function(player, ctx)
                local room = Game():GetRoom()
                ctx.spot = Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y)
                ctx.itemId = itemName ~= "NONE" and CollectibleType["COLLECTIBLE_" .. itemName] or nil
                if ctx.itemId then player:AddCollectible(ctx.itemId, 0, false) end
                player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
                ctx.target = H.target(player, true)
                ctx.targetSpot = ctx.spot + Vector(30, 0)
                pin(ctx)
                ctx.rockIndex = room:GetGridIndex(ctx.spot + Vector(0, -50))
                room:RemoveGridEntity(ctx.rockIndex, 0, false)
                ctx.rockMade = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
            end)
            plan.waitUntil(function(player, ctx)
                pin(ctx)
                player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
                return H.targetReady(ctx.target)
            end, 30, label .. ": target ready")
            plan.act(function(player, ctx)
                ctx.seen, ctx.appeared, ctx.statuses = {}, {}, {}
                for _, entity in ipairs(Isaac.GetRoomEntities()) do ctx.seen[GetPtrHash(entity)] = true end
                ctx.hp = ctx.target.HitPoints
                ctx.flags = player:GetBombFlags()
                probeShield = {}
                local damage = player.Damage * M().data.damageMultiplier
                local game = Game()
                local picture = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BOMB_EXPLOSION, 0, ctx.spot, Vector.Zero, nil)
                picture.SpriteScale = Vector(0.45, 0.45)
                local okDamage, errDamage = pcall(game.BombDamage, game, ctx.spot, damage, 40, true, player, ctx.flags,
                    DamageFlag.DAMAGE_EXPLOSION, false)
                local okExtra, errExtra = pcall(game.BombTearflagEffects, game, ctx.spot, 40, ctx.flags, player, 1)
                ctx.calls = string.format("%s%s/%s%s", tostring(okDamage), okDamage and "" or ("(" .. tostring(errDamage) .. ")"),
                    tostring(okExtra), okExtra and "" or ("(" .. tostring(errExtra) .. ")"))
                ctx.until_ = Game():GetFrameCount() + 75
            end)
            plan.waitUntil(function(player, ctx)
                pin(ctx)
                player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    local hash = GetPtrHash(entity)
                    if not ctx.seen[hash] then
                        ctx.seen[hash] = true
                        local key = string.format("%d.%d", entity.Type, entity.Variant)
                        ctx.appeared[key] = (ctx.appeared[key] or 0) + 1
                    end
                end
                local target = ctx.target
                if target and target:Exists() then
                    for _, name in ipairs(STATUS) do
                        local flag = EntityFlag[name]
                        if flag and target:HasEntityFlags(flag) then ctx.statuses[name] = true end
                    end
                end
                return Game():GetFrameCount() >= ctx.until_, "watching"
            end, 120, label .. ": 75 updates after the blast")
            plan.note(label, function(_, ctx)
                local grid = Game():GetRoom():GetGridEntity(ctx.rockIndex)
                local appeared, statuses = {}, {}
                for key, count in pairs(ctx.appeared) do appeared[#appeared + 1] = key .. "x" .. count end
                table.sort(appeared)
                for name in pairs(ctx.statuses) do statuses[#statuses + 1] = name:gsub("^FLAG_", "") end
                table.sort(statuses)
                local hp = ctx.target and ctx.target:Exists() and ctx.hp - ctx.target.HitPoints or -1
                return string.format("calls=%s hpLost=%.2f status=[%s] rock=%s playerHits=[%s] appeared=[%s]",
                    ctx.calls, hp, table.concat(statuses, " "),
                    grid and string.format("state=%d coll=%d", grid.State, grid.CollisionClass) or "gone",
                    table.concat(probeShield or {}, " "), table.concat(appeared, " "))
            end)
            plan.act(function(player, ctx)
                probeShield = nil
                if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
                ctx.target = nil
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    local t = entity.Type
                    if t == EntityType.ENTITY_BOMB or t == EntityType.ENTITY_TEAR or t == EntityType.ENTITY_LASER
                        or t == EntityType.ENTITY_PICKUP or (t == EntityType.ENTITY_EFFECT and entity.Variant ~= M().mineVariant())
                        or (t == EntityType.ENTITY_FAMILIAR and entity.Variant == FamiliarVariant.BLUE_SPIDER) then
                        entity:Remove()
                    end
                end
                Game():GetRoom():RemoveGridEntity(ctx.rockIndex, 0, false)
                if ctx.itemId then player:RemoveCollectible(ctx.itemId) end
            end)
            plan.wait(5)
        end
    end
end)
S.rows[#S.rows].manual = true

-- A fifth measurement, run by name: which part of the fake explosion breaks
-- the rock 50 units away: the picture alone, Game():BombDamage alone (radius
-- 40, then 20) or Game():BombTearflagEffects alone, with no item and with Sad
-- Bombs and Hot Bombs held.
local PROBE5_PARTS = { "picture", "damage40", "damage20", "extra" }
S.add("LANDMINE", "bomb_probe5", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.act(function(_, ctx)
        table.insert(ctx.cleanupFns, 1, function() probeShield = nil end)
    end)
    for _, itemName in ipairs({ "NONE", "SAD_BOMBS", "HOT_BOMBS" }) do
        for _, part in ipairs(PROBE5_PARTS) do
            local label = itemName .. " / " .. part
            plan.act(function(player, ctx)
                local room = Game():GetRoom()
                ctx.spot = Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y)
                ctx.itemId = itemName ~= "NONE" and CollectibleType["COLLECTIBLE_" .. itemName] or nil
                if ctx.itemId then player:AddCollectible(ctx.itemId, 0, false) end
                player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
                ctx.target = H.target(player, true)
                ctx.targetSpot = ctx.spot + Vector(30, 0)
                pin(ctx)
                ctx.rockIndex = room:GetGridIndex(ctx.spot + Vector(0, -50))
                room:RemoveGridEntity(ctx.rockIndex, 0, false)
                Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true)
                ctx.rockDistance = room:GetGridPosition(ctx.rockIndex):Distance(ctx.spot)
            end)
            plan.waitUntil(function(player, ctx)
                pin(ctx)
                player.Position, player.Velocity = ctx.spot + Vector(-45, 0), Vector.Zero
                return H.targetReady(ctx.target)
            end, 30, label .. ": target ready")
            plan.act(function(player, ctx)
                ctx.hp = ctx.target.HitPoints
                probeShield = {}
                local game, flags = Game(), player:GetBombFlags()
                local damage = player.Damage * M().data.damageMultiplier
                if part == "picture" then
                    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BOMB_EXPLOSION, 0, ctx.spot, Vector.Zero, nil)
                elseif part == "damage40" or part == "damage20" then
                    game:BombDamage(ctx.spot, damage, part == "damage40" and 40 or 20, true, player, flags,
                        DamageFlag.DAMAGE_EXPLOSION, false)
                else
                    game:BombTearflagEffects(ctx.spot, 40, flags, player, 1)
                end
            end)
            plan.wait(40)
            plan.note(label, function(_, ctx)
                local grid = Game():GetRoom():GetGridEntity(ctx.rockIndex)
                local hp = ctx.target and ctx.target:Exists() and ctx.hp - ctx.target.HitPoints or -1
                return string.format("rockAt=%.0f rock=%s hpLost=%.2f burn=%s playerHits=%d", ctx.rockDistance,
                    grid and (grid.State == 2 and "BROKEN" or "whole") or "gone", hp,
                    tostring(ctx.target and ctx.target:HasEntityFlags(EntityFlag.FLAG_BURN)), #probeShield)
            end)
            plan.act(function(player, ctx)
                probeShield = nil
                if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
                ctx.target = nil
                for _, entity in ipairs(Isaac.GetRoomEntities()) do
                    local t = entity.Type
                    if t == EntityType.ENTITY_TEAR or t == EntityType.ENTITY_LASER or t == EntityType.ENTITY_PICKUP
                        or (t == EntityType.ENTITY_EFFECT and entity.Variant ~= M().mineVariant()) then
                        entity:Remove()
                    end
                end
                Game():GetRoom():RemoveGridEntity(ctx.rockIndex, 0, false)
                if ctx.itemId then player:RemoveCollectible(ctx.itemId) end
            end)
            plan.wait(5)
        end
    end
end)
S.rows[#S.rows].manual = true

-- A sixth measurement, run by name: (1) the exact effects a real bomb makes
-- for Ghost Bombs and Bob's Curse (variant, subtype, spawner, timeout); (2)
-- Game():BombDamage at an enemy's own position with radius 1 and Hot Bombs:
-- does it hit, burn, and keep a rock right beside the enemy, and a rock under a
-- flying enemy; (3) the same ghost and cloud spawned by us with the player as
-- spawner: do they hurt the target and spare the player.
local function cleanRoom(ctx)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local t = entity.Type
        if t == EntityType.ENTITY_BOMB or t == EntityType.ENTITY_TEAR or t == EntityType.ENTITY_LASER
            or t == EntityType.ENTITY_PICKUP or (t == EntityType.ENTITY_EFFECT and entity.Variant ~= M().mineVariant()) then
            entity:Remove()
        end
    end
    if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
    ctx.target = nil
    if ctx.rockIndex then Game():GetRoom():RemoveGridEntity(ctx.rockIndex, 0, false) end
end

S.add("LANDMINE", "bomb_probe6", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.act(function(_, ctx)
        table.insert(ctx.cleanupFns, 1, function() probeShield = nil end)
    end)
    -- (1) what a real bomb makes for Ghost Bombs and Bob's Curse
    for _, itemName in ipairs({ "GHOST_BOMBS", "BOBS_CURSE" }) do
        plan.act(function(player, ctx)
            local room = Game():GetRoom()
            ctx.spot = Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y)
            ctx.itemId = CollectibleType["COLLECTIBLE_" .. itemName]
            player:AddCollectible(ctx.itemId, 0, false)
            player.Position, player.Velocity = ctx.spot + Vector(-120, 0), Vector.Zero
            ctx.seen, ctx.made = {}, {}
            for _, entity in ipairs(Isaac.GetRoomEntities()) do ctx.seen[GetPtrHash(entity)] = true end
            local bomb = Isaac.Spawn(EntityType.ENTITY_BOMB, BombVariant.BOMB_NORMAL, 0, ctx.spot, Vector.Zero, player):ToBomb()
            bomb.Flags = player:GetBombFlags()
            bomb:SetExplosionCountdown(0)
        end)
        plan.wait(6)
        plan.note(itemName .. " / what the bomb made", function(_, ctx)
            local parts = {}
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if not ctx.seen[GetPtrHash(entity)] and entity.Type == EntityType.ENTITY_EFFECT
                    and (entity.Variant == 186 or entity.Variant == 141) then
                    local effect = entity:ToEffect()
                    local spawner = entity.SpawnerEntity
                    parts[#parts + 1] = string.format("%d.%d.%d spawner=%s parent=%s timeout=%s state=%s",
                        entity.Type, entity.Variant, entity.SubType,
                        spawner and string.format("%d.%d", spawner.Type, spawner.Variant) or "nil",
                        entity.Parent and string.format("%d.%d", entity.Parent.Type, entity.Parent.Variant) or "nil",
                        effect and tostring(effect.Timeout) or "?", effect and tostring(effect.State) or "?")
                end
            end
            return table.concat(parts, " | ")
        end)
        plan.act(function(player, ctx)
            cleanRoom(ctx)
            player:RemoveCollectible(ctx.itemId)
        end)
        plan.wait(3)
    end
    -- (2) BombDamage at an enemy with radius 1: grounded beside a rock, flying over one
    for _, flying in ipairs({ false, true }) do
        local label = flying and "radius 1 / fly over a rock" or "radius 1 / maggot beside a rock"
        plan.act(function(player, ctx)
            local room = Game():GetRoom()
            player:AddCollectible(CollectibleType.COLLECTIBLE_HOT_BOMBS, 0, false)
            ctx.rockIndex = room:GetGridIndex(Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y - 80))
            room:RemoveGridEntity(ctx.rockIndex, 0, false)
            Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true)
            local rock = room:GetGridPosition(ctx.rockIndex)
            ctx.targetSpot = flying and rock or rock + Vector(0, 30)
            player.Position, player.Velocity = rock + Vector(-120, 60), Vector.Zero
            ctx.target = H.target(player, not flying)
            pin(ctx)
        end)
        plan.waitUntil(function(_, ctx)
            pin(ctx)
            return H.targetReady(ctx.target)
        end, 30, label .. ": target ready")
        plan.act(function(player, ctx)
            pin(ctx)
            ctx.hp = ctx.target.HitPoints
            probeShield = {}
            Game():BombDamage(ctx.target.Position, player.Damage * M().data.damageMultiplier, 1, true, player,
                player:GetBombFlags(), DamageFlag.DAMAGE_EXPLOSION, false)
            ctx.burned = ctx.target:HasEntityFlags(EntityFlag.FLAG_BURN)
        end)
        plan.wait(10)
        plan.note(label, function(_, ctx)
            local grid = Game():GetRoom():GetGridEntity(ctx.rockIndex)
            return string.format("hpLost=%.2f burned=%s rock=%s playerHits=%d", ctx.hp - ctx.target.HitPoints,
                tostring(ctx.burned), grid and (grid.State == 2 and "BROKEN" or "whole") or "gone", #probeShield)
        end)
        plan.act(function(player, ctx)
            probeShield = nil
            cleanRoom(ctx)
            player:RemoveCollectible(CollectibleType.COLLECTIBLE_HOT_BOMBS)
        end)
        plan.wait(3)
    end
    -- (3) a ghost and a cloud spawned by us
    for _, which in ipairs({ { 186, 0, "ghost" }, { 141, 0, "cloud" } }) do
        local label = "our " .. which[3]
        plan.act(function(player, ctx)
            local room = Game():GetRoom()
            ctx.spot = Vector(room:GetCenterPos().X + 40, room:GetCenterPos().Y)
            player.Position, player.Velocity = ctx.spot + Vector(-30, 0), Vector.Zero
            ctx.target = H.target(player, true)
            ctx.targetSpot = ctx.spot + Vector(60, 0)
            pin(ctx)
        end)
        plan.waitUntil(function(player, ctx)
            pin(ctx)
            player.Position, player.Velocity = ctx.spot + Vector(-30, 0), Vector.Zero
            return H.targetReady(ctx.target)
        end, 30, label .. ": target ready")
        plan.act(function(player, ctx)
            ctx.hp = ctx.target.HitPoints
            probeShield = {}
            local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, which[1], which[2], ctx.spot, Vector.Zero, player)
            ctx.made = effect and effect:Exists()
            ctx.until_ = Game():GetFrameCount() + 120
        end)
        plan.waitUntil(function(player, ctx)
            pin(ctx)
            player.Position, player.Velocity = ctx.spot + Vector(-30, 0), Vector.Zero
            return Game():GetFrameCount() >= ctx.until_, "watching"
        end, 150, label .. ": 120 updates")
        plan.note(label, function(_, ctx)
            return string.format("made=%s hpLost=%.2f poisoned=%s playerHits=%d", tostring(ctx.made),
                ctx.hp - ctx.target.HitPoints, tostring(ctx.target:HasEntityFlags(EntityFlag.FLAG_POISON)), #probeShield)
        end)
        plan.act(function(_, ctx)
            probeShield = nil
            cleanRoom(ctx)
        end)
        plan.wait(3)
    end
end)
S.rows[#S.rows].manual = true

-- A measurement, run by name: does Monstro's Lung fire when the bench holds
-- the shoot key for a while and lets go, without Landmine and with it; logs the
-- most tears seen at once, the tears this module took up and the Lung's
-- weapon charge as the key was let go.
S.add("LANDMINE", "lung_probe", { conditions = true }, function(plan, id)
    setup(plan, id)
    withEnemy(plan)
    for _, withItem in ipairs({ false, true }) do
        for _, hold in ipairs({ 60, 150 }) do
            local label = string.format("%s, held %d", withItem and "with Landmine" or "without Landmine", hold)
            plan.act(function(player, ctx)
                player:AddCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG, 0, false)
                give(player, id, withItem and 1 or 0)
                clearMines()
                T().resetEvidence()
                ctx.most, ctx.charge = 0, nil
            end)
            plan.wait(3)
            stand(plan, function(room) return leftSide(room) end, hold, true)
            plan.act(function(player, ctx)
                local weapon = type(player.GetWeapon) == "function" and player:GetWeapon(1) or nil
                ctx.charge = weapon and type(weapon.GetCharge) == "function" and weapon:GetCharge() or "?"
                ctx.until_ = Game():GetFrameCount() + 30
            end)
            plan.waitUntil(function(_, ctx)
                ctx.most = math.max(ctx.most, #Isaac.FindByType(EntityType.ENTITY_TEAR))
                return Game():GetFrameCount() >= ctx.until_, "watching"
            end, 40, label .. ": 30 updates after letting go")
            plan.note(label, function(player, ctx)
                return string.format("mostTears=%d taken=%d laid=%d chargeAtRelease=%s lung=%s tears=%s", ctx.most,
                    evidence().fired, evidence().laid, tostring(ctx.charge),
                    tostring(player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS)),
                    tostring(player:HasWeaponType(WeaponType.WEAPON_TEARS)))
            end)
            plan.act(function(player)
                player:RemoveCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
                clearMines()
                give(player, id, 1)
            end)
            plan.wait(3)
        end
    end
end)
S.rows[#S.rows].manual = true

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

-- Measurement only (run by name): what mines on the floor cost. Each window
-- logs the wall time between updates (average, worst, and how many took over
-- 40 ms, a dropped frame at 30 updates a second), the process CPU time per
-- update (engine and every mod), this mod's own handlers (callback_profiler)
-- and the entity count, with 0, 300 and 1000 mines, while shooting, and as a
-- pile of 60 goes off under the player.
local Profiler = require("scripts.dev.callback_profiler")
local PERF_WINDOW, PERF_TOP = 150, 5

local function perfWindow(plan, label, updates, shoot)
    updates = updates or PERF_WINDOW
    plan.act(function(player, ctx)
        Profiler.start()
        ctx.perf = { updates = 0, cpu0 = os.clock(), wall0 = Isaac.GetTime(), last = Isaac.GetTime(), worst = 0,
            slow = 0 }
        if shoot then startShooting(player, ctx) end
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        if ctx.spot then player.Position, player.Velocity = ctx.spot, Vector.Zero end
        local p, now = ctx.perf, Isaac.GetTime()
        if p.updates > 0 then
            local step = now - p.last
            if step > p.worst then p.worst = step end
            if step > 40 then p.slow = p.slow + 1 end
        end
        p.last, p.updates = now, p.updates + 1
        return p.updates >= updates, p.updates .. " updates"
    end, updates + 5, label)
    plan.act(function(_, ctx)
        stopShooting()
        local p = ctx.perf
        p.cpu = (os.clock() - p.cpu0) * 1000 / math.max(1, p.updates)
        p.wall = (Isaac.GetTime() - p.wall0) / math.max(1, p.updates)
        Profiler.stop()
        p.top, p.total = Profiler.report(PERF_TOP)
        p.entities, p.mines = #Isaac.GetRoomEntities(), #M().mines()
    end)
    plan.note(label, function(_, ctx)
        local p = ctx.perf
        return string.format("%d mines, %d entities: wall %.1f ms/update (worst %d, %d over 40 ms), CPU %.2f ms/update,"
            .. " this mod %.3f ms/update", p.mines, p.entities, p.wall, p.worst, p.slow, p.cpu,
            p.total / p.updates)
    end)
    for i = 1, PERF_TOP do
        plan.note(label .. " #" .. i, function(_, ctx)
            local row, p = ctx.perf.top[i], ctx.perf
            if not row then return "-" end
            return string.format("%.4f ms/update, %d calls (%.2f us/call): %s", row.ms / p.updates, row.calls,
                row.calls > 0 and row.ms * 1000 / row.calls or 0, row.label)
        end)
    end
end

-- Lays landed mines over the room's floor until `total` lie there, kept two
-- tiles from the player and the enemy.
local function fillMines(plan, total)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        local tl, br = room:GetTopLeftPos(), room:GetBottomRightPos()
        local step = total > 1200 and 8 or total > 400 and 12 or 22
        local count = #M().mines()
        for y = tl.Y + 10, br.Y - 10, step do
            for x = tl.X + 10, br.X - 10, step do
                if count >= total then return end
                local spot = Vector(x, y)
                if spot:Distance(ctx.spot) > 80 and spot:Distance(ctx.targetSpot) > 80 and T().isFloor(room, spot) then
                    lay(player, spot)
                    count = count + 1
                end
            end
        end
    end)
    plan.wait(15)
end

-- Other mods' handlers that run for every effect (no variant filter) or for
-- the mine's variant: each runs once per mine every update or render.
local function effectHandlers()
    local parts = {}
    for _, name in ipairs({ "MC_POST_EFFECT_INIT", "MC_POST_EFFECT_UPDATE", "MC_POST_EFFECT_RENDER",
        "MC_PRE_EFFECT_RENDER" }) do
        local id = ModCallbacks[name]
        if id then
            local mods = {}
            for _, entry in ipairs(Isaac.GetCallbacks(id, false) or {}) do
                if entry.Param == nil or entry.Param == -1 or entry.Param == M().mineVariant() then
                    mods[#mods + 1] = tostring(entry.Mod and entry.Mod.Name)
                end
            end
            parts[#parts + 1] = name:gsub("^MC_", "") .. "=" .. #mods .. " [" .. table.concat(mods, ", ") .. "]"
        end
    end
    return table.concat(parts, "; ")
end

S.add("LANDMINE", "perf", { conditions = true }, function(plan, id)
    setup(plan, id)
    plan.require("callback profiler and wall clock available", function()
        return Profiler.available() and type(Isaac.GetTime) == "function" or nil, "needs Isaac.GetCallbacks"
    end)
    withEnemy(plan)
    plan.act(function(player, ctx)
        ctx.spot = leftSide(Game():GetRoom())
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        table.insert(ctx.cleanupFns, 1, function() Profiler.stop() end)
    end)
    plan.note("handlers run for every effect", function() return effectHandlers() end)
    plan.wait(10)
    perfWindow(plan, "no mines")
    fillMines(plan, 300)
    perfWindow(plan, "300 mines")
    fillMines(plan, 1000)
    perfWindow(plan, "1000 mines")
    perfWindow(plan, "1000 mines, shooting", nil, true)
    plan.act(function(player, ctx)
        clearMines()
        ctx.pile = Vector(ctx.spot.X + 120, ctx.spot.Y)
        for _ = 1, 60 do lay(player, ctx.pile) end
    end)
    plan.wait(15)
    plan.act(function(_, ctx) ctx.spot = ctx.pile end)
    perfWindow(plan, "a pile of 60 going off under the player", 30)
end)
S.rows[#S.rows].manual = true

-- Measurement only (run by name): the real cost of mines, free of the game's
-- fixed 33.3 ms update. While work fits in a frame the game waits out the rest,
-- so an update always looks 33.3 ms long; here every render frame is given
-- extra busy work (a loop calibrated against the wall clock, so loads finer
-- than its 1 ms ticks) and a search finds the largest load that still keeps
-- updates on time. That load is the frame's headroom; the headroom with no
-- mines less the headroom with N mines is what N mines cost each frame, the
-- engine, every mod and this one included.
local spinLoops = 0         -- the busy loop's length, while a window runs
local spinSink = 0
local function spin(loops)
    local x = spinSink
    for i = 1, loops do x = x + i % 7 end
    spinSink = x
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if spinLoops > 0 then spin(spinLoops) end
end)

-- Windows of 90 updates after 10 to settle; an update over 34.0 ms on average
-- is late; the search runs 9 halvings of 0-32 ms (to 0.06 ms).
local HEADROOM = { settle = 10, window = 90, late = 34.0, top = 32, steps = 9 }

-- One window at the current load: the average wall time between updates.
local function headroomWindow(state, now)
    local w = state.window
    if not w then
        state.window = { from = nil, count = -HEADROOM.settle }
        return false
    end
    w.count = w.count + 1
    if w.count == 0 then w.from = now end
    if w.count < HEADROOM.window then return false end
    state.window = nil
    return true, (now - w.from) / HEADROOM.window
end

-- A search over the load, in ms of work per frame: lo keeps updates on time,
-- hi does not.
local function headroomSearch(plan, label)
    plan.act(function(_, ctx)
        ctx.search = { lo = 0, hi = HEADROOM.top, step = 0, load = 0, base = true, log = {} }
        spinLoops = 0
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        if ctx.spot then player.Position, player.Velocity = ctx.spot, Vector.Zero end
        local s = ctx.search
        local done, interval = headroomWindow(s, Isaac.GetTime())
        if not done then return false, string.format("load %.2f ms, step %d", s.load, s.step) end
        s.log[#s.log + 1] = string.format("%.2f->%.1f", s.load, interval)
        local onTime = interval <= HEADROOM.late
        if s.base then
            -- The first window has no load: is the scene on time at all?
            s.base, s.baseInterval, s.baseOnTime = false, interval, onTime
            if not onTime then
                spinLoops = 0
                return true
            end
        else
            if onTime then s.lo = s.load else s.hi = s.load end
            s.step = s.step + 1
            if s.step >= HEADROOM.steps then
                spinLoops = 0
                return true
            end
        end
        s.load = (s.lo + s.hi) / 2
        spinLoops = math.floor(s.load * ctx.loopsPerMs + 0.5)
        return false, string.format("load %.2f ms", s.load)
    end, (HEADROOM.window + HEADROOM.settle + 5) * (HEADROOM.steps + 2) * 2, label)
    plan.act(function(_, ctx)
        spinLoops = 0
        local s = ctx.search
        ctx.headroom = ctx.headroom or {}
        ctx.headroom[label] = s.baseOnTime and s.lo or 0
        ctx.last = { label = label, headroom = ctx.headroom[label], base = s.baseInterval, onTime = s.baseOnTime,
            log = table.concat(s.log, " "), mines = #M().mines(), entities = #Isaac.GetRoomEntities() }
    end)
    plan.note(label, function(_, ctx)
        local l, zero = ctx.last, ctx.headroom["no mines"]
        local cost = zero and l.onTime and string.format(", so they cost %.2f ms of each frame (%.2f ms an update)",
            zero - l.headroom, 2 * (zero - l.headroom)) or ""
        return string.format("%d mines, %d entities: %s %.1f ms/update with no load; headroom %.2f ms of work per"
            .. " frame%s [load->interval: %s]", l.mines, l.entities, l.onTime and "on time" or "LATE", l.base,
            l.headroom, cost, l.log)
    end)
end

-- Sets the scene up for a headroom search: the player at the left, the enemy
-- pinned, and the busy loop calibrated (how many loops make a millisecond,
-- timed over about a third of a second so the 1 ms clock is a fraction of a
-- percent).
local function headroomSetup(plan, id)
    setup(plan, id)
    plan.require("wall clock available", function()
        return type(Isaac.GetTime) == "function" or nil, "needs Isaac.GetTime"
    end)
    withEnemy(plan)
    plan.act(function(player, ctx)
        ctx.spot = leftSide(Game():GetRoom())
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        table.insert(ctx.cleanupFns, 1, function() spinLoops = 0 end)
        local loops, t0 = 200000, Isaac.GetTime()
        while true do
            local start = Isaac.GetTime()
            spin(loops)
            local took = Isaac.GetTime() - start
            if took >= 300 then
                ctx.loopsPerMs = loops / took
                break
            end
            loops = loops * 2
            if Isaac.GetTime() - t0 > 5000 then error("calibration took too long") end
        end
    end)
    plan.note("busy loop", function(_, ctx) return string.format("%.0f loops per ms", ctx.loopsPerMs) end)
    plan.wait(30)
end

S.add("LANDMINE", "headroom", { conditions = true }, function(plan, id)
    headroomSetup(plan, id)
    headroomSearch(plan, "no mines")
    fillMines(plan, 300)
    headroomSearch(plan, "300 mines")
    fillMines(plan, 1000)
    headroomSearch(plan, "1000 mines")
    fillMines(plan, 2000)
    headroomSearch(plan, "2000 mines")
end)
S.rows[#S.rows].manual = true

-- Measurement only (run by name): the same 250 mines drawn by the field and
-- as 250 effect entities of their own (the way mines were drawn before
-- 2026-11-25), each against the headroom with no mines.
S.add("LANDMINE", "headroom_compare", { conditions = true }, function(plan, id)
    headroomSetup(plan, id)
    headroomSearch(plan, "no mines")
    fillMines(plan, 250)
    headroomSearch(plan, "250 mines drawn by the field")
    plan.act(function(player, ctx)
        local spots = {}
        for _, record in ipairs(M().mines()) do spots[#spots + 1] = record.spot end
        clearMines()
        ctx.entityMines = {}
        for _, spot in ipairs(spots) do
            local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, M().mineVariant(), 0, spot, Vector.Zero, player)
            effect = effect and effect:ToEffect()
            if effect then
                effect.DepthOffset = -1000
                effect:GetSprite():Play("Idle", true)
                ctx.entityMines[#ctx.entityMines + 1] = effect
            end
        end
        table.insert(ctx.cleanupFns, 1, function()
            for _, effect in ipairs(ctx.entityMines or {}) do
                if effect:Exists() then effect:Remove() end
            end
        end)
    end)
    plan.wait(15)
    headroomSearch(plan, "250 mines as entities (the old way)")
    plan.note("entity mines", function(_, ctx) return #ctx.entityMines .. " effect entities of the mine's variant" end)
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

-- A blast is the holder's damage (user decision 2026-11-27; half from
-- 2026-11-25, twice before that).
local BLAST = 1

-- Whether the enemy lost exactly what was recorded, every blast the holder's
-- damage and every tear hit the holder's damage.
local function exactLoss(ctx, damage)
    local sum, bad, mines = 0, 0, 0
    for _, hit in ipairs(ctx.hits or {}) do
        sum = sum + hit.amount
        if hit.kind == "mine" then
            mines = mines + 1
            if not H.near(hit.amount, BLAST * damage) then bad = bad + 1 end
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
        return e.landedOn >= 1, describeMines()
    end)
    plan.check("the enemy lost exactly its tear hits and the holder's damage for every blast", function(_, ctx)
        local ok, blasts, detail = exactLoss(ctx, ctx.damage)
        return ok and blasts >= 1, detail
    end)
    plan.section("LANDMINE / on_enemy", "tears hit the maggot and burst into mines around it; those landing on it blow up in green at once")
end)

-- A player walking onto an armed mine sets it off and takes no damage; the
-- enemy beside it loses the holder's damage.
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
    plan.check("the enemy beside it lost exactly the holder's damage", function(_, ctx)
        local ok, blasts, detail = exactLoss(ctx, ctx.damage)
        return ok and blasts == 1, detail
    end)
    plan.check("the player was not hurt", function(player, ctx)
        local hits = playerHits or {}
        return #hits == 0 and health(player) == ctx.health,
            string.format("playerHits=[%s] health %d -> %d", table.concat(hits, "; "), ctx.health, health(player))
    end)
end)

-- A dud (user decisions 2026-11-28): first a real bomb of the player's own, as
-- strong as the dud, at their feet shows what it does to them (the control);
-- then the player
-- steps on a dud beside a pinned enemy and a rock. It goes off as a real bomb:
-- the player takes the same hit as from the real bomb, the enemy loses twice
-- the mine's damage and the rock breaks. An ordinary mine never hurts the player
-- or the room (`player_steps`, `trigger`).
damageCase("dud", function(plan, id)
    plan.section("LANDMINE / dud", "a rusted mine with a fast-blinking button lies there; a real bomb, then the dud, blow up")
    setup(plan, id)
    withEnemy(plan, function(room) return leftSide(room) + Vector(154, 0) end)
    plan.act(function(player, ctx)
        ctx.spot = leftSide(Game():GetRoom()) + Vector(0, 80)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        playerHits = {}
        local bomb = Isaac.Spawn(EntityType.ENTITY_BOMB, BombVariant.BOMB_NORMAL, 0, ctx.spot, Vector.Zero, player)
        bomb = bomb and bomb:ToBomb()
        if bomb then
            -- as strong as the dud will be (a bomb of 100 took a full heart, one
            -- this weak half of one; measured 2026-11-28)
            bomb.ExplosionDamage = player.Damage * M().data.damageMultiplier * M().data.dudDamage
            bomb:SetExplosionCountdown(1)
        end
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        return #playerHits >= 1, "waiting for the bomb"
    end, 60, "control: a real bomb of the player's at their feet hurts them")
    plan.act(function(_, ctx)
        ctx.control = playerHits[1]
        playerHits = nil
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        local cooldown = type(player.GetDamageCooldown) == "function" and player:GetDamageCooldown() or 0
        return cooldown <= 0, "damage cooldown " .. cooldown
    end, 150, "the player can be hurt again")
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        ctx.spot = leftSide(room)
        ctx.mineSpot = ctx.spot + Vector(120, 0)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        ctx.damage = player.Damage
        ctx.rockIndex = room:GetGridIndex(ctx.mineSpot + Vector(0, -40))
        room:RemoveGridEntity(ctx.rockIndex, 0, false)
        ctx.rockMade = Isaac.GridSpawn(GridEntityType.GRID_ROCK, 0, room:GetGridPosition(ctx.rockIndex), true) ~= nil
        ctx.mine = T().lay(player, ctx.mineSpot, player.Damage, nil, nil, { dud = true })
    end)
    armed(plan, "the dud is armed with nobody on it")
    plan.require("one armed dud, the enemy within its blast but not on it, a rock above it", function(_, ctx)
        local reach = M().data.triggerRadius + ctx.target.Size
        local gap = ctx.target.Position:Distance(ctx.mineSpot)
        return #roomMines() == 1 and ctx.mine and ctx.mine.dud == true and ctx.rockMade and gap > reach
            and gap <= M().data.blastRadius + ctx.target.Size,
            string.format("enemy %.1f from the mine, reach %.1f dud=%s rock=%s %s", gap, reach,
                tostring(ctx.mine and ctx.mine.dud), tostring(ctx.rockMade), describeMines())
    end)
    plan.act(function(player, ctx)
        ctx.health = health(player)
        ctx.hpBefore = ctx.target.HitPoints
        playerHits = {}
        ctx.spot = ctx.mineSpot
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        return evidence().exploded >= 1, "waiting for the player to set it off"
    end, 10, "the player steps on the dud")
    plan.wait(3)
    plan.check("the player set the dud off and it went off as a real bomb", function()
        local e = evidence()
        return e.byPlayer == 1 and e.exploded == 1 and e.realBlasts == 1 and #roomMines() == 0,
            string.format("realBlasts=%d %s", e.realBlasts, describeMines())
    end)
    plan.check("the enemy beside it lost twice the mine's damage", function(_, ctx)
        local lost = ctx.hpBefore - (ctx.target:Exists() and ctx.target.HitPoints or 0)
        local want = ctx.damage * M().data.dudDamage
        return math.abs(lost - want) <= 0.01 * want, string.format("lost %.3f, want %.3f", lost, want)
    end)
    plan.check("the dud hurt the player once, as their own real bomb did", function(player, ctx)
        local hits = playerHits or {}
        local control = ctx.control and ctx.control:match("amt=[%d.]+ flags=%d+")
        local got = hits[1] and hits[1]:match("amt=[%d.]+ flags=%d+")
        return #hits == 1 and control ~= nil and got == control and health(player) < ctx.health,
            string.format("control=[%s] dud=[%s] health %d -> %d", tostring(ctx.control),
                table.concat(hits, "; "), ctx.health, health(player))
    end)
    plan.check("the rock above it broke", function(_, ctx)
        local grid = Game():GetRoom():GetGridEntity(ctx.rockIndex)
        return grid == nil or grid.State == 2 or grid:GetType() ~= GridEntityType.GRID_ROCK,
            grid and string.format("type=%d state=%d", grid:GetType(), grid.State) or "gone"
    end)
    -- A dud the enemy sets off far from the player spares the player.
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        local cooldown = type(player.GetDamageCooldown) == "function" and player:GetDamageCooldown() or 0
        return cooldown <= 0, "damage cooldown " .. cooldown
    end, 150, "the player can be hurt again")
    plan.act(function(player, ctx)
        T().resetEvidence()
        ctx.spot = leftSide(Game():GetRoom())
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        ctx.farMine = T().lay(player, ctx.target.Position, player.Damage, nil, nil, { dud = true })
        ctx.health = health(player)
        playerHits = {}
    end)
    plan.waitUntil(function(player, ctx)
        pin(ctx)
        player.Position, player.Velocity = ctx.spot, Vector.Zero
        return evidence().exploded >= 1, describeMines()
    end, 30, "the enemy sets off a dud far from the player")
    plan.wait(3)
    plan.check("a dud the enemy set off far away left the player unhurt", function(player, ctx)
        local hits = playerHits or {}
        local gap = ctx.spot:Distance(ctx.farMine.spot)
        return evidence().realBlasts == 1 and #hits == 0 and health(player) == ctx.health,
            string.format("gap=%.0f realBlasts=%d hits=[%s] health %d -> %d", gap, evidence().realBlasts,
                table.concat(hits, "; "), ctx.health, health(player))
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
    plan.check("both blasts reached the enemy, the holder's damage each", function(_, ctx)
        local ok, blasts, detail = exactLoss(ctx, ctx.damage)
        return ok and blasts == 2, detail
    end)
end)

-- An enemy walking onto an armed mine sets it off: it loses exactly the
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
    plan.check("the enemy lost exactly the holder's damage", function(_, ctx)
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
