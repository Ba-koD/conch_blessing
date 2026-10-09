-- Run conch_test appraisal detail: actual engine uses, native entry, pickup and return.
-- TestBench restarts before and after; ordinary gameplay does not run this.
local TestBench = require("scripts.dev.test_bench")
local NativeGalleryRooms = require("scripts.rooms.death_certificate_gallery_rooms")
local observing
local STOCK_KEY = "__ConchBlessingAppraisalStock"

local function session()
    local run = ConchBlessing.SaveManager.TryGetRunSave(nil, false)
    return run and run.appraisalGallerySession
end

local function nativeSession()
    local value = session()
    return value and value.version == 11 and value.mode == "appraisal_trinkets_death_certificate" and value
end

local function atEntrance()
    local value = nativeSession()
    return value and value.phase == "browsing" and value.entryCommitted == true
        and ConchBlessing.GalleryManager.isCurrentGalleryRoom()
        and Game():GetLevel():GetCurrentRoomDesc().ListIndex == value.graph.entrance.listIndex
end

local function completed()
    local value = nativeSession()
    return value and value.phase == "completed" and not value.pendingChoice
        and not ConchBlessing.GalleryManager.isCurrentGalleryRoom()
end

local function smeltCount(player, id)
    local value = player:GetSmeltedTrinkets()[id] or {}
    return (tonumber(value.trinketAmount) or 0) + (tonumber(value.goldenTrinketAmount) or 0)
end

local function use(player)
    player:UseActiveItem(ConchBlessing.ItemData.APPRAISAL_CERTIFICATE.id, UseFlag.USE_OWNED, ActiveSlot.SLOT_PRIMARY)
end

