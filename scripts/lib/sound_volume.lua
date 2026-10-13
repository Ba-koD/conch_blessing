-- The player's sound settings from Mod Config Menu (user, 2026-10-13). Every
-- sound this mod plays passes its volume through Sound.volume, so one MCM
-- setting turns all of them up or down, and 진's rain has its own on top.
-- Settings are steps of 10% from 0 to 10; a missing or invalid value counts as
-- 100%, so the defaults sound exactly as before. Scaling only ever lowers a
-- volume, never raises it above the cue's own level.
local Sound = { STEPS = 10 }

-- The config keys MCM writes: every sound, and 진's rain loop.
Sound.ALL = "soundVolume"
Sound.RAIN = "rainVolume"

local function step(key)
    local config = type(ConchBlessing) == "table" and ConchBlessing.Config
    local value = type(config) == "table" and tonumber(config[key])
    if not value then return 1 end
    return math.max(0, math.min(Sound.STEPS, math.floor(value + 0.5))) / Sound.STEPS
end

-- The share of a cue's volume the settings let through; `kind` "rain" adds the
-- rain setting on top of the overall one.
function Sound.scale(kind)
    local share = step(Sound.ALL)
    if kind == "rain" then share = share * step(Sound.RAIN) end
    return share
end

-- A cue's volume after the player's settings.
function Sound.volume(volume, kind)
    return (volume or 1) * Sound.scale(kind)
end

return Sound
