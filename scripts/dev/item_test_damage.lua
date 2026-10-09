local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

local function whirlpool()
    for _,e in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT,-1,-1)) do
        if e:GetData().__ConchDragonWhirlpool then return e end
    end
end

S.add("DRAGON","vortex_damage",{damage=true,synergies=true,conditions=true},function(plan,id)
    plan.require("real weapon observer available",function() return ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED and true or nil,"requires REPENTOGON weapon events" end)
    plan.act(function(player) S.collectible(player,id,2) end)
    plan.wait(4)
    for _,profile in ipairs({"base","increased","restored"}) do
        plan.section("DRAGON / full vortex lifecycle / " .. profile)
        plan.act(function(player,ctx)
            if profile=="increased" then S.collectible(player,CollectibleType.COLLECTIBLE_STEVEN,5)
            elseif profile=="restored" then S.collectible(player,CollectibleType.COLLECTIBLE_STEVEN,0) end
            player.Position=Game():GetRoom():GetCenterPos()
            H.shoot(player,"__ConchDragonVortex",ctx,5)
        end)
        plan.waitUntil(function(_,ctx) return ctx.shots.count>0 end,180,"real fifth attack creates tornadoes")
        plan.act(function(_,ctx)
            H.stopShooting()
            ctx.attack=ctx.shots.entities[1]
            H.isolateAttack(ctx.attack)
        end)
        plan.waitUntil(function(_,ctx)
            -- Keep this isolated attack in the test area; leave damage/lifetime untouched.
            if ctx.attack:Exists() then ctx.attack.Position=Game():GetRoom():GetCenterPos() end
            ctx.pool=whirlpool()
            if not ctx.pool then return false end
            ctx.poolStart=Game():GetFrameCount()
            return true
        end,90,"tornado naturally becomes whirlpool")
        plan.act(function(player,ctx)
            ctx.target=H.target(player,true)
            ctx.target.EntityCollisionClass=EntityCollisionClass.ENTCOLL_ALL
            ctx.target.Position=ctx.pool.Position+Vector(120,0)
            ctx.outsideTarget=H.target(player,true)
            ctx.outsideTarget.EntityCollisionClass=EntityCollisionClass.ENTCOLL_ALL
            ctx.outsideTarget.Position=ctx.pool.Position+Vector(230,0)
            ctx.hp,ctx.farHp=ctx.target.HitPoints,ctx.outsideTarget.HitPoints
            ctx.explosionExpected=player.Damage*25
            ctx.pulled=false; ctx.lastSeen=Game():GetFrameCount()
        end)
        plan.wait(2)
        plan.require("explosion targets finish initialization and accept damage",function(_,ctx)
            return ctx.target:Exists() and ctx.target:IsVulnerableEnemy() and ctx.outsideTarget:IsVulnerableEnemy(),
                "near/far targets must be initialized vulnerable NPCs"
        end)
        plan.waitUntil(function(_,ctx)
            if not ctx.pool:Exists() then ctx.poolEnd=Game():GetFrameCount(); return true end
            ctx.pulled=ctx.pulled or ctx.target.Velocity:Dot(ctx.pool.Position-ctx.target.Position)>0
            -- Hold both NPCs outside touch range, leaving the explosion isolated.
            ctx.target.Position=ctx.pool.Position+Vector(120,0)
            ctx.outsideTarget.Position=ctx.pool.Position+Vector(230,0)
            ctx.target.Velocity=Vector.Zero; ctx.outsideTarget.Velocity=Vector.Zero
            ctx.lastSeen=Game():GetFrameCount()
            return false
        end,75,"real two-second whirlpool expiry")
        -- The effect disappearing is not the enemy HP-buffer commit boundary.
        plan.wait(2)
        plan.check("whirlpool actually pulls the nearby enemy",function(_,ctx) return ctx.pulled,"observed inward NPC velocity" end)
        plan.check("whirlpool persists for two seconds",function(_,ctx)
            local elapsed=ctx.poolEnd-ctx.poolStart
            return elapsed>=59 and elapsed<=61,"observed updates=" .. elapsed .. " expected=60 (one update observation tolerance)"
        end)
        plan.check("expiry explosion deals 25 times current damage exactly once",function(_,ctx)
            local passed,detail=H.expect(ctx.hp-ctx.target.HitPoints,ctx.explosionExpected)
            return passed,detail.."; target collision="..ctx.target.EntityCollisionClass
                .." vulnerable="..tostring(ctx.target:IsVulnerableEnemy())
        end)
        plan.check("target outside explosion range loses no HP",function(_,ctx) return H.expect(ctx.outsideTarget.HitPoints,ctx.farHp) end)
        plan.act(function(_,ctx) ctx.target:Remove(); ctx.outsideTarget:Remove(); ctx.target=nil; ctx.outsideTarget=nil; ctx.attack=nil end)
    end
end,{"dragon"})

