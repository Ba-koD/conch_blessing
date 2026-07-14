-- Conch's Blessing - Upgrade System
-- Item conversion system using Magic Conch API

ConchBlessing.printDebug("Upgrade system loaded!")

-- Upgrade job queue (ensures BEFORE fully completes before AFTER)
ConchBlessing._upgradeJobs = ConchBlessing._upgradeJobs or {}

local function _resolveFunction(path)
    if type(path) ~= "string" then
        return nil
    end
    
    ConchBlessing.printDebug("_resolveFunction called with path: " .. tostring(path))
    
    -- Try to use CallbackManager first if available
    if ConchBlessing.CallbackManager and ConchBlessing.CallbackManager.getFunctionByPath then
        local func = ConchBlessing.CallbackManager.getFunctionByPath(path)
        ConchBlessing.printDebug("  CallbackManager result: " .. tostring(func))
        if func then
            return func
        end
    end
    
    -- Fallback: direct function lookup
    local parts = {}
    for part in path:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    
    ConchBlessing.printDebug("  Direct lookup parts: " .. table.concat(parts, ", "))
    
    local current = ConchBlessing
    for _, part in ipairs(parts) do
        if current and current[part] then
            current = current[part]
            ConchBlessing.printDebug("    Found part: " .. part .. " -> " .. tostring(current))
        else
            ConchBlessing.printDebug("    Missing part: " .. part)
            return nil
        end
    end
    
    ConchBlessing.printDebug("  Final result: " .. tostring(current))
    return current
end

local VALID_UPGRADE_FLAGS = {
    positive = true,
    neutral = true,
    negative = true,
}

local PENDING_UPGRADE_DATA_KEY = "__ConchBlessingUpgradeJob"
local PICKUP_LOCK_DATA_KEY = "__ConchBlessingUpgradePickupLock"

local function _callUpgradeFunction(label, fn, ...)
    if type(fn) ~= "function" then
        return 0
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        ConchBlessing.printError("[Upgrade] " .. label .. " failed: " .. tostring(result))
        return 0
    end

    return tonumber(result) or 0
end

local function _callConfiguredHook(path, label, ...)
    if path == nil then
        return 0
    end

    local fn = _resolveFunction(path)
    if type(fn) ~= "function" then
        ConchBlessing.printError("[Upgrade] " .. label .. " is not callable: " .. tostring(path))
        return 0
    end

    return _callUpgradeFunction(label, fn, ...)
end

local function _getUpgradeTemplate(flag)
    if not VALID_UPGRADE_FLAGS[flag] then
        return nil
    end

    local templateRoot = ConchBlessing.template
    local template = templateRoot and templateRoot[flag] or nil
    if type(template) ~= "table"
        or type(template.onBeforeChange) ~= "function"
        or type(template.onAfterChange) ~= "function" then
        ConchBlessing.printError("[Upgrade] Missing template for flag: " .. tostring(flag))
        return nil
    end

    return template
end

