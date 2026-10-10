local H = require("scripts.dev.item_test_support")
local C = {}
local used = {}

C.AR_GLASSES = { stage = function(plan, _, n)
    plan.require("next-use Conch reservation API available", function()
        local api=MagicConch and MagicConch.API
        return api and type(api.PreviewResult)=="function"
            and type(api.ReserveNextResult)=="function" and type(api.GetNextResultReservation)=="function"
            and type(api.ClearNextResultReservation)=="function" or nil,
            "requires current Magic Conch API"
    end)
    plan.check("chooser ownership follows copies and final removal", function()
        return ConchBlessing.arglasses.hasOwner()==(n>0), "copies="..n
    end)
    plan.check("cycling/cancelling a choice does not use Conch", function()
        local before=MagicConch:GetCurrentRoomUsage()
        local ar=ConchBlessing.arglasses
        ar.reset()
        local opened=ar.cycle()
        local prediction=ar.getSelection()
        ar.reset()
        return opened==(n>0) and (prediction~=nil)==(n>0)
            and before==MagicConch:GetCurrentRoomUsage(), "no use consumed"
    end)
end }

C.HEMISPATIAL_NEGLECT = { stage = function(plan, id, n)
    plan.check("damage doubles per copy and restores after removal", function(player, ctx)
        return H.expect(player.Damage, ctx.base.Damage * 2^n)
    end)
    plan.check("StatsAPI owns one replacement multiplier", function(player)
        local state=ConchBlessing.getUnifiedMultiplierState(player, ConchBlessing.stats.unifiedMultipliers)
        local row=state and state.itemMultipliers and state.itemMultipliers[id]
        local value=row and row.Damage and row.Damage.value
        return n==0 and value==nil or value==2^n, "multiplier="..tostring(value)
    end)
end }

C.REAL_EYES = { stage = function(plan, _, n)
    plan.require("Magic Conch read-only preview API available", function()
        return MagicConch and MagicConch.API and type(MagicConch.API.PreviewResult) == "function"
            and MagicConch.Config.enabled or nil, "requires enabled Magic Conch with PreviewResult"
    end)
    plan.check("prediction follows ownership through stacking, removal and reacquisition", function()
        local prediction, reason = ConchBlessing.realeyes.getPrediction()
        if n == 0 then return prediction == nil and reason == "NO_OWNER", "expected no prediction; reason=" .. tostring(reason) end
        local expected = MagicConch.API.PreviewResult(0)
        return prediction ~= nil and expected ~= nil and prediction.id == expected.id
            and prediction.text == expected.text and prediction.type == expected.type,
            "expected=" .. tostring(expected and expected.text) .. " actual=" .. tostring(prediction and prediction.text)
    end)
    plan.check("repeated predictions consume no room uses", function()
        local before = MagicConch:GetCurrentRoomUsage()
        for _ = 1, 60 do ConchBlessing.realeyes.getPrediction() end
        return H.expect(MagicConch:GetCurrentRoomUsage(), before)
    end)
end }

ConchBlessing:AddCallback(ModCallbacks.MC_USE_ITEM, function(_, id)
    if not require("scripts.dev.test_bench").isRunning() then return end
    used[id] = (used[id] or 0) + 1
end)

local function pedestals()
    return Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1)
end

local function clearPedestals()
    for _, pickup in ipairs(pedestals()) do pickup:Remove() end
end

C.INF_D6 = { stage = function(plan, id, n)
    if n == 0 then
        plan.check("no active remains in either slot", function(player)
            return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) ~= id and player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) ~= id,
                "removed from active slots"
        end)
        return
    end
    plan.act(function(player, ctx)
        ctx.pickup = H.pickup(player, CollectibleType.COLLECTIBLE_BREAKFAST)
        ctx.d6Before = used[CollectibleType.COLLECTIBLE_D6] or 0
        H.use(player, id)
    end)
    plan.wait(5)
    plan.check("exactly one vanilla D6 use per activation with either copy count", function(_, ctx)
        return H.expect((used[CollectibleType.COLLECTIBLE_D6] or 0) - ctx.d6Before, 1)
    end)
    plan.check("rerolled pedestal remains and active is reusable", function(player, ctx)
        return ctx.pickup:Exists() and ctx.pickup.SubType > 0 and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == id,
            "pedestal=" .. ctx.pickup.SubType
    end)
    plan.act(clearPedestals)
end }

