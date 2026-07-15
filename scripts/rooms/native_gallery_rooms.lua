ConchBlessing.NativeGalleryRooms = ConchBlessing.NativeGalleryRooms or {}
local M = ConchBlessing.NativeGalleryRooms

local GRAPH_VERSION = 5
local DC_DIMENSION = 2
local CONFIG_REGISTRATION_SCHEMA = 3
local ROOM_SUBTYPE = 34
local DISPLAY_FLAGS_VISIBLE_WITH_ICON = 5
local DC_ENTRANCE_GRID_INDEX = 80

-- Vanilla Death Certificate only checks and targets grid 80. Appraisal must
-- place its entrance there so the canonical item effect can initialize the
-- engine's private return snapshot without generating the vanilla room set.
M.ENTRANCE_GRID_INDEX = DC_ENTRANCE_GRID_INDEX

-- These variants are deliberately stable. Native room saves identify virtual
-- RoomConfigs through REPENTOGON's registered room database, so changing the
-- registration order or variants would make continued runs ambiguous.
local CONFIG_SPECS = {
    {
        key = "entrance",
        kind = "entrance",
        name = "ConchBlessing:NativeGallery:Entrance:v2",
        variant = 4342100,
        capacity = 0,
    },
    {
        key = "1x1",
        kind = "stock",
        name = "ConchBlessing:NativeGallery:1x1:v1",
        variant = 4342101,
        capacity = 28,
    },
    {
        key = "1x2",
        kind = "stock",
        name = "ConchBlessing:NativeGallery:1x2:v1",
        variant = 4342102,
        capacity = 52,
    },
    {
        key = "2x1",
        kind = "stock",
        name = "ConchBlessing:NativeGallery:2x1:v1",
        variant = 4342103,
        capacity = 60,
    },
    {
        key = "2x2",
        kind = "stock",
        name = "ConchBlessing:NativeGallery:2x2:v1",
        variant = 4342104,
        capacity = 76,
    },
}

local SPEC_BY_KEY = {}
for _, spec in ipairs(CONFIG_SPECS) do
    SPEC_BY_KEY[spec.key] = spec
end

