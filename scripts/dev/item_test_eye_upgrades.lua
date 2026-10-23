local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")
local EyeSample = require("scripts.dev.eye_sample")
local sample

local TRIGGERS = 6          -- real weapon triggers per burst
local MAX_BURSTS = 4        -- bounded resampling for each fixture state
local TIMING_TOLERANCE = 2  -- frames per trigger, as in the original span comparison
local COOLDOWN_LIMIT, BURST_LIMIT = 90, 240 -- the original per-burst bounds
local NO_RECORD = "REPENTOGON EntityPlayer:GetTearDisplacement unavailable; no engine eye record"

-- Every tear compares the item's marker with the engine's eye record for the
-- shot that spawned it. REPENTOGON documents TearDisplacement as the eye of
-- the last shot, which at post-fire is this tear's shot. It is a per-shot
-- record: a both-eye shot (The Wiz) is judged by its pair instead.
ConchBlessing:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
    if not sample then return end
    local p=tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not p or GetPtrHash(p)~=sample.owner then return end
    local blocked=ConchBlessing.hemispatialneglect.isBlockedTear(tear)
    local eye=type(p.GetTearDisplacement)=="function" and p:GetTearDisplacement() or nil
    EyeSample.addTear(sample,Game():GetFrameCount(),blocked,eye)
    if blocked then sample.blockedEntities[#sample.blockedEntities+1]=tear end
end)

-- Cadence is measured on the real weapon-trigger event, one per shot.
if ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED, function(_, _, _, owner)
        if sample and owner and GetPtrHash(owner)==sample.owner then
            EyeSample.addTrigger(sample,Game():GetFrameCount())
        end
    end)
end

-- The shooting fixture answers MC_INPUT_ACTION with a value, which ends the
-- callback chain, so this observer runs earlier and returns nothing. An update
-- in which the engine never asked for the held shot marks the burst so it can
-- be repeated instead of being mistaken for a cadence change (the 2026-10-23
-- A/B rerun lost about 60 updates of fire while the game window was resized).
local callbackPriority = rawget(_G, "CallbackPriority")
local OBSERVE_PRIORITY = type(callbackPriority) == "table" and tonumber(callbackPriority.IMPORTANT) or -200
local inputObserved = false
if type(ConchBlessing.AddPriorityCallback) == "function" and ButtonAction and ModCallbacks.MC_INPUT_ACTION then
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_INPUT_ACTION, OBSERVE_PRIORITY, function(_, entity, _, action)
        if sample and sample.holding and entity and action == ButtonAction.ACTION_SHOOTRIGHT
            and GetPtrHash(entity) == sample.owner then sample.queried = true end
    end)
    inputObserved = true
end

-- Eyes firing each shot, from the engine's MultiShotParams and the fixture's
-- declaration. The per-shot eye record attributes a tear only when exactly one
-- eye fires, so if either source says both fire, the pair contract is used.
local function eyesPerShot(player, declared)
    local ok, count = pcall(function()
        return player:GetMultiShotParams(WeaponType.WEAPON_TEARS):GetNumEyesActive()
    end)
    if not ok or type(count) ~= "number" then return declared, "fixture declaration; MultiShotParams unavailable" end
    if count == declared then return count, "engine MultiShotParams" end
    return math.max(count, declared), "engine " .. count .. " vs fixture " .. declared .. "; the larger applies"
end

-- The engine exposes one FireDelay but no per-eye readiness, and Eye Drops'
-- uneven cadence carries over between bursts. Both eyes therefore idle for two
-- native shot intervals (the slowest fixture so far) before every burst.
local function settleFrames(player, ctx)
    return 2 * (math.ceil(math.max(player.MaxFireDelay or 0, ctx.eyeLastDelay or 0)) + 1)
end

local function eyesList(attempts)
    local list = {}
    for i, r in ipairs(attempts) do list[i] = r.eyes end
    return table.concat(list, ",")
end

