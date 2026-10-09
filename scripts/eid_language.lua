-- EID Language Support for Conch's Blessing
-- Handles multilingual item descriptions and names for EID mod

local isc = require("scripts.lib.isaacscript-common")

-- Effective mod language: explicit selection or the configured automatic/date policy.
local function getCurrentLang()
    local ConchBlessing_Config = require("scripts.conch_blessing_config")
    return ConchBlessing_Config.GetCurrentLanguage()
end

ConchBlessing.EID = ConchBlessing.EID or {}
ConchBlessing._eidRegistered = ConchBlessing._eidRegistered or { } -- [type:id][native language] = text signature

local function resolveItemText(itemData)
    if type(itemData) ~= "table" then
        return nil, nil
    end

    local currentLang = getCurrentLang()
    local itemName = type(itemData.name) == "table"
        and (itemData.name[currentLang] or itemData.name.en)
        or itemData.name
    local itemDescription = type(itemData.description) == "table"
        and (itemData.description[currentLang] or itemData.description.en)
        or itemData.description
    return itemName, itemDescription
end

-- Use one localized path for real acquisitions and successful pedestal morphs.
-- Repentance+ routes this two-string overload through the same stacked streak
-- pool as pills/cards; keeping the existing overload also preserves older
-- runtimes where the optional stacking argument is unavailable.
ConchBlessing.EID.showItemText = function(itemData)
    local ok, shownOrError = pcall(function()
        local itemName, itemDescription = resolveItemText(itemData)
        if not itemName or not itemDescription then
            return false
        end

        local hud = Game():GetHUD()
        if not hud or type(hud.ShowItemText) ~= "function" then
            ConchBlessing.printDebug("HUD not available for ShowItemText")
            return false
        end

        hud:ShowItemText(itemName, itemDescription)
        return true
    end)
    if not ok then
        ConchBlessing.printError("[HUD] ShowItemText failed: " .. tostring(shownOrError))
        return false
    end
    return shownOrError == true
end

-- Internal variants such as urimal are not EID-native language codes. Keep a
-- deterministic native-language baseline and overlay only our own item entries
-- in EID's current native language. Never change EID's global language setting.
local NATIVE_LANGUAGES = {
    { source = "en", target = "en_us" },
    { source = "kr", target = "ko_kr" },
    { source = "ja", target = "ja_jp" },
    { source = "zh", target = "zh_cn" },
}

local function getEIDLanguage()
    local config = require("scripts.conch_blessing_config")
    if type(config.GetEIDLanguage) == "function" then return config.GetEIDLanguage() end
    -- Compatibility during a partial reload. Do not call EID:getLanguage():
    -- the provider can rewrite an invalid Config.Language while resolving it.
    local language = EID and EID.Config and EID.Config.Language
    if language and language ~= "auto" then
        for _, entry in ipairs(NATIVE_LANGUAGES) do
            if language == entry.target then return language end
        end
        if EID.descriptions and type(EID.descriptions[language]) == "table" then return language end
    end
    local gameLanguage = Options and Options.Language
    local gameMap = { kr = "ko_kr", jp = "ja_jp", ja = "ja_jp", zh = "zh_cn" }
    return gameMap[gameLanguage] or "en_us"
end

