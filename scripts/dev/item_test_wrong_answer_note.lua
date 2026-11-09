local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 오답노트 (Wrong Answer Note): the lifecycle contract and its cases. Hits are
-- real (H.hit: the player takes damage from a live attack fly, which the note
-- writes down as kind 18.0), the extra damage is read from real enemy HP loss,
-- and floors are really changed.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local Hits = require("scripts.lib.player_hits")
local C = {}

local function note() return ConchBlessing.wronganswernote end
local function T() return note()._test end
local function evidence() return T().evidence() end
local function golden(id) return id | TrinketType.TRINKET_GOLDEN_FLAG end

local FLY = "18.0" -- the attack fly H.hit and H.target use

local function ledger(player) return note().ledger(player) end

local function kinds(player)
    local parts = {}
    for key, hits in pairs((ledger(player) or {}).kinds or {}) do parts[#parts + 1] = key .. "=" .. hits end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "} floors=" .. tostring((ledger(player) or {}).floors)
end

local function requireModule(plan)
    plan.require("Wrong Answer Note module and REPENTOGON's damage return ready", function()
        local m = note()
        return m and m._test and m._test.started() and rawget(_G, "REPENTOGON") ~= nil and true or false,
            "module missing, not started or no REPENTOGON"
    end)
end

local function hold(plan, id, flag)
    plan.act(function(player)
        for slot = 0, 1 do
            local t = player:GetTrinket(slot)
            if t > 0 then player:TryRemoveTrinket(t) end
        end
        player:AddTrinket(id | (flag or 0), false)
        T().resetEvidence()
    end)
    plan.wait(4)
end

-- Two zero-contact targets: an attack fly (the kind H.hit writes down) and a
-- maggot (never written down). Each takes one 10-damage hit from the player.
local function measure(plan, label)
    plan.act(function(player, ctx)
        ctx.fly = H.target(player)
        ctx.maggot = H.target(player, true)
        ctx.maggot.Position = player.Position + Vector(-80, 0)
    end)
    plan.waitUntil(function(_, ctx)
        local a, why = H.targetReady(ctx.fly)
        local b, why2 = H.targetReady(ctx.maggot)
        return a and b, why or why2
    end, 60, "both targets ready (" .. label .. ")")
    plan.act(function(player, ctx)
        ctx.flyBefore, ctx.maggotBefore = ctx.fly.HitPoints, ctx.maggot.HitPoints
        ctx.fly:TakeDamage(10, 0, EntityRef(player), 0)
        ctx.maggot:TakeDamage(10, 0, EntityRef(player), 0)
    end)
    plan.wait(4)
    plan.act(function(_, ctx)
        ctx.flyLoss = ctx.flyBefore - ctx.fly.HitPoints
        ctx.maggotLoss = ctx.maggotBefore - ctx.maggot.HitPoints
        ctx.fly:Remove(); ctx.maggot:Remove()
    end)
end

local function near(a, b) return math.abs(a - b) < 0.01 end

C.WRONG_ANSWER_NOTE = { stage = function(plan, id, n)
    plan.check("the note's strength is the trinket multiplier", function(player)
        local m = note().multiplier(player)
        return m == player:GetTrinketMultiplier(id) and (n == 0) == (m == 0),
            string.format("multiplier=%d engine=%d copies=%d", m, player:GetTrinketMultiplier(id), n)
    end)
    plan.check("nothing written down without a hit", function(player)
        local l = ledger(player)
        return l ~= nil and next(l.kinds) == nil and l.floors == 0, kinds(player)
    end)
end }

-- A real hit from an enemy writes its kind down and shows the note's icon;
-- self-damage writes nothing.
S.add("WRONG_ANSWER_NOTE", "hit_noted", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id)
    H.hit(plan)
    plan.check("the attack fly's kind is written down once", function(player)
        local l = ledger(player)
        return l.kinds[FLY] == 1 and evidence().noted == 1, kinds(player)
    end)
    plan.check("the note's icon shows over Isaac", function(player)
        local shown = Hits._test.shown(player)
        for _, key in ipairs(shown or {}) do if key == "WRONG_ANSWER_NOTE" then return true end end
        return false, "shown=" .. table.concat(shown or {}, ",")
    end)
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 180, "damage cooldown expires")
    plan.act(function(player, ctx)
        ctx.source = H.target(player)
        ctx.source.Position = player.Position + Vector(240, 0)
        player:AddHearts(4)
        ctx.selfHit = player:TakeDamage(1, DamageFlag.DAMAGE_RED_HEARTS, EntityRef(ctx.source), 30)
    end)
    plan.wait(4)
    plan.check("self-damage (a red-heart cost) writes nothing", function(player, ctx)
        if ctx.source then ctx.source:Remove() end
        return ledger(player).kinds[FLY] == 1, kinds(player) .. " accepted=" .. tostring(ctx.selfHit)
    end)
