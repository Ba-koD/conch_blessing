local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local sample

-- Observe actual output, never infer an eye from the player's later eye value.
ConchBlessing:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
    if not sample then return end
    local p=tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not p or GetPtrHash(p)~=sample.owner then return end
    local blocked=ConchBlessing.hemispatialneglect.isBlockedTear(tear)
    sample.total=sample.total+1
    sample[blocked and "blocked" or "kept"]=sample[blocked and "blocked" or "kept"]+1
    if blocked then sample.blockedEntities[#sample.blockedEntities+1]=tear end
    local frame=Game():GetFrameCount()
    sample.first=sample.first or frame; sample.last=frame
end)

S.add("HEMISPATIAL_NEGLECT", "right_eye", {conditions=true,damage=true}, function(plan,id)
    plan.section("HEMISPATIAL_NEGLECT / appearance (manual only)",
        "Front: Isaac's right half hidden; back: opposite screen half hidden; left-facing: normal; right-facing: outline only. Check costumes/blink and full restoration after loss. Gameplay PASS does not verify this image.")
    plan.require("right-tear suppression capabilities and XML loaded",function()
        return ConchBlessing.hemispatialneglect.canRestrictTears() and true or nil,
            "full game restart and REPENTOGON tear-params/pre-update callbacks required"
    end)
    plan.act(function(_,ctx)
        ctx.cleanupFns=ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns+1]=function() sample=nil; H.stopShooting() end
        ctx.eyeControls={}
    end)
    local fixtures={
        {"ordinary"}, {"multishot",CollectibleType.COLLECTIBLE_MUTANT_SPIDER},
        {"dual_eyes",CollectibleType.COLLECTIBLE_THE_WIZ},
        {"eye_drops",CollectibleType.COLLECTIBLE_EYE_DROPS},
        {"high_tears",CollectibleType.COLLECTIBLE_SOY_MILK},
    }
    for _,fixture in ipairs(fixtures) do
        for _,state in ipairs({{label="control",count=0},{label="owned",count=1},
            {label="stacked",count=2},{label="removed",count=0}}) do
            plan.section("HEMISPATIAL_NEGLECT / "..fixture[1].." / "..state.label)
            plan.act(function(player)
                for _,row in ipairs(fixtures) do if row[2] then S.collectible(player,row[2],0) end end
                if fixture[2] then S.collectible(player,fixture[2],1) end
                S.collectible(player,id,state.count)
                H.isolateAttack(nil)
            end)
            plan.wait(2)
            plan.waitUntil(function(player) return player.FireDelay<=0 end,90,"native firing cooldown ready")
            plan.act(function(player,ctx)
                sample={owner=GetPtrHash(player),total=0,blocked=0,kept=0,blockedEntities={}}
                ctx.eyeSample=sample
                H.shoot(player,"$tears",ctx,6)
            end)
            plan.waitUntil(function(_,ctx) return ctx.shots.triggers>=6 end,240,"six actual weapon triggers")
            plan.act(function() H.stopShooting(); sample=nil end)
            plan.check("right tear output omitted; left output and native cadence preserved",function(_,ctx)
                local actual=ctx.eyeSample
                if state.label=="control" then
                    ctx.eyeControls[fixture[1]]={total=actual.total,span=(actual.last or 0)-(actual.first or 0)}
                    return actual.total>0 and actual.blocked==0,"control tears="..actual.total
                end
                local base=ctx.eyeControls[fixture[1]]
                if not base or base.total==0 then return false,"no independent vanilla control" end
                local expectedKept=state.count>0 and base.total/2 or base.total
                local expectedBlocked=base.total-expectedKept
                local survivors=0
                for _,tear in ipairs(actual.blockedEntities) do if tear:Exists() then survivors=survivors+1 end end
                local span=(actual.last or 0)-(actual.first or 0)
                return actual.kept==expectedKept and actual.blocked==expectedBlocked and survivors==0
                    and math.abs(span-base.span)<=2,
                    string.format("kept expected=%s actual=%s; blocked expected=%s actual=%s; remaining=%s; firing span control=%s actual=%s",
                        expectedKept,actual.kept,expectedBlocked,actual.blocked,survivors,base.span,span)
            end)
        end
    end
    plan.act(function(player)
        for _,row in ipairs(fixtures) do if row[2] then S.collectible(player,row[2],0) end end
    end)
    -- Independent baseline HP loss, then one surviving tear from two eye turns.
    for _,count in ipairs({0,1,2,0}) do
        plan.act(function(player,ctx)
            S.collectible(player,id,count); H.isolateAttack(nil)
            ctx.target=H.target(player)
        end)
        plan.wait(4)
        H.fireWeaponAtTarget(plan,"tear",count>0 and 2 or 1)
        plan.require("real enemy HP loss matches the intended damage multiplier",function(_,ctx)
            return H.expect(ctx.weaponHpLoss, ctx.base.Damage * 2^count)
        end)
        plan.act(function(_,ctx) ctx.target:Remove(); ctx.target=nil end)
    end
