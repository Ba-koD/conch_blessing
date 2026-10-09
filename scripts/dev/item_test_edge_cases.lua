-- Description clauses that run inside their item's existing lifecycle bench.
-- These fixtures use actual pickups/NPCs; no item handler is invoked directly.
local H=require("scripts.dev.item_test_support")
local E={}

function E.initialCharge(plan,id)
    plan.section("first acquisition / actual pedestal and half charge")
    plan.act(function(player,ctx)
        local active=player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
        if active>0 then player:RemoveCollectible(active,true,ActiveSlot.SLOT_PRIMARY) end
        H.suppressRandomGoldenPedestals(ctx)
        ctx.pickup=H.pickup(player,id)
        ctx.pickup.Wait=0
        player.Position=ctx.pickup.Position
    end)
    plan.waitUntil(function(player)
        return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)==id and player:IsItemQueueEmpty()
    end,180,"natural first active acquisition finishes")
    plan.check("first acquisition really starts with six of twelve charges",function(player)
        local config=Isaac.GetItemConfig():GetCollectible(id)
        return config.MaxCharges==12 and player:GetActiveCharge(ActiveSlot.SLOT_PRIMARY)==6,
            "max="..tostring(config.MaxCharges).." charge="..player:GetActiveCharge(ActiveSlot.SLOT_PRIMARY)
    end)
    plan.act(function(player,ctx)
        player:RemoveCollectible(id,true,ActiveSlot.SLOT_PRIMARY)
        ctx.pickup=nil
    end)
    plan.wait(4)
    plan.require("unused active removal leaves no owned copy",function(player)
        return H.expect(player:GetCollectibleNum(id,true),0)
    end)
end

function E.swordCleave(plan,id)
    local kind=EntityType.ENTITY_FATTY
    local function living()
        local out={}
        for _,entity in ipairs(Isaac.FindByType(kind,0,0)) do
            local npc=entity:ToNPC()
            if npc and not npc:IsDead() then
                npc.CollisionDamage=0 -- fixture safety, including engine-created halves
                out[#out+1]=npc
            end
        end
        return out
    end
    local function spawn(ctx)
        local npc=Isaac.Spawn(kind,0,0,Game():GetRoom():GetCenterPos()+Vector(100,0),Vector.Zero,nil):ToNPC()
        assert(npc and type(npc.TrySplit)=="function","native TrySplit unavailable")
        npc.CollisionDamage=0
        ctx.splitOriginalHP=npc.MaxHitPoints
        ctx.splitOriginalSeed=npc.InitSeed
        Game():GetRoom():SetClear(false)
        return npc
    end
    plan.section("SEALED_DEMON_SWORD / actual cleaving, waves, removal")
    plan.require("native split support available",function()
        return REPENTOGON and REPENTOGON.Real or nil,"REPENTOGON TrySplit required"
    end)
    plan.act(function(player,ctx)
        assert(#living()==0,"unexpected monsters in cleave fixture")
        ctx.cleanupFns=ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns+1]=function()
            for _,npc in ipairs(living()) do npc:Remove() end
            if ctx.splitBoss and ctx.splitBoss:Exists() then ctx.splitBoss:Remove() end
        end
        player:AddCollectible(id,0,false)
    end)
    plan.wait(4)
    for wave=1,2 do
        plan.section("SEALED_DEMON_SWORD / spawn wave "..wave)
        plan.act(function(player,ctx)
            if wave==2 then player:AddCollectible(id,0,false) end
            spawn(ctx)
        end)
        plan.waitUntil(function() return #living()==2*wave end,60,"engine produces two halves for the new enemy")
        plan.check("new enemy halves retain forty percent of original maximum HP",function(_,ctx)
            for _,npc in ipairs(living()) do
                if not H.near(npc.MaxHitPoints,ctx.splitOriginalHP*0.4) then
                    return false,"HP="..npc.MaxHitPoints.." expected="..ctx.splitOriginalHP*0.4
                end
            end
            return true,"two halves per original, even with stacked copies"
        end)
        plan.wait(12)
        plan.check("existing halves are never split or damaged again",function(_,ctx)
            local enemies=living()
            if #enemies~=2*wave then return false,"living halves="..#enemies.." expected="..2*wave end
            for _,npc in ipairs(enemies) do
                if not H.near(npc.HitPoints,npc.MaxHitPoints) then return false,"half unexpectedly lost HP" end
            end
            return true,"stable halves after twelve updates"
        end)
    end
    plan.act(function(player,ctx)
        ctx.splitBoss=Isaac.Spawn(EntityType.ENTITY_MONSTRO,0,0,Game():GetRoom():GetCenterPos()+Vector(-100,0),Vector.Zero,nil):ToNPC()
        ctx.splitBossHp=ctx.splitBoss.HitPoints
    end)
    plan.wait(4)
    plan.check("boss is neither cleaved nor damaged",function(_,ctx)
        return ctx.splitBoss:Exists() and ctx.splitBoss:IsBoss() and ctx.splitBoss.HitPoints==ctx.splitBossHp,
            "boss HP unchanged"
    end)
    plan.act(function(player,ctx)
        ctx.splitBoss:Remove();ctx.splitBoss=nil
        for _,npc in ipairs(living()) do npc:Remove() end
        while player:HasCollectible(id) do player:RemoveCollectible(id) end
    end)
    plan.wait(4)
    plan.act(function(_,ctx) ctx.target=spawn(ctx) end)
    plan.wait(6)
    plan.check("new enemy remains whole after final item loss",function(_,ctx)
        local enemies=living()
        return #enemies==1 and enemies[1].InitSeed==ctx.splitOriginalSeed
            and H.near(enemies[1].MaxHitPoints,ctx.splitOriginalHP),"one unchanged original"
    end)
    plan.act(function(player,ctx)
        if ctx.target and ctx.target:Exists() then ctx.target:Remove() end
        ctx.target=nil
        Game():GetRoom():SetClear(true)
        -- A canonical split may emit a death event. Retain that real ledger;
        -- the following 300-kill evolution test continues from the observed count.
        ctx.swordDeaths=(H.save(player).sealedDemonSword or {}).killCount or 0
    end)
end

return E
