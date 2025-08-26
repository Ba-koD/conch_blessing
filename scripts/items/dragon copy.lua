local ConchBlessing = ConchBlessing
local DRAGON_ID = Isaac.GetItemIdByName("Dragon")

-- Dragon Item Data
ConchBlessing.dragon = {
    data = {
        chargeTime = 150,      -- Breath Cooldown (ticks, 150 = 5 seconds at 30 FPS)
        breathDuration = 150,  -- Breath Duration (ticks, 150 = 5 seconds at 30 FPS)
        shotspeed = 15.0,      -- Fireball Speed Multiplier
        perroom = 0,           -- Breaths per room (0 = unlimited, >0 = limited)
        colorUpdateInterval = 30,  -- Color update interval (ticks)
        debugInterval = 90,    -- Debug message interval (ticks) to prevent spam
    }
}

-- Check if enemies exist in the current room
function ConchBlessing.dragon.hasEnemies()
    local enemyCount = Isaac.CountEnemies()
    if enemyCount > 0 then return true end
    
    local entities = Isaac.GetRoomEntities()
    if entities then
        for i, entity in ipairs(entities) do
            if entity and type(entity) == "userdata" and entity.IsEnemy and entity.IsActive and entity:IsEnemy() and entity:IsActive() then
                return true
            end
        end
    end
    return false
end

-- Store original player color
function ConchBlessing.dragon.storeOriginalColor(player, dragonData)
    local bodyColor = player:GetBodyColor()
    if bodyColor and type(bodyColor) == "userdata" and bodyColor.Red then
        -- Verify it's a valid Color object
        dragonData.originalColor = {bodyColor = bodyColor}
        ConchBlessing.printDebug("Dragon: Original body color stored: " .. tostring(bodyColor))
    else
        -- Fallback to sprite color
        local playerSprite = player:GetSprite()
        if playerSprite and playerSprite.Color then
            local currentColor = playerSprite.Color
            if currentColor.Red and currentColor.Green and currentColor.Blue and currentColor.Alpha then
                dragonData.originalColor = {
                    r = currentColor.Red,
                    g = currentColor.Green,
                    b = currentColor.Blue,
                    a = currentColor.Alpha
                }
                ConchBlessing.printDebug("Dragon: Original sprite color stored (R:" .. string.format("%.2f", currentColor.Red) .. " G:" .. string.format("%.2f", currentColor.Green) .. " B:" .. string.format("%.2f", currentColor.Blue) .. ")")
            else
                dragonData.originalColor = {r = 1.0, g = 1.0, b = 1.0, a = 1.0}
                ConchBlessing.printDebug("Dragon: Using default white as original color")
            end
        else
            dragonData.originalColor = {r = 1.0, g = 1.0, b = 1.0, a = 1.0}
            ConchBlessing.printDebug("Dragon: Using default white as original color (fallback)")
        end
    end
end

-- Restore original color
function ConchBlessing.dragon.restoreOriginalColor(player, dragonData)
    ConchBlessing.printDebug("Dragon: COLOR RESTORE - Attempting to restore original color")
    
    if dragonData.originalColor then
        if dragonData.originalColor.bodyColor and type(dragonData.originalColor.bodyColor) == "userdata" and dragonData.originalColor.bodyColor.Red then
            -- bodyColor is a valid Color object, use it directly
            player:SetColor(dragonData.originalColor.bodyColor, -1, 1, false, false)
            ConchBlessing.printDebug("Dragon: COLOR RESTORE - Original body color restored (PERMANENT duration)")
        else
            local r = dragonData.originalColor.r or 1.0
            local g = dragonData.originalColor.g or 1.0
            local b = dragonData.originalColor.b or 1.0
            local a = dragonData.originalColor.a or 1.0
            player:SetColor(Color(r, g, b, a, 0, 0, 0), -1, 1, false, false)
            ConchBlessing.printDebug("Dragon: COLOR RESTORE - Original RGB color restored (R:" .. string.format("%.2f", r) .. " G:" .. string.format("%.2f", g) .. " B:" .. string.format("%.2f", b) .. ") - Duration: PERMANENT")
        end
    else
        player:SetColor(Color(1.0, 1.0, 1.0, 1.0, 0, 0, 0), -1, 1, false, false)
        ConchBlessing.printDebug("Dragon: COLOR RESTORE - Default white color restored (no original color stored) - Duration: PERMANENT")
    end
