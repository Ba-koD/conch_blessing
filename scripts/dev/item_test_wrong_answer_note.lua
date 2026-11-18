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
    local l = ledger(player) or {}
    for key, bonus in pairs(l.kinds or {}) do parts[#parts + 1] = key .. "=" .. bonus end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "} all=" .. tostring(l.all) .. " floors=" .. tostring(l.floors)
end

-- Cases that share one run (S.sequenceBundle below); each stays callable alone.
-- A hit the note writes down is earned for the run, so every case whose real
-- hits write the note (hit_noted, damage, golden, golden_later, marker, floor)
-- keeps a run of its own; these leave the note as empty as they found it.
local shared = {}
local case = S.caseIn(shared, "WRONG_ANSWER_NOTE", {})

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
        return l ~= nil and next(l.kinds) == nil and l.floors == 0 and l.all == 0, kinds(player)
    end)
end }

-- A real hit from an enemy writes its kind down and shows the note's icon;
-- self-damage writes nothing.
S.add("WRONG_ANSWER_NOTE", "hit_noted", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id)
    H.hit(plan)
    plan.check("the attack fly's kind is written down once, worth +50%", function(player)
        local l = ledger(player)
        return near(l.kinds[FLY] or 0, 0.5) and evidence().noted == 1, kinds(player)
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
        return near(ledger(player).kinds[FLY] or 0, 0.5), kinds(player) .. " accepted=" .. tostring(ctx.selfHit)
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

-- A note made golden later grows only the later hits (user rule 2026-11-15).
S.add("WRONG_ANSWER_NOTE", "golden_later", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id)
    H.hit(plan)
    hold(plan, id, TrinketType.TRINKET_GOLDEN_FLAG)
    plan.require("the note is golden now", function(player)
        return note().multiplier(player) == 2, "multiplier=" .. note().multiplier(player)
    end)
    measure(plan, "golden after one plain note")
    plan.check("the hit written before stays +50%", function(player, ctx)
        return near(ctx.flyLoss, 15) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f (want 15) maggot %.2f; %s", ctx.flyLoss, ctx.maggotLoss, kinds(player))
    end)
    H.hit(plan)
    measure(plan, "golden, a second note")
    plan.check("a hit while golden adds +100% (+150% in all)", function(player, ctx)
        return near(ctx.flyLoss, 25) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f (want 25) maggot %.2f; %s", ctx.flyLoss, ctx.maggotLoss, kinds(player))
    end)
    hold(plan, id)
    measure(plan, "plain again")
    plan.check("going back to a plain note shrinks nothing", function(player, ctx)
        return near(ctx.flyLoss, 25) and near(ctx.maggotLoss, 10),
            string.format("fly %.2f (want 25) maggot %.2f; %s", ctx.flyLoss, ctx.maggotLoss, kinds(player))
    end)
end)

