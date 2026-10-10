-- Test fixtures only. No inventory, input or gameplay mutation outside a bench.
local H = {}
local TimerClock = require("scripts.lib.timer_clock")
local DamageOracle = require("scripts.dev.damage_oracle")

function H.beginClock(ctx)
    assert(require("scripts.dev.test_bench").isRunning(), "clock requires an active test")
    ctx.clockStart = TimerClock.begin(ctx)
    return ctx.clockStart
end

function H.clockAt(ctx, frame) TimerClock.advance(ctx, frame) end
function H.clockNow() return TimerClock.now() end
local inputPlayer, observing
local targetSerial = 0
local deaths = {}
local pendingKills = {}
local pendingKillPointers = {}
local killRoomEpoch = 0
local damageCapture
local pickupCapture
local awards = 0
local awardPickups = {}

if ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
        if require("scripts.dev.test_bench").isRunning() then
            awards=awards+1
            -- This observer loads AFTER ItemData's callbacks. Snapshot pickups
            -- emitted by those callbacks before the engine's vanilla award.
            awardPickups = {}
            for _, row in ipairs(pickupCapture and pickupCapture.rows or {}) do
                awardPickups[#awardPickups+1] = row
            end
        end
    end)
end

function H.awards() return awards end
function H.awardPickups() return awardPickups end

function H.clearAward(plan, natural)
    plan.require("engine award API available",function()
        return type(Game():GetRoom().SpawnClearAward)=="function" or nil,"Room:SpawnClearAward capability"
    end)
    plan.act(function(player,ctx)
        ctx.awardsBefore=awards
        ctx.awardCapture=H.capturePickups(nil,true)
        -- Canonical engine award operation; no direct item callback invocation.
        if natural then
            H.killTarget(player,ctx)
            Game():GetRoom():SetClear(false)
        else Game():GetRoom():SpawnClearAward() end
    end)
    if natural then
        plan.waitUntil(H.deathObserved,90,"award target completes a confirmed lethal hit")
        plan.check("native enemy death confirmed independently",H.deathObserved)
    end
    plan.waitUntil(function(_,ctx) return awards>ctx.awardsBefore end,60,"engine emits clean-award callback")
end

function H.capturePickups(variant, hold)
    pickupCapture = { variant = variant, hold = hold, count = 0, rows = {} }
    return pickupCapture
end

if ModCallbacks.MC_POST_PICKUP_INIT then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, function(_, pickup)
        if not pickupCapture or pickupCapture.variant and pickup.Variant ~= pickupCapture.variant then return end
        local c = pickupCapture
        c.count = c.count + 1
        c.rows[#c.rows + 1] = { entity = pickup, variant = pickup.Variant, subtype = pickup.SubType, frame = Game():GetFrameCount() }
        if c.hold then pickup.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE end
    end)
end

function H.refresh(player)
    player:AddCacheFlags(CacheFlag.CACHE_ALL)
    player:EvaluateItems()
end

function H.near(actual, expected)
    return type(actual) == "number" and type(expected) == "number"
        and math.abs(actual - expected) <= 0.0002 * math.max(1, math.abs(expected))
end

function H.expect(actual, expected)
    return H.near(actual, expected), string.format("actual=%s expected=%s", tostring(actual), tostring(expected))
end

function H.stats(player)
    return { Damage = player.Damage, Tears = 30 / (player.MaxFireDelay + 1), Range = player.TearRange / 40,
        Luck = player.Luck, Speed = player.MoveSpeed, ShotSpeed = player.ShotSpeed }
end

function H.sameStats(player, expected)
    for stat, actual in pairs(H.stats(player)) do
        if not H.near(actual, expected[stat]) then
            return false, string.format("%s actual=%.6f expected=%.6f", stat, actual, expected[stat])
        end
    end
    return true, "all six displayed stats match"
end

function H.save(player) return assert(ConchBlessing.SaveManager.GetRunSave(player), "missing run save") end

function H.entry(player, group, id, stat)
    local state = assert(ConchBlessing.getUnifiedMultiplierState(player), "missing StatsAPI player state")
    return state[group] and state[group][id] and state[group][id][stat]
end

function H.addition(player, group, id, stat)
    local entry = H.entry(player, group, id, stat)
    return entry and entry.cumulative or 0
end

