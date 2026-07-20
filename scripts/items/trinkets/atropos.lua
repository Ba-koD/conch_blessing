local isc = require("scripts.lib.isaacscript-common")

local callbackPriority = rawget(_G, "CallbackPriority")
local CALLBACK_PRIORITY_EARLY = type(callbackPriority) == "table"
    and tonumber(callbackPriority.EARLY)
    or -100

ConchBlessing.atropos = ConchBlessing.atropos or {}
local M = ConchBlessing.atropos

local DC_DIMENSION = 2
local DC_ENTRANCE_GRID_INDEX = 80
local SAVE_KEY = "atroposNativeDeathCertificate"
local OPTION_SAVE_KEY = "atroposChoiceOptionGroups"
local SAVE_VERSION = 2
local OPTION_SAVE_VERSION = 1
local RETURN_DOOR_NAME = "ConchBlessingAtroposDeathCertificateReturn"
local RETURN_DOOR_KIND = "atropos_death_certificate_return"
local APPRAISAL_ORIGIN_KIND = "appraisal_stageapi"
local PHASE_PREPARED = "prepared"
local PHASE_CANCELLED = "cancelled"
local PHASE_CLOSING = "closing"

M._confirmedSaveRevision = M._confirmedSaveRevision or 0

local function anyoneHasAtropos()
    local itemData = ConchBlessing.ItemData
    local trinketId = itemData and itemData.ATROPOS and itemData.ATROPOS.id or nil
    if not trinketId or trinketId <= 0 then return false end

    local game = Game()
    for playerIndex = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(playerIndex)
        if player and player:HasTrinket(trinketId) then return true end
    end
    return false
end

local function isAppraisalGalleryRoom()
    local manager = ConchBlessing.GalleryManager
    return type(manager) == "table"
        and type(manager.isCurrentGalleryRoom) == "function"
        and manager.isCurrentGalleryRoom()
end

local function getGalleryManager()
    local manager = ConchBlessing.GalleryManager
    if type(manager) == "table" then return manager end
    return nil
end

local function isAppraisalOrigin(origin)
    return type(origin) == "table" and origin.kind == APPRAISAL_ORIGIN_KIND
end

local function getState()
    M._state = M._state or {
        gameStartedKnown = false,
        lastDimension = nil,
        droppedInCurrentDC = false,
        runtimeTransactionToken = nil,
        nativeSessionReady = false,
        nativeBoundarySavePending = nil,
        continuedSessionFailureReported = false,
        mapFingerprintFailureReported = false,
        optionGroupsReady = false,
        optionGroupsOwnerActive = false,
        optionRestoreNeeded = true,
        optionSaveBlocked = false,
        optionFallbackLinked = false,
        hourglassTransition = nil,
        pendingNativeOrigin = nil,
        returnTransitionIssued = nil,
    }
    return M._state
end

local function getRunSave(create)
    local saveManager = ConchBlessing.SaveManager
    if type(saveManager) ~= "table"
        or type(saveManager.IsLoaded) ~= "function"
        or not saveManager.IsLoaded()
    then
        return nil
    end

    if create then
        if type(saveManager.GetRunSave) ~= "function" then return nil end
        return saveManager.GetRunSave(nil, false)
    end
    if type(saveManager.TryGetRunSave) ~= "function" then return nil end
    return saveManager.TryGetRunSave(nil, false)
end

local function getNativeSave(create)
    local runSave = getRunSave(create)
    if not runSave then return nil end

    local nativeSave = runSave[SAVE_KEY]
    if type(nativeSave) ~= "table" or nativeSave.version ~= SAVE_VERSION then
        if not create then return nil end
        nativeSave = {
            version = SAVE_VERSION,
            active = false,
            sequence = 0,
            rooms = {},
        }
        runSave[SAVE_KEY] = nativeSave
    end
    if type(nativeSave.rooms) ~= "table" then nativeSave.rooms = {} end
    return nativeSave
end

local function getOptionSave(create)
    local runSave = getRunSave(create)
    if not runSave then return nil end

    local optionSave = runSave[OPTION_SAVE_KEY]
    if type(optionSave) ~= "table" or optionSave.version ~= OPTION_SAVE_VERSION then
        if not create then return nil end
        optionSave = {
            version = OPTION_SAVE_VERSION,
            rooms = {},
        }
        runSave[OPTION_SAVE_KEY] = optionSave
    end
    if type(optionSave.rooms) ~= "table" then optionSave.rooms = {} end
    return optionSave
end

local function saveNow()
    local saveManager = ConchBlessing.SaveManager
    if type(saveManager) ~= "table" or type(saveManager.Save) ~= "function" then
        return false
    end

    local before = M._confirmedSaveRevision
    local ok = pcall(function() saveManager.Save() end)
    return ok and M._confirmedSaveRevision > before
end

local function registerSaveConfirmation()
    local saveManager = ConchBlessing.SaveManager
    if type(saveManager) ~= "table"
        or type(saveManager.SaveCallbacks) ~= "table"
        or saveManager.SaveCallbacks.POST_DATA_SAVE == nil
        or type(ConchBlessing.originalMod) ~= "table"
        or type(ConchBlessing.originalMod.AddCallback) ~= "function"
        or M._saveConfirmationRegistered
    then
        return
    end

    ConchBlessing.originalMod:AddCallback(
        saveManager.SaveCallbacks.POST_DATA_SAVE,
        function()
            M._confirmedSaveRevision = M._confirmedSaveRevision + 1
            local state = M._state
            local pending = state and state.nativeBoundarySavePending or nil
            local nativeSave = getNativeSave(false)
            if type(pending) == "table"
                and pending.kind == "begin"
                and nativeSave
                and nativeSave.active == true
                and nativeSave.sessionId == pending.sessionId
            then
                state.nativeBoundarySavePending = nil
                state.nativeSessionReady = true
            elseif type(pending) == "table"
                and pending.kind == "end"
                and nativeSave
                and nativeSave.active ~= true
            then
                state.nativeBoundarySavePending = nil
            end
        end
    )
    M._saveConfirmationRegistered = true
end

local function getCurrentDimension()
    local level = Game():GetLevel()
    if not level then return nil end

    if type(level.GetDimension) == "function" then
        local ok, dimension = pcall(function() return level:GetDimension() end)
        if ok then return dimension end
    end

    local roomIndex = level:GetCurrentRoomIndex()
    local current = level:GetRoomByIdx(roomIndex, -1)
    if not current then return nil end
    for dimension = 0, DC_DIMENSION do
        local room = level:GetRoomByIdx(roomIndex, dimension)
        if room and GetPtrHash(room) == GetPtrHash(current) then
            return dimension
        end
    end
    return nil
end

local function getCurrentRoomContext()
    local level = Game():GetLevel()
    if not level then return nil end

    local descriptor = level:GetCurrentRoomDesc()
    local data = descriptor and descriptor.Data or nil
    local context = {
        stage = level:GetStage(),
        stageType = level:GetStageType(),
        roomIndex = level:GetCurrentRoomIndex(),
        listIndex = descriptor and descriptor.ListIndex or nil,
        spawnSeed = descriptor and descriptor.SpawnSeed or nil,
        decorationSeed = descriptor and descriptor.DecorationSeed or nil,
        awardSeed = descriptor and descriptor.AwardSeed or nil,
        gridIndex = descriptor and descriptor.GridIndex or nil,
        safeGridIndex = descriptor and descriptor.SafeGridIndex or nil,
        roomType = data and data.Type or nil,
        roomVariant = data and data.Variant or nil,
        roomSubType = data and (data.Subtype or data.SubType) or nil,
        dimension = getCurrentDimension(),
    }
    context.key = table.concat({
        tostring(context.stage),
        tostring(context.stageType),
        tostring(context.roomIndex),
        tostring(context.listIndex),
        tostring(context.spawnSeed),
        tostring(context.decorationSeed),
        tostring(context.dimension),
    }, ":")
    return context
end

