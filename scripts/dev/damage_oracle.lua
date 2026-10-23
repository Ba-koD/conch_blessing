-- Independent test expectations. Never read production damage/status fields to
-- derive the promised base damage; callers supply that from the item contract.
local O = {}

function O.blueFlameFactor(hit)
    local age, remaining = hit.age, hit.timeout
    if type(age) ~= "number" or age < 1 or type(remaining) ~= "number" or remaining <= 0 then
        return nil, "missing/expired blue-flame lifetime evidence"
    end
    -- The 2026-10-09 runtime samples match this remaining-lifetime curve.
    -- Every engine bench also checks unmarked vanilla controls before using it.
    return remaining / (remaining + age - 1)
end

-- One float32 unit in the last place at this HP. Isaac stores NPC HP as a
-- float32, so every applied hit is rounded to this step when subtracted.
function O.ulp(hp)
    return 2 ^ (math.floor(math.log(math.max(1, hp), 2)) - 23)
end

function O.evaluate(baseDamage, capture, hpLoss, hpBefore, model)
    if model ~= nil and model ~= "blue_flame" then return false, "unknown damage oracle: " .. tostring(model) end
    if not capture or #capture.hits ~= 1 or (capture.foreignHits or 0) > 0 then
        return false, "isolated first hit required; appliedHits=" .. (capture and #capture.hits or 0)
            .. " foreignHits=" .. (capture and capture.foreignHits or 0)
    end
    local hit = capture.hits[1]
    local factor, err = 1
    if model == "blue_flame" then factor, err = O.blueFlameFactor(hit) end
    if not factor then return false, err end
    local expected = baseDamage * factor
    -- Isaac stores NPC HP as float32. Subtraction at a large HP baseline loses
    -- precision; allow two ULPs, not a broad fixed percentage of the attack.
    local ulp = O.ulp(hpBefore)
    local hpTolerance = math.max(0.0001, 2 * ulp, math.abs(expected) * 0.00001)
    local hitTolerance = math.max(0.00001, math.abs(expected) * 0.00001)
    local passed = math.abs(hit.amount - expected) <= hitTolerance
        and math.abs(hpLoss - expected) <= hpTolerance
    return passed, string.format("HP loss=%s expected=%s base=%s factor=%s applied=%s HP tolerance=%s model=%s",
        tostring(hpLoss), tostring(expected), tostring(baseDamage), tostring(factor),
        tostring(hit.amount), tostring(hpTolerance), model or "constant")
end

-- HP lost over a window of several applied hits against the hits recorded in
-- it. Each hit is subtracted from a float32 HP and rounded to the nearest ULP
-- of the HP at that moment (never coarser than the starting HP's), so the two
-- may differ by at most half a ULP per hit; allow one per hit, never a share
-- of the damage. The caller keeps the HP baseline low (at 100,000 HP one ULP
-- is 1/128 and a 0.175 tick loses 0.003) and closes the window only once no
-- hit is still waiting in the engine's deferred HP update. A baseline so high
-- that the bound could swallow half of the smallest hit fails closed: such a
-- comparison could not see a hit missing from HP.
function O.hpSum(hpBefore, hpAfter, amounts)
    local recorded, smallest = 0, math.huge
    for _, amount in ipairs(amounts) do
        recorded = recorded + amount
        if amount < smallest then smallest = amount end
    end
    local loss = hpBefore - hpAfter
    local tolerance = (#amounts + 1) * O.ulp(hpBefore)
    local detail = string.format("HP loss=%s recorded=%s hits=%d tolerance=%s",
        tostring(loss), tostring(recorded), #amounts, tostring(tolerance))
    if tolerance >= smallest / 2 then
        return false, detail .. " (HP baseline too coarse to resolve one hit of " .. tostring(smallest) .. ")", loss, recorded
    end
    return math.abs(loss - recorded) <= tolerance, detail, loss, recorded
end

return O
