ConchBlessing.sealeddemonsword = {}

local SEALED_DEMON_SWORD_ID = Isaac.GetItemIdByName("Sealed Demon Sword")
local TYRFING_ID = Isaac.GetItemIdByName("Tyrfing")

local SaveManager = require("scripts.lib.save_manager")
local EnemyUtils = require("scripts.lib.enemy_utils")

-- Constants
local KILLS_TO_EVOLVE = 300
local SPEED_PENALTY = 0.2
-- Damage handed to TrySplit. It is the threshold the engine uses to decide the
-- split, not damage dealt to the player; enemies that cannot split take it as
-- real damage instead, matching Meat Cleaver's own behaviour.
local SPLIT_DAMAGE = 25

-- Data structure
ConchBlessing.sealeddemonsword.data = {
    killsToEvolve = KILLS_TO_EVOLVE,
    speedPenalty = SPEED_PENALTY,
    splitDamage = SPLIT_DAMAGE,
    -- Bosses are excluded by default: halving a boss into two 40% copies changes
    -- fight pacing far more than it does for regular enemies.
    splitBosses = false,
    -- Hard ceiling on splits per room. Waves, summoners and a misread half can
    -- all push the entity count past what the frame rate tolerates.
    maxSplitsPerRoom = 60,
}

-- Get saved data for player
local function getSaveData(player)
    local playerSave = SaveManager.GetRunSave(player)
    if not playerSave.sealedDemonSword then
        playerSave.sealedDemonSword = {
            killCount = 0
        }
    end
    return playerSave.sealedDemonSword
end

-- Enemies arrive already split rather than being cleaved by an active use.
--
-- With REPENTOGON we split each enemy as it spawns through EntityNPC:TrySplit,
-- which is the engine's own Meat Cleaver split, so wave spawns and summons are
-- covered too. Without it we fall back to one room-wide Meat Cleaver use on
-- entry, which misses anything summoned later but needs no extender.
local function hasRepentogon()
    local repentogon = rawget(_G, "REPENTOGON")
    return type(repentogon) == "table" and repentogon.Real == true
end

local function anyPlayerHasSword()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:HasCollectible(SEALED_DEMON_SWORD_ID) then
            return player
        end
    end
    return nil
end

-- Split bookkeeping, reset per room.
--
-- A half carries 40% of the parent's health, and TrySplit's damage argument is
-- dealt to anything it cannot split. So re-splitting a half does not double it,
-- it kills it. Timing cannot tell a half from a fresh spawn reliably -- halves
-- appear some frames later -- so compare health instead: the first health seen
-- for an enemy kind in this room is the baseline, and anything of that kind that
-- turns up well below it is a half.
local SPLIT_BASELINE_RATIO = 0.9
local MAX_SPLITS_PER_ROOM = 60

local splitState = {
    handled = {},
    baselineHP = {},
    splits = 0,
    budgetWarned = false,
}

local function resetSplitState()
    splitState.handled = {}
    splitState.baselineHP = {}
    splitState.splits = 0
    splitState.budgetWarned = false
end

-- Champions of the same kind carry a multiplied health pool, so they need their
-- own baseline. Sharing one would make every normal enemy of that kind look like
-- a half next to the champion figure and stop it from ever splitting.
local function enemyKindKey(npc)
    local champion = -1
    if type(npc.GetChampionColorIdx) == "function" then
        local ok, idx = pcall(function() return npc:GetChampionColorIdx() end)
        if ok and type(idx) == "number" then champion = idx end
    end
    return npc.Type .. ":" .. npc.Variant .. ":" .. npc.SubType .. ":" .. champion
end

