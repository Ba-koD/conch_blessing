local isc = require("scripts.lib.isaacscript-common")

ConchBlessing.appraisal = ConchBlessing.appraisal or {}
local M = ConchBlessing.appraisal

M.config = M.config or {
    costCoins = 30,
    replaceMax = 512,
    preferStageAPI = true,
    debug = true,
    scanMaxProbe = 8192,
    scanEmptyLimit = nil,
    queueWaitFrames = 45,
    enterDelayFrames = 20,
    returnRetryFrames = 10,
}

M.state = M.state or {
    active = false,
    prevRoomIndex = nil,
    prevDimension = nil,
    trinketIter = nil,
    spawnedCount = 0,
    cidToTid = {},
    groupId = nil,
    usingDC = false,
    usingStageAPI = false,
    trinketList = nil,
    usedTid = {},
    nextTrinketIndex = 1,
    pendingTrinketId = nil,
    queuedCheckStartedAt = 0,
    pendingPlayerSeed = nil,
    blockFurtherPickups = false,
    pendingReturnToRoom = false,
    lastReturnAttemptFrame = 0,
    returnReadyAtFrame = nil,
}

local function buildTrinketIterator()
    local cfg = Isaac.GetItemConfig()
    if not cfg then
        return function()
            return nil
        end
    end
    local ids = {}
    for id = 1, TrinketType.NUM_TRINKETS - 1 do
        local ok, tr = pcall(function()
            return cfg:GetTrinket(id)
        end)
        if ok and tr then
            table.insert(ids, id)
        end
    end
    local i = 0
    return function()
        i = i + 1
        return ids[i]
    end
end

local function _buildTrinketList()
    local cfg = Isaac.GetItemConfig()
    local list = {}
    if not cfg then return list end
    local maxProbe = (M.config and M.config.scanMaxProbe) or 8192
    local emptyStreak = 0
    local emptyLimit = (M.config and M.config.scanEmptyLimit)
    for id = 1, maxProbe do
        local ok, tr = pcall(function() return cfg:GetTrinket(id) end)
        if ok and tr then
            table.insert(list, id)
            emptyStreak = 0
        else
            emptyStreak = emptyStreak + 1
            if emptyLimit and emptyStreak >= emptyLimit then
                break
            end
        end
    end
    if M.config and M.config.debug then
        ConchBlessing.print(string.format("[Appraisal] Built trinket list: count=%d, maxProbe=%d, emptyLimit=%s", #list, maxProbe, tostring(emptyLimit)))
    end
    return list
end

local function getCurrentDimension(level, roomIndex)
    if level and level.GetDimension then
        local ok, dim = pcall(function() return level:GetDimension() end)
        if ok then return dim end
    end
    level = level or (Game() and Game():GetLevel())
    if not level then return nil end
    local idx = roomIndex or level:GetCurrentRoomIndex()
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

local function mapCollectibleToTrinket(collectibleId)
    if type(collectibleId) ~= "number" or collectibleId <= 0 then return nil end
    if M.state.cidToTid[collectibleId] then return M.state.cidToTid[collectibleId] end
    if not M.state.trinketList then
        M.state.trinketList = _buildTrinketList()
    end
    local maxTrinkets = #(M.state.trinketList)
    if maxTrinkets <= 0 then return nil end

    while M.state.nextTrinketIndex <= maxTrinkets and M.state.usedTid[M.state.trinketList[M.state.nextTrinketIndex]] do
        M.state.nextTrinketIndex = M.state.nextTrinketIndex + 1
    end
    if M.state.nextTrinketIndex > maxTrinkets then
        if M.config and M.config.debug then
            ConchBlessing.print(string.format("[Appraisal] Exhausted trinkets at %d; will remove further collectibles", maxTrinkets))
        end
        return nil
    end

    local mapped = M.state.trinketList[M.state.nextTrinketIndex]
    M.state.nextTrinketIndex = M.state.nextTrinketIndex + 1
    M.state.cidToTid[collectibleId] = mapped
    M.state.usedTid[mapped] = true
    if M.config and M.config.debug then
        ConchBlessing.print(string.format("[Appraisal] Sequential map C:%d -> T:%d (idx=%d)", collectibleId, mapped, M.state.nextTrinketIndex - 1))
    end
    return mapped
end

-- Process a single collectible pickup in DC dimension: replace to trinket or remove
local function processCollectiblePickupInDC(pickup)
    if not pickup or pickup:IsDead() then return end
    if pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return end
    local data = pickup:GetData()
    if data and data.appraisalProcessed then return end
    local cid = pickup.SubType or 0
    local tid = mapCollectibleToTrinket(cid)
    if not tid then
        if M.config and M.config.debug then
            ConchBlessing.print(string.format("[Appraisal] Removing leftover collectible C:%d (no trinket remaining)", cid))
        end
        pickup:Remove()
        if data then data.appraisalProcessed = true end
        return
    end
    local pos = pickup.Position
    pickup:Remove()
    local trinket = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, tid, pos, Vector.Zero, nil)
    if M.config and M.config.debug then
        ConchBlessing.print(string.format("[Appraisal] Replaced C:%d -> T:%d at (%.1f,%.1f)", cid, tid, pos.X, pos.Y))
    end
    if not M.state.groupId then
        local lvl = Game():GetLevel()
        M.state.groupId = tostring(lvl:GetCurrentRoomIndex()) .. ":" .. tostring(Game():GetFrameCount())
    end
    local td = trinket and trinket:GetData() or nil
    if td then
        td.appraisalGroupId = M.state.groupId
        td.appraisalMappedFrom = cid
    end
    M.state.spawnedCount = (M.state.spawnedCount or 0) + 1
    if data then data.appraisalProcessed = true end
end

function M.onUseItem(_, collectibleID, rng, player, useFlags, activeSlot, varData)
    local coins = player:GetNumCoins()
    local cost = M.config.costCoins or 30
    do
        local game = Game()
        local level = game:GetLevel()
        local dim = getCurrentDimension(level)
        if dim == 2 then
            if M.config and M.config.debug then
                ConchBlessing.print("[Appraisal] Cannot use Appraisal Certificate inside AC dimension")
            end
            return { Discharge = false, Remove = false, ShowAnim = false }
        end
    end
    if coins < cost then
        ConchBlessing.print("[Appraisal] Not enough coins (" .. tostring(coins) .. "/" .. tostring(cost) .. ")")
        return { Discharge = false, Remove = false, ShowAnim = false }
    end

    player:AddCoins(-cost)
    local game = Game()
    local level = game:GetLevel()
    M.state.prevRoomIndex = level:GetCurrentRoomIndex()
    do
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
    end
    local prevDim = getCurrentDimension(level)
    M.state.prevDimension = prevDim
    M.state.active = true
    M.state.trinketIter = buildTrinketIterator()
    M.state.spawnedCount = 0
    M.state.cidToTid = {}
    M.state.groupId = nil
    M.state.usingDC = true
    M.state.usingStageAPI = false
    M.state.usedTid = {}
    M.state.nextTrinketIndex = 1

    M.state._enterScheduledAt = nil
    player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, 0)

    return { Discharge = false, Remove = false, ShowAnim = false }
