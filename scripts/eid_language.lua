-- EID Language Support for Conch's Blessing
-- Handles multilingual item descriptions and names for EID mod

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
    
    -- Get current language from Options
    local currentLang = Options.Language or "en"
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

-- Show item text when picking up items
ConchBlessing:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    ---@param pickup EntityPickup
    ---@param collider Entity
    function(_, pickup, collider)
        ConchBlessing.printDebug("MC_PRE_PICKUP_COLLISION called with pickup: " .. tostring(pickup) .. ", collider: " .. tostring(collider))
        
        -- Check if it's a collectible item and the collider is a player
        if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and collider:ToPlayer() then
            local collectibleType = pickup.SubType
            
            -- Find the item data for this item
            for itemKey, itemData in pairs(ConchBlessing.ItemData) do
                ConchBlessing.printDebug("Checking item: " .. itemKey .. " (ID: " .. tostring(itemData.id) .. ")")
                if itemData.id == collectibleType then
                    -- Get current language
                    local currentLang = Options.Language or "en"
                    
                    -- Extract name for current language
                    local itemName = nil
                    if type(itemData.name) == "table" then
                        -- Check if current language exists, otherwise use English
                        if itemData.name[currentLang] then
                            itemName = itemData.name[currentLang]
                        else
                            itemName = itemData.name["en"]
                        end
                    else
                        -- Simple string
                        itemName = itemData.name
                    end
                    
                    -- Extract description for current language (for ShowItemText)
                    local itemDescription = nil
                    if type(itemData.description) == "table" then
                        -- Check if current language exists, otherwise use English
                        itemDescription = itemData.description[currentLang] or itemData.description["en"]
                    else
                        -- Simple string
                        itemDescription = itemData.description
                    end
                    
                    -- Show item text if we have both name and description
                    if itemName and itemDescription then
                        ConchBlessing.printDebug("Attempting to show item text...")
                        ConchBlessing.printDebug("Item name: " .. tostring(itemName))
                        ConchBlessing.printDebug("Item description: " .. tostring(itemDescription))
                        
                        local hud = Game():GetHUD()
                        if hud then
                            ConchBlessing.printDebug("HUD found, calling ShowItemText...")
                            hud:ShowItemText(itemName, itemDescription)
                            ConchBlessing.printDebug("ShowItemText called successfully")
                        else
                            ConchBlessing.printDebug("HUD not found!")
                        end
                    else
                        ConchBlessing.printDebug("Missing name or description for ShowItemText")
                        ConchBlessing.printDebug("Name: " .. tostring(itemName))
                        ConchBlessing.printDebug("Description: " .. tostring(itemDescription))
                    end
                    
                    break
                end
            end
        end
    end
) 