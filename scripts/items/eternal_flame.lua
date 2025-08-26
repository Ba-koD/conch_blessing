ConchBlessing.eternalflame = {}

ConchBlessing.eternalflame.data = {
    curseRemoved = false,
    curseRemovalTimer = nil,
    pendingCurses = nil,
    pendingCurseCount = nil,
    fixedDamageBonus = 3.0,
    fixedFireDelayBonus = 1.0,
    curseCount = 0
}

local ETERNAL_FLAME_ID = Isaac.GetItemIdByName("Eternal Flame")

local function supportsTearPoisonAPI(player)
    return player and type(player.GetTearPoisonDamage) == "function" and type(player.SetTearPoisonDamage) == "function"
end

-- remove curses and apply stat bonuses (following da rules logic with timer)
local function removeCurses(player)
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

-- detect curse changes with 1 second delay
local function detectCurseChanges(player)
    local level = Game():GetLevel()
    local data = ConchBlessing.eternalflame.data
    
    if not data then return end
    
    if data.curseRemoved then return end
    
    local currentCurses = level:GetCurses()
    
    if currentCurses ~= 0 then
        ConchBlessing.printDebug("Eternal Flame: Detected curses: 0x" .. string.format("%X", currentCurses))
        
        local curseNames = {}
        for curseName, curseValue in pairs(LevelCurse) do
            if curseValue > 0 and currentCurses & curseValue > 0 then
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

-- callback functions
function ConchBlessing.eternalflame.onPickup(_, player, collectibleType, rng)
    if collectibleType ~= ETERNAL_FLAME_ID then return end
    
    ConchBlessing.printDebug("Eternal Flame picked up by player")
    
    -- initial data setup
    local data = ConchBlessing.eternalflame.data
    if data then
        data.curseRemoved = false
    end
end

function ConchBlessing.eternalflame.onEvaluateCache(_, player, cacheFlag)
    if not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE and cacheFlag ~= CacheFlag.CACHE_FIREDELAY then return end
    
    local data = ConchBlessing.eternalflame.data
    if not data then return end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        if data.curseCount > 0 then
            local totalDamageBonus = data.curseCount * data.fixedDamageBonus
            player.Damage = player.Damage + totalDamageBonus
            
            if supportsTearPoisonAPI(player) then
                local pdata = player:GetData()
                pdata.conch_eternalflame_tpd_base = pdata.conch_eternalflame_tpd_base or player:GetTearPoisonDamage()
                if data.fixedDamageBonus == 0 then
                    pdata.conch_eternalflame_tpd_base = player:GetTearPoisonDamage()
                end
                local base = pdata.conch_eternalflame_tpd_base or 0
                local totalDamage = base + totalDamageBonus
                player:SetTearPoisonDamage(totalDamage)
            end
        end
        
    elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
        if data.curseCount > 0 then
            local currentMaxFireDelay = player.MaxFireDelay
            local currentSPS = 30 / (currentMaxFireDelay + 1)
            local totalFireDelayBonus = data.curseCount * data.fixedFireDelayBonus
            local targetSPS = currentSPS + totalFireDelayBonus
            
            local newMaxFireDelay = math.max(0, (30 / targetSPS) - 1)
            
            local fireDelayReduction = currentMaxFireDelay - newMaxFireDelay
            player.MaxFireDelay = math.max(0, currentMaxFireDelay - fireDelayReduction)
            
            ConchBlessing.printDebug("Eternal Flame: FireDelay -" .. string.format("%.2f", fireDelayReduction) .. 
                " (SPS: " .. string.format("%.2f", currentSPS) .. " -> " .. string.format("%.2f", targetSPS) .. 
                " | Curse bonus: +" .. totalFireDelayBonus .. ")")
        end
    end
end

local function resetCurseDetection()
    local data = ConchBlessing.eternalflame.data
    if data then
        data.curseRemoved = false
        data.curseRemovalTimer = nil
        data.pendingCurses = nil
        data.pendingCurseCount = nil
    end
end

-- reset curse detection on new level
function ConchBlessing.eternalflame.onNewLevel()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    resetCurseDetection()
    ConchBlessing.printDebug("Eternal Flame: New level entered, curse detection reset (Total curses removed: " .. ConchBlessing.eternalflame.data.curseCount .. ")")
end

-- reset curse detection on new room
function ConchBlessing.eternalflame.onNewRoom()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    resetCurseDetection()
    ConchBlessing.printDebug("Eternal Flame: New room entered, curse detection reset")
end

-- increase curse chance
function ConchBlessing.eternalflame.onCurseEval(level, curses)
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    for curseName, curseValue in pairs(LevelCurse) do
        if curseValue > 0 and curses & curseValue == 0 and math.random() < 0.3 then
            curses = curses | curseValue
            ConchBlessing.printDebug("Eternal Flame: Added curse: " .. curseName .. " (0x" .. string.format("%X", curseValue) .. ")")
        end
    end
    
    return curses
end

function ConchBlessing.eternalflame.onUpdate(_)
    ConchBlessing.template.onUpdate(ConchBlessing.eternalflame.data)
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
    
    local data = ConchBlessing.eternalflame.data
    if not data then return end
    
    if not data.curseRemoved then
        if data.curseRemovalTimer and data.curseRemovalTimer > 0 then
            data.curseRemovalTimer = data.curseRemovalTimer - 1
            if data.curseRemovalTimer <= 0 then
                ConchBlessing.printDebug("Eternal Flame: Timer expired, executing curse removal...")
                removeCurses(player)
            end
        else
            detectCurseChanges(player)
        end
    else
        local level = Game():GetLevel()
        local currentCurses = level:GetCurses()
        if currentCurses ~= 0 then
            ConchBlessing.printDebug("Eternal Flame: New curses detected after removal, resetting detection...")
            data.curseRemoved = false
            detectCurseChanges(player)
        end
    end
    
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

-- optional custom upgrade handlers (called by upgrade system)
ConchBlessing.eternalflame.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.eternalflame.data)
end

ConchBlessing.eternalflame.onAfterChange = function(upgradePos, pickup, itemData)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.eternalflame.data)
end

-- onPlayerUpdate function for callback registration
function ConchBlessing.eternalflame.onPlayerUpdate(_, player)
    if not player or not player:HasCollectible(ETERNAL_FLAME_ID) then return end
end
