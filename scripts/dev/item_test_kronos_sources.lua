local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local cases = require("scripts.dev.kronos_synergy_cases")

local function manualGrants(player,ctx)
    local expected={}
    for _,row in pairs(ctx.manualIds) do
        local spec=row.spec
        if spec and spec.grant then
            local id=assert(CollectibleType["COLLECTIBLE_" .. spec.grant],"unresolved Manual conversion")
            expected[id]=(expected[id] or 0)+(spec.cap==0 and row.count or math.min(row.count,spec.cap))
        end
    end
    for id,wanted in pairs(expected) do
        local actual=player:GetCollectibleNum(id,true)
        if actual~=wanted then return false,"conversion " .. id .. " actual=" .. actual .. " expected=" .. wanted end
    end
    return true,"actual conversion inventory matches the independently listed familiar grants"
end

local function roomEntry(plan)
    plan.act(function(_,ctx)
        ctx.beforeRooms=ctx.rooms
        local level=Game():GetLevel()
        Game():StartRoomTransition(level:GetCurrentRoomIndex(),Direction.NO_DIRECTION,RoomTransitionAnim.FADE)
    end)
    plan.waitUntil(function(_,ctx) return ctx.rooms>ctx.beforeRooms end,150,"real room-entry callback")
    plan.wait(4)
end

local function bobby(plan,id)
    plan.act(function(player,ctx)
        player:AddCollectible(id,0,false)
        ctx.baseTears=H.stats(player).Tears
        player:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,0,false)
    end)
    plan.waitUntil(function(player) return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,true)==0 end,120,"Bobby absorbed")
    plan.wait(4)
end

S.add("KRONOS","synergy_box_of_friends",{synergies=true,conditions=true},function(plan,id)
    bobby(plan,id)
    plan.require("Mongo Minisaac API available",function(player)
        return type(player.AddMinisaac)=="function" or nil,"AddMinisaac capability"
    end)
    plan.act(function(player,ctx)
        ctx.boxFamiliars={CollectibleType.COLLECTIBLE_BROTHER_BOBBY,CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL,
            CollectibleType.COLLECTIBLE_PASCHAL_CANDLE,CollectibleType.COLLECTIBLE_SACK_OF_PENNIES,CollectibleType.COLLECTIBLE_MONGO_BABY}
        for index=2,#ctx.boxFamiliars do player:AddCollectible(ctx.boxFamiliars[index],0,false) end
    end)
    plan.waitUntil(function(player,ctx)
        for _,familiarId in ipairs(ctx.boxFamiliars) do
            if player:GetCollectibleNum(familiarId,true)>0 then return false end
        end
        return H.near(H.addition(player,"itemAdditions",id,"Damage"),10)
    end,120,"all five real familiars absorbed")
    plan.wait(4)
    local function mongoCount(player)
        local count=0
        for _,e in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,FamiliarVariant.MINISAAC,-1)) do
            local f=e:ToFamiliar()
            if f and f.Player and GetPtrHash(f.Player)==GetPtrHash(player) and f:GetData().__kronosMongoMinisaac then count=count+1 end
        end
        return count
    end
    local function checkStats(multiplier,earned)
        plan.check("Box x" .. multiplier .. " actual damage, tears and speed",function(player,ctx)
            local actual=H.stats(player)
            local damage=ctx.base.Damage+10*multiplier
            local tears=ctx.baseTears+(2+earned)*multiplier
            local speed=ctx.base.Speed+0.3*multiplier
            return H.near(actual.Damage,damage) and H.near(actual.Tears,tears) and H.near(actual.Speed,speed),
                string.format("damage=%.4f expected=%.4f; tears=%.4f expected=%.4f; speed=%.4f expected=%.4f",
                    actual.Damage,damage,actual.Tears,tears,actual.Speed,speed)
        end)
    end
    H.clearAward(plan,true)
    checkStats(1,0.03)
    plan.act(function(player,ctx)
        player:AddCoins(17-player:GetNumCoins())
        ctx.boxCoins=player:GetNumCoins()
        ctx.boxDollars=player:GetCollectibleNum(CollectibleType.COLLECTIBLE_DOLLAR,true)
        ctx.foreignMini=player:AddMinisaac(player.Position,true)
        assert(ctx.foreignMini,"unrelated Minisaac fixture failed")
    end)
    plan.require("conversion reward exists before Box",function(_,ctx) return H.expect(ctx.boxDollars,1) end)
    plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS,UseFlag.USE_NOANIM,-1) end)
    plan.wait(4)
    checkStats(2,0.03)
    plan.check("Box creates exactly one additional Mongo Minisaac",function(player) return H.expect(mongoCount(player),2) end)
    plan.check("Box never grants another conversion item or acquisition coins",function(player,ctx)
        local dollars=player:GetCollectibleNum(CollectibleType.COLLECTIBLE_DOLLAR,true)
        return dollars==ctx.boxDollars and player:GetNumCoins()==ctx.boxCoins,
            "Dollar=" .. dollars .. " expected=1; coins=" .. player:GetNumCoins() .. " expected=" .. ctx.boxCoins
    end)
    plan.check("Box does not create a Demon Baby",function() return H.expect(#Isaac.FindByType(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DEMON_BABY,-1),0) end)
    H.clearAward(plan,false)
    checkStats(2,0.06)
    plan.check("Box does not multiply permanent Paschal earnings",function()
        return H.expect(ConchBlessing.SaveManager.GetRunSave(nil).kronos.paschalHundredths,6)
    end)
    -- Travel to a different native room, then return to the original one. Keep
    -- collectible stock uncollidable through the existing test pickup observer.
    plan.act(function(player,ctx)
        local level=Game():GetLevel()
        ctx.boxOrigin=level:GetCurrentRoomIndex()
        ctx.boxOriginList=level:GetCurrentRoomDesc().ListIndex
        local rooms=level:GetRooms()
        local target
        for index=0,rooms.Size-1 do
            local desc=rooms:Get(index)
            if desc.Data and desc.Data.Type==RoomType.ROOM_TREASURE then target=desc; break end
        end
        assert(target,"no native treasure room for Box exit/reentry")
        ctx.boxDestination=target.ListIndex
        Game():StartRoomTransition(target.SafeGridIndex,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player)
    end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.boxDestination end,180,"leave the Box room")
    plan.wait(4)
    checkStats(1,0.06)
    plan.check("room exit removes only the extra owned Mongo copies",function(player,ctx)
        return mongoCount(player)==1 and ctx.foreignMini:Exists(),"owned Minisaacs=" .. mongoCount(player) .. " expected=1; unrelated alive=" .. tostring(ctx.foreignMini:Exists())
    end)
    plan.act(function(player,ctx) Game():StartRoomTransition(ctx.boxOrigin,Direction.NO_DIRECTION,RoomTransitionAnim.FADE,player) end)
    plan.waitUntil(function(_,ctx) return Game():GetLevel():GetCurrentRoomDesc().ListIndex==ctx.boxOriginList end,180,"return to the original Box room")
    plan.wait(4)
    checkStats(1,0.06)
    plan.act(function(player) player:UseActiveItem(CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS,UseFlag.USE_NOANIM,-1) end)
    plan.wait(4)
    checkStats(2,0.06)
    plan.act(function(player) player:RemoveCollectible(id) end)
    plan.waitUntil(function(player,ctx)
        for _,familiarId in ipairs(ctx.boxFamiliars) do
            if player:GetCollectibleNum(familiarId,true)~=1 then return false end
        end
        return true
    end,120,"Kronos loss returns each original familiar once")
    plan.check("Kronos loss removes Box's damage and extra Mongo copies",function(player,ctx)
        return H.near(H.addition(player,"itemAdditions",id,"Damage"),0) and mongoCount(player)<=1 and ctx.foreignMini:Exists(),
            "damage contribution=" .. H.addition(player,"itemAdditions",id,"Damage") .. " expected=0; owned Minisaacs=" .. mongoCount(player)
    end)
    plan.check("Kronos loss takes back the single conversion item",function(player)
        return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_DOLLAR,true),0)
    end)
