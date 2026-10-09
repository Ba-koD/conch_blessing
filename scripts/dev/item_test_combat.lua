local H = require("scripts.dev.item_test_support")
local C = {}

C.KRONOS = { prepare = function(plan)
    plan.act(function(player)
        for _ = 1, 2 do player:AddCollectible(CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, 0, false) end
    end)
end, stage = function(plan, _, n)
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, true) == (n > 0 and 0 or 2)
    end, 90, "familiar absorption or return completes")
    plan.check("two special familiars each supply +2, independent of Kronos copies", function(player, ctx)
        return H.expect(player.Damage, ctx.base.Damage + (n > 0 and 4 or 0))
    end)
    plan.check("last-copy loss returns familiars; partial loss keeps absorptions", function(player)
        local held = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, true)
        return held == (n > 0 and 0 or 2), "Guardian Angel inventory=" .. held
    end)
end, finish = function(plan, id)
    plan.section("KRONOS / absorbed abilities follow damage changes")
    if not require("scripts.lib.damage_provenance").hasAppliedDamageCallback() then
        plan.check("real absorbed ability damage", function() return nil, "applied-damage callback unavailable" end)
        return
    end
    plan.act(function(player)
        player:AddCollectible(id, 0, false)
        for _ = 1, 10 do player:AddCollectible(CollectibleType.COLLECTIBLE_DADDY_LONGLEGS, 0, false) end
        for _ = 1, 4 do player:AddCollectible(CollectibleType.COLLECTIBLE_LIL_SPEWER, 0, false) end
    end)
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_DADDY_LONGLEGS, true) == 0
            and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_LIL_SPEWER, true) == 0
    end, 120, "guaranteed stomp and creep abilities absorbed")
    plan.wait(2)
    for _, profile in ipairs({ "base", "increased", "restored" }) do
        plan.section("KRONOS / ability damage " .. profile)
        plan.act(function(player)
            for _ = 1, 5 do
                if profile == "increased" then player:AddCollectible(CollectibleType.COLLECTIBLE_STEVEN, 0, false)
                elseif profile == "restored" then player:RemoveCollectible(CollectibleType.COLLECTIBLE_STEVEN) end
            end
        end)
        plan.wait(4)
        plan.act(function(player, ctx)
            local target = H.target(player)
            ctx.target = target
            ctx.oldCreeps = {}
            for _, creep in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_CREEP_RED, -1)) do
                ctx.oldCreeps[GetPtrHash(creep)] = true
            end
            ctx.absorbedDamage = player.Damage
        end)
        H.fireWeaponAtTarget(plan,"tear")
        -- Enemy HP is buffered by the engine. The flying input target cannot
        -- take creep damage while the direct hit and stomp settle.
        plan.wait(2)
        plan.act(function(_,ctx)
            ctx.stompHpLoss = ctx.weaponHpBefore - ctx.target.HitPoints
            ctx.creepDamages = {}
            for _, creep in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_CREEP_RED, -1)) do
                if not ctx.oldCreeps[GetPtrHash(creep)] then
                    ctx.creepDamages[#ctx.creepDamages + 1] = creep.CollisionDamage
                    creep:Remove()
                end
            end
            ctx.target:Remove()
            ctx.target = nil
        end)
        plan.check("stomp actual HP loss follows current damage", function(_, ctx)
            return H.expect(ctx.stompHpLoss, ctx.shots.directDamage + 2 * ctx.absorbedDamage)
        end)
        plan.check("new creep damage follows current damage", function(_, ctx)
            if #ctx.creepDamages == 0 then return false, "no new creep spawned at 100% chance" end
            local expected = ctx.absorbedDamage * 0.66
            for _, damage in ipairs(ctx.creepDamages) do
                if not H.near(damage, expected) then return H.expect(damage, expected) end
            end
            return true, "all new creep damage=" .. expected .. "; HP ticks not measured here"
        end)
    end
end }

C.TIME_MONEY = { stage = function(plan, _, n)
    plan.check("live familiar count follows copies, including zero", function(player)
        local item = ConchBlessing.ItemData.TIME_MONEY
        local variant = assert(item.entity and item.entity.variant, "missing familiar registry variant")
        local count = 0
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1)) do
            local familiar = entity:ToFamiliar()
            if familiar and familiar.Player and GetPtrHash(familiar.Player) == GetPtrHash(player) then count = count + 1 end
        end
        return H.expect(count, n)
    end)
end }