for key,spec in pairs({FIRE_BREATH={data="__ConchFireBreath",luck=20,flag="FLAG_BURN",duration=120,countdown="GetBurnCountdown"},
    ICE_BREATH={data="__ConchIceBreath",luck=100,flag="FLAG_FREEZE",duration=60,countdown="GetFreezeCountdown"}}) do
    S.add(key,"status_conditions",{damage=true,conditions=true},function(plan,id)
        plan.require("real weapon observer available",function() return ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED and true or nil,"weapon events unavailable" end)
        plan.require("applied-hit observer available for status isolation",function()
            return ModCallbacks.MC_POST_ENTITY_TAKE_DMG and true or nil,"requires exact first-hit isolation"
        end)
        plan.act(function(player) player:AddCollectible(id,0,false) end)
        plan.wait(4)
        if key=="ICE_BREATH" then
            plan.act(function(player,ctx) ctx.target=H.target(player) end)
            plan.waitUntil(function(_,ctx) return H.targetReady(ctx.target) end,30,"native freeze control target ready")
            plan.note("native freeze control; diagnostic only, not item verification",function(player,ctx)
                local npc=ctx.target
                local function countdown()
                    return type(npc.GetFreezeCountdown)=="function" and npc:GetFreezeCountdown() or "unavailable"
                end
                local before=countdown()
                npc:AddFreeze(EntityRef(player),60)
                local once=countdown()
                if EntityFlag.FLAG_ICE then npc:AddEntityFlags(EntityFlag.FLAG_ICE) end
                local ice=countdown()
                npc:AddFreeze(EntityRef(player),60)
                local twice=countdown()
                npc:Remove();ctx.target=nil
                return string.format("before=%s AddFreeze(60)=%s after FLAG_ICE=%s repeated AddFreeze(60)=%s",
                    tostring(before),tostring(once),tostring(ice),tostring(twice))
            end)
        end
        for _,luck in ipairs({0,spec.luck,0}) do
            plan.section(key .. " / real status at luck=" .. luck)
            plan.act(function(player) S.collectible(player,CollectibleType.COLLECTIBLE_LUCKY_FOOT,luck) end)
            plan.wait(4)
            plan.act(function(player,ctx)
                ctx.target=H.target(player)
                ctx.target.Position=player.Position+Vector(0,100)
            end)
            plan.waitUntil(function(_,ctx) return H.targetReady(ctx.target) end,30,"status target finishes native initialization")
            plan.act(function(player,ctx)
                local previous=(player:GetData()[spec.data] or {}).attackCount or 0
                H.shoot(player,spec.data,ctx,math.max(1,math.floor(15-player.Luck)-previous))
            end)
            plan.waitUntil(function(_,ctx) return ctx.shots.count>0 end,300,"real breath emitted")
            plan.act(function(player,ctx)
                H.stopShooting()
                ctx.attack=ctx.shots.entities[1]; H.isolateAttack(ctx.attack)
                ctx.target:ClearEntityFlags(EntityFlag.FLAG_FREEZE | EntityFlag.FLAG_NO_TARGET)
                ctx.target.EntityCollisionClass=EntityCollisionClass.ENTCOLL_ALL
                ctx.target.Position=ctx.attack.Position+ctx.attack.Velocity
                ctx.hp=ctx.target.HitPoints
                H.captureDamage(ctx, true)
            end)
            plan.waitUntil(function(_,ctx)
                if ctx.target.HitPoints>=ctx.hp then return false end
                ctx.statusAtHit=ctx.target:HasEntityFlags(EntityFlag[spec.flag])
                local getter=ctx.target[spec.countdown]
                ctx.statusCountdownAtHit=type(getter)=="function" and getter(ctx.target) or nil
                ctx.hitTime=Game():GetFrameCount()
                ctx.hitNpcFrame=ctx.target.FrameCount
                ctx.hitEvidence=H.damageEvidence(ctx)
                H.stopDamageCapture(ctx)
                if ctx.attack:Exists() then ctx.attack:Remove() end
                ctx.attack=nil
                return true
            end,30,"real breath damages enemy")
            plan.check("zero/guaranteed luck produces the correct actual status",function(_,ctx)
                return #ctx.hitCapture.hits==1 and ctx.hitCapture.foreignHits==0 and ctx.statusAtHit==(luck>0),
                    "status=" .. tostring(ctx.statusAtHit) .. " expected=" .. tostring(luck>0)
                    .. "; "..ctx.hitEvidence
            end)
            if luck>0 then
                plan.check("accepted hit starts the engine status countdown",function(_,ctx)
                    local remaining=ctx.statusCountdownAtHit
                    if remaining==nil then return nil,"engine countdown inspection unavailable" end
                    return remaining>0 and remaining<=spec.duration,
                        "remaining="..remaining.." maximum="..spec.duration
                end)
                plan.waitUntil(function(_,ctx) return Game():GetFrameCount()>=ctx.hitTime+spec.duration-5 end,spec.duration,"status remains near its intended duration")
                plan.check("status has not expired early",function(_,ctx) return ctx.target:HasEntityFlags(EntityFlag[spec.flag]),"expected active status" end)
                plan.wait(10)
                plan.check("status expires after its intended duration",function(_,ctx)
                    local getter=ctx.target[spec.countdown]
                    local remaining=type(getter)=="function" and getter(ctx.target) or nil
                    return not ctx.target:HasEntityFlags(EntityFlag[spec.flag]) and (remaining==nil or remaining<=0),
                        "elapsed="..(Game():GetFrameCount()-ctx.hitTime).." NPC updates="..(ctx.target.FrameCount-ctx.hitNpcFrame)
                            .." initial countdown="..tostring(ctx.statusCountdownAtHit).." remaining="..tostring(remaining)
                            .." expected expired status"
                end)
            end
            plan.act(function(_,ctx) ctx.target:Remove(); ctx.target=nil end)
        end
    end)
end

return S
