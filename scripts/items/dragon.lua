local ConchBlessing = ConchBlessing
local DRAGON_ID = Isaac.GetItemIdByName("Dragon")

-- Dragon Item Data
ConchBlessing.dragon = {
    data = {
        -- Tech Laser System
        laserDelay = 150,      -- Room entry delay before laser activation (ticks, 150 = 5 seconds)
        laserDuration = 150,   -- Laser duration (ticks, 150 = 5 seconds)
        laserCount = 5,        -- Number of laser strikes
        laserRange = 160,      -- Detection range in pixels ( 5 blocks)
        laserPerRoom = 5,      -- Lasers per room (0 = unlimited, >0 = limited)
        indicatorMaxBling = 25,
        laserDamagePercent = 5,
        fireIntervalFrames = 2, -- Strike interval during firing (in frames)
        showRangeIndicator = true,
        rangeRingOffsetY = 32,
    }
}

function ConchBlessing.dragon.hasEnemies(player, range)
    local entities = Isaac.GetRoomEntities()
    local enemyCount = 0
    local enemyList = {}
    
    if entities then
        for i, entity in ipairs(entities) do
            if entity and entity:IsActiveEnemy(false) and not entity:IsDead() then
                if not entity:IsInvincible() and entity:IsVulnerableEnemy() then
                    local within = true
                    if player and range then
                        within = (player.Position:Distance(entity.Position) <= range)
                    end
                    if within then
                        enemyCount = enemyCount + 1
                        table.insert(enemyList, {
                            type = entity.Type,
                            variant = entity.Variant,
                            position = entity.Position
                        })
                    end
                end
            end
        end
    end
    
    if enemyCount > 0 then
        ConchBlessing.printDebug("Dragon: Found " .. enemyCount .. " enemies in room:")
        for i, enemy in ipairs(enemyList) do
            ConchBlessing.printDebug("  Enemy " .. i .. ": Type=" .. enemy.type .. ", Variant=" .. enemy.variant .. ", Pos=(" .. math.floor(enemy.position.X) .. "," .. math.floor(enemy.position.Y) .. ")")
        end
    end
    return enemyCount > 0
end

function ConchBlessing.dragon.createTechLaser(player, targetPosition)
    local percent = ConchBlessing.dragon.data.laserDamagePercent
    -- For Tech lasers, the last parameter is a damage MULTIPLIER to player damage.
    local damageMultiplier = percent / 100
    local expectedDamage = player.Damage * damageMultiplier

    local skyPosition = Vector(targetPosition.X, targetPosition.Y - 200)
    local direction = Vector(0, 1)
    local laser = player:FireTechLaser(skyPosition, LaserOffset.LASER_TECH1_OFFSET, direction, false, false, player, damageMultiplier)

    if laser then
        laser:SetMaxDistance(200)
        laser:SetTimeout(10)
        laser:SetColor(Color(1, 1, 0, 1, 0, 0, 0), -1, 1, false, false)
        -- Add Hook Worm-like tear flag if available
        if TearFlags and laser.AddTearFlags then
            local hookFlag = TearFlags.TEAR_WORM or TearFlags.TEAR_HOOK or TearFlags.TEAR_WIGGLE
            if hookFlag then
                laser:AddTearFlags(hookFlag)
            end
        end
        laser:GetData().DragonTechLaser = true
        laser:GetData().Duration = 30
        ConchBlessing.printDebug("Dragon: Created Tech Laser from sky at pos (" .. math.floor(skyPosition.X) .. "," .. math.floor(skyPosition.Y) .. ") targeting (" .. math.floor(targetPosition.X) .. "," .. math.floor(targetPosition.Y) .. ") with mul " .. string.format("%.3f", damageMultiplier) .. " (expected ~" .. string.format("%.3f", expectedDamage) .. ")")
        return laser
    end

    ConchBlessing.printDebug("Dragon: Failed to create Tech Laser")
    return nil
end

