local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
ConchBlessing.tyrfing = {}

local TYRFING_ID = Isaac.GetItemIdByName("Tyrfing")

local SaveManager = require("scripts.lib.save_manager")
local Hits = require("scripts.lib.player_hits")
local EnemyUtils = require("scripts.lib.enemy_utils")

-- Constants
local DAMAGE_PER_KILL = 0.05 -- +0.05 damage per kill per currently owned copy
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

-- A dead holder (in its death animation) or a co-op ghost earns nothing from kills.
local function isActingPlayer(player)
    if not player then return false end
    if type(player.IsDead) == "function" and player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

-- Cache evaluation callback. The XML cache="damage" makes the engine evaluate
-- damage on acquisition and loss, so no pickup hook is needed.
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
    
    -- Self-damage and Sacrifice Room spikes are not hits (scripts/lib/player_hits.lua).
    if not Hits.counts(flags) then
        ConchBlessing.printDebug(string.format("[Tyrfing] Ignored self-inflicted damage (flags=%d)", flags or -1))
        return
    end
    
    local data = getSaveData(player)
    local currentDamage = data.accumulatedDamage or 0
    
    if currentDamage > 0 then
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
    return true
end
Hits.register("TYRFING", ConchBlessing.tyrfing.onEntityTakeDamage)

-- NPC death callback - add damage
ConchBlessing.tyrfing.onNPCDeath = function(_, npc)
    local game = Game()
    
    -- Check all living holders
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if isActingPlayer(player) and player:HasCollectible(TYRFING_ID) then
            -- Furniture is not a kill: fires and shopkeepers used to pay damage too.
            if EnemyUtils.isMonsterKind(npc) then
                local data = getSaveData(player)
                
                -- Earn each copy's contribution now; later inventory changes do
                -- not rescale damage already accumulated.
                local stackCount = player:GetCollectibleNum(TYRFING_ID)
                data.accumulatedDamage = (data.accumulatedDamage or 0) + DAMAGE_PER_KILL * stackCount
                
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

    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:HasCollectible(TYRFING_ID) then
            local data = getSaveData(player)
            ConchBlessing.printDebug("[Tyrfing] Restored - Accumulated damage: " .. tostring(data.accumulatedDamage))

            player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
            player:EvaluateItems()
        end
    end
end

-- EID dynamic description modifier to show accumulated damage
if EID then
    EID:addDescriptionModifier("Tyrfing Accumulated Damage", function(descObj)
        if descObj.ObjType == EntityType.ENTITY_PICKUP 
           and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE 
           and descObj.ObjSubType == TYRFING_ID then
            
            -- EID's own reader of this description: the Item Reminder's player,
            -- else the one nearest the pedestal. Never a guess at player 0.
            local player = nil
            if type(EID.ClosestPlayerTo) == "function" then
                local ok, found = pcall(EID.ClosestPlayerTo, EID, descObj.Entity)
                player = ok and found or nil
            end
            local accDmg = 0

            local playerSave = player and SaveManager.TryGetRunSave(player)
            if type(playerSave) == "table" then
                local data = playerSave.tyrfing or {}
                accDmg = data.accumulatedDamage or 0
            end
            
            -- Add accumulated damage info to description (text: ui.tyrfing in scripts/locale)
            local infoText = ConchBlessing.Locale.text("ui.tyrfing.accumulated_damage", string.format("%.2f", accDmg))
            
            -- Append to existing description
            descObj.Description = descObj.Description .. infoText
            
        end
        
        return descObj
    end)
    
    ConchBlessing.printDebug("[EID] Tyrfing: Description modifier registered")
end