for key, spec in pairs({ FIRE_BREATH = { dataKey = "__ConchFireBreath", coef = 0.3 },
    ICE_BREATH = { dataKey = "__ConchIceBreath", coef = 0.2 },
    DRAGON = { dataKey = { "__ConchDragonTechX", "__ConchDragonVortex" }, coef = 0.25 } }) do
    C[key] = { prepare = key ~= "DRAGON" and function(plan)
        -- Copy/removal checks need one real burst, not a repeated low-luck wait.
        -- The owned-stat matrix separately exercises 15/10/2/1-shot boundaries.
        plan.act(function(player)
            for _ = 1, 14 do player:AddCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT, 0, false) end
        end)
        if key=="ICE_BREATH" then
            H.flameDecayControl(plan)
            H.blueFlameDamageControl(plan)
        end
    end or nil, stage = function(plan, _, n)
        if key == "DRAGON" then
            plan.check("flight/spectral flags follow presence", function(player, ctx)
                return player.CanFly == (n > 0 or ctx.baseFly)
                    and (player.TearFlags & TearFlags.TEAR_SPECTRAL ~= 0) == (n > 0 or ctx.baseSpectral),
                    "flight=" .. tostring(player.CanFly)
            end)
        end
        if not ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
            plan.check("real weapon-trigger path", function() return nil, "MC_POST_TRIGGER_WEAPON_FIRED unavailable" end)
            return
        end
        plan.act(function(player, ctx)
            local interval = key == "DRAGON" and 5 or math.max(1, math.floor(15 - player.Luck))
            local state = player:GetData()[key == "DRAGON" and "__ConchDragon" or spec.dataKey]
            local previous = state and state.attackCount or 0
            ctx.requiredTriggers = n > 0 and math.max(1, interval - previous) or interval
            H.shoot(player, spec.dataKey, ctx, ctx.requiredTriggers)
        end)
        plan.waitUntil(function(_, ctx)
            return n > 0 and ctx.shots.count > 0 or n == 0 and ctx.shots.triggers >= ctx.requiredTriggers
        end, 300, "required attacks observed")
        plan.act(function() H.stopShooting() end)
        plan.check("real firing spawns only while owned", function(_, ctx)
            local s = ctx.shots
            if s.triggers == 0 then return false, "no real weapon-trigger events received" end
            return (n > 0 and s.count > 0) or (n == 0 and s.count == 0),
                "weapon triggers=" .. s.triggers .. " new projectiles=" .. s.count
        end)
        if key == "DRAGON" then
            plan.check("one copy fires lightning; stacked copies replace it with typhoons", function(_, ctx)
                local lightning = ctx.shots.countsByKey.__ConchDragonTechX or 0
                local typhoons = ctx.shots.countsByKey.__ConchDragonVortex or 0
                local correct = n == 0 and lightning == 0 and typhoons == 0
                    or n == 1 and lightning > 0 and typhoons == 0
                    or n >= 2 and lightning == 0 and typhoons > 0
                return correct, "lightning=" .. lightning .. " typhoons=" .. typhoons
            end)
        end
        if n > 0 then
            plan.check("burst occurs at the required real attack count", function(_, ctx)
                return H.expect(ctx.shots.triggers, ctx.requiredTriggers)
            end)
            plan.check("burst projectile count follows current tears", function(player, ctx)
                local expected = key == "DRAGON" and 5 or math.max(1, math.floor(30 / (math.max(0, player.MaxFireDelay) + 1)))
                return H.expect(ctx.shots.count, expected)
            end)
            plan.check("projectile damage scales with remaining copies", function(player, ctx)
                local expected = player.Damage * spec.coef * n
                if #ctx.shots.damages == 0 then return false, "no spawned damage sample" end
                for _, actual in ipairs(ctx.shots.damages) do
                    if not H.near(actual, expected) then return H.expect(actual, expected) end
                end
                return true, "all samples match " .. expected
            end)
            if key ~= "DRAGON" then
                plan.check("emitted flame status chance follows live luck", function(player, ctx)
                    local chance = math.max(0, math.min(1, player.Luck * (key == "FIRE_BREATH" and 0.05 or 0.01)))
                    for _, sample in ipairs(ctx.shots.samples) do
                        if not H.near(sample.chance, chance) then return false, "status chance: " .. tostring(sample.chance) .. " expected " .. chance end
                    end
                    return #ctx.shots.samples > 0, "spawned chance=" .. chance .. "; actual status checked in status_conditions"
                end)
            end
            H.sampleAttackDamage(plan, function(player) return player.Damage * spec.coef * n end,
                function(_, ctx) return ctx.shots.entities[1] end, {blueFlame=key=="ICE_BREATH"})
        else
            plan.check("attack counter cleared after loss", function(player)
                local keyName = key == "DRAGON" and "__ConchDragon" or spec.dataKey
                local state = player:GetData()[keyName]
                return not state or state.attackCount == 0, "no stored attacks while absent"
            end)
        end
    end }
end

