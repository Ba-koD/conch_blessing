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
local function windowed(a, b, c, d, x) return ease(a, b, x) * (1 - ease(c, d, x)) end
local function point(x, y) return Vector(x, y) end
local function color(r, g, b, a, add) return Color(r, g, b, a or 1, add or 0, add or 0, add or 0) end
local function hex(value)
    return { tonumber(value:sub(2, 3), 16) / 255, tonumber(value:sub(4, 5), 16) / 255,
        tonumber(value:sub(6, 7), 16) / 255 }
end
-- The approved HTML preview is the reference. Its palette, value noise and
-- second-based curves are mirrored here so both draw the same motion.
local function rand(i)
    local n = math.sin(i * 128.731 + 38.41) * 43758.5453
    return n - math.floor(n)
end
local VOID_MARK = hex("#796193")
local BOLT_GLOW, BOLT_CORE = hex("#678aae"), hex("#ddf3ff")
local RAIN_DROP, RAIN_HIT = hex("#b0d3e1"), hex("#a6d9ff")
-- First visible-core row (alpha > 64) in each 48px vanilla fire frame. The
-- orange and blue sheets share this silhouette; ignore the faint outer glow.
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
    local length, w = math.sqrt(dx * dx + dy * dy), width or 1
    if length <= 0 then return end
    -- The pixel's pivot is its corner; centre the stroke like a canvas line.
    draw(asset(scene, "pixel"), x1 + dy / length * w / 2, y1 - dx / length * w / 2, length, w,
        tint(rgb, alpha), math.deg(math.atan(dy, dx)))
end
local function rect(scene, x, y, w, h, rgb, alpha)
    draw(asset(scene, "pixel"), math.floor(x + 0.5), math.floor(y + 0.5),
        math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5)), tint(rgb, alpha))
end
local function ring(scene, x, y, rx, ry, rgb, alpha)
    if alpha <= 0 then return end
    for i = 0, 23 do
        local a, b = i * PI / 12, (i + 1) * PI / 12
        line(scene, x + math.cos(a) * rx, y + math.sin(a) * ry, x + math.cos(b) * rx, y + math.sin(b) * ry, rgb, alpha)
    end
end

-- Runtime evidence (never saved): what each scene actually played and drew.
-- conch_test morph reads these records; debug mode also writes them to the log.
local function debugOn() return ConchBlessing.Config and ConchBlessing.Config.debugMode end
local function trace(scene, event, detail)
    if not debugOn() then return end
    ConchBlessing.printDebug(string.format("[ConchMorph] %s %s frame=%d/%d%s", event, tostring(scene.key),
        scene.frame, scene.duration, detail and detail ~= "" and " " .. detail or ""))
