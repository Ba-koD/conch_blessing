ConchBlessing.tyrfing = {}

local TYRFING_ID = Isaac.GetItemIdByName("Tyrfing")

local SaveManager = require("scripts.lib.save_manager")
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")

-- Constants
local DAMAGE_PER_KILL = 0.05 -- +0.05 damage per kill
local DAMAGE_LOSS_ON_HIT = 0.5 -- Lose 50% of accumulated damage on hit

-- Data structure
ConchBlessing.tyrfing.data = {
    damagePerKill = DAMAGE_PER_KILL,
    damageLossOnHit = DAMAGE_LOSS_ON_HIT
}


-- Get saved data for player
local function getSaveData(player)
    local playerSave = SaveManager.GetRunSave(player)
    if not playerSave.tyrfing then
        playerSave.tyrfing = {
            accumulatedDamage = 0
        }
    end
    return playerSave.tyrfing
end

-- On pickup callback
ConchBlessing.tyrfing.onPickup = function(player)
    ConchBlessing.printDebug("[Tyrfing] Item picked up")
    
    local data = getSaveData(player)
    
    -- Initialize if needed
    if data.accumulatedDamage == nil then
        data.accumulatedDamage = 0
    end
    
    ConchBlessing.printDebug("[Tyrfing] Accumulated damage: " .. tostring(data.accumulatedDamage))
    
    -- Force cache update
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
    player:EvaluateItems()
    
    SaveManager.Save()
end

-- Cache evaluation callback
ConchBlessing.tyrfing.onEvaluateCache = function(_, player, cacheFlag)
    if not player:HasCollectible(TYRFING_ID) then
        return
    end
    
    local data = getSaveData(player)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        -- Apply accumulated damage from killing enemies
        local accDmg = data.accumulatedDamage or 0
        if accDmg > 0 then
            ConchBlessing.stats.damage.applyAddition(player, accDmg, nil)
            ConchBlessing.printDebug("[Tyrfing] Applied accumulated damage: +" .. tostring(accDmg))
        end
    end
    
    -- Note: No tear delay penalty for Tyrfing (evolution removes the penalty)
end

-- Entity take damage callback - lose 50% accumulated damage on hit
ConchBlessing.tyrfing.onEntityTakeDamage = function(_, entity, amount, flags, source, countdown)
    local player = entity:ToPlayer()
    if not player then return end
    
    if not player:HasCollectible(TYRFING_ID) then return end
    
    -- Ignore self-inflicted damage (same as time_power)
    if DamageUtils.isSelfInflictedDamage(flags) then
        ConchBlessing.printDebug(string.format("[Tyrfing] Ignored self-inflicted damage (flags=%d)", flags or -1))
        return
    end
    
    local data = getSaveData(player)
    local currentDamage = data.accumulatedDamage or 0
    
    if currentDamage > 0 then
        -- Lose 50% of accumulated damage
        local damageLost = currentDamage * DAMAGE_LOSS_ON_HIT
        data.accumulatedDamage = currentDamage - damageLost
        
        ConchBlessing.printDebug(string.format("[Tyrfing] Player took damage! Lost %.2f damage (%.2f -> %.2f)", 
            damageLost, currentDamage, data.accumulatedDamage))
        
        -- Update cache for damage change
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
        
        SaveManager.Save()
    else
        ConchBlessing.printDebug("[Tyrfing] Player took damage but no accumulated damage to lose")
    end
end

-- NPC death callback - add damage
ConchBlessing.tyrfing.onNPCDeath = function(_, npc)
    local game = Game()
    
    -- Check all players
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:HasCollectible(TYRFING_ID) then
            -- Ignore friendly NPCs
            if npc and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) and npc:IsEnemy() then
                local data = getSaveData(player)
                
                -- Add damage bonus per kill
                data.accumulatedDamage = (data.accumulatedDamage or 0) + DAMAGE_PER_KILL
                
                -- Only log every 10 kills to reduce spam
                local shouldLog = math.random(1, 10) == 1
                if shouldLog then
                    ConchBlessing.printDebug("[Tyrfing] Enemy killed, accumulated damage: +" .. string.format("%.2f", data.accumulatedDamage))
                end
                
                -- Update cache for damage change
                player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
                player:EvaluateItems()
                
                SaveManager.Save()
            end
        end
    end
end

-- Game started callback
ConchBlessing.tyrfing.onGameStarted = function(_)
    ConchBlessing.printDebug("[Tyrfing] Game started, restoring data...")
    
    local player = Isaac.GetPlayer(0)
    if player and player:HasCollectible(TYRFING_ID) then
        local data = getSaveData(player)
        ConchBlessing.printDebug("[Tyrfing] Restored - Accumulated damage: " .. tostring(data.accumulatedDamage))
        
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
end

-- Update callback
ConchBlessing.tyrfing.onUpdate = function(_)
    -- Handle template update if needed
    if ConchBlessing.template and ConchBlessing.template.onUpdate then
        ConchBlessing.template.onUpdate(ConchBlessing.tyrfing.data)
    end
end

-- Upgrade related functions (for display effects)
ConchBlessing.tyrfing.onBeforeChange = function(upgradePos, pickup, itemData)
    if ConchBlessing.template and ConchBlessing.template.positive then
        return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.tyrfing.data)
    end
    return 0
end

ConchBlessing.tyrfing.onAfterChange = function(upgradePos, pickup, itemData)
    if ConchBlessing.template and ConchBlessing.template.positive then
        return ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.tyrfing.data)
    end
    return 0
end

-- EID dynamic description modifier to show accumulated damage
if EID then
    EID:addDescriptionModifier("Tyrfing Accumulated Damage", function(descObj)
        if descObj.ObjType == EntityType.ENTITY_PICKUP 
           and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE 
           and descObj.ObjSubType == TYRFING_ID then
            
            local player = Isaac.GetPlayer(0)
            local accDmg = 0
            
            if player then
                local playerSave = SaveManager.GetRunSave(player)
                local data = playerSave.tyrfing or {}
                accDmg = data.accumulatedDamage or 0
            end
            
            -- Get current language
            local ConchBlessing_Config = require("scripts.conch_blessing_config")
            local currentLang = ConchBlessing_Config.GetCurrentLanguage()
            
            -- Add accumulated damage info to description
            local infoText = ""
            if currentLang == "kr" then
                infoText = "#{{Damage}} 누적 공격력: +" .. string.format("%.2f", accDmg)
            else
                infoText = "#{{Damage}} Accumulated damage: +" .. string.format("%.2f", accDmg)
            end
            
            -- Append to existing description
            descObj.Description = descObj.Description .. infoText
            
            ConchBlessing.printDebug("[EID] Tyrfing: Added accumulated damage info: +" .. string.format("%.2f", accDmg))
        end
        
        return descObj
    end)
    
    ConchBlessing.printDebug("[EID] Tyrfing: Description modifier registered")
end
