-- Pure presentation shared by real upgrades and conch_morph. Never spawn an
-- entity: vanilla fire, explosions and Holy Light have native combat behaviour.
local Visuals = { catalog = require("scripts.upgrade_visual_catalog") }
local Devour = require("scripts.lib.upgrade_devour")
local PickupVisual = require("scripts.lib.upgrade_pickup_visual")
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
-- First visible-core row (alpha > 64) in each 48px vanilla fire frame. Red
-- and blue share this silhouette; ignore the almost-transparent outer glow.
local FIRE_TIP_ROWS = { 11, 11, 10, 12, 11, 10 }
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

function Visuals.create(key, pos, sourceVariant, sourceId, startFrame, owner)
    local item = assert(ConchBlessing.ItemData[key], "unknown morph item")
    local profile = assert(profiles[key], "missing morph profile")
    local targetVariant = item.type == "trinket" and PickupVariant.PICKUP_TRINKET or PickupVariant.PICKUP_COLLECTIBLE
    if not sourceVariant then sourceVariant, sourceId = Visuals.origin(item) end
    local scene = {
        key = key, profile = profile, flag = item.flag,
        pos = point(pos.X, pos.Y), frame = startFrame or 0,
        impact = profile.impact or 60, duration = profile.duration or (profile.effect and 102 or 120),
        sourceVariant = sourceVariant, targetVariant = targetVariant,
        before = Visuals.icon(sourceVariant, sourceId), after = Visuals.icon(targetVariant, item.id),
        assets = {}, sounded = {}, floorCells = {},
    }
    -- Probe required primitives before a real pickup is hidden.
    asset(scene, "pixel")
    local effect = profile.effect
    if effect == "lightning" then asset(scene, "spotlight") end
    if effect == "devour" then Devour.prepare(scene, owner, asset) end
    if effect and effect:find("clock", 1, true) then
        for _, part in ipairs({ "rim", "minute", "hour" }) do asset(scene, "clock_" .. part) end
    end
    if effect == "purify" then asset(scene, "halo") end
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

local function soundOnce(scene, name, at, volume, pitch)
    local cue = name .. ":" .. at
    if scene.frame < at or scene.sounded[cue] then return end
    scene.sounded[cue] = true
    local id = SoundEffect and SoundEffect[name]
    if id then SFXManager():Play(id, volume or 0.5, 0, false, pitch or 1) end
end

function Visuals.update(scene)
    scene.frame = math.min(scene.duration, scene.frame + 1)
    local effect = scene.profile.effect
    if effect == "lightning" then
        -- Distant thunder follows the darkening; a separate crack coincides
        -- with the actual conversion. A late commit never replays the lead-in.
        if scene.frame < scene.impact then
            soundOnce(scene, "SOUND_THUNDER", scene.impact - 25, 0.35, 0.65)
        end
        soundOnce(scene, "SOUND_LIGHTBOLT", scene.impact, 0.8, 1)
    end
    if effect == "fire" or effect == "ice" then
        soundOnce(scene, "SOUND_CANDLE_LIGHT", 5, 0.4)
        soundOnce(scene, "SOUND_FLAME_BURST", scene.impact - 7, 0.5)
        if effect == "ice" then soundOnce(scene, "SOUND_FREEZE", scene.impact, 0.4) end
    end
    if effect == "devour" then
        if #scene.pets > 0 then
            soundOnce(scene, SoundEffect.SOUND_MEGAFATTY_SUCKIN and "SOUND_MEGAFATTY_SUCKIN" or "SOUND_PORTAL_OPEN",
                scene.devour.first, 0.3, 0.85)
        end
        local bite = SoundEffect and SoundEffect.SOUND_BONE_SNAP and "SOUND_BONE_SNAP" or "SOUND_SMB_LARGE_CHEWS_4"
        soundOnce(scene, bite, scene.devour.closed, 0.65, 0.85)
        if scene.frame >= scene.devour.closed and not scene.mawShook then
            scene.mawShook = true
            if Game().ShakeScreen then Game():ShakeScreen(6) end
        end
    end
    if effect == "missile" then
        -- Three increasingly close lock tones, each played once from updates.
        if scene.frame < scene.impact - 16 then
            soundOnce(scene, "SOUND_BEEP", 6, 0.35, 1)
            soundOnce(scene, "SOUND_BEEP", 22, 0.35, 1.1)
            soundOnce(scene, "SOUND_BEEP", scene.impact - 19, 0.4, 1.2)
        end
        soundOnce(scene, "SOUND_ROCKET_LAUNCH", scene.impact - 16, 0.4)
        soundOnce(scene, "SOUND_BOSS1_EXPLOSIONS", scene.impact, 0.6)
        if scene.frame >= scene.impact and not scene.shook then
            scene.shook = true
            if Game().ShakeScreen then Game():ShakeScreen(9) end
        end
    end
    if effect == "purify" and scene.frame <= scene.impact then soundOnce(scene, "SOUND_ANGEL_WING", 18, 0.3) end
    if effect == "purify" or (not effect and scene.flag == "positive") then
        soundOnce(scene, "SOUND_HOLY", scene.impact, 0.35)
    end
