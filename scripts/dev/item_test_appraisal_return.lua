local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- How a vanilla Death Certificate visit ends, so Appraisal's return can follow
-- it (user request 2026-11-10: the screen shakes, Isaac lies down, then the
-- fade). Measurement by name only: `cb test appraisal_certificate dc_vanilla`
-- takes a real item in the real Death Certificate area and logs, from the
-- pickup until home, every change of dimension, room, RoomTransition mode,
-- Isaac's animation (with frame), visibility, controls and item queue, each
-- start of a screen shake (with its countdown) and every sound played (DIAG).
local S = require("scripts.dev.item_scenarios")
local C = {}

local recording = nil -- the trace while a window is open

if type(ModCallbacks.MC_PRE_SFX_PLAY) == "number" then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_SFX_PLAY, function(_, id, volume, delay, loop, pitch)
        if recording then
            recording[#recording + 1] = string.format("+%d SOUND %d vol=%.2f pitch=%.2f delay=%s", recording.tick, id,
                volume or -1, pitch or -1, tostring(delay))
        end
    end)
end

-- Render frames run while updates wait (the pause before the return and the
-- transition itself), so the same things are sampled there too.
ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    local trace = recording
    local player = trace and Isaac.GetPlayer(0)
    if not player then return end
    trace.renders = (trace.renders or 0) + 1
    local sprite = player:GetSprite()
    local shake = Game():GetScreenShakeCountdown()
    local key = string.format("mode=%d anim=%s dim=%d", RoomTransition.GetTransitionMode(), sprite:GetAnimation(),
        Game():GetLevel():GetDimension())
    if key ~= trace.renderKey or shake > (trace.renderShake or 0) then
        trace[#trace + 1] = string.format("r%d(+%d) %s frame=%d shake=%d", trace.renders, trace.tick, key,
            sprite:GetFrame(), shake)
        trace.renderKey = key
    end
    trace.renderShake = shake
end)

local function state(player)
    local level, sprite = Game():GetLevel(), player:GetSprite()
    return string.format("dim=%d room=%d mode=%d anim=%s%s visible=%s queue=%d controls=%s",
        level:GetDimension(), level:GetCurrentRoomIndex(), RoomTransition.GetTransitionMode(), sprite:GetAnimation(),
        sprite:GetOverlayAnimation() ~= "" and ("+" .. sprite:GetOverlayAnimation()) or "", tostring(player.Visible),
        player.QueuedItem and player.QueuedItem.Item and player.QueuedItem.Item.ID or 0, tostring(player.ControlsEnabled))
end

