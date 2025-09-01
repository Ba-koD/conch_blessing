ConchBlessing.eternalflame = {}

-- SaveManager integration
local SaveManager = require("scripts.lib.save_manager")

ConchBlessing.eternalflame.data = {
    curseRemoved = false,
    curseRemovalTimer = nil,
    pendingCurses = nil,
    pendingCurseCount = nil,
    baseDamageBonus = 3.0,
    baseFireDelayBonus = 1.0,
    curseCount = 0,
    itemCount = 0
}

local ETERNAL_FLAME_ID = Isaac.GetItemIdByName("Eternal Flame")

local function supportsTearPoisonAPI(player)
    return player and type(player.GetTearPoisonDamage) == "function" and type(player.SetTearPoisonDamage) == "function"
end

-- Execute curse removal and apply stat bonuses
local function executeCurseRemoval(player)
    local level = Game():GetLevel()
    local data = ConchBlessing.eternalflame.data
    
    if not data or not data.pendingCurses or not data.pendingCurseCount then return end
    
    local cursesToRemove = data.pendingCurses
    local curseCount = data.pendingCurseCount
    
    ConchBlessing.printDebug("Eternal Flame: Executing curse removal for " .. curseCount .. " curses...")
    ConchBlessing.printDebug("Eternal Flame: Curses bitmask: " .. string.format("0x%X", cursesToRemove))
    
    local removedCount = 0
    
    local currentCurses = level:GetCurses()
    ConchBlessing.printDebug("Eternal Flame: Current curses before removal: 0x" .. string.format("%X", currentCurses))
    
    ConchBlessing.printDebug("Eternal Flame: Found " .. curseCount .. " active curses to remove")
    
    if currentCurses > 0 then
        level:RemoveCurses(currentCurses)
        removedCount = curseCount
        
        local finalCurses = level:GetCurses()
        if finalCurses == 0 then
            ConchBlessing.printDebug("Eternal Flame: Successfully removed all " .. removedCount .. " curses!")
        else
            ConchBlessing.printDebug("Eternal Flame: Warning - " .. string.format("0x%X", finalCurses) .. " curses still remain")
        end
    end
    
    if level:GetCurses() == 0 then
        ConchBlessing.printDebug("Eternal Flame: Successfully removed all curses!")
        
        data.curseRemoved = true
        data.curseCount = data.curseCount + removedCount
        
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY)
        player:EvaluateItems()
        
        local flameEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, 1, 0, player.Position, Vector.Zero, player)
        if flameEffect then
            local sprite = flameEffect:GetSprite()
            if sprite then
                sprite:Load("gfx/effects/flame.anm2", true)
                sprite:Play("Idle", true)
            end
            
            if flameEffect.SetTimeout then
                flameEffect:SetTimeout(60)
            end
            
            if not ConchBlessing.eternalflame.activeEffects then
                ConchBlessing.eternalflame.activeEffects = {}
            end
            
            table.insert(ConchBlessing.eternalflame.activeEffects, {
                effect = flameEffect,
                timer = 60
            })
        end
        
        data.curseRemovalTimer = nil
        data.pendingCurses = nil
        data.pendingCurseCount = nil
        
        ConchBlessing.printDebug("Eternal Flame: Curse removal completed, timer cleared")
    else
        ConchBlessing.printDebug("Eternal Flame: Some curses could not be removed - they may be persistent or require special handling")
        ConchBlessing.printDebug("Eternal Flame: Remaining curses: 0x" .. string.format("%X", level:GetCurses()))
        
        data.curseRemovalTimer = nil
        data.pendingCurses = nil
        data.pendingCurseCount = nil
        
        ConchBlessing.printDebug("Eternal Flame: Curse removal failed, no stat bonuses applied")
    end
end

-- Monitor curse changes and set removal timer
local function monitorCurseChanges(player)
    local level = Game():GetLevel()
    local data = ConchBlessing.eternalflame.data
    
    if not data then return end
    
    if data.curseRemoved then return end
    
    local currentCurses = level:GetCurses()
    
    if currentCurses ~= 0 then
        ConchBlessing.printDebug("Eternal Flame: Detected curses: 0x" .. string.format("%X", currentCurses))
        
        local curseNames = {}
        for curseName, curseValue in pairs(LevelCurse) do
            -- Skip NUM_CURSES as it's not an actual curse
            if curseName ~= "NUM_CURSES" and curseValue > 0 and currentCurses & curseValue > 0 then
                table.insert(curseNames, curseName)
            end
        end
        
        ConchBlessing.printDebug("Eternal Flame: Active curses: " .. table.concat(curseNames, ", "))
        
        data.curseRemovalTimer = 30
        data.pendingCurses = currentCurses
        data.pendingCurseCount = #curseNames
        
        ConchBlessing.printDebug("Eternal Flame: Found " .. data.pendingCurseCount .. " curses, timer set to 30 frames")
    end
