-- Shared physical doorway geometry for native DC entrances. The nominal LEFT0
-- position can lie outside a narrow room; session ownership remains the caller's.
local M = {}

function M.leftWall(room)
    if not room or type(room.GetClampedPosition) ~= "function"
        or type(room.GetCenterPos) ~= "function"
        or type(room.IsPositionInRoom) ~= "function" then return nil end
    local boundary = room:GetClampedPosition(room:GetCenterPos() - Vector(10000, 0), 0)
    local index = room:GetGridIndex(boundary - Vector(20, 0))
    local position = room:GetGridPosition(index)
    if room:IsPositionInRoom(position, 0)
        or not room:IsPositionInRoom(position + Vector(40, 0), 0) then return nil end
    return index, position
end

function M.spawn(stageAPI, room, name, data)
    local index, position = M.leftWall(room)
    assert(index, "no reachable return-door wall")
    assert(not room:GetDoor(DoorSlot.LEFT0)
        and not stageAPI.GetCustomDoorDataAtSlot(DoorSlot.LEFT0), "return-door slot occupied")
    local nominalIndex = room:GetGridIndex(room:GetDoorSlotPosition(DoorSlot.LEFT0))
    if index == nominalIndex then
        stageAPI.SpawnCustomDoor(DoorSlot.LEFT0, nil, nil, name, data,
            DoorSlot.RIGHT0, nil, RoomTransitionAnim.FADE, nil, false)
    else
        assert(stageAPI.CustomDoorGrid and type(stageAPI.CustomDoorGrid.Spawn) == "function"
            and type(stageAPI.GetCustomGrids) == "function"
            and #stageAPI.GetCustomGrids(index) == 0, "return-door wall unavailable or already owned")
        stageAPI.CustomDoorGrid:Spawn(index, nil, false, {
            Slot = DoorSlot.LEFT0, ExitSlot = DoorSlot.RIGHT0, DoorDataName = name,
            Data = data, TransitionAnim = RoomTransitionAnim.FADE,
        })
    end
    return index, position, nominalIndex
end

return M