local function updateChoiceOptionGroups(hasAtropos)
    local optionSave = getOptionSave(hasAtropos)
    if not hasAtropos
        and (not optionSave or type(optionSave.rooms) ~= "table" or next(optionSave.rooms) == nil)
    then
        return true
    end

    local context = getCurrentRoomContext()
    if not context then return false end

    local roomOptions = optionSave
        and optionSave.rooms
        and optionSave.rooms[context.key]
        or nil
    if not hasAtropos and type(roomOptions) ~= "table" then return true end

    local pickups = {}
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity and entity:ToPickup() or nil
        if pickup and pickup:Exists() then pickups[#pickups + 1] = pickup end
    end

    if not hasAtropos then
        for _, pickup in ipairs(pickups) do
            local original = roomOptions[tostring(pickup.InitSeed)]
            if type(original) == "number" and pickup.OptionsPickupIndex == 0 then
                pickup.OptionsPickupIndex = original
            end
        end
        -- Ownership ends with the last holder. Release every saved entry after
        -- the one restoration pass so a later mod-owned zero is never
        -- overwritten by stale Atropos state. A failed save leaves the desired
        -- removal in memory for the next successful run-save write; continue
        -- can safely repeat this idempotent release once.
        optionSave.rooms[context.key] = nil
        saveNow()
        getState().optionFallbackLinked = false
        return true
    end
    if not optionSave then return false end

    if type(roomOptions) ~= "table" then
        roomOptions = {}
        optionSave.rooms[context.key] = roomOptions
    end

    local addedKeys = {}
    for _, pickup in ipairs(pickups) do
        local key = tostring(pickup.InitSeed)
        if roomOptions[key] == nil and pickup.OptionsPickupIndex ~= 0 then
            roomOptions[key] = pickup.OptionsPickupIndex
            addedKeys[#addedKeys + 1] = key
        end
    end

    -- Persist ownership of every option-group mutation before setting it to 0.
    if #addedKeys > 0 and not saveNow() then
        for _, key in ipairs(addedKeys) do roomOptions[key] = nil end
        -- A mixed room (old groups already unlinked, new groups still linked)
        -- would allow multiple vanilla choices. Restore every Atropos-owned
        -- zero and release this room's ownership before falling back to the
        -- engine's original option linkage.
        for _, pickup in ipairs(pickups) do
            local original = roomOptions[tostring(pickup.InitSeed)]
            if type(original) == "number" and pickup.OptionsPickupIndex == 0 then
                pickup.OptionsPickupIndex = original
            end
        end
        optionSave.rooms[context.key] = nil
        getState().optionFallbackLinked = true
        return false
    end

    for _, pickup in ipairs(pickups) do
        if roomOptions[tostring(pickup.InitSeed)] ~= nil then
            pickup.OptionsPickupIndex = 0
        end
    end
    getState().optionFallbackLinked = false
    return true
end

local function synchronizeChoiceOptionsForCollision(pickup)
    local state = getState()
    local hasAtropos = anyoneHasAtropos()
    local ownershipChanged = state.optionGroupsOwnerActive ~= hasAtropos
    if ownershipChanged then
        state.optionGroupsOwnerActive = hasAtropos
        state.optionGroupsReady = false
        state.optionSaveBlocked = false
        state.optionFallbackLinked = false
    end

    local needsSync = ownershipChanged
        or state.optionRestoreNeeded == true
        or (hasAtropos and pickup.OptionsPickupIndex ~= 0)
    if not needsSync then return hasAtropos, true end
    if hasAtropos and state.optionSaveBlocked == true then
        return hasAtropos, state.optionFallbackLinked == true
    end

    state.optionGroupsReady = updateChoiceOptionGroups(hasAtropos)
    state.optionRestoreNeeded = state.optionGroupsReady ~= true
    if hasAtropos and state.optionGroupsReady ~= true then
        state.optionSaveBlocked = true
        return hasAtropos, state.optionFallbackLinked == true
    end
    if not hasAtropos and state.optionGroupsReady ~= true then
        -- We cannot prove that an old Atropos-owned zero was restored, so block
        -- this collision instead of allowing an unlinked choice without owner.
        return hasAtropos, false
    end
    return hasAtropos, true
end

local function getNativeMapFingerprint()
    if type(isc.getRoomsOfDimension) ~= "function" then return nil end

    local ok, descriptors = pcall(isc.getRoomsOfDimension, nil, DC_DIMENSION)
    if not ok or type(descriptors) ~= "table" then return nil end

    local roomTokens = {}
    for _, descriptor in ipairs(descriptors) do
        local data = descriptor and descriptor.Data or nil
        if data then
            roomTokens[#roomTokens + 1] = table.concat({
                tostring(descriptor.ListIndex),
                tostring(descriptor.SafeGridIndex),
                tostring(descriptor.SpawnSeed),
                tostring(descriptor.DecorationSeed),
                tostring(descriptor.AwardSeed),
                tostring(data.Type),
                tostring(data.Variant),
                tostring(data.Subtype or data.SubType),
                tostring(data.Shape),
            }, ":")
        end
    end
    if #roomTokens == 0 then return nil end

    table.sort(roomTokens)
    return table.concat(roomTokens, "|")
end

local function numbersMatch(left, right)
    return tonumber(left) ~= nil
        and tonumber(right) ~= nil
        and tonumber(left) == tonumber(right)
end

local function getDescriptorDimension(descriptor)
    if descriptor and type(descriptor.GetDimension) == "function" then
        local ok, dimension = pcall(function() return descriptor:GetDimension() end)
        if ok then return dimension end
    end
    return nil
end

local function descriptorMatchesSnapshot(snapshot, descriptor, dimension)
    if type(snapshot) ~= "table" or not descriptor then return false end
    local data = descriptor.Data
    if not data then return false end

    local descriptorDimension = getDescriptorDimension(descriptor)
    if descriptorDimension ~= nil
        and not numbersMatch(descriptorDimension, snapshot.dimension)
    then
        return false
    end
    if dimension ~= nil and not numbersMatch(dimension, snapshot.dimension) then
        return false
    end

    return numbersMatch(descriptor.ListIndex, snapshot.listIndex)
        and numbersMatch(descriptor.GridIndex, snapshot.gridIndex)
        and numbersMatch(descriptor.SafeGridIndex, snapshot.safeGridIndex)
        and numbersMatch(descriptor.SpawnSeed, snapshot.spawnSeed)
        and numbersMatch(descriptor.DecorationSeed, snapshot.decorationSeed)
        and numbersMatch(descriptor.AwardSeed, snapshot.awardSeed)
        and numbersMatch(data.Type, snapshot.roomType)
        and numbersMatch(data.Variant, snapshot.roomVariant)
        and numbersMatch(data.Subtype or data.SubType, snapshot.roomSubType)
end

local function snapshotCurrentDescriptor(player)
    local level = Game():GetLevel()
    local descriptor = level and level:GetCurrentRoomDesc() or nil
    local data = descriptor and descriptor.Data or nil
    local dimension = getCurrentDimension()
    local playerIndex = player and isc.getPlayerIndex(nil, player) or nil
    if not level
        or not descriptor
        or not data
        or dimension == nil
        or playerIndex == nil
        or tonumber(descriptor.SafeGridIndex) == nil
        or tonumber(descriptor.SafeGridIndex) < 0
    then
        return nil
    end

    local snapshot = {
        stage = level:GetStage(),
        stageType = level:GetStageType(),
        dimension = dimension,
        roomIndex = level:GetCurrentRoomIndex(),
        listIndex = descriptor.ListIndex,
        gridIndex = descriptor.GridIndex,
        safeGridIndex = descriptor.SafeGridIndex,
        spawnSeed = descriptor.SpawnSeed,
        decorationSeed = descriptor.DecorationSeed,
        awardSeed = descriptor.AwardSeed,
        roomType = data.Type,
        roomVariant = data.Variant,
        roomSubType = data.Subtype or data.SubType,
        playerIndex = playerIndex,
    }
    if not descriptorMatchesSnapshot(snapshot, descriptor, dimension) then return nil end
    return snapshot
end

local function snapshotCurrentEntrance()
    local context = getCurrentRoomContext()
    if not context
        or not numbersMatch(context.dimension, DC_DIMENSION)
        or not numbersMatch(context.roomIndex, DC_ENTRANCE_GRID_INDEX)
        or not numbersMatch(context.gridIndex, DC_ENTRANCE_GRID_INDEX)
        or not numbersMatch(context.safeGridIndex, DC_ENTRANCE_GRID_INDEX)
        or not numbersMatch(context.roomSubType, 33)
    then
        return nil
    end

    return {
        key = context.key,
        stage = context.stage,
        stageType = context.stageType,
        dimension = context.dimension,
        roomIndex = context.roomIndex,
        listIndex = context.listIndex,
        gridIndex = context.gridIndex,
        safeGridIndex = context.safeGridIndex,
        spawnSeed = context.spawnSeed,
        decorationSeed = context.decorationSeed,
        awardSeed = context.awardSeed,
        roomType = context.roomType,
        roomVariant = context.roomVariant,
        roomSubType = context.roomSubType,
    }
end

local function getRoomTransitionMode()
    local roomTransition = rawget(_G, "RoomTransition")
    if type(roomTransition) ~= "table"
        or type(roomTransition.GetTransitionMode) ~= "function"
    then
        return nil
    end
    local ok, mode = pcall(roomTransition.GetTransitionMode)
    if ok and type(mode) == "number" then return mode end
    return nil
end

local function entranceMatchesCurrent(entrance)
    if type(entrance) ~= "table" then return false end
    local level = Game():GetLevel()
    local descriptor = level and level:GetCurrentRoomDesc() or nil
    if not level
        or not numbersMatch(level:GetStage(), entrance.stage)
        or not numbersMatch(level:GetStageType(), entrance.stageType)
        or not numbersMatch(level:GetCurrentRoomIndex(), entrance.roomIndex)
    then
        return false
    end
    return descriptorMatchesSnapshot(entrance, descriptor, getCurrentDimension())
end

local function resolveOriginDescriptor(origin)
    if type(origin) ~= "table" then return nil end
    local level = Game():GetLevel()
    if not level
        or not numbersMatch(level:GetStage(), origin.stage)
        or not numbersMatch(level:GetStageType(), origin.stageType)
    then
        return nil
    end

    local checked = {}
    for _, index in ipairs({ origin.roomIndex, origin.safeGridIndex, origin.gridIndex }) do
        index = tonumber(index)
        if index and not checked[index] then
            checked[index] = true
            local descriptor = level:GetRoomByIdx(index, origin.dimension)
            if descriptorMatchesSnapshot(origin, descriptor, origin.dimension) then
                return descriptor
            end
        end
    end
    return nil
end

local function originIsValid(origin, dcSessionId)
    if isAppraisalOrigin(origin) then
        local manager = getGalleryManager()
        return manager ~= nil
            and type(manager.isDeathCertificateDetourValid) == "function"
            and manager.isDeathCertificateDetourValid(origin, dcSessionId) == true
    end
    return resolveOriginDescriptor(origin) ~= nil
end

local function currentRoomMatchesOrigin(origin)
    if type(origin) ~= "table" then return false end
    if isAppraisalOrigin(origin) then
        local manager = getGalleryManager()
        return manager ~= nil
            and type(manager.isCurrentDeathCertificateOrigin) == "function"
            and manager.isCurrentDeathCertificateOrigin(origin) == true
    end
    local level = Game():GetLevel()
    local descriptor = level and level:GetCurrentRoomDesc() or nil
    local currentRoomIndex = level and level:GetCurrentRoomIndex() or nil
    return level ~= nil
        and numbersMatch(level:GetStage(), origin.stage)
        and numbersMatch(level:GetStageType(), origin.stageType)
        and (numbersMatch(currentRoomIndex, origin.roomIndex)
            or numbersMatch(currentRoomIndex, origin.safeGridIndex)
            or numbersMatch(currentRoomIndex, origin.gridIndex))
        and descriptorMatchesSnapshot(origin, descriptor, getCurrentDimension())
end

local function takeValidatedPendingOrigin(previousDimension)
    local state = getState()
    local pending = state.pendingNativeOrigin
    state.pendingNativeOrigin = nil
    if type(pending) ~= "table"
        or type(pending.origin) ~= "table"
        or not snapshotCurrentEntrance()
    then
        return nil
    end

    local level = Game():GetLevel()
    if not level or type(level.GetPreviousRoomIndex) ~= "function" then return nil end
    local ok, previousRoomIndex = pcall(function() return level:GetPreviousRoomIndex() end)
    if not ok then return nil end

    if isAppraisalOrigin(pending.origin) then
        local origin = pending.origin
        local manager = getGalleryManager()
        local stageAPI = rawget(_G, "StageAPI")
        local previousExtra = type(stageAPI) == "table"
            and stageAPI.PreviousExtraRoomData
            or nil
        local descriptorOK, descriptor = pcall(function()
            return level:GetRoomByIdx(origin.baseRoomIndex)
        end)
        local data = descriptorOK and descriptor and descriptor.Data or nil
        local valid = numbersMatch(previousDimension, origin.underlyingDimension)
            and numbersMatch(level:GetStage(), origin.stage)
            and numbersMatch(level:GetStageType(), origin.stageType)
            and numbersMatch(previousRoomIndex, origin.baseRoomIndex)
            and descriptor ~= nil
            and data ~= nil
            and numbersMatch(data.Variant, origin.baseRoomVariant)
            and numbersMatch(descriptor.SpawnSeed, origin.baseRoomSpawnSeed)
            and type(previousExtra) == "table"
            and numbersMatch(previousExtra.MapID, origin.mapDimension)
            and numbersMatch(previousExtra.RoomID, origin.mapID)
            and numbersMatch(previousExtra.RoomIndex, origin.baseRoomIndex)
            and numbersMatch(previousExtra.RoomVariant, origin.baseRoomVariant)
            and numbersMatch(previousExtra.RoomSeed, origin.baseRoomSpawnSeed)
            and manager ~= nil
            and type(manager.isDeathCertificateDetourPrepared) == "function"
            and manager.isDeathCertificateDetourPrepared(origin) == true
        if not valid then
            if manager and type(manager.abortDeathCertificateDetour) == "function" then
                manager.abortDeathCertificateDetour(origin, nil)
            end
            return nil
        end
        return pending
    end

    if not numbersMatch(previousDimension, pending.origin.dimension)
        or not resolveOriginDescriptor(pending.origin)
        or (not numbersMatch(previousRoomIndex, pending.origin.roomIndex)
            and not numbersMatch(previousRoomIndex, pending.origin.safeGridIndex)
            and not numbersMatch(previousRoomIndex, pending.origin.gridIndex))
    then
        return nil
    end
    return pending
end

local function isStageAPIExtraOrigin()
    local stageAPI = rawget(_G, "StageAPI")
    if type(stageAPI) ~= "table" then return true end

    if type(stageAPI.InOrTransitioningToExtraRoom) == "function" then
        local ok, result = pcall(stageAPI.InOrTransitioningToExtraRoom)
        if not ok or type(result) ~= "boolean" then return true end
        return result
    end
    if stageAPI.TransitioningToExtraRoom == true then return true end
    if type(stageAPI.InExtraRoom) == "function" then
        local ok, result = pcall(stageAPI.InExtraRoom)
        if not ok or type(result) ~= "boolean" then return true end
        return result
    end
    if stageAPI.CurrentLevelMapRoomID ~= nil
        or (stageAPI.CurrentLevelMapID ~= nil
            and stageAPI.CurrentLevelMapID ~= stageAPI.DefaultLevelMapID)
    then
        return true
    end
    -- Without one of StageAPI's explicit extra-room signals the origin cannot
    -- be proven native, so the vanilla Fool remains the only return path.
    return true
end

local function getReturnDoorData(gridData)
    local persistData = gridData and (gridData.PersistData or gridData.PersistentData) or nil
    local data = persistData and persistData.Data or nil
    if type(persistData) ~= "table"
        or persistData.DoorDataName ~= RETURN_DOOR_NAME
        or type(data) ~= "table"
        or data.kind ~= RETURN_DOOR_KIND
    then
        return nil, nil
    end
    return data, persistData
end

local function returnDoorDataMatches(gridData, nativeSave)
    local data, persistData = getReturnDoorData(gridData)
    local entrance = nativeSave and nativeSave.entrance or nil
    return data ~= nil
        and persistData ~= nil
        and numbersMatch(persistData.Slot, DoorSlot.LEFT0)
        and type(nativeSave) == "table"
        and data.sessionId == nativeSave.sessionId
        and type(entrance) == "table"
        and data.entranceKey == entrance.key
end

local function supportsReturnDoor()
    local stageAPI = rawget(_G, "StageAPI")
    local repentogon = rawget(_G, "REPENTOGON")
    local game = Game()
    return M._returnDoorRegistered == true
        and type(repentogon) == "table"
        and repentogon.Real == true
        and type(stageAPI) == "table"
        and stageAPI.Loaded == true
        and type(stageAPI.GetCustomDoorDataAtSlot) == "function"
        and type(stageAPI.GetCustomDoors) == "function"
        and type(stageAPI.SpawnCustomDoor) == "function"
        and type(stageAPI.SetDoorOpen) == "function"
        and game ~= nil
        and type(game.StartRoomTransition) == "function"
        and getRoomTransitionMode() ~= nil
end

local function removeOwnedReturnDoor(nativeSave)
    local stageAPI = rawget(_G, "StageAPI")
    if type(stageAPI) ~= "table" or type(stageAPI.GetCustomDoors) ~= "function" then
        return false
    end

    local removed = false
    local ok, doors = pcall(stageAPI.GetCustomDoors, RETURN_DOOR_NAME)
    if not ok or type(doors) ~= "table" then return false end
    for _, customGrid in ipairs(doors) do
        local data, persistData = getReturnDoorData(customGrid)
        if data
            and persistData
            and numbersMatch(persistData.Slot, DoorSlot.LEFT0)
            and (not nativeSave or not returnDoorDataMatches(customGrid, nativeSave))
            and type(customGrid.Remove) == "function"
        then
            local door = customGrid.Data and customGrid.Data.DoorEntity or nil
            if door and door:Exists() then
                pcall(stageAPI.SetDoorOpen, false, door)
                pcall(function() door:Remove() end)
            end
            local removedOk = pcall(function() customGrid:Remove(true) end)
            removed = removedOk or removed
        end
    end
    return removed
end

local function setReturnDoorOpen(nativeSave, open)
    local stageAPI = rawget(_G, "StageAPI")
    if type(stageAPI) ~= "table"
        or type(stageAPI.GetCustomDoors) ~= "function"
        or type(stageAPI.SetDoorOpen) ~= "function"
    then
        return
    end

    local ok, doors = pcall(stageAPI.GetCustomDoors, RETURN_DOOR_NAME)
    if not ok or type(doors) ~= "table" then return end
    for _, customGrid in ipairs(doors) do
        if returnDoorDataMatches(customGrid, nativeSave) then
            local door = customGrid.Data and customGrid.Data.DoorEntity or nil
            if door then pcall(stageAPI.SetDoorOpen, open, door) end
        end
    end
end

local function rollbackReturnIntent(nativeSave, intent, message)
    local state = getState()
    state.returnTransitionIssued = nil
    nativeSave.returnIntent = nil
    if not saveNow() then nativeSave.returnIntent = intent end
    if message then ConchBlessing.printError(message) end
end

local function tryReturnThroughDoor(doorGridData)
    local state = getState()
    if state.returnDoorSyncInProgress == true
        or state.returnTransitionIssued ~= nil
        or type(state.hourglassTransition) == "table"
        or isAppraisalGalleryRoom()
    then
        return
    end

    local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
    if not nativeSave
        or nativeSave.active ~= true
        or type(nativeSave.transaction) == "table"
        or nativeSave.returnIntent ~= nil
        or not returnDoorDataMatches({ PersistData = doorGridData }, nativeSave)
        or not entranceMatchesCurrent(nativeSave.entrance)
        or not originIsValid(nativeSave.origin, nativeSave.sessionId)
        or not anyoneHasAtropos()
    then
        return
    end

    local player = isc.getPlayerFromIndex(nil, nativeSave.ownerPlayerIndex)
    local game = Game()
    if not player or getRoomTransitionMode() ~= 0 then return end

    local intent = {
        sessionId = nativeSave.sessionId,
        entranceKey = nativeSave.entrance.key,
        targetKind = nativeSave.origin.kind,
        detourId = nativeSave.origin.detourId,
        targetMapDimension = nativeSave.origin.mapDimension,
        targetMapID = nativeSave.origin.mapID,
        originListIndex = nativeSave.origin.listIndex,
        targetSafeGridIndex = nativeSave.origin.safeGridIndex,
        targetDimension = nativeSave.origin.dimension,
    }
    nativeSave.returnIntent = intent
    if not saveNow() then
        nativeSave.returnIntent = nil
        ConchBlessing.printError("Atropos kept its return door closed because the return intent was not saved.")
        return
    end

    -- Arm the process latch before invoking the engine: MC_POST_NEW_ROOM may
    -- run synchronously, and StageAPI evaluates this exit callback every frame.
    state.returnTransitionIssued = nativeSave.sessionId
    setReturnDoorOpen(nativeSave, false)
    local transitioned, transitionError
    if isAppraisalOrigin(nativeSave.origin) then
        local manager = getGalleryManager()
        local callOK, result, reason = pcall(function()
            return manager and manager.returnDeathCertificateDetour(
                nativeSave.origin,
                nativeSave.sessionId,
                player
            )
        end)
        transitioned = callOK and result == true
        transitionError = callOK and reason or result
    else
        transitioned, transitionError = pcall(function()
            game:StartRoomTransition(
                nativeSave.origin.safeGridIndex,
                Direction.NO_DIRECTION,
                RoomTransitionAnim.FADE,
                player,
                nativeSave.origin.dimension
            )
        end)
    end
    local modeAfter = getRoomTransitionMode()
    local sessionEnded = nativeSave.active ~= true
    if not transitioned or (not sessionEnded and (modeAfter == nil or modeAfter == 0)) then
        rollbackReturnIntent(
            nativeSave,
            intent,
            "Atropos could not start its Death Certificate return transition: "
                .. tostring(transitionError or modeAfter)
        )
    end
end

local function syncReturnDoorInner()
    if getCurrentDimension() ~= DC_DIMENSION or isAppraisalGalleryRoom() then return end

    local state = getState()
    local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
    if not nativeSave
        or nativeSave.active ~= true
        or not entranceMatchesCurrent(nativeSave.entrance)
    then
        -- A saved StageAPI custom grid can respawn before this mod has proved
        -- the matching native session. Remove it instead of leaving a passable
        -- wall whose exit callback must reject the player.
        removeOwnedReturnDoor(nil)
        return
    end

    local stageAPI = rawget(_G, "StageAPI")
    if not supportsReturnDoor()
        or not anyoneHasAtropos()
        or not originIsValid(nativeSave.origin, nativeSave.sessionId)
    then
        removeOwnedReturnDoor(nil)
        return
    end

    local room = Game():GetRoom()
    if room and room:GetDoor(DoorSlot.LEFT0) then
        removeOwnedReturnDoor(nil)
        return
    end

    local existing = stageAPI.GetCustomDoorDataAtSlot(DoorSlot.LEFT0)
    if existing and not returnDoorDataMatches(existing, nativeSave) then
        local owned = getReturnDoorData(existing) ~= nil
        if not owned then return end
        removeOwnedReturnDoor(nativeSave)
        existing = stageAPI.GetCustomDoorDataAtSlot(DoorSlot.LEFT0)
        if existing then return end
    end

    if not existing then
        local spawned = pcall(
            stageAPI.SpawnCustomDoor,
            DoorSlot.LEFT0,
            nil,
            nil,
            RETURN_DOOR_NAME,
            {
                kind = RETURN_DOOR_KIND,
                sessionId = nativeSave.sessionId,
                entranceKey = nativeSave.entrance.key,
            },
            DoorSlot.RIGHT0,
            nil,
            RoomTransitionAnim.FADE,
            nil,
            false
        )
        if not spawned then return end
        existing = stageAPI.GetCustomDoorDataAtSlot(DoorSlot.LEFT0, RETURN_DOOR_NAME)
        if not returnDoorDataMatches(existing, nativeSave) then return end
    end

    local open = nativeSave.transaction == nil
        and nativeSave.returnIntent == nil
        and state.returnTransitionIssued == nil
    setReturnDoorOpen(nativeSave, open)
end

local function syncReturnDoor()
    local state = getState()
    if state.returnDoorSyncInProgress == true then return end
    state.returnDoorSyncInProgress = true
    local ok, syncError = pcall(syncReturnDoorInner)
    state.returnDoorSyncInProgress = false
    if not ok and state.returnDoorSyncFailureReported ~= true then
        state.returnDoorSyncFailureReported = true
        ConchBlessing.printError("Atropos could not synchronize its return door: " .. tostring(syncError))
    elseif ok then
        state.returnDoorSyncFailureReported = false
    end
end

local function bindAppraisalOriginIfNeeded(nativeSave)
    local origin = nativeSave and nativeSave.origin or nil
    if not isAppraisalOrigin(origin) then return true end
    local manager = getGalleryManager()
    local bound = manager
        and type(manager.bindDeathCertificateDetour) == "function"
        and manager.bindDeathCertificateDetour(origin, nativeSave.sessionId) == true
    if not bound and manager
        and type(manager.isDeathCertificateDetourValid) == "function"
    then
        bound = manager.isDeathCertificateDetourValid(
            origin,
            nativeSave.sessionId
        ) == true
    end
    if bound then return true end

    if manager and type(manager.abortDeathCertificateDetour) == "function" then
        manager.abortDeathCertificateDetour(origin, nil)
    end
    nativeSave.origin = nil
    nativeSave.ownerPlayerIndex = nil
    nativeSave.entrance = nil
    nativeSave.returnIntent = nil
    if not saveNow() then
        ConchBlessing.printError(
            "Atropos could not persist removal of an unbound Appraisal return origin."
        )
    end
    ConchBlessing.printError(
        "Atropos could not bind Appraisal to its Death Certificate session; The Fool remains available."
    )
    return false
end

local function beginNativeSession(origin, ownerPlayerIndex)
    local state = getState()
    state.nativeSessionReady = false

    local nativeSave = getNativeSave(true)
    if not nativeSave then return nil end

    local mapFingerprint = getNativeMapFingerprint()
    if not mapFingerprint then
        local pending = state.nativeBoundarySavePending
        state.nativeBoundarySavePending = {
            kind = "initialize",
            attempts = type(pending) == "table" and pending.kind == "initialize"
                and (tonumber(pending.attempts) or 0)
                or 0,
            origin = origin,
            ownerPlayerIndex = ownerPlayerIndex,
        }
        if state.mapFingerprintFailureReported ~= true then
            state.mapFingerprintFailureReported = true
            ConchBlessing.printError("Atropos is waiting for the current Death Certificate map.")
        end
        return nil
    end
    state.mapFingerprintFailureReported = false

    local sequence = (tonumber(nativeSave.sequence) or 0) + 1
    local seeds = Game():GetSeeds()
    local startSeed = seeds and seeds:GetStartSeed() or 0
    nativeSave.active = true
    nativeSave.sequence = sequence
    nativeSave.mapFingerprint = mapFingerprint
    nativeSave.sessionId = tostring(startSeed) .. ":" .. tostring(sequence)
    nativeSave.rooms = {}
    nativeSave.transaction = nil
    nativeSave.returnIntent = nil
    nativeSave.foolSpawned = false
    local acceptsOrigin = isAppraisalOrigin(origin)
        or resolveOriginDescriptor(origin) ~= nil
    nativeSave.origin = acceptsOrigin and origin or nil
    nativeSave.ownerPlayerIndex = nativeSave.origin and ownerPlayerIndex or nil
    nativeSave.entrance = nativeSave.origin and snapshotCurrentEntrance() or nil
    if saveNow() then
        bindAppraisalOriginIfNeeded(nativeSave)
        state.nativeSessionReady = true
        state.nativeBoundarySavePending = nil
        state.returnTransitionIssued = nil
        return nativeSave
    end

    state.nativeBoundarySavePending = {
        kind = "begin",
        sessionId = nativeSave.sessionId,
        attempts = 0,
    }
    ConchBlessing.printError("Atropos blocked Death Certificate choices until its session start is saved.")
    return nil
end

local function ensureContinuedNativeSession()
    local state = getState()
    state.nativeSessionReady = false

    local nativeSave = getNativeSave(false)
    local mapFingerprint = getNativeMapFingerprint()
    if type(mapFingerprint) ~= "string" then
        local pending = state.nativeBoundarySavePending
        state.nativeBoundarySavePending = {
            kind = "continue",
            attempts = type(pending) == "table" and pending.kind == "continue"
                and (tonumber(pending.attempts) or 0)
                or 0,
        }
        return nil
    end
    if not nativeSave
        or nativeSave.active ~= true
        or type(nativeSave.sessionId) ~= "string"
        or nativeSave.mapFingerprint ~= mapFingerprint
    then
        state.nativeBoundarySavePending = nil
        if state.continuedSessionFailureReported ~= true then
            state.continuedSessionFailureReported = true
            ConchBlessing.printError(
                "Atropos found no matching saved Death Certificate session; choices remain locked."
            )
        end
        return nil
    end

    if isAppraisalOrigin(nativeSave.origin)
        and not originIsValid(nativeSave.origin, nativeSave.sessionId)
    then
        local manager = getGalleryManager()
        if manager
            and type(manager.isDeathCertificateDetourPrepared) == "function"
            and manager.isDeathCertificateDetourPrepared(nativeSave.origin) == true
        then
            bindAppraisalOriginIfNeeded(nativeSave)
        end
    end
    if isAppraisalOrigin(nativeSave.origin)
        and not originIsValid(nativeSave.origin, nativeSave.sessionId)
    then
        local staleOrigin = nativeSave.origin
        local manager = getGalleryManager()
        if manager and type(manager.abortDeathCertificateDetour) == "function" then
            manager.abortDeathCertificateDetour(staleOrigin, nativeSave.sessionId)
        end
        nativeSave.origin = nil
        nativeSave.ownerPlayerIndex = nil
        nativeSave.entrance = nil
        nativeSave.returnIntent = nil
        if not saveNow() then
            ConchBlessing.printError(
                "Atropos could not persist removal of a stale Appraisal return origin."
            )
        end
    elseif nativeSave.returnIntent ~= nil and not isAppraisalOrigin(nativeSave.origin) then
        local interruptedIntent = nativeSave.returnIntent
        nativeSave.returnIntent = nil
        if not saveNow() then
            nativeSave.returnIntent = interruptedIntent
            ConchBlessing.printError(
                "Atropos kept an interrupted return intent closed; The Fool remains available."
            )
        end
    end

    state.nativeSessionReady = true
    state.nativeBoundarySavePending = nil
    return nativeSave
end

local function endNativeSession()
    local state = getState()
    state.nativeSessionReady = false
    state.returnTransitionIssued = nil
    state.pendingNativeOrigin = nil

    local nativeSave = getNativeSave(false)
    if not nativeSave then
        state.nativeBoundarySavePending = nil
        return true
    end

    -- Keep an inactive tombstone so the monotonic sequence survives repeated
    -- visits in the same run. Deleting the key would let stale disk state and a
    -- reused session ID collide after consecutive boundary-save failures.
    nativeSave.active = false
    nativeSave.sessionId = nil
    nativeSave.mapFingerprint = nil
    nativeSave.rooms = {}
    nativeSave.transaction = nil
    nativeSave.foolSpawned = nil
    nativeSave.origin = nil
    nativeSave.ownerPlayerIndex = nil
    nativeSave.entrance = nil
    nativeSave.returnIntent = nil
    if saveNow() then
        state.nativeBoundarySavePending = nil
        return true
    end

    state.nativeBoundarySavePending = { kind = "end", attempts = 0 }
    ConchBlessing.printError("Atropos will retry saving its Death Certificate session end.")
    return false
end

local function settleCurrentAppraisalDetour()
    if not isAppraisalGalleryRoom() then return false end
    local state = getState()
    local manager = getGalleryManager()
    if not manager
        or type(manager.getDeathCertificateDetour) ~= "function"
        or type(manager.markDeathCertificateDetourArrived) ~= "function"
        or type(manager.completeDeathCertificateDetourArrival) ~= "function"
    then
        return false
    end

    local pending = state.pendingAppraisalDetourCompletion
    local nativeSave = getNativeSave(false)
    if type(pending) ~= "table" then
        if nativeSave
            and nativeSave.active == true
            and isAppraisalOrigin(nativeSave.origin)
            and type(nativeSave.sessionId) == "string"
            and currentRoomMatchesOrigin(nativeSave.origin)
        then
            pending = {
                origin = nativeSave.origin,
                dcSessionId = nativeSave.sessionId,
                underlyingDimension = nativeSave.origin.underlyingDimension,
            }
        else
            local detour = manager.getDeathCertificateDetour()
            if nativeSave and nativeSave.active == true then return false end
            if type(detour) ~= "table"
                or detour.phase ~= "arrived"
                or type(detour.dcSessionId) ~= "string"
                or manager.isCurrentDeathCertificateOrigin(detour) ~= true
            then
                return false
            end
            pending = {
                origin = detour,
                dcSessionId = detour.dcSessionId,
                underlyingDimension = detour.underlyingDimension,
            }
        end

        local marked, markReason = manager.markDeathCertificateDetourArrived(
            pending.origin,
            pending.dcSessionId
        )
        if marked ~= true then
            ConchBlessing.printError(
                "Atropos could not persist its return to Appraisal: "
                    .. tostring(markReason)
            )
            return false
        end
        state.pendingAppraisalDetourCompletion = pending
    end

    nativeSave = getNativeSave(false)
    if nativeSave and nativeSave.active == true then
        if nativeSave.sessionId ~= pending.dcSessionId
            or not isAppraisalOrigin(nativeSave.origin)
        then
            return false
        end
        if not endNativeSession() then return false end
    elseif type(state.nativeBoundarySavePending) == "table" then
        return false
    end

    local completed, completionReason = manager.completeDeathCertificateDetourArrival(
        pending.origin,
        pending.dcSessionId
    )
    if completed ~= true then
        ConchBlessing.printError(
            "Atropos could not close its completed Appraisal detour: "
                .. tostring(completionReason)
        )
        return false
    end
    state.pendingAppraisalDetourCompletion = nil
    state.returnTransitionIssued = nil
    state.droppedInCurrentDC = false
    state.lastDimension = tonumber(pending.underlyingDimension)
    return true
end

local function endNativeSessionAndAbortAppraisalDetour(nativeSave)
    local state = getState()
    local origin = nativeSave and nativeSave.origin or nil
    local dcSessionId = nativeSave and nativeSave.sessionId or nil
    local isDetour = isAppraisalOrigin(origin) and type(dcSessionId) == "string"
    local ended = endNativeSession()
    if not isDetour then return ended end
    local pending = {
        origin = origin,
        dcSessionId = dcSessionId,
    }
    if not ended then
        state.pendingAppraisalDetourAbort = pending
        return false
    end
    local manager = getGalleryManager()
    local aborted = manager
        and type(manager.abortDeathCertificateDetour) == "function"
        and manager.abortDeathCertificateDetour(origin, dcSessionId) == true
    if not aborted then
        state.pendingAppraisalDetourAbort = pending
        return false
    end
    state.pendingAppraisalDetourAbort = nil
    return true
end

local function finishPendingAppraisalDetourAbort()
    if isAppraisalGalleryRoom() or getCurrentDimension() == DC_DIMENSION then
        return false
    end
    local state = getState()
    local manager = getGalleryManager()
    if not manager or type(manager.abortDeathCertificateDetour) ~= "function" then
        return false
    end
    local pending = state.pendingAppraisalDetourAbort
    local nativeSave = getNativeSave(false)
    if type(pending) ~= "table"
        and (not nativeSave or nativeSave.active ~= true)
        and type(manager.getDeathCertificateDetour) == "function"
    then
        local detour = manager.getDeathCertificateDetour()
        if type(detour) == "table"
            and type(detour.dcSessionId) == "string"
            and (detour.phase == "active"
                or detour.phase == "reentering"
                or detour.phase == "arrived")
        then
            pending = { origin = detour, dcSessionId = detour.dcSessionId }
            state.pendingAppraisalDetourAbort = pending
        end
    end
    if type(pending) ~= "table"
        or (nativeSave and nativeSave.active == true)
        or type(state.nativeBoundarySavePending) == "table"
    then
        return false
    end
    if manager.abortDeathCertificateDetour(
        pending.origin,
        pending.dcSessionId
    ) ~= true then
        return false
    end
    state.pendingAppraisalDetourAbort = nil
    return true
end

local function resumeAppraisalReturnIfNeeded()
    local state = getState()
    local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
    if getCurrentDimension() ~= DC_DIMENSION
        or isAppraisalGalleryRoom()
        or state.returnTransitionIssued ~= nil
        or not nativeSave
        or nativeSave.active ~= true
        or not isAppraisalOrigin(nativeSave.origin)
        or type(nativeSave.returnIntent) ~= "table"
        or nativeSave.returnIntent.sessionId ~= nativeSave.sessionId
        or not entranceMatchesCurrent(nativeSave.entrance)
        or not originIsValid(nativeSave.origin, nativeSave.sessionId)
        or getRoomTransitionMode() ~= 0
    then
        return false
    end
    local player = isc.getPlayerFromIndex(nil, nativeSave.ownerPlayerIndex)
    local manager = getGalleryManager()
    if not player or not manager
        or type(manager.returnDeathCertificateDetour) ~= "function"
    then
        return false
    end
    state.returnTransitionIssued = nativeSave.sessionId
    setReturnDoorOpen(nativeSave, false)
    local callOK, transitioned, reason = pcall(
        manager.returnDeathCertificateDetour,
        nativeSave.origin,
        nativeSave.sessionId,
        player
    )
    if callOK and transitioned == true then return true end
    rollbackReturnIntent(
        nativeSave,
        nativeSave.returnIntent,
        "Atropos could not resume its Appraisal return transition: "
            .. tostring(callOK and reason or transitioned)
    )
    return false
end

local function retryNativeBoundarySave()
    local state = getState()
    local pending = state.nativeBoundarySavePending
    if type(pending) ~= "table" then return end
    local attempts = tonumber(pending.attempts) or 0
    if attempts >= 1 then return end
    pending.attempts = attempts + 1

    local dimension = getCurrentDimension()
    local nativeSave = getNativeSave(false)
    if pending.kind == "initialize" then
        if dimension == DC_DIMENSION then
            beginNativeSession(pending.origin, pending.ownerPlayerIndex)
        end
    elseif pending.kind == "continue" then
        if dimension == DC_DIMENSION then ensureContinuedNativeSession() end
    elseif pending.kind == "begin" then
        if dimension ~= DC_DIMENSION
            or not nativeSave
            or nativeSave.active ~= true
            or nativeSave.sessionId ~= pending.sessionId
        then
            return
        end
        if saveNow() then
            bindAppraisalOriginIfNeeded(nativeSave)
            state.nativeBoundarySavePending = nil
            state.nativeSessionReady = true
        end
    elseif pending.kind == "end" then
        if (dimension == DC_DIMENSION and not isAppraisalGalleryRoom())
            or not nativeSave
            or nativeSave.active == true
        then
            return
        end
        if saveNow() then state.nativeBoundarySavePending = nil end
    end
end

function M.clearPendingDeathCertificateOrigin()
    local state = M._state
    if state then state.pendingNativeOrigin = nil end
end

function M.onPreUseDeathCertificate(_, collectibleId, _, player)
    local state = getState()
    -- Every invocation invalidates an older candidate first so a failed or
    -- superseded use cannot bind its origin to a later dimension-2 entry.
    M.clearPendingDeathCertificateOrigin()
    if collectibleId ~= CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE
        or state.gameStartedKnown ~= true
        or not player
        or type(state.hourglassTransition) == "table"
        or getRoomTransitionMode() ~= 0
    then
        return
    end

    if isAppraisalGalleryRoom() then
        if not anyoneHasAtropos() then return end
        local manager = getGalleryManager()
        local origin, reason
        if manager and type(manager.prepareDeathCertificateDetour) == "function" then
            origin, reason = manager.prepareDeathCertificateDetour(player)
        end
        if origin then
            state.pendingNativeOrigin = {
                origin = origin,
                playerIndex = origin.playerIndex,
            }
        else
            ConchBlessing.printError(
                "Atropos could not prepare Appraisal's Death Certificate return: "
                    .. tostring(reason or "manager_unavailable")
            )
        end
        -- Never cancel Death Certificate. If exact Appraisal capture failed,
        -- vanilla still enters dimension 2 and The Fool remains its escape.
        return
    end

    if getCurrentDimension() == DC_DIMENSION or isStageAPIExtraOrigin() then
        return
    end

    local origin = snapshotCurrentDescriptor(player)
    if not origin then return end
    state.pendingNativeOrigin = {
        origin = origin,
        playerIndex = origin.playerIndex,
    }
end

local function spawnFoolIfNeeded(state)
    if state.droppedInCurrentDC or not anyoneHasAtropos() then return end

    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_TAROTCARD,
        Card.CARD_FOOL,
        false,
        false
    )) do
        local pickup = entity:ToPickup()
        if pickup and pickup:Exists() then
            state.droppedInCurrentDC = true
            local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
            if nativeSave and nativeSave.foolSpawned ~= true then
                nativeSave.foolSpawned = true
                saveNow()
            end
            return
        end
    end

    local room = Game():GetRoom()
    local center = room and room:GetCenterPos() or Vector(320, 280)
    Isaac.Spawn(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_TAROTCARD,
        Card.CARD_FOOL,
        center,
        Vector.Zero,
        nil
    )
    state.droppedInCurrentDC = true
    local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
    if nativeSave and nativeSave.foolSpawned ~= true then
        nativeSave.foolSpawned = true
        saveNow()
    end
    ConchBlessing.printDebug("[Atropos] Dropped The Fool in Death Certificate.")
