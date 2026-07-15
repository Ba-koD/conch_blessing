local isc = require("scripts.lib.isaacscript-common")

local callbackPriority = rawget(_G, "CallbackPriority")
local CALLBACK_PRIORITY_EARLY = type(callbackPriority) == "table"
    and tonumber(callbackPriority.EARLY)
    or -100

ConchBlessing.atropos = ConchBlessing.atropos or {}
local M = ConchBlessing.atropos

local DC_DIMENSION = 2
local SAVE_KEY = "atroposNativeDeathCertificate"
local OPTION_SAVE_KEY = "atroposChoiceOptionGroups"
local SAVE_VERSION = 2
local OPTION_SAVE_VERSION = 1
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
    local context = {
        stage = level:GetStage(),
        stageType = level:GetStageType(),
        roomIndex = level:GetCurrentRoomIndex(),
        listIndex = descriptor and descriptor.ListIndex or nil,
        spawnSeed = descriptor and descriptor.SpawnSeed or nil,
        decorationSeed = descriptor and descriptor.DecorationSeed or nil,
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

local function beginNativeSession()
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
    if saveNow() then
        state.nativeSessionReady = true
        state.nativeBoundarySavePending = nil
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

    state.nativeSessionReady = true
    state.nativeBoundarySavePending = nil
    return nativeSave
end

local function endNativeSession()
    local state = getState()
    state.nativeSessionReady = false

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
    if saveNow() then
        state.nativeBoundarySavePending = nil
        return true
    end

    state.nativeBoundarySavePending = { kind = "end", attempts = 0 }
    ConchBlessing.printError("Atropos will retry saving its Death Certificate session end.")
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
        if dimension == DC_DIMENSION then beginNativeSession() end
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
            state.nativeBoundarySavePending = nil
            state.nativeSessionReady = true
        end
    elseif pending.kind == "end" then
        if dimension == DC_DIMENSION
            or not nativeSave
            or nativeSave.active == true
        then
            return
        end
        if saveNow() then state.nativeBoundarySavePending = nil end
    end
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
        -- The rewound session already owns the Fool created at its original
        -- entry. Do not create another card in later DC rooms.
        state.droppedInCurrentDC = true
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
    if isAppraisalGalleryRoom() then return end
    local state = getState()
    if type(state.hourglassTransition) == "table" then return end
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
end

function M.onPostNewRoom()
    local dimension = getCurrentDimension()
    local state = getState()
    if isAppraisalGalleryRoom() then
        -- Appraisal owns these native dimension-2 descriptors. They are not a
        -- vanilla Death Certificate session: do not spawn The Fool, rewrite
        -- option groups, or open Atropos's collectible transaction here.
        state.lastDimension = nil
        state.nativeSessionReady = false
        state.nativeBoundarySavePending = nil
        state.runtimeTransactionToken = nil
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

    if previousDimension == DC_DIMENSION and dimension ~= DC_DIMENSION then
        endNativeSession()
        state.droppedInCurrentDC = false
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
    }
    M._reportedSaveUnavailable = false

    if isAppraisalGalleryRoom() then
        M._state.lastDimension = nil
        return
    end

    if dimension == DC_DIMENSION then
        if isContinued then
            if ensureContinuedNativeSession() then
                -- A valid continued session already spawned its one Fool on
                -- the original entry; keep the documented first-room scope.
                M._state.droppedInCurrentDC = true
            end
        else
            beginNativeSession()
        end
        spawnFoolIfNeeded(M._state)
    else
        endNativeSession()
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

registerSaveConfirmation()
registerHourglassCallbacks()

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
