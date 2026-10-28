local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Conch Pearl (소라 진주): the lifecycle contract and its isolated cases. Every
-- draw goes through the engine's own ItemPool:GetCollectible, so the item's
-- MC_POST_GET_COLLECTIBLE runs exactly as it does for a real pedestal. Preview
-- draws (decrease = false) leave the pools untouched; the pedestal case spawns
-- real pedestals and therefore always starts from a fresh run.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local C = {}

local SEEDS = 400
local POOLS = { "POOL_TREASURE", "POOL_BOSS", "POOL_DEVIL", "POOL_SHOP" }

local function pearl() return ConchBlessing.conchpearl end

local function seedAt(i) return i * 7919 + 13 end

local function info(id)
    local config = id and id > 0 and Isaac.GetItemConfig():GetCollectible(id)
    if not config then return nil end
    return { quality = config.Quality, quest = config:HasTags(ItemConfig.TAG_QUEST),
        own = pearl()._test.getRegistry().own[id] == true }
end

local function drawAll(poolType)
    local pool, list = Game():GetItemPool(), {}
    for i = 1, SEEDS do list[i] = pool:GetCollectible(poolType, false, seedAt(i)) end
    return list
end

local function requireModule(plan)
    plan.require("Conch Pearl module, item config quality and quest tags available", function()
        local module = pearl()
        return module and module._test and ItemConfig and ItemConfig.TAG_QUEST
            and type(Game():GetItemPool().GetCollectible) == "function" or nil, "module or capability missing"
    end)
end

-- Low quality never shows while held; without a holder the filter does nothing.
local function lowQualityShown(list)
    local shown = 0
    for _, id in ipairs(list) do
        local item = info(id)
        if item and item.quality <= 1 and not item.quest and not item.own then shown = shown + 1 end
    end
    return shown
end

C.CONCH_PEARL = { stage = function(plan, _, n)
    plan.check("filter follows ownership through stacking, removal and reacquisition", function()
        return pearl().isActive() == (n > 0), "copies=" .. n .. " active=" .. tostring(pearl().isActive())
    end)
    plan.check(n > 0 and "treasure draws never show quality 0-1" or "no holder: draws are left alone", function()
        local module = pearl()
        module._test.resetEvidence()
        local shown = lowQualityShown(drawAll(ItemPoolType.POOL_TREASURE))
        local evidence = module._test.evidence()
        if n > 0 then
            return shown == 0 and evidence.redraws > 0,
                "low quality shown=" .. shown .. " redraws=" .. evidence.redraws
        end
        return evidence.redraws == 0 and evidence.conversions == 0,
            "redraws=" .. evidence.redraws .. " conversions=" .. evidence.conversions
    end)
end }