end

function M.onPostPickupInit(_, pickup)
    if not (M.state.active and M.state.usingDC) then
        return
    end
    local level = Game():GetLevel()
    local currentDim = getCurrentDimension(level)
    if currentDim ~= 2 then
        return
    end
    processCollectiblePickupInDC(pickup)
end

function M.onPrePickupCollision(_, pickup, collider, low)
    if not (M.state.active and M.state.usingDC) then
        return
    end
    if pickup.Variant ~= PickupVariant.PICKUP_TRINKET then
        return
    end
    local player = collider and collider:ToPlayer() or nil
    if not player then
        return
    end

    local trinketId = pickup.SubType
    if trinketId and trinketId > 0 then
        if anyoneHasAtropos() then
            return
        end
        if M.state.blockFurtherPickups then
            return true
        end
        M.state.pendingTrinketId = trinketId
        M.state.queuedCheckStartedAt = Game():GetFrameCount()
        M.state.pendingPlayerSeed = player.InitSeed
        M.state.blockFurtherPickups = true
        if M.config and M.config.debug then
            ConchBlessing.print(string.format("[Appraisal] Queued T:%d for smelt after queue clears", trinketId))
        end
        local pickedHash = GetPtrHash(pickup)
        local trinkets = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1, false, false)
        for _, e in ipairs(trinkets) do
            if GetPtrHash(e) ~= pickedHash then
                local p2 = e:ToPickup()
                if p2 then p2:Remove() end
            end
        end
        pcall(function()
            local sfx = SFXManager()
            sfx:Play(SoundEffect.SOUND_HOLY, 1.0, 0, false, 1.0)
        end)
        M.state.pendingReturnToRoom = true
        M.state._enterScheduledAt = nil
        return
    end
end

function M.onPostNewRoom()
    do
        local game = Game()
        local level = game:GetLevel()
        local currentDim = getCurrentDimension(level)
        if M.state.active and M.state.usingDC and currentDim == 2 then
            local entities = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)
            for _, e in ipairs(entities) do
                local p = e:ToPickup()
                if p then
                    processCollectiblePickupInDC(p)
                end
            end
            if M.config and M.config.debug then
                ConchBlessing.print("[Appraisal] Converted collectibles to trinkets on entering DC room")
            end
        end
    end
    if M.state.active and M.state.prevRoomIndex ~= nil then
        local cur = Game():GetLevel():GetCurrentRoomIndex()
        if cur == M.state.prevRoomIndex then
            M.state.active = false
            M.state.trinketIter = nil
            M.state.spawnedCount = 0
            M.state.cidToTid = {}
            M.state.groupId = nil
            M.state.usingDC = false
            M.state.usedTid = {}
            M.state.nextTrinketIndex = 1
            M.state.pendingTrinketId = nil
            M.state.pendingPlayerSeed = nil
            M.state.blockFurtherPickups = false
        end
    end
    if M.state.pendingReturnToRoom and M.state.prevRoomIndex ~= nil then
        local game = Game()
        local level = game:GetLevel()
        local currentDim = getCurrentDimension(level)
        if currentDim == 2 then
            return
        end
        local curIdx = level:GetCurrentRoomIndex()
        local wantIdx = M.state.prevRoomIndex
        if curIdx ~= wantIdx then
            pcall(function()
                level.EnterDoor = -1
                level.LeaveDoor = -1
            end)
            game:StartRoomTransition(wantIdx, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, 0)
            if M.config and M.config.debug then
                ConchBlessing.print(string.format("[Appraisal] Forcing return to pre-DC room idx=%d (cur=%d, dim=%s)", wantIdx, curIdx, tostring(currentDim)))
            end
        else
            if M.config and M.config.debug then
                ConchBlessing.print(string.format("[Appraisal] Already in pre-DC room idx=%d; skipping extra transition", wantIdx))
            end
        end
        M.state.pendingReturnToRoom = false
        M.state.prevRoomIndex = nil
        M.state.prevDimension = nil
        local player = Isaac.GetPlayer(0)
        pcall(function() player:AnimateSad() end)
    end