local function mirroredSlots(maxX, maxY, upperRows)
    local slots = {}
    for _, row in ipairs(upperRows) do
        local y = row.y
        for _, x in ipairs(row.xs) do
            -- Append every slot with its 180-degree partner. Besides matching
            -- the vanilla HOME layouts, this keeps a partially filled final
            -- room visually balanced instead of consuming one side first.
            slots[#slots + 1] = { x, y }
            slots[#slots + 1] = { maxX + 1 - x, maxY + 1 - y }
        end
    end
    return slots
end

-- Coordinates use the room/STB grid, including the one-cell wall border.
-- These are dense delta-1 patterns derived from vanilla 35.home.stb Death
-- Certificate rooms. Every possible native door axis remains clear, producing
-- cross-shaped walking lanes regardless of which generated branches are used.
local SLOT_TEMPLATES = {
    ["1x1"] = mirroredSlots(
        13,
        7,
        {
            { y = 1, xs = { 1, 2, 3, 4, 5, 9, 10, 11, 12, 13 } },
            { y = 3, xs = { 3, 5, 9, 11 } },
        }
    ),
    ["1x2"] = mirroredSlots(
        13,
        14,
        {
            { y = 1, xs = { 1, 2, 3, 4, 5, 9, 10, 11, 12, 13 } },
            { y = 5, xs = { 1, 2, 3, 4, 5, 9, 10, 11, 12, 13 } },
            { y = 7, xs = { 1, 3, 5, 9, 11, 13 } },
        }
    ),
    ["2x1"] = mirroredSlots(
        26,
        7,
        {
            {
                y = 1,
                xs = {
                    1, 2, 3, 4, 5, 6,
                    8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                    21, 22, 23, 24, 25, 26,
                },
            },
            { y = 3, xs = { 11, 12, 13, 14, 15, 16 } },
        }
    ),
    ["2x2"] = mirroredSlots(
        26,
        14,
        {
            {
                y = 2,
                xs = {
                    2, 3, 4, 5, 6,
                    8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                    21, 22, 23, 24, 25,
                },
            },
            { y = 5, xs = { 2, 5, 9, 12, 15, 18, 22, 25 } },
            { y = 7, xs = { 2, 5, 9, 12, 15, 18, 22, 25 } },
        }
    ),
}

local function getRepentogon()
    local repentogon = rawget(_G, "REPENTOGON")
    if type(repentogon) == "table" and repentogon.Real == true then
        return repentogon
    end
    return nil
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

local function getLevel()
    if type(Game) ~= "function" then
        return nil, "Game API is unavailable"
    end

    local ok, level = pcall(function() return Game():GetLevel() end)
    if not ok or level == nil then
        return nil, "current Level is unavailable"
    end
    return level
end

local function resolveConfigDefinitions()
    if type(RoomShape) ~= "table" or type(DoorSlot) ~= "table" then
        return nil, "room shape or door-slot enums are unavailable"
    end

    local shape1x1 = RoomShape.ROOMSHAPE_1x1
    local shape1x2 = RoomShape.ROOMSHAPE_1x2
    local shape2x1 = RoomShape.ROOMSHAPE_2x1
    local shape2x2 = RoomShape.ROOMSHAPE_2x2
    local left0 = DoorSlot.LEFT0
    local up0 = DoorSlot.UP0
    local right0 = DoorSlot.RIGHT0
    local down0 = DoorSlot.DOWN0
    local left1 = DoorSlot.LEFT1
    local up1 = DoorSlot.UP1
    local right1 = DoorSlot.RIGHT1
    local down1 = DoorSlot.DOWN1

    local required = {
        { "ROOMSHAPE_1x1", shape1x1 },
        { "ROOMSHAPE_1x2", shape1x2 },
        { "ROOMSHAPE_2x1", shape2x1 },
        { "ROOMSHAPE_2x2", shape2x2 },
        { "LEFT0", left0 },
        { "UP0", up0 },
        { "RIGHT0", right0 },
        { "DOWN0", down0 },
        { "LEFT1", left1 },
        { "UP1", up1 },
        { "RIGHT1", right1 },
        { "DOWN1", down1 },
    }
    for _, entry in ipairs(required) do
        if type(entry[2]) ~= "number" then
            return nil, "required room shape or door-slot enum is missing: "
                .. entry[1]
        end
    end

    local resolved = {
        entrance = {
            -- REPENTOGON's dynamic HOME IH geometry is shorter than the
            -- runtime wall template in the supported build and corrupts the
            -- room on entry. A normal 1x1 with the same horizontal topology
            -- is the verified entrance shape.
            shape = shape1x1,
            doors = { left0, right0 },
        },
        ["1x1"] = {
            shape = shape1x1,
            doors = { left0, up0, right0, down0 },
        },
        ["1x2"] = {
            shape = shape1x2,
            doors = { left0, up0, right0, down0, left1, right1 },
        },
        ["2x1"] = {
            shape = shape2x1,
            doors = { left0, up0, right0, down0, up1, down1 },
        },
        ["2x2"] = {
            shape = shape2x2,
            doors = {
                left0, up0, right0, down0,
                left1, up1, right1, down1,
            },
        },
    }

    for _, spec in ipairs(CONFIG_SPECS) do
        local resolvedSpec = resolved[spec.key]
        spec.shape = resolvedSpec.shape
        spec.doors = resolvedSpec.doors
    end

    return resolved
end

local function checkStaticAvailability()
    if not getRepentogon() then
        return false, "REPENTOGON is unavailable"
    end
    if type(RoomConfig) ~= "table" or type(RoomConfig.AddRooms) ~= "function" then
        return false, "RoomConfig.AddRooms is unavailable"
    end
    if type(StbType) ~= "table" or type(StbType.HOME) ~= "number" then
        return false, "StbType.HOME is unavailable"
    end
    if type(RoomType) ~= "table" or type(RoomType.ROOM_DEFAULT) ~= "number" then
        return false, "RoomType.ROOM_DEFAULT is unavailable"
    end

    local resolved, reason = resolveConfigDefinitions()
    if not resolved then return false, reason end
    return true
end

local function makeRoomConfigTable(spec)
    local room = {
        TYPE = RoomType.ROOM_DEFAULT,
        VARIANT = spec.variant,
        SUBTYPE = ROOM_SUBTYPE,
        NAME = spec.name,
        SHAPE = spec.shape,
        DIFFICULTY = 1,
        WEIGHT = 0,
    }

    for _, slot in ipairs(spec.doors) do
        room[#room + 1] = {
            ISDOOR = true,
            EXISTS = true,
            SLOT = slot,
        }
    end
    return room
end

local function getCurrentRoomConfigMode()
    local ok, greedMode = pcall(function() return Game():IsGreedMode() end)
    return ok and greedMode == true and 1 or 0
end

local function selectCurrentConfigSet()
    local mode = getCurrentRoomConfigMode()
    local configs = type(M._configsByMode) == "table"
        and M._configsByMode[mode]
        or nil
    if type(configs) ~= "table" then
        return false, "native room configs are unavailable for mode " .. tostring(mode)
    end
    M._configsByKey = configs
    return true
end

local function setModeRegistrationError(mode, message)
    M._registrationErrorsByMode = type(M._registrationErrorsByMode) == "table"
        and M._registrationErrorsByMode
        or {}
    M._registrationErrorsByMode[mode] = message
    return false, message
end

local function expectedDoorMask(spec)
    local mask = 0
    for _, slot in ipairs(spec.doors) do
        mask = mask | (1 << slot)
    end
    return mask
end

local function validateRegisteredConfig(config, spec)
    local expected = {
        { "Type", RoomType.ROOM_DEFAULT },
        { "Variant", spec.variant },
        { "Subtype", ROOM_SUBTYPE },
        { "Name", spec.name },
        { "Shape", spec.shape },
        { "Difficulty", 1 },
        { "Doors", expectedDoorMask(spec) },
    }
    for _, field in ipairs(expected) do
        local actual = getMember(config, field[1])
        if actual ~= field[2] then
            return false, field[1] .. " mismatch"
        end
    end
    return true
end

local function recoverRegisteredConfigSet(mode)
    if type(RoomConfig.GetRoomByStageTypeAndVariant) ~= "function" then
        return nil
    end

    local byKey = {}
    local found = 0
    for _, spec in ipairs(CONFIG_SPECS) do
        local ok, config = pcall(function()
            return RoomConfig.GetRoomByStageTypeAndVariant(
                StbType.HOME,
                RoomType.ROOM_DEFAULT,
                spec.variant,
                mode
            )
        end)
        if not ok then return nil end
        if config ~= nil then
            found = found + 1
            local valid, mismatch = validateRegisteredConfig(config, spec)
            if not valid then
                return false, "existing " .. spec.key .. " config has " .. mismatch
            end
            byKey[spec.key] = config
        end
    end

    if found == 0 then return nil end
    if found ~= #CONFIG_SPECS then
        return false, "existing native room registration is partial for mode "
            .. tostring(mode)
    end
    return byKey
end

local function ensureConfigs()
    if M._registrationSchemaVersion ~= nil
        and M._registrationSchemaVersion ~= CONFIG_REGISTRATION_SCHEMA
    then
        return false, "native room config schema changed; restart the executable"
    end

    local available, reason = checkStaticAvailability()
    if not available then
        return false, reason
    end

    -- Re-resolve local metadata whenever this file is explicitly re-included;
    -- registered userdata lives on M, while CONFIG_SPECS is local to this load.
    if M._registrationSchemaVersion == nil then
        -- Migrate an earlier all-modes attempt by discarding only its Lua-side
        -- state. Exact process-lifetime configs are recovered and validated
        -- below by their stable HOME/type/variant identity before any AddRooms.
        M._configsByMode = nil
        M._registrationErrorsByMode = nil
        M._configsRegistered = nil
        M._registrationFailedPermanently = nil
        M._registrationError = nil
    end
    M._registrationSchemaVersion = CONFIG_REGISTRATION_SCHEMA
    local mode = getCurrentRoomConfigMode()
    M._configsByMode = type(M._configsByMode) == "table" and M._configsByMode or {}
    M._registrationErrorsByMode = type(M._registrationErrorsByMode) == "table"
        and M._registrationErrorsByMode
        or {}
    if type(M._configsByMode[mode]) == "table" then
        M._registrationSchemaVersion = CONFIG_REGISTRATION_SCHEMA
        return selectCurrentConfigSet()
    end
    if M._registrationErrorsByMode[mode] ~= nil then
        return false, M._registrationErrorsByMode[mode]
    end

    local recovered, recoveryReason = recoverRegisteredConfigSet(mode)
    if recovered == false then
        return setModeRegistrationError(
            mode,
            "could not adopt native room configs: " .. tostring(recoveryReason)
        )
    elseif type(recovered) == "table" then
        M._configsByMode[mode] = recovered
        M._configsRegistered = true
        return selectCurrentConfigSet()
    end

    for _, spec in ipairs(CONFIG_SPECS) do
        local slots = SLOT_TEMPLATES[spec.key]
        if spec.kind == "stock"
            and (type(slots) ~= "table" or #slots ~= spec.capacity)
        then
            local message = "slot template capacity mismatch for " .. spec.key
            M._registrationSchemaError = message
            return false, message
        end
    end
    if M._registrationSchemaError ~= nil then
        return false, M._registrationSchemaError
    end

    local roomTables = {}
    for _, spec in ipairs(CONFIG_SPECS) do
        roomTables[#roomTables + 1] = makeRoomConfigTable(spec)
    end

    local ok, configs = pcall(function()
        return RoomConfig.AddRooms(StbType.HOME, mode, roomTables)
    end)
    if not ok then
        -- AddRooms may have inserted an earlier entry before raising. The
        -- provider has no rollback/removal API, so retrying this mode in the
        -- same Lua state is unsafe. Other modes remain independent.
        return setModeRegistrationError(
            mode,
            "RoomConfig.AddRooms failed for mode "
                .. tostring(mode) .. ": " .. tostring(configs)
        )
    end
    if type(configs) ~= "table" then
        return setModeRegistrationError(
            mode,
            "RoomConfig.AddRooms returned no config table for mode " .. tostring(mode)
        )
    end

    local byKey = {}
    for index, spec in ipairs(CONFIG_SPECS) do
        local config = configs[index]
        if config == nil or config == false then
            -- Valid configs before this index may already have been inserted.
            -- Retrying this mode would duplicate its database entries and make
            -- saves depend on registration history. Do not poison another mode.
            return setModeRegistrationError(
                mode,
                "RoomConfig.AddRooms rejected " .. spec.key
                    .. " for mode " .. tostring(mode)
            )
        end
        byKey[spec.key] = config
    end

    M._configsByMode[mode] = byKey
    M._configsRegistered = true
    return selectCurrentConfigSet()
end

function M.isAvailable()
    local registered, reason = ensureConfigs()
    if not registered then return false, reason end

    local level, levelReason = getLevel()
    if not level then return false, levelReason end
    if not hasMethod(level, "TryPlaceRoom")
        or not hasMethod(level, "TryPlaceRoomAtDoor")
        or not hasMethod(level, "UpdateVisibility")
    then
        return false, "REPENTOGON native room-placement methods are unavailable"
    end

    local okCurrent, current = pcall(function() return level:GetCurrentRoomDesc() end)
    if not okCurrent then
        return false, "current RoomDescriptor is unavailable"
    end
    if current ~= nil and not hasMethod(current, "GetDimension") then
        return false, "RoomDescriptor:GetDimension is unavailable"
    end
    return true
end

local function getDescriptorDimension(descriptor)
    if descriptor == nil or not hasMethod(descriptor, "GetDimension") then
        return nil, "RoomDescriptor:GetDimension is unavailable"
    end
    local ok, dimension = pcall(function() return descriptor:GetDimension() end)
    if not ok or type(dimension) ~= "number" then
        return nil, "could not read RoomDescriptor dimension"
    end
    return dimension
end

local function getLevelDescriptors(level)
    local ok, roomList = pcall(function() return level:GetRooms() end)
    if not ok or roomList == nil then
        return nil, "could not enumerate Level rooms"
    end

    local size = tonumber(getMember(roomList, "Size"))
    if not size then
        return nil, "RoomDescriptorList.Size is unavailable"
    end

    local descriptors = {}
    for index = 0, size - 1 do
        local descriptor = roomList:Get(index)
        if descriptor ~= nil and getMember(descriptor, "Data") ~= nil then
            descriptors[#descriptors + 1] = descriptor
        end
    end
    return descriptors
end

local function getDimensionDescriptors(level, dimension)
    local descriptors, reason = getLevelDescriptors(level)
    if not descriptors then return nil, reason end

    local matching = {}
    for _, descriptor in ipairs(descriptors) do
        local descriptorDimension, dimensionReason = getDescriptorDimension(descriptor)
        if descriptorDimension == nil then return nil, dimensionReason end
        if descriptorDimension == dimension then
            matching[#matching + 1] = descriptor
        end
    end
    return matching
end

function M.isDimensionEmpty()
    local available, reason = M.isAvailable()
    if not available then return nil, reason end
    local level, levelReason = getLevel()
    if not level then return nil, levelReason end
    local descriptors, descriptorReason = getDimensionDescriptors(level, DC_DIMENSION)
    if not descriptors then return nil, descriptorReason end
    return #descriptors == 0
end

local function setDescriptorReady(descriptor)
    local ok, reason = pcall(function()
        descriptor.Clear = true
        descriptor.DisplayFlags = (tonumber(descriptor.DisplayFlags) or 0)
            | DISPLAY_FLAGS_VISIBLE_WITH_ICON
    end)
    if not ok then
        return false, "could not reveal native room descriptor: " .. tostring(reason)
    end
    return true
end

local function updateVisibility(level)
    local ok, reason = pcall(function() level:UpdateVisibility() end)
    if not ok then
        return false, "Level:UpdateVisibility failed: " .. tostring(reason)
    end
    return true
end

local function makeManifest(descriptor, spec, manifestKey, catalogStart, slotCount)
    local ok, manifest = pcall(function()
        local data = descriptor.Data
        return {
            kind = spec.kind,
            key = manifestKey,
            layoutKey = spec.key,
            listIndex = descriptor.ListIndex,
            safeGridIndex = descriptor.SafeGridIndex,
            gridIndex = descriptor.GridIndex,
            variant = data.Variant,
            shape = data.Shape,
            spawnSeed = descriptor.SpawnSeed,
            capacity = spec.capacity,
            catalogStart = catalogStart,
            slotCount = slotCount,
        }
    end)
    if not ok or type(manifest) ~= "table" then
        return nil, "could not read placed RoomDescriptor"
    end
    if manifest.variant ~= spec.variant or manifest.shape ~= spec.shape then
        return nil, "placed RoomDescriptor does not match config " .. spec.key
    end
    return manifest
end

local function copyManifest(manifest)
    return {
        kind = manifest.kind,
        key = manifest.key,
        layoutKey = manifest.layoutKey,
        listIndex = manifest.listIndex,
        safeGridIndex = manifest.safeGridIndex,
        gridIndex = manifest.gridIndex,
        variant = manifest.variant,
        shape = manifest.shape,
        spawnSeed = manifest.spawnSeed,
        capacity = manifest.capacity,
        catalogStart = manifest.catalogStart,
        slotCount = manifest.slotCount,
    }
end

local function copyGraph(graph)
    local copy = {
        version = graph.version,
        dimension = graph.dimension,
        seed = graph.seed,
        catalogCount = graph.catalogCount,
        complete = graph.complete == true,
        entrance = graph.entrance and copyManifest(graph.entrance) or nil,
        rooms = {},
    }
    for _, manifest in ipairs(graph.rooms or {}) do
        copy.rooms[#copy.rooms + 1] = copyManifest(manifest)
    end
    return copy
end

local function notifyPlaced(onPlaced, graph)
    local ok, accepted, callbackReason = pcall(onPlaced, copyGraph(graph))
    if not ok then
        return false, "onPlaced failed: " .. tostring(accepted)
    end
    if accepted == false then
        return false, callbackReason or "onPlaced rejected the partial graph"
    end
    return true
end

local function normalizePositiveInteger(value, name, allowZero)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil, name .. " must be a finite number"
    end
    if number ~= math.floor(number) then
        return nil, name .. " must be an integer"
    end
    if number < (allowZero and 0 or 1) then
        return nil, name .. (allowZero and " must be non-negative" or " must be positive")
    end
    return number
end

local function newDeterministicRNG(seed)
    local state = seed % 2147483647
    if state <= 0 then state = state + 2147483646 end

    return function(maxExclusive)
        state = (state * 48271) % 2147483647
        if not maxExclusive or maxExclusive <= 1 then return 0 end
        return state % maxExclusive
    end
end

local function shuffledIndices(count, nextInt)
    local indices = {}
    for index = 1, count do indices[index] = index end
    for index = count, 2, -1 do
        local other = nextInt(index) + 1
        indices[index], indices[other] = indices[other], indices[index]
    end
    return indices
end

local function tryPlaceAnchor(level, config, nextInt)
    local placementSeed = nextInt(2147483646) + 1
    local ok, descriptor = pcall(function()
        return level:TryPlaceRoom(
            config,
            DC_ENTRANCE_GRID_INDEX,
            DC_DIMENSION,
            placementSeed,
            false,
            false,
            true
        )
    end)
    if not ok then
        return nil, "canonical Death Certificate entrance placement failed: "
            .. tostring(descriptor)
    end
    if descriptor == nil or descriptor == false then
        return nil, "grid 80 was unavailable for the Death Certificate entrance"
    end
    return descriptor
end

local function getOpenDoorSlots(descriptor, spec)
    local neighbors = {}
    if hasMethod(descriptor, "GetNeighboringRooms") then
        local ok, found = pcall(function() return descriptor:GetNeighboringRooms() end)
        if ok and type(found) == "table" then neighbors = found end
    end

    local open = {}
    for _, slot in ipairs(spec.doors) do
        if neighbors[slot] == nil then open[#open + 1] = slot end
    end
    return open
end

local function addDescriptorFrontier(frontier, descriptor, spec)
    for _, slot in ipairs(getOpenDoorSlots(descriptor, spec)) do
        frontier[#frontier + 1] = {
            descriptor = descriptor,
            slot = slot,
        }
    end
end

local function tryPlaceAtFrontier(level, frontier, spec, nextInt)
    local config = M._configsByKey[spec.key]
    if config == nil then
        return nil, nil, "missing RoomConfig for " .. spec.key
    end

    for _, frontierIndex in ipairs(shuffledIndices(#frontier, nextInt)) do
        local edge = frontier[frontierIndex]
        local placementSeed = nextInt(2147483646) + 1
        local ok, descriptor = pcall(function()
            return level:TryPlaceRoomAtDoor(
                config,
                edge.descriptor,
                edge.slot,
                placementSeed,
                false,
                false
            )
        end)
        if not ok then
            return nil, nil, "TryPlaceRoomAtDoor failed: " .. tostring(descriptor)
        end
        if descriptor ~= nil and descriptor ~= false then
            table.remove(frontier, frontierIndex)
            return descriptor, edge
        end
    end
    return nil
end

local function tryPlaceAtFixedDoor(level, parent, slot, specs, nextInt)
    for _, spec in ipairs(specs) do
        local config = M._configsByKey[spec.key]
        local placementSeed = nextInt(2147483646) + 1
        local ok, descriptor = pcall(function()
            return level:TryPlaceRoomAtDoor(
                config,
                parent,
                slot,
                placementSeed,
                false,
                false
            )
        end)
        if not ok then
            return nil, nil, "TryPlaceRoomAtDoor failed: " .. tostring(descriptor)
        end
        if descriptor ~= nil and descriptor ~= false then return descriptor, spec end
    end
    return nil, nil, "the entrance RIGHT0 door could not place a stock room"
end

local function tryPlaceBranchChild(level, parent, parentSpec, specs, nextInt)
    local openSlots = getOpenDoorSlots(parent, parentSpec)
    for _, openIndex in ipairs(shuffledIndices(#openSlots, nextInt)) do
        local descriptor, placedSpec, reason = tryPlaceAtFixedDoor(
            level,
            parent,
            openSlots[openIndex],
            specs,
            nextInt
        )
        if descriptor then return descriptor, placedSpec end
        if reason and reason:find("TryPlaceRoomAtDoor failed:", 1, true) then
            return nil, nil, reason
        end
    end
    return nil, nil, "the native gallery hub could not place a distinct branch"
end

-- New floor graphs currently use only one-cell stock rooms. Keep the other
-- registered layouts available so an existing frozen floor can still be
-- restored and the policy can be adjusted later without changing room
-- identity. A zero weight removes a layout from both selection and placement
-- fallback, so a new graph can never silently grow a larger room.
local STOCK_LAYOUT_WEIGHTS = {
    ["1x1"] = 100,
    ["1x2"] = 0,
    ["2x1"] = 0,
    ["2x2"] = 0,
}
local STOCK_KEYS = { "1x1", "1x2", "2x1", "2x2" }

local function getEnabledStockKeys()
    local keys = {}
    for _, key in ipairs(STOCK_KEYS) do
        if (tonumber(STOCK_LAYOUT_WEIGHTS[key]) or 0) > 0 then
            keys[#keys + 1] = key
        end
    end
    return keys
end

local function getFallbackSpecs(preferredKey, nextInt)
    local keys = {}
    for _, key in ipairs(getEnabledStockKeys()) do
        if key ~= preferredKey then keys[#keys + 1] = key end
    end
    for index = #keys, 2, -1 do
        local other = nextInt(index) + 1
        keys[index], keys[other] = keys[other], keys[index]
    end

    local specs = { SPEC_BY_KEY[preferredKey] }
    for _, key in ipairs(keys) do specs[#specs + 1] = SPEC_BY_KEY[key] end
    return specs
end

local function choosePreferredKey(_remaining, nextInt)
    local enabled = getEnabledStockKeys()
    local totalWeight = 0
    for _, key in ipairs(enabled) do
        totalWeight = totalWeight + (tonumber(STOCK_LAYOUT_WEIGHTS[key]) or 0)
    end
    if totalWeight <= 0 then return nil end

    local roll = nextInt(totalWeight)
    local cursor = 0
    for _, key in ipairs(enabled) do
        cursor = cursor + (tonumber(STOCK_LAYOUT_WEIGHTS[key]) or 0)
        if roll < cursor then return key end
    end
    return enabled[#enabled]
end

function M.build(seed, catalogCount, onPlaced)
    local available, reason = M.isAvailable()
    if not available then return nil, reason end
    if type(onPlaced) ~= "function" then
        return nil, "onPlaced callback is required before native room placement"
    end

    local normalizedSeed, seedReason = normalizePositiveInteger(seed, "seed", false)
    if not normalizedSeed then return nil, seedReason end
    local count, countReason = normalizePositiveInteger(catalogCount, "catalogCount", false)
    if not count then return nil, countReason end

    local level, levelReason = getLevel()
    if not level then return nil, levelReason end
    local existing, existingReason = getDimensionDescriptors(level, DC_DIMENSION)
    if not existing then return nil, existingReason end
    if #existing > 0 then
        return nil, "Death Certificate dimension is already occupied"
    end

    local nextInt = newDeterministicRNG(normalizedSeed)
    local graph = {
        version = GRAPH_VERSION,
        dimension = DC_DIMENSION,
        seed = normalizedSeed,
        catalogCount = count,
        complete = false,
        entrance = nil,
        rooms = {},
    }

    local entranceSpec = SPEC_BY_KEY.entrance
    local entrance, entranceReason = tryPlaceAnchor(
        level,
        M._configsByKey.entrance,
        nextInt
    )
    if not entrance then return nil, entranceReason end

    local ready, readyReason = setDescriptorReady(entrance)
    if not ready then return nil, readyReason end
    local entranceManifest, manifestReason = makeManifest(
        entrance,
        entranceSpec,
        "entrance",
        0,
        0
    )
    if not entranceManifest then return nil, manifestReason end
    graph.entrance = entranceManifest
    local visible, visibilityReason = updateVisibility(level)
    if not visible then return nil, visibilityReason end
    local persisted, persistReason = notifyPlaced(onPlaced, graph)
    if not persisted then return nil, persistReason end

    local nextCatalog = 1
    local firstKey = choosePreferredKey(count, nextInt)
    if not firstKey then return nil, "native gallery has no enabled stock-room layout" end
    local firstSpecs = getFallbackSpecs(firstKey, nextInt)
    local first, firstSpec, firstReason = tryPlaceAtFixedDoor(
        level,
        entrance,
        DoorSlot.RIGHT0,
        firstSpecs,
        nextInt
    )
    if not first then return nil, firstReason end

    local function recordStockRoom(descriptor, spec)
        local remaining = count - nextCatalog + 1
        local slotCount = math.min(spec.capacity, remaining)
        local manifest, stockManifestReason = makeManifest(
            descriptor,
            spec,
            "stock:" .. tostring(#graph.rooms + 1),
            nextCatalog,
            slotCount
        )
        if not manifest then return false, stockManifestReason end

        local stockReady, stockReadyReason = setDescriptorReady(descriptor)
        if not stockReady then return false, stockReadyReason end
        graph.rooms[#graph.rooms + 1] = manifest
        nextCatalog = nextCatalog + slotCount
        graph.complete = nextCatalog > count

        local stockVisible, stockVisibilityReason = updateVisibility(level)
        if not stockVisible then return false, stockVisibilityReason end
        return notifyPlaced(onPlaced, graph)
    end

    local recorded, recordReason = recordStockRoom(first, firstSpec)
    if not recorded then return nil, recordReason end
    if graph.complete then return graph end

    local frontier = {}
    local branchChildren = {}
    -- Place the next room directly from the first stock hub. If that room did
    -- not finish the catalog, place the third through a different hub door
    -- before exposing any child frontier. This bases the fork on the actual
    -- enabled room capacity, not a hypothetical largest-room estimate.
    for _ = 1, 2 do
        if graph.complete then break end
        local remaining = count - nextCatalog + 1
        local preferredKey = choosePreferredKey(remaining, nextInt)
        if not preferredKey then
            return nil, "native gallery has no enabled stock-room layout"
        end
        local candidates = getFallbackSpecs(preferredKey, nextInt)
        local descriptor, placedSpec, placementReason = tryPlaceBranchChild(
            level,
            first,
            firstSpec,
            candidates,
            nextInt
        )
        if not descriptor then return nil, placementReason end

        local placed, placedReason = recordStockRoom(descriptor, placedSpec)
        if not placed then return nil, placedReason end
        branchChildren[#branchChildren + 1] = {
            descriptor = descriptor,
            spec = placedSpec,
        }
    end
    if graph.complete then return graph end

    -- LEFT0 belongs to Atropos's semantic return door. Never consume it with
    -- a generated neighbor, even when the graph was first built without the
    -- trinket and Atropos is acquired before a later paid visit.
    addDescriptorFrontier(frontier, first, firstSpec)
    for _, child in ipairs(branchChildren) do
        addDescriptorFrontier(frontier, child.descriptor, child.spec)
    end

    while nextCatalog <= count do
        local remaining = count - nextCatalog + 1
        local preferredKey = choosePreferredKey(remaining, nextInt)
        if not preferredKey then
            return nil, "native gallery has no enabled stock-room layout"
        end
        local candidates = getFallbackSpecs(preferredKey, nextInt)
        local descriptor
        local placedSpec
        local placementReason

        for _, spec in ipairs(candidates) do
            descriptor, _, placementReason = tryPlaceAtFrontier(
                level,
                frontier,
                spec,
                nextInt
            )
            if placementReason then return nil, placementReason end
            if descriptor then
                placedSpec = spec
                break
            end
        end

        if not descriptor then
            return nil, "native gallery ran out of valid tree placements"
        end

        local placed, placedReason = recordStockRoom(descriptor, placedSpec)
        if not placed then return nil, placedReason end
        addDescriptorFrontier(frontier, descriptor, placedSpec)
    end

    return graph
end

local function validateManifestShape(manifest, expectedKind)
    if type(manifest) ~= "table" then return false, "room manifest is missing" end
    local spec = SPEC_BY_KEY[manifest.layoutKey]
    if not spec or spec.kind ~= expectedKind or manifest.kind ~= expectedKind then
        return false, "room manifest kind/key is invalid"
    end
    if manifest.variant ~= spec.variant
        or manifest.shape ~= spec.shape
        or manifest.capacity ~= spec.capacity
    then
        return false, "room manifest config does not match " .. spec.key
    end

    local numericFields = {
        "listIndex", "safeGridIndex", "gridIndex", "variant", "shape",
        "spawnSeed", "capacity", "catalogStart", "slotCount",
    }
    for _, field in ipairs(numericFields) do
        if type(manifest[field]) ~= "number" then
            return false, "room manifest field is invalid: " .. field
        end
    end
    if manifest.slotCount < 0 or manifest.slotCount > manifest.capacity then
        return false, "room manifest slot count is invalid"
    end
    return true, nil, spec
end

local function validateGraph(graph)
    if type(graph) ~= "table"
        or graph.version ~= GRAPH_VERSION
        or graph.dimension ~= DC_DIMENSION
    then
        return nil, "native gallery graph version or dimension is invalid"
    end
    if type(graph.catalogCount) ~= "number" or graph.catalogCount < 1 then
        return nil, "native gallery catalog count is invalid"
    end
    if type(graph.rooms) ~= "table" then
        return nil, "native gallery stock-room list is missing"
    end

    local validEntrance, entranceReason = validateManifestShape(graph.entrance, "entrance")
    if not validEntrance then return nil, entranceReason end
    if graph.entrance.catalogStart ~= 0 or graph.entrance.slotCount ~= 0 then
        return nil, "native gallery entrance manifest has stock slots"
    end
    if graph.entrance.key ~= "entrance" then
        return nil, "native gallery entrance key is invalid"
    end
    if graph.entrance.safeGridIndex ~= DC_ENTRANCE_GRID_INDEX
        or graph.entrance.gridIndex ~= DC_ENTRANCE_GRID_INDEX
    then
        return nil, "native gallery entrance is not at canonical grid 80"
    end

    local manifests = { graph.entrance }
    local nextCatalog = 1
    local seenListIndices = { [graph.entrance.listIndex] = true }
    for index, manifest in ipairs(graph.rooms) do
        local valid, manifestReason = validateManifestShape(manifest, "stock")
        if not valid then return nil, manifestReason end
        if manifest.key ~= "stock:" .. tostring(index) then
            return nil, "native gallery stock-room key is invalid"
        end
        if manifest.catalogStart ~= nextCatalog or manifest.slotCount < 1 then
            return nil, "native gallery catalog slots are not contiguous"
        end
        if seenListIndices[manifest.listIndex] then
            return nil, "native gallery contains a duplicate ListIndex"
        end
        seenListIndices[manifest.listIndex] = true
        manifests[#manifests + 1] = manifest
        nextCatalog = nextCatalog + manifest.slotCount
    end

    local represented = nextCatalog - 1
    if represented > graph.catalogCount then
        return nil, "native gallery represents more slots than its catalog"
    end
    if graph.complete == true and represented ~= graph.catalogCount then
        return nil, "completed native gallery is missing catalog slots"
    end
    if graph.complete ~= true and represented >= graph.catalogCount then
        return nil, "partial native gallery is incorrectly marked incomplete"
    end
    return manifests
end

local function descriptorMatchesManifest(descriptor, manifest)
    local dimension, dimensionReason = getDescriptorDimension(descriptor)
    if dimension == nil then return false, dimensionReason end
    if dimension ~= DC_DIMENSION then return false, "room dimension changed" end

    local spec = SPEC_BY_KEY[manifest.layoutKey]
    local ok, mismatch = pcall(function()
        local data = descriptor.Data
        if data == nil then return "RoomConfig data is missing" end
        if descriptor.ListIndex ~= manifest.listIndex then return "ListIndex changed" end
        if descriptor.SafeGridIndex ~= manifest.safeGridIndex then return "SafeGridIndex changed" end
        if descriptor.GridIndex ~= manifest.gridIndex then return "GridIndex changed" end
        if descriptor.SpawnSeed ~= manifest.spawnSeed then return "SpawnSeed changed" end
        if data.Variant ~= manifest.variant or data.Variant ~= spec.variant then
            return "room variant changed"
        end
        if data.Shape ~= manifest.shape or data.Shape ~= spec.shape then
            return "room shape changed"
        end
        if data.Subtype ~= ROOM_SUBTYPE then return "room subtype changed" end
        if data.Name ~= nil and data.Name ~= spec.name then return "room name changed" end
        return nil
    end)
    if not ok then return false, "could not validate RoomDescriptor" end
    if mismatch then return false, mismatch end
    return true
end

local function revealRuntime(level, graph, runtime)
    local manifests, graphReason = validateGraph(graph)
    if not manifests then return false, graphReason end
    if type(runtime) ~= "table" or type(runtime.byListIndex) ~= "table" then
        return false, "native gallery runtime binding is missing"
    end

    for _, manifest in ipairs(manifests) do
        local descriptor = runtime.byListIndex[manifest.listIndex]
        if descriptor == nil then
            return false, "native gallery runtime is missing a descriptor"
        end
        local matches, matchReason = descriptorMatchesManifest(descriptor, manifest)
        if not matches then return false, matchReason end
        local ready, readyReason = setDescriptorReady(descriptor)
        if not ready then return false, readyReason end
    end
    return updateVisibility(level)
end

function M.rebind(graph)
    local available, reason = M.isAvailable()
    if not available then return nil, reason end
    local manifests, graphReason = validateGraph(graph)
    if not manifests then return nil, graphReason end

    local level, levelReason = getLevel()
    if not level then return nil, levelReason end
    local descriptors, descriptorReason = getDimensionDescriptors(level, DC_DIMENSION)
    if not descriptors then return nil, descriptorReason end

    local manifestsByListIndex = {}
    for _, manifest in ipairs(manifests) do
        manifestsByListIndex[manifest.listIndex] = manifest
    end

    local descriptorsByListIndex = {}
    for _, descriptor in ipairs(descriptors) do
        local listIndex = getMember(descriptor, "ListIndex")
        local manifest = manifestsByListIndex[listIndex]
        if not manifest then
            return nil, "Death Certificate dimension contains a foreign room"
        end
        if descriptorsByListIndex[listIndex] ~= nil then
            return nil, "Death Certificate dimension contains a duplicate room"
        end
        local matches, matchReason = descriptorMatchesManifest(descriptor, manifest)
        if not matches then
            return nil, "native gallery room restore mismatch: " .. tostring(matchReason)
        end
        descriptorsByListIndex[listIndex] = descriptor
    end

    for _, manifest in ipairs(manifests) do
        if descriptorsByListIndex[manifest.listIndex] == nil then
            return nil, "native gallery room is missing after restore"
        end
    end

    local runtime = {
        entrance = descriptorsByListIndex[graph.entrance.listIndex],
        stockRooms = {},
        descriptors = {},
        byListIndex = descriptorsByListIndex,
        manifestByListIndex = manifestsByListIndex,
    }
    runtime.descriptors[1] = runtime.entrance
    for index, manifest in ipairs(graph.rooms) do
        local descriptor = descriptorsByListIndex[manifest.listIndex]
        runtime.stockRooms[index] = descriptor
        runtime.descriptors[#runtime.descriptors + 1] = descriptor
    end

    local revealed, revealReason = revealRuntime(level, graph, runtime)
    if not revealed then return nil, revealReason end
    return runtime
end

function M.getCurrentManifest(graph, runtime)
    if type(graph) ~= "table"
        or type(runtime) ~= "table"
        or type(runtime.manifestByListIndex) ~= "table"
    then
        return nil
    end

    local level = getLevel()
    if not level then return nil end
    local descriptor = level:GetCurrentRoomDesc()
    if descriptor == nil then return nil end
    local dimension = getDescriptorDimension(descriptor)
    if dimension ~= DC_DIMENSION then return nil end

    local manifest = runtime.manifestByListIndex[descriptor.ListIndex]
    if not manifest then return nil end
    local matches = descriptorMatchesManifest(descriptor, manifest)
    if not matches then return nil end
    return manifest, descriptor
end

function M.getSlotWorldPosition(room, manifest, slot)
    if room == nil or type(manifest) ~= "table" or manifest.kind ~= "stock" then
        return nil, "stock room and manifest are required"
    end
    local spec = SPEC_BY_KEY[manifest.layoutKey]
    local slots = spec and SLOT_TEMPLATES[spec.key] or nil
    if type(slots) ~= "table" or #slots ~= manifest.capacity then
        return nil, "slot template does not match room manifest"
    end

    local slotIndex, slotReason = normalizePositiveInteger(slot, "slot", false)
    if not slotIndex then return nil, slotReason end
    if slotIndex > manifest.slotCount then
        return nil, "slot is outside this room's catalog range"
    end

    local level, levelReason = getLevel()
    if not level then return nil, levelReason end
    local current = level:GetCurrentRoomDesc()
    if current == nil or current.ListIndex ~= manifest.listIndex then
        return nil, "slot positions are available only in the manifest's live room"
    end
    local matches, matchReason = descriptorMatchesManifest(current, manifest)
    if not matches then return nil, matchReason end

    local coordinate = slots[slotIndex]
    local ok, position = pcall(function()
        local gridWidth = room:GetGridWidth()
        local gridIndex = coordinate[1] + coordinate[2] * gridWidth
        return room:GetGridPosition(gridIndex)
    end)
    if not ok or position == nil then
        return nil, "could not resolve stock slot world position"
    end
    return position
end

function M.reveal(graph, runtime)
    local available, reason = M.isAvailable()
    if not available then return false, reason end
    local level, levelReason = getLevel()
    if not level then return false, levelReason end
    return revealRuntime(level, graph, runtime)
end

-- Register early enough for REPENTOGON to restore virtual RoomConfig pointers
-- on continue. A later isAvailable/build call retries only transient failures.
local registered, registrationReason = ensureConfigs()
if not registered and type(ConchBlessing.printError) == "function" then
    local mode = getCurrentRoomConfigMode()
    local permanentForCurrentMode = type(M._registrationErrorsByMode) == "table"
        and M._registrationErrorsByMode[mode] ~= nil
    if permanentForCurrentMode then
        ConchBlessing.printError(
            "Appraisal native room registration failed: " .. tostring(registrationReason)
        )
    end
end

return M
