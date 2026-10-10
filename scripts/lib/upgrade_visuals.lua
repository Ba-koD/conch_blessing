-- Pure presentation shared by real upgrades and conch_morph. Never spawn an
-- entity: vanilla fire, explosions and Holy Light have native combat behaviour.
local Visuals = { catalog = require("scripts.upgrade_visual_catalog") }
local profiles = {}
for _, row in ipairs(Visuals.catalog) do profiles[row.key] = row end
local PI = math.pi
local function clamp(x) return math.max(0, math.min(1, x)) end
local function ease(a, b, x)
    local p = clamp((x - a) / (b - a))
    return p * p * (3 - 2 * p)
end
local function point(x, y) return Vector(x, y) end
local function color(r, g, b, a, add) return Color(r, g, b, a or 1, add or 0, add or 0, add or 0) end
local WHITE = { 1, 1, 1 }
local GOLD = { 1, 0.84, 0.43 }
local BLUE = { 0.65, 0.85, 1 }
local RED = { 0.95, 0.28, 0.24 }
local function tint(rgb, alpha) return color(rgb[1], rgb[2], rgb[3], clamp(alpha or 1)) end

local function sprite(path, animation, sheet)
    -- Sprite is a callable table on some supported builds.
    local s = Sprite()
    s:Load(path, true)
    if s.IsLoaded and not s:IsLoaded() then error("could not load " .. path) end
    if sheet then s:ReplaceSpritesheet(0, sheet); s:LoadGraphics() end
    s:SetFrame(animation or "Idle", 0)
    return s
end
local function asset(scene, name)
    if not scene.assets[name] then
        scene.assets[name] = sprite("gfx/effects/conch_upgrade_" .. name .. ".anm2")
    end
    return scene.assets[name]
end
local function native(scene, name, path, animation)
    if not scene.assets[name] then scene.assets[name] = sprite(path, animation) end
    return scene.assets[name]
end
local function draw(s, x, y, sx, sy, c, rotation)
    s.Scale = point(sx or 1, sy or sx or 1)
    s.Color = c or color(1, 1, 1, 1)
    s.Rotation = rotation or 0
    s:Render(point(x, y))
end
local function line(scene, x1, y1, x2, y2, rgb, alpha, width)
    local dx, dy = x2 - x1, y2 - y1
    draw(asset(scene, "pixel"), x1, y1, math.sqrt(dx * dx + dy * dy), width or 1,
        tint(rgb, alpha), math.deg(math.atan(dy, dx)))
end
local function ring(scene, x, y, radius, rgb, alpha, squash)
    for i = 0, 23 do
        local a, b = i * PI / 12, (i + 1) * PI / 12
        line(scene, x + math.cos(a) * radius, y + math.sin(a) * radius * (squash or 1),
            x + math.cos(b) * radius, y + math.sin(b) * radius * (squash or 1), rgb, alpha)
    end
end
local function star(scene, x, y, size, rgb, alpha)
    line(scene, x - size, y, x + size, y, rgb, alpha)
    line(scene, x, y - size, x, y + size, rgb, alpha)
end

function Visuals.profile(key) return profiles[key] end
function Visuals.isApplied(key) return profiles[key] ~= nil and profiles[key].effect ~= nil end
function Visuals.resolveKey(text)
    local normalized = string.lower(text or ""):gsub("[_%s%-]", "")
    for _, row in ipairs(Visuals.catalog) do
        if string.lower(row.key):gsub("_", "") == normalized then return row.key end
    end
end

function Visuals.config(variant, id)
    local config = Isaac.GetItemConfig()
    if variant == PickupVariant.PICKUP_TRINKET then return config:GetTrinket(id % 32768) end
    return config:GetCollectible(id)
end

function Visuals.origin(item)
    local origin = item.origin
    local id = type(origin) == "table" and (origin.id or origin.name) or origin
    local kind = type(origin) == "table" and origin.type or item.type
    local variant = kind == "trinket" and PickupVariant.PICKUP_TRINKET or PickupVariant.PICKUP_COLLECTIBLE
    if type(id) == "string" then
        id = variant == PickupVariant.PICKUP_TRINKET and Isaac.GetTrinketIdByName(id) or Isaac.GetItemIdByName(id)
    end
    return variant, id
end

function Visuals.icon(variant, id)
    local config = Visuals.config(variant, id)
    assert(config and config.GfxFileName and config.GfxFileName ~= "", "missing item art: " .. tostring(id))
    return sprite("gfx/effects/conch_upgrade_icon.anm2", "Idle", config.GfxFileName)
