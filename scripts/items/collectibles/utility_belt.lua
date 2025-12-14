ConchBlessing.utilitybelt = {}

local UTILITY_BELT_ID = Isaac.GetItemIdByName("Utility Belt")

-- Load isaacscript-common for setActiveItem function
local isc = require("scripts.lib.isaacscript-common")

-- Data for upgrade system
ConchBlessing.utilitybelt.data = {}

-- Track players who had no active on pickup (need to watch for next active)
ConchBlessing.utilitybelt._pendingPlayers = {}

-- Build blacklist safely to avoid nil key errors
ConchBlessing.utilitybelt.blacklist = {}

-- Helper function to safely add to blacklist
local function addToBlacklist(collectibleType)
    if collectibleType and collectibleType > 0 then
        ConchBlessing.utilitybelt.blacklist[collectibleType] = true
    end
end

-- Add known problematic items to blacklist
addToBlacklist(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL_PASSIVE)
addToBlacklist(CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES)
addToBlacklist(CollectibleType.COLLECTIBLE_D_INFINITY)
addToBlacklist(CollectibleType.COLLECTIBLE_BLANK_CARD)
addToBlacklist(CollectibleType.COLLECTIBLE_PLACEBO)
addToBlacklist(CollectibleType.COLLECTIBLE_CLEAR_RUNE)
addToBlacklist(CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
addToBlacklist(CollectibleType.COLLECTIBLE_JAR_OF_WISPS)

-- Check if an item can be moved to pocket slot
local function canMoveToPocket(itemID)
    if itemID <= 0 then return false end
    if ConchBlessing.utilitybelt.blacklist[itemID] then return false end
    return true
end

-- Move active item from primary to pocket slot (SLOT_POCKET only)
local function moveActiveToPocket(player)
    local primaryItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
    local pocketItem = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
    
    -- If no primary item, skip
    if primaryItem <= 0 then
        ConchBlessing.printDebug("Utility Belt: No primary active to move")
        return false
    end
    
    -- If pocket slot is already occupied, do nothing
    if pocketItem > 0 then
        ConchBlessing.printDebug("Utility Belt: Pocket slot already occupied by " .. tostring(pocketItem) .. ", cannot move")
        return false
    end
    
    -- Check if item is blacklisted
    if not canMoveToPocket(primaryItem) then
        ConchBlessing.printDebug("Utility Belt: Item " .. tostring(primaryItem) .. " is blacklisted, cannot move")
        return false
    end
    
    -- Get current charge info
    local primaryCharge = player:GetActiveCharge(ActiveSlot.SLOT_PRIMARY)
    local primaryBattery = player:GetBatteryCharge(ActiveSlot.SLOT_PRIMARY)
    local totalCharge = primaryCharge + primaryBattery
    
    ConchBlessing.printDebug("Utility Belt: Moving item " .. tostring(primaryItem) .. " (charge: " .. tostring(totalCharge) .. ") from PRIMARY to POCKET")
    
    -- Use isaacscript-common's setActiveItem function to properly move the item
    -- First, set the item to pocket slot with charge
    isc:setActiveItem(player, primaryItem, ActiveSlot.SLOT_POCKET, totalCharge)
    -- Then clear the primary slot (use 0 for NULL)
    isc:setActiveItem(player, 0, ActiveSlot.SLOT_PRIMARY, 0)
    
    -- Play sound effect
    SFXManager():Play(SoundEffect.SOUND_POWERUP_SPEWER, 1.0, 0, false, 1.0, 0)
    
    ConchBlessing.printDebug("Utility Belt: Successfully moved active to pocket slot!")
    return true
end

-- Track when player acquires Utility Belt and new active items
ConchBlessing.utilitybelt.onPlayerUpdate = function(_, player)
    if not player then return end
    
    -- Safety check: skip if item ID is invalid
    if not UTILITY_BELT_ID or UTILITY_BELT_ID <= 0 then return end
    
    local playerHash = GetPtrHash(player)
    local playerData = player:GetData()
    
    -- Initialize player data
    if not playerData._panicButton then
        playerData._panicButton = {
            hadItem = false,
            lastPrimaryItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY),
            initialized = true
        }
    end
    
    local hasPanicButton = player:HasCollectible(UTILITY_BELT_ID)
    local hadPanicButton = playerData._panicButton.hadItem or false
    
    -- Detect when player just picked up Utility Belt
    if hasPanicButton and not hadPanicButton then
        playerData._panicButton.hadItem = true
        ConchBlessing.printDebug("Utility Belt: Item just picked up!")
        
        local primaryItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
        
        if primaryItem > 0 then
            -- Has active item - move it to pocket immediately
            if moveActiveToPocket(player) then
                playerData._panicButton.lastPrimaryItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            end
        else
            -- No active item - mark this player as pending (will move next active)
            ConchBlessing.utilitybelt._pendingPlayers[playerHash] = true
            ConchBlessing.printDebug("Utility Belt: No active item, will move next acquired active to pocket")
        end
        return
    end
    
    -- Update hadItem status
    playerData._panicButton.hadItem = hasPanicButton
    
    -- If player doesn't have Utility Belt, don't process further
    if not hasPanicButton then return end
    
    local currentPrimary = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
    local lastPrimary = playerData._panicButton.lastPrimaryItem or 0
    
    -- Check if a new active was acquired in primary slot
    if currentPrimary > 0 and currentPrimary ~= lastPrimary then
        local pocketItem = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
        
        -- If pending (had no active when Utility Belt was picked up) and pocket is empty
        if ConchBlessing.utilitybelt._pendingPlayers[playerHash] and pocketItem <= 0 then
            ConchBlessing.printDebug("Utility Belt: New active detected in primary slot: " .. tostring(currentPrimary))
            
            if moveActiveToPocket(player) then
                ConchBlessing.utilitybelt._pendingPlayers[playerHash] = nil
                -- Update last primary since we moved it
                playerData._panicButton.lastPrimaryItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
                return
            end
        end
    end
    
    playerData._panicButton.lastPrimaryItem = currentPrimary
