local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 레인메이커의 장미 (Rose of the Rainmaker): the lifecycle contract and its
-- cases. The expected numbers are the user's design (2026-11-27), written out
-- here rather than read from the module: a homing tear of the holder falls
-- from the sky for every copy every 3 x (MaxFireDelay + 1) updates, a hit the
-- holder really takes brings down 25 at once, self-damage brings none, and
-- shot speed rises by 0.2 once. Every drop is checked as a real tear in the
-- room (owner, homing, high start, unaimed mark), and the rain's damage as HP
-- the target really lost.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local function R() return ConchBlessing.rainmakersRose end
local function T() return R()._test end

local MARK = "__ConchBlessingRainmakersRose"
local DOWNPOUR = 25
local SHOT_SPEED = 0.2

-- ------------------------------------------------------------------ observers
-- Every marked tear seen in the room while observing, by its pointer: its
-- owner, flags and height the first time it is seen.
local watch = { on = false, seen = {}, list = {}, hits = {} }

local function observe(on)
    watch.on, watch.seen, watch.list, watch.hits = on, {}, {}, {}
end

-- Offline bench tests load this file with only a few callback ids.
local function on(id, fn)
    if type(id) == "number" then ConchBlessing:AddCallback(id, fn) end
end

on(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
    if not watch.on or not tear:GetData()[MARK] then return end
    local hash = GetPtrHash(tear)
    if watch.seen[hash] then return end
    watch.seen[hash] = true
    local owner = tear.SpawnerEntity or tear.Parent
    watch.list[#watch.list + 1] = {
        owner = owner and GetPtrHash(owner), homing = tear:HasTearFlags(TearFlags.TEAR_HOMING),
        height = tear.Height, unaimed = tear:GetData().__ConchBlessingUnaimed == true,
        born = Game():GetFrameCount() - tear.FrameCount, variant = tear.Variant, visible = tear.Visible,
        damage = tear.CollisionDamage, scale = tear.Scale,
    }
end)

