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
    local ulp = 2 ^ (math.floor(math.log(math.max(1, hpBefore), 2)) - 23)
    local hpTolerance = math.max(0.0001, 2 * ulp, math.abs(expected) * 0.00001)
    local hitTolerance = math.max(0.00001, math.abs(expected) * 0.00001)
    local passed = math.abs(hit.amount - expected) <= hitTolerance
        and math.abs(hpLoss - expected) <= hpTolerance
    return passed, string.format("HP loss=%s expected=%s base=%s factor=%s applied=%s HP tolerance=%s model=%s",
        tostring(hpLoss), tostring(expected), tostring(baseDamage), tostring(factor),
        tostring(hit.amount), tostring(hpTolerance), model or "constant")
end

return O