C.LIVE_EYE = { stage = function(plan, _, n)
    if not ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
        plan.check("real tear hit", function() return nil, "weapon-trigger observer unavailable" end)
        return
    end
    plan.act(function(player, ctx)
        ctx.target = H.target(player)
        ctx.target.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
        ctx.target.CollisionDamage = 0
        ctx.targetHp = ctx.target.HitPoints
        ctx.eyeBefore = ConchBlessing.liveeye.data.damageMultiplier
        H.shoot(player, "conch_liveeye", ctx, 1)
    end)
    plan.waitUntil(function(_, ctx) return ctx.shots.triggers >= 1 end, 90, "first real tear attack")
    plan.act(function() H.stopShooting() end)
    plan.waitUntil(function(_, ctx) return ctx.target.HitPoints < ctx.targetHp end, 90, "first shot actually damages the target")
    plan.wait(2)
    plan.check("real tear hit updates once, and stops after removal", function(_, ctx)
        local expected = n > 0 and math.min(3, ctx.eyeBefore + 0.1) or ctx.eyeBefore
        return H.expect(ConchBlessing.liveeye.data.damageMultiplier, expected)
    end)
    plan.check("live multiplier applies once with duplicate copies", function(player, ctx)
        local expected = ctx.base.Damage * (n > 0 and ConchBlessing.liveeye.data.damageMultiplier or 1)
        return H.expect(player.Damage, expected)
    end)
    plan.act(function(_, ctx)
        if ctx.target then ctx.target:Remove(); ctx.target = nil end
    end)
end }

C.VOID_DAGGER = { prepare = function(plan)
    plan.act(function(player)
        for _=1,200 do player:AddCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT,0,false) end
    end)
end, stage = function(plan,_,n)
    plan.require("confirmed damage proc available",function()
        return require("scripts.lib.damage_provenance").hasAppliedDamageCallback() or nil,"applied-damage callback required"
    end)
    plan.act(function(player,ctx)
        H.isolateAttack()
        player.Position=Game():GetRoom():GetCenterPos()-Vector(180,0)
        ctx.target=H.target(player)
        ctx.beforeLasers={}
        for _,laser in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER,-1,-1)) do ctx.beforeLasers[GetPtrHash(laser)]=true end
        ctx.procDamage=player.Damage
    end)
    H.fireWeaponAtTarget(plan,"tear")
    plan.check("one ring for the real attack; zero after final removal",function(_,ctx)
        local count=0
        for _,entity in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER,-1,-1)) do
            if not ctx.beforeLasers[GetPtrHash(entity)] then count=count+1;ctx.ring=entity:ToLaser() end
        end
        return H.expect(count,n>0 and 1 or 0)
    end)
    if n>0 then
        plan.check("spawned ring uses current player damage",function(_,ctx)
            return ctx.ring and H.near(ctx.ring.CollisionDamage,ctx.procDamage),"ring damage="..tostring(ctx.ring and ctx.ring.CollisionDamage).." expected="..ctx.procDamage
        end)
        plan.act(function(_,ctx) ctx.target:Remove();ctx.target=nil end)
        H.sampleAttackDamage(plan,function(player) return player.Damage end,function(_,ctx) return ctx.ring end)
    end
    plan.act(function(_,ctx) if ctx.target then ctx.target:Remove();ctx.target=nil end end)
end }

C.SOFLAM = { prepare = function(plan)
    plan.act(function(player)
        for _=1,200 do player:AddCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT,0,false) end
    end)
end, stage = function(plan,_,n)
    plan.require("laser replacement follows actual ownership",function(player)
        if type(player.HasWeaponType)~="function" then return nil,"weapon inspection unavailable" end
        return player:HasWeaponType(WeaponType.WEAPON_LASER)==(n>0)
            and player:HasWeaponType(WeaponType.WEAPON_TEARS)==(n==0),"Technology while held; default tears after removal"
    end)
    plan.require("confirmed damage proc available",function()
        return require("scripts.lib.damage_provenance").hasAppliedDamageCallback() or nil,"applied-damage callback required"
    end)
    plan.act(function(player,ctx)
        H.isolateAttack()
        player.Position=Game():GetRoom():GetCenterPos()-Vector(180,0)
        ctx.target=H.target(player)
        ctx.procDamage=player.Damage
        ctx.strikesBefore=#ConchBlessing.soflam._pendingStrikes
    end)
    H.fireWeaponAtTarget(plan,n>0 and "laser" or "tear")
    plan.check("one strike per real attack, independent of item copies; zero when removed",function(_,ctx)
        return H.expect(#ConchBlessing.soflam._pendingStrikes-ctx.strikesBefore,n>0 and 1 or 0)
    end)
    plan.wait(2)
    plan.act(function(_,ctx) ctx.hpBeforeStrike=ctx.target.HitPoints end)
    if n>0 then
        plan.waitUntil(function(_,ctx)
            ctx.target.Position=ctx.weaponTargetPosition; ctx.target.Velocity=Vector.Zero
            return ctx.target.HitPoints<ctx.hpBeforeStrike and #ConchBlessing.soflam._pendingStrikes==ctx.strikesBefore
        end,120,"laser-designated missile actually damages target and finishes")
        plan.check("actual missile HP loss is three times current damage",function(_,ctx)
            local actual,expected=ctx.hpBeforeStrike-ctx.target.HitPoints,ctx.procDamage*3
            return math.abs(actual-expected)<=math.max(0.02,expected*0.002),"HP loss="..actual.." expected="..expected
        end)
    end
    plan.act(function(_,ctx) ctx.target:Remove();ctx.target=nil end)
end }

return C