function ConchBlessing.dragon.fireTechLasers(player)
    local playerPos = player.Position
    local nearbyEnemies = {}
    local entities = Isaac.GetRoomEntities()
    
    ConchBlessing.printDebug("Dragon: fireTechLasers called - Player pos: (" .. math.floor(playerPos.X) .. "," .. math.floor(playerPos.Y) .. ")")
    
    if entities then
        for _, entity in ipairs(entities) do
            if entity and entity:IsActiveEnemy(false) and not entity:IsDead() then
                if not entity:IsInvincible() and entity:IsVulnerableEnemy() then
                    local distance = playerPos:Distance(entity.Position)
                    if distance <= ConchBlessing.dragon.data.laserRange then
                        table.insert(nearbyEnemies, { ent = entity, dist = distance })
                    end
                end
            end
        end
    end
    
    -- sort by distance and hit up to laserCount nearest (simultaneous strikes)
    table.sort(nearbyEnemies, function(a,b) return a.dist < b.dist end)
    local lasersFired = 0
    local maxTargets = math.min(ConchBlessing.dragon.data.laserCount, #nearbyEnemies)
    for i = 1, maxTargets do
        local enemy = nearbyEnemies[i].ent
        ConchBlessing.dragon.createTechLaser(player, enemy.Position)
        lasersFired = lasersFired + 1
    end
    
    ConchBlessing.printDebug("Dragon: Fired " .. lasersFired .. " lasers total")
    return lasersFired
end

function ConchBlessing.dragon.updateTechLaser(laser)
    if not laser:GetData().DragonTechLaser then return end
    
    local data = laser:GetData()
    if data.Duration <= 0 then
        laser:Remove()
        return
    end
    data.Duration = data.Duration - 1
    -- enforce yellow tint every tick (use offsets to overpower red base)
    laser:SetColor(Color(1, 1, 0.3, 1, 0.35, 0.35, 0), -1, 1, false, false)
end

function ConchBlessing.dragon.handleLaserSystem(player, dragonData)
    if not dragonData.laserTimer then
        dragonData.laserTimer = 0
        dragonData.phase = "charging"
        ConchBlessing.printDebug("Dragon: Starting charging phase")
    end
    
    if not dragonData.phase then
        dragonData.phase = "charging"
        ConchBlessing.printDebug("Dragon: Phase was missing, initialized to charging")
    end
    
    if dragonData.phase == "charging" then
        -- only charge when there are any enemies in the room
        local hasEnemies = ConchBlessing.dragon.hasEnemies()
        if not hasEnemies then
            if dragonData.indicator and dragonData.indicator:Exists() then dragonData.indicator:Remove() end
            dragonData.indicator = nil
            dragonData.sparkTimer = 0
            dragonData.laserTimer = 0
            if dragonData.rangeRing and dragonData.rangeRing:Exists() then dragonData.rangeRing:Remove() end
            dragonData.rangeRing = nil
            return true
        end
        
        -- Range indicator (ring) + blings
        if ConchBlessing.dragon.data.showRangeIndicator then
            if not dragonData.rangeRing or not dragonData.rangeRing:Exists() then
                local ringVar = (EffectVariant and (EffectVariant.HALO or EffectVariant.GROUND_GLOW or EffectVariant.BRIMSTONE_SWIRL)) or 0
                dragonData.rangeRing = Isaac.Spawn(EntityType.ENTITY_EFFECT, ringVar, 0, player.Position, Vector(0,0), player):ToEffect()
                if dragonData.rangeRing then
                    dragonData.rangeRing.DepthOffset = -20
                    dragonData.rangeRing.PositionOffset = Vector(0, ConchBlessing.dragon.data.rangeRingOffsetY or 6)
                end
            end
            if dragonData.rangeRing and dragonData.rangeRing:Exists() then
                dragonData.rangeRing.Position = player.Position
                dragonData.rangeRing.PositionOffset = Vector(0, ConchBlessing.dragon.data.rangeRingOffsetY or 6)
                local scale = (ConchBlessing.dragon.data.laserRange / 32) * 0.6
                dragonData.rangeRing.SpriteScale = Vector(scale, scale)
                dragonData.rangeRing:SetColor(Color(1, 1, 0.3, 0.25, 0.2, 0.2, 0), -1, 1, false, false)
            end
        end
        if dragonData.blingList == nil then dragonData.blingList = {} end
        local blingVariant = (EffectVariant and (EffectVariant.ULTRA_GREED_BLING or EffectVariant.GROUND_GLOW)) or 0
        local progress = math.max(0, math.min(1, dragonData.laserTimer / ConchBlessing.dragon.data.laserDelay))
        local targetCount = math.floor(progress * ConchBlessing.dragon.data.indicatorMaxBling)
        while #dragonData.blingList < targetCount do
            local angle = math.random() * math.pi * 2
            local radius = 18 + math.random(0, 10)
            local offset = Vector(math.cos(angle), math.sin(angle)) * radius
            local e = Isaac.Spawn(EntityType.ENTITY_EFFECT, blingVariant, 0, player.Position + offset, Vector(0,0), player):ToEffect()
            if e then e.DepthOffset = 15 table.insert(dragonData.blingList, e) else break end
        end
        for i = #dragonData.blingList, 1, -1 do
            local eff = dragonData.blingList[i]
            if not eff or not eff:Exists() then table.remove(dragonData.blingList, i)
            else
                eff.Position = player.Position + (eff.Position - player.Position):Resized((eff.Position - player.Position):Length())
                eff:SetColor(Color(1, 1, 0.4, 0.4 + 0.4 * progress, 0.2, 0.2, 0), -1, 1, false, false)
            end
        end
        
        dragonData.laserTimer = dragonData.laserTimer + 1
        if dragonData.laserTimer >= ConchBlessing.dragon.data.laserDelay then
            -- check per-cycle limit before entering firing
            if ConchBlessing.dragon.data.laserPerRoom and ConchBlessing.dragon.data.laserPerRoom > 0 then
                if (dragonData.cyclesUsed or 0) >= ConchBlessing.dragon.data.laserPerRoom then
                    -- stay in charging without progressing cycles
                    dragonData.laserTimer = 0
                    return true
                end
            end
            dragonData.phase = "firing"
            dragonData.laserTimer = 0
            dragonData.firingTimer = 0
            ConchBlessing.printDebug("Dragon: Charging complete! Starting firing phase")
            -- start firing: gradually clear bling effects
            dragonData.blingFade = true
        else
            if dragonData.laserTimer % 30 == 0 then
                local remaining = ConchBlessing.dragon.data.laserDelay - dragonData.laserTimer
                ConchBlessing.printDebug("Dragon: Charging... " .. remaining .. " ticks remaining")
            end
        end
    elseif dragonData.phase == "firing" then
        dragonData.firingTimer = (dragonData.firingTimer or 0) + 1
        
        ConchBlessing.printDebug("Dragon: FIRING! Timer: " .. dragonData.firingTimer .. "/" .. ConchBlessing.dragon.data.laserDuration)

        -- keep range ring visible and following player during firing
        if ConchBlessing.dragon.data.showRangeIndicator then
            if not dragonData.rangeRing or not dragonData.rangeRing:Exists() then
                local ringVar = (EffectVariant and (EffectVariant.HALO or EffectVariant.GROUND_GLOW or EffectVariant.BRIMSTONE_SWIRL)) or 0
                dragonData.rangeRing = Isaac.Spawn(EntityType.ENTITY_EFFECT, ringVar, 0, player.Position, Vector(0,0), player):ToEffect()
                if dragonData.rangeRing then
                    dragonData.rangeRing.DepthOffset = -20
                    dragonData.rangeRing.PositionOffset = Vector(0, ConchBlessing.dragon.data.rangeRingOffsetY or 6)
                end
            end
            if dragonData.rangeRing and dragonData.rangeRing:Exists() then
                dragonData.rangeRing.Position = player.Position
                dragonData.rangeRing.PositionOffset = Vector(0, ConchBlessing.dragon.data.rangeRingOffsetY or 6)
                local scale = (ConchBlessing.dragon.data.laserRange / 32) * 0.6
                dragonData.rangeRing.SpriteScale = Vector(scale, scale)
                dragonData.rangeRing:SetColor(Color(1, 1, 0.3, 0.2, 0.2, 0.2, 0), -1, 1, false, false)
            end
        end


        -- fade out charging blings while firing
        if dragonData.blingList then
            for i = #dragonData.blingList, 1, -1 do
                local eff = dragonData.blingList[i]
                if eff and eff:Exists() then
                    eff:SetColor(Color(1, 1, 0.4, math.max(0, 0.6 - dragonData.firingTimer / ConchBlessing.dragon.data.laserDuration), 0.2, 0.2, 0), -1, 1, false, false)
                else
                    table.remove(dragonData.blingList, i)
                end
            end
        end

        if dragonData.firingTimer >= ConchBlessing.dragon.data.laserDuration then
            dragonData.phase = "charging"
            dragonData.laserTimer = 0
            dragonData.firingTimer = 0
            dragonData.cyclesUsed = (dragonData.cyclesUsed or 0) + 1
            ConchBlessing.printDebug("Dragon: Firing complete! Back to charging phase")
            if dragonData.blingList then
                for _, eff in ipairs(dragonData.blingList) do
                    if eff and eff:Exists() then eff:Remove() end
                end
                dragonData.blingList = nil
            end
            -- keep range ring for next charging; do not remove here
        else
            local interval = ConchBlessing.dragon.data.fireIntervalFrames or 2
            if interval < 1 then interval = 1 end
            if dragonData.firingTimer % interval == 0 then
                ConchBlessing.printDebug("Dragon: 2-frame fire tick")
                local lasersFired = ConchBlessing.dragon.fireTechLasers(player)
                if lasersFired > 0 then
                    ConchBlessing.printDebug("Dragon: Fired " .. lasersFired .. " lasers this tick")
                end
            end
        end
    end
    
    return true
end

function ConchBlessing.dragon.onEvaluateCache(_, player, cacheFlag)
    if not player or type(player) ~= "userdata" or not player.HasCollectible then
        player = Isaac.GetPlayer(0)
        if not player then return end
    end
    
    if not DRAGON_ID or not player:HasCollectible(DRAGON_ID) then return end
    
    if cacheFlag == CacheFlag.CACHE_FLYING then
        player.CanFly = true
    end
    
    if cacheFlag == CacheFlag.CACHE_TEARFLAG then
        player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
    end
end

function ConchBlessing.dragon.onUpdate()
    ConchBlessing.template.onUpdate(ConchBlessing.dragon.data)
    
    local player = Isaac.GetPlayer(0)
    if not player or type(player) ~= "userdata" or not player.HasCollectible then return end
    
    if not DRAGON_ID or not player:HasCollectible(DRAGON_ID) then return end
    
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if not dragonData then
        dragonData = {
            laserTimer = 0,
            lasersUsed = 0,
            cyclesUsed = 0,
            hasAppliedEffects = false,
            phase = "charging",
            firingTimer = 0
        }
        ConchBlessing.SaveManager.GetRunSave(player).dragon = dragonData
        ConchBlessing.printDebug("Dragon: Initialized dragon data with phase=charging")
    end
    
    if not dragonData.hasAppliedEffects then
        ConchBlessing.dragon.onEvaluateCache(nil, player, CacheFlag.CACHE_FLYING)
        ConchBlessing.dragon.onEvaluateCache(nil, player, CacheFlag.CACHE_TEARFLAG)
        dragonData.hasAppliedEffects = true
        ConchBlessing.printDebug("Dragon: Applied flight and spectral effects")
    end
    
    if Isaac.GetFrameCount() % 300 == 0 then
        local phase = dragonData.phase or "unknown"
        local timer = dragonData.laserTimer or 0
        local firingTimer = dragonData.firingTimer or 0
        ConchBlessing.printDebug("Dragon Status: Phase=" .. phase .. ", Timer=" .. timer .. ", FiringTimer=" .. firingTimer)
    end
    
    ConchBlessing.dragon.handleLaserSystem(player, dragonData)
end

function ConchBlessing.dragon.onLaserUpdate(_, laser)
    ConchBlessing.dragon.updateTechLaser(laser)
end

ConchBlessing.dragon.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.dragon.data)
end

