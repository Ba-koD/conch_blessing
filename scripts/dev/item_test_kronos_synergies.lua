local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local cases = require("scripts.dev.kronos_synergy_cases")
local Events = require("scripts.dev.item_test_kronos_events")
local specialSources = { box_of_friends=true, monster_manual=true, sacrificial_altar=true, trinket_the_twins=true }
local statusFlags = { lil_haunt="FLAG_FEAR", little_gish="FLAG_SLOW", intruder="FLAG_SLOW", worm_friend="FLAG_SLOW" }
local procs = {
    rotten_baby={copies=2,variant="BLUE_FLY"}, ["7_seals"]={copies=2,variant="BLUE_FLY"},
    juicy_sack={copies=2,variant="BLUE_SPIDER"}, sissy_longlegs={copies=2,variant="BLUE_SPIDER"},
    daddy_longlegs={copies=10}, moms_razor={copies=10,flag="FLAG_BLEED_OUT"},
    cube_baby={copies=10,flag="FLAG_FREEZE"}, lil_spewer={copies=4},
}

local function familiarId(name)
    return assert(CollectibleType["COLLECTIBLE_" .. string.upper(name)], "unresolved familiar: " .. name)
end

local function give(plan, name, amount)
    plan.act(function(player,ctx)
        local id = familiarId(name)
        ctx.totalGiven = (ctx.totalGiven or 0) + amount
        for _=1,amount do player:AddCollectible(id,0,false) end
    end)
    plan.waitUntil(function(player) return player:GetCollectibleNum(familiarId(name),true)==0 end,120,"actual familiar absorbed: " .. name)
    plan.wait(2)
end

local function hitEnemy(plan)
    plan.act(function(player,ctx)
        H.isolateAttack()
        ctx.target=H.target(player)
        ctx.attackDamage=player.Damage
    end)
    H.fireWeaponAtTarget(plan,"tear")
end

local function blockTest(plan,name)
    local count=math.ceil(1/cases[name].block)
    give(plan,name,count-(procs[name] and procs[name].copies or 2))
    plan.act(function(player,ctx)
        ctx.health=player:GetHearts()+player:GetSoulHearts()
        ctx.blocks=(ConchBlessing.kronos._counters.projectileBlocks or 0)
        ctx.target=H.target(player)
        Isaac.Spawn(EntityType.ENTITY_PROJECTILE,0,0,player.Position+Vector(12,0),Vector(-4,0),ctx.target)
    end)
    plan.waitUntil(function(_,ctx) return (ConchBlessing.kronos._counters.projectileBlocks or 0)>ctx.blocks end,90,"real projectile hits the 100% barrier")
    plan.check("100% barrier preserves actual health",function(player,ctx)
        return H.expect(player:GetHearts()+player:GetSoulHearts(),ctx.health)
    end)
    plan.act(function(_,ctx) ctx.target:Remove(); ctx.target=nil end)
    H.hit(plan)
    plan.check("barrier does not cancel non-projectile damage",function(player,ctx)
        return player:GetHearts()+player:GetSoulHearts()<ctx.health,"health actually decreased on non-projectile hit"
    end)
end

local anchors = { succubus="__kronosSuccubus", censer="__kronosCenser", star_of_bethlehem="__kronosStarOfBethlehem",
    bloodshot_eye="__kronosBloodshotEye", angelic_prism="__kronosAngelicPrism",
    twisted_pair="__kronosTwistedPair", incubus="__kronosIncubus" }

local function liveAnchors(player,name)
    return H.familiarAnchors(player,anchors[name])
end