function H.use(player, id, slot)
    slot = slot or ActiveSlot.SLOT_PRIMARY
    player:FullCharge(slot, true)
    player:UseActiveItem(id, UseFlag.USE_OWNED | UseFlag.USE_NOANIM, slot)
end

function H.pickup(player, id)
    return Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id,
        Game():GetRoom():GetCenterPos() + Vector(140, 0), Vector.Zero, nil):ToPickup()
end

-- Keep ordinary cycle fixtures deterministic with Golden Items installed. The
-- golden integration case separately upgrades the held active with SetGoldenItem.
function H.suppressRandomGoldenPedestals(ctx)
    local provider = GoldenItems and GoldenItems.Pickup and GoldenItems.Pickup.GOLDEN_ITEM
    if not provider or type(provider.TurnItemGold) ~= "function" or ctx.goldenSpawnFixture then return end
    ctx.goldenSpawnFixture = true
    local previous = provider.DisableGoldPedestal
    provider.DisableGoldPedestal = true
    ctx.cleanupFns = ctx.cleanupFns or {}
    ctx.cleanupFns[#ctx.cleanupFns + 1] = function() provider.DisableGoldPedestal = previous end
end

function H.target(player, grounded)
    -- Neither target shoots or spawns enemies on death. Do not freeze it or set
    -- NO_TARGET: those flags mask aura/status eligibility and stop death logic.
    local npc = Isaac.Spawn(grounded and EntityType.ENTITY_MAGGOT or EntityType.ENTITY_ATTACKFLY, 0, 0,
        player.Position + Vector(80, 0), Vector.Zero, nil):ToNPC()
    assert(npc, "could not spawn test enemy")
    targetSerial = targetSerial + 1
    npc:GetData().__ConchBlessingTestTarget = targetSerial
    -- Skip only the spawn presentation. The NPC still receives its real first
    -- update before a death/weapon fixture is allowed to use it.
    npc:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    -- ENTCOLL_NONE also makes the engine report IsVulnerableEnemy() == false.
    -- Keep the real damage/collision path; zero contact damage protects the player.
    npc.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
    npc.CollisionDamage = 0
    npc.HitPoints, npc.MaxHitPoints = 100000, 100000
    return npc
end

function H.targetReady(npc)
    if not npc or not npc:Exists() or npc:IsDead() then return false, "target missing or dead" end
    if npc.FrameCount < 1 then return false, "waiting for first NPC update" end
    local active, vulnerable = npc:IsActiveEnemy(false), npc:IsVulnerableEnemy()
    if not active or not vulnerable then
        return false, string.format("target %s.%s.%s frame=%s active=%s vulnerable=%s collision=%s state=%s",
            tostring(npc.Type),tostring(npc.Variant),tostring(npc.SubType),tostring(npc.FrameCount),
            tostring(active),tostring(vulnerable),tostring(npc.EntityCollisionClass),tostring(npc.State))
    end
    return true
end

-- Test positioning is allowed; the attack's damage, lifetime, flags and item
-- callbacks are never changed. Keep one real output so HP loss is attributable.
function H.isolateAttack(keep)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local data = entity:GetData()
        if (not keep or GetPtrHash(entity) ~= GetPtrHash(keep)) and
            (entity.Type == EntityType.ENTITY_TEAR or entity.Type == EntityType.ENTITY_LASER
                or entity.Type == EntityType.ENTITY_BOMB
                or entity.Type == EntityType.ENTITY_EFFECT and (data.__ConchFireBreath or data.__ConchIceBreath
                    or data.__ConchDragonVortex or data.__ConchDragonWhirlpool)) then entity:Remove() end
    end
end

function H.familiarAnchors(player, marker)
    local list = {}
    -- FindByType excludes FLAG_NO_QUERY (including native hidden familiars).
    -- A production tracking table is diagnostic only; enumerate actual room
    -- entities and require the familiar's real owner on every assertion.
    for _,entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_FAMILIAR and entity:Exists() then
            local f = entity:ToFamiliar()
            if f and f.Player and GetPtrHash(f.Player) == GetPtrHash(player)
                and f:GetData()[marker] then list[#list+1] = f end
        end
    end
    return list
end

function H.sampleAttackDamage(plan, expected, selectAttack, options)
    options = options or {}
    if not options.control then
        plan.require("applied-hit observer available for HP measurement",function()
            return ModCallbacks.MC_POST_ENTITY_TAKE_DMG and true or nil,"requires exact applied-hit evidence"
        end)
    end
    plan.act(function(player, ctx)
        ctx.damageExpected = expected(player, ctx)
        ctx.attack = selectAttack(player, ctx)
        assert(ctx.attack and ctx.attack:Exists(), "no live attack available for HP test")
        H.isolateAttack(ctx.attack)
        ctx.target = H.target(player, true)
        ctx.target:ClearEntityFlags(EntityFlag.FLAG_NO_TARGET)
        ctx.target.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
        ctx.target.Position=player.Position+Vector(-100,100)
        -- Avoid 100,000 HP float rounding swallowing small damage differences.
        ctx.target.HitPoints = math.max(1000, math.abs(ctx.damageExpected) * 100)
        ctx.target.MaxHitPoints = ctx.target.HitPoints
        ctx.damageModel = options.blueFlame and ctx.attack.Type == EntityType.ENTITY_EFFECT
            and ctx.attack.Variant == EffectVariant.BLUE_FLAME and "blue_flame" or nil
    end)
    plan.waitUntil(function(_,ctx) return H.targetReady(ctx.target) end,30,"damage target finishes native initialization")
    plan.act(function(player,ctx)
        assert(ctx.attack:Exists(),"attack expired before initialized target; damage not measured")
        ctx.target.Position = ctx.attack.Position + ctx.attack.Velocity
        local laser = ctx.attack:ToLaser()
        if laser and laser.Radius and laser.Radius > 0 then
            ctx.target.Position = ctx.attack.Position + Vector(laser.Radius, 0)
        end
        ctx.damageBefore = ctx.target.HitPoints
        H.captureDamage(ctx, true)
    end)
    plan.waitUntil(function(_, ctx)
        if #ctx.hitCapture.hits == 0 or ctx.target.HitPoints >= ctx.damageBefore then return false end
        -- Stop at the applied hit, then let the engine commit its HP buffer.
        -- The attack was removed by the observer, so no second collision can
        -- silently change the expected one-hit contract.
        if not ctx.hitCapture.hpSeen then ctx.hitCapture.hpSeen=true; return false end
        ctx.actualHpLoss = ctx.damageBefore - ctx.target.HitPoints
        ctx.damageEvidence=H.damageEvidence(ctx)
        ctx.damagePassed, ctx.damageComparison = DamageOracle.evaluate(ctx.damageExpected,
            ctx.hitCapture, ctx.actualHpLoss, ctx.damageBefore, ctx.damageModel)
        H.stopDamageCapture(ctx)
        ctx.target:Remove(); ctx.target = nil
        if ctx.attack:Exists() then ctx.attack:Remove() end
        ctx.attack = nil
        return true
    end, 30, "real generated attack damages the target")
    local function result(_,ctx) return ctx.damagePassed,ctx.damageComparison.."; "..ctx.damageEvidence end
    if options.control then
        plan.note("vanilla blue-flame HP control (fixture, not item verification)",function(_,ctx)
            return ctx.damageComparison.."; "..ctx.damageEvidence
        end)
        plan.act(function(_,ctx)
            assert(ctx.damagePassed,"vanilla damage control disagrees with oracle: "..ctx.damageComparison)
        end)
    else
        plan.check("actual target HP loss matches the attack contract", result)
    end
end

local function pendingKillFor(entity)
    local row = pendingKillPointers[GetPtrHash(entity)]
    -- GetData can be cleared by another callback during death. Identity must
    -- survive that, but a reused address or copied marker must not match.
    if row and row.seed == entity.InitSeed and row.roomEpoch == killRoomEpoch then return row end
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM,function() killRoomEpoch=killRoomEpoch+1 end)

if ModCallbacks.MC_POST_NPC_DEATH then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc)
        if next(pendingKills)==nil then return end
        local row = pendingKillFor(npc)
        if row then deaths[row.token] = true; row.deathEvents=(row.deathEvents or 0)+1 end
    end)