end)

-- The holder's hits deal +50% to the written-down kind only.
S.add("WRONG_ANSWER_NOTE", "damage", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id)
    measure(plan, "before any note")
    plan.check("with nothing written down both take the plain 10", function(_, ctx)
        return near(ctx.flyLoss, 10) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f maggot %.2f", ctx.flyLoss, ctx.maggotLoss)
    end)
    H.hit(plan)
    measure(plan, "after one note")
    plan.check("the noted kind takes +50%, another kind the plain damage", function(_, ctx)
        return near(ctx.flyLoss, 15) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f (want 15) maggot %.2f (want 10)", ctx.flyLoss, ctx.maggotLoss)
    end)
    H.hit(plan)
    measure(plan, "after two notes")
    plan.check("a second hit from the kind stacks to +100%", function(player, ctx)
        return near(ctx.flyLoss, 20) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f (want 20) maggot %.2f; %s", ctx.flyLoss, ctx.maggotLoss, kinds(player))
    end)
end)

-- Golden doubles the step.
S.add("WRONG_ANSWER_NOTE", "golden", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id, TrinketType.TRINKET_GOLDEN_FLAG)
    plan.require("a golden note counts twice", function(player)
        return note().multiplier(player) == 2, "multiplier=" .. note().multiplier(player)
    end)
    H.hit(plan)
    measure(plan, "golden, one note")
    plan.check("one hit gives the noted kind +100%", function(_, ctx)
        return near(ctx.flyLoss, 20) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f (want 20) maggot %.2f", ctx.flyLoss, ctx.maggotLoss)
    end)
end)

-- A floor passed without a hit adds +25% against every enemy; a floor with a
-- hit adds nothing.
S.add("WRONG_ANSWER_NOTE", "floor", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id)
    plan.act(function(player) ConchBlessing.minuschain.setNoHit(player, true) end)
    S.newFloor(plan, 2)
    plan.check("the clean floor counts once", function(player)
        return ledger(player).floors == 1 and evidence().floors == 1, kinds(player)
    end)
    measure(plan, "one clean floor")
    plan.check("every enemy takes +25%", function(_, ctx)
        return near(ctx.flyLoss, 12.5) and near(ctx.maggotLoss, 12.5),
            string.format("fly %.2f maggot %.2f (want 12.5)", ctx.flyLoss, ctx.maggotLoss)
    end)
    H.hit(plan)
    S.newFloor(plan, 3)
    plan.check("a floor with a hit adds nothing", function(player)
        return ledger(player).floors == 1, kinds(player)
    end)
    plan.section("WRONG_ANSWER_NOTE / floor", "a gold +25% popped over Isaac on reaching the clean floor")
end)

-- Without the note nothing is written and nothing is added.
S.add("WRONG_ANSWER_NOTE", "not_held", {}, function(plan)
    requireModule(plan)
    plan.act(function() T().resetEvidence() end)
    H.hit(plan)
    plan.check("a hit writes nothing without the note", function(player)
        return next(ledger(player).kinds) == nil and evidence().noted == 0, kinds(player)
    end)
    measure(plan, "no note")
    plan.check("both take the plain 10", function(_, ctx)
        return near(ctx.flyLoss, 10) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f maggot %.2f", ctx.flyLoss, ctx.maggotLoss)
    end)
end)

-- An enemy of a written-down kind shows its number when it appears.
S.add("WRONG_ANSWER_NOTE", "marker", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id)
    H.hit(plan)
    plan.act(function(player, ctx)
        T().resetEvidence()
        ctx.fly = H.target(player)
        ctx.maggot = H.target(player, true)
    end)
    plan.wait(2)
    plan.check("the new attack fly carries a red +50%, the maggot nothing", function(_, ctx)
        local fly, maggot
        for _, marker in ipairs(T().markers()) do
            if marker.hash == GetPtrHash(ctx.fly) then fly = marker.text end
            if marker.hash == GetPtrHash(ctx.maggot) then maggot = marker.text end
        end
        return fly == "+50%" and maggot == nil, "fly=" .. tostring(fly) .. " maggot=" .. tostring(maggot)
    end)
    plan.section("WRONG_ANSWER_NOTE / marker", "a small red +50% popped over the new attack fly for about a second")
    plan.wait(90)
    plan.check("the marker is gone after its moment", function(_, ctx)
        for _, marker in ipairs(T().markers()) do
            if marker.hash == GetPtrHash(ctx.fly) then return false, "still showing at age " .. marker.age end
        end
        ctx.fly:Remove(); ctx.maggot:Remove()
        return true
    end)
end)

return C