local function extended(plan,name)
    if anchors[name] then
        local expected=name=="twisted_pair" and 4 or 2
        plan.waitUntil(function(player,ctx)
            local count=#liveAnchors(player,name)
            ctx.anchorCount=count
            local states={}
            for _,entity in ipairs(Isaac.GetRoomEntities()) do
                local f=entity.Type==EntityType.ENTITY_FAMILIAR and entity:ToFamiliar()
                if f and (f:GetData()[anchors[name]] or name=="twisted_pair" and f.Variant==FamiliarVariant.TWISTED_BABY) then
                    states[#states+1]=string.format("variant=%s subtype=%s age=%s owner=%s marked=%s noQuery=%s",tostring(f.Variant),
                        tostring(f.SubType),tostring(f.FrameCount),f.Player and tostring(GetPtrHash(f.Player)) or "nil",
                        tostring(f:GetData()[anchors[name]]==true),
                        tostring(EntityFlag.FLAG_NO_QUERY and f:HasEntityFlags(EntityFlag.FLAG_NO_QUERY) or false))
                end
            end
            if name=="twisted_pair" then
                states[#states+1]="tracked="..#(player:GetData().__kronosTwistedPairs or {})
                    .." absorbed="..tostring(ConchBlessing.kronos._getEffectCount(player,CollectibleType.COLLECTIBLE_TWISTED_PAIR))
            end
            ctx.anchorEvidence=string.format("actual=%d expected=%d player=%s; %s",count,expected,tostring(GetPtrHash(player)),table.concat(states," | "))
            return name=="angelic_prism" and count>0 or count==expected,
                ctx.anchorEvidence
        end,90,"native familiar anchors ready")
        plan.check("native anchors track the owner and absorbed count",function(player,ctx)
            for _,f in ipairs(liveAnchors(player,name)) do
                if f.Position:Distance(player.Position)>100 then return false,"anchor detached from player" end
            end
            return true,ctx.anchorEvidence or ("owned anchors=" .. #liveAnchors(player,name))
        end)
        plan.act(function(player,ctx)
            local list=liveAnchors(player,name)
            ctx.anchorSurvivor=list[2]; list[1]:Remove()
        end)
        plan.waitUntil(function(player,ctx) return #liveAnchors(player,name)==ctx.anchorCount end,90,"missing anchor rebuilt through production updates")
        plan.wait(4)
        plan.check("replenishment does not duplicate anchors",function(player,ctx) return H.expect(#liveAnchors(player,name),ctx.anchorCount) end)
        if name=="censer" or name=="succubus" then
            plan.act(function(player,ctx)
                ctx.target=H.target(player,true); ctx.target.Position=player.Position+Vector(25,0)
                ctx.outsideTarget=H.target(player,true); ctx.outsideTarget.Position=player.Position+Vector(220,0)
                ctx.hp,ctx.farHp=ctx.target.HitPoints,ctx.outsideTarget.HitPoints
            end)
            local function positionTargets(player,ctx)
                ctx.target.Position=player.Position+Vector(25,0)
                ctx.outsideTarget.Position=player.Position+Vector(220,0)
                ctx.target.Velocity=Vector.Zero; ctx.outsideTarget.Velocity=Vector.Zero
            end
            plan.waitUntil(function(player,ctx)
                positionTargets(player,ctx)
                return H.targetReady(ctx.target) and H.targetReady(ctx.outsideTarget)
            end,60,"aura targets are active and vulnerable")
            plan.waitUntil(function(player,ctx)
                positionTargets(player,ctx)
                return name=="censer" and ctx.target:HasEntityFlags(EntityFlag.FLAG_SLOW)
                    or name=="succubus" and ctx.target.HitPoints<ctx.hp
            end,120,"actual native aura affects nearby enemy")
            plan.check("aura does not affect the distant target",function(player,ctx)
                return name=="censer" and not ctx.outsideTarget:HasEntityFlags(EntityFlag.FLAG_SLOW)
                    or name=="succubus" and ctx.outsideTarget.HitPoints==ctx.farHp,
                    "near HP loss=" .. (ctx.hp-ctx.target.HitPoints) .. " far HP loss=" .. (ctx.farHp-ctx.outsideTarget.HitPoints)
                    .. "; near distance=" .. ctx.target.Position:Distance(player.Position)
                    .. "; far distance=" .. ctx.outsideTarget.Position:Distance(player.Position)
            end)
            plan.act(function(_,ctx) ctx.target:Remove(); ctx.outsideTarget:Remove(); ctx.target=nil; ctx.outsideTarget=nil end)
        elseif name=="star_of_bethlehem" then
            plan.check("native Star aura changes actual owner stats",function(player,ctx)
                return player.Damage>ctx.base.Damage+4 and H.stats(player).Tears>ctx.base.Tears,
                    "Damage=" .. player.Damage .. " Tears=" .. H.stats(player).Tears
            end)
        elseif name=="twisted_pair" or name=="incubus" then
            plan.act(function(player,ctx) H.shoot(player,"$tears",ctx,3) end)
            plan.waitUntil(function(_,ctx)
                ctx.extraAttacks={}
                for _,e in ipairs(ctx.shots.entities) do
                    local source=e:Exists() and e.SpawnerEntity
                    if source and source:GetData()[anchors[name]] then ctx.extraAttacks[#ctx.extraAttacks+1]=e end
                end
                return #ctx.extraAttacks>=expected
            end,150,"real extra familiar attacks")
            plan.act(H.stopShooting)
            local ratio=name=="twisted_pair" and 0.375 or 0.75
            plan.check("extra attack damage matches its promised ratio",function(player,ctx)
                for _,e in ipairs(ctx.extraAttacks) do if not H.near(e.CollisionDamage,player.Damage*ratio) then return H.expect(e.CollisionDamage,player.Damage*ratio) end end
                return true,"extra attacks=" .. #ctx.extraAttacks .. " damage=" .. player.Damage*ratio
            end)
            H.sampleAttackDamage(plan,function(player) return player.Damage*ratio end,function(_,ctx) return ctx.extraAttacks[1] end)
        elseif name=="angelic_prism" then
            plan.require("real weapon-trigger observer available",function() return ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED and true or nil,"weapon events unavailable" end)
            plan.act(function(player,ctx) H.shoot(player,"$tears",ctx,1) end)
            plan.waitUntil(function(_,ctx) return ctx.shots.count>=4 end,120,"real prism split creates four attacks")
            plan.act(H.stopShooting)
            plan.check("one real attack splits through the native prism",function(_,ctx) return ctx.shots.count>=4,"observed tears=" .. ctx.shots.count end)
            plan.act(function() H.isolateAttack() end)
        end
    elseif name=="buddy_in_a_box" or name=="lil_delirium" then
        plan.check("one stable floor pick per absorbed copy",function(player,ctx)
            local picks=ConchBlessing.SaveManager.GetRunSave(nil).kronos.floorPicks
            if not picks or #picks.ids~=2 then return false,"expected two floor picks" end
            ctx.pickIds=table.concat(picks.ids,",")
            return true,ctx.pickIds
        end)
        plan.wait(30)
        plan.check("same-floor updates do not reroll picks",function(player,ctx)
            return table.concat(ConchBlessing.SaveManager.GetRunSave(nil).kronos.floorPicks.ids,",")==ctx.pickIds,"stable picks"
        end)
        S.newFloor(plan,2)
        plan.check("new floor retains exactly two effect picks",function(player)
            return H.expect(#ConchBlessing.SaveManager.GetRunSave(nil).kronos.floorPicks.ids,2)
        end)
    elseif name=="mongo_baby" then
        plan.check("actual Minisaac count matches absorbed copies",function()
            return H.expect(#Isaac.FindByType(EntityType.ENTITY_FAMILIAR,FamiliarVariant.MINISAAC,-1),2)
        end)
        plan.act(function()
            for _,f in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,FamiliarVariant.MINISAAC,-1)) do f:Remove() end
        end)
        S.newFloor(plan,2)
        plan.check("room entry refills missing Minisaacs without duplicates",function()
            return H.expect(#Isaac.FindByType(EntityType.ENTITY_FAMILIAR,FamiliarVariant.MINISAAC,-1),2)
        end)
    elseif name=="gb_bug" then
        -- GB itself is already absorbed twice. A new copy returns half of four
        -- other copies; the same returned copies must remain exempt afterwards.
        give(plan,"brother_bobby",4)
        give(plan,"gb_bug",1)
        plan.check("GB returns half of other absorbed familiars",function(player)
            return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,true),2)
        end)
        plan.wait(30)
        plan.check("returned copies are not immediately reabsorbed",function(player)
            return H.expect(player:GetCollectibleNum(CollectibleType.COLLECTIBLE_BROTHER_BOBBY,true),2)
        end)
        plan.act(function(_,ctx) ctx.totalGiven=3 end) -- only GB copies are asserted by the common return check
    end
end

local function procTest(plan,name,spec)
    plan.require("confirmed enemy-damage events available",function() return ModCallbacks.MC_POST_ENTITY_TAKE_DMG and true or nil,"confirmed damage callback unavailable" end)
    give(plan,name,spec.copies-2)
    plan.act(function(player,ctx)
        ctx.beforeEntities={}
        for _,e in ipairs(Isaac.GetRoomEntities()) do ctx.beforeEntities[GetPtrHash(e)]=true end
    end)
    hitEnemy(plan)
    plan.wait(2)
    plan.act(function(_,ctx)
        ctx.immediateLoss=ctx.weaponHpBefore-ctx.target.HitPoints
        ctx.created={}
        for _,e in ipairs(Isaac.GetRoomEntities()) do
            if not ctx.beforeEntities[GetPtrHash(e)] and (spec.variant and e.Type==EntityType.ENTITY_FAMILIAR and e.Variant==FamiliarVariant[spec.variant]
                or name=="lil_spewer" and e.Type==EntityType.ENTITY_EFFECT and e.Variant==EffectVariant.PLAYER_CREEP_RED) then
                ctx.created[#ctx.created+1]=e
            end
        end
    end)
    local check=(spec.variant or name=="lil_spewer") and plan.require or plan.check
    -- Missing output prevents only its dependent damage measurement. Never
    -- dereference a nonexistent fly/spider/creep and obscure the first failure.
    check("confirmed attack triggers the guaranteed unique ability",function(_,ctx)
        if name=="daddy_longlegs" then return H.expect(ctx.immediateLoss,ctx.shots.directDamage+2*ctx.attackDamage) end
        if spec.flag then return ctx.target:HasEntityFlags(EntityFlag[spec.flag]),"actual enemy status=" .. spec.flag end
        return H.expect(#ctx.created,1)
    end)
    if name=="lil_spewer" or spec.variant then
        plan.act(function(_,ctx) ctx.target:Remove(); ctx.target=nil end)
        H.sampleAttackDamage(plan,function(_,ctx) return ctx.attackDamage*(spec.variant and 2 or 0.66) end,function(_,ctx) return ctx.created[1] end)
    end
    plan.act(function(_,ctx) if ctx.target then ctx.target:Remove(); ctx.target=nil end end)
end

local function unique(plan,name,n)
    if name=="brother_bobby" or name=="guardian_angel" or name=="guillotine" then
        plan.check("absorbed unique stat bonus stacks independently of +2",function(player,ctx)
            if name=="guardian_angel" then return H.expect(player.MoveSpeed,ctx.base.Speed+0.3*n) end
            local tears=ctx.base.Tears+(name=="brother_bobby" and 2 or 0.5)*n
            if not H.near(H.stats(player).Tears,tears) then return H.expect(H.stats(player).Tears,tears) end
            return name~="guillotine" or H.near(player.Damage,ctx.base.Damage+3*n),"tear bonus=" .. tears
        end)
    end
    if cases[name].block then
        plan.check("live projectile-block probability matches absorbed copies",function(player)
            local actual=ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK(player)
            local expected=ConchBlessing.Locale.formatPercent(string.format("%g",cases[name].block*100*n))
            return actual==expected,"actual=" .. tostring(actual) .. " expected=" .. expected
        end)
    end
    if statusFlags[name] then
        hitEnemy(plan)
        plan.wait(2)
        plan.check("actual damaged enemy receives the status",function(_,ctx)
            return ctx.target:HasEntityFlags(EntityFlag[statusFlags[name]]),statusFlags[name]
        end)
        plan.act(function(_,ctx) ctx.target:Remove(); ctx.target=nil end)
    elseif name=="seraphim" or name=="little_steven" then
        plan.require("real weapon-trigger observer available",function() return ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED and true or nil,"weapon events unavailable" end)
        plan.act(function(player,ctx) H.shoot(player,"$tears",ctx,1) end)
        plan.waitUntil(function(_,ctx) return ctx.shots.count>0 end,120,"real tear fire callback")
        plan.act(H.stopShooting)
        plan.check("real fired tear has the granted flags",function(player,ctx)
            local flags=TearFlags.TEAR_HOMING
            if name=="seraphim" then flags=flags|TearFlags.TEAR_SPECTRAL end
            local tear=ctx.shots.entities[1]:ToTear()
            return tear and tear:HasTearFlags(flags) and (name~="seraphim" or player.CanFly),"actual tear flags and flight"
        end)
        plan.act(function() H.isolateAttack() end)
    end
end

local names={}
for name in pairs(cases) do if not specialSources[name] then names[#names+1]=name end end
table.sort(names)
for _,name in ipairs(names) do
    local spec=cases[name]
    local damage = procs[name]~=nil or statusFlags[name]~=nil or name=="gemini" or name=="dry_baby"
        or name=="bird_cage" or name=="holy_water" or name=="incubus" or name=="twisted_pair" or name=="succubus"
    S.add("KRONOS","synergy_" .. name,{synergies=true,conditions=true,damage=damage},function(plan,kronosId)
        plan.act(function(player,ctx)
            ctx.totalGiven=0
            if spec.grant then
                ctx.grantId=assert(CollectibleType["COLLECTIBLE_" .. spec.grant],"unresolved promised grant " .. spec.grant)
                -- A pre-owned copy must survive eventual loss of Kronos.
                player:AddCollectible(ctx.grantId,0,false)
            end
            player:AddCollectible(kronosId,0,false)
        end)
        plan.wait(4)
        plan.act(function(player,ctx) ctx.base=H.stats(player) end)
        for n=1,2 do
            if spec.excluded then
                plan.act(function(player,ctx) player:AddCollectible(familiarId(name),0,false); ctx.totalGiven=n end)
                plan.wait(10)
            else give(plan,name,1) end
            plan.check("familiar inventory and flat absorption damage follow the contract",function(player)
                local count=player:GetCollectibleNum(familiarId(name),true)
                local damage=H.addition(player,"itemAdditions",kronosId,"Damage")
                return count==(spec.excluded and n or 0) and H.near(damage,spec.excluded and 0 or 2*n),
                    "held=" .. count .. " expected=" .. (spec.excluded and n or 0) .. "; flat damage=" .. damage .. " expected=" .. (spec.excluded and 0 or 2*n)
            end)
            if spec.grant then
                plan.check("promised collectible respects its grant cap",function(player,ctx)
                    return H.expect(player:GetCollectibleNum(ctx.grantId,true),1+(spec.cap==0 and n or math.min(n,spec.cap)))
                end)
            end
            unique(plan,name,n)
        end
        if procs[name] then procTest(plan,name,procs[name]) end
        if spec.block then blockTest(plan,name) end
        extended(plan,name)
        Events.build(plan,name,give)
        plan.act(function(player) player:RemoveCollectible(kronosId) end)
        plan.wait(8)
        plan.check("last Kronos loss returns every familiar and removes flat damage",function(player,ctx)
            local held=player:GetCollectibleNum(familiarId(name),true)
            return held==ctx.totalGiven and H.near(H.addition(player,"itemAdditions",kronosId,"Damage"),0),
                "returned=" .. held .. " expected=" .. ctx.totalGiven
        end)
        if spec.grant then
            plan.check("only the original player-owned grant remains",function(player,ctx) return H.expect(player:GetCollectibleNum(ctx.grantId,true),1) end)
            if name=="seraphim" then
                -- Separate Kronos withdrawal from the later fixture removal of
                -- the player's original Sacred Heart. A mismatch after only the
                -- latter operation must not be attributed to absorbed stats.
                plan.check("Seraphim withdrawal restores the original Sacred Heart stats",function(player,ctx)
                    return H.sameStats(player,ctx.base)
                end)
            end
        end
    end,{name})
end

return S
