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

local function getRewards(player)
    local save = SaveManager.GetRunSave(player)
    if not save then return nil end
    save.eternalFlame = save.eternalFlame or {}
    local rewards = save.eternalFlame
    if rewards.earnedUnits == nil then
        -- Old saves recorded only the total curses and last observed stack.
        -- Freeze their last representable reward once; new removals use exact
        -- acquisition-time units and never rescale that historical total.
        rewards.earnedUnits = math.max(0, rewards.curseCount or 0)
            * math.max(1, rewards.itemCount or 1)
        if (rewards.curseCount or 0) > 0 then rewards.eternalHeartGiven = true end
    end
    return rewards
end

local function countBits(mask)
    local count = 0
    while mask > 0 do count = count + (mask & 1); mask = mask >> 1 end
    return count
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
        removedCount = countBits(currentCurses & (~level:GetCurses()))
        
        local finalCurses = level:GetCurses()
        if finalCurses == 0 then
            ConchBlessing.printDebug("Eternal Flame: Successfully removed all " .. removedCount .. " curses!")
        else
            ConchBlessing.printDebug("Eternal Flame: Warning - " .. string.format("0x%X", finalCurses) .. " curses still remain")
        end
    end
    
    if removedCount > 0 then
        ConchBlessing.printDebug("Eternal Flame: Awarding rewards for " .. removedCount .. " removed curses")
        
        data.curseRemoved = true
        data.curseCount = data.curseCount + removedCount
        
        -- Each holder earns exactly the copies owned at this removal, even in
        -- co-op. A later pickup, loss or cache evaluation cannot rescale it.
        for i = 0, Game():GetNumPlayers() - 1 do
            local owner = Isaac.GetPlayer(i)
            local copies = owner:GetCollectibleNum(ETERNAL_FLAME_ID, true)
            if copies > 0 then
                local rewards = assert(getRewards(owner), "Eternal Flame run save unavailable")
                rewards.earnedUnits = rewards.earnedUnits + removedCount * copies
                rewards.curseCount = (rewards.curseCount or 0) + removedCount
                rewards.itemCount = copies
                owner:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY)
                owner:EvaluateItems()
            end
        end
        SaveManager.Save()
        
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

-- Pickup callbacks only reset detection; rewards live in the player's run save.
function ConchBlessing.eternalflame.onPickup()
    ConchBlessing.eternalflame.data.curseRemoved = false
end

function ConchBlessing.eternalflame.onEvaluateCache(_, player, cacheFlag)
    local rewards = getRewards(player)
    if not rewards then return end
    if player:HasCollectible(ETERNAL_FLAME_ID) and not rewards.eternalHeartGiven then
        player:AddEternalHearts(1)
        rewards.eternalHeartGiven = true
        SaveManager.Save()
    end
    local units = rewards.earnedUnits
    if units <= 0 then return end
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.stats.damage.applyAddition(player, units * 3, nil)
    elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
        ConchBlessing.stats.tears.applyAddition(player, units, nil)
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

local function updateFlameEffects()
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

-- Main update loop for curse management and effects
function ConchBlessing.eternalflame.onUpdate(_)
    updateFlameEffects()
    local player
    for i = 0, Game():GetNumPlayers() - 1 do
        local candidate = Isaac.GetPlayer(i)
        if candidate:HasCollectible(ETERNAL_FLAME_ID) then player = candidate; break end
    end
    if not player then resetCurseDetectionState(); return end

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
    

end

-- Player update handler for callback registration
function ConchBlessing.eternalflame.onPlayerUpdate(_, player)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
end

-- SaveManager supplies the current run (including Continue/Hourglass state).
-- Reapply earned rewards even when no copy remains in the inventory.
ConchBlessing.eternalflame.onGameStarted = function(_)
    resetCurseDetectionState()
    ConchBlessing.eternalflame.activeEffects = {}
    ConchBlessing.eternalflame.data.curseCount = 0
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if getRewards(player) then
            player:AddCacheFlags(CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY)
            player:EvaluateItems()
        end
    end
end
