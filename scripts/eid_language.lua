-- EID Language Support for Conch's Blessing
-- Handles multilingual item descriptions and names for EID mod

local isc = require("scripts.lib.isaacscript-common")

-- Inline language resolver to ensure immediate reflection of config
local function getCurrentLang()
    local normalize = (ConchBlessing and ConchBlessing.Config and ConchBlessing.NormalizeLanguage)
        or (require("scripts.conch_blessing_config").NormalizeLanguage)

    local cfg = ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.language
    if type(cfg) == "string" and cfg ~= "Auto" and cfg ~= "auto" then
        return normalize(cfg)
    end

    -- If Auto, prefer EID language first (if available), else fall back to Options
    if EID then
        local eidLang = (EID.Config and EID.Config.Language) or (EID.UserConfig and EID.UserConfig.Language)
        if eidLang and eidLang ~= "auto" then
            return normalize(eidLang)
        end
    end

    return normalize((Options and Options.Language) or "en")
end

ConchBlessing.EID = {}
ConchBlessing._eidRegistered = ConchBlessing._eidRegistered or { } -- [id] = true

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
    
    -- Extract name for current language with fallback to English
    local itemName = nil
    if type(itemData.name) == "table" then
        itemName = itemData.name[currentLang] or itemData.name["en"]
        ConchBlessing.printDebug("Resolved name (" .. currentLang .. "): " .. tostring(itemName))
    else
        itemName = itemData.name
        ConchBlessing.printDebug("Resolved name (string): " .. tostring(itemName))
    end
    
    -- Extract eid description for current language with fallback to English
    local eidDescription = nil
    if type(itemData.eid) == "table" then
        local eidData = itemData.eid[currentLang] or itemData.eid["en"]
        if type(eidData) == "table" then
            eidDescription = table.concat(eidData, "\n")
        else
            eidDescription = eidData
        end
        ConchBlessing.printDebug("Resolved eid (" .. currentLang .. "): " .. tostring(eidDescription))
    else
        eidDescription = itemData.eid
        ConchBlessing.printDebug("Resolved eid (string): " .. tostring(eidDescription))
    end
    
    -- Register with EID if we have both name and eid description
    if itemName and eidDescription then
        -- helper: map internal code -> EID code
        local function toEIDLang(code)
            local map = { en = "en_us", kr = "ko_kr", ja = "ja_jp", zh = "zh_cn" }
            return map[code] or (EID and EID.Config and EID.Config.Language) or (EID and EID.DefaultLanguageCode) or "en_us"
        end

        -- Always register English as fallback so EID's internal fallback works for any unsupported language
        local englishName = (type(itemData.name) == "table" and (itemData.name["en"] or itemData.name.en)) or itemData.name
        local englishDesc
        if type(itemData.eid) == "table" then
            local enEid = itemData.eid["en"] or itemData.eid.en
            englishDesc = type(enEid) == "table" and table.concat(enEid, "\n") or enEid
        else
            englishDesc = itemData.eid
        end

        local isTrinket = (itemData.type == "trinket")
        if englishName and englishDesc and not (ConchBlessing._eidRegistered[itemId] and ConchBlessing._eidRegistered[itemId].en_us) then
            if isTrinket then
                EID:addTrinket(itemId, englishDesc, englishName, "en_us")
            else
                EID:addCollectible(itemId, englishDesc, englishName, "en_us")
            end
            ConchBlessing._eidRegistered[itemId] = ConchBlessing._eidRegistered[itemId] or {}
            ConchBlessing._eidRegistered[itemId].en_us = true
        end

        -- Additionally register the currently resolved language if it isn't English
        if currentLang ~= "en" then
            local eidLangCode = toEIDLang(currentLang)
            if not (ConchBlessing._eidRegistered[itemId] and ConchBlessing._eidRegistered[itemId][eidLangCode]) then
                if isTrinket then
                    EID:addTrinket(itemId, eidDescription, itemName, eidLangCode)
                else
                    EID:addCollectible(itemId, eidDescription, itemName, eidLangCode)
                end
                ConchBlessing._eidRegistered[itemId] = ConchBlessing._eidRegistered[itemId] or {}
                ConchBlessing._eidRegistered[itemId][eidLangCode] = true
            end
        end
        ConchBlessing.printDebug(string.format("EID registered (%s): %s - %s", isTrinket and "trinket" or "collectible", itemName, eidDescription))
        
        -- Store in ConchBlessing.EID table for reference
        ConchBlessing.EID[itemId] = {
            name = itemName,
            description = eidDescription
        }
    else
        ConchBlessing.printDebug("Missing name or eid description, skipping EID registration")
    end
end

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

ConchBlessing:AddCallbackCustom(
    isc.ModCallbackCustom.PRE_ITEM_PICKUP,
    function(_, player, pickingUpItem)
        ConchBlessing.printDebug("PRE_ITEM_PICKUP called with player: " .. tostring(player) .. ", pickingUpItem: " .. tostring(pickingUpItem))

        if not pickingUpItem then
            return
        end

        local subType = pickingUpItem.subType
        local found = nil
        for _, itemData in pairs(ConchBlessing.ItemData) do
            if itemData and itemData.id == subType then
                found = itemData
                break
            end
        end
        if not found then return end

        local currentLang = getCurrentLang()
        local itemName = type(found.name) == "table" and (found.name[currentLang] or found.name["en"]) or found.name
        local itemDescription = type(found.description) == "table" and (found.description[currentLang] or found.description["en"]) or found.description
        if itemName and itemDescription then
            local hud = Game():GetHUD()
            if hud then
                hud:ShowItemText(itemName, itemDescription)
            end
        end
    end
)
