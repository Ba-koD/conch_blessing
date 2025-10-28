local hiddenItemManager = require("scripts.lib.hidden_item_manager")

ConchBlessing.chronus = ConchBlessing.chronus or {}

-- STATS: Item stat modifiers (Dark Rock style)
ConchBlessing.chronus.STATS = {
    DAMAGE_PER_FAMILIAR = 2.0,        -- Flat damage per absorbed familiar with absorbActions
}

-- Data container: configuration and runtime-safe defaults (no hardcoded debug literals)
ConchBlessing.chronus.data = ConchBlessing.chronus.data or {
    absorbAll = false,
    spriteNullPath = "gfx/ui/null.png",
    pairOffsetPixels = 2.0,
    laserEyeYOffset = -6,
    anchorDepthOffset = -10,
    scanIntervalFrames = 1,
    suspendWindowFrames = 120,
    blacklist = {
        [CollectibleType.COLLECTIBLE_ONE_UP] = true,
        [CollectibleType.COLLECTIBLE_ISAACS_HEART] = true,
        [CollectibleType.COLLECTIBLE_DEAD_CAT] = true,
        [CollectibleType.COLLECTIBLE_KEY_PIECE_1] = true,
        [CollectibleType.COLLECTIBLE_KEY_PIECE_2] = true,
        [CollectibleType.COLLECTIBLE_KNIFE_PIECE_1] = true,
        [CollectibleType.COLLECTIBLE_KNIFE_PIECE_2] = true,
    },
    -- Familiar -> Item conversion mapping
    -- When a familiar is absorbed, it grants this item
    -- maxGrants: 0 = unlimited, 1 = once only, 2 = twice, etc.
    familiarToItemMap = {
        [CollectibleType.COLLECTIBLE_ROBO_BABY] = {  -- Robo-Baby -> Technology
            itemId = CollectibleType.COLLECTIBLE_TECHNOLOGY,
            maxGrants = 0,  -- Unlimited: each Robo Baby grants Technology
        },
        [CollectibleType.COLLECTIBLE_LIL_BRIMSTONE] = {  -- Lil Brimstone -> Brimstone
            itemId = CollectibleType.COLLECTIBLE_BRIMSTONE,
            maxGrants = 0,  -- Unlimited: each Lil Brimstone grants Brimstone
        },
        [CollectibleType.COLLECTIBLE_BOBS_BRAIN] = {  -- Bob's Brain -> Ipecac
            itemId = CollectibleType.COLLECTIBLE_IPECAC,
            maxGrants = 1,  -- Only first Bob's Brain grants Ipecac
        },
        [CollectibleType.COLLECTIBLE_SERAPHIM] = {  -- Seraphim -> Sacred Heart
            itemId = CollectibleType.COLLECTIBLE_SACRED_HEART,
            maxGrants = 1,  -- Only first Seraphim grants Sacred Heart
        },
        -- Add more familiar -> item conversions here
        -- [FamiliarID] = { itemId = ItemID, maxGrants = N },
    },
    absorbActions = {
        [CollectibleType.COLLECTIBLE_TWISTED_PAIR] = function(player, total, delta)
            ConchBlessing.printDebug(string.format("[Chronus] Twisted Pair absorbed: total=%d, delta=%d", tonumber(total) or 0, tonumber(delta) or 0))
            ConchBlessing.chronus._ensureTwistedPairs(player)
            ConchBlessing.chronus._updateTwistedPairAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_INCUBUS] = function(player, total, delta)
            ConchBlessing.printDebug(string.format("[Chronus] Incubus absorbed: total=%d, delta=%d", tonumber(total) or 0, tonumber(delta) or 0))
            ConchBlessing.chronus._ensureIncubusStack(player)
            ConchBlessing.chronus._updateIncubusAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_SUCCUBUS] = function(player, total, delta)
            ConchBlessing.printDebug(string.format("[Chronus] Succubus absorbed: total=%d, delta=%d", tonumber(total) or 0, tonumber(delta) or 0))
            ConchBlessing.chronus._ensureSuccubusStack(player)
            ConchBlessing.chronus._updateSuccubusAnchors(player)
        end,
        [CollectibleType.COLLECTIBLE_SERAPHIM] = function(player, total, delta)
            ConchBlessing.printDebug(string.format("[Chronus] Seraphim absorbed: total=%d, delta=%d", tonumber(total) or 0, tonumber(delta) or 0))
            ConchBlessing.chronus._ensureSeraphimEffects(player)
        end,
    },
}

local CHRONUS_ID = Isaac.GetItemIdByName("Chronus")

local function dbg(msg)
    if ConchBlessing.Config and ConchBlessing.Config.debugMode then
        ConchBlessing.printDebug("[Chronus] " .. tostring(msg))
    end
end