end

local function clock(scene, x, y, alpha)
    -- One continuous revolution, then the face fades away. No stepped ticks.
    alpha = alpha * (1 - ease(scene.impact, scene.impact + 10, scene.frame))
    if alpha <= 0 then return end
    -- Fit the full face inside the item's 32px box; draw over the item so its
    -- hands sweep across it, then fade away to reveal the converted result.
    local scale = 2 / 3
    local angle = ease(scene.impact - 28, scene.impact, scene.frame) * 360
    draw(asset(scene, "clock_rim"), x, y, scale, scale, color(1, 1, 1, alpha * 0.85))
    draw(asset(scene, "clock_hour"), x, y, scale, scale, color(1, 1, 1, alpha), -60 + angle / 12)
    draw(asset(scene, "clock_minute"), x, y, scale, scale, color(1, 1, 1, alpha), angle)
end

function Visuals.renderFloor(scene)
    if #scene.floorCells == 0 then return end
    local f = scene.frame
    local alpha = ease(8, 80, f) * (1 - ease(scene.duration - 20, scene.duration, f)) * 0.93
    if alpha <= 0 then return end
    for _, cell in ipairs(scene.floorCells) do
        local p = Isaac.WorldToScreen(cell)
        draw(asset(scene, "floor"), p.X, p.Y, 1, 1, color(0.82, 0.94, 1, alpha))
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

-- Each landing boosts the RATE of blue absorption, not the color value itself.
-- Integrate a sharp decaying impulse plus a small continuing flow. The same
-- scene time always yields the same tint (pause/replay/commit cannot drift).
local RAIN_STRIKES = { -5, 3, -1, 6, -3 }
local function absorbedRain(age)
    age = math.max(0, age)
    return age * 0.035 + 1 - math.exp(-age / 2.5)
end
local function rainWetness(scene)
    if scene.frame >= scene.impact then return 0 end
    local absorbed, total = 0, 0
    for i = 1, #RAIN_STRIKES do
        local landing = scene.impact - 48 + i * 8
        absorbed = absorbed + absorbedRain(scene.frame - landing)
        total = total + absorbedRain(scene.impact - 1 - landing)
    end
    return clamp(absorbed / total)
end

local function rainOnItem(scene, x, y, alpha)
    for i, offset in ipairs(RAIN_STRIKES) do
        local age = scene.frame - (scene.impact - 48 + i * 8)
        local hitX, hitY = x + offset, y - 6
        if age >= -12 and age < 0 then
            local progress = (age + 12) / 12
            local dropX, dropY = hitX + (1 - progress) * 9, hitY - (1 - progress) * 68
            line(scene, dropX + 1, dropY - 6, dropX, dropY, BLUE, alpha * 0.9)
        elseif age >= 0 and age < 6 then
            local spread, fade = 1 + age * 0.9, (1 - age / 6) * alpha
            line(scene, hitX - spread, hitY - 2, hitX - spread - 1, hitY - 4 + age * 0.5, BLUE, fade)
            line(scene, hitX + spread, hitY - 2, hitX + spread + 1, hitY - 4 + age * 0.5, BLUE, fade)
        end
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

