local isc = require("scripts.lib.isaacscript-common")

ConchBlessing.appraisal = ConchBlessing.appraisal or {}
local M = ConchBlessing.appraisal

-- Configuration
M.config = M.config or {
    costCoins = 30,
    debug = true,
    conversionDelayFrames = 15, -- Delay before converting items after entering DC
}

-- State
M.state = M.state or {
    active = false,
    prevRoomIndex = nil,
    prevDimension = nil,
    conversionScheduledFrame = nil,
    conversionCompleted = false,
    pendingTrinketId = nil,
    pendingPlayerSeed = nil,
    allowedPickupHash = nil,
}

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

-- Check if trinket with given ID exists
local function trinketExists(trinketId)
    local cfg = Isaac.GetItemConfig()
    if not cfg then return false end
    
    local ok, trinket = pcall(function() return cfg:GetTrinket(trinketId) end)
    return ok and trinket ~= nil
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
    local currentDim = getCurrentDimension()
    
    -- Cannot use inside Death Certificate dimension
    if currentDim == 2 then
        if M.config.debug then
            ConchBlessing.print("[Appraisal] Cannot use inside Death Certificate dimension")
        end
        return { Discharge = false, Remove = false, ShowAnim = false }
    end
    
    -- Check if player has enough coins
    local coins = player:GetNumCoins()
    local cost = M.config.costCoins or 30
    
    if coins < cost then
        if M.config.debug then
            ConchBlessing.print(string.format("[Appraisal] Not enough coins (%d/%d)", coins, cost))
        end
        return { Discharge = false, Remove = false, ShowAnim = false }
    end
    
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
    M.state.conversionScheduledFrame = nil
    M.state.conversionCompleted = false
    M.state.pendingTrinketId = nil
    M.state.pendingPlayerSeed = nil
    M.state.allowedPickupHash = nil
    
    -- Use Death Certificate
    player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, 0)
    
    if M.config.debug then
        ConchBlessing.print("[Appraisal] Entering Death Certificate dimension")
    end
    
    return { Discharge = false, Remove = false, ShowAnim = false }
end

-- Post New Room callback
function M.onPostNewRoom()
    if not M.state.active then return end
    
    local game = Game()
    local level = game:GetLevel()
    local currentDim = getCurrentDimension()
    local currentRoomIndex = level:GetCurrentRoomIndex()
    
    -- Check if we entered Death Certificate dimension
    if currentDim == 2 and not M.state.conversionCompleted then
        -- Schedule conversion after a few frames to ensure all items are spawned
        local delayFrames = M.config.conversionDelayFrames or 15
        M.state.conversionScheduledFrame = game:GetFrameCount() + delayFrames
        
        if M.config.debug then
            ConchBlessing.print(string.format("[Appraisal] Entered DC dimension, scheduling conversion in %d frames", delayFrames))
        end
    end
    
    -- Check if we returned to original room
    if M.state.prevRoomIndex and currentRoomIndex == M.state.prevRoomIndex and currentDim ~= 2 then
        if M.config.debug then
            ConchBlessing.print("[Appraisal] Returned to original room, cleaning up")
        end
        
        -- Clean up state
        M.state.active = false
        M.state.prevRoomIndex = nil
        M.state.prevDimension = nil
        M.state.conversionScheduledFrame = nil
        M.state.conversionCompleted = false
        M.state.pendingTrinketId = nil
        M.state.pendingPlayerSeed = nil
        M.state.allowedPickupHash = nil
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

-- Pre Pickup Collision callback (handle trinket pickup)
function M.onPrePickupCollision(_, pickup, collider, low)
    if not M.state.active then return end
    if pickup.Variant ~= PickupVariant.PICKUP_TRINKET then return end
    
    local player = collider and collider:ToPlayer() or nil
    if not player then return end
    
    local trinketId = pickup.SubType
    if not trinketId or trinketId <= 0 then return end
    
    -- Block other trinkets if one is already being picked up
    local ph = GetPtrHash(pickup)
    if M.state.allowedPickupHash == nil then
        M.state.allowedPickupHash = ph
    elseif M.state.allowedPickupHash ~= ph then
        return true -- Block this pickup
    end
    
    -- If player has Atropos, don't auto-smelt
    if anyoneHasAtropos() then return end
    
    -- Store pending trinket for smelting
    M.state.pendingTrinketId = trinketId
    M.state.pendingPlayerSeed = player.InitSeed
    
    if M.config.debug then
        ConchBlessing.print(string.format("[Appraisal] Picked up T:%d, will smelt and return", trinketId))
    end
    
    -- Remove all other trinkets
    local pickedHash = GetPtrHash(pickup)
    local trinkets = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1, false, false)
    for _, e in ipairs(trinkets) do
        if GetPtrHash(e) ~= pickedHash then
            local p = e:ToPickup()
            if p then p:Remove() end
        end
    end
    
    -- Play sound
    pcall(function()
        local sfx = SFXManager()
        sfx:Play(SoundEffect.SOUND_HOLY, 1.0, 0, false, 1.0)
    end)
end

-- Update callback
function M.onUpdate()
    if not M.state.active then return end
    
    local game = Game()
    local currentFrame = game:GetFrameCount()
    local currentDim = getCurrentDimension()
    
    -- Execute scheduled conversion
    if M.state.conversionScheduledFrame and currentFrame >= M.state.conversionScheduledFrame then
        M.state.conversionScheduledFrame = nil
        
        if currentDim == 2 and not M.state.conversionCompleted then
            convertAllCollectiblesInDC()
        end
    end
    
    -- Handle trinket smelting and return
    if M.state.pendingTrinketId then
        local player = Isaac.GetPlayer(0)
        if not player or (M.state.pendingPlayerSeed and player.InitSeed ~= M.state.pendingPlayerSeed) then
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
            M.state.pendingPlayerSeed = nil
            M.state.allowedPickupHash = nil
        end
    end
end

-- Required by item system
function M.onBeforeChange(upgradePos, pickup, itemData)
    if M.config.debug then
        ConchBlessing.print("[Appraisal] onBeforeChange called")
    end
    return true
end

function M.onAfterChange(upgradePos, pickup, itemData)
    if M.config.debug then
        ConchBlessing.print("[Appraisal] onAfterChange called")
    end
end

return M
