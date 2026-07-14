ConchBlessing.timepowertrinket = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

-- Data container (persistable gameplay constants)
ConchBlessing.timepowertrinket.data = {
    increasePerSecond = 0.006, -- damage gained per second while held
    pauseSecondsOnHit = 60,    -- pause duration after taking damage
    keepOnDrop = true,        -- keep bonus when dropped (convert to permanent)
    framesPerSecond = 30       -- frame rate baseline for per-frame delta
}

-- Internal state keys
local function getKey(player)
    return tostring(player:GetPlayerType())
end

local function ensureState()
    ConchBlessing.timepowertrinket.state = ConchBlessing.timepowertrinket.state or { perPlayer = {} }
    return ConchBlessing.timepowertrinket.state
end

local function getPlayerState(player)
    local s = ensureState()
    local key = getKey(player)
    s.perPlayer[key] = s.perPlayer[key] or {
        damageBonus = 0.0,
        permanentBonus = 0.0,
        pausedUntilFrame = 0,
        hadTrinketLastFrame = false,
        lastApplied = 0.0,
    }
    return s.perPlayer[key]
end

local function getPauseFramesRemaining(ps, currentFrame)
    local pausedUntilFrame = tonumber(ps and ps.pausedUntilFrame) or currentFrame
    return math.max(0, math.floor(pausedUntilFrame - currentFrame))
end

local function getPauseDurationFrames()
    return math.max(0, math.floor((tonumber(ConchBlessing.timepowertrinket.data.pauseSecondsOnHit) or 0) * 30))
end

local function writePauseTimerRecord(rec, ps, currentFrame)
    rec.pauseFramesRemaining = math.min(getPauseDurationFrames(), getPauseFramesRemaining(ps, currentFrame))
    rec.pausedUntilFrame = nil
end

local function getTrinketId()
    return ConchBlessing.ItemData.TIME_POWER and ConchBlessing.ItemData.TIME_POWER.id
end

-- Persist run data via SaveManager
local function loadFromSave(player)
    local id = getTrinketId()
    if not id then return end
    local save = SaveManager.GetRunSave(player)
    if not save then return end
    save.timePower = save.timePower or {}
    local key = getKey(player)
    local ps = getPlayerState(player)
    local rec = save.timePower[key]
    if rec then
        ps.damageBonus = tonumber(rec.damageBonus) or 0.0
        ps.permanentBonus = tonumber(rec.permanentBonus) or 0.0
        ps.lastApplied = tonumber(rec.lastApplied) or 0.0
        if rec.data then
            -- load persisted constants if present
            local d = rec.data
            if type(d.increasePerSecond) == 'number' then ConchBlessing.timepowertrinket.data.increasePerSecond = d.increasePerSecond end
            if type(d.pauseSecondsOnHit) == 'number' then ConchBlessing.timepowertrinket.data.pauseSecondsOnHit = d.pauseSecondsOnHit end
            if type(d.keepOnDrop) == 'boolean' then ConchBlessing.timepowertrinket.data.keepOnDrop = d.keepOnDrop end
            if type(d.framesPerSecond) == 'number' then ConchBlessing.timepowertrinket.data.framesPerSecond = d.framesPerSecond end
        end
        -- Legacy absolute frames cannot be related to a new gameplay session safely.
        local remainingFrames = math.max(0, math.min(getPauseDurationFrames(), math.floor(tonumber(rec.pauseFramesRemaining) or 0)))
        local currentFrame = Game():GetFrameCount()
        ps.pausedUntilFrame = currentFrame + remainingFrames
        writePauseTimerRecord(rec, ps, currentFrame)
    end
end