end

-- Calculate stacking bonuses based on item count
local function calculateStackingBonus(baseValue, itemCount)
    if itemCount <= 1 then
        return baseValue
    else
        local multiplier = 1.0 + (itemCount - 1)
        return baseValue * multiplier
    end
end

-- Handle item pickup and update stacking data
function ConchBlessing.eternalflame.onPickup(_, player, collectibleType, rng)
    if collectibleType ~= ETERNAL_FLAME_ID then return end
    
    ConchBlessing.printDebug("Eternal Flame picked up by player")
    
    -- Update item count for stacking
    local data = ConchBlessing.eternalflame.data
    if data then
        data.itemCount = player:GetCollectibleNum(ETERNAL_FLAME_ID)
        data.curseRemoved = false
        
        ConchBlessing.printDebug("Eternal Flame: Item count updated to " .. data.itemCount .. " for stacking calculations")
    end
end

-- Apply stat bonuses when cache is evaluated
function ConchBlessing.eternalflame.onEvaluateCache(_, player, cacheFlag)
    if not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    local data = ConchBlessing.eternalflame.data
    if not data then return end
    
    -- Update item count for current evaluation
    data.itemCount = player:GetCollectibleNum(ETERNAL_FLAME_ID)
    
    -- Give eternal heart on first evaluation (when item is first obtained)
    if not data.eternalHeartGiven then
        player:AddEternalHearts(1)
        data.eternalHeartGiven = true
        ConchBlessing.printDebug("Eternal Flame: Added 1 eternal heart to player on first evaluation")
    end
    
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE and cacheFlag ~= CacheFlag.CACHE_FIREDELAY then return end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        if data.curseCount > 0 then
            local baseDamageBonus = calculateStackingBonus(data.baseDamageBonus, data.itemCount)
            local totalDamageBonus = data.curseCount * baseDamageBonus
            
            -- Use stats system with addition
            ConchBlessing.stats.damage.applyAddition(player, totalDamageBonus, nil)
            
            ConchBlessing.printDebug("Eternal Flame: Damage addition - Base bonus: " .. string.format("%.2f", baseDamageBonus) .. 
                ", Total addition: " .. string.format("%.2f", totalDamageBonus) .. 
                ", Item count: " .. data.itemCount)
            
            -- Save curse count to SaveManager
            local playerSave = SaveManager.GetRunSave(player)
            if playerSave then
                if not playerSave.eternalFlame then
                    playerSave.eternalFlame = {}
                end
                playerSave.eternalFlame.curseCount = data.curseCount
                playerSave.eternalFlame.itemCount = data.itemCount
                SaveManager.Save()
                ConchBlessing.printDebug("Eternal Flame: Curse count and item count saved to SaveManager: " .. data.curseCount .. ", " .. data.itemCount)
            end
        end
        
    elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
        if data.curseCount > 0 then
            local currentMaxFireDelay = player.MaxFireDelay
            local currentSPS = 30 / (currentMaxFireDelay + 1)
            local baseFireDelayBonus = calculateStackingBonus(data.baseFireDelayBonus, data.itemCount)
            local totalFireDelayBonus = data.curseCount * baseFireDelayBonus
            
            -- Use stats system with addition
            ConchBlessing.stats.tears.applyAddition(player, totalFireDelayBonus, nil)
            
            ConchBlessing.printDebug("Eternal Flame: FireDelay addition - Base bonus: " .. string.format("%.2f", baseFireDelayBonus) .. 
                ", Total addition: " .. string.format("%.2f", totalFireDelayBonus) .. 
                ", SPS: " .. string.format("%.2f", currentSPS) .. " -> " .. string.format("%.2f", currentSPS + totalFireDelayBonus) .. 
                ", Item count: " .. data.itemCount)
        end
    end
end

-- Reset curse detection state
local function resetCurseDetectionState()
    local data = ConchBlessing.eternalflame.data
    if data then
        data.curseRemoved = false
        data.curseRemovalTimer = nil
        data.pendingCurses = nil
        data.pendingCurseCount = nil
    end
end

-- Handle new level entry
function ConchBlessing.eternalflame.onNewLevel()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    resetCurseDetectionState()
    ConchBlessing.printDebug("Eternal Flame: New level entered, curse detection reset (Total curses removed: " .. ConchBlessing.eternalflame.data.curseCount .. ")")
end

