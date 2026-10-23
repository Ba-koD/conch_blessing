local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local TimerClock = require("scripts.lib.timer_clock")
ConchBlessing.timemoney = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local Hits = require("scripts.lib.player_hits")
local TrinketUtils = ConchBlessing.TrinketUtils or require("scripts.lib.trinket_utils")

local CS = CoinSubType or {
	NULL = 0,
	PENNY = 1,
	NICKEL = 2,
	DIME = 3,
	DOUBLE_PACK = 4,
	LUCKY_PENNY = 5,
	STICKY_NICKEL = 6,
	GOLDEN = 7
}

local function C(key, default)
	local t = CS
	local v = (type(t) == "table") and t[key] or nil
	return type(v) == "number" and v or default
end

ConchBlessing.timemoney.data = {
	framesPerSecond = 30,          -- baseline fps used by other items
	dropIntervalSeconds = 60,      -- drop coins every N seconds
	percentPerInterval = 0.05,     -- percent of current money per interval (min 1)
	initialDropCount = 5,          -- coins dropped on pickup (once per gain)
	probNickel = 0.05,             -- base replacement chance for nickel
	probGolden = 0.02,             -- base replacement chance for golden coin
	probLucky = 0.02,              -- base replacement chance for lucky penny
	probDime = 0.01,               -- base replacement chance for dime
	luckMultiplierPerPoint = 0.1,  -- each Luck increases chances by this multiplier factor
	luckMultiplierCap = 4.0,       -- cap for total multiplier
	followLagFactor = 0.95,        -- follower trail factor (0.9~0.98)
	-- Keep some distance from the player (pixels)
	followMinDistancePixels = 24,
	-- Render offsets for preview text (screen space delta)
	renderOffsetX = -3,
	renderOffsetY = -35,
}

-- Runtime state belongs to the exact player entity and is rebuilt every
-- session; the saved copy count and timer live in that player's own run save,
-- which SaveManager keys by the player's collectible RNG seed. Two players of
-- one character, Esau or a character change keep their own counts.
local function getKey(player)
	return GetPtrHash(player)
end

local function ensureState()
	ConchBlessing.timemoney.state = ConchBlessing.timemoney.state or { perPlayer = {} }
	return ConchBlessing.timemoney.state
end

TimerClock.onRebase("timemoney", function(delta)
    for _, state in pairs(ensureState().perPlayer) do
        state.lastDropFrame = (state.lastDropFrame or 0) + delta
    end
end)

local loadFromSave