end

function H.killTarget(player, ctx)
    ctx.target = H.target(player)
    ctx.deathToken = ctx.target:GetData().__ConchBlessingTestTarget
    local row = {npc=ctx.target,player=player,token=ctx.deathToken,seed=ctx.target.InitSeed,roomEpoch=killRoomEpoch}
    pendingKills[ctx.deathToken] = row
    pendingKillPointers[GetPtrHash(ctx.target)] = row
end

function H.deathObserved(_, ctx)
    local row = pendingKills[ctx.deathToken]
    if row and row.roomEpoch ~= killRoomEpoch then return false,"target room changed before death verification" end
    local detail="waiting for independently confirmed lethal damage"
    if row then
        local npc=row.npc
        detail=string.format("target token=%s exists=%s damageRequested=%s accepted=%s killEvent=%s removeEvent=%s npcDeathEvents=%s",
            tostring(ctx.deathToken),tostring(npc:Exists()),tostring(row.requested),tostring(row.accepted),
            tostring(row.killed==true),tostring(row.removed==true),tostring(row.deathEvents or 0))
        if npc:Exists() then
            detail=detail..string.format(" HP=%s frame=%s dead=%s state=%s; %s",tostring(npc.HitPoints),
                tostring(npc.FrameCount),tostring(npc:IsDead()),tostring(npc.State),select(2,H.targetReady(npc)) or "ready")
        end
    end
    -- NPC_DEATH is the animation-completion callback, not the only proof of a
    -- kill. Instant death may instead report KILL then REMOVE. Require the
    -- requested, accepted lethal hit AND both native events for that path.
    -- An item-dependent reward/counter assertion still follows this evidence.
    return deaths[ctx.deathToken] == true or row ~= nil and row.requested == true
        and row.accepted == true and row.killed == true and row.removed == true, detail
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    for token,row in pairs(pendingKills) do
        local npc=row.npc
        if row.roomEpoch == killRoomEpoch and not row.requested and not deaths[token] and H.targetReady(npc) then
            -- A real lethal hit follows the NPC's ordinary damage/death path.
            -- Kill or removal alone is never our death oracle.
            row.requested=true
            row.accepted=npc:TakeDamage(npc.HitPoints+10,0,EntityRef(row.player),0)
        end
    end