local function saveToSave(player)
    local id = getTrinketId()
    if not id then return end
    local save = SaveManager.GetRunSave(player)
    if not save then return end
    save.timePower = save.timePower or {}
    local key = getKey(player)
    local ps = getPlayerState(player)
    save.timePower[key] = save.timePower[key] or {}
    local rec = save.timePower[key]
    rec.damageBonus = ps.damageBonus
    rec.permanentBonus = ps.permanentBonus
    writePauseTimerRecord(rec, ps, Game():GetFrameCount())
    rec.data = {
        increasePerSecond = ConchBlessing.timepowertrinket.data.increasePerSecond,
        pauseSecondsOnHit = ConchBlessing.timepowertrinket.data.pauseSecondsOnHit,
        keepOnDrop = ConchBlessing.timepowertrinket.data.keepOnDrop,
        framesPerSecond = ConchBlessing.timepowertrinket.data.framesPerSecond,
    }
    rec.lastApplied = ps.lastApplied
    SaveManager.Save()
end

do
    local mod = ConchBlessing and ConchBlessing.originalMod
    if mod and mod.__SAVEMANAGER_UNIQUE_KEY and SaveManager.SaveCallbacks then
        local callbackKey = SaveManager.SaveCallbacks.PRE_DATA_SAVE
        mod:AddCallback(callbackKey, function(_, saveData)
            local runData = saveData and saveData.game and saveData.game.run
            local perPlayer = ensureState().perPlayer
            local currentFrame = Game():GetFrameCount()
            for _, playerRun in pairs(runData or {}) do
                for key, rec in pairs((playerRun and playerRun.timePower) or {}) do
                    local ps = perPlayer[key]
                    if ps and type(rec) == "table" then
                        writePauseTimerRecord(rec, ps, currentFrame)
                    end
                end
            end
        end)
    end
end

-- Public: allow toggling drop reset behavior
function ConchBlessing.timepowertrinket.SetKeepOnDrop(player, keep)
    ConchBlessing.timepowertrinket.data.keepOnDrop = keep == true
    -- persist setting for this run by saving with current player's record
    saveToSave(player)
end

-- Cache application for damage
function ConchBlessing.timepowertrinket.onEvaluateCache(_, player, cacheFlag)
     if cacheFlag ~= CacheFlag.CACHE_DAMAGE then return end
     local ps = getPlayerState(player)
     local bonus = (ps.permanentBonus or 0.0)
     local id = getTrinketId()
     if id and player:HasTrinket(id) then
         bonus = bonus + (ps.damageBonus or 0.0)
     end
    ConchBlessing.printDebug(string.format("[Time=Power] onEvaluateCache: bonus=%.6f (perm=%.6f, temp=%.6f)", bonus, ps.permanentBonus or 0.0, ps.damageBonus or 0.0))
     if bonus ~= 0 then
        -- Apply via stats library to keep consistency with other modifiers
        local minD = (ConchBlessing.stats and ConchBlessing.stats.BASE_STATS and ConchBlessing.stats.BASE_STATS.damage or 0.1) * 0.4
        if ConchBlessing.stats and ConchBlessing.stats.damage and ConchBlessing.stats.damage.applyAddition then
            ConchBlessing.stats.damage.applyAddition(player, bonus, minD)
        else
            player.Damage = player.Damage + bonus
        end
     end
 end