local function newPlayerState()
	return {
		lastDropFrame = 0,
		lastItemCount = 0,
        pendingPenalty = 0,
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
ConchBlessing.timemoney.getPlayerState = getPlayerState

local function getDropIntervalFrames()
	local fps = tonumber(ConchBlessing.timemoney.data.framesPerSecond) or 30
	if fps <= 0 then fps = 30 end
	return math.max(0, math.floor((tonumber(ConchBlessing.timemoney.data.dropIntervalSeconds) or 0) * fps))
end

local function getDropFramesRemaining(ps, currentFrame)
	local intervalFrames = getDropIntervalFrames()
	if intervalFrames <= 0 then return 0 end
	local lastDropFrame = tonumber(ps and ps.lastDropFrame) or currentFrame
	local elapsedFrames = math.max(0, currentFrame - lastDropFrame)
	return math.max(0, intervalFrames - elapsedFrames)
end

local function rebaseDropTimer(ps, remainingFrames, currentFrame)
	local intervalFrames = getDropIntervalFrames()
	remainingFrames = math.max(0, math.min(intervalFrames, math.floor(tonumber(remainingFrames) or intervalFrames)))
	ps.lastDropFrame = currentFrame - (intervalFrames - remainingFrames)
end

local function writeDropTimerRecord(rec, ps, currentFrame)
	rec.dropFramesRemaining = getDropFramesRemaining(ps, currentFrame)
	rec.lastDropFrame = nil
end

local function getItemId()
	return ConchBlessing.ItemData.TIME_MONEY and ConchBlessing.ItemData.TIME_MONEY.id
end

local function getFamiliarVariant()
	local data = ConchBlessing.ItemData.TIME_MONEY
	return data and data.entity and data.entity.variant or nil
end

-- The player's own record in its run save. Older saves nested it under the
-- PlayerType; the record of the current type (else the one that had seen the
-- most copies, so no initial payout repeats) is adopted once.
local function getRecord(player)
	local save = SaveManager.GetRunSave(player)
	if type(save) ~= "table" then return nil end
	if type(save.timeMoney) ~= "table" then save.timeMoney = {} end
	local rec = save.timeMoney
	local legacy = TrinketUtils.popPlayerTypeRecords(rec)
	if #legacy > 0 and rec.lastItemCount == nil then
		local chosen
		for _, entry in ipairs(legacy) do
			if entry.type == tostring(player:GetPlayerType()) then chosen = entry.rec end
		end
		if not chosen then
			for _, entry in ipairs(legacy) do
				if not chosen or (tonumber(entry.rec.lastItemCount) or 0) > (tonumber(chosen.lastItemCount) or 0) then
					chosen = entry.rec
				end
			end
		end
		rec.lastItemCount = chosen.lastItemCount
		rec.dropFramesRemaining = chosen.dropFramesRemaining
		rec.data = chosen.data
	end
	return rec
end

loadFromSave = function(player, ps)
	local rec = getRecord(player)
	if rec and rec.lastItemCount == nil and rec.dropFramesRemaining == nil then
		-- Nothing saved for this player yet: a full interval starts now.
		rebaseDropTimer(ps, getDropIntervalFrames(), TimerClock.now())
	elseif rec then
		local d = rec.data
		if d then
			if type(d.framesPerSecond) == 'number' then ConchBlessing.timemoney.data.framesPerSecond = d.framesPerSecond end
			if type(d.dropIntervalSeconds) == 'number' then ConchBlessing.timemoney.data.dropIntervalSeconds = d.dropIntervalSeconds end
			if type(d.percentPerInterval) == 'number' then ConchBlessing.timemoney.data.percentPerInterval = d.percentPerInterval end
			if type(d.initialDropCount) == 'number' then ConchBlessing.timemoney.data.initialDropCount = d.initialDropCount end
			if type(d.probNickel) == 'number' then ConchBlessing.timemoney.data.probNickel = d.probNickel end
			if type(d.probGolden) == 'number' then ConchBlessing.timemoney.data.probGolden = d.probGolden end
			if type(d.probDime) == 'number' then ConchBlessing.timemoney.data.probDime = d.probDime end
			if type(d.probLucky) == 'number' then ConchBlessing.timemoney.data.probLucky = d.probLucky end
			if type(d.luckMultiplierPerPoint) == 'number' then ConchBlessing.timemoney.data.luckMultiplierPerPoint = d.luckMultiplierPerPoint end
			if type(d.luckMultiplierCap) == 'number' then ConchBlessing.timemoney.data.luckMultiplierCap = d.luckMultiplierCap end
		end
		ps.lastItemCount = tonumber(rec.lastItemCount) or 0
		local remainingFrames = tonumber(rec.dropFramesRemaining)
		if remainingFrames == nil then
			-- Legacy saves only contain a session-local absolute frame. Restart a full
			-- interval instead of carrying that unrelated frame into this session.
			remainingFrames = getDropIntervalFrames()
		end
		local currentFrame = TimerClock.now()
		rebaseDropTimer(ps, remainingFrames, currentFrame)
		writeDropTimerRecord(rec, ps, currentFrame)
	end
end

local function saveToSave(player)
	local ps = getPlayerState(player)
	local rec = getRecord(player)
	if not rec then return end
	writeDropTimerRecord(rec, ps, TimerClock.now())
	rec.lastItemCount = ps.lastItemCount
	rec.data = {
		framesPerSecond = ConchBlessing.timemoney.data.framesPerSecond,
		dropIntervalSeconds = ConchBlessing.timemoney.data.dropIntervalSeconds,
		percentPerInterval = ConchBlessing.timemoney.data.percentPerInterval,
		initialDropCount = ConchBlessing.timemoney.data.initialDropCount,
		probNickel = ConchBlessing.timemoney.data.probNickel,
		probGolden = ConchBlessing.timemoney.data.probGolden,
		probDime = ConchBlessing.timemoney.data.probDime,
		probLucky = ConchBlessing.timemoney.data.probLucky,
		luckMultiplierPerPoint = ConchBlessing.timemoney.data.luckMultiplierPerPoint,
		luckMultiplierCap = ConchBlessing.timemoney.data.luckMultiplierCap
	}
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
				local rec = type(playerRun) == "table" and playerRun.timeMoney
				if type(rec) == "table" then
					writeDropTimerRecord(rec, ps, currentFrame)
				end
			end
		end)
	end