end
Visuals.trace = trace
-- One value per scene frame, e.g. Kronos's black strength or the storm's darkness.
local function sample(scene, name, value)
    local values = scene.samples[name]
    if not values then values = {}; scene.samples[name] = values end
    values[scene.frame] = value
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
        cues = {}, marks = {}, rendered = {}, samples = {}, floorRenders = 0,
    }
    -- Probe required primitives before a real pickup is hidden.
    asset(scene, "pixel")
    local effect = profile.effect
    if effect == "lightning" then asset(scene, "spotlight") end
    if effect == "saturn" then Devour.prepare(scene, owner) end
    if effect and effect:find("clock", 1, true) then
        for _, part in ipairs({ "rim", "minute", "hour" }) do asset(scene, "clock_" .. part) end
    end
    if effect == "purify" then
        asset(scene, "halo")
        native(scene, "holy", "gfx/1000.019_crack the sky.anm2", "Spotlight")
        native(scene, "glint", "gfx/1000.103_ultragreedbling.anm2", "Bling1")
    end
    if effect == "missile" then
        asset(scene, "fire")
        native(scene, "target", "gfx/1000.030_dr. fetus target.anm2", "Idle")
        native(scene, "rocket", "gfx/1000.031_dr. fetus rocket.anm2", "Falling")
        native(scene, "explosion", "gfx/1000.001_bomb explosion.anm2", "Explosion")
    end
    if effect == "void" or effect == "purify" then asset(scene, "smoke") end
    if effect == "fire" or effect == "ice" then asset(scene, effect) end
    if effect == "rain" then
        asset(scene, "floor")
        native(scene, "ripple", "gfx/1000.133_water ripple.anm2", "Poof")
        local room = Game():GetRoom()
        for i = 0, room:GetGridSize() - 1 do
            local p = room:GetGridPosition(i)
            if room:IsPositionInRoom(point(p.X - 19, p.Y - 19), 0)
                and room:IsPositionInRoom(point(p.X + 19, p.Y + 19), 0) then
                scene.floorCells[#scene.floorCells + 1] = point(p.X, p.Y)
            end
        end
        -- The preview's 28 drops cover a 13x7 floor. Keep that density in
        -- larger rooms and leave the voids of L-shaped rooms dry.
        local topLeft, bottomRight = room:GetTopLeftPos(), room:GetBottomRightPos()
        local width, height = bottomRight.X - topLeft.X, bottomRight.Y - topLeft.Y
        scene.drops = {}
        for i = 0, math.min(112, math.max(1, math.floor(28 * #scene.floorCells / 91 + 0.5))) - 1 do
            local world = point(topLeft.X + (13 + rand(i + 10) * 338) / 364 * width,
                topLeft.Y + (15 + rand(i + 80) * 183) / 204 * height)
            if room:IsPositionInRoom(world, 0) then scene.drops[#scene.drops + 1] = { index = i, pos = world } end
        end
    end
    if debugOn() then
        trace(scene, "SCENE", string.format("effect=%s impact=%d source=%s:%s target=%s:%s%s%s",
            tostring(effect), scene.impact, tostring(sourceVariant), tostring(sourceId),
            tostring(targetVariant), tostring(item.id),
            scene.pets and string.format(" pets=%d(%s)", #scene.pets, tostring(scene.petSource)) or "",
            scene.drops and string.format(" floorCells=%d drops=%d floorHook=%s", #scene.floorCells, #scene.drops,
                tostring(ModCallbacks.MC_PRE_BACKDROP_RENDER_WATER ~= nil)) or ""))
    end
    return scene
end

-- `sound` is a SoundEffect name or an already resolved custom sound ID.
local function soundOnce(scene, sound, at, volume, pitch)
    if not sound then return end
    local cue = tostring(sound) .. ":" .. at
    if scene.frame < at or scene.sounded[cue] then return end
    scene.sounded[cue] = true
    local id = type(sound) == "number" and sound or (SoundEffect and SoundEffect[sound])
    if not id then
        ConchBlessing.printError("[ConchMorph] unknown sound: " .. tostring(sound))
        return
    end
    local sfx = SFXManager()
    sfx:Play(id, volume or 0.5, 0, false, pitch or 1)
    -- Evidence for in-game audibility reports: the cue fired, and whether the
    -- engine actually started the sample (another mod's PRE_SFX_PLAY may not).
    -- The engine may start it on its next audio tick, so the following update
    -- checks again before the SOUND line is logged.
    local cue = { sound = sound, id = id, at = at, frame = scene.frame, volume = volume or 0.5, pitch = pitch or 1 }
    if type(sfx.IsPlaying) == "function" then cue.now = sfx:IsPlaying(id) end
    scene.cues[#scene.cues + 1] = cue
end
local customNames = {}
local function cueName(cue) return customNames[cue.id] or tostring(cue.sound) end
Visuals.cueName = cueName
local function confirmCue(scene, cue)
    if cue.checked then return end
    cue.checked = true
    local sfx = SFXManager()
    if type(sfx.IsPlaying) == "function" then cue.next = sfx:IsPlaying(cue.id) end
    cue.heard = cue.now == true or cue.next == true
    trace(scene, "SOUND", string.format("%s id=%d at=%d played=%d volume=%.2f pitch=%.2f playing=%s/%s",
        cueName(cue), cue.id, cue.at, cue.frame, cue.volume, cue.pitch, tostring(cue.now), tostring(cue.next)))
end

-- content/sounds.xml registers the generator-owned project sounds. The engine
-- has no single-sample close thunder (SOUND_THUNDER swells like distant
-- thunder and SOUND_LIGHTBOLT is a sharp electric buzz), no rain sound effect
-- and no clock tick. A missing registration reports once and stays silent.
local customSounds = {}
local function customSound(name)
    if customSounds[name] == nil then
        local id = Isaac.GetSoundIdByName and Isaac.GetSoundIdByName(name)
        customSounds[name] = type(id) == "number" and id > 0 and id or false
        if customSounds[name] then customNames[id] = name
        else ConchBlessing.printError("[ConchMorph] missing sound: " .. name) end
    end
    return customSounds[name] or nil
end

-- The clock runs six hours, from 6:00 to 12:00: the minute hand makes six
-- turns at one constant, fast speed. Every turn is one 째깍: 째 as the minute
-- hand passes 6 and 깍 as it reaches 12, so the ticking is continuous and the
-- sixth 깍 and 12:00 land on the change.
local CLOCK_START, CLOCK_TURNS, START_HOUR = 0, 6, 180
local function turnLength(scene) return (scene.impact - CLOCK_START) / CLOCK_TURNS end
-- { frame, "tick" | "tock" } for every half turn, in order.
function Visuals.clockTicks(scene)
    local ticks = {}
    for j = 1, CLOCK_TURNS * 2 do
        ticks[j] = { math.floor(CLOCK_START + turnLength(scene) * j / 2 + 0.5), j % 2 == 1 and "tick" or "tock" }
    end
    return ticks
end
-- Completed minute-hand turns at frame f (0 to 6), at constant speed.
function Visuals.clockTurns(scene, f)
    return CLOCK_TURNS * clamp((f - CLOCK_START) / (scene.impact - CLOCK_START))
end
-- Hand angles in degrees clockwise from 12: minute 0..2160, hour 180 (6) .. 360 (12).
function Visuals.clockHands(scene, f)
    local turns = Visuals.clockTurns(scene, f)
    return turns * 360, START_HOUR + turns * 30
end

-- Values the renderer draws, as pure functions of the scene frame so update,
-- render, the debug log and tests all read the same numbers.
local function stormAlpha(scene, f) return f < scene.impact and ease(2, 18, f) * 0.88 or 0 end
local function crownWhite(scene, f) return ease(10, 38, f) * (1 - ease(scene.impact + 8, scene.duration - 8, f)) end
local function voidVanish(scene, f) return clamp((f - scene.impact) / 3) end
local function flameItemAlpha(scene, f)
    if f >= scene.impact then return ease(scene.impact, 68, f) end
    return 1 - ease(24, scene.impact, f)
end
-- Hemispatial Neglect: the left half of the view fades to black, holds
-- through the change and gradually returns.
local NEGLECT_DARK_FROM, NEGLECT_DARK_TO, NEGLECT_RETURN = 6, 42, 45
local function neglectDarkness(scene, f)
    if f < scene.impact then return ease(NEGLECT_DARK_FROM, NEGLECT_DARK_TO, f) end
    return 1 - ease(scene.impact, scene.impact + NEGLECT_RETURN, f)
end
Visuals.neglectDarkness = neglectDarkness
local rainWetness, strikeLanding, floodLevel -- defined with the rain drawing below

-- Named moments of each presentation, in frame order. Each is logged once
-- under debug mode and recorded in scene.marks with the frame it was reached.
function Visuals.milestones(scene)
    local i, e, list = scene.impact, scene.profile.effect, {}
    local function add(name, frame, value) list[#list + 1] = { name = name, frame = frame, value = value } end
    local function dark(f) return string.format("darkness=%.2f", stormAlpha(scene, f)) end
    local function black(f) return string.format("black=%.2f", Devour.black(scene, f, ease)) end
    if e == "lightning" then
        add("blackout", 2, dark); add("darkness-full", 18, dark); add("darkness-held", i - 1, dark)
    elseif e == "saturn" then
        for k = 1, #(scene.pets or {}) do add("pet" .. k .. "-appears", 4 + (k - 1) * 8) end
        add("spin", 40); add("blacken", 70, black); add("fuse", i - 12, black); add("collapse", i - 6, black)
    elseif e == "rain" then
        local function wet() return string.format("wet=%.2f flood=%.2f", rainWetness(scene), floodLevel(scene)) end
        for k = 1, 5 do add("drop" .. k .. "-lands", strikeLanding(scene, k), wet) end
        add("dry+23", i + 23, wet); add("dried", i + 45, wet)
    elseif e == "missile" then
        add("reticle", 3); add("launch", i - 16)
    elseif e == "void" then
        add("gathered", i - 3)
    elseif e == "fire" or e == "ice" then
        add("ignite", 4)
        add("burst", i - 7, function(f) return string.format("itemAlpha=%.2f", flameItemAlpha(scene, f)) end)
    elseif e == "neglect" then
        local function dark(f) return string.format("darkness=%.2f", neglectDarkness(scene, f)) end
        add("left-darkening", NEGLECT_DARK_FROM, dark); add("left-black", NEGLECT_DARK_TO, dark)
        add("left-held", i - 1, dark)
    elseif e == "purify" then
        add("halo", 12)
        add("whitest", 38, function(f) return string.format("white=%.2f", crownWhite(scene, f)) end)
    end
    if e and e:find("clock", 1, true) then
        local function hands(f)
            local minute, hour = Visuals.clockHands(scene, f)
            return string.format("minute=%.0f hour=%.0f", minute, hour)
        end
        for _, beat in ipairs(Visuals.clockTicks(scene)) do
            -- Each 깍 below the last marks a full hour on the dial.
            if beat[2] == "tock" and beat[1] < i then
                add("hour" .. math.floor(6 + Visuals.clockTurns(scene, beat[1]) + 0.5), beat[1], hands)
            end
        end
    end
    add("commit", i, e == "lightning" and dark or e == "saturn" and black or nil)
    if e == "lightning" then add("flash-gone", i + 7); add("ring-gone", i + 16) end
    if e == "saturn" then
        for _, step in ipairs({ 15, 23, 30, 45 }) do add("colour+" .. step, i + step, black) end
    end
    if e == "void" then
        add("vanished", i + 3, function(f) return string.format("vanish=%.2f", voidVanish(scene, f)) end)
    end
    if e == "missile" then add("blast-gone", i + 19) end
    if e == "neglect" then
        add("left-returning", i + 23, function(f) return string.format("darkness=%.2f", neglectDarkness(scene, f)) end)
        add("left-back", i + NEGLECT_RETURN, function(f) return string.format("darkness=%.2f", neglectDarkness(scene, f)) end)
    end
    if e == "fire" or e == "ice" then add("settled", i + 25) end
    if e and e:find("clock", 1, true) then add("face-gone", i + 10) end
    add("end", scene.duration)
    table.sort(list, function(a, b) return a.frame < b.frame end)
    return list
end

local function markMilestones(scene)
    scene.milestoneList = scene.milestoneList or Visuals.milestones(scene)
    for _, m in ipairs(scene.milestoneList) do
        if scene.frame >= m.frame and not scene.marks[m.name] then
            scene.marks[m.name] = scene.frame
            trace(scene, "MARK", m.name .. " at=" .. m.frame .. (m.value and " " .. m.value(scene.frame) or ""))
        end
    end
end

function Visuals.update(scene)
    for _, cue in ipairs(scene.cues) do confirmCue(scene, cue) end
    -- The commit tick shows the impact frame itself instead of skipping it.
    if scene.holdFrame then scene.holdFrame = nil
    else scene.frame = math.min(scene.duration, scene.frame + 1) end
    markMilestones(scene)
    local effect = scene.profile.effect
    if effect == "lightning" then
        -- A low rumble rolls in with the blackout and swells under it; the
        -- nearby strike bangs on the actual conversion. A late commit never
        -- replays the lead-in.
        if scene.frame < scene.impact then
            soundOnce(scene, "SOUND_THUNDER", 2, 1, 0.65)
        end
        soundOnce(scene, customSound("Conch Upgrade Thunder Strike"), scene.impact, 1, 1)
    end
    -- Cue volumes stay at or below 1: the engine is not relied on to amplify.
    -- Every cue must be audible over gameplay (tests/test_upgrade_sound_levels.py).
    if effect and effect:find("clock", 1, true) then
        local tick = customSound("Conch Upgrade Clock Tick")
        local tock = customSound("Conch Upgrade Clock Tock")
        for _, beat in ipairs(Visuals.clockTicks(scene)) do
            -- The last 깍 strikes 12 on the change itself; a late commit never
            -- replays the earlier ones.
            if beat[1] >= scene.impact or scene.frame < scene.impact then
                if beat[2] == "tick" then soundOnce(scene, tick, beat[1], 1)
                else soundOnce(scene, tock, beat[1], 1) end
            end
        end
        -- 댕: a heavy grandfather-clock gong strikes 12 together with the change.
        soundOnce(scene, customSound("Conch Upgrade Clock Bell"), scene.impact, 1)
    end
    if effect == "rain" and scene.frame < scene.impact then
        soundOnce(scene, customSound("Conch Upgrade Rain"), 5, 1)
    end
    if effect == "fire" or effect == "ice" then
        -- A late commit never replays the ignition or the burst.
        if scene.frame < scene.impact then
            soundOnce(scene, "SOUND_CANDLE_LIGHT", 5, 0.8)
            soundOnce(scene, "SOUND_FLAME_BURST", scene.impact - 7, 1)
        end
        if effect == "ice" then soundOnce(scene, "SOUND_FREEZE", scene.impact, 1) end
    end
    if effect == "saturn" then
        -- Advance only the snapshot copies, like the preview's living pets.
        for _, pet in ipairs(scene.pets) do if pet.Update then pet:Update() end end
        -- A whirling wind-up as the orbit accelerates, then Kronos's own
        -- absorption sound as the ring collapses into the item.
        if scene.frame < scene.impact then soundOnce(scene, "SOUND_MOTHER_SPIN_START", 56, 1) end
        soundOnce(scene, "SOUND_SUMMONSOUND", scene.impact, 1)
        if scene.frame >= scene.impact and not scene.ringShook then
            scene.ringShook = true
            if Game().ShakeScreen then Game():ShakeScreen(6) end
        end
    end
    if effect == "missile" then
        -- The item's own lock-on warning sounds as the reticle appears, then
        -- the rocket and blast. A late commit never replays the build-up.
        if scene.frame < scene.impact then
            soundOnce(scene, "SOUND_DR_REMOTE_WARNING", 3, 1)
            soundOnce(scene, "SOUND_ROCKET_LAUNCH", scene.impact - 16, 0.8)
        end
        soundOnce(scene, "SOUND_ROCKET_EXPLOSION", scene.impact, 1)
        if scene.frame >= scene.impact and not scene.shook then
            scene.shook = true
            if Game().ShakeScreen then Game():ShakeScreen(9) end
        end
    end
    if effect == "purify" then
        -- Like every lead-in, a late commit never replays the wing beat.
        if scene.frame < scene.impact then soundOnce(scene, "SOUND_ANGEL_WING", 18, 1) end
        soundOnce(scene, "SOUND_HOLY", scene.impact, 1)
    end
end

local function clock(scene, x, y, alpha)
    -- Six constant-speed turns from 6:00 to 12:00, then the face fades away.
    local minute, hour = Visuals.clockHands(scene, scene.frame)
    sample(scene, "minute", minute)
    sample(scene, "hour", hour)
    alpha = alpha * (1 - ease(scene.impact, scene.impact + 10, scene.frame))
    if alpha <= 0 then return end
    -- Fit the full face inside the item's 32px box; draw over the item so its
    -- hands sweep across it, then fade away to reveal the converted result.
    local scale = 2 / 3
    draw(asset(scene, "clock_rim"), x, y, scale, scale, color(1, 1, 1, alpha * 0.85))
    draw(asset(scene, "clock_hour"), x, y, scale, scale, color(1, 1, 1, alpha), hour)
    draw(asset(scene, "clock_minute"), x, y, scale, scale, color(1, 1, 1, alpha), minute)
end

-- The flood rises like the preview, then drains with the scene's end.
function floodLevel(scene)
    local t = scene.frame / 30
    return ease(0.6, 3.05, t) * (1 - ease((scene.duration - 20) / 30, scene.duration / 30, t))
end

function Visuals.renderFloor(scene)
    if #scene.floorCells == 0 then return end
    scene.floorRenders = scene.floorRenders + 1
    if scene.floorRenders == 1 then trace(scene, "FLOOR", "overlay drawn cells=" .. #scene.floorCells) end
    local alpha = floodLevel(scene) * 0.94
    if alpha <= 0 then return end
    for _, cell in ipairs(scene.floorCells) do
        local p = Isaac.WorldToScreen(cell)
        draw(asset(scene, "floor"), p.X, p.Y, 1, 1, color(0.82, 0.94, 1, alpha))
    end
end

-- Every third drop falls in front of the item, the rest behind it.
local function rain(scene, front)
    local t = scene.frame / 30
    if not scene.drops or t < 0.15 then return end
    local alpha = ease(0.15, 0.85, t) * (1 - ease((scene.duration - 24) / 30, scene.duration / 30, t))
    if alpha <= 0 then return end
    for _, drop in ipairs(scene.drops) do
        local i = drop.index
        local age = t - (0.12 + rand(i + 30) * 0.65)
        if (i % 3 == 0) == front and age >= 0 then
            local period = 1 + rand(i + 70) * 0.7
            local p = (age % period) / period
            local s = Isaac.WorldToScreen(drop.pos)
            if p < 0.7 then
                local dropY = s.Y - 110 * (1 - p / 0.7)
                line(scene, s.X + 3, dropY - 7, s.X, dropY, RAIN_DROP, alpha * 0.6)
            else
                local frame = math.floor((p - 0.7) * period * 30)
                if frame < 14 then
                    local ripple = native(scene, "ripple", "gfx/1000.133_water ripple.anm2", "Poof")
                    ripple:SetFrame("Poof", frame)
                    draw(ripple, s.X, s.Y, 0.22, 0.22, color(1, 1, 1, alpha * 0.45))
                end
            end
        end
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
-- Five drops spread across the wait; the last lands eight ticks before the change.
function strikeLanding(scene, i)
    return scene.impact - 8 - (#RAIN_STRIKES - i) * math.floor((scene.impact - 14) / 5)
end
-- After the change the converted item dries over this many frames.
local RAIN_DRY = 45
function rainWetness(scene)
    if scene.frame >= scene.impact then return 1 - ease(scene.impact, scene.impact + RAIN_DRY, scene.frame) end
    local absorbed, total = 0, 0
    for i = 1, #RAIN_STRIKES do
        local landing = strikeLanding(scene, i)
        absorbed = absorbed + absorbedRain(scene.frame - landing)
        total = total + absorbedRain(scene.impact - 1 - landing)
    end
    return clamp(absorbed / total)
end

local function rainOnItem(scene, x, y)
    local f = scene.frame
    for i, offset in ipairs(RAIN_STRIKES) do
        local age = f - strikeLanding(scene, i)
        local hitX, hitY = x + offset, y - 6
        if age >= -12 and age < 0 then
            local progress = (age + 12) / 12
            local dropX, dropY = hitX + (1 - progress) * 9, hitY - (1 - progress) * 68
            line(scene, dropX + 1, dropY - 6, dropX, dropY, RAIN_HIT, ease(0, 12, f) * 0.9)
        elseif age >= 0 and age < 6 then
            local spread, fade = 1 + age * 0.9, 1 - age / 6
            line(scene, hitX - spread, hitY - 2, hitX - spread - 1, hitY - 4 + age * 0.5, RAIN_HIT, fade)
            line(scene, hitX + spread, hitY - 2, hitX + spread + 1, hitY - 4 + age * 0.5, RAIN_HIT, fade)
        end
    end
end

local function smoke(scene, x, y, scale, alpha)
    draw(asset(scene, "smoke"), x, y, scale, scale, color(1, 1, 1, alpha))
end
local function holy(scene, x, y, f)
    local age = math.floor((f - scene.impact) * 0.65)
    if age < 0 or age >= 24 then return end
    local s = native(scene, "holy", "gfx/1000.019_crack the sky.anm2", "Spotlight")
    s:SetFrame("Spotlight", age)
    draw(s, x, y + 17, 0.75)
end
-- The preview's fixed bolt: a glow, a core and one side branch.
local BOLT = { { -8, -136 }, { 5, -99 }, { -9, -75 }, { 6, -50 }, { -3, -30 }, { 0, 3 } }
local BOLT_BRANCH = { { 4, -100 }, { 29, -85 }, { 37, -61 } }
local function polyline(scene, x, y, points, rgb, width)
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        line(scene, x + a[1], y + a[2], x + b[1], y + b[2], rgb, 1, width)
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

-- Black over the left half of the screen, with a soft 24px edge at the middle.
local NEGLECT_FEATHER = 24
local function leftHalfDark(scene, alpha)
    if alpha <= 0 then return end
    local width, height = screenSize()
    local mid = width / 2
    scene.neglectMid = mid
    draw(asset(scene, "pixel"), 0, 0, mid - NEGLECT_FEATHER / 2, height, tint({ 0, 0, 0 }, alpha))
    for k = 0, NEGLECT_FEATHER / 2 - 1 do
        local fade = 1 - ease(-0.5, NEGLECT_FEATHER / 2 - 0.5, k)
        draw(asset(scene, "pixel"), mid - NEGLECT_FEATHER / 2 + k * 2, 0, 2, height, tint({ 0, 0, 0 }, alpha * fade))
    end
end

local function drawItem(scene, target, x, y, sx, sy, c, rotation)
    -- The colour actually applied to the item this frame (tests read it).
    sample(scene, "tint", { c.R, c.G, c.B, c.A, c.RO, c.GO, c.BO })
    if scene.pickupVisual then
        PickupVisual.render(scene.pickupVisual, x, y, sx, sy, c, rotation)
    else
        draw(target and scene.after or scene.before, x, y, sx, sy, c, rotation)
    end
end

function Visuals.render(scene)
    local f, effect = scene.frame, scene.profile.effect
    scene.rendered[f] = (scene.rendered[f] or 0) + 1
    local t, impact = f / 30, scene.impact
    local p = Isaac.WorldToScreen(scene.pos)
    local target = f >= impact
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

    if effect == "saturn" then
        Devour.render(scene, x, y, { ease = ease, draw = draw, drawItem = drawItem,
            color = color, line = line, rect = rect, sample = sample })
        return
    end

    -- Behind the item.
    if effect == "rain" then rain(scene, false) end
    if effect == "missile" then
        draw(native(scene, "target", "gfx/1000.030_dr. fetus target.anm2", "Idle"), x, y, 1, 1,
            color(1, 0.12, 0.12, windowed(3, 7.5, impact, impact + 3.6, f)))
    elseif effect == "purify" then
        local blessing = ease(12, 28, f) * (1 - ease(impact + 5, impact + 23, f))
        draw(asset(scene, "halo"), fx, fy - 32 + ease(12, 36, f) * 8, 1, 1, color(1, 1, 1, blessing))
        for i = 1, 7 do
            local a = i * PI / 3.5
            local burn = ease(24 + i, 48 + i, f)
            if burn < 1 then smoke(scene, fx + math.cos(a) * 23, fy + math.sin(a) * 15,
                0.22 * (1 - burn), (1 - burn) * ease(0, 12, f)) end
        end
    end

    local size, itemColor = 1, color(1, 1, 1, 1)
    if effect == "fire" or effect == "ice" then
        size = target and (0.7 + 0.3 * ease(impact, 70, f)) or 1
        local alpha = flameItemAlpha(scene, f)
        itemColor = color(1, 1, 1, alpha)
        sample(scene, "itemAlpha", alpha)
    elseif effect == "purify" then
        -- Interpolate each pixel toward white instead of adding brightness:
        -- additive white clips light colors and hides most of the return fade.
        local white = crownWhite(scene, f)
        itemColor = color(1 - white, 1 - white, 1 - white, 1, white)
        sample(scene, "white", white)
    elseif effect == "rain" then
        local wet = rainWetness(scene)
        itemColor = Color(1 - wet * 0.7, 1 - wet * 0.3, 1, 1, 0, wet * 0.05, wet * 0.35)
        sample(scene, "wet", wet)
    end
    drawItem(scene, target, x, y, size, size, itemColor)

    -- In front of the item.
    if effect and effect:find("clock", 1, true) then clock(scene, x, y, envelope) end
    if effect == "rain" then
        rain(scene, true)
        rainOnItem(scene, x, y)
    end
    if effect == "neglect" then
        local dark = neglectDarkness(scene, f)
        sample(scene, "neglect", dark)
        leftHalfDark(scene, dark)
    end
    if effect == "lightning" then
        -- The storm darkens early, holds until the strike and clears on it;
        -- only the strike's brief flash remains.
        local darkness = stormAlpha(scene, f)
        sample(scene, "darkness", darkness)
        stormDarkness(scene, x, y, darkness)
        if f >= impact and f < impact + 7 then
            screenVeil(scene, { 0.91, 0.96, 1 }, (1 - ease(impact, impact + 7, f)) * 0.55)
            polyline(scene, x, y, BOLT, BOLT_GLOW, 7)
            polyline(scene, x, y, BOLT, BOLT_CORE, 3)
            polyline(scene, x, y, BOLT_BRANCH, BOLT_CORE, 1)
        end
        if f >= impact then
            local spread = ease(impact, impact + 15.6, f)
            ring(scene, x, y + 26, 12 + 34 * spread, 4 + 8 * spread, BOLT_CORE, (1 - spread) * 0.75)
        end
    elseif effect == "fire" or effect == "ice" then
        local grow, settle = ease(4, impact, f), ease(impact, impact + 25, f)
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
        local launch = impact - 16
        if f >= launch and f < impact then
            local rocketY = y - 255 + 267 * ((f - launch) / 16) ^ 2
            draw(native(scene, "rocket", "gfx/1000.031_dr. fetus rocket.anm2", "Falling"), x, rocketY, 2.35)
            local exhaust = asset(scene, "fire")
            exhaust:SetFrame("Idle", math.floor(t * 15) % 6)
            draw(exhaust, x, rocketY - 132, 25 / 48, 25 / 48, color(1, 1, 1, 0.8))
        elseif f >= impact and f < impact + 19 then
            local explosion = native(scene, "explosion", "gfx/1000.001_bomb explosion.anm2", "Explosion")
            explosion:SetFrame("Explosion", f - impact)
            draw(explosion, x, y + 24, 1.1)
        end
    elseif effect == "purify" then
        holy(scene, fx, fy, f)
        for i, offset in ipairs({ { -17, -9 }, { 15, -14 }, { 5, 12 } }) do
            local age = f - impact - (i - 1) * 6
            if age >= 0 and age < 24 then
                -- door_sparkle exists in extracted files but is not loadable
                -- in the tested game. Use the native BLING effect animation.
                local glint = native(scene, "glint", "gfx/1000.103_ultragreedbling.anm2", "Bling1")
                glint:SetFrame("Bling1", math.floor(age / 3))
                draw(glint, fx + offset[1], fy + offset[2], 0.75, 0.75, color(1, 1, 1, 1 - ease(18, 24, age)))
            end
        end
    elseif effect == "void" then
        -- Motes keep their size and density while they gather into a swirling
        -- knot on the hilt; they vanish together within three ticks of the change.
        local vanish = voidVanish(scene, f)
        sample(scene, "vanish", vanish)
        for i = 0, 17 do
            local born = 0.08 + i * 0.036
            local progress = ease(born, impact / 30 - 0.1, t)
            local angle = i * 2.4 + progress * 2.9 + t * 2.2
            local radius = (18 + rand(i) * 7) * (1 - progress) + (3 + rand(i + 50) * 3) * progress
            local mote = (9 + rand(i + 30) * 5) * (1 - 0.3 * progress) * (1 - vanish)
            local fade = ease(born, born + 0.3, t) * (1 - vanish)
            if mote > 0.1 and fade > 0 then
                smoke(scene, x + math.cos(angle) * radius, y + 7 + math.sin(angle) * radius * 0.65, mote / 48, fade)
            end
        end
        ring(scene, x, y + 7, 2 + 2 * (1 - ease(0.2, 1.9, t)), 2, VOID_MARK, windowed(0.12, 0.5, 2.45, 3.1, t) * 0.65)
    end
end

-- Called once when the shared template ends a scene for any reason. Settles
-- the last cue checks and writes a one-line summary under debug mode.
function Visuals.finish(scene, reason)
    if not scene or scene.finished then return end
    scene.finished = reason or "ended"
    for _, cue in ipairs(scene.cues) do confirmCue(scene, cue) end
    if not debugOn() then return end
    local heard, frames, missing, marks = 0, 0, {}, 0
    for _, cue in ipairs(scene.cues) do if cue.heard then heard = heard + 1 end end
    -- Frame 0 is the creation frame; it is drawn only if a render precedes the first update.
    for f = 1, scene.frame do
        if scene.rendered[f] then frames = frames + 1 elseif #missing < 8 then missing[#missing + 1] = f end
    end
    for _ in pairs(scene.marks) do marks = marks + 1 end
    trace(scene, "SUMMARY", string.format(
        "reason=%s cues=%d heard=%d renderedFrames=%d/%d missing=%s marks=%d/%d floorRenders=%d failed=%s",
        tostring(reason), #scene.cues, heard, frames, scene.frame,
        #missing > 0 and table.concat(missing, ",") or "none", marks, #(scene.milestoneList or {}),
        scene.floorRenders, tostring(scene.failed == true)))
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