end,{"box_of_friends"})

S.add("KRONOS","synergy_sacrificial_altar",{synergies=true,conditions=true},function(plan,id)
    bobby(plan,id)
    plan.act(function(player) player:AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,0,false) end)
    plan.waitUntil(function(player) return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,true)==0 end,120,"second Bobby absorbed")
    plan.act(function(player,ctx)
        ctx.items=H.capturePickups(PickupVariant.PICKUP_COLLECTIBLE,true)
        player:UseActiveItem(CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR,UseFlag.USE_NOANIM,-1)
    end)
    plan.waitUntil(function(_,ctx) return ctx.items.count>=2 end,120,"two real devil pedestals spawned")
    plan.check("Altar consumes both absorbed copies and their stat bonuses",function(player,ctx)
        return ctx.items.count==2 and H.near(H.stats(player).Tears,ctx.baseTears)
            and H.near(H.addition(player,"itemAdditions",id,"Damage"),0),"pedestals=" .. ctx.items.count .. "; tears=" .. H.stats(player).Tears
    end)
    plan.act(function(player) player:RemoveCollectible(id) end)
    plan.wait(4)
    plan.check("sacrificed familiars are not returned on Kronos loss",function(player)
        return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,true),0)
    end)
end,{"sacrificial_altar"})