end)

for _,event in ipairs({{"MC_POST_ENTITY_KILL","killed"},{"MC_POST_ENTITY_REMOVE","removed"}}) do
    if ModCallbacks[event[1]] then
        ConchBlessing:AddCallback(ModCallbacks[event[1]],function(_,entity)
            if next(pendingKills)==nil then return end
            local row=pendingKillFor(entity)
            if row then row[event[2]]=true end
        end)
    end
end

function H.captureDamage(ctx, stopAfterFirst)
    ctx.hitCapture={target=GetPtrHash(ctx.target),attack=GetPtrHash(ctx.attack),hits={},foreignHits=0,
        stopAfterFirst=stopAfterFirst,
        variant=ctx.attack.Type..":"..ctx.attack.Variant..":"..ctx.attack.SubType,
        preparedAge=ctx.attack.FrameCount,preparedDamage=ctx.attack.CollisionDamage}
    damageCapture=ctx.hitCapture
end

function H.blueFlameDamageControl(plan)
    -- Check the empirical lifetime oracle on real, unmarked vanilla attacks at
    -- separated ages before testing the item's own projectiles against it.
    plan.require("applied-hit observer available for vanilla control",function()
        return ModCallbacks.MC_POST_ENTITY_TAKE_DMG and true or nil,"cannot calibrate damage without applied hits"
    end)
    for _,age in ipairs({1,10}) do
        plan.act(function(player,ctx)
            ctx.controlFlame=assert(Isaac.Spawn(EntityType.ENTITY_EFFECT,EffectVariant.BLUE_FLAME,0,
                player.Position+Vector(180,0),Vector.Zero,player):ToEffect())
            ctx.controlFlame:SetTimeout(40)
            ctx.controlFlame.CollisionDamage=0.7
        end)
        plan.waitUntil(function(_,ctx) return ctx.controlFlame.FrameCount>=age end,20,"vanilla damage control age "..age)
        H.sampleAttackDamage(plan,function() return 0.7 end,function(_,ctx) return ctx.controlFlame end,
            {blueFlame=true,control=true})
        plan.act(function(_,ctx) ctx.controlFlame=nil end)
    end
end

function H.stopDamageCapture(ctx)
    if damageCapture==ctx.hitCapture then damageCapture=nil end
end