ConchBlessing.dragon.onAfterChange = function(upgradePos, pickup, itemData)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.dragon.data)
end

ConchBlessing.dragon.onGameStarted = function(_)
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(DRAGON_ID) then return end
    
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if dragonData then
        dragonData.laserTimer = 0
        dragonData.firingTimer = 0
        dragonData.phase = "charging"
        dragonData.lasersUsed = 0
        ConchBlessing.printDebug("Dragon: Game started - reset to charging phase")
    end
end

function ConchBlessing.dragon.onRoomClear()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(DRAGON_ID) then return end
    
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if dragonData then
        dragonData.laserTimer = 0
        dragonData.firingTimer = 0
        dragonData.phase = "charging"
        dragonData.lasersUsed = 0
    end
end

function ConchBlessing.dragon.onRoomEnter()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(DRAGON_ID) then return end
    
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if dragonData then
        dragonData.laserTimer = 0
        dragonData.firingTimer = 0
        dragonData.phase = "charging"
        dragonData.lasersUsed = 0
        dragonData.cyclesUsed = 0
        ConchBlessing.printDebug("Dragon: Room entered - reset to charging phase")
    end
end

-- also reset when new room is created (covers some transitions)
function ConchBlessing.dragon.onNewRoom()
    local player = Isaac.GetPlayer(0)
    if not player or not player:HasCollectible(DRAGON_ID) then return end
    local dragonData = ConchBlessing.SaveManager.GetRunSave(player).dragon
    if dragonData then
        dragonData.laserTimer = 0
        dragonData.firingTimer = 0
        dragonData.phase = "charging"
        dragonData.lasersUsed = 0
        dragonData.cyclesUsed = 0
        ConchBlessing.printDebug("Dragon: New room - reset to charging phase")
    end
end