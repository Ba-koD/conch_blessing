-- EID Language Support for Conch's Blessing
-- Handles multilingual item descriptions and names for EID mod

local isc = require("scripts.lib.isaacscript-common")

-- Inline language resolver to ensure immediate reflection of config
local function getCurrentLang()
    local cfg = ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.language
    if type(cfg) == "string" and cfg ~= "auto" then
        return cfg
    end
    return (Options and Options.Language) or "en"
end

ConchBlessing.EID = {}

-- Add multilingual description to EID
-- Usage: ConchBlessing.EID.addOptLangDescription(itemId, itemData)
-- itemData should have name, description, and eid as multilingual objects
ConchBlessing.EID.addOptLangDescription = function(itemId, itemData)
    if not EID then
        ConchBlessing.printDebug("EID not found, skipping language registration")
        return
    end
    
    if not itemData or not itemData.name or not itemData.eid then
        ConchBlessing.printDebug("Item data missing name or eid")
        return
    end
    
    -- Get current language from config / Options
    local currentLang = getCurrentLang()
    ConchBlessing.printDebug("Current language: " .. currentLang)
    
    -- Extract name for current language
    local itemName = nil
    if type(itemData.name) == "table" then
        -- Multilingual structure: { kr = "...", en = "..." }
        itemName = itemData.name[currentLang] or itemData.name["en"]
        ConchBlessing.printDebug("Found multilingual name: " .. (itemName or "nil"))
    else
        -- Simple string
        itemName = itemData.name
        ConchBlessing.printDebug("Found simple name: " .. (itemName or "nil"))
    end
    
    -- Extract eid description for current language
    local eidDescription = nil
    if type(itemData.eid) == "table" then
        -- Multilingual structure: { kr = {...}, en = {...} }
        local eidData = itemData.eid[currentLang] or itemData.eid["en"]
        if type(eidData) == "table" then
            -- Join multiple lines with newlines for EID
            eidDescription = table.concat(eidData, "\n")
        else
            eidDescription = eidData
        end
        ConchBlessing.printDebug("Found multilingual eid description: " .. tostring(eidDescription))
    else
        -- Simple string
        eidDescription = itemData.eid
        ConchBlessing.printDebug("Found simple eid description: " .. (eidDescription or "nil"))
    end
    
    -- Register with EID if we have both name and eid description
    if itemName and eidDescription then
        EID:addCollectible(itemId, eidDescription, itemName)
        ConchBlessing.printDebug(string.format("EID registered: %s - %s", itemName, eidDescription))
        
        -- Store in ConchBlessing.EID table for reference
        ConchBlessing.EID[itemId] = {
            name = itemName,
            description = eidDescription
        }
    else
        ConchBlessing.printDebug("Missing name or eid description, skipping EID registration")
    end
end

-- Add EID Collectible function similar to Astro:AddEIDCollectible
ConchBlessing.EID.AddEIDCollectible = function(id, name, description, eidDescription)
    if EID then
        EID:addCollectible(id, eidDescription, name)
    end

    ConchBlessing.EID[id] = {
        name = name,
        description = description
    }
end

-- Register all items with EID
ConchBlessing.EID.registerAllItems = function()
    ConchBlessing.printDebug("Registering all items with EID...")
    
    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        local itemId = itemData.id
        if itemId and itemId ~= -1 then
            ConchBlessing.EID.addOptLangDescription(itemId, itemData)
        else
            ConchBlessing.printDebug("Skipping " .. itemKey .. " - invalid item ID")
        end
    end
    
    ConchBlessing.printDebug("EID registration complete!")
end

-- Auto-register when mod loads
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    ConchBlessing.EID.registerAllItems()
end)

-- Prefer custom callback if available; otherwise, fall back to vanilla collision callback
ConchBlessing:AddCallbackCustom(
    isc.ModCallbackCustom.PRE_ITEM_PICKUP,
    ---@param player EntityPlayer
    ---@param pickingUpItem { itemType: ItemType, subType: CollectibleType | TrinketType }
    function(_, player, pickingUpItem)
        ConchBlessing.printDebug("PRE_ITEM_PICKUP called with player: " .. tostring(player) .. ", pickingUpItem: " .. tostring(pickingUpItem))

        if not pickingUpItem then
            return
        end
        if pickingUpItem.itemType == ItemType.ITEM_TRINKET then
            return
        end

        ConchBlessing.printDebug("Picking up item: " .. tostring(pickingUpItem.itemType) .. ", " .. tostring(pickingUpItem.subType))

        local collectibleType = pickingUpItem.subType

        for _, itemData in pairs(ConchBlessing.ItemData) do
            if itemData and itemData.id == collectibleType then
                local currentLang = getCurrentLang()
                local itemName = type(itemData.name) == "table" and (itemData.name[currentLang] or itemData.name["en"]) or itemData.name
                local itemDescription = type(itemData.description) == "table" and (itemData.description[currentLang] or itemData.description["en"]) or itemData.description
                if itemName and itemDescription then
                    local hud = Game():GetHUD()
                    if hud then
                        hud:ShowItemText(itemName, itemDescription)
                    end
                end
                break
            end
        end
    end
)
