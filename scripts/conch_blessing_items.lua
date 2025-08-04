-- ItemData table
-- available attributes:
--   type: "passive" | "active" | "familiar" | "null" - item type
--   id: Isaac.GetItemIdByName("item name") - item ID (generated from XML)
--   name: "item name" - item display name
--   description: "description" - item description
--   pool: { RoomType.ROOM_XXX, ... } - item pools it appears in (can specify multiple pools as an array)
--     possible pools: TREASURE, SHOP, SECRET, SUPERSECRET, DEVIL, ANGEL, BOSS, MINIBOSS
--   weight: number - item weight in pool (higher number means more frequent appearance)
--   DecreaseBy: number - weight decrease when item is selected from pool
--   RemoveOn: number - probability of item being removed from pool (0.0-1.0)
--   quality: number - item quality (0-5, 5 is highest quality)
--   tags: "tag1 tag2" - item tags (offensive, defensive, summonable, mushroom, devil, angel, etc.)
--     possible tags: dead, syringe, mom, tech, battery, guppy, fly, bob, mushroom, baby, angel, devil, poop, book, spider, quest, monstermanual, nogreed
--   cache: "cache flag" - cache flag (all, damage, firedelay, shotspeed, range, tearflag, etc.)
--   hidden: true/false - hidden item
--   devilprice: number - price in devil room (heart count)
--   shopprice: number - price in shop (coin count)
--   maxcharges: number - max charges for active item
--   chargetype: "type" - charge type (normal, special)
--   hearts: number - heart change amount (can be negative)
--   maxhearts: number - max heart change amount (can be negative)
--   blackhearts: number - black heart count
--   soulhearts: number - soul heart count
--   script: "script path" - item effect script file path (default path is used if omitted)
--   callbacks: { callback functions } - callback functions to automatically register
--     pickup: "function name" - called when item is picked up
--     use: "function name" - called when item is used
--     evaluateCache: "function name" - called when cache is calculated
--     tearHit: "function name" - called when tear hits
--     tearCollision: "function name" - called when tear collides
--     gameStarted: "function name" - called when game starts

-- Conch's Blessing - Items System
-- Item information and callback management system

ConchBlessing.printDebug("Item system loaded!")

-- check if ModCallbacks is defined
if not ModCallbacks then
    ConchBlessing.printError("Error: ModCallbacks is not defined!")
    return
end

-- define ItemData table
ConchBlessing.ItemData = {
    LIVE_EYE = {
        type = "passive",
        id = Isaac.GetItemIdByName("Live Eye"),
        name = "Live Eye",
        description = "The eye moves!",
        pool = {
            RoomType.ROOM_TREASURE,
            RoomType.ROOM_SHOP,
            RoomType.ROOM_SECRET,
            RoomType.ROOM_SUPERSECRET,
            RoomType.ROOM_DEVIL,
            RoomType.ROOM_ANGEL,
            RoomType.ROOM_BOSS,
        },
        quality = 3,
        tags = "offensive",
        cache = "all",
        hidden = false,
        weight = 1.0,
        DecreaseBy = 1,
        RemoveOn = 0.1,
        shopprice = 20, -- 상점에서의 가격 (코인)
        devilprice = 2, -- 악마방에서의 가격 (하트)
        maxcharges = 0,
        chargetype = "normal",
        hearts = 0,
        maxhearts = 0,
        blackhearts = 0,
        soulhearts = 0,
        -- origin = CollectibleType.COLLECTIBLE_BRIMSTONE, -- original item information
        origin = CollectibleType.COLLECTIBLE_DEAD_EYE, -- original item information
        flag = "positive", -- match Magic Conch result type
        script = "scripts/items/live_eye",
        callbacks = {
            pickup = "liveeye.onPickup",
            use = "liveeye.onUse",
            evaluateCache = "liveeye.onEvaluateCache",
            fireTear = "liveeye.onFireTear",
            tearCollision = "liveeye.onTearCollision",
            gameStarted = "liveeye.onGameStarted",
            update = "liveeye.onUpdate"
        }
    }
}