end

-- Utility: resolve coin subtype with weighted replacement odds and synergy
local function chooseCoinSubtype(player, rng)
	-- base: penny
	local subtype = C("PENNY", 1)
	local luck = player.Luck or 0
	local mult = 1 + (ConchBlessing.timemoney.data.luckMultiplierPerPoint or 0) * luck
	local cap = ConchBlessing.timemoney.data.luckMultiplierCap or 1
	if mult < 1 then mult = 1 end
	if mult > cap then mult = cap end
	-- roll order: dime -> golden -> nickel
	local dimeP = (ConchBlessing.timemoney.data.probDime or 0) * mult
	local goldP = (ConchBlessing.timemoney.data.probGolden or 0) * mult
	local nickelP = (ConchBlessing.timemoney.data.probNickel or 0) * mult
	local luckyP = (ConchBlessing.timemoney.data.probLucky or 0) * mult
	if rng:RandomFloat() < dimeP then
		subtype = C("DIME", 3)
	elseif rng:RandomFloat() < goldP then
		subtype = C("GOLDEN", 7)
	elseif rng:RandomFloat() < nickelP then
		subtype = C("NICKEL", 2)
	elseif rng:RandomFloat() < luckyP then
		subtype = C("LUCKY_PENNY", 5)
	end
	return subtype
end

-- Utility: spawn a single coin near an entity
local function spawnCoinNear(anchor, player, rng)
	local pos = anchor.Position
	local angle = rng:RandomFloat() * 360
	local radius = 10 + rng:RandomFloat() * 30
	local offset = Vector(radius, 0):Rotated(angle)
	-- Basic float down: give initial upward velocity then gravity pulls down naturally
	local vel = Vector(0, -3):Rotated(rng:RandomFloat() * 30 - 15)
	local sub = chooseCoinSubtype(player, rng)
	-- Guard nil subtype to avoid Spawn error
    if type(sub) ~= "number" then sub = C("PENNY", 1) end
	local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, sub, pos + offset, vel, anchor)
    -- Play spawn effect with a standard poof, then swap to our Spawn animation if possible
    pcall(function()
        local e = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF_2, 0, pos + offset, Vector.Zero, anchor)
        if e and e:ToEffect() then
            local eff = e:ToEffect()
            eff.Timeout = 10
            local spr = eff:GetSprite()
            if spr then
                spr:Load("gfx/time_money.anm2", true)
                spr:Play("Spawn", true)
            end
        end
    end)
	return pickup
end

-- Play the Spawn animation on this player's first Time = Money familiar
local function playFamiliarSpawnAnim(player)
    local variant = getFamiliarVariant()
    if not variant then return end
    local owner = GetPtrHash(player)
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant) or {}) do
        local fam = entity:ToFamiliar()
        if fam and fam.Player and GetPtrHash(fam.Player) == owner then
            local spr = fam:GetSprite()
            if spr then
                pcall(function()
                    spr:Play("Spawn", true)
                end)
            end
            return
        end
    end
end

-- Initial drop when item is newly gained
local function tryInitialDrop(player, diffCount)
	local id = getItemId()
	if not id then return end
	if diffCount <= 0 then return end
	local rng = player:GetCollectibleRNG(id)
    local count = ConchBlessing.timemoney.data.initialDropCount or 0
	playFamiliarSpawnAnim(player)
	for _ = 1, count do
		spawnCoinNear(player, player, rng)
	end
	ConchBlessing.printDebug(string.format("[Time=Money] initial drop executed, count=%d, diff=%d", count, diffCount))