end

local function resumeHourglassNativeSession()
    local state = getState()
    state.nativeSessionReady = false
    state.nativeBoundarySavePending = nil
    state.runtimeTransactionToken = nil
    state.optionGroupsReady = false
    state.optionRestoreNeeded = true
    state.optionSaveBlocked = false
    state.optionFallbackLinked = false

    local nativeSave = ensureContinuedNativeSession()
    if nativeSave then
        -- Preserve the exact first-room Fool state instead of assuming that
        -- Atropos was already held when the rewound DC session began.
        state.droppedInCurrentDC = nativeSave.foolSpawned == true
        return true
    end

    state.droppedInCurrentDC = false
    spawnFoolIfNeeded(state)
    return false
end

local function tryFinalizeHourglassTransition()
    local state = getState()
    local transition = state.hourglassTransition
    if type(transition) ~= "table"
        or transition.postResetSeen ~= true
        or transition.targetRoomSeen ~= true
    then
        return false
    end

    local targetDimension = transition.targetDimension
    state.hourglassTransition = nil
    state.lastDimension = targetDimension
    if targetDimension == DC_DIMENSION then
        resumeHourglassNativeSession()
    else
        -- The restored run save is authoritative outside Death Certificate.
        -- Do not overwrite it with a fresh end-session tombstone.
        state.nativeSessionReady = false
        state.nativeBoundarySavePending = nil
        state.droppedInCurrentDC = false
    end
    return true
