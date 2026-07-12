local isc = require("scripts.lib.isaacscript-common")

ConchBlessing.atropos = {}

local DC_DIMENSION = 2
local GOLDEN_TRINKET_FLAG = 32768

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
        choiceCandidate = nil,
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

local function isAppraisalChoiceRoom()
    local appraisal = ConchBlessing.appraisal
    return appraisal
        and appraisal.state
        and appraisal.state.active == true
        and appraisal.state.conversionCompleted == true
end

local function getCurrentRoomKey()
    local level = Game():GetLevel()
    if not level then return nil end

    return table.concat({
        tostring(level:GetStage()),
        tostring(level:GetStageType()),
        tostring(level:GetCurrentRoomIndex()),
        tostring(getCurrentDimension()),
    }, ":")
end

local function normalizeChoiceSubType(variant, subType)
    local id = tonumber(subType)
    if not id then return nil end
    if variant == PickupVariant.PICKUP_TRINKET and id >= GOLDEN_TRINKET_FLAG then
        return id - GOLDEN_TRINKET_FLAG
    end
    return id
end

local function getChoiceVariant(pickup)
    if not pickup then return nil end

    if isAppraisalChoiceRoom() then
        return pickup.Variant == PickupVariant.PICKUP_TRINKET
            and PickupVariant.PICKUP_TRINKET
            or nil
    end

    return pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
        and PickupVariant.PICKUP_COLLECTIBLE
        or nil
end

local function candidateMatchesPickup(candidate, pickingUpItem)
    if not candidate or not pickingUpItem then return false end

    if candidate.variant == PickupVariant.PICKUP_TRINKET then
        if not isc.isPickingUpItemTrinket(nil, pickingUpItem) then return false end
    elseif candidate.variant == PickupVariant.PICKUP_COLLECTIBLE then
        if not isc.isPickingUpItemCollectible(nil, pickingUpItem) then return false end
    else
        return false
    end

    local pickedSubType = pickingUpItem.subType or pickingUpItem.SubType
    return candidate.subType == normalizeChoiceSubType(candidate.variant, pickedSubType)
end

local function canStartChoice(player, pickup)
    if (tonumber(pickup.Wait) or 0) > 0 then return false end
    if type(player.IsItemQueueEmpty) == "function" and not player:IsItemQueueEmpty() then
        return false
    end

    if type(player.CanPickupItem) == "function" then
        local ok, canPickup = pcall(function()
            return player:CanPickupItem()
        end)
        if ok and canPickup == false then return false end
    end

    return true
end

function ConchBlessing.atropos.onPrePickupCollision(_, pickup, collider)
    if not pickup or getCurrentDimension() ~= DC_DIMENSION then return end

    local player = collider and collider:ToPlayer() or nil
    if not player then return end

    local variant = getChoiceVariant(pickup)
    if not variant then return end

    local state = getState()
    local playerKey = isc.getPlayerIndex(nil, player)
    local roomKey = getCurrentRoomKey()
    local pickupKey = GetPtrHash(pickup)
    local candidate = state.choiceCandidate
    if candidate and candidate.roomKey ~= roomKey then
        state.choiceCandidate = nil
        candidate = nil
    end

    if candidate then
        if candidate.playerKey == playerKey and candidate.pickupKey == pickupKey then
            return
        end
        return true
    end

    if not anyoneHasAtropos() or not canStartChoice(player, pickup) then return end

    local subType = normalizeChoiceSubType(variant, pickup.SubType)
    if not subType or subType <= 0 then return end

    state.choiceCandidate = {
        playerKey = playerKey,
        pickupKey = pickupKey,
        roomKey = roomKey,
        variant = variant,
        subType = subType,
    }
end

local function removeRoomPickups(variant)
    local removed = 0
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, variant, -1, false, false)) do
        local pickup = entity:ToPickup()
        if pickup and pickup:Exists() then
            pickup:Remove()
            removed = removed + 1
        end
    end
    return removed
end

function ConchBlessing.atropos.onPostItemPickup(_, player, pickingUpItem)
    if not player or getCurrentDimension() ~= DC_DIMENSION then return end

    local state = getState()
    local playerKey = isc.getPlayerIndex(nil, player)
    local candidate = state.choiceCandidate
    if not candidate
        or candidate.playerKey ~= playerKey
        or candidate.roomKey ~= getCurrentRoomKey()
    then
        return
    end
    if not candidateMatchesPickup(candidate, pickingUpItem) then return end

    state.choiceCandidate = nil
    local removed = removeRoomPickups(candidate.variant)
    ConchBlessing.printDebug(string.format(
        "[Atropos] Removed %d remaining Death Certificate choice pickup(s), variant=%d.",
        removed,
        candidate.variant
    ))
end

function ConchBlessing.atropos.onPostUpdate()
    local state = getState()
    local candidate = state.choiceCandidate
    if candidate then
        local player = isc.getPlayerFromIndex(nil, candidate.playerKey)
        if candidate.roomKey ~= getCurrentRoomKey()
            or not player
            or player:IsItemQueueEmpty()
        then
            state.choiceCandidate = nil
        end
    end

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
    st.choiceCandidate = nil

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

function ConchBlessing.atropos.onGameStarted()
    ConchBlessing.atropos._state = nil
end

ConchBlessing:AddCallbackCustom(
    isc.ModCallbackCustom.POST_ITEM_PICKUP,
    ConchBlessing.atropos.onPostItemPickup
)

return true