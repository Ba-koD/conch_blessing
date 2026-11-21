local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Dev-only: `cb test locale icons` (run by name only) follows
-- every description EID would show for our items, cards and runes in EID's
-- current language the way EID draws them (markup expansion, line wrapping at
-- the configured width, colour parts, then each {{...}} icon), and does the
-- same for some vanilla items as a control. It reports icon markup EID does not
-- know (drawn as its ERROR icon), markup the line wrapping cuts in two (drawn
-- as text), icon sprites that are not loaded, and characters EID's current
-- font has no glyph for. It also compares our raw English and Korean entries.
-- Our descriptions are checked; the vanilla control is only measured. It
-- changes no language, setting or item. The glyph check reads EID's current
-- font, so the English entries are judged against that font too.
local TestBench = require("scripts.dev.test_bench")

local LIST_CAP = 40

local function utf8Chars(text)
    return text:gmatch("[\xC2-\xF4][\x80-\xBF]*")
end

local function newResult()
    return { descriptions = 0, icons = 0, unknown = {}, split = {}, unloaded = {}, glyphs = {}, glyphOrder = {} }
end

local function add(list, entry)
    list[#list + 1] = entry
end

local function spriteOf(lookup)
    local sprite = lookup[7]
    if type(sprite) == "function" then sprite = sprite() end
    return sprite or EID.InlineIconSprite
end

local function language()
    return EID:getLanguage()
end

-- The lines EID prints for a description: printBulletPoints' markup passes,
-- then fitTextToWidth at the configured width.
local function wrappedLines(text)
    local width = tonumber(EID.Config.TextboxWidth) or 130
    local breakUtf8 = EID.BreakUtf8CharsLanguage and EID.BreakUtf8CharsLanguage[language()]
    text = EID:replaceNameMarkupStrings(text)
    text = EID:replaceShortMarkupStrings(text)
    if type(EID.replaceMarkupSize) == "function" then text = EID:replaceMarkupSize(text) end
    local lines = {}
    for line in text:gmatch("([^#]+)") do
        local edited = EID:handleTextIndentation(line)
        for _, wrapped in ipairs(EID:fitTextToWidth(edited, width, breakUtf8)) do lines[#lines + 1] = wrapped end
    end
    return lines
end

local function scanLine(result, where, line)
    for _, part in ipairs(EID:filterColorMarkup(line, KColor(1, 1, 1, 1))) do
        local text = part[1] or ""
        for word in text:gmatch("{{.-}}") do
            result.icons = result.icons + 1
            local lookup = EID:getIcon(word)
            if type(lookup) ~= "table" or lookup[1] == "ERROR" then
                add(result.unknown, where .. " " .. word)
            else
                local sprite = spriteOf(lookup)
                if sprite == nil or (type(sprite.IsLoaded) == "function" and not sprite:IsLoaded()) then
                    add(result.unloaded, where .. " " .. word)
                end
            end
        end
        local rest = text:gsub("{{.-}}", "")
        if rest:find("{{", 1, true) or rest:find("}}", 1, true) then add(result.split, where .. " [" .. text .. "]") end
        for ch in utf8Chars(rest) do
            if ch ~= "\xC2\xA4" and EID:getStrWidth(ch) <= 0 and not result.glyphs[ch] then
                result.glyphs[ch] = where
                add(result.glyphOrder, ch)
            end
        end
    end
end

local function scanDescription(result, where, obj)
    result.descriptions = result.descriptions + 1
    local name = (obj.Name or "") .. (obj.ModName and EID:getModNameString(obj) or "")
    scanLine(result, where .. " name", EID:replaceShortMarkupStrings(name))
    for i, line in ipairs(wrappedLines(obj.Description or "")) do scanLine(result, where .. " L" .. i, line) end
end

local function scanText(result, where, text)
    result.descriptions = result.descriptions + 1
    for i, line in ipairs(wrappedLines(text or "")) do scanLine(result, where .. " L" .. i, line) end
end

local function ours()
    local list = {}
    for key, row in pairs(ConchBlessing.ItemData or {}) do
        if type(row.id) == "number" and row.id > 0 then
            list[#list + 1] = { key = key, variant = row.type == "trinket" and PickupVariant.PICKUP_TRINKET
                or PickupVariant.PICKUP_COLLECTIBLE, id = row.id }
        end
    end
    for key, row in pairs(ConchBlessing.PocketData or {}) do
        if type(row.id) == "number" and row.id > 0 then
            list[#list + 1] = { key = key, variant = PickupVariant.PICKUP_TAROTCARD, id = row.id }
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

local function vanilla()
    local config, list = Isaac.GetItemConfig(), {}
    for id = 1, 40 do
        if config:GetCollectible(id) then list[#list + 1] = { key = "c" .. id, variant = PickupVariant.PICKUP_COLLECTIBLE, id = id } end
    end
    for id = 1, 15 do
        if config:GetTrinket(id) then list[#list + 1] = { key = "t" .. id, variant = PickupVariant.PICKUP_TRINKET, id = id } end
    end
    for id = 1, 10 do list[#list + 1] = { key = "card" .. id, variant = PickupVariant.PICKUP_TAROTCARD, id = id } end
    return list
end

local function capped(list)
    if #list == 0 then return "none" end
    local shown = {}
    for i = 1, math.min(#list, LIST_CAP) do shown[i] = list[i] end
    return table.concat(shown, " | ") .. (#list > LIST_CAP and (" | ... " .. (#list - LIST_CAP) .. " more") or "")
end

local function summary(result)
    return string.format("%d descriptions, %d icon markups, %d unknown, %d cut by wrapping, %d sprites not loaded, %d characters without a glyph",
        result.descriptions, result.icons, #result.unknown, #result.split, #result.unloaded, #result.glyphOrder)
end

local function glyphs(result)
    local shown = {}
    for i, ch in ipairs(result.glyphOrder) do
        if i > LIST_CAP then break end
        shown[#shown + 1] = ch .. "(" .. result.glyphs[ch] .. ")"
    end
    return #shown == 0 and "none" or table.concat(shown, " ")
end

local function customEntry(lang, variant, id)
    local tableName = variant == PickupVariant.PICKUP_TRINKET and "trinkets"
        or variant == PickupVariant.PICKUP_TAROTCARD and "cards" or "collectibles"
    local custom = EID.descriptions and EID.descriptions[lang] and EID.descriptions[lang].custom
    local entry = custom and custom["5." .. variant .. "." .. id]
    if type(entry) == "table" then return entry[3] end
    local legacy = EID.descriptions and EID.descriptions[lang] and EID.descriptions[lang][tableName]
    return legacy and type(legacy[id]) == "table" and legacy[id][3] or nil
end

local function build(plan)
    plan.section("EID icons", "measurements; the screen itself is not checked")
    plan.require("EID is installed", function()
        if not EID then return nil, "EID is not installed" end
        return true, tostring(EID.ModVersion or "?")
    end)
    plan.note("languages", function()
        local config = require("scripts.conch_blessing_config")
        return string.format("EID %s (Config.Language=%s, game %s), ours %s, font %s, textbox %s, markup %s, bulletpoints %s",
            language(), tostring(EID.Config.Language), tostring(Options and Options.Language),
            tostring(config.GetCurrentLanguage()), tostring(EID.Config.FontType), tostring(EID.Config.TextboxWidth),
            tostring(EID.Config.MarkupSize), tostring(EID.Config.StatAndPickupBulletpoints))
    end)
    plan.act(function(_, ctx)
        ctx.ours, ctx.vanilla, ctx.rawEn, ctx.rawKr = newResult(), newResult(), newResult(), newResult()
        for _, entry in ipairs(ours()) do
            local obj = EID:getDescriptionObj(EntityType.ENTITY_PICKUP, entry.variant, entry.id)
            scanDescription(ctx.ours, entry.key, obj)
            local en, kr = customEntry("en_us", entry.variant, entry.id), customEntry("ko_kr", entry.variant, entry.id)
            if en then scanText(ctx.rawEn, entry.key, en) end
            if kr then scanText(ctx.rawKr, entry.key, kr) end
        end
        for _, entry in ipairs(vanilla()) do
            scanDescription(ctx.vanilla, entry.key, EID:getDescriptionObj(EntityType.ENTITY_PICKUP, entry.variant, entry.id))
        end
        local underdog = ConchBlessing.ItemData.UNDERDOG
        local obj = underdog and EID:getDescriptionObj(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, underdog.id)
        ctx.sample = obj and table.concat(wrappedLines(obj.Description or ""), " / ") or "none"
        ctx.sampleName = obj and ((obj.Name or "") .. EID:getModNameString(obj)) or "none"
    end)
    for _, group in ipairs({ { "ours", "our items, cards and runes as EID shows them now" },
        { "vanilla", "vanilla control" }, { "rawEn", "our raw en_us entries" }, { "rawKr", "our raw ko_kr entries" } }) do
        local key, label = group[1], group[2]
        plan.note(label, function(_, ctx) return summary(ctx[key]) end)
        plan.note(label .. ": unknown icons", function(_, ctx) return capped(ctx[key].unknown) end)
        plan.note(label .. ": markup cut by wrapping", function(_, ctx) return capped(ctx[key].split) end)
        plan.note(label .. ": sprites not loaded", function(_, ctx) return capped(ctx[key].unloaded) end)
        plan.note(label .. ": characters without a glyph", function(_, ctx) return glyphs(ctx[key]) end)
    end
    plan.check("EID knows every icon in our descriptions", function(_, ctx)
        return #ctx.ours.unknown == 0, capped(ctx.ours.unknown)
    end)
    plan.check("line wrapping cuts no icon markup in our descriptions", function(_, ctx)
        return #ctx.ours.split == 0, capped(ctx.ours.split)
    end)
    plan.check("every icon sprite in our descriptions is loaded", function(_, ctx)
        return #ctx.ours.unloaded == 0, capped(ctx.ours.unloaded)
    end)
    plan.check("EID's font has a glyph for every character in our descriptions", function(_, ctx)
        return #ctx.ours.glyphOrder == 0 and #ctx.rawEn.glyphOrder == 0 and #ctx.rawKr.glyphOrder == 0,
            "shown " .. glyphs(ctx.ours) .. "; en_us " .. glyphs(ctx.rawEn) .. "; ko_kr " .. glyphs(ctx.rawKr)
    end)
    plan.note("Underdog name line", function(_, ctx) return ctx.sampleName end)
    plan.note("Underdog lines as wrapped", function(_, ctx) return ctx.sample end)
end

TestBench.register({ command = "cb test locale icons", tag = "LocaleProbe", duration = "about 2 seconds",
    build = build })

return {}
