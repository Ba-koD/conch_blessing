-- The current room as "placementSeed:stage:stageType:roomIndex:dimension", the
-- key Severed Oath and Family Combo file their per-room pedestal state under.
-- They ask once or twice per pedestal every update; the five numbers are read
-- each time and the string is built again only when one of them changed.
local M = {}

local seed, stage, stageType, roomIndex, dimension, key

local function placementSeed(level)
    if type(level.GetDungeonPlacementSeed) == "function" then
        local ok, value = pcall(level.GetDungeonPlacementSeed, level)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

local function currentDimension(level)
    if type(level.GetDimension) == "function" then
        local ok, value = pcall(level.GetDimension, level)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

function M.current()
    local level = Game():GetLevel()
    if not level then
        return table.concat({ "0", "-1", "-1", "-1", "0" }, ":")
    end
    local s, st, ty = placementSeed(level), level:GetStage(), level:GetStageType()
    local index, dim = level:GetCurrentRoomIndex(), currentDimension(level)
    if key and s == seed and st == stage and ty == stageType and index == roomIndex and dim == dimension then
        return key
    end
    seed, stage, stageType, roomIndex, dimension = s, st, ty, index, dim
    key = table.concat({ tostring(s), tostring(st), tostring(ty), tostring(index), tostring(dim) }, ":")
    return key
end

return M
