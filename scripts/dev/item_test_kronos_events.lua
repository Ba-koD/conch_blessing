-- Real engine event paths for absorbed abilities; no item callback calls.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local E = {}
local hurt = {holy_water=true,dry_baby=true,milk=true,bird_cage=true,mystery_egg=true,my_shadow=true,hallowed_ground=true}
local clears = {bum_friend=1,lil_chest=1,relic=6,mystery_sack=6,rune_bag=7,paschal_candle=1}

local function whitePoop()
    local room, count = Game():GetRoom(), 0
    for i=0,room:GetGridSize()-1 do
        local grid=room:GetGridEntity(i)
        if grid and grid:GetType()==GridEntityType.GRID_POOP and grid:GetVariant()==6 then count=count+1 end
    end
    return count
end

function E.build(plan,name,give)
    if hurt[name] then
        plan.require("confirmed player-damage callback available",function()
            return ModCallbacks.MC_POST_ENTITY_TAKE_DMG and true or nil,"needs confirmed damage events"
        end)
        local copies=({dry_baby=4,holy_water=5,mystery_egg=6,my_shadow=4})[name] or 2
        if copies>2 then give(plan,name,copies-2) end
        plan.act(function(player,ctx)
            ctx.beforeTears=H.stats(player).Tears
            ctx.beforePoop=whitePoop()
            ctx.preHurtEntities={}
            for _,e in ipairs(Isaac.GetRoomEntities()) do ctx.preHurtEntities[GetPtrHash(e)]=true end
            ctx.target=H.target(player,true); ctx.target.Position=player.Position+Vector(60,0)
            ctx.outsideTarget=H.target(player,true); ctx.outsideTarget.Position=player.Position+Vector(170,0)
            ctx.hp,ctx.farHp=ctx.target.HitPoints,ctx.outsideTarget.HitPoints
        end)
        H.hit(plan)
        plan.check("confirmed hit produces the promised ability",function(player,ctx)
            if name=="milk" then return H.expect(H.stats(player).Tears,ctx.beforeTears+copies) end
            if name=="hallowed_ground" then return H.expect(whitePoop()-ctx.beforePoop,1) end
            if name=="bird_cage" then
                return H.near(ctx.hp-ctx.target.HitPoints,45*copies) and ctx.farHp==ctx.outsideTarget.HitPoints,
                    "near HP loss=" .. (ctx.hp-ctx.target.HitPoints) .. " expected=" .. 45*copies .. "; far=" .. (ctx.farHp-ctx.outsideTarget.HitPoints)
            end
            if name=="dry_baby" then
                return H.near(ctx.hp-ctx.target.HitPoints,40) and H.near(ctx.farHp-ctx.outsideTarget.HitPoints,40),
                    "Necronomicon HP loss: near=" .. (ctx.hp-ctx.target.HitPoints) .. " far=" .. (ctx.farHp-ctx.outsideTarget.HitPoints) .. " expected=40 each"
            end
            ctx.spawned={}
            for _,e in ipairs(Isaac.GetRoomEntities()) do
                if not ctx.preHurtEntities[GetPtrHash(e)] then
                    local matches=name=="holy_water" and e.Type==EntityType.ENTITY_EFFECT and e.Variant==EffectVariant.PLAYER_CREEP_HOLYWATER
                        or name=="mystery_egg" and e.Type==EntityType.ENTITY_ATTACKFLY and e:HasEntityFlags(EntityFlag.FLAG_CHARM)
                        or name=="my_shadow" and e.Type==EntityType.ENTITY_CHARGER and e.Variant==2 and e:HasEntityFlags(EntityFlag.FLAG_CHARM)
                    if matches then ctx.spawned[#ctx.spawned+1]=e end
                end
            end
            return H.expect(#ctx.spawned,({holy_water=4,mystery_egg=5,my_shadow=3})[name])
        end)
        plan.act(function(_,ctx)
            ctx.target:Remove(); ctx.outsideTarget:Remove(); ctx.target=nil; ctx.outsideTarget=nil
        end)
        if name=="holy_water" then
            plan.act(function(_,ctx) for i=2,#(ctx.spawned or {}) do ctx.spawned[i]:Remove() end end)
            H.sampleAttackDamage(plan,function(player) return player.Damage*0.66 end,function(_,ctx) return ctx.spawned[1] end)
        elseif name=="milk" then
            H.hit(plan)
            plan.check("second hit does not add Milk again",function(player,ctx) return H.expect(H.stats(player).Tears,ctx.beforeTears+copies) end)
            S.newFloor(plan,2)
            plan.check("new floor resets Milk's temporary bonus",function(player,ctx) return H.expect(H.stats(player).Tears,ctx.beforeTears) end)
        end
    elseif clears[name] then
        plan.require("actual pickup observer available",function() return ModCallbacks.MC_POST_PICKUP_INIT and true or nil,"pickup-init capability" end)
        if name=="bum_friend" or name=="lil_chest" then give(plan,name,8) end -- 100%, no probabilistic timeout
        plan.act(function(player,ctx) ctx.clearTears=H.stats(player).Tears end)
        local interval=clears[name]
        for index=1,interval do
            -- Include a real enemy-death room clear, then exercise the engine's
            -- award operation directly for the remaining interval boundaries.
            H.clearAward(plan,index==1)
            plan.check("award " .. index .. " respects its reward interval",function(player,ctx)
                if name=="paschal_candle" then return H.expect(H.stats(player).Tears,ctx.clearTears+0.06*index) end
                local rows=H.awardPickups()
                local expected=index==interval and ((name=="bum_friend" or name=="lil_chest") and 1 or 2) or 0
                if #rows~=expected then return H.expect(#rows,expected) end
                for _,row in ipairs(rows) do
                    if name=="lil_chest" and row.variant~=PickupVariant.PICKUP_CHEST then return false,"wrong chest variant=" .. row.variant end
                    if name=="relic" and (row.variant~=PickupVariant.PICKUP_HEART or row.subtype~=HeartSubType.HEART_SOUL) then return false,"expected soul hearts" end
                    if name=="rune_bag" and row.variant~=PickupVariant.PICKUP_TAROTCARD then return false,"expected rune pickup" end
                end
                return true,"actual callback-spawned pickups=" .. #rows .. " (vanilla clear award excluded)"
            end)
        end
    elseif name=="lost_soul" then
        plan.act(function(_,ctx) ctx.hearts=H.capturePickups(PickupVariant.PICKUP_HEART,true) end)
        S.newFloor(plan,2)
        local function eternal(ctx)
            local n=0
            for _,row in ipairs(ctx.hearts.rows) do if row.subtype==HeartSubType.HEART_ETERNAL then n=n+1 end end
            return n
        end
        plan.check("clean floor spawns one eternal heart per copy",function(_,ctx) return H.expect(eternal(ctx),2) end)
        H.hit(plan)
        plan.act(function(_,ctx) ctx.hearts=H.capturePickups(PickupVariant.PICKUP_HEART,true) end)
        S.newFloor(plan,3)
        plan.check("a hit cancels the next floor reward",function(_,ctx) return H.expect(eternal(ctx),0) end)
    elseif name=="gemini" then
        plan.act(function(player,ctx)
            ctx.target=H.target(player,true)
            ctx.target:AddEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK | EntityFlag.FLAG_NO_PHYSICS_KNOCKBACK)
            ctx.target.EntityCollisionClass=EntityCollisionClass.ENTCOLL_ALL
            ctx.target.Position=player.Position
            ctx.hp=ctx.target.HitPoints
        end)
        plan.waitUntil(function(player,ctx)
            ctx.target.Position=player.Position
            if ctx.target.HitPoints==ctx.hp then return false end
            ctx.firstContact=Game():GetFrameCount(); ctx.contactHp=ctx.target.HitPoints
            return true
        end,60,"actual player/enemy collision deals contact damage")
        plan.waitUntil(function(player,ctx)
            ctx.target.Position=player.Position
            if Game():GetFrameCount()<ctx.firstContact+29 then return false end
            ctx.contactLoss=ctx.hp-ctx.target.HitPoints
            ctx.target.Position=player.Position+Vector(180,0)
            ctx.hpOutside=ctx.target.HitPoints
            return true
        end,40,"one full second of real contact")
        plan.check("two copies deal 12 HP over one second of contact",function(_,ctx) return H.expect(ctx.contactLoss,12) end)
        plan.wait(15)
        plan.check("separation stops contact damage",function(_,ctx) return H.expect(ctx.target.HitPoints,ctx.hpOutside) end)
        plan.act(function(_,ctx) ctx.target:Remove(); ctx.target=nil end)
    end
end

return E
