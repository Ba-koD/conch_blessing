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


-- Tunables
ConchBlessing.timemoney.data = {
	initialDropCount = 5,                 -- initial coins on pickup
	dropIntervalFrames = 60 * 30,         -- 60 seconds at 30 fps (업데이트: 1800프레임 = 60초)
	percentOfHeldCoins = 0.05,           -- 5% of current coins (최소 1개 보장)
	maxCoinCap = 999,                    -- pickup limit increase target
	minDropCount = 1,                    -- minimum coins per drop (EID 설명과 일치)
	-- base replacement chances (luck 기반 확률 증가)
	nickelChance = 0.05,                 -- 5% base chance for nickel
	goldenChance = 0.02,                -- 2% base chance for golden coin  
	dimeChance = 0.01,                  -- 1% base chance for dime
	luckScale = 0.1,                    -- multiplier per luck: (1 + luckScale * Luck)
	luckScaleMaxMult = 4.0,             -- cap total multiplier up to 4x
	
	spawnAnimDuration = 4,              -- frames for spawn animation (Spawn 애니메이션 프레임 수)
}

local function getPlayerSave(player)
	local save = SaveManager.GetRunSave(player)
	save.timeMoney = save.timeMoney or {}
	return save.timeMoney
end

-- Attach familiar to nearest player if Player is missing
local function ensureFamiliarHasPlayer(familiar)
    if familiar.Player then return familiar.Player end
    local game = Game()
    local num = game:GetNumPlayers()
    local bestPlayer = nil
    local bestDistSq = math.huge
    for i = 0, num - 1 do
        local p = Isaac.GetPlayer(i)
        if p then
            local d = (p.Position - familiar.Position):LengthSquared()
            if d < bestDistSq then
                bestDistSq = d
                bestPlayer = p
            end
        end
    end
    if bestPlayer then
        familiar.Player = bestPlayer
        familiar:AddToFollowers()
        familiar.IsFollower = true
        ConchBlessing.printDebug("[Time=Money] Attached familiar to nearest player (fallback)")
    end
    return familiar.Player
end

-- Find our familiar instance for a specific player (avoids duplicates)
local function findOurFamiliarForPlayer(player)
    local variant = ConchBlessing.timemoney.getVariant()
    if not (variant and variant > 0) then return nil end
    local found = nil
    for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1, false, false)) do
        local fam = ent:ToFamiliar()
        if fam and fam.Player and GetPtrHash(fam.Player) == GetPtrHash(player) then
            found = fam
            break
        end
    end
    return found
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

    local sprite = familiar:GetSprite()
    if sprite and sprite:HasAnimation("Spawn") then
        sprite:Play("Spawn", true)
        ConchBlessing.printDebug("[Time=Money] Playing Spawn animation")
    elseif sprite and sprite:HasAnimation("IdleDown") then
        -- briefly poke IdleDown to show activity if Spawn not available
        sprite:Play("IdleDown", true)
        ConchBlessing.printDebug("[Time=Money] Fallback: playing IdleDown animation")
    end
    
    -- Play coin spawn sound for feedback
    if not isInitial then  -- 초기 드롭은 소음 방지를 위해 소리 제외
        Isaac.GetSoundManager():Play(SoundEffect.SOUND_COINPICKUP, 0.7, 2, false, 1.2)
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

	-- Enhanced debug output with detailed coin information
	local debugMsg = "[Time=Money] Dropped " .. tostring(count) .. " coins"
	if isInitial then
		debugMsg = debugMsg .. " (initial drop)"
	else
		debugMsg = debugMsg .. " (60-second timer)"
	end
	ConchBlessing.printDebug(debugMsg .. " - spawn complete")
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
            local count = player:GetCollectibleNum(tmId)
            local itemConfig = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(tmId)
            local variant = ConchBlessing.timemoney.getVariant()
            if variant and variant > 0 then
                player:CheckFamiliar(variant, count, player:GetCollectibleRNG(tmId), itemConfig, 0)
                ConchBlessing.printDebug("[Time=Money] Forced CheckFamiliar on game start (variant=" .. tostring(variant) .. ", count=" .. tostring(count) .. ")")
            else
                ConchBlessing.printDebug("[Time=Money] Variant unresolved on game start; will retry via callbacks")
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
    local effects = player:GetEffects()
    local count = player:GetCollectibleNum(id) + (effects and effects:GetCollectibleEffectNum(id) or 0)
    local itemConfig = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(id)
    if variant and variant > 0 then
        player:CheckFamiliar(variant, count, player:GetCollectibleRNG(id), itemConfig, 0)
        ConchBlessing.printDebug("[Time=Money] onPostGetCollectible: CheckFamiliar applied (variant=" .. tostring(variant) .. ", count=" .. tostring(count) .. ")")
    end