end

-- Reset all dragon states and restore original color
function ConchBlessing.dragon.resetAllStates(player, dragonData)
    local previousState = dragonData.isBreathing and "BREATHING" or (dragonData.chargeTimer > 0 and "CHARGING" or "PRE-CHARGING")
    ConchBlessing.printDebug("Dragon: STATE CHANGE - " .. previousState .. " → PRE-CHARGING (forced reset)")
    
    dragonData.chargeTimer = 0
    dragonData.breathTimer = 0
    dragonData.isBreathing = false
    dragonData.breathingPhase = nil
    dragonData.finalChargeColor = nil
    dragonData.breathsUsed = 0
    
    -- Restore original color
    ConchBlessing.dragon.restoreOriginalColor(player, dragonData)
    
    -- Ensure blindfold is completely removed and shooting is restored
    player:GetData().DragonCantShoot = false
    player:GetData().DragonCanShoot = true
    
    -- Force restore normal challenge to ensure shooting ability
    local currchall = Game().Challenge
    Game().Challenge = 0
    player:UpdateCanShoot()
    Game().Challenge = currchall
    
    -- Restore tearFlags
    player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
    
    ConchBlessing.printDebug("Dragon: All states reset, blindfold removed, shooting restored")
end

-- Handle charging phase (getting redder)
function ConchBlessing.dragon.handleCharging(player, dragonData)
    if dragonData.chargeTimer == 0 then
        -- Store original color on first charge
        ConchBlessing.dragon.storeOriginalColor(player, dragonData)
        ConchBlessing.printDebug("Dragon: STATE CHANGE - Entered CHARGING phase")
    end
    
    dragonData.chargeTimer = dragonData.chargeTimer + 1
    
    -- Color change every 30 ticks (getting redder)
    if dragonData.chargeTimer % ConchBlessing.dragon.data.colorUpdateInterval == 0 then
        local progress = dragonData.chargeTimer / ConchBlessing.dragon.data.chargeTime
        local r = 0.5 + 0.5 * progress  -- 0.5 -> 1.0
        local g = 0.5 * (1.0 - progress)  -- 0.5 -> 0.0
        local b = 0.5 * (1.0 - progress)  -- 0.5 -> 0.0
        
        player:SetColor(Color(r, g, b, 1.0, 0, 0, 0), -1, 1, false, false)
        ConchBlessing.printDebug("Dragon: COLOR SET - Charging color applied (R:" .. string.format("%.2f", r) .. " G:" .. string.format("%.2f", g) .. " B:" .. string.format("%.2f", b) .. ") - Duration: PERMANENT")
        
        -- Debug spam prevention: only every 90 ticks (3 seconds)
        if dragonData.chargeTimer % ConchBlessing.dragon.data.debugInterval == 0 then
            ConchBlessing.printDebug("Dragon: Charging " .. math.floor(progress * 100) .. "% - Color: R:" .. string.format("%.2f", r) .. " G:" .. string.format("%.2f", g) .. " B:" .. string.format("%.2f", b))
        end
    end
end