end

function Visuals.create(key, pos, sourceVariant, sourceId, startFrame)
    local item = assert(ConchBlessing.ItemData[key], "unknown morph item")
    local profile = assert(profiles[key], "missing morph profile")
    local targetVariant = item.type == "trinket" and PickupVariant.PICKUP_TRINKET or PickupVariant.PICKUP_COLLECTIBLE
    if not sourceVariant then sourceVariant, sourceId = Visuals.origin(item) end
    local scene = {
        key = key, profile = profile, flag = item.flag,
        pos = point(pos.X, pos.Y), frame = startFrame or 0,
        impact = profile.impact or 60, duration = profile.effect and 102 or 120,
        sourceVariant = sourceVariant, targetVariant = targetVariant,
        before = Visuals.icon(sourceVariant, sourceId), after = Visuals.icon(targetVariant, item.id),
        assets = {}, sounded = {}, floorCells = {},
    }
    -- Probe required primitives before a real pickup is hidden.
    asset(scene, "pixel")
    local effect = profile.effect
    if effect == "void" or effect == "purify" then asset(scene, "smoke") end
    if effect == "fire" or effect == "ice" then asset(scene, effect) end
    if effect == "rain" or effect == "clock_rain" then
        asset(scene, "floor")
        local room = Game():GetRoom()
        for i = 0, room:GetGridSize() - 1 do
            local p = room:GetGridPosition(i)
            if room:IsPositionInRoom(point(p.X - 19, p.Y - 19), 0)
                and room:IsPositionInRoom(point(p.X + 19, p.Y + 19), 0) then
                scene.floorCells[#scene.floorCells + 1] = point(p.X, p.Y)
            end
        end
    end
    return scene
end

local function soundOnce(scene, name, at, volume)
    if scene.frame < at or scene.sounded[name] then return end
    scene.sounded[name] = true
    local id = SoundEffect and SoundEffect[name]
    if id then SFXManager():Play(id, volume or 0.5, 0, false, 1) end
end

function Visuals.update(scene)
    scene.frame = math.min(scene.duration, scene.frame + 1)
    local effect = scene.profile.effect
    if effect == "lightning" then soundOnce(scene, "SOUND_REDLIGHTNING_ZAP", scene.impact, 0.6) end
    if effect == "missile" then
        soundOnce(scene, "SOUND_ROCKET_BLAST_DEATH", 27, 0.4)
        soundOnce(scene, "SOUND_BOSS1_EXPLOSIONS", scene.impact, 0.6)
        if scene.frame >= scene.impact and not scene.shook then
            scene.shook = true
            if Game().ShakeScreen then Game():ShakeScreen(9) end
        end
    end
    if effect == "purify" or (not effect and scene.flag == "positive") then
        soundOnce(scene, "SOUND_HOLY", scene.impact, 0.35)
    end
end

local function clock(scene, x, y, alpha)
    ring(scene, x, y, 29, GOLD, alpha * 0.7)
    for i = 0, 11 do
        local a = i * PI / 6 - PI / 2
        line(scene, x + math.cos(a) * 25, y + math.sin(a) * 25,
            x + math.cos(a) * 28, y + math.sin(a) * 28, GOLD, alpha)
    end
    local a = math.floor(scene.frame / 9) * PI / 3 - PI / 2
    line(scene, x, y, x + math.cos(a) * 23, y + math.sin(a) * 23, GOLD, alpha, 2)
end

function Visuals.renderFloor(scene)
    if #scene.floorCells == 0 then return end
    local f = scene.frame
    local alpha = ease(10, 57, f) * (1 - ease(76, 102, f)) * 0.8
    if alpha <= 0 then return end
    for _, cell in ipairs(scene.floorCells) do
        local p = Isaac.WorldToScreen(cell)
        draw(asset(scene, "floor"), p.X, p.Y, 1, 1, color(0.75, 0.92, 1, alpha))
    end
end

local function rain(scene, alpha)
    -- Sample the room's actual footprint: this also leaves L-room voids dry.
    for i = 1, math.min(50, #scene.floorCells) do
        local cell = scene.floorCells[((i * 17 - 1) % #scene.floorCells) + 1]
        local p = Isaac.WorldToScreen(cell)
        local age = (scene.frame * 5 + i * 19) % 65
        line(scene, p.X + 9, p.Y - 65 + age, p.X + 7, p.Y - 57 + age, BLUE, alpha * 0.55)
        if age > 54 then ring(scene, p.X + 7, p.Y, (age - 54) * 0.7, BLUE, alpha * 0.3, 0.35) end
    end
end

local function smoke(scene, x, y, scale, alpha)
    draw(asset(scene, "smoke"), x, y, scale, scale, color(0.7, 0.6, 0.9, alpha))
end
local function holy(scene, x, y, f, slow)
    local age = math.floor((f - scene.impact) * (slow or 1))
    if age < 0 or age >= 24 then return end
    local s = native(scene, "holy", "gfx/1000.019_crack the sky.anm2", "Spotlight")
    s:SetFrame("Spotlight", age)
    draw(s, x, y + 17, 0.75)
end
local function bolt(scene, x, y, f, alpha)
    local previousX, previousY = x - 12, y - 160
    for i = 1, 10 do
        local px = i == 10 and x or x + math.sin(i * 9 + math.floor(f / 2)) * 13
        local py = y - 160 + i * 16
        line(scene, previousX, previousY, px, py, BLUE, alpha * 0.6, 5)
        line(scene, previousX, previousY, px, py, WHITE, alpha, 2)
        previousX, previousY = px, py
    end
end

function Visuals.render(scene)
    local f, effect = scene.frame, scene.profile.effect
    local p = Isaac.WorldToScreen(scene.pos)
    local target = f >= scene.impact
    local variant = target and scene.targetVariant or scene.sourceVariant
    local x, y = p.X, p.Y - (variant == PickupVariant.PICKUP_TRINKET and 6 or 22)
    local envelope = ease(0, 12, f) * (1 - ease(78, 102, f))
    local size, alpha, white, rotation = 1, 1, 0, 0

    if effect and effect:find("clock", 1, true) then clock(scene, x, y, envelope) end
    if effect == "rain" or effect == "clock_rain" then rain(scene, envelope) end
    if effect == "void" then
        size = target and (0.55 + 0.45 * ease(scene.impact, 70, f)) or (1 - ease(33, scene.impact, f) * 0.5)
        for i = 1, 14 do
            local progress = ease(i, scene.impact, f)
            local a, radius = i * 2.4 + progress * 1.4, (23 + i % 4) * (1 - progress)
            if f < scene.impact then
                smoke(scene, x + math.cos(a) * radius, y + 6 + math.sin(a) * radius * 0.7,
                    (0.22 + (i % 3) * 0.04) * (1 - progress), envelope * 0.75)
            end
        end
    elseif effect == "fire" or effect == "ice" then
        alpha = target and ease(scene.impact, 68, f) or 1 - ease(24, scene.impact, f)
        size = target and (0.7 + 0.3 * ease(scene.impact, 70, f)) or 1
    elseif effect == "grade" then
        local flip = math.abs(math.cos(ease(30, 66, f) * PI))
        size = math.max(0.03, flip)
        local wipe = ease(9, 34, f)
        line(scene, x - 20, y - 17, x - 20 + 40 * wipe, y - 17, WHITE, envelope * 0.7, 3)
    elseif effect == "purify" then
        white = ease(10, 38, f) * (1 - ease(52, 84, f))
        for i = 1, 7 do
            local a = i * PI / 3.5
            local burn = ease(24 + i, 48 + i, f)
            if burn < 1 then smoke(scene, x + math.cos(a) * 23, y + math.sin(a) * 15,
                0.22 * (1 - burn), (1 - burn) * envelope) end
        end
    elseif effect == "thread" then
        local split = ease(scene.impact, 70, f)
        draw(scene.before, x - 43 - split * 7, y + 3, 0.55, 0.55, color(1, 1, 1, envelope * 0.7))
        draw(scene.after, x + 43 + split * 7, y + 3, 0.55, 0.55, color(1, 1, 1, envelope * 0.7))
        line(scene, x - 34 - split * 7, y, x - 3 - split * 19, y + split * 11, WHITE, envelope)
        line(scene, x + 3 + split * 19, y + split * 11, x + 34 + split * 7, y, WHITE, envelope)
        rotation = -16 * math.sin(ease(24, 62, f) * PI)
    elseif not effect then
        local fade = target and 1 - (f - scene.impact) / 60 or f / 60
        if scene.flag == "positive" then white = fade * 0.8
        elseif scene.flag == "neutral" then alpha = 1; white = 0 end
    end

    local itemColor = color(1, 1, 1, alpha, white)
    if not effect and scene.flag ~= "positive" then
        local fade = target and 1 - (f - scene.impact) / 60 or f / 60
        local dark = 1 - fade * (scene.flag == "negative" and 0.8 or 0.42)
        itemColor = color(dark + (scene.flag == "negative" and fade * 0.5 or 0), dark, dark, 1)
    end
    draw(target and scene.after or scene.before, x, y, size,
        effect == "grade" and 1 or size, itemColor, rotation)

    if effect == "lightning" and f >= scene.impact - 2 and f < scene.impact + 7 then
        local flash = 1 - ease(scene.impact, scene.impact + 7, f)
        bolt(scene, x, y, f, flash)
        draw(target and scene.after or scene.before, x, y, 1, 1, color(1, 1, 1, flash, 1))
        ring(scene, x, y + 18, (f - scene.impact + 3) * 4, BLUE, flash * 0.6, 0.35)
    elseif effect == "fire" or effect == "ice" then
        local strength = ease(4, scene.impact, f) * (1 - ease(scene.impact, 75, f))
        local s = asset(scene, effect)
        s:SetFrame("Idle", math.floor(f / 2) % 6)
        draw(s, x, y + 12, 0.3 + strength * 1.05, 0.3 + strength * 1.35, color(1, 1, 1, envelope * (1 - ease(62, 78, f))))
    elseif effect == "missile" then
        local aim = 1 - ease(scene.impact, scene.impact + 5, f)
        ring(scene, x, y, 19, RED, aim * envelope)
        for i = 0, 3 do
            local a = i * PI / 2
            line(scene, x + math.cos(a) * 13, y + math.sin(a) * 13,
                x + math.cos(a) * 25, y + math.sin(a) * 25, RED, aim * envelope, 2)
        end
        if f >= 27 and f < scene.impact then
            local rocket = native(scene, "rocket", "gfx/1000.031_dr. fetus rocket.anm2", "Falling")
            draw(rocket, x, y - (1 - ease(27, scene.impact, f)) * 230, 2.1)
        elseif f >= scene.impact and f < scene.impact + 19 then
            local explosion = native(scene, "explosion", "gfx/1000.001_bomb explosion.anm2", "Explosion")
            explosion:SetFrame("Explosion", f - scene.impact)
            draw(explosion, x, y + 10, 1.1)
        end
    elseif effect == "purify" then
        holy(scene, x, y, f, 0.65)
        ring(scene, x, y - 20, 14 + ease(38, 72, f) * 4, GOLD, envelope, 0.3)
        for i = 1, 6 do
            local a = i * PI / 3
            star(scene, x + math.cos(a) * 26, y + math.sin(a) * 21, 2,
                WHITE, ease(37 + i, 45 + i, f) * (1 - ease(66, 86, f)))
        end
    elseif effect == "clock_coin" then
        for i = 1, 3 do
            local age = f - i * 14
            if age >= 0 and age < 28 then
                ring(scene, x + (i - 2) * 15, y - 24 + age * 1.6, 4, GOLD, 1 - age / 28, 1.2)
            end
        end
    elseif effect == "clock_power" then
        for i = 1, 4 do
            line(scene, x - 18 + i * 7, y + 25, x - 18 + i * 7, y + 25 - i * 4,
                RED, envelope * ease(i * 10, i * 10 + 5, f), 4)
        end
    elseif effect == "clock_luck" then
        for i = 1, 4 do
            local a = i * PI / 2
            ring(scene, x + math.cos(a) * 7, y - 28 + math.sin(a) * 5,
                4 * ease(i * 10, i * 10 + 7, f), { 0.6, 0.9, 0.4 }, envelope, 0.8)
        end
    elseif effect == "grade" then
        if f > scene.impact then
            local grade = scene.key:sub(1, 1) .. " -"
            Isaac.RenderText(grade, x - 7, y - 33, 1, 0.85, 0.6, envelope)
            if scene.key == "A_MINUS" then star(scene, x + 18, y - 20, 3, GOLD, envelope) end
        end
    elseif effect == "thread" and f >= scene.impact and f < scene.impact + 14 then
        local cut = 1 - ease(scene.impact, scene.impact + 14, f)
        star(scene, x - 6, y, 5, WHITE, cut); star(scene, x + 6, y, 3, GOLD, cut)
    elseif not effect and scene.flag == "positive" then holy(scene, x, y, f) end
end

-- A visual failure must restore a hidden pedestal, never cancel its gameplay
-- transaction or leave a callback throwing each frame.
function Visuals.safe(method, scene)
    if scene.failed then return false end
    local ok, err = pcall(method, scene)
    if not ok then
        scene.failed = true
        ConchBlessing.printError("[ConchMorph] " .. scene.key .. ": " .. tostring(err))
    end
    return ok
end

return Visuals