end

-- Periodic drop based on current money
local function tryPeriodicDrop(player)
	local game = Game()
	local frame = TimerClock.now()
	local ps = getPlayerState(player)
	local intervalFrames = getDropIntervalFrames()
	if intervalFrames <= 0 then return end
	if frame - (ps.lastDropFrame or 0) < intervalFrames then return end
	local coins = player:GetNumCoins()
	local pct = ConchBlessing.timemoney.data.percentPerInterval or 0
    local effectivePct = pct
    -- BFFS!: change base percent from 5% -> 10%
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BFFS) then
        effectivePct = 0.10
    end
    local toDrop = math.floor(coins * effectivePct)
    -- apply pending damage penalties (from onEntityTakeDamage)
    toDrop = toDrop - (ps.pendingPenalty or 0)
	if toDrop < 1 then toDrop = 1 end
	local rng = player:GetCollectibleRNG(getItemId() or 0)
	playFamiliarSpawnAnim(player)
	for _ = 1, toDrop do
		spawnCoinNear(player, player, rng)
	end
	ps.lastDropFrame = frame
    ps.pendingPenalty = 0 -- reset after a drop cycle
	saveToSave(player)
	ConchBlessing.printDebug(string.format("[Time=Money] periodic drop executed, toDrop=%d, coins=%d", toDrop, coins))
end

-- Callbacks
function ConchBlessing.timemoney.onFamiliarInit(_, familiar)
	-- Ensure follower behavior
	local fam = familiar:ToFamiliar()
	if fam then
		-- Register into follower chain so multiple familiars line up instead of overlapping
		fam:AddToFollowers()
		fam:FollowParent()
		-- Play default floating animation from ANM2
		local spr = fam:GetSprite()
		if spr then
			pcall(function()
				spr:Play("FloatDown", true)
			end)
		end
	end
end

function ConchBlessing.timemoney.onFamiliarUpdate(_, familiar)
	-- Only process our familiar variant and keep following parent smoothly
	local targetVariant = getFamiliarVariant()
	if not targetVariant or familiar.Variant ~= targetVariant then return end
	local fam = familiar:ToFamiliar()
	if fam then
		fam:FollowParent()
		-- Maintain a small trailing distance with configurable lag and min distance
		local parent = fam.Player
		if parent then
			local lag = ConchBlessing.timemoney.data.followLagFactor or 0.95
			local minDist = ConchBlessing.timemoney.data.followMinDistancePixels or 0
			local target = parent.Position
			local current = fam.Position
			-- Compute follow target using min distance and optional side offset; let TBOI chain handle smoothing
			local delta = current - target
			local dist = delta:Length()
			local dir = dist > 0 and (delta / dist) or Vector(1, 0)
			local side = ConchBlessing.timemoney.data.followSideOffsetPixels or 0
			local perp = side ~= 0 and Vector(-dir.Y, dir.X):Resized(side) or Vector.Zero
			local minVec = (minDist > 0) and (dir * minDist) or Vector.Zero
			local followTarget = target + minVec + perp
			fam:FollowPosition(followTarget)
		end
		local spr = fam:GetSprite()
		if spr and (spr:IsFinished("Spawn") or spr:IsFinished("IdleDown")) then
			pcall(function()
				spr:Play("FloatDown", true)
			end)
		end
	end
end

