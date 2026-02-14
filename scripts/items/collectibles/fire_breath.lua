ConchBlessing.firebreath = {}

local FIRE_CANDLE_ID = Isaac.GetItemIdByName("Fire Breath")
local ICE_CANDLE_ID = Isaac.GetItemIdByName("Ice Breath")

ConchBlessing.firebreath.data = {
    baseDamageCoef = 0.30,
    baseBurnChance = 0.0,
    burnDuration = 90,
    ticksPerSecond = 30,
    flameScale = 1.0,
    spawnScale = 1.0,
    growFrames = 1
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
    local p = l * stackCount * m
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

local function spawnFireBreath(player, direction, stackCount)
    local damageCoef = ConchBlessing.firebreath.data.baseDamageCoef * stackCount
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
        tear.SpriteScale = Vector(ConchBlessing.firebreath.data.spawnScale, ConchBlessing.firebreath.data.spawnScale)
        tear:ChangeVariant(TearVariant.FIRE)
        local color = Color(1.0, 1.0, 1.0, 1.0, 0, 0, 0)
        color:SetColorize(1, 0.4, 0.1, 1)
        tear:SetColor(color, 0, 0, false, false)
        tear.Velocity = vel
        tear.Scale = ConchBlessing.firebreath.data.flameScale
        tear.TearFlags = tear.TearFlags | TearFlags.TEAR_SPECTRAL | TearFlags.TEAR_PIERCING
        if TearFlags and TearFlags.TEAR_NO_KNOCKBACK then
            tear.TearFlags = tear.TearFlags | TearFlags.TEAR_NO_KNOCKBACK
        end
        tear.CollisionDamage = baseDamage
        tear.KnockbackMultiplier = 0
        local range = (player.TearRange or 0) / 40.0
        local life = math.max(5, math.floor(range * 6))
        if tear.SetTimeout then
            tear:SetTimeout(life)
        end
        tear.Visible = false
        local fire = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.RED_CANDLE_FLAME, 0, tear.Position, vel, player):ToEffect()
        if fire then
            fire.SpriteScale = Vector(ConchBlessing.firebreath.data.flameScale, ConchBlessing.firebreath.data.flameScale)
            fire.Scale = ConchBlessing.firebreath.data.flameScale
            fire.CollisionDamage = baseDamage
            fire.GridCollisionClass = GridCollisionClass.COLLISION_NONE
            if fire.SetTimeout then
                fire:SetTimeout(life)
            end
        end
        local tdata = tear:GetData()
        tdata.__ConchFireBreath = {
            chance = getChanceFromLuck(player.Luck, stackCount, 2.0),
            duration = ConchBlessing.firebreath.data.burnDuration,
            source = player,
            baseDamage = baseDamage
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

ConchBlessing.firebreath.onPlayerUpdate = function(_, player)
    if not player then return end
    local hasIce = player:HasCollectible(ICE_CANDLE_ID)
    local hasFire = player:HasCollectible(FIRE_CANDLE_ID)
    if not hasIce and not hasFire then
        setBlindfold(player, false)
        return
    end
    setBlindfold(player, true)
    if not hasFire then return end
    local direction = getBreathDirection(player, "__ConchFireBreathLastDir")
    if not direction then return end
    ConchBlessing.firebreath._lastFireFrame = ConchBlessing.firebreath._lastFireFrame or {}
    local playerID = player:GetPlayerType()
    local frame = Game():GetFrameCount()
    if ConchBlessing.firebreath._lastFireFrame[playerID] == frame then return end
    if frame % 3 ~= 0 then return end
    ConchBlessing.firebreath._lastFireFrame[playerID] = frame
    local stackCount = player:GetCollectibleNum(FIRE_CANDLE_ID)
    if stackCount < 1 then return end
    spawnFireBreath(player, direction, stackCount)
end

ConchBlessing.firebreath.onTearCollision = function(_, tear, collider, _)
    if not tear or not collider then return end
    local npc = collider:ToNPC()
    if not npc or not npc:IsVulnerableEnemy() then return end
    local preVel = npc.Velocity
    local data = tear:GetData()
    if not data or not data.__ConchFireBreath then return end
    if data.__ConchFireBreathApplied then return end
    data.__ConchFireBreathApplied = true
    local chance = data.__ConchFireBreath.chance or 0
    if chance <= 0 then return end
    if math.random() <= chance then
        local source = data.__ConchFireBreath.source or tear.SpawnerEntity or npc
        local burnDamage = 0
        local sp = source and source.ToPlayer and source:ToPlayer() or nil
        if sp then
            burnDamage = math.max(1.0, (sp.Damage or 1.0) * 0.2)
        else
            burnDamage = 1.0
        end
        npc:AddBurn(EntityRef(source), data.__ConchFireBreath.duration or 60, burnDamage)
    end
    if preVel then
        npc.Velocity = preVel
    end
end

ConchBlessing.firebreath.onTearUpdate = function(_, tear)
    if not tear then return end
    local data = tear:GetData()
    if not data or not data.__ConchFireBreath then return end
    local targetScale = ConchBlessing.firebreath.data.flameScale
    local startScale = ConchBlessing.firebreath.data.spawnScale
    local growFrames = ConchBlessing.firebreath.data.growFrames or 1
    local t = math.min(1, math.max(0, tear.FrameCount / growFrames))
    local currentScale = startScale + (targetScale - startScale) * t
    if tear.Scale ~= currentScale then
        tear.Scale = currentScale
    end
    local targetVec = Vector(currentScale, currentScale)
    if tear.SpriteScale.X ~= targetVec.X or tear.SpriteScale.Y ~= targetVec.Y then
        tear.SpriteScale = targetVec
    end
    if data.__ConchFireBreath.baseDamage and tear.CollisionDamage ~= data.__ConchFireBreath.baseDamage then
        tear.CollisionDamage = data.__ConchFireBreath.baseDamage
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