-- A floor passed without a hit adds +25% against every enemy; a floor with a
-- hit adds nothing.
S.add("WRONG_ANSWER_NOTE", "floor", {}, function(plan, id)
    requireModule(plan)
    hold(plan, id)
    plan.act(function(player) ConchBlessing.minuschain.setNoHit(player, true) end)
    S.newFloor(plan, 2)
    plan.check("the clean floor counts once, worth +25%", function(player)
        local l = ledger(player)
        return l.floors == 1 and near(l.all, 0.25) and evidence().floors == 1, kinds(player)
    end)
    plan.check("a gold +25% shows over Isaac", function(player)
        local text = T().shownText(player)
        return text == "+25%", "shown=" .. tostring(text)
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
    plan.check("the gold +25% is still over Isaac", function(player)
        local text = T().shownText(player)
        return text == "+25%", "shown=" .. tostring(text)
    end)
    plan.section("WRONG_ANSWER_NOTE / floor", "a gold +25% stays over Isaac from the clean floor on")
end)

-- Without the note nothing is written and nothing is added.
case("not_held", function(plan)
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

-- An enemy of a written-down kind shows its number the whole time.
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
    local function shown(ctx) return T().shownText(ctx.fly), T().shownText(ctx.maggot) end
    plan.check("the new attack fly carries a red +50%, the maggot nothing", function(_, ctx)
        local fly, maggot = shown(ctx)
        return fly == "+50%" and maggot == nil, "fly=" .. tostring(fly) .. " maggot=" .. tostring(maggot)
    end)
    plan.section("WRONG_ANSWER_NOTE / marker", "a small red +50% stays over the attack fly")
    plan.wait(150)
    plan.check("five seconds later it is still there", function(_, ctx)
        local fly = shown(ctx)
        return fly == "+50%", "fly=" .. tostring(fly)
    end)
    H.hit(plan)
    plan.check("a second hit grows it to +100%", function(_, ctx)
        local fly = shown(ctx)
        return fly == "+100%", "fly=" .. tostring(fly)
    end)
    plan.act(function(player)
        for slot = 0, 1 do
            local t = player:GetTrinket(slot)
            if t > 0 then player:TryRemoveTrinket(t) end
        end
    end)
    plan.wait(2)
    plan.check("without the note it shows nothing", function(_, ctx)
        local fly = shown(ctx)
        ctx.fly:Remove(); ctx.maggot:Remove()
        return fly == nil, "fly=" .. tostring(fly)
    end)
end)

-- A big monster's number sits just over its drawn top and stays on the screen
-- (user report 2026-11-15: over Hush it was hard to see). Hush is spawned near
-- the top wall, frozen and harmless, with its kind written into the note as a
-- fixture; both are taken back.
case("big_marker", function(plan, id)
    requireModule(plan)
    hold(plan, id)
    plan.act(function(player, ctx)
        ledger(player).kinds["407.0"] = 0.5
        local room = Game():GetRoom()
        local at = Vector(room:GetCenterPos().X, room:GetTopLeftPos().Y + 60)
        ctx.hush = Isaac.Spawn(EntityType.ENTITY_HUSH, 0, 0, at, Vector.Zero, nil):ToNPC()
        ctx.hush:AddEntityFlags(EntityFlag.FLAG_FREEZE)
        ctx.hush.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        ctx.hush.CollisionDamage = 0
    end)
    plan.wait(8)
    plan.check("Hush's number is just over its drawn top, on the screen", function(_, ctx)
        local hush = ctx.hush
        local mark = hush and T().tracked()[GetPtrHash(hush)]
        local top = hush and T().spriteTop(hush)
        if not (mark and mark.y and top) then
            return false, string.format("mark=%s y=%s top=%s", tostring(mark ~= nil), tostring(mark and mark.y), tostring(top))
        end
        local data = note().data
        local offset = hush.SpriteOffset
        local base = Isaac.WorldToScreen(hush.Position + hush.PositionOffset).Y + offset.Y
        local drawnTop = base - top * hush.SpriteScale.Y
        local want = drawnTop - data.gap - (mark.line or data.lineHeight)
        local clamped = want < data.edge
        local onScreen = mark.y >= data.edge and mark.y <= Isaac.GetScreenHeight() - data.edge
        local fits = clamped and mark.y == data.edge or math.abs(mark.y - want) <= 3
        local old = base - (data.lift + hush.Size * data.sizeLift) * hush.SpriteScale.Y
        return onScreen and fits, string.format("y=%.1f want=%.1f drawn top=%.1f (size rule would put it at %.1f)%s",
            mark.y, want, drawnTop, old, clamped and " clamped" or "")
    end)
    plan.section("WRONG_ANSWER_NOTE / big_marker", "a red +50% sits just over Hush's face, on the screen")
    plan.act(function(player, ctx)
        if ctx.hush then ctx.hush:Remove() end
        ledger(player).kinds["407.0"] = nil
    end)
    plan.wait(2)
end)

-- A huge total still multiplies real damage exactly and shows as a whole
-- number. The totals are a fixture written into the note (+9950% against the
-- attack fly, +500% against everything), taken back afterwards.
case("large", function(plan, id)
    requireModule(plan)
    hold(plan, id)
    plan.act(function(player)
        local l = ledger(player)
        l.kinds[FLY], l.all = 99.5, 5
    end)
    measure(plan, "huge totals")
    plan.check("the fly takes x105.5 and the maggot x6", function(player, ctx)
        return near(ctx.flyLoss, 1055) and near(ctx.maggotLoss, 60),
            string.format("fly %.2f (want 1055) maggot %.2f (want 60); %s", ctx.flyLoss, ctx.maggotLoss, kinds(player))
    end)
    plan.act(function(player, ctx) ctx.marked = H.target(player) end)
    plan.wait(2)
    plan.check("the numbers read +9950% and +500%", function(player, ctx)
        local fly, gold = T().shownText(ctx.marked), T().shownText(player)
        ctx.marked:Remove()
        return fly == "+9950%" and gold == "+500%", "fly=" .. tostring(fly) .. " gold=" .. tostring(gold)
    end)
    plan.act(function(player)
        local l = ledger(player)
        l.kinds[FLY], l.all = nil, 0
    end)
end)

-- Hits landing on one watched target, by who fired them (REPENTOGON's
-- post-damage callback: the damage the target really took).
local watch = nil
if ModCallbacks.MC_POST_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source, _, extraSource)
        if not watch or GetPtrHash(entity) ~= watch.target then return end
        local attack = require("scripts.lib.damage_provenance").getSourceEntity(source, extraSource)
        if not attack or attack.Type ~= EntityType.ENTITY_TEAR then return end
        local spawner = attack.SpawnerEntity
        local kind = spawner and spawner:ToFamiliar() and "familiar" or spawner and spawner:ToPlayer() and "player" or "other"
        watch.hits[#watch.hits + 1] = { kind = kind, amount = amount, base = attack.CollisionDamage }
    end)
