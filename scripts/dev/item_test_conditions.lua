local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

for key, nextKey in pairs({ F_MINUS="C_MINUS", C_MINUS="B_MINUS", B_MINUS="A_MINUS" }) do
    for _, golden in ipairs({false,true}) do
        S.add(key, "floor_evolution_" .. (golden and "golden" or "normal"), { conditions=true }, function(plan,id)
            local flag = golden and TrinketType.TRINKET_GOLDEN_FLAG or 0
            plan.act(function(player) player:AddTrinket(id+flag,false) end)
            plan.wait(4)
            H.hit(plan)
            S.newFloor(plan,2)
            plan.check("hit floor does not evolve the trinket", function(player)
                return player:GetTrinket(0)==id+flag, "held=" .. player:GetTrinket(0)
            end)
            S.newFloor(plan,3)
            plan.check("next clean floor evolves once and preserves golden state", function(player)
                local target = ConchBlessing.ItemData[nextKey].id+flag
                local found = player:GetTrinket(0)==target and 1 or 0
                for _, p in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TRINKET,target)) do found=found+1 end
                return player:GetTrinket(0)~=id+flag and found==1, "evolved copies=" .. found .. " expected=1"
            end)
        end)
    end
end

S.add("A_MINUS", "hit_demotes", {conditions=true}, function(plan,id)
    for _, flag in ipairs({0,TrinketType.TRINKET_GOLDEN_FLAG}) do
        plan.act(function(player)
            for slot=0,1 do local t=player:GetTrinket(slot); if t>0 then player:TryRemoveTrinket(t) end end
            for _, p in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TRINKET,-1)) do p:Remove() end
            player:AddTrinket(id+flag,false)
        end)
        plan.wait(4)
        H.hit(plan)
        plan.check("real hit demotes A to B preserving golden state", function(player)
            local target=ConchBlessing.ItemData.B_MINUS.id+flag
            return not player:HasTrinket(id) and (#Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_TRINKET,target)==1
                or player:GetTrinket(0)==target), "A removed and exactly one matching B returned"
        end)
        plan.check("A multiplier removed on demotion", function(player)
            for _, stat in ipairs({"Damage","Tears","Luck"}) do
                if H.entry(player,"itemMultipliers",id,stat) then return false,"orphan A multiplier: " .. stat end
            end
            return true,"all three A contributions released"
        end)
    end
end)

for key, spec in pairs({ TIME_POWER={"timepowertrinket","damageBonus",0.006},
    TIME_TEAR={"timeteartrinket","spsBonus",0.0066}, TIME_LUCK={"timelucktrinket","luckBonus",0.01} }) do
    S.add(key,"hit_pause_resume",{conditions=true},function(plan,id)
        local function bonus(player)
            return ConchBlessing[spec[1]].state.perPlayer[tostring(player:GetPlayerType())][spec[2]]
        end
        plan.section(key .. " / accelerated 1800-tick pause boundaries")
        plan.act(function(player,ctx) H.beginClock(ctx); player:AddTrinket(id,false) end)
        plan.wait(3)
        for cycle=1,2 do
            plan.section(key .. " / real hit " .. cycle .. ", accelerated deadline")
            plan.act(function(_,ctx) ctx.hitClock=H.clockNow() end)
            H.hit(plan)
            plan.act(function(player,ctx)
                ctx.pausedBonus=bonus(player)
                H.clockAt(ctx,ctx.hitClock+1799)
            end)
            plan.wait(1)
            plan.check("growth stays paused at tick 1799",function(player,ctx)
                return H.expect(bonus(player),ctx.pausedBonus)
            end)
            plan.act(function(_,ctx) H.clockAt(ctx,ctx.hitClock+1800) end)
            plan.wait(1)
            plan.check("exact deadline resumes one normal growth update",function(player,ctx)
                return H.expect(bonus(player)-ctx.pausedBonus,spec[3]/30)
            end)
            plan.act(function(player,ctx)
                ctx.resumedBonus=bonus(player); H.clockAt(ctx,ctx.hitClock+1801)
            end)
            plan.wait(1)
            plan.check("tick 1801 grows once without catching up skipped time",function(player,ctx)
                return H.expect(bonus(player)-ctx.resumedBonus,spec[3]/30)
            end)
        end
        plan.act(function(player,ctx)
            ctx.droppedStats=H.stats(player); player:TryRemoveTrinket(id)
            H.clockAt(ctx,H.clockNow()+1800)
        end)
        plan.wait(3)
        plan.check("dropping stops growth without removing earned stats",function(player,ctx)
            return H.sameStats(player,ctx.droppedStats)
        end)
    end)
