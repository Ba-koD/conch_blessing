local isc = require("scripts.lib.isaacscript-common")
local NativeGalleryRooms = require("scripts.rooms.native_gallery_rooms")

-- CallbackPriority is an engine/REPENTOGON global. The vendored IsaacScript
-- Common root does not re-export this enum even though its internal modules
-- use the same values.
local callbackPriority = rawget(_G, "CallbackPriority")
local CALLBACK_PRIORITY_EARLY = type(callbackPriority) == "table"
    and tonumber(callbackPriority.EARLY)
    or -100
local CALLBACK_PRIORITY_LATE = type(callbackPriority) == "table"
    and tonumber(callbackPriority.LATE)
    or 100

ConchBlessing.GalleryManager = ConchBlessing.GalleryManager or {}
local M = ConchBlessing.GalleryManager

local SAVE_KEY = "appraisalGallerySession"
local SEQUENCE_KEY = "appraisalGallerySequence"
local SESSION_VERSION = 8
local MODE_APPRAISAL = "appraisal_trinkets_native"
local DC_DIMENSION = 2
local GOLDEN_TRINKET_FLAG = 32768
local MAX_RETURN_MISDIRECTIONS = 1
local RETURN_TRANSITION = RoomTransitionAnim.FADE
local GALLERY_MUSIC = type(Music) == "table" and Music.MUSIC_DARK_CLOSET or nil
local SMELTER_SWALLOW_SOUND = type(SoundEffect) == "table"
    and SoundEffect.SOUND_SMELTER_SWALLOW
    or nil
local STOCK_DATA_KEY = "__ConchBlessingAppraisalStock"
local RETURN_DOOR_NAME = "ConchBlessingGalleryReturn"

M._confirmedSaveRevision = tonumber(M._confirmedSaveRevision) or 0
M._durableChoiceClosures = M._durableChoiceClosures or {}
M._durableSmeltAttempts = M._durableSmeltAttempts or {}
M._removedChoiceStock = M._removedChoiceStock or {}
M._returnTransitionIssued = M._returnTransitionIssued or {}
-- Diagnostic-only state is process-local and may be discarded on Lua reload;
-- it must never become part of the gallery transaction.
M._debugStockAudit = nil
-- MC_POST_NEW_ROOM/MC_POST_NEW_LEVEL can precede MC_POST_GAME_STARTED while
-- SaveManager still exposes the previous on-disk run. Only the game-start
-- callback may open this semantic lifecycle gate.
M._runLifecycleReady = false

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

local function getSession()
    local runSave = getRunSave(false)
    local session = runSave and runSave[SAVE_KEY] or nil
    if type(session) == "table"
        and session.version == SESSION_VERSION
        and session.mode == MODE_APPRAISAL
    then
        return session
    end
    return nil
end

local function setSession(session)
    local runSave = getRunSave(true)
    if not runSave then return false end
    runSave[SAVE_KEY] = session
    return true
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
        end
    )
    M._saveConfirmationRegistered = true
end

registerSaveConfirmation()

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
        local descriptor = level:GetRoomByIdx(roomIndex, dimension)
        if descriptor and GetPtrHash(descriptor) == GetPtrHash(current) then
            return dimension
        end
    end
    return nil
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

local function getDeathCertificateUseFlags()
    local useFlag = rawget(_G, "UseFlag")
    if type(useFlag) ~= "table" then return nil end
    local required = {
        "USE_NOANIM",
        "USE_NOCOSTUME",
        "USE_NOANNOUNCER",
        "USE_NOHUD",
        "USE_ALLOWNONMAIN",
    }
    local flags = 0
    for _, key in ipairs(required) do
        local value = tonumber(useFlag[key])
        if value == nil then return nil end
        flags = flags | value
    end
    return flags
end

local function getMusicManager()
    if type(MusicManager) ~= "function" then return nil end
    local ok, manager = pcall(MusicManager)
    if ok then return manager end
    return nil
end

local function getCurrentMusicId()
    local manager = getMusicManager()
    if not manager or type(manager.GetCurrentMusicID) ~= "function" then return nil end
    local ok, musicId = pcall(function() return manager:GetCurrentMusicID() end)
    if ok and type(musicId) == "number" then return musicId end
    return nil
end

local function getScreenShakeCountdown()
    local game = Game()
    if not game or type(game.GetScreenShakeCountdown) ~= "function" then return nil end
    local ok, countdown = pcall(function() return game:GetScreenShakeCountdown() end)
    if ok and type(countdown) == "number" then return countdown end
    return nil
end

local function isSmelterSwallowPlaying()
    if type(SMELTER_SWALLOW_SOUND) ~= "number" or type(SFXManager) ~= "function" then
        return false
    end
    local okManager, manager = pcall(SFXManager)
    if not okManager or not manager or type(manager.IsPlaying) ~= "function" then
        return false
    end
    local okPlaying, playing = pcall(function()
        return manager:IsPlaying(SMELTER_SWALLOW_SOUND)
    end)
    return okPlaying and playing == true
end

local function crossfadeMusic(musicId)
    if type(musicId) ~= "number" then return false end
    local manager = getMusicManager()
    if not manager or type(manager.Crossfade) ~= "function" then return false end
    if getCurrentMusicId() == musicId then return true end
    return pcall(function() manager:Crossfade(musicId, 0.08) end)
end

local function playGalleryMusic()
    if GALLERY_MUSIC == nil then return false end
    return crossfadeMusic(GALLERY_MUSIC)
end

local function restoreOriginMusic(session)
    local origin = session and session.origin or nil
    local musicId = type(origin) == "table" and tonumber(origin.musicId) or nil
    if musicId == nil then return false end
    return crossfadeMusic(musicId)
end

local function getCurrentFloorIdentity()
    local level = Game():GetLevel()
    if not level then return nil end
    local placementSeed
    if type(level.GetDungeonPlacementSeed) == "function" then
        local ok, result = pcall(function() return level:GetDungeonPlacementSeed() end)
        if ok then placementSeed = tonumber(result) end
    end
    return {
        stage = level:GetStage(),
        stageType = level:GetStageType(),
        placementSeed = placementSeed,
    }
end

local function sessionMatchesCurrentFloor(session)
    if type(session) ~= "table" or type(session.floor) ~= "table" then
        return false
    end
    local floor = getCurrentFloorIdentity()
    return floor
        and session.floor.stage == floor.stage
        and session.floor.stageType == floor.stageType
        and session.floor.placementSeed == floor.placementSeed
end

local function getPlayerIndex(player)
    if not player then return nil end
    local ok, index = pcall(isc.getPlayerIndex, nil, player)
    if ok then return index end
    return nil
end

local function getPlayerFromIndex(index)
    if index == nil then return nil end
    local ok, player = pcall(isc.getPlayerFromIndex, nil, index)
    if ok then return player end
    return nil
end

local function anyoneHasAtropos()
    local itemData = ConchBlessing.ItemData
    local id = itemData and itemData.ATROPOS and itemData.ATROPOS.id or nil
    if not id or id <= 0 then return false end
    local game = Game()
    for playerIndex = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(playerIndex)
        if player and player:HasTrinket(id) then return true end
    end
    return false
end

local function normalizeTrinketId(exactId)
    local id = tonumber(exactId)
    if not id then return nil end
    if id >= GOLDEN_TRINKET_FLAG then return id - GOLDEN_TRINKET_FLAG end
    return id
end

local function debugEnabled()
    return type(ConchBlessing.Config) == "table"
        and ConchBlessing.Config.debugMode == true
        and type(ConchBlessing.printDebug) == "function"
end

local function debugPrint(message)
    if debugEnabled() then ConchBlessing.printDebug("[Appraisal] " .. tostring(message)) end
end

