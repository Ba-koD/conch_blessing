-- Locale test bench: `conch_test locale` restarts the run, checks that every item's
-- text came from scripts/locale (all three languages loaded, no icon token left,
-- every icon a real item), that EID holds and renders the selected mod locale
-- (descriptions, conch-mode lines, synergy lines and the live lines items add),
-- and that Mod Config Menu reads its text, then restarts the run again
-- (scripts/dev/test_bench.lua). Only this mod's language preference is switched;
-- EID's native/global language remains untouched. Cleanup also restores the
-- preference and registered descriptions after cancellation or a failed step.
-- This file is dev tooling and only acts while its command runs.

local TestBench = require("scripts.dev.test_bench")
local Config = require("scripts.conch_blessing_config")

local Locale = ConchBlessing.Locale
local LANGUAGES = { "en", "kr", "urimal" }
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

local function refreshLanguage()
    if EID and ConchBlessing.EID and type(ConchBlessing.EID.refreshLanguage) == "function" then
        ConchBlessing.EID.refreshLanguage()
    end
end

local function rememberLanguage(ctx)
    ctx.languageSelection = Config.GetSelectedLanguage()
    ctx.eidProvider = EID
    ctx.eidConfig = EID and EID.Config
    ctx.eidUserConfig = EID and EID.UserConfig
    ctx.eidLanguage = ctx.eidConfig and ctx.eidConfig.Language
    ctx.eidUserLanguage = ctx.eidUserConfig and ctx.eidUserConfig.Language
    ctx.languageSaved = true
end

local function restoreLanguage(ctx)
    if not ctx.languageSaved then return end
    assert(Config.SetLanguage(ctx.languageSelection), "could not restore the original language preference")
    refreshLanguage()
end

local function eidLanguageUnchanged(ctx)
    if not ctx.eidProvider then return true, "EID was not installed when the test started" end
    return ctx.eidProvider.Config == ctx.eidConfig and ctx.eidProvider.UserConfig == ctx.eidUserConfig
        and (not ctx.eidConfig or ctx.eidConfig.Language == ctx.eidLanguage)
        and (not ctx.eidUserConfig or ctx.eidUserConfig.Language == ctx.eidUserLanguage),
        "EID Config.Language=" .. tostring(ctx.eidConfig and ctx.eidConfig.Language)
            .. "; UserConfig.Language=" .. tostring(ctx.eidUserConfig and ctx.eidUserConfig.Language)
end

