local ConchBlessing = ConchBlessing
local SaveManager = require("scripts.lib.save_manager")

-- Time = Money Familiar
ConchBlessing.timemoney = {}
-- Robust resolver for item ID (handles early -1 cases)
local function getTimeMoneyItemId()
    local data = ConchBlessing.ItemData and ConchBlessing.ItemData.TIME_MONEY
    if not data then return -1 end
    if data.id and data.id ~= -1 then return data.id end
    local id = Isaac.GetItemIdByName("Time = Money")
    if id and id > 0 then
        data.id = id
        ConchBlessing.printDebug("[Time=Money] Resolved item ID late: " .. tostring(id))
        return id
    end
    return -1
end


-- Tunables (no magic numbers in logic; change values here)
ConchBlessing.timemoney.data = {
	initialDropCount = 5,                 -- initial coins on pickup
	dropIntervalFrames = 60 * 30,         -- 60 seconds at 30 fps
	percentOfHeldCoins = 0.05,           -- 5% of current coins
	maxCoinCap = 999,                    -- pickup limit increase target
	-- base replacement chances
	nickelChance = 0.05,                 -- 5%
	goldenChance = 0.02,                -- 2%
	dimeChance = 0.01,                  -- 1%
	luckScale = 0.1,                    -- multiplier per luck: (1 + luckScale * Luck)
	luckScaleMaxMult = 4.0,             -- cap total multiplier up to 4x
}

local function getPlayerSave(player)
	local save = SaveManager.GetRunSave(player)
	save.timeMoney = save.timeMoney or {}
	return save.timeMoney
end

-- English comments required by user; keep debug values dynamic
local function getLuckMultiplier(luck)
	local data = ConchBlessing.timemoney.data
	local mult = 1 + data.luckScale * (luck or 0)
	if mult > data.luckScaleMaxMult then
		mult = data.luckScaleMaxMult
	end
	return mult
end

local function chooseCoinType(rng, player)
	-- Returns pickup variant id and subtype
	local data = ConchBlessing.timemoney.data
	local mult = getLuckMultiplier(player and player.Luck or 0)
	local r = rng:RandomFloat()
	-- scale chances by multiplier
	local nickel = data.nickelChance * mult
	local golden = data.goldenChance * mult
	local dime = data.dimeChance * mult
	-- normalize cumulative selection
	if r < dime then
		return PickupVariant.PICKUP_COIN, CoinSubType.COIN_DIME
	elseif r < dime + golden then
		return PickupVariant.PICKUP_COIN, CoinSubType.COIN_GOLDEN
	elseif r < dime + golden + nickel then
		return PickupVariant.PICKUP_COIN, CoinSubType.COIN_NICKEL
	else
		-- normal coin; synergy converts later if needed
		return PickupVariant.PICKUP_COIN, CoinSubType.COIN_PENNY
	end
end

local function dropCoinsNear(familiar, count, player, isInitial)
	if count <= 0 then return end
	local rng = player and player:GetCollectibleRNG(ConchBlessing.ItemData.TIME_MONEY.id) or RNG()
	local hasDeepPockets = player and player:HasCollectible(CollectibleType.COLLECTIBLE_DEEP_POCKETS)

    -- Play an Active Sack-like "Spawn" animation when dropping coins
    local sprite = familiar:GetSprite()
    if sprite and sprite:HasAnimation("Spawn") then
        sprite:Play("Spawn", true)
    end

	for i = 1, count do
		local variant, subtype = chooseCoinType(rng, player)
		-- Deep Pockets synergy: normal coins become nickels
		if hasDeepPockets and variant == PickupVariant.PICKUP_COIN and subtype == CoinSubType.COIN_PENNY then
			subtype = CoinSubType.COIN_NICKEL
		end
		local offset = Vector.FromAngle(rng:RandomInt(0, 359)):Resized(10 + rng:RandomInt(0, 15))
		local pos = familiar.Position + offset
		Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, pos, Vector.Zero, familiar)
	end

	ConchBlessing.printDebug("[Time=Money] Dropped coins: " .. tostring(count) .. (isInitial and " (initial)" or "") )
