ConchBlessing.timemoney = {}

local SaveManager = ConchBlessing.SaveManager or require("scripts.lib.save_manager")
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")

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

local function getKey(player)
	return tostring(player:GetPlayerType())
end

local function ensureState()
	ConchBlessing.timemoney.state = ConchBlessing.timemoney.state or { perPlayer = {} }
	return ConchBlessing.timemoney.state
end

local function getPlayerState(player)
	local s = ensureState()
	local key = getKey(player)
	s.perPlayer[key] = s.perPlayer[key] or {
		lastDropFrame = 0,
		lastItemCount = 0,
        pendingPenalty = 0,
	}
	return s.perPlayer[key]
end

local function getItemId()
	return ConchBlessing.ItemData.TIME_MONEY and ConchBlessing.ItemData.TIME_MONEY.id
end

local function getFamiliarVariant()
	local data = ConchBlessing.ItemData.TIME_MONEY
	return data and data.entity and data.entity.variant or nil
end

local function loadFromSave(player)
	local save = SaveManager.GetRunSave(player)
	if not save then return end
	save.timeMoney = save.timeMoney or {}
	local key = getKey(player)
	local ps = getPlayerState(player)
	local rec = save.timeMoney[key]
	if rec then
		ps.lastDropFrame = tonumber(rec.lastDropFrame) or 0
		ps.lastItemCount = tonumber(rec.lastItemCount) or 0
		local d = rec.data
		if d then
			if type(d.framesPerSecond) == 'number' then ConchBlessing.timemoney.data.framesPerSecond = d.framesPerSecond end
			if type(d.dropIntervalSeconds) == 'number' then ConchBlessing.timemoney.data.dropIntervalSeconds = d.dropIntervalSeconds end
			if type(d.percentPerInterval) == 'number' then ConchBlessing.timemoney.data.percentPerInterval = d.percentPerInterval end
			if type(d.initialDropCount) == 'number' then ConchBlessing.timemoney.data.initialDropCount = d.initialDropCount end
			if type(d.probNickel) == 'number' then ConchBlessing.timemoney.data.probNickel = d.probNickel end
			if type(d.probGolden) == 'number' then ConchBlessing.timemoney.data.probGolden = d.probGolden end
			if type(d.probDime) == 'number' then ConchBlessing.timemoney.data.probDime = d.probDime end
			if type(d.luckMultiplierPerPoint) == 'number' then ConchBlessing.timemoney.data.luckMultiplierPerPoint = d.luckMultiplierPerPoint end
			if type(d.luckMultiplierCap) == 'number' then ConchBlessing.timemoney.data.luckMultiplierCap = d.luckMultiplierCap end
		end
	end
end

local function saveToSave(player)
	local save = SaveManager.GetRunSave(player)
	if not save then return end
	save.timeMoney = save.timeMoney or {}
	local key = getKey(player)
	local ps = getPlayerState(player)
	save.timeMoney[key] = save.timeMoney[key] or {}
	local rec = save.timeMoney[key]
	rec.lastDropFrame = ps.lastDropFrame
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

-- Play time_money familiar Spawn animation (first instance)
local function playFamiliarSpawnAnim(player)
    local variant = getFamiliarVariant()
    if not variant then return end
    local list = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant)
    if list and #list > 0 then
        local fam = list[1]:ToFamiliar()
        if fam then
            local spr = fam:GetSprite()
            if spr then
                pcall(function()
                    spr:Play("Spawn", true)
                end)
            end
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
	local frame = game:GetFrameCount()
	local ps = getPlayerState(player)
	local fps = ConchBlessing.timemoney.data.framesPerSecond or 30
	if fps <= 0 then fps = 30 end
	local intervalFrames = math.floor((ConchBlessing.timemoney.data.dropIntervalSeconds or 0) * fps)
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
    if DamageUtils and DamageUtils.isSelfInflictedDamage and DamageUtils.isSelfInflictedDamage(flags) then
        return
    end
    local ps = getPlayerState(player)
    ps.pendingPenalty = (ps.pendingPenalty or 0) + 1
    saveToSave(player)
end

function ConchBlessing.timemoney.onEvaluateCache(_, player, cacheFlag)
	if cacheFlag ~= CacheFlag.CACHE_FAMILIARS then return end
	local id = getItemId()
	local var = getFamiliarVariant()
	if not id or not var then return end
	local count = player:GetCollectibleNum(id)
	if count and count > 0 then
		local rng = player:GetCollectibleRNG(id)
		player:CheckFamiliar(var, count, rng)
	end
end

function ConchBlessing.timemoney.onGameStarted(_, isContinued)
	local game = Game()
	local num = game:GetNumPlayers()
	for i = 0, num - 1 do
		local p = game:GetPlayer(i)
		if isContinued then
			loadFromSave(p)
		else
			local ps = getPlayerState(p)
			ps.lastDropFrame = 0
			ps.lastItemCount = p:GetCollectibleNum(getItemId() or 0)
			saveToSave(p)
		end
	end
end



function ConchBlessing.timemoney.onPlayerUpdate(_)
	local game = Game()
	local num = game:GetNumPlayers()
	local id = getItemId()
	if not id then return end
	for i = 0, num - 1 do
		local p = game:GetPlayer(i)
		local ps = getPlayerState(p)
		local curCount = p:GetCollectibleNum(id)
		if curCount > (ps.lastItemCount or 0) then
			tryInitialDrop(p, curCount - (ps.lastItemCount or 0))
			ps.lastItemCount = curCount
			saveToSave(p)
		end
		if curCount > 0 then
			tryPeriodicDrop(p)
		end
	end
end