local function build(plan)
    plan.section("load", nil)
    plan.act(function(_, ctx) rememberLanguage(ctx) end)
    plan.check("English, Korean and Urimal locale files load", function()
        local languages = table.concat(Locale.languages(), ", ")
        return languages == "en, kr, urimal", languages
    end)
    plan.check("the loader reported no problems", function()
        local count = #Locale.problems
        return count == 0, count == 0 and "none" or (count .. ", first: " .. Locale.problems[1])
    end)
    plan.check("every item has a name from each explicit locale file", function()
        local total, missing = 0, {}
        for key, data in pairs(ConchBlessing.ItemData) do
            total = total + 1
            for _, lang in ipairs(LANGUAGES) do
                local source = Locale.tables[lang] and Locale.tables[lang].items[key]
                if not (type(data.name) == "table" and source and type(source.name) == "string"
                    and data.name[lang] == source.name) then missing[#missing + 1] = key .. "/" .. lang end
            end
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

    plan.section("EID text by language", nil)
    plan.act(function(player)
        player:AddCollectible(ConchBlessing.ItemData.LIVE_EYE.id, 0, false)
    end)
    plan.wait(5)
    for _, lang in ipairs({ "en", "kr", "urimal", "kr_standard" }) do
        plan.act(function(_, ctx)
            assert(Config.SetLanguage(lang), "could not select locale " .. lang)
            refreshLanguage()
            -- October 9 intentionally resolves a Korean preference to Urimal.
            -- The standard preference also exercises Korean's rendered entries
            -- on that date, without changing or mocking the PC calendar.
            ctx.localeLanguage = Config.GetCurrentLanguage()
        end)
        plan.check(lang .. ": selected and effective language resolve", function(_, ctx)
            return Config.GetSelectedLanguage() == lang and Locale.tables[ctx.localeLanguage] ~= nil
                and (lang ~= "kr_standard" or ctx.localeLanguage == "kr"),
                "selected=" .. Config.GetSelectedLanguage() .. "; effective=" .. ctx.localeLanguage
        end)
        plan.check(lang .. ": EID's global language stays unchanged", function(_, ctx)
            return eidLanguageUnchanged(ctx)
        end)
        plan.check(lang .. ": EID holds every item's effective locale text", function(_, ctx)
            if not EID then return nil, "EID is not installed" end
            local native = Config.GetEIDLanguage()
            local language = ctx.localeLanguage
            local checked, wrong = 0, {}
            local custom = EID.descriptions[native] and EID.descriptions[native].custom
            for key, data in pairs(ConchBlessing.ItemData) do
                if type(data.id) == "number" and data.id > 0 and type(data.eid) == "table" then
                    local fullID = (data.type == "trinket" and "5.350." or "5.100.") .. data.id
                    local lines = data.eid[language]
                    local entry = custom and custom[fullID]
                    checked = checked + 1
                    local text = type(lines) == "table" and table.concat(lines, "\n") or lines
                    if not (entry and entry[2] == data.name[language] and entry[3] == text) then
                        wrong[#wrong + 1] = key .. "/" .. language
                    end
                end
            end
            return #wrong == 0 and checked > 0,
                checked .. " entries in " .. native .. "; effective=" .. language .. listed("wrong", wrong)
        end)
        plan.check(lang .. ": Live Eye's description is its locale text", function(_, ctx)
            if not EID then return nil, "EID is not installed" end
            local first = Locale.get("items.LIVE_EYE.eid", ctx.localeLanguage)[1]
            return describe(ConchBlessing.ItemData.LIVE_EYE.id):find(first, 1, true) == 1, first
        end)
        plan.check(lang .. ": Kronos base EID shows its live projectile-ignore chance", function(_, ctx)
            if not EID then return nil, "EID is not installed" end
            local template = Locale.get("items.KRONOS.eid", ctx.localeLanguage)[3]
            local chance = ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK()
            local expected = template:gsub("%%KRONOS_BLOCK%%", function() return chance end)
            local description = describe(ConchBlessing.ItemData.KRONOS.id)
            return contains(description, expected) and not contains(description, "%KRONOS_BLOCK%"), expected
        end)
        plan.check(lang .. ": Dead Eye shows the conch-mode line for Live Eye", function(_, ctx)
            if not EID then return nil, "EID is not installed" end
            local data = ConchBlessing.ItemData.LIVE_EYE
            local template = ConchBlessing._conchModeTemplates[ctx.localeLanguage][data.flag]
            local line = "#{{ConchMode}} " .. (template:gsub("{{item_name}}", "{{icon_live_eye}}(" .. data.name[ctx.localeLanguage] .. ")"))
            return contains(describe(CollectibleType.COLLECTIBLE_DEAD_EYE), line), line
        end)
        plan.check(lang .. ": Rock Bottom shows Live Eye's synergy line", function(_, ctx)
            if not EID then return nil, "EID is not installed" end
            local line = Locale.expandIcons(Locale.get("items.LIVE_EYE.synergies.rock_bottom", ctx.localeLanguage))
            return contains(describe(CollectibleType.COLLECTIBLE_ROCK_BOTTOM), line), line
        end)
        for _, live in ipairs(LIVE_LINES) do
            plan.check(lang .. ": " .. live.item .. " adds its live line", function(_, ctx)
                if not EID then return nil, "EID is not installed" end
                local template = Locale.get(live.path, ctx.localeLanguage)
                local prefix = template:sub(1, template:find("%s", 1, true) - 1)
                return contains(describe(ConchBlessing.ItemData[live.item].id), prefix), prefix
            end)
        end
        plan.check(lang .. ": UTILITY_BELT adds its slot status", function(player, ctx)
            if not EID then return nil, "EID is not installed" end
            local text = describe(ConchBlessing.ItemData.UTILITY_BELT.id)
            local primary = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            local options = {
                Locale.textIn(ctx.localeLanguage, "ui.utility_belt.pocket_full"),
                Locale.textIn(ctx.localeLanguage, "ui.utility_belt.no_active"),
                Locale.textIn(ctx.localeLanguage, "ui.utility_belt.will_move", "{{Collectible" .. tostring(primary) .. "}}"),
            }
            for _, option in ipairs(options) do
                if contains(text, option) then return true, option end
            end
            return false, "none of the three status lines"
        end)
    end
    plan.act(function(_, ctx)
        restoreLanguage(ctx)
    end)
    plan.check("the original mod language preference is restored", function(_, ctx)
        return Config.GetSelectedLanguage() == ctx.languageSelection, Config.GetSelectedLanguage()
    end)
    plan.check("EID's global language still matches the player's setting", function(_, ctx)
        return eidLanguageUnchanged(ctx)
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

    plan.section("pickup banner", "the item banner uses the restored mod language, including October 9's Korean-to-Urimal rule")
    plan.check("the banner takes its text from the locale", function()
        local shown = ConchBlessing.EID.showItemText(ConchBlessing.ItemData.LIVE_EYE)
        return shown == true, "HUD:ShowItemText " .. tostring(shown)
    end)
    plan.wait(90)
end

TestBench.register({
    command = "conch_test locale",
    tag = "LocaleProbe",
    duration = "about 5 seconds",
    cleanup = restoreLanguage,
    build = build,
})

return {}