end

-- Ensure coin cap is effectively raised by preventing our spawns from being skipped due to soft caps
local function clampPlayerCoins(player)
	local data = ConchBlessing.timemoney.data
	if player and player:GetNumCoins() > data.maxCoinCap then
		player:AddCoins(data.maxCoinCap - player:GetNumCoins())
	end
end

-- On game start: initialize per-player state
ConchBlessing.timemoney.onGameStarted = function()
	local game = Game()
	for i = 0, game:GetNumPlayers() - 1 do
		local player = Isaac.GetPlayer(i)
		local save = getPlayerSave(player)
		-- initialize timers when item present
        local tmId = getTimeMoneyItemId()
        if player:HasCollectible(tmId) then
			save.nextDropFrame = save.nextDropFrame or (game:GetFrameCount() + ConchBlessing.timemoney.data.dropIntervalFrames)
			save.didInitial = save.didInitial or false
            ConchBlessing.printDebug("[Time=Money] Initialized for player " .. tostring(i) .. ", nextDropFrame=" .. tostring(save.nextDropFrame))
            -- Ensure familiar spawn on load/new run if item already owned
            player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
            player:EvaluateItems()
            local variant = ConchBlessing.timemoney.getVariant()
            if variant and variant > 0 then
                local count = player:GetCollectibleNum(tmId)
                local itemConfig = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(tmId)
                player:CheckFamiliar(variant, count, player:GetCollectibleRNG(tmId), itemConfig, 0)
                ConchBlessing.printDebug("[Time=Money] Forced CheckFamiliar on game start (variant=" .. tostring(variant) .. ", count=" .. tostring(count) .. ")")
            else
                ConchBlessing.printDebug("[Time=Money] Variant not resolved on game start; will rely on engine reload of entities2.xml")
            end
		end
	end
end

-- On pickup: force CACHE_FAMILIARS so the familiar spawns immediately
ConchBlessing.timemoney.onPostGetCollectible = function(_, collectibleID, _, player)
    if not player then return end
    local id = getTimeMoneyItemId()
    ConchBlessing.printDebug("[Time=Money] PostGet: got=" .. tostring(collectibleID) .. " ours=" .. tostring(id))
    if collectibleID ~= id then
        -- Fallback: compare by item name if ID not resolved yet
        local cfg = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(collectibleID)
        if not (cfg and cfg.Name == "Time = Money") then
            return
        end
        ConchBlessing.printDebug("[Time=Money] PostGetCollectible matched by name fallback")
    end
    ConchBlessing.printDebug("[Time=Money] onPostGetCollectible: forcing CACHE_FAMILIARS")
    player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
    player:EvaluateItems()
    local variant = ConchBlessing.timemoney.getVariant()
    ConchBlessing.printDebug("[Time=Money] PostGet: variant=" .. tostring(variant))
    if variant and variant > 0 then
        local count = player:GetCollectibleNum(id)
        local itemConfig = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(id)
        player:CheckFamiliar(variant, count, player:GetCollectibleRNG(id), itemConfig, 0)
        ConchBlessing.printDebug("[Time=Money] onPostGetCollectible: CheckFamiliar applied (variant=" .. tostring(variant) .. ", count=" .. tostring(count) .. ")")
    else
        ConchBlessing.printDebug("[Time=Money] onPostGetCollectible: variant not resolved; ensure entities2.xml is loaded (restart may be required)")
    end
end