local function getRunSave(player)
    local sm = ConchBlessing.SaveManager
    if not sm then return nil end
    local globalSave = sm.GetRunSave(nil)
    if not globalSave then return nil end
    globalSave.chronus = globalSave.chronus or { 
        absorbed = {}, 
        totalAbsorbed = 0,
        itemGrants = {},  -- Track how many items granted per familiar: ["fam_95"] = 3
    }

    if player then
        local per = sm.GetRunSave(player)
        if per and per.chronus and (per.chronus.absorbed or per.chronus.totalAbsorbed) then
            dbg("Migrating per-player chronus data to global store")
            local g = globalSave.chronus
            g.absorbed = g.absorbed or {}
            for cid, entry in pairs(per.chronus.absorbed or {}) do
                local prev = (g.absorbed[cid] and g.absorbed[cid].count) or 0
                local add = (entry and entry.count) or 0
                if add > 0 then
                    g.absorbed[cid] = { count = prev + add }
                end
            end
            g.totalAbsorbed = (g.totalAbsorbed or 0) + (per.chronus.totalAbsorbed or 0)
            per.chronus = nil
            sm.Save()
        end
    end

    return globalSave.chronus
end

local function isSuspended(player)
    local pdata = player and player:GetData() or nil
    local untilFrame = (pdata and pdata.__chronusSuspendUntil) or 0
    return Game():GetFrameCount() <= (tonumber(untilFrame) or 0)
end

local function ownsAnyBlacklisted(player)
    local bl = (ConchBlessing.chronus.data and ConchBlessing.chronus.data.blacklist) or {}
    for id, v in pairs(bl) do
        if v then
            local ok, has = pcall(function() return player:HasCollectible(id, true) end)
            if ok and has then return true end
        end
    end
    return false
end

function ConchBlessing.chronus.registerAbsorbAction(familiarCollectibleId, fn)
    if type(familiarCollectibleId) ~= "number" then return end
    if type(fn) ~= "function" then return end
    ConchBlessing.chronus.data.absorbActions[familiarCollectibleId] = fn
end

function ConchBlessing.chronus.addToBlacklist(familiarCollectibleId)
    if type(familiarCollectibleId) ~= "number" then return end
    ConchBlessing.chronus.data.blacklist[familiarCollectibleId] = true
end

local function countOwnedFamiliarCollectibles(player)
    local counts = {}
    local cfg = Isaac.GetItemConfig()
    if not cfg then return counts end
    for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
        local okItem, item = pcall(function() return cfg:GetCollectible(id) end)
        if okItem and item and item.Type == ItemType.ITEM_FAMILIAR then
            local okOwned, owned = pcall(function() return player:GetCollectibleNum(id, true) end)
            if okOwned and owned and owned > 0 then counts[id] = owned end
        end
    end
    return counts
end

function ConchBlessing.chronus._getAbsorbedCount(player, famId)
    local rs = getRunSave(player)
    if not rs then return 0 end
    -- Use string key to match how we save it
    local key = "fam_" .. tostring(famId)
    local sub = rs.absorbed[key]
    local count = (sub and sub.count) or 0
    return count
end

function ConchBlessing.chronus._handleFamiliarToItemConversion(player, familiarId, total, delta)
    local rs = getRunSave(player)
    if not rs then return end
    
    -- Check if this familiar has an item conversion defined in the map
    local conversionData = ConchBlessing.chronus.data.familiarToItemMap[familiarId]
    if not conversionData or not conversionData.itemId then return end
    
    local maxGrants = conversionData.maxGrants or 0
    local key = "fam_" .. tostring(familiarId)
    local currentGrants = (rs.itemGrants and rs.itemGrants[key]) or 0
    local itemsToGrant = 0
    
    if maxGrants == 0 then
        -- Unlimited: grant for each absorbed
        itemsToGrant = delta
    else
        -- Limited: grant only up to maxGrants total
        itemsToGrant = math.max(0, math.min(delta, maxGrants - currentGrants))
    end
    
    if itemsToGrant > 0 then
        for i = 1, itemsToGrant do
            player:AddCollectible(conversionData.itemId, 0, true)
        end
        -- Update granted count
        rs.itemGrants = rs.itemGrants or {}
        rs.itemGrants[key] = currentGrants + itemsToGrant
        ConchBlessing.SaveManager.Save()
        
        -- Update cache for item effects
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
        
        dbg(string.format("[Chronus] Familiar ID=%d -> Granted %d item(s) (ID=%d) (total granted: %d, maxGrants: %d)", 
            tonumber(familiarId) or 0, itemsToGrant, tonumber(conversionData.itemId) or 0, rs.itemGrants[key], maxGrants))
    elseif delta > 0 then
        dbg(string.format("[Chronus] Familiar ID=%d absorbed but no items granted (max %d already granted)", 
            tonumber(familiarId) or 0, maxGrants))
    end