end)

S.add("AR_GLASSES", "choice", {conditions=true}, function(plan,id)
    plan.require("next-use answer reservation API",function()
        local api=MagicConch and MagicConch.API
        return api and type(api.PreviewResult)=="function" and type(api.TriggerMagicConch)=="function"
            and type(api.GetLastResult)=="function" and type(api.GetState)=="function"
            and type(api.ReserveNextResult)=="function" and type(api.GetNextResultReservation)=="function"
            and type(api.ClearNextResultReservation)=="function" or nil,
            "current Magic Conch provider required"
    end)
    plan.act(function(player,ctx)
        player:AddCollectible(id,0,false)
        local c=MagicConch.Config
        local enabled,timing,attempts=c.enabled,c.timing,c.attemptsPerRoom
        ctx.forced=c.forcedReply
        ctx.cleanupFns=ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns+1]=function()
            c.enabled,c.timing,c.attemptsPerRoom=enabled,timing,attempts
            ConchBlessing.arglasses.reset()
        end
        c.enabled,c.attemptsPerRoom=true,0
        c.timing={shake=1,wait=1,display=1,cooldown=0}
        ConchBlessing.arglasses.reset()
    end)
    for _,kind in ipairs({"positive","negative","neutral"}) do
        plan.waitUntil(function() return MagicConch.API.GetState()=="idle" end,180,"Conch idle")
        plan.wait(12)
        plan.act(function(_,ctx)
            ctx.before=MagicConch:GetCurrentRoomUsage()
            ctx.reserved=ConchBlessing.arglasses.cycle()
            ctx.preview=ConchBlessing.arglasses.getSelection()
            ctx.afterSelection=MagicConch:GetCurrentRoomUsage()
        end)
        plan.require("C choice reserves without activating or consuming a use",function(_,ctx)
            return ctx.reserved and ctx.preview and ctx.preview.type==kind
                and ctx.afterSelection==ctx.before and MagicConch.API.GetState()=="idle",
                "selected="..kind.." usage before="..ctx.before.." after="..ctx.afterSelection
        end)
        plan.act(function(_,ctx)
            ctx.result=MagicConch.API.TriggerMagicConch("ConchBlessing ordinary-use test")
            ctx.success=ctx.result and ctx.result.success
        end)
        plan.require("selected answer accepted exactly once",function(_,ctx)
            return ctx.success and ctx.preview and ctx.preview.type==kind
                and MagicConch:GetCurrentRoomUsage()==ctx.before+1,
                "selected="..kind.." result="..tostring(ctx.result and ctx.result.reason)
        end)
        plan.waitUntil(function() return MagicConch.API.GetState()=="idle" end,180,"actual answer completes")
        plan.check("actual answer equals selection; persistent forced setting unchanged",function(_,ctx)
            local result=MagicConch.API.GetLastResult()
            return result and result.type==kind and result.text==ctx.preview.text
                and MagicConch.Config.forcedReply==ctx.forced, "actual="..tostring(result and result.text)
        end)
    end
end)
return S