local function registrationLanguages()
    local active, effective = getEIDLanguage(), getCurrentLang()
    local languages, known = {}, {}
    local adapter = ConchBlessing.EID
    -- Retain visited native targets through a luamod reload, but never carry
    -- that bookkeeping to a replacement EID provider. Languages such as Polish
    -- have no Conch translation yet; their canonical base is English.
    if adapter._nativeLanguageProvider ~= EID then
        adapter._nativeLanguageProvider, adapter._extraNativeLanguages = EID, {}
    end
    for _, entry in ipairs(NATIVE_LANGUAGES) do
        known[entry.target] = true
        languages[#languages + 1] = {
            source = entry.target == active and effective or entry.source,
            target = entry.target,
        }
    end
    if not known[active] then adapter._extraNativeLanguages[active] = true end
    local extra = {}
    for target in pairs(adapter._extraNativeLanguages) do extra[#extra + 1] = target end
    table.sort(extra)
    for _, target in ipairs(extra) do
        languages[#languages + 1] = {
            source = target == active and effective or "en",
            target = target,
        }
    end
    return languages
end

local function extractText(field, langCode)
    if type(field) == "table" then field = field[langCode] or field.en end
    if type(field) == "table" then return table.concat(field, "\n") end
    return field
end

-- Type-prefixed keys keep a trinket and collectible sharing an ID separate.
-- The cache holds the actual registered text, so manual/date changes replace an
-- existing entry and leaving an override restores its canonical translation.
ConchBlessing.EID.addOptLangDescription = function(itemId, itemData)
    if not EID or type(EID.addCollectible) ~= "function" or type(EID.addTrinket) ~= "function" then return end
    if not itemData or not itemData.name or not itemData.eid then return end
    local isTrinket = itemData.type == "trinket"
    local regKey = (isTrinket and "T:" or "C:") .. tostring(itemId)
    local cache = ConchBlessing._eidRegistered
    cache[regKey] = cache[regKey] or {}
    for _, language in ipairs(registrationLanguages()) do
        local name = extractText(itemData.name, language.source)
        local description = extractText(itemData.eid, language.source)
        if name and description then
            local signature = name .. "\0" .. description
            if cache[regKey][language.target] ~= signature then
                if isTrinket then EID:addTrinket(itemId, description, name, language.target)
                else EID:addCollectible(itemId, description, name, language.target) end
                cache[regKey][language.target] = signature
            end
        end
    end
    ConchBlessing.EID[regKey] = {
        name = extractText(itemData.name, getCurrentLang()),
        description = extractText(itemData.eid, getCurrentLang()),
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

    local languages = registrationLanguages()

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
    local canRegisterSpecials = type(EID.CreateDescriptionTableIfMissing) == "function"
        and type(EID.addGoldenTrinketTable) == "function" and type(EID.descriptions) == "table"
    
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
        if data and data.type == "trinket" and data.id and data.id ~= -1 and data.specials and canRegisterSpecials then
            local specTop = data.specials
            
            -- Register for each supported language
            for _, language in ipairs(languages) do
                local langCode, targetEidLang = language.source, language.target
                local specLang = type(specTop[langCode]) == "table" and specTop[langCode]
                    or type(specTop.en) == "table" and specTop.en or nil
                
                local function pick(k)
                    if specLang and specLang[k] ~= nil then return specLang[k] end
                    return specTop[k]
                end
                local aVal = pick("append")
                local nVal = pick("normal")
                local mVal = pick("moms_box")
                local bVal = pick("both")

                if type(aVal) == "table" and #aVal > 0 then
                    -- Append mode: the golden/Mom's Box effect is an extra line rather
                    -- than a bigger number, so the base description stays as written.
                    -- EID reads this table as { golden, moms_box, both }.
                    local appended = {}
                    for i = 1, #aVal do appended[i] = tostring(aVal[i]) end
                    EID:CreateDescriptionTableIfMissing("goldenTrinketEffects", targetEidLang)
                    EID.descriptions[targetEidLang].goldenTrinketEffects[data.id] = appended
                    -- GoldenTrinketData is language-independent; register it once.
                    if targetEidLang == "en_us" then
                        EID:addGoldenTrinketTable(data.id, { append = true })
                    end
                    ConchBlessing.printDebug("[EID] Golden trinket append registered for " .. key .. " (" .. targetEidLang .. ")")
                elseif nVal ~= nil or mVal ~= nil or bVal ~= nil then
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
                        if targetEidLang == "en_us" then
                            EID:addGoldenTrinketTable(data.id, { fullReplace = true })
                        end
                        ConchBlessing.printDebug("[EID] Golden trinket fullReplace registered for " .. key .. " (" .. targetEidLang .. ")")
                    else
                        local num = tonumber(nVal)
                        if num then
                            -- Numeric multiplier (language-independent, only register once)
                            if targetEidLang == "en_us" then
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
                            if targetEidLang == "en_us" then
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

-- Registration is scoped to the provider object, registry and resolved language.
-- A reload can keep the ConchBlessing table alive, while a late EID load can replace
-- the provider object entirely. Neither can reuse another provider's text cache.
local registeredProvider, registeredItems, registeredSignature, registrationError
local registerItems = ConchBlessing.EID.registerAllItems
ConchBlessing.EID.registerAllItems = function()
    if not EID or type(EID.addCollectible) ~= "function" or type(EID.addTrinket) ~= "function" then return false end
    local provider, previousMod = EID, EID._currentMod
    local ok, err = pcall(registerItems)
    provider._currentMod = previousMod
    if not ok then
        if registrationError ~= tostring(err) then
            ConchBlessing.printError("[EID] Language registration failed: " .. tostring(err))
            registrationError = tostring(err)
        end
        return false
    end
    registrationError = nil
    return true
end

local function ensureDescriptionsRegistered(force)
    if not EID or type(EID.addCollectible) ~= "function" or type(EID.addTrinket) ~= "function" then return false end
    local specialsReady = type(EID.CreateDescriptionTableIfMissing) == "function"
        and type(EID.addGoldenTrinketTable) == "function" and type(EID.descriptions) == "table"
    local signature = getCurrentLang() .. ":" .. getEIDLanguage() .. ":" .. tostring(specialsReady)
    if not force and registeredProvider == EID and registeredItems == ConchBlessing.ItemData
        and registeredSignature == signature then return true end
    if registeredProvider ~= EID then ConchBlessing._eidRegistered = {} end
    if not ConchBlessing.EID.registerAllItems() then return false end
    registeredProvider, registeredItems, registeredSignature = EID, ConchBlessing.ItemData, signature
    ConchBlessing._eidDescriptionsRegistered = true
    return true
end

-- Also used by MCM and locale probes while the simulation is paused.
ConchBlessing.EID.refreshLanguage = function() return ensureDescriptionsRegistered(true) end
ensureDescriptionsRegistered()
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    ensureDescriptionsRegistered(true)
end)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    ensureDescriptionsRegistered()
end)
if ModCallbacks.MC_POST_RENDER then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        ensureDescriptionsRegistered()
    end)
end

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

        ConchBlessing.EID.showItemText(found)
    end
)
