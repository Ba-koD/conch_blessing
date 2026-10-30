local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 인 (Tiger): the lifecycle contract and its isolated cases. Every kill is a
-- real lethal hit through the engine's damage path, every 창귀 the engine's own
-- Purgatory soul, and every explosion check reads the enemy's actual HP.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function tiger() return ConchBlessing.tiger end

-- ---------------------------------------------------------------- observers
-- `log` records every damage, kill, death, removal and ghost spawn while the
-- measurement observes, in callback order, so DIAG lines show what the engine
-- did. `deaths` keeps each test target's native kill (HP and place) for the
-- gameplay cases; it is never a substitute for the kill evidence itself.
local log
local order = 0
local deaths = {}
local explosionHook

local function describeEntity(entity)
    if not entity then return "nil" end
    local spawner = entity.SpawnerEntity
    return string.format("%d.%d.%d%s", entity.Type, entity.Variant, entity.SubType,
        spawner and string.format("<%d.%d", spawner.Type, spawner.Variant) or "")
end

local function push(kind, text)
    if not log then return end
    order = order + 1
    log[#log + 1] = string.format("#%d f%d %s %s", order, Game():GetFrameCount(), kind, text)
end

local function observe(name, fn, filter)
    if ModCallbacks[name] then ConchBlessing:AddCallback(ModCallbacks[name], fn, filter) end
end

observe("MC_ENTITY_TAKE_DMG", function(_, entity, amount, flags, source)
    if not log or entity.Type == EntityType.ENTITY_PLAYER then return end
    push("pre", string.format("%s@%.0f,%.0f amt=%.3f flags=%d hp=%.3f src=%s", describeEntity(entity),
        entity.Position.X, entity.Position.Y, amount, flags, entity.HitPoints, describeEntity(source and source.Entity)))
end)
observe("MC_POST_ENTITY_TAKE_DMG", function(_, entity, amount, flags, source, _, extra)
    if not log or entity.Type == EntityType.ENTITY_PLAYER then return end
    push("post", string.format("%s amt=%.3f flags=%d hp=%.3f src=%s extra=%s", describeEntity(entity), amount, flags,
        entity.HitPoints, describeEntity(source and source.Entity), describeEntity(extra and extra.Entity)))
end)
observe("MC_POST_ENTITY_KILL", function(_, entity)
    local token = entity:GetData().__ConchBlessingTestTarget
    if token then deaths[token] = { hp = entity.HitPoints, x = entity.Position.X, y = entity.Position.Y } end
    if log then push("kill", describeEntity(entity) .. string.format(" hp=%.3f", entity.HitPoints)) end
end)
observe("MC_POST_NPC_DEATH", function(_, npc)
    if log then push("npcDeath", describeEntity(npc)) end
end)
observe("MC_POST_ENTITY_REMOVE", function(_, entity)
    if log and (entity.Type == EntityType.ENTITY_EFFECT and (entity.Variant == EffectVariant.PURGATORY
        or entity.Variant == EffectVariant.ENEMY_GHOST) or entity:ToNPC()) then push("remove", describeEntity(entity)) end
end)
observe("MC_POST_EFFECT_INIT", function(_, effect)
    if not log or (effect.Variant ~= EffectVariant.PURGATORY and effect.Variant ~= EffectVariant.ENEMY_GHOST) then return end
    push("effectInit", describeEntity(effect) .. string.format(" at %.0f,%.0f", effect.Position.X, effect.Position.Y))
    if explosionHook and effect.Variant == EffectVariant.ENEMY_GHOST then explosionHook(effect) end
end)

local function startLog() log, order = {}, 0 end
local function stopLog()
    local lines = log or {}
    log = nil
    return lines
end

local function chunks(lines, size)
    local out = {}
    for i = 1, #lines, size do out[#out + 1] = table.concat(lines, " | ", i, math.min(#lines, i + size - 1)) end
    return out
end

-- Each fixture's test token, kept here so a removed entity's data is never read.
local tokens = setmetatable({}, { __mode = "k" })

local function targetAt(player, offset, hp)
    local npc = H.target(player, true)
    npc.Position = player.Position + offset
    npc.HitPoints, npc.MaxHitPoints = hp, hp
    tokens[npc] = npc:GetData().__ConchBlessingTestTarget
    return npc
end

local function died(npc) return npc and tokens[npc] and deaths[tokens[npc]] end

-- Live 창귀 (Purgatory souls) and their explosions in the room, NO_QUERY included.
local function ghosts(player)
    local list = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == EffectVariant.PURGATORY
            and entity.SubType == 1 and entity:Exists() then
            local spawner = entity.SpawnerEntity
            if not player or spawner and GetPtrHash(spawner) == GetPtrHash(player) then list[#list + 1] = entity end
        end
    end
    return list
end

local function clearGhosts()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_EFFECT and (entity.Variant == EffectVariant.PURGATORY
            or entity.Variant == EffectVariant.ENEMY_GHOST) then entity:Remove() end
    end
end

local function cleanupOnExit(ctx, list)
    ctx.cleanupFns = ctx.cleanupFns or {}
    table.insert(ctx.cleanupFns, function()
        log, explosionHook = nil, nil
        for _, npc in ipairs(list(ctx)) do if npc and npc:Exists() then npc:Remove() end end
        clearGhosts()
    end)
end

local function requireModule(plan)
    plan.require("Tiger module and the vanilla Purgatory soul available", function()
        local module = tiger()
        return module and module._test and EffectVariant.PURGATORY and EffectVariant.ENEMY_GHOST and true or nil,
            "module or effect enum missing"
    end)
end

local function give(player, id, copies)
    while player:GetCollectibleNum(id) < copies do player:AddCollectible(id, 0, false) end
end

local function evidence() return tiger()._test.evidence() end

C.TIGER = { stage = function(plan, id, n)
    plan.check("kill chance is 1/3 per copy, at most certain", function(player)
        local expected = math.min(1, n / 3)
        local actual = tiger()._test.chanceFor(tiger().copies(player))
        return math.abs(actual - expected) < 1e-9, string.format("copies=%d chance=%.4f expected %.4f", n, actual, expected)
    end)
    if n == 0 then
        plan.act(function(player, ctx)
            tiger()._test.resetEvidence()
            H.killTarget(player, ctx)
        end)
        plan.waitUntil(H.deathObserved, 90, "real target lethal hit and death without Tiger")
        plan.wait(2)
        plan.check("without Tiger a real kill raises no 창귀", function(player)
            local e = evidence()
            return #ghosts(player) == 0 and e.rolls == 0 and e.spawned == 0,
                string.format("ghosts=%d rolls=%d spawned=%d", #ghosts(player), e.rolls, e.spawned)
        end)
    end
end }

-- A real kill by the holder with three copies always raises one 창귀, owned by
-- the holder, where the enemy died.
S.add("TIGER", "kill_proc", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        cleanupOnExit(ctx, function(c) return { c.target } end)
        give(player, id, 3)
        tiger()._test.resetEvidence()
        H.killTarget(player, ctx)
    end)
    plan.waitUntil(H.deathObserved, 90, "real target lethal hit and death")
    plan.check("native enemy death confirmed independently", H.deathObserved)
    plan.wait(2)
    plan.check("the kill raised exactly one 창귀 where the enemy died", function(player, ctx)
        local list, death = ghosts(player), deaths[ctx.deathToken]
        local ghost = list[1]
        local distance = ghost and death and ghost.Position:Distance(Vector(death.x, death.y)) or -1
        return #list == 1 and distance >= 0 and distance <= 4,
            string.format("ghosts=%d distance=%.1f deathHP=%s", #list, distance, tostring(death and death.hp))
    end)
    plan.check("one roll at 100% with three copies", function()
        local e = evidence()
        return e.rolls == 1 and e.spawned == 1 and e.lastRoll and e.lastRoll.chance == 1,
            string.format("rolls=%d spawned=%d chance=%s", e.rolls, e.spawned, tostring(e.lastRoll and e.lastRoll.chance))
    end)
    plan.section("TIGER / kill_proc", "a red ghost rises from where the enemy died")
end)

-- Kills that are not the holder's raise nothing: another enemy's hit, a hit
-- with no source, and a direct Kill() of an enemy the holder had hit. A
-- holder's kill in the same run is the control.
S.add("TIGER", "other_kills", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        cleanupOnExit(ctx, function(c) return { c.byEnemy, c.killer, c.bySourceless, c.byKill, c.control } end)
        give(player, id, 3)
        ctx.byEnemy = targetAt(player, Vector(120, 100), 10)
        ctx.killer = targetAt(player, Vector(-160, 100), 1000)
        ctx.bySourceless = targetAt(player, Vector(120, -100), 10)
        ctx.byKill = targetAt(player, Vector(-120, -100), 1000)
        ctx.control = targetAt(player, Vector(180, 0), 10)
    end)
    plan.waitUntil(function(_, ctx)
        for _, npc in ipairs({ ctx.byEnemy, ctx.killer, ctx.bySourceless, ctx.byKill, ctx.control }) do
            if not H.targetReady(npc) then return false, "targets initializing" end
        end
        return true
    end, 30, "targets ready")
    plan.act(function(player, ctx)
        tiger()._test.resetEvidence()
        ctx.byEnemy:TakeDamage(30, 0, EntityRef(ctx.killer), 0)
        ctx.bySourceless:TakeDamage(30, 0, EntityRef(nil), 0)
        ctx.byKill:TakeDamage(5, 0, EntityRef(player), 0)
    end)
    plan.wait(3)
    plan.act(function(_, ctx) ctx.byKill:Kill() end)
    plan.waitUntil(function(_, ctx)
        return died(ctx.byEnemy) and died(ctx.bySourceless) and died(ctx.byKill) and true or false,
            "waiting for the three native kills"
    end, 60, "the three non-holder kills happen")
    plan.wait(2)
    plan.check("another enemy's kill, a sourceless kill and a direct Kill() raise no 창귀", function(player, ctx)
        local e = evidence()
        return #ghosts() == 0 and e.spawned == 0 and e.rolls == 0,
            string.format("ghosts=%d rolls=%d spawned=%d killHP=%.1f", #ghosts(), e.rolls, e.spawned, died(ctx.byKill).hp)
    end)
    plan.act(function(player, ctx) ctx.control:TakeDamage(30, 0, EntityRef(player), 0) end)
    plan.waitUntil(function(_, ctx) return died(ctx.control) ~= nil end, 30, "the holder's control kill happens")
    plan.wait(2)
    plan.check("control: the holder's own kill in the same run raises one", function(player)
        local e = evidence()
        return #ghosts(player) == 1 and e.spawned == 1, string.format("ghosts=%d spawned=%d", #ghosts(player), e.spawned)
    end)
end)

-- The 창귀 flies to the only enemy left and bursts: that enemy loses exactly
-- three times the holder's damage, once, and is feared for three seconds.
S.add("TIGER", "explosion", { damage = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        cleanupOnExit(ctx, function(c) return { c.victim, c.target } end)
        give(player, id, 3)
        ctx.victim = targetAt(player, Vector(120, 0), 10)
        ctx.target = targetAt(player, Vector(200, 80), 1000)
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.victim) and H.targetReady(ctx.target) end, 30, "targets ready")
    plan.act(function(player, ctx)
        tiger()._test.resetEvidence()
        ctx.damage, ctx.before = player.Damage, ctx.target.HitPoints
        ctx.victim:TakeDamage(30, 0, EntityRef(player), 0)
    end)
    plan.waitUntil(function() return evidence().spawned >= 1 end, 30, "the kill raises a 창귀")
    plan.waitUntil(function() return evidence().hits >= 1 end, 300, "the 창귀 reaches the enemy and explodes")
    -- The vanilla explosion ticks again at its frames 3, 8 and 13; all are cancelled.
    plan.wait(20)
    plan.check("the enemy lost exactly 3x the holder's damage, once", function(_, ctx)
        local loss, expected = ctx.before - ctx.target.HitPoints, 3 * ctx.damage
        local e = evidence()
        return H.near(loss, expected) and e.hits == 1,
            string.format("loss=%.4f expected=%.4f hits=%d cancelled=%d", loss, expected, e.hits, e.cancelled)
    end)
    plan.check("the vanilla explosion's own ticks were cancelled", function()
        local e = evidence()
        return e.claimed == 1 and e.cancelled >= 1, string.format("claimed=%d cancelled=%d", e.claimed, e.cancelled)
    end)
    plan.check("the enemy it hit is feared", function(_, ctx)
        return ctx.target:HasEntityFlags(EntityFlag.FLAG_FEAR), "fear=" .. tostring(ctx.target:HasEntityFlags(EntityFlag.FLAG_FEAR))
    end)
    plan.wait(55)
    plan.check("still feared 2.5 seconds after the hit", function(_, ctx)
        return ctx.target:HasEntityFlags(EntityFlag.FLAG_FEAR), "fear=" .. tostring(ctx.target:HasEntityFlags(EntityFlag.FLAG_FEAR))
    end)
    plan.waitUntil(function(_, ctx) return not ctx.target:HasEntityFlags(EntityFlag.FLAG_FEAR) end, 40,
        "fear ends about 3 seconds after the hit")
    plan.section("TIGER / explosion", "the red ghost flies at the enemy and bursts in a red explosion")
end)

-- A 창귀's kill is the holder's kill: with three copies it raises the next 창귀,
-- which flies on to the last enemy.
S.add("TIGER", "chain", { damage = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        cleanupOnExit(ctx, function(c) return { c.first, c.second, c.last } end)
        give(player, id, 3)
        ctx.damage = player.Damage
        ctx.first = targetAt(player, Vector(100, 0), 10)
        ctx.second = targetAt(player, Vector(150, 50), 2 * player.Damage)
        ctx.last = targetAt(player, Vector(-260, 0), 1000)
    end)
    plan.waitUntil(function(_, ctx)
        return H.targetReady(ctx.first) and H.targetReady(ctx.second) and H.targetReady(ctx.last)
    end, 30, "targets ready")
    plan.act(function(player, ctx)
        tiger()._test.resetEvidence()
        ctx.before = ctx.last.HitPoints
        ctx.first:TakeDamage(30, 0, EntityRef(player), 0)
    end)
    plan.waitUntil(function(_, ctx) return died(ctx.second) ~= nil end, 300, "the first 창귀 kills the second enemy")
    plan.waitUntil(function() return evidence().spawned >= 2 end, 30, "that kill raises the next 창귀")
    plan.waitUntil(function() return evidence().hits >= 2 end, 300, "the next 창귀 reaches the last enemy")
    plan.wait(20)
    plan.check("the second enemy died from the 창귀's explosion", function(_, ctx)
        local death = died(ctx.second)
        return death and death.hp <= 0, "deathHP=" .. tostring(death and death.hp)
    end)
    plan.check("the chained 창귀 hit the last enemy for 3x the holder's damage", function(_, ctx)
        local loss, expected = ctx.before - ctx.last.HitPoints, 3 * ctx.damage
        local e = evidence()
        return H.near(loss, expected) and e.spawned == 2,
            string.format("loss=%.4f expected=%.4f spawned=%d hits=%d", loss, expected, e.spawned, e.hits)
    end)
end)

-- Many real kills at once per copy count: about 1/3 and 2/3 of them raise a
-- 창귀, and all of them from three copies. The exact odds are `conch_test rng`.
S.add("TIGER", "odds", { conditions = true }, function(plan, id)
    local KILLS = 36
    -- Three standard deviations around n/3 of KILLS (an outside sample is a FAIL).
    local bounds = { [1] = { 4, 20 }, [2] = { 16, 32 }, [3] = { KILLS, KILLS } }
    requireModule(plan)
    plan.act(function(_, ctx) cleanupOnExit(ctx, function(c) return c.victims or {} end) end)
    for copies = 1, 3 do
        plan.act(function(player, ctx)
            clearGhosts()
            for _, npc in ipairs(ctx.victims or {}) do if npc:Exists() then npc:Remove() end end
            give(player, id, copies)
            ctx.victims = {}
            -- Three rings of twelve, flattened to stay inside a 1x1 room.
            for i = 1, KILLS do
                local angle, ring = math.rad(i * 30), (i - 1) // 12
                ctx.victims[i] = targetAt(player, Vector(math.cos(angle) * (120 + 50 * ring),
                    math.sin(angle) * (60 + 25 * ring)), 10)
            end
        end)
        plan.waitUntil(function(_, ctx)
            for _, npc in ipairs(ctx.victims) do if not H.targetReady(npc) then return false, "victims initializing" end end
            return true
        end, 30, KILLS .. " victims ready")
        plan.act(function(player, ctx)
            tiger()._test.resetEvidence()
            for _, npc in ipairs(ctx.victims) do npc:TakeDamage(30, 0, EntityRef(player), 0) end
        end)
        plan.waitUntil(function(_, ctx)
            for _, npc in ipairs(ctx.victims) do if not died(npc) then return false, "kills pending" end end
            return true
        end, 30, "every victim really dies")
        plan.wait(2)
        plan.check(string.format("%d cop%s: %d kills raise about %d%% 창귀", copies, copies == 1 and "y" or "ies", KILLS,
            math.floor(math.min(1, copies / 3) * 100 + 0.5)), function(player)
            local e = evidence()
            local low, high = bounds[copies][1], bounds[copies][2]
            return e.rolls == KILLS and e.spawned >= low and e.spawned <= high and #ghosts(player) == e.spawned,
                string.format("rolls=%d spawned=%d (bounds %d-%d) ghosts=%d", e.rolls, e.spawned, low, high, #ghosts(player))
        end)
    end
end)

-- How the vanilla Purgatory soul (1000.189.1) moves and deals its damage when a
-- player spawns it, and in what order the engine reports a lethal hit, a kill
-- and a removal. A measurement for designing the 창귀; it checks nothing. Run
-- with Tiger unheld. Measured 2026-10-31: the soul appears for 39 frames,
-- charges its target and bursts into Ghost Bombs' explosion (1000.144.1, spawner
-- the player), which ticks 2x the player's damage at its frames 0, 3, 8 and 13
-- with no source and overwrites a CollisionDamage set at its init; a lethal hit
-- kills on the next update with HP below 0, a direct Kill() keeps its HP.
local function flySoul(plan, label, zeroExplosion)
    plan.act(function(player, ctx)
        for _, npc in ipairs(ctx.targets or {}) do if npc:Exists() then npc:Remove() end end
        ctx.targets = {
            targetAt(player, Vector(160, 0), 1000), targetAt(player, Vector(200, 50), 1000),
            targetAt(player, Vector(-220, 60), 1000),
        }
    end)
    plan.waitUntil(function(_, ctx)
        for _, npc in ipairs(ctx.targets) do if not H.targetReady(npc) then return false end end
        return true
    end, 30, "targets ready")
    plan.act(function(player, ctx)
        startLog()
        ctx.zeroExplosion = zeroExplosion
        ctx.damage = player.Damage
        ctx.soul = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.PURGATORY, 1,
            player.Position + Vector(0, -40), Vector.Zero, player):ToEffect()
        ctx.anims, ctx.lastAnim, ctx.soulFrames, ctx.explosion = {}, nil, 0, nil
    end)
    plan.waitUntil(function(_, ctx)
        local soul = ctx.soul
        if soul:Exists() then
            ctx.soulFrames = ctx.soulFrames + 1
            local anim = soul:GetSprite():GetAnimation()
            if anim ~= ctx.lastAnim then
                ctx.lastAnim = anim
                ctx.anims[#ctx.anims + 1] = string.format("f%d %s target=%s", soul.FrameCount, anim, describeEntity(soul.Target))
            end
            return false
        end
        local e = ctx.explosion
        if e and e:Exists() then
            push("boom", string.format("f%d anim=%s frame=%d collisionDamage=%.3f size=%.1f radius=%.1f",
                e.FrameCount, e:GetSprite():GetAnimation(), e:GetSprite():GetFrame(), e.CollisionDamage, e.Size,
                e.SizeMulti and e.SizeMulti.X or -1))
            return false
        end
        return e ~= nil
    end, 300, label)
    plan.wait(6)
    plan.act(function(_, ctx) ctx.soulLog = stopLog() end)
    plan.note(label .. " timeline", function(_, ctx)
        local hp = {}
        for _, npc in ipairs(ctx.targets) do hp[#hp + 1] = string.format("%.1f fear=%s", npc.HitPoints,
            tostring(npc:HasEntityFlags(EntityFlag.FLAG_FEAR))) end
        return string.format("damage=%.3f life=%d anims=[%s] targets=[%s]", ctx.damage, ctx.soulFrames,
            table.concat(ctx.anims, "; "), table.concat(hp, ", "))
    end)
    for i = 1, 5 do
        plan.note(label .. " events " .. i, function(_, ctx) return chunks(ctx.soulLog, 5)[i] or "-" end)
    end
end


S.add("TIGER", "ghost_native", {}, function(plan)
    plan.act(function(_, ctx)
        cleanupOnExit(ctx, function(c)
            local list = { c.lethal, c.direct }
            for _, npc in ipairs(c.targets or {}) do list[#list + 1] = npc end
            return list
        end)
        explosionHook = function(effect)
            ctx.explosion = effect
            push("boomInit", string.format("collisionDamage=%.3f size=%.1f", effect.CollisionDamage, effect.Size))
            if ctx.zeroExplosion then effect.CollisionDamage = 0 end
        end
    end)
    flySoul(plan, "native soul", false)
    flySoul(plan, "soul with explosion CollisionDamage 0", true)
    -- A lethal player hit, then a direct Kill() of a damaged enemy.
    plan.act(function(player, ctx)
        ctx.lethal = targetAt(player, Vector(120, 120), 10)
        ctx.direct = targetAt(player, Vector(-120, 120), 1000)
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.lethal) and H.targetReady(ctx.direct) end, 30, "kill targets ready")
    plan.act(function(player, ctx)
        startLog()
        push("call", "lethal TakeDamage(20) from player")
        ctx.lethal:TakeDamage(20, 0, EntityRef(player), 0)
        push("call", "returned")
    end)
    plan.wait(4)
    plan.act(function(player, ctx)
        push("call", "direct TakeDamage(5) from player")
        ctx.direct:TakeDamage(5, 0, EntityRef(player), 0)
    end)
    plan.wait(4)
    plan.act(function(_, ctx)
        push("call", string.format("Kill() hp=%.1f", ctx.direct.HitPoints))
        ctx.direct:Kill()
        push("call", "returned")
    end)
    plan.wait(4)
    plan.act(function(_, ctx) ctx.killLog = stopLog() end)
    for i = 1, 4 do
        plan.note("kill events " .. i, function(_, ctx) return chunks(ctx.killLog, 6)[i] or "-" end)
    end
end)
S.rows[#S.rows].manual = true

return C