end

ConchBlessing.timemoney.onFamiliarUpdate = function(familiar)
    -- Guard: run only for our familiar variant
    local variant = ConchBlessing.timemoney.getVariant()
    if not (variant and variant > 0) or familiar.Variant ~= variant then return end
    local player = familiar.Player or ensureFamiliarHasPlayer(familiar)
    if not player then return end

    -- Follow parent like standard familiars
    familiar:FollowParent()

    local sprite = familiar:GetSprite()
    if sprite then
        -- When Spawn animation finishes, transition to floating animation
        if sprite:IsFinished("Spawn") then
            if sprite:HasAnimation("FloatDown") then
                sprite:Play("FloatDown", true)
                ConchBlessing.printDebug("[Time=Money] Spawn -> FloatDown transition")
            elseif sprite:HasAnimation("IdleDown") then
                sprite:Play("IdleDown", true)
            end
        -- When IdleDown finishes, start floating loop
        elseif sprite:IsFinished("IdleDown") then
            if sprite:HasAnimation("FloatDown") then
                sprite:Play("FloatDown", true)
            end
        -- If no animation is playing, default to floating
        elseif not sprite:IsPlaying() then
            if sprite:HasAnimation("FloatDown") then
                sprite:Play("FloatDown", true)
            elseif sprite:HasAnimation("IdleDown") then
                sprite:Play("IdleDown", true)
            end
        end
    end

	local save = getPlayerSave(player)
	local frame = Game():GetFrameCount()
	
	-- Debug: show remaining time until next drop (helpful for development)
	if save.nextDropFrame and frame < save.nextDropFrame then
		local remainingFrames = save.nextDropFrame - frame
		local remainingSeconds = math.floor(remainingFrames / 30)
		if frame % 90 == 0 then  -- Every 3 seconds, show timer status (avoid spam)
			ConchBlessing.printDebug("[Time=Money] Timer status: " .. tostring(remainingSeconds) .. " seconds until next drop")
		end
	end

    if save._initDropScheduled or not save.didInitial then
		local data = ConchBlessing.timemoney.data
		local initial = data.initialDropCount
		ConchBlessing.printDebug("[Time=Money] Performing initial drop: " .. tostring(initial) .. " coins")
		dropCoinsNear(familiar, initial, player, true)
        save.didInitial = true
        save._initDropScheduled = nil
        save.nextDropFrame = save.nextDropFrame or (frame + data.dropIntervalFrames)
        local nextInSeconds = math.floor(data.dropIntervalFrames / 30)
        ConchBlessing.printDebug("[Time=Money] Initial drop complete; 60-second timer started (next drop in " .. tostring(nextInSeconds) .. " seconds)")
	end

	-- periodic drop every 60 seconds (EID: "60초마다 현재 소지중인 동전의 5%만큼 동전을 드랍")
	if save.nextDropFrame and frame >= save.nextDropFrame then
		local data = ConchBlessing.timemoney.data
		local held = player:GetNumCoins()
		local toDrop = math.max(math.floor(held * data.percentOfHeldCoins), data.minDropCount)
		
		-- Enhanced debug info matching EID description 
		local timeLeft = math.floor((save.nextDropFrame - frame) / 30) -- seconds remaining
		ConchBlessing.printDebug("[Time=Money] 60-second timer triggered! held=" .. tostring(held) .. " coins, 5% = " .. tostring(toDrop) .. " coins to drop")
		
		clampPlayerCoins(player)
		dropCoinsNear(familiar, toDrop, player, false)
		save.nextDropFrame = frame + data.dropIntervalFrames
        ConchBlessing.printDebug("[Time=Money] Timer reset: next drop in 60 seconds (frame " .. tostring(save.nextDropFrame) .. ")")
        
        -- Add visual feedback for successful timer trigger
        local room = Game():GetRoom()
        if room then
            local pos = familiar.Position + Vector(0, -10)
            -- Brief visual effect to indicate timer activation
            Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, pos, Vector.Zero, familiar)
        end
	end
