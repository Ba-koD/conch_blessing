ConchBlessing.timelucktrinket = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

-- Data container (persistable gameplay constants)
ConchBlessing.timelucktrinket.data = {
	increasePerSecond = 0.01,  -- luck gained per second while held
	pauseSecondsOnHit = 60,    -- pause duration after taking damage
	keepOnDrop = true,        -- keep bonus when dropped (convert to permanent)
	framesPerSecond = 30       -- frame rate baseline for per-frame delta
}

-- Internal state keys
local function getKey(player)
	return tostring(player:GetPlayerType())
end

local function ensureState()
	ConchBlessing.timelucktrinket.state = ConchBlessing.timelucktrinket.state or { perPlayer = {} }
	return ConchBlessing.timelucktrinket.state
end

local function getPlayerState(player)
	local s = ensureState()
	local key = getKey(player)
	s.perPlayer[key] = s.perPlayer[key] or {
		luckBonus = 0.0,
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
	return math.max(0, math.floor((tonumber(ConchBlessing.timelucktrinket.data.pauseSecondsOnHit) or 0) * 30))
end

local function writePauseTimerRecord(rec, ps, currentFrame)
	rec.pauseFramesRemaining = math.min(getPauseDurationFrames(), getPauseFramesRemaining(ps, currentFrame))
	rec.pausedUntilFrame = nil
end

local function getTrinketId()
	return ConchBlessing.ItemData.TIME_LUCK and ConchBlessing.ItemData.TIME_LUCK.id
end

-- Persist run data via SaveManager
local function loadFromSave(player)
	local id = getTrinketId()
	if not id then return end
	local save = SaveManager.GetRunSave(player)
	if not save then return end
	save.timeLuck = save.timeLuck or {}
	local key = getKey(player)
	local ps = getPlayerState(player)
	local rec = save.timeLuck[key]
	if rec then
		ps.luckBonus = tonumber(rec.luckBonus) or 0.0
		ps.permanentBonus = tonumber(rec.permanentBonus) or 0.0
		ps.lastApplied = tonumber(rec.lastApplied) or 0.0
		if rec.data then
			local d = rec.data
			if type(d.increasePerSecond) == 'number' then ConchBlessing.timelucktrinket.data.increasePerSecond = d.increasePerSecond end
			if type(d.pauseSecondsOnHit) == 'number' then ConchBlessing.timelucktrinket.data.pauseSecondsOnHit = d.pauseSecondsOnHit end
			if type(d.keepOnDrop) == 'boolean' then ConchBlessing.timelucktrinket.data.keepOnDrop = d.keepOnDrop end
			if type(d.framesPerSecond) == 'number' then ConchBlessing.timelucktrinket.data.framesPerSecond = d.framesPerSecond end
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
	save.timeLuck = save.timeLuck or {}
	local key = getKey(player)
	local ps = getPlayerState(player)
	save.timeLuck[key] = save.timeLuck[key] or {}
	local rec = save.timeLuck[key]
	rec.luckBonus = ps.luckBonus
	rec.permanentBonus = ps.permanentBonus
	writePauseTimerRecord(rec, ps, Game():GetFrameCount())
	rec.data = {
		increasePerSecond = ConchBlessing.timelucktrinket.data.increasePerSecond,
		pauseSecondsOnHit = ConchBlessing.timelucktrinket.data.pauseSecondsOnHit,
		keepOnDrop = ConchBlessing.timelucktrinket.data.keepOnDrop,
		framesPerSecond = ConchBlessing.timelucktrinket.data.framesPerSecond,
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
				for key, rec in pairs((playerRun and playerRun.timeLuck) or {}) do
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
function ConchBlessing.timelucktrinket.SetKeepOnDrop(player, keep)
	ConchBlessing.timelucktrinket.data.keepOnDrop = keep == true
	saveToSave(player)
end

-- Cache application for luck
function ConchBlessing.timelucktrinket.onEvaluateCache(_, player, cacheFlag)
	if cacheFlag ~= CacheFlag.CACHE_LUCK then return end
	local ps = getPlayerState(player)
	local bonus = (ps.permanentBonus or 0.0)
	local id = getTrinketId()
	if id and player:HasTrinket(id) then
		bonus = bonus + (ps.luckBonus or 0.0)
	end
	ConchBlessing.printDebug(string.format("[Time=Luck] onEvaluateCache: bonus=%.6f (perm=%.6f, temp=%.6f)", bonus, ps.permanentBonus or 0.0, ps.luckBonus or 0.0))
	if bonus ~= 0 then
		local minL = (ConchBlessing.stats and ConchBlessing.stats.BASE_STATS and ConchBlessing.stats.BASE_STATS.luck or 0.1) * 0.4
		if ConchBlessing.stats and ConchBlessing.stats.luck and ConchBlessing.stats.luck.applyAddition then
			ConchBlessing.stats.luck.applyAddition(player, bonus, minL)
		else
			player.Luck = player.Luck + bonus
		end
	end
end

-- Update growth and handle drop-reset
function ConchBlessing.timelucktrinket.onUpdate()
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
			if ConchBlessing.timelucktrinket.data.keepOnDrop then
				ps.permanentBonus = (ps.permanentBonus or 0.0) + (ps.luckBonus or 0.0)
				ps.luckBonus = 0.0
				ps.lastApplied = 0.0
				saveToSave(p)
				p:AddCacheFlags(CacheFlag.CACHE_LUCK)
				p:EvaluateItems()
				ConchBlessing.printDebug("[Time=Luck] Keep-on-drop: converted to permanent")
			else
				ps.luckBonus = 0.0
				ps.lastApplied = 0.0
				saveToSave(p)
				p:AddCacheFlags(CacheFlag.CACHE_LUCK)
				p:EvaluateItems()
				ConchBlessing.printDebug("[Time=Luck] Reset on drop")
			end
		end

		ps.hadTrinketLastFrame = has

		-- Growth when held and not paused
		if has then
			if frame >= ps.pausedUntilFrame then
				local fps = ConchBlessing.timelucktrinket.data.framesPerSecond or 30
				if fps <= 0 then fps = 30 end
				-- Compute effective stacks with golden and Mom's Box rules (via util)
				local normalCount, goldenCount, hasMomsBox = TrinketUtils.getTrinketCounts(p, id)
				local mult = (normalCount * (hasMomsBox and 2 or 1)) + (goldenCount * (hasMomsBox and 3 or 2))
				if mult <= 0 then goto after_growth end
				local perSecond = (ConchBlessing.timelucktrinket.data.increasePerSecond or 0) * mult
				local delta = perSecond / fps
				ps.luckBonus = ps.luckBonus + delta
				p:AddCacheFlags(CacheFlag.CACHE_LUCK)
				p:EvaluateItems()
				if frame % fps == 0 then
					ConchBlessing.printDebug(string.format("[Time=Luck] perSecond=%.6f perTick=%.6f (mult=%d, momsBox=%s)", perSecond, delta, mult, tostring(hasMomsBox)))
					local normalUnit = (hasMomsBox and 2 or 1)
					local goldenUnit = (hasMomsBox and 3 or 2)
					local contribNormal = normalCount * normalUnit
					local contribGolden = goldenCount * goldenUnit
					ConchBlessing.printDebug(string.format("[Time=Luck] counts normal=%d unit=%d ->%d, golden=%d unit=%d ->%d", normalCount, normalUnit, contribNormal, goldenCount, goldenUnit, contribGolden))
				end
				if frame % 90 == 0 then
					saveToSave(p)
				end
				::after_growth::
			end
		end
	end
end

-- Pause growth on taking damage
function ConchBlessing.timelucktrinket.onEntityTakeDamage(_, entity, amount, flags, source, countdown)
	local player = entity:ToPlayer()
	if not player then return end
	local id = getTrinketId()
	if not id then return end
	if not player:HasTrinket(id) then return end
	if DamageUtils.isSelfInflictedDamage(flags, source) then
		ConchBlessing.printDebug(string.format("[Time=Luck] ignore pause by flags=%d", flags or -1))
		return
	end
	local ps = getPlayerState(player)
	local frame = Game():GetFrameCount()
	ps.pausedUntilFrame = math.max(ps.pausedUntilFrame or 0, frame + getPauseDurationFrames())
	saveToSave(player)
	return nil
end

-- Load state at game start
function ConchBlessing.timelucktrinket.onGameStarted(_, isContinued)
	local game = Game()
	local num = game:GetNumPlayers()
	for i = 0, num - 1 do
		local p = game:GetPlayer(i)
		if isContinued then
			loadFromSave(p)
		else
			local ps = getPlayerState(p)
			ps.luckBonus = 0.0
			ps.permanentBonus = 0.0
			ps.lastApplied = 0.0
			ps.pausedUntilFrame = 0
			ps.hadTrinketLastFrame = false
			saveToSave(p)
		end
		p:AddCacheFlags(CacheFlag.CACHE_LUCK)
		p:EvaluateItems()
	end
end

