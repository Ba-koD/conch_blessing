local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 에이징 커브 (Aging Curve), the Magic Conch's neutral answer to Growth Hormones
-- (user decision 2026-11-24). Growth Hormones gives the same stats all run;
-- this spends them where a run is weakest, at its start: every stat but luck
-- falls by the same step every stage, from large on stage 1 to nothing on
-- stage 6 and below nothing after it, while luck rises by 1 a stage from stage
-- 4 (the veteran's know-how). The user's numbers (2026-11-24): damage
-- 9 - 1.5 x stage, tears 3 - 0.5 x stage, range 6 - stage tiles, shot speed
-- and speed 0.6 - 0.1 x stage. The item sets no floor of its own: the user
-- leaves the lowest values to the engine. The stats follow the floor the
-- player is on, so nothing is saved: a
-- new floor re-evaluates every holder. Greed Mode floors count as two each,
-- and the Ascent counts as the late game, so a run's way back up does not
-- make the player young again. Copies add up. Base API only.
local M = {}
ConchBlessing.agingCurve = M

local ID = Isaac.GetItemIdByName("Aging Curve")

M.data = {
    zeroAt = 6,           -- the stage where every stat but luck is nothing
    -- Per copy, lost each stage (range in TearRange units: 40 is a tile).
    step = { damage = 1.5, tears = 0.5, speed = 0.1, range = 40, shotSpeed = 0.1 },
    luckFrom = 4,         -- the first stage with luck: +1 there, +1 more each stage
    luckStep = 1,
    ascentStage = 12,     -- the stage the Ascent counts as
}

-- One entry per stat: StatsAPI's table and the cache flag it is evaluated on.
local RULES = {
    { field = "damage", flag = CacheFlag.CACHE_DAMAGE },
    { field = "tears", flag = CacheFlag.CACHE_FIREDELAY },   -- shots per second
    { field = "speed", flag = CacheFlag.CACHE_SPEED },
    { field = "range", flag = CacheFlag.CACHE_RANGE },
    { field = "shotSpeed", flag = CacheFlag.CACHE_SHOTSPEED },
    { field = "luck", flag = CacheFlag.CACHE_LUCK },
}
local ALL_FLAGS = 0
for _, rule in ipairs(RULES) do ALL_FLAGS = ALL_FLAGS | rule.flag end

-- ------------------------------------------------------------------ pure rules
-- The stage that counts for a level: its own number, a Greed Mode floor as
-- two (1, 3, 5 ...), the Ascent as the late game.
local function stageOf(levelStage, greed, ascent)
    if ascent then return M.data.ascentStage end
    local stage = math.max(1, math.floor(tonumber(levelStage) or 1))
    if greed then stage = math.min(13, 2 * stage - 1) end
    return stage
end

-- The change of `field` with `copies` held at `stage`.
local function amount(field, stage, copies)
    local d = M.data
    copies = math.max(0, math.floor(tonumber(copies) or 0))
    if field == "luck" then
        return math.max(0, stage - d.luckFrom + 1) * d.luckStep * copies
    end
    return (d.zeroAt - stage) * (d.step[field] or 0) * copies
end

local function currentStage()
    local game = Game()
    local level = game:GetLevel()
    local ascent = type(level.IsAscent) == "function" and level:IsAscent() or false
    return stageOf(level:GetStage(), game:IsGreedMode(), ascent)
end

-- ------------------------------------------------------------------ callbacks
function M.onEvaluateCache(_, player, flag)
    if ID <= 0 or not player then return end
    local copies = player:GetCollectibleNum(ID)
    if copies <= 0 then return end
    for _, rule in ipairs(RULES) do
        if flag == rule.flag then
            local value = amount(rule.field, currentStage(), copies)
            local stat = ConchBlessing.stats and ConchBlessing.stats[rule.field]
            if value ~= 0 and stat and stat.applyAddition then stat.applyAddition(player, value, nil) end
            return
        end
    end
end

-- A new floor moves every holder along the curve.
function M.onNewLevel()
    if ID <= 0 then return end
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:GetCollectibleNum(ID) > 0 then
            player:AddCacheFlags(ALL_FLAGS)
            player:EvaluateItems()
        end
    end
end

M._test = {
    stageOf = stageOf,
    amount = amount,
    currentStage = currentStage,
    rules = RULES,
}

return M