S.add("CONCH_PEARL", "draws", { conditions = true }, function(plan, id)
    requireModule(plan)
    plan.act(function(_, ctx)
        -- The same seeds without a holder are the vanilla answer for each draw.
        ctx.control = {}
        for _, name in ipairs(POOLS) do ctx.control[name] = drawAll(ItemPoolType[name]) end
    end)
    plan.act(function(player, ctx)
        player:AddCollectible(id, 0, false)
        pearl()._test.resetEvidence()
        ctx.held = {}
        for _, name in ipairs(POOLS) do ctx.held[name] = drawAll(ItemPoolType[name]) end
    end)
    plan.check("every draw keeps, redraws or converts by its vanilla quality", function(_, ctx)
        for _, name in ipairs(POOLS) do
            for i = 1, SEEDS do
                local before, after = ctx.control[name][i], ctx.held[name][i]
                local v, r = info(before), info(after)
                if not v or not r then return false, name .. " seed " .. i .. ": unknown item" end
                local ok
                if v.quest or v.own or v.quality >= 3 then ok = after == before
                elseif v.quality == 2 then ok = after == before or r.own
                else ok = r.own or (r.quality >= 2 and not r.quest) or (r.quest and after ~= before) end
                if not ok then
                    return false, string.format("%s seed %d: vanilla %d (q%d) -> %d (q%d)",
                        name, i, before, v.quality, after, r.quality)
                end
            end
        end
        return true, SEEDS .. " seeds x " .. #POOLS .. " pools"
    end)
    plan.check("quality 2 converts at the advertised 10%", function(_, ctx)
        local q2, converted = 0, 0
        for _, name in ipairs(POOLS) do
            for i = 1, SEEDS do
                local v = info(ctx.control[name][i])
                if v and v.quality == 2 and not v.quest and not v.own then
                    q2 = q2 + 1
                    if ctx.held[name][i] ~= ctx.control[name][i] then converted = converted + 1 end
                end
            end
        end
        local chance = pearl().data.convertChance
        if q2 < 100 then return nil, "only " .. q2 .. " quality 2 draws; inconclusive" end
        local rate = converted / q2
        local bound = 3 * math.sqrt(chance * (1 - chance) / q2)
        return math.abs(rate - chance) <= bound,
            string.format("converted %d/%d = %.2f%% (expected %.0f%% +/- %.2f%%)", converted, q2,
                rate * 100, chance * 100, bound * 100)
    end)
    plan.check("conversions come from the draw's pool first, else from any of ours", function(_, ctx)
        for _, name in ipairs(POOLS) do
            local allowed = {}
            for _, candidate in ipairs(pearl().candidatesFor(ItemPoolType[name])) do allowed[candidate] = true end
            for i = 1, SEEDS do
                local before, after = ctx.control[name][i], ctx.held[name][i]
                local r = info(after)
                if after ~= before and r and r.own and not allowed[after] then
                    return false, name .. " converted to " .. after .. " outside its candidates"
                end
            end
        end
        return true, "devil/shop/treasure: own pool; boss: any"
    end)
    plan.note("redraws and conversions", function()
        local e = pearl()._test.evidence()
        return "redraws=" .. e.redraws .. " conversions=" .. e.conversions .. " fallbacks=" .. e.fallbacks
            .. " spawnCollectibles=" .. tostring(ConchBlessing.Config and ConchBlessing.Config.spawnCollectibles)
    end)
end)

S.add("CONCH_PEARL", "exclusions", { conditions = true }, function(plan, id)
    requireModule(plan)
    local function ids(name)
        local data = ConchBlessing.ItemData[name]
        return data and data.id
    end
    plan.act(function(player, ctx)
        ctx.kronos, ctx.power, ctx.dragon = ids("KRONOS"), ids("POWER_TRAINING"), ids("DRAGON")
        assert(ctx.kronos and ctx.power and ctx.dragon, "fixture items unresolved")
        player:AddCollectible(id, 0, false)
        player:AddCollectible(ctx.kronos, 0, false)       -- one copy is all that counts
        player:AddCollectible(ctx.power, 0, true, ActiveSlot.SLOT_PRIMARY) -- an active
        player:AddCollectible(ctx.dragon, 0, false)       -- copies stack
    end)
    plan.wait(4)
    plan.check("held single-copy items, held actives and the pearl itself are never offered", function(_, ctx)
        local offered = {}
        for _, candidate in ipairs(pearl().candidatesFor(ItemPoolType.POOL_BOSS)) do offered[candidate] = true end
        return not offered[ctx.kronos] and not offered[ctx.power] and not offered[id] and offered[ctx.dragon] == true,
            "kronos=" .. tostring(offered[ctx.kronos]) .. " power=" .. tostring(offered[ctx.power])
                .. " pearl=" .. tostring(offered[id]) .. " dragon=" .. tostring(offered[ctx.dragon])
    end)
    plan.check("real draws never become an excluded item", function(_, ctx)
        local dragon, total = 0, 0
        for _, name in ipairs(POOLS) do
            for _, result in ipairs(drawAll(ItemPoolType[name])) do
                if result == ctx.kronos or result == ctx.power or result == id then
                    return false, name .. " drew excluded " .. result
                end
                if result == ctx.dragon then dragon = dragon + 1 end
                total = total + 1
            end
        end
        return true, total .. " draws, Dragon offered " .. dragon .. " times"
    end)
    plan.act(function(player, ctx) player:RemoveCollectible(ctx.kronos) end)
    plan.wait(2)
    plan.check("dropping the single-copy item makes it a candidate again", function(_, ctx)
        for _, candidate in ipairs(pearl().candidatesFor(ItemPoolType.POOL_BOSS)) do
            if candidate == ctx.kronos then return true, "Kronos offered again" end
        end
        return false, "Kronos still excluded"
    end)
end)