C.APPRAISAL_CERTIFICATE = { stage = function(plan, id, n)
    if n == 0 then return end
    plan.act(function(player, ctx)
        player:AddCoins(29 - player:GetNumCoins())
        ctx.appraisalUses = used[id] or 0
        ctx.roomBefore = Game():GetLevel():GetCurrentRoomDesc().ListIndex
        H.use(player, id)
    end)
    plan.wait(5)
    plan.check("failed use costs nothing and never reaches MC_USE_ITEM", function(player, ctx)
        return (used[id] or 0) == ctx.appraisalUses and player:GetNumCoins() == 29
            and Game():GetLevel():GetCurrentRoomDesc().ListIndex == ctx.roomBefore, "29 coins, same room, no accepted use"
    end)
end }

C.UTILITY_BELT = { stage = function(plan, _, n, index)
    -- A moved active is intentionally kept when the belt is lost. A fresh belt
    -- ownership can move the next primary; a second copy cannot duplicate it.
    if index == 1 or index == 4 then
        plan.act(function(player)
            local pocket = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            if pocket > 0 then player:RemoveCollectible(pocket, false, ActiveSlot.SLOT_POCKET) end
            player:AddCollectible(CollectibleType.COLLECTIBLE_D6, 3, false, ActiveSlot.SLOT_PRIMARY)
        end)
        plan.wait(10)
    end
    plan.check("active placement and charge survive stack changes", function(player)
        if n == 0 and index == 4 then
            return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == CollectibleType.COLLECTIBLE_D6
                and player:GetActiveItem(ActiveSlot.SLOT_POCKET) == 0, "lost belt does not move a new active"
        end
        return player:GetActiveItem(ActiveSlot.SLOT_POCKET) == CollectibleType.COLLECTIBLE_D6
            and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) == 0
            and player:GetActiveCharge(ActiveSlot.SLOT_POCKET) == 3, "exactly one D6 in pocket with three charges"
    end)
end }

C.TWO_FACED_PENNY = { permanent = true, stage = function(plan, _, n, index)
    plan.act(function(player, ctx)
        ctx.unclaimed = (index == 1 or index == 2 or index == 5) and 1 or 0
        ctx.rewardBefore = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, true)
        player:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, 0, true)
    end)
    plan.wait(10)
    plan.check("new acquisition rewards exactly the still-unclaimed copies", function(player, ctx)
        return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, true) - ctx.rewardBefore,
            1 + (n > 0 and ctx.unclaimed or 0))
    end)
    plan.check("removed copies release their tracking slots", function(player)
        return H.expect(#(player:GetData().__twofacedpenny.slots or {}), n)
    end)
    plan.act(function(player, ctx) ctx.rewardStable = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, true) end)
    plan.wait(20)
    plan.check("granted copies neither recurse nor disappear on owner loss", function(player, ctx)
        return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY, true), ctx.rewardStable)
    end)
end }

