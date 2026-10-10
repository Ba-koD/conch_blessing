-- Kronos's presentation snapshot. Never retain or animate a live familiar.
local Devour = {}
local fallback = {
    { "gfx/003.001_brother bobby.anm2", "FloatDown" },
    { "gfx/003.002_demon baby.anm2", "FloatDown" },
    { "gfx/003.005_little steve.anm2", "FloatDown" },
    { "gfx/003.006_robo-baby.anm2", "FloatDown" },
    { "gfx/003.010_harlequin baby.anm2", "FloatDown" },
}
local serial = 0
local function samePlayer(a, b)
    return a and b and (a == b or (GetPtrHash and GetPtrHash(a) == GetPtrHash(b)))
end

local function copySprite(source)
    -- REPENTOGON Copy preserves modded sheets/layers. Older builds can still
    -- reconstruct the familiar's own ANM2 pose, without editing its live sprite.
    if source.Copy then
        local ok, result = pcall(source.Copy, source)
        if ok and result and result ~= source then return result end
    end
    local result = Sprite()
    result:Load(source:GetFilename(), true)
    if result.IsLoaded and not result:IsLoaded() then error("familiar ANM2 load failed") end
    result:SetFrame(source:GetAnimation(), source:GetFrame())
    if source.GetOverlayAnimation and result.SetOverlayFrame then
        local overlay = source:GetOverlayAnimation()
        if overlay and overlay ~= "" then result:SetOverlayFrame(overlay, source:GetOverlayFrame()) end
    end
    result.FlipX, result.FlipY = source.FlipX, source.FlipY
    return result
end

