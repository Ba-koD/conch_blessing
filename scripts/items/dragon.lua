local ConchBlessing = ConchBlessing
local DRAGON_ID = Isaac.GetItemIdByName("Dragon")

-- Dragon Item Data
ConchBlessing.dragon = {
    data = {
        chargeTime = 5,        -- Breath Cooldown (seconds)
        breathDuration = 5,    -- Breath Duration (seconds)
        breathFireRate = 0.1,  -- Breath Fire Rate (seconds)
        shotspeed = 15.0,       -- Fireball Speed Multiplier (faster!)
    }
}

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
        ConchBlessing.printDebug("Dragon: Firing stationary fireballs at player position")
        
        ConchBlessing.dragon.fireTear(player, player.Position, Vector(0, 0), true)  -- Center
        ConchBlessing.dragon.fireTear(player, player.Position, Vector(0, 0), true)  -- Left
        ConchBlessing.dragon.fireTear(player, player.Position, Vector(0, 0), true)  -- Right
        
        ConchBlessing.printDebug("Dragon: 3 stationary fireballs created!")
    else
        -- Moving fireballs with 3-degree spread
        ConchBlessing.dragon.fireTear(player, player.Position, aimDirection, false)  -- Center
        
        -- Calculate left and right directions (3 degrees)
        local angle = ConchBlessing.dragon.calculateAngle(aimDirection)
        local leftDirection = ConchBlessing.dragon.calculateDirection(angle - math.rad(3))
        local rightDirection = ConchBlessing.dragon.calculateDirection(angle + math.rad(3))
        
        ConchBlessing.dragon.fireTear(player, player.Position, leftDirection, false)   -- Left
        ConchBlessing.dragon.fireTear(player, player.Position, rightDirection, false)  -- Right
        
        ConchBlessing.printDebug("Dragon: 3 moving fireballs fired!")
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
    -- If player parameter is invalid, use Isaac.GetPlayer() instead
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
            hasAppliedEffects = false,  -- Check if effects have been applied
            lastFireDirection = Vector(0, 1)  -- Store last fire direction (default: down)
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
    
    -- Update breath timer
    if not dragonData.isBreathing then
        -- Increase charge timer (only when enemies are present)
        local hasEnemies = false
        
        -- First check with Isaac.CountEnemies() (simplest and most reliable)
        local enemyCount = Isaac.CountEnemies()
        if enemyCount > 0 then
            hasEnemies = true
        else
            -- Check with Isaac.GetRoomEntities() (recommended by IsaacDocs)
            local entities = Isaac.GetRoomEntities()
            if entities then
                for i, entity in ipairs(entities) do
                    if entity and 
                       type(entity) == "userdata" and 
                       entity.IsEnemy and 
                       entity.IsActive and
                       entity:IsEnemy() and 
                       entity:IsActive() then
                        hasEnemies = true
                        break
                    end
                end
            end
        end
        
        -- Increase charge timer only when enemies are present
        if hasEnemies then
            dragonData.chargeTimer = dragonData.chargeTimer + 1/30  -- 30 FPS
            ConchBlessing.printDebug("Dragon: Charging... " .. string.format("%.1f", dragonData.chargeTimer) .. "/" .. ConchBlessing.dragon.data.chargeTime .. " seconds")
        else
            -- Reset charge timer if no enemies are present
            if dragonData.chargeTimer > 0 then
                dragonData.chargeTimer = 0
                ConchBlessing.printDebug("Dragon: No enemies - charge timer reset")
                
                -- Smoothly restore original color when charging is cancelled
                player:SetColor(Color(1, 1, 1, 1, 0, 0, 0), 2, 1, false, false)
                ConchBlessing.printDebug("Dragon: Charging cancelled - smoothly restore original color")
            end
        end
        
        -- Start breathing condition: cooldown complete + enemies present
        if dragonData.chargeTimer >= ConchBlessing.dragon.data.chargeTime then
            if hasEnemies then
                dragonData.isBreathing = true
                dragonData.breathTimer = 0
                dragonData.chargeTimer = 0
                
                player:GetData().DragonCantShoot = true
                player:GetData().DragonCanShoot = false
                
                local currchall = Game().Challenge
                Game().Challenge = 6
                player:UpdateCanShoot()
                Game().Challenge = currchall
                
                ConchBlessing.printDebug("Dragon: Player shooting disabled")
                
                player.TearFlags = TearFlags.TEAR_NORMAL
                ConchBlessing.printDebug("Dragon: Player TearFlags set to minimum value to prevent shooting")
                
                -- Fire 3 fireballs using helper function
                local aimDirection = player:GetAimDirection()
                ConchBlessing.dragon.fireTripleFireballs(player, aimDirection, aimDirection.X == 0 and aimDirection.Y == 0)
            else
                ConchBlessing.printDebug("Dragon: No enemies - cannot start breathing")
            end
        end
        
        -- Gradual color change (red) - use SetColor
        -- Only change color when enemies are present
        if dragonData.chargeTimer > 0 then
            local hasEnemies = false
            
            -- First check with Isaac.CountEnemies() (simplest and most reliable)
            local enemyCount = Isaac.CountEnemies()
            if enemyCount > 0 then
                hasEnemies = true
            else
                -- Check with Isaac.GetRoomEntities() (recommended by IsaacDocs)
                local entities = Isaac.GetRoomEntities()
                if entities then
                    for i, entity in ipairs(entities) do
                        if entity and 
                           type(entity) == "userdata" and 
                           entity.IsEnemy and 
                           entity.IsActive and
                           entity:IsEnemy() and 
                           entity:IsActive() then
                            hasEnemies = true
                            break
                        end
                    end
                end
            end
            
            -- Only change color when enemies are present
            if hasEnemies then
                local progress = dragonData.chargeTimer / ConchBlessing.dragon.data.chargeTime
                -- Gradually change to red (R increases, G/B decreases)
                local r = 0.5 + 0.5 * progress  -- 0.5 -> 1.0
                local g = 0.5 * (1.0 - progress)  -- 0.5 -> 0.0
                local b = 0.5 * (1.0 - progress)  -- 0.5 -> 0.0
                
                -- Apply color with much longer duration to prevent flickering
                -- Only update color every 30 frames (1 time per second) for smooth transition
                if math.floor(dragonData.chargeTimer * 30) % 30 == 0 then
                    player:SetColor(Color(r, g, b, 1.0, 0, 0, 0), 5, 1, false, false)
                end
                
                -- Debug: Check color change (every 1 second)
                if math.floor(dragonData.chargeTimer * 30) % 30 == 0 then
                    ConchBlessing.printDebug("Dragon: Charging - R:" .. string.format("%.2f", r) .. 
                        " G:" .. string.format("%.2f", g) .. 
                        " B:" .. string.format("%.2f", b) .. 
                        " (Progress:" .. string.format("%.1f", progress * 100) .. "%)")
                end
            else
                -- Restore original color when no enemies are present
                player:SetColor(Color(1, 1, 1, 1, 0, 0, 0), 5, 1, false, false)
                ConchBlessing.printDebug("Dragon: No enemies - restore original color")
            end
        end
    else
        -- Breathing
        dragonData.breathTimer = dragonData.breathTimer + 1/30
        
        -- Gradual color restoration during breathing (like charging but reverse)
        -- Only change color every 30 frames (1 time per second) for smooth transition
        local progress = dragonData.breathTimer / ConchBlessing.dragon.data.breathDuration
        if progress < 1.0 then
            -- Gradually restore color: Red -> Orange -> Original (reverse of charging)
            local r = 1.0 - 0.5 * progress  -- 1.0 -> 0.5 (Red -> Orange)
            local g = 0.5 * progress         -- 0.0 -> 0.5 (Black -> Orange)
            local b = 0.5 * progress         -- 0.0 -> 0.5 (Black -> Orange)
            
            -- Apply color with much longer duration to prevent flickering
            -- Only update color every 30 frames (1 time per second) for smooth transition
            if math.floor(dragonData.breathTimer * 30) % 30 == 0 then
                player:SetColor(Color(r, g, b, 1.0, 0, 0, 0), 5, 1, false, false)
            end
            
            -- Debug: Check color restoration (every 1 second)
            if math.floor(dragonData.breathTimer * 30) % 30 == 0 then
                ConchBlessing.printDebug("Dragon: Breathing - R:" .. string.format("%.2f", r) .. 
                    " G:" .. string.format("%.2f", g) .. 
                    " B:" .. string.format("%.2f", b) .. 
                    " (Restoration:" .. string.format("%.1f", progress * 100) .. "%)")
            end
        else
            -- Restore original color when breathing is complete
            player:SetColor(Color(1, 1, 1, 1, 0, 0, 0), 5, 1, false, false)
            ConchBlessing.printDebug("Dragon: Breathing complete - restore original color")
        end
        
        -- Fire fireballs during breathing (based on IsaacDocs)
        if dragonData.isBreathing then
            -- Fire once per onUpdate (30 FPS = 30 times per second)
            local aimDirection = player:GetAimDirection()
            
            -- Fire 3 fireballs using helper function
            ConchBlessing.dragon.fireTripleFireballs(player, aimDirection, aimDirection.X == 0 and aimDirection.Y == 0)
        end
        
        -- Check if breathing is complete
        if dragonData.breathTimer >= ConchBlessing.dragon.data.breathDuration then
            dragonData.isBreathing = false
            dragonData.chargeTimer = 0
            
            -- Restore shooting flag
            player:GetData().DragonCantShoot = false
            player:GetData().DragonCanShoot = true
            
            -- Set normal challenge to update shooting ability
            local currchall = Game().Challenge
            Game().Challenge = 0
            player:UpdateCanShoot()
            Game().Challenge = currchall
            
            ConchBlessing.printDebug("Dragon: Shooting flag restored")
            
            -- Restore tearFlags (piercing terrain)
            player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
            ConchBlessing.printDebug("Dragon: Player TearFlags restored (piercing terrain)")
            
            -- Restore shooting flag
            player:GetData().DragonCantShoot = false
            player:GetData().DragonCanShoot = true
            ConchBlessing.printDebug("Dragon: Shooting flag restored")
            
            ConchBlessing.printDebug("Dragon: Breathing complete! Switch back to charging mode")
        end
    end
end

function ConchBlessing.dragon.onFireTear(_, player, tear)
    if not player or not tear then
        return
    end
    
    -- Check if Dragon item is equipped
    if not player:HasCollectible(DRAGON_ID) then
        return
    end
    
    -- Get Dragon data
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if not dragonData then
        return
    end
    
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
    end
end

-- Register MC_EVALUATE_CACHE callback directly (LATE priority)
ConchBlessing.originalMod:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, CallbackPriority.LATE, ConchBlessing.dragon.onEvaluateCache)

-- optional custom upgrade handlers (called by upgrade system)
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

-- Template system is now called directly in onUpdate function