-- Handle new room entry
function ConchBlessing.eternalflame.onNewRoom()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    resetCurseDetectionState()
    ConchBlessing.printDebug("Eternal Flame: New room entered, curse detection reset")
end

-- Main update loop for curse management and effects
function ConchBlessing.eternalflame.onUpdate(_)
    ConchBlessing.template.onUpdate(ConchBlessing.eternalflame.data)
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    local data = ConchBlessing.eternalflame.data
    if not data then return end
    
    -- Update item count for stacking calculations
    data.itemCount = player:GetCollectibleNum(ETERNAL_FLAME_ID)
    
    if not data.curseRemoved then
        if data.curseRemovalTimer and data.curseRemovalTimer > 0 then
            data.curseRemovalTimer = data.curseRemovalTimer - 1
            if data.curseRemovalTimer <= 0 then
                ConchBlessing.printDebug("Eternal Flame: Timer expired, executing curse removal...")
                executeCurseRemoval(player)
            end
        else
            monitorCurseChanges(player)
        end
    else
        local level = Game():GetLevel()
        local currentCurses = level:GetCurses()
        if currentCurses ~= 0 then
            ConchBlessing.printDebug("Eternal Flame: New curses detected after removal, resetting detection...")
            data.curseRemoved = false
            monitorCurseChanges(player)
        end
    end
    
    -- Update flame effects
    if ConchBlessing.eternalflame.activeEffects then
        for i = #ConchBlessing.eternalflame.activeEffects, 1, -1 do
            local effectData = ConchBlessing.eternalflame.activeEffects[i]
            if effectData and effectData.effect and effectData.effect:Exists() then
                effectData.timer = effectData.timer - 1
                if effectData.timer <= 0 then
                    effectData.effect:Remove()
                    table.remove(ConchBlessing.eternalflame.activeEffects, i)
                end
            else
                table.remove(ConchBlessing.eternalflame.activeEffects, i)
            end
        end
    end
end

-- Optional custom upgrade handlers (called by upgrade system)
ConchBlessing.eternalflame.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.eternalflame.data)
end

ConchBlessing.eternalflame.onAfterChange = function(upgradePos, pickup, itemData)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.eternalflame.data)
end

-- Player update handler for callback registration
function ConchBlessing.eternalflame.onPlayerUpdate(_, player)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
end

-- Initialize data when game started
ConchBlessing.eternalflame.onGameStarted = function(_)
    local player = Isaac.GetPlayer(0)
    if player then
        local playerSave = SaveManager.GetRunSave(player)
        
        -- Check if this is a new game (no saved data)
        if not playerSave or not playerSave.eternalFlame or not playerSave.eternalFlame.curseCount or playerSave.eternalFlame.curseCount == 0 then
            -- New game - reset data
            local data = ConchBlessing.eternalflame.data
            if data then
                data.curseCount = 0
                data.itemCount = 0
                data.curseRemoved = false
                data.curseRemovalTimer = nil
                data.pendingCurses = nil
                data.pendingCurseCount = nil
                data.eternalHeartGiven = false
            end
            
            -- Clear saved data
            if playerSave then
                if not playerSave.eternalFlame then
                    playerSave.eternalFlame = {}
                end
                playerSave.eternalFlame.curseCount = 0
                playerSave.eternalFlame.itemCount = 0
                SaveManager.Save()
            end
            
            ConchBlessing.printDebug("Eternal Flame: New game detected, data reset to 0")
        else
            -- Continue game - load saved data
            if playerSave.eternalFlame.curseCount then
                local data = ConchBlessing.eternalflame.data
                if data then
                    data.curseCount = playerSave.eternalFlame.curseCount
                    data.itemCount = playerSave.eternalFlame.itemCount or 0
                    ConchBlessing.printDebug("Eternal Flame: Loaded curse count from SaveManager: " .. data.curseCount .. ", item count: " .. data.itemCount)
                    
                    -- Apply stats on game start if player has the item
                    if player:HasCollectible(ETERNAL_FLAME_ID) then
                        ConchBlessing.printDebug("Eternal Flame: Applying stats on game start for " .. data.curseCount .. " curses with " .. data.itemCount .. " items")
                        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY)
                        player:EvaluateItems()
                        ConchBlessing.printDebug("Eternal Flame: Stats applied on game start!")
                    end
                end
            else
                ConchBlessing.printDebug("Eternal Flame: No saved data, starting with 0 curse count")
            end
        end
    else
        ConchBlessing.printDebug("Eternal Flame: No player found on game start")
    end
    
    ConchBlessing.printDebug("Eternal Flame: onGameStarted called!")
end
