ConchBlessing.icebreath = {}

local ICE_CANDLE_ID = Isaac.GetItemIdByName("Ice Breath")
local FIRE_CANDLE_ID = Isaac.GetItemIdByName("Fire Breath")

ConchBlessing.icebreath.data = {
    baseDamageCoef = 0.02,
    baseFreezeChance = 0.0,
    freezeDuration = 60,
    ticksPerSecond = 30,
    flameScale = 1.0,
    spawnScale = 1.0,
    growFrames = 1,
    noKnockback = true,
    rangeLifeScale = 1.0,
    nonMonsterKnockback = 6.0
}

local function setBlindfold(player, enabled)
    if not player then return end
    local pdata = player:GetData()
    if enabled then
        if pdata.__ConchBreathBlindfold then return end
        pdata.__ConchBreathBlindfold = true
        local currchall = Game().Challenge
        Game().Challenge = 6
        player:UpdateCanShoot()
        Game().Challenge = currchall
    else
        if not pdata.__ConchBreathBlindfold then return end
        pdata.__ConchBreathBlindfold = false
        local currchall = Game().Challenge
        Game().Challenge = 0
        player:UpdateCanShoot()
        Game().Challenge = currchall
    end
end

local function getChanceFromLuck(luck, stackCount, mult)
    local l = math.max(0.0, luck or 0.0)
    local m = mult or 1.0
    local p = (l * 0.01) * stackCount * m
    if p > 1.0 then p = 1.0 end
    if p < 0 then p = 0 end
    return p
end

local function directionFromMove(dir)
    if dir == Direction.LEFT then return Vector(-1, 0) end
    if dir == Direction.RIGHT then return Vector(1, 0) end
    if dir == Direction.UP then return Vector(0, -1) end
    if dir == Direction.DOWN then return Vector(0, 1) end
    return nil
end

local function getShotsPerSecond(player)
    local maxDelay = player.MaxFireDelay or 0
    return math.max(1.0, 30.0 / (maxDelay + 1.0))
end

local function buildBreathFlags(noKnockback)
    local flags = TearFlags.TEAR_SPECTRAL | TearFlags.TEAR_PIERCING
    if noKnockback and TearFlags.TEAR_NO_KNOCKBACK then
        flags = flags | TearFlags.TEAR_NO_KNOCKBACK
    end
    return flags
end

local function applyBreathTear(tear, baseDamage, color, scale, noKnockback)
    tear:ChangeVariant(TearVariant.FIRE)
    tear:SetColor(color, -1, 1, false, false)
    tear.Scale = scale
    tear.TearFlags = buildBreathFlags(noKnockback)
    if EntityCollisionClass and EntityCollisionClass.ENTCOLL_NONE then
        tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    end
    tear.GridCollisionClass = GridCollisionClass.COLLISION_NONE
    tear.CollisionDamage = baseDamage
    if noKnockback then
        if tear.SetKnockbackMultiplier then
            tear:SetKnockbackMultiplier(0)
        else
            tear.KnockbackMultiplier = 0
        end
    end
end

local function getBreathDirection(player, key)
    local pdata = player:GetData()
    local dir = player:GetAimDirection()
    if dir.X ~= 0 or dir.Y ~= 0 then
        dir = dir:Normalized()
        pdata[key] = dir
        return dir
    end
    if player.GetFireDirection then
        local fireDir = player:GetFireDirection()
        if fireDir and fireDir ~= Direction.NO_DIRECTION then
            local fd = directionFromMove(fireDir)
            if fd then
                pdata[key] = fd
                return fd
            end
        end
    end
    return nil
end