S.add("KRONOS","synergy_trinket_the_twins",{synergies=true,conditions=true},function(plan,id)
    bobby(plan,id)
    plan.act(function(player,ctx) player:AddTrinket(TrinketType.TRINKET_THE_TWINS,false); ctx.doubled=false; ctx.normal=false end)
    for _=1,24 do
        roomEntry(plan)
        plan.check("Twins room effect is exactly one Bobby or double Bobby",function(player,ctx)
            local bonus=H.stats(player).Tears-ctx.baseTears
            ctx.doubled=ctx.doubled or H.near(bonus,4)
            ctx.normal=ctx.normal or H.near(bonus,2)
            return H.near(bonus,2) or H.near(bonus,4),"actual tear bonus=" .. bonus .. " expected=2 or 4"
        end)
    end
    plan.check("both stochastic outcomes observed",function(_,ctx)
        if not ctx.doubled or not ctx.normal then return nil,"24 entries inconclusive; probability calibration belongs to conch_test rng" end
        return true,"both actual outcomes; this is not a statistical proof of 50%"
    end)
    plan.act(function(player) player:TryRemoveTrinket(TrinketType.TRINKET_THE_TWINS) end)
    roomEntry(plan)
    plan.check("dropping Twins prevents doubling in the next room",function(player,ctx) return H.expect(H.stats(player).Tears,ctx.baseTears+2) end)
end,{"trinket_the_twins"})

for _,order in ipairs({"before","after"}) do
    S.add("KRONOS","manual_" .. order,{synergies=true,conditions=true},function(plan,id)
        plan.require("temporary effect enumeration available",function(player)
            return type(player:GetEffects().GetEffectsList)=="function" or nil,"GetEffectsList capability"
        end)
        plan.act(function(player,ctx)
            if order=="after" then player:AddCollectible(id,0,false) end
            player:UseActiveItem(CollectibleType.COLLECTIBLE_MONSTER_MANUAL,UseFlag.USE_NOANIM,-1)
            ctx.manualIds={}; ctx.manualExpected=0; ctx.excludedSummons=0
            local list=player:GetEffects():GetEffectsList()
            for i=0,list.Size-1 do
                local effect=list:Get(i)
                local item=effect and effect.Item
                if item and item.Type==ItemType.ITEM_FAMILIAR and effect.Count>0 then
                    local spec
                    for name,value in pairs(cases) do
                        if CollectibleType["COLLECTIBLE_" .. string.upper(name)]==item.ID then spec=value; break end
                    end
                    if spec and spec.excluded then ctx.excludedSummons=ctx.excludedSummons+effect.Count
                    else
                        ctx.manualIds[item.ID]={count=effect.Count,spec=spec}
                        ctx.manualExpected=ctx.manualExpected+effect.Count
                    end
                end
            end
        end)
        plan.require("Manual selected an absorbable familiar",function(_,ctx)
            if ctx.manualExpected==0 and ctx.excludedSummons>0 then return nil,"random use selected only excluded familiars; rerun this scenario" end
            return ctx.manualExpected>0,"independent engine effect count=" .. ctx.manualExpected
        end)
        plan.wait(4)
        if order=="before" then
            plan.require("Manual produced a vanilla familiar before acquisition",function()
                return #Isaac.FindByType(EntityType.ENTITY_FAMILIAR,-1,-1)>0,"actual familiar entity before Kronos"
            end)
            plan.act(function(player) player:AddCollectible(id,0,false) end)
        end
        plan.waitUntil(function(player) return H.addition(player,"itemAdditions",id,"Damage")>0 end,120,"Manual familiar absorbed through production updates")
        plan.act(function(player,ctx) ctx.absorbDamage=H.addition(player,"itemAdditions",id,"Damage"); ctx.manualStats=H.stats(player) end)
        plan.check("each real Manual summon contributes exactly two damage",function(_,ctx)
            return H.expect(ctx.absorbDamage,ctx.manualExpected*2)
        end)
        plan.check("Manual actually grants its promised converted items",manualGrants)
        roomEntry(plan)
        plan.check("room entry does not re-credit Manual",function(player,ctx)
            return H.expect(H.addition(player,"itemAdditions",id,"Damage"),ctx.absorbDamage)
        end)
        plan.check("room entry keeps consumed temporary effects absent",function(player,ctx)
            for familiarId in pairs(ctx.manualIds) do
                if player:GetEffects():GetCollectibleEffectNum(familiarId)~=0 then return false,"temporary effect returned: " .. familiarId end
            end
            return true,"no engine familiar effect restored"
        end)
        plan.check("Manual converted items survive room entry without duplication",manualGrants)
        S.newFloor(plan,2)
        plan.check("new floor expires temporary absorption damage",function(player)
            return H.expect(H.addition(player,"itemAdditions",id,"Damage"),0)
        end)
        plan.check("new floor removes temporary granted stats",function(player,ctx) return H.sameStats(player,ctx.base) end)
        plan.check("new floor removes temporary converted items",function(player,ctx)
            for _,row in pairs(ctx.manualIds) do
                if row.spec and row.spec.grant then
                    local grant=CollectibleType["COLLECTIBLE_" .. row.spec.grant]
                    if player:GetCollectibleNum(grant,true)~=0 then return false,"temporary grant remained: " .. row.spec.grant end
                end
            end
            return true,"temporary conversion inventory cleared"
        end)
    end,order=="before" and {"monster_manual"} or nil)
end

return S
