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

ConchBlessing.EID = ConchBlessing.EID or {}
ConchBlessing._eidRegistered = ConchBlessing._eidRegistered or { } -- [type:id][lang] = true

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
        local regKey = (isTrinket and "T:" or "C:") .. tostring(itemId)
        if englishName and englishDesc and not (ConchBlessing._eidRegistered[regKey] and ConchBlessing._eidRegistered[regKey].en_us) then
            if isTrinket then
                EID:addTrinket(itemId, englishDesc, englishName, "en_us")
            else
                EID:addCollectible(itemId, englishDesc, englishName, "en_us")
            end
            ConchBlessing._eidRegistered[regKey] = ConchBlessing._eidRegistered[regKey] or {}
            ConchBlessing._eidRegistered[regKey].en_us = true
        end

        -- Additionally register the currently resolved language if it isn't English
        if currentLang ~= "en" then
            local eidLangCode = toEIDLang(currentLang)
            if not (ConchBlessing._eidRegistered[regKey] and ConchBlessing._eidRegistered[regKey][eidLangCode]) then
                if isTrinket then
                    EID:addTrinket(itemId, eidDescription, itemName, eidLangCode)
                else
                    EID:addCollectible(itemId, eidDescription, itemName, eidLangCode)
                end
                ConchBlessing._eidRegistered[regKey] = ConchBlessing._eidRegistered[regKey] or {}
                ConchBlessing._eidRegistered[regKey][eidLangCode] = true
                ConchBlessing.printDebug("[EID] Registered current mod language mapping: " .. tostring(eidLangCode))
            end
        end

        -- Mirror into EID's current display language, so descriptions follow our MCM setting without forcing EID language
        local eidDisplayLang = (EID and ((EID.Config and EID.Config.Language) or EID.DefaultLanguageCode)) or nil
        if eidDisplayLang then
            local targetLang = tostring(eidDisplayLang)
            local already = ConchBlessing._eidRegistered[regKey] and ConchBlessing._eidRegistered[regKey][targetLang]
            if not already then
                if isTrinket then
                    EID:addTrinket(itemId, eidDescription, itemName, targetLang)
                else
                    EID:addCollectible(itemId, eidDescription, itemName, targetLang)
                end
                ConchBlessing._eidRegistered[regKey] = ConchBlessing._eidRegistered[regKey] or {}
                ConchBlessing._eidRegistered[regKey][targetLang] = true
                ConchBlessing.printDebug("[EID] Mirrored mapping into EID display language: " .. targetLang)
            end
        else
            ConchBlessing.printDebug("[EID] No EID display language detected for mirroring")
        end
        ConchBlessing.printDebug(string.format("EID registered (%s): %s - %s", isTrinket and "trinket" or "collectible", itemName, eidDescription))
        
        -- Store in ConchBlessing.EID table for reference with type-prefixed key to avoid collisions
        ConchBlessing.EID[regKey] = {
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

    -- 1) Do NOT force EID language. Instead, only try to load a suitable font for current language
    local function toEIDLang(code)
        local map = { en = "en_us", kr = "ko_kr", ja = "ja_jp", zh = "zh_cn" }
        return map[code] or "en_us"
    end
    local short = getCurrentLang() -- prioritizes ConchBlessing.Config.language
    local eidLang = toEIDLang(short)
    if EID then
        EID.Config = EID.Config or {}
        -- Debug: show current EID language (not forcing changes)
        ConchBlessing.printDebug("[EID] Current EID.Config.Language = " .. tostring(EID.Config.Language))

        -- Try to load font from External Item Descriptions' font folder if exists
        -- NOTE: Do not hardcode exact font type; respect EID.Config.FontType if available
        local fontType = EID.Config["FontType"]
        local externalFontBase = "C:/Program Files (x86)/Steam/steamapps/common/The Binding of Isaac Rebirth/mods/external item descriptions_836319872/resources/font/"
        local function tryLoadFont(path)
            if type(EID.loadFont) == "function" then
                local ok, err = pcall(function()
                    EID:loadFont(path)
                end)
                if ok then
                    ConchBlessing.printDebug("[EID] Loaded font: " .. tostring(path))
                    return true
                else
                    ConchBlessing.printDebug("[EID] Failed to load font: " .. tostring(path) .. ", error=" .. tostring(err))
                end
            end
            return false
        end

        -- Candidate font paths in order (language-aware first, then generic by FontType, then EID default path)
        local candidates = {}
        -- language-specific families commonly used by EID (these filenames may vary by user setup; we attempt reasonable variants)
        table.insert(candidates, externalFontBase .. "eid_" .. tostring(fontType or "") .. ".fnt")
        table.insert(candidates, externalFontBase .. "eid_default.fnt")
        -- fallback to EID's own mod fonts if present
        if EID.modPath then
            if fontType then
                table.insert(candidates, EID.modPath .. "resources/font/eid_" .. tostring(fontType) .. ".fnt")
            end
            table.insert(candidates, EID.modPath .. "resources/font/eid_default.fnt")
        end

        local loaded = false
        for _, p in ipairs(candidates) do
            if p and p ~= externalFontBase .. "eid_.fnt" then
                if tryLoadFont(p) then
                    loaded = true
                    break
                end
            end
        end

        -- Signal EID to refresh without changing its language
        EID.MCM_OptionChanged = true
        EID.ForceRefreshCache = true
        ConchBlessing.printDebug("[EID] Font refresh requested; language preserved: " .. tostring(EID.Config.Language))
        if not loaded then
            ConchBlessing.printDebug("[EID] No candidate font loaded; EID will keep current font settings")
        end
    end

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

    -- 3) Register specials (Golden/Mom's Box) for the current language only
    local function getBaseEidTextForCurrentLang(itemData)
        local eidSrc = itemData.eid
        local langEid = (type(eidSrc) == "table") and (eidSrc[short] or eidSrc["en"]) or eidSrc
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
            local specLang = type(specTop[short]) == "table" and specTop[short] or nil
            local function pick(k)
                if specLang and specLang[k] ~= nil then return specLang[k] end
                return specTop[k]
            end
            local nVal = pick("normal")
            local mVal = pick("moms_box")
            local bVal = pick("both")

            if nVal ~= nil or mVal ~= nil or bVal ~= nil then
                if type(nVal) == "table" then
                    -- Array full replace for current language
                    local base = getBaseEidTextForCurrentLang(data)
                    local ln = nVal
                    local lm = (type(mVal) == "table") and mVal or ln
                    local lb = (type(bVal) == "table") and bVal or lm
                    local t1 = replaceNumbersInOrder(base, ln, false)
                    local t2 = replaceNumbersInOrder(base, lm, true)
                    local t3 = replaceNumbersInOrder(base, lb, true)
                    EID:CreateDescriptionTableIfMissing("goldenTrinketEffects", eidLang)
                    EID.descriptions[eidLang].goldenTrinketEffects[data.id] = { t1, t2, t3 }
                    EID:addGoldenTrinketTable(data.id, { fullReplace = true })
                else
                    local num = tonumber(nVal)
                    if num then
                        -- Language-specific multiplier metadata
                        EID:CreateDescriptionTableIfMissing("goldenTrinketData", eidLang)
                        EID.descriptions[eidLang].goldenTrinketData[data.id] = { t = { num } }
                    else
                        -- String find/replace for current language
                        EID:CreateDescriptionTableIfMissing("goldenTrinketEffects", eidLang)
                        local repl = {
                            tostring(nVal or ""),
                            tostring(mVal or nVal or ""),
                            tostring(bVal or mVal or nVal or "")
                        }
                        EID.descriptions[eidLang].goldenTrinketEffects[data.id] = repl
                        EID:addGoldenTrinketTable(data.id, { findReplace = true })
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
