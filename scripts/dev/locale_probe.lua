-- Locale test bench: `conch_locale` restarts the run, checks that every item's
-- text came from scripts/locale (both languages loaded, no icon token left,
-- every icon a real item), that EID holds and renders it in English and Korean
-- (descriptions, conch-mode lines, synergy lines and the live lines items add),
-- and that Mod Config Menu reads its text, then restarts the run again
-- (scripts/dev/test_bench.lua). EID's language is switched only for the checks
-- and put back right after them.
-- This file is dev tooling and only acts while its command runs.

local TestBench = require("scripts.dev.test_bench")

local Locale = ConchBlessing.Locale
local LANGUAGES = { "en", "kr" }
local EID_LANGUAGE = { en = "en_us", kr = "ko_kr" }
local TEXT_FIELDS = { "name", "description", "eid", "synergies", "specials" }

-- Items whose EID description gains a live line, and the template it uses.
local LIVE_LINES = {
    { item = "VOID_DAGGER", path = "ui.void_dagger.proc_chance" },
    { item = "TYRFING", path = "ui.tyrfing.accumulated_damage" },
    { item = "SEALED_DEMON_SWORD", path = "ui.sealed_demon_sword.remaining_kills" },
    { item = "INJECTABLE_STEROIDS", path = "ui.injectable_steroids.death_chance" },
}

local function eachString(value, fn)
    if type(value) == "string" then
        fn(value)
    elseif type(value) == "table" then
        for _, inner in pairs(value) do eachString(inner, fn) end
    end
end

local function eachItemText(fn)
    for key, data in pairs(ConchBlessing.ItemData) do
        for _, field in ipairs(TEXT_FIELDS) do
            eachString(data[field], function(text) fn(key, field, text) end)
        end
    end
end

local function describe(id)
    return EID:getDescriptionObj(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id).Description or ""
end

local function contains(text, part)
    return text:find(part, 1, true) ~= nil
end

local function listed(prefix, names)
    if #names == 0 then return "" end
    return ", " .. prefix .. ": " .. table.concat(names, " ")
end