end

function M.onPreHourglassReset()
    local state = getState()
    state.hourglassTransition = {
        postResetSeen = false,
        targetRoomSeen = false,
        sourceDimension = getCurrentDimension(),
    }
    state.nativeSessionReady = false
    state.runtimeTransactionToken = nil
    state.pendingNativeOrigin = nil
    state.returnTransitionIssued = nil
end

function M.onPostHourglassReset()
    local state = getState()
    local transition = state.hourglassTransition
    if type(transition) ~= "table" then
        transition = {
            postResetSeen = false,
            targetRoomSeen = false,
            sourceDimension = nil,
        }
        state.hourglassTransition = transition
    end
    transition.postResetSeen = true
    state.nativeBoundarySavePending = nil
    state.runtimeTransactionToken = nil
    state.pendingNativeOrigin = nil
    state.returnTransitionIssued = nil
    state.optionGroupsReady = false
    state.optionRestoreNeeded = true
    state.optionSaveBlocked = false
    state.optionFallbackLinked = false
    tryFinalizeHourglassTransition()
end

local function removeRoomCollectibles()
    local removed = 0
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_COLLECTIBLE,
        -1,
        false,
        false
    )) do
        local pickup = entity:ToPickup()
        if pickup and pickup:Exists() then
            pickup:Remove()
            removed = removed + 1
        end
    end
    return removed