S.add("CONCH_PEARL", "pedestal", {}, function(plan, id)
    requireModule(plan)
    plan.section("CONCH_PEARL / pedestal",
        "the replaced item's icon rises over the new pedestal, holds, then crumbles into the air")
    plan.act(function(player, ctx)
        -- The dust is hidden over question-mark pedestals; this case checks it is shown.
        local level = Game():GetLevel()
        if (level:GetCurses() & LevelCurse.CURSE_OF_BLIND) ~= 0 then level:RemoveCurses(LevelCurse.CURSE_OF_BLIND) end
        player:AddCollectible(id, 0, false)
        ctx.spawns, ctx.lowShown, ctx.effectsBefore = 0, 0, #pearl()._test.effects()
        pearl()._test.resetEvidence()
        ctx.position = Game():GetRoom():FindFreePickupSpawnPosition(player.Position + Vector(0, -80), 0, true)
        ctx.cleanupFns = ctx.cleanupFns or {}
        table.insert(ctx.cleanupFns, function()
            if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end
        end)
    end)
    -- Spawn real random pedestals (they draw from the room's pool with decrease)
    -- until one is converted; check every pedestal on the way.
    plan.waitUntil(function(_, ctx)
        if ctx.pickup and ctx.pickup:Exists() then ctx.pickup:Remove() end
        ctx.spawns = ctx.spawns + 1
        ctx.pickup = Game():Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, ctx.position,
            Vector.Zero, nil, 0, seedAt(ctx.spawns + 1000)):ToPickup()
        local item = info(ctx.pickup.SubType)
        if item and item.quality <= 1 and not item.quest and not item.own then ctx.lowShown = ctx.lowShown + 1 end
        -- The draw and the pickup's init run inside Spawn, so a conversion for
        -- this pedestal is already recorded when Spawn returns.
        local last = pearl()._test.evidence().lastConversion
        if last and ctx.pickup.SubType == last.id then ctx.conversion = last; return true end
        return false, "spawned " .. ctx.spawns
    end, 300, "a real pedestal converted")
    plan.check("no spawned pedestal showed quality 0-1", function(_, ctx)
        return ctx.lowShown == 0, "low quality pedestals=" .. ctx.lowShown .. " of " .. ctx.spawns
    end)
    plan.check("the converted pedestal holds one of ours and shows what it replaced", function(_, ctx)
        local effects = pearl()._test.effects()
        local effect = effects[#effects]
        local item = info(ctx.pickup.SubType)
        return item and item.own and #effects > ctx.effectsBefore and effect.icons[1].itemId == ctx.conversion.replaced,
            "pedestal=" .. ctx.pickup.SubType .. " replaced=" .. tostring(ctx.conversion.replaced)
                .. " effects=" .. #effects
    end)
    plan.note("pedestal draw", function(_, ctx)
        return "pool=" .. tostring(ctx.conversion.pool) .. " decrease=" .. tostring(ctx.conversion.decrease)
            .. " spawns=" .. ctx.spawns
            .. " spawnCollectibles=" .. tostring(ConchBlessing.Config and ConchBlessing.Config.spawnCollectibles)
    end)
    plan.waitUntil(function() return #pearl()._test.effects() == 0 end, 200, "the dust ends after its timeline")
end)

return C
