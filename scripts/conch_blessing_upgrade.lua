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

local function _enqueueUpgradeJob(entityPickup, upgradeData, savedFields)
    local itemData = upgradeData.itemData or {}
    -- Frames to wait; will be set dynamically from callbacks or itemData
    local beforeFrames = 0
    local afterFrames = 0
    table.insert(ConchBlessing._upgradeJobs, {
        pickup = entityPickup,
        pos = Vector(entityPickup.Position.X, entityPickup.Position.Y),
        upgradeId = upgradeData.upgradeId,
        itemData = itemData,
        saved = savedFields or {},
        phase = 0,           -- 0: run BEFORE, 1: wait BEFORE frames, 2: morph+run AFTER, 3: wait AFTER frames
        counter = 0,
        beforeFrames = beforeFrames,
        afterFrames = afterFrames,
    })
end

local function _processUpgradeJobs()
    if #ConchBlessing._upgradeJobs == 0 then return end
    for i = #ConchBlessing._upgradeJobs, 1, -1 do
        local job = ConchBlessing._upgradeJobs[i]
        local pickup = job.pickup and job.pickup:ToPickup() or nil
        if not pickup or not pickup:Exists() then
            table.remove(ConchBlessing._upgradeJobs, i)
            goto continue
        end
        local advanced = true
        while advanced do
            advanced = false
            if job.phase == 0 then
            -- BEFORE hooks/effects
                _spawnEffects(job.itemData.upgradeEffectsBefore, job.pos)
                local fnBefore = _resolveFunction(job.itemData.onBeforeChange)
            local beforeRet = nil
            if type(fnBefore) == "function" then
                local ok, ret = pcall(fnBefore, job.pos, pickup, job.itemData)
                if ok then beforeRet = ret end
            end
            -- derive delay solely from callback return (frames)
            local derivedBefore = tonumber(beforeRet) or 0
            job.counter = (job.beforeFrames and job.beforeFrames > 0) and job.beforeFrames or derivedBefore
                job.phase = 1
                advanced = (job.counter <= 0)
            elseif job.phase == 1 then
                job.counter = job.counter - 1
                if job.counter <= 0 then
                    -- Morph while preserving pedestal/shop fields
                    pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, job.upgradeId, true, true, true)
                    local s = job.saved or {}
                    pickup.Price = s.price or pickup.Price
                    pickup.OptionsPickupIndex = s.options or pickup.OptionsPickupIndex
                    pickup.Wait = s.wait or pickup.Wait
                    pickup.Timeout = s.timeout or pickup.Timeout
                    pickup.Touched = s.touched or pickup.Touched
                    pickup.ShopItemId = s.shopId or pickup.ShopItemId
                    pickup.State = s.state or pickup.State
                                -- AFTER hooks/effects
            _spawnEffects(job.itemData.upgradeEffectsAfter or job.itemData.upgradeEffects, job.pos)
            local fnAfter = _resolveFunction(job.itemData.onAfterChange or job.itemData.onUpgrade)
            ConchBlessing.printDebug("  onAfterChange function resolved: " .. tostring(fnAfter))
            local afterRet = nil
            if type(fnAfter) == "function" then
                ConchBlessing.printDebug("  Calling onAfterChange function...")
                local ok, ret = pcall(fnAfter, job.pos, pickup, job.itemData)
                if ok then 
                    afterRet = ret 
                    ConchBlessing.printDebug("  onAfterChange returned: " .. tostring(ret))
                else
                    ConchBlessing.printError("  onAfterChange error: " .. tostring(ret))
                end
            else
                ConchBlessing.printError("  onAfterChange is not a function! Type: " .. type(fnAfter))
            end
                    local derivedAfter = tonumber(afterRet) or 0
                    job.counter = (job.afterFrames and job.afterFrames > 0) and job.afterFrames or derivedAfter
                    job.phase = 3
                    advanced = (job.counter <= 0)
                end
            elseif job.phase == 3 then
                job.counter = job.counter - 1
                if job.counter <= 0 then
                    table.remove(ConchBlessing._upgradeJobs, i)
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