end

local function hitsOf(ctx, kind)
    local list = {}
    for _, hit in ipairs(ctx.hits or {}) do if hit.kind == kind then list[#list + 1] = hit end end
    return list
end

local function describe(list)
    local parts = {}
    for i, hit in ipairs(list) do
        if i > 4 then break end
        parts[#parts + 1] = string.format("%.2f of %.2f", hit.amount, hit.base)
    end
    return #list .. " hits [" .. table.concat(parts, ", ") .. "]"
end

-- A familiar's own shots get the bonus like Isaac's (user question
-- 2026-11-16). Brother Bobby and Isaac really shoot a frozen Monstro (a big
-- target both lines of tears reach) whose kind is written into the note (+50%,
-- a fixture taken back afterwards); every tear that lands must deal its own
-- damage x1.5.
local TARGET = "20.0"
case("familiar", function(plan, id)
    requireModule(plan)
    hold(plan, id)
    plan.act(function(player, ctx)
        player:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, 0, false)
        player:SetMinDamageCooldown(3000)
        ledger(player).kinds[TARGET] = 0.5
    end)
    plan.wait(30)
    plan.act(function(player, ctx)
        ctx.target = Isaac.Spawn(EntityType.ENTITY_MONSTRO, 0, 0, player.Position + Vector(140, 0), Vector.Zero, nil):ToNPC()
        ctx.target:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        ctx.target:AddEntityFlags(EntityFlag.FLAG_FREEZE)
        ctx.target.CollisionDamage = 0
        ctx.target.MaxHitPoints, ctx.target.HitPoints = 1000000, 1000000
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 60, "Monstro ready")
    plan.act(function(player, ctx)
        ctx.hits = {}
        watch = { target = GetPtrHash(ctx.target), hits = ctx.hits }
        H.shoot(player, "WRONG_ANSWER_NOTE", ctx)
    end)
    plan.waitUntil(function(_, ctx)
        return #hitsOf(ctx, "familiar") >= 2 and #hitsOf(ctx, "player") >= 2
    end, 300, "Isaac's and Bobby's tears land")
    plan.act(function(player, ctx)
        H.stopShooting()
        watch = nil
    end)
    local function boosted(list)
        if #list == 0 then return false end
        for _, hit in ipairs(list) do
            if math.abs(hit.amount - hit.base * 1.5) > 0.01 then return false end
        end
        return true
    end
    plan.check("Brother Bobby's tears deal x1.5", function(_, ctx)
        local list = hitsOf(ctx, "familiar")
        return boosted(list), describe(list)
    end)
    plan.check("Isaac's tears deal x1.5", function(_, ctx)
        local list = hitsOf(ctx, "player")
        return boosted(list), describe(list)
    end)
    plan.act(function(player, ctx)
        if ctx.target then ctx.target:Remove() end
        ledger(player).kinds[TARGET] = nil
        player:RemoveCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
    end)
    plan.wait(4)
end)

-- Bosses with armor (entities2.xml shieldStrength: Hush 140 on 6666 HP) take
-- less from big hits, the note's included (user question 2026-11-16). One
-- 10-damage hit lands on a frozen Hush without and then with a +99950% note
-- (a fixture, taken back), and on Monstro, which has no armor, with the same.
-- Isaac cannot be hurt meanwhile.
local HUSH, MONSTRO = "407.0", "20.0"
-- While `shield` is set, every hit on the player is cancelled and recorded
-- (what it was, its flags), so a boss fixture can never end the run.
local shield = nil
if ModCallbacks.MC_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
        if not shield or not entity:ToPlayer() then return end
        local e = source and source.Entity
        shield[#shield + 1] = string.format("%.1f from %s flags=%d", amount,
            e and (e.Type .. "." .. e.Variant) or tostring(source and source.Type), flags)
        return false
    end, EntityType.ENTITY_PLAYER)
