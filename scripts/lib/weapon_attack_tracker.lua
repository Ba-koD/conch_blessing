local WeaponAttackTracker = {}

local DEFAULT_COUNTER_KEY = "attackCount"

-- MC_POST_TRIGGER_WEAPON_FIRED reports one weapon trigger and also supplies
-- FireAmount. Callers count the callback itself: FireAmount describes the
-- trigger's output, not additional player attack inputs. Familiar weapons keep
-- their own owners and must not be folded into a player's counter.
function WeaponAttackTracker.getDirectPlayerOwner(owner)
    if not owner or type(owner.ToPlayer) ~= "function" then
        return nil
    end

    return owner:ToPlayer()
end

function WeaponAttackTracker.resolveDirection(fireDirection, weapon, player)
    if fireDirection and fireDirection:Length() >= 0.1 then
        return fireDirection:Normalized()
    end

    if weapon and type(weapon.GetDirection) == "function" then
        local direction = weapon:GetDirection()
        if direction and direction:Length() >= 0.1 then
            return direction:Normalized()
        end
    end

    if player and type(player.GetShootingInput) == "function" then
        local direction = player:GetShootingInput()
        if direction and direction:Length() >= 0.1 then
            return direction:Normalized()
        end
    end

    return nil
end

function WeaponAttackTracker.advance(state, threshold, counterKey)
    if type(state) ~= "table" then
        return false, 0
    end

    local key = counterKey or DEFAULT_COUNTER_KEY
    local target = math.max(1, math.floor(tonumber(threshold) or 1))
    local count = math.max(0, math.floor(tonumber(state[key]) or 0)) + 1

    if count >= target then
        state[key] = 0
        return true, 0
    end

    state[key] = count
    return false, count
end

function WeaponAttackTracker.reset(state, counterKey)
    if type(state) ~= "table" then
        return
    end

    state[counterKey or DEFAULT_COUNTER_KEY] = 0
end

return WeaponAttackTracker