function H.flameDecayControl(plan)
    -- Unmarked vanilla flame: observe its native age curve independently of
    -- this item's update callbacks. This diagnostic never passes the item.
    local function snapshot(ctx,age)
        local flame=ctx.controlFlame
        if not flame:Exists() then return "expired before age "..age end
        return string.format("age=%s timeout=%s collisionDamage=%s",tostring(flame.FrameCount),
            tostring(flame.Timeout),tostring(flame.CollisionDamage))
    end
    plan.act(function(player,ctx)
        ctx.controlFlame=assert(Isaac.Spawn(EntityType.ENTITY_EFFECT,EffectVariant.BLUE_FLAME,0,
            player.Position+Vector(180,0),Vector.Zero,player):ToEffect(),"native flame control spawn failed")
        ctx.controlFlame:SetTimeout(40)
        ctx.controlFlame.CollisionDamage=player.Damage*0.2
        ctx.controlFlame.SpriteScale=Vector(0.8,0.8)
        ctx.controlSample=snapshot(ctx,0)
    end)
    for _,age in ipairs({0,5,10}) do
        if age>0 then
            plan.waitUntil(function(_,ctx)
                local ready=not ctx.controlFlame:Exists() or ctx.controlFlame.FrameCount>=age
                if ready then ctx.controlSample=snapshot(ctx,age) end
                return ready
            end,30,"native blue-flame control reaches age "..age)
        end
        plan.note("native blue-flame age control; diagnostic only",function(_,ctx)
            return ctx.controlSample
        end)
    end
    plan.act(function(_,ctx)
        if ctx.controlFlame:Exists() then ctx.controlFlame:Remove() end
        ctx.controlFlame=nil
    end)
end

function H.damageEvidence(ctx)
    local capture=ctx.hitCapture
    if not capture then return "no hit capture" end
    local parts={"attack="..capture.variant,"preparedAge="..tostring(capture.preparedAge),
        "preparedDamage="..tostring(capture.preparedDamage),"appliedHits="..#capture.hits,
        "foreignHits="..(capture.foreignHits or 0)}
    for index,hit in ipairs(capture.hits) do
        parts[#parts+1]=string.format("hit%d amount=%s age=%s timeout=%s collisionDamage=%s freeze=%s",
            index,tostring(hit.amount),tostring(hit.age),tostring(hit.timeout),tostring(hit.damage),tostring(hit.freeze))
    end
    return table.concat(parts,"; ")
end

function H.kill(plan, saveKey, field, expectedDelta)
    plan.act(function(player, ctx)
        ctx.beforeKill = (H.save(player)[saveKey] or {})[field] or 0
        H.killTarget(player, ctx)
    end)
    plan.waitUntil(H.deathObserved, 90, "real target lethal hit and death")
    plan.check("native enemy death confirmed independently",H.deathObserved)
    plan.check("real enemy death contribution", function(player, ctx)
        local now = (H.save(player)[saveKey] or {})[field] or 0
        return H.expect(now - ctx.beforeKill, expectedDelta)
    end)
end

function H.hit(plan)
    plan.waitUntil(function(player) return player:GetDamageCooldown() == 0 end, 180, "damage cooldown expires")
    plan.act(function(player, ctx)
        player:AddHearts(12)
        ctx.hitSource = H.target(player)
        ctx.hitSource.Position = player.Position + Vector(240,0)
        ctx.hitAccepted = player:TakeDamage(1, 0, EntityRef(ctx.hitSource), 30)
        ctx.hitFrame = Game():GetFrameCount()
    end)
    plan.wait(2)
    plan.check("test hit accepted", function(_, ctx) return ctx.hitAccepted == true, tostring(ctx.hitAccepted) end)
    plan.act(function(_, ctx) if ctx.hitSource then ctx.hitSource:Remove(); ctx.hitSource = nil end end)
end

-- Observe spawned attacks during real shooting input, including their first
-- visible damage values. Calling an item's callback ourselves could conceal a
-- missing callback registration, so these fixtures never do that.
function H.shoot(player, key, ctx, triggerLimit)
    inputPlayer = player
    observing = { player = player, keys = type(key) == "table" and key or { key }, seen = {}, attacks = {}, count = 0,
        countsByKey = {}, damages = {}, samples = {}, entities = {}, triggers = 0, triggerLimit = triggerLimit }
    -- Only new attacks belong to this sample. No need to wait several seconds
    -- for previous projectiles to expire just to avoid counting them twice.
    for _, entity in ipairs(Isaac.GetRoomEntities()) do observing.seen[GetPtrHash(entity)] = true end
    ctx.shots = observing
end

function H.stopShooting() inputPlayer, observing = nil, nil end

