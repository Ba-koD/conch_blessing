local isc = require("scripts.lib.isaacscript-common")

ConchBlessing.appraisal = ConchBlessing.appraisal or {}
local M = ConchBlessing.appraisal
local GOLDEN_TRINKET_FLAG = 32768

-- Configuration
M.config = M.config or {
    costCoins = 30,
    debug = true,
}

-- State
M.state = M.state or {
    active = false,
    prevRoomIndex = nil,
    prevDimension = nil,
    conversionCompleted = false,
    pendingTrinketId = nil,
    pendingPlayerIndex = nil,
    choiceCandidate = nil,
}

local function resetState()
    M.state.active = false
    M.state.prevRoomIndex = nil
    M.state.prevDimension = nil
    M.state.conversionCompleted = false
    M.state.pendingTrinketId = nil
    M.state.pendingPlayerIndex = nil
    M.state.choiceCandidate = nil
end

-- Get current dimension (0 = normal, 1 = ???, 2 = Death Certificate)
local function getCurrentDimension()
    local game = Game()
    local level = game:GetLevel()
    
    if level.GetDimension then
        local ok, dim = pcall(function() return level:GetDimension() end)
        if ok then return dim end
    end
    
    local idx = level:GetCurrentRoomIndex()
    local okRef, ref = pcall(function() return level:GetRoomByIdx(idx, -1) end)
    if not okRef or not ref then return nil end
    
    for i = 0, 2 do
        local okRoom, room = pcall(function() return level:GetRoomByIdx(idx, i) end)
        if okRoom and room and GetPtrHash(room) == GetPtrHash(ref) then
            return i
        end
    end
    
    return nil
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

-- Check if anyone has Atropos trinket (prevents auto-pickup)
local function anyoneHasAtropos()
    local id = ConchBlessing.ItemData and ConchBlessing.ItemData.ATROPOS and ConchBlessing.ItemData.ATROPOS.id
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

local function normalizeTrinketId(trinketId)
    local id = tonumber(trinketId)
    if not id then return nil end
    if id >= GOLDEN_TRINKET_FLAG then
        return id - GOLDEN_TRINKET_FLAG
    end
    return id
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

-- Check if trinket with given ID exists
local function trinketExists(trinketId)
    local cfg = Isaac.GetItemConfig()
    if not cfg then return false end
    
    local ok, trinket = pcall(function() return cfg:GetTrinket(trinketId) end)
    return ok and trinket ~= nil
end

local function getUseBlockReason(player)
    local currentDim = getCurrentDimension()
    if currentDim == 2 then
        return "death_certificate"
    end

    if not player or not player.GetNumCoins then
        return "invalid_player"
    end

    local cost = M.config.costCoins or 30
    if player:GetNumCoins() < cost then
        return "coins", cost, player:GetNumCoins()
    end

    return nil
end

local function logBlockedUse(reason, cost, coins)
    if not M.config.debug then return end

    if reason == "death_certificate" then
        ConchBlessing.print("[Appraisal] Cannot use inside Death Certificate dimension")
    elseif reason == "coins" then
        ConchBlessing.print(string.format("[Appraisal] Not enough coins (%d/%d)", coins or 0, cost or 30))
    elseif reason == "invalid_player" then
        ConchBlessing.print("[Appraisal] Invalid player during item use")
    end
end

-- Convert all collectibles to trinkets in DC dimension
local function convertAllCollectiblesInDC()
    if M.config.debug then
        ConchBlessing.print("[Appraisal] Starting collectible to trinket conversion")
    end
    
    local entities = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)
    local convertedCount = 0
    local removedCount = 0
    
    for _, e in ipairs(entities) do
        local pickup = e:ToPickup()
        if pickup and not pickup:IsDead() then
            local collectibleId = pickup.SubType
            local pos = pickup.Position
            
            -- Remove the collectible
            pickup:Remove()
            
            -- Check if corresponding trinket exists
            if trinketExists(collectibleId) then
                -- Spawn trinket with same ID
                Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, collectibleId, pos, Vector.Zero, nil)
                convertedCount = convertedCount + 1
                
                if M.config.debug then
                    ConchBlessing.print(string.format("[Appraisal] Converted C:%d -> T:%d", collectibleId, collectibleId))
                end
            else
                -- No trinket with this ID, just delete
                removedCount = removedCount + 1
                
                if M.config.debug then
                    ConchBlessing.print(string.format("[Appraisal] Removed C:%d (no trinket exists)", collectibleId))
                end
            end
        end
    end
    
    if M.config.debug then
        ConchBlessing.print(string.format("[Appraisal] Conversion complete: %d converted, %d removed", convertedCount, removedCount))
    end
    
    M.state.conversionCompleted = true
