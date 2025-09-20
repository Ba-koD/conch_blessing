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
	if save.timeLuck[key] then
		ps.luckBonus = tonumber(save.timeLuck[key].luckBonus) or 0.0
		ps.permanentBonus = tonumber(save.timeLuck[key].permanentBonus) or 0.0
		ps.pausedUntilFrame = tonumber(save.timeLuck[key].pausedUntilFrame) or 0
		ps.lastApplied = tonumber(save.timeLuck[key].lastApplied) or 0.0
		if save.timeLuck[key].data then
			local d = save.timeLuck[key].data
			if type(d.increasePerSecond) == 'number' then ConchBlessing.timelucktrinket.data.increasePerSecond = d.increasePerSecond end
			if type(d.pauseSecondsOnHit) == 'number' then ConchBlessing.timelucktrinket.data.pauseSecondsOnHit = d.pauseSecondsOnHit end
			if type(d.keepOnDrop) == 'boolean' then ConchBlessing.timelucktrinket.data.keepOnDrop = d.keepOnDrop end
			if type(d.framesPerSecond) == 'number' then ConchBlessing.timelucktrinket.data.framesPerSecond = d.framesPerSecond end
		end
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
	save.timeLuck[key].luckBonus = ps.luckBonus
	save.timeLuck[key].permanentBonus = ps.permanentBonus
	save.timeLuck[key].pausedUntilFrame = ps.pausedUntilFrame
	save.timeLuck[key].data = {
		increasePerSecond = ConchBlessing.timelucktrinket.data.increasePerSecond,
		pauseSecondsOnHit = ConchBlessing.timelucktrinket.data.pauseSecondsOnHit,
		keepOnDrop = ConchBlessing.timelucktrinket.data.keepOnDrop,
		framesPerSecond = ConchBlessing.timelucktrinket.data.framesPerSecond,
	}
	save.timeLuck[key].lastApplied = ps.lastApplied
	SaveManager.Save()
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
	if DamageUtils.isSelfInflictedDamage(flags) then
		ConchBlessing.printDebug(string.format("[Time=Luck] ignore pause by flags=%d", flags or -1))
		return
	end
	local ps = getPlayerState(player)
	local frame = Game():GetFrameCount()
	ps.pausedUntilFrame = math.max(ps.pausedUntilFrame or 0, frame + ((ConchBlessing.timelucktrinket.data.pauseSecondsOnHit or 0) * 30))
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

ConchBlessing.timelucktrinket.onBeforeChange = function(upgradePos, pickup, itemData)
	return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.timelucktrinket.data)
end

ConchBlessing.timelucktrinket.onAfterChange = function(upgradePos, pickup, itemData)
	ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.timelucktrinket.data)
end