end

-- Reset tracking on new run
ConchBlessing.utilitybelt.onGameStarted = function(_, isContinued)
    if not isContinued then
        ConchBlessing.utilitybelt._processedPlayers = {}
        ConchBlessing.utilitybelt._pendingPlayers = {}
    end
    ConchBlessing.printDebug("Utility Belt: Game started, tracking reset")
end

-- Reset player data on new level
ConchBlessing.utilitybelt.onNewLevel = function(_)
    -- Keep pending status across floors
    ConchBlessing.printDebug("Utility Belt: New level")
end

-- Upgrade visuals
ConchBlessing.utilitybelt.onBeforeChange = function(upgradePos, pickup, _)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.utilitybelt.data)
end

ConchBlessing.utilitybelt.onAfterChange = function(upgradePos, pickup, _)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.utilitybelt.data)
end

-- Update callback
ConchBlessing.utilitybelt.onUpdate = function(_)
    ConchBlessing.template.onUpdate(ConchBlessing.utilitybelt.data)
end

-- EID description modifier
if EID and UTILITY_BELT_ID and UTILITY_BELT_ID > 0 then
    EID:addDescriptionModifier("Utility Belt Active Info", function(descObj)
        if descObj.ObjType == EntityType.ENTITY_PICKUP 
           and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE 
           and descObj.ObjSubType == UTILITY_BELT_ID then
            
            local player = Isaac.GetPlayer(0)
            if not player then
                return descObj
            end
            
            local ConchBlessing_Config = require("scripts.conch_blessing_config")
            local currentLang = ConchBlessing_Config.GetCurrentLanguage()
            
            local primaryItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            local pocketItem = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            
            local statusText = ""
            if currentLang == "kr" then
                -- Check pocket slot first - if full, nothing can be moved
                if pocketItem > 0 then
                    statusText = "#{{ColorRed}}포켓 슬롯이 이미 사용 중 - 이동 불가{{CR}}"
                elseif primaryItem > 0 then
                    -- Display item icon only
                    statusText = "#{{ColorGreen}}획득 시 이동: {{Collectible" .. tostring(primaryItem) .. "}}{{CR}}"
                else
                    statusText = "#{{ColorYellow}}현재 액티브 없음 - 다음 획득 액티브를 이동{{CR}}"
                end
            else
                -- Check pocket slot first - if full, nothing can be moved
                if pocketItem > 0 then
                    statusText = "#{{ColorRed}}Pocket slot already in use - cannot move{{CR}}"
                elseif primaryItem > 0 then
                    -- Display item icon only
                    statusText = "#{{ColorGreen}}Will move: {{Collectible" .. tostring(primaryItem) .. "}}{{CR}}"
                else
                    statusText = "#{{ColorYellow}}No active - will move next acquired active{{CR}}"
                end
            end
            
            descObj.Description = descObj.Description .. statusText
        end
        
        return descObj
    end)
    
    ConchBlessing.printDebug("[EID] Utility Belt: Description modifier registered")
end