end

-- Use Item callback
function M.onUseItem(_, collectibleID, rng, player, useFlags, activeSlot, varData)
    local game = Game()
    local level = game:GetLevel()

    local reason, cost, coins = getUseBlockReason(player)
    if reason then
        logBlockedUse(reason, cost, coins)
        return { Discharge = false, Remove = false, ShowAnim = false }
    end

    local currentDim = getCurrentDimension()
    cost = M.config.costCoins or 30
    
    -- Consume coins
    player:AddCoins(-cost)
    
    if M.config.debug then
        ConchBlessing.print(string.format("[Appraisal] Used item, consumed %d coins", cost))
    end
    
    -- Clear trinkets using Smelter
    local safety = 0
    while safety < 6 do
        local t0 = player:GetTrinket(0)
        local t1 = player:GetTrinket(1)
        if (not t0 or t0 == 0) and (not t1 or t1 == 0) then
            break
        end
        player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM, 0)
        safety = safety + 1
    end
    
    -- Initialize state
    M.state.active = true
    M.state.prevRoomIndex = level:GetCurrentRoomIndex()
    M.state.prevDimension = currentDim
    M.state.conversionCompleted = false
    M.state.pendingTrinketId = nil
    M.state.pendingPlayerIndex = nil
    M.state.choiceCandidate = nil
    
    -- Use Death Certificate
    player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, 0)
    
    if M.config.debug then
        ConchBlessing.print("[Appraisal] Entering Death Certificate dimension")
    end
    
    return { Discharge = false, Remove = false, ShowAnim = false }
end

function M.onPreUseItem(_, collectibleID, rng, player, useFlags, activeSlot, varData)
    local reason, cost, coins = getUseBlockReason(player)
    if not reason then
        return nil
    end

    logBlockedUse(reason, cost, coins)
    return true
end

-- Post New Room callback
function M.onPostNewRoom()
    if not M.state.active then return end
    
    local currentDim = getCurrentDimension()
    M.state.choiceCandidate = nil
    
    -- Check if we entered Death Certificate dimension
    if currentDim == 2 and not M.state.conversionCompleted then
        convertAllCollectiblesInDC()
    end
    
    -- Any exit from the shared DC dimension ends this Appraisal session.
    if currentDim ~= 2 then
        if M.config.debug then
            ConchBlessing.print("[Appraisal] Left Death Certificate dimension, cleaning up")
        end

        resetState()
    end
end

-- Post Pickup Init callback
function M.onPostPickupInit(_, pickup)
    if not M.state.active then return end
    
    local currentDim = getCurrentDimension()
    if currentDim ~= 2 then return end
    
    -- If conversion already completed, convert any newly spawned collectibles
    if M.state.conversionCompleted and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
        local collectibleId = pickup.SubType
        local pos = pickup.Position
        
        pickup:Remove()
        
        if trinketExists(collectibleId) then
            Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, collectibleId, pos, Vector.Zero, nil)
            if M.config.debug then
                ConchBlessing.print(string.format("[Appraisal] Converted spawned C:%d -> T:%d", collectibleId, collectibleId))
            end
        else
            if M.config.debug then
                ConchBlessing.print(string.format("[Appraisal] Removed spawned C:%d (no trinket)", collectibleId))
            end
        end
    end
end

-- Reserve one physical choice; acquisition is confirmed by POST_ITEM_PICKUP.
function M.onPrePickupCollision(_, pickup, collider, low)
    if not M.state.active then return end
    if getCurrentDimension() ~= 2 or not M.state.conversionCompleted then return end
    if pickup.Variant ~= PickupVariant.PICKUP_TRINKET then return end
    
    local player = collider and collider:ToPlayer() or nil
    if not player then return end
    
    local trinketId = normalizeTrinketId(pickup.SubType)
    if not trinketId or trinketId <= 0 then return end

    -- Atropos keeps the selected trinket instead of smelting and returning.
    if anyoneHasAtropos() then return end

    local playerIndex = isc.getPlayerIndex(nil, player)
    local pickupHash = GetPtrHash(pickup)
    local roomKey = getCurrentRoomKey()
    local candidate = M.state.choiceCandidate
    if candidate and candidate.roomKey ~= roomKey then
        M.state.choiceCandidate = nil
        candidate = nil
    end

    if candidate then
        if candidate.playerIndex == playerIndex and candidate.pickupHash == pickupHash then
            return
        end
        return true
    end

    if not canStartChoice(player, pickup) then return end

    M.state.choiceCandidate = {
        playerIndex = playerIndex,
        pickupHash = pickupHash,
        roomKey = roomKey,
        trinketId = trinketId,
    }