end

S.add("TWO_FACED_PENNY","clean_and_hit_floors",{conditions=true},function(plan,id)
    plan.act(function(player) player:AddCollectible(id,0,false) end)
    plan.wait(4)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_D6,0,true) end)
    plan.wait(4)
    plan.check("active acquisition does not consume or duplicate the reserved reward",function(player)
        local saved=player:GetData().__twofacedpenny
        return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)==CollectibleType.COLLECTIBLE_D6
            and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_D6,true)==1
            and saved and saved.slots[1] and saved.slots[1].itemId==nil,
            "one D6 and an unclaimed Penny reward"
    end)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION,0,true) end)
    plan.wait(4)
    plan.check("next passive still receives its extra copy after the active",function(player)
        return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION,true),2)
    end)
    plan.act(function(player,ctx) ctx.before=player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION,true) end)
    S.newFloor(plan,2)
    plan.check("clean floor grants one reserved collectible",function(player,ctx)
        local ok,detail=H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION,true)-ctx.before,1)
        return ok and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_D6,true)==1,detail
    end)
    H.hit(plan)
    plan.act(function(player,ctx) ctx.before=player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION,true) end)
    S.newFloor(plan,3)
    plan.check("hit floor grants no extra collectible",function(player,ctx)
        return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_SAD_ONION,true),ctx.before)
    end)
end)

S.add("TIME_MONEY","bffs_period_and_penalty",{synergies=true,conditions=true},function(plan,id)
    plan.require("pickup spawn observer available",function() return ModCallbacks.MC_POST_PICKUP_INIT and true or nil,"requires pickup-init events" end)
    plan.act(function(player,ctx)
        H.beginClock(ctx)
        ctx.cycleStart=ConchBlessing.timemoney.state.perPlayer[tostring(player:GetPlayerType())].lastDropFrame
        player:AddCoins(80-player:GetNumCoins())
        ctx.coins=H.capturePickups(PickupVariant.PICKUP_COIN,true)
        player:AddCollectible(id,0,false)
    end)
    plan.waitUntil(function(_,ctx) return ctx.coins.count>=5 end,90,"five initial coins actually spawn")
    plan.check("acquisition spawns exactly five coins",function(_,ctx) return H.expect(ctx.coins.count,5) end)
    plan.section("TIME_MONEY / accelerated 1800-tick payout boundaries")
    for _, spec in ipairs({{bffs=0,coins=80,hits=0,count=4},{bffs=1,coins=80,hits=1,count=7},
        {bffs=2,coins=80,hits=0,count=8},{bffs=0,coins=0,hits=0,count=1}}) do
        plan.section("TIME_MONEY / BFFS=" .. spec.bffs .. " coins=" .. spec.coins .. " hits=" .. spec.hits)
        plan.act(function(player,ctx)
            for _, p in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COIN,-1)) do p:Remove() end
            S.collectible(player,CollectibleType.COLLECTIBLE_BFFS,spec.bffs)
            player:AddCoins(spec.coins-player:GetNumCoins())
            ctx.coins=H.capturePickups(PickupVariant.PICKUP_COIN,true)
        end)
        if spec.hits>0 then H.hit(plan) end
        plan.act(function(_,ctx) H.clockAt(ctx,ctx.cycleStart+1799) end)
        plan.wait(1)
        plan.check("no payout before tick 1800",function(_,ctx) return H.expect(ctx.coins.count,0) end)
        plan.act(function(_,ctx) H.clockAt(ctx,ctx.cycleStart+1800) end)
        plan.wait(1)
        plan.check("exact deadline spawns coins with BFFS, hit penalty and minimum",function(_,ctx)
            return H.expect(ctx.coins.count,spec.count)
        end)
        plan.act(function(_,ctx) H.clockAt(ctx,ctx.cycleStart+1801) end)
        plan.wait(1)
        plan.check("next tick does not duplicate the payout",function(_,ctx)
            return H.expect(ctx.coins.count,spec.count)
        end)
        plan.act(function(_,ctx) ctx.cycleStart=ctx.cycleStart+1800 end)
    end
    plan.act(function(player,ctx) player:RemoveCollectible(id); ctx.coins=H.capturePickups(PickupVariant.PICKUP_COIN,true) end)
    plan.act(function(_,ctx) H.clockAt(ctx,ctx.cycleStart+3601) end)
    plan.wait(2)
    plan.check("last removal prevents next scheduled payout",function(_,ctx) return H.expect(ctx.coins.count,0) end)