end

function M.onUpdate()
    if not (M.state.active and M.state.usingDC) then
        return
    end
    local game = Game()
    if M.state._enterScheduledAt and game:GetFrameCount() >= M.state._enterScheduledAt then
        M.state._enterScheduledAt = nil
        local player = Isaac.GetPlayer(0)
        if player then
            player:UseActiveItem(CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE, UseFlag.USE_NOANIM, 0)
            if M.config and M.config.debug then
                ConchBlessing.print("[Appraisal] Entering DC after pre-effect")
            end
        end
    end
    do
        local level = game:GetLevel()
        local currentDim = getCurrentDimension(level)
        if currentDim == 2 then
            local entities = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)
            for _, e in ipairs(entities) do
                local p = e:ToPickup()
                if p then
                    processCollectiblePickupInDC(p)
                end
            end
            local player = Isaac.GetPlayer(0)
            local queued = player and player.QueuedItem or nil
            local hasQueuedTrinket = queued ~= nil and queued.Item ~= nil
            if hasQueuedTrinket and not anyoneHasAtropos() then
                local pickedHash = -1
                local trinkets = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1, false, false)
                for _, e in ipairs(trinkets) do
                    local p2 = e:ToPickup()
                    if p2 then
                        p2:Remove()
                    end
                end
            end
        end
    end
    if not M.state.pendingTrinketId then
        return
    end
    local player = Isaac.GetPlayer(0)
    if not player or (M.state.pendingPlayerSeed and player.InitSeed ~= M.state.pendingPlayerSeed) then
        return
    end
    local queued = player.QueuedItem
    local queueActive = queued ~= nil and queued.Item ~= nil
    local elapsed = game:GetFrameCount() - (M.state.queuedCheckStartedAt or 0)
    if M.config and M.config.debug then
        if elapsed % 15 == 0 then
            ConchBlessing.print(string.format("[Appraisal] Queue polling: active=%s, elapsed=%d", tostring(queueActive), elapsed))
        end
    end
    if queueActive then
        return
    end

    local tid = M.state.pendingTrinketId
    if tid and tid > 0 then
        pcall(function() player:FlushQueueItem() end)
        local ok = pcall(function()
            isc.smeltTrinket(nil, player, tid, 1)
        end)
        if not ok then
            player:AddTrinket(tid, true)
            player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM, 0)
        end
        if player:HasTrinket(tid, true) then
            player:TryRemoveTrinket(tid)
        end
        do
            local trinkets = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TRINKET, -1, false, false)
            for _, e in ipairs(trinkets) do
                local p = e:ToPickup()
                if p then
                    local d = p:GetData()
                    if d and (M.state.groupId and d.appraisalGroupId == M.state.groupId) then
                        p:Remove()
                    end
                end
            end
        end
        if M.state.pendingReturnToRoom and M.state.prevRoomIndex then
            if not anyoneHasAtropos() then
                local level = game:GetLevel()
                pcall(function()
                    level.EnterDoor = -1
                    level.LeaveDoor = -1
                end)
                pcall(function()
                    local sfx = SFXManager()
                    sfx:Stop(SoundEffect.SOUND_DEVIL_CARD)
                    sfx:Stop(SoundEffect.SOUND_DEVILROOM_DEAL)
                    sfx:Stop(SoundEffect.SOUND_EVIL_LAUGH)
                end)
                game:StartRoomTransition(M.state.prevRoomIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, 0)
                if M.config and M.config.debug then
                    ConchBlessing.print(string.format("[Appraisal] Returning after queue delay to idx=%d", M.state.prevRoomIndex))
                end
            end
        end
    end

    M.state.active = false
    M.state.trinketIter = nil
    M.state.spawnedCount = 0
    M.state.cidToTid = {}
    M.state.groupId = nil
    M.state.usingDC = false
    M.state.usedTid = {}
    M.state.nextTrinketIndex = 1
    M.state.pendingTrinketId = nil
    M.state.pendingPlayerSeed = nil
    M.state.blockFurtherPickups = false
    M.state.pendingReturnToRoom = false
end

return M