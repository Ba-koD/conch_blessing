local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- `cb test kronos bloodshot_probe` (a measurement, run by name only): which
-- part of Kronos's hidden Bloodshot Eye stops it from firing. The same eye is
-- spawned plain, hidden, without collision, pinned to the player and exactly
-- as Kronos does it, against the real item as the control. Each variant gets
-- the same pinned target; DIAG lines count the attacks it fired and the HP it
-- took. Nothing here is a PASS for Kronos.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

local watch = nil -- { eye = familiar, fired = n, hp = n } while one variant runs

local function fromEye(entity)
    for _ = 1, 4 do
        if not entity then return false end
        if watch and watch.eye and GetPtrHash(entity) == GetPtrHash(watch.eye) then return true end
        entity = entity.SpawnerEntity or entity.Parent
    end
    return false
end

for _, name in ipairs({ "MC_POST_TEAR_INIT", "MC_POST_LASER_INIT" }) do
    if ModCallbacks[name] then
        ConchBlessing:AddCallback(ModCallbacks[name], function(_, entity)
            if watch and fromEye(entity) then watch.fired = watch.fired + 1 end
        end)
    end
end
if ModCallbacks.MC_POST_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG, function(_, entity, amount, _, source, _, extra)
        if not (watch and watch.target and GetPtrHash(entity) == GetPtrHash(watch.target)) then return end
        local attack = require("scripts.lib.damage_provenance").getSourceEntity(source, extra)
        if fromEye(attack) then watch.hp = watch.hp + amount end
    end)
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not watch then return end
    if watch.target and watch.target:Exists() then
        watch.target.Position, watch.target.Velocity = watch.targetPos, Vector.Zero
    end
    local eye, player = watch.eye, watch.player
    if eye and eye:Exists() and watch.orbit0 then
        eye.OrbitDistance = Vector.Zero
        watch.maxGap = math.max(watch.maxGap or 0, eye.Position:Distance(watch.player.Position))
        if watch.hide then eye.Visible = false end
    end
    if eye and eye:Exists() and watch.pin and player then
        eye.Position, eye.Velocity = player.Position, Vector.Zero
        if watch.hide then eye.Visible = false end
    end
end)

local VARIANTS = {
    { name = "the real item (control)", real = true },
    { name = "spawned, untouched" },
    { name = "spawned, hidden", hide = true },
    { name = "spawned, no collision", nocollide = true },
    { name = "spawned, pinned on the player", pin = true },
    { name = "spawned like Kronos (hidden, no collision, pinned)", hide = true, nocollide = true, pin = true },
    { name = "orbit radius zero", orbit0 = true },
    { name = "orbit radius zero, hidden, no collision", orbit0 = true, hide = true, nocollide = true },
}

S.add("KRONOS", "bloodshot_probe", {}, function(plan)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        player.Position = room:GetCenterPos() - Vector(60, 0)
        ctx.target = H.target(player, true)
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            watch = nil
            if ctx.target:Exists() then ctx.target:Remove() end
        end
    end)
    plan.waitUntil(function(_, ctx) return H.targetReady(ctx.target) end, 60, "the target is ready")
    for _, v in ipairs(VARIANTS) do
        plan.act(function(player, ctx)
            watch = { player = player, target = ctx.target, targetPos = player.Position + Vector(45, 0),
                fired = 0, hp = 0, pin = v.pin, hide = v.hide }
            if v.real then
                player:AddCollectible(CollectibleType.COLLECTIBLE_BLOODSHOT_EYE, 0, false)
            else
                local eye = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLOODSHOT_EYE, 0, player.Position,
                    Vector.Zero, player):ToFamiliar()
                eye:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                if v.hide then eye.Visible = false end
                if v.nocollide then
                    eye.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
                    eye.GridCollisionClass = GridCollisionClass.COLLISION_NONE
                end
                if v.orbit0 then eye.OrbitDistance = Vector.Zero end
                watch.eye = eye
            end
            watch.orbit0 = v.orbit0
        end)
        plan.wait(5)
        plan.act(function(player)
            if v.real then
                for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLOODSHOT_EYE)) do
                    watch.eye = e:ToFamiliar()
                end
            end
        end)
        plan.wait(180)
        plan.note(v.name, function()
            local eye = watch.eye
            return string.format("fired %d, HP %.1f; orbit layer %s, state %s, visible %s, farthest from player %.1f",
                watch.fired, watch.hp, tostring(eye and eye.OrbitLayer), tostring(eye and eye.State),
                tostring(eye and eye.Visible), watch.maxGap or -1)
        end)
        plan.act(function(player)
            if v.real then
                player:RemoveCollectible(CollectibleType.COLLECTIBLE_BLOODSHOT_EYE)
            elseif watch.eye and watch.eye:Exists() then
                watch.eye:Remove()
            end
            watch = nil
        end)
        plan.wait(10)
    end
end)
S.rows[#S.rows].manual = true