C.SEVERED_OATH = { prepare = function(plan)
    plan.act(function(_, ctx) H.suppressRandomGoldenPedestals(ctx) end)
end, stage = function(plan, id, n)
    plan.act(function(player, ctx)
        clearPedestals()
        ctx.pickup = H.pickup(player, CollectibleType.COLLECTIBLE_BREAKFAST)
        ctx.cycleAPI = type(ctx.pickup.GetCollectibleCycle) == "function" and type(ctx.pickup.AddCollectibleCycle) == "function"
    end)
    plan.wait(15)
    plan.check("new pedestal receives only one extra choice while owned", function(_, ctx)
        if not ctx.cycleAPI then return nil, "collectible-cycle API unavailable" end
        return H.expect(#ctx.pickup:GetCollectibleCycle(), n > 0 and 1 or 0)
    end)
    if n > 0 then
        plan.act(function(player, ctx) if ctx.cycleAPI then H.use(player, id) end end)
        plan.wait(10)
        plan.check("one activation splits the two choices exactly once", function(_, ctx)
            if not ctx.cycleAPI then return nil, "collectible-cycle API unavailable" end
            return H.expect(#pedestals(), 2)
        end)
    end
    plan.act(clearPedestals)
end }

C.ATROPOS = { prepare = function(plan)
    plan.act(function(player, ctx)
        ctx.options = { H.pickup(player, CollectibleType.COLLECTIBLE_BREAKFAST), H.pickup(player, CollectibleType.COLLECTIBLE_DINNER) }
        for i, pickup in ipairs(ctx.options) do
            pickup.Position = Game():GetRoom():GetCenterPos() + Vector(100, (i - 1) * 60)
            pickup.OptionsPickupIndex = 777
        end
    end)
end, stage = function(plan, _, n)
    plan.check("option links clear once while held and restore after final loss", function(_, ctx)
        for _, pickup in ipairs(ctx.options) do
            if not pickup:Exists() then return false, "option pickup disappeared" end
            if pickup.OptionsPickupIndex ~= (n > 0 and 0 or 777) then
                return false, "option group=" .. pickup.OptionsPickupIndex
            end
        end
        return true, "both original group IDs retained across duplicate copies and reacquisition"
    end)
end, finish=function(plan,id)
    plan.section("ATROPOS / actually acquire both formerly linked choices")
    plan.act(function(player) player:AddTrinket(id,false) end)
    plan.wait(4)
    for index=1,2 do
        plan.act(function(player,ctx)
            local pickup=ctx.options[index]
            assert(pickup and pickup:Exists(),"remaining choice disappeared")
            ctx.choiceId=pickup.SubType
            ctx.choiceBefore=player:GetCollectibleNum(ctx.choiceId,true)
            pickup.Wait=0
            player.Position=pickup.Position
        end)
        plan.waitUntil(function(player,ctx)
            return player:GetCollectibleNum(ctx.choiceId,true)==ctx.choiceBefore+1 and player:IsItemQueueEmpty()
        end,180,"natural choice pickup finishes")
        if index==1 then
            plan.check("second original choice survives the first real acquisition",function(_,ctx)
                return ctx.options[2]:Exists() and ctx.options[2].OptionsPickupIndex==0,"second pedestal still available"
            end)
        end
    end
end }

local function visitTreasure(plan)
    plan.act(function(player, ctx)
        local rooms = Game():GetLevel():GetRooms()
        local target
        for i = 0, rooms.Size - 1 do
            local desc = rooms:Get(i)
            if desc.Data and desc.Data.Type == RoomType.ROOM_TREASURE then target = desc; break end
        end
        assert(target, "no native treasure room on this test floor")
        ctx.treasureIndex = target.ListIndex
        Game():StartRoomTransition(target.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, player)
    end)
    plan.waitUntil(function(_, ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex == ctx.treasureIndex end,
        180, "native treasure-room entry")
    plan.wait(20)
end

C.ANGELS_CROWN = { permanent = true, stage = function(plan, _, _, index)
    if index == 1 then visitTreasure(plan) end
    plan.check("converted angel deals survive partial/final trinket removal", function(_, ctx)
        local pickups = pedestals()
        if #pickups == 0 then return false, "no converted pedestal" end
        local snapshot = {}
        for _, entity in ipairs(pickups) do
            local pickup = entity:ToPickup()
            local config = Isaac.GetItemConfig():GetCollectible(pickup.SubType)
            local expected = config and config.ShopPrice and config.ShopPrice > 0 and math.floor(config.ShopPrice) or 15
            if pickup.Price ~= expected or pickup.ShopItemId ~= -1 or pickup.AutoUpdatePrice then
                return false, "coin-price contract changed: " .. tostring(pickup.Price) .. " expected " .. expected
            end
            snapshot[pickup.InitSeed] = pickup.SubType
        end
        if ctx.deals then
            local count = 0
            for seed, id in pairs(ctx.deals) do
                count = count + 1
                if snapshot[seed] ~= id then return false, "conversion repeated on count change" end
            end
            if count ~= #pickups then return false, "duplicate reward after stack change" end
        end
        ctx.deals = snapshot
        return true, "stable pedestal identities and individual coin prices"
    end)
end, finish = function(plan)
    plan.act(function(_, ctx) ctx.oldStage = Game():GetLevel():GetStage(); Isaac.ExecuteCommand("stage 2") end)
    plan.waitUntil(function(_, ctx) return Game():GetLevel():GetStage() ~= ctx.oldStage end, 180, "fresh unowned floor")
    visitTreasure(plan)
    plan.check("new room is not converted after final removal", function()
        local pickups = pedestals()
        if #pickups == 0 then return false, "no fresh treasure pedestal" end
        for _, entity in ipairs(pickups) do if entity:ToPickup().Price ~= 0 then return false, "new paid deal while absent" end end
        return true, "new treasure room stays free"
    end)
end }

return C