-- Update growth and handle drop-reset
function ConchBlessing.timepowertrinket.onUpdate()
    local game = Game()
    local frame = game:GetFrameCount()
    local num = game:GetNumPlayers()
    for i = 0, num - 1 do
        local p = game:GetPlayer(i)
        local ps = getPlayerState(p)
        local has = false
        local id = getTrinketId()
        if id then has = p:HasTrinket(id) end

        -- Detect drop (transition from had->not have)
        if ps.hadTrinketLastFrame and not has then
            if ConchBlessing.timepowertrinket.data.keepOnDrop then
                -- convert current bonus to permanent and reset session bonus
                ps.permanentBonus = (ps.permanentBonus or 0.0) + (ps.damageBonus or 0.0)
                ps.damageBonus = 0.0
                ps.lastApplied = 0.0
                saveToSave(p)
                p:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
                p:EvaluateItems()
                ConchBlessing.printDebug("[Time=Power] Keep-on-drop: converted to permanent")
            else
                -- reset completely
                ps.damageBonus = 0.0
                ps.lastApplied = 0.0
                saveToSave(p)
                p:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
                p:EvaluateItems()
                ConchBlessing.printDebug("[Time=Power] Reset on drop")
            end
        end

        ps.hadTrinketLastFrame = has

        -- Growth when held and not paused
        if has then
            if frame >= ps.pausedUntilFrame then
                local fps = ConchBlessing.timepowertrinket.data.framesPerSecond or 30
                if fps <= 0 then fps = 30 end
				-- Compute effective stacks with golden and Mom's Box rules (via util)
				local normalCount, goldenCount, hasMomsBox = TrinketUtils.getTrinketCounts(p, id)
				local mult = (normalCount * (hasMomsBox and 2 or 1)) + (goldenCount * (hasMomsBox and 3 or 2))
                if mult <= 0 then goto after_growth end
                local perSecond = (ConchBlessing.timepowertrinket.data.increasePerSecond or 0) * mult
                local delta = perSecond / fps -- per-frame with stacking
                ps.damageBonus = ps.damageBonus + delta
                -- Evaluate every frame at 30 FPS (lightweight enough)
                p:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
                p:EvaluateItems()
				if frame % fps == 0 then
					-- Print current per-second and per-tick increase without cumulative totals
					ConchBlessing.printDebug(string.format("[Time=Power] perSecond=%.6f perTick=%.6f (mult=%d, momsBox=%s)", perSecond, delta, mult, tostring(hasMomsBox)))
					-- Breakdown of contributions
					local normalUnit = (hasMomsBox and 2 or 1)
					local goldenUnit = (hasMomsBox and 3 or 2)
					local contribNormal = normalCount * normalUnit
					local contribGolden = goldenCount * goldenUnit
					ConchBlessing.printDebug(string.format("[Time=Power] counts normal=%d unit=%d ->%d, golden=%d unit=%d ->%d", normalCount, normalUnit, contribNormal, goldenCount, goldenUnit, contribGolden))
				end
                -- Periodically save to avoid excessive IO
                if frame % 90 == 0 then -- every ~3 seconds
                    saveToSave(p)
                end
                ::after_growth::
            end
        end
    end
end

-- Pause growth on taking damage
function ConchBlessing.timepowertrinket.onEntityTakeDamage(_, entity, amount, flags, source, countdown)
    local player = entity:ToPlayer()
    if not player then return end
    local id = getTrinketId()
    if not id then return end
    if not player:HasTrinket(id) then return end
    if DamageUtils.isSelfInflictedDamage(flags, source) then
        ConchBlessing.printDebug(string.format("[Time=Power] ignore pause by flags=%d", flags or -1))
        return
    end
    local ps = getPlayerState(player)
    local frame = Game():GetFrameCount()
    ps.pausedUntilFrame = math.max(ps.pausedUntilFrame or 0, frame + getPauseDurationFrames())
    saveToSave(player)
    return nil
end

-- Load state at game start
function ConchBlessing.timepowertrinket.onGameStarted(_, isContinued)
    local game = Game()
    local num = game:GetNumPlayers()
    for i = 0, num - 1 do
        local p = game:GetPlayer(i)
        if isContinued then
            -- Normal continue: restore saved bonuses
            loadFromSave(p)
        else
            -- New run (R key): reset run-scoped bonuses
            local ps = getPlayerState(p)
            ps.damageBonus = 0.0
            ps.permanentBonus = 0.0
            ps.lastApplied = 0.0
            ps.pausedUntilFrame = 0
            ps.hadTrinketLastFrame = false
            saveToSave(p)
        end
        -- reflect current state to cache
        p:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        p:EvaluateItems()
    end
end