-- Start breathing phase
function ConchBlessing.dragon.startBreathing(player, dragonData)
    ConchBlessing.printDebug("Dragon: STATE CHANGE - CHARGING → BREATHING transition")
    
    dragonData.isBreathing = true
    dragonData.breathTimer = 0
    dragonData.chargeTimer = 0
    
    -- Store final charge color (full red)
    dragonData.finalChargeColor = {r = 1.0, g = 0.0, b = 0.0}
    
    -- Apply final charge color
    player:SetColor(Color(1.0, 0.0, 0.0, 1.0, 0, 0, 0), -1, 1, false, false)
    ConchBlessing.printDebug("Dragon: COLOR SET - Breathing red color applied (R:1.00 G:0.00 B:0.00) - Duration: PERMANENT")
    ConchBlessing.printDebug("Dragon: BREATHING START - Final charge color applied")
    
    -- Set breathing phase
    dragonData.breathingPhase = "start"
    
    -- Disable shooting (blindfold effect)
    player:GetData().DragonCantShoot = true
    player:GetData().DragonCanShoot = false
    
    local currchall = Game().Challenge
    Game().Challenge = 6
    player:UpdateCanShoot()
    Game().Challenge = currchall
    
    -- Fire fireballs
    local aimDirection = player:GetAimDirection()
    ConchBlessing.dragon.fireTripleFireballs(player, aimDirection, aimDirection.X == 0 and aimDirection.Y == 0)
    
    ConchBlessing.printDebug("Dragon: BREATHING START - Shooting disabled, fireballs fired")
end

-- Handle breathing phase (restoring color)
function ConchBlessing.dragon.handleBreathing(player, dragonData)
    dragonData.breathTimer = dragonData.breathTimer + 1
    
    -- Keep red color during breathing - NO color restoration until complete
    -- The color was already set to red in startBreathing function
    
    -- Check if breathing is complete
    if dragonData.breathTimer >= ConchBlessing.dragon.data.breathDuration then
        ConchBlessing.dragon.completeBreathing(player, dragonData)
    end
    
    -- Fire fireballs during breathing - EVERY TICK for maximum fire rate
    local aimDirection = player:GetAimDirection()
    ConchBlessing.dragon.fireTripleFireballs(player, aimDirection, aimDirection.X == 0 and aimDirection.Y == 0)
    
    -- Debug fireball firing every 30 ticks to avoid spam
    if dragonData.breathTimer % 30 == 0 then
        ConchBlessing.printDebug("Dragon: FIREBALLS - Fired at tick " .. dragonData.breathTimer .. " (every tick firing active)")
    end
end

-- Complete breathing phase
function ConchBlessing.dragon.completeBreathing(player, dragonData)
    ConchBlessing.printDebug("Dragon: STATE CHANGE - BREATHING → COMPLETE transition")
    
    dragonData.isBreathing = false
    dragonData.chargeTimer = 0
    
    -- Increment breaths used counter
    dragonData.breathsUsed = (dragonData.breathsUsed or 0) + 1
    ConchBlessing.printDebug("Dragon: Breath completed! Total breaths used: " .. dragonData.breathsUsed)
    
    -- Restore original color when breathing is complete
    ConchBlessing.dragon.restoreOriginalColor(player, dragonData)
    
    -- Restore shooting ability
    player:GetData().DragonCantShoot = false
    player:GetData().DragonCanShoot = true
    
    local currchall = Game().Challenge
    Game().Challenge = 0
    player:UpdateCanShoot()
    Game().Challenge = currchall
    
    -- Restore tearFlags
    player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
    
    ConchBlessing.printDebug("Dragon: BREATHING COMPLETE - Original color restored, shooting restored, back to charging mode")
end

-- Main dragon state management function
function ConchBlessing.dragon.manageDragonState(player, dragonData)
    local hasEnemies = ConchBlessing.dragon.hasEnemies()
    
    -- If no enemies, force pre-charging state and return false
    if not hasEnemies then
        if dragonData.isBreathing or dragonData.chargeTimer > 0 then
            ConchBlessing.dragon.resetAllStates(player, dragonData)
            ConchBlessing.printDebug("Dragon: No enemies - forced reset to pre-charging state")
        end
        return false  -- Exit immediately, no further processing
    end
    
    -- Check per-room limit before processing
    if ConchBlessing.dragon.data.perroom > 0 then
        local breathsUsed = dragonData.breathsUsed or 0
        if breathsUsed >= ConchBlessing.dragon.data.perroom then
            if dragonData.chargeTimer % ConchBlessing.dragon.data.debugInterval == 0 then
                ConchBlessing.printDebug("Dragon: Per-room limit reached (" .. breathsUsed .. "/" .. ConchBlessing.dragon.data.perroom .. ") - cannot charge")
            end
            return true
        end
    end
    
    -- Handle charging phase
    if not dragonData.isBreathing then
        ConchBlessing.dragon.handleCharging(player, dragonData)
        
        -- Start breathing when charge is complete
        if dragonData.chargeTimer >= ConchBlessing.dragon.data.chargeTime then
            ConchBlessing.printDebug("Dragon: CHARGE COMPLETE - Ready to start breathing")
            ConchBlessing.dragon.startBreathing(player, dragonData)
        end
    else
        -- Handle breathing phase
        ConchBlessing.dragon.handleBreathing(player, dragonData)
    end
    
    return true