-- Render next-drop preview above the familiar
function ConchBlessing.timemoney.onFamiliarRender(_, familiar, offset)
	-- Only render for our own familiar variant
	local targetVariant = getFamiliarVariant()
	if not targetVariant then return end
	if familiar.Variant ~= targetVariant then
		-- Debug (prints once per run when debugMode is on): non-target familiar render skipped
		local st = ensureState()
		if ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.debugMode and not st.loggedNonTargetVariantSeen then
			ConchBlessing.printDebug(string.format("[Time=Money] skipping render for variant=%s (target=%s)", tostring(familiar.Variant), tostring(targetVariant)))
			st.loggedNonTargetVariantSeen = true
		end
		return
	end

	local fam = familiar:ToFamiliar()
	if not fam then return end
	local player = fam.Player
	if not player then return end
    local ps = getPlayerState(player)
    local coins = player:GetNumCoins()
    local pct = ConchBlessing.timemoney.data.percentPerInterval or 0
    local effectivePct = player:HasCollectible(CollectibleType.COLLECTIBLE_BFFS) and 0.10 or pct
    local preview = math.floor(coins * effectivePct) - (ps.pendingPenalty or 0)
    if preview < 1 then preview = 1 end
	-- Draw at familiar position with configurable offset (no hard-coded numbers in logic)
	local pos = Isaac.WorldToScreen(fam.Position)
	local dx = ConchBlessing.timemoney.data.renderOffsetX or 0
	local dy = ConchBlessing.timemoney.data.renderOffsetY or 0
	Isaac.RenderText(tostring(preview), pos.X + dx, pos.Y + dy, 1, 1, 0.5, 0.9)
	-- Debug (once per run): log current offsets
	local st = ensureState()
	if ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.debugMode and not st.loggedRenderOffsetOnce then
		ConchBlessing.printDebug(string.format("[Time=Money] render offset dx=%s dy=%s", tostring(dx), tostring(dy)))
		st.loggedRenderOffsetOnce = true
	end
end

-- On damage: increment pending penalty unless excluded by time-trinket rules
function ConchBlessing.timemoney.onEntityTakeDamage(_, entity, amount, flags, source, countdown)
    local player = entity:ToPlayer()
    if not player then return end
    local id = getItemId()
    if not id or player:GetCollectibleNum(id) <= 0 then return end
    if not Hits.counts(flags) then
        return
    end
    local ps = getPlayerState(player)
    ps.pendingPenalty = (ps.pendingPenalty or 0) + 1
    saveToSave(player)
    return true
end
Hits.register("TIME_MONEY", ConchBlessing.timemoney.onEntityTakeDamage)

function ConchBlessing.timemoney.onEvaluateCache(_, player, cacheFlag)
	if cacheFlag ~= CacheFlag.CACHE_FAMILIARS then return end
	local id = getItemId()
	local var = getFamiliarVariant()
	if not id or not var then return end
	local count = player:GetCollectibleNum(id)
	-- The zero-count call is what removes our remaining engine familiar.
	local rng = player:GetCollectibleRNG(id)
	player:CheckFamiliar(var, count or 0, rng)
end

function ConchBlessing.timemoney.onGameStarted(_, isContinued)
	local game = Game()
	local num = game:GetNumPlayers()
	-- Entity hashes from an earlier session mean nothing now.
	ensureState().perPlayer = {}
	for i = 0, num - 1 do
		local p = game:GetPlayer(i)
		if isContinued then
			getPlayerState(p)
		else
			local ps = newPlayerState()
			ensureState().perPlayer[getKey(p)] = ps
			ps.lastDropFrame = TimerClock.now()
			ps.lastItemCount = p:GetCollectibleNum(getItemId() or 0)
			saveToSave(p)
		end
	end
end

-- MC_POST_PLAYER_UPDATE: runs once for each player, so only that player's
-- copies, timer and coins are handled here.
function ConchBlessing.timemoney.onPlayerUpdate(_, player)
	if not player then return end
	local id = getItemId()
	if not id then return end
	local ps = getPlayerState(player)
	local curCount = player:GetCollectibleNum(id)
	if curCount > (ps.lastItemCount or 0) then
		tryInitialDrop(player, curCount - (ps.lastItemCount or 0))
	end
	if curCount ~= (ps.lastItemCount or 0) then
		ps.lastItemCount = curCount
		saveToSave(player)
	end
	if curCount > 0 then
		tryPeriodicDrop(player)
	end
end


-- Test hooks for scripts/dev/rng_probe.lua. Pure helpers, no gameplay use.
ConchBlessing.timemoney._test = { chooseCoinSubtype = chooseCoinSubtype }
