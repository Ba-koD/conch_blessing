local H = require("scripts.dev.item_test_support")
local C = {}

C.KRONOS = { prepare = function(plan)
    plan.act(function(player)
        for _ = 1, 2 do player:AddCollectible(CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, 0, false) end
    end)
end, stage = function(plan, _, n)
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, true) == (n > 0 and 0 or 2)
    end, 90, "familiar absorption or return completes")
    plan.check("two special familiars each supply +2, independent of Kronos copies", function(player, ctx)
        return H.expect(player.Damage, ctx.base.Damage + (n > 0 and 4 or 0))
    end)
    plan.check("last-copy loss returns familiars; partial loss keeps absorptions", function(player)
        local held = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_GUARDIAN_ANGEL, true)
        return held == (n > 0 and 0 or 2), "Guardian Angel inventory=" .. held
    end)
end, finish = function(plan, id)
    plan.section("KRONOS / absorbed abilities follow damage changes")
    if not require("scripts.lib.damage_provenance").hasAppliedDamageCallback() then
        plan.check("real absorbed ability damage", function() return nil, "applied-damage callback unavailable" end)
        return
    end
    plan.act(function(player)
        player:AddCollectible(id, 0, false)
        for _ = 1, 10 do player:AddCollectible(CollectibleType.COLLECTIBLE_DADDY_LONGLEGS, 0, false) end
        for _ = 1, 4 do player:AddCollectible(CollectibleType.COLLECTIBLE_LIL_SPEWER, 0, false) end
    end)
    plan.waitUntil(function(player)
        return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_DADDY_LONGLEGS, true) == 0
            and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_LIL_SPEWER, true) == 0
    end, 120, "guaranteed stomp and creep abilities absorbed")
    plan.wait(2)
    for _, profile in ipairs({ "base", "increased", "restored" }) do
        plan.section("KRONOS / ability damage " .. profile)
        plan.act(function(player)
            for _ = 1, 5 do
                if profile == "increased" then player:AddCollectible(CollectibleType.COLLECTIBLE_STEVEN, 0, false)
                elseif profile == "restored" then player:RemoveCollectible(CollectibleType.COLLECTIBLE_STEVEN) end
            end
        end)
        plan.wait(4)
        plan.act(function(player, ctx)
            local target = H.target(player)
            ctx.target = target
            ctx.oldCreeps = {}
            for _, creep in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_CREEP_RED, -1)) do
                ctx.oldCreeps[GetPtrHash(creep)] = true
            end
            ctx.absorbedDamage = player.Damage
        end)
        H.fireWeaponAtTarget(plan,"tear")
        -- Enemy HP is buffered by the engine. The flying input target cannot
        -- take creep damage while the direct hit and stomp settle.
        plan.wait(2)
        plan.act(function(_,ctx)
            ctx.stompHpLoss = ctx.weaponHpBefore - ctx.target.HitPoints
            ctx.creepDamages = {}
            for _, creep in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_CREEP_RED, -1)) do
                if not ctx.oldCreeps[GetPtrHash(creep)] then
                    ctx.creepDamages[#ctx.creepDamages + 1] = creep.CollisionDamage
                    creep:Remove()
                end
            end
            ctx.target:Remove()
            ctx.target = nil
        end)
        plan.check("stomp actual HP loss follows current damage", function(_, ctx)
            return H.expect(ctx.stompHpLoss, ctx.shots.directDamage + 2 * ctx.absorbedDamage)
        end)
        plan.check("new creep damage follows current damage", function(_, ctx)
            if #ctx.creepDamages == 0 then return false, "no new creep spawned at 100% chance" end
            local expected = ctx.absorbedDamage * 0.66
            for _, damage in ipairs(ctx.creepDamages) do
                if not H.near(damage, expected) then return H.expect(damage, expected) end
            end
            return true, "all new creep damage=" .. expected .. "; HP ticks not measured here"
        end)
    end
end }

