ConchBlessing.StageAPIGalleryRooms = ConchBlessing.StageAPIGalleryRooms or {}
local M = ConchBlessing.StageAPIGalleryRooms

-- StageAPI LevelMaps are virtual maps backed by the engine's reusable off-grid
-- rooms. This fixed, project-owned ID keeps Appraisal entirely outside native
-- dimension 2, so vanilla Death Certificate remains free to build its own map.
-- StageAPI's automatic IDs start at -2 and count downward; this deliberately
-- distant value also makes accidental collision with an ordinary LevelMap very
-- unlikely. Every adoption path still validates ownership before touching it.
local MAP_DIMENSION = -434210
local GRAPH_VERSION = 1
local MARKER_SCHEMA = 1
local BACKEND_NAME = "stageapi_levelmap"
local MARKER_KEY = "__ConchBlessingStageAPIGallery"
local RUNTIME_MAP_MARKER = "__ConchBlessingStageAPIGalleryMap"
local CALLBACK_OWNER = "ConchBlessing.StageAPIGalleryRooms"
local EMPTY_LAYOUT_NAME = "ConchBlessing:StageAPIGallery:Empty1x1:v1"
local STOCK_CAPACITY = 28
local PERSISTENT_INDEX_STRIDE = 1000
local MINIMAP_ROOM_ID_PREFIX = "ConchBlessing:Appraisal:"
local MINIMAP_DISPLAY_FLAGS = 5
local STAGEAPI_MINIMAP_COMPAT_MARKER = "__ConchBlessingMinimapCompatProvider"
-- MiniMAPI's NiceJourney (map mouse/keypad teleport) delegates rooms carrying
-- a TeleportHandler entirely to that handler. The methods are attached after
-- the shared member helpers below; registration and validation compare this
-- table by identity, so it must stay the single handler instance.
local MINIMAP_TELEPORT_HANDLER = {}

M.MAP_DIMENSION = MAP_DIMENSION
M.GRAPH_VERSION = GRAPH_VERSION
M.BACKEND_NAME = BACKEND_NAME
M.ENTRANCE_MAP_ID = 1
M.STOCK_CAPACITY = STOCK_CAPACITY

local function getStageAPI()
    local stageAPI = rawget(_G, "StageAPI")
    if type(stageAPI) == "table" and stageAPI.Loaded == true then
        return stageAPI
    end
    return nil
end

local function getMinimapAPI()
    local minimapAPI = rawget(_G, "MinimapAPI")
    if type(minimapAPI) == "table" then return minimapAPI end
    return nil
end

local function checkMinimapCapabilities(minimapAPI)
    if type(minimapAPI) ~= "table" then
        return false, "MiniMAPI is unavailable"
    end
    local requiredFunctions = {
        "AddRoom",
        "GetRoomTypeIconID",
        "GetUnknownRoomTypeIconID",
        "GetLevel",
        "SetLevel",
        "SetPlayerPosition",
        "AddPlayerPositionCallback",
        "AddDimensionCallback",
        "RemovePlayerPositionCallbacks",
        "RemoveDimensionCallbacks",
    }
    for _, name in ipairs(requiredFunctions) do
        if type(minimapAPI[name]) ~= "function" then
            return false, "MiniMAPI capability is missing: " .. name
        end
    end
    if type(minimapAPI.RoomTypeDisplayFlagsAdjacent) ~= "table" then
        return false, "MiniMAPI room display data is unavailable"
    end
    return true
end

local function ensureStageAPIMinimapCompatibility(stageAPI, minimapAPI)
    if type(stageAPI) ~= "table"
        or type(stageAPI.LoadMinimapAPICompat) ~= "function"
    then
        return false, "StageAPI MiniMAPI compatibility capability is unavailable"
    end
    local bridgedProvider = rawget(stageAPI, STAGEAPI_MINIMAP_COMPAT_MARKER)
    if stageAPI.LoadedMinimapAPICompat == true
        and bridgedProvider == minimapAPI
    then
        return true
    end
    local reset, resetError = pcall(function()
        minimapAPI:RemovePlayerPositionCallbacks("StageAPI")
        minimapAPI:RemoveDimensionCallbacks("StageAPI")
    end)
    if not reset then
        return false, "could not reset StageAPI's MiniMAPI callbacks: "
            .. tostring(resetError)
    end
    local loaded, loadError = pcall(function()
        stageAPI.LoadMinimapAPICompat()
    end)
    if not loaded then
        return false, "could not install StageAPI's MiniMAPI bridge: "
            .. tostring(loadError)
    end
    stageAPI.LoadedMinimapAPICompat = true
    rawset(stageAPI, STAGEAPI_MINIMAP_COMPAT_MARKER, minimapAPI)
    return true
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

local function snapshotExtraTransitionState(stageAPI)
    local level = Game():GetLevel()
    return {
        currentMapID = stageAPI.CurrentLevelMapID,
        currentMapRoomID = stageAPI.CurrentLevelMapRoomID,
        transitioning = stageAPI.TransitioningToExtraRoom,
        doing = stageAPI.DoingExtraRoomTransition,
        forcePosition = stageAPI.ForcePlayerNewRoomPosition,
        forceDoorSlot = stageAPI.ForcePlayerDoorSlot,
        lastNonExtraRoom = stageAPI.LastNonExtraRoom,
        leaveDoor = level and level.LeaveDoor or nil,
        enterDoor = level and level.EnterDoor or nil,
    }
end

local function restoreExtraTransitionState(stageAPI, snapshot)
    if type(snapshot) ~= "table" then return end
    stageAPI.CurrentLevelMapID = snapshot.currentMapID
    stageAPI.CurrentLevelMapRoomID = snapshot.currentMapRoomID
    stageAPI.TransitioningToExtraRoom = snapshot.transitioning
    stageAPI.DoingExtraRoomTransition = snapshot.doing
    stageAPI.ForcePlayerNewRoomPosition = snapshot.forcePosition
    stageAPI.ForcePlayerDoorSlot = snapshot.forceDoorSlot
    stageAPI.LastNonExtraRoom = snapshot.lastNonExtraRoom
    local level = Game():GetLevel()
    if level then
        level.LeaveDoor = snapshot.leaveDoor
        level.EnterDoor = snapshot.enterDoor
    end
end