end

-- Detect pickups reliably even if MC_POST_GET_COLLECTIBLE is not fired by engine/mods
ConchBlessing.timemoney.onPlayerUpdate = function(_, player)
    -- Guard: ensure we received a valid EntityPlayer from the engine
    if not player or type(player) ~= "userdata" or (player.ToPlayer and not player:ToPlayer()) then
        return
    end
    local save = getPlayerSave(player)
    local frame = Game():GetFrameCount()
    local tmId = getTimeMoneyItemId()
    if tmId == -1 then return end
    local current = player:GetCollectibleNum(tmId)
    if save._lastCount ~= current then
        ConchBlessing.printDebug("[Time=Money] onPlayerUpdate: count changed " .. tostring(save._lastCount) .. " -> " .. tostring(current))
        save._lastCount = current
        -- Force familiar evaluation
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
        local itemConfig = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(tmId)
        local effects = player:GetEffects()
        local target = current + (effects and effects:GetCollectibleEffectNum(tmId) or 0)
        local variant = ConchBlessing.timemoney.getVariant()
        if variant and variant > 0 then
            player:CheckFamiliar(variant, target, player:GetCollectibleRNG(tmId), itemConfig, 0)
            ConchBlessing.printDebug("[Time=Money] onPlayerUpdate: CheckFamiliar applied (variant=" .. tostring(variant) .. ", count=" .. tostring(target) .. ")")
            -- Defer manual spawn check to next frame to give the engine time to create the familiar
            save._deferredSpawnFrame = frame + 1
        end
    end

    -- Safety: if player owns the item but familiar missing, try to spawn it once
    if current > 0 then
        local fam = findOurFamiliarForPlayer(player)
        if not fam then
            -- Only run manual spawn after the deferred frame (engine may create on next tick)
            if save._deferredSpawnFrame and frame >= save._deferredSpawnFrame and not save._manualSpawnDone then
                local after = findOurFamiliarForPlayer(player)
                if not after then
                    local variant = ConchBlessing.timemoney.getVariant()
                    if variant and variant > 0 then
                        local spawned = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, variant, 0, player.Position, Vector.Zero, player):ToFamiliar()
                        if spawned then
                            spawned.Player = player
                            spawned:AddToFollowers()
                            spawned.IsFollower = true
                            ConchBlessing.printDebug("[Time=Money] Manual familiar spawn executed (variant=" .. tostring(variant) .. ")")
                            local s = spawned:GetSprite()
                            if s and s:HasAnimation("Spawn") then
                                s:Play("Spawn", true)
                            end
                        end
                    end
                end
                save._manualSpawnDone = true
            end
        end
    end
end