end

local function enforceCompletedRoom(nativeSave, context)
    local roomState = nativeSave
        and context
        and nativeSave.rooms
        and nativeSave.rooms[context.key]
        or nil
    if type(roomState) ~= "table"
        or roomState.completed ~= true
        or roomState.committed ~= true
    then
        return false
    end
    removeRoomCollectibles()
    return true
end

local function canStartChoice(player, pickup)
    if (tonumber(pickup.Wait) or 0) > 0 then return false end
    if type(player.IsItemQueueEmpty) ~= "function" or not player:IsItemQueueEmpty() then
        return false
    end
    if type(player.CanPickupItem) == "function" then
        local ok, canPickup = pcall(function() return player:CanPickupItem() end)
        if ok and canPickup == false then return false end
    end
    return true
end

local function findPreparedSource(transaction)
    local state = getState()
    local room = Game():GetRoom()
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_COLLECTIBLE,
        -1,
        false,
        false
    )) do
        local pickup = entity:ToPickup()
        if pickup
            and pickup:Exists()
            and tonumber(pickup.InitSeed) == tonumber(transaction.pickupInitSeed)
        then
            local exact = tonumber(pickup.SubType) == tonumber(transaction.collectibleId)
            if state.runtimeTransactionToken == transaction.token then
                exact = exact
                    and tonumber(GetPtrHash(pickup)) == tonumber(transaction.pickupHash)
            elseif transaction.gridIndex ~= nil and room then
                exact = exact
                    and room:GetGridIndex(pickup.Position) == transaction.gridIndex
            end
            return pickup, exact
        end
    end
    return nil, false