local function spawnIceBreath(player, direction, stackCount)
    local sps = getShotsPerSecond(player)
    local damageCoef = (sps * ConchBlessing.icebreath.data.baseDamageCoef) * stackCount
    local baseDamage = (player.Damage or 0) * damageCoef
    local basePos = player.Position + (direction * 5)
    local shotSpeed = (player.ShotSpeed or 1.0) * 2
    local speed = math.max(1.0, 8.0 * shotSpeed)
    local wType = 1
    if player.GetWeaponType then wType = player:GetWeaponType() end

    local function spawnSingle(pos, vel)
        if vel:Length() < 0.01 then
            vel = direction * speed
        else
            vel = vel:Normalized():Resized(speed)
        end
        local tear = player:FireTear(pos, vel, false, false, false, player, damageCoef)
        if not tear then return end
        tear.SpriteScale = Vector(ConchBlessing.icebreath.data.spawnScale, ConchBlessing.icebreath.data.spawnScale)
        tear.Velocity = vel
        local color = Color(0.3, 0.6, 1.0, 1.0, 0, 0, 0)
        applyBreathTear(
            tear,
            baseDamage,
            color,
            ConchBlessing.icebreath.data.spawnScale,
            ConchBlessing.icebreath.data.noKnockback
        )
        local rangeScale = ConchBlessing.icebreath.data.rangeLifeScale or 0.6
        local maxDistance = math.max(40, (player.TearRange or 0) * rangeScale)
        local speedLen = math.max(0.1, tear.Velocity:Length())
        local lifeFrames = math.max(4, math.floor(maxDistance / speedLen))
        if tear.SetTimeout then
            tear:SetTimeout(lifeFrames)
        end
        local tdata = tear:GetData()
        tdata.__ConchIceBreath = {
            chance = getChanceFromLuck(player.Luck, stackCount, 1.0),
            duration = ConchBlessing.icebreath.data.freezeDuration,
            source = player,
            baseDamage = baseDamage,
            noKnockback = ConchBlessing.icebreath.data.noKnockback,
            startPos = Vector(tear.Position.X, tear.Position.Y),
            maxDistance = maxDistance,
            lifeFrames = lifeFrames
        }
    end

    if player.GetMultiShotParams and player.GetMultiShotPositionVelocity then
        local multiParams = player:GetMultiShotParams(wType)
        local numTears = multiParams:GetNumTears()
        if numTears < 1 then numTears = 1 end
        for i = 0, numTears - 1 do
            local posVel = player:GetMultiShotPositionVelocity(i, wType, direction, shotSpeed, multiParams)
            local pos = basePos + posVel.Position
            local vel = posVel.Velocity
            spawnSingle(pos, vel)
        end
    else
        local velocity = direction * speed
        spawnSingle(basePos, velocity)
    end
end

ConchBlessing.icebreath.onPlayerUpdate = function(_, player)
    if not player then return end
    local hasIce = player:HasCollectible(ICE_CANDLE_ID)
    local hasFire = player:HasCollectible(FIRE_CANDLE_ID)
    if not hasIce and not hasFire then
        setBlindfold(player, false)
        return
    end
    setBlindfold(player, true)
    if not hasIce then return end
    local direction = getBreathDirection(player, "__ConchIceBreathLastDir")
    if not direction then return end
    ConchBlessing.icebreath._lastFireFrame = ConchBlessing.icebreath._lastFireFrame or {}
    local playerID = player:GetPlayerType()
    local frame = Game():GetFrameCount()
    if ConchBlessing.icebreath._lastFireFrame[playerID] == frame then return end
    local tps = ConchBlessing.icebreath.data.ticksPerSecond or 30
    local interval = math.max(1, math.floor(30 / tps))
    if frame % interval ~= 0 then return end
    ConchBlessing.icebreath._lastFireFrame[playerID] = frame
    local stackCount = player:GetCollectibleNum(ICE_CANDLE_ID)
    if stackCount < 1 then return end
    spawnIceBreath(player, direction, stackCount)
end

local function processIceBreathHit(tear, npc, breathData)
    if not tear or not npc or not breathData then return end
    local source = breathData.source or tear.SpawnerEntity or tear
    local damage = breathData.baseDamage or tear.CollisionDamage or 0
    if damage > 0 then
        npc:TakeDamage(damage, 0, EntityRef(source), 0)
    end
    if breathData.__ConchIceBreathApplied then return end
    breathData.__ConchIceBreathApplied = true
    local chance = breathData.chance or 0
    if chance <= 0 then return end
    if math.random() <= chance then
        local freezeSource = breathData.source or tear.SpawnerEntity or npc
        local duration = breathData.duration or 60
        npc:AddFreeze(EntityRef(freezeSource), duration)
        if EntityFlag and EntityFlag.FLAG_ICE then
            npc:AddEntityFlags(EntityFlag.FLAG_ICE)
        end
        npc:SetColor(Color(0.5, 0.8, 1.0, 1.0, 0, 0, 0), duration, 1, false, true)
    end
end

local function processIceBreathHitEntity(tear, ent, breathData)
    if not tear or not ent or not breathData then return end
    local source = breathData.source or tear.SpawnerEntity or tear
    local damage = breathData.baseDamage or tear.CollisionDamage or 0
    if damage > 0 then
        ent:TakeDamage(damage, 0, EntityRef(source), 0)
    end
end

local function isNonMonsterPushTarget(ent)
    return ent and ent.Type == EntityType.ENTITY_BOMB