-- Use real shooting input and the engine's collision path. In particular,
-- SOFLAM's Technology replacement must be tested with its emitted laser, never
-- a fabricated tear passed to TakeDamage.
function H.fireWeaponAtTarget(plan, weapon, triggerLimit)
    plan.require("real weapon event observer available",function()
        return (ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED
            and ModCallbacks.MC_POST_ENTITY_TAKE_DMG
            and (weapon~="laser" or ModCallbacks.MC_POST_LASER_INIT)) and true or nil,
            "weapon-trigger, applied-damage and laser-init callbacks required"
    end)
    plan.waitUntil(function(_,ctx) return H.targetReady(ctx.target) end,60,"weapon target initialized and vulnerable")
    plan.act(function(player,ctx)
        assert(ctx.target and ctx.target:Exists(),"missing weapon target")
        ctx.target.Position=player.Position+Vector(200,0)
        ctx.target.Velocity=Vector.Zero
        ctx.target.EntityCollisionClass=EntityCollisionClass.ENTCOLL_ALL
        ctx.weaponTargetPosition=Vector(ctx.target.Position.X,ctx.target.Position.Y)
        ctx.weaponHpBefore=ctx.target.HitPoints
        ctx.weaponStartedAt=Game():GetFrameCount()
        H.shoot(player,weapon=="laser" and "$lasers" or "$tears",ctx,triggerLimit or 1)
        ctx.shots.directOnly=true
        ctx.shots.targetHash=GetPtrHash(ctx.target)
        -- One physical beam designates the target. With multishot, SOFLAM
        -- queues multiple missiles for EACH beam: isolate one real beam so its
        -- rocket-count contract can be measured without overlapping explosions.
        ctx.shots.isolateLasers=weapon=="laser"
    end)
    plan.waitUntil(function(_,ctx)
        ctx.target.Position=ctx.weaponTargetPosition
        ctx.target.Velocity=Vector.Zero
        return ctx.shots.count>0 and ctx.target.HitPoints<ctx.weaponHpBefore
    end,180,"one real "..weapon.." attack hits the target")
    plan.act(function(_,ctx)
        H.stopShooting()
        ctx.weaponHpLoss=ctx.weaponHpBefore-ctx.target.HitPoints
        ctx.weaponAttack=ctx.shots.entities[1]
        -- A normal tear may already be removed by the hit that reduced HP.
        ctx.weaponType=ctx.shots.samples[1] and ctx.shots.samples[1].entityType
        ctx.weaponHitAt=ctx.shots.hitFrame
        -- The first strike's input damage has now settled. Remove only the
        -- observed input attack so later HP loss belongs to the queued missile.
        for _,attack in ipairs(ctx.shots.entities) do if attack:Exists() then attack:Remove() end end
    end)
    plan.require("actual emitted "..weapon.." and direct HP damage observed",function(_,ctx)
        local kind=weapon=="laser" and EntityType.ENTITY_LASER or EntityType.ENTITY_TEAR
        return ctx.weaponType==kind and ctx.weaponHpLoss>0 and ctx.weaponHitAt~=nil,
            "entity type="..tostring(ctx.weaponType).." HP loss="..tostring(ctx.weaponHpLoss)
    end)
end

ConchBlessing:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
    if not inputPlayer or not entity or GetPtrHash(entity) ~= GetPtrHash(inputPlayer) then return end
    if action ~= ButtonAction.ACTION_SHOOTRIGHT then return end
    if hook == InputHook.GET_ACTION_VALUE then return 1 end
    return true
end)