end

local function clearCancelledTransaction(nativeSave, transaction)
    if transaction.phase ~= PHASE_CANCELLED then
        transaction.phase = PHASE_CANCELLED
        if not saveNow() then
            transaction.phase = PHASE_PREPARED
            if transaction.cancelSaveFailureReported ~= true then
                transaction.cancelSaveFailureReported = true
                ConchBlessing.printError("Atropos could not persist a cancelled Death Certificate choice.")
            end
            return false
        end
    end

    -- The durable cancelled phase makes clearing the journal retryable without
    -- ever mistaking the prepared collision for a completed acquisition.
    nativeSave.transaction = nil
    if saveNow() then
        getState().runtimeTransactionToken = nil
        return true
    end

    -- Keep blocking the prepared source until the cleanup save succeeds.
    nativeSave.transaction = transaction
    if transaction.cancelSaveFailureReported ~= true then
        transaction.cancelSaveFailureReported = true
        ConchBlessing.printError("Atropos could not clear its cancelled Death Certificate journal.")
    end
    return false
end

local function closeTransaction(nativeSave, transaction, context, status, selectedId)
    transaction.phase = PHASE_CLOSING
    transaction.result = status
    transaction.selectedId = tonumber(selectedId)
    local roomState = {
        completed = true,
        committed = false,
        status = status,
        selectedId = tonumber(selectedId),
        playerIndex = transaction.playerIndex,
        pickupInitSeed = transaction.pickupInitSeed,
    }
    nativeSave.rooms[transaction.roomKey] = roomState

    -- Persist the one-choice result before removing any remaining pedestals.
    if not saveNow() then
        if transaction.closingSaveFailureReported ~= true then
            transaction.closingSaveFailureReported = true
            ConchBlessing.printError("Atropos could not persist its closing Death Certificate choice.")
        end
        return false
    end
    roomState.committed = true

    local removed = 0
    if context and context.key == transaction.roomKey then
        removed = removeRoomCollectibles()
    end
    ConchBlessing.printDebug(string.format(
        "[Atropos] Closed Death Certificate room choice (%s); removed %d collectible(s).",
        tostring(status),
        removed
    ))

    nativeSave.transaction = nil
    getState().runtimeTransactionToken = nil
    -- If this final cleanup save fails, the durable closing journal safely
    -- replays the room cleanup on continue.
    saveNow()
    return true
end

local function hasStrongExtendedConfirmation(transaction)
    if transaction.extendedCallbacks ~= true
        or transaction.collisionCompleted ~= true
        or transaction.collisionWindowOpen == true
        or transaction.evidenceSaveFailed == true
        or transaction.preAddAmbiguous == true
        or transaction.postAddAmbiguous == true
        or transaction.queueAmbiguous == true
        or (tonumber(transaction.preAddCount) or 0) ~= 1
        or (tonumber(transaction.postAddCount) or 0) ~= 1
        or (tonumber(transaction.queueCount) or 0) ~= 1
    then
        return false
    end

    local originalId = tonumber(transaction.collectibleId)
    local preId = tonumber(transaction.preAddObservedId)
    local actualId = tonumber(transaction.postAddObservedId)
    local queueId = tonumber(transaction.queueObservedId)
    return preId == originalId
        and actualId ~= nil
        and (queueId == originalId or queueId == actualId)
end

local function preEvidenceAllowsCancellation(transaction)
    local preCount = tonumber(transaction.preAddCount) or 0
    return (tonumber(transaction.postAddCount) or 0) == 0
        and (tonumber(transaction.queueCount) or 0) == 0
        and preCount <= 1
        and transaction.preAddAmbiguous ~= true
        and (preCount == 0
            or tonumber(transaction.preAddObservedId) == tonumber(transaction.collectibleId))
end

