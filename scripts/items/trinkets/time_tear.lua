ConchBlessing.timeteartrinket = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")

-- Data container (persistable gameplay constants)
ConchBlessing.timeteartrinket.data = {
	increasePerSecond = 0.0066, -- SPS gained per second while held
	pauseSecondsOnHit = 60,     -- pause duration after taking damage
	keepOnDrop = true,         -- keep bonus when dropped (convert to permanent)
	framesPerSecond = 30        -- frame rate baseline for per-frame delta
}

-- Internal state keys
local function getKey(player)
	return tostring(player:GetPlayerType())
end

local function ensureState()
	ConchBlessing.timeteartrinket.state = ConchBlessing.timeteartrinket.state or { perPlayer = {} }
	return ConchBlessing.timeteartrinket.state
end

local function getPlayerState(player)
	local s = ensureState()
	local key = getKey(player)
	s.perPlayer[key] = s.perPlayer[key] or {
		spsBonus = 0.0, -- store as SPS bonus; convert to fire delay on cache
		permanentBonus = 0.0,
		pausedUntilFrame = 0,
		hadTrinketLastFrame = false,
		lastApplied = 0.0,
	}
	return s.perPlayer[key]
end

local function getTrinketId()
	return ConchBlessing.ItemData.TIME_TEAR and ConchBlessing.ItemData.TIME_TEAR.id
end

-- Persist run data via SaveManager
local function loadFromSave(player)
	local id = getTrinketId()
	if not id then return end
	local save = SaveManager.GetRunSave(player)
	if not save then return end
	save.timeTear = save.timeTear or {}
	local key = getKey(player)
	local ps = getPlayerState(player)
	if save.timeTear[key] then
		ps.spsBonus = tonumber(save.timeTear[key].spsBonus) or 0.0
		ps.permanentBonus = tonumber(save.timeTear[key].permanentBonus) or 0.0
		ps.pausedUntilFrame = tonumber(save.timeTear[key].pausedUntilFrame) or 0
		ps.lastApplied = tonumber(save.timeTear[key].lastApplied) or 0.0
		if save.timeTear[key].data then
			local d = save.timeTear[key].data
			if type(d.increasePerSecond) == 'number' then ConchBlessing.timeteartrinket.data.increasePerSecond = d.increasePerSecond end
			if type(d.pauseSecondsOnHit) == 'number' then ConchBlessing.timeteartrinket.data.pauseSecondsOnHit = d.pauseSecondsOnHit end
			if type(d.keepOnDrop) == 'boolean' then ConchBlessing.timeteartrinket.data.keepOnDrop = d.keepOnDrop end
			if type(d.framesPerSecond) == 'number' then ConchBlessing.timeteartrinket.data.framesPerSecond = d.framesPerSecond end
		end
	end
end

local function saveToSave(player)
	local id = getTrinketId()
	if not id then return end
	local save = SaveManager.GetRunSave(player)
	if not save then return end
	save.timeTear = save.timeTear or {}
	local key = getKey(player)
	local ps = getPlayerState(player)
	save.timeTear[key] = save.timeTear[key] or {}
	save.timeTear[key].spsBonus = ps.spsBonus
	save.timeTear[key].permanentBonus = ps.permanentBonus
	save.timeTear[key].pausedUntilFrame = ps.pausedUntilFrame
	save.timeTear[key].data = {
		increasePerSecond = ConchBlessing.timeteartrinket.data.increasePerSecond,
		pauseSecondsOnHit = ConchBlessing.timeteartrinket.data.pauseSecondsOnHit,
		keepOnDrop = ConchBlessing.timeteartrinket.data.keepOnDrop,
		framesPerSecond = ConchBlessing.timeteartrinket.data.framesPerSecond,
	}
	save.timeTear[key].lastApplied = ps.lastApplied
	SaveManager.Save()
end

-- Public: allow toggling drop reset behavior
function ConchBlessing.timeteartrinket.SetKeepOnDrop(player, keep)
	ConchBlessing.timeteartrinket.data.keepOnDrop = keep == true
	saveToSave(player)
end

-- Cache application for tears (convert SPS bonus to MaxFireDelay)
function ConchBlessing.timeteartrinket.onEvaluateCache(_, player, cacheFlag)
	if cacheFlag ~= CacheFlag.CACHE_FIREDELAY then return end
	local ps = getPlayerState(player)
	local sps = (ps.permanentBonus or 0.0)
	local id = getTrinketId()
	if id and player:HasTrinket(id) then
		sps = sps + (ps.spsBonus or 0.0)
	end
	ConchBlessing.printDebug(string.format("[Time=Tear] onEvaluateCache: sps=%.6f (perm=%.6f, temp=%.6f)", sps, ps.permanentBonus or 0.0, ps.spsBonus or 0.0))
	if sps ~= 0 then
		-- Use stats.tears.applyAddition with SPS unit
		ConchBlessing.stats.tears.applyAddition(player, sps, 0.1)
	end