-- One waitUntil drives bursts: settle, align the starting eye, fire six real
-- triggers, then keep the burst. The control needs two agreeing bursts; an
-- item state needs one burst in the control's eye phase. Every burst is kept
-- and judged, so resampling never hides an output failure.
local function burster(name, isControl)
    return function(player, ctx)
        if not ctx.eyeRecord then return true end
        local run = ctx.eyeRun
        local frame = Game():GetFrameCount()
        run.updates = run.updates + 1
        if run.phase == "settle" then
            local settle = settleFrames(player, ctx)
            if run.updates > COOLDOWN_LIMIT + settle then
                error(string.format("burst %d: native firing cooldown not ready after %d updates (FireDelay=%s)",
                    #run.attempts + 1, run.updates, tostring(player.FireDelay)))
            end
            if player.FireDelay > 0 then return false, "native firing cooldown ready" end
            if ctx.eyeLastShot and frame - ctx.eyeLastShot < settle then
                return false, "both eyes idle for " .. settle .. " updates"
            end
            -- Same start for every burst: the next native shot flips to the left eye.
            if type(player.SetTearDisplacement) == "function" then player:SetTearDisplacement(EyeSample.RIGHT) end
            run.eyesPerShot, run.eyeSource = eyesPerShot(player, run.declaredEyes)
            sample = EyeSample.new(GetPtrHash(player))
            sample.holding, sample.inputObserved = true, inputObserved
            H.shoot(player, "$tears", ctx, TRIGGERS)
            run.phase, run.updates = "burst", 0
            return false, "burst " .. (#run.attempts + 1) .. " of at most " .. MAX_BURSTS
        end
        if run.updates > BURST_LIMIT then
            error(string.format("burst %d: %d actual weapon triggers within %d updates, want %d",
                #run.attempts + 1, ctx.shots and ctx.shots.triggers or 0, BURST_LIMIT, TRIGGERS))
        end
        if sample.holding then
            if sample.inputObserved and not sample.queried then sample.inputGaps = sample.inputGaps + 1 end
            sample.queried = false
            if ctx.shots.triggers >= TRIGGERS then sample.holding = false end
            return false, "six actual weapon triggers"
        end
        -- One update past the last trigger, as before, so a late tear still counts.
        H.stopShooting()
        local s = sample
        sample = nil
        local survivors = 0
        for _, tear in ipairs(s.blockedEntities) do if tear:Exists() then survivors = survivors + 1 end end
        run.attempts[#run.attempts + 1] = EyeSample.summarize(s, survivors)
        ctx.eyeLastShot, ctx.eyeLastDelay = s.triggers[#s.triggers] or frame, player.MaxFireDelay
        run.phase, run.updates = "settle", 0
        local final = #run.attempts >= MAX_BURSTS
        if isControl then
            run.reference = EyeSample.reference(run.attempts, TIMING_TOLERANCE)
            return run.reference ~= nil or final, "a second control burst reproducing the first"
        end
        local control = ctx.eyeControls[name]
        if not control or control.skip then return true end
        run.match = EyeSample.comparable(run.attempts, control.reference, final)
        return run.match ~= nil or final, "a burst in the control's native eye phase"
    end
end

S.add("HEMISPATIAL_NEGLECT", "right_eye", {conditions=true,damage=true}, function(plan,id)
    plan.section("HEMISPATIAL_NEGLECT / appearance (manual only)",
        "Front: Isaac's right half hidden; back: opposite screen half hidden; left-facing: normal; right-facing: outline only. Check costumes/blink and full restoration after loss. Gameplay PASS does not verify this image.")
    plan.require("right-tear suppression capabilities and XML loaded",function()
        return ConchBlessing.hemispatialneglect.canRestrictTears() and true or nil,
            "full game restart and REPENTOGON tear-params/pre-update callbacks required"
    end)
    plan.act(function(player,ctx)
        ctx.cleanupFns=ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns+1]=function() sample=nil; H.stopShooting() end
        ctx.eyeControls={}
        ctx.eyeRecord=type(player.GetTearDisplacement)=="function"
        ctx.eyeLastShot,ctx.eyeLastDelay=nil,nil
    end)
    plan.note("burst evidence sources",function(player,ctx)
        return string.format("engine eye record=%s; starting-eye alignment=%s; input-delivery observer=%s",
            tostring(ctx.eyeRecord),tostring(type(player.SetTearDisplacement)=="function"),tostring(inputObserved))
    end)
    -- eyes: the fallback eyes-per-shot when the engine cannot report it.
    local fixtures={
        {"ordinary",eyes=1}, {"multishot",CollectibleType.COLLECTIBLE_MUTANT_SPIDER,eyes=1},
        {"dual_eyes",CollectibleType.COLLECTIBLE_THE_WIZ,eyes=2},
        {"eye_drops",CollectibleType.COLLECTIBLE_EYE_DROPS,eyes=1},
        {"high_tears",CollectibleType.COLLECTIBLE_SOY_MILK,eyes=1},
    }
    for _,fixture in ipairs(fixtures) do
        local name=fixture[1]
        for _,state in ipairs({{label="control",count=0},{label="owned",count=1},
            {label="stacked",count=2},{label="removed",count=0}}) do
            local isControl,owned=state.label=="control",state.count>0
            plan.section("HEMISPATIAL_NEGLECT / "..name.." / "..state.label)
            plan.act(function(player,ctx)
                for _,row in ipairs(fixtures) do if row[2] then S.collectible(player,row[2],0) end end
                if fixture[2] then S.collectible(player,fixture[2],1) end
                S.collectible(player,id,state.count)
                H.isolateAttack(nil)
                ctx.eyeRun={phase="settle",attempts={},updates=0,declaredEyes=fixture.eyes}
            end)
            plan.wait(2)
            plan.waitUntil(burster(name,isControl),MAX_BURSTS*(COOLDOWN_LIMIT+BURST_LIMIT+120),
                isControl and "two vanilla control bursts agree" or "a burst in the control's native eye phase")
            plan.note("bursts (eyes: engine eye record per tear; marks: lower case = suppressed)",function(_,ctx)
                local run=ctx.eyeRun
                if not ctx.eyeRecord then return NO_RECORD end
                local parts={"eyes per shot="..tostring(run.eyesPerShot).." ("..tostring(run.eyeSource)..")"}
                for i,r in ipairs(run.attempts) do parts[#parts+1]="burst "..i..": "..EyeSample.describe(r) end
                return table.concat(parts,"; ")
            end)
            if isControl then
                plan.check("vanilla control suppresses nothing and reproduces its native eye schedule",function(_,ctx)
                    if not ctx.eyeRecord then return nil,NO_RECORD end
                    local run=ctx.eyeRun
                    for i,r in ipairs(run.attempts) do
                        local ok,detail=EyeSample.controlContract(r,run.eyesPerShot)
                        if ok==nil then ctx.eyeControls[name]={skip=detail}; return nil,detail end
                        if not ok then return false,"burst "..i..": "..detail.." ("..EyeSample.describe(r)..")" end
                    end
                    if not run.reference then
                        return false,"no two of "..#run.attempts.." control bursts agree (eyes "..eyesList(run.attempts)..")"
                    end
                    ctx.eyeControls[name]={reference=run.reference,eyesPerShot=run.eyesPerShot}
                    return true,"reference "..EyeSample.describe(run.reference).." from "..#run.attempts.." bursts"
                end)
            else
                plan.check(owned and "right-eye output omitted and left-eye output kept on every burst"
                    or "nothing suppressed after the item is removed, on every burst",function(_,ctx)
                    if not ctx.eyeRecord then return nil,NO_RECORD end
                    local run=ctx.eyeRun
                    if #run.attempts==0 then return false,"no burst observed" end
                    local details={}
                    for i,r in ipairs(run.attempts) do
                        local ok,detail=EyeSample.eyeContract(r,owned,run.eyesPerShot)
                        if ok~=true then return ok,"burst "..i..": "..detail.." ("..EyeSample.describe(r)..")" end
                        details[i]="burst "..i..": "..detail
                    end
                    return true,table.concat(details,"; ")
                end)
                plan.check("output and native cadence match the vanilla control",function(_,ctx)
                    if not ctx.eyeRecord then return nil,NO_RECORD end
                    local control=ctx.eyeControls[name]
                    if not control then return false,"no reproducible vanilla control" end
                    if control.skip then return nil,control.skip end
                    local run=ctx.eyeRun
                    if run.eyesPerShot~=control.eyesPerShot then
                        return false,"eyes per shot control="..tostring(control.eyesPerShot).." actual="..tostring(run.eyesPerShot)
                    end
                    if not run.match then
                        return false,"no burst fired the control's native eye schedule (control "
                            ..control.reference.eyes.."; bursts "..eyesList(run.attempts)..")"
                    end
                    local ok,detail=EyeSample.matchesControl(run.match,control.reference,owned,run.eyesPerShot,TIMING_TOLERANCE)
                    if run.match.inputGaps>0 then
                        detail=detail.."; shooting input undelivered on "..run.match.inputGaps.." update(s)"
                    end
                    return ok,detail
                end)
            end
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
