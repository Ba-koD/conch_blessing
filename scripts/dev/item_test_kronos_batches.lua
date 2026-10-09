-- Independent catalog expectations; batch only common contracts. Auras, real
-- attack procs, room/floor rewards and temporary sources retain dedicated cases.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local cases = require("scripts.dev.kronos_synergy_cases")
local grants, barriers, excluded = {}, {}, {}
for name, spec in pairs(cases) do
    if spec.excluded then excluded[#excluded + 1] = name
    elseif spec.grant and not spec.block and name ~= "seraphim" and name ~= "star_of_bethlehem" then
        grants[#grants + 1] = name
    elseif spec.block and not spec.grant and name ~= "guillotine" and name ~= "moms_razor" then
        barriers[#barriers + 1] = name
    end
end
for _, names in ipairs({ grants, barriers, excluded }) do table.sort(names) end
local function id(name) return assert(CollectibleType["COLLECTIBLE_" .. name:upper()], name) end
local function amount(player, name) return player:GetCollectibleNum(id(name), true) end
local function sum(t) local n=0; for _,v in pairs(t) do n=n+v end; return n end
local function give(player, ctx, name, n)
    ctx.given[name] = (ctx.given[name] or 0) + n
    for _=1,n do player:AddCollectible(id(name),0,false) end
end
local function waitAbsorbed(plan, names)
    plan.waitUntil(function(player)
        for _,name in ipairs(names) do
            local held=amount(player,name)
            if held ~= 0 then return false,name .. " still held=" .. held .. " expected=0" end
        end
        return true
    end,90,"batch inventory absorption completes")
    plan.wait(2) -- deferred stat cache
end
local function checkCopies(plan, names, kronosId, isExcluded)
    for _,name in ipairs(names) do
        plan.check(name .. " / exact absorbed or excluded copies", function(player,ctx)
            local wanted = ctx.given[name]
            local held = amount(player,name)
            local absorbed = ConchBlessing.kronos._getAbsorbedCount(player,id(name))
            return held == (isExcluded and wanted or 0) and absorbed == (isExcluded and 0 or wanted),
                "held=" .. held .. " absorbed=" .. absorbed .. " given=" .. wanted
        end)
    end
    plan.check("every absorbed copy contributes +2",function(player,ctx)
        return H.expect(H.addition(player,"itemAdditions",kronosId,"Damage"),isExcluded and 0 or 2*sum(ctx.given))
    end)
end
local function checkGrants(plan)
    plan.check("all conversion caps and shared grant baselines",function(player,ctx)
        local expected = {}
        for name,count in pairs(ctx.given) do
            local spec = cases[name]
            local target = id(spec.grant)
            expected[target] = (expected[target] or 1) + (spec.cap == 0 and count or math.min(count,spec.cap))
        end
        for target,wanted in pairs(expected) do
            local actual = player:GetCollectibleNum(target,true)
            if actual ~= wanted then return false,"grant ID=" .. target .. " actual=" .. actual .. " expected=" .. wanted end
        end
        return true,"one pre-owned baseline per target; per-familiar lifetime caps retained"
    end)
end
local function release(plan, names, kronosId, isExcluded)
    plan.section("KRONOS / batch removal and exact return")
    plan.act(function(player,ctx)
        ctx.releaseFrame=Game():GetFrameCount()
        player:RemoveCollectible(kronosId)
    end)
    plan.waitUntil(function(player,ctx)
        for _,name in ipairs(names) do
            local held=amount(player,name)
            if held ~= ctx.given[name] then return false,name .. " returned=" .. held .. " expected=" .. ctx.given[name] end
        end
        return H.expect(H.addition(player,"itemAdditions",kronosId,"Damage"),0)
    end,90,"all copies returned and absorption damage withdrawn")
    plan.wait(2)
    for _,name in ipairs(names) do
        plan.check(name .. " / removal returns exact inventory",function(player,ctx) return H.expect(amount(player,name),ctx.given[name]) end)
    end
    plan.check("no remaining absorbed contribution",function(player)
        for _,name in ipairs(names) do
            if ConchBlessing.kronos._getAbsorbedCount(player,id(name)) ~= 0 then return false,"stale absorption " .. name end
        end
        return H.expect(H.addition(player,"itemAdditions",kronosId,"Damage"),0)
    end)
    if not isExcluded then
        plan.check("bulk return uses one bounded visual group",function(player,ctx)
            local count,icons,copies=0,0,0
            for _,group in ipairs(ConchBlessing.kronos._test.transferGroups()) do
                if group.hash == GetPtrHash(player) then
                    if not group.reverse then return false,"stale absorption animation after release" end
                    count=count+1; icons=icons+group.icons; copies=copies+(group.copies or 0)
                end
            end
            return count==1 and icons<=12 and copies==sum(ctx.given),
                "groups=" .. count .. " icons=" .. icons .. " returned copies=" .. copies
                    .. " elapsed updates=" .. (Game():GetFrameCount()-ctx.releaseFrame)
        end)
    end
end

S.bundle("KRONOS","conversions",{synergies=true,conditions=true},function(plan,kronosId)
    plan.act(function(player,ctx)
        ctx.given,ctx.grants={},{}
        for _,name in ipairs(grants) do ctx.grants[id(cases[name].grant)]=true end
        for target in pairs(ctx.grants) do player:AddCollectible(target,0,false) end
        player:AddCollectible(kronosId,0,false)
    end)
    for copy=1,2 do
        plan.section("KRONOS / all conversion familiars / copy " .. copy)
        plan.act(function(player,ctx) for _,name in ipairs(grants) do give(player,ctx,name,1) end end)
        waitAbsorbed(plan,grants)
        checkCopies(plan,grants,kronosId)
        checkGrants(plan)
    end
    -- Stress both capped and uncapped conversion contributions in this same run.
    -- These are real inventory acquisitions, never a fabricated absorption ledger.
    plan.section("KRONOS / bulk capped and uncapped copies")
    plan.act(function(player,ctx)
        local tested={}
        for _,name in ipairs(grants) do
            local cap=cases[name].cap
            if not tested[cap] then give(player,ctx,name,128); tested[cap]=true end
        end
    end)
    waitAbsorbed(plan,grants)
    checkCopies(plan,grants,kronosId)
    checkGrants(plan)
    release(plan,grants,kronosId)
    plan.check("bulk removal preserves every original grant",function(player,ctx)
        for target in pairs(ctx.grants) do
            local actual=player:GetCollectibleNum(target,true)
            if actual~=1 then return false,"grant ID=" .. target .. " actual=" .. actual .. " expected=1" end
        end
        return true,"all owned baselines survive; all converted copies withdrawn"
    end)
end,grants)

S.bundle("KRONOS","barriers",{synergies=true,conditions=true},function(plan,kronosId)
    plan.act(function(player,ctx)
        ctx.given,ctx.block={},0
        player:AddCollectible(kronosId,0,false)
    end)
    -- Check each contribution before the combined probability reaches the cap.
    for _,name in ipairs(barriers) do
        plan.section("KRONOS / projectile barrier / " .. name)
        plan.act(function(player,ctx) give(player,ctx,name,1); ctx.block=ctx.block+cases[name].block end)
        waitAbsorbed(plan,{name})
        plan.check(name .. " / live cumulative block chance",function(player,ctx)
            local actual=ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK(player)
            local expected=ConchBlessing.Locale.formatPercent(string.format("%g",math.min(1,ctx.block)*100))
            return actual==expected,"actual=" .. tostring(actual) .. " expected=" .. expected
        end)
    end
    plan.act(function(player,ctx) for _,name in ipairs(barriers) do give(player,ctx,name,1) end end)
    waitAbsorbed(plan,barriers)
    checkCopies(plan,barriers,kronosId)
    plan.check("second copies also double the combined block contribution",function(player,ctx)
        local actual=ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK(player)
        local expected=ConchBlessing.Locale.formatPercent(string.format("%g",math.min(1,ctx.block*2)*100))
        return actual==expected,"actual=" .. tostring(actual) .. " expected=" .. expected
    end)
    plan.act(function(player,ctx)
        local chance=0; for name,count in pairs(ctx.given) do chance=chance+cases[name].block*count end
        give(player,ctx,barriers[1],math.max(0,math.ceil((1-chance)/cases[barriers[1]].block)))
    end)
    waitAbsorbed(plan,barriers)
    plan.act(function(player,ctx)
        ctx.health=player:GetHearts()+player:GetSoulHearts()
        ctx.blocks=ConchBlessing.kronos._counters.projectileBlocks or 0
        ctx.target=H.target(player)
        Isaac.Spawn(EntityType.ENTITY_PROJECTILE,0,0,player.Position+Vector(12,0),Vector(-4,0),ctx.target)
    end)
    plan.waitUntil(function(_,ctx) return (ConchBlessing.kronos._counters.projectileBlocks or 0)>ctx.blocks end,90,"real projectile hits combined 100% barrier")
    plan.check("combined barrier preserves actual health",function(player,ctx) return H.expect(player:GetHearts()+player:GetSoulHearts(),ctx.health) end)
    plan.act(function(_,ctx) ctx.target:Remove(); ctx.target=nil end)
    H.hit(plan)
    plan.check("barrier allows non-projectile HP damage",function(player,ctx)
        return player:GetHearts()+player:GetSoulHearts()<ctx.health,"actual health decreased"
    end)
    release(plan,barriers,kronosId)
    plan.check("removal clears the projectile-ignore contribution",function(player)
        local actual=ConchBlessing.EIDDynamicTokens.KRONOS_BLOCK(player)
        local expected=ConchBlessing.Locale.formatPercent(0)
        return actual==expected,"actual=" .. tostring(actual) .. " expected=" .. expected
    end)
end,barriers)

S.bundle("KRONOS","exclusions",{synergies=true,conditions=true},function(plan,kronosId)
    plan.act(function(player,ctx) ctx.given={}; player:AddCollectible(kronosId,0,false) end)
    for copy=1,2 do
        plan.section("KRONOS / every excluded familiar / copy " .. copy)
        plan.act(function(player,ctx) for _,name in ipairs(excluded) do give(player,ctx,name,1) end end)
        -- Exclusion is a non-event: span two ordinary 15-update scan intervals.
        plan.wait(32)
        checkCopies(plan,excluded,kronosId,true)
    end
    release(plan,excluded,kronosId,true)
end,excluded)

local Isolation = require("scripts.dev.test_isolation")
local sequential = {
    attacks={"rotten_baby","7_seals","juicy_sack","sissy_longlegs","daddy_longlegs","moms_razor",
        "cube_baby","lil_spewer","lil_haunt","little_gish","intruder","worm_friend","gemini"},
    auras={"censer","succubus","star_of_bethlehem","bloodshot_eye","angelic_prism","twisted_pair","incubus"},
    abilities={"brother_bobby","guardian_angel","guillotine","little_steven","seraphim",
        "holy_water","dry_baby","bird_cage","mystery_egg","my_shadow"},
}
for _,group in ipairs({"attacks","auras","abilities"}) do
    S.sequenceBundle("KRONOS",group,{synergies=true,conditions=true,damage=true},sequential[group],
        function(plan)
            Isolation.begin(plan,true)
            plan.act(function(player,ctx) ctx.base=H.stats(player) end)
        end,
        function(plan,kronosId) Isolation.finish(plan,"KRONOS",kronosId,true) end)
end

return { conversions=grants, barriers=barriers, exclusions=excluded, sequential=sequential }