local function formatNumberRanges(values)
    if type(values) ~= "table" or #values == 0 then return "none" end
    local numbers = {}
    for _, value in ipairs(values) do
        local number = tonumber(value)
        if number then numbers[#numbers + 1] = number end
    end
    if #numbers == 0 then return "none" end
    table.sort(numbers)

    local ranges = {}
    local first = numbers[1]
    local last = first
    for index = 2, #numbers do
        local value = numbers[index]
        if value == last + 1 then
            last = value
        else
            ranges[#ranges + 1] = first == last
                and tostring(first)
                or tostring(first) .. "-" .. tostring(last)
            first = value
            last = value
        end
    end
    ranges[#ranges + 1] = first == last
        and tostring(first)
        or tostring(first) .. "-" .. tostring(last)
    return table.concat(ranges, ",")
end

local function getRegisteredTrinkets(emitAudit)
    local itemConfig = Isaac.GetItemConfig()
    if not itemConfig then return {} end
    local list = itemConfig:GetTrinkets()
    local size = list and tonumber(list.Size) or 0
    local result = {}
    local audit = emitAudit ~= false and debugEnabled() and {
        present = 0,
        hidden = {},
        missing = {},
        unavailableButIncluded = {},
    } or nil
    for trinketId = 1, math.max(0, size - 1) do
        local ok, config = pcall(function() return itemConfig:GetTrinket(trinketId) end)
        if ok and config and config.Hidden ~= true then
            -- This room is a complete registry showcase, not an item-pool
            -- roll. Locked-but-valid trinkets remain real content and must not
            -- disappear merely because ItemConfig:IsAvailable() reflects the
            -- current save's unlock state. Hidden/internal configs stay out.
            result[#result + 1] = trinketId
            if audit then
                audit.present = audit.present + 1
                if type(config.IsAvailable) == "function" then
                    local availableOK, available = pcall(function()
                        return config:IsAvailable()
                    end)
                    if availableOK and available == false then
                        audit.unavailableButIncluded[#audit.unavailableButIncluded + 1] = trinketId
                    end
                end
            end
        elseif ok and config then
            if audit then
                audit.present = audit.present + 1
                audit.hidden[#audit.hidden + 1] = trinketId
            end
        elseif audit then
            audit.missing[#audit.missing + 1] = trinketId
        end
    end
    table.sort(result)
    if audit then
        debugPrint(string.format(
            "catalog registry size=%d maxId=%d present=%d included=%d hidden=%d missing=%d unavailableButIncluded=%d",
            size,
            math.max(0, size - 1),
            audit.present,
            #result,
            #audit.hidden,
            #audit.missing,
            #audit.unavailableButIncluded
        ))
        debugPrint("catalog includedIds=" .. formatNumberRanges(result))
        debugPrint("catalog hiddenIds=" .. formatNumberRanges(audit.hidden)
            .. " missingIds=" .. formatNumberRanges(audit.missing))
        debugPrint("catalog unavailableButIncludedIds="
            .. formatNumberRanges(audit.unavailableButIncluded))
    end
    return result
end

local function compareCatalogs(expected, actual)
    local expectedSet = {}
    local actualSet = {}
    for _, trinketId in ipairs(expected or {}) do
        local normalized = tonumber(trinketId)
        if normalized then expectedSet[normalized] = true end
    end
    for _, trinketId in ipairs(actual or {}) do
        local normalized = tonumber(trinketId)
        if normalized then actualSet[normalized] = true end
    end

    local missing = {}
    local extra = {}
    for trinketId in pairs(expectedSet) do
        if not actualSet[trinketId] then missing[#missing + 1] = trinketId end
    end
    for trinketId in pairs(actualSet) do
        if not expectedSet[trinketId] then extra[#extra + 1] = trinketId end
    end
    local matches = #missing == 0
        and #extra == 0
        and #(expected or {}) == #(actual or {})
    return matches, missing, extra
end

local function debugAuditGraph(session)
    if not debugEnabled()
        or type(session) ~= "table"
        or type(session.catalog) ~= "table"
        or type(session.graph) ~= "table"
        or type(session.graph.rooms) ~= "table"
    then
        return
    end

    local seenCatalogIndices = {}
    local duplicateCatalogIndices = {}
    local assignedIds = {}
    local layoutCounts = {}
    local nonOneCellRooms = {}
    local assignedCount = 0
    local slotCount = 0

    for roomIndex, manifest in ipairs(session.graph.rooms) do
        local layoutKey = tostring(manifest.layoutKey or "missing")
        layoutCounts[layoutKey] = (layoutCounts[layoutKey] or 0) + 1
        if layoutKey ~= "1x1" then
            nonOneCellRooms[#nonOneCellRooms + 1] = tostring(manifest.key or roomIndex)
                .. ":" .. layoutKey
        end

        local roomIds = {}
        local start = tonumber(manifest.catalogStart) or 0
        local count = tonumber(manifest.slotCount) or 0
        slotCount = slotCount + count
        for slot = 1, count do
            local catalogIndex = start + slot - 1
            if seenCatalogIndices[catalogIndex] then
                duplicateCatalogIndices[#duplicateCatalogIndices + 1] = catalogIndex
            end
            seenCatalogIndices[catalogIndex] = true
            local trinketId = tonumber(session.catalog[catalogIndex])
            if trinketId then
                assignedCount = assignedCount + 1
                assignedIds[#assignedIds + 1] = trinketId
                roomIds[#roomIds + 1] = trinketId
            end
        end
        debugPrint(string.format(
            "graph room=%s layout=%s listIndex=%s catalogStart=%d slots=%d ids=%s",
            tostring(manifest.key or roomIndex),
            layoutKey,
            tostring(manifest.listIndex),
            start,
            count,
            formatNumberRanges(roomIds)
        ))
    end

    local missingCatalogIndices = {}
    local seenCatalogIds = {}
    local duplicateCatalogIds = {}
    for catalogIndex, trinketId in ipairs(session.catalog) do
        if not seenCatalogIndices[catalogIndex] then
            missingCatalogIndices[#missingCatalogIndices + 1] = catalogIndex
        end
        local normalized = tonumber(trinketId)
        if normalized then
            if seenCatalogIds[normalized] then
                duplicateCatalogIds[#duplicateCatalogIds + 1] = normalized
            end
            seenCatalogIds[normalized] = true
        end
    end

    local layoutParts = {}
    for _, key in ipairs({ "1x1", "1x2", "2x1", "2x2", "missing" }) do
        if layoutCounts[key] then
            layoutParts[#layoutParts + 1] = key .. "=" .. tostring(layoutCounts[key])
        end
    end
    local graphComplete = session.graph.complete == true
        and tonumber(session.graph.catalogCount) == #session.catalog
        and slotCount == #session.catalog
        and assignedCount == #session.catalog
        and #missingCatalogIndices == 0
        and #duplicateCatalogIndices == 0
        and #duplicateCatalogIds == 0
    local liveCatalog = getRegisteredTrinkets(false)
    local registryMatches, registryMissing, registryExtra = compareCatalogs(
        liveCatalog,
        session.catalog
    )
    local oneCellOnly = #nonOneCellRooms == 0
    local complete = graphComplete and registryMatches

    debugPrint(string.format(
        "graph coverage=%s graphInternal=%s registryCoverage=%s frozenCatalog=%d liveCatalog=%d graphCatalog=%s rooms=%d slots=%d assigned=%d layouts=%s oneCellOnly=%s",
        complete and "PASS" or "FAIL",
        graphComplete and "PASS" or "FAIL",
        registryMatches and "PASS" or "FAIL",
        #session.catalog,
        #liveCatalog,
        tostring(session.graph.catalogCount),
        #session.graph.rooms,
        slotCount,
        assignedCount,
        #layoutParts > 0 and table.concat(layoutParts, ",") or "none",
        oneCellOnly and "PASS" or "FAIL"
    ))
    debugPrint("graph assignedIds=" .. formatNumberRanges(assignedIds))
    debugPrint("graph missingCatalogIndices=" .. formatNumberRanges(missingCatalogIndices)
        .. " duplicateCatalogIndices=" .. formatNumberRanges(duplicateCatalogIndices)
        .. " duplicateCatalogIds=" .. formatNumberRanges(duplicateCatalogIds))
    debugPrint("graph registryMissingIds=" .. formatNumberRanges(registryMissing)
        .. " registryExtraIds=" .. formatNumberRanges(registryExtra))
    if #nonOneCellRooms > 0 then
        debugPrint("graph nonOneCellRooms=" .. table.concat(nonOneCellRooms, ","))
    end
end

local function countHeldTrinkets(player)
    local count = 0
    for slot = 0, 1 do
        local exactId = player:GetTrinket(slot)
        if exactId and exactId ~= 0 then count = count + 1 end
    end
    return count
end

local function countExactHeldTrinkets(player, exactId)
    local count = 0
    for slot = 0, 1 do
        if player:GetTrinket(slot) == exactId then count = count + 1 end
    end
    return count
end

local function getHeldTrinketSnapshot(player)
    return { player:GetTrinket(0) or 0, player:GetTrinket(1) or 0 }
end

local function heldTrinketSnapshotMatches(player, snapshot)
    return type(snapshot) == "table"
        and player:GetTrinket(0) == (tonumber(snapshot[1]) or 0)
        and player:GetTrinket(1) == (tonumber(snapshot[2]) or 0)
end

local function restoreHeldTrinketSnapshot(player, snapshot)
    if type(snapshot) ~= "table" then return false end
    local safety = 0
    while countHeldTrinkets(player) > 0 and safety < 2 do
        local exactId = player:GetTrinket(0)
        if not exactId or exactId == 0 then exactId = player:GetTrinket(1) end
        local before = countHeldTrinkets(player)
        if exactId and exactId ~= 0 then player:TryRemoveTrinket(exactId) end
        if countHeldTrinkets(player) >= before then return false end
        safety = safety + 1
    end
    if countHeldTrinkets(player) ~= 0 then return false end
    for slot = 1, 2 do
        local exactId = tonumber(snapshot[slot]) or 0
        if exactId ~= 0 then player:AddTrinket(exactId, false) end
    end
    return heldTrinketSnapshotMatches(player, snapshot)
end

local function getSmeltedSnapshot(player)
    if type(player.GetSmeltedTrinkets) ~= "function" then return nil end
    local ok, smelted = pcall(function() return player:GetSmeltedTrinkets() end)
    if not ok or type(smelted) ~= "table" then return nil end
    local snapshot = {}
    for trinketId, description in pairs(smelted) do
        local id = tonumber(trinketId)
        if id and type(description) == "table" then
            local normal = math.max(0, tonumber(description.trinketAmount) or 0)
            local golden = math.max(0, tonumber(description.goldenTrinketAmount) or 0)
            if normal > 0 or golden > 0 then
                snapshot[tostring(id)] = { normal = normal, golden = golden }
            end
        end
    end
    return snapshot
end

local function getPositiveSmeltedDelta(before, current)
    if type(before) ~= "table" or type(current) ~= "table" then return nil end
    local delta = {}
    for id, actual in pairs(current) do
        local previous = before[id] or {}
        local normal = math.max(
            0,
            (tonumber(actual.normal) or 0) - (tonumber(previous.normal) or 0)
        )
        local golden = math.max(
            0,
            (tonumber(actual.golden) or 0) - (tonumber(previous.golden) or 0)
        )
        if normal > 0 or golden > 0 then
            delta[id] = { normal = normal, golden = golden }
        end
    end
    return delta
end

local function getSmeltedDeltaSize(delta)
    if type(delta) ~= "table" then return 0 end
    local count = 0
    for _, addition in pairs(delta) do
        count = count
            + math.max(0, tonumber(addition.normal) or 0)
            + math.max(0, tonumber(addition.golden) or 0)
    end
    return count
end

local function smeltedDeltaApplied(before, current, delta)
    if type(before) ~= "table"
        or type(current) ~= "table"
        or type(delta) ~= "table"
    then
        return false
    end
    for id, addition in pairs(delta) do
        local previous = before[id] or {}
        local actual = current[id] or {}
        if (tonumber(actual.normal) or 0)
                < (tonumber(previous.normal) or 0) + (tonumber(addition.normal) or 0)
            or (tonumber(actual.golden) or 0)
                < (tonumber(previous.golden) or 0) + (tonumber(addition.golden) or 0)
        then
            return false
        end
    end
    return true
end

local function smeltedSnapshotsMatch(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    local ids = {}
    for id in pairs(left) do ids[id] = true end
    for id in pairs(right) do ids[id] = true end
    for id in pairs(ids) do
        local a = left[id] or {}
        local b = right[id] or {}
        if (tonumber(a.normal) or 0) ~= (tonumber(b.normal) or 0)
            or (tonumber(a.golden) or 0) ~= (tonumber(b.golden) or 0)
        then
            return false
        end
    end
    return true
end

local function canJournalDirectSmelt(player)
    return type(player.AddSmeltedTrinket) == "function"
        and type(player.GetSmeltedTrinkets) == "function"
        and type(player.TryRemoveSmeltedTrinket) == "function"
end

local function rollbackSmeltedDelta(player, before, delta)
    local current = getSmeltedSnapshot(player)
    if type(before) ~= "table"
        or type(current) ~= "table"
        or type(delta) ~= "table"
    then
        return false
    end
    for id, addition in pairs(delta) do
        local baseId = tonumber(id)
        local previous = before[id] or {}
        local actual = current[id] or {}
        local normal = math.min(
            math.max(0, (tonumber(actual.normal) or 0) - (tonumber(previous.normal) or 0)),
            math.max(0, tonumber(addition.normal) or 0)
        )
        local golden = math.min(
            math.max(0, (tonumber(actual.golden) or 0) - (tonumber(previous.golden) or 0)),
            math.max(0, tonumber(addition.golden) or 0)
        )
        if baseId then
            for _ = 1, normal do player:TryRemoveSmeltedTrinket(baseId) end
            for _ = 1, golden do
                player:TryRemoveSmeltedTrinket(baseId + GOLDEN_TRINKET_FLAG)
            end
        end
    end
    return smeltedSnapshotsMatch(before, getSmeltedSnapshot(player))
end

local function absorbHeldTrinketsDirect(player, session)
    while true do
        local journal = session.heldAbsorptionJournal
        if type(journal) ~= "table" then
            if countHeldTrinkets(player) == 0 then return true end
            local exactId = player:GetTrinket(0)
            if not exactId or exactId == 0 then exactId = player:GetTrinket(1) end
            local beforeSmelted = getSmeltedSnapshot(player)
            if not exactId or exactId == 0 or not beforeSmelted then return false end
            journal = {
                exactId = exactId,
                heldCopiesBefore = countExactHeldTrinkets(player, exactId),
                beforeSmelted = beforeSmelted,
            }
            session.heldAbsorptionJournal = journal
            if not saveNow() then
                session.heldAbsorptionJournal = nil
                return false
            end
        end

        local exactId = tonumber(journal.exactId)
        local heldCopiesBefore = tonumber(journal.heldCopiesBefore) or 0
        local currentSmelted = getSmeltedSnapshot(player)
        local appliedDelta = journal.appliedSmeltedDelta
        if type(appliedDelta) ~= "table" then
            local observed = getPositiveSmeltedDelta(journal.beforeSmelted, currentSmelted)
            if getSmeltedDeltaSize(observed) > 0 then
                journal.appliedSmeltedDelta = observed
                appliedDelta = observed
                if not saveNow() then return false end
            end
        end
        local smelted = type(appliedDelta) == "table"
            and smeltedDeltaApplied(journal.beforeSmelted, currentSmelted, appliedDelta)
        local heldCopies = exactId and countExactHeldTrinkets(player, exactId) or 0

        if smelted and heldCopies == heldCopiesBefore - 1 then
            session.heldAbsorptionJournal = nil
            if not saveNow() then return false end
        else
            if not smelted then
                if not exactId or heldCopies ~= heldCopiesBefore then return false end
                local ok, added = pcall(function()
                    return player:AddSmeltedTrinket(exactId, false)
                end)
                currentSmelted = getSmeltedSnapshot(player)
                appliedDelta = getPositiveSmeltedDelta(journal.beforeSmelted, currentSmelted)
                smelted = getSmeltedDeltaSize(appliedDelta) > 0
                    and smeltedDeltaApplied(
                        journal.beforeSmelted,
                        currentSmelted,
                        appliedDelta
                    )
                if not ok or added ~= true or not smelted then
                    rollbackSmeltedDelta(player, journal.beforeSmelted, appliedDelta)
                    session.heldAbsorptionJournal = nil
                    saveNow()
                    return false
                end
                journal.appliedSmeltedDelta = appliedDelta
                if not saveNow() then
                    rollbackSmeltedDelta(player, journal.beforeSmelted, appliedDelta)
                    session.heldAbsorptionJournal = nil
                    return false
                end
            end

            local beforeRemoval = countExactHeldTrinkets(player, exactId)
            player:TryRemoveTrinket(exactId)
            if countExactHeldTrinkets(player, exactId) ~= beforeRemoval - 1 then
                rollbackSmeltedDelta(player, journal.beforeSmelted, appliedDelta)
                session.heldAbsorptionJournal = nil
                saveNow()
                return false
            end
            session.heldAbsorptionJournal = nil
            if not saveNow() then return false end
        end
    end
end

local function invalidateRuntime()
    M._runtime = nil
    M._currentContext = nil
end

local function getRuntime(session)
    if not session or type(session.graph) ~= "table" then return nil, "missing_graph" end
    if type(M._runtime) == "table" and M._runtimeToken == session.token then
        return M._runtime
    end
    local runtime, reason = NativeGalleryRooms.rebind(session.graph)
    if not runtime then
        invalidateRuntime()
        return nil, reason or "graph_restore_failed"
    end
    M._runtime = runtime
    M._runtimeToken = session.token
    return runtime
end

local function getCurrentGalleryContext(session)
    if M._runLifecycleReady ~= true then return nil end
    if not session or not sessionMatchesCurrentFloor(session) then return nil end
    if getCurrentDimension() ~= DC_DIMENSION then return nil end
    local runtime = getRuntime(session)
    if not runtime then return nil end
    local manifest, descriptor = NativeGalleryRooms.getCurrentManifest(
        session.graph,
        runtime
    )
    if not manifest or not descriptor then return nil end
    return {
        runtime = runtime,
        manifest = manifest,
        descriptor = descriptor,
    }
end

function M.isCurrentGalleryRoom()
    return getCurrentGalleryContext(getSession()) ~= nil
end

function M.isVisitActive()
    if M._runLifecycleReady ~= true then return false end
    local session = getSession()
    return session ~= nil
        and sessionMatchesCurrentFloor(session)
        and session.phase ~= "completed"
        and session.phase ~= "build_failed"
end

local originDescriptorMatches

local function isOriginRoom(session)
    local origin = session and session.origin or nil
    if type(origin) ~= "table" or getCurrentDimension() ~= origin.dimension then
        return false
    end
    local level = Game():GetLevel()
    if not level then return false end
    local descriptor = level:GetCurrentRoomDesc()
    if not originDescriptorMatches(origin, descriptor, origin.dimension) then return false end
    return level:GetCurrentRoomIndex() == tonumber(origin.safeGridIndex)
        or level:GetCurrentRoomIndex() == tonumber(origin.roomIndex)
        or level:GetCurrentRoomIndex() == tonumber(origin.gridIndex)
end

local function expectedTrinket(session, manifest, slot)
    if type(session.catalog) ~= "table" or type(manifest) ~= "table" then return nil end
    local start = tonumber(manifest.catalogStart) or 1
    return session.catalog[start + slot - 1]
end

local function getSourceSeed(session, manifest, slot)
    manifest.sourceSeeds = manifest.sourceSeeds or {}
    local saved = tonumber(manifest.sourceSeeds[slot])
    if saved and saved ~= 0 then return saved end
    local graphIndex = tonumber(manifest.graphIndex) or tonumber(manifest.listIndex) or 1
    local value = (
        math.abs(tonumber(session.seed) or 1)
        + graphIndex * 104729
        + slot * 8191
    ) % 2147483646 + 1
    manifest.sourceSeeds[slot] = value
    return value
end

local function indexCurrentRoomTrinkets()
    local bySeed = {}
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_TRINKET,
        -1,
        false,
        false
    )) do
        local pickup = entity:ToPickup()
        local seed = pickup and pickup:Exists() and tonumber(pickup.InitSeed) or nil
        if seed then
            -- InitSeed is the durable manager identity. A duplicate is
            -- ambiguous and must not be adopted as manager stock.
            bySeed[seed] = bySeed[seed] == nil and pickup or false
        end
    end
    return bySeed
end

local function findSourceForSlot(session, manifest, slot, sourcesBySeed)
    local expectedId = expectedTrinket(session, manifest, slot)
    local expectedSeed = getSourceSeed(session, manifest, slot)
    if not expectedId then return nil end
    local indexed = sourcesBySeed or indexCurrentRoomTrinkets()
    local pickup = indexed[expectedSeed]
    if pickup
        and pickup:Exists()
        and tonumber(pickup.InitSeed) == expectedSeed
        and tonumber(pickup.SubType) == tonumber(expectedId)
    then
        pickup:GetData()[STOCK_DATA_KEY] = {
            token = session.token,
            roomKey = manifest.key,
            slot = slot,
            trinketId = expectedId,
        }
        return pickup
    end
    return nil
end

local function clearDebugStockRoomVerification(session, manifest)
    if type(M._debugStockAudit) ~= "table"
        or type(session) ~= "table"
        or type(session.graph) ~= "table"
        or type(manifest) ~= "table"
    then
        return
    end
    local auditToken = tostring(session.token) .. ":" .. tostring(session.graph.seed)
    if M._debugStockAudit.token == auditToken
        and type(M._debugStockAudit.verifiedRooms) == "table"
    then
        M._debugStockAudit.verifiedRooms[manifest.key] = nil
    end
end

local function debugAuditCurrentStockRoom(session, manifest, sourcesBySeed)
    if not debugEnabled()
        or type(session) ~= "table"
        or type(session.catalog) ~= "table"
        or type(session.graph) ~= "table"
        or type(manifest) ~= "table"
        or manifest.kind ~= "stock"
    then
        return
    end

    local auditToken = tostring(session.token) .. ":" .. tostring(session.graph.seed)
    if type(M._debugStockAudit) ~= "table"
        or M._debugStockAudit.token ~= auditToken
    then
        M._debugStockAudit = { token = auditToken, verifiedRooms = {} }
    end

    local indexed = sourcesBySeed or indexCurrentRoomTrinkets()
    local expectedIds = {}
    local actualIds = {}
    local missingSlots = {}
    local duplicateSeeds = {}
    local subtypeMismatches = {}
    local duplicateSeedSet = {}
    local seenExpectedSeeds = {}
    local uniqueExpectedSeeds = 0
    local verified = 0
    local count = tonumber(manifest.slotCount) or 0

    for slot = 1, count do
        local expectedId = tonumber(expectedTrinket(session, manifest, slot))
        local expectedSeed = tonumber(getSourceSeed(session, manifest, slot))
        if expectedId then expectedIds[#expectedIds + 1] = expectedId end
        if expectedSeed then
            if seenExpectedSeeds[expectedSeed] and not duplicateSeedSet[expectedSeed] then
                duplicateSeedSet[expectedSeed] = true
                duplicateSeeds[#duplicateSeeds + 1] = tostring(expectedSeed)
            elseif not seenExpectedSeeds[expectedSeed] then
                seenExpectedSeeds[expectedSeed] = true
                uniqueExpectedSeeds = uniqueExpectedSeeds + 1
            end
        end
        local pickup = expectedSeed and indexed[expectedSeed] or nil
        if pickup == false then
            if not duplicateSeedSet[expectedSeed] then
                duplicateSeedSet[expectedSeed] = true
                duplicateSeeds[#duplicateSeeds + 1] = tostring(expectedSeed)
            end
        elseif pickup and pickup:Exists() and tonumber(pickup.InitSeed) == expectedSeed then
            local actualId = tonumber(pickup.SubType)
            if actualId then actualIds[#actualIds + 1] = actualId end
            if actualId == expectedId then
                verified = verified + 1
            else
                subtypeMismatches[#subtypeMismatches + 1] = tostring(slot)
                    .. ":" .. tostring(expectedId)
                    .. "->" .. tostring(actualId)
            end
        else
            missingSlots[#missingSlots + 1] = slot
        end
    end

    local roomPass = verified == count
        and uniqueExpectedSeeds == count
        and #missingSlots == 0
        and #duplicateSeeds == 0
        and #subtypeMismatches == 0
    M._debugStockAudit.verifiedRooms[manifest.key] = roomPass and count or nil

    local verifiedRooms = 0
    local verifiedSlots = 0
    local totalRooms = 0
    local oneCellOnly = true
    local remainingIds = {}
    for _, roomManifest in ipairs(session.graph.rooms or {}) do
        totalRooms = totalRooms + 1
        if roomManifest.layoutKey ~= "1x1" then oneCellOnly = false end
        local roomCount = tonumber(roomManifest.slotCount) or 0
        if M._debugStockAudit.verifiedRooms[roomManifest.key] == roomCount then
            verifiedRooms = verifiedRooms + 1
            verifiedSlots = verifiedSlots + roomCount
        else
            for slot = 1, roomCount do
                local trinketId = expectedTrinket(session, roomManifest, slot)
                if trinketId then remainingIds[#remainingIds + 1] = trinketId end
            end
        end
    end

    local liveCatalog = getRegisteredTrinkets(false)
    local registryMatches, registryMissing, registryExtra = compareCatalogs(
        liveCatalog,
        session.catalog
    )
    local allPass = verifiedRooms == totalRooms
        and verifiedSlots == #session.catalog
        and #remainingIds == 0
        and registryMatches
    debugPrint(string.format(
        "stock room=%s listIndex=%s expected=%d verified=%d uniqueSeeds=%d status=%s expectedIds=%s actualIds=%s",
        tostring(manifest.key),
        tostring(manifest.listIndex),
        count,
        verified,
        uniqueExpectedSeeds,
        roomPass and "PASS" or "FAIL",
        formatNumberRanges(expectedIds),
        formatNumberRanges(actualIds)
    ))
    debugPrint("stock room=" .. tostring(manifest.key)
        .. " missingSlots=" .. formatNumberRanges(missingSlots)
        .. " duplicateSeeds=" .. (#duplicateSeeds > 0 and table.concat(duplicateSeeds, ",") or "none")
        .. " subtypeMismatches="
        .. (#subtypeMismatches > 0 and table.concat(subtypeMismatches, ",") or "none"))
    debugPrint(string.format(
        "stock cumulative=%s verifiedRooms=%d/%d verifiedTrinkets=%d/%d liveCatalog=%d registryCoverage=%s oneCellOnly=%s remainingIds=%s",
        allPass and "PASS" or "INCOMPLETE",
        verifiedRooms,
        totalRooms,
        verifiedSlots,
        #session.catalog,
        #liveCatalog,
        registryMatches and "PASS" or "FAIL",
        oneCellOnly and "PASS" or "FAIL",
        formatNumberRanges(remainingIds)
    ))
    debugPrint("stock registryMissingIds=" .. formatNumberRanges(registryMissing)
        .. " registryExtraIds=" .. formatNumberRanges(registryExtra))
end

local function sourceSlot(session, manifest, pickup)
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_TRINKET then return nil end
    local data = pickup:GetData()[STOCK_DATA_KEY]
    if type(data) == "table"
        and data.token == session.token
        and data.roomKey == manifest.key
    then
        local slot = tonumber(data.slot)
        if slot
            and expectedTrinket(session, manifest, slot) == pickup.SubType
            and getSourceSeed(session, manifest, slot) == pickup.InitSeed
        then
            return slot
        end
    end
    for slot = 1, tonumber(manifest.slotCount) or 0 do
        if expectedTrinket(session, manifest, slot) == pickup.SubType
            and getSourceSeed(session, manifest, slot) == pickup.InitSeed
        then
            return slot
        end
    end
    return nil
end

local function removeRoomStock(session, manifest, sourcesBySeed)
    if type(manifest) ~= "table" or manifest.kind ~= "stock" then return end
    local indexed = sourcesBySeed or indexCurrentRoomTrinkets()
    for slot = 1, tonumber(manifest.slotCount) or 0 do
        local pickup = findSourceForSlot(session, manifest, slot, indexed)
        if pickup then pickup:Remove() end
    end
end

local function closeRoom(session, manifest)
    session.closedRooms = session.closedRooms or {}
    local wasClosed = session.closedRooms[manifest.key]
    session.closedRooms[manifest.key] = true
    if not saveNow() then
        session.closedRooms[manifest.key] = wasClosed
        ConchBlessing.printError("Appraisal could not persist its room-wide choice closure.")
        return false
    end
    removeRoomStock(session, manifest)
    return true
end

local function isChoiceClosureDurable(pending)
    return type(pending) == "table"
        and type(pending.token) == "string"
        and M._durableChoiceClosures[pending.token] == true
end

local function persistChoiceClosure(session, pending, manifest)
    if type(session) ~= "table"
        or type(pending) ~= "table"
        or pending.roomClosed ~= true
        or not pending.token
    then
        return false
    end
    if not isChoiceClosureDurable(pending) then
        if not saveNow() then return false end
        M._durableChoiceClosures[pending.token] = true
    end
    if manifest
        and manifest.key == pending.roomKey
        and M._removedChoiceStock[pending.token] ~= true
    then
        removeRoomStock(session, manifest)
        M._removedChoiceStock[pending.token] = true
    end
    return true
end

local function spawnSource(session, manifest, slot)
    local exactId = expectedTrinket(session, manifest, slot)
    local position = NativeGalleryRooms.getSlotWorldPosition(
        Game():GetRoom(),
        manifest,
        slot
    )
    if not exactId or not position then return nil end
    local seed = getSourceSeed(session, manifest, slot)
    local entity = Game():Spawn(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_TRINKET,
        position,
        Vector.Zero,
        nil,
        exactId,
        seed
    )
    local pickup = entity and entity:ToPickup() or nil
    if not pickup then return nil end
    manifest.sourceSeeds[slot] = pickup.InitSeed
    pickup.OptionsPickupIndex = 0
    pickup.Price = 0
    pickup:GetData()[STOCK_DATA_KEY] = {
        token = session.token,
        roomKey = manifest.key,
        slot = slot,
        trinketId = exactId,
    }
    return pickup
end

local function initializeRoomStock(session, manifest)
    if manifest.kind ~= "stock" then return true end
    session.closedRooms = session.closedRooms or {}
    if session.closedRooms[manifest.key] == true then
        removeRoomStock(session, manifest)
        return true
    end

    local pending = session.pendingChoice
    if type(pending) == "table" and pending.roomKey == manifest.key then
        if pending.roomClosed == true and isChoiceClosureDurable(pending) then
            persistChoiceClosure(session, pending, manifest)
        end
        return true
    end

    if manifest.initialized == true then
        local sourcesBySeed = indexCurrentRoomTrinkets()
        for slot = 1, tonumber(manifest.slotCount) or 0 do
            if not findSourceForSlot(session, manifest, slot, sourcesBySeed) then
                -- A previously initialized source cannot be recreated safely:
                -- it may have been consumed immediately before a process exit.
                clearDebugStockRoomVerification(session, manifest)
                ConchBlessing.printError(
                    "Appraisal found missing native room stock and closed that room fail-closed."
                )
                return closeRoom(session, manifest)
            end
        end
        debugAuditCurrentStockRoom(session, manifest, sourcesBySeed)
        return true
    end

    manifest.initializing = true
    if not saveNow() then
        manifest.initializing = nil
        return false
    end

    local spawned = {}
    local sourcesBySeed = indexCurrentRoomTrinkets()
    for slot = 1, tonumber(manifest.slotCount) or 0 do
        local pickup = findSourceForSlot(session, manifest, slot, sourcesBySeed)
            or spawnSource(session, manifest, slot)
        if not pickup then
            for _, source in ipairs(spawned) do
                if source:Exists() then source:Remove() end
            end
            manifest.initializing = nil
            clearDebugStockRoomVerification(session, manifest)
            ConchBlessing.printError("Appraisal could not create all native room stock.")
            saveNow()
            return false
        end
        spawned[#spawned + 1] = pickup
        sourcesBySeed[tonumber(pickup.InitSeed)] = pickup
    end

    manifest.initialized = true
    manifest.initializing = nil
    if not saveNow() then
        for _, source in ipairs(spawned) do
            if source:Exists() then source:Remove() end
        end
        manifest.initialized = nil
        clearDebugStockRoomVerification(session, manifest)
        return false
    end
    debugAuditCurrentStockRoom(session, manifest, sourcesBySeed)
    return true
end

local function setNativeDoorsOpen(open)
    if not M.isCurrentGalleryRoom() then return end
    local room = Game():GetRoom()
    if not room then return end
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then
            pcall(function()
                if open then door:Open() else door:Close(true) end
            end)
        end
    end
end

local function getStageAPI()
    local stageAPI = rawget(_G, "StageAPI")
    return type(stageAPI) == "table" and stageAPI or nil
end

local function getStageAPIExtraRoomState()
    local stageAPI = getStageAPI()
    if not stageAPI then return false end

    if type(stageAPI.InOrTransitioningToExtraRoom) == "function" then
        local ok, result = pcall(function()
            return stageAPI.InOrTransitioningToExtraRoom()
        end)
        if not ok then return nil, "stageapi_origin_unknown" end
        return not not result
    end

    if stageAPI.TransitioningToExtraRoom then return true end
    if type(stageAPI.InExtraRoom) == "function" then
        local ok, result = pcall(function() return stageAPI.InExtraRoom() end)
        if not ok then return nil, "stageapi_origin_unknown" end
        return not not result
    end

    -- This is StageAPI 2.33's own InExtraRoom identity. It is deliberately
    -- narrower than inspecting the native placeholder RoomDescriptor.
    return not not (stageAPI.CurrentLevelMapID and stageAPI.CurrentLevelMapRoomID)
end

local function stageAPIDoorReady(stageAPI)
    return type(stageAPI) == "table"
        and stageAPI.Loaded == true
        and type(stageAPI.CustomDoor) == "table"
        and type(stageAPI.SpawnCustomDoor) == "function"
        and type(stageAPI.GetCustomDoors) == "function"
        and type(stageAPI.GetCustomDoorDataAtSlot) == "function"
        and type(stageAPI.SetDoorOpen) == "function"
end

local function removeReturnDoor(stageAPI)
    if not stageAPIDoorReady(stageAPI) then return false end
    local ok, removed = pcall(function()
        local found = false
        for _, door in ipairs(stageAPI.GetCustomDoors(RETURN_DOOR_NAME)) do
            local persistent = door and door.PersistentData or nil
            if persistent and persistent.Slot == DoorSlot.LEFT0 then
                found = true
                if type(door.Remove) ~= "function" then return false end
                door:Remove(true)
            end
        end
        return found or stageAPI.GetCustomDoorDataAtSlot(
            DoorSlot.LEFT0,
            RETURN_DOOR_NAME
        ) == nil
    end)
    return ok and removed == true
end

local function getReturnDoorData(stageAPI)
    local gridData = stageAPI.GetCustomDoorDataAtSlot(
        DoorSlot.LEFT0,
        RETURN_DOOR_NAME
    )
    return gridData and gridData.PersistData and gridData.PersistData.Data or nil
end

local function setCustomDoorsOpen(open)
    local stageAPI = getStageAPI()
    if not stageAPIDoorReady(stageAPI) or type(stageAPI.GetCustomDoors) ~= "function" then
        return
    end
    local session = getSession()
    local context = session and getCurrentGalleryContext(session) or nil
    if not session
        or not context
        or context.manifest.kind ~= "entrance"
        or session.atroposMode ~= true
        or not session.visitId
    then
        return
    end
    pcall(function()
        for _, customDoor in ipairs(stageAPI.GetCustomDoors(RETURN_DOOR_NAME)) do
            local persistent = customDoor and customDoor.PersistentData or nil
            local data = persistent and persistent.Data or nil
            local door = customDoor
                and customDoor.Data
                and customDoor.Data.DoorEntity
                or nil
            if data
                and data.kind == "gallery_return"
                and data.token == session.token
                and data.visitId == session.visitId
                and persistent.Slot == DoorSlot.LEFT0
                and door
                and door:Exists()
            then
                stageAPI.SetDoorOpen(open, door)
            end
        end
    end)
end

local function setAllGalleryDoorsOpen(open)
    setNativeDoorsOpen(open)
    setCustomDoorsOpen(open)
end

local function ensureReturnDoor(session, context)
    if session.atroposMode ~= true
        or context.manifest.kind ~= "entrance"
        or (session.phase ~= "entering" and session.phase ~= "browsing")
    then
        return true
    end
    local stageAPI = getStageAPI()
    if not stageAPIDoorReady(stageAPI) then return false end
    local data = getReturnDoorData(stageAPI)
    if data and data.token == session.token then
        -- The native floor graph is reused. Re-adopt an earlier Atropos door
        -- instead of depending on StageAPI 2.33's broken GetCustomDoorAtSlot
        -- helper or trying to duplicate its persistent grid.
        data.visitId = session.visitId
        data.kind = "gallery_return"
        return true
    end
    if data and not removeReturnDoor(stageAPI) then return false end
    local room = Game():GetRoom()
    if room:GetDoor(DoorSlot.LEFT0)
        or stageAPI.GetCustomDoorDataAtSlot(DoorSlot.LEFT0)
    then
        return false
    end
    local ok, err = pcall(function()
        stageAPI.SpawnCustomDoor(
            DoorSlot.LEFT0,
            nil,
            nil,
            RETURN_DOOR_NAME,
            {
                token = session.token,
                visitId = session.visitId,
                kind = "gallery_return",
            },
            nil,
            nil,
            RoomTransitionAnim.FADE
        )
    end)
    if not ok then
        ConchBlessing.printError(
            "Appraisal return door could not be spawned: " .. tostring(err)
        )
    end
    return ok
end

local function clearVisitFields(session)
    session.origin = nil
    session.ownerPlayerIndex = nil
    session.cost = nil
    session.atroposMode = nil
    session.entryCommitted = nil
    session.entryJournal = nil
    session.heldAbsorptionJournal = nil
    session.pendingChoice = nil
    session.returnReason = nil
    session.returnIssuedFrom = nil
    session.returnMisdirectionCount = nil
    session.permanentVisitFailure = nil
    session.visitRewardCount = nil
    session.visitId = nil
end

local function resetSessionRuntime(session)
    invalidateRuntime()
    M._runtimeToken = nil
    M._preparedRoomKey = nil
    M._collisionToken = nil
    if session and session.token then
        M._returnTransitionIssued[session.token] = nil
    end
end

local function finalizeFloorEndedSession(session)
    if not session or session.floorEnded ~= true then return false end

    session.phase = "floor_ended_complete"
    clearVisitFields(session)
    if not saveNow() then
        ConchBlessing.printError(
            "Appraisal could not persist its completed cross-floor settlement."
        )
        return false
    end

    local runSave = getRunSave(true)
    if runSave then
        local stored = runSave[SAVE_KEY]
        if stored == session
            or type(stored) == "table" and stored.token == session.token
        then
            runSave[SAVE_KEY] = nil
        end
    end
    resetSessionRuntime(session)
    M._durableChoiceClosures = {}
    M._durableSmeltAttempts = {}
    M._removedChoiceStock = {}
    if not saveNow() then
        -- The durable tombstone above is sufficient for continue recovery;
        -- this in-memory removal only makes the new floor immediately usable.
        ConchBlessing.printError("Appraisal could not remove its settled floor tombstone.")
    end
    return true
end

local function descriptorData(descriptor)
    if not descriptor then return nil end
    local ok, data = pcall(function() return descriptor.Data end)
    if ok then return data end
    return nil
end

local function optionalNumberMatches(saved, actual)
    return saved == nil or tonumber(saved) == tonumber(actual)
end

originDescriptorMatches = function(origin, descriptor, dimension)
    local data = descriptorData(descriptor)
    if type(origin) ~= "table" or not data then return false end
    if not optionalNumberMatches(origin.listIndex, descriptor.ListIndex)
        or not optionalNumberMatches(origin.safeGridIndex, descriptor.SafeGridIndex)
        or not optionalNumberMatches(origin.gridIndex, descriptor.GridIndex)
        or not optionalNumberMatches(origin.spawnSeed, descriptor.SpawnSeed)
        or not optionalNumberMatches(origin.roomType, data.Type)
        or not optionalNumberMatches(origin.roomVariant, data.Variant)
        or not optionalNumberMatches(origin.roomSubType, data.Subtype)
    then
        return false
    end
    if type(descriptor.GetDimension) == "function" then
        local ok, actualDimension = pcall(function()
            return descriptor:GetDimension()
        end)
        if not ok or tonumber(actualDimension) ~= tonumber(dimension) then return false end
    end
    return true
end

local function getValidatedOriginDescriptor(session)
    local origin = session and session.origin or nil
    local dimension = type(origin) == "table" and tonumber(origin.dimension) or nil
    local level = Game():GetLevel()
    if not level or dimension == nil then return nil, nil, "missing_origin" end
    if not optionalNumberMatches(origin.stage, level:GetStage())
        or not optionalNumberMatches(origin.stageType, level:GetStageType())
    then
        return nil, nil, "origin_floor_changed"
    end

    local candidates = {}
    local function addCandidate(value)
        local candidate = tonumber(value)
        if candidate then candidates[#candidates + 1] = candidate end
    end
    addCandidate(origin.roomIndex)
    addCandidate(origin.safeGridIndex)
    addCandidate(origin.gridIndex)
    local checked = {}
    for _, target in ipairs(candidates) do
        if target and not checked[target] then
            checked[target] = true
            local ok, descriptor = pcall(function()
                return level:GetRoomByIdx(target, dimension)
            end)
            if ok and originDescriptorMatches(origin, descriptor, dimension) then
                return descriptor, target
            end
        end
    end
    return nil, nil, "origin_descriptor_invalid"
end

local function isStaleOriginLocation(session)
    local origin = session and session.origin or nil
    if type(origin) ~= "table" or getCurrentDimension() ~= origin.dimension then
        return false
    end
    local level = Game():GetLevel()
    local descriptor = level and level:GetCurrentRoomDesc() or nil
    if not level or not descriptor or origin.listIndex == nil then return false end
    local currentIndex = level:GetCurrentRoomIndex()
    local sameGrid = currentIndex == tonumber(origin.safeGridIndex)
        or currentIndex == tonumber(origin.roomIndex)
    return sameGrid and not originDescriptorMatches(origin, descriptor, origin.dimension)
end

local function settleStaleOrigin(session, message)
    ConchBlessing.printError(message
        or "Appraisal's saved return room no longer matches the room at that map position.")
    local previousPhase = session.phase
    session.permanentVisitFailure = true
    session.phase = "build_failed"
    if not saveNow() then
        session.phase = previousPhase
        session.permanentVisitFailure = nil
        return false
    end
    M._returnTransitionIssued[session.token] = nil
    clearVisitFields(session)
    if not saveNow() then
        ConchBlessing.printError("Appraisal could not clean up its stale return origin.")
    end
    return true
end

local function transitionToOrigin(session)
    local origin = session and session.origin or nil
    if type(origin) ~= "table" then return false end
    local dimension = tonumber(origin.dimension)
    if dimension == nil then return false end
    local descriptor, _, reason = getValidatedOriginDescriptor(session)
    local target = descriptor and tonumber(descriptor.SafeGridIndex) or nil
    if not target then
        return settleStaleOrigin(
            session,
            "Appraisal refused an invalid native return descriptor: " .. tostring(reason)
        )
    end
    local player = getPlayerFromIndex(session.ownerPlayerIndex)
    if not player then return false end
    local level = Game():GetLevel()
    local current = level and level:GetCurrentRoomDesc() or nil
    session.returnIssuedFrom = {
        dimension = getCurrentDimension(),
        listIndex = current and current.ListIndex or nil,
        gridIndex = current and current.GridIndex or nil,
        safeGridIndex = current and current.SafeGridIndex or nil,
    }
    if not saveNow() then
        session.returnIssuedFrom = nil
        return false
    end
    -- Arm before calling the engine. A no-op or synchronously delivered room
    -- callback must not reopen the transaction and recursively issue it again.
    M._returnTransitionIssued[session.token] = true
    local ok, err = pcall(function()
        Game():StartRoomTransition(
            target,
            Direction.NO_DIRECTION,
            RETURN_TRANSITION,
            player,
            dimension
        )
    end)
    if not ok then
        M._returnTransitionIssued[session.token] = nil
        session.returnIssuedFrom = nil
        saveNow()
        ConchBlessing.printError(
            "Appraisal return transition failed: " .. tostring(err)
        )
    end
    return ok
end

local function releaseCompletedReturnLatch(session)
    if not session or M._returnTransitionIssued[session.token] ~= true then return true end
    local departure = session.returnIssuedFrom
    local level = Game():GetLevel()
    local current = level and level:GetCurrentRoomDesc() or nil
    local sameDeparture = type(departure) == "table"
        and current
        and tonumber(getCurrentDimension()) == tonumber(departure.dimension)
        and ((departure.listIndex ~= nil
                and tonumber(current.ListIndex) == tonumber(departure.listIndex))
            or (departure.listIndex == nil
                and (tonumber(current.GridIndex) == tonumber(departure.gridIndex)
                    or tonumber(current.SafeGridIndex)
                        == tonumber(departure.safeGridIndex))))
    if sameDeparture then
        -- A synchronous/no-op callback is not a completed transition. Keep the
        -- write-before-call latch armed so it cannot recurse into another call.
        return false
    end

    local previousCount = tonumber(session.returnMisdirectionCount) or 0
    M._returnTransitionIssued[session.token] = nil
    session.returnIssuedFrom = nil
    session.returnMisdirectionCount = previousCount + 1
    if not saveNow() then
        session.returnMisdirectionCount = previousCount
        session.returnIssuedFrom = departure
        M._returnTransitionIssued[session.token] = true
        return false
    end
    if session.returnMisdirectionCount > MAX_RETURN_MISDIRECTIONS then
        settleStaleOrigin(
            session,
            "Appraisal stopped after repeated native return redirection."
        )
        return false
    end
    return true
end

local function beginReturn(session, reason)
    if not session then return false end
    if session.floorEnded == true then
        return finalizeFloorEndedSession(session)
    end
    if type(session.origin) ~= "table" then return false end
    if session.phase ~= "return_ready" and session.phase ~= "returning" then
        session.phase = "return_ready"
        session.returnReason = reason
    elseif reason and not session.returnReason then
        session.returnReason = reason
    end
    M._collisionToken = nil
    setAllGalleryDoorsOpen(false)

    if session.phase == "return_ready" then
        if not saveNow() then
            ConchBlessing.printError("Appraisal could not persist its return intent.")
            return false
        end
        session.phase = "returning"
        if not saveNow() then
            session.phase = "return_ready"
            ConchBlessing.printError("Appraisal could not persist its return transaction.")
            return false
        end
    end

    if isOriginRoom(session) then return true end
    if isStaleOriginLocation(session) then return settleStaleOrigin(session) end
    if M._returnTransitionIssued[session.token] == true then return true end
    return transitionToOrigin(session)
end

local function returnToOrigin(reason)
    return beginReturn(getSession(), reason)
end

M.returnToOrigin = returnToOrigin

local function completeVisitAtOrigin(session)
    if not session
        or (session.phase ~= "returning" and session.phase ~= "completing")
        or not sessionMatchesCurrentFloor(session)
        or not isOriginRoom(session)
    then
        return false
    end
    if session.phase == "returning" then
        session.phase = "completing"
        if not saveNow() then
            session.phase = "returning"
            ConchBlessing.printError("Appraisal could not persist its arrival at the origin.")
            return false
        end
    end

    local finalPhase = session.permanentVisitFailure == true
        and "build_failed"
        or "completed"
    session.phase = finalPhase
    if not saveNow() then
        session.phase = "completing"
        ConchBlessing.printError("Appraisal could not persist its completed visit.")
        return false
    end

    M._collisionToken = nil
    M._returnTransitionIssued[session.token] = nil
    restoreOriginMusic(session)
    clearVisitFields(session)
    -- The final phase is already durable. This second save only removes stale
    -- visit metadata; a failure cannot reopen or duplicate the transaction.
    if not saveNow() then
        ConchBlessing.printError("Appraisal could not clean up its completed visit metadata.")
    end
    return true
end

local function completeVisitOutsideGallery(session)
    if not session or (session.phase ~= "browsing"
        and session.phase ~= "completing_external")
    then
        return false
    end
    if session.phase == "browsing" then
        session.phase = "completing_external"
        if not saveNow() then
            session.phase = "browsing"
            return false
        end
    end
    session.phase = "completed"
    if not saveNow() then
        session.phase = "completing_external"
        return false
    end
    M._collisionToken = nil
    M._returnTransitionIssued[session.token] = nil
    clearVisitFields(session)
    if not saveNow() then
        ConchBlessing.printError("Appraisal could not clean up an externally ended visit.")
    end
    return true
end

local function heldSnapshotCount(snapshot)
    local count = 0
    if type(snapshot) ~= "table" then return count end
    for slot = 1, 2 do
        if (tonumber(snapshot[slot]) or 0) ~= 0 then count = count + 1 end
    end
    return count
end

local function rollbackEntry(player, session)
    local journal = session and session.entryJournal or nil
    if not player or type(journal) ~= "table" then return false end
    local beforeSmelted = journal.beforeSmelted
    local currentSmelted = getSmeltedSnapshot(player)
    local delta = type(journal.appliedSmeltedDelta) == "table"
        and journal.appliedSmeltedDelta
        or getPositiveSmeltedDelta(beforeSmelted, currentSmelted)
    local smeltedRestored = rollbackSmeltedDelta(player, beforeSmelted, delta)
    local heldRestored = restoreHeldTrinketSnapshot(player, journal.heldSnapshot)
    local coinsBefore = tonumber(journal.coinsBefore)
    if coinsBefore then
        player:AddCoins(coinsBefore - player:GetNumCoins())
    end
    return smeltedRestored
        and heldRestored
        and (not coinsBefore or player:GetNumCoins() == coinsBefore)
end

local function failEntry(session, player, message)
    ConchBlessing.printError(message)
    local rolledBack = rollbackEntry(player, session)
    session.permanentVisitFailure = not rolledBack
    session.entryCommitted = nil
    session.heldAbsorptionJournal = nil
    if session.floorEnded == true then
        return finalizeFloorEndedSession(session)
    end
    beginReturn(session, "entry_failed")
    return false
end

local function commitEntry(session, player)
    if session.phase ~= "entering" or session.entryCommitted == true then
        return session.entryCommitted == true
    end
    local journal = session.entryJournal
    if type(journal) ~= "table" then
        return failEntry(session, player, "Appraisal entry journal was unavailable.")
    end
    if not heldTrinketSnapshotMatches(player, journal.heldSnapshot)
        or player:GetNumCoins() ~= tonumber(journal.coinsBefore)
    then
        return failEntry(
            session,
            player,
            "Appraisal entry inventory changed before its transaction could commit."
        )
    end
    if not canJournalDirectSmelt(player) then
        return failEntry(
            session,
            player,
            "Appraisal requires REPENTOGON's reversible smelt inventory API."
        )
    end

    if not absorbHeldTrinketsDirect(player, session) then
        return failEntry(session, player, "Appraisal could not absorb held trinkets.")
    end
    local currentSmelted = getSmeltedSnapshot(player)
    local appliedDelta = getPositiveSmeltedDelta(journal.beforeSmelted, currentSmelted)
    if countHeldTrinkets(player) ~= 0
        or getSmeltedDeltaSize(appliedDelta) ~= heldSnapshotCount(journal.heldSnapshot)
    then
        return failEntry(
            session,
            player,
            "Appraisal could not verify its held-trinket absorption."
        )
    end
    journal.appliedSmeltedDelta = appliedDelta
    if not saveNow() then
        return failEntry(
            session,
            player,
            "Appraisal could not persist its absorbed held trinkets."
        )
    end

    local cost = math.max(0, math.floor(tonumber(session.cost) or 0))
    player:AddCoins(-cost)
    if player:GetNumCoins() ~= tonumber(journal.coinsBefore) - cost then
        return failEntry(session, player, "Appraisal could not apply its coin payment.")
    end
    journal.coinsApplied = true
    session.entryCommitted = true
    session.phase = "browsing"
    if not saveNow() then
        return failEntry(
            session,
            player,
            "Appraisal could not persist its committed entry."
        )
    end
    setAllGalleryDoorsOpen(true)
    return true
end

local function findHeldReward(player, pending)
    local held = getHeldTrinketSnapshot(player)
    local candidates = {}
    for slot = 1, 2 do
        local exactId = tonumber(held[slot]) or 0
        if exactId ~= 0 then candidates[#candidates + 1] = exactId end
    end
    if #candidates ~= 1 then return nil end
    if pending.pickupConfirmationAmbiguous == true
        or pending.pickupEvidenceSaveFailed == true
        or pending.preAddAmbiguous == true
        or pending.postAddAmbiguous == true
    then
        return nil
    end
    local exactId = candidates[1]
    local expectedExactId = tonumber(pending.expectedExactId)
    local collisionQueueExactId = tonumber(pending.queueExactId)
    local completedQueueExactId = tonumber(pending.pickupQueueExactId)
    local preAddExactId = tonumber(pending.preAddObservedExactId)
    local actualExactId = tonumber(pending.actualExactId)
    if pending.collisionCompleted ~= true
        or pending.pickupConfirmed ~= true
        or pending.nativeAddWindowOpen == true
        or tonumber(pending.pickupConfirmationCount) ~= 1
        or tonumber(pending.preAddCount) ~= 1
        or tonumber(pending.postAddCount) ~= 1
        or expectedExactId == nil
        or (collisionQueueExactId ~= nil
            and collisionQueueExactId ~= expectedExactId
            and collisionQueueExactId ~= actualExactId)
        or preAddExactId ~= expectedExactId
        or actualExactId ~= exactId
        or (completedQueueExactId ~= expectedExactId
            and completedQueueExactId ~= actualExactId)
    then
        return nil
    end
    return actualExactId
end

local function finishFailedSmeltRollback(player, pending, attempt)
    attempt.phase = "rollback_pending"
    local currentSmelted = getSmeltedSnapshot(player)
    local rollbackDelta = type(attempt.rollbackDelta) == "table"
        and attempt.rollbackDelta
        or getPositiveSmeltedDelta(attempt.beforeSmelted, currentSmelted)
    attempt.rollbackDelta = rollbackDelta
    -- Persist the recovery intent before mutating either inventory domain.
    if type(rollbackDelta) ~= "table" or not saveNow() then return nil end

    local smeltedRestored = rollbackSmeltedDelta(
        player,
        attempt.beforeSmelted,
        rollbackDelta
    )
    local heldRestored = restoreHeldTrinketSnapshot(player, attempt.heldSnapshot)
    if not smeltedRestored or not heldRestored then
        saveNow()
        ConchBlessing.printError(
            "Appraisal retained its Smelter journal because inventory rollback is incomplete."
        )
        return nil
    end

    attempt.phase = "rolled_back"
    if not saveNow() then return nil end
    pending.smeltAttempt = nil
    M._durableSmeltAttempts[pending.token] = nil
    if not saveNow() then
        pending.smeltAttempt = attempt
        M._durableSmeltAttempts[pending.token] = true
        return nil
    end
    return false
end

local function absorbSelectedRewardWithSmelter(player, pending)
    local attempt = pending.smeltAttempt
    if type(attempt) ~= "table" then
        local beforeSmelted = getSmeltedSnapshot(player)
        local heldSnapshot = getHeldTrinketSnapshot(player)
        if not beforeSmelted
            or countHeldTrinkets(player) ~= 1
            or heldSnapshot[1] ~= pending.actualExactId
                and heldSnapshot[2] ~= pending.actualExactId
        then
            return false
        end
        attempt = {
            exactId = pending.actualExactId,
            beforeSmelted = beforeSmelted,
            heldSnapshot = heldSnapshot,
            phase = "prepared",
        }
        pending.smeltAttempt = attempt
    end
    if M._durableSmeltAttempts[pending.token] ~= true then
        if not saveNow() then return nil end
        M._durableSmeltAttempts[pending.token] = true
    end

    local currentSmelted = getSmeltedSnapshot(player)
    if not currentSmelted then return false end
    local observedDelta = getPositiveSmeltedDelta(
        attempt.beforeSmelted,
        currentSmelted
    )
    if attempt.phase == "rollback_pending" or attempt.phase == "rolled_back" then
        return finishFailedSmeltRollback(player, pending, attempt)
    end
    local alreadyApplied = countHeldTrinkets(player) == 0
        and getSmeltedDeltaSize(observedDelta) == 1
        and smeltedDeltaApplied(
            attempt.beforeSmelted,
            currentSmelted,
            observedDelta
        )

    if not alreadyApplied then
        if not heldTrinketSnapshotMatches(player, attempt.heldSnapshot)
            or not smeltedSnapshotsMatch(currentSmelted, attempt.beforeSmelted)
        then
            return false
        end
        local shakeBefore = getScreenShakeCountdown()
        local ok = pcall(function()
            player:UseActiveItem(
                CollectibleType.COLLECTIBLE_SMELTER,
                UseFlag.USE_NOANIM,
                -1
            )
        end)
        local shakeAfter = getScreenShakeCountdown()
        attempt.shakeBaseline = shakeBefore
        attempt.shakeObserved = type(shakeAfter) == "number"
            and shakeAfter > (tonumber(shakeBefore) or 0)
        attempt.swallowSoundObserved = isSmelterSwallowPlaying()
        currentSmelted = getSmeltedSnapshot(player)
        observedDelta = getPositiveSmeltedDelta(
            attempt.beforeSmelted,
            currentSmelted
        )
        alreadyApplied = ok
            and countHeldTrinkets(player) == 0
            and getSmeltedDeltaSize(observedDelta) == 1
            and smeltedDeltaApplied(
                attempt.beforeSmelted,
                currentSmelted,
                observedDelta
            )
    end

    if not alreadyApplied then
        attempt.rollbackDelta = observedDelta
        return finishFailedSmeltRollback(player, pending, attempt)
    end

    attempt.phase = "applied"
    attempt.appliedSmeltedDelta = observedDelta
    pending.appliedSmeltedDelta = observedDelta
    pending.smelted = true
    if not saveNow() then
        -- The synchronous engine mutation is still observable. Keep the
        -- prepared journal in memory and retry the durability barrier instead
        -- of granting a second smelt or discarding an applied reward.
        pending.smelted = nil
        return nil
    end
    return true
end

local function finishChoiceFailure(session, message)
    local pending = session.pendingChoice
    if session.phase ~= "choice_failed" then
        local previousPhase = session.phase
        local previousReturnReason = session.returnReason
        local previousPermanentFailure = session.permanentVisitFailure
        local previousFailureReason = type(pending) == "table"
            and pending.failureReason
            or nil
        ConchBlessing.printError(message)
        if type(pending) == "table" then pending.failureReason = message end
        if session.permanentVisitFailure ~= true then
            session.permanentVisitFailure = false
        end
        session.phase = "choice_failed"
        session.returnReason = "choice_failed"
        -- Keep the full pending journal until the failure decision itself is
        -- durable. Finalize it from the next semantic update/lifecycle event;
        -- StartRoomTransition must not re-enter native room code while the
        -- item-queue completion callback is still unwinding.
        if not saveNow() then
            session.phase = previousPhase
            session.returnReason = previousReturnReason
            session.permanentVisitFailure = previousPermanentFailure
            if type(pending) == "table" then
                pending.failureReason = previousFailureReason
            end
            return false
        end
        return false
    end
    if session.floorEnded == true then
        return finalizeFloorEndedSession(session)
    end
    if type(pending) == "table" and pending.token then
        M._durableChoiceClosures[pending.token] = nil
        M._durableSmeltAttempts[pending.token] = nil
        M._removedChoiceStock[pending.token] = nil
    end
    session.pendingChoice = nil
    session.heldAbsorptionJournal = nil
    return beginReturn(session, "choice_failed")
end

local function finishChoiceSuccess(session)
    local pending = session.pendingChoice
    if type(pending) ~= "table" or pending.smelted ~= true then return false end

    if session.phase ~= "choice_complete_ready" then
        local recordedNow = pending.rewardRecorded ~= true
        if recordedNow then
            pending.rewardRecorded = true
            session.visitRewardCount = (tonumber(session.visitRewardCount) or 0) + 1
        end
        session.phase = "choice_complete_ready"
        -- The canonical Smelter call owns its sound and screen shake. Persist
        -- the completed absorption, then let the next semantic update perform
        -- the return instead of re-entering room transition code in this call.
        if saveNow() then return true end
        session.phase = "absorbing"
        if recordedNow then
            pending.rewardRecorded = nil
            session.visitRewardCount = math.max(
                0,
                (tonumber(session.visitRewardCount) or 1) - 1
            )
        end
        return false
    end

    if session.floorEnded == true then
        return finalizeFloorEndedSession(session)
    end

    local attempt = pending.smeltAttempt
    if type(attempt) == "table" and attempt.effectComplete ~= true then
        local shakeCountdown = getScreenShakeCountdown()
        local shakeStillPlaying = attempt.shakeObserved == true
            and type(shakeCountdown) == "number"
            and shakeCountdown > (tonumber(attempt.shakeBaseline) or 0)
        local soundStillPlaying = attempt.swallowSoundObserved == true
            and isSmelterSwallowPlaying()
        if shakeStillPlaying or soundStillPlaying then return false end
        attempt.effectComplete = true
        if not saveNow() then
            attempt.effectComplete = nil
            return false
        end
    end

    local stayInGallery = session.atroposMode == true
        and session.permanentVisitFailure ~= true
        and session.floorEnded ~= true
        and getCurrentGalleryContext(session) ~= nil
    if stayInGallery then
        local completedPending = pending
        session.pendingChoice = nil
        session.heldAbsorptionJournal = nil
        session.phase = "browsing"
        if not saveNow() then
            session.pendingChoice = completedPending
            session.phase = "choice_complete_ready"
            ConchBlessing.printError(
                "Appraisal could not persist its completed Atropos room choice."
            )
            return false
        end
        M._durableChoiceClosures[pending.token] = nil
        M._durableSmeltAttempts[pending.token] = nil
        M._removedChoiceStock[pending.token] = nil
        M._collisionToken = nil
        setAllGalleryDoorsOpen(true)
        return true
    end

    session.pendingChoice = nil
    session.heldAbsorptionJournal = nil
    M._durableChoiceClosures[pending.token] = nil
    M._durableSmeltAttempts[pending.token] = nil
    M._removedChoiceStock[pending.token] = nil
    M._collisionToken = nil
    return beginReturn(
        session,
        session.atroposMode == true and "choice_complete_external" or "choice_complete"
    )
end

local function resolvePreparedChoice(session, context)
    local pending = session.pendingChoice
    if type(pending) ~= "table" or pending.phase ~= "prepared" then return end
    local player = getPlayerFromIndex(pending.playerIndex)
    local source
    if context and context.manifest.key == pending.roomKey then
        source = findSourceForSlot(session, context.manifest, pending.slot)
    end
    local queueEmpty = player
        and type(player.IsItemQueueEmpty) == "function"
        and player:IsItemQueueEmpty()
    if pending.collisionCompleted ~= true and source and queueEmpty then
        local prepared = pending
        session.pendingChoice = nil
        session.phase = "browsing"
        M._collisionToken = nil
        if not saveNow() then
            session.pendingChoice = prepared
            session.phase = "pickup_prepared"
            finishChoiceFailure(session, "Appraisal could not cancel an unapplied choice.")
            return
        end
        setAllGalleryDoorsOpen(true)
        return
    end

    if pending.collisionCompleted ~= true and not source then
        finishChoiceFailure(
            session,
            "Appraisal lost a prepared source without exact collision confirmation."
        )
    end
end

local function advanceChoiceClosure(session, context)
    local pending = session.pendingChoice
    if type(pending) ~= "table" or pending.phase ~= "closing" then return false end
    local manifest = context
        and context.manifest.key == pending.roomKey
        and context.manifest
        or nil
    if not persistChoiceClosure(session, pending, manifest) then return false end

    pending.phase = "animating"
    session.phase = "pickup_animating"
    if not saveNow() then
        pending.phase = "closing"
        session.phase = "pickup_closing"
        return false
    end
    return true
end

local function resolveChoice(session, context)
    local pending = session.pendingChoice
    if type(pending) ~= "table" then return end
    if pending.phase == "prepared" then
        resolvePreparedChoice(session, context)
        pending = session.pendingChoice
        if type(pending) ~= "table" then return end
    end
    if pending.phase == "closing" then
        if not advanceChoiceClosure(session, context) then return end
        pending = session.pendingChoice
    end
    if pending.phase ~= "animating" and pending.phase ~= "absorbing" then return end

    local manifest = context
        and context.manifest.key == pending.roomKey
        and context.manifest
        or nil
    if pending.roomClosed == true
        and not persistChoiceClosure(session, pending, manifest)
    then
        return
    end

    setAllGalleryDoorsOpen(false)
    local player = getPlayerFromIndex(pending.playerIndex)
    if not player or type(player.IsItemQueueEmpty) ~= "function" then
        finishChoiceFailure(session, "Appraisal lost the player owning its choice.")
        return
    end
    if not player:IsItemQueueEmpty() then return end

    if pending.phase == "animating" then
        -- IsaacScript Common emits POST_ITEM_PICKUP from its reordered player
        -- update after MC_POST_UPDATE. Queue-empty alone is therefore not the
        -- acquisition boundary; wait for that explicit completion event.
        if pending.nativeAddWindowOpen == true or pending.pickupConfirmed ~= true then
            return
        end
        local actualExactId = findHeldReward(player, pending)
        if not actualExactId then
            finishChoiceFailure(
                session,
                "Appraisal could not verify the naturally acquired trinket."
            )
            return
        end
        pending.actualExactId = actualExactId
        pending.beforeSmelted = getSmeltedSnapshot(player)
        pending.heldAfterPickup = getHeldTrinketSnapshot(player)
        pending.phase = "absorbing"
        session.phase = "absorbing"
        if not pending.beforeSmelted then
            finishChoiceFailure(session, "Appraisal could not prepare reward absorption.")
            return
        end
        if not saveNow() then return end
    end

    if pending.smelted == true then
        finishChoiceSuccess(session)
        return
    end
    if type(pending.smeltAttempt) ~= "table"
        and (not heldTrinketSnapshotMatches(player, pending.heldAfterPickup)
            or countHeldTrinkets(player) ~= 1)
    then
        finishChoiceFailure(session, "Appraisal reward inventory changed before absorption.")
        return
    end
    local absorbed = absorbSelectedRewardWithSmelter(player, pending)
    if absorbed == nil then return end
    if not absorbed then
        finishChoiceFailure(session, "Appraisal could not absorb its selected trinket.")
        return
    end
    if countHeldTrinkets(player) ~= 0
        or getSmeltedDeltaSize(pending.appliedSmeltedDelta) ~= 1
    then
        finishChoiceFailure(session, "Appraisal could not verify selected-trinket absorption.")
        return
    end
    finishChoiceSuccess(session)
end

local function registerReturnDoor(stageAPI)
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
            local data = doorGridData and doorGridData.Data or nil
            local session = getSession()
            local context = session and getCurrentGalleryContext(session) or nil
            if session
                and data
                and data.kind == "gallery_return"
                and data.token == session.token
                and data.visitId ~= nil
                and data.visitId == session.visitId
                and session.atroposMode == true
                and session.entryCommitted == true
                and session.phase == "browsing"
                and doorGridData.Slot == DoorSlot.LEFT0
                and context
                and context.manifest.kind == "entrance"
            then
                returnToOrigin("gallery_return_door")
            end
        end
    )
end

function M.initializeStageAPI()
    local stageAPI = getStageAPI()
    if not stageAPIDoorReady(stageAPI) then return false end
    if M._initializedStageAPI == stageAPI then return true end
    local ok, err = pcall(registerReturnDoor, stageAPI)
    if not ok then
        ConchBlessing.printError(
            "Appraisal StageAPI return-door initialization failed: " .. tostring(err)
        )
        return false
    end
    M._initializedStageAPI = stageAPI
    return true
end

function M.bootstrapStageAPI()
    local stageAPI = getStageAPI()
    if type(stageAPI) ~= "table" then return false end
    if stageAPI.Loaded == true then return M.initializeStageAPI() end
    if type(stageAPI.ToCall) ~= "table" then return false end
    if stageAPI.__ConchBlessingNativeGalleryQueued then return false end
    stageAPI.__ConchBlessingNativeGalleryQueued = true
    table.insert(stageAPI.ToCall, function()
        stageAPI.__ConchBlessingNativeGalleryQueued = nil
        local manager = ConchBlessing and ConchBlessing.GalleryManager or nil
        if manager and type(manager.initializeStageAPI) == "function" then
            manager.initializeStageAPI()
        end
    end)
    return false
end

local function canStartChoice(player, pickup)
    if not player or not pickup or (tonumber(pickup.Wait) or 0) > 0 then return false end
    if type(player.IsItemQueueEmpty) ~= "function" or not player:IsItemQueueEmpty() then
        return false
    end
    if countHeldTrinkets(player) ~= 0 then return false end
    if type(player.CanPickupItem) == "function" then
        local ok, canPickup = pcall(function() return player:CanPickupItem() end)
        if ok and canPickup == false then return false end
    end
    return true
end

function M.onPrePickupCollision(_, pickup, collider)
    if M._runLifecycleReady ~= true then return end
    local session = getSession()
    if not session then return end
    local context = getCurrentGalleryContext(session)
    if not context or context.manifest.kind ~= "stock" then return end
    local slot = sourceSlot(session, context.manifest, pickup)
    if not slot then return end
    -- From this point onward the pickup is exact manager-owned stock. Block
    -- every competing same-tick/co-op collision while one semantic choice is
    -- unresolved, but never interfere with player-dropped trinkets.
    if session.phase ~= "browsing"
        or session.pendingChoice
        or session.closedRooms and session.closedRooms[context.manifest.key] == true
    then
        return true
    end
    local player = collider and collider:ToPlayer() or nil
    if not player then return true end
    if not canStartChoice(player, pickup) then return true end
    local playerIndex = getPlayerIndex(player)
    if playerIndex == nil then return true end

    local token = table.concat({
        session.token,
        context.manifest.key,
        tostring(slot),
        tostring(pickup.InitSeed),
        tostring(playerIndex),
    }, ":")
    session.pendingChoice = {
        version = 1,
        phase = "prepared",
        token = token,
        roomKey = context.manifest.key,
        slot = slot,
        playerIndex = playerIndex,
        pickupInitSeed = pickup.InitSeed,
        expectedExactId = pickup.SubType,
        collisionWindowOpen = M._nativeEvidenceCallbacksRegistered == true,
    }
    session.phase = "pickup_prepared"
    if not saveNow() then
        session.pendingChoice = nil
        session.phase = "browsing"
        return true
    end
    M._collisionToken = token
    setAllGalleryDoorsOpen(false)
    -- Do not cancel the collision. The engine owns the real trinket pickup,
    -- player hold-up animation, item queue, and pickup sound.
end

function M.onPostPickupCollision(_, pickup, collider)
    if M._runLifecycleReady ~= true then return end
    local session = getSession()
    local pending = session and session.pendingChoice or nil
    if not session
        or session.phase ~= "pickup_prepared"
        or type(pending) ~= "table"
        or pending.phase ~= "prepared"
    then
        return
    end
    local player = collider and collider:ToPlayer() or nil
    if not player
        or pending.playerIndex ~= getPlayerIndex(player)
        or pending.pickupInitSeed ~= pickup.InitSeed
        or pending.token ~= M._collisionToken
    then
        return
    end
    local context = getCurrentGalleryContext(session)
    if not context
        or context.manifest.key ~= pending.roomKey
        or sourceSlot(session, context.manifest, pickup) ~= pending.slot
    then
        return
    end

    pending.collisionWindowOpen = false
    pending.collisionCompleted = true
    pending.nativeAddWindowOpen = true
    pending.phase = "closing"
    pending.roomClosed = true
    session.phase = "pickup_closing"
    session.closedRooms = session.closedRooms or {}
    session.closedRooms[pending.roomKey] = true
    M._collisionToken = nil
    local queued = player.QueuedItem and player.QueuedItem.Item or nil
    if queued and tonumber(queued.ID) then pending.queueExactId = tonumber(queued.ID) end
    if not persistChoiceClosure(session, pending, context.manifest) then
        ConchBlessing.printError("Appraisal could not persist its native pickup collision.")
        return
    end
    pending.phase = "animating"
    session.phase = "pickup_animating"
    if not saveNow() then
        pending.phase = "closing"
        session.phase = "pickup_closing"
        ConchBlessing.printError("Appraisal could not persist its pickup-animation state.")
    end
end

function M.onPostItemPickup(_, player, pickingUpItem)
    if M._runLifecycleReady ~= true then return end
    local session = getSession()
    local pending = session and session.pendingChoice or nil
    if not session
        or type(pending) ~= "table"
        or pending.collisionCompleted ~= true
        or pending.nativeAddWindowOpen ~= true
        or (pending.phase ~= "closing"
            and pending.phase ~= "animating"
            and pending.phase ~= "absorbing")
        or not player
        or not pickingUpItem
        or not isc.isPickingUpItemTrinket(nil, pickingUpItem)
        or pending.playerIndex ~= getPlayerIndex(player)
    then
        return
    end
    local exactId = tonumber(pickingUpItem.subType or pickingUpItem.SubType)
    if not exactId then
        pending.pickupConfirmationAmbiguous = true
        pending.nativeAddWindowOpen = false
        if not saveNow() then pending.pickupEvidenceSaveFailed = true end
        return
    end
    pending.pickupConfirmationCount = (tonumber(pending.pickupConfirmationCount) or 0) + 1
    if pending.pickupConfirmationCount == 1 then
        pending.pickupQueueExactId = exactId
        pending.pickupConfirmed = true
    else
        pending.pickupConfirmationAmbiguous = true
    end
    pending.nativeAddWindowOpen = false
    if not saveNow() then pending.pickupEvidenceSaveFailed = true end
end

local function isNativeAddEvidenceWindow(pending)
    if type(pending) ~= "table" then return false end
    if pending.phase == "prepared" and pending.collisionWindowOpen == true then
        return true
    end
    return pending.collisionCompleted == true
        and pending.nativeAddWindowOpen == true
        and (pending.phase == "closing" or pending.phase == "animating")
end

function M.onPreAddTrinket(_, player, exactId)
    if M._runLifecycleReady ~= true then return end
    local session = getSession()
    local pending = session and session.pendingChoice or nil
    if not session
        or type(pending) ~= "table"
        or not isNativeAddEvidenceWindow(pending)
        or not player
        or pending.playerIndex ~= getPlayerIndex(player)
    then
        return
    end
    pending.preAddCount = (tonumber(pending.preAddCount) or 0) + 1
    if pending.preAddCount == 1 then
        pending.preAddObservedExactId = tonumber(exactId)
    else
        pending.preAddAmbiguous = true
    end
end

function M.onPostTriggerTrinketAdded(_, player, exactId, _, innate)
    if M._runLifecycleReady ~= true then return end
    local session = getSession()
    local pending = session and session.pendingChoice or nil
    if not session
        or type(pending) ~= "table"
        or not isNativeAddEvidenceWindow(pending)
        or not player
        or innate == true
        or pending.playerIndex ~= getPlayerIndex(player)
    then
        return
    end
    pending.postAddCount = (tonumber(pending.postAddCount) or 0) + 1
    if pending.postAddCount == 1 then
        pending.actualExactId = tonumber(exactId)
    else
        pending.postAddAmbiguous = true
    end
    saveNow()
end

local function failVisitInfrastructure(session, message)
    local player = getPlayerFromIndex(session.ownerPlayerIndex)
    local pending = session.pendingChoice
    local choiceCommitted = type(pending) == "table"
        and (pending.collisionCompleted == true
            or pending.roomClosed == true
            or pending.phase == "closing"
            or pending.phase == "animating"
            or pending.phase == "absorbing")
    if (tonumber(session.visitRewardCount) or 0) == 0 and not choiceCommitted then
        return failEntry(session, player, message)
    end
    ConchBlessing.printError(message)
    session.permanentVisitFailure = true
    if choiceCommitted then
        -- Once the native pickup collision committed, entry payment may no
        -- longer be rolled back independently of its reward. Reconcile the
        -- exact pickup/Smelter journal first; it may still be waiting for the
        -- engine item queue to finish its real hold-up animation.
        resolveChoice(session, nil)
        if session.pendingChoice then return false end
        if session.phase == "return_ready" or session.phase == "returning" then
            return true
        end
    end
    return beginReturn(session, "gallery_infrastructure_failed")
end

local function prepareCurrentGalleryRoom(session, context)
    if M._preparedRoomKey == context.manifest.key then return true end
    playGalleryMusic()
    local room = Game():GetRoom()
    if room then room:SetClear(true) end
    local revealed, revealReason = NativeGalleryRooms.reveal(session.graph, context.runtime)
    if not revealed then
        failVisitInfrastructure(
            session,
            "Appraisal could not reveal its native room graph: " .. tostring(revealReason)
        )
        return false
    end
    if session.phase == "entering" and context.manifest.kind == "entrance" then
        setAllGalleryDoorsOpen(false)
        local player = getPlayerFromIndex(session.ownerPlayerIndex)
        if not player then
            failEntry(session, nil, "Appraisal lost its entering player.")
            return false
        end
        if session.atroposMode == true and not ensureReturnDoor(session, context) then
            failEntry(
                session,
                player,
                "Appraisal could not prepare its Atropos return door before payment."
            )
            return false
        end
        if not commitEntry(session, player) then return false end
    end
    if session.phase == "browsing" then
        if context.manifest.kind == "stock" then
            if not initializeRoomStock(session, context.manifest) then
                failVisitInfrastructure(
                    session,
                    "Appraisal could not initialize the current native stock room."
                )
                return false
            end
        elseif context.manifest.kind == "entrance" then
            local stageAPI = getStageAPI()
            if session.atroposMode ~= true and stageAPIDoorReady(stageAPI) then
                -- A previous Atropos visit can leave this persistent custom
                -- grid in the reused floor graph. Prefer removing it; its
                -- callback remains a safe same-floor return fallback if the
                -- provider has not materialized it yet.
                removeReturnDoor(stageAPI)
            end
            if not ensureReturnDoor(session, context) and session.atroposMode == true then
                failVisitInfrastructure(
                    session,
                    "Appraisal lost its Atropos return door after entry."
                )
                return false
            end
        end
        setAllGalleryDoorsOpen(true)
    elseif session.phase == "pickup_prepared"
        or session.phase == "pickup_closing"
        or session.phase == "pickup_animating"
        or session.phase == "absorbing"
        or session.phase == "choice_complete_ready"
    then
        setAllGalleryDoorsOpen(false)
        local pending = session.pendingChoice
        if type(pending) == "table"
            and pending.roomKey == context.manifest.key
            and isChoiceClosureDurable(pending)
        then
            persistChoiceClosure(session, pending, context.manifest)
        end
    end
    M._preparedRoomKey = context.manifest.key
    return true
end

local function markSessionFloorEnded(session)
    if not session then return false end
    if session.floorEnded == true then return true end
    session.floorEnded = true
    session.floorEndedFromPhase = session.phase
    session.floorEndedOn = getCurrentFloorIdentity()
    if not saveNow() then
        session.floorEnded = nil
        session.floorEndedFromPhase = nil
        session.floorEndedOn = nil
        ConchBlessing.printError("Appraisal could not persist its cross-floor settlement intent.")
        return false
    end
    return true
end

local function settleFloorEndedSession(session)
    if not session or session.floorEnded ~= true then return false end
    if session.phase == "floor_ended_complete" then
        return finalizeFloorEndedSession(session)
    end
    if session.phase == "entering" then
        return failEntry(
            session,
            getPlayerFromIndex(session.ownerPlayerIndex),
            "Appraisal entry was interrupted by a floor transition."
        )
    end
    if session.phase == "choice_failed" then
        local pending = session.pendingChoice
        return finishChoiceFailure(
            session,
            type(pending) == "table" and pending.failureReason
                or "Appraisal is settling a failed cross-floor choice."
        )
    end
    if session.pendingChoice then
        resolveChoice(session, nil)
        if getSession() ~= session then return true end
        if session.pendingChoice then return false end
    end
    return finalizeFloorEndedSession(session)
end

function M.onUpdate()
    if M._runLifecycleReady ~= true then return end
    local session = getSession()
    if not session then return end
    if session.floorEnded == true then
        settleFloorEndedSession(session)
        return
    end
    if not sessionMatchesCurrentFloor(session) then
        if markSessionFloorEnded(session) then settleFloorEndedSession(session) end
        return
    end
    if session.phase == "completed" or session.phase == "build_failed" then return end
    if completeVisitAtOrigin(session) then return end

    if session.phase == "return_ready" or session.phase == "returning" then
        beginReturn(session, session.returnReason)
        return
    end
    if session.phase == "completing" then
        -- Completing is only valid at the exact saved origin. If another
        -- provider moved the player between the two durability barriers,
        -- restore the return transaction instead of accepting the wrong room.
        session.phase = "return_ready"
        beginReturn(session, session.returnReason)
        return
    end
    if session.phase == "choice_failed" then
        local pending = session.pendingChoice
        finishChoiceFailure(
            session,
            type(pending) == "table" and pending.failureReason
                or "Appraisal is recovering a failed choice."
        )
        return
    end
    if session.phase == "completing_external" then
        completeVisitOutsideGallery(session)
        return
    end

    local context = getCurrentGalleryContext(session)
    if context then
        if session.phase == "entering" and context.manifest.kind == "entrance" then
            prepareCurrentGalleryRoom(session, context)
        elseif session.phase == "browsing"
            and M._preparedRoomKey ~= context.manifest.key
        then
            prepareCurrentGalleryRoom(session, context)
        end
        if session.phase == "entering"
            or session.phase == "pickup_prepared"
            or session.phase == "pickup_closing"
            or session.phase == "pickup_animating"
            or session.phase == "absorbing"
            or session.phase == "choice_complete_ready"
        then
            setAllGalleryDoorsOpen(false)
        end
    end
    if session.pendingChoice then resolveChoice(session, context) end
end

function M.onPostNewRoom()
    if M._runLifecycleReady ~= true then return end
    M._preparedRoomKey = nil
    M._collisionToken = nil
    invalidateRuntime()
    local session = getSession()
    if not session then return end
    if session.floorEnded == true then
        settleFloorEndedSession(session)
        return
    end
    if not sessionMatchesCurrentFloor(session) then
        if markSessionFloorEnded(session) then settleFloorEndedSession(session) end
        return
    end
    if completeVisitAtOrigin(session) then return end
    if (session.phase == "return_ready"
            or session.phase == "returning"
            or session.phase == "completing")
        and not releaseCompletedReturnLatch(session)
    then
        return
    end
    local context = getCurrentGalleryContext(session)
    if context then
        if session.phase == "entering" and context.manifest.kind ~= "entrance" then
            failEntry(
                session,
                getPlayerFromIndex(session.ownerPlayerIndex),
                "Appraisal entry reached the wrong native room."
            )
            return
        end
        if session.phase == "return_ready"
            or session.phase == "returning"
            or session.phase == "completing"
        then
            if session.phase == "completing" then session.phase = "return_ready" end
            beginReturn(session, session.returnReason)
            return
        end
        if session.phase == "choice_failed" then
            local pending = session.pendingChoice
            finishChoiceFailure(
                session,
                type(pending) == "table" and pending.failureReason
                    or "Appraisal is recovering a failed choice."
            )
            return
        end
        prepareCurrentGalleryRoom(session, context)
        if session.pendingChoice then resolveChoice(session, context) end
        return
    end

    if getCurrentDimension() ~= DC_DIMENSION then
        if session.phase == "entering" then
            failEntry(
                session,
                getPlayerFromIndex(session.ownerPlayerIndex),
                "Appraisal entry ended outside its native entrance."
            )
        elseif session.phase == "choice_failed" then
            local pending = session.pendingChoice
            finishChoiceFailure(
                session,
                type(pending) == "table" and pending.failureReason
                    or "Appraisal is recovering a failed choice."
            )
        elseif session.pendingChoice then
            resolveChoice(session, nil)
        elseif session.phase == "return_ready"
            or session.phase == "returning"
            or session.phase == "completing"
        then
            if session.phase == "completing" then session.phase = "return_ready" end
            beginReturn(session, session.returnReason)
        elseif session.phase == "browsing" or session.phase == "completing_external" then
            completeVisitOutsideGallery(session)
        end
        return
    end

    if session.phase ~= "completed" and session.phase ~= "build_failed" then
        if session.phase == "entering" then
            failEntry(
                session,
                getPlayerFromIndex(session.ownerPlayerIndex),
                "Appraisal entered an unowned Death Certificate room."
            )
        elseif session.pendingChoice then
            resolveChoice(session, nil)
        else
            session.permanentVisitFailure = true
            beginReturn(session, "foreign_death_certificate_room")
        end
    end
end

function M.onPostNewLevel()
    if M._runLifecycleReady ~= true then return end
    local session = getSession()
    invalidateRuntime()
    M._runtimeToken = nil
    M._preparedRoomKey = nil
    M._collisionToken = nil
    M._debugStockAudit = nil
    if session and session.token then M._returnTransitionIssued[session.token] = nil end
    if session then
        if markSessionFloorEnded(session) then settleFloorEndedSession(session) end
        return
    end
    M._durableChoiceClosures = {}
    M._durableSmeltAttempts = {}
    M._removedChoiceStock = {}
    M._returnTransitionIssued = {}
end

local function reconcileInterruptedBuild(session)
    if not session or session.phase ~= "building" then return session end

    if type(session.graph) == "table" and session.graph.complete == true then
        invalidateRuntime()
        M._runtimeToken = nil
        local runtime, reason = getRuntime(session)
        if runtime then
            session.phase = "completed"
            if not saveNow() then
                ConchBlessing.printError(
                    "Appraisal restored its completed room build but could not persist recovery."
                )
            end
            return session
        end
        ConchBlessing.printError(
            "Appraisal could not restore its interrupted native build: " .. tostring(reason)
        )
        session.phase = "build_failed"
        saveNow()
        return session
    end

    if type(session.graph) ~= "table" or session.graph.entrance == nil then
        local empty = NativeGalleryRooms.isDimensionEmpty()
        if empty == true then
            local runSave = getRunSave(true)
            if runSave then runSave[SAVE_KEY] = nil end
            saveNow()
            return nil
        end
    end

    -- Native placed rooms cannot be rolled back. A partial persisted graph is
    -- therefore a permanent floor-local tombstone, never an active visit.
    session.phase = "build_failed"
    if not saveNow() then
        ConchBlessing.printError("Appraisal could not persist its interrupted-build tombstone.")
    end
    return session
end

local function clearRunTransientState()
    invalidateRuntime()
    M._runtimeToken = nil
    M._preparedRoomKey = nil
    M._collisionToken = nil
    M._durableChoiceClosures = {}
    M._durableSmeltAttempts = {}
    M._removedChoiceStock = {}
    M._returnTransitionIssued = {}
    M._debugStockAudit = nil
end

function M.onGameStarted(_, isContinued)
    M._runLifecycleReady = false
    clearRunTransientState()
    M.bootstrapStageAPI()

    local runSave = getRunSave(true)
    local rawSession = runSave and runSave[SAVE_KEY] or nil
    if type(rawSession) == "table"
        and (rawSession.version ~= SESSION_VERSION or rawSession.mode ~= MODE_APPRAISAL)
    then
        runSave[SAVE_KEY] = nil
        rawSession = nil
        if not saveNow() then
            ConchBlessing.printError(
                "Appraisal could not discard an incompatible saved room session."
            )
            return
        end
    end
    local session = getSession()
    if not isContinued and session then
        runSave[SAVE_KEY] = nil
        if not saveNow() then
            ConchBlessing.printError(
                "Appraisal could not discard the previous run's room session."
            )
            return
        end
        session = nil
    end
    -- From here onward this callback has authoritatively reconciled new-run
    -- versus continued-run state. Later room/update callbacks may now act.
    M._runLifecycleReady = true
    if not session then return end
    local loadedPending = session.pendingChoice
    if isContinued
        and type(loadedPending) == "table"
        and loadedPending.nativeAddWindowOpen == true
        and loadedPending.pickupConfirmed ~= true
    then
        -- The process-local deferred AddTrinket/queue completion event cannot
        -- be replayed or attributed exactly after continue. Close it failed
        -- instead of leaving the selected room locked forever.
        loadedPending.nativeAddWindowOpen = false
        loadedPending.pickupConfirmationAmbiguous = true
        finishChoiceFailure(
            session,
            "Appraisal could not resume an interrupted native trinket pickup."
        )
        return
    end
    if type(loadedPending) == "table"
        and loadedPending.roomClosed == true
        and loadedPending.token
    then
        -- This session was reconstructed from disk, so its closure ledger is
        -- already beyond the durability barrier even though runtime markers
        -- intentionally do not survive a process restart.
        M._durableChoiceClosures[loadedPending.token] = true
    end
    if type(loadedPending) == "table"
        and type(loadedPending.smeltAttempt) == "table"
        and loadedPending.token
    then
        M._durableSmeltAttempts[loadedPending.token] = true
    end

    if session.phase == "floor_ended_complete" then
        session.floorEnded = true
        finalizeFloorEndedSession(session)
        return
    end
    if session.floorEnded == true or not sessionMatchesCurrentFloor(session) then
        if markSessionFloorEnded(session) then settleFloorEndedSession(session) end
        return
    end

    session = reconcileInterruptedBuild(session)
    if not session then return end

    if completeVisitAtOrigin(session) then return end
    if session.phase == "return_ready" or session.phase == "returning" then
        beginReturn(session, session.returnReason)
        return
    end
    if session.phase == "completing" then
        session.phase = "return_ready"
        beginReturn(session, session.returnReason)
        return
    end
    if session.phase == "choice_failed" then
        finishChoiceFailure(
            session,
            type(loadedPending) == "table" and loadedPending.failureReason
                or "Appraisal is recovering a failed choice."
        )
        return
    end
    if session.phase == "completing_external" then
        completeVisitOutsideGallery(session)
        return
    end
    if session.phase == "entering" and getCurrentDimension() ~= DC_DIMENSION then
        failEntry(
            session,
            getPlayerFromIndex(session.ownerPlayerIndex),
            "Appraisal recovered an entry that never reached its native entrance."
        )
        return
    end

    local runtime, reason = getRuntime(session)
    if not runtime then
        ConchBlessing.printError(
            "Appraisal could not restore its native room graph: " .. tostring(reason)
        )
        if session.phase == "entering" then
            failEntry(session, getPlayerFromIndex(session.ownerPlayerIndex), "Appraisal entry graph was lost.")
        elseif session.pendingChoice then
            resolveChoice(session, nil)
        elseif session.phase ~= "completed" and session.phase ~= "build_failed" then
            session.permanentVisitFailure = true
            beginReturn(session, "graph_restore_failed")
        else
            session.phase = "build_failed"
            saveNow()
        end
        return
    end
    debugAuditGraph(session)
    local revealed, revealReason = NativeGalleryRooms.reveal(session.graph, runtime)
    if not revealed then
        ConchBlessing.printError(
            "Appraisal could not reveal its restored native graph: " .. tostring(revealReason)
        )
        if session.phase == "completed" then
            session.phase = "build_failed"
            saveNow()
        else
            failVisitInfrastructure(
                session,
                "Appraisal could not safely resume its native room graph."
            )
        end
        return
    end
    local context = getCurrentGalleryContext(session)
    if context then
        if session.phase == "entering" and context.manifest.kind ~= "entrance" then
            failEntry(
                session,
                getPlayerFromIndex(session.ownerPlayerIndex),
                "Appraisal continued in the wrong native room."
            )
            return
        end
        prepareCurrentGalleryRoom(session, context)
        if session.pendingChoice then resolveChoice(session, context) end
    elseif session.phase == "entering" then
        failEntry(
            session,
            getPlayerFromIndex(session.ownerPlayerIndex),
            "Appraisal continued outside its exact native entrance."
        )
    elseif session.pendingChoice then
        resolveChoice(session, nil)
    elseif session.phase == "browsing" then
        completeVisitOutsideGallery(session)
    end
end

function M.onPreGameExit()
    M._runLifecycleReady = false
    clearRunTransientState()
end

local function isPrimaryPocketHourglass(player)
    if type(player.GetPocketItem) == "function"
        and type(PillCardSlot) == "table"
        and type(PocketItemType) == "table"
    then
        local ok, pocket = pcall(function()
            return player:GetPocketItem(PillCardSlot.PRIMARY)
        end)
        if ok and pocket
            and type(pocket.GetType) == "function"
            and type(pocket.GetSlot) == "function"
        then
            local typeOK, pocketType = pcall(function() return pocket:GetType() end)
            local slotOK, rawSlot = pcall(function() return pocket:GetSlot() end)
            if typeOK and slotOK and pocketType == PocketItemType.ACTIVE_ITEM then
                local activeSlot = tonumber(rawSlot)
                activeSlot = activeSlot and activeSlot - 1 or nil
                if activeSlot ~= ActiveSlot.SLOT_POCKET
                    and activeSlot ~= ActiveSlot.SLOT_POCKET2
                then
                    return false
                end
                return player:GetActiveItem(activeSlot)
                    == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
            end
            return false
        end
    end
    local pocketHasHourglass = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
        or player:GetActiveItem(ActiveSlot.SLOT_POCKET2)
            == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
    if not pocketHasHourglass then return false end
    return player:GetCard(0) == 0 and player:GetPill(0) == 0
end

local function isHourglassCopyCard(player)
    local card = player:GetCard(0)
    if card == Card.CARD_QUESTIONMARK then
        return player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
    end
    if card ~= Card.CARD_WILD
        or type(player.GetWildCardItem) ~= "function"
        or type(player.GetWildCardItemType) ~= "function"
    then
        return false
    end
    local ok, item, itemType = pcall(function()
        return player:GetWildCardItem(), player:GetWildCardItemType()
    end)
    local isActiveType = itemType == ItemType.ITEM_ACTIVE
        or (type(PocketItemType) == "table" and itemType == PocketItemType.ACTIVE_ITEM)
    return ok
        and isActiveType
        and item == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
end

function M.onInputAction(_, entity, inputHook, action)
    if M._runLifecycleReady ~= true then return end
    if action ~= ButtonAction.ACTION_ITEM and action ~= ButtonAction.ACTION_PILLCARD then
        return
    end
    local player = entity and entity:ToPlayer() or nil
    if not player or not M.isCurrentGalleryRoom() then return end
    local blocksHourglass = action == ButtonAction.ACTION_ITEM
        and player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
        or action == ButtonAction.ACTION_PILLCARD
            and (isPrimaryPocketHourglass(player) or isHourglassCopyCard(player))
    if not blocksHourglass then return end
    if inputHook == InputHook.GET_ACTION_VALUE then return 0.0 end
    if inputHook == InputHook.IS_ACTION_PRESSED
        or inputHook == InputHook.IS_ACTION_TRIGGERED
    then
        return false
    end
end

function M.onPreUseGlowingHourglass()
    if M._runLifecycleReady ~= true then return end
    if M.isCurrentGalleryRoom() then
        ConchBlessing.print("[Appraisal] Glowing Hourglass is disabled in its rooms.")
        return true
    end
end

local function hasRemainingStock(session)
    if type(session) ~= "table" or type(session.graph) ~= "table" then return false end
    local closed = session.closedRooms or {}
    for _, manifest in ipairs(session.graph.rooms or {}) do
        if manifest.kind == "stock"
            and (tonumber(manifest.slotCount) or 0) > 0
            and closed[manifest.key] ~= true
        then
            return true
        end
    end
    return false
end

local function inspectStart(player, cost)
    if M._runLifecycleReady ~= true then return "run_not_ready" end
    local inStageAPIExtraRoom, stageAPIOriginReason = getStageAPIExtraRoomState()
    if inStageAPIExtraRoom == nil then
        return stageAPIOriginReason or "stageapi_origin_unknown"
    end
    if inStageAPIExtraRoom then return "stageapi_extra_room" end

    local available, dependencyReason = NativeGalleryRooms.isAvailable()
    if not available then return dependencyReason or "repentogon_missing" end
    local transitionMode = getRoomTransitionMode()
    if getDeathCertificateUseFlags() == nil or transitionMode == nil then
        return "repentogon_incompatible"
    end
    if transitionMode ~= 0 then return "transition_busy" end
    if M._nativeEvidenceCallbacksRegistered ~= true then
        return "repentogon_incompatible"
    end
    if not player or getPlayerIndex(player) == nil then return "invalid_player" end
    if not canJournalDirectSmelt(player) then return "repentogon_missing" end
    if not getRunSave(true) then return "save_unavailable" end
    if getCurrentDimension() == DC_DIMENSION then return "death_certificate" end

    local requiredCoins = math.max(0, math.floor(tonumber(cost) or 0))
    if player:GetNumCoins() < requiredCoins then
        return "coins", requiredCoins, player:GetNumCoins()
    end

    local session = getSession()
    if session and (session.floorEnded == true or not sessionMatchesCurrentFloor(session)) then
        if markSessionFloorEnded(session) then settleFloorEndedSession(session) end
        session = getSession()
        if session then return "active" end
    end
    session = reconcileInterruptedBuild(session)
    if session and (session.phase == "return_ready" or session.phase == "returning") then
        beginReturn(session, session.returnReason)
        if isOriginRoom(session) then completeVisitAtOrigin(session) end
        session = getSession()
    elseif session and session.phase == "completing" and isOriginRoom(session) then
        completeVisitAtOrigin(session)
        session = getSession()
    end
    if session and session.phase == "build_failed" then return "build_failed" end
    if session and session.phase ~= "completed" then return "active" end
    if session then
        invalidateRuntime()
        local runtime, reason = getRuntime(session)
        if not runtime then return reason or "graph_restore_failed" end
        debugAuditGraph(session)
        if not hasRemainingStock(session) then return "no_trinkets" end
        if session.atroposMode == true and not M.initializeStageAPI() then
            return "stageapi_missing"
        end
        return nil, requiredCoins, player:GetNumCoins(), session.catalog, session
    end

    local catalog = getRegisteredTrinkets()
    if #catalog == 0 then return "no_trinkets" end
    if anyoneHasAtropos() and not M.initializeStageAPI() then
        return "stageapi_missing"
    end
    return nil, requiredCoins, player:GetNumCoins(), catalog, nil
end

function M.getStartBlockReason(player, cost)
    return inspectStart(player, cost)
end

local function createFloorSession(catalog)
    local runSave = getRunSave(true)
    if not runSave then return nil, "save_unavailable" end
    runSave[SEQUENCE_KEY] = (tonumber(runSave[SEQUENCE_KEY]) or 0) + 1
    local sequence = runSave[SEQUENCE_KEY]
    local startSeed = Game():GetSeeds():GetStartSeed()
    local session = {
        version = SESSION_VERSION,
        mode = MODE_APPRAISAL,
        token = tostring(startSeed) .. ":" .. tostring(sequence),
        seed = ((math.abs(startSeed) + sequence * 104729) % 2147483646) + 1,
        floor = getCurrentFloorIdentity(),
        catalog = catalog,
        closedRooms = {},
        phase = "building",
    }
    if not setSession(session) then
        return nil, "save_failed"
    end
    if not saveNow() then
        runSave[SAVE_KEY] = nil
        return nil, "save_failed"
    end

    local graph, reason = NativeGalleryRooms.build(
        session.seed,
        #catalog,
        function(partialGraph)
            session.graph = partialGraph
            return saveNow()
        end
    )
    if not graph then
        local mayHaveNoPlacedRoom = not session.graph or not session.graph.entrance
        local dimensionEmpty = mayHaveNoPlacedRoom
            and NativeGalleryRooms.isDimensionEmpty()
            or false
        if dimensionEmpty == true then
            runSave[SAVE_KEY] = nil
        else
            -- TryPlaceRoom mutates the native level before the first manifest
            -- can be persisted. Any non-empty or unknowable dimension must
            -- retain a floor-local tombstone because native rooms cannot be
            -- rolled back.
            session.phase = "build_failed"
        end
        saveNow()
        return nil, reason or "build_failed"
    end
    session.graph = graph
    session.phase = "completed"
    if not saveNow() then
        session.phase = "build_failed"
        saveNow()
        return nil, "save_failed"
    end
    invalidateRuntime()
    M._runtimeToken = nil
    local runtime, restoreReason = getRuntime(session)
    if not runtime then
        session.phase = "build_failed"
        saveNow()
        return nil, restoreReason or "graph_restore_failed"
    end
    debugAuditGraph(session)
    return session
end

function M.startAppraisal(player, cost)
    local reason, requiredCoins, coins, catalog, session = inspectStart(player, cost)
    if reason then return false, reason, requiredCoins, coins end
    if not session then
        session, reason = createFloorSession(catalog)
        if not session then return false, reason end
    end
    if not hasRemainingStock(session) then return false, "no_trinkets" end

    -- Re-enumerate the full shared dimension immediately before opening an
    -- entry transaction. The canonical Death Certificate routine accepts any
    -- non-empty descriptor at grid 80, so cached ownership is not sufficient.
    invalidateRuntime()
    M._runtimeToken = nil
    local runtime, runtimeReason = getRuntime(session)
    if not runtime then return false, runtimeReason or "graph_restore_failed" end

    local level = Game():GetLevel()
    local descriptor = level and level:GetCurrentRoomDesc() or nil
    local originData = descriptorData(descriptor)
    local originDimension = getCurrentDimension()
    if not level or not descriptor or not originData or originDimension == nil then
        return false, "invalid_room"
    end
    local beforeSmelted = getSmeltedSnapshot(player)
    if not beforeSmelted then return false, "repentogon_missing" end

    local atroposMode = anyoneHasAtropos()
    if atroposMode and not M.initializeStageAPI() then
        return false, "stageapi_missing"
    end
    clearVisitFields(session)
    session.visitSequence = (tonumber(session.visitSequence) or 0) + 1
    session.visitId = session.token .. ":visit:" .. tostring(session.visitSequence)
    session.visitRewardCount = 0
    session.phase = "entering"
    session.ownerPlayerIndex = getPlayerIndex(player)
    session.cost = requiredCoins
    session.atroposMode = atroposMode
    session.origin = {
        roomIndex = level:GetCurrentRoomIndex(),
        gridIndex = descriptor.GridIndex,
        safeGridIndex = descriptor.SafeGridIndex,
        listIndex = descriptor.ListIndex,
        spawnSeed = descriptor.SpawnSeed,
        roomType = originData.Type,
        roomVariant = originData.Variant,
        roomSubType = originData.Subtype,
        dimension = originDimension,
        stage = level:GetStage(),
        stageType = level:GetStageType(),
        musicId = getCurrentMusicId(),
    }
    session.entryJournal = {
        heldSnapshot = getHeldTrinketSnapshot(player),
        beforeSmelted = beforeSmelted,
        coinsBefore = player:GetNumCoins(),
    }
    if not saveNow() then
        session.phase = "completed"
        clearVisitFields(session)
        return false, "save_failed"
    end

    local entrance = session.graph and session.graph.entrance or nil
    local entranceDescriptor = runtime.entrance
    local target = entrance and tonumber(entrance.safeGridIndex) or nil
    local canonicalTarget = tonumber(NativeGalleryRooms.ENTRANCE_GRID_INDEX)
    if not target
        or not canonicalTarget
        or target ~= canonicalTarget
        or tonumber(entrance.gridIndex) ~= canonicalTarget
        or not entranceDescriptor
        or tonumber(entranceDescriptor.SafeGridIndex) ~= canonicalTarget
        or tonumber(entranceDescriptor.GridIndex) ~= canonicalTarget
    then
        session.phase = "build_failed"
        clearVisitFields(session)
        saveNow()
        return false, "graph_restore_failed"
    end

    local transitionModeBefore = getRoomTransitionMode()
    if transitionModeBefore == nil or transitionModeBefore ~= 0 then
        session.phase = "completed"
        clearVisitFields(session)
        saveNow()
        return false, transitionModeBefore == nil
            and "repentogon_incompatible"
            or "transition_busy"
    end

    -- Directly transitioning into dimension 2 skips the private return-room
    -- snapshot owned by Death Certificate and crashes Level::ChangeRoom on
    -- exit. The canonical item effect sees our validated room at grid 80,
    -- skips vanilla room generation, records that snapshot, and owns the
    -- lying/fade/get-up sequence. Arrival still commits only after the exact
    -- manager entrance is observed in MC_POST_NEW_ROOM.
    local transitioned, transitionError = pcall(function()
        player:UseActiveItem(
            CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE,
            getDeathCertificateUseFlags(),
            -1
        )
    end)
    local transitionModeAfter = getRoomTransitionMode()
    if not transitioned or transitionModeAfter == nil or transitionModeAfter == 0 then
        session.phase = "completed"
        clearVisitFields(session)
        saveNow()
        ConchBlessing.printError(
            "Appraisal canonical Death Certificate entry failed: "
                .. tostring(transitionError or transitionModeAfter)
        )
        return false, "transition_failed"
    end
    return true
end

ConchBlessing:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    M.onPrePickupCollision,
    PickupVariant.PICKUP_TRINKET
)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, M.onUpdate)
ConchBlessing:AddPriorityCallback(
    ModCallbacks.MC_POST_NEW_ROOM,
    CALLBACK_PRIORITY_LATE,
    M.onPostNewRoom
)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, M.onPostNewLevel)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, M.onGameStarted)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, M.onPreGameExit)
ConchBlessing:AddPriorityCallback(
    ModCallbacks.MC_INPUT_ACTION,
    CALLBACK_PRIORITY_LATE,
    M.onInputAction
)
ConchBlessing:AddCallback(
    ModCallbacks.MC_PRE_USE_ITEM,
    M.onPreUseGlowingHourglass,
    CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
)
ConchBlessing:AddCallbackCustom(
    isc.ModCallbackCustom.POST_ITEM_PICKUP,
    M.onPostItemPickup
)

local repentogon = rawget(_G, "REPENTOGON")
local preAddTrinketCallback = ModCallbacks.MC_PRE_ADD_TRINKET
local postAddTrinketCallback = ModCallbacks.MC_POST_TRIGGER_TRINKET_ADDED
local postPickupCollisionCallback = ModCallbacks.MC_POST_PICKUP_COLLISION
if type(repentogon) == "table"
    and repentogon.Real == true
    and type(preAddTrinketCallback) == "number"
    and type(postAddTrinketCallback) == "number"
    and type(postPickupCollisionCallback) == "number"
then
    ConchBlessing:AddPriorityCallback(
        preAddTrinketCallback,
        CALLBACK_PRIORITY_EARLY,
        M.onPreAddTrinket
    )
    ConchBlessing:AddCallback(postAddTrinketCallback, M.onPostTriggerTrinketAdded)
    ConchBlessing:AddPriorityCallback(
        postPickupCollisionCallback,
        CALLBACK_PRIORITY_EARLY,
        M.onPostPickupCollision,
        PickupVariant.PICKUP_TRINKET
    )
    M._nativeEvidenceCallbacksRegistered = true
else
    M._nativeEvidenceCallbacksRegistered = false
end

return M