-- Tie item count to familiar count
ConchBlessing.timemoney.onEvaluateCache = function(player, cacheFlag)
	if cacheFlag ~= CacheFlag.CACHE_FAMILIARS then return end
    local tmId = getTimeMoneyItemId()
    local effects = player:GetEffects()
    local count = player:GetCollectibleNum(tmId) + (effects and effects:GetCollectibleEffectNum(tmId) or 0)
    local itemConfig = Isaac.GetItemConfig() and Isaac.GetItemConfig():GetCollectible(tmId)
    local variant = ConchBlessing.timemoney.getVariant()
    ConchBlessing.printDebug("[Time=Money] EvalCache: variant=" .. tostring(variant) .. " count=" .. tostring(count))
    if variant and variant > 0 then
        -- Use tutorial-style stable RNG seeding for CheckFamiliar
        local baseRng = player:GetCollectibleRNG(tmId)
        baseRng:Next()
        local seededRng = RNG()
        seededRng:SetSeed(baseRng:GetSeed(), 32)
        player:CheckFamiliar(variant, count, seededRng, itemConfig, 0)
        ConchBlessing.printDebug("[Time=Money] EvalCache: CheckFamiliar called with stable RNG")
    else
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
    end
end

-- Dynamic variant getter with caching
function ConchBlessing.timemoney.getVariant()
    if ConchBlessing.timemoney._cachedVariant and ConchBlessing.timemoney._cachedVariant > 0 then
        return ConchBlessing.timemoney._cachedVariant
    end

    local byName = Isaac.GetEntityVariantByName and Isaac.GetEntityVariantByName("Time = Money")
    if byName and byName > 0 then
        ConchBlessing.timemoney._cachedVariant = byName
        return byName
    end

    if ConchBlessing.ItemData and ConchBlessing.ItemData.TIME_MONEY and ConchBlessing.ItemData.TIME_MONEY.entity then
        local configured = ConchBlessing.ItemData.TIME_MONEY.entity.variant
        if configured and configured > 0 then
            ConchBlessing.timemoney._cachedVariant = configured
            return configured
        end
    end

    return 0
end

-- Enhanced familiar initialization
ConchBlessing.timemoney.onFamiliarInit = function(familiar)
    -- Guard: run only for our familiar variant
    local variant = ConchBlessing.timemoney.getVariant()
    if not (variant and variant > 0) or familiar.Variant ~= variant then return end
    
    -- Add to followers like standard familiars
    familiar:AddToFollowers()
    familiar.IsFollower = true
    familiar:FollowParent() -- ensure immediate following in the first frame
    
    local sprite = familiar:GetSprite()
    if sprite then
        if sprite:HasAnimation("Spawn") then
            sprite:Play("Spawn", true)
            ConchBlessing.printDebug("[Time=Money] Playing Spawn animation on init")
        elseif sprite:HasAnimation("IdleDown") then
            sprite:Play("IdleDown", true)
            ConchBlessing.printDebug("[Time=Money] Fallback: playing IdleDown on init")
        elseif sprite:HasAnimation("FloatDown") then
            sprite:Play("FloatDown", true)
            ConchBlessing.printDebug("[Time=Money] Fallback: playing FloatDown on init")
        end
    end
    
    -- Schedule initial drop on the next update tick
    local player = ensureFamiliarHasPlayer(familiar)
    if player then
        local save = getPlayerSave(player)
        save._initDropScheduled = true
        ConchBlessing.printDebug("[Time=Money] Initial drop scheduled for next update")
    end
    
    ConchBlessing.printDebug("[Time=Money] Familiar initialized successfully for player " .. tostring(familiar.Player and familiar.Player.InitSeed))
end

-- Debug helper functions for testing (only use in development)
ConchBlessing.timemoney.forceTimerTrigger = function()
    ConchBlessing.printDebug("[Time=Money] DEBUG: Force triggering timer for all Time=Money familiars")
    local variant = ConchBlessing.timemoney.getVariant()
    if not (variant and variant > 0) then return end
    for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1, false, false)) do
        local familiar = ent:ToFamiliar()
        if familiar and familiar.Player then
            local save = getPlayerSave(familiar.Player)
            save.nextDropFrame = Game():GetFrameCount() - 1  -- Trigger next update
            ConchBlessing.printDebug("[Time=Money] DEBUG: Forced timer trigger for familiar")
        end
    end