-- Automatically generate conversion map based on ItemData
local function generateItemMaps()
    ConchBlessing.printDebug("Generating conversion map based on ItemData...")
    
    if not ConchBlessing.ItemData or not ConchBlessing.ItemDataReady then
        ConchBlessing.printDebug("ConchBlessing.ItemData not ready yet (ItemData: " .. tostring(ConchBlessing.ItemData ~= nil) .. ", ItemDataReady: " .. tostring(ConchBlessing.ItemDataReady) .. "), skipping conversion map generation")
        return false
    end
    
    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        if itemData.origin and itemData.flag then
            ConchBlessing.printDebug("Upgrade item found: " .. itemKey .. " (origin: " .. tostring(itemData.origin) .. ", flag: " .. itemData.flag .. ")")
            
            -- 같은 origin에 대해 flag별로 다른 아이템을 매핑
            if not ConchBlessing.ItemMaps[itemData.origin] then
                ConchBlessing.ItemMaps[itemData.origin] = {}
            end
            
            ConchBlessing.ItemMaps[itemData.origin][itemData.flag] = {
                upgradeId = itemData.id,
                flag = itemData.flag,
                itemData = itemData -- reference to full item data
            }
            
            ConchBlessing.printDebug("  Added to conversion map: " .. tostring(itemData.origin) .. "[" .. itemData.flag .. "] -> " .. tostring(itemData.id))
        end
    end
    
    ConchBlessing.printDebug("Conversion map created! Total " .. ConchBlessing.tableLength(ConchBlessing.ItemMaps) .. " origin mappings created.")
    return true
end

