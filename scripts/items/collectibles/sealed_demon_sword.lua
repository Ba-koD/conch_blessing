ConchBlessing.sealeddemonsword = {}

local SEALED_DEMON_SWORD_ID = Isaac.GetItemIdByName("Sealed Demon Sword")
local TYRFING_ID = Isaac.GetItemIdByName("Tyrfing")

local SaveManager = require("scripts.lib.save_manager")

-- Constants
local KILLS_TO_EVOLVE = 300
local SPEED_PENALTY = 0.2

-- Data structure
ConchBlessing.sealeddemonsword.data = {
    killsToEvolve = KILLS_TO_EVOLVE,
    speedPenalty = SPEED_PENALTY
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
            -- Ignore friendly NPCs
            if npc and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) and npc:IsEnemy() then
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

-- Update callback
ConchBlessing.sealeddemonsword.onUpdate = function(_)
    -- Handle template update if needed
    if ConchBlessing.template and ConchBlessing.template.onUpdate then
        ConchBlessing.template.onUpdate(ConchBlessing.sealeddemonsword.data)
    end
end

-- Upgrade related functions (for Magic Conch positive enhancement)
ConchBlessing.sealeddemonsword.onBeforeChange = function(upgradePos, pickup, itemData)
    if ConchBlessing.template and ConchBlessing.template.positive then
        return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.sealeddemonsword.data)
    end
    return 0
end

ConchBlessing.sealeddemonsword.onAfterChange = function(upgradePos, pickup, itemData)
    -- When upgraded via Magic Conch, initialize Tyrfing data
    local player = Isaac.GetPlayer(0)
    if player then
        local playerSave = SaveManager.GetRunSave(player)
        
        -- Initialize Tyrfing data
        playerSave.tyrfing = playerSave.tyrfing or {}
        playerSave.tyrfing.accumulatedDamage = 0 -- Tyrfing starts fresh
        playerSave.tyrfing.deathChance = 10 -- Base death chance
        
        -- Clear sealed demon sword data
        playerSave.sealedDemonSword = nil
        
        SaveManager.Save()
        ConchBlessing.printDebug("[SealedDemonSword] Upgraded to Tyrfing via Magic Conch")
    end
    
    if ConchBlessing.template and ConchBlessing.template.positive then
        return ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.sealeddemonsword.data)
    end
    return 0
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
            
            ConchBlessing.printDebug("[EID] Sealed Demon Sword: Added remaining kills info: " .. tostring(remaining))
        end
        
        return descObj
    end)
    
    ConchBlessing.printDebug("[EID] Sealed Demon Sword: Description modifier registered")
end