C.TIME_MONEY = { stage = function(plan, _, n)
    plan.check("live familiar count follows copies, including zero", function(player)
        local item = ConchBlessing.ItemData.TIME_MONEY
        local variant = assert(item.entity and item.entity.variant, "missing familiar registry variant")
        local count = 0
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1)) do
            local familiar = entity:ToFamiliar()
            if familiar and familiar.Player and GetPtrHash(familiar.Player) == GetPtrHash(player) then count = count + 1 end
        end
        return H.expect(count, n)
    end)
end }

-- Azure Dragon (console only): one long familiar per copy, no flight or spectral tears. Contact 5%
-- of damage per tick; lightning for 5x damage on every enemy its snout runs
-- into, once every five seconds each per dragon. The
-- boss multiplier is covered offline (tests/test_dragon_familiar_contracts.py):
-- spawning a real boss would attack the test player. Its recorded hits
-- separate 5x bolts from 5% body contact, and HP loss must agree with every
-- recorded hit.
local function dragonsOf(player)
    local variant = assert(ConchBlessing.ItemData.AZURE_DRAGON.entity.variant, "missing Azure Dragon familiar variant")
    local list = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1)) do
        local familiar = entity:ToFamiliar()
        if familiar and familiar.Player and GetPtrHash(familiar.Player) == GetPtrHash(player) then list[#list + 1] = familiar end
    end
    return list
end

-- Offsets from the room centre, well outside the dragon's orbit around the player.
local DRAGON_SPOTS = { { 170, -100 }, { 190, 95 }, { -200, -70 }, { -215, 85 }, { 235, 0 }, { -240, 5 } }
local function pinTargets(ctx)
    for i, target in ipairs(ctx.targets) do
        local spot = DRAGON_SPOTS[i]
        if target:Exists() then target.Position = ctx.center + Vector(spot[1], spot[2]); target.Velocity = Vector.Zero end
    end
end

C.AZURE_DRAGON = { stage = function(plan, _, n)
    plan.check("Azure Dragon grants no flight or spectral tears", function(player, ctx)
        return player.CanFly == ctx.baseFly
            and (player.TearFlags & TearFlags.TEAR_SPECTRAL ~= 0) == ctx.baseSpectral,
            "flight=" .. tostring(player.CanFly)
    end)
    plan.check("one dragon per copy", function(player)
        local list, segmented = dragonsOf(player), true
        for _, familiar in ipairs(list) do
            local state = familiar:GetData().__ConchDragon
            segmented = segmented and state ~= nil and #state.segments == #ConchBlessing.azureDragon.data.parts
        end
        local expected = n
        return #list == expected and segmented, string.format("dragons=%d expected=%d copies=%d segments=%s",
            #list, expected, n, tostring(segmented))
    end)
    if n == 0 then return end
    plan.act(function(player, ctx)
        H.isolateAttack()
        ctx.center = Game():GetRoom():GetCenterPos()
        player.Position = ctx.center
        ctx.dragon = dragonsOf(player)[1]
        ctx.targets = {}
        for i = 1, #DRAGON_SPOTS do ctx.targets[i] = H.target(player, true) end
        pinTargets(ctx)
        ctx.hp = {}
        H.recordDragonHits(true)
    end)
    plan.waitUntil(function(_, ctx)
        pinTargets(ctx)
        for _, target in ipairs(ctx.targets) do
            local ready, why = H.targetReady(target)
            if not ready then return false, why end
        end
        for i, target in ipairs(ctx.targets) do ctx.hp[i] = target.HitPoints end
        return true
    end, 60, "six far targets initialized and vulnerable")
    plan.act(function()
        -- Readiness waits are over; count only hits from here on.
        H.recordDragonHits(true)
    end)
    -- The dragon hunts the targets in turn; lightning strikes each one its snout runs into.
    plan.waitUntil(function(player, ctx)
        pinTargets(ctx)
        player.Position = ctx.center
        local struck = 0
        for _, target in ipairs(ctx.targets) do
            if #H.dragonHits(target, player.Damage * 2) > 0 then struck = struck + 1 end
        end
        return struck >= 3, "targets struck=" .. struck
    end, 450, "the dragon runs into and strikes several targets")
    plan.waitUntil(function(player, ctx)
        pinTargets(ctx); player.Position = ctx.center
        ctx.settle = (ctx.settle or 0) + 1
        return ctx.settle >= 6
    end, 8, "HP settles")
    plan.check("every enemy the snout runs into is struck for 5x current damage", function(player, ctx)
        local expected = player.Damage * 5 * (player:HasCollectible(CollectibleType.COLLECTIBLE_BFFS) and 2 or 1)
        local struck, wrong = 0, {}
        for i, target in ipairs(ctx.targets) do
            local bolts = H.dragonHits(target, player.Damage * 2)
            if #bolts > 0 then struck = struck + 1 end
            for _, bolt in ipairs(bolts) do
                if not H.near(bolt.amount, expected) then wrong[#wrong + 1] = i .. ":bolt " .. bolt.amount end
            end
            -- Every HP point lost is a recorded dragon hit (lightning plus body contact).
            local loss = ctx.hp[i] - target.HitPoints
            if math.abs(loss - H.dragonDamage(target)) > math.max(0.02, expected * 0.002) then
                wrong[#wrong + 1] = i .. ":HP loss " .. loss .. " vs hits " .. H.dragonDamage(target)
            end
        end
        return struck >= 3 and #wrong == 0, string.format("struck=%d damage=%s wrong=%s", struck, expected, table.concat(wrong, ","))
    end)
    plan.check("a dragon strikes the same enemy at most once every five seconds", function(player, ctx)
        local gaps = {}
        for i, target in ipairs(ctx.targets) do
            -- Each dragon keeps its own rhythm; several dragons may strike one enemy.
            local last = {}
            for _, bolt in ipairs(H.dragonHits(target, player.Damage * 2)) do
                local who = bolt.dragon or 0
                local gap = last[who] and bolt.frame - last[who]
                if gap and gap < ConchBlessing.azureDragon.data.strikeCooldown then gaps[#gaps + 1] = i .. ":" .. gap end
                last[who] = bolt.frame
            end
        end
        return #gaps == 0, "too-close bolts=" .. (#gaps > 0 and table.concat(gaps, ",") or "none")
    end)
    -- Contact: the body held against one enemy hurts it every tick.
    plan.act(function(player, ctx)
        for i = 2, #ctx.targets do ctx.targets[i]:Remove() end
        ctx.biter = ctx.targets[1]
        ctx.contactTicks, ctx.contactHp = 0, nil
        ctx.contactExpected = player.Damage * 0.05 * (player:HasCollectible(CollectibleType.COLLECTIBLE_BFFS) and 2 or 1)
        H.recordDragonHits(true)
    end)
    plan.waitUntil(function(player, ctx)
        player.Position = ctx.center
        local state = ctx.dragon:GetData().__ConchDragon
        ctx.biter.Position = state.segments[6]
        ctx.biter.Velocity = Vector.Zero
        if not ctx.contactHp then ctx.contactHp = ctx.biter.HitPoints end
        ctx.contactTicks = ctx.contactTicks + 1
        return ctx.contactTicks > 40
    end, 45, "an enemy held against the dragon's body")
    plan.check("contact deals 5% of current damage every tick", function(_, ctx)
        -- 40 updates of contact; a bolt may land too if the head swings round.
        local touches, odd = 0, 0
        local mine = ctx.dragon and GetPtrHash(ctx.dragon)
        for _, hit in ipairs(H.dragonHits(ctx.biter)) do
            -- Count the measured dragon's touches; other dragons may brush past too.
            if hit.amount < ctx.contactExpected * 10 and not (mine and hit.dragon and hit.dragon ~= mine) then
                touches = touches + 1
                if not H.near(hit.amount, ctx.contactExpected) then odd = odd + 1 end
            end
        end
        local loss = ctx.contactHp - ctx.biter.HitPoints
        local recorded = H.dragonDamage(ctx.biter)
        return touches >= 39 and touches <= 41 and odd == 0 and math.abs(loss - recorded) <= math.max(0.02, recorded * 0.002),
            string.format("contact hits=%d (39-41 expected, %.3f each) odd=%d HP loss=%.3f recorded=%.3f",
                touches, ctx.contactExpected, odd, loss, recorded)
    end)
    plan.act(function(_, ctx)
        H.recordDragonHits(false)
        if ctx.biter and ctx.biter:Exists() then ctx.biter:Remove() end
        ctx.targets, ctx.biter, ctx.dragon = nil, nil, nil
    end)
end }

-- 진 (Dragon) weather: while enemies are present, tears stat / 5 bolts a second
-- per copy, on their own. A bolt catches its enemy only as often as the holder's
-- luck allows (50% at Isaac's luck 0), so strikes are counted from the weather's
-- own bolt counter, never from hits. The holder never shoots here, so every hit
-- whose source is the player itself is the weather's: bolts for 1x damage,
-- twister touches for 5%. Rain and the dim room are visual only; the rain loop
-- and the hit odds are covered offline and by conch_test rng.
local WEATHER_SPOTS = { { -220, -100 }, { 0, 110 }, { 220, -100 } }
local function pinWeatherTargets(ctx)
    for i, target in ipairs(ctx.targets or {}) do
        local spot = WEATHER_SPOTS[i]
        if target:Exists() then target.Position = ctx.center + Vector(spot[1], spot[2]); target.Velocity = Vector.Zero end
    end
end

local function weatherStrikesExpected(player, n, updates)
    local d = ConchBlessing.dragon.data
    return n * (30 / (player.MaxFireDelay + 1)) / d.tearsDivisor * updates / 30
end

local function watchTwisters(ctx)
    for _, twister in ipairs(ConchBlessing.dragon._twisters) do
        if not ctx.seenTwisters[twister] then ctx.seenTwisters[twister] = true; ctx.risen = ctx.risen + 1 end
    end
end

C.DRAGON = { stage = function(plan, _, n)
    plan.section(string.format("DRAGON / weather with %d cop%s", n, n == 1 and "y" or "ies"),
        n > 0 and "rain falls and the room is dimmed as if under dark clouds" or "no rain and the room's own light")
    plan.act(function(player, ctx)
        H.isolateAttack()
        ctx.center = Game():GetRoom():GetCenterPos()
        player.Position = ctx.center
        ctx.targets = {}
        for i = 1, #WEATHER_SPOTS do ctx.targets[i] = H.target(player, true) end
        pinWeatherTargets(ctx)
        H.recordPlayerHits(true)
    end)
    plan.waitUntil(function(player, ctx)
        pinWeatherTargets(ctx); player.Position = ctx.center
        for _, target in ipairs(ctx.targets) do
            local ready, why = H.targetReady(target)
            if not ready then return false, why end
        end
        return true
    end, 60, "three far-apart targets initialized and vulnerable")
    plan.act(function(_, ctx)
        H.recordPlayerHits(true)
        ctx.hp = {}
        for i, target in ipairs(ctx.targets) do ctx.hp[i] = target.HitPoints end
        ctx.ticks, ctx.risen, ctx.seenTwisters = 0, 0, {}
        ctx.boltsStart = ConchBlessing.dragon._sky.bolts
        for _, twister in ipairs(ConchBlessing.dragon._twisters) do ctx.seenTwisters[twister] = true end
    end)
    plan.waitUntil(function(player, ctx)
        pinWeatherTargets(ctx); player.Position = ctx.center
        watchTwisters(ctx)
        ctx.ticks = ctx.ticks + 1
        return ctx.ticks >= 150
    end, 160, "five seconds of weather")
    plan.waitUntil(function(player, ctx)
        pinWeatherTargets(ctx); player.Position = ctx.center
        ctx.settle = (ctx.settle or 0) + 1
        return ctx.settle >= 6
    end, 8, "HP settles")
    plan.check("bolts follow the tears stat and copies (tears / 5 a second per copy)", function(player, ctx)
        local bolts = ConchBlessing.dragon._sky.bolts - ctx.boltsStart
        local expected = weatherStrikesExpected(player, n, ctx.ticks)
        local strikes = bolts + ctx.risen
        return math.abs(strikes - expected) <= 1.01, string.format("bolts=%d twisters=%d expected=%.2f copies=%d MaxFireDelay=%.2f",
            bolts, ctx.risen, expected, n, player.MaxFireDelay)
    end)
    plan.check("no bolt hits more than one of the far-apart targets", function(player, ctx)
        local hits = #H.playerHits(nil, player.Damage * 0.5)
        local bolts = ConchBlessing.dragon._sky.bolts - ctx.boltsStart
        return hits <= bolts, string.format("hits=%d bolts=%d luck=%.1f", hits, bolts, player.Luck)
    end)
    if n > 0 then
        plan.check("every bolt hits for 1x current damage and HP loss matches", function(player, ctx)
            local wrong = {}
            for _, hit in ipairs(H.playerHits(nil, player.Damage * 0.5)) do
                if not H.near(hit.amount, player.Damage) then wrong[#wrong + 1] = "bolt " .. hit.amount end
            end
            for i, target in ipairs(ctx.targets) do
                local loss = ctx.hp[i] - target.HitPoints
                if math.abs(loss - H.playerDamage(target)) > math.max(0.02, player.Damage * 0.002) then
                    wrong[#wrong + 1] = i .. ":HP loss " .. loss .. " vs hits " .. H.playerDamage(target)
                end
            end
            return #wrong == 0, "wrong=" .. (#wrong > 0 and table.concat(wrong, ",") or "none")
        end)
    end
    local weather = ConchBlessing.dragon and ConchBlessing.dragon.data
    if n >= (weather and weather.twisterMinCopies or 2) then
        -- Twister mechanics with the chance forced to 1 for this check only; the
        -- 5% roll itself is measured by conch_test rng and rng_report.py.
        plan.act(function(player, ctx)
            ctx.chance = ConchBlessing.dragon.data.twisterChance
            ConchBlessing.dragon.data.twisterChance = 1
            ctx.twister, ctx.most = nil, 0
            H.recordPlayerHits(true)
        end)
        plan.waitUntil(function(player, ctx)
            pinWeatherTargets(ctx); player.Position = ctx.center
            ctx.twister = ctx.twister or ConchBlessing.dragon._twisters[#ConchBlessing.dragon._twisters]
            return ctx.twister ~= nil, "no twister yet"
        end, 60, "a bolt rises as a twister")
        plan.act(function(_, ctx)
            ConchBlessing.dragon.data.twisterChance = ctx.chance
            ctx.rose = Vector(ctx.twister.position.X, ctx.twister.position.Y)
            ctx.puller = ctx.targets[2]
            ctx.pullStart = nil
        end)
        plan.waitUntil(function(player, ctx)
            player.Position = ctx.center
            ctx.most = math.max(ctx.most, #ConchBlessing.dragon._twisters)
            -- Hold the others away; let one target go 100px from the twister and watch it come in.
            for i, target in ipairs(ctx.targets) do
                if target ~= ctx.puller and target:Exists() then
                    local spot = WEATHER_SPOTS[i]; target.Position = ctx.center + Vector(spot[1], spot[2]) * 2; target.Velocity = Vector.Zero
                end
            end
            if not ctx.pullStart then
                ctx.puller.Position = ctx.rose + Vector(100, 0); ctx.puller.Velocity = Vector.Zero
                ctx.pullStart = 100
            end
            ctx.pullEnd = ctx.puller.Position:Distance(ctx.rose)
            ctx.waited = (ctx.waited or 0) + 1
            return ctx.waited >= 20
        end, 25, "a target drifts near the twister")
        plan.check("the twister stays where it rose and pulls enemies in", function(_, ctx)
            local still = ctx.twister.position:Distance(ctx.rose) < 0.01
            return still and ctx.pullEnd < ctx.pullStart - 10, string.format("moved=%s distance %d -> %.1f",
                tostring(not still), ctx.pullStart, ctx.pullEnd)
        end)
        plan.check("a twister hurts what it touches for 5% of damage a tick", function(player, ctx)
            local expected = player.Damage * ConchBlessing.dragon.data.twisterDamagePercent
            local touches, odd = 0, 0
            for _, hit in ipairs(H.playerHits(ctx.puller)) do
                if hit.amount < player.Damage * 0.5 then
                    touches = touches + 1
                    if not H.near(hit.amount, expected) then odd = odd + 1 end
                end
            end
            return touches > 0 and odd == 0, string.format("touches=%d odd=%d each=%.3f", touches, odd, expected)
        end)
        plan.check("never more than five twisters at once", function(_, ctx)
            return ctx.most <= ConchBlessing.dragon.data.twisterLimit, "most=" .. ctx.most
        end)
        plan.waitUntil(function(player)
            player.Position = Game():GetRoom():GetCenterPos()
            for _, twister in ipairs(ConchBlessing.dragon._twisters) do
                if twister.age < ConchBlessing.dragon.data.twisterTicks + ConchBlessing.dragon.data.twisterEndTicks - 1 then return false, "twisters still standing" end
            end
            return true
        end, 200, "the twisters run their five seconds")
    end
    plan.act(function(_, ctx)
        if ctx.chance then ConchBlessing.dragon.data.twisterChance = ctx.chance end
        H.recordPlayerHits(false)
        for _, target in ipairs(ctx.targets or {}) do if target:Exists() then target:Remove() end end
        ctx.targets, ctx.twister, ctx.puller, ctx.chance = nil, nil, nil, nil
    end)
end }

for key, spec in pairs({ FIRE_BREATH = { dataKey = "__ConchFireBreath", coef = 0.3 },
    ICE_BREATH = { dataKey = "__ConchIceBreath", coef = 0.2 } }) do
    C[key] = { prepare = function(plan)
        -- Copy/removal checks need one real burst, not a repeated low-luck wait.
        -- The owned-stat matrix separately exercises 15/10/2/1-shot boundaries.
        plan.act(function(player)
            for _ = 1, 14 do player:AddCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT, 0, false) end
        end)
        if key=="ICE_BREATH" then
            H.flameDecayControl(plan)
            H.blueFlameDamageControl(plan)
        end
    end, stage = function(plan, _, n)
        if not ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
            plan.check("real weapon-trigger path", function() return nil, "MC_POST_TRIGGER_WEAPON_FIRED unavailable" end)
            return
        end
        plan.act(function(player, ctx)
            local interval = math.max(1, math.floor(15 - player.Luck))
            local state = player:GetData()[spec.dataKey]
            local previous = state and state.attackCount or 0
            ctx.requiredTriggers = n > 0 and math.max(1, interval - previous) or interval
            H.shoot(player, spec.dataKey, ctx, ctx.requiredTriggers)
        end)
        plan.waitUntil(function(_, ctx)
            return n > 0 and ctx.shots.count > 0 or n == 0 and ctx.shots.triggers >= ctx.requiredTriggers
        end, 300, "required attacks observed")
        plan.act(function() H.stopShooting() end)
        plan.check("real firing spawns only while owned", function(_, ctx)
            local s = ctx.shots
            if s.triggers == 0 then return false, "no real weapon-trigger events received" end
            return (n > 0 and s.count > 0) or (n == 0 and s.count == 0),
                "weapon triggers=" .. s.triggers .. " new projectiles=" .. s.count
        end)
        if n > 0 then
            plan.check("burst occurs at the required real attack count", function(_, ctx)
                return H.expect(ctx.shots.triggers, ctx.requiredTriggers)
            end)
            plan.check("burst projectile count follows current tears", function(player, ctx)
                local expected = math.max(1, math.floor(30 / (math.max(0, player.MaxFireDelay) + 1)))
                return H.expect(ctx.shots.count, expected)
            end)
            plan.check("projectile damage scales with remaining copies", function(player, ctx)
                local expected = player.Damage * spec.coef * n
                if #ctx.shots.damages == 0 then return false, "no spawned damage sample" end
                for _, actual in ipairs(ctx.shots.damages) do
                    if not H.near(actual, expected) then return H.expect(actual, expected) end
                end
                return true, "all samples match " .. expected
            end)
            plan.check("emitted flame status chance follows live luck", function(player, ctx)
                local chance = math.max(0, math.min(1, player.Luck * (key == "FIRE_BREATH" and 0.05 or 0.01)))
                for _, sample in ipairs(ctx.shots.samples) do
                    if not H.near(sample.chance, chance) then return false, "status chance: " .. tostring(sample.chance) .. " expected " .. chance end
                end
                return #ctx.shots.samples > 0, "spawned chance=" .. chance .. "; actual status checked in status_conditions"
            end)
            H.sampleAttackDamage(plan, function(player) return player.Damage * spec.coef * n end,
                function(_, ctx) return ctx.shots.entities[1] end, {blueFlame=key=="ICE_BREATH"})
        else
            plan.check("attack counter cleared after loss", function(player)
                local state = player:GetData()[spec.dataKey]
                return not state or state.attackCount == 0, "no stored attacks while absent"
            end)
        end
    end }
end

C.LIVE_EYE = { stage = function(plan, _, n)
    if not ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED then
        plan.check("real tear hit", function() return nil, "weapon-trigger observer unavailable" end)
        return
    end
    plan.act(function(player, ctx)
        ctx.target = H.target(player)
        ctx.target.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
        ctx.target.CollisionDamage = 0
        ctx.targetHp = ctx.target.HitPoints
        ctx.eyeBefore = ConchBlessing.liveeye.data.damageMultiplier
        H.shoot(player, "conch_liveeye", ctx, 1)
    end)
    plan.waitUntil(function(_, ctx) return ctx.shots.triggers >= 1 end, 90, "first real tear attack")
    plan.act(function() H.stopShooting() end)
    plan.waitUntil(function(_, ctx) return ctx.target.HitPoints < ctx.targetHp end, 90, "first shot actually damages the target")
    plan.wait(2)
    plan.check("real tear hit updates once, and stops after removal", function(_, ctx)
        local expected = n > 0 and math.min(3, ctx.eyeBefore + 0.1) or ctx.eyeBefore
        return H.expect(ConchBlessing.liveeye.data.damageMultiplier, expected)
    end)
    plan.check("live multiplier applies once with duplicate copies", function(player, ctx)
        local expected = ctx.base.Damage * (n > 0 and ConchBlessing.liveeye.data.damageMultiplier or 1)
        return H.expect(player.Damage, expected)
    end)
    plan.act(function(_, ctx)
        if ctx.target then ctx.target:Remove(); ctx.target = nil end
    end)
end }

C.VOID_DAGGER = { prepare = function(plan)
    plan.act(function(player)
        for _=1,200 do player:AddCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT,0,false) end
    end)
end, stage = function(plan,_,n)
    plan.require("confirmed damage proc available",function()
        return require("scripts.lib.damage_provenance").hasAppliedDamageCallback() or nil,"applied-damage callback required"
    end)
    plan.act(function(player,ctx)
        H.isolateAttack()
        player.Position=Game():GetRoom():GetCenterPos()-Vector(180,0)
        ctx.target=H.target(player)
        ctx.beforeLasers={}
        for _,laser in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER,-1,-1)) do ctx.beforeLasers[GetPtrHash(laser)]=true end
        ctx.procDamage=player.Damage
    end)
    H.fireWeaponAtTarget(plan,"tear")
    plan.check("one ring for the real attack; zero after final removal",function(_,ctx)
        local count=0
        for _,entity in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER,-1,-1)) do
            if not ctx.beforeLasers[GetPtrHash(entity)] then count=count+1;ctx.ring=entity:ToLaser() end
        end
        return H.expect(count,n>0 and 1 or 0)
    end)
    if n>0 then
        plan.check("spawned ring uses current player damage",function(_,ctx)
            return ctx.ring and H.near(ctx.ring.CollisionDamage,ctx.procDamage),"ring damage="..tostring(ctx.ring and ctx.ring.CollisionDamage).." expected="..ctx.procDamage
        end)
        plan.act(function(_,ctx) ctx.target:Remove();ctx.target=nil end)
        H.sampleAttackDamage(plan,function(player) return player.Damage end,function(_,ctx) return ctx.ring end)
    end
    plan.act(function(_,ctx) if ctx.target then ctx.target:Remove();ctx.target=nil end end)
end }

-- SFXManager reports whether the lock-on sample is actually playing, which is
-- engine evidence independent of SOFLAM's own sound callbacks.
local function trackLockWarning(ctx)
    local id=SoundEffect.SOUND_DR_REMOTE_WARNING
    local playing=id~=nil and SFXManager():IsPlaying(id)
    if playing and not ctx.warningPlaying then ctx.warningStarts=(ctx.warningStarts or 0)+1 end
    ctx.warningPlaying=playing
end

C.SOFLAM = { prepare = function(plan)
    plan.act(function(player)
        for _=1,200 do player:AddCollectible(CollectibleType.COLLECTIBLE_LUCKY_FOOT,0,false) end
    end)
end, stage = function(plan,_,n)
    plan.require("laser replacement follows actual ownership",function(player)
        if type(player.HasWeaponType)~="function" then return nil,"weapon inspection unavailable" end
        return player:HasWeaponType(WeaponType.WEAPON_LASER)==(n>0)
            and player:HasWeaponType(WeaponType.WEAPON_TEARS)==(n==0),"Technology while held; default tears after removal"
    end)
    plan.require("confirmed damage proc available",function()
        return require("scripts.lib.damage_provenance").hasAppliedDamageCallback() or nil,"applied-damage callback required"
    end)
    plan.act(function(player,ctx)
        H.isolateAttack()
        player.Position=Game():GetRoom():GetCenterPos()-Vector(180,0)
        ctx.target=H.target(player)
        ctx.procDamage=player.Damage
        ctx.strikesBefore=#ConchBlessing.soflam._pendingStrikes
        ctx.warningStarts=0;ctx.warningPlaying=false
    end)
    H.fireWeaponAtTarget(plan,n>0 and "laser" or "tear")
    plan.check("one strike per real attack, independent of item copies; zero when removed",function(_,ctx)
        return H.expect(#ConchBlessing.soflam._pendingStrikes-ctx.strikesBefore,n>0 and 1 or 0)
    end)
    plan.check("lock-on warning plays as the reticle appears; silent when removed",function(_,ctx)
        if not SoundEffect.SOUND_DR_REMOTE_WARNING then return nil,"lock-on warning sound unavailable" end
        trackLockWarning(ctx)
        return H.expect(ctx.warningStarts,n>0 and 1 or 0)
    end)
    plan.wait(2)
    plan.act(function(_,ctx) ctx.hpBeforeStrike=ctx.target.HitPoints end)
    if n>0 then
        plan.waitUntil(function(_,ctx)
            ctx.target.Position=ctx.weaponTargetPosition; ctx.target.Velocity=Vector.Zero
            trackLockWarning(ctx)
            return ctx.target.HitPoints<ctx.hpBeforeStrike and #ConchBlessing.soflam._pendingStrikes==ctx.strikesBefore
        end,120,"laser-designated missile actually damages target and finishes")
        -- The bomb explodes after the strike settles; keep listening past it.
        plan.waitUntil(function(_,ctx)
            trackLockWarning(ctx); ctx.warningTail=(ctx.warningTail or 0)+1
            return ctx.warningTail>=10
        end,12,"listen after the missile lands")
        plan.check("lock-on warning does not replay when the missile lands",function(_,ctx)
            if not SoundEffect.SOUND_DR_REMOTE_WARNING then return nil,"lock-on warning sound unavailable" end
            return ctx.warningStarts==1,"warning starts="..tostring(ctx.warningStarts).." expected=1"
        end)
        plan.check("actual missile HP loss is three times current damage",function(_,ctx)
            local actual,expected=ctx.hpBeforeStrike-ctx.target.HitPoints,ctx.procDamage*3
            return math.abs(actual-expected)<=math.max(0.02,expected*0.002),"HP loss="..actual.." expected="..expected
        end)
    end
    plan.act(function(_,ctx) ctx.target:Remove();ctx.target=nil end)
end }

return C