end

-- Fire tear helper function
function ConchBlessing.dragon.fireTear(player, position, direction, isStationary)
    local tear = player:FireTear(position, direction, false, false, false, nil, 2.0)
    if tear then
        tear:ChangeVariant(TearVariant.FIRE)
        tear:SetColor(Color(1, 0.5, 0, 1, 0, 0, 0), -1, 1, false, false)
        tear.Scale = tear.Scale * 1.2
        
        if isStationary then
            tear.Velocity = Vector(0, 0)  -- Stationary
        else
            tear.Velocity = tear.Velocity * ConchBlessing.dragon.data.shotspeed
        end
        
        tear.TearFlags = tear.TearFlags | TearFlags.TEAR_SPECTRAL
        return tear
    end
    return nil
end

-- Fire 3 fireballs helper function
function ConchBlessing.dragon.fireTripleFireballs(player, aimDirection, isStationary)
    if aimDirection.X == 0 and aimDirection.Y == 0 then
        -- Stationary fireballs
        ConchBlessing.dragon.fireTear(player, player.Position, Vector(0, 0), true)  -- Center
        ConchBlessing.dragon.fireTear(player, player.Position, Vector(0, 0), true)  -- Left
        ConchBlessing.dragon.fireTear(player, player.Position, Vector(0, 0), true)  -- Right
    else
        -- Moving fireballs with 3-degree spread
        ConchBlessing.dragon.fireTear(player, player.Position, aimDirection, false)  -- Center
        
        -- Calculate left and right directions (3 degrees)
        local angle = ConchBlessing.dragon.calculateAngle(aimDirection)
        local leftDirection = ConchBlessing.dragon.calculateDirection(angle - math.rad(3))
        local rightDirection = ConchBlessing.dragon.calculateDirection(angle + math.rad(3))
        
        ConchBlessing.dragon.fireTear(player, player.Position, leftDirection, false)   -- Left
        ConchBlessing.dragon.fireTear(player, player.Position, rightDirection, false)  -- Right
    end
end

-- Calculate angle from direction vector
function ConchBlessing.dragon.calculateAngle(direction)
    if direction.X == 0 then
        if direction.Y > 0 then
            return math.pi / 2  -- Down
        else
            return -math.pi / 2  -- Up
        end
    else
        local angle = math.atan(direction.Y / direction.X)
        if direction.X < 0 then
            angle = angle + math.pi
        end
        return angle
    end
end

-- Calculate direction vector from angle
function ConchBlessing.dragon.calculateDirection(angle)
    return Vector(math.cos(angle), math.sin(angle))
end

-- Dragon Item Cache Evaluation Callback
function ConchBlessing.dragon.onEvaluateCache(_, player, cacheFlag)
    if not player or type(player) ~= "userdata" or not player.HasCollectible then
        player = Isaac.GetPlayer(0)
        if not player then return end
    end
    
    if not DRAGON_ID or not player:HasCollectible(DRAGON_ID) then return end
    
    if cacheFlag == CacheFlag.CACHE_FLYING then
        player.CanFly = true
        ConchBlessing.printDebug("Dragon: CanFly applied")
    end
    
    if cacheFlag == CacheFlag.CACHE_TEARFLAG then
        player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
        ConchBlessing.printDebug("Dragon: TearFlags.SPECTRAL applied")
    end
end

