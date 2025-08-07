-- Conch's Blessing - Upgrade System
-- Item conversion system using Magic Conch API

ConchBlessing.printDebug("Upgrade system loaded!")

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
    
    if not ConchBlessing.ItemData then
        ConchBlessing.printError("ConchBlessing.ItemData is not defined!")
        return
    end
    
    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        if itemData.origin and itemData.flag then
            ConchBlessing.printDebug("Upgrade item found: " .. itemKey .. " (origin: " .. tostring(itemData.origin) .. ", flag: " .. itemData.flag .. ")")
            
            -- add origin item directly to conversion map
            ConchBlessing.ItemMaps[itemData.origin] = {
                upgradeId = itemData.id,
                flag = itemData.flag,
                itemData = itemData -- reference to full item data
            }
            ConchBlessing.printDebug("  Added to conversion map: " .. tostring(itemData.origin) .. " -> " .. tostring(itemData.id) .. " (flag: " .. itemData.flag .. ", price: " .. tostring(itemData.price) .. ")")
        end
    end
    
    ConchBlessing.printDebug("Conversion map created! Total " .. ConchBlessing.tableLength(ConchBlessing.ItemMaps) .. " mappings created.")
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
    
    ConchBlessing.printDebug("Number of entities in room: " .. tostring(#entities))
    
    for _, entity in ipairs(entities) do
        -- check if it's an item pickup
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local collectibleId = entity.SubType
            ConchBlessing.printDebug("Field item found: " .. tostring(collectibleId))
            
            -- find item in conversion map
            local upgradeData = ConchBlessing.ItemMaps[collectibleId]
            if upgradeData then
                ConchBlessing.printDebug("Convertible item found: " .. tostring(collectibleId))
                ConchBlessing.printDebug("  Required flag: " .. upgradeData.flag)
                ConchBlessing.printDebug("  Current result type: " .. result.type)
                
                -- check if flag matches result type
                if upgradeData.flag == result.type then
                    ConchBlessing.printDebug("Flag matches! Item conversion: " .. tostring(collectibleId) .. " -> " .. tostring(upgradeData.upgradeId))
                    
                    -- Save original item properties (including pedestal)
                    local pickup = entity:ToPickup()

                    if pickup == nil then
                        ConchBlessing.printError("Pickup is nil!")
                        return
                    end
                    
                    -- Only perform conversion (no purchase handling)
                    ConchBlessing.printDebug("Item conversion in progress")
                    
                    local originalPrice = pickup.Price
                    local originalOptions = pickup.OptionsPickupIndex
                    local originalWait = pickup.Wait
                    local originalTimeout = pickup.Timeout
                    local originalTouched = pickup.Touched
                    local originalShopItemId = pickup.ShopItemId
                    local originalState = pickup.State
                    
                    -- Replace with complete item config using GetCollectible
                    if pickup then
                        local itemConfig = Isaac.GetItemConfig()
                        local newCollectible = itemConfig:GetCollectible(upgradeData.upgradeId)
                        
                        if newCollectible then
                            ConchBlessing.printDebug("새 아이템 config 적용: " .. newCollectible.Name)
                            
                            -- Change item SubType
                            entity.SubType = upgradeData.upgradeId
                            
                            -- Update with complete new item config
                            -- Replace sprite
                            local sprite = pickup:GetSprite()
                            if sprite then
                                sprite:Load("gfx/005.100_collectible.anm2", true)
                                sprite:ReplaceSpritesheet(1, newCollectible.GfxFileName)
                                sprite:LoadGraphics()
                                sprite:Play("Idle", true)
                                ConchBlessing.printDebug("  스프라이트 교체: " .. newCollectible.GfxFileName)
                            end
                            
                            -- Restore pedestal state
                            pickup.OptionsPickupIndex = originalOptions
                            pickup.Wait = originalWait
                            pickup.Timeout = originalTimeout
                            pickup.Touched = originalTouched
                            pickup.ShopItemId = originalShopItemId
                            pickup.State = originalState
                            
                            -- Apply default attributes from new item config
                            ConchBlessing.printDebug("  Apply new item config:")
                            ConchBlessing.printDebug("    Name: " .. newCollectible.Name)
                            ConchBlessing.printDebug("    Description: " .. newCollectible.Description)
                            if newCollectible.Quality then
                                ConchBlessing.printDebug("    Quality: " .. tostring(newCollectible.Quality))
                            end
                            
                            ConchBlessing.printDebug("  Price is handled by shopprice/devilprice attributes in items.xml")
                        else
                            ConchBlessing.printDebug("ERROR: New item config not found: " .. tostring(upgradeData.upgradeId))
                        end
                    end
                    
                    -- add conversion effect
                    local sfxManager = SFXManager()
                    sfxManager:Play(SoundEffect.SOUND_POWERUP_SPEWER, 0.5)
                    
                    -- particle effect (optional)
                    local particlePosition = Vector(entity.Position.X, entity.Position.Y - 10)
                    for i = 1, 5 do
                        Isaac.Spawn(
                            EntityType.ENTITY_EFFECT,
                            EffectVariant.POOF01,
                            0,
                            particlePosition + Vector(math.random(-10, 10), math.random(-10, 10)),
                            Vector.Zero,
                            nil
                        )
                    end
                    
                    transformed = true
                    ConchBlessing.printDebug("Item conversion complete! (SubType changed)")
                    break
                else
                    ConchBlessing.printDebug("Flag does not match. No conversion.")
                end
            end
        end
        ::continue:: -- goto continue 라벨
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
    generateItemMaps() -- Generate conversion map
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

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, apiRegistrationCallback)

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