-- Normalize origin declaration (number | string | table) to numeric id and trinket/collectible type
local function _resolveOriginAny(originDecl, fallbackItemType)
    local explicitType = nil
    local resolvedId = nil

    -- Accept simple number id directly
    if type(originDecl) == "number" then
        resolvedId = originDecl
    elseif type(originDecl) == "string" then
        -- Try by name; prefer collectible first, then trinket
        local ok1, idCol = pcall(function()
            return Isaac.GetItemIdByName and Isaac.GetItemIdByName(originDecl) or nil
        end)
        if ok1 and type(idCol) == "number" and idCol > 0 then
            resolvedId = idCol
            explicitType = "collectible"
        else
            local ok2, idTr = pcall(function()
                return Isaac.GetTrinketIdByName and Isaac.GetTrinketIdByName(originDecl) or nil
            end)
            if ok2 and type(idTr) == "number" and idTr > 0 then
                resolvedId = idTr
                explicitType = "trinket"
            end
        end
    elseif type(originDecl) == "table" then
        explicitType = originDecl.type
        resolvedId = originDecl.id
        if not resolvedId then
            if originDecl.collectible then
                explicitType = explicitType or "collectible"
                local okC, idC = pcall(function()
                    return Isaac.GetItemIdByName and Isaac.GetItemIdByName(originDecl.collectible) or nil
                end)
                if okC and type(idC) == "number" and idC > 0 then
                    resolvedId = idC
                end
            elseif originDecl.trinket then
                explicitType = explicitType or "trinket"
                local okT, idT = pcall(function()
                    return Isaac.GetTrinketIdByName and Isaac.GetTrinketIdByName(originDecl.trinket) or nil
                end)
                if okT and type(idT) == "number" and idT > 0 then
                    resolvedId = idT
                end
            elseif originDecl.name then
                if explicitType == "trinket" then
                    local okTN, idTN = pcall(function()
                        return Isaac.GetTrinketIdByName and Isaac.GetTrinketIdByName(originDecl.name) or nil
                    end)
                    if okTN and type(idTN) == "number" and idTN > 0 then
                        resolvedId = idTN
                    end
                elseif explicitType == "collectible" then
                    local okCN, idCN = pcall(function()
                        return Isaac.GetItemIdByName and Isaac.GetItemIdByName(originDecl.name) or nil
                    end)
                    if okCN and type(idCN) == "number" and idCN > 0 then
                        resolvedId = idCN
                    end
                else
                    -- No explicit type: try collectible then trinket
                    local okCN, idCN = pcall(function()
                        return Isaac.GetItemIdByName and Isaac.GetItemIdByName(originDecl.name) or nil
                    end)
                    if okCN and type(idCN) == "number" and idCN > 0 then
                        resolvedId = idCN
                        explicitType = "collectible"
                    else
                        local okTN, idTN = pcall(function()
                            return Isaac.GetTrinketIdByName and Isaac.GetTrinketIdByName(originDecl.name) or nil
                        end)
                        if okTN and type(idTN) == "number" and idTN > 0 then
                            resolvedId = idTN
                            explicitType = "trinket"
                        end
                    end
                end
            end
        end
    end

    -- Decide trinket vs collectible
    local isTrinket = nil
    if type(explicitType) == "string" then
        local t = string.lower(explicitType)
        if t == "trinket" then isTrinket = true end
        if t == "collectible" then isTrinket = false end
    end
    if isTrinket == nil and type(fallbackItemType) == "string" then
        local t = string.lower(fallbackItemType)
        if t == "trinket" then isTrinket = true end
        if t == "collectible" then isTrinket = false end
    end
    if isTrinket == nil and resolvedId then
        local cfg = Isaac and Isaac.GetItemConfig and Isaac.GetItemConfig()
        if cfg then
            if cfg:GetTrinket(resolvedId) then
                isTrinket = true
            elseif cfg:GetCollectible(resolvedId) then
                isTrinket = false
            end
        end
    end

    ConchBlessing.printDebug("_resolveOriginAny: origin=" .. tostring(originDecl) .. ", id=" .. tostring(resolvedId) .. ", isTrinket=" .. tostring(isTrinket))
    return resolvedId, isTrinket
end

local function _spawnEffects(list, pos)
    if not list then return end
    for _, eff in ipairs(list) do
        local count = eff.count or 1
        local spread = eff.spread or 0
        local etype = eff.entityType or EntityType.ENTITY_EFFECT
        local evar = eff.variant or EffectVariant.POOF01
        local esub = eff.subType or 0
        for i = 1, count do
            local offset = spread > 0 and Vector(math.random(-spread, spread), math.random(-spread, spread)) or Vector.Zero
            local ent = Isaac.Spawn(etype, evar, esub, pos + offset, Vector.Zero, nil)
            local effObj = ent:ToEffect()
            if effObj then
                if eff.timeout and eff.timeout > 0 then effObj.Timeout = eff.timeout end
                if eff.depthOffset then effObj.DepthOffset = eff.depthOffset end
                if eff.scale then effObj.SpriteScale = Vector(eff.scale, eff.scale) end
                if eff.color then
                    local c = eff.color
                    effObj:SetColor(Color(c.r or 1, c.g or 1, c.b or 1, c.a or 1, c.ro or 0, c.go or 0, c.bo or 0), -1, 1, false, false)
                end
            end
        end
    end
end

