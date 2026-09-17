-- Character base stats: what each vanilla PlayerType has before any item,
-- pickup, or effect changes it.
--
-- The engine hardcodes these per character and exposes no API for them
-- (REPENTOGON's EntityConfigPlayer has no stat fields either), so the rows
-- below are transcribed from the Binding of Isaac Rebirth Wiki source
-- "Template:Character Tables" (Repentance values). Each row keeps the wiki's
-- own terms so it can be audited line by line:
--   damage       base damage before the character multiplier (3.5 unless listed)
--   damageMult   character damage multiplier
--   tears        change to the Tears stat (tears-up units, not shots per second)
--   fireRateMult character fire rate multiplier, applied after the tear delay
--   shotSpeed, range, speed, luck   displayed values
--
-- Every result is returned in the units the HUD shows: shots per second for
-- tears and TearRange / 40 for range.
--
-- Limits: modded PlayerTypes use Isaac's row, Eden and Tainted Eden use the
-- centre of their random ranges, and conditional modifiers (Eve's Whore of
-- Babylon, Tainted Samson's berserk) are not part of the base.

local M = {}

local DEFAULT_ROW = {
    damage = 3.5,
    damageMult = 1.0,
    tears = 0,
    fireRateMult = 1.0,
    shotSpeed = 1.0,
    range = 6.5,
    speed = 1.0,
    luck = 0,
}

-- Fire rate page: "Fire Rate = (30 / (Tear Delay + 1) + S) * P", where the
-- tear delay comes from the Tears stat T with this piecewise formula.
local function tearDelayFromTearsStat(t)
    if t >= 0 then
        return 16 - 6 * math.sqrt(t * 1.3 + 1)
    elseif t > -0.77 then
        return 16 - 6 * math.sqrt(t * 1.3 + 1) - 6 * t
    end
    return 16 - 6 * t
end

local P = PlayerType
local ROWS = {
    [P.PLAYER_ISAAC] = {},
    [P.PLAYER_MAGDALENE] = { speed = 0.85 },
    [P.PLAYER_CAIN] = { damageMult = 1.20, range = 4.5, speed = 1.3 },
    [P.PLAYER_JUDAS] = { damageMult = 1.35 },
    [P.PLAYER_BLACKJUDAS] = { damageMult = 2.00, speed = 1.1 },
    [P.PLAYER_BLUEBABY] = { damageMult = 1.05, speed = 1.1 },
    [P.PLAYER_EVE] = { damageMult = 0.75, speed = 1.23 },
    [P.PLAYER_SAMSON] = { tears = -0.1, shotSpeed = 1.31, range = 5.0, speed = 1.1 },
    [P.PLAYER_AZAZEL] = { damageMult = 1.50, tears = 0.5, fireRateMult = 0.267, range = 4.5, speed = 1.25 },
    [P.PLAYER_LAZARUS] = { range = 4.5, luck = -1 },
    [P.PLAYER_LAZARUS2] = { damageMult = 1.40, speed = 1.25 },
    [P.PLAYER_EDEN] = {},
    [P.PLAYER_THELOST] = {},
    [P.PLAYER_LILITH] = {},
    [P.PLAYER_KEEPER] = { damageMult = 1.20, tears = -1.9, speed = 0.9, luck = -2 },
    [P.PLAYER_APOLLYON] = {},
    [P.PLAYER_THEFORGOTTEN] = { damageMult = 1.50, fireRateMult = 0.5 },
    [P.PLAYER_THESOUL] = { speed = 1.3 },
    [P.PLAYER_BETHANY] = {},
    [P.PLAYER_JACOB] = { damage = 2.75, tears = 0.277, shotSpeed = 1.15, range = 5, luck = 1 },
    [P.PLAYER_ESAU] = { damage = 3.75, tears = -0.1, shotSpeed = 0.85, range = 8, luck = -1 },

    [P.PLAYER_ISAAC_B] = {},
    [P.PLAYER_MAGDALENE_B] = { damageMult = 0.75 },
    [P.PLAYER_CAIN_B] = { damageMult = 1.20, range = 4.5, speed = 1.3 },
    [P.PLAYER_JUDAS_B] = { range = 4.5, speed = 1.23 },
    [P.PLAYER_BLUEBABY_B] = { tears = -0.35, speed = 0.9 },
    [P.PLAYER_EVE_B] = { damageMult = 1.20, tears = -0.5, fireRateMult = 0.66 },
    [P.PLAYER_SAMSON_B] = { tears = -0.1, range = 5 },
    [P.PLAYER_AZAZEL_B] = { damageMult = 1.50, fireRateMult = 1 / 3 },
    [P.PLAYER_LAZARUS_B] = { range = 4.5 },
    [P.PLAYER_LAZARUS2_B] = { damageMult = 1.50, tears = -0.1, speed = 0.9, luck = -2 },
    [P.PLAYER_EDEN_B] = {},
    [P.PLAYER_THELOST_B] = { damageMult = 1.30 },
    [P.PLAYER_LILITH_B] = { speed = 0.85 },
    [P.PLAYER_KEEPER_B] = { tears = -2.2, luck = -2 },
    [P.PLAYER_APOLLYON_B] = { tears = -0.5 },
    [P.PLAYER_THEFORGOTTEN_B] = { damageMult = 1.50, fireRateMult = 0.5 },
    -- The wiki lists no attack stats for Tainted Soul; it keeps the defaults.
    [P.PLAYER_THESOUL_B] = {},
    [P.PLAYER_BETHANY_B] = {},
    [P.PLAYER_JACOB_B] = { tears = 0.277 },
}
-- Tainted Jacob's ghost form is not listed separately; it is the same character.
ROWS[P.PLAYER_JACOB2_B] = ROWS[P.PLAYER_JACOB_B]

local function resolveRow(row)
    local value = function(key)
        local v = row[key]
        if v == nil then v = DEFAULT_ROW[key] end
        return v
    end
    return {
        Speed = value("speed"),
        Tears = 30 / (tearDelayFromTearsStat(value("tears")) + 1) * value("fireRateMult"),
        Damage = value("damage") * value("damageMult"),
        Range = value("range"),
        ShotSpeed = value("shotSpeed"),
        Luck = value("luck"),
    }
end

local DEFAULT_STATS = resolveRow(DEFAULT_ROW)
local STATS_BY_TYPE = {}
for playerType, row in pairs(ROWS) do
    STATS_BY_TYPE[playerType] = resolveRow(row)
end

---Base stats for a PlayerType, keyed Speed/Tears/Damage/Range/ShotSpeed/Luck.
---@param playerType PlayerType
---@return table stats
---@return boolean known false when the type has no vanilla row (modded character)
function M.getForType(playerType)
    local stats = STATS_BY_TYPE[playerType]
    if stats then
        return stats, true
    end
    return DEFAULT_STATS, false
end

---@param player EntityPlayer
function M.get(player)
    return M.getForType(player:GetPlayerType())
end

return M