local function getMember(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function hasMethod(object, key)
    return type(getMember(object, key)) == "function"
end

local function printError(message)
    if ConchBlessing and type(ConchBlessing.printError) == "function" then
        ConchBlessing.printError(message)
    elseif type(Isaac) == "table" and type(Isaac.DebugString) == "function" then
        Isaac.DebugString("[Conch's Blessing] " .. tostring(message))
    end
end

local function normalizeInteger(value, name, minimum)
    local number = tonumber(value)
    if number == nil or number ~= math.floor(number) then
        return nil, tostring(name) .. " must be an integer"
    end
    if minimum ~= nil and number < minimum then
        return nil, tostring(name) .. " is below its minimum"
    end
    return number
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return copy
end

local function getRoomShape1x1()
    return type(RoomShape) == "table" and RoomShape.ROOMSHAPE_1x1 or nil
end

local function getDefaultRoomType()
    return type(RoomType) == "table" and RoomType.ROOM_DEFAULT or nil
end

local function expectedPersistentIndex(manifest, slot)
    local mapID = tonumber(manifest and manifest.mapID)
    local normalizedSlot = tonumber(slot)
    if not mapID or not normalizedSlot then return nil end
    return mapID * PERSISTENT_INDEX_STRIDE + normalizedSlot
end

local function expectedRoomID(key)
    return "ConchBlessing:StageAPIGallery:" .. tostring(key)
end

local function expectedStockPosition(index, stockCount)
    if index == 1 then return 1, 0 end
    if stockCount == 2 and index == 2 then return 2, 0 end
    if index == 2 then return 1, -1 end
    if index == 3 then return 1, 1 end

    local armOffset = index - 4
    local x = 2 + math.floor(armOffset / 2)
    local y = armOffset % 2 == 0 and -1 or 1
    return x, y
end

local function makePersistentIndices(mapID, slotCount)
    local indices = {}
    for slot = 1, slotCount do
        indices[slot] = mapID * PERSISTENT_INDEX_STRIDE + slot
    end
    return indices
end

local function expectedDecorationSeed(spawnSeed)
    return ((spawnSeed + 32452843) % 2147483646) + 1
end

local function expectedAwardSeed(spawnSeed)
    return ((spawnSeed + 49979687) % 2147483646) + 1
end

local function makeManifest(seed, mapID, key, kind, x, y, catalogStart, slotCount)
    local spawnSeed = ((math.abs(seed) + mapID * 104729) % 2147483646) + 1
    local capacity = kind == "stock" and STOCK_CAPACITY or 0
    return {
        key = key,
        kind = kind,
        layoutKey = kind == "entrance" and "entrance" or "1x1",
        mapID = mapID,
        -- Kept as a compatibility alias for manager diagnostics while the
        -- physical identity is now a StageAPI MapID, not a native ListIndex.
        listIndex = mapID,
        roomID = expectedRoomID(key),
        graphIndex = mapID,
        x = x,
        y = y,
        shape = getRoomShape1x1(),
        capacity = capacity,
        catalogStart = catalogStart,
        slotCount = slotCount,
        spawnSeed = spawnSeed,
        graphSeed = seed,
        persistentIndices = kind == "stock"
            and makePersistentIndices(mapID, slotCount)
            or {},
    }
end

local function makeGraph(seed, catalogCount)
    local stockCount = math.ceil(catalogCount / STOCK_CAPACITY)
    local graph = {
        version = GRAPH_VERSION,
        backend = BACKEND_NAME,
        dimension = MAP_DIMENSION,
        seed = seed,
        catalogCount = catalogCount,
        complete = false,
        entrance = makeManifest(seed, 1, "entrance", "entrance", 0, 0, 0, 0),
        rooms = {},
    }

    local nextCatalog = 1
    for index = 1, stockCount do
        local x, y = expectedStockPosition(index, stockCount)
        local slotCount = math.min(STOCK_CAPACITY, catalogCount - nextCatalog + 1)
        local mapID = index + 1
        graph.rooms[index] = makeManifest(
            seed,
            mapID,
            "stock:" .. tostring(index),
            "stock",
            x,
            y,
            nextCatalog,
            slotCount
        )
        nextCatalog = nextCatalog + slotCount
    end
    graph.complete = nextCatalog > catalogCount
    return graph
end

local function copyGraph(graph, stockLimit)
    local copy = {
        version = graph.version,
        backend = graph.backend,
        dimension = graph.dimension,
        seed = graph.seed,
        catalogCount = graph.catalogCount,
        complete = graph.complete == true,
        entrance = graph.entrance and deepCopy(graph.entrance) or nil,
        rooms = {},
    }
    local limit = stockLimit == nil and #(graph.rooms or {}) or stockLimit
    for index = 1, math.min(limit, #(graph.rooms or {})) do
        copy.rooms[index] = deepCopy(graph.rooms[index])
    end
    if stockLimit ~= nil and stockLimit < #(graph.rooms or {}) then
        copy.complete = false
    end
    return copy
end

local function validatePersistentIndices(manifest)
    if manifest.kind ~= "stock" then return true end
    if type(manifest.persistentIndices) ~= "table" then
        return false, "stock manifest has no persistent-index table"
    end
    for slot = 1, manifest.slotCount do
        if tonumber(manifest.persistentIndices[slot])
            ~= expectedPersistentIndex(manifest, slot)
        then
            return false, "stock persistent index mismatch at slot " .. tostring(slot)
        end
    end
    return true
end

local function validateManifest(manifest, expectedKind, expectedIndex, stockCount)
    if type(manifest) ~= "table" then return false, "room manifest is missing" end
    local expectedMapID = expectedKind == "entrance" and 1 or expectedIndex + 1
    local expectedKey = expectedKind == "entrance"
        and "entrance"
        or "stock:" .. tostring(expectedIndex)
    local expectedX, expectedY = 0, 0
    if expectedKind == "stock" then
        expectedX, expectedY = expectedStockPosition(expectedIndex, stockCount)
    end

    if manifest.kind ~= expectedKind
        or tostring(manifest.key) ~= expectedKey
        or tonumber(manifest.mapID) ~= expectedMapID
        or tostring(manifest.roomID) ~= expectedRoomID(expectedKey)
        or tonumber(manifest.x) ~= expectedX
        or tonumber(manifest.y) ~= expectedY
        or tonumber(manifest.shape) ~= tonumber(getRoomShape1x1())
        or tonumber(manifest.graphSeed) == nil
        or tonumber(manifest.spawnSeed) == nil
        or tonumber(manifest.spawnSeed) < 1
    then
        return false, "room manifest identity/topology mismatch for " .. expectedKey
    end

    if expectedKind == "entrance" then
        if tonumber(manifest.capacity) ~= 0
            or tonumber(manifest.catalogStart) ~= 0
            or tonumber(manifest.slotCount) ~= 0
        then
            return false, "entrance manifest contains stock"
        end
    else
        local slotCount = tonumber(manifest.slotCount)
        if tonumber(manifest.capacity) ~= STOCK_CAPACITY
            or not slotCount
            or slotCount < 1
            or slotCount > STOCK_CAPACITY
        then
            return false, "stock manifest capacity is invalid"
        end
        local persistentOK, persistentReason = validatePersistentIndices(manifest)
        if not persistentOK then return false, persistentReason end
    end
    return true
end

local function validateGraph(graph, allowPartial)
    if type(graph) ~= "table"
        or graph.version ~= GRAPH_VERSION
        or graph.backend ~= BACKEND_NAME
        or tonumber(graph.dimension) ~= MAP_DIMENSION
    then
        return nil, "StageAPI gallery graph version/backend is invalid"
    end
    local seed, seedReason = normalizeInteger(graph.seed, "graph seed", 1)
    if not seed then return nil, seedReason end
    local catalogCount, countReason = normalizeInteger(
        graph.catalogCount,
        "catalog count",
        1
    )
    if not catalogCount then return nil, countReason end

    local stockCount = math.ceil(catalogCount / STOCK_CAPACITY)
    local entranceOK, entranceReason = validateManifest(
        graph.entrance,
        "entrance",
        0,
        stockCount
    )
    if not entranceOK then return nil, entranceReason end
    if tonumber(graph.entrance.graphSeed) ~= seed then
        return nil, "entrance graph seed mismatch"
    end
    if type(graph.rooms) ~= "table" then return nil, "stock manifests are missing" end
    if not allowPartial and #graph.rooms ~= stockCount then
        return nil, "stock manifest count does not cover the catalog"
    end
    if allowPartial and #graph.rooms > stockCount then
        return nil, "partial graph has too many stock rooms"
    end

    local nextCatalog = 1
    local occupied = { ["0:0"] = true }
    for index, manifest in ipairs(graph.rooms) do
        local valid, reason = validateManifest(manifest, "stock", index, stockCount)
        if not valid then return nil, reason end
        if tonumber(manifest.graphSeed) ~= seed then
            return nil, "stock graph seed mismatch at room " .. tostring(index)
        end
        if tonumber(manifest.catalogStart) ~= nextCatalog then
            return nil, "stock catalog ranges are not contiguous"
        end
        local coordinateKey = tostring(manifest.x) .. ":" .. tostring(manifest.y)
        if occupied[coordinateKey] then return nil, "stock map positions overlap" end
        occupied[coordinateKey] = true
        nextCatalog = nextCatalog + manifest.slotCount
    end

    if not allowPartial then
        if nextCatalog - 1 ~= catalogCount or graph.complete ~= true then
            return nil, "StageAPI gallery graph is incomplete"
        end
    elseif graph.complete == true and nextCatalog - 1 ~= catalogCount then
        return nil, "partial graph is incorrectly marked complete"
    end
    return true
end

local function markerFromManifest(graph, manifest)
    return {
        schema = MARKER_SCHEMA,
        graphVersion = GRAPH_VERSION,
        backend = BACKEND_NAME,
        dimension = MAP_DIMENSION,
        graphSeed = graph.seed,
        catalogCount = graph.catalogCount,
        totalRooms = 1 + #graph.rooms,
        order = manifest.mapID,
        mapID = manifest.mapID,
        roomID = manifest.roomID,
        key = manifest.key,
        kind = manifest.kind,
        layoutKey = manifest.layoutKey,
        x = manifest.x,
        y = manifest.y,
        shape = manifest.shape,
        capacity = manifest.capacity,
        catalogStart = manifest.catalogStart,
        slotCount = manifest.slotCount,
        spawnSeed = manifest.spawnSeed,
        persistentIndices = deepCopy(manifest.persistentIndices),
        autoDoors = true,
        layoutName = EMPTY_LAYOUT_NAME,
    }
end

local function getRoomMarker(levelRoom)
    local persistentData = getMember(levelRoom, "PersistentData")
    if type(persistentData) ~= "table" then return nil end
    local marker = persistentData[MARKER_KEY]
    if type(marker) == "table"
        and marker.schema == MARKER_SCHEMA
        and marker.backend == BACKEND_NAME
        and tonumber(marker.dimension) == MAP_DIMENSION
    then
        return marker
    end
    return nil
end

local function validateMarker(marker)
    if type(marker) ~= "table"
        or marker.schema ~= MARKER_SCHEMA
        or marker.graphVersion ~= GRAPH_VERSION
        or marker.backend ~= BACKEND_NAME
        or tonumber(marker.dimension) ~= MAP_DIMENSION
    then
        return false, "room marker schema/backend is invalid"
    end
    local order = tonumber(marker.order)
    local totalRooms = tonumber(marker.totalRooms)
    if not order or order ~= math.floor(order) or order < 1
        or not totalRooms or totalRooms ~= math.floor(totalRooms) or totalRooms < 2
        or order > totalRooms
    then
        return false, "room marker order/count is invalid"
    end
    local graphSeed = tonumber(marker.graphSeed)
    local catalogCount = tonumber(marker.catalogCount)
    local spawnSeed = tonumber(marker.spawnSeed)
    if not graphSeed
        or graphSeed ~= math.floor(graphSeed)
        or graphSeed < 1
        or not catalogCount
        or catalogCount ~= math.floor(catalogCount)
        or catalogCount < 1
        or not spawnSeed
        or spawnSeed ~= math.floor(spawnSeed)
        or spawnSeed < 1
        or tonumber(marker.mapID) ~= order
        or tostring(marker.roomID) ~= expectedRoomID(marker.key)
        or tonumber(marker.shape) ~= tonumber(getRoomShape1x1())
        or spawnSeed ~= ((math.abs(graphSeed) + order * 104729) % 2147483646) + 1
        or marker.layoutName ~= EMPTY_LAYOUT_NAME
        or marker.autoDoors ~= true
    then
        return false, "room marker identity is invalid"
    end
    local stockCount = math.ceil(catalogCount / STOCK_CAPACITY)
    if catalogCount < 1 or totalRooms ~= stockCount + 1 then
        return false, "room marker catalog/room count is invalid"
    end
    local expectedKind = order == 1 and "entrance" or "stock"
    local expectedIndex = order == 1 and 0 or order - 1
    local manifestValid, manifestReason = validateManifest(
        marker,
        expectedKind,
        expectedIndex,
        stockCount
    )
    if not manifestValid then return false, manifestReason end
    local expectedLayoutKey = expectedKind == "entrance" and "entrance" or "1x1"
    if marker.layoutKey ~= expectedLayoutKey then
        return false, "room marker layout key is invalid"
    end
    if expectedKind == "stock" then
        local expectedCatalogStart = (expectedIndex - 1) * STOCK_CAPACITY + 1
        local expectedSlotCount = math.min(
            STOCK_CAPACITY,
            catalogCount - expectedCatalogStart + 1
        )
        if tonumber(marker.catalogStart) ~= expectedCatalogStart
            or tonumber(marker.slotCount) ~= expectedSlotCount
        then
            return false, "stock marker catalog range is invalid"
        end
    end
    return true
end

local function validateLevelRoomPayload(levelRoom, marker)
    if type(levelRoom) ~= "table" then return false, "LevelRoom is missing" end
    local markerValid, markerReason = validateMarker(marker)
    if not markerValid then return false, markerReason end

    local spawnSeed = tonumber(marker.spawnSeed)
    local stageAPI = getStageAPI()
    local registeredLayout = stageAPI
        and type(stageAPI.Layouts) == "table"
        and stageAPI.Layouts[EMPTY_LAYOUT_NAME]
        or nil
    local actualLayout = getMember(levelRoom, "Layout")
    if tostring(getMember(levelRoom, "LayoutName")) ~= EMPTY_LAYOUT_NAME
        or registeredLayout == nil
        or actualLayout ~= registeredLayout
        or tonumber(getMember(levelRoom, "Shape")) ~= tonumber(getRoomShape1x1())
        or tonumber(getMember(levelRoom, "RoomType")) ~= tonumber(getDefaultRoomType())
        or tonumber(getMember(levelRoom, "SpawnSeed")) ~= spawnSeed
        or tonumber(getMember(levelRoom, "DecorationSeed"))
            ~= expectedDecorationSeed(spawnSeed)
        or tonumber(getMember(levelRoom, "AwardSeed")) ~= expectedAwardSeed(spawnSeed)
        or getMember(levelRoom, "IsExtraRoom") ~= true
        or getMember(levelRoom, "IgnoreDoors") == true
        or getMember(levelRoom, "NoChampions") ~= true
        or getMember(levelRoom, "TypeOverride") ~= nil
        or getMember(levelRoom, "FromData") ~= nil
        or getMember(levelRoom, "RoomsListName") ~= nil
        or getMember(levelRoom, "RoomsListID") ~= nil
    then
        return false, "LevelRoom payload does not match the owned empty gallery room"
    end
    return true
end

local function restoreLastPersistentIndex(levelRoom, marker)
    local maximum = tonumber(getMember(levelRoom, "LastPersistentIndex")) or 0
    if maximum ~= math.floor(maximum) or maximum < 0 then
        return false, "LevelRoom LastPersistentIndex is invalid"
    end

    local function include(value, source)
        if value == nil then return true end
        local index = tonumber(value)
        if index == nil or index ~= math.floor(index) or index < 0 then
            return false, tostring(source) .. " has an invalid persistent index"
        end
        maximum = math.max(maximum, index)
        return true
    end

    for index in pairs(getMember(levelRoom, "PersistenceData") or {}) do
        local valid, reason = include(index, "PersistenceData")
        if not valid then return false, reason end
    end
    for index in pairs(getMember(levelRoom, "AvoidSpawning") or {}) do
        local valid, reason = include(index, "AvoidSpawning")
        if not valid then return false, reason end
    end
    for _, spawns in pairs(getMember(levelRoom, "ExtraSpawn") or {}) do
        if type(spawns) ~= "table" then
            return false, "ExtraSpawn contains an invalid spawn list"
        end
        for _, spawn in pairs(spawns) do
            if type(spawn) ~= "table" then
                return false, "ExtraSpawn contains invalid spawn data"
            end
            local valid, reason = include(spawn.PersistentIndex, "ExtraSpawn")
            if not valid then return false, reason end
        end
    end
    for _, index in pairs(
        type(marker) == "table" and marker.persistentIndices or {}
    ) do
        local valid, reason = include(index, "gallery marker")
        if not valid then return false, reason end
    end

    levelRoom.LastPersistentIndex = maximum
    return true
end

local function safeMapGetSaveData(self)
    -- StageAPI 2.33 restores populated maps before it reconstructs LevelRooms.
    -- Saving only this shell prevents LevelMap:AddRoom(nil) from dereferencing
    -- a missing LevelRoom. The marked LevelRooms still use StageAPI's ordinary
    -- save, and the callback below rebuilds this topology before room loading.
    return {
        Map = {},
        Dimension = self.Dimension,
        StartingRoom = self.StartingRoom,
        Persistent = true,
        OverlapDimension = self.OverlapDimension,
    }
end

local function markOwnedMap(map)
    if type(map) ~= "table" then return end
    map[RUNTIME_MAP_MARKER] = {
        schema = MARKER_SCHEMA,
        dimension = MAP_DIMENSION,
    }
    map.Persistent = true
    map.StartingRoom = 1
    map.GetSaveData = safeMapGetSaveData
end

local function mapHasRuntimeOwnership(map)
    local marker = type(map) == "table" and map[RUNTIME_MAP_MARKER] or nil
    return type(marker) == "table"
        and marker.schema == MARKER_SCHEMA
        and tonumber(marker.dimension) == MAP_DIMENSION
end

local function mapIsExactEmptyOwnedShell(map)
    return type(map) == "table"
        and tonumber(map.Dimension) == MAP_DIMENSION
        and tonumber(map.StartingRoom) == M.ENTRANCE_MAP_ID
        and map.Persistent == true
        and type(map.Map) == "table"
        and next(map.Map) == nil
        and type(map.Map2D) == "table"
        and next(map.Map2D) == nil
end

local function resetMapTopology(map)
    map.Map = {}
    map.Map2D = {}
    map.LowX = nil
    map.HighX = nil
    map.LowY = nil
    map.HighY = nil
end

local function addRoomToOwnedMap(map, levelRoom, roomData, noUpdateDoors)
    local minimapAPI = getMinimapAPI()
    local available, reason = checkMinimapCapabilities(minimapAPI)
    if not available then error(reason) end
    local previousDimension = minimapAPI.CurrentDimension
    minimapAPI.CurrentDimension = MAP_DIMENSION
    local added, roomOrError = pcall(function()
        return map:AddRoom(levelRoom, roomData, noUpdateDoors)
    end)
    minimapAPI.CurrentDimension = previousDimension
    if not added then error(roomOrError) end
    return roomOrError
end

local function checkCapabilities(stageAPI)
    if type(stageAPI) ~= "table" then return false, "StageAPI is unavailable" end
    if type(stageAPI.LevelMap) ~= "table"
        or type(stageAPI.LevelRoom) ~= "table"
        or not hasMethod(stageAPI.LevelMap, "AddRoom")
        or not hasMethod(stageAPI.LevelMap, "RemoveRoom")
        or not hasMethod(stageAPI.LevelMap, "SetAllRoomDoors")
        or not hasMethod(stageAPI.LevelMap, "AddRoomToMinimap")
        or not hasMethod(stageAPI.LevelMap, "Destroy")
    then
        return false, "StageAPI LevelMap capabilities are unavailable"
    end
    local requiredFunctions = {
        "AddCallback",
        "UnregisterCallbacks",
        "CreateEmptyRoomLayout",
        "RegisterLayout",
        "SetLevelRoom",
        "GetLevelRoom",
        "GetCurrentLevelMap",
        "GetCurrentRoom",
        "InExtraRoom",
        "InOrTransitioningToExtraRoom",
        "ExtraRoomTransition",
        "SaveModData",
        "CheckPersistence",
        "SetEntityPersistenceData",
        "GetEntityPersistenceData",
        "GetCustomDoors",
        "SetDoorOpen",
    }
    for _, name in ipairs(requiredFunctions) do
        if type(stageAPI[name]) ~= "function" then
            return false, "StageAPI capability is missing: " .. name
        end
    end
    if type(stageAPI.LevelMaps) ~= "table"
        or type(stageAPI.LevelRooms) ~= "table"
        or type(stageAPI.RoomsToLoad) ~= "table"
        or type(stageAPI.Enum) ~= "table"
        or type(stageAPI.Enum.Callbacks) ~= "table"
        or stageAPI.Enum.Callbacks.POST_STAGEAPI_LOAD_SAVE == nil
    then
        return false, "StageAPI save/restore tables are unavailable"
    end
    local minimapAPI = getMinimapAPI()
    local minimapAvailable, minimapReason = checkMinimapCapabilities(minimapAPI)
    if not minimapAvailable then return false, minimapReason end
    local bridged, bridgeReason = ensureStageAPIMinimapCompatibility(
        stageAPI,
        minimapAPI
    )
    if not bridged then return false, bridgeReason end
    if getRoomShape1x1() == nil
        or getDefaultRoomType() == nil
        or type(Direction) ~= "table"
        or Direction.NO_DIRECTION == nil
        or type(RoomTransitionAnim) ~= "table"
        or RoomTransitionAnim.FADE == nil
    then
        return false, "room/transition enums are unavailable"
    end
    return true
end

local function ensureLayout(stageAPI)
    local existing = type(stageAPI.Layouts) == "table"
        and stageAPI.Layouts[EMPTY_LAYOUT_NAME]
        or nil
    if existing then
        if tonumber(existing.Shape) ~= tonumber(getRoomShape1x1())
            or tonumber(existing.Type) ~= tonumber(getDefaultRoomType())
        then
            return false, "StageAPI gallery layout name is occupied by incompatible data"
        end
        return true
    end

    local ok, layoutOrError = pcall(function()
        return stageAPI.CreateEmptyRoomLayout(getRoomShape1x1())
    end)
    if not ok or type(layoutOrError) ~= "table" then
        return false, "could not create the StageAPI gallery layout: "
            .. tostring(layoutOrError)
    end
    layoutOrError.Name = EMPTY_LAYOUT_NAME
    layoutOrError.Type = getDefaultRoomType()
    local registered, registerError = pcall(function()
        stageAPI.RegisterLayout(EMPTY_LAYOUT_NAME, layoutOrError)
    end)
    if not registered then
        return false, "could not register the StageAPI gallery layout: "
            .. tostring(registerError)
    end
    return true
end

local function createLevelRoom(stageAPI, graph, manifest)
    local ok, levelRoomOrError = pcall(function()
        return stageAPI.LevelRoom({
            LayoutName = EMPTY_LAYOUT_NAME,
            SpawnSeed = manifest.spawnSeed,
            DecorationSeed = expectedDecorationSeed(manifest.spawnSeed),
            AwardSeed = expectedAwardSeed(manifest.spawnSeed),
            Shape = getRoomShape1x1(),
            RoomType = getDefaultRoomType(),
            IsExtraRoom = true,
            IsPersistentRoom = true,
            IgnoreDoors = false,
            Doors = {},
            IsClear = true,
            NoChampions = true,
        })
    end)
    if not ok or type(levelRoomOrError) ~= "table" then
        return nil, "could not initialize a StageAPI LevelRoom: "
            .. tostring(levelRoomOrError)
    end
    local levelRoom = levelRoomOrError
    levelRoom.IsPersistentRoom = true
    levelRoom.PersistentData = type(levelRoom.PersistentData) == "table"
        and levelRoom.PersistentData
        or {}
    local marker = markerFromManifest(graph, manifest)
    levelRoom.PersistentData[MARKER_KEY] = marker
    local restored, restoreReason = restoreLastPersistentIndex(levelRoom, marker)
    if not restored then return nil, restoreReason end
    return levelRoom
end

local function roomDataFromMarker(marker)
    return {
        RoomID = marker.roomID,
        X = marker.x,
        Y = marker.y,
        AutoDoors = marker.autoDoors ~= false,
        Shape = marker.shape,
    }
end

local function roomDataFromManifest(manifest)
    return {
        RoomID = manifest.roomID,
        X = manifest.x,
        Y = manifest.y,
        AutoDoors = true,
        Shape = manifest.shape,
    }
end

local function sortedOwnedLevelRooms(stageAPI)
    local dimensionRooms = stageAPI.LevelRooms[MAP_DIMENSION]
    if type(dimensionRooms) ~= "table" then return {}, nil end
    local sorted = {}
    for roomID, levelRoom in pairs(dimensionRooms) do
        local marker = getRoomMarker(levelRoom)
        if not marker then
            return nil, "fixed StageAPI gallery dimension contains a foreign LevelRoom"
        end
        local valid, reason = validateMarker(marker)
        if not valid then return nil, reason end
        if tostring(marker.roomID) ~= tostring(roomID) then
            return nil, "LevelRoom key does not match its ownership marker"
        end
        sorted[#sorted + 1] = { roomID = roomID, room = levelRoom, marker = marker }
    end
    table.sort(sorted, function(a, b)
        return tonumber(a.marker.order) < tonumber(b.marker.order)
    end)
    for index, entry in ipairs(sorted) do
        if tonumber(entry.marker.order) ~= index then
            return nil, "owned LevelRoom marker order is not contiguous"
        end
    end
    return sorted
end

local function rebuildMapFromLevelRooms(stageAPI, map, sorted)
    resetMapTopology(map)
    markOwnedMap(map)
    for index, entry in ipairs(sorted) do
        entry.room.IsPersistentRoom = true
        local added, roomDataOrError = pcall(function()
            return addRoomToOwnedMap(
                map,
                entry.room,
                roomDataFromMarker(entry.marker),
                true
            )
        end)
        if not added or type(roomDataOrError) ~= "table"
            or tonumber(roomDataOrError.MapID) ~= index
        then
            resetMapTopology(map)
            return false, "could not rebuild StageAPI map room " .. tostring(index)
                .. ": " .. tostring(roomDataOrError)
        end
    end
    local doorsOK, doorsError = pcall(function() map:SetAllRoomDoors() end)
    if not doorsOK then
        resetMapTopology(map)
        return false, "could not rebuild StageAPI map doors: " .. tostring(doorsError)
    end
    return true
end

local function makeRuntime(stageAPI, map, graph)
    local runtime = {
        map = map,
        entrance = nil,
        byKey = {},
        byMapID = {},
        byRoomID = {},
        roomsByMapID = {},
    }
    local manifests = { graph.entrance }
    for _, manifest in ipairs(graph.rooms or {}) do
        manifests[#manifests + 1] = manifest
    end
    for _, manifest in ipairs(manifests) do
        local levelRoom = stageAPI.GetLevelRoom(manifest.roomID, MAP_DIMENSION)
        runtime.byKey[manifest.key] = manifest
        runtime.byMapID[manifest.mapID] = manifest
        runtime.byRoomID[manifest.roomID] = manifest
        runtime.roomsByMapID[manifest.mapID] = levelRoom
        if manifest.kind == "entrance" then runtime.entrance = levelRoom end
    end
    return runtime
end

local function consumeValidatedOwnedQueueEntries(stageAPI)
    local removed = 0
    for index = #stageAPI.RoomsToLoad, 1, -1 do
        local entry = stageAPI.RoomsToLoad[index]
        if tonumber(entry and entry.Dimension) == MAP_DIMENSION then
            local roomSave = type(entry.RoomSaveData) == "table"
                and entry.RoomSaveData.Room
                or nil
            local marker = type(roomSave) == "table"
                and type(roomSave.PersistentData) == "table"
                and roomSave.PersistentData[MARKER_KEY]
                or nil
            local valid = validateMarker(marker)
            if valid and tostring(entry.LIndex) == tostring(marker.roomID) then
                table.remove(stageAPI.RoomsToLoad, index)
                removed = removed + 1
            end
        end
    end
    return removed
end

local function failQueuedRestore(stageAPI, message)
    -- A failed adapter must consume only entries whose full marker and key
    -- prove project ownership. Leaving those entries in StageAPI's ordinary
    -- post-level queue would materialize a partial graph after we failed
    -- closed; foreign or ambiguous entries remain untouched.
    consumeValidatedOwnedQueueEntries(stageAPI)
    M._restoreFailure = tostring(message)
    if tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION then
        stageAPI.CurrentLevelMapRoomID = nil
        stageAPI.TransitioningToExtraRoom = false
        if tonumber(stageAPI.DefaultLevelMapID) ~= MAP_DIMENSION then
            stageAPI.CurrentLevelMapID = stageAPI.DefaultLevelMapID
        else
            stageAPI.CurrentLevelMapID = nil
        end
    end
    printError("Appraisal StageAPI shell restore failed: " .. tostring(message))
    return false, message
end

local function restoreQueuedOwnedRooms(stageAPI)
    local queued = {}
    local fixedDimensionEntries = 0
    for queueIndex, entry in ipairs(stageAPI.RoomsToLoad) do
        if tonumber(entry.Dimension) == MAP_DIMENSION then
            fixedDimensionEntries = fixedDimensionEntries + 1
            local roomSave = type(entry.RoomSaveData) == "table"
                and entry.RoomSaveData.Room
                or nil
            local marker = type(roomSave) == "table"
                and type(roomSave.PersistentData) == "table"
                and roomSave.PersistentData[MARKER_KEY]
                or nil
            local valid, reason = validateMarker(marker)
            if not valid then
                return failQueuedRestore(
                    stageAPI,
                    reason or "fixed dimension has a foreign queued LevelRoom"
                )
            end
            if tostring(entry.LIndex) ~= tostring(marker.roomID) then
                return failQueuedRestore(stageAPI, "queued LevelRoom key/marker mismatch")
            end
            queued[#queued + 1] = {
                queueIndex = queueIndex,
                entry = entry,
                marker = marker,
            }
        end
    end
    if fixedDimensionEntries == 0 then
        local sorted, sortedReason = sortedOwnedLevelRooms(stageAPI)
        if not sorted then return failQueuedRestore(stageAPI, sortedReason) end
        if #sorted == 0 then return true end
        local firstMarker = sorted[1].marker
        for index, item in ipairs(sorted) do
            if tonumber(item.marker.order) ~= index
                or tonumber(item.marker.totalRooms) ~= #sorted
                or tonumber(item.marker.graphSeed) ~= tonumber(firstMarker.graphSeed)
                or tonumber(item.marker.catalogCount) ~= tonumber(firstMarker.catalogCount)
            then
                return failQueuedRestore(stageAPI, "loaded gallery room markers disagree")
            end
            local payloadValid, payloadReason = validateLevelRoomPayload(
                item.room,
                item.marker
            )
            if not payloadValid then
                return failQueuedRestore(stageAPI, payloadReason)
            end
            local restored, restoreReason = restoreLastPersistentIndex(
                item.room,
                item.marker
            )
            if not restored then
                return failQueuedRestore(stageAPI, restoreReason)
            end
        end
        local loadedMap = stageAPI.LevelMaps[MAP_DIMENSION]
        if mapHasRuntimeOwnership(loadedMap)
            and type(loadedMap.Map) == "table"
            and #loadedMap.Map == #sorted
        then
            return true
        end
        if not mapIsExactEmptyOwnedShell(loadedMap) then
            return failQueuedRestore(stageAPI, "loaded gallery shell cannot be adopted")
        end
        local rebuilt, rebuildReason = rebuildMapFromLevelRooms(
            stageAPI,
            loadedMap,
            sorted
        )
        if not rebuilt then return failQueuedRestore(stageAPI, rebuildReason) end
        M._restoreFailure = nil
        M._runtime = nil
        return true
    end

    table.sort(queued, function(a, b)
        return tonumber(a.marker.order) < tonumber(b.marker.order)
    end)
    local first = queued[1] and queued[1].marker or nil
    if not first or #queued ~= tonumber(first.totalRooms) then
        return failQueuedRestore(stageAPI, "queued gallery LevelRoom set is incomplete")
    end
    for index, item in ipairs(queued) do
        local marker = item.marker
        if tonumber(marker.order) ~= index
            or tonumber(marker.totalRooms) ~= #queued
            or tonumber(marker.graphSeed) ~= tonumber(first.graphSeed)
            or tonumber(marker.catalogCount) ~= tonumber(first.catalogCount)
        then
            return failQueuedRestore(stageAPI, "queued gallery markers disagree")
        end
    end

    local map = stageAPI.LevelMaps[MAP_DIMENSION]
    if map == nil then
        return failQueuedRestore(stageAPI, "saved gallery map shell is missing")
    elseif type(map) ~= "table" or #(map.Map or {}) ~= 0 then
        return failQueuedRestore(stageAPI, "saved gallery map shell is not empty")
    end
    if not mapIsExactEmptyOwnedShell(map) then
        return failQueuedRestore(stageAPI, "saved gallery map shell identity is invalid")
    end
    markOwnedMap(map)

    local savedCurrentRoomID = stageAPI.CurrentLevelMapRoomID
    local savedTransitioning = stageAPI.TransitioningToExtraRoom
    local wasCurrent = tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION
    if wasCurrent then
        stageAPI.CurrentLevelMapRoomID = nil
        stageAPI.TransitioningToExtraRoom = false
    end

    local createdRooms = {}
    for _, item in ipairs(queued) do
        local constructed, levelRoomOrError = pcall(function()
            return stageAPI.LevelRoom({FromSave = item.entry.RoomSaveData.Room})
        end)
        if not constructed or type(levelRoomOrError) ~= "table" then
            for _, created in ipairs(createdRooms) do
                stageAPI.SetLevelRoom(nil, created.roomID, MAP_DIMENSION)
            end
            return failQueuedRestore(stageAPI, "could not restore a marked LevelRoom: "
                .. tostring(levelRoomOrError))
        end
        local levelRoom = levelRoomOrError
        levelRoom.IsPersistentRoom = true
        local payloadValid, payloadReason = validateLevelRoomPayload(
            levelRoom,
            item.marker
        )
        if not payloadValid then
            for _, created in ipairs(createdRooms) do
                stageAPI.SetLevelRoom(nil, created.roomID, MAP_DIMENSION)
            end
            return failQueuedRestore(stageAPI, payloadReason)
        end
        local restored, restoreReason = restoreLastPersistentIndex(
            levelRoom,
            item.marker
        )
        if not restored then
            for _, created in ipairs(createdRooms) do
                stageAPI.SetLevelRoom(nil, created.roomID, MAP_DIMENSION)
            end
            return failQueuedRestore(stageAPI, restoreReason)
        end
        stageAPI.SetLevelRoom(levelRoom, item.entry.LIndex, MAP_DIMENSION)
        createdRooms[#createdRooms + 1] = {
            roomID = item.entry.LIndex,
            room = levelRoom,
            marker = item.marker,
        }
    end

    local rebuilt, rebuildReason = rebuildMapFromLevelRooms(stageAPI, map, createdRooms)
    if not rebuilt then
        for _, created in ipairs(createdRooms) do
            stageAPI.SetLevelRoom(nil, created.roomID, MAP_DIMENSION)
        end
        return failQueuedRestore(stageAPI, rebuildReason)
    end

    local removalIndices = {}
    for _, item in ipairs(queued) do removalIndices[#removalIndices + 1] = item.queueIndex end
    table.sort(removalIndices, function(a, b) return a > b end)
    for _, queueIndex in ipairs(removalIndices) do
        table.remove(stageAPI.RoomsToLoad, queueIndex)
    end

    if wasCurrent then
        if tonumber(savedCurrentRoomID) == nil
            or tonumber(savedCurrentRoomID) < 1
            or tonumber(savedCurrentRoomID) > #createdRooms
        then
            return failQueuedRestore(stageAPI, "saved current gallery room ID is invalid")
        end
        stageAPI.CurrentLevelMapID = MAP_DIMENSION
        stageAPI.CurrentLevelMapRoomID = savedCurrentRoomID
        stageAPI.TransitioningToExtraRoom = savedTransitioning == true
    end
    M._restoreFailure = nil
    M._runtime = nil
    return true
end

local function registerRestoreCallback(stageAPI)
    local callbackID = stageAPI.Enum.Callbacks.POST_STAGEAPI_LOAD_SAVE
    stageAPI.UnregisterCallbacks(CALLBACK_OWNER)
    stageAPI.AddCallback(CALLBACK_OWNER, callbackID, -1000, function()
        restoreQueuedOwnedRooms(stageAPI)
    end)
    M._callbackStageAPI = stageAPI
    return true
end

function M.initialize()
    local stageAPI = getStageAPI()
    local available, reason = checkCapabilities(stageAPI)
    if not available then return false, reason end
    local layoutReady, layoutReason = ensureLayout(stageAPI)
    if not layoutReady then return false, layoutReason end
    local registered, registerError = pcall(registerRestoreCallback, stageAPI)
    if not registered then
        return false, "could not register the gallery save adapter: "
            .. tostring(registerError)
    end
    -- Handles a hot reload that happens after StageAPI decoded its save but
    -- before its ordinary MC_POST_NEW_LEVEL queue consumer ran.
    local restored, restoreReason = restoreQueuedOwnedRooms(stageAPI)
    if not restored then return false, restoreReason end
    M._initializedStageAPI = stageAPI
    return true
end

function M.isAvailable()
    local stageAPI = getStageAPI()
    local available, reason = checkCapabilities(stageAPI)
    if not available then return false, reason end
    local layoutReady, layoutReason = ensureLayout(stageAPI)
    if not layoutReady then return false, layoutReason end
    if M._callbackStageAPI ~= stageAPI then
        local initialized, initializeReason = M.initialize()
        if not initialized then return false, initializeReason end
    end
    if M._restoreFailure ~= nil then
        return false, "StageAPI gallery restore is failed closed: "
            .. tostring(M._restoreFailure)
    end
    return true
end

function M.getRestoreFailure()
    return M._restoreFailure
end

function M.isDimensionEmpty()
    local available, reason = M.isAvailable()
    if not available then return false, reason end
    local stageAPI = getStageAPI()
    local map = stageAPI.LevelMaps[MAP_DIMENSION]
    local rooms = stageAPI.LevelRooms[MAP_DIMENSION]
    if map ~= nil then return false end
    if type(rooms) == "table" and next(rooms) ~= nil then return false end
    if type(stageAPI.CustomGrids) == "table"
        and type(stageAPI.CustomGrids[MAP_DIMENSION]) == "table"
        and next(stageAPI.CustomGrids[MAP_DIMENSION]) ~= nil
    then
        return false
    end
    if type(stageAPI.RoomGrids) == "table"
        and type(stageAPI.RoomGrids[MAP_DIMENSION]) == "table"
        and next(stageAPI.RoomGrids[MAP_DIMENSION]) ~= nil
    then
        return false
    end
    for _, entry in ipairs(stageAPI.RoomsToLoad) do
        if tonumber(entry and entry.Dimension) == MAP_DIMENSION then return false end
    end
    local minimapAPI = getMinimapAPI()
    local minimapAvailable, minimapReason = checkMinimapCapabilities(minimapAPI)
    if not minimapAvailable then return false, minimapReason end
    local readMinimap, minimapLevelOrError = pcall(function()
        return minimapAPI:GetLevel(MAP_DIMENSION)
    end)
    if not readMinimap then
        return false, "could not inspect the fixed MiniMAPI dimension: "
            .. tostring(minimapLevelOrError)
    end
    if minimapLevelOrError ~= nil then
        if type(minimapLevelOrError) ~= "table" then
            return false, "fixed MiniMAPI dimension contains incompatible data"
        end
        if next(minimapLevelOrError) ~= nil then
            return false, "fixed MiniMAPI dimension is already occupied"
        end
    end
    return true
end

local function notifyPlaced(onPlaced, graph, stockLimit)
    local partial = copyGraph(graph, stockLimit)
    local ok, accepted, callbackReason = pcall(onPlaced, partial)
    if not ok then return false, "onPlaced failed: " .. tostring(accepted) end
    if accepted == false then
        return false, callbackReason or "onPlaced rejected the partial StageAPI graph"
    end
    return true
end

local function removeOwnedLevelRooms(stageAPI)
    local rooms = stageAPI.LevelRooms[MAP_DIMENSION]
    if type(rooms) ~= "table" then return true end
    for roomID, room in pairs(rooms) do
        if not getRoomMarker(room) then
            return false, "fixed gallery dimension contains a foreign LevelRoom"
        end
    end
    for roomID in pairs(rooms) do
        stageAPI.SetLevelRoom(nil, roomID, MAP_DIMENSION)
    end
    stageAPI.LevelRooms[MAP_DIMENSION] = nil
    return true
end

local function validateOwnedQueuedRooms(stageAPI, remove)
    local count = 0
    for index = #stageAPI.RoomsToLoad, 1, -1 do
        local entry = stageAPI.RoomsToLoad[index]
        if tonumber(entry and entry.Dimension) == MAP_DIMENSION then
            count = count + 1
            local roomSave = type(entry.RoomSaveData) == "table"
                and entry.RoomSaveData.Room
                or nil
            local marker = type(roomSave) == "table"
                and type(roomSave.PersistentData) == "table"
                and roomSave.PersistentData[MARKER_KEY]
                or nil
            local valid, reason = validateMarker(marker)
            if not valid
                or tostring(entry.LIndex) ~= tostring(marker and marker.roomID)
            then
                return false, reason or "fixed gallery dimension has a foreign queued room"
            end
            if remove == true then table.remove(stageAPI.RoomsToLoad, index) end
        end
    end
    return true, count
end

function M.build(seed, catalogCount, onPlaced)
    local available, reason = M.isAvailable()
    if not available then return nil, reason end
    if type(onPlaced) ~= "function" then
        return nil, "onPlaced callback is required before StageAPI room materialization"
    end
    local normalizedSeed, seedReason = normalizeInteger(seed, "seed", 1)
    if not normalizedSeed then return nil, seedReason end
    local count, countReason = normalizeInteger(catalogCount, "catalogCount", 1)
    if not count then return nil, countReason end

    local stageAPI = getStageAPI()
    local dimensionEmpty, dimensionReason = M.isDimensionEmpty()
    if dimensionEmpty ~= true then
        return nil, dimensionReason or "fixed StageAPI gallery dimension is already occupied"
    end

    local graph = makeGraph(normalizedSeed, count)
    local valid, graphReason = validateGraph(graph, false)
    if not valid then return nil, graphReason end

    local mapOK, mapOrError = pcall(function()
        return stageAPI.LevelMap({
            Dimension = MAP_DIMENSION,
            StartingRoom = 1,
            Persistent = true,
        })
    end)
    if not mapOK or type(mapOrError) ~= "table" then
        return nil, "could not create StageAPI gallery map: " .. tostring(mapOrError)
    end
    local map = mapOrError
    markOwnedMap(map)
    resetMapTopology(map)

    local manifests = { graph.entrance }
    for _, manifest in ipairs(graph.rooms) do manifests[#manifests + 1] = manifest end
    local materialized = {}
    for index, manifest in ipairs(manifests) do
        local levelRoom, roomReason = createLevelRoom(stageAPI, graph, manifest)
        if not levelRoom then
            M.destroy(copyGraph(graph, math.max(0, index - 2)))
            return nil, roomReason
        end
        local added, roomDataOrError = pcall(function()
            return addRoomToOwnedMap(
                map,
                levelRoom,
                roomDataFromManifest(manifest),
                true
            )
        end)
        if not added or type(roomDataOrError) ~= "table"
            or tonumber(roomDataOrError.MapID) ~= tonumber(manifest.mapID)
        then
            M.destroy(copyGraph(graph, math.max(0, index - 2)))
            return nil, "could not add StageAPI gallery room: "
                .. tostring(roomDataOrError)
        end
        materialized[#materialized + 1] = manifest

        local stockLimit = index - 1
        local persisted, persistReason = notifyPlaced(onPlaced, graph, stockLimit)
        if not persisted then
            M.destroy(copyGraph(graph, stockLimit))
            return nil, persistReason
        end
    end

    local doorsOK, doorsError = pcall(function() map:SetAllRoomDoors() end)
    if not doorsOK then
        M.destroy(graph)
        return nil, "could not connect StageAPI gallery rooms: " .. tostring(doorsError)
    end
    markOwnedMap(map)
    M._runtime = makeRuntime(stageAPI, map, graph)
    return graph
end

local function validateRuntimeRoom(graph, manifest, levelRoom)
    if type(levelRoom) ~= "table" then return false, "LevelRoom is missing" end
    local marker = getRoomMarker(levelRoom)
    if not marker then return false, "LevelRoom ownership marker is missing" end
    local markerValid, markerReason = validateMarker(marker)
    if not markerValid then return false, markerReason end
    local expected = markerFromManifest(graph, manifest)
    local scalarFields = {
        "schema", "graphVersion", "backend", "dimension", "graphSeed",
        "catalogCount", "totalRooms", "order", "mapID", "roomID", "key",
        "kind", "layoutKey", "x", "y", "shape", "capacity",
        "catalogStart", "slotCount", "spawnSeed", "autoDoors", "layoutName",
    }
    for _, field in ipairs(scalarFields) do
        local expectedValue = expected[field]
        local matches = type(expectedValue) == "number"
            and tonumber(marker[field]) == expectedValue
            or marker[field] == expectedValue
        if not matches then
            return false, "LevelRoom marker does not match the saved graph: "
                .. tostring(field)
        end
    end
    for key, value in pairs(expected.persistentIndices or {}) do
        if tonumber(marker.persistentIndices and marker.persistentIndices[key])
            ~= tonumber(value)
        then
            return false, "LevelRoom marker persistent indices do not match the graph"
        end
    end
    for key, value in pairs(marker.persistentIndices or {}) do
        if tonumber(expected.persistentIndices and expected.persistentIndices[key])
            ~= tonumber(value)
        then
            return false, "LevelRoom marker contains an unexpected persistent index"
        end
    end
    local payloadValid, payloadReason = validateLevelRoomPayload(levelRoom, marker)
    if not payloadValid then
        return false, payloadReason
    end
    if tonumber(marker.graphSeed) ~= tonumber(manifest.graphSeed) then
        return false, "LevelRoom graph seed mismatch"
    end
    if tonumber(marker.mapID) ~= tonumber(manifest.mapID) then
        return false, "LevelRoom marker does not match the saved graph"
    end
    return true
end

function M.rebind(graph)
    local available, reason = M.isAvailable()
    if not available then return nil, reason end
    local valid, graphReason = validateGraph(graph, false)
    if not valid then return nil, graphReason end
    local stageAPI = getStageAPI()
    local map = stageAPI.LevelMaps[MAP_DIMENSION]
    if type(map) ~= "table" then
        return nil, "saved StageAPI gallery map is missing"
    end
    if not mapHasRuntimeOwnership(map) then
        return nil, "fixed StageAPI gallery map has no validated ownership marker"
    end

    local manifests = { graph.entrance }
    for _, manifest in ipairs(graph.rooms) do manifests[#manifests + 1] = manifest end
    local dimensionRooms = stageAPI.LevelRooms[MAP_DIMENSION]
    if type(dimensionRooms) ~= "table" then
        return nil, "saved StageAPI gallery LevelRooms are missing"
    end

    for _, manifest in ipairs(manifests) do
        local levelRoom = dimensionRooms[manifest.roomID]
        if levelRoom == nil then
            return nil, "saved StageAPI gallery LevelRoom is missing: "
                .. tostring(manifest.roomID)
        end
        local roomValid, roomReason = validateRuntimeRoom(graph, manifest, levelRoom)
        if not roomValid then return nil, roomReason end
        local restored, restoreReason = restoreLastPersistentIndex(
            levelRoom,
            getRoomMarker(levelRoom)
        )
        if not restored then return nil, restoreReason end
        levelRoom.IsPersistentRoom = true
    end
    for roomID, levelRoom in pairs(dimensionRooms) do
        local marker = getRoomMarker(levelRoom)
        if not marker then
            return nil, "fixed StageAPI gallery dimension contains a foreign room"
        end
        local found = false
        for _, manifest in ipairs(manifests) do
            if tostring(manifest.roomID) == tostring(roomID) then found = true break end
        end
        if not found then return nil, "StageAPI gallery has an unexpected owned room" end
    end

    local sorted, sortReason = sortedOwnedLevelRooms(stageAPI)
    if not sorted then return nil, sortReason end
    local shouldRebuild = #(map.Map or {}) ~= #manifests
    if not shouldRebuild then
        for index, manifest in ipairs(manifests) do
            local roomData = map.Map[index]
            if type(roomData) ~= "table"
                or tonumber(roomData.MapID) ~= tonumber(manifest.mapID)
                or tostring(roomData.RoomID) ~= tostring(manifest.roomID)
                or tonumber(roomData.X) ~= tonumber(manifest.x)
                or tonumber(roomData.Y) ~= tonumber(manifest.y)
            then
                shouldRebuild = true
                break
            end
        end
    end
    if shouldRebuild then
        local rebuilt, rebuildReason = rebuildMapFromLevelRooms(stageAPI, map, sorted)
        if not rebuilt then return nil, rebuildReason end
    else
        markOwnedMap(map)
        local doorsOK, doorsError = pcall(function() map:SetAllRoomDoors() end)
        if not doorsOK then return nil, tostring(doorsError) end
    end

    local runtime = makeRuntime(stageAPI, map, graph)
    for _, manifest in ipairs(manifests) do
        local levelRoom = runtime.roomsByMapID[manifest.mapID]
        local roomValid, roomReason = validateRuntimeRoom(graph, manifest, levelRoom)
        if not roomValid then return nil, roomReason end
    end
    M._runtime = runtime
    M._restoreFailure = nil
    return runtime
end

function M.getCurrentManifest(graph, runtime)
    runtime = runtime or M._runtime
    if type(graph) ~= "table" or type(runtime) ~= "table" then return nil end
    local stageAPI = getStageAPI()
    if not stageAPI
        or not stageAPI.InExtraRoom()
        or stageAPI.TransitioningToExtraRoom == true
        or stageAPI.DoingExtraRoomTransition == true
        or tonumber(stageAPI.CurrentLevelMapID) ~= MAP_DIMENSION
        or stageAPI.GetCurrentLevelMap() ~= runtime.map
    then
        return nil
    end
    local mapID = tonumber(stageAPI.CurrentLevelMapRoomID)
    local manifest = mapID and runtime.byMapID[mapID] or nil
    local levelRoom = mapID and runtime.roomsByMapID[mapID] or nil
    if not manifest
        or not levelRoom
        or levelRoom.Loaded ~= true
        or stageAPI.GetCurrentRoom() ~= levelRoom
    then
        return nil
    end
    local valid = validateRuntimeRoom(graph, manifest, levelRoom)
    if not valid then return nil end
    return manifest, levelRoom
end

function M.isCurrentRoom(graph, runtime)
    return M.getCurrentManifest(graph, runtime) ~= nil
end

-- Coordinates use the normal 1x1 STB grid including its wall border. The
-- mirrored order keeps partially filled final rooms balanced and leaves every
-- door-aligned cross axis clear.
local function mirroredStockSlots()
    local slots = {}
    local rows = {
        { y = 1, xs = { 1, 2, 3, 4, 5, 9, 10, 11, 12, 13 } },
        { y = 3, xs = { 3, 5, 9, 11 } },
    }
    for _, row in ipairs(rows) do
        for _, x in ipairs(row.xs) do
            slots[#slots + 1] = { x, row.y }
            slots[#slots + 1] = { 14 - x, 8 - row.y }
        end
    end
    return slots
end

local STOCK_SLOTS = mirroredStockSlots()

function M.getSlotWorldPosition(room, manifest, slot)
    if room == nil or type(manifest) ~= "table" or manifest.kind ~= "stock" then
        return nil, "stock room and manifest are required"
    end
    local normalizedSlot, reason = normalizeInteger(slot, "slot", 1)
    if not normalizedSlot then return nil, reason end
    if normalizedSlot > tonumber(manifest.slotCount or 0)
        or normalizedSlot > #STOCK_SLOTS
    then
        return nil, "slot is outside this room's catalog range"
    end
    local stageAPI = getStageAPI()
    if not stageAPI or tonumber(stageAPI.CurrentLevelMapID) ~= MAP_DIMENSION then
        return nil, "stock slot position is available only in the owned LevelMap"
    end
    local currentMapID = tonumber(stageAPI.CurrentLevelMapRoomID)
    if currentMapID ~= tonumber(manifest.mapID) then
        return nil, "stock manifest is not the current StageAPI room"
    end
    local coordinate = STOCK_SLOTS[normalizedSlot]
    local ok, positionOrError = pcall(function()
        local gridWidth = room:GetGridWidth()
        local gridIndex = coordinate[1] + coordinate[2] * gridWidth
        return room:GetGridPosition(gridIndex)
    end)
    if not ok or positionOrError == nil then
        return nil, "could not resolve stock slot world position: "
            .. tostring(positionOrError)
    end
    return positionOrError
end

local function getMinimapRoomID(graph, mapID)
    return MINIMAP_ROOM_ID_PREFIX
        .. tostring(graph.seed)
        .. ":"
        .. tostring(mapID)
end

local function isOwnedMinimapRoom(room)
    local roomID = getMember(room, "ID")
    return type(roomID) == "string"
        and string.sub(roomID, 1, #MINIMAP_ROOM_ID_PREFIX) == MINIMAP_ROOM_ID_PREFIX
end

local function parseMinimapRoomID(roomID)
    if type(roomID) ~= "string" then return nil end
    local seed, mapID = string.match(
        roomID,
        "^" .. MINIMAP_ROOM_ID_PREFIX .. "(.-):(%-?%d+)$"
    )
    if seed == nil then return nil end
    return seed, tonumber(mapID)
end

-- MiniMAPI calls CanTeleport for every rendered room on each frame while its
-- teleport UI is open, and Teleport on click. Both resolve through the live
-- GalleryManager's seed-scoped gates so this backend never trusts a MiniMAPI
-- room table by itself, and a stale handler cannot bypass the session checks.
function MINIMAP_TELEPORT_HANDLER:CanTeleport(room, _)
    local manager = ConchBlessing and ConchBlessing.GalleryManager or nil
    if type(manager) ~= "table"
        or type(manager.canTeleportToGalleryRoom) ~= "function"
    then
        return false
    end
    local seed, mapID = parseMinimapRoomID(getMember(room, "ID"))
    if seed == nil or mapID == nil then return false end
    local ok, allowed = pcall(manager.canTeleportToGalleryRoom, seed, mapID)
    return ok and allowed == true
end

function MINIMAP_TELEPORT_HANDLER:Teleport(room)
    local manager = ConchBlessing and ConchBlessing.GalleryManager or nil
    if type(manager) ~= "table"
        or type(manager.teleportToGalleryRoom) ~= "function"
    then
        return false
    end
    local seed, mapID = parseMinimapRoomID(getMember(room, "ID"))
    if seed == nil or mapID == nil then return false end
    local ok, teleported = pcall(
        manager.teleportToGalleryRoom,
        seed,
        mapID,
        Isaac.GetPlayer(0)
    )
    return ok and teleported == true
end

local function getMinimapRoomCoordinates(room)
    local position = getMember(room, "Position")
    return tonumber(getMember(position, "X")), tonumber(getMember(position, "Y"))
end

local function resetOwnedMinimapLevel(minimapAPI)
    local reset, resetError = pcall(function()
        minimapAPI:SetLevel({}, MAP_DIMENSION)
    end)
    if not reset then
        return false, "could not reset the Appraisal MiniMAPI level: "
            .. tostring(resetError)
    end
    local read, levelOrError = pcall(function()
        return minimapAPI:GetLevel(MAP_DIMENSION)
    end)
    if not read or type(levelOrError) ~= "table" or next(levelOrError) ~= nil then
        return false, "Appraisal MiniMAPI level did not reset cleanly: "
            .. tostring(levelOrError)
    end
    return true
end

local function makeExpectedMinimapRooms(graph, runtime)
    local expectedByID = {}
    local expectedByLegacyID = {}
    local expectedList = {}
    for _, roomData in ipairs(runtime.map.Map or {}) do
        local mapID = tonumber(roomData and roomData.MapID)
        local x = tonumber(roomData and roomData.X)
        local y = tonumber(roomData and roomData.Y)
        local manifest = mapID and runtime.byMapID and runtime.byMapID[mapID] or nil
        local levelRoom = mapID
            and runtime.roomsByMapID
            and runtime.roomsByMapID[mapID]
            or nil
        local shape = tonumber(getMember(levelRoom, "Shape"))
        local roomType = tonumber(getMember(levelRoom, "RoomType"))
        if mapID == nil or mapID ~= math.floor(mapID) or mapID < 1
            or x == nil or x ~= math.floor(x)
            or y == nil or y ~= math.floor(y)
            or type(manifest) ~= "table"
            or tonumber(manifest.x) ~= x
            or tonumber(manifest.y) ~= y
            or shape == nil
            or roomType == nil
        then
            return nil, nil, "StageAPI map data cannot be represented by MiniMAPI"
        end
        local roomID = getMinimapRoomID(graph, mapID)
        if expectedByID[roomID] ~= nil or expectedByLegacyID[mapID] ~= nil then
            return nil, nil, "StageAPI map contains duplicate MiniMAPI room identities"
        end
        local expected = {
            id = roomID,
            legacyID = mapID,
            x = x,
            y = y,
            shape = shape,
            roomType = roomType,
        }
        expectedByID[roomID] = expected
        expectedByLegacyID[mapID] = expected
        expectedList[#expectedList + 1] = expected
    end
    if #expectedList ~= 1 + #(graph.rooms or {}) then
        return nil, nil, "StageAPI map room count does not match the saved graph"
    end
    return expectedByID, expectedByLegacyID, expectedList
end

local function minimapRoomMatches(room, expected, expectedID)
    if type(room) ~= "table" or type(expected) ~= "table" then return false end
    local x, y = getMinimapRoomCoordinates(room)
    return getMember(room, "ID") == expectedID
        and tonumber(getMember(room, "Dimension")) == MAP_DIMENSION
        and x == expected.x
        and y == expected.y
        and tonumber(getMember(room, "Shape")) == expected.shape
        and tonumber(getMember(room, "Type")) == expected.roomType
end

local function isExactLegacyMinimapRoom(room, map, stageAPI)
    local mapID = tonumber(getMember(room, "ID"))
    if mapID == nil or mapID ~= math.floor(mapID) or mapID < 1
        or type(map) ~= "table" or type(map.Map) ~= "table"
    then
        return false
    end
    local roomData = map.Map[mapID]
    local levelRoom = roomData
        and stageAPI.GetLevelRoom(roomData.RoomID, MAP_DIMENSION)
        or nil
    local expected = roomData and levelRoom and {
        x = tonumber(roomData.X),
        y = tonumber(roomData.Y),
        shape = tonumber(getMember(levelRoom, "Shape")),
        roomType = tonumber(getMember(levelRoom, "RoomType")),
    } or nil
    return expected ~= nil
        and expected.x ~= nil
        and expected.y ~= nil
        and expected.shape ~= nil
        and expected.roomType ~= nil
        and minimapRoomMatches(room, expected, mapID)
end

local function clearOwnedMinimapRooms(minimapAPI, map, stageAPI)
    local available, reason = checkMinimapCapabilities(minimapAPI)
    if not available then return false, reason end
    local read, levelOrError = pcall(function()
        return minimapAPI:GetLevel(MAP_DIMENSION)
    end)
    if not read then
        return false, "could not inspect MiniMAPI during gallery cleanup: "
            .. tostring(levelOrError)
    end
    if levelOrError == nil then return true end
    if type(levelOrError) ~= "table" then
        return false, "gallery MiniMAPI cleanup found incompatible level data"
    end

    local retained = {}
    local removed = {}
    for index, room in pairs(levelOrError) do
        if type(index) ~= "number" or index ~= math.floor(index) or index < 1 then
            return false, "gallery MiniMAPI cleanup found non-room level data"
        end
        if isOwnedMinimapRoom(room)
            or isExactLegacyMinimapRoom(room, map, stageAPI)
        then
            removed[#removed + 1] = room
        else
            retained[#retained + 1] = room
        end
    end
    for _, room in ipairs(retained) do
        local removeAdjacent = getMember(room, "RemoveAdjacentRoom")
        if type(removeAdjacent) == "function" then
            for _, removedRoom in ipairs(removed) do
                local cleaned, cleanupError = pcall(function()
                    room:RemoveAdjacentRoom(removedRoom)
                end)
                if not cleaned then
                    return false, "could not detach an owned MiniMAPI room: "
                        .. tostring(cleanupError)
                end
            end
        end
    end

    local replaced, replaceError = pcall(function()
        minimapAPI:SetLevel(retained, MAP_DIMENSION)
    end)
    if not replaced then
        return false, "could not clear owned gallery MiniMAPI rooms: "
            .. tostring(replaceError)
    end
    local verified, currentOrError = pcall(function()
        return minimapAPI:GetLevel(MAP_DIMENSION)
    end)
    if not verified or currentOrError ~= retained then
        return false, "gallery MiniMAPI cleanup could not verify its replacement level"
    end
    for _, room in ipairs(currentOrError) do
        if isOwnedMinimapRoom(room)
            or isExactLegacyMinimapRoom(room, map, stageAPI)
        then
            return false, "an owned gallery MiniMAPI room survived cleanup"
        end
    end
    return true
end

function M.reveal(graph, runtime)
    local valid, reason = validateGraph(graph, false)
    if not valid then return false, reason end
    local available, availabilityReason = M.isAvailable()
    if not available then return false, availabilityReason end
    runtime = runtime or M._runtime
    if type(runtime) ~= "table" or type(runtime.map) ~= "table" then
        return false, "StageAPI gallery runtime is unavailable"
    end
    local stageAPI = getStageAPI()
    if stageAPI == nil or stageAPI.LevelMaps[MAP_DIMENSION] ~= runtime.map then
        return false, "StageAPI gallery map is no longer the owned fixed-dimension map"
    end

    local minimapAPI = getMinimapAPI()
    local minimapAvailable, minimapReason = checkMinimapCapabilities(minimapAPI)
    if not minimapAvailable then return false, minimapReason end
    local expectedByID, expectedByLegacyID, expectedListOrReason =
        makeExpectedMinimapRooms(graph, runtime)
    if expectedByID == nil then return false, expectedListOrReason end
    local expectedList = expectedListOrReason
    local expectedCount = #expectedList

    local readExisting, existingOrError = pcall(function()
        return minimapAPI:GetLevel(MAP_DIMENSION)
    end)
    if not readExisting then
        return false, "could not inspect the Appraisal MiniMAPI level: "
            .. tostring(existingOrError)
    end
    if existingOrError ~= nil and type(existingOrError) ~= "table" then
        return false, "Appraisal MiniMAPI level has incompatible data"
    end
    for index, room in pairs(existingOrError or {}) do
        if type(index) ~= "number" or index ~= math.floor(index) or index < 1 then
            return false, "Appraisal MiniMAPI level contains non-room data"
        end
        if not isOwnedMinimapRoom(room) then
            local legacyID = tonumber(getMember(room, "ID"))
            local expected = legacyID and expectedByLegacyID[legacyID] or nil
            if not minimapRoomMatches(room, expected, legacyID) then
                return false, "Appraisal MiniMAPI dimension contains a foreign room"
            end
        end
    end

    local reset, resetReason = resetOwnedMinimapLevel(minimapAPI)
    if not reset then return false, resetReason end
    local registrationDimension = minimapAPI.CurrentDimension
    minimapAPI.CurrentDimension = MAP_DIMENSION
    for _, expected in ipairs(expectedList) do
        local added, roomOrError = pcall(function()
            local permanentIcon = minimapAPI:GetRoomTypeIconID(expected.roomType)
            local lockedIcon = minimapAPI:GetUnknownRoomTypeIconID(expected.roomType)
            return minimapAPI:AddRoom({
                Shape = expected.shape,
                PermanentIcons = permanentIcon ~= nil and { permanentIcon } or {},
                LockedIcons = lockedIcon ~= nil and { lockedIcon } or {},
                ItemIcons = {},
                VisitedIcons = {},
                Position = Vector(expected.x, expected.y),
                Type = expected.roomType,
                Dimension = MAP_DIMENSION,
                ID = expected.id,
                DisplayFlags = MINIMAP_DISPLAY_FLAGS,
                AdjacentDisplayFlags = MINIMAP_DISPLAY_FLAGS,
                Visited = true,
                Clear = true,
                NoUpdate = true,
                TeleportHandler = MINIMAP_TELEPORT_HANDLER,
            })
        end)
        if not added or type(roomOrError) ~= "table" then
            minimapAPI.CurrentDimension = registrationDimension
            resetOwnedMinimapLevel(minimapAPI)
            return false, "could not add an Appraisal MiniMAPI room: "
                .. tostring(roomOrError)
        end
    end
    minimapAPI.CurrentDimension = registrationDimension

    local readLevel, levelOrError = pcall(function()
        return minimapAPI:GetLevel(MAP_DIMENSION)
    end)
    if not readLevel or type(levelOrError) ~= "table" then
        resetOwnedMinimapLevel(minimapAPI)
        return false, "could not validate the Appraisal MiniMAPI level: "
            .. tostring(levelOrError)
    end
    if #levelOrError ~= expectedCount then
        resetOwnedMinimapLevel(minimapAPI)
        return false, "Appraisal MiniMAPI room count does not match its graph"
    end
    local seen = {}
    for _, room in ipairs(levelOrError) do
        local roomID = getMember(room, "ID")
        local expected = expectedByID[roomID]
        if expected == nil or seen[roomID]
            or not minimapRoomMatches(room, expected, roomID)
            or tonumber(getMember(room, "DisplayFlags")) ~= MINIMAP_DISPLAY_FLAGS
            or tonumber(getMember(room, "AdjacentDisplayFlags")) ~= MINIMAP_DISPLAY_FLAGS
            or getMember(room, "Visited") ~= true
            or getMember(room, "Clear") ~= true
            or getMember(room, "NoUpdate") ~= true
            or getMember(room, "TeleportHandler") ~= MINIMAP_TELEPORT_HANDLER
        then
            resetOwnedMinimapLevel(minimapAPI)
            return false, "Appraisal MiniMAPI room registration failed exact validation"
        end
        seen[roomID] = true
    end
    for roomID in pairs(expectedByID) do
        if not seen[roomID] then
            resetOwnedMinimapLevel(minimapAPI)
            return false, "Appraisal MiniMAPI room is missing after registration"
        end
    end
    local isCurrentGallery = stageAPI.InExtraRoom()
        and tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION
        and stageAPI.GetCurrentLevelMap() == runtime.map
    local previousMinimapDimension = minimapAPI.CurrentDimension
    local adjacencyReady, adjacencyError = pcall(function()
        -- MiniMAPI's room adjacency helper resolves against CurrentDimension,
        -- even when AddRoom received an explicit custom dimension. Rebuild the
        -- cache against the owned map, then restore the native HUD dimension if
        -- this synchronization happened before the extra-room transition.
        minimapAPI.CurrentDimension = MAP_DIMENSION
        for _, room in ipairs(levelOrError) do
            if not hasMethod(room, "UpdateAdjacentRoomsCache") then
                error("MiniMAPI room adjacency capability is unavailable")
            end
            room:UpdateAdjacentRoomsCache()
        end
    end)
    if not isCurrentGallery then
        minimapAPI.CurrentDimension = previousMinimapDimension
    end
    if not adjacencyReady then
        minimapAPI.CurrentDimension = previousMinimapDimension
        return false, "could not build Appraisal MiniMAPI adjacency: "
            .. tostring(adjacencyError)
    end
    if isCurrentGallery then
        if not hasMethod(runtime.map, "GetCurrentRoomData") then
            return false, "StageAPI cannot expose the current MiniMAPI room position"
        end
        local resolved, roomDataOrError = pcall(function()
            return runtime.map:GetCurrentRoomData()
        end)
        local currentMapID = resolved
            and roomDataOrError
            and tonumber(roomDataOrError.MapID)
            or nil
        local expected = currentMapID and expectedByLegacyID[currentMapID] or nil
        if expected == nil
            or tonumber(roomDataOrError.X) ~= expected.x
            or tonumber(roomDataOrError.Y) ~= expected.y
        then
            return false, "StageAPI current room has no exact MiniMAPI position"
        end
        local synchronized, syncError = pcall(function()
            minimapAPI.CurrentDimension = MAP_DIMENSION
            minimapAPI:SetPlayerPosition(Vector(expected.x, expected.y))
            if type(minimapAPI.UpdateMinimapCenterOffset) == "function" then
                minimapAPI:UpdateMinimapCenterOffset(true)
            end
        end)
        if not synchronized then
            return false, "could not synchronize the current MiniMAPI room: "
                .. tostring(syncError)
        end
    end
    return true
end

function M.enterRoom(graph, runtime, mapID, player)
    local valid, reason = validateGraph(graph, false)
    if not valid then return false, reason end
    runtime = runtime or M._runtime
    local targetMapID, mapIDReason = normalizeInteger(mapID, "mapID", 1)
    if not targetMapID then return false, mapIDReason end
    local targetManifest = type(runtime) == "table"
        and runtime.byMapID
        and runtime.byMapID[targetMapID]
        or nil
    local targetRoom = type(runtime) == "table"
        and runtime.roomsByMapID
        and runtime.roomsByMapID[targetMapID]
        or nil
    if type(runtime) ~= "table"
        or runtime.map == nil
        or targetManifest == nil
        or targetRoom == nil
    then
        return false, "StageAPI gallery runtime is unavailable"
    end
    local targetRoomData = runtime.map.Map
        and runtime.map.Map[targetMapID]
        or nil
    if type(targetRoomData) ~= "table"
        or tostring(targetRoomData.RoomID) ~= tostring(targetManifest.roomID)
    then
        return false, "StageAPI gallery target route changed"
    end
    local roomValid, roomReason = validateRuntimeRoom(
        graph,
        targetManifest,
        targetRoom
    )
    if not roomValid then return false, roomReason end
    if player == nil or type(player.ToPlayer) ~= "function" or player:ToPlayer() == nil then
        return false, "entry player is invalid"
    end
    local stageAPI = getStageAPI()
    if not stageAPI then return false, "StageAPI is unavailable" end
    local stateOK, inExtraOrTransitioning = pcall(function()
        return stageAPI.InOrTransitioningToExtraRoom()
    end)
    if not stateOK or inExtraOrTransitioning then
        return false, stateOK and "already in a StageAPI extra room" or "extra-room state is unknown"
    end
    if stageAPI.LevelMaps[MAP_DIMENSION] ~= runtime.map then
        return false, "StageAPI gallery map ownership changed"
    end
    if getRoomTransitionMode() ~= 0 then
        return false, "another room transition is already active"
    end
    local revealed, revealReason = M.reveal(graph, runtime)
    if not revealed then
        return false, "MiniMAPI graph is not ready for gallery entry: "
            .. tostring(revealReason)
    end

    local transitionSnapshot = snapshotExtraTransitionState(stageAPI)
    local transitioned, transitionError = pcall(function()
        stageAPI.ExtraRoomTransition(
            targetMapID,
            Direction.NO_DIRECTION,
            RoomTransitionAnim.FADE,
            MAP_DIMENSION,
            -1,
            -1,
            Vector(320, 280),
            getDefaultRoomType()
        )
    end)
    if not transitioned then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "StageAPI gallery entry failed: " .. tostring(transitionError)
    end
    if tonumber(stageAPI.CurrentLevelMapID) ~= MAP_DIMENSION
        or tonumber(stageAPI.CurrentLevelMapRoomID) ~= targetMapID
    then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "StageAPI did not arm the gallery entry transition"
    end
    local modeAfter = getRoomTransitionMode()
    local arrivedSynchronously = stageAPI.TransitioningToExtraRoom ~= true
        and targetRoom.Loaded == true
        and tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION
        and tonumber(stageAPI.CurrentLevelMapRoomID) == targetMapID
    if not arrivedSynchronously and (modeAfter == nil or modeAfter == 0) then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "StageAPI did not start the gallery entry transition"
    end
    return true
end

function M.enter(graph, runtime, player)
    local entranceMapID = type(graph) == "table"
        and type(graph.entrance) == "table"
        and graph.entrance.mapID
        or nil
    return M.enterRoom(graph, runtime, entranceMapID, player)
end

-- Programmatic gallery-room-to-gallery-room travel for the MiniMAPI teleport
-- UI. Unlike enterRoom (native -> gallery entry, which requires the player to
-- be OUTSIDE any extra room), this requires the player to already stand in a
-- settled gallery room and hands StageAPI the same extra-room transition its
-- own doors perform.
function M.teleportWithinGallery(graph, runtime, mapID, player)
    local valid, reason = validateGraph(graph, false)
    if not valid then return false, reason end
    runtime = runtime or M._runtime
    local targetMapID, mapIDReason = normalizeInteger(mapID, "mapID", 1)
    if not targetMapID then return false, mapIDReason end
    if player == nil or type(player.ToPlayer) ~= "function" or player:ToPlayer() == nil then
        return false, "entry player is invalid"
    end
    local stageAPI = getStageAPI()
    if not stageAPI then return false, "StageAPI is unavailable" end
    -- getCurrentManifest also proves: inside this runtime's map, no extra-room
    -- transition in flight, current room loaded and validated.
    local currentManifest = M.getCurrentManifest(graph, runtime)
    if not currentManifest then
        return false, "the player is not inside a settled gallery room"
    end
    if stageAPI.LevelMaps[MAP_DIMENSION] ~= runtime.map then
        return false, "StageAPI gallery map ownership changed"
    end
    if tonumber(stageAPI.CurrentLevelMapRoomID) == targetMapID then
        return false, "the target room is the current room"
    end
    local targetManifest = type(runtime) == "table"
        and runtime.byMapID
        and runtime.byMapID[targetMapID]
        or nil
    local targetRoom = type(runtime) == "table"
        and runtime.roomsByMapID
        and runtime.roomsByMapID[targetMapID]
        or nil
    if targetManifest == nil or targetRoom == nil then
        return false, "StageAPI gallery runtime is unavailable"
    end
    local targetRoomData = runtime.map.Map
        and runtime.map.Map[targetMapID]
        or nil
    if type(targetRoomData) ~= "table"
        or tostring(targetRoomData.RoomID) ~= tostring(targetManifest.roomID)
    then
        return false, "StageAPI gallery target route changed"
    end
    local roomValid, roomReason = validateRuntimeRoom(
        graph,
        targetManifest,
        targetRoom
    )
    if not roomValid then return false, roomReason end
    if getRoomTransitionMode() ~= 0 then
        return false, "another room transition is already active"
    end
    local transitionSnapshot = snapshotExtraTransitionState(stageAPI)
    local transitioned, transitionError = pcall(function()
        stageAPI.ExtraRoomTransition(
            targetMapID,
            Direction.NO_DIRECTION,
            RoomTransitionAnim.FADE,
            MAP_DIMENSION,
            -1,
            -1,
            Vector(320, 280),
            getDefaultRoomType()
        )
    end)
    if not transitioned then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "StageAPI gallery travel failed: " .. tostring(transitionError)
    end
    if tonumber(stageAPI.CurrentLevelMapID) ~= MAP_DIMENSION
        or tonumber(stageAPI.CurrentLevelMapRoomID) ~= targetMapID
    then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "StageAPI did not arm the gallery travel transition"
    end
    local modeAfter = getRoomTransitionMode()
    local arrivedSynchronously = stageAPI.TransitioningToExtraRoom ~= true
        and targetRoom.Loaded == true
        and tonumber(stageAPI.CurrentLevelMapRoomID) == targetMapID
    if not arrivedSynchronously and (modeAfter == nil or modeAfter == 0) then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "StageAPI did not start the gallery travel transition"
    end
    return true
end

local function descriptorData(descriptor)
    local ok, data = pcall(function() return descriptor and descriptor.Data end)
    if ok then return data end
    return nil
end

local function optionalNumberMatches(saved, actual)
    return saved == nil or tonumber(saved) == tonumber(actual)
end

local function originDescriptorMatches(origin, descriptor, dimension)
    local data = descriptorData(descriptor)
    if type(origin) ~= "table" or descriptor == nil or data == nil then return false end
    if not optionalNumberMatches(origin.listIndex, descriptor.ListIndex)
        or not optionalNumberMatches(origin.safeGridIndex, descriptor.SafeGridIndex)
        or not optionalNumberMatches(origin.gridIndex, descriptor.GridIndex)
        or not optionalNumberMatches(origin.spawnSeed, descriptor.SpawnSeed)
        or not optionalNumberMatches(origin.roomType, data.Type)
        or not optionalNumberMatches(origin.roomVariant, data.Variant)
        or not optionalNumberMatches(origin.roomSubType, data.Subtype or data.SubType)
    then
        return false
    end
    if type(descriptor.GetDimension) == "function" then
        local ok, actualDimension = pcall(function() return descriptor:GetDimension() end)
        if not ok or tonumber(actualDimension) ~= tonumber(dimension) then return false end
    end
    return true
end

function M.exitToNative(origin, player)
    if type(origin) ~= "table" then return false, "native origin is missing" end
    if player == nil or type(player.ToPlayer) ~= "function" or player:ToPlayer() == nil then
        return false, "return player is invalid"
    end
    local stageAPI = getStageAPI()
    if not stageAPI
        or not stageAPI.InExtraRoom()
        or tonumber(stageAPI.CurrentLevelMapID) ~= MAP_DIMENSION
    then
        return false, "player is not in the StageAPI gallery"
    end
    local level = Game():GetLevel()
    local dimension = tonumber(origin.dimension)
    local target = tonumber(origin.safeGridIndex or origin.roomIndex or origin.gridIndex)
    if not level or dimension == nil or target == nil then
        return false, "native return identity is incomplete"
    end
    if not optionalNumberMatches(origin.stage, level:GetStage())
        or not optionalNumberMatches(origin.stageType, level:GetStageType())
    then
        return false, "native return floor changed"
    end
    if type(level.GetDimension) ~= "function" then
        return false, "native dimension validation is unavailable"
    end
    local dimensionOK, currentNativeDimension = pcall(function()
        return level:GetDimension()
    end)
    if not dimensionOK or tonumber(currentNativeDimension) == nil then
        return false, "underlying native dimension could not be validated"
    end
    local descriptorOK, descriptor = pcall(function()
        return level:GetRoomByIdx(target, dimension)
    end)
    if not descriptorOK or not originDescriptorMatches(origin, descriptor, dimension) then
        return false, "native return descriptor is stale"
    end
    if getRoomTransitionMode() ~= 0 then
        return false, "another room transition is already active"
    end

    local sameDimension = tonumber(currentNativeDimension) == dimension
    local transitionSnapshot = snapshotExtraTransitionState(stageAPI)
    local transitioned, transitionError
    if sameDimension then
        transitioned, transitionError = pcall(function()
            stageAPI.ExtraRoomTransition(
                target,
                Direction.NO_DIRECTION,
                RoomTransitionAnim.FADE,
                nil,
                -1,
                -1,
                nil,
                getDefaultRoomType()
            )
        end)
    else
        -- Returning to this exact gallery room from native Death Certificate
        -- changes the off-grid room's underlying engine dimension to 2. Save
        -- the LevelRoom first, then use the engine's dimension-aware native
        -- transition; StageAPI clears its current map in MC_POST_NEW_ROOM.
        local currentMapID = tonumber(stageAPI.CurrentLevelMapRoomID)
        local currentMap = stageAPI.LevelMaps[MAP_DIMENSION]
        local currentRoomData = currentMapID
            and currentMap
            and currentMap.Map
            and currentMap.Map[currentMapID]
            or nil
        local current = stageAPI.GetCurrentRoom()
        local currentMarker = getRoomMarker(current)
        if not current
            or current.Loaded ~= true
            or not currentMarker
            or type(currentRoomData) ~= "table"
            or tostring(currentRoomData.RoomID) ~= tostring(currentMarker.roomID)
            or stageAPI.GetLevelRoom(currentRoomData.RoomID, MAP_DIMENSION) ~= current
        then
            return false, "current gallery LevelRoom cannot be saved"
        end
        local roomSaved, roomSaveError = pcall(function() current:Save() end)
        if not roomSaved then
            return false, "current gallery LevelRoom save failed: "
                .. tostring(roomSaveError)
        end
        local providerSaved, providerSaveError = pcall(function()
            stageAPI.SaveModData()
        end)
        if not providerSaved then
            return false, "StageAPI gallery save failed before native return: "
                .. tostring(providerSaveError)
        end
        transitioned, transitionError = pcall(function()
            Game():StartRoomTransition(
                target,
                Direction.NO_DIRECTION,
                RoomTransitionAnim.FADE,
                player,
                dimension
            )
        end)
    end
    if not transitioned then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "native return transition failed: " .. tostring(transitionError)
    end
    local modeAfter = getRoomTransitionMode()
    local arrivedSynchronously
    local currentDimensionOK, currentDimension = pcall(function()
        return level:GetDimension()
    end)
    local currentDescriptor = level:GetCurrentRoomDesc()
    arrivedSynchronously = currentDimensionOK
        and tonumber(currentDimension) == dimension
        and tonumber(level:GetCurrentRoomIndex()) == target
        and originDescriptorMatches(origin, currentDescriptor, dimension)
        and (not stageAPI.InExtraRoom())
    if not arrivedSynchronously and (modeAfter == nil or modeAfter == 0) then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "native return transition did not start"
    end
    if sameDimension and (stageAPI.CurrentLevelMapRoomID ~= nil
        or tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION)
    then
        restoreExtraTransitionState(stageAPI, transitionSnapshot)
        return false, "StageAPI did not release the gallery map"
    end
    return true
end

function M.finalizeNativeExit()
    local stageAPI = getStageAPI()
    if not stageAPI then return false, "StageAPI is unavailable" end
    if stageAPI.InExtraRoom()
        or tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION
    then
        return false, "StageAPI still reports the gallery as current"
    end
    local previousExtra = stageAPI.PreviousExtraRoomData
    if type(previousExtra) == "table"
        and tonumber(previousExtra.MapID) == MAP_DIMENSION
    then
        stageAPI.PreviousExtraRoomData = {}
    end
    local saved, saveError = pcall(function() stageAPI.SaveModData() end)
    if not saved then
        return false, "could not persist StageAPI's completed gallery exit: "
            .. tostring(saveError)
    end
    return true
end

local function currentOwnedRoomContext()
    local stageAPI = getStageAPI()
    if not stageAPI
        or not stageAPI.InExtraRoom()
        or tonumber(stageAPI.CurrentLevelMapID) ~= MAP_DIMENSION
    then
        return nil, nil, nil, "current room is not an owned gallery room"
    end
    local map = stageAPI.LevelMaps[MAP_DIMENSION]
    local mapID = tonumber(stageAPI.CurrentLevelMapRoomID)
    local roomData = map and mapID and map.Map[mapID] or nil
    local levelRoom = roomData and stageAPI.GetLevelRoom(roomData.RoomID, MAP_DIMENSION) or nil
    local marker = getRoomMarker(levelRoom)
    if not map or not roomData or not levelRoom or not marker then
        return nil, nil, nil, "current StageAPI gallery room is not bound"
    end
    return stageAPI, levelRoom, marker
end

local function removeExtraSpawnPersistentIndex(levelRoom, persistentIndex)
    for gridIndex, spawns in pairs(levelRoom.ExtraSpawn or {}) do
        for index = #spawns, 1, -1 do
            if tonumber(spawns[index].PersistentIndex) == tonumber(persistentIndex) then
                table.remove(spawns, index)
            end
        end
        if #spawns == 0 then levelRoom.ExtraSpawn[gridIndex] = nil end
    end
end

function M.bindStockPickup(pickup, manifest, slot)
    if pickup == nil
        or tonumber(pickup.Type) ~= tonumber(EntityType.ENTITY_PICKUP)
        or tonumber(pickup.Variant) ~= tonumber(PickupVariant.PICKUP_TRINKET)
    then
        return nil, "stock pickup is invalid"
    end
    if type(manifest) ~= "table" or manifest.kind ~= "stock" then
        return nil, "stock manifest is invalid"
    end
    local normalizedSlot, slotReason = normalizeInteger(slot, "slot", 1)
    if not normalizedSlot then return nil, slotReason end
    if normalizedSlot > tonumber(manifest.slotCount or 0) then
        return nil, "stock slot is outside the manifest"
    end
    local expected = expectedPersistentIndex(manifest, normalizedSlot)
    if type(manifest.persistentIndices) ~= "table"
        or tonumber(manifest.persistentIndices[normalizedSlot]) ~= expected
    then
        return nil, "stock manifest did not pre-reserve its persistent index"
    end

    local stageAPI, levelRoom, marker, contextReason = currentOwnedRoomContext()
    if not stageAPI then return nil, contextReason end
    if tonumber(marker.mapID) ~= tonumber(manifest.mapID)
        or tostring(marker.key) ~= tostring(manifest.key)
    then
        return nil, "stock manifest is not the current LevelRoom"
    end

    local existing = stageAPI.GetEntityPersistenceData(pickup)
    if existing ~= nil and tonumber(existing) ~= expected then
        return nil, "pickup already has a foreign persistent index"
    end
    local persistenceData = stageAPI.CheckPersistence(
        pickup.Type,
        pickup.Variant,
        pickup.SubType
    )
    if type(persistenceData) ~= "table" then
        return nil, "StageAPI has no pickup persistence contract"
    end

    removeExtraSpawnPersistentIndex(levelRoom, expected)
    local room = Game():GetRoom()
    local gridIndex = room:GetGridIndex(pickup.Position)
    levelRoom.ExtraSpawn = type(levelRoom.ExtraSpawn) == "table"
        and levelRoom.ExtraSpawn
        or {}
    levelRoom.ExtraSpawn[gridIndex] = levelRoom.ExtraSpawn[gridIndex] or {}
    levelRoom.ExtraSpawn[gridIndex][#levelRoom.ExtraSpawn[gridIndex] + 1] = {
        Data = {
            Type = pickup.Type,
            Variant = pickup.Variant,
            SubType = pickup.SubType,
            Index = gridIndex,
        },
        Persistent = true,
        PersistentIndex = expected,
    }
    levelRoom.PersistenceData = type(levelRoom.PersistenceData) == "table"
        and levelRoom.PersistenceData
        or {}
    levelRoom.PersistenceData[expected] = levelRoom.PersistenceData[expected] or {}
    levelRoom.PersistenceData[expected].Position = {
        X = pickup.Position.X,
        Y = pickup.Position.Y,
    }
    levelRoom.PersistenceData[expected].Price = {
        Price = pickup.Price,
        AutoUpdate = pickup.AutoUpdatePrice,
    }
    levelRoom.PersistenceData[expected].OptionsPickupIndex = pickup.OptionsPickupIndex
    levelRoom.AvoidSpawning = type(levelRoom.AvoidSpawning) == "table"
        and levelRoom.AvoidSpawning
        or {}
    levelRoom.AvoidSpawning[expected] = nil
    levelRoom.LastPersistentIndex = math.max(
        tonumber(levelRoom.LastPersistentIndex) or 0,
        expected
    )
    stageAPI.SetEntityPersistenceData(pickup, expected, persistenceData)
    local data = pickup:GetData()
    data.__ConchBlessingStageAPIPersistentIndex = expected
    return expected
end

function M.getPickupPersistentIndex(pickup)
    if pickup == nil then return nil end
    local stageAPI = getStageAPI()
    if stageAPI and type(stageAPI.GetEntityPersistenceData) == "function" then
        local ok, persistentIndex = pcall(function()
            return stageAPI.GetEntityPersistenceData(pickup)
        end)
        if ok and tonumber(persistentIndex) then return tonumber(persistentIndex) end
    end
    local ok, data = pcall(function() return pickup:GetData() end)
    if ok and type(data) == "table" then
        return tonumber(data.__ConchBlessingStageAPIPersistentIndex)
    end
    return nil
end

function M.unbindStockPickup(pickup)
    if pickup == nil then return false, "stock pickup is missing" end
    local stageAPI, levelRoom, marker, reason = currentOwnedRoomContext()
    if not stageAPI then return false, reason end
    local persistentIndex = M.getPickupPersistentIndex(pickup)
    if not persistentIndex then return false, "pickup has no persistent index" end

    local owned = false
    for slot = 1, tonumber(marker.slotCount) or 0 do
        if tonumber(marker.persistentIndices and marker.persistentIndices[slot])
            == persistentIndex
        then
            owned = true
            break
        end
    end
    if not owned then return false, "pickup persistent index is not owned by this room" end

    removeExtraSpawnPersistentIndex(levelRoom, persistentIndex)
    levelRoom.PersistenceData[persistentIndex] = nil
    levelRoom.AvoidSpawning[persistentIndex] = true
    if type(stageAPI.ActiveEntityPersistenceData) == "table" then
        stageAPI.ActiveEntityPersistenceData[GetPtrHash(pickup)] = nil
    end
    local data = pickup:GetData()
    data.__ConchBlessingStageAPIPersistentIndex = nil
    return true
end

function M.setCurrentDoorsOpen(open)
    local stageAPI, _, _, reason = currentOwnedRoomContext()
    if not stageAPI then return false, reason end
    local map = stageAPI.LevelMaps[MAP_DIMENSION]
    local mapID = tonumber(stageAPI.CurrentLevelMapRoomID)
    local roomData = map and mapID and map.Map[mapID] or nil
    local expectedDoors = roomData and roomData.Doors or nil
    if type(expectedDoors) ~= "table" or next(expectedDoors) == nil then
        return false, "current gallery room has no internal map route"
    end
    local ok, doorsOrError = pcall(function() return stageAPI.GetCustomDoors() end)
    if not ok or type(doorsOrError) ~= "table" then
        return false, "could not enumerate StageAPI gallery doors: "
            .. tostring(doorsOrError)
    end

    local doorsBySlot = {}
    for _, customGrid in ipairs(doorsOrError) do
        local persistent = getMember(customGrid, "PersistentData")
        local slot = type(persistent) == "table" and tonumber(persistent.Slot) or nil
        if slot ~= nil then
            doorsBySlot[slot] = doorsBySlot[slot] or {}
            doorsBySlot[slot][#doorsBySlot[slot] + 1] = customGrid
        end
        if type(persistent) == "table"
            and tonumber(persistent.LevelMapID) == MAP_DIMENSION
        then
            local expected = slot ~= nil and expectedDoors[slot] or nil
            if type(expected) ~= "table"
                or tonumber(persistent.LeadsTo) ~= tonumber(expected.ExitRoom)
                or tonumber(persistent.ExitSlot) ~= tonumber(expected.ExitSlot)
            then
                return false, "gallery room contains an unexpected internal map door"
            end
        end
    end

    for slot, expected in pairs(expectedDoors) do
        local candidates = doorsBySlot[tonumber(slot)] or {}
        if #candidates ~= 1 then
            return false, "gallery internal door count mismatch at slot "
                .. tostring(slot)
        end
        local customGrid = candidates[1]
        local persistent = getMember(customGrid, "PersistentData")
        if type(persistent) ~= "table"
            or tonumber(persistent.LevelMapID) ~= MAP_DIMENSION
            or tonumber(persistent.Slot) ~= tonumber(slot)
            or tonumber(persistent.LeadsTo) ~= tonumber(expected.ExitRoom)
            or tonumber(persistent.ExitSlot) ~= tonumber(expected.ExitSlot)
        then
            return false, "gallery internal door route mismatch at slot "
                .. tostring(slot)
        end
        local target = map.Map[tonumber(expected.ExitRoom)]
        local reverse = target
            and type(target.Doors) == "table"
            and target.Doors[tonumber(expected.ExitSlot)]
            or nil
        if type(reverse) ~= "table"
            or tonumber(reverse.ExitRoom) ~= mapID
            or tonumber(reverse.ExitSlot) ~= tonumber(slot)
        then
            return false, "gallery internal door has no matching reverse route"
        end
        local gridData = getMember(customGrid, "Data")
        local door = type(gridData) == "table" and gridData.DoorEntity or nil
        local exists = door ~= nil
        if exists and hasMethod(door, "Exists") then
            local checked, result = pcall(function() return door:Exists() end)
            exists = checked and result == true
        end
        if not exists then
            return false, "a StageAPI gallery custom door has no live DoorEntity"
        end
        local setOK, setError = pcall(function()
            -- Appraisal routes are never a transaction lock. The argument is
            -- retained for API compatibility, but every verified route opens.
            stageAPI.SetDoorOpen(true, door)
        end)
        if not setOK then
            return false, "could not change a StageAPI gallery door: "
                .. tostring(setError)
        end
    end
    return true
end

function M.save(graph, runtime)
    if graph ~= nil then
        local valid, reason = validateGraph(graph, false)
        if not valid then return false, reason end
    end
    local stageAPI = getStageAPI()
    if not stageAPI then return false, "StageAPI is unavailable" end
    runtime = runtime or M._runtime
    if runtime and runtime.map ~= stageAPI.LevelMaps[MAP_DIMENSION] then
        return false, "StageAPI gallery runtime ownership changed"
    end

    if stageAPI.InExtraRoom()
        and tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION
    then
        local current = stageAPI.GetCurrentRoom()
        if not getRoomMarker(current) then
            return false, "current StageAPI room is not gallery-owned"
        end
        if current.Loaded == true then
            local saved, saveError = pcall(function() current:Save() end)
            if not saved then
                return false, "could not snapshot the current LevelRoom: "
                    .. tostring(saveError)
            end
        end
    end
    local saved, saveError = pcall(function() stageAPI.SaveModData() end)
    if not saved then
        return false, "could not save StageAPI gallery state: " .. tostring(saveError)
    end
    return true
end

function M.destroy(graph, runtime)
    local stageAPI = getStageAPI()
    if not stageAPI then return false, "StageAPI is unavailable" end
    if graph ~= nil then
        local valid, reason = validateGraph(graph, true)
        if not valid then return false, reason end
    end
    if tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION
        or stageAPI.TransitioningToExtraRoom == true
            and tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION
    then
        return false, "cannot destroy the StageAPI gallery while it is current"
    end

    local map = stageAPI.LevelMaps[MAP_DIMENSION]
    local sorted, sortReason = sortedOwnedLevelRooms(stageAPI)
    if not sorted then return false, sortReason end
    local queueValid, queuedCountOrReason = validateOwnedQueuedRooms(stageAPI, false)
    if not queueValid then return false, queuedCountOrReason end
    local queuedCount = tonumber(queuedCountOrReason) or 0
    local runtimeOwned = mapHasRuntimeOwnership(map)
    local shellOwnedByQueue = queuedCount > 0 and mapIsExactEmptyOwnedShell(map)
    local hasOwnedEvidence = runtimeOwned or #sorted > 0 or queuedCount > 0
    if map ~= nil then
        if not runtimeOwned and not shellOwnedByQueue then
            return false, "fixed StageAPI gallery map has no validated ownership evidence"
        end
        for _, roomData in pairs(map.Map or {}) do
            local roomID = roomData and roomData.RoomID
            local room = roomID and stageAPI.GetLevelRoom(roomID, MAP_DIMENSION) or nil
            if not room or not getRoomMarker(room) then
                return false, "fixed StageAPI gallery map contains an unowned room"
            end
        end
    elseif #sorted == 0 and queuedCount == 0 then
        local hasCustomGrids = type(stageAPI.CustomGrids) == "table"
            and type(stageAPI.CustomGrids[MAP_DIMENSION]) == "table"
            and next(stageAPI.CustomGrids[MAP_DIMENSION]) ~= nil
        local hasRoomGrids = type(stageAPI.RoomGrids) == "table"
            and type(stageAPI.RoomGrids[MAP_DIMENSION]) == "table"
            and next(stageAPI.RoomGrids[MAP_DIMENSION]) ~= nil
        if hasCustomGrids or hasRoomGrids then
            return false, "fixed gallery dimension has grids without room ownership evidence"
        end
    end

    local minimapAPI = getMinimapAPI()
    local minimapCleared, minimapReason = clearOwnedMinimapRooms(
        minimapAPI,
        map,
        stageAPI
    )
    if not minimapCleared then return false, minimapReason end

    if map and type(map.RemoveRoom) == "function" then
        local roomDataList = {}
        for _, roomData in pairs(map.Map or {}) do
            roomDataList[#roomDataList + 1] = roomData
        end
        table.sort(roomDataList, function(a, b)
            return tonumber(a.MapID or 0) > tonumber(b.MapID or 0)
        end)
        for _, roomData in ipairs(roomDataList) do
            local removed, removeError = pcall(function()
                map:RemoveRoom(roomData, true, false)
            end)
            if not removed then
                return false, "could not remove a StageAPI gallery room: "
                    .. tostring(removeError)
            end
        end
    end
    local roomsRemoved, roomsReason = removeOwnedLevelRooms(stageAPI)
    if not roomsRemoved then return false, roomsReason end
    local queuesRemoved, queuesReason = validateOwnedQueuedRooms(stageAPI, true)
    if not queuesRemoved then return false, queuesReason end

    if hasOwnedEvidence and type(stageAPI.CustomGrids) == "table" then
        stageAPI.CustomGrids[MAP_DIMENSION] = nil
    end
    if hasOwnedEvidence and type(stageAPI.RoomGrids) == "table" then
        stageAPI.RoomGrids[MAP_DIMENSION] = nil
    end
    if map and type(map.Destroy) == "function" then
        local destroyed, destroyError = pcall(function() map:Destroy() end)
        if not destroyed then return false, tostring(destroyError) end
    else
        stageAPI.LevelMaps[MAP_DIMENSION] = nil
    end
    if tonumber(stageAPI.CurrentLevelMapID) == MAP_DIMENSION then
        stageAPI.CurrentLevelMapID = stageAPI.DefaultLevelMapID
        stageAPI.CurrentLevelMapRoomID = nil
        stageAPI.TransitioningToExtraRoom = false
    end
    if type(stageAPI.PreviousExtraRoomData) == "table"
        and tonumber(stageAPI.PreviousExtraRoomData.MapID) == MAP_DIMENSION
    then
        stageAPI.PreviousExtraRoomData = {}
    end
    M._runtime = nil
    local saved, saveError = pcall(function() stageAPI.SaveModData() end)
    if not saved then
        return false, "could not persist StageAPI gallery cleanup: "
            .. tostring(saveError)
    end
    M._restoreFailure = nil
    return true
end

local initialized, initializationReason = M.initialize()
if not initialized then
    printError("Appraisal StageAPI room backend initialization failed: "
        .. tostring(initializationReason))
end

return M