end

function M.onPostItemPickup(_, player, pickingUpItem)
    if not M.state.active or getCurrentDimension() ~= 2 then return end
    if not player or not pickingUpItem then return end
    if not isc.isPickingUpItemTrinket(nil, pickingUpItem) then return end

    local candidate = M.state.choiceCandidate
    local playerIndex = isc.getPlayerIndex(nil, player)
    local pickedTrinketId = normalizeTrinketId(pickingUpItem.subType or pickingUpItem.SubType)
    if not candidate
        or candidate.playerIndex ~= playerIndex
        or candidate.roomKey ~= getCurrentRoomKey()
        or candidate.trinketId ~= pickedTrinketId
    then
        return
    end

    M.state.choiceCandidate = nil
    M.state.pendingTrinketId = candidate.trinketId
    M.state.pendingPlayerIndex = candidate.playerIndex

    local trinkets = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1, false, false)
    for _, e in ipairs(trinkets) do
        local remainingPickup = e:ToPickup()
        if remainingPickup then remainingPickup:Remove() end
    end

    if M.config.debug then
        ConchBlessing.print(string.format(
            "[Appraisal] Confirmed T:%d pickup, will smelt and return",
            candidate.trinketId
        ))
    end

    pcall(function()
        local sfx = SFXManager()
        sfx:Play(SoundEffect.SOUND_HOLY, 1.0, 0, false, 1.0)
    end)
end

function M.onGameStarted()
    resetState()
end

-- Update callback
function M.onUpdate()
    if not M.state.active then return end
    
    local game = Game()

    local candidate = M.state.choiceCandidate
    if candidate then
        local candidatePlayer = isc.getPlayerFromIndex(nil, candidate.playerIndex)
        if candidate.roomKey ~= getCurrentRoomKey()
            or not candidatePlayer
            or candidatePlayer:IsItemQueueEmpty()
        then
            M.state.choiceCandidate = nil
        end
    end

    -- Handle trinket smelting and return
    if M.state.pendingTrinketId then
        local player = isc.getPlayerFromIndex(nil, M.state.pendingPlayerIndex)
        if not player then
            return
        end
        
        -- Check if queue is clear
        local queued = player.QueuedItem
        local queueActive = queued ~= nil and queued.Item ~= nil
        
        if not queueActive then
            local trinketId = M.state.pendingTrinketId
            
            -- Smelt the trinket
            pcall(function() player:FlushQueueItem() end)
            local ok = pcall(function()
                isc.smeltTrinket(nil, player, trinketId, 1)
            end)
            if not ok then
                player:AddTrinket(trinketId, true)
                player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM, 0)
            end
            
            -- Remove trinket if still held
            if player:HasTrinket(trinketId, true) then
                player:TryRemoveTrinket(trinketId)
            end
            
            if M.config.debug then
                ConchBlessing.print(string.format("[Appraisal] Smelted T:%d, returning to original room", trinketId))
            end
            
            -- Return to original room
            if M.state.prevRoomIndex then
                local level = game:GetLevel()
                pcall(function()
                    level.EnterDoor = -1
                    level.LeaveDoor = -1
                end)
                pcall(function()
                    local sfx = SFXManager()
                    sfx:Stop(SoundEffect.SOUND_DEVIL_CARD)
                    sfx:Stop(SoundEffect.SOUND_DEVILROOM_DEAL)
                end)
                game:StartRoomTransition(M.state.prevRoomIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, 0)
            end
            
            M.state.pendingTrinketId = nil
            M.state.pendingPlayerIndex = nil
            M.state.choiceCandidate = nil
        end
    end
end

ConchBlessing:AddCallbackCustom(
    isc.ModCallbackCustom.POST_ITEM_PICKUP,
    M.onPostItemPickup
)

return M
