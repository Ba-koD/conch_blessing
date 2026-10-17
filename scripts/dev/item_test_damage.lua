local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

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