-- Main update function
function ConchBlessing.dragon.onUpdate()
    -- Call template system first
    ConchBlessing.template.onUpdate(ConchBlessing.dragon.data)
    
    local player = Isaac.GetPlayer(0)
    if not player or type(player) ~= "userdata" or not player.HasCollectible then return end
    
    if not DRAGON_ID or not player:HasCollectible(DRAGON_ID) then return end
    
    -- Get Dragon Data from SaveManager
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if not dragonData then
        -- Create initial data
        dragonData = {
            chargeTimer = 0,
            breathTimer = 0,
            isBreathing = false,
            hasAppliedEffects = false
        }
        ConchBlessing.SaveManager.GetRunSave(player).dragon = dragonData
        ConchBlessing.printDebug("Dragon: Initial data created")
    end
    
    -- Apply effects immediately when item is picked up (once only)
    if not dragonData.hasAppliedEffects then
        ConchBlessing.printDebug("Dragon: Item obtained! Effects applied immediately")
        
        -- Force MC_EVALUATE_CACHE
        ConchBlessing.dragon.onEvaluateCache(nil, player, CacheFlag.CACHE_FLYING)
        ConchBlessing.dragon.onEvaluateCache(nil, player, CacheFlag.CACHE_TEARFLAG)
        
        dragonData.hasAppliedEffects = true
        ConchBlessing.printDebug("Dragon: Effects applied immediately!")
    end
    
    -- Main dragon state management
    local stateResult = ConchBlessing.dragon.manageDragonState(player, dragonData)
    
    -- Additional safety check: if no enemies, ensure we're in pre-charging state
    if not ConchBlessing.dragon.hasEnemies() then
        if dragonData.isBreathing or dragonData.chargeTimer > 0 then
            ConchBlessing.printDebug("Dragon: onUpdate safety check - forcing pre-charging state")
            ConchBlessing.dragon.resetAllStates(player, dragonData)
        end
    end
end

-- Block normal tear firing during breathing
function ConchBlessing.dragon.onFireTear(_, player, tear)
    if not player or not tear then return end
    
    if not player:HasCollectible(DRAGON_ID) then return end
    
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if not dragonData then return end
    
    -- ONLY apply blindfold during breathing phase
    if dragonData.isBreathing then
        -- Set shooting flag to false
        player:GetData().DragonCantShoot = true
        player:GetData().DragonCanShoot = false
        
        -- Set normal challenge to update shooting ability
        local currchall = Game().Challenge
        Game().Challenge = 6
        player:UpdateCanShoot()
        Game().Challenge = currchall
        
        ConchBlessing.printDebug("Dragon: Breathing - normal tear shooting blocked (blindfold)")
        return
    else
        -- Ensure blindfold is NOT applied when not breathing
        player:GetData().DragonCantShoot = false
        player:GetData().DragonCanShoot = true
        
        -- Restore normal challenge
        local currchall = Game().Challenge
        Game().Challenge = 0
        player:UpdateCanShoot()
        Game().Challenge = currchall
        
        ConchBlessing.printDebug("Dragon: Not breathing - blindfold removed, shooting restored")
    end
end

-- Callbacks are managed by conch_blessing_items.lua

-- Optional custom upgrade handlers (called by upgrade system)
ConchBlessing.dragon.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.dragon.data)
end

ConchBlessing.dragon.onAfterChange = function(upgradePos, pickup, itemData)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.dragon.data)
end

-- onGameStarted function for data initialization
ConchBlessing.dragon.onGameStarted = function(_)
    ConchBlessing.printDebug("Dragon: Game started - data will be initialized when item is picked up")
end

-- Reset all Dragon states when room is cleared
function ConchBlessing.dragon.onRoomClear()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(DRAGON_ID) then return end
    
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if dragonData then
        ConchBlessing.printDebug("Dragon: Room cleared - resetting all states and breaths counter")
        ConchBlessing.dragon.resetAllStates(player, dragonData)
        
        -- Clear original color after room clear reset
        dragonData.originalColor = nil
        ConchBlessing.printDebug("Dragon: Room clear - original color cleared")
    end
end