local function _isPickupPending(pickup)
    if not pickup then
        return false
    end

    local data = pickup:GetData()
    if data and data[PENDING_UPGRADE_DATA_KEY] ~= nil then
        return true
    end

    for _, job in ipairs(ConchBlessing._upgradeJobs) do
        if job.pickup == pickup and (job.phase == 0 or job.phase == 1) then
            return true
        end
    end

    return false
end

local function _clearPendingMarker(job)
    local pickup = job and job.pickup and job.pickup:ToPickup() or nil
    if not pickup then
        return
    end

    local data = pickup:GetData()
    if data and data[PENDING_UPGRADE_DATA_KEY] == job.token then
        data[PENDING_UPGRADE_DATA_KEY] = nil
    end
    if data and data[PICKUP_LOCK_DATA_KEY] == job.token then
        data[PICKUP_LOCK_DATA_KEY] = nil
    end
end

local function _removeUpgradeJob(index, job, cancelAnimation)
    if cancelAnimation
        and ConchBlessing.template
        and type(ConchBlessing.template.cancelForPickup) == "function" then
        ConchBlessing.template.cancelForPickup(job and job.pickup or nil)
    end
    _clearPendingMarker(job)
    table.remove(ConchBlessing._upgradeJobs, index)
end

local function _enqueueUpgradeJob(entityPickup, upgradeData, savedFields)
    if not entityPickup or _isPickupPending(entityPickup) then
        return false
    end

    local itemData = upgradeData.itemData or {}
    local targetVariant = PickupVariant.PICKUP_COLLECTIBLE
    if itemData.type == "trinket" then
        targetVariant = PickupVariant.PICKUP_TRINKET
    end

    local job = {
        pickup = entityPickup,
        pos = Vector(entityPickup.Position.X, entityPickup.Position.Y),
        sourceVariant = entityPickup.Variant,
        sourceSubType = entityPickup.SubType,
        sourceInitSeed = entityPickup.InitSeed,
        upgradeId = upgradeData.upgradeId,
        itemKey = upgradeData.itemKey,
        itemData = itemData,
        saved = savedFields or {},
        phase = 0,
        counter = 0,
        beforeFrames = math.max(0, tonumber(itemData.beforeFrames) or 0),
        afterFrames = math.max(0, tonumber(itemData.afterFrames) or 0),
        targetVariant = targetVariant,
        templateState = {},
        token = {},
    }

    local data = entityPickup:GetData()
    data[PENDING_UPGRADE_DATA_KEY] = job.token
    data[PICKUP_LOCK_DATA_KEY] = job.token
    table.insert(ConchBlessing._upgradeJobs, job)
    return true
end

local function _sourceStillMatches(job, pickup)
    return pickup
        and pickup:Exists()
        and pickup.Variant == job.sourceVariant
        and pickup.SubType == job.sourceSubType
        and pickup.InitSeed == job.sourceInitSeed
end

local function _preventPendingUpgradePickup(_, pickup, collider)
    if not pickup or not collider or not collider:ToPlayer() then
        return
    end

    local data = pickup:GetData()
    if data and data[PICKUP_LOCK_DATA_KEY] ~= nil then
        return true
    end
end

local function _restorePickupFields(pickup, saved)
    local fields = {
        { "Price", "price" },
        { "OptionsPickupIndex", "options" },
        { "Wait", "wait" },
        { "Timeout", "timeout" },
        { "Touched", "touched" },
        { "ShopItemId", "shopId" },
        { "State", "state" },
    }

    for _, field in ipairs(fields) do
        local savedValue = saved[field[2]]
        if savedValue ~= nil then
            pickup[field[1]] = savedValue
        end
    end
end