end

local function pushNonMonster(tear, ent, breathData)
    if not tear or not ent then return end
    if not ent.Velocity then return end
    local strength = (breathData and breathData.nonMonsterKnockback) or ConchBlessing.icebreath.data.nonMonsterKnockback or 6.0
    local dir = ent.Position - tear.Position
    if dir.X == 0 and dir.Y == 0 then return end
    local push = dir:Normalized() * strength
    ent.Velocity = ent.Velocity + push
end

ConchBlessing.icebreath.onTearCollision = function(_, tear, collider, _)
    if not tear then return end
    local data = tear:GetData()
    if not data or not data.__ConchIceBreath then return end
    return false
end

ConchBlessing.icebreath.onTearUpdate = function(_, tear)
    if not tear then return end
    local data = tear:GetData()
    if not data or not data.__ConchIceBreath then return end
    if data.__ConchIceBreath.lifeFrames and tear.FrameCount >= data.__ConchIceBreath.lifeFrames then
        tear:Remove()
        return
    end
    if data.__ConchIceBreath.startPos and data.__ConchIceBreath.maxDistance then
        if tear.Position:Distance(data.__ConchIceBreath.startPos) >= data.__ConchIceBreath.maxDistance then
            tear:Remove()
            return
        end
    end
    local color = Color(0.3, 0.6, 1.0, 1.0, 0, 0, 0)
    local targetScale = ConchBlessing.icebreath.data.flameScale
    local startScale = ConchBlessing.icebreath.data.spawnScale
    local growFrames = ConchBlessing.icebreath.data.growFrames or 1
    local t = math.min(1, math.max(0, tear.FrameCount / growFrames))
    local currentScale = startScale + (targetScale - startScale) * t
    local targetVec = Vector(currentScale, currentScale)
    if tear.SpriteScale.X ~= targetVec.X or tear.SpriteScale.Y ~= targetVec.Y then
        tear.SpriteScale = targetVec
    end
    local baseDamage = data.__ConchIceBreath.baseDamage or tear.CollisionDamage
    applyBreathTear(tear, baseDamage, color, currentScale, data.__ConchIceBreath.noKnockback)
    data.__ConchIceBreathHits = data.__ConchIceBreathHits or {}
    local room = Game():GetRoom()
    local grid = room and room:GetGridEntityFromPos(tear.Position) or nil
    if grid then
        local gtype = (grid.GetType and grid:GetType()) or nil
        local isFireGrid = GridEntityType and gtype == GridEntityType.GRID_FIREPLACE
        local isTntGrid = GridEntityType and gtype == GridEntityType.GRID_TNT
        if isFireGrid or isTntGrid then
            grid:Destroy()
        end
    end
    local roomEntities = Isaac.GetRoomEntities()
    local hitRadiusPadding = 4
    for i = 1, #roomEntities do
        local ent = roomEntities[i]
        local npc = ent and ent:ToNPC() or nil
        if npc and npc:IsVulnerableEnemy() and not npc:IsDead() then
            local hitId = npc.InitSeed or npc.Index
            if not data.__ConchIceBreathHits[hitId] then
                local dist = tear.Position:Distance(npc.Position)
                local hitRadius = (tear.Size or 0) + (npc.Size or 0) + hitRadiusPadding
                if dist <= hitRadius then
                    data.__ConchIceBreathHits[hitId] = true
                    processIceBreathHit(tear, npc, data.__ConchIceBreath)
                end
            end
        elseif isNonMonsterPushTarget(ent) then
            local hitId = ent.InitSeed or ent.Index
            if not data.__ConchIceBreathHits[hitId] then
                local dist = tear.Position:Distance(ent.Position)
                local hitRadius = (tear.Size or 0) + (ent.Size or 0) + hitRadiusPadding
                if dist <= hitRadius then
                    data.__ConchIceBreathHits[hitId] = true
                    pushNonMonster(tear, ent, data.__ConchIceBreath)
                    if ent.Type == EntityType.ENTITY_FIREPLACE or ent.Type == EntityType.ENTITY_BOMB then
                        processIceBreathHitEntity(tear, ent, data.__ConchIceBreath)
                    end
                end
            end
        end
    end
    if tear.FrameCount <= 1 then
        local spr = tear:GetSprite()
        if spr then
            local anim = spr:GetAnimation()
            if anim and anim ~= "" and spr:IsPlaying(anim) then
                pcall(function() spr:SetFrame(anim, 1) end)
            else
                pcall(function() spr:SetFrame("Move", 1) end)
            end
        end
    end
end