local damageCallback = ModCallbacks.MC_POST_ENTITY_TAKE_DMG or ModCallbacks.MC_ENTITY_TAKE_DMG
on(damageCallback, function(_, entity, amount, _, source)
    if not watch.on or (tonumber(amount) or 0) <= 0 then return end
    local from = source and source.Entity
    if not (from and from.Type == EntityType.ENTITY_TEAR and from:GetData()[MARK]) then return end
    watch.hits[#watch.hits + 1] = { target = GetPtrHash(entity), amount = amount }
end)

local function give(player, id, copies)
    while player:GetCollectibleNum(id) < copies do player:AddCollectible(id, 0, false) end
    while player:GetCollectibleNum(id) > copies do player:RemoveCollectible(id) end
end

local function requireModule(plan)
    plan.require("Rose of the Rainmaker module ready", function()
        return R() and R()._test and true or nil, "module missing"
    end)
end

-- The drops seen whose tear was born from `from` to `to`: a drop fired before
-- the window may still be falling when it opens, and is not one of its drops.
local function seenBetween(from, to)
    local out = {}
    for _, drop in ipairs(watch.list) do
        if drop.born >= from and drop.born <= to then out[#out + 1] = drop end
    end
    return out
end

-- Whether every drop is the player's homing tear starting high and unaimed.
local function dropsAreRain(player, drops)
    local bad = 0
    for _, drop in ipairs(drops) do
        if drop.owner ~= GetPtrHash(player) or not drop.homing or drop.height > -300 or not drop.unaimed then
            bad = bad + 1
        end
    end
    return bad == 0, string.format("%d drops, %d not the holder's high homing unaimed tear", #drops, bad)
end

-- The item's share of shot speed: with every copy, less with none.
local function measureShotSpeed(plan, id)
    plan.act(function(player, ctx)
        ctx.withShot = player.ShotSpeed
        ctx.held = player:GetCollectibleNum(id)
        give(player, id, 0)
    end)
    plan.wait(1)
    plan.act(function(player, ctx)
        ctx.shotShare = ctx.withShot - player.ShotSpeed
        give(player, id, ctx.held)
    end)
    plan.wait(1)
end

-- Rain over `updates` updates: the drops the item fired and the ones seen.
local function rainWindow(plan, updates)
    plan.act(function(player, ctx)
        observe(true)
        T().resetEvidence()
        ctx.every = 3 * (player.MaxFireDelay + 1)
        ctx.startFrame = Game():GetFrameCount()
    end)
    plan.wait(updates)
    plan.act(function(_, ctx)
        ctx.fired = T().evidence.rain
        ctx.endFrame = Game():GetFrameCount()
    end)
    plan.wait(3)
    plan.act(function(_, ctx)
        ctx.drops = seenBetween(ctx.startFrame, ctx.endFrame)
        observe(false)
    end)
end

-- n copies: shot speed +0.2 once, and n drops every 3 x (MaxFireDelay + 1)
-- updates, each a real homing tear of the holder falling from high above.
C.RAINMAKERS_ROSE = { stage = function(plan, id, n)
    requireModule(plan)
    measureShotSpeed(plan, id)
    plan.check(n > 0 and "shot speed +0.2, once whatever the copies" or "without the rose shot speed stays",
        function(_, ctx)
            local want = n > 0 and SHOT_SPEED or 0
            return math.abs(ctx.shotShare - want) < 0.002,
                string.format("%d cop%s: shot speed share %.4f (want %.4f)", n, n == 1 and "y" or "ies", ctx.shotShare, want)
        end)
    local window = 165
    rainWindow(plan, window)
    plan.check(n > 0 and string.format("%d drop%s every third of the tears", n, n == 1 and "" or "s")
        or "without the rose no rain falls", function(player, ctx)
        local low = math.floor(window / ctx.every)
        local ok = ctx.fired % math.max(1, n) == 0 and ctx.fired >= low * n and ctx.fired <= (low + 1) * n
            and #ctx.drops >= ctx.fired - n and #ctx.drops <= ctx.fired
        return ok, string.format("%d cop%s, a drop every %.2f updates: %d fired in %d updates (want %d-%d), %d seen",
            n, n == 1 and "y" or "ies", ctx.every, ctx.fired, window, low * n, (low + 1) * n, #ctx.drops)
    end)
    if n > 0 then
        plan.check("every drop is the holder's homing tear falling from high above", function(player, ctx)
            return dropsAreRain(player, ctx.drops)
        end)
    end
end }

-- A real hit brings down 25 drops at once; a self-inflicted one (Razor
-- Blade's red-heart damage) brings none.
S.add("RAINMAKERS_ROSE", "downpour", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player)
        give(player, id, 1)
        player:AddHearts(12)
    end)
    plan.wait(2)
    plan.act(function()
        observe(true)
        T().resetEvidence()
    end)
    H.hit(plan)
    plan.wait(3)
    plan.check("a real hit brings down 25 drops at once", function(player, ctx)
        local downpour = {}
        for _, drop in ipairs(watch.list) do
            if drop.born >= ctx.hitFrame - 1 and drop.born <= ctx.hitFrame + 1 then downpour[#downpour + 1] = drop end
        end
        local rainOk, detail = dropsAreRain(player, downpour)
        return T().evidence.downpour == DOWNPOUR and #downpour >= DOWNPOUR and rainOk,
            string.format("downpour %d (want %d); born with the hit: %s", T().evidence.downpour, DOWNPOUR, detail)
    end)
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 180, "damage cooldown expires")
    plan.act(function(player, ctx)
        player:AddHearts(4)
        T().resetEvidence()
        ctx.selfAccepted = player:TakeDamage(1, DamageFlag.DAMAGE_RED_HEARTS, EntityRef(player), 30)
    end)
    plan.wait(3)
    plan.check("self-damage (red hearts only) brings no downpour", function(_, ctx)
        return ctx.selfAccepted == true and T().evidence.downpour == 0,
            string.format("accepted %s, downpour %d", tostring(ctx.selfAccepted), T().evidence.downpour)
    end)
    plan.act(function(player)
        observe(false)
        give(player, id, 0)
    end)
    plan.wait(30)
end)

-- The rain hurts enemies with the holder's own tear damage: a target takes
-- hits from marked tears and loses that HP.
S.add("RAINMAKERS_ROSE", "rain_hits", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        give(player, id, 3)
        ctx.target = H.target(player, true)
        ctx.target.Position = Game():GetRoom():GetCenterPos()
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 60, "target ready")
    plan.act(function(player, ctx)
        observe(true)
        ctx.hp0 = ctx.target.HitPoints
        ctx.damage = player.Damage
    end)
    plan.waitUntil(function(_, ctx)
        local n = 0
        for _, hit in ipairs(watch.hits) do if hit.target == GetPtrHash(ctx.target) then n = n + 1 end end
        return n >= 2, string.format("%d rain hits on the target", n)
    end, 900, "the rain hits the target twice")
    plan.act(function(player)
        give(player, id, 0)
    end)
    plan.wait(30)
    plan.check("each rain hit is the holder's tear damage and the target lost it", function(_, ctx)
        local total, ok, n = 0, true, 0
        for _, hit in ipairs(watch.hits) do
            if hit.target == GetPtrHash(ctx.target) then
                n = n + 1
                total = total + hit.amount
                if math.abs(hit.amount - ctx.damage) > 0.01 then ok = false end
            end
        end
        local lost = ctx.hp0 - ctx.target.HitPoints
        return ok and n >= 2 and math.abs(lost - total) < 0.05,
            string.format("%d hits, %.4f damage (each want %.4f), HP lost %.4f", n, total, ctx.damage, lost)
    end)
    plan.act(function(_, ctx)
        observe(false)
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
    end)
end)

-- With Live Eye, the rain is not aimed: drops landing in an empty room are no
-- misses and leave the multiplier where it was.
S.add("RAINMAKERS_ROSE", "live_eye", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.require("Live Eye ready", function()
        local row = ConchBlessing.ItemData.LIVE_EYE
        return row and row.id and row.id > 0 and ConchBlessing.liveeye and true or nil, "Live Eye missing"
    end)
    plan.act(function(player, ctx)
        player:AddCollectible(ConchBlessing.ItemData.LIVE_EYE.id, 0, false)
        give(player, id, 3)
    end)
    plan.wait(2)
    plan.act(function(player, ctx)
        T().resetEvidence()
        ctx.mult = ConchBlessing.liveeye.getMultiplier(player)
        ctx.misses = ConchBlessing.liveeye._counters.misses
    end)
    plan.waitUntil(function() return T().evidence.rain >= 6, string.format("%d drops", T().evidence.rain) end,
        300, "six drops fall")
    plan.act(function(player) give(player, id, 0) end)
    plan.wait(30)
    plan.check("Live Eye scores no rain tear as a miss", function(player, ctx)
        local mult, misses = ConchBlessing.liveeye.getMultiplier(player), ConchBlessing.liveeye._counters.misses
        return math.abs(mult - ctx.mult) < 0.0001 and misses == ctx.misses,
            string.format("%d drops landed; multiplier %.2f -> %.2f, misses %d -> %d", T().evidence.rain,
                ctx.mult, mult, ctx.misses, misses)
    end)
    plan.act(function(player)
        player:RemoveCollectible(ConchBlessing.ItemData.LIVE_EYE.id)
    end)
end)

-- 진's storm (user decision 2026-11-27): while a living player holds 진, two
-- drops fall per copy each time.
S.add("RAINMAKERS_ROSE", "dragon", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.require("진 ready", function()
        local dragon = Isaac.GetItemIdByName("Dragon")
        return dragon > 0 or nil, "Dragon missing"
    end)
    plan.act(function(player)
        give(player, id, 1)
        player:AddCollectible(Isaac.GetItemIdByName("Dragon"), 0, false)
    end)
    plan.wait(5)
    rainWindow(plan, 165)
    plan.check("with 진 the rain falls twice over", function(_, ctx)
        local low = math.floor(165 / ctx.every)
        return ctx.fired >= 2 * low and ctx.fired <= 2 * (low + 1) and ctx.fired % 2 == 0,
            string.format("a drop every %.2f updates: %d fired in 165 updates (want %d-%d, even)", ctx.every,
                ctx.fired, 2 * low, 2 * (low + 1))
    end)
    plan.act(function(player)
        player:RemoveCollectible(Isaac.GetItemIdByName("Dragon"))
        give(player, id, 0)
    end)
    plan.wait(30)
end, { "dragon" })

-- The rain takes the form of the attack (user decision 2026-11-27). Each item
-- is held with three roses until three of its drops have come down: a beam,
-- ring or blast strikes for each (its carrier unseen and harmless), and blades,
-- sword beams and fetuses fall as those tears. Isaac's health never moves.
local FORM_ITEMS = {
    { item = "BRIMSTONE", strike = "brimstone" },
    { item = "TECHNOLOGY", strike = "laser" },
    { item = "TECH_X", strike = "ring" },
    { item = "DR_FETUS", strike = "bomb" },
    { item = "EPIC_FETUS", strike = "rocket" },
    { item = "MOMS_KNIFE", variant = "RAZOR" },
    { item = "SPIRIT_SWORD", variant = "SWORD_BEAM" },
    { item = "C_SECTION", variant = "FETUS" },
}

local function health(player)
    return player:GetHearts() + player:GetSoulHearts() + player:GetBlackHearts() + player:GetBoneHearts()
end

S.add("RAINMAKERS_ROSE", "weapon_forms", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player, ctx)
        give(player, id, 3)
        ctx.target = H.target(player, true)
        ctx.target.Position = Game():GetRoom():GetCenterPos() + Vector(0, 60)
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 60, "target ready")
    for _, entry in ipairs(FORM_ITEMS) do
        local item = CollectibleType["COLLECTIBLE_" .. entry.item]
        if type(item) == "number" and item > 0 then
            plan.act(function(player) player:AddCollectible(item, 0, false) end)
            plan.wait(6)
            plan.act(function(player, ctx)
                observe(true)
                T().resetEvidence()
                ctx.health, ctx.hp0, ctx.startFrame = health(player), ctx.target.HitPoints, Game():GetFrameCount()
            end)
            plan.waitUntil(function()
                local done = entry.strike and T().evidence[entry.strike] or T().evidence.rain
                return done >= 3, string.format("%d", done)
            end, 600, entry.item .. ": three drops come down")
            plan.wait(12)
            if entry.strike then
                -- The strikes must really hurt: wait for the target to lose HP to them.
                plan.waitUntil(function(_, ctx)
                    return ctx.target.HitPoints < ctx.hp0, string.format("target HP %.2f", ctx.target.HitPoints)
                end, 900, entry.item .. ": a strike hurts the target")
            end
            plan.check(entry.item .. (entry.strike and (": the rain strikes as " .. entry.strike)
                or (": the rain falls as " .. entry.variant .. " tears")), function(player, ctx)
                local drops = seenBetween(ctx.startFrame, Game():GetFrameCount())
                local wrong = 0
                for _, drop in ipairs(drops) do
                    if entry.strike and drop.visible then wrong = wrong + 1 end
                    if entry.variant and drop.variant ~= TearVariant[entry.variant] then wrong = wrong + 1 end
                end
                local struck = entry.strike and T().evidence[entry.strike] or 0
                local falls = entry.strike == "bomb" or entry.strike == "rocket"
                local ok = #drops >= 3 and wrong == 0 and (not entry.strike or struck >= 3)
                    and health(player) == ctx.health and (not entry.strike or ctx.target.HitPoints < ctx.hp0)
                    and (not falls or T().evidence.drawn > 0)
                return ok, string.format("%d drops seen, %d of the wrong kind, %d strikes, health %d -> %d,"
                    .. " target lost %.2f, falling bombs/rockets drawn %d", #drops, wrong, struck, ctx.health,
                    health(player), ctx.hp0 - ctx.target.HitPoints, T().evidence.drawn)
            end)
            plan.act(function(player)
                observe(false)
                player:RemoveCollectible(item)
            end)
            plan.wait(20)
        end
    end
    plan.act(function(player, ctx)
        give(player, id, 0)
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
    end)
    plan.wait(30)
end, { "brimstone", "technology", "tech_x", "dr_fetus", "epic_fetus", "moms_knife", "spirit_sword", "c_section" })