-- automatically load scripts and callbacks based on ItemData
local function loadAllItems()
    ConchBlessing.printDebug("Loading scripts and callbacks based on ItemData...")
    
    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        ConchBlessing.printDebug("Processing: " .. itemKey)
        
        -- 1. load script
        local scriptPath = itemData.script or "scripts/items/" .. string.lower(itemKey) .. ".lua"
        ConchBlessing.printDebug("  Loading script: " .. scriptPath)
        
        local scriptSuccess, scriptErr = pcall(function()
            include(scriptPath)
        end)
        if scriptSuccess then
            ConchBlessing.printDebug("  Script loaded successfully: " .. scriptPath)
        else
            ConchBlessing.printError("  Script load failed: " .. scriptPath .. " - " .. tostring(scriptErr))
        end
        
        -- 2. register callbacks
        if itemData.callbacks then
            -- helper function to find functions by dot notation
            local function getFunctionByPath(path)
                local parts = {}
                for part in path:gmatch("[^%.]+") do
                    table.insert(parts, part)
                end
                
                local current = ConchBlessing
                for _, part in ipairs(parts) do
                    if current and current[part] then
                        current = current[part]
                    else
                        return nil
                    end
                end
                return current
            end
            
            -- first check if item ID is valid
            local itemId = itemData.id
            if itemId == -1 or itemId == nil then
                ConchBlessing.printError("  Warning: " .. itemKey .. " has an invalid item ID (" .. tostring(itemId) .. "). Skipping callback registration.")
                ConchBlessing.printError("  Check if the item is properly registered in the XML file.")
            else
                ConchBlessing.printDebug("  Item ID check: " .. itemKey .. " = " .. itemId)
                
                if itemData.callbacks.pickup then
                    local func = getFunctionByPath(itemData.callbacks.pickup)
                    if func then
                        ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, func, itemId)
                        ConchBlessing.printDebug("  pickup callback registered (ID: " .. itemId .. ")")
                    else
                        ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.pickup) .. " function is not defined!")
                    end
                end
                if itemData.callbacks.use then
                    local func = getFunctionByPath(itemData.callbacks.use)
                    if func then
                        ConchBlessing:AddCallback(ModCallbacks.MC_USE_ITEM, func, itemId)
                        ConchBlessing.printDebug("  use callback registered (ID: " .. itemId .. ")")
                    else
                        ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.use) .. " function is not defined!")
                    end
                end
            end
            
            -- ID가 필요하지 않은 콜백들
            if itemData.callbacks.evaluateCache then
                local func = getFunctionByPath(itemData.callbacks.evaluateCache)
                if func then
                    ConchBlessing:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, func)
                    ConchBlessing.printDebug("  evaluateCache callback registered")
                else
                    ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.evaluateCache) .. " function is not defined!")
                end
            end
            if itemData.callbacks.tearInit then
                local func = getFunctionByPath(itemData.callbacks.tearInit)
                if func then
                    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, func)
                    ConchBlessing.printDebug("  tearInit callback registered")
                else
                    ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.tearInit) .. " function is not defined!")
                end
            end
            if itemData.callbacks.tearUpdate then
                local func = getFunctionByPath(itemData.callbacks.tearUpdate)
                if func then
                    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, func)
                    ConchBlessing.printDebug("  tearUpdate callback registered")
                else
                    ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.tearUpdate) .. " function is not defined!")
                end
            end
            if itemData.callbacks.fireTear then
                local func = getFunctionByPath(itemData.callbacks.fireTear)
                if func then
                    ConchBlessing:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, func)
                    ConchBlessing.printDebug("  fireTear callback registered")
                else
                    ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.fireTear) .. " function is not defined!")
                end
            end
            if itemData.callbacks.tearCollision then
                local func = getFunctionByPath(itemData.callbacks.tearCollision)
                if func then
                    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_TEAR_COLLISION, func)
                    ConchBlessing.printDebug("  tearCollision callback registered")
                else
                    ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.tearCollision) .. " function is not defined!")
                end
            end
            if itemData.callbacks.gameStarted then
                local func = getFunctionByPath(itemData.callbacks.gameStarted)
                if func then
                    ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, func)
                    ConchBlessing.printDebug("  gameStarted callback registered")
                else
                    ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.gameStarted) .. " function is not defined!")
                end
            end
            if itemData.callbacks.update then
                local func = getFunctionByPath(itemData.callbacks.update)
                if func then
                    ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, func)
                    ConchBlessing.printDebug("  update callback registered")
                else
                    ConchBlessing.printError("  Warning: " .. tostring(itemData.callbacks.update) .. " function is not defined!")
                end
            end
        end
        
        ConchBlessing.printDebug("  " .. itemKey .. " processed")
    end
    
    ConchBlessing.printDebug("Scripts and callbacks loaded successfully!")
end

loadAllItems()

-- item pools are handled in the XML file (content/itempools.xml)
ConchBlessing.printDebug("Item pools are handled in the XML file (content/itempools.xml)")

-- item management functions (add as needed)
