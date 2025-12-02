-- EID Language Support for Conch's Blessing
-- Handles multilingual item descriptions and names for EID mod

local isc = require("scripts.lib.isaacscript-common")

-- Language resolver: EID setting -> Game setting (no mod-specific override)
local function getCurrentLang()
    local ConchBlessing_Config = require("scripts.conch_blessing_config")
    return ConchBlessing_Config.GetCurrentLanguage()
end

ConchBlessing.EID = ConchBlessing.EID or {}
ConchBlessing._eidRegistered = ConchBlessing._eidRegistered or { } -- [type:id][lang] = true

-- Add multilingual description to EID
-- Usage: ConchBlessing.EID.addOptLangDescription(itemId, itemData)
-- itemData should have name, description, and eid as multilingual objects
-- This function registers ALL available languages from itemData to EID,
-- so EID can display the correct language based on its own settings (not MCM)
ConchBlessing.EID.addOptLangDescription = function(itemId, itemData)
    if not EID then
        ConchBlessing.printDebug("EID not found, skipping language registration")
        return
    end
    
    if not itemData or not itemData.name or not itemData.eid then
        ConchBlessing.printDebug("Item data missing name or eid")
        return
    end
    
    -- Helper: map internal language code to EID language code
    local function toEIDLang(code)
        local map = { en = "en_us", kr = "ko_kr", ja = "ja_jp", zh = "zh_cn" }
        return map[code] or "en_us"
    end
    
    -- Helper: extract text from itemData field (supports both string and table)
    local function extractText(field, langCode)
        if type(field) == "table" then
            local data = field[langCode]
            if type(data) == "table" then
                return table.concat(data, "\n")
            else
                return data
            end
        else
            return field
        end
    end
    
    local isTrinket = (itemData.type == "trinket")
    local regKey = (isTrinket and "T:" or "C:") .. tostring(itemId)
    ConchBlessing._eidRegistered[regKey] = ConchBlessing._eidRegistered[regKey] or {}
    
    -- Collect all available languages from itemData.name
    local availableLanguages = {}
    if type(itemData.name) == "table" then
        for langCode, _ in pairs(itemData.name) do
            availableLanguages[langCode] = true
        end
    end
    -- Also check itemData.eid for additional languages
    if type(itemData.eid) == "table" then
        for langCode, _ in pairs(itemData.eid) do
            availableLanguages[langCode] = true
        end
    end
    -- Always ensure English is registered as fallback
    availableLanguages["en"] = true
    
    -- Register each available language to EID
    local registeredCount = 0
    for langCode, _ in pairs(availableLanguages) do
        local eidLangCode = toEIDLang(langCode)
        
        -- Skip if already registered for this language
        if not ConchBlessing._eidRegistered[regKey][eidLangCode] then
            local itemName = extractText(itemData.name, langCode)
            local eidDescription = extractText(itemData.eid, langCode)
            
            -- Fallback to English if language not found in either field
            if not itemName then
                itemName = extractText(itemData.name, "en")
            end
            if not eidDescription then
                eidDescription = extractText(itemData.eid, "en")
            end
            
            if itemName and eidDescription then
                -- Register to EID with correct language code
                if isTrinket then
                    EID:addTrinket(itemId, eidDescription, itemName, eidLangCode)
                else
                    EID:addCollectible(itemId, eidDescription, itemName, eidLangCode)
                end
                
                ConchBlessing._eidRegistered[regKey][eidLangCode] = true
                registeredCount = registeredCount + 1
                ConchBlessing.printDebug("[EID] Registered " .. eidLangCode .. ": " .. itemName)
            else
                ConchBlessing.printDebug("[EID] Missing text for " .. langCode .. " (name=" .. tostring(itemName) .. ", desc=" .. tostring(eidDescription) .. ")")
            end
        end
    end
    
    ConchBlessing.printDebug(string.format("[EID] Registered %d language(s) for item ID %d (%s)", registeredCount, itemId, isTrinket and "trinket" or "collectible"))
    
    -- Store current language version in ConchBlessing.EID table for reference (used by ShowItemText)
    local currentLang = getCurrentLang()
    local itemName = extractText(itemData.name, currentLang) or extractText(itemData.name, "en")
    local eidDescription = extractText(itemData.eid, currentLang) or extractText(itemData.eid, "en")
    ConchBlessing.EID[regKey] = {
        name = itemName,
        description = eidDescription
    }
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

    -- 1) Prepare language mapping for EID registration (without forcing EID language changes)
    local function toEIDLang(code)
        local map = { en = "en_us", kr = "ko_kr", ja = "ja_jp", zh = "zh_cn" }
        return map[code] or "en_us"
    end
    local short = getCurrentLang() -- auto-detect from EID/game language
    local eidLang = toEIDLang(short)

    -- 1.5) Ensure EID mod context for proper mod name tagging on registrations
    local prevCurrentMod = EID and EID._currentMod
    if EID then
        EID._currentMod = "Conch's Blessing"
        EID.ModIndicator = EID.ModIndicator or {}
        EID.ModIndicator["Conch's Blessing"] = EID.ModIndicator["Conch's Blessing"] or { Name = "Conch's Blessing", Icon = nil }
    end

    -- 1.75) Build separate origin mappings by type to support IDs that exist as both collectible and trinket (Separate mappings solve ID collision issues like 109 and 145)
    local originItemFlags = {
        collectible = {}, -- [originID] = { itemKey1, itemKey2, ... }
        trinket = {}      -- [originID] = { itemKey1, itemKey2, ... }
    }

    -- Normalize origin declaration to an ID and optional explicit type
    local function resolveOriginAny(origin)
        -- Supports:
        -- 1) number (collectible/trinket id)
        -- 2) { id = number, type = "collectible"|"trinket" }
        -- 3) { name = string, type = "collectible"|"trinket" }
        -- 4) { collectible = string } or { trinket = string }
        if type(origin) == "number" then
            return origin, nil
        end
        if type(origin) == "table" then
            local explicitType = origin.type
            local id = origin.id
            if not id then
                if origin.name and explicitType == "trinket" then
                    id = Isaac.GetTrinketIdByName(origin.name)
                elseif origin.name and explicitType == "collectible" then
                    id = Isaac.GetItemIdByName(origin.name)
                elseif origin.trinket then
                    id = Isaac.GetTrinketIdByName(origin.trinket)
                    explicitType = explicitType or "trinket"
                elseif origin.collectible then
                    id = Isaac.GetItemIdByName(origin.collectible)
                    explicitType = explicitType or "collectible"
                end
            end
            local isTrink = nil
            if explicitType == "trinket" then
                isTrink = true
            elseif explicitType == "collectible" then
                isTrink = false
            end
            return id or -1, isTrink
        end
        return nil, nil
    end

    ConchBlessing.printDebug("Building origin mappings for EID descriptions...")
    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        if itemData.origin and itemData.flag then
            local originID, originIsTrinkExp = resolveOriginAny(itemData.origin)
            if type(originID) ~= "number" or originID <= 0 then
                ConchBlessing.printError("  Invalid origin ID for " .. itemKey .. ": " .. tostring(originID))
            else
                -- Determine origin type: explicit > auto-detect
                local originIsTrinket = originIsTrinkExp
                ConchBlessing.printDebug("[EID] Processing origin for " .. itemKey .. ": originID=" .. tostring(originID) .. ", explicitType=" .. tostring(originIsTrinkExp))
                
                if originIsTrinket == nil then
                    -- Auto-detect from game config only if type not explicitly specified
                    local cfg = Isaac.GetItemConfig()
                    local hasTrinket = (cfg and cfg:GetTrinket(originID) ~= nil) or false
                    local hasCollectible = (cfg and cfg:GetCollectible(originID) ~= nil) or false
                    ConchBlessing.printDebug("[EID] Auto-detecting origin ID " .. tostring(originID) .. ": hasTrinket=" .. tostring(hasTrinket) .. ", hasCollectible=" .. tostring(hasCollectible))
                    
                    if hasTrinket and not hasCollectible then
                        originIsTrinket = true
                    elseif hasCollectible and not hasTrinket then
                        originIsTrinket = false
                    else
                        -- Ambiguous: skip this origin
                        ConchBlessing.printDebug("[EID] Ambiguous origin ID " .. tostring(originID) .. " for " .. itemKey .. "; requires explicit type declaration")
                        originIsTrinket = nil
                    end
                end
                
                -- Map to appropriate category
                if originIsTrinket == true then
                    if not originItemFlags.trinket[originID] then
                        originItemFlags.trinket[originID] = {}
                    end
                    table.insert(originItemFlags.trinket[originID], itemKey)
                    ConchBlessing.printDebug("[EID] Mapped " .. itemKey .. " to TRINKET origin " .. tostring(originID) .. " (flag: " .. itemData.flag .. ")")
                elseif originIsTrinket == false then
                    if not originItemFlags.collectible[originID] then
                        originItemFlags.collectible[originID] = {}
                    end
                    table.insert(originItemFlags.collectible[originID], itemKey)
                    ConchBlessing.printDebug("[EID] Mapped " .. itemKey .. " to COLLECTIBLE origin " .. tostring(originID) .. " (flag: " .. itemData.flag .. ")")
                else
                    ConchBlessing.printDebug("[EID] FAILED to map " .. itemKey .. " - originIsTrinket is nil")
                end
            end
        end
    end

    -- Expose origin maps for EID modifier use
    ConchBlessing._originItemFlags = originItemFlags
    ConchBlessing.printDebug("Origin mappings built successfully!")

    -- 2) Register base names/descriptions in the resolved language
    for itemKey, itemData in pairs(ConchBlessing.ItemData) do
        local itemId = itemData.id
        if itemId and itemId ~= -1 then
            ConchBlessing.EID.addOptLangDescription(itemId, itemData)
            -- Prevent cross-type bleed: if trinket id collides with collectible id, ensure we only register by type
            -- addOptLangDescription now uses type-prefixed keys internally, so nothing else needed here
        else
            ConchBlessing.printDebug("Skipping " .. itemKey .. " - invalid item ID")
        end
    end

    -- 3) Register specials (Golden/Mom's Box) for ALL available languages
    -- Supported languages for registration
    local supportedLangs = { "en", "kr", "ja", "zh" }
    
    local function getBaseEidTextForLang(itemData, langCode)
        local eidSrc = itemData.eid
        local langEid
        if type(eidSrc) == "table" then
            langEid = eidSrc[langCode] or eidSrc["en"]
        else
            langEid = eidSrc
        end
        local baseText = ""
        if type(langEid) == "table" then
            baseText = table.concat(langEid, "\n")
        else
            baseText = tostring(langEid or "")
        end
        return baseText
    end

    local function replaceNumbersInOrder(text, values, colorGold)
        local i = 1
        local function repl(num)
            local v = values[i]
            if v ~= nil then
                i = i + 1
                local s = tostring(v)
                if colorGold then return "{{ColorGold}}" .. s .. "{{CR}}" end
                return s
            end
            i = i + 1
            return num
        end
        return text:gsub("%d*%.?%d+", repl)
    end

    for key, data in pairs(ConchBlessing.ItemData or {}) do
        if data and data.type == "trinket" and data.id and data.id ~= -1 and data.specials then
            local specTop = data.specials
            
            -- Register for each supported language
            for _, langCode in ipairs(supportedLangs) do
                local targetEidLang = toEIDLang(langCode)
                local specLang = type(specTop[langCode]) == "table" and specTop[langCode] or nil
                
                local function pick(k)
                    if specLang and specLang[k] ~= nil then return specLang[k] end
                    return specTop[k]
                end
                local nVal = pick("normal")
                local mVal = pick("moms_box")
                local bVal = pick("both")

                if nVal ~= nil or mVal ~= nil or bVal ~= nil then
                    if type(nVal) == "table" then
                        -- Array full replace for this language
                        local base = getBaseEidTextForLang(data, langCode)
                        local ln = nVal
                        local lm = (type(mVal) == "table") and mVal or ln
                        local lb = (type(bVal) == "table") and bVal or lm
                        local t1 = replaceNumbersInOrder(base, ln, false)
                        local t2 = replaceNumbersInOrder(base, lm, true)
                        local t3 = replaceNumbersInOrder(base, lb, true)
                        EID:CreateDescriptionTableIfMissing("goldenTrinketEffects", targetEidLang)
                        EID.descriptions[targetEidLang].goldenTrinketEffects[data.id] = { t1, t2, t3 }
                        -- Only call addGoldenTrinketTable once (for en_us as base)
                        if langCode == "en" then
                            EID:addGoldenTrinketTable(data.id, { fullReplace = true })
                        end
                        ConchBlessing.printDebug("[EID] Golden trinket fullReplace registered for " .. key .. " (" .. targetEidLang .. ")")
                    else
                        local num = tonumber(nVal)
                        if num then
                            -- Numeric multiplier (language-independent, only register once)
                            if langCode == "en" then
                                EID:CreateDescriptionTableIfMissing("goldenTrinketData", targetEidLang)
                                EID.descriptions[targetEidLang].goldenTrinketData[data.id] = { t = { num } }
                                ConchBlessing.printDebug("[EID] Golden trinket multiplier registered for " .. key .. ": " .. tostring(num))
                            end
                        else
                            -- String find/replace for this language
                            EID:CreateDescriptionTableIfMissing("goldenTrinketEffects", targetEidLang)
                            local repl = {
                                tostring(nVal or ""),
                                tostring(mVal or nVal or ""),
                                tostring(bVal or mVal or nVal or "")
                            }
                            EID.descriptions[targetEidLang].goldenTrinketEffects[data.id] = repl
                            -- Only call addGoldenTrinketTable once (for en_us as base)
                            if langCode == "en" then
                                EID:addGoldenTrinketTable(data.id, { findReplace = true })
                            end
                            ConchBlessing.printDebug("[EID] Golden trinket findReplace registered for " .. key .. " (" .. targetEidLang .. ")")
                        end
                    end
                end
            end
        end
    end

    -- Restore previous EID mod context
    if EID then EID._currentMod = prevCurrentMod end

    ConchBlessing.printDebug("EID registration complete!")
end

-- Register a simple EID Mod Indicator for Conch's Blessing
if EID then
    -- Ensure proper mod context and ModIndicator entry (mirrors EID's own RegisterMod override pattern)
    local prevCurrentMod = EID._currentMod
    EID._currentMod = "Conch's Blessing"
    EID.ModIndicator = EID.ModIndicator or {}
    EID.ModIndicator["Conch's Blessing"] = EID.ModIndicator["Conch's Blessing"] or { Name = "Conch's Blessing", Icon = nil }

    -- Set indicator name and icon
    if EID.setModIndicatorName then EID:setModIndicatorName("Conch's Blessing") end
    if EID.setModIndicatorIcon then
        -- Prefer dedicated mod icon; fallback to ConchMode if needed
        local ok = pcall(function() EID:setModIndicatorIcon("ConchBlessing ModIcon") end)
        if not ok then pcall(function() EID:setModIndicatorIcon("ConchMode") end) end
    end
    -- restore previous mod context to not affect other mods
    EID._currentMod = prevCurrentMod
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

        -- Support both lowercase and engine field casing
        local itemType = pickingUpItem.itemType or pickingUpItem.ItemType
        local subType = pickingUpItem.subType or pickingUpItem.SubType
        local targetIsTrinket = (itemType == ItemType.ITEM_TRINKET)
        if itemType == nil then
            -- Fallback to variant-based inference
            local variant = pickingUpItem.variant or pickingUpItem.Variant
            targetIsTrinket = (variant == PickupVariant.PICKUP_TRINKET)
        end
        if type(subType) ~= "number" then return end
        -- Strip golden trinket flag for comparison
        if targetIsTrinket and subType >= 32768 then
            subType = subType - 32768
        end

        local found = nil
        for _, itemData in pairs(ConchBlessing.ItemData) do
            if itemData and itemData.id == subType then
                local isDataTrinket = (itemData.type == "trinket")
                if (targetIsTrinket and isDataTrinket) or ((not targetIsTrinket) and (not isDataTrinket)) then
                    found = itemData
                    break
                end
            end
        end
        if not found then
            ConchBlessing.printDebug("PRE_ITEM_PICKUP: no matching itemData for itemType=" .. tostring(itemType) .. ", subType=" .. tostring(subType))
            return
        end

        local currentLang = getCurrentLang()
        local itemName = type(found.name) == "table" and (found.name[currentLang] or found.name["en"]) or found.name
        local itemDescription = type(found.description) == "table" and (found.description[currentLang] or found.description["en"]) or found.description
        if itemName and itemDescription then
            local hud = Game():GetHUD()
            if hud then
                hud:ShowItemText(itemName, itemDescription)
            else
                ConchBlessing.printDebug("HUD not available for ShowItemText")
            end
        end
    end
)