local function _processUpgradeJobs()
    if #ConchBlessing._upgradeJobs == 0 then
        return
    end

    for i = #ConchBlessing._upgradeJobs, 1, -1 do
        local job = ConchBlessing._upgradeJobs[i]
        local pickup = job.pickup and job.pickup:ToPickup() or nil
        if not pickup or not pickup:Exists() then
            _removeUpgradeJob(i, job, true)
            goto continue
        end
        if (job.phase == 0 or job.phase == 1) and not _sourceStillMatches(job, pickup) then
            ConchBlessing.printDebug("[Upgrade] Source pickup changed; cancelling " .. tostring(job.itemKey or job.upgradeId))
            _removeUpgradeJob(i, job, true)
            goto continue
        end

        local advanced = true
        while advanced do
            advanced = false

            if job.phase == 0 then
                _spawnEffects(job.itemData.upgradeEffectsBefore, job.pos)

                job.template = _getUpgradeTemplate(job.itemData.flag)
                local templateDelay = 0
                if job.template then
                    templateDelay = _callUpgradeFunction(
                        "template." .. job.itemData.flag .. ".onBeforeChange",
                        job.template.onBeforeChange,
                        job.pos,
                        pickup,
                        job.templateState
                    )
                end

                local hookDelay = _callConfiguredHook(
                    job.itemData.onBeforeChange,
                    tostring(job.itemKey or job.upgradeId) .. ".onBeforeChange",
                    job.pos,
                    pickup,
                    job.itemData
                )

                job.counter = math.max(job.beforeFrames, templateDelay, hookDelay)
                job.phase = 1
                advanced = (job.counter <= 0)

            elseif job.phase == 1 then
                job.counter = job.counter - 1
                if job.counter <= 0 then
                    if not _sourceStillMatches(job, pickup) then
                        ConchBlessing.printDebug("[Upgrade] Source pickup changed before morph; cancelling " .. tostring(job.itemKey or job.upgradeId))
                        _removeUpgradeJob(i, job, true)
                        goto continue
                    end

                    if ConchBlessing.template and type(ConchBlessing.template.cancelForPickup) == "function" then
                        ConchBlessing.template.cancelForPickup(pickup)
                    end

                    local variantToUse = job.targetVariant
                    local morphId = job.upgradeId
                    if variantToUse == PickupVariant.PICKUP_TRINKET and job.saved.wasGoldenTrinket then
                        morphId = morphId + 32768
                    end

                    ConchBlessing.printDebug("[Upgrade] Morphing pickup to variant=" .. tostring(variantToUse) .. ", id=" .. tostring(morphId))
                    local morphOk, morphError = pcall(function()
                        pickup:Morph(EntityType.ENTITY_PICKUP, variantToUse, morphId, true, true, true)
                    end)
                    if not morphOk then
                        ConchBlessing.printError("[Upgrade] Morph failed for " .. tostring(job.itemKey or job.upgradeId) .. ": " .. tostring(morphError))
                        _removeUpgradeJob(i, job, true)
                        goto continue
                    end
                    if pickup.Variant ~= variantToUse or pickup.SubType ~= morphId then
                        ConchBlessing.printError("[Upgrade] Morph result mismatch for " .. tostring(job.itemKey or job.upgradeId))
                        _removeUpgradeJob(i, job, true)
                        goto continue
                    end

                    _restorePickupFields(pickup, job.saved)
                    _clearPendingMarker(job)
                    _spawnEffects(job.itemData.upgradeEffectsAfter or job.itemData.upgradeEffects, job.pos)

                    local templateDelay = 0
                    if job.template then
                        templateDelay = _callUpgradeFunction(
                            "template." .. job.itemData.flag .. ".onAfterChange",
                            job.template.onAfterChange,
                            job.pos,
                            pickup,
                            job.templateState
                        )
                    end

                    local hookDelay = _callConfiguredHook(
                        job.itemData.onAfterChange or job.itemData.onUpgrade,
                        tostring(job.itemKey or job.upgradeId) .. ".onAfterChange",
                        job.pos,
                        pickup,
                        job.itemData
                    )

                    job.counter = math.max(job.afterFrames, templateDelay, hookDelay)
                    job.phase = 3
                    advanced = (job.counter <= 0)
                end

            elseif job.phase == 3 then
                job.counter = job.counter - 1
                if job.counter <= 0 then
                    _removeUpgradeJob(i, job, false)
                end
            end
        end

        ::continue::
    end
end

-- Check if ModCallbacks is defined
if not ModCallbacks then
    ConchBlessing.printError("ModCallbacks is not defined!")
    return
end

