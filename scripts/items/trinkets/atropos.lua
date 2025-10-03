ConchBlessing.atropos = {}

local function debugSetCount(numAffected)
    ConchBlessing.printDebug(string.format("[Atropos] Set OptionsPickupIndex=0 for %d pickups in room", tonumber(numAffected) or -1))
end

local function anyoneHasAtropos()
    local id = ConchBlessing.ItemData.ATROPOS and ConchBlessing.ItemData.ATROPOS.id
    if not id or id <= 0 then return false end
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local p = game:GetPlayer(i)
        if p and p:HasTrinket(id) then
            return true
        end
    end
    return false
end

local function getState()
    ConchBlessing.atropos._state = ConchBlessing.atropos._state or {
        lastDimension = nil,
        droppedInCurrentDC = false,
    }
    return ConchBlessing.atropos._state
end

local function getCurrentDimension()
    local game = Game()
    local ok, dim = pcall(function()
        local level = game:GetLevel()
        if not level then return nil end
        local roomIndex = level:GetCurrentRoomIndex()
        if not roomIndex then return nil end
        for i = 0, 2 do
            local roomByIdx = level:GetRoomByIdx(roomIndex, i)
            local currentRoom = level:GetRoomByIdx(roomIndex, -1)
            if roomByIdx and currentRoom and GetPtrHash(roomByIdx) == GetPtrHash(currentRoom) then
                return i
            end
        end
        return nil
    end)
    if ok then return dim else return nil end
end

local DC_DIMENSION = 2

function ConchBlessing.atropos.onPostUpdate()
    if not anyoneHasAtropos() then return end

    local affected = 0
    local entities = Isaac.GetRoomEntities()
    for _, ent in ipairs(entities) do
        if ent and ent:ToPickup() then
            local p = ent:ToPickup()
            if p.OptionsPickupIndex ~= 0 then
                p.OptionsPickupIndex = 0
                affected = affected + 1
            end
        end
    end

    if affected > 0 then
        debugSetCount(affected)
    end
end

function ConchBlessing.atropos.onPostNewRoom()
    local dim = getCurrentDimension()
    local st = getState()
    local last = st.lastDimension

    ConchBlessing.printDebug(string.format("[Atropos] onPostNewRoom: dimension=%s, last=%s, droppedInCurrentDC=%s", tostring(dim), tostring(last), tostring(st.droppedInCurrentDC)))

    if last == DC_DIMENSION and dim ~= DC_DIMENSION then
        st.droppedInCurrentDC = false
    end

    if dim == DC_DIMENSION and last ~= DC_DIMENSION then
        if anyoneHasAtropos() and not st.droppedInCurrentDC then
            local game = Game()
            local room = game:GetRoom()
            local center = room and room:GetCenterPos() or Vector(320, 280)
            Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, Card.CARD_FOOL, center, Vector.Zero, nil)
            st.droppedInCurrentDC = true
            ConchBlessing.printDebug("[Atropos] Dropped The Fool (first entry into Death Certificate dimension)")
        end
    end

    st.lastDimension = dim
end

return true