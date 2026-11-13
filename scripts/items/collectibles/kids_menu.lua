local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
local RoomKey = require("scripts.lib.room_key")
-- Family Combo (패밀리 세트), the Magic Conch's Binge Eater (user design 2026-11-07).
--
-- Binge Eater gives an item pedestal a food choice. Measured 2026-11-07
-- (`conch_test kids_menu parity`, Binge Eater arm) it follows Birthright's
-- rules exactly: a pedestal created while someone holds it gains one choice
-- (a room's first-visit stock, a later reward, a reroll with a new seed, a
-- Diplopia copy, Damocles' extra pedestal); items seen before, an active
-- dropped onto a pedestal, the Death Certificate area and anything made while
-- nobody holds it never do; a choice already given stays after the item is
-- lost. Family Combo does the same with a familiar item instead of food.
--
-- The familiar is any available, non-hidden familiar collectible that some
-- item pool lists (one no pool lists, such as another mod's upgrade-only item,
-- never comes up; user decision 2026-11-13), drawn from the pedestal's own
-- seed: the pools are only read, never drawn from or emptied, so the same
-- familiar may come up on several pedestals (user request: duplicates allowed) and a
-- Diplopia copy shows the same one, like Binge Eater's food. One choice per
-- pedestal however many copies are held, like Binge Eater. It is appended
-- after the choices the engine already gave, and never while a Magic Conch
-- upgrade holds the pedestal's queue.
ConchBlessing.kidsmenu = ConchBlessing.kidsmenu or {}
local M = ConchBlessing.kidsmenu

local KIDS_MENU_ID = Isaac.GetItemIdByName("Family Combo")
local SAVE_KEY = "kidsMenu"
local MAX_CYCLE = 8
local RNG_SHIFT = 35
-- Death Certificate rooms: StageID HOME with these room subtypes, dimension 2.
local HOME_STAGE_ID = 35
local DEATH_CERTIFICATE_SUBTYPES = { [33] = true, [34] = true }
local DEATH_CERTIFICATE_DIMENSION = 2
-- Severed Oath's split products stay one item (its own markers).
local OATH_SPLIT_MARKER = "__conchBlessingSeveredOathSplit"

local started = false        -- this run's game start has been seen
local roomKey = nil
local snapshotReady = false  -- the room's own pickups have been classified
local firstVisit = false
local seen = {}              -- pointer hash -> seed classified in this room
local copied = {}            -- pointer hash -> seed of a fresh same-seed copy
local states = {}            -- pointer hash -> { seed, state }: the saved record, read once
local familiars = nil        -- the familiar items, by ID, cached per run

-- The same room key as Severed Oath's (scripts/lib/room_key.lua).
local function currentRoomKey()
    return RoomKey.current()
end

local function ensureRoom()
    local key = currentRoomKey()
    if key ~= roomKey then
        roomKey, snapshotReady, seen, copied, states = key, false, {}, {}, {}
    end
end

local function inDeathCertificateArea()
    local level = Game():GetLevel()
    local ok, data = pcall(function() return level:GetCurrentRoomDesc().Data end)
    local stage = ok and data and tonumber(data.StageID)
    if stage then
        return stage == HOME_STAGE_ID and DEATH_CERTIFICATE_SUBTYPES[tonumber(data.Subtype)] == true
    end
    if type(level.GetDimension) == "function" then
        local dimOk, dimension = pcall(level.GetDimension, level)
        return dimOk and dimension == DEATH_CERTIFICATE_DIMENSION
    end
    return false
end

local function anyoneHolds()
    if not KIDS_MENU_ID or KIDS_MENU_ID <= 0 then return false end
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        local ghost = player and type(player.IsCoopGhost) == "function" and player:IsCoopGhost()
        if player and not player:IsDead() and not ghost and player:HasCollectible(KIDS_MENU_ID) then return true end
    end
    return false
end

local function pickupSave(pickup, create)
    local saveManager = ConchBlessing.SaveManager
    local method = saveManager and saveManager[create and "GetNoRerollPickupSave" or "TryGetNoRerollPickupSave"]
    if type(method) ~= "function" then return nil end
    local ok, save = pcall(method, pickup)
    if not ok or type(save) ~= "table" then return nil end
    if create and type(save[SAVE_KEY]) ~= "table" then save[SAVE_KEY] = {} end
    return type(save[SAVE_KEY]) == "table" and save[SAVE_KEY] or nil
end

local function flush()
    local saveManager = ConchBlessing.SaveManager
    if saveManager and type(saveManager.Save) == "function" then pcall(saveManager.Save) end
end

-- The items some item pool lists (any pool, vanilla or a mod's own, however
-- much of it is left), or nil when the build cannot list pools. An item no
-- pool lists, such as another mod's upgrade-only item, is never offered
-- (user decision 2026-11-13).
local function pooledItems()
    local pool = Game():GetItemPool()
    if not pool or type(pool.GetCollectiblesFromPool) ~= "function" then return nil end
    local count = type(pool.GetNumItemPools) == "function" and pool:GetNumItemPools()
        or (ItemPoolType and ItemPoolType.NUM_ITEMPOOLS)
    if type(count) ~= "number" or count <= 0 then return nil end
    local listed = {}
    for kind = 0, count - 1 do
        local ok, entries = pcall(pool.GetCollectiblesFromPool, pool, kind)
        if ok and type(entries) == "table" then
            for _, entry in ipairs(entries) do
                if type(entry) == "table" and type(entry.itemID) == "number" then listed[entry.itemID] = true end
            end
        end
    end
    return listed
end

-- Every available familiar item that some pool lists, sorted by ID so a seed
-- picks the same one.
function M.familiarItems()
    if familiars then return familiars end
    local pooled = pooledItems()
    local list, config = {}, Isaac.GetItemConfig()
    local collectibles = config and config:GetCollectibles()
    local last = collectibles and collectibles.Size - 1 or 0
    local quest = ItemConfig and ItemConfig.TAG_QUEST
    for id = 1, last do
        local item = config:GetCollectible(id)
        if item and item.Type == ItemType.ITEM_FAMILIAR and not item.Hidden
            and not (quest and type(item.HasTags) == "function" and item:HasTags(quest)) then
            local available = true
            if type(item.IsAvailable) == "function" then
                local ok, result = pcall(item.IsAvailable, item)
                available = not ok or result ~= false
            end
            if available and (not pooled or pooled[id]) then list[#list + 1] = id end
        end
    end
    familiars = list
    return list
end

-- The familiar a pedestal with this seed offers. Its own RNG: no item pool and
-- no gameplay RNG is touched.
function M.familiarFor(seed, list)
    list = list or M.familiarItems()
    if #list == 0 then return nil end
    local rng = RNG()
    seed = math.floor(tonumber(seed) or 0) % 4294967296
    rng:SetSeed(seed ~= 0 and seed or 1, RNG_SHIFT)
    return list[rng:RandomInt(#list) + 1]
end

-- Like Birthright and Binge Eater, only a pedestal created while someone holds
-- the item gains a choice. Decided once and kept with the pedestal, so a native
-- turn, an upgrade, a revisit or Continue reads the same answer.
local function decide(pickup, atRoomEntry)
    local new = pickup.Touched ~= true and not inDeathCertificateArea()
        and (not atRoomEntry or firstVisit)
    local state = pickupSave(pickup, true)
    if not state then return nil end
    state.eligible = new and anyoneHolds()
    state.granted = nil
    seen[GetPtrHash(pickup)] = pickup.InitSeed
    states[GetPtrHash(pickup)] = { seed = pickup.InitSeed, state = state }
    return state
end

local function classify(pickup, atRoomEntry)
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return nil end
    ensureRoom()
    local hash = GetPtrHash(pickup)
    -- A Diplopia/Crooked Penny copy arrives with its source's record; it is a
    -- pedestal of its own, so its own answer replaces that record.
    if copied[hash] == pickup.InitSeed and seen[hash] ~= pickup.InitSeed and snapshotReady and not atRoomEntry then
        copied[hash] = nil
        local state = pickupSave(pickup, true)
        if state then
            for field in pairs(state) do state[field] = nil end
        end
        return decide(pickup, false)
    end
    local cached = states[hash]
    if cached and cached.seed == pickup.InitSeed then return cached.state end
    local state = pickupSave(pickup, false)
    if state and type(state.eligible) == "boolean" then
        seen[hash] = pickup.InitSeed
        states[hash] = { seed = pickup.InitSeed, state = state }
        return state
    end
    -- Init callbacks run before the room boundary; the boundary classifies
    -- the room's own pedestals.
    if not snapshotReady then return nil end
    return decide(pickup, atRoomEntry)
end

local function isSplitProduct(pickup)
    if pickup:GetData()[OATH_SPLIT_MARKER] then return true end
    local saveManager = ConchBlessing.SaveManager
    local ok, save = pcall(saveManager.TryGetNoRerollPickupSave, pickup)
    return ok and type(save) == "table" and type(save.severedOath) == "table" and save.severedOath.split == true
end

local function readTail(pickup)
    local ok, cycle = pcall(pickup.GetCollectibleCycle, pickup)
    if not ok or type(cycle) ~= "table" then return nil end
    local tail = {}
    for i, id in ipairs(cycle) do tail[i] = id end
    return tail
end

-- Append the pedestal's familiar after the choices it already has.
local function grant(pickup, state)
    if type(pickup.AddCollectibleCycle) ~= "function" or type(pickup.GetCollectibleCycle) ~= "function" then
        return
    end
    if isSplitProduct(pickup) then
        state.eligible = false
        flush()
        return
    end
    local upgrade = ConchBlessing.upgrade
    if upgrade and type(upgrade.isCycleFrozen) == "function" and upgrade.isCycleFrozen(pickup) then return end
    local tail = readTail(pickup)
    if not tail or #tail >= MAX_CYCLE then return end -- full: wait for room
    local familiar = M.familiarFor(pickup.InitSeed)
    if not familiar then return end
    pcall(pickup.AddCollectibleCycle, pickup, familiar)
    local after = readTail(pickup)
    if after and #after == #tail + 1 and after[#after] == familiar then
        state.granted = familiar
        flush()
        ConchBlessing.printDebug("[Family Combo] pedestal %s (%d) offers familiar %d",
            tostring(pickup.InitSeed), pickup.SubType, familiar)
    end
end

local function snapshotRoom(atStart, continued)
    ensureRoom()
    local room = Game():GetRoom()
    local ok, first = pcall(room.IsFirstVisit, room)
    firstVisit = ok and first == true and not continued
    snapshotReady = true
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local pickup = entity:ToPickup()
            if pickup and pickup:Exists() then classify(pickup, true) end
        end
    end
end

function M.onGameStarted(_, isContinued)
    started, roomKey, familiars = true, nil, nil
    snapshotRoom(true, isContinued == true)
end

function M.onNewRoom()
    if not started then return end
    snapshotRoom(false, false)
end

function M.onGameExit()
    started, snapshotReady = false, false
end

function M.onPickupInit(_, pickup)
    if not started or not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return end
    classify(pickup, false)
end

function M.onPickupUpdate(_, pickup)
    if not started or not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return end
    local state = classify(pickup, false)
    if state and state.eligible == true and state.granted == nil then grant(pickup, state) end
end

-- SaveManager copies a source's record onto a fresh same-seed copy before the
-- init callback; note the copy so only its own record is replaced. It forgets
-- the pairing every update, so a native turn of a pedestal with a same-seed
-- twin would take the twin's record: refuse it for a pedestal already seen.
function M.onDupePickupDataLoad(_, _, duped)
    if not duped then return end
    ensureRoom()
    local hash = GetPtrHash(duped)
    if seen[hash] == duped.InitSeed then return true end
    copied[hash] = duped.InitSeed
end

do
    local mod = ConchBlessing.originalMod
    local saveManager = ConchBlessing.SaveManager or SaveManager
    local callback = saveManager and saveManager.SaveCallbacks and saveManager.SaveCallbacks.DUPE_PICKUP_DATA_LOAD
    if mod and mod.__SAVEMANAGER_UNIQUE_KEY and callback and type(mod.AddCallback) == "function" then
        mod:AddCallback(callback, M.onDupePickupDataLoad)
    end
end

M._test = {
    reset = function() started, roomKey, snapshotReady, seen, copied, states, familiars = false, nil, false, {}, {}, {}, nil end,
    state = function(pickup) return pickupSave(pickup, false) end,
}