end

-- Update growth and handle drop-reset
function ConchBlessing.timeteartrinket.onUpdate()
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
			if ConchBlessing.timeteartrinket.data.keepOnDrop then
				ps.permanentBonus = (ps.permanentBonus or 0.0) + (ps.spsBonus or 0.0)
				ps.spsBonus = 0.0
				ps.lastApplied = 0.0
				saveToSave(p)
				p:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
				p:EvaluateItems()
				ConchBlessing.printDebug("[Time=Tear] Keep-on-drop: converted to permanent")
			else
				ps.spsBonus = 0.0
				ps.lastApplied = 0.0
				saveToSave(p)
				p:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
				p:EvaluateItems()
				ConchBlessing.printDebug("[Time=Tear] Reset on drop")
			end
		end

		ps.hadTrinketLastFrame = has

		-- Growth when held and not paused
		if has then
			if frame >= ps.pausedUntilFrame then
				local fps = ConchBlessing.timeteartrinket.data.framesPerSecond or 30
				if fps <= 0 then fps = 30 end
				-- Compute effective stacks with golden and Mom's Box rules
				local hasMomsBox = p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_BOX)
				local momsBoxStack = hasMomsBox and 1 or 0
				local rawMult = p:GetTrinketMultiplier(id) or 0
				local goldenId = id and (id + 32768) or nil
				local goldenRaw = 0
				if goldenId then
					goldenRaw = p:GetTrinketMultiplier(goldenId) or 0
				end
				local goldenStacks = goldenRaw - momsBoxStack
				if goldenStacks < 0 then goldenStacks = 0 end
				local goldenCount = math.floor(goldenStacks / 2)
				local normalCount = rawMult - (2 * goldenCount) - momsBoxStack
				if normalCount < 0 then normalCount = 0 end
				local mult = (normalCount * (hasMomsBox and 2 or 1)) + (goldenCount * (hasMomsBox and 3 or 2))
				if mult <= 0 then goto after_growth end
				local perSecond = (ConchBlessing.timeteartrinket.data.increasePerSecond or 0) * mult
				local delta = perSecond / fps
				ps.spsBonus = ps.spsBonus + delta
				p:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
				p:EvaluateItems()
				if frame % fps == 0 then
					ConchBlessing.printDebug(string.format("[Time=Tear] perSecond=%.6f perTick=%.6f (mult=%d, momsBox=%s)", perSecond, delta, mult, tostring(hasMomsBox)))
					local normalUnit = (hasMomsBox and 2 or 1)
					local goldenUnit = (hasMomsBox and 3 or 2)
					local contribNormal = normalCount * normalUnit
					local contribGolden = goldenCount * goldenUnit
					ConchBlessing.printDebug(string.format("[Time=Tear] counts normal=%d unit=%d ->%d, golden=%d unit=%d ->%d, baseRaw=%d goldenRaw=%d momsBoxStack=%d", normalCount, normalUnit, contribNormal, goldenCount, goldenUnit, contribGolden, rawMult, goldenRaw, momsBoxStack))
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
function ConchBlessing.timeteartrinket.onEntityTakeDamage(_, entity, amount, flags, source, countdown)
	local player = entity:ToPlayer()
	if not player then return end
	local id = getTrinketId()
	if not id then return end
	if not player:HasTrinket(id) then return end
	local ps = getPlayerState(player)
	local frame = Game():GetFrameCount()
	ps.pausedUntilFrame = math.max(ps.pausedUntilFrame or 0, frame + ((ConchBlessing.timeteartrinket.data.pauseSecondsOnHit or 0) * 30))
	saveToSave(player)
	return nil
end

-- Load state at game start
function ConchBlessing.timeteartrinket.onGameStarted(_, isContinued)
	local game = Game()
	local num = game:GetNumPlayers()
	for i = 0, num - 1 do
		local p = game:GetPlayer(i)
		if isContinued then
			loadFromSave(p)
		else
			local ps = getPlayerState(p)
			ps.spsBonus = 0.0
			ps.permanentBonus = 0.0
			ps.lastApplied = 0.0
			ps.pausedUntilFrame = 0
			ps.hadTrinketLastFrame = false
			saveToSave(p)
		end
		p:AddCacheFlags(CacheFlag.CACHE_FIREDELAY)
		p:EvaluateItems()
	end
end

ConchBlessing.timeteartrinket.onBeforeChange = function(upgradePos, pickup, itemData)
	return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.timeteartrinket.data)
end

ConchBlessing.timeteartrinket.onAfterChange = function(upgradePos, pickup, itemData)
	ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.timeteartrinket.data)
end