-- Record from the pickup until Isaac is home, the transition is over and 45
-- quiet updates have passed, then log the trace.
local function recordHome(plan, label)
    plan.waitUntil(function(player, ctx)
        local trace = ctx.trace
        trace.tick = trace.tick + 1
        local line = state(player)
        local frame = player:GetSprite():GetFrame()
        if line ~= ctx.last then
            trace[#trace + 1] = string.format("+%d %s frame=%d", trace.tick, line, frame)
            ctx.last, ctx.quiet = line, 0
        else
            ctx.quiet = ctx.quiet + 1
        end
        local shake = Game():GetScreenShakeCountdown()
        if shake > ctx.shake then trace[#trace + 1] = string.format("+%d SHAKE countdown=%d", trace.tick, shake) end
        ctx.shake = shake
        return Game():GetLevel():GetDimension() == 0 and RoomTransition.GetTransitionMode() == 0 and ctx.quiet >= 45,
            trace.tick .. " updates"
    end, 900, label)
    plan.act(function() recording = nil end)
    plan.note("steps", function(_, ctx) return #ctx.trace .. " (item " .. tostring(ctx.item) .. ")" end)
    for i = 1, 70 do
        plan.note("#" .. i, function(_, ctx) return ctx.trace[i] or "-" end)
    end
    plan.note("landed", function(_, ctx)
        return string.format("room=%d (used in %d)", Game():GetLevel():GetCurrentRoomIndex(), ctx.originRoom)
    end)
end

local function startRecording(ctx)
    recording = { tick = 0 }
    ctx.trace, ctx.last, ctx.shake, ctx.quiet = recording, nil, Game():GetScreenShakeCountdown(), 0
end

S.add("APPRAISAL_CERTIFICATE", "dc_vanilla", {}, function(plan)
    plan.require("dimension, transition mode, shake countdown and Death Certificate", function()
        return (type(Game():GetLevel().GetDimension) == "function" and type(RoomTransition) == "table"
            and type(RoomTransition.GetTransitionMode) == "function"
            and type(Game().GetScreenShakeCountdown) == "function") or nil, "REPENTOGON required"
    end)
    plan.act(function(player, ctx)
        ctx.originRoom = Game():GetLevel():GetCurrentRoomIndex()
        player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, -1)
    end)
    plan.waitUntil(function() return Game():GetLevel():GetDimension() == 2 and RoomTransition.GetTransitionMode() == 0 end,
        300, "Death Certificate entry")
    plan.wait(10)
    plan.act(function(player, ctx)
        local room = Game():GetRoom()
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomIndex >= 0 then
                ctx.stock = door.TargetRoomIndex
                Game():StartRoomTransition(ctx.stock, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, 2)
                return
            end
        end
        error("no room next to the Death Certificate entrance")
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomIndex() == ctx.stock and RoomTransition.GetTransitionMode() == 0
    end, 180, "a Death Certificate item room")
    plan.wait(15)
    plan.act(function(player, ctx)
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)) do
            local pickup = entity:ToPickup()
            if pickup and pickup.SubType > 0 then
                ctx.item = pickup.SubType
                startRecording(ctx)
                player.Position = pickup.Position
                player.Velocity = Vector.Zero
                return
            end
        end
        error("no item pedestal in the Death Certificate room")
    end)
    recordHome(plan, "vanilla pickup and return")
end)
S.rows[#S.rows].manual = true

-- The same record for Appraisal: pay, enter, walk into a stock room, take the
-- first trinket and go home.
local function appraisalSession()
    local run = ConchBlessing.SaveManager.TryGetRunSave(nil, false)
    local value = run and run.appraisalGallerySession
    return value and value.version == 11 and value
end

S.add("APPRAISAL_CERTIFICATE", "appraisal_return", {}, function(plan, id)
    plan.act(function(player, ctx)
        ctx.originRoom = Game():GetLevel():GetCurrentRoomIndex()
        player:AddCollectible(id, 0, false, ActiveSlot.SLOT_PRIMARY)
        player:AddCoins(30 - player:GetNumCoins())
        player:UseActiveItem(id, UseFlag.USE_OWNED, ActiveSlot.SLOT_PRIMARY)
    end)
    plan.waitUntil(function()
        local value = appraisalSession()
        return value and value.phase == "browsing" and value.entryCommitted == true
            and RoomTransition.GetTransitionMode() == 0 or false
    end, 300, "Appraisal entry")
    plan.wait(10)
    plan.act(function(player, ctx)
        for _, manifest in ipairs(appraisalSession().graph.rooms) do
            if manifest.kind == "stock" and manifest.slotCount > 0 then
                ctx.stock = manifest
                Game():StartRoomTransition(manifest.safeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, 2)
                return
            end
        end
        error("no stock room")
    end)
    plan.waitUntil(function(_, ctx)
        return Game():GetLevel():GetCurrentRoomDesc().ListIndex == ctx.stock.listIndex and RoomTransition.GetTransitionMode() == 0
    end, 300, "an Appraisal stock room")
    plan.wait(15)
    plan.act(function(player, ctx)
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET)) do
            local pickup = entity:ToPickup()
            if pickup and pickup:GetData().__ConchBlessingAppraisalStock then
                ctx.item = pickup.SubType
                startRecording(ctx)
                pickup.Wait = 0
                player.Position = pickup.Position
                player.Velocity = Vector.Zero
                return
            end
        end
        error("no stock trinket")
    end)
    recordHome(plan, "Appraisal pickup and return")
end)
S.rows[#S.rows].manual = true

return C