-- Define item conversion map (generated from ItemData)
ConchBlessing.ItemMaps = {}
ConchBlessing._itemMapsReady = false

local function _getConfiguredItem(itemConfig, itemId, isTrinket)
    if isTrinket then
        return itemConfig:GetTrinket(itemId)
    end
    return itemConfig:GetCollectible(itemId)
end

-- Automatically generate conversion map based on ItemData
local function generateItemMaps()
    ConchBlessing.printDebug("Generating conversion map based on ItemData...")
    
    if not ConchBlessing.ItemData or not ConchBlessing.ItemDataReady then
        ConchBlessing.printDebug("ConchBlessing.ItemData not ready yet (ItemData: " .. tostring(ConchBlessing.ItemData ~= nil) .. ", ItemDataReady: " .. tostring(ConchBlessing.ItemDataReady) .. "), skipping conversion map generation")
        return false
    end

    local itemConfig = Isaac.GetItemConfig()
    if not itemConfig then
        ConchBlessing.printError("[Upgrade] ItemConfig is unavailable; conversion map was not built")
        ConchBlessing.ItemMaps = {}
        ConchBlessing._itemMapsReady = false
        return false
    end

    local newMaps = {}
    local invalidSlots = {}
    local hasErrors = false

    local function addMapping(itemKey, itemData)
        if itemData.origin ~= nil or itemData.flag ~= nil then
            if itemData.origin == nil or not VALID_UPGRADE_FLAGS[itemData.flag] then
                ConchBlessing.printError("[Upgrade] Invalid origin/flag declaration for " .. tostring(itemKey))
                return false
            end

            local originId, originIsTrinket = _resolveOriginAny(itemData.origin, itemData.type)
            if type(originId) ~= "number" or originId <= 0 or originIsTrinket == nil then
                ConchBlessing.printError("[Upgrade] Unresolved origin for " .. tostring(itemKey) .. ": " .. tostring(itemData.origin))
                return false
            end

            if not _getConfiguredItem(itemConfig, originId, originIsTrinket) then
                ConchBlessing.printError("[Upgrade] Origin ItemConfig entry is missing for " .. tostring(itemKey) .. ": " .. tostring(originId))
                return false
            end

            local targetIsTrinket = itemData.type == "trinket"
            if itemData.type ~= "active"
                and itemData.type ~= "passive"
                and itemData.type ~= "familiar"
                and not targetIsTrinket then
                ConchBlessing.printError("[Upgrade] Unsupported target item type for " .. tostring(itemKey) .. ": " .. tostring(itemData.type))
                return false
            end

            if type(itemData.id) ~= "number" or itemData.id <= 0
                or not _getConfiguredItem(itemConfig, itemData.id, targetIsTrinket) then
                ConchBlessing.printError("[Upgrade] Target ItemConfig entry is missing for " .. tostring(itemKey) .. ": " .. tostring(itemData.id))
                return false
            end

            if not _getUpgradeTemplate(itemData.flag) then
                return false
            end

            local originKeyPrefix = (originIsTrinket == true) and "T:" or "C:"
            local originKey = originKeyPrefix .. tostring(originId)
            local slotKey = originKey .. ":" .. itemData.flag
            if not newMaps[originKey] then
                newMaps[originKey] = {}
            end

            if invalidSlots[slotKey] or newMaps[originKey][itemData.flag] then
                local previous = newMaps[originKey][itemData.flag]
                ConchBlessing.printError(
                    "[Upgrade] Duplicate origin/flag mapping: "
                        .. slotKey
                        .. " ("
                        .. tostring(previous and previous.itemKey or "duplicate")
                        .. ", "
                        .. tostring(itemKey)
                        .. ")"
                )
                newMaps[originKey][itemData.flag] = nil
                invalidSlots[slotKey] = true
                return false
            end

            newMaps[originKey][itemData.flag] = {
                upgradeId = itemData.id,
                flag = itemData.flag,
                itemKey = itemKey,
                itemData = itemData,
            }

            ConchBlessing.printDebug("  Added to conversion map: " .. originKey .. "[" .. itemData.flag .. "] -> " .. tostring(itemData.id))
        end

        return true
    end

    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        if not addMapping(itemKey, itemData) then
            hasErrors = true
        end
    end

    if hasErrors then
        ConchBlessing.ItemMaps = {}
        ConchBlessing._itemMapsReady = false
        ConchBlessing.printError("[Upgrade] Conversion map validation failed; transformations remain disabled")
        return false
    end

    ConchBlessing.ItemMaps = newMaps
    ConchBlessing._itemMapsReady = true
    ConchBlessing.printDebug("Conversion map created! Total " .. ConchBlessing.tableLength(newMaps) .. " origin mappings created.")
    return true