local function recordAttack(entity,key,data)
    local hash=GetPtrHash(entity)
    if observing.seen[hash] then return end
    observing.seen[hash]=true
    observing.attacks[hash]=true
    observing.count=observing.count+1
    observing.entities[#observing.entities+1]=entity
    observing.countsByKey[key]=(observing.countsByKey[key] or 0)+1
    observing.damages[#observing.damages+1]=data.baseDamage or data.damage or data.touchDamage or entity.CollisionDamage
    observing.samples[#observing.samples+1]={key=key,entityType=entity.Type,range=data.maxDistance,
        speed=data.initialSpeed,chance=data.burnChance or data.freezeChance}
end

if ModCallbacks.MC_POST_LASER_INIT then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_LASER_INIT,function(_,laser)
        if not (observing and observing.isolateLasers) then return end
        local owner=require("scripts.lib.damage_provenance").getDirectPlayerOwner(laser)
        if not owner or GetPtrHash(owner)~=GetPtrHash(observing.player) then return end
        if observing.primaryLaser and observing.primaryLaser~=GetPtrHash(laser) then laser:Remove();return end
        observing.primaryLaser=GetPtrHash(laser)
        recordAttack(laser,"$lasers",{})
    end)
end

if ModCallbacks.MC_POST_ENTITY_TAKE_DMG then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG,function(_,entity,amount,_,source,_,extraSource)
        if damageCapture and damageCapture.target==GetPtrHash(entity) and amount>0 then
            local attack=require("scripts.lib.damage_provenance").getSourceEntity(source,extraSource)
            if attack and damageCapture.attack==GetPtrHash(attack) then
                local effect=attack:ToEffect()
                damageCapture.hits[#damageCapture.hits+1]={amount=amount,age=attack.FrameCount,
                    timeout=effect and effect.Timeout,damage=attack.CollisionDamage,
                    freeze=type(entity.GetFreezeCountdown)=="function" and entity:GetFreezeCountdown() or nil}
                if damageCapture.stopAfterFirst and attack:Exists() then attack:Remove() end
            else
                damageCapture.foreignHits=(damageCapture.foreignHits or 0)+1
            end
        end
        if not (observing and observing.targetHash==GetPtrHash(entity) and amount>0) then return end
        local attack=require("scripts.lib.damage_provenance").getSourceEntity(source,extraSource)
        if attack and observing.attacks[GetPtrHash(attack)] then
            observing.hitFrame=observing.hitFrame or Game():GetFrameCount()
            observing.directDamage=(observing.directDamage or 0)+amount
            observing.directHits=(observing.directHits or 0)+1
        end
    end)
end

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not observing then return end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type ~= EntityType.ENTITY_PLAYER then
            for _, key in ipairs(observing.keys) do
                local data = (key == "$tears" and entity.Type == EntityType.ENTITY_TEAR
                    or key == "$lasers" and entity.Type == EntityType.ENTITY_LASER) and {} or entity:GetData()[key]
                if data and (key=="$tears" or key=="$lasers") then
                    local provenance=require("scripts.lib.damage_provenance")
                    local owner=observing.directOnly and provenance.getDirectPlayerOwner(entity)
                        or not observing.directOnly and provenance.getPlayerOwner(entity)
                    if not owner or GetPtrHash(owner)~=GetPtrHash(observing.player) then data=nil end
                end
                local hash = GetPtrHash(entity)
                if data and not observing.seen[hash] then recordAttack(entity,key,data) end
            end
        end
    end
end)

if ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED, function(_, _, _, owner)
        if observing and owner and inputPlayer and GetPtrHash(owner) == GetPtrHash(inputPlayer) then
            observing.triggers = observing.triggers + 1
            if observing.triggerLimit and observing.triggers >= observing.triggerLimit then inputPlayer = nil end
        end
    end)
end

function H.cleanup(ctx)
    local failure
    for _,name in ipairs(ctx.bundleRemaining or {}) do
        local line="[ConchTest] NOT RUN "..name.." (bundle stopped before this case)"
        Isaac.ConsoleOutput(line.."\n")
        Isaac.DebugString(line)
    end
    ctx.bundleRemaining=nil
    if ctx.caseCtx then
        local ok,err=pcall(H.cleanup,ctx.caseCtx)
        ctx.caseCtx=nil
        if not ok then failure=err end
    end
    for _, cleanup in ipairs(ctx.cleanupFns or {}) do
        local ok,err=pcall(cleanup)
        if not ok then failure=failure or err end
    end
    ctx.cleanupFns = nil
    local released,err=pcall(TimerClock.release,ctx)
    if not released then failure=failure or err end
    H.stopShooting()
    damageCapture=nil
    for _,row in pairs(pendingKills) do if row.npc:Exists() then row.npc:Remove() end end
    pendingKills = {}
    pendingKillPointers = {}
    deaths = {}
    awards = 0
    awardPickups = {}
    pickupCapture = nil
    for _, key in ipairs({ "target", "hitSource", "pickup", "attack", "tear", "outsideTarget", "nearTarget", "controlFlame" }) do
        local entity = ctx[key]
        if entity and entity:Exists() then entity:Remove() end
    end
    if failure then error(failure) end
end

return H