-- A measurement (run by name): what the rain is with each attack. For every
-- item that changes the weapon or the tears, three roses rain for 70 updates
-- while Isaac stands still, and the log records the weapons the engine reports,
-- the drops seen (tear variant, damage, scale) and every other entity that
-- appeared in the room meanwhile (type.variant and count).
local PROBE_ITEMS = { "BRIMSTONE", "MONSTROS_LUNG", "DR_FETUS", "IPECAC", "HAEMOLACRIA", "TECHNOLOGY", "TECH_X",
    "MOMS_KNIFE", "EPIC_FETUS", "SPIRIT_SWORD", "LUDOVICO_TECHNIQUE", "C_SECTION", "TECHNOLOGY_2", "TECH_5",
    "NEPTUNUS", "CURSED_EYE", "CHOCOLATE_MILK", "TECHNOLOGY_ZERO" }

local function weaponNames(player)
    local out = {}
    if type(player.HasWeaponType) ~= "function" or not WeaponType then return "unknown" end
    for name, value in pairs(WeaponType) do
        if type(value) == "number" and player:HasWeaponType(value) then out[#out + 1] = name end
    end
    table.sort(out)
    return table.concat(out, ",")
end

local function counted(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    local out = {}
    for _, key in ipairs(keys) do out[#out + 1] = key .. "x" .. map[key] end
    return #out > 0 and table.concat(out, " ") or "none"
end

S.add("RAINMAKERS_ROSE", "weapon_probe", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(player) give(player, id, 3) end)
    plan.wait(5)
    for _, name in ipairs(PROBE_ITEMS) do
        local item = CollectibleType["COLLECTIBLE_" .. name]
        if type(item) == "number" and item > 0 then
            plan.act(function(player) player:AddCollectible(item, 0, false) end)
            plan.wait(6)
            plan.act(function(player, ctx)
                observe(true)
                T().resetEvidence()
                ctx.weapons = weaponNames(player)
                ctx.known, ctx.others, ctx.updates = {}, {}, 0
                for _, e in ipairs(Isaac.GetRoomEntities()) do ctx.known[GetPtrHash(e)] = true end
            end)
            plan.waitUntil(function(_, ctx)
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    local hash = GetPtrHash(e)
                    if not ctx.known[hash] then
                        ctx.known[hash] = true
                        local isDrop = e.Type == EntityType.ENTITY_TEAR and e:GetData()[MARK]
                        if not isDrop then
                            local key = e.Type .. "." .. e.Variant
                            ctx.others[key] = (ctx.others[key] or 0) + 1
                        end
                    end
                end
                ctx.updates = ctx.updates + 1
                return ctx.updates >= 70 and T().evidence.rain >= 6, string.format("%d drops fired", T().evidence.rain)
            end, 400, name .. " window (two falls of three roses)")
            plan.note(name, function(player, ctx)
                ctx.weapons = ctx.weapons .. string.format(" MaxFireDelay %.2f", player.MaxFireDelay)
                local variants, damage, scale = {}, 0, 0
                for _, drop in ipairs(watch.list) do
                    variants["tear." .. drop.variant] = (variants["tear." .. drop.variant] or 0) + 1
                    damage, scale = drop.damage, drop.scale
                end
                return string.format("weapons %s | FireTear returned %d | drops seen %d (%s), last damage %.2f"
                    .. " scale %.2f | others %s", ctx.weapons, T().evidence.rain, #watch.list, counted(variants),
                    damage, scale, counted(ctx.others))
            end)
            plan.act(function(player)
                observe(false)
                player:RemoveCollectible(item)
            end)
            plan.wait(20)
        end
    end
    plan.act(function(player) give(player, id, 0) end)
    plan.wait(30)
end)
S.rows[#S.rows].manual = true

return C
