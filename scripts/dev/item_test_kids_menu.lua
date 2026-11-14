local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Family Combo (패밀리 세트): the lifecycle contract. At every stage a pedestal
-- created now gains exactly one familiar choice while a copy is held (two
-- copies still give one, like Binge Eater), and none once the item is gone;
-- an earlier pedestal keeps what it was given. The rules against vanilla
-- Binge Eater are `cb test kids_menu parity`.
local H = require("scripts.dev.item_test_support")
local C = {}

local function pedestals()
    return Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1)
end

local function isFamiliar(id)
    local item = id and Isaac.GetItemConfig():GetCollectible(id)
    return item ~= nil and item ~= false and item.Type == ItemType.ITEM_FAMILIAR
end

C.KIDS_MENU = { prepare = function(plan)
    plan.act(function(_, ctx)
        H.suppressRandomGoldenPedestals(ctx)
        for _, p in ipairs(pedestals()) do p:Remove() end
        ctx.kept = nil
    end)
    plan.note("familiar items no item pool lists (never offered)", function()
        local menu, pool = ConchBlessing.kidsmenu, Game():GetItemPool()
        if not menu or type(pool.GetNumItemPools) ~= "function" then return "pool lists unavailable" end
        local offered, left = {}, {}
        for _, id in ipairs(menu.familiarItems()) do offered[id] = true end
        local config = Isaac.GetItemConfig()
        for id = 1, config:GetCollectibles().Size - 1 do
            local item = config:GetCollectible(id)
            if item and item.Type == ItemType.ITEM_FAMILIAR and not item.Hidden and not offered[id] then
                left[#left + 1] = id .. "(" .. tostring(item.Name) .. ")"
            end
        end
        return #left .. " left out of " .. (#left + #menu.familiarItems()) .. ": " .. table.concat(left, " ", 1, math.min(#left, 12))
    end)
end, stage = function(plan, _, n)
    plan.act(function(player, ctx)
        ctx.pickup = H.pickup(player, CollectibleType.COLLECTIBLE_SAD_ONION)
        ctx.cycleAPI = type(ctx.pickup.GetCollectibleCycle) == "function"
    end)
    plan.wait(15)
    plan.check(n > 0 and "a pedestal created now gains one familiar choice" or "a pedestal created without the item gains nothing",
        function(_, ctx)
            if not ctx.cycleAPI then return nil, "collectible-cycle API unavailable" end
            local cycle = ctx.pickup:GetCollectibleCycle()
            if n == 0 then return #cycle == 0, "extra choices=" .. #cycle end
            -- The pedestal turns: the familiar may be the one on show.
            local shown = ctx.pickup.SubType
            local familiar = isFamiliar(cycle[1]) and cycle[1] or isFamiliar(shown) and shown or nil
            return #cycle == 1 and familiar ~= nil,
                "copies=" .. n .. " shown=" .. shown .. " extra=[" .. table.concat(cycle, ",") .. "]"
        end)
    if n > 0 then
        -- User decision 2026-11-13: a familiar no item pool lists (another
        -- mod's upgrade-only item) is never offered. Read from the pools here,
        -- not from the item's own list.
        plan.check("the offered familiar is one some item pool lists", function(_, ctx)
            if not ctx.cycleAPI then return nil, "collectible-cycle API unavailable" end
            local pool = Game():GetItemPool()
            if type(pool.GetCollectiblesFromPool) ~= "function" or type(pool.GetNumItemPools) ~= "function" then
                return nil, "REPENTOGON pool lists unavailable"
            end
            local ids = { ctx.pickup.SubType }
            for _, id in ipairs(ctx.pickup:GetCollectibleCycle()) do ids[#ids + 1] = id end
            local familiar
            for _, id in ipairs(ids) do if id ~= CollectibleType.COLLECTIBLE_SAD_ONION and isFamiliar(id) then familiar = id end end
            if not familiar then return false, "no familiar on the pedestal" end
            local pools = {}
            for kind = 0, pool:GetNumItemPools() - 1 do
                for _, entry in ipairs(pool:GetCollectiblesFromPool(kind)) do
                    if entry.itemID == familiar then pools[#pools + 1] = kind break end
                end
            end
            return #pools > 0, string.format("familiar %d in pools [%s]", familiar, table.concat(pools, ","))
        end)
    end
    plan.check("an earlier pedestal keeps what it was given", function(_, ctx)
        if not ctx.kept then return true, "first stage" end
        local p = ctx.kept.pickup
        if not p:Exists() then return false, "earlier pedestal gone" end
        local ids = { p.SubType }
        for _, id in ipairs(p:GetCollectibleCycle()) do ids[#ids + 1] = id end
        local found = 0
        for _, id in ipairs(ids) do if id == ctx.kept.familiar then found = found + 1 end end
        return found == 1 and #ids == 2, "circle [" .. table.concat(ids, ",") .. "] familiar " .. tostring(ctx.kept.familiar)
    end)
    plan.act(function(_, ctx)
        local cycle = ctx.cycleAPI and ctx.pickup:GetCollectibleCycle() or {}
        if n > 0 and not ctx.kept and #cycle == 1 then
            -- Keep the first granted pedestal for the later stages; move it aside.
            ctx.pickup.Position = Game():GetRoom():GetCenterPos() + Vector(-140, -80)
            local shown = ctx.pickup.SubType
            ctx.kept = { pickup = ctx.pickup, familiar = isFamiliar(cycle[1]) and cycle[1] or shown }
        else
            ctx.pickup:Remove()
        end
    end)
end, finish = function(plan)
    plan.act(function() for _, p in ipairs(pedestals()) do p:Remove() end end)
end }

return C