end

function ConchBlessing.chronus._detectAndAbsorb(player)
    if not player then return false end
    if isSuspended(player) then return false end

    local rs = getRunSave(player)
    if not rs then return false end

    local owned = countOwnedFamiliarCollectibles(player)
    local changed = false
    local bl = ConchBlessing.chronus.data.blacklist or {}
    local actions = ConchBlessing.chronus.data.absorbActions or {}

    -- Store absorbed familiars info for later processing
    local absorbedFamiliars = {}
    
    for famId, ownedNow in pairs(owned) do
        if not bl[famId] and ownedNow > 0 then
            local prev = ConchBlessing.chronus._getAbsorbedCount(player, famId)
            local removed = 0
            for _ = 1, ownedNow do
                if player:HasCollectible(famId, true) then
                    player:RemoveCollectible(famId)
                    removed = removed + 1
                end
            end
            if removed > 0 then
                -- Use string key to prevent SaveManager from converting to array index
                local key = "fam_" .. tostring(famId)
                rs.absorbed[key] = { count = prev + removed, id = famId }
                rs.totalAbsorbed = (rs.totalAbsorbed or 0) + removed
                changed = true
                
                dbg(string.format("[Chronus] Absorbed familiar: ID=%d (key=%s), prev=%d, removed=%d, total=%d", 
                    tonumber(famId) or 0, key, prev, removed, prev + removed))
                
                -- Store for later processing
                table.insert(absorbedFamiliars, {
                    famId = famId,
                    total = prev + removed,
                    delta = removed
                })
            end
        end
    end

    -- Calculate damage bonus for ALL absorbed familiars
    local totalBonusDamage = 0
    for _, info in ipairs(absorbedFamiliars) do
        -- All absorbed familiars get damage bonus
        totalBonusDamage = totalBonusDamage + (ConchBlessing.chronus.STATS.DAMAGE_PER_FAMILIAR * info.delta)
        dbg(string.format("[Chronus] Adding damage bonus for familiar ID=%d: +%.2f (delta=%d)", 
            tonumber(info.famId) or 0, 
            ConchBlessing.chronus.STATS.DAMAGE_PER_FAMILIAR * info.delta, 
            tonumber(info.delta) or 0))
    end
    
    -- Apply damage bonus for all absorbed familiars (pass delta only, unified system handles cumulative)
    if changed and totalBonusDamage > 0 then
        dbg(string.format("[Chronus] Applying delta absorbed familiar bonus damage: +%.2f", totalBonusDamage))
        local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
        if um and um.SetItemAddition then
            -- SetItemAddition accumulates internally: cumulative = existing.cumulative + addition
            -- So pass ONLY the delta (totalBonusDamage), NOT the cumulative total
            um:SetItemAddition(player, CHRONUS_ID, "Damage", totalBonusDamage, string.format("Chronus: +%d familiars", #absorbedFamiliars))
            um:QueueCacheUpdate(player, "Damage")
            if um.SaveToSaveManager then um:SaveToSaveManager(player) end
            dbg(string.format("[Chronus] Applied delta bonus: +%.2f (unified system will accumulate)", totalBonusDamage))
        end
    end
    
    -- Now run absorbActions and item conversions AFTER base damage
    for _, info in ipairs(absorbedFamiliars) do
        -- 1. Run custom absorb action if defined (e.g., positioning, special effects)
        local fn = actions[info.famId]
        if type(fn) == "function" then
            pcall(fn, player, info.total, info.delta)
        end
        
        -- 2. Auto-handle familiarToItemMap conversions for ALL familiars
        ConchBlessing.chronus._handleFamiliarToItemConversion(player, info.famId, info.total, info.delta)
    end

    return changed
end

function ConchBlessing.chronus._finalizeAbsorb(player)
    if not player then return end
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if um and um.QueueCacheUpdate then
        um:QueueCacheUpdate(player, "Damage")
    else
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
end

-- Track converted item removal for all familiar->item mappings
function ConchBlessing.chronus._trackConvertedItemRemoval(player)
    if not player then return end
    
    local rs = getRunSave(player)
    if not rs then return end
    
    local familiarToItemMap = ConchBlessing.chronus.data.familiarToItemMap or {}
    rs.itemGrants = rs.itemGrants or {}
    
    -- Check each familiar->item conversion
    for familiarId, conversionData in pairs(familiarToItemMap) do
        if type(conversionData) ~= "table" then
            -- Old format compatibility
            conversionData = { itemId = conversionData, maxGrants = 0 }
        end
        
        local itemId = conversionData.itemId
        if not itemId then goto continue end  -- Skip if no item (like Seraphim with flying)
        
        local absorbedCount = ConchBlessing.chronus._getAbsorbedCount(player, familiarId)
        if absorbedCount <= 0 then goto continue end
        
        local key = "fam_" .. tostring(familiarId)
        local grantedCount = rs.itemGrants[key] or 0
        if grantedCount <= 0 then goto continue end
        
        -- Get actual converted item count
        local currentItemCount = player:GetCollectibleNum(itemId, true)
        
        -- Calculate how many granted items were removed
        local itemsRemoved = math.max(0, grantedCount - currentItemCount)
        
        if itemsRemoved > 0 then
            -- Reduce absorbed familiar count by items removed (up to maxGrants limit)
            local maxGrants = conversionData.maxGrants or 0
            local familiarReduction
            
            if maxGrants == 0 then
                -- Unlimited: 1 familiar per item removed
                familiarReduction = itemsRemoved
            else
                -- Limited: reduce only up to maxGrants
                familiarReduction = math.min(itemsRemoved, maxGrants)
            end
            
            -- Update absorbed count
            local newAbsorbedCount = math.max(0, absorbedCount - familiarReduction)
            if newAbsorbedCount > 0 then
                rs.absorbed[key] = { count = newAbsorbedCount, id = familiarId }
            else
                rs.absorbed[key] = nil
            end
            
            -- Update granted count
            rs.itemGrants[key] = math.max(0, currentItemCount)
            
            -- Update total absorbed
            rs.totalAbsorbed = (rs.totalAbsorbed or 0) - familiarReduction
            if rs.totalAbsorbed < 0 then rs.totalAbsorbed = 0 end
            
            ConchBlessing.SaveManager.Save()
            dbg(string.format("[Chronus] Detected %d item (ID:%d) removal, reduced familiar (ID:%d) count: %d -> %d (maxGrants=%d)", 
                itemsRemoved, tonumber(itemId) or 0, tonumber(familiarId) or 0, absorbedCount, newAbsorbedCount, maxGrants))
        end
        
        ::continue::
    end
end

-- Twisted Pair: spawn invisible Incubus with offset (2 per pair)
local function spawnInvisibleTwistedPairIncubus(player, pairIndex, side)
    dbg(string.format("Spawning Twisted Pair Incubus: pairIndex=%d, side=%d", tonumber(pairIndex) or 0, tonumber(side) or 0))
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.INCUBUS, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then 
        dbg("Failed to spawn Twisted Pair Incubus entity")
        return nil 
    end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    local spr = fam:GetSprite()
    local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
    pcall(function() spr:ReplaceSpritesheet(0, path) end)
    pcall(function() spr:LoadGraphics() end)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    local fd = fam:GetData()
    fd.__chronusTwistedPair = true
    fd.__chronusPairIndex = tonumber(pairIndex) or 1
    fd.__chronusSide = tonumber(side) or 1
    dbg(string.format("Twisted Pair Incubus spawned at position (%f, %f)", fam.Position.X, fam.Position.Y))
    return fam
end

function ConchBlessing.chronus._ensureTwistedPairs(player)
    if not player then return end
    
    local absorbedPairs = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_TWISTED_PAIR)
    local target = math.max(0, absorbedPairs * 2)
    
    local pdata = player:GetData()
    pdata.__chronusTwistedPairs = pdata.__chronusTwistedPairs or {}
    
    local kept = {}
    for _, f in ipairs(pdata.__chronusTwistedPairs) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusTwistedPair then table.insert(kept, f) end
        end
    end
    pdata.__chronusTwistedPairs = kept

    -- Only log when spawning new pairs
    while #pdata.__chronusTwistedPairs < target do
        local idx = math.floor(#pdata.__chronusTwistedPairs / 2) + 1
        local side = (#pdata.__chronusTwistedPairs % 2 == 0) and 1 or -1
        dbg(string.format("Spawning Twisted Pair Incubus %d/%d", #pdata.__chronusTwistedPairs + 1, target))
        local fam = spawnInvisibleTwistedPairIncubus(player, idx, side)
        if not fam then 
            dbg("Failed to spawn Twisted Pair Incubus, breaking loop")
            break 
        end
        table.insert(pdata.__chronusTwistedPairs, fam)
    end
end

function ConchBlessing.chronus._updateTwistedPairAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusTwistedPairs or nil
    if not list or #list == 0 then return end
    local dir = player:GetShootingInput()
    if not (dir and dir:Length() > 0) then dir = player:GetAimDirection() end
    if not (dir and dir:Length() > 0) then dir = player:GetMovementInput() end
    if not (dir and dir:Length() > 0) then dir = Vector(1, 0) end
    dir = dir:Normalized()
    local perp = Vector(-dir.Y, dir.X)
    if perp:Length() > 0 then perp = perp:Normalized() end
    local baseOffset = tonumber(ConchBlessing.chronus.data.pairOffsetPixels) or 0
    local eyeY = tonumber(ConchBlessing.chronus.data.laserEyeYOffset) or 0
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            local fd = fam:GetData()
            local side = (fd and fd.__chronusSide) or 1
            local pos = player.Position + perp * (side * baseOffset) + Vector(0, eyeY)
            fam.Position = pos
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
            fam:AddEntityFlags(EntityFlag.FLAG_NO_QUERY)
        end
    end
end

-- Incubus: spawn invisible Incubus fixed to player position (1 per item)
local function spawnInvisibleIncubus(player)
    dbg("Spawning Incubus (fixed position)")
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.INCUBUS, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then 
        dbg("Failed to spawn Incubus entity")
        return nil 
    end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    local spr = fam:GetSprite()
    local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
    pcall(function() spr:ReplaceSpritesheet(0, path) end)
    pcall(function() spr:LoadGraphics() end)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    local fd = fam:GetData()
    fd.__chronusIncubus = true
    dbg(string.format("Incubus spawned at position (%f, %f)", fam.Position.X, fam.Position.Y))
    return fam
end

function ConchBlessing.chronus._ensureIncubusStack(player)
    if not player then return end
    
    local absorbed = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_INCUBUS)
    local target = math.max(0, absorbed)
    
    local pdata = player:GetData()
    pdata.__chronusIncubi = pdata.__chronusIncubi or {}

    local kept = {}
    for _, f in ipairs(pdata.__chronusIncubi) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusIncubus then table.insert(kept, f) end
        end
    end
    pdata.__chronusIncubi = kept

    -- Only log when spawning new incubi
    while #pdata.__chronusIncubi < target do
        dbg(string.format("Spawning Incubus %d/%d", #pdata.__chronusIncubi + 1, target))
        local fam = spawnInvisibleIncubus(player)
        if not fam then 
            dbg("Failed to spawn Incubus, breaking loop")
            break 
        end
        table.insert(pdata.__chronusIncubi, fam)
    end
end

function ConchBlessing.chronus._updateIncubusAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusIncubi or nil
    if not list or #list == 0 then return end
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            fam.Position = player.Position
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
        end
    end
end

local function spawnInvisibleSuccubus(player)
    local ent = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SUCCUBUS, 0, player.Position, Vector.Zero, player)
    local fam = ent and ent:ToFamiliar() or nil
    if not fam then return nil end
    fam:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    local spr = fam:GetSprite()
    local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
    pcall(function() spr:ReplaceSpritesheet(0, path) end)
    pcall(function() spr:LoadGraphics() end)
    fam.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    fam:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
    fam.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    fam.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    local fd = fam:GetData()
    fd.__chronusSuccubus = true
    return fam
end

function ConchBlessing.chronus._ensureSuccubusStack(player)
    if not player then return end
    local absorbed = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_SUCCUBUS)
    local target = math.max(0, absorbed)
    local pdata = player:GetData()
    pdata.__chronusSuccubi = pdata.__chronusSuccubi or {}

    local kept = {}
    for _, f in ipairs(pdata.__chronusSuccubi) do
        if f and f:Exists() and f:ToFamiliar() then
            local fd = f:GetData()
            if fd and fd.__chronusSuccubus then table.insert(kept, f) end
        end
    end
    pdata.__chronusSuccubi = kept

    while #pdata.__chronusSuccubi < target do
        local fam = spawnInvisibleSuccubus(player)
        if not fam then break end
        table.insert(pdata.__chronusSuccubi, fam)
    end
end

-- Seraphim: add Fate costume for visual flying effect
-- Note: Flying ability is handled in onEvaluateCache, Homing+Spectral in onFireTear
function ConchBlessing.chronus._ensureSeraphimEffects(player)
    if not player then return end
    local absorbed = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
    if absorbed > 0 then
        -- Add Fate costume for visual flying effect
        local itemConfig = Isaac.GetItemConfig()
        local fateCostume = itemConfig:GetCollectible(CollectibleType.COLLECTIBLE_FATE)
        if fateCostume then
            player:AddCostume(fateCostume, false)
        end
    end
end

function ConchBlessing.chronus._updateSuccubusAnchors(player)
    local pdata = player and player:GetData() or nil
    local list = pdata and pdata.__chronusSuccubi or nil
    if not list or #list == 0 then return end
    local depth = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
    for _, fam in ipairs(list) do
        if fam and fam:Exists() then
            fam.Position = player.Position
            fam.DepthOffset = depth
            fam.Velocity = Vector.Zero
        end
    end
end

ConchBlessing.chronus.onPickup = function(_, player, collectibleType)
    if collectibleType ~= CHRONUS_ID then return end
    dbg("Picked up - initial sweep")
    local changed = ConchBlessing.chronus._detectAndAbsorb(player)
    if changed then ConchBlessing.chronus._finalizeAbsorb(player) end
end

ConchBlessing.chronus.onPlayerUpdate = function(_)
    local frame = Game():GetFrameCount()
    local n = Game():GetNumPlayers()
    for i = 0, n - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local pdata = player:GetData()
            if player:HasCollectible(CHRONUS_ID) then
                local hasBlacklisted = ownsAnyBlacklisted(player)
                if hasBlacklisted then
                    pdata.__chronusSuspendUntil = frame -- immediate expire; preserve visuals
                end
                pdata.__chronusNextScan = pdata.__chronusNextScan or 0
                local interval = tonumber(ConchBlessing.chronus.data.scanIntervalFrames) or 15
                if frame >= pdata.__chronusNextScan then
                    pdata.__chronusNextScan = frame + interval
                    if not hasBlacklisted then
                        local ok, changed = pcall(function() return ConchBlessing.chronus._detectAndAbsorb(player) end)
                        if ok and changed then ConchBlessing.chronus._finalizeAbsorb(player) end
                    end
                end

                -- Track converted item removal (all familiar->item conversions)
                ConchBlessing.chronus._trackConvertedItemRemoval(player)
                
                -- Update Twisted Pair (offset position)
                ConchBlessing.chronus._ensureTwistedPairs(player)
                ConchBlessing.chronus._updateTwistedPairAnchors(player)
                -- Update Incubus (fixed to player position)
                ConchBlessing.chronus._ensureIncubusStack(player)
                ConchBlessing.chronus._updateIncubusAnchors(player)
                -- Update Succubus (fixed to player position)
                ConchBlessing.chronus._ensureSuccubusStack(player)
                ConchBlessing.chronus._updateSuccubusAnchors(player)
            else
                ConchBlessing.chronus._revertAll(player)
            end
        end
    end
end

ConchBlessing.chronus.onPostUpdate = function() end

ConchBlessing.chronus.onEvaluateCache = function(_, player, cacheFlag)
    if not player then return end
    if not player:HasCollectible(CHRONUS_ID) then return end
    
    -- Grant flying ability when Seraphim is absorbed
    if cacheFlag == CacheFlag.CACHE_FLYING then
        local seraphimCount = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
        if seraphimCount > 0 then
            player.CanFly = true
            dbg(string.format("[Chronus] Granted flying ability (Seraphim absorbed: %d)", seraphimCount))
        end
    end
end

ConchBlessing.chronus.onGameStarted = function(_)
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(CHRONUS_ID) then return end
    local rs = getRunSave(player)
    if rs then
        dbg(string.format("Loaded: total=%d, kinds=%d", tonumber(rs.totalAbsorbed or 0), rs.absorbed and (function(t) local c=0 for _ in pairs(t) do c=c+1 end return c end)(rs.absorbed) or 0))
        
        if rs.absorbed then
            for key, data in pairs(rs.absorbed) do
                local famId = data.id or tonumber(key:match("fam_(%d+)")) or 0
                dbg(string.format("[Chronus] Loaded absorbed familiar: key=%s, ID=%d, count=%d", 
                    tostring(key), tonumber(famId) or 0, data.count or 0))
            end
        end
        
        -- Unified system automatically restores damage bonuses from its own save data
        -- No manual restoration needed; it handles cumulative additions internally
        dbg("[Chronus] Unified system will restore absorbed familiar damage bonuses automatically")
        
        -- Clean up old save data fields (no longer needed as unified system manages this)
        if rs.absorbedBonusDamage or rs.absorbActionBonusDamage then
            rs.absorbedBonusDamage = nil
            rs.absorbActionBonusDamage = nil
            ConchBlessing.SaveManager.Save()
            dbg("[Chronus] Cleaned up legacy damage bonus fields from save data")
        end
        
        local seraphimCount = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
        dbg(string.format("Found %d absorbed Seraphim on game start", tonumber(seraphimCount) or 0))
        
        -- Restore converted items for all familiar->item conversions
        local familiarToItemMap = ConchBlessing.chronus.data.familiarToItemMap or {}
        rs.itemGrants = rs.itemGrants or {}
        
        for familiarId, conversionData in pairs(familiarToItemMap) do
            if type(conversionData) ~= "table" then
                conversionData = { itemId = conversionData, maxGrants = 0 }
            end
            
            local itemId = conversionData.itemId
            if not itemId then goto continue_restore end  -- Skip if no item
            
            local familiarCount = ConchBlessing.chronus._getAbsorbedCount(player, familiarId)
            if familiarCount > 0 then
                local maxGrants = conversionData.maxGrants or 0
                local itemsToGrant
                
                if maxGrants == 0 then
                    -- Unlimited: grant for each familiar
                    itemsToGrant = familiarCount
                else
                    -- Limited: grant only up to maxGrants
                    itemsToGrant = math.min(familiarCount, maxGrants)
                end
                
                if itemsToGrant > 0 then
                    for i = 1, itemsToGrant do
                        player:AddCollectible(itemId, 0, true)
                    end
                    -- Track granted count
                    local key = "fam_" .. tostring(familiarId)
                    rs.itemGrants[key] = itemsToGrant
                    ConchBlessing.SaveManager.Save()
                    dbg(string.format("Restored %d item(s) (ID:%d) from %d absorbed familiar (ID:%d, maxGrants=%d)", 
                        itemsToGrant, tonumber(itemId) or 0, familiarCount, tonumber(familiarId) or 0, maxGrants))
                end
            end
            
            ::continue_restore::
        end
        
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FLYING | CacheFlag.CACHE_TEARFLAG | CacheFlag.CACHE_FIREDELAY)
        player:EvaluateItems()
    end
end

function ConchBlessing.chronus._revertAll(player)
    local rs = getRunSave(player)
    if not rs or not rs.absorbed then return false end
    local hadAny = false
    do
        local pdata = player and player:GetData() or {}
        -- Remove Twisted Pair
        if pdata.__chronusTwistedPairs then
            for _, f in ipairs(pdata.__chronusTwistedPairs) do
                if f and f:Exists() then f:Remove() end
            end
            pdata.__chronusTwistedPairs = nil
        end
        -- Remove Incubus
        if pdata.__chronusIncubi then
            for _, f in ipairs(pdata.__chronusIncubi) do
                if f and f:Exists() then f:Remove() end
            end
            pdata.__chronusIncubi = nil
        end
        -- Remove Succubi
        if pdata.__chronusSuccubi then
            for _, f in ipairs(pdata.__chronusSuccubi) do
                if f and f:Exists() then f:Remove() end
            end
            pdata.__chronusSuccubi = nil
        end
    end
    local familiarToItemMap = ConchBlessing.chronus.data.familiarToItemMap or {}
    
    for key, entry in pairs(rs.absorbed) do
        local count = (entry and entry.count) or 0
        if count > 0 then
            hadAny = true
            -- Extract actual ID from entry or key
            local famId = entry.id or tonumber(key:match("fam_(%d+)"))
            
            -- Check if this familiar has item conversion mapping
            local conversionData = famId and familiarToItemMap[famId]
            if type(conversionData) ~= "table" and conversionData then
                conversionData = { itemId = conversionData, maxGrants = 0 }
            end
            
            if famId and not conversionData then
                -- Normal familiar restoration (no item conversion)
                for _ = 1, count do
                    player:AddCollectible(famId, 0, false)
                end
                dbg(string.format("[Chronus] Restored familiar: key=%s, ID=%d, count=%d", tostring(key), tonumber(famId) or 0, count))
            elseif conversionData then
                -- Familiar with item conversion - will be handled via converted item removal below
                local itemId = conversionData.itemId or "none"
                dbg(string.format("[Chronus] Skipping familiar ID=%d restoration (has item conversion to ID=%s): count=%d", 
                    tonumber(famId) or 0, tostring(itemId), count))
            end
        end
    end
    if hadAny then
        -- Remove all damage additions and multipliers using unified system
        local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
        if um and um.RemoveItemAddition then
            -- RemoveItemAddition removes BOTH flat additions AND additive multipliers for the item
            um:RemoveItemAddition(player, CHRONUS_ID, "Damage")
            um:QueueCacheUpdate(player, "Damage")
        else
            player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
            player:EvaluateItems()
        end
        
        -- Remove converted items and restore familiars (for all familiar->item conversions)
        rs.itemGrants = rs.itemGrants or {}
        
        for familiarId, conversionData in pairs(familiarToItemMap) do
            if type(conversionData) ~= "table" then
                conversionData = { itemId = conversionData, maxGrants = 0 }
            end
            
            local itemId = conversionData.itemId
            if not itemId then goto continue_revert end  -- Skip if no item
            
            local familiarCount = ConchBlessing.chronus._getAbsorbedCount(player, familiarId)
            if familiarCount > 0 then
                local key = "fam_" .. tostring(familiarId)
                local grantedCount = rs.itemGrants[key] or 0
                local currentItemCount = player:GetCollectibleNum(itemId, true)
                
                -- Remove granted items (only what's present)
                local itemsToRemove = math.min(currentItemCount, grantedCount)
                for i = 1, itemsToRemove do
                    player:RemoveCollectible(itemId)
                end
                
                -- Calculate how many familiars to restore
                -- Based on removed items, but capped by maxGrants logic
                local maxGrants = conversionData.maxGrants or 0
                local familiarsToRestore
                
                if maxGrants == 0 then
                    -- Unlimited: restore 1 familiar per removed item
                    familiarsToRestore = itemsToRemove
                else
                    -- Limited: restore based on how many were actually granted
                    -- If maxGrants=1 and we remove 1 item, restore min(familiarCount, amount we can restore)
                    familiarsToRestore = math.min(itemsToRemove, familiarCount)
                end
                
                -- Restore familiars
                for i = 1, familiarsToRestore do
                    player:AddCollectible(familiarId, 0, false)
                end
                
                if familiarsToRestore < familiarCount then
                    dbg(string.format("[Chronus] Removed %d item (ID:%d) and restored %d familiar (ID:%d). %d familiar lost (granted:%d, maxGrants=%d)", 
                        itemsToRemove, tonumber(itemId) or 0, familiarsToRestore, tonumber(familiarId) or 0, 
                        familiarCount - familiarsToRestore, grantedCount, maxGrants))
                else
                    dbg(string.format("[Chronus] Removed %d item (ID:%d) and restored %d familiar (ID:%d) (granted:%d, maxGrants=%d)", 
                        itemsToRemove, tonumber(itemId) or 0, familiarsToRestore, tonumber(familiarId) or 0, grantedCount, maxGrants))
                end
            end
            
            ::continue_revert::
        end
        
        rs.absorbed = {}
        rs.totalAbsorbed = 0
        rs.itemGrants = {}  -- Clear granted item counts
        -- Legacy fields cleanup (unified system manages these now)
        rs.absorbedBonusDamage = nil
        rs.absorbActionBonusDamage = nil
        dbg("Reverted all Chronus effects and restored familiars")
        return true
    end
    return false
end

ConchBlessing.chronus.onFamiliarUpdate = function(_, fam)
    local f = fam and fam:ToFamiliar() or nil
    if not f then return end
    local fd = f:GetData() or {}
    
    -- Handle Twisted Pair Incubus (offset position with side)
    if f.Variant == FamiliarVariant.INCUBUS and fd.__chronusTwistedPair then
        if not fd.__chronusTwistedPairSpr then
            local spr = f:GetSprite()
            local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
            pcall(function() spr:ReplaceSpritesheet(0, path) end)
            pcall(function() spr:LoadGraphics() end)
            fd.__chronusTwistedPairSpr = true
            dbg(string.format("Twisted Pair Incubus sprite initialized: pairIdx=%s, side=%s", 
                tostring(fd.__chronusPairIndex or "nil"), 
                tostring(fd.__chronusSide or "nil")))
        end
        return
    end
    
    -- Handle Incubus (fixed to player position)
    if f.Variant == FamiliarVariant.INCUBUS and fd.__chronusIncubus then
        if not fd.__chronusIncubusSpr then
            local spr = f:GetSprite()
            local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
            pcall(function() spr:ReplaceSpritesheet(0, path) end)
            pcall(function() spr:LoadGraphics() end)
            fd.__chronusIncubusSpr = true
            dbg("Incubus sprite initialized (fixed position)")
        end
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE
        local player = f.Player
        if player then
            f.Position = player.Position
            f.Velocity = Vector.Zero
            f.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
        end
        return
    end
    
    -- Handle Succubus (fixed to player position)
    if f.Variant == FamiliarVariant.SUCCUBUS and fd.__chronusSuccubus then
        if not fd.__chronusSuccubusSpr then
            local spr = f:GetSprite()
            local path = tostring(ConchBlessing.chronus.data.spriteNullPath or "gfx/ui/null.png")
            pcall(function() spr:ReplaceSpritesheet(0, path) end)
            pcall(function() spr:LoadGraphics() end)
            fd.__chronusSuccubusSpr = true
        end
        f:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
        f.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        f.GridCollisionClass = GridCollisionClass.COLLISION_NONE
        local player = f.Player
        if player then
            f.Position = player.Position
            f.Velocity = Vector.Zero
            f.DepthOffset = tonumber(ConchBlessing.chronus.data.anchorDepthOffset) or 0
        end
    end
end

-- Add homing and spectral effects when Seraphim is absorbed
ConchBlessing.chronus.onFireTear = function(_, tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer() or nil
    if not player or not player:HasCollectible(CHRONUS_ID) then return end
    
    -- Robo Baby tech laser effect is handled by Technology item (granted in absorbAction)
    
    local seraphimCount = ConchBlessing.chronus._getAbsorbedCount(player, CollectibleType.COLLECTIBLE_SERAPHIM)
    if seraphimCount > 0 then
        -- Add homing and spectral effects when Seraphim is absorbed
        tear:AddTearFlags(TearFlags.TEAR_HOMING | TearFlags.TEAR_SPECTRAL)
        dbg(string.format("Added homing and spectral to tear (Seraphim absorbed: %d)", tonumber(seraphimCount) or 0))
    end
end