-- Table length helper function
ConchBlessing.tableLength = function(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Magic Conch result handling function
local function handleMagicConchResult(result)
    ConchBlessing.printDebug("Magic Conch result received: " .. result.text .. " (type: " .. result.type .. ")")
    
    local player = Isaac.GetPlayer(0)
    if not player then
        ConchBlessing.printError("Player not found!")
        return
    end
    
    -- Check all entities in the current room (field items)
    local room = Game():GetRoom()
    local entities = Isaac.GetRoomEntities()
    local transformed = false
    local upgradeCount = 0
    
    ConchBlessing.printDebug("Number of entities in room: " .. tostring(#entities))
    
    -- 먼저 모든 변환 가능한 아이템을 찾아서 수집
    local upgradeableItems = {}
    
    for _, entity in ipairs(entities) do
        -- check if it's an item pickup
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local collectibleId = entity.SubType
            ConchBlessing.printDebug("Field item found: " .. tostring(collectibleId))
            
            -- find item in conversion map
            local originMappings = ConchBlessing.ItemMaps[collectibleId]
            if originMappings then
                ConchBlessing.printDebug("Convertible item found: " .. tostring(collectibleId))
                
                local availableFlags = {}
                for flag, _ in pairs(originMappings) do
                    table.insert(availableFlags, flag)
                end
                ConchBlessing.printDebug("  Available flags: " .. table.concat(availableFlags, ", "))
                ConchBlessing.printDebug("  Current result type: " .. result.type)
                
                local upgradeData = originMappings[result.type]
                if upgradeData then
                    ConchBlessing.printDebug("Flag matches! Item conversion: " .. tostring(collectibleId) .. " -> " .. tostring(upgradeData.upgradeId))
                    ConchBlessing.printDebug("  Flag type: " .. upgradeData.flag .. ", Result type: " .. result.type)
                    
                    -- 변환 가능한 아이템 정보를 수집
                    table.insert(upgradeableItems, {
                        entity = entity,
                        upgradeData = upgradeData
                    })
                else
                    ConchBlessing.printDebug("Flag does not match. No conversion.")
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

            if pickup == nil then
                ConchBlessing.printError("Pickup is nil!")
                goto continue
            end
            
            -- Only perform conversion (no purchase handling)
            ConchBlessing.printDebug("Item conversion in progress for item " .. tostring(entity.SubType))
            
            local originalPrice = pickup.Price
            local originalOptions = pickup.OptionsPickupIndex
            local originalWait = pickup.Wait
            local originalTimeout = pickup.Timeout
            local originalTouched = pickup.Touched
            local originalShopItemId = pickup.ShopItemId
            local originalState = pickup.State
            
            -- add conversion effect immediately (sound)
            local sfxManager = SFXManager()
            sfxManager:Play(SoundEffect.SOUND_POWERUP_SPEWER, 0.5)
            
            -- Enqueue staged job to ensure BEFORE completes before AFTER
            if pickup then
                _enqueueUpgradeJob(pickup, upgradeData, {
                    price = originalPrice,
                    options = originalOptions,
                    wait = originalWait,
                    timeout = originalTimeout,
                    touched = originalTouched,
                    shopId = originalShopItemId,
                    state = originalState,
                })
            end
            
            upgradeCount = upgradeCount + 1
            transformed = true
            ConchBlessing.printDebug("Item conversion queued for item " .. tostring(entity.SubType))
            
            ::continue::
        end
        
        ConchBlessing.printDebug("Total " .. upgradeCount .. " items queued for upgrade!")
    end
    
    if not transformed then
        ConchBlessing.printDebug("No convertible field item found or conditions not met.")
    end
end

-- Register Magic Conch API
local function registerMagicConchAPI()
    ConchBlessing.printDebug("Registering Magic Conch API callbacks...")
    ConchBlessing.printDebug("handleMagicConchResult function exists: " .. tostring(handleMagicConchResult ~= nil))
    
    local success = MagicConch.API.RegisterCallback(handleMagicConchResult, "Conch's Blessing")
    ConchBlessing.printDebug("RegisterCallback return value: " .. tostring(success))
    
    if success then
        ConchBlessing.printDebug("Magic Conch API callback registration successful!")
    else
        ConchBlessing.printError("Magic Conch API callback registration failed!")
    end
end

-- Check if Magic Conch API is ready
local function isMagicConchAPIReady()
    return MagicConch and 
           MagicConch.API and 
           type(MagicConch.API) == "table" and
           MagicConch.API.RegisterCallback and 
           type(MagicConch.API.RegisterCallback) == "function" and
           MagicConch.API.IsReady and 
           type(MagicConch.API.IsReady) == "function" and
           MagicConch.API.IsReady()
end

-- Generate conversion map on game start
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    generateItemMaps()
end)

-- Initialize Magic Conch on new floor start
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    -- Initialize Magic Conch API when ready
    if isMagicConchAPIReady() and MagicConch.API.ResetAllAttempts then
        MagicConch.API.ResetAllAttempts()
        ConchBlessing.printDebug("New floor start: Magic Conch reset all attempts")
    elseif MagicConch and MagicConch.ResetAllAttempts then
        -- Alternative method: direct function call
        MagicConch.ResetAllAttempts()
        ConchBlessing.printDebug("New floor start: Magic Conch reset all attempts (direct call)")
    else
        ConchBlessing.printDebug("New floor start: Magic Conch initialization function not found")
    end
end)

-- Safe API Registration System
local apiCheckTimer = 0
local maxRetries = 60 -- 10 seconds (60 * 1/6 seconds)
local retryCount = 0

-- API Registration Callback
local function apiRegistrationCallback()
    -- Use flag to ensure only one execution
    if not ConchBlessing.apiRegistered then
        apiCheckTimer = apiCheckTimer + 1
        
        -- Check API readiness every 1/6 second
        if apiCheckTimer >= 10 then -- 10 frames = approximately 1/6 second
            apiCheckTimer = 0
            retryCount = retryCount + 1
            
            ConchBlessing.printDebug("Checking API readiness... (attempt " .. retryCount .. "/" .. maxRetries .. ")")
            
            if isMagicConchAPIReady() then
                ConchBlessing.printDebug("=== Magic Conch API ready! ===")
                ConchBlessing.printDebug("MagicConch exists: " .. tostring(MagicConch ~= nil))
                ConchBlessing.printDebug("MagicConch.API exists: " .. tostring(MagicConch.API ~= nil))
                ConchBlessing.printDebug("RegisterCallback function exists: " .. tostring(MagicConch.API.RegisterCallback ~= nil))
                
                ConchBlessing.printDebug("Attempting API registration...")
                registerMagicConchAPI()
                ConchBlessing.apiRegistered = true
                ConchBlessing.printDebug("API registration complete!")
                ConchBlessing.printDebug("=== Initialization complete ===")
            elseif retryCount >= maxRetries then
                ConchBlessing.printError("=== Warning: Magic Conch API initialization failed ===")
                ConchBlessing.printError("Maximum retry count reached.")
                ConchBlessing.printError("MagicConch exists: " .. tostring(MagicConch ~= nil))
                if MagicConch then
                    ConchBlessing.printDebug("MagicConch.API exists: " .. tostring(MagicConch.API ~= nil))
                    if MagicConch.API then
                        ConchBlessing.printDebug("RegisterCallback function exists: " .. tostring(MagicConch.API.RegisterCallback ~= nil))
                    end
                end
                ConchBlessing.printDebug("Upgrade system disabled.")
                ConchBlessing.apiRegistered = true -- don't try again
            end
        end
    end
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    apiRegistrationCallback()
    _processUpgradeJobs()
end)

-- New Level Callback
local function newLevelCallback()
    if isMagicConchAPIReady() and not ConchBlessing.apiRegistered then
        ConchBlessing.printDebug("Attempting API registration on new level...")
        registerMagicConchAPI()
        ConchBlessing.apiRegistered = true
    end
end

-- Register API on new level (just in case)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, newLevelCallback)