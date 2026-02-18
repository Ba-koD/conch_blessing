ConchBlessing.infd6 = {}

local INF_D6_ID = Isaac.GetItemIdByName("Inf D6")

ConchBlessing.infd6.onUse = function(player, collectibleID, useFlags, activeSlot, customVarData)
    if collectibleID ~= INF_D6_ID then
        return
    end

    if not player or not player.Position or not player.GetPlayerType then
        player = Isaac.GetPlayer(0)
        if not player then
            return
        end
    end

    local flags = UseFlag.USE_NOANIM
    local extraFlags = 0
    if type(useFlags) == "number" then
        extraFlags = useFlags
    else
        local coerced = tonumber(useFlags)
        if type(coerced) == "number" then
            extraFlags = coerced
        end
    end
    if extraFlags ~= 0 then
        flags = flags | extraFlags
    end
    if UseFlag and UseFlag.USE_MIMIC then
        flags = flags | UseFlag.USE_MIMIC
    end

    player:UseActiveItem(CollectibleType.COLLECTIBLE_D6, flags, -1)

    return { Discharge = false, Remove = false, ShowAnim = true }
end