local function screenSize()
    local room = Game():GetRoom()
    local center = Isaac.WorldToScreen(room:GetCenterPos())
    local bottom = Isaac.WorldToScreen(room:GetBottomRightPos())
    local width = Isaac.GetScreenWidth and Isaac.GetScreenWidth() or center.X * 2
    local height = Isaac.GetScreenHeight and Isaac.GetScreenHeight() or bottom.Y + 30
    return width, height
end

local function screenVeil(scene, rgb, alpha)
    if alpha <= 0 then return end
    local width, height = screenSize()
    -- Scene-owned drawing only: never change Game:Darken, room colors, or a
    -- persistent backdrop. Cancellation/room change therefore clears at once.
    draw(asset(scene, "pixel"), 0, 0, width, height, tint(rgb, alpha))
end

local function stormDarkness(scene, x, y, alpha)
    if alpha <= 0 then return end
    local width, height = screenSize()
    local left, top = math.floor(x) - 80, math.floor(y) - 80
    local right, bottom = left + 160, top + 160
    local c = tint({ 0.025, 0.035, 0.07 }, alpha)
    local function fill(x1, y1, x2, y2)
        x1, y1 = math.max(0, x1), math.max(0, y1)
        x2, y2 = math.min(width, x2), math.min(height, y2)
        if x2 > x1 and y2 > y1 then
            draw(asset(scene, "pixel"), x1, y1, x2 - x1, y2 - y1, c)
        end
    end
    -- One soft aperture and four non-overlapping rectangles cover any screen
    -- size, even near a door. The transparent centre preserves the actual room
    -- and item underneath, instead of painting a pale disk over the darkness.
    fill(0, 0, width, top)
    fill(0, bottom, width, height)
    fill(0, top, left, bottom)
    fill(right, top, width, bottom)
    draw(asset(scene, "spotlight"), left + 80, top + 80, 1, 1, c)
end

local function drawItem(scene, target, x, y, sx, sy, c, rotation)
    if scene.pickupVisual then
        PickupVisual.render(scene.pickupVisual, x, y, sx, sy, c, rotation)
    else
        draw(target and scene.after or scene.before, x, y, sx, sy, c, rotation)
    end
end