end

-- Table length helper function
ConchBlessing.tableLength = function(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Check if Delete Mode is enabled in Magic Conch
local function isDeleteModeEnabled()
    -- Check via API Config
    if MagicConch and MagicConch.API and MagicConch.API.Config then
        return MagicConch.API.Config.deleteMode == true
    end
    -- Check via direct Config
    if MagicConch and MagicConch.Config then
        return MagicConch.Config.deleteMode == true
    end
    return false
end

-- Delete a pickup item with effect
local function deletePickupWithEffect(entity)
    local sfxManager = SFXManager()
    sfxManager:Play(SoundEffect.SOUND_THUMBS_DOWN, 0.7)
    
    -- Spawn poof effect at item position
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, entity.Position, Vector.Zero, nil)
    
    -- Remove the entity
    entity:Remove()
    ConchBlessing.printDebug("Delete Mode: Item removed at position " .. tostring(entity.Position.X) .. ", " .. tostring(entity.Position.Y))
end

-- Magic Conch result handling function
local function handleMagicConchResult(result)
    if type(result) ~= "table" or not VALID_UPGRADE_FLAGS[result.type] then
        ConchBlessing.printError("[Upgrade] Ignoring invalid Magic Conch result")
        return
    end

    if not ConchBlessing._itemMapsReady and not generateItemMaps() then
        ConchBlessing.printError("[Upgrade] Ignoring Magic Conch result because the conversion map is unavailable")
        return
    end

    local resultType = result.type
    ConchBlessing.printDebug("Magic Conch result received: " .. tostring(result.text) .. " (type: " .. resultType .. ")")

    -- Check all entities in the current room (field items)
    local entities = Isaac.GetRoomEntities()
    local transformed = false
    local upgradeCount = 0
    local deleteCount = 0
    
    -- Check if Delete Mode is enabled
    local deleteModeActive = isDeleteModeEnabled()
    ConchBlessing.printDebug("Delete Mode active: " .. tostring(deleteModeActive))
    
    ConchBlessing.printDebug("Number of entities in room: " .. tostring(#entities))
    
    -- Collect items for upgrade and delete
    local upgradeableItems = {}
    local deleteableItems = {}
    
    for _, entity in ipairs(entities) do
        -- check if it's a pickup (collectible or trinket)
        if entity.Type == EntityType.ENTITY_PICKUP
            and (entity.Variant == PickupVariant.PICKUP_COLLECTIBLE or entity.Variant == PickupVariant.PICKUP_TRINKET)
            and not _isPickupPending(entity:ToPickup()) then
            local rawId = entity.SubType
            local isTrinketPickup = (entity.Variant == PickupVariant.PICKUP_TRINKET)
            local baseId = rawId
            local wasGoldenTrinket = false
            if isTrinketPickup and rawId >= 32768 then
                baseId = rawId - 32768
                wasGoldenTrinket = true
            end
            local variantName = isTrinketPickup and "TRINKET" or "COLLECTIBLE"
            ConchBlessing.printDebug("Field item found: variant=" .. variantName .. ", id=" .. tostring(rawId) .. ", baseId=" .. tostring(baseId))

            -- find item in conversion map by type + id (trinket/collectible 구분)
            local originKey = (isTrinketPickup and "T:" or "C:") .. tostring(baseId)
            local originMappings = ConchBlessing.ItemMaps[originKey]
            
            if originMappings then
                -- This item HAS evolution possibilities
                ConchBlessing.printDebug("Convertible item found: originKey=" .. originKey)

                local availableFlags = {}
                for flag, _ in pairs(originMappings) do
                    table.insert(availableFlags, flag)
                end
                ConchBlessing.printDebug("  Available flags: " .. table.concat(availableFlags, ", "))
                ConchBlessing.printDebug("  Current result type: " .. resultType)

                local upgradeData = originMappings[resultType]
                if upgradeData then
                    -- Flag matches - perform upgrade
                    ConchBlessing.printDebug("Flag matches! Item conversion: id=" .. tostring(baseId) .. " -> " .. tostring(upgradeData.upgradeId))
                    ConchBlessing.printDebug("  Flag type: " .. upgradeData.flag .. ", Result type: " .. resultType)

                    -- Queue upgrade info
                    table.insert(upgradeableItems, {
                        entity = entity,
                        upgradeData = upgradeData,
                        wasGoldenTrinket = wasGoldenTrinket,
                        isTrinketPickup = isTrinketPickup,
                    })
                else
                    -- Flag does NOT match - if Delete Mode is on, delete the item
                    ConchBlessing.printDebug("Flag does not match. No conversion.")
                    if deleteModeActive then
                        ConchBlessing.printDebug("Delete Mode: Item has evolution but result type doesn't match any flag. Marking for deletion.")
                        table.insert(deleteableItems, entity)
                    end
                end
            else
                -- This item has NO evolution possibilities in ConchBlessing
                -- If Delete Mode is on and result is "negative", delete the item
                if deleteModeActive and resultType == "negative" then
                    ConchBlessing.printDebug("Delete Mode: Item has no evolution and result is negative. Marking for deletion.")
                    table.insert(deleteableItems, entity)
                end
            end
        end
    end
    
    -- 수집된 모든 아이템을 한꺼번에 업그레이드
    if #upgradeableItems > 0 then
        ConchBlessing.printDebug("Found " .. #upgradeableItems .. " upgradeable items. Processing all upgrades...")
        
        for _, itemInfo in ipairs(upgradeableItems) do
            local entity = itemInfo.entity
            local upgradeData = itemInfo.upgradeData

            -- Save original item properties (including pedestal)
            local pickup = entity:ToPickup()

            if pickup then
                local queued = _enqueueUpgradeJob(pickup, upgradeData, {
                    price = pickup.Price,
                    options = pickup.OptionsPickupIndex,
                    wait = pickup.Wait,
                    timeout = pickup.Timeout,
                    touched = pickup.Touched,
                    shopId = pickup.ShopItemId,
                    state = pickup.State,
                    wasGoldenTrinket = itemInfo.wasGoldenTrinket,
                })

                if queued then
                    SFXManager():Play(SoundEffect.SOUND_POWERUP_SPEWER, 0.5)
                    ConchBlessing.printDebug("Item conversion in progress for item " .. tostring(entity.SubType))

                    if ConchBlessing.UpgradeHighlight and ConchBlessing.UpgradeHighlight.StopForPickup then
                        ConchBlessing.UpgradeHighlight.StopForPickup(pickup)
                    end

                    upgradeCount = upgradeCount + 1
                    transformed = true

                    ConchBlessing.printDebug("Item conversion queued for item " .. tostring(entity.SubType))
                end
            else
                ConchBlessing.printError("[Upgrade] Queued entity is no longer a pickup")
            end
        end
        
        ConchBlessing.printDebug("Total " .. upgradeCount .. " items queued for upgrade!")
    end
    
    -- Process deleteable items (Delete Mode)
    if #deleteableItems > 0 then
        ConchBlessing.printDebug("Delete Mode: Processing " .. #deleteableItems .. " items for deletion...")
        for _, entity in ipairs(deleteableItems) do
            deletePickupWithEffect(entity)
            deleteCount = deleteCount + 1
        end
        ConchBlessing.printDebug("Delete Mode: Total " .. deleteCount .. " items deleted!")
    end
    
    if not transformed and deleteCount == 0 then
        ConchBlessing.printDebug("No convertible field item found or conditions not met.")
    end
end

-- Register Magic Conch API
local MAGIC_CONCH_CALLBACK_NAME = "Conch's Blessing"
local apiCheckTimer = 0
local maxRetries = 60
local retryCount = 0
local retryExhausted = false

ConchBlessing.magicConchApiRegistered = false

-- Check if Magic Conch API is ready
local function isMagicConchAPIReady()
    if not MagicConch
        or type(MagicConch.API) ~= "table"
        or type(MagicConch.API.RegisterCallback) ~= "function"
        or type(MagicConch.API.IsReady) ~= "function" then
        return false
    end

    local ok, ready = pcall(MagicConch.API.IsReady)
    return ok and ready == true
end

local function registerMagicConchAPI()
    if not ConchBlessing._itemMapsReady or not isMagicConchAPIReady() then
        return false
    end

    ConchBlessing.printDebug("Registering Magic Conch API callbacks...")
    local callOk, registered = pcall(
        MagicConch.API.RegisterCallback,
        handleMagicConchResult,
        MAGIC_CONCH_CALLBACK_NAME
    )
    local success = callOk and registered == true

    if success then
        ConchBlessing.magicConchApiRegistered = true
        retryExhausted = false
        ConchBlessing.printDebug("Magic Conch API callback registration successful!")
    else
        ConchBlessing.magicConchApiRegistered = false
        ConchBlessing.printError("Magic Conch API callback registration failed: " .. tostring(registered))
    end

    return success
end

local function unregisterMagicConchAPI()
    local api = MagicConch and MagicConch.API or nil
    if type(api) ~= "table" or type(api.UnregisterCallback) ~= "function" then
        ConchBlessing.magicConchApiRegistered = false
        return false
    end

    local callOk, unregistered = pcall(api.UnregisterCallback, MAGIC_CONCH_CALLBACK_NAME)
    ConchBlessing.magicConchApiRegistered = false
    if not callOk then
        ConchBlessing.printError("[Upgrade] Magic Conch callback cleanup failed: " .. tostring(unregistered))
        return false
    end

    return unregistered == true
end

local function resetRegistrationAttempts()
    apiCheckTimer = 0
    retryCount = 0
    retryExhausted = false
end

local function clearUpgradeJobs()
    for i = #ConchBlessing._upgradeJobs, 1, -1 do
        _removeUpgradeJob(i, ConchBlessing._upgradeJobs[i], true)
    end
end

-- API Registration Callback
local function apiRegistrationCallback()
    if ConchBlessing.magicConchApiRegistered or retryExhausted then
        return
    end

    apiCheckTimer = apiCheckTimer + 1
    if apiCheckTimer < 10 then
        return
    end

    apiCheckTimer = 0
    retryCount = retryCount + 1
    ConchBlessing.printDebug("Checking Magic Conch API readiness (attempt " .. retryCount .. "/" .. maxRetries .. ")")

    if not ConchBlessing._itemMapsReady and not generateItemMaps() then
        unregisterMagicConchAPI()
    end
    if ConchBlessing._itemMapsReady and isMagicConchAPIReady() then
        registerMagicConchAPI()
    end

    if not ConchBlessing.magicConchApiRegistered and retryCount >= maxRetries then
        retryExhausted = true
        ConchBlessing.printError("[Upgrade] Magic Conch API registration retries exhausted; will retry on the next game or floor")
    end
end

local function onGameStarted()
    clearUpgradeJobs()
    ConchBlessing.magicConchApiRegistered = false
    resetRegistrationAttempts()

    if not generateItemMaps() then
        unregisterMagicConchAPI()
        return
    end

    if isMagicConchAPIReady() then
        registerMagicConchAPI()
    end
end

local function onNewLevel()
    if ConchBlessing.magicConchApiRegistered then
        return
    end

    resetRegistrationAttempts()
    if not ConchBlessing._itemMapsReady and not generateItemMaps() then
        unregisterMagicConchAPI()
        return
    end
    if ConchBlessing._itemMapsReady and isMagicConchAPIReady() then
        registerMagicConchAPI()
    end
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, onGameStarted)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    apiRegistrationCallback()
    _processUpgradeJobs()
end)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, onNewLevel)
ConchBlessing:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    _preventPendingUpgradePickup,
    PickupVariant.PICKUP_COLLECTIBLE
)
ConchBlessing:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    _preventPendingUpgradePickup,
    PickupVariant.PICKUP_TRINKET
)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clearUpgradeJobs)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, clearUpgradeJobs)