local function stockSources(value, manifest)
    local found = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1)) do
        local pickup = entity:ToPickup()
        local data = pickup:GetData()[STOCK_KEY]
        if data and data.token == value.token and data.roomKey == manifest.key then
            found[#found + 1] = pickup
        end
    end
    table.sort(found, function(a, b) return a:GetData()[STOCK_KEY].slot < b:GetData()[STOCK_KEY].slot end)
    return found
end

local function enterStock(player, ctx, pickOpen)
    local value = nativeSession()
    if not atEntrance() then ctx.stock = nil; return end
    ctx.stock = nil
    for _, manifest in ipairs(value.graph.rooms) do
        if manifest.kind == "stock" and manifest.slotCount > 0 and (not pickOpen or not value.closedRooms[manifest.key]) then
            ctx.stock = manifest
            break
        end
    end
    if not ctx.stock then return end
    Game():StartRoomTransition(ctx.stock.safeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player, 2)
end

local function atStock(_, ctx)
    return ctx.stock and ConchBlessing.GalleryManager.isCurrentGalleryRoom()
        and Game():GetLevel():GetCurrentRoomDesc().ListIndex == ctx.stock.listIndex
        and nativeSession().phase == "browsing"
end

local function takeFirst(player, ctx)
    ctx.rewardId, ctx.rewardBefore, ctx.chosenRoom = nil, nil, nil
    if not atStock(player, ctx) then return end
    local sources = stockSources(nativeSession(), ctx.stock)
    local pickup = sources[1]
    if not pickup then return end
    ctx.rewardId = pickup.SubType
    ctx.rewardBefore = smeltCount(player, ctx.rewardId)
    ctx.chosenRoom = ctx.stock.key
    pickup.Wait = 0
    pickup.Velocity = Vector.Zero
    player.Position = pickup.Position
    player.Velocity = Vector.Zero
end

local function build(plan)
    plan.section("29 coins: rejected engine use")
    plan.act(function(player, ctx)
        observing = ctx
        ctx.uses = 0
        ctx.originIndex = Game():GetLevel():GetCurrentRoomDesc().ListIndex
        ctx.held = TrinketType.TRINKET_SWALLOWED_PENNY
        for slot = 0, 1 do
            local held = player:GetTrinket(slot)
            if held ~= 0 then player:TryRemoveTrinket(held) end
        end
        player:AddCollectible(ConchBlessing.ItemData.APPRAISAL_CERTIFICATE.id, 0, false, ActiveSlot.SLOT_PRIMARY)
        player:AddTrinket(ctx.held, false)
        player:AddCoins(29 - player:GetNumCoins())
        ctx.heldSmeltsBefore = smeltCount(player, ctx.held)
        use(player)
    end)
    plan.wait(5)
    plan.eq("no accepted MC_USE_ITEM event", function(_, ctx) return ctx.uses end, 0)
    plan.eq("coins stay at 29", function(player) return player:GetNumCoins() end, 29)
    plan.check("held trinket is unchanged", function(player, ctx)
        return player:GetTrinket(0) == ctx.held and smeltCount(player, ctx.held) == ctx.heldSmeltsBefore, tostring(player:GetTrinket(0))
    end)
    plan.check("no session or room build", function() return session() == nil and NativeGalleryRooms.isDimensionEmpty() == true, tostring(session()) end)
    plan.check("manual use is suppressed before activation", function(player)
        return ConchBlessing.appraisal.onInputAction(nil, player, InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_ITEM) == false, "primary active input"
    end)

    plan.section("30 coins: canonical Death Certificate entry", "dimension 2 contains trinket rooms; entrance LEFT0 has an open green door with a lit EXIT sign that flickers now and then")
    plan.act(function(player) player:AddCoins(1); use(player) end)
    plan.waitUntil(atEntrance, 300)
    plan.check("native version-11 entrance is paid and ready", function() return not not atEntrance(), tostring(session() and session().phase) end)
    plan.eq("one accepted Appraisal use", function(_, ctx) return ctx.uses end, 1)
    plan.eq("exactly 30 coins paid", function(player) return player:GetNumCoins() end, 0)
    plan.check("held trinket absorbed exactly once", function(player, ctx)
        return player:GetTrinket(0) == 0 and smeltCount(player, ctx.held) == ctx.heldSmeltsBefore + 1, tostring(smeltCount(player, ctx.held))
    end)
    plan.check("complete catalog replaces vanilla DC pedestals", function(_, ctx)
        local value = nativeSession()
        if not value or not value.graph then return false, "no native graph" end
        ctx.token = value.token
        local count = 0
        for _, manifest in ipairs(value.graph.rooms) do
            if manifest.stageId ~= 35 or manifest.name ~= "Death Certificate"
                or manifest.slotCount > manifest.capacity then return false, manifest.layoutKey end
            count = count + manifest.slotCount
        end
        return value.graph.dimension == 2 and value.graph.complete == true and count == #value.catalog, tostring(count) .. "/" .. tostring(#value.catalog)
    end)
    plan.check("Atropos excluded from the Appraisal catalog", function()
        local value = nativeSession()
        if not value then return false, "no native session" end
        for _, id in ipairs(value.catalog) do
            if id == ConchBlessing.ItemData.ATROPOS.id then return false, "Atropos is in the catalog" end
        end
        return true, "Atropos excluded; unlock availability does not exclude other trinkets"
    end)
    plan.check("exact live native return door", function()
        local value = nativeSession()
        if not value then return false, "no native session" end
        local count = 0
        for _, grid in ipairs(StageAPI.GetCustomDoors("ConchBlessingNativeGalleryReturn")) do
            local persistent = grid.PersistentData
            local data = persistent and persistent.Data
            local door = grid.Data and grid.Data.DoorEntity
            if persistent and persistent.Slot == DoorSlot.LEFT0 and data and data.token == value.token
                and data.visitId == value.visitId and door and door:Exists() then
                local room = Game():GetRoom()
                local inside = room:IsPositionInRoom(door.Position + Vector(40, 0), 0)
                if inside and room:GetGridIndex(door.Position) == grid.GridIndex then count = count + 1 end
            end
        end
        return count == 1, tostring(count)
    end)
    plan.check("return door wears the green EXIT door", function()
        for _, grid in ipairs(StageAPI.GetCustomDoors("ConchBlessingNativeGalleryReturn")) do
            local door = grid.Data and grid.Data.DoorEntity
            if door and door:Exists() then
                local sprite = door:GetSprite()
                local anm2 = sprite:GetFilename()
                if not anm2:lower():find("door_01x_ghostexit.anm2", 1, true) then return false, anm2 end
                -- The sheet path is only readable through REPENTOGON's LayerState.
                local layer = type(sprite.GetLayer) == "function" and sprite:GetLayer(3) or nil
                if not (layer and type(layer.GetSpritesheetPath) == "function") then
                    return nil, anm2 .. "; sheet not readable without REPENTOGON"
                end
                local sheet = layer:GetSpritesheetPath()
                return sheet:lower():find("door_01x_ghostexit_green.png", 1, true) ~= nil, anm2 .. "; " .. sheet
            end
        end
        return false, "no live return door"
    end)
    plan.waitUntil(function(player)
        if completed() then return true end
        if not atEntrance() then return false end
        for _, grid in ipairs(StageAPI.GetCustomDoors("ConchBlessingNativeGalleryReturn")) do
            local door = grid.Data and grid.Data.DoorEntity
            if door and door:Exists() then
                player.Velocity = (door.Position - player.Position):Resized(5)
                break
            end
        end
        return false
    end, 300)
    plan.act(function(player) player.Velocity = Vector.Zero end)
    plan.check("walking through the reachable return door reaches the exact origin", function(_, ctx)
        return not not completed() and Game():GetLevel():GetCurrentRoomDesc().ListIndex == ctx.originIndex, tostring(Game():GetLevel():GetCurrentRoomDesc().ListIndex)
    end)
    -- A failed physical-door check must not strand later independent cases.
    plan.act(function() if atEntrance() then ConchBlessing.GalleryManager.returnToOrigin("appraisal_probe_recovery") end end)
    plan.waitUntil(completed, 300)

    plan.section("same-floor reuse and natural stock pickup")
    plan.act(function(player) if completed() then player:AddCoins(30); use(player) end end)
    plan.waitUntil(atEntrance, 300)
    plan.check("paid second visit reuses the same graph", function(_, ctx)
        return not not atEntrance() and nativeSession().token == ctx.token and ctx.uses == 2, tostring(ctx.uses)
    end)
    plan.act(function(player, ctx) enterStock(player, ctx, true) end)
    plan.waitUntil(atStock, 300)
    plan.check("stock matches the room's assigned catalog", function(player, ctx)
        if not atStock(player, ctx) then return false, "not in stock room" end
        local count = #stockSources(nativeSession(), ctx.stock)
        return count == ctx.stock.slotCount, tostring(count) .. "/" .. tostring(ctx.stock.slotCount)
    end)
    plan.eq("vanilla collectible pedestals were removed", function()
        return #Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1)
    end, 0)
    plan.act(takeFirst)
    plan.waitUntil(completed, 420)
    plan.check("natural pickup closes its room and returns", function(_, ctx)
        local value = nativeSession()
        return not not completed() and ctx.chosenRoom ~= nil and value.closedRooms[ctx.chosenRoom] == true, tostring(value and value.phase)
    end)
    plan.check("chosen reward is smelted exactly once", function(player, ctx)
        if not ctx.rewardId then return false, "no chosen reward" end
        return smeltCount(player, ctx.rewardId) == ctx.rewardBefore + 1 and player:GetTrinket(0) == 0, tostring(smeltCount(player, ctx.rewardId))
    end)

    plan.section("Atropos: one reward per room, no automatic return")
    plan.act(function(player)
        if not completed() then return end
        player:AddSmeltedTrinket(ConchBlessing.ItemData.ATROPOS.id, false)
        player:AddCoins(30)
        use(player)
    end)
    plan.waitUntil(atEntrance, 300)
    plan.act(function(player, ctx) enterStock(player, ctx, true) end)
    plan.waitUntil(atStock, 300)
    plan.act(takeFirst)
    plan.waitUntil(function(_, ctx)
        local value = nativeSession()
        return value and ctx.chosenRoom and value.closedRooms[ctx.chosenRoom] == true
            and value.phase == "browsing" and not value.pendingChoice
    end, 420)
    plan.check("Atropos stays in the owned native graph", function(_, ctx)
        local value = nativeSession()
        return value and value.atroposMode == true and value.phase == "browsing" and not value.pendingChoice
            and value.closedRooms[ctx.chosenRoom] == true and ConchBlessing.GalleryManager.isCurrentGalleryRoom(), tostring(value and value.phase)
    end)
    plan.check("Atropos reward is absorbed exactly once", function(player, ctx)
        if not ctx.rewardId then return false, "no chosen reward" end
        return smeltCount(player, ctx.rewardId) == ctx.rewardBefore + 1, tostring(smeltCount(player, ctx.rewardId))
    end)
    plan.act(function()
        local value = nativeSession()
        if value and not value.pendingChoice and ConchBlessing.GalleryManager.isCurrentGalleryRoom() then
            ConchBlessing.GalleryManager.returnToOrigin("appraisal_probe_complete")
        end
    end)
    plan.waitUntil(completed, 300)
    plan.check("final visit settled", function() return not not completed(), tostring(session() and session().phase) end)
    plan.act(function() observing = nil end)
end

-- Appraisal's own MC_USE_ITEM handler returns its result table, and the engine
-- stops running later callbacks once one returns a value; count uses early.
local callbackPriority = rawget(_G, "CallbackPriority")
local OBSERVE_PRIORITY = type(callbackPriority) == "table" and tonumber(callbackPriority.IMPORTANT) or -200
ConchBlessing:AddPriorityCallback(ModCallbacks.MC_USE_ITEM, OBSERVE_PRIORITY, function()
    if observing and TestBench.isRunning() then observing.uses = observing.uses + 1 end
end, ConchBlessing.ItemData.APPRAISAL_CERTIFICATE.id)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() observing = nil end)

TestBench.register({ command = "conch_test appraisal detail", tag = "AppraisalProbe", duration = "about 40 seconds", build = build })

return {}