function Visuals.render(scene)
    local f, effect = scene.frame, scene.profile.effect
    local p = Isaac.WorldToScreen(scene.pos)
    local target = f >= scene.impact
    local variant = target and scene.targetVariant or scene.sourceVariant
    local x, y = p.X, p.Y - (variant == PickupVariant.PICKUP_TRINKET and 6 or 22)
    if scene.pickupVisual then
        local center = PickupVisual.center(scene.pickupVisual)
        x, y = center.X, center.Y
    end
    local fx, fy = x, y
    if scene.profile.anchorX and scene.profile.anchorY then
        if scene.pickupVisual then
            local center = PickupVisual.center(scene.pickupVisual, point(scene.profile.anchorX, scene.profile.anchorY))
            fx, fy = center.X, center.Y
        else
            fx, fy = x + scene.profile.anchorX - 16, y + scene.profile.anchorY - 16
        end
    end
    local envelope = ease(0, 12, f) * (1 - ease(scene.duration - 24, scene.duration, f))
    local size, alpha, white, rotation = 1, 1, 0, 0

    if effect == "devour" then
        Devour.render(scene, x, y, { ease = ease, draw = draw, drawItem = drawItem,
            asset = asset, color = color, line = line })
        return
    end

    if effect == "rain" or effect == "clock_rain" then rain(scene, envelope) end
    if effect == "void" then
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
        white = ease(10, 38, f) * (1 - ease(scene.impact + 8, scene.duration - 8, f))
        local blessing = ease(12, 28, f) * (1 - ease(scene.impact + 5, scene.impact + 23, f))
        draw(asset(scene, "halo"), fx, fy - 32 + ease(12, 36, f) * 8, 1, 1,
            color(1, 1, 1, blessing))
        for i = 1, 7 do
            local a = i * PI / 3.5
            local burn = ease(24 + i, 48 + i, f)
            if burn < 1 then smoke(scene, fx + math.cos(a) * 23, fy + math.sin(a) * 15,
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
    if effect == "purify" then
        -- Interpolate each pixel toward white instead of adding brightness:
        -- additive white clips light colors and hides most of the return fade.
        itemColor = color(1 - white, 1 - white, 1 - white, alpha, white)
    elseif effect == "rain" or effect == "clock_rain" then
        local wet = rainWetness(scene)
        itemColor = Color(1 - wet * 0.7, 1 - wet * 0.3, 1, alpha, 0, wet * 0.05, wet * 0.35)
    elseif not effect and scene.flag ~= "positive" then
        local fade = target and 1 - (f - scene.impact) / 60 or f / 60
        local dark = 1 - fade * (scene.flag == "negative" and 0.8 or 0.42)
        itemColor = color(dark + (scene.flag == "negative" and fade * 0.5 or 0), dark, dark, 1)
    end
    drawItem(scene, target, x, y, size,
        effect == "grade" and 1 or size, itemColor, rotation)
    if effect and effect:find("clock", 1, true) then clock(scene, x, y, envelope) end
    if effect == "rain" or effect == "clock_rain" then rainOnItem(scene, x, y, envelope) end

    if effect == "lightning" then
        -- The storm clears on the strike itself; only its brief flash remains.
        local darkness = f < scene.impact and ease(scene.impact - 43, scene.impact - 27, f) * 0.88 or 0
        stormDarkness(scene, x, y, darkness)
        if f >= scene.impact and f < scene.impact + 7 then
            local flash = 1 - ease(scene.impact, scene.impact + 7, f)
            screenVeil(scene, { 0.91, 0.96, 1 }, flash * 0.55)
            bolt(scene, x, y, f, flash)
            drawItem(scene, true, x, y, 1, 1, color(1, 1, 1, flash, 1))
            ring(scene, x, y + 18, (f - scene.impact + 3) * 4, BLUE, flash * 0.6, 0.35)
        end
    elseif effect == "fire" or effect == "ice" then
        local grow, settle = ease(4, scene.impact, f), ease(scene.impact, scene.impact + 25, f)
        local sx = (0.08 + grow * 0.97) * (1 - settle) + 0.7 * settle
        local sy = (0.08 + grow * 0.82) * (1 - settle) + 0.6 * settle
        local frame = math.floor(f / 2) % 6
        local s = asset(scene, effect)
        s:SetFrame("Idle", frame)
        -- Ignite just above the wick, then keep the visible tip fixed while the
        -- flame grows DOWN over the candle. Its authored root pivot is at y=40.
        local rootY = y - 14 + (40 - FIRE_TIP_ROWS[frame + 1]) * sy
        draw(s, x, rootY, sx, sy, color(1, 1, 1, envelope * (1 - ease(62, 78, f))))
    elseif effect == "missile" then
        local aim = 1 - ease(scene.impact, scene.impact + 5, f)
        local reticle = native(scene, "target", "gfx/1000.030_dr. fetus target.anm2", "Idle")
        draw(reticle, x, y, 1, 1, color(1, 0.12, 0.12, aim * envelope))
        local launch = scene.impact - 16
        if f >= launch and f < scene.impact then
            local rocket = native(scene, "rocket", "gfx/1000.031_dr. fetus rocket.anm2", "Falling")
            local flight = clamp((f - launch) / 16)
            draw(rocket, x, y - (1 - flight * flight) * 230, 2.1)
        elseif f >= scene.impact and f < scene.impact + 19 then
            local explosion = native(scene, "explosion", "gfx/1000.001_bomb explosion.anm2", "Explosion")
            explosion:SetFrame("Explosion", f - scene.impact)
            draw(explosion, x, y + 10, 1.1)
        end
    elseif effect == "purify" then
        holy(scene, fx, fy, f, 0.65)
        for i, offset in ipairs({ { -17, -9 }, { 15, -14 }, { 5, 12 } }) do
            local age = f - scene.impact - (i - 1) * 6
            if age >= 0 and age < 24 then
                -- door_sparkle exists in extracted files but is not loadable
                -- in the tested game. Use the native BLING effect animation.
                local glint = native(scene, "glint", "gfx/1000.103_ultragreedbling.anm2", "Bling1")
                glint:SetFrame("Bling1", math.floor(age / 3))
                draw(glint, fx + offset[1], fy + offset[2], 0.75, 0.75, color(1, 1, 1, 1 - ease(18, 24, age)))
            end
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
