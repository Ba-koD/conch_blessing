local H = require("scripts.dev.item_test_support")
local Edge = require("scripts.dev.item_test_edge_cases")
local C = {}

C.MONEY_TEAR = { prepare = function(plan)
    plan.act(function(player) player:AddCoins(10 - player:GetNumCoins()) end)
end, stage = function(plan, id, n)
    plan.check("coin-scaled tears contribution", function(player)
        return H.expect(H.addition(player, "itemAdditions", id, "Tears"), n * player:GetNumCoins() * 0.066)
    end)
    plan.check("displayed tears", function(player, ctx)
        return H.expect(H.stats(player).Tears, ctx.base.Tears + n * player:GetNumCoins() * 0.066)
    end)
end }

local steroids = {
    ORAL_STEROIDS = { save = "oralSteroids", floor = 0.4 },
    POWER_TRAINING = { save = "powerTraining", floor = 0.5, active = true },
    INJECTABLE_STEROIDS = { save = "injectableSteroids", floor = 0.25, active = true },
}
for key, spec in pairs(steroids) do
    C[key] = { permanent = spec.active, prepare = spec.active and Edge.initialCharge or nil, stage = function(plan, id, n)
        if spec.active and n > 0 then
            plan.act(function(player, ctx)
                if key == "INJECTABLE_STEROIDS" then
                    -- Keep the real death roll. A real 1UP revival independently
                    -- distinguishes its no-stat death branch from a missing use.
                    player:AddCollectible(CollectibleType.COLLECTIBLE_1UP, 0, false)
                    ctx.livesBefore = player:GetExtraLives()
                    ctx.expectedDeathFrames = 300
                end
                H.use(player, id)
            end)
            plan.waitUntil(function(player, ctx)
                if player:IsDead() then return false end
                return #(H.save(player)[spec.save] or {}) == (ctx.uses or 0) + 1
                    or (key == "INJECTABLE_STEROIDS" and player:GetExtraLives() == ctx.livesBefore - 1)
            end, 180, "active use produces a roll or completes revival")
            plan.check("accepted use produces a roll or a real revival", function(player, ctx)
                ctx.expectedDeathFrames = nil
                local died = key == "INJECTABLE_STEROIDS" and player:GetExtraLives() == ctx.livesBefore - 1
                ctx.uses = (ctx.uses or 0) + (died and 0 or 1)
                return #(H.save(player)[spec.save] or {}) == ctx.uses,
                    died and "death roll consumed one 1UP; no stat roll granted" or "one new stat roll"
            end)
        end
        plan.check("stored rolls match copies/uses", function(player, ctx)
            return H.expect(#(H.save(player)[spec.save] or {}), spec.active and (ctx.uses or 0) or n)
        end)
        plan.check("additive roll stacking, floor and removal", function(player)
            local rows = H.save(player)[spec.save] or {}
            for _, stat in ipairs({ "Damage", "Tears", "Range", "Luck" }) do
                if not spec.active and #rows == 0 and H.entry(player, "itemAdditiveMultipliers", id, stat) then
                    return false, "orphan " .. stat .. " entry after final removal"
                end
                local sum = 1
                for _, row in ipairs(rows) do sum = sum + row[string.lower(stat)] - 1 end
                local expected = #rows > 0 and math.max(spec.floor, sum) or 1
                local actual = 1 + H.addition(player, "itemAdditiveMultipliers", id, stat)
                if not H.near(actual, expected) then return false, stat .. ": " .. actual .. " expected " .. expected end
            end
            return true, "four registered totals equal remaining rolls; permanent uses survive active loss"
        end)
        if key == "ORAL_STEROIDS" then
            plan.check("partial removal preserves earlier rolls", function(player, ctx)
                local first = (H.save(player).oralSteroids or {})[1]
                if first and ctx.firstRoll then
                    for stat, value in pairs(ctx.firstRoll) do
                        if first[stat] ~= value then return false, "earlier roll changed: " .. stat end
                    end
                end
                ctx.firstRoll = first and { tears = first.tears, damage = first.damage, range = first.range, luck = first.luck }
                return true, "no reroll on partial removal or repeated evaluation"
            end)
        end
    end }
end

for key, fields in pairs({ F_MINUS = { Luck = 5 }, C_MINUS = { Luck = 4, Tears = 2 },
    B_MINUS = { Luck = 3, Tears = 3, Damage = 3 } }) do
    C[key] = { stage = function(plan, id)
        plan.check("flat bonuses scale with effective trinket copies", function(player, ctx)
            local count = player:GetTrinketMultiplier(id)
            local stats = H.stats(player)
            for stat, amount in pairs(fields) do
                local expected = ctx.base[stat] + amount * count
                if not H.near(stats[stat], expected) then return false, stat .. ": " .. stats[stat] .. " expected " .. expected end
            end
            return true, "normal/golden/remaining copies match"
        end)
    end }
end

C.A_MINUS = { stage = function(plan, id, n)
    plan.check("one stable split; remove all multipliers on loss", function(player, ctx)
        local split = (H.save(player).aMinus or {}).split
        if n > 0 and type(split) ~= "table" then return false, "split not generated" end
        local sum = 0
        local actualStats=H.stats(player)
        local flat={Damage=4,Tears=4,Luck=2}
        for _, stat in ipairs({ "Damage", "Tears", "Luck" }) do
            local entry = H.entry(player, "itemMultipliers", id, stat)
            if n == 0 then
                if entry then return false, "orphan " .. stat .. " multiplier" end
                if not H.near(actualStats[stat],ctx.base[stat]) then return false,stat.." did not restore baseline" end
            else
                if not entry or not H.near(entry.value, split[stat]) then return false, stat .. " split not applied" end
                if split[stat]<0.8 then return false,stat.." multiplier below 0.8" end
                if ctx.split and not H.near(ctx.split[stat], split[stat]) then return false, "split rerolled" end
                local expected=(ctx.base[stat]+flat[stat]*player:GetTrinketMultiplier(id))*split[stat]
                if not H.near(actualStats[stat],expected) then
                    return false,stat.." actual="..actualStats[stat].." expected="..expected
                end
                sum = sum + split[stat]
            end
        end
        if n > 0 then
            ctx.split = { Damage = split.Damage, Tears = split.Tears, Luck = split.Luck }
            return H.expect(sum, 4)
        end
        return true, "no owned multiplier remains"
    end)
end }

for key, spec in pairs({ TIME_POWER = { namespace = "timepowertrinket", field = "damageBonus", rate = 0.006 },
    TIME_TEAR = { namespace = "timeteartrinket", field = "spsBonus", rate = 0.0066 },
    TIME_LUCK = { namespace = "timelucktrinket", field = "luckBonus", rate = 0.01 } }) do
    C[key] = { permanent = true, beforeChange = function(player, ctx, n)
        if n == 0 then
            local s = ConchBlessing[spec.namespace].state.perPlayer[tostring(player:GetPlayerType())]
            ctx.dropTotal = s[spec.field] + s.permanentBonus
        end
    end, stage = function(plan, id, n)
        local function state(player)
            return ConchBlessing[spec.namespace].state.perPlayer[tostring(player:GetPlayerType())]
        end
        plan.act(function(player, ctx)
            local s = state(player)
            ctx.growthBefore = s[spec.field]
            ctx.permanentBefore = s.permanentBonus
            ctx.growthFrame = Game():GetFrameCount()
        end)
        plan.wait(4)
        plan.check("growth rate follows remaining effective copies", function(player, ctx)
            local elapsed = Game():GetFrameCount() - ctx.growthFrame
            local expected = spec.rate / 30 * player:GetTrinketMultiplier(id) * elapsed
            local s = state(player)
            return H.expect(s[spec.field] - ctx.growthBefore, expected)
        end)
        plan.check("dropped bonus becomes permanent once; no continued growth", function(player, ctx)
            local s = state(player)
            if n == 0 then
                return s[spec.field] == 0 and H.near(s.permanentBonus, ctx.permanentBefore)
                    and H.near(s.permanentBonus, ctx.dropTotal)
                    and s.hadTrinketLastFrame == false, "permanent=" .. tostring(s.permanentBonus)
            end
            return s[spec.field] > 0 and H.near(s.permanentBonus, ctx.permanentBefore), "held growth, stable permanent ledger"
        end)
    end }
end

for _, key in ipairs({ "CEIL", "ROUND", "FLOOR" }) do
    C[key] = { stage = function(plan, _, n)
        plan.check("rounding applied once regardless of copies", function(player, ctx)
            local base = require("scripts.lib.character_base_stats").get(player)
            for stat, actual in pairs(H.stats(player)) do
                local expected = ctx.base[stat]
                if n > 0 then
                    local hud = math.floor(expected * 100 + 0.5) / 100
                    if key == "CEIL" then expected = math.ceil(hud)
                    elseif key == "FLOOR" then expected = math.max(math.floor(hud), base[stat])
                    else expected = math.floor(hud + 0.5); if stat ~= "Luck" and hud > 0 then expected = math.max(1, expected) end end
                end
                if not H.near(actual, expected) then return false, stat .. ": " .. actual .. " expected " .. expected end
            end
            return true, "six HUD stats; losing final copy restores baseline"
        end)
    end }
end

C.SEALED_DEMON_SWORD = { prepare = Edge.swordCleave, stage = function(plan, _, n)
    plan.check("speed penalty is presence-based", function(player, ctx)
        return H.expect(player.MoveSpeed, ctx.base.Speed - (n > 0 and 0.2 or 0))
    end)
    H.kill(plan, "sealedDemonSword", "killCount", n > 0 and 1 or 0)
    plan.act(function(_, ctx) ctx.swordDeaths = (ctx.swordDeaths or 0) + (n > 0 and 1 or 0) end)
end, finish = function(plan, id)
    plan.section("SEALED_DEMON_SWORD / all copies evolve at 300 real kills")
    plan.act(function(player)
        for _ = 1, 3 do player:AddCollectible(id, 0, false) end
    end)
    plan.wait(20)
    plan.require("earlier real kills survived inventory changes", function(player, ctx)
        return H.expect((H.save(player).sealedDemonSword or {}).killCount or 0, ctx.swordDeaths)
    end)
    -- Keep the expected count in the fixture, never seed the production counter
    -- to 299. Kill real enemies so the registered death callback must execute.
    for _ = 1, 30 do
        plan.act(function(player, ctx)
            ctx.killTokens = {}
            for _ = 1, math.min(10, 299 - ctx.swordDeaths) do
                H.killTarget(player, ctx)
                ctx.killTokens[#ctx.killTokens + 1] = ctx.deathToken
            end
        end)
        plan.waitUntil(function(player, ctx)
            for _, token in ipairs(ctx.killTokens) do
                if not H.deathObserved(player, { deathToken = token }) then return false end
            end
            return true
        end, 90, "batch of real monster deaths")
        plan.act(function(_, ctx) ctx.swordDeaths = ctx.swordDeaths + #ctx.killTokens end)
    end
    plan.require("299 actual kills reached the production ledger", function(player)
        return H.expect((H.save(player).sealedDemonSword or {}).killCount or 0, 299)
    end)
    plan.check("299 kills do not evolve any of three swords", function(player)
        return player:GetCollectibleNum(id, true) == 3
            and player:GetCollectibleNum(ConchBlessing.ItemData.TYRFING.id, true) == 0,
            "three swords and no Tyrfing before threshold"
    end)
    plan.act(function(player, ctx)
        H.killTarget(player, ctx)
    end)
    plan.waitUntil(H.deathObserved, 90, "300th real target lethal hit and death")
    plan.wait(2)
    plan.check("300th kill converts every sword into one Tyrfing each", function(player)
        local swords = player:GetCollectibleNum(id, true)
        local tyrfings = player:GetCollectibleNum(ConchBlessing.ItemData.TYRFING.id, true)
        return swords == 0 and tyrfings == 3, "swords=" .. swords .. " Tyrfing=" .. tyrfings
    end)
    plan.check("evolution releases sword speed penalty", function(player, ctx)
        return H.expect(player.MoveSpeed, ctx.base.Speed)
    end)
end }

C.TYRFING = { stage = function(plan, _, n)
    H.kill(plan, "tyrfing", "accumulatedDamage", 0.05 * n)
    plan.act(function(player, ctx) ctx.tyrfingBeforeHit = (H.save(player).tyrfing or {}).accumulatedDamage or 0 end)
    H.hit(plan)
    plan.check("hit always loses half regardless of copies; absent item stops tracking", function(player, ctx)
        local expected = ctx.tyrfingBeforeHit * (n > 0 and 0.5 or 1)
        return H.expect((H.save(player).tyrfing or {}).accumulatedDamage or 0, expected)
    end)
    plan.check("accumulated damage applies only while owned", function(player, ctx)
        return H.expect(player.Damage, ctx.base.Damage + (n > 0 and (H.save(player).tyrfing or {}).accumulatedDamage or 0))
    end)
end }

C.ETERNAL_FLAME = { permanent = true, prepare = function(plan)
    plan.act(function(player, ctx)
        -- The generated floor may already have a curse. Remove that fixture
        -- input before acquisition, so only the explicit curse events below
        -- earn rewards. Never reset the item's earned reward ledger.
        local level = Game():GetLevel()
        level:RemoveCurses(level:GetCurses())
        ctx.flameDamage,ctx.flameTears=0,0
        ctx.eternalHeartsBefore=player:GetEternalHearts()
    end)
    plan.require("curse fixture starts clean before acquisition",function()
        return Game():GetLevel():GetCurses()==0,"only explicitly added curses may contribute to this matrix"
    end)
end, stage = function(plan, _, n, index)
    plan.check("one initial eternal heart; no duplicate on stacking or reacquisition",function(player,ctx)
        return H.expect(player:GetEternalHearts(),ctx.eternalHeartsBefore+1)
    end)
    if index == 1 or index == 2 or index == 5 then
        plan.act(function(_, ctx)
            local curses=LevelCurse.CURSE_OF_DARKNESS
            local count=index==2 and 2 or 1
            if count==2 then curses=curses|LevelCurse.CURSE_OF_THE_LOST end
            Game():GetLevel():AddCurse(curses, false)
            ctx.flameDamage = ctx.flameDamage + 3 * n * count
            ctx.flameTears = ctx.flameTears + n * count
        end)
        plan.waitUntil(function() return Game():GetLevel():GetCurses() == 0 end, 300, "curse removed")
    elseif n==0 then
        plan.act(function() Game():GetLevel():AddCurse(LevelCurse.CURSE_OF_DARKNESS,false) end)
        plan.wait(35)
        plan.check("curse is not removed or rewarded while unowned",function()
            return Game():GetLevel():GetCurses()&LevelCurse.CURSE_OF_DARKNESS~=0,"unowned curse stays active"
        end)
        plan.act(function() Game():GetLevel():RemoveCurses(LevelCurse.CURSE_OF_DARKNESS) end)
    end
    -- Rewards are earned at removal with the then-current copy count. Later
    -- inventory changes cannot revoke or retroactively recalculate them.
    plan.check("earned curse damage stays permanent through stack changes and loss", function(player, ctx)
        return H.expect(player.Damage, ctx.base.Damage + ctx.flameDamage)
    end)
    plan.check("earned curse tears stay permanent through stack changes and loss", function(player, ctx)
        return H.expect(30 / (player.MaxFireDelay + 1), ctx.base.Tears + ctx.flameTears)
    end)
end }

return C