-- True when this enemy is a product of an earlier split rather than a new spawn.
local function isSplitHalf(npc)
    local key = enemyKindKey(npc)
    local baseline = splitState.baselineHP[key]
    if not baseline then
        splitState.baselineHP[key] = npc.MaxHitPoints
        return false
    end
    if npc.MaxHitPoints > baseline then
        -- A bigger one showed up later (champion, or the baseline was itself a
        -- half from a previous pass). Trust the larger value from now on.
        splitState.baselineHP[key] = npc.MaxHitPoints
        return false
    end
    return npc.MaxHitPoints < baseline * SPLIT_BASELINE_RATIO
end

-- A living monster, with this item's own boss rule on top. Furniture is ruled out by
-- the shared predicate: fires, shopkeepers and machines used to be cleaved too, which
-- handed the player a second shopkeeper to break and left a room with more fireplaces
-- after every visit until the entity count cost frames.
local function isSplitTarget(npc)
    if not EnemyUtils.isLiveMonster(npc) then return false end
    if npc:IsBoss() and not ConchBlessing.sealeddemonsword.data.splitBosses then
        return false
    end
    return true
end

ConchBlessing.sealeddemonsword.onUpdate = function()
    if not hasRepentogon() then return end

    -- A settled room is left alone. That covers shops, arcades and burnt-out fire
    -- rooms, and it stops the scan once the fight ends. Enemies arriving later
    -- shut the doors again, which marks the room uncleared, so they still count.
    local room = Game():GetRoom()
    if room:IsClear() then return end

    local player = anyPlayerHasSword()
    if not player then return end

    local budget = tonumber(ConchBlessing.sealeddemonsword.data.maxSplitsPerRoom)
        or MAX_SPLITS_PER_ROOM
    if splitState.splits >= budget then
        if not splitState.budgetWarned then
            splitState.budgetWarned = true
            ConchBlessing.printDebug(
                "[SealedDemonSword] Split budget reached for this room: " .. tostring(budget))
        end
        return
    end

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc and isSplitTarget(npc) then
            local hash = GetPtrHash(npc)
            if not splitState.handled[hash] then
                -- Mark first either way: a failed split must not retry every frame.
                splitState.handled[hash] = true
                if not isSplitHalf(npc) and type(npc.TrySplit) == "function" then
                    local ok, err = pcall(function()
                        return npc:TrySplit(
                            tonumber(ConchBlessing.sealeddemonsword.data.splitDamage)
                                or SPLIT_DAMAGE,
                            EntityRef(player), false)
                    end)
                    if ok then
                        splitState.splits = splitState.splits + 1
                        if splitState.splits >= budget then break end
                    else
                        ConchBlessing.printError(
                            "[SealedDemonSword] TrySplit failed: " .. tostring(err))
                    end
                end
            end
        end
    end
end

-- New room: forget the previous room's ledger, and run the base-game fallback
-- when TrySplit is unavailable (one room-wide cleave, missing later summons).
ConchBlessing.sealeddemonsword.onNewRoom = function(_)
    resetSplitState()
    if hasRepentogon() then return end
    local player = anyPlayerHasSword()
    if not player then return end
    local room = Game():GetRoom()
    if room:IsClear() then return end
    player:UseActiveItem(CollectibleType.COLLECTIBLE_MEAT_CLEAVER,
        UseFlag.USE_NOANIM | UseFlag.USE_NOCOSTUME)
end

-- On pickup callback
ConchBlessing.sealeddemonsword.onPickup = function(player)
    ConchBlessing.printDebug("[SealedDemonSword] Item picked up")
    
    local data = getSaveData(player)
    -- Initialize if needed
    if not data.killCount then data.killCount = 0 end
    
    -- Force cache update
    player:AddCacheFlags(CacheFlag.CACHE_SPEED)
    player:EvaluateItems()
    
    SaveManager.Save()
end

-- Cache evaluation callback
ConchBlessing.sealeddemonsword.onEvaluateCache = function(_, player, cacheFlag)
    if not player:HasCollectible(SEALED_DEMON_SWORD_ID) then
        return
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        -- Apply speed penalty
        player.MoveSpeed = player.MoveSpeed - SPEED_PENALTY
        ConchBlessing.printDebug("[SealedDemonSword] Applied speed penalty: -" .. tostring(SPEED_PENALTY) .. " -> " .. tostring(player.MoveSpeed))
    end