end,{"bffs"})

for key,spec in pairs({F_MINUS={Luck=5},C_MINUS={Luck=4,Tears=2},B_MINUS={Luck=3,Tears=3,Damage=3},
    TIME_POWER={stat="Damage",rate=0.006},TIME_TEAR={stat="Tears",rate=0.0066},TIME_LUCK={stat="Luck",rate=0.01}}) do
    S.add(key,"moms_box",{conditions=true,synergies=true},function(plan,id)
        -- Calibrate Mom's Box's own vanilla stat change before adding a trinket.
        plan.act(function(player) S.collectible(player,CollectibleType.COLLECTIBLE_MOMS_BOX,1) end)
        plan.wait(4)
        plan.act(function(player,ctx)
            ctx.boxDelta={}
            for stat,value in pairs(H.stats(player)) do ctx.boxDelta[stat]=value-ctx.base[stat] end
            S.collectible(player,CollectibleType.COLLECTIBLE_MOMS_BOX,0)
        end)
        plan.wait(4)
        for _,golden in ipairs({false,true}) do
            plan.act(function(player,ctx)
                ctx.trinketBase=H.stats(player)
                player:AddTrinket(id+(golden and TrinketType.TRINKET_GOLDEN_FLAG or 0),false)
            end)
            for _,box in ipairs({0,1,0}) do
                plan.act(function(player) S.collectible(player,CollectibleType.COLLECTIBLE_MOMS_BOX,box) end)
                plan.wait(4)
                if spec.rate then
                    plan.act(function(player,ctx) ctx.rateStart=H.stats(player)[spec.stat]; ctx.rateFrame=Game():GetFrameCount() end)
                    plan.wait(4)
                end
                plan.check("Mom's Box add/remove with " .. (golden and "golden" or "normal") .. " trinket, box=" .. box,function(player,ctx)
                    local copies=(golden and 2 or 1)+box
                    local stats=H.stats(player)
                    if spec.rate then
                        return H.expect(stats[spec.stat]-ctx.rateStart,spec.rate*copies*(Game():GetFrameCount()-ctx.rateFrame)/30)
                    end
                    for stat,amount in pairs(spec) do
                        local expected=ctx.trinketBase[stat]+amount*copies+ctx.boxDelta[stat]*box
                        if not H.near(stats[stat],expected) then return false,stat .. " actual=" .. stats[stat] .. " expected=" .. expected end
                    end
                    return true,"all granted stats track the independent normal/golden/Box table"
                end)
            end
            plan.act(function(player) player:TryRemoveTrinket(id+(golden and TrinketType.TRINKET_GOLDEN_FLAG or 0)) end)
            plan.wait(4)
        end
    end)
end

return S
