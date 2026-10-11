-- Kronos's presentation: snapshots of the upgrading player's own familiars
-- ride the turned Saturn ring. Never retain or animate a live familiar.
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

function Devour.prepare(scene, owner)
    scene.pets, scene.petSource = Devour.snapshot(owner)
end

-- The turned Saturn ring, with the same numbers as the HTML preview's
-- ringPass. A slow build like MattPack's ~3 s whitening transformations:
-- pets fade in one by one already riding the orbit, circle faster and closer to the item
-- while it turns white, fuse into one golden ring, hold, collapse into the
-- item on the catalog's impact frame, and the result regains its colours.
-- The icon is the Saturn sign turned 232 degrees clockwise, so the ring and
-- the half that passes in front of the item turn with it.
local TILT = math.rad(-16 + 232)
local APPEAR_AT, APPEAR_STEP, APPEAR_LEN = 4, 8, 24
local SPIN_START = 40
local WHITE_START, COLOR_RETURN = 70, 45
local COLLAPSE = { 14, 10, 6, 2 }
local LAND = { { 1.25, .8 }, { .9, 1.12 }, { 1.04, .97 } }
local GOLD, PALE, SPARK = { .859, .698, .427 }, { 1, .945, .757 }, { .137, .098, .114 }

function Devour.frames(scene)
    return { impact = scene.impact, fuse = scene.impact - 12, collapse = scene.impact - 6 }
end

function Devour.ring(scene, f, x, y, ease)
    local fuse = scene.impact - 12
    local spin = ease(SPIN_START, fuse, f)
    local rx = 48 - 34 * spin
    local turn = 0
    -- The orbit turns from the first tick, slowly, so pets appear mid-orbit.
    for j = 0, f - 1 do turn = turn + .05 + .5 * ease(SPIN_START, fuse, j) end
    return { rx = rx, ry = rx * .27, spin = spin, turn = turn, cx = x, cy = y + 2 }
end

function Devour.point(ring, phase, rx, ry)
    local px, py = math.cos(phase) * (rx or ring.rx), math.sin(phase) * (ry or ring.ry)
    return ring.cx + px * math.cos(TILT) - py * math.sin(TILT),
        ring.cy + px * math.sin(TILT) + py * math.cos(TILT), math.sin(phase) > 0
end

-- Lerp-to-white strength of the item: rises before impact, then fades out.
function Devour.white(scene, f, ease)
    if f < scene.impact then
        local p = math.max(0, math.min(1, (f - WHITE_START) / (scene.impact - WHITE_START)))
        return p * p
    end
    return 1 - ease(scene.impact, scene.impact + COLOR_RETURN, f)
end

local function arc(scene, h, ring, rx, ry, from, to, rgb, alpha, width)
    local steps = math.max(2, math.ceil(math.abs(to - from) / (math.pi / 16)))
    local px, py = Devour.point(ring, from, rx, ry)
    for i = 1, steps do
        local x, y = Devour.point(ring, from + (to - from) * i / steps, rx, ry)
        h.line(scene, px, py, x, y, rgb, alpha, width)
        px, py = x, y
    end
end

local function spark(scene, h, x, y)
    -- The preview's 3 px cross: a dark outline under a pale core.
    h.rect(scene, x - 3, y, 7, 1, SPARK, 1); h.rect(scene, x, y - 3, 1, 7, SPARK, 1)
    h.rect(scene, x - 2, y, 5, 1, PALE, 1); h.rect(scene, x, y - 2, 1, 5, PALE, 1)
end

local function pass(scene, h, x, y, front)
    local f, k = scene.frame, Devour.frames(scene)
    local ring = Devour.ring(scene, f, x, y, h.ease)
    local count = math.max(1, #scene.pets)
    local glow = f < k.impact and h.ease(36, 60, f) or 0
    if glow > 0 then
        local size = f >= k.collapse and COLLAPSE[math.min(4, f - k.collapse + 1)] or ring.rx
        local bright = f >= k.fuse
        arc(scene, h, ring, size, math.max(1, size * .27), front and 0 or math.pi, front and math.pi or 2 * math.pi,
            bright and PALE or GOLD, glow * (bright and 1 or .75), bright and 3 or 1.5)
    end
    for i, pet in ipairs(scene.pets) do
        local born = APPEAR_AT + (i - 1) * APPEAR_STEP
        local show = h.ease(born, born + APPEAR_LEN, f)
        if show > 0 and f < k.fuse then
            local phase = ring.turn + (i - 1) * 2 * math.pi / count + math.pi
            local ox, oy, near = Devour.point(ring, phase)
            if near == front then
                if ring.spin > .2 then
                    arc(scene, h, ring, ring.rx, ring.ry, phase - .6 * ring.spin, phase, GOLD, .45 * ring.spin, 2)
                end
                local s = (1 - .55 * ring.spin) * (.3 + .7 * show)
                -- Familiar art sits above its pivot; centre it on the orbit.
                h.draw(pet, ox, oy + 10 * s, s, s, h.color(1, 1, 1, show))
            end
        end
    end
    if front and f >= k.fuse and f < k.fuse + 2 then
        for i = 1, #scene.pets do
            local px, py = Devour.point(ring, ring.turn + (i - 1) * 2 * math.pi / count + math.pi)
            spark(scene, h, px, py)
        end
    end
end

function Devour.render(scene, x, y, h)
    local f = scene.frame
    local white = Devour.white(scene, f, h.ease)
    if h.sample then h.sample(scene, "white", white) end
    -- Interpolate toward white (as the crown does) rather than adding light.
    local tint = h.color(1 - white, 1 - white, 1 - white, 1, white)
    pass(scene, h, x, y, false)
    if f < scene.impact then
        h.drawItem(scene, false, x, y, 1, 1, tint)
    else
        local land = LAND[f - scene.impact + 1] or { 1, 1 }
        h.drawItem(scene, true, x, y, land[1], land[2], tint)
    end
    pass(scene, h, x, y, true)
end

return Devour
