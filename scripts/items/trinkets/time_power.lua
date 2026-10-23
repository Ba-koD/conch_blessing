local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local TimerClock = require("scripts.lib.timer_clock")
ConchBlessing.timepowertrinket = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local Hits = require("scripts.lib.player_hits")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

-- Data container (persistable gameplay constants)
ConchBlessing.timepowertrinket.data = {
    increasePerSecond = 0.006, -- damage gained per second while held
    pauseSecondsOnHit = 60,    -- pause duration after taking damage
    keepOnDrop = true,        -- keep bonus when dropped (convert to permanent)
    framesPerSecond = 30       -- frame rate baseline for per-frame delta
}

-- Runtime state belongs to the exact player entity and is rebuilt every
-- session; what the player earned lives in that player's own run save, which
-- SaveManager keys by the player's collectible RNG seed. So a same-type co-op
-- player, Esau or Strawman grows and pauses on its own, and a character change
-- (Lazarus, Clicker) keeps what was earned.
local function getKey(player)
    return GetPtrHash(player)
end

local function ensureState()
    ConchBlessing.timepowertrinket.state = ConchBlessing.timepowertrinket.state or { perPlayer = {} }
    return ConchBlessing.timepowertrinket.state
end

TimerClock.onRebase("timepowertrinket", function(delta)
    for _, state in pairs(ensureState().perPlayer) do
        state.pausedUntilFrame = (state.pausedUntilFrame or 0) + delta
    end
end)

local loadFromSave

local function newPlayerState()
    return {
        damageBonus = 0.0,
        permanentBonus = 0.0,
        pausedUntilFrame = 0,
        hadTrinketLastFrame = false,
        lastApplied = 0.0,
    }
end

-- A player first seen this session (Continue, a reload, a player added
-- mid-run) starts from its own saved record.
local function getPlayerState(player)
    local s = ensureState()
    local key = getKey(player)
    local ps = s.perPlayer[key]
    if not ps then
        ps = newPlayerState()
        s.perPlayer[key] = ps
        loadFromSave(player, ps)
    end
    return ps
end
ConchBlessing.timepowertrinket.getPlayerState = getPlayerState

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

-- The player's own record in its run save. Older saves nested it under the
-- PlayerType; those records are folded in once.
local function getRecord(player)
    local save = SaveManager.GetRunSave(player)
    if type(save) ~= "table" then return nil end
    if type(save.timePower) ~= "table" then save.timePower = {} end
    local rec = save.timePower
    TrinketUtils.migrateTimeRecord(rec, player:GetPlayerType(), "damageBonus",
        ConchBlessing.timepowertrinket.data.keepOnDrop)
    return rec
end

-- Persist run data via SaveManager
loadFromSave = function(player, ps)
    local id = getTrinketId()
    if not id then return end
    local rec = getRecord(player)
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
        local currentFrame = TimerClock.now()
        ps.pausedUntilFrame = currentFrame + remainingFrames
        writePauseTimerRecord(rec, ps, currentFrame)
    end
end

local function saveToSave(player)
    local id = getTrinketId()
    if not id then return end
    local ps = getPlayerState(player)
    local rec = getRecord(player)
    if not rec then return end
    rec.damageBonus = ps.damageBonus
    rec.permanentBonus = ps.permanentBonus
    writePauseTimerRecord(rec, ps, TimerClock.now())
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
            local getSaveIndex = SaveManager.Utility and SaveManager.Utility.GetSaveIndex
            if type(runData) ~= "table" or type(getSaveIndex) ~= "function" then return end
            local perPlayer = ensureState().perPlayer
            local currentFrame = TimerClock.now()
            local game = Game()
            for i = 0, game:GetNumPlayers() - 1 do
                local p = game:GetPlayer(i)
                local ps = p and perPlayer[getKey(p)]
                local playerRun = ps and runData[getSaveIndex(p)]
                local rec = type(playerRun) == "table" and playerRun.timePower
                if type(rec) == "table" then
                    writePauseTimerRecord(rec, ps, currentFrame)
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
    local frame = TimerClock.now()
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
				-- The engine's trinket multiplier: +1 per normal copy, +2 per golden
				-- copy, +1 once for Mom's Box.
				local mult = TrinketUtils.getMultiplier(p, id)
                if mult <= 0 then goto after_growth end
                local perSecond = (ConchBlessing.timepowertrinket.data.increasePerSecond or 0) * mult
                local delta = perSecond / fps -- per-frame with stacking
                ps.damageBonus = ps.damageBonus + delta
                -- Evaluate every frame at 30 FPS (lightweight enough)
                p:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
                p:EvaluateItems()
				-- Only report when the stack composition changes. This block used to
				-- fire twice a second for as long as the trinket was held.
				local logKey = tostring(mult)
				if ps.lastLogKey ~= logKey then
				    ps.lastLogKey = logKey
					if ConchBlessing.Config and ConchBlessing.Config.debugMode then
						local normalCount, goldenCount, hasMomsBox = TrinketUtils.getTrinketCounts(p, id)
						ConchBlessing.printDebug(string.format("[Time=Power] perSecond=%.6f perTick=%.6f (mult=%d: normal=%d golden=%d momsBox=%s)",
							perSecond, delta, mult, normalCount, goldenCount, tostring(hasMomsBox)))
					end
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
    if not Hits.counts(flags) then
        ConchBlessing.printDebug(string.format("[Time=Power] ignore pause by flags=%d", flags or -1))
        return
    end
    local ps = getPlayerState(player)
    local frame = TimerClock.now()
    ps.pausedUntilFrame = math.max(ps.pausedUntilFrame or 0, frame + getPauseDurationFrames())
    saveToSave(player)
    return true
end
Hits.register("TIME_POWER", ConchBlessing.timepowertrinket.onEntityTakeDamage)

-- Load state at game start
function ConchBlessing.timepowertrinket.onGameStarted(_, isContinued)
    local game = Game()
    local num = game:GetNumPlayers()
    -- Entity hashes from an earlier session mean nothing now.
    ensureState().perPlayer = {}
    for i = 0, num - 1 do
        local p = game:GetPlayer(i)
        if isContinued then
            -- Normal continue: restore saved bonuses
            getPlayerState(p)
        else
            -- New run (R key): reset run-scoped bonuses
            ensureState().perPlayer[getKey(p)] = newPlayerState()
            saveToSave(p)
        end
        -- reflect current state to cache
        p:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        p:EvaluateItems()
    end
end