function Devour.snapshot(owner)
    -- The provider's global result has no initiating-player field. A single
    -- player is unambiguous; co-op requires an explicit owner from the caller.
    -- Unknown ownership never borrows another player's pets or invents a roster.
    if not owner and Game():GetNumPlayers() == 1 then owner = Isaac.GetPlayer(0) end
    local pets, owned = {}, {}
    if not owner then return pets, "unknown" end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local familiar = entity:ToFamiliar()
        if familiar and samePlayer(familiar.Player, owner) then owned[#owned + 1] = familiar end
    end
    table.sort(owned, function(a, b) return a.InitSeed < b.InitSeed end)
    serial = serial + 1
    -- Local cosmetic PRNG. Do not advance player, item, room or Lua math.random RNG.
    local seed = ((owner.InitSeed or 1) + serial * 997) % 2147483647
    if seed == 0 then seed = 1 end
    local function pick(n) seed = (seed * 16807) % 2147483647; return seed % n + 1 end
    if #owned > 0 then
        while #owned > 0 and #pets < 3 do
            local familiar = table.remove(owned, pick(#owned))
            local ok, result = pcall(copySprite, familiar:GetSprite())
            if ok then pets[#pets + 1] = result
            else ConchBlessing.printError("[ConchMorph] familiar snapshot: " .. tostring(result)) end
        end
        return pets, "owned"
    end
    local choices = { 1, 2, 3, 4, 5 }
    while #pets < 3 and #choices > 0 do
        local spec = fallback[table.remove(choices, pick(#choices))]
        local s = Sprite(); s:Load(spec[1], true); s:SetFrame(spec[2], 0)
        if s.IsLoaded and not s:IsLoaded() then error("missing familiar illustration: " .. spec[1]) end
        pets[#pets + 1] = s
    end
    return pets, "random"
end

function Devour.prepare(scene, owner, asset)
    scene.pets, scene.petSource = Devour.snapshot(owner)
    local feedEnd = 18 + math.max(0, #scene.pets - 1) * 14 + 20
    local open = feedEnd + 8
    scene.devour = { first = 18, spacing = 14, feedEnd = feedEnd,
        open = open, swallow = open + 2, swallowed = open + 5,
        close = open + 2, closed = open + 6, gone = open + 10 }
    scene.impact = scene.devour.gone
    scene.duration = scene.impact + 24
    for _, part in ipairs({ "all", "upper", "lower", "sides" }) do asset(scene, "maw_" .. part) end
end

local function clamp(value) return math.max(0, math.min(1, value)) end
local function ease(a, b, f)
    local p = clamp((f - a) / (b - a))
    return p * p * (3 - 2 * p)
end

function Devour.petPose(scene, index, f, x, y)
    local start = scene.devour.first + (index - 1) * scene.devour.spacing
    local pull = clamp((f - start) / 20) ^ 2.6
    local angle = -math.pi * .96 + (index - 1) * 1.11
    -- A short outward drag precedes accelerating suction. No orbit, spin,
    -- bouncing, hands or feeding mouth are added to the BFF heart.
    local tension = ease(start - 5, start, f) * (1 - pull) * 3
    local radius = 60 + tension
    local px, py = x + math.cos(angle) * radius * (1 - pull), y + 3 + math.sin(angle) * radius * .75 * (1 - pull)
    local scale = (1 - .94 * ease(.2, 1, pull))
    return { x = px, y = py, pull = pull, scale = scale,
        alpha = ease(2, 9, f) * (1 - ease(.8, 1, pull)),
        angle = math.deg(angle), visible = f < start + 20 }
end

function Devour.mawPose(scene, f)
    local k = scene.devour
    local opening = ease(k.open - 1, k.open + 1, f)
    local closing = ease(k.close, k.closed, f)
    -- An abrupt apparition at the item's depth, never a jaw sliding down from
    -- above. It seizes the heart in six ticks and is gone four ticks later.
    return { width = 112, yOffset = 0, gape = opening * (1 - closing),
        alpha = ease(k.open - 1, k.open, f) * (1 - ease(k.closed + 1, k.gone, f)) }
end

function Devour.render(scene, x, y, h)
    local f, k = scene.frame, scene.devour
    local draw, asset, color = h.draw, h.asset, h.color
    local mouth = Devour.mawPose(scene, f)
    local scale = mouth.width / 64
    local mouthY = y + mouth.yOffset
    if mouth.alpha > 0 then
        -- Only the black cavity changes height. Teeth/gums keep their shape;
        -- the two separate jaws translate toward each other to deliver the bite.
        draw(asset(scene, "maw_all"), x, mouthY, scale, scale * (.15 + .85 * mouth.gape),
            color(.025, .018, .025, mouth.alpha))
    end
    local function jaws()
        if mouth.alpha <= 0 then return end
        local shift = 14 * scale * (1 - mouth.gape)
        draw(asset(scene, "maw_upper"), x, mouthY + shift, scale, scale, color(1, 1, 1, mouth.alpha))
        draw(asset(scene, "maw_lower"), x, mouthY - shift, scale, scale, color(1, 1, 1, mouth.alpha))
        draw(asset(scene, "maw_sides"), x, mouthY, scale, scale * (.46 + .54 * mouth.gape),
            color(1, 1, 1, mouth.alpha))
    end
    -- The whole apparition starts BEHIND the item; only the closing tooth
    -- rows cross in front while it is seized into the depth of the throat.
    if f < k.close then jaws() end
    for i, pet in ipairs(scene.pets) do
        local p = Devour.petPose(scene, i, f, x, y)
        if p.visible and p.alpha > 0 then
            if p.pull > .03 then
                for trail = 2, 1, -1 do
                    local old = Devour.petPose(scene, i, f - trail * 2, x, y)
                    draw(pet, old.x, old.y + 10 * old.scale, old.scale, old.scale,
                        color(.35, .25, .32, p.alpha * .12 / trail))
                end
            end
            local shade = 1 - .6 * p.pull
            draw(pet, p.x, p.y + 10 * p.scale, p.scale, p.scale,
                color(shade, shade, shade, p.alpha))
        end
    end
    if f < scene.impact then
        local swallow = ease(k.swallow, k.swallowed, f)
        if f < k.swallowed then
            local shade = 1 - .75 * swallow
            h.drawItem(scene, false, x, y, 1 - swallow * .96,
                1 - swallow * .96, color(shade, shade, shade, 1 - ease(.65, 1, swallow)))
        end
    else
        -- The closed jaws already conceal the change. Reveal at their last
        -- visible frame, without an empty pause or a second fade from zero.
        h.drawItem(scene, true, x, y, 1, 1, color(1, 1, 1, 1))
    end
    if f >= k.close then jaws() end
end

return Devour