end
local function hitOnce(plan, field, key, bonus)
    plan.act(function(player, ctx)
        ledger(player).kinds[key] = bonus
        T().resetEvidence()
        local target = ctx[field]
        ctx.before = target.HitPoints
        target:TakeDamage(10, 0, EntityRef(player), 0)
    end)
    plan.wait(4)
    plan.act(function(player, ctx)
        ctx[field .. key .. tostring(bonus)] = { loss = ctx.before - ctx[field].HitPoints, damage = T().evidence().lastDamage }
    end)
end

case("boss_armor", function(plan, id)
    requireModule(plan)
    hold(plan, id)
    plan.act(function(player, ctx)
        shield = {}
        ctx.shield = shield
        local room = Game():GetRoom()
        -- Hush is big enough to shove Isaac out of a 1x1 room: Isaac waits at
        -- the bottom, the doors are shut and neither boss touches players.
        player.Position = Vector(room:GetCenterPos().X, room:GetBottomRightPos().Y - 30)
        room:SetClear(false)
        for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
            local door = room:GetDoor(slot)
            if door then door:Close(true) end
        end
        ctx.roomIndex = Game():GetLevel():GetCurrentRoomIndex()
        ctx.hush = Isaac.Spawn(EntityType.ENTITY_HUSH, 0, 0,
            Vector(room:GetCenterPos().X, room:GetTopLeftPos().Y + 60), Vector.Zero, nil):ToNPC()
        ctx.monstro = Isaac.Spawn(EntityType.ENTITY_MONSTRO, 0, 0,
            room:GetCenterPos() + Vector(-160, 80), Vector.Zero, nil):ToNPC()
        ctx.monstro.MaxHitPoints, ctx.monstro.HitPoints = 1000000, 1000000
        ctx.monstro:ClearEntityFlags(EntityFlag.FLAG_APPEAR) -- its appear is a jump it cannot be hit in
        ctx.hush:AddEntityFlags(EntityFlag.FLAG_FREEZE)
        for _, boss in ipairs({ ctx.hush, ctx.monstro }) do
            boss.CollisionDamage = 0
            boss.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYEROBJECTS
        end
    end)
    -- a newly spawned armored boss starts nearly immune for 120 updates
    plan.wait(150)
    -- Monstro is frozen once it stands on the ground (in a jump it cannot be hit)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.monstro) end, 300, "Monstro on the ground")
    plan.act(function(_, ctx) ctx.monstro:AddEntityFlags(EntityFlag.FLAG_FREEZE) end)
    plan.wait(2)
    plan.require("Hush and Monstro can be hurt, Isaac still in the room", function(_, ctx)
        if Game():GetLevel():GetCurrentRoomIndex() ~= ctx.roomIndex then return false, "Isaac left the room" end
        local a, why = H.targetReady(ctx.hush)
        local b, why2 = H.targetReady(ctx.monstro)
        return a and b, why and ("Hush: " .. why) or why2 and ("Monstro: " .. why2)
    end)
    hitOnce(plan, "hush", HUSH, nil)
    plan.wait(130)  -- armor looks back 120 updates
    hitOnce(plan, "hush", HUSH, 999.5)
    hitOnce(plan, "monstro", MONSTRO, 999.5)
    plan.note("Hush, one 10-damage hit", function(_, ctx)
        local plain, noted = ctx["hush" .. HUSH .. "nil"], ctx["hush" .. HUSH .. "999.5"]
        return string.format("without the note %.2f HP; with +99950%% the note asked for %.2f and Hush lost %.2f (x%.1f of plain)",
            plain.loss, noted.damage, noted.loss, noted.loss / math.max(plain.loss, 0.001))
    end)
    plan.check("the note multiplies the hit before Hush's armor", function(_, ctx)
        local noted = ctx["hush" .. HUSH .. "999.5"]
        return near(noted.damage, 10005), string.format("asked for %.2f", noted.damage)
    end)
    plan.check("Hush still loses more with the note than without", function(_, ctx)
        local plain, noted = ctx["hush" .. HUSH .. "nil"], ctx["hush" .. HUSH .. "999.5"]
        return noted.loss > plain.loss * 2, string.format("%.2f vs %.2f", noted.loss, plain.loss)
    end)
    plan.check("Monstro, with no armor, loses the full 10005", function(_, ctx)
        local noted = ctx["monstro" .. MONSTRO .. "999.5"]
        return near(noted.loss, 10005), string.format("lost %.2f", noted.loss)
    end)
    -- Without the note, 20 hits of 10 two updates apart (about 150 a second,
    -- over Hush's soft cap of 6666 / 140 = 48 a second): what each one costs.
    plan.wait(130)
    plan.act(function(player, ctx)
        ledger(player).kinds[HUSH] = nil
        ctx.series = {}
    end)
    for _ = 1, 20 do
        plan.act(function(player, ctx)
            ctx.seriesBefore = ctx.hush.HitPoints
            ctx.hush:TakeDamage(10, 0, EntityRef(player), 0)
        end)
        plan.wait(2)
        plan.act(function(_, ctx) ctx.series[#ctx.series + 1] = ctx.seriesBefore - ctx.hush.HitPoints end)
    end
    plan.note("Hush, 20 plain hits of 10 in a row", function(_, ctx)
        local parts, total = {}, 0
        for _, loss in ipairs(ctx.series) do
            parts[#parts + 1] = string.format("%.2f", loss)
            total = total + loss
        end
        return string.format("%s (total %.2f of 200)", table.concat(parts, " "), total)
    end)
    plan.note("hits on Isaac turned away during the fixture", function(_, ctx)
        return #ctx.shield .. (#ctx.shield > 0 and (": " .. table.concat(ctx.shield, "; ", 1, math.min(5, #ctx.shield))) or "")
    end)
    plan.act(function(player, ctx)
        for _, boss in ipairs({ ctx.hush, ctx.monstro }) do if boss then boss:Remove() end end
        ledger(player).kinds[HUSH], ledger(player).kinds[MONSTRO] = nil, nil
        shield = nil
    end)
    plan.wait(4)
end)

-- The shared cases write only fixtures into the note and take them back, so
-- they share one run as long as the note is still empty between them.
-- boss_armor goes last: it leaves the room uncleared with its doors shut.
S.last(shared, "boss_armor")
S.sequenceBundle("WRONG_ANSWER_NOTE", "shared", {}, shared, function(plan)
    S.resetPlayer(plan, nil, function(player)
        local l = ledger(player)
        return l ~= nil and next(l.kinds) == nil and l.all == 0 and l.floors == 0, "note not empty: " .. kinds(player)
    end)
end)

return C
