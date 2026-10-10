-- Shared, read-only screen-space presentation for Conch's answer items.
local V = {}
local font, attempted
local icons, warned = {}, {}
V.colors = { positive = {0.65, 1, 0.78}, neutral = {0.9, 0.86, 0.7}, negative = {1, 0.58, 0.62} }
function V.warn(key, detail)
    if warned[key] then return end
    warned[key] = true
    ConchBlessing.printError("[ConchAnswer] " .. key .. ": " .. tostring(detail))
end
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function V.usage(api, preview)
    if type(api.GetCurrentRoomUsage) == "function" then
        local ok, n = pcall(api.GetCurrentRoomUsage)
        if ok and finite(n) and n >= 0 then return math.floor(n) end
    end
    local n = preview and preview.usageCount
    return finite(n) and n >= 0 and math.floor(n) or nil
end
function V.anchor(api, config, width, rows)
    local w, h = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    -- GetResultPosition describes the transient popup, NOT the persistent
    -- bottom-right status. The installed provider renders that status directly
    -- from iconX/Y (type at Y-30, usage at X+10). Follow it read-only.
    local x = finite(config.iconX) and config.iconX or 430
    local y = finite(config.iconY) and config.iconY or 265
    local usage = api and V.usage(api) or 0
    local limit = finite(config.attemptsPerRoom) and config.attemptsPerRoom or 0
    local counter = tostring(usage or 0) .. "/" .. (limit == 0 and "INF" or tostring(limit))
    local right = math.min(w - 8, x + math.max(Isaac.GetTextWidth("negative"), 10 + Isaac.GetTextWidth(counter)))
    local top = y - 44 - ((rows or 1) - 1) * 12
    return math.max(24, right - width), math.max(4, math.min(h - 40, top)), "status_icon"
end
local function getFont()
    if not attempted then
        attempted = true
        local ok, value = pcall(function()
            local f = Font(); f:Load("font/cjk/lanapixel.fnt")
            assert(f:IsLoaded() and type(f.DrawStringScaledUTF8) == "function" and type(f.GetStringWidthUTF8) == "function")
            return f
        end)
        if ok then font = value else V.warn("FONT_FALLBACK", value) end
    end
    return font
end
function V.text(key, ...)
    if getFont() then return ConchBlessing.Locale.text(key, ...) end
    return ConchBlessing.Locale.textIn("en", key, ...)
end
local function width(s) return font and font:GetStringWidthUTF8(s) or Isaac.GetTextWidth(s) end
local function draw(s, x, y, scale, rgb)
    for _, offset in ipairs({1, 0}) do
        local c = offset == 1 and {0, 0, 0} or rgb
        if font then font:DrawStringScaledUTF8(s, x+offset, y+offset, scale, scale, KColor(c[1],c[2],c[3],1),0,false)
        else Isaac.RenderText(s, x+offset, y+offset,c[1],c[2],c[3],1) end
    end
end
local function icon(path)
    if icons[path] == nil then
        local ok, value = pcall(function()
            local s = Sprite(); s:Load("gfx/005.100_collectible.anm2", true)
            s:ReplaceSpritesheet(1, "gfx/items/collectibles/" .. path .. ".png")
            s:LoadGraphics(); s:SetFrame("Idle", 0)
            assert(s:IsLoaded() and type(s.RenderLayer) == "function")
            s.Scale = Vector(0.5, 0.5); return s
        end)
        icons[path] = ok and value or false
        if not ok then V.warn("ICON_UNAVAILABLE", value) end
    end
    return icons[path]
end
function V.render(rows)
    local hud = Game():GetHUD()
    if hud and type(hud.IsVisible) == "function" and not hud:IsVisible() then return end
    getFont()
    local provider = rawget(_G, "MagicConch")
    if not provider then return end
    local maxWidth = math.min(210, Isaac.GetScreenWidth() - 40)
    for i, row in ipairs(rows) do
        local scale = font and math.min(0.65, maxWidth / math.max(1, width(row.text))) or 1
        local x, y = V.anchor(provider.API, provider.Config or {}, width(row.text) * scale, #rows)
        y = y + (i - 1) * 12
        draw(row.text, x, y, scale, V.colors[row.kind] or {0.8,0.8,0.8})
        if row.icon then
            local s = icon(row.icon)
            if s then s:RenderLayer(1, Vector(x-10,y+12)) end
        end
    end
end
return V