local function resolvePreparedTransaction(nativeSave, context)
    local transaction = nativeSave and nativeSave.transaction or nil
    if type(transaction) ~= "table" then return end

    if transaction.phase == PHASE_CLOSING then
        closeTransaction(
            nativeSave,
            transaction,
            context,
            transaction.result or "continued_fail_closed",
            transaction.selectedId
        )
        return
    end
    if transaction.phase == PHASE_CANCELLED then
        clearCancelledTransaction(nativeSave, transaction)
        return
    end
    if transaction.phase ~= PHASE_PREPARED then
        closeTransaction(nativeSave, transaction, context, "invalid_transaction", nil)
        return
    end

    if transaction.collisionWindowOpen == true then
        -- MC_POST_PICKUP_COLLISION is the semantic end of the evidence window.
        -- If the provider never delivered it (for example because another
        -- callback skipped collision effects), close locally at the first
        -- update boundary and never accept later collectible-add callbacks.
        transaction.collisionWindowOpen = false
        transaction.collisionPostMissing = true
        getState().runtimeTransactionToken = nil
        if not saveNow() then transaction.evidenceSaveFailed = true end
    end
    if not context or transaction.roomKey ~= context.key then
        closeTransaction(nativeSave, transaction, nil, "left_room_pending", nil)
        return
    end

    local player = isc.getPlayerFromIndex(nil, transaction.playerIndex)
    if not player then
        closeTransaction(nativeSave, transaction, context, "missing_player", nil)
        return
    end
    if type(player.IsItemQueueEmpty) ~= "function" then
        closeTransaction(nativeSave, transaction, context, "queue_api_unavailable", nil)
        return
    end
    if not player:IsItemQueueEmpty() then return end

    local source, sourceIsExact = findPreparedSource(transaction)
    if source then
        if sourceIsExact and preEvidenceAllowsCancellation(transaction) then
            clearCancelledTransaction(nativeSave, transaction)
        else
            -- A surviving source plus an applied/ambiguous add event can only
            -- be an unrelated grant or a modified pickup transaction.
            closeTransaction(nativeSave, transaction, context, "source_still_present_ambiguous", nil)
        end
        return
    end

    if hasStrongExtendedConfirmation(transaction) then
        closeTransaction(
            nativeSave,
            transaction,
            context,
            "confirmed",
            transaction.postAddObservedId
        )
        return
    end

    -- The exact prepared source is gone, so reopening the room could grant a
    -- second choice. Base API and interrupted/continued paths therefore close
    -- the room without attributing an unrelated queued grant as the reward.
    closeTransaction(nativeSave, transaction, context, "source_consumed_unconfirmed", nil)
end

local function getMatchingPreparedTransaction(player)
    if getCurrentDimension() ~= DC_DIMENSION then return nil, nil, nil end
    local nativeSave = getNativeSave(false)
    local transaction = nativeSave and nativeSave.transaction or nil
    local context = getCurrentRoomContext()
    local state = getState()
    if type(transaction) ~= "table"
        or transaction.phase ~= PHASE_PREPARED
        or not context
        or transaction.roomKey ~= context.key
        or transaction.playerIndex ~= isc.getPlayerIndex(nil, player)
        or transaction.collisionWindowOpen ~= true
        or state.runtimeTransactionToken ~= transaction.token
    then
        return nil, nil, nil
    end
    return nativeSave, transaction, context
end

function M.onPrePickupCollision(_, pickup, collider)
    if isAppraisalGalleryRoom() then return end
    if not pickup then return end
    local player = collider and collider:ToPlayer() or nil
    if not player then return end
    if type(getState().hourglassTransition) == "table" then return true end
    local hasAtropos, optionStateSafe = synchronizeChoiceOptionsForCollision(pickup)
    if not optionStateSafe then return true end
    if pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE
        or getCurrentDimension() ~= DC_DIMENSION
    then
        return
    end

    local context = getCurrentRoomContext()
    if not context then return true end

    local state = getState()
    local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
    local transaction = nativeSave and nativeSave.transaction or nil
    if type(transaction) == "table" then
        -- An already-journaled room choice remains globally locked even if the
        -- last Atropos holder drops or loses the trinket mid-transaction.
        return true
    end

    if not hasAtropos then return end
    if state.optionSaveBlocked == true then return true end
    if state.optionGroupsReady ~= true then
        state.optionGroupsReady = updateChoiceOptionGroups(true)
        if state.optionGroupsReady ~= true then state.optionSaveBlocked = true end
    end
    if state.optionGroupsReady ~= true then return true end
    if state.nativeSessionReady ~= true then retryNativeBoundarySave() end
    if state.nativeSessionReady ~= true then return true end
    nativeSave = getNativeSave(false)
    if not nativeSave or nativeSave.active ~= true then
        if M._reportedSaveUnavailable ~= true then
            M._reportedSaveUnavailable = true
            ConchBlessing.printError("Atropos blocked a Death Certificate choice because its session is unavailable.")
        end
        return true
    end
    if nativeSave and enforceCompletedRoom(nativeSave, context) then return true end

    if (tonumber(pickup.SubType) or 0) <= 0 or not canStartChoice(player, pickup) then
        return true
    end

    local room = Game():GetRoom()
    local playerIndex = isc.getPlayerIndex(nil, player)
    if playerIndex == nil then return true end
    local transactionToken = table.concat({
        tostring(nativeSave.sessionId),
        context.key,
        tostring(pickup.InitSeed),
        tostring(playerIndex),
    }, ":")
    transaction = {
        version = 1,
        phase = PHASE_PREPARED,
        token = transactionToken,
        roomKey = context.key,
        listIndex = context.listIndex,
        playerIndex = playerIndex,
        collectibleId = pickup.SubType,
        pickupInitSeed = pickup.InitSeed,
        pickupHash = GetPtrHash(pickup),
        gridIndex = room and room:GetGridIndex(pickup.Position) or nil,
        position = { x = pickup.Position.X, y = pickup.Position.Y },
        beforeCollectibleCount = player:GetCollectibleNum(pickup.SubType),
        extendedCallbacks = M._collectibleEvidenceCallbacksRegistered == true,
        collisionWindowOpen = M._collectibleEvidenceCallbacksRegistered == true,
        collisionCompleted = false,
        preAddCount = 0,
        postAddCount = 0,
        queueCount = 0,
    }
    nativeSave.transaction = transaction
    if not saveNow() then
        nativeSave.transaction = nil
        ConchBlessing.printError("Atropos could not journal a Death Certificate choice.")
        return true
    end

    state.runtimeTransactionToken = transactionToken
    syncReturnDoor()
end

function M.onPreAddCollectible(_, collectibleId, _, _, _, _, player)
    if isAppraisalGalleryRoom() then return end
    if not player then return end
    local _, transaction = getMatchingPreparedTransaction(player)
    if not transaction then return end

    transaction.preAddCount = (tonumber(transaction.preAddCount) or 0) + 1
    if transaction.preAddCount == 1 then
        transaction.preAddObservedId = tonumber(collectibleId)
    else
        transaction.preAddAmbiguous = true
    end
end

function M.onPostTriggerCollectibleAdded(_, player, collectibleId, _, wispOrInnate)
    if isAppraisalGalleryRoom() then return end
    if not player or wispOrInnate == true then return end
    local _, transaction = getMatchingPreparedTransaction(player)
    if not transaction then return end

    transaction.postAddCount = (tonumber(transaction.postAddCount) or 0) + 1
    if transaction.postAddCount == 1 then
        transaction.postAddObservedId = tonumber(collectibleId)
    else
        transaction.postAddAmbiguous = true
    end
    if not saveNow() then transaction.evidenceSaveFailed = true end
end

function M.onPostPickupCollision(_, pickup, collider)
    if isAppraisalGalleryRoom()
        or not pickup
        or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE
        or getCurrentDimension() ~= DC_DIMENSION
    then
        return
    end

    local player = collider and collider:ToPlayer() or nil
    if not player then return end
    local _, transaction = getMatchingPreparedTransaction(player)
    if not transaction
        or tonumber(pickup.InitSeed) ~= tonumber(transaction.pickupInitSeed)
        or tonumber(GetPtrHash(pickup)) ~= tonumber(transaction.pickupHash)
    then
        return
    end

    -- REPENTOGON runs this immediately after the exact pickup's internal
    -- collision code. Close the evidence window before any later mod callback
    -- can attribute an unrelated collectible grant to this pedestal.
    transaction.collisionWindowOpen = false
    transaction.collisionCompleted = true
    getState().runtimeTransactionToken = nil

    local ok, queuedItem = pcall(function()
        return player.QueuedItem and player.QueuedItem.Item or nil
    end)
    local queuedId = ok and queuedItem and tonumber(queuedItem.ID) or nil
    if queuedId and queuedId > 0 then
        transaction.queueCount = 1
        transaction.queueObservedId = queuedId
    else
        transaction.queueCount = 0
        transaction.queueObservedId = nil
    end
    if not saveNow() then transaction.evidenceSaveFailed = true end
end

function M.onPostUpdate()
    local state = getState()
    if type(state.nativeBoundarySavePending) == "table" then
        retryNativeBoundarySave()
    end
    if isAppraisalGalleryRoom() then
        settleCurrentAppraisalDetour()
        return
    end
    finishPendingAppraisalDetourAbort()
    if type(state.hourglassTransition) == "table" then return end
    resumeAppraisalReturnIfNeeded()
    if state.gameStartedKnown
        and state.nativeSessionReady == true
        and getCurrentDimension() == DC_DIMENSION
    then
        local nativeSave = getNativeSave(false)
        local context = getCurrentRoomContext()
        if nativeSave and context then
            if not enforceCompletedRoom(nativeSave, context) then
                resolvePreparedTransaction(nativeSave, context)
            end
        end
    end

    local hasAtropos = anyoneHasAtropos()
    local ownershipChanged = state.optionGroupsOwnerActive ~= hasAtropos
    if ownershipChanged then
        state.optionGroupsOwnerActive = hasAtropos
        state.optionGroupsReady = false
        state.optionSaveBlocked = false
        state.optionFallbackLinked = false
    end
    if hasAtropos and state.optionSaveBlocked == true then
        state.optionGroupsReady = false
    elseif hasAtropos or ownershipChanged or state.optionRestoreNeeded == true then
        state.optionGroupsReady = updateChoiceOptionGroups(hasAtropos)
        state.optionRestoreNeeded = state.optionGroupsReady ~= true
        if hasAtropos and state.optionGroupsReady ~= true then
            state.optionSaveBlocked = true
        end
    else
        state.optionGroupsReady = true
    end
    if not state.optionGroupsReady
        and hasAtropos
        and state.optionSaveFailureReported ~= true
    then
        state.optionSaveFailureReported = true
        ConchBlessing.printError(
            "Atropos left new option groups linked because their originals could not be saved."
        )
    elseif hasAtropos then
        state.optionSaveFailureReported = false
    end

    if getCurrentDimension() == DC_DIMENSION then
        -- Acquiring Atropos after entry may materialize the first-room escape,
        -- but must never move the documented Fool drop into a later room.
        local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
        if nativeSave and entranceMatchesCurrent(nativeSave.entrance) then
            spawnFoolIfNeeded(state)
        end
        syncReturnDoor()
    end