local function build(plan)
    plan.section("load", nil)
    plan.check("both locale files load", function()
        local languages = table.concat(Locale.languages(), ", ")
        return languages == "en, kr", languages
    end)
    plan.check("the loader reported no problems", function()
        local count = #Locale.problems
        return count == 0, count == 0 and "none" or (count .. ", first: " .. Locale.problems[1])
    end)
    plan.check("every item has an English and a Korean name", function()
        local total, missing = 0, {}
        for key, data in pairs(ConchBlessing.ItemData) do
            total = total + 1
            if not (type(data.name) == "table" and data.name.en and data.name.kr) then missing[#missing + 1] = key end
        end
        return #missing == 0, total .. " items" .. listed("missing", missing)
    end)

    plan.section("icons", nil)
    plan.check("no icon token is left in item text", function()
        local left = {}
        eachItemText(function(key, field, text)
            for token in text:gmatch("{%a+:[^{}]+}") do left[#left + 1] = key .. "." .. field .. " " .. token end
        end)
        return #left == 0, #left == 0 and "none" or table.concat(left, ", ")
    end)
    plan.check("every icon in item text is a real item or card", function()
        local config = Isaac.GetItemConfig()
        local lookups = {
            Collectible = function(id) return config:GetCollectible(id) end,
            Trinket = function(id) return config:GetTrinket(id) end,
            Card = function(id) return config:GetCard(id) end,
        }
        local count, unknown = 0, {}
        eachItemText(function(key, _, text)
            for kind, id in text:gmatch("{{(%a+)(%d+)}}") do
                if lookups[kind] then
                    count = count + 1
                    if not lookups[kind](tonumber(id)) then unknown[#unknown + 1] = key .. ":" .. kind .. id end
                end
            end
        end)
        return #unknown == 0 and count > 0, count .. " icons" .. listed("unknown", unknown)
    end)

    plan.section("EID entries", nil)
    plan.check("EID holds every item's English and Korean text", function()
        if not EID then return nil, "EID is not installed" end
        local checked, wrong = 0, {}
        for key, data in pairs(ConchBlessing.ItemData) do
            if type(data.id) == "number" and data.id > 0 and type(data.eid) == "table" then
                local fullID = (data.type == "trinket" and "5.350." or "5.100.") .. data.id
                for _, lang in ipairs(LANGUAGES) do
                    local lines = data.eid[lang]
                    if lines then
                        checked = checked + 1
                        local text = type(lines) == "table" and table.concat(lines, "\n") or lines
                        local custom = EID.descriptions[EID_LANGUAGE[lang]] and EID.descriptions[EID_LANGUAGE[lang]].custom
                        local entry = custom and custom[fullID]
                        if not (entry and entry[2] == data.name[lang] and entry[3] == text) then
                            wrong[#wrong + 1] = key .. "/" .. lang
                        end
                    end
                end
            end
        end
        return #wrong == 0 and checked > 0, checked .. " entries" .. listed("wrong", wrong)
    end)

    plan.section("EID text by language", nil)
    plan.act(function(player, ctx)
        player:AddCollectible(ConchBlessing.ItemData.LIVE_EYE.id, 0, false)
        if EID then ctx.eidLanguage = EID.Config["Language"] end
    end)
    plan.wait(5)
    for _, lang in ipairs(LANGUAGES) do
        plan.act(function()
            if EID then EID.Config["Language"] = EID_LANGUAGE[lang] end
        end)
        plan.check(lang .. ": Live Eye's description is its locale text", function()
            if not EID then return nil, "EID is not installed" end
            local first = Locale.get("items.LIVE_EYE.eid", lang)[1]
            return describe(ConchBlessing.ItemData.LIVE_EYE.id):find(first, 1, true) == 1, first
        end)
        plan.check(lang .. ": Cronus base EID shows its live projectile-ignore chance", function()
            if not EID then return nil, "EID is not installed" end
            local template = Locale.get("items.CRONUS.eid", lang)[3]
            local chance = ConchBlessing.EIDDynamicTokens.CRONUS_BLOCK()
            local expected = template:gsub("%%CRONUS_BLOCK%%", function() return chance end)
            local description = describe(ConchBlessing.ItemData.CRONUS.id)
            return contains(description, expected) and not contains(description, "%CRONUS_BLOCK%"), expected
        end)
        plan.check(lang .. ": Dead Eye shows the conch-mode line for Live Eye", function()
            if not EID then return nil, "EID is not installed" end
            local data = ConchBlessing.ItemData.LIVE_EYE
            local template = ConchBlessing._conchModeTemplates[lang][data.flag]
            local line = "#{{ConchMode}} " .. (template:gsub("{{item_name}}", "{{icon_live_eye}}(" .. data.name[lang] .. ")"))
            return contains(describe(CollectibleType.COLLECTIBLE_DEAD_EYE), line), line
        end)
        plan.check(lang .. ": Rock Bottom shows Live Eye's synergy line", function()
            if not EID then return nil, "EID is not installed" end
            local line = Locale.expandIcons(Locale.get("items.LIVE_EYE.synergies.rock_bottom", lang))
            return contains(describe(CollectibleType.COLLECTIBLE_ROCK_BOTTOM), line), line
        end)
        for _, live in ipairs(LIVE_LINES) do
            plan.check(lang .. ": " .. live.item .. " adds its live line", function()
                if not EID then return nil, "EID is not installed" end
                local template = Locale.get(live.path, lang)
                local prefix = template:sub(1, template:find("%s", 1, true) - 1)
                return contains(describe(ConchBlessing.ItemData[live.item].id), prefix), prefix
            end)
        end
        plan.check(lang .. ": UTILITY_BELT adds its slot status", function(player)
            if not EID then return nil, "EID is not installed" end
            local text = describe(ConchBlessing.ItemData.UTILITY_BELT.id)
            local primary = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            local options = {
                Locale.textIn(lang, "ui.utility_belt.pocket_full"),
                Locale.textIn(lang, "ui.utility_belt.no_active"),
                Locale.textIn(lang, "ui.utility_belt.will_move", "{{Collectible" .. tostring(primary) .. "}}"),
            }
            for _, option in ipairs(options) do
                if contains(text, option) then return true, option end
            end
            return false, "none of the three status lines"
        end)
    end
    plan.act(function(_, ctx)
        if EID and ctx.eidLanguage then EID.Config["Language"] = ctx.eidLanguage end
    end)
    plan.check("EID's language is back to the player's setting", function(_, ctx)
        if not EID then return nil, "EID is not installed" end
        return EID.Config["Language"] == ctx.eidLanguage, tostring(EID.Config["Language"])
    end)

    plan.section("Mod Config Menu", nil)
    plan.check("the menu reads its text from en.lua", function()
        if not (ModConfigMenu and type(ModConfigMenu.MenuData) == "table") then
            return nil, "Mod Config Menu is not installed"
        end
        local category
        for _, entry in pairs(ModConfigMenu.MenuData) do
            if type(entry) == "table" and type(entry.Name) == "string" and entry.Name:find("Conch's Blessing v", 1, true) == 1 then
                category = entry
            end
        end
        if not category then return false, "Conch's Blessing category not found" end
        local state = Locale.textIn("en", ConchBlessing.Config.debugMode and "ui.mcm.on" or "ui.mcm.off")
        local expected = Locale.textIn("en", "ui.mcm.debug_mode", state)
        local general = Locale.textIn("en", "ui.mcm.tab_general")
        for _, sub in ipairs(category.Subcategories or {}) do
            if sub.Name == general then
                for _, option in ipairs(sub.Options or {}) do
                    if type(option.Display) == "function" and option.Display() == expected then
                        return true, general .. " / " .. expected
                    end
                end
            end
        end
        return false, "no option shows " .. expected
    end)

    plan.section("pickup banner", "the item banner reads Live Eye / Misses happen, in Korean when the game or EID language is Korean")
    plan.check("the banner takes its text from the locale", function()
        local shown = ConchBlessing.EID.showItemText(ConchBlessing.ItemData.LIVE_EYE)
        return shown == true, "HUD:ShowItemText " .. tostring(shown)
    end)
    plan.wait(90)
end

TestBench.register({
    command = "conch_locale",
    tag = "LocaleProbe",
    duration = "about 5 seconds",
    build = build,
})

return {}