end

ConchBlessing.timemoney.debugInfo = function()
    ConchBlessing.printDebug("[Time=Money] DEBUG: Current familiar status:")
    local variant = ConchBlessing.timemoney.getVariant()
    if not (variant and variant > 0) then
        ConchBlessing.printDebug("[Time=Money] DEBUG: Variant unresolved")
        return
    end
    local count = 0
    for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1, false, false)) do
            local familiar = ent:ToFamiliar()
            if familiar and familiar.Player then
                count = count + 1
                local save = getPlayerSave(familiar.Player)
                local frame = Game():GetFrameCount()
                local remaining = save.nextDropFrame and save.nextDropFrame - frame or "N/A"
                ConchBlessing.printDebug("[Time=Money] DEBUG: Familiar #" .. tostring(count) .. " - Frames until drop: " .. tostring(remaining))
            end
    end
    if count == 0 then
        ConchBlessing.printDebug("[Time=Money] DEBUG: No familiars found")
    end
end

-- Test and debug functions
ConchBlessing.timemoney.testCallbacks = function()
    ConchBlessing.printDebug("[Time=Money] TEST: Testing callback system")
    local variant = ConchBlessing.timemoney.getVariant()
    ConchBlessing.printDebug("[Time=Money] TEST: Current variant = " .. tostring(variant))
    
    if not ConchBlessing.timemoney.onFamiliarInit then
        ConchBlessing.printError("[Time=Money] TEST: onFamiliarInit function is missing!")
    else
        ConchBlessing.printDebug("[Time=Money] TEST: onFamiliarInit function exists")
    end
    
    if not ConchBlessing.timemoney.onFamiliarUpdate then
        ConchBlessing.printError("[Time=Money] TEST: onFamiliarUpdate function is missing!")
    else
        ConchBlessing.printDebug("[Time=Money] TEST: onFamiliarUpdate function exists")
    end
    
    ConchBlessing.printDebug("[Time=Money] TEST: Callback test complete")
end

-- Force check all players for Time=Money and ensure familiars exist
ConchBlessing.timemoney.forceCheckAllPlayers = function()
    ConchBlessing.printDebug("[Time=Money] Force checking all players for missing familiars")
    local game = Game()
    local tmId = getTimeMoneyItemId()
    if tmId == -1 then 
        ConchBlessing.printDebug("[Time=Money] Item ID not resolved, skipping force check")
        return 
    end
    
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player:HasCollectible(tmId) then
            ConchBlessing.printDebug("[Time=Money] Player " .. tostring(i) .. " has item, checking familiar")
            local familiar = findOurFamiliarForPlayer(player)
            if not familiar then
                ConchBlessing.printDebug("[Time=Money] Missing familiar for player " .. tostring(i) .. ", forcing spawn")
                player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
                player:EvaluateItems()
                
                -- Double-check and manual spawn if needed
                local stillMissing = findOurFamiliarForPlayer(player)
                if not stillMissing then
                    local variant = ConchBlessing.timemoney.getVariant()
                    if variant and variant > 0 then
                        ConchBlessing.printDebug("[Time=Money] Manual spawning familiar for player " .. tostring(i))
                        local spawned = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, variant, 0, player.Position, Vector.Zero, player):ToFamiliar()
                        if spawned then
                            spawned.Player = player
                            spawned:AddToFollowers()
                            spawned.IsFollower = true
                            local sprite = spawned:GetSprite()
                            if sprite and sprite:HasAnimation("Spawn") then
                                sprite:Play("Spawn", true)
                            end
                            ConchBlessing.printDebug("[Time=Money] Manual spawn successful")
                        end
                    end
                end
            else
                ConchBlessing.printDebug("[Time=Money] Player " .. tostring(i) .. " already has familiar")
            end
        end
    end
end