end

-- NPC death callback - track kills
ConchBlessing.sealeddemonsword.onNPCDeath = function(_, npc)
    local game = Game()
    
    -- Check all players
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:HasCollectible(SEALED_DEMON_SWORD_ID) then
            -- Furniture is not a kill: a stomped fire or a broken shopkeeper used to
            -- count towards the evolution.
            if EnemyUtils.isMonsterKind(npc) then
                local data = getSaveData(player)
                
                -- Increment kill count
                data.killCount = (data.killCount or 0) + 1
                
                ConchBlessing.printDebug("[SealedDemonSword] Kill count: " .. tostring(data.killCount) .. "/" .. tostring(KILLS_TO_EVOLVE))
                
                -- Check for evolution
                if data.killCount >= KILLS_TO_EVOLVE then
                    ConchBlessing.printDebug("[SealedDemonSword] Evolution triggered! Transforming to Tyrfing...")
                    
                    -- Initialize Tyrfing data
                    local playerSave = SaveManager.GetRunSave(player)
                    playerSave.tyrfing = playerSave.tyrfing or {}
                    playerSave.tyrfing.accumulatedDamage = 0 -- Tyrfing starts fresh
                    playerSave.tyrfing.deathChance = 10 -- Base death chance for Tyrfing
                    
                    -- Remove Sealed Demon Sword and add Tyrfing
                    player:RemoveCollectible(SEALED_DEMON_SWORD_ID)
                    player:AddCollectible(TYRFING_ID, 0, false)
                    
                    -- Play transformation effect
                    SFXManager():Play(SoundEffect.SOUND_POWERUP_SPEWER, 1.0)
                    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, player.Position, Vector.Zero, nil)
                    
                    -- Clear sealed demon sword data
                    playerSave.sealedDemonSword = nil
                    
                    SaveManager.Save()
                    return
                end
                
                SaveManager.Save()
            end
        end
    end
end

-- Game started callback
ConchBlessing.sealeddemonsword.onGameStarted = function(_)
    ConchBlessing.printDebug("[SealedDemonSword] Game started, restoring data...")
    
    local player = Isaac.GetPlayer(0)
    if player and player:HasCollectible(SEALED_DEMON_SWORD_ID) then
        player:AddCacheFlags(CacheFlag.CACHE_SPEED)
        player:EvaluateItems()
    end
end

-- EID dynamic description modifier to show remaining kills
if EID then
    EID:addDescriptionModifier("Sealed Demon Sword Remaining Kills", function(descObj)
        if descObj.ObjType == EntityType.ENTITY_PICKUP 
           and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE 
           and descObj.ObjSubType == SEALED_DEMON_SWORD_ID then
            
            local player = Isaac.GetPlayer(0)
            local remaining = KILLS_TO_EVOLVE
            
            if player then
                local playerSave = SaveManager.GetRunSave(player)
                local data = playerSave.sealedDemonSword or {}
                local killCount = data.killCount or 0
                remaining = KILLS_TO_EVOLVE - killCount
            end
            
            -- Get current language
            local ConchBlessing_Config = require("scripts.conch_blessing_config")
            local currentLang = ConchBlessing_Config.GetCurrentLanguage()
            
            -- Add remaining kills info to description
            local remainingText = ""
            if currentLang == "kr" then
                remainingText = "#{{ColorYellow}}남은 처치 수: " .. tostring(remaining) .. "{{CR}}"
            else
                remainingText = "#{{ColorYellow}}Remaining kills: " .. tostring(remaining) .. "{{CR}}"
            end
            
            -- Append to existing description
            descObj.Description = descObj.Description .. remainingText
            
        end
        
        return descObj
    end)
    
    ConchBlessing.printDebug("[EID] Sealed Demon Sword: Description modifier registered")
end