end

function M.onPostNewRoom()
    local dimension = getCurrentDimension()
    local state = getState()
    if isAppraisalGalleryRoom() then
        -- Appraisal is a StageAPI detour outside every native dimension. Keep
        -- lastDimension and the complete Death Certificate ledger untouched:
        -- entering AC from DC and returning to DC is not a DC exit/re-entry.
        -- Only process-local collision evidence cannot survive leaving the
        -- physical room and is safe to discard here.
        state.runtimeTransactionToken = nil
        if state.gameStartedKnown then settleCurrentAppraisalDetour() end
        return
    end
    if not state.gameStartedKnown then
        -- MC_POST_NEW_ROOM can precede MC_POST_GAME_STARTED. Record no entry
        -- inference until the authoritative continued flag is available.
        state.observedDimensionBeforeGameStart = dimension
        return
    end

    local hourglassTransition = state.hourglassTransition
    if type(hourglassTransition) == "table" then
        -- SaveManager restoration and the engine's target-room callback can
        -- arrive in either order. Record the room event and make no gameplay
        -- mutation until both halves of the handshake have completed.
        state.runtimeTransactionToken = nil
        state.pendingNativeOrigin = nil
        state.returnTransitionIssued = nil
        state.optionGroupsReady = false
        state.optionRestoreNeeded = true
        state.optionSaveBlocked = false
        state.optionFallbackLinked = false
        hourglassTransition.targetRoomSeen = true
        hourglassTransition.targetDimension = dimension
        state.lastDimension = dimension
        tryFinalizeHourglassTransition()
        return
    end

    local previousDimension = state.lastDimension
    state.runtimeTransactionToken = nil
    state.optionGroupsReady = false
    state.optionRestoreNeeded = true
    state.optionSaveBlocked = false
    state.optionFallbackLinked = false
    if dimension ~= DC_DIMENSION and previousDimension ~= DC_DIMENSION then
        state.pendingNativeOrigin = nil
    end

    local pending = dimension == DC_DIMENSION
        and takeValidatedPendingOrigin(previousDimension)
        or nil

    if previousDimension == DC_DIMENSION and dimension ~= DC_DIMENSION then
        local nativeSave = getNativeSave(false)
        if nativeSave
            and nativeSave.active == true
            and type(nativeSave.returnIntent) == "table"
            and nativeSave.returnIntent.sessionId == nativeSave.sessionId
            and not currentRoomMatchesOrigin(nativeSave.origin)
        then
            ConchBlessing.printError(
                "Atropos's return transition reached an unexpected room; its session was closed."
            )
        end
        endNativeSessionAndAbortAppraisalDetour(nativeSave)
        state.droppedInCurrentDC = false
    elseif dimension == DC_DIMENSION and pending then
        beginNativeSession(
            pending.origin,
            pending.playerIndex
        )
        state.droppedInCurrentDC = false
        spawnFoolIfNeeded(state)
    elseif dimension == DC_DIMENSION and previousDimension ~= DC_DIMENSION then
        beginNativeSession()
        state.droppedInCurrentDC = false
        spawnFoolIfNeeded(state)
    elseif dimension == DC_DIMENSION then
        local nativeSave = state.nativeSessionReady == true and getNativeSave(false) or nil
        local context = getCurrentRoomContext()
        if nativeSave and context then
            if not enforceCompletedRoom(nativeSave, context) then
                resolvePreparedTransaction(nativeSave, context)
            end
        end
    end

    state.lastDimension = dimension
    if dimension == DC_DIMENSION then syncReturnDoor() end
end

function M.onGameStarted(_, isContinued)
    local dimension = getCurrentDimension()
    M._state = {
        gameStartedKnown = true,
        lastDimension = dimension,
        droppedInCurrentDC = false,
        runtimeTransactionToken = nil,
        nativeSessionReady = false,
        nativeBoundarySavePending = nil,
        continuedSessionFailureReported = false,
        optionGroupsReady = false,
        optionGroupsOwnerActive = false,
        optionRestoreNeeded = true,
        optionSaveBlocked = false,
        optionFallbackLinked = false,
        hourglassTransition = nil,
        pendingNativeOrigin = nil,
        returnTransitionIssued = nil,
        pendingAppraisalDetourCompletion = nil,
        pendingAppraisalDetourAbort = nil,
    }
    M._reportedSaveUnavailable = false

    if isAppraisalGalleryRoom() then
        local manager = ConchBlessing.GalleryManager
        local originDimension = type(manager) == "table"
            and type(manager.getCurrentGalleryOriginDimension) == "function"
            and manager.getCurrentGalleryOriginDimension()
            or nil
        local nativeSave = getNativeSave(false)
        if settleCurrentAppraisalDetour() then return end
        local preservesDeathCertificate = originDimension == DC_DIMENSION
            or (
                originDimension == nil
                and nativeSave
                and nativeSave.active == true
            )
            or (nativeSave
                and nativeSave.active == true
                and isAppraisalOrigin(nativeSave.origin))
        M._state.lastDimension = preservesDeathCertificate
            and DC_DIMENSION
            or originDimension
        if isContinued and preservesDeathCertificate then
            local restored = ensureContinuedNativeSession()
            M._state.droppedInCurrentDC = restored
                and restored.foolSpawned == true
                or false
        end
        return
    end

    if dimension == DC_DIMENSION then
        if isContinued then
            local restored = ensureContinuedNativeSession()
            if restored then
                -- A valid continued session retains whether its first-room
                -- Fool was actually created before the save.
                local nativeSave = getNativeSave(false)
                M._state.droppedInCurrentDC = nativeSave
                    and nativeSave.foolSpawned == true
                    or false
            else
                local manager = getGalleryManager()
                local detour = manager
                    and type(manager.getDeathCertificateDetour) == "function"
                    and manager.getDeathCertificateDetour()
                    or nil
                if type(detour) == "table"
                    and detour.phase == "prepared"
                    and type(manager.abortDeathCertificateDetour) == "function"
                then
                    manager.abortDeathCertificateDetour(detour, nil)
                end
            end
        else
            beginNativeSession()
        end
        spawnFoolIfNeeded(M._state)
        syncReturnDoor()
    else
        endNativeSessionAndAbortAppraisalDetour(getNativeSave(false))
    end
end

local function registerHourglassCallbacks()
    local saveManager = ConchBlessing.SaveManager
    local callbacks = type(saveManager) == "table" and saveManager.SaveCallbacks or nil
    if type(callbacks) ~= "table"
        or callbacks.PRE_GLOWING_HOURGLASS_RESET == nil
        or callbacks.POST_GLOWING_HOURGLASS_RESET == nil
        or type(ConchBlessing.originalMod) ~= "table"
        or type(ConchBlessing.originalMod.AddCallback) ~= "function"
        or M._hourglassCallbacksRegistered
    then
        return
    end

    ConchBlessing.originalMod:AddCallback(
        callbacks.PRE_GLOWING_HOURGLASS_RESET,
        M.onPreHourglassReset
    )
    ConchBlessing.originalMod:AddCallback(
        callbacks.POST_GLOWING_HOURGLASS_RESET,
        M.onPostHourglassReset
    )
    M._hourglassCallbacksRegistered = true
end

local function registerReturnDoorType()
    M._returnDoorRegistered = false
    local stageAPI = rawget(_G, "StageAPI")
    if type(stageAPI) ~= "table" or type(stageAPI.CustomDoor) ~= "table" then
        return
    end

    local ok, registerError = pcall(function()
        stageAPI.CustomDoor(
            RETURN_DOOR_NAME,
            nil,
            nil,
            nil,
            nil,
            nil,
            false,
            true,
            function(_, _, _, _, doorGridData)
                tryReturnThroughDoor(doorGridData)
            end,
            nil,
            RoomTransitionAnim.FADE
        )
    end)
    if not ok then
        ConchBlessing.printError(
            "Atropos could not register its Death Certificate return door: "
                .. tostring(registerError)
        )
        return
    end
    M._returnDoorRegistered = true
end

registerReturnDoorType()
registerSaveConfirmation()
registerHourglassCallbacks()

local preUseItemCallback = ModCallbacks.MC_PRE_USE_ITEM
if type(preUseItemCallback) == "number" then
    ConchBlessing:AddPriorityCallback(
        preUseItemCallback,
        CALLBACK_PRIORITY_EARLY,
        M.onPreUseDeathCertificate,
        CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE
    )
end

local repentogon = rawget(_G, "REPENTOGON")
local preAddCollectibleCallback = ModCallbacks.MC_PRE_ADD_COLLECTIBLE
local postAddCollectibleCallback = ModCallbacks.MC_POST_TRIGGER_COLLECTIBLE_ADDED
local postPickupCollisionCallback = ModCallbacks.MC_POST_PICKUP_COLLISION
if type(repentogon) == "table"
    and repentogon.Real == true
    and type(preAddCollectibleCallback) == "number"
    and type(postAddCollectibleCallback) == "number"
    and type(postPickupCollisionCallback) == "number"
then
    ConchBlessing:AddPriorityCallback(
        preAddCollectibleCallback,
        CALLBACK_PRIORITY_EARLY,
        M.onPreAddCollectible
    )
    ConchBlessing:AddCallback(
        postAddCollectibleCallback,
        M.onPostTriggerCollectibleAdded
    )
    ConchBlessing:AddPriorityCallback(
        postPickupCollisionCallback,
        CALLBACK_PRIORITY_EARLY,
        M.onPostPickupCollision,
        PickupVariant.PICKUP_COLLECTIBLE
    )
    M._collectibleEvidenceCallbacksRegistered = true
else
    M._collectibleEvidenceCallbacksRegistered = false
end

return M