ConchBlessing.timemoney.onFamiliarUpdate = function(familiar)
    -- Guard: run only for our familiar variant
    if familiar.Variant ~= ConchBlessing.timemoney.getVariant() then return end
	local player = familiar.Player
	if not player then return end

    -- Follow parent like standard familiars
    familiar:FollowParent()

    -- Active Sack-like float transition: when any current anim finishes, play FloatDown (or Idle fallback)
    local sprite = familiar:GetSprite()
    if sprite and sprite:IsFinished() then
        if sprite:HasAnimation("FloatDown") then
            sprite:Play("FloatDown", true)
        elseif sprite:HasAnimation("IdleDown") then
            sprite:Play("IdleDown", true)
        elseif sprite:HasAnimation("Idle") then
            sprite:Play("Idle", true)
        end
    end

	local save = getPlayerSave(player)
	local frame = Game():GetFrameCount()

	-- initial drop once
	if not save.didInitial then
		local initial = ConchBlessing.timemoney.data.initialDropCount
		dropCoinsNear(familiar, initial, player, true)
		save.didInitial = true
		save.nextDropFrame = save.nextDropFrame or (frame + ConchBlessing.timemoney.data.dropIntervalFrames)
        ConchBlessing.printDebug("[Time=Money] Initial drop done; next at frame " .. tostring(save.nextDropFrame))
	end

	-- periodic drop by percentage of held coins
	if save.nextDropFrame and frame >= save.nextDropFrame then
		local percent = ConchBlessing.timemoney.data.percentOfHeldCoins
		local held = player:GetNumCoins()
		local toDrop = math.floor(held * percent)
		if toDrop < 1 then toDrop = 1 end
		clampPlayerCoins(player)
		dropCoinsNear(familiar, toDrop, player, false)
		save.nextDropFrame = frame + ConchBlessing.timemoney.data.dropIntervalFrames
        ConchBlessing.printDebug("[Time=Money] Periodic drop: held=" .. tostring(held) .. ", percent=" .. tostring(percent) .. ", dropped=" .. tostring(toDrop) .. ", next=" .. tostring(save.nextDropFrame))
	end
end

-- Tie item count to familiar count
ConchBlessing.timemoney.onEvaluateCache = function(player, cacheFlag)
	if cacheFlag ~= CacheFlag.CACHE_FAMILIARS then return end
    local tmId = getTimeMoneyItemId()
    local count = player:GetCollectibleNum(tmId)
    local itemConfig = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(tmId)
    local var = ConchBlessing.timemoney.getVariant()
    ConchBlessing.printDebug("[Time=Money] EvalCache: variant=" .. tostring(var) .. " count=" .. tostring(count))
    if var and var > 0 then
        player:CheckFamiliar(var, count, player:GetCollectibleRNG(tmId), itemConfig, 0)
        ConchBlessing.printDebug("[Time=Money] EvalCache: CheckFamiliar called")
    end
end

-- Variant getter: use reserved range from our entities2.xml when present, fallback to default Baby familiar variant slot if needed
function ConchBlessing.timemoney.getVariant()
    -- Prefer engine-registered variant from entities2.xml; fallback to custom ID
    local v = nil
    if Isaac.GetEntityVariantByName then
        v = Isaac.GetEntityVariantByName("Time = Money")
    end
    ConchBlessing.printDebug("[Time=Money] getVariant: byName=" .. tostring(v))
    if v and v > 0 then
        return v
    end
    -- No explicit variant: let engine assign; until then, return 0 to avoid spawning the wrong familiar
    return 0
end

-- Optional: on familiar init to add to followers and idle anim
ConchBlessing.timemoney.onFamiliarInit = function(familiar)
    -- Guard: run only for our familiar variant
    if familiar.Variant ~= ConchBlessing.timemoney.getVariant() then return end
    familiar:AddToFollowers()
    familiar.IsFollower = true
    local sprite = familiar:GetSprite()
    -- Active Sack-like spawn: try to play "Spawn" if present; fallback to "Idle"
    if sprite and sprite:HasAnimation("Spawn") then
        sprite:Play("Spawn", true)
    else
        if sprite and sprite:HasAnimation("Idle") then
            sprite:Play("Idle", true)
        end
    